# 骰子模式的物理擲骰桌（畫面層；docs/系統說明.md §55「物理擲骰」）：自己一個 3D 世界（SubViewport.own_world_3d），Godot 內建物理
# 6 顆骰子真的滾、互撞、撞牆，停下來朝上的那面就是結果（settled 送出每顆的面編號，DicePanel 轉成 OP_DICE_FACES 給模擬層）
# 擲法（設定頁「骰子用骰盅擲」）：
#   骰盅：按住滑鼠，骰盅出現在滑鼠下、把骰子罩住，跟著滑鼠走（甩動就在搖）；放開時骰盅的速度與方向就是丟出去的力道
#   蓄力條：按住滑鼠或空白鍵，力道條上下跑；放開那一刻的力道決定丟多大力（從桌子左邊往右丟）
# 重擲：點桌上停好的骰子拿到後面的保留區（DicePanel 送 OP_DICE_LOCK），剩下的再丟一次；保留區的骰子照原本的面擺好、不動
# 骰子斜靠著牆或別顆停住（朝上那面不夠平）自動往上輕推一下再滾；超過 SETTLE_TIMEOUT 秒還沒停就照現在朝上的面算
# 連線（§55「連線」）：物理只在擲的人這台算。record_enabled 時自己擲的每一段（骰盅、6 顆骰子的位置與轉向）錄下來送出（frames_recorded），
# 隊友的桌子收到就照著播（play_frames，骰子凍住不跑物理），大家看到同一段
# 兩種擺法：預設自己一個 3D 世界、畫在介面中間（檢查用這個）；骰子模式的遊戲畫面 use_world 之後桌子放進遊戲的 3D 世界、
# 擺在戰場旁邊（set_origin，只繞 Y 轉），用遊戲的鏡頭看、滑鼠由 DicePanel 轉過來（world_input）。桌子自己的座標都是桌面本地的，
# 剛體的速度與衝量是世界座標，要經過 _g / _l 轉
class_name DiceTable
extends SubViewportContainer

signal thrown()                     # 丟出去了（DicePanel 送 OP_DICE_ROLL）
signal settled(faces: Array)        # 全部停好：每顆朝上的面編號（0~5，保留區的照原本的）；播隊友的錄影不送
signal die_clicked(index: int)      # 點了桌上 / 保留區的第幾顆（鎖住 / 放回）
signal clacked(gain: float)         # 骰子撞到東西（音量比例，DicePanel 轉成 diceClack 音效）
signal suspense_changed(on: bool)   # 最後一顆快湊到大獎：放慢、鏡頭推近（main.gd 把音樂收小）；停好就結束
signal frames_recorded(data: PackedByteArray)   # 連線：自己擲的錄影，每 REC_CHUNK 幀一段、停好送最後一段（main.gd 交給 NetSession）

enum State { IDLE, AIM, ROLLING, SETTLED }

const VIEW_SIZE := Vector2i(960, 430)
const PLAY := Vector2(12.0, 5.6)           # 桌面能滾的範圍（x 寬、z 深），中心在原點
const WALL_H := 6.0                        # 牆的碰撞高度（畫面上只畫矮矮的木框）
const RIM_H := 0.5
const SHELF_Z := -PLAY.y / 2.0 - 1.4       # 保留區（後面那條木架）
const GRAVITY := 32.0                      # 骰子邊長 1：重力加大才不會像在月球上
const CUP_RADIUS := 1.7
const CUP_HEIGHT := 2.8
const CUP_MAX_STEP := 0.35                 # 骰盅每個物理步最多移動多遠（跟不上滑鼠也不要讓骰子穿過盅壁）
const CUP_WALL := 0.6                      # 盅壁厚度（薄了骰子一甩就穿出去）
const THROW_SPEED := Vector2(8.0, 24.0)    # 丟出去的速度範圍（蓄力條 0 → 1；骰盅照放開時的速度夾在這裡）
const CHARGE_PERIOD := 1.1                 # 力道條來回一次的秒數
const REST_LIN := 0.15                     # 速度小於這個算停住
const REST_ANG := 0.3                      # 只看翻滾（繞水平軸）：平躺著原地打轉不會換面，不用等它轉完
const REST_FRAMES := 18                    # 連續停住這麼多個物理步才算停好
const FLAT_DOT := 0.93                     # 朝上那面的法線跟正上方的夾角餘弦小於這個 = 斜靠著，要推一下
const MAX_NUDGES := 1                      # 推了這麼多次還斜著 / 疊著：那顆從半空重新丟下來
const SETTLE_TIMEOUT := 6.0               # 到了還沒停好：還在動 / 斜著 / 疊著的那幾顆直接擺平（照最接近朝上的那面），不讓人等
const ON_TABLE_Y := 0.8                    # 停住時中心高過這個 = 疊在別顆上面（也算沒停好）
# 骰子 6 面的法線（面編號 = 骰面陣列的 index）
const NORMALS: Array[Vector3] = [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
const DICE_LAYER := 2                      # 骰子多一層碰撞層：點骰子只打這層（看不到的高牆有 6 高，斜著看射線會先打到牆）
const REC_EVERY := 2                       # 錄影每 2 個物理步錄一幀（30 幀 / 秒；播的時候兩幀之間補間）
const REC_CHUNK := 6                       # 每 6 幀（0.2 秒）送一段：隊友晚約這麼久 + 網路延遲看到
const PLAY_LEAD := 5                       # 收到這麼多幀才開始播（網路抖一下不會播到一半停住）
const PLAY_CATCH_UP := 15                  # 落後超過這麼多幀就加快 1.25 倍追上

var cup_mode := true
var record_enabled := false         # 連線時 main.gd 開：自己擲的錄下來
var replaying := false              # 正在播隊友擲的錄影（骰子凍住，照錄影擺）
var replays_done := 0               # 播完幾次隊友的錄影（連線檢查用）
var can_throw := false              # DicePanel 每幀設：輪到本機、還能擲 / 重擲、骰子沒在轉
var can_pick := false               # 停好之後還能重擲：點骰子才收
var state := State.IDLE
var charge := 0.0                   # 蓄力條 0~1（畫面讀）
var charging := false

var _viewport := SubViewport.new()
var _camera := Camera3D.new()
var _dice: Array[RigidBody3D] = []
var _faces: Array = []              # 每顆的 6 面（StringName），畫面照它上色
var _weapon_id: StringName = &""
var _kept: Array[bool] = [false, false, false, false, false, false]
var _rolling: Array[bool] = []      # 這次有丟出去的（保留區的不算）
var _rest_frames := 0
var _nudges := 0
var _roll_time := 0.0
var _charge_t := 0.0
var _cup: AnimatableBody3D
var _cup_mesh: MeshInstance3D
var _cup_target := Vector3.ZERO
var _cup_vel := Vector3.ZERO
var _cup_prev := Vector3.ZERO
var _cup_arming := 0              # 骰盅剛出現：先關碰撞幾個物理步（從桌子底下瞬移上來，物理會當成高速撞上去把骰子彈飛）
var _face_nodes: Array = []         # 每顆 6 個 [底色 MeshInstance3D, Label3D]
var _font: Font
var _rec_id := 0                    # 正在錄的這一次擲的編號（隨機，隊友靠它分辨是不是新的一次）；0 = 沒在錄
var _rec_buf := StreamPeerBuffer.new()
var _rec_frames := 0                # 這一段錄了幾幀
var _rec_tick := 0
var _frame_clack := 0.0             # 這一幀最大的撞擊聲（錄進去，隊友播的時候照著響）
var _play_id := 0                   # 正在播的錄影編號
var _play: Array = []               # 收到的幀：[骰盅看得到, 撞擊聲, 骰盅位置, [[位置, 轉向] × 6]]
var _play_t := 0.0                  # 播到第幾幀（有小數 = 兩幀之間）
var _play_done := -1                # 撞擊聲播到第幾幀
var _play_final := false            # 最後一段收到了
var _slow := 1.0                    # 放慢的倍速（演出）：骰子的速度與重力照它縮，物理照樣算，看起來就是慢動作
var _suspense_die := -1             # 放慢時盯著的那顆（鏡頭推過去）；-1 = 沒在放慢
var _suspense_t := 0.0              # 放慢了幾秒（實際時間）
var _cam_home := Transform3D()      # 鏡頭平常的位置
var _cam_focus := -1                # 鏡頭推近哪一顆（自己放慢、或播隊友錄影裡的）
var world_mode := false             # 放進遊戲的 3D 世界（use_world）
var _ext_cam: Camera3D              # 放進遊戲世界時用遊戲的鏡頭
var _root: Node3D
var _sun: DirectionalLight3D
var _env: WorldEnvironment
var _felt: MeshInstance3D
const WORLD_FELT := Color("5c2328")   # 放進遊戲世界時的絨布（酒紅）：綠的在遊戲的暖光下跟草地分不出來


func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(VIEW_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = VIEW_SIZE
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.physics_object_picking = false
	add_child(_viewport)
	_font = load("res://assets/fonts/hud_font.tres")
	_build_scene()


func _ready() -> void:
	# 這個 3D 世界自己的重力（骰子邊長 1，預設 9.8 太慢）
	PhysicsServer3D.area_set_param(_viewport.find_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, GRAVITY)


# ---------- 場景 ----------

func _build_scene() -> void:
	var root := Node3D.new()
	_root = root
	_viewport.add_child(root)
	_camera.fov = 36.0
	_camera.look_at_from_position(Vector3(0, 12.0, 8.0), Vector3(0, 0, -0.7))   # 還沒進場景樹：不能用 look_at
	_cam_home = _camera.transform
	root.add_child(_camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -30, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	_sun = sun
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.7, 0.62)
	env.environment.ambient_light_energy = 0.75
	_env = env
	root.add_child(env)
	# 桌面（深綠絨布）與木框；保留區是後面一條木架
	var felt := _box(Vector3(PLAY.x + 1.2, 0.4, PLAY.y + 1.2), Vector3(0, -0.2, 0), Color("2f4a37"))
	_felt = felt
	root.add_child(felt)
	var wood := Color("5a3d28")
	for w: Array in [[Vector3(PLAY.x + 1.2, WALL_H, 0.6), Vector3(0, WALL_H / 2.0, -PLAY.y / 2.0 - 0.3)],
			[Vector3(PLAY.x + 1.2, WALL_H, 0.6), Vector3(0, WALL_H / 2.0, PLAY.y / 2.0 + 0.3)],
			[Vector3(0.6, WALL_H, PLAY.y + 1.2), Vector3(-PLAY.x / 2.0 - 0.3, WALL_H / 2.0, 0)],
			[Vector3(0.6, WALL_H, PLAY.y + 1.2), Vector3(PLAY.x / 2.0 + 0.3, WALL_H / 2.0, 0)]]:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = w[0]
		col.shape = shape
		body.add_child(col)
		body.position = w[1]
		root.add_child(body)
		var rim := MeshInstance3D.new()   # 只畫矮的木框，上面是看不到的牆
		var bm := BoxMesh.new()
		bm.size = Vector3(w[0].x, RIM_H, w[0].z)
		rim.mesh = bm
		rim.material_override = _mat(wood)
		rim.position = Vector3(w[1].x, RIM_H / 2.0, w[1].z)
		root.add_child(rim)
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(PLAY.x + 2.0, 0.4, PLAY.y + 2.0)
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	floor_body.position = Vector3(0, -0.2, 0)
	floor_body.physics_material_override = _phys(0.7, 0.2)
	root.add_child(floor_body)
	root.add_child(_box(Vector3(PLAY.x + 1.2, 0.3, 1.8), Vector3(0, -0.15, SHELF_Z), Color("6b4a31")))
	for i in DiceDefs.DICE_COUNT:
		var d := _make_die(i)
		root.add_child(d)
		_dice.append(d)
		_rolling.append(false)
	_build_cup(root)
	_line_up()


func _make_die(i: int) -> RigidBody3D:
	var d := RigidBody3D.new()
	d.collision_layer = 1 | DICE_LAYER   # 照樣跟牆、桌面、骰盅、別顆撞；點骰子的射線只看 DICE_LAYER
	d.mass = 1.0
	d.continuous_cd = true
	d.can_sleep = true
	d.contact_monitor = true
	d.max_contacts_reported = 4
	d.physics_material_override = _phys(0.55, 0.32)
	d.angular_damp = 0.6
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE
	col.shape = shape
	d.add_child(col)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.98
	body.mesh = bm
	body.material_override = _mat(Color("efe6d4"))
	d.add_child(body)
	var nodes: Array = []
	for k in NORMALS.size():
		var n: Vector3 = NORMALS[k]
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.84, 0.84)
		quad.mesh = qm
		d.add_child(quad)
		_face_to(quad, n, 0.495)
		var lab := Label3D.new()
		lab.font = _font
		lab.font_size = 64
		lab.pixel_size = 0.0078
		lab.outline_size = 0
		lab.modulate = Color(0.08, 0.06, 0.04)
		lab.double_sided = false
		lab.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		d.add_child(lab)
		_face_to(lab, n, 0.502)
		nodes.append([quad, lab])
	_face_nodes.append(nodes)
	d.body_entered.connect(func(_other: Node) -> void:
		var v := d.linear_velocity.length()
		if v > 1.2 and state != State.SETTLED and not replaying:
			var gain := clampf(v / 14.0, 0.15, 1.0)
			_frame_clack = maxf(_frame_clack, gain)
			clacked.emit(gain))
	return d


# 把面（QuadMesh 預設朝 +Z）轉成朝 n、放在離中心 dist 的地方
static func _face_to(node: Node3D, n: Vector3, dist: float) -> void:
	node.position = n * dist
	if n == Vector3.BACK:
		node.basis = Basis()
	elif n == Vector3.FORWARD:
		node.basis = Basis(Vector3.UP, PI)
	else:
		node.basis = Basis(Quaternion(Vector3.BACK, n))


func _build_cup(root: Node3D) -> void:
	_cup = AnimatableBody3D.new()
	_cup.sync_to_physics = true
	var ring := 12
	for k in ring:   # 一圈厚牆 + 頂蓋：底是開的，蓋在桌面上把骰子罩住（內緣半徑 CUP_RADIUS）
		var a := TAU * k / ring
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		var mid := CUP_RADIUS + CUP_WALL / 2.0
		shape.size = Vector3(2.0 * (CUP_RADIUS + CUP_WALL) * tan(PI / ring) + 0.1, CUP_HEIGHT, CUP_WALL)
		col.shape = shape
		col.position = Vector3(sin(a), 0, cos(a)) * mid + Vector3(0, CUP_HEIGHT / 2.0, 0)
		col.rotation.y = a
		_cup.add_child(col)
	var lid := CollisionShape3D.new()
	var lid_shape := CylinderShape3D.new()
	lid_shape.radius = CUP_RADIUS + 0.1
	lid_shape.height = 0.25
	lid.shape = lid_shape
	lid.position = Vector3(0, CUP_HEIGHT, 0)
	_cup.add_child(lid)
	_cup_mesh = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = CUP_RADIUS + CUP_WALL * 0.6
	cm.bottom_radius = CUP_RADIUS + CUP_WALL
	cm.height = CUP_HEIGHT
	_cup_mesh.mesh = cm
	var m := _mat(Color(0.33, 0.2, 0.12, 0.88))
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cup_mesh.material_override = m
	_cup_mesh.position = Vector3(0, CUP_HEIGHT / 2.0, 0)
	_cup.add_child(_cup_mesh)
	_cup.position = Vector3(0, -20, 0)
	_cup.collision_layer = 0
	root.add_child(_cup)


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.75
	return m


static func _phys(friction: float, bounce: float) -> PhysicsMaterial:
	var p := PhysicsMaterial.new()
	p.friction = friction
	p.bounce = bounce
	return p


static func _box(size: Vector3, at: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = at
	return mi


# ---------- 對外 ----------

# 骰面（每顆 6 面）與這把武器（技能面能不能用決定顏色）；變了才重畫
func set_faces(pool: Array, weapon_id: StringName) -> void:
	if pool == _faces and weapon_id == _weapon_id:
		return
	_faces = pool.duplicate(true)
	_weapon_id = weapon_id
	for i in mini(_dice.size(), pool.size()):
		var die: Array = pool[i]
		for k in NORMALS.size():
			var face: StringName = die[k]
			var kind := DiceDefs.kind_of(face, weapon_id)
			var nodes: Array = _face_nodes[i][k]
			(nodes[0] as MeshInstance3D).material_override = _mat(DicePanel.KIND_COLORS[kind])
			var lab := nodes[1] as Label3D
			lab.text = DiceDefs.icon_of(face) if not SkillIcons.has(DiceDefs.icon_of(face)) else DiceDefs.name_of(face).substr(0, 1)
			lab.modulate = Color(0.95, 0.93, 0.9) if kind == &"blank" else Color(0.08, 0.06, 0.04)


# 一次新的擲骰（新的一場、自己花次數擲）：全部回到桌子中間排一排、各露出不同的面
func reset_round() -> void:
	_kept.fill(false)
	state = State.IDLE
	_stop_replay()
	_end_suspense()
	_rec_id = 0
	charging = false
	_hide_cup()
	_line_up()


# 保留區：kept 的照 face 那面朝上擺在後面的木架，不動；從保留區放回的擺回桌上原位附近
func set_kept(kept: Array[bool], faces: Array[int]) -> void:
	for i in _dice.size():
		var want: bool = kept[i] if i < kept.size() else false
		if want == _kept[i]:
			continue
		_kept[i] = want
		var d := _dice[i]
		if want:
			_place(d, Vector3(-PLAY.x / 2.0 + 1.6 + i * 1.75, 0.5, SHELF_Z), faces[i] if i < faces.size() else 0, true)
		else:
			_place(d, Vector3(-PLAY.x / 2.0 + 1.6 + i * 1.75, 0.5, 0.8), faces[i] if i < faces.size() else 0, false)


# 停好之後模擬層的面跟桌上不一樣（模擬層等太久自己抽了）：桌上那顆原地擺成模擬層的面
func match_faces(faces: Array[int]) -> void:
	for i in mini(_dice.size(), faces.size()):
		if not _kept[i] and up_face(_dice[i]) != faces[i]:
			var at := _dice[i].position
			_place(_dice[i], Vector3(at.x, 0.5, at.z), faces[i], false)


# 現在每顆朝上的面編號
func up_faces() -> Array[int]:
	var out: Array[int] = []
	for d in _dice:
		out.append(up_face(d))
	return out


static func up_face(d: Node3D) -> int:
	var best := 0
	var best_y := -2.0
	for k in NORMALS.size():
		var y := (d.global_transform.basis * NORMALS[k]).y
		if y > best_y:
			best_y = y
			best = k
	return best


static func up_dot(d: Node3D) -> float:
	var best := -2.0
	for n in NORMALS:
		best = maxf(best, (d.global_transform.basis * n).y)
	return best


# 不用滑鼠直接丟（時間到自動擲、骰盅模式按鍵盤、檢查）：power 0~1
func auto_throw(power: float) -> void:
	_hide_cup()
	_throw_from_edge(power)


# 蓄力條（滑鼠 / 空白鍵）
func begin_charge() -> void:
	if not can_throw or state == State.ROLLING or state == State.AIM:
		return
	charging = true
	_charge_t = 0.0
	charge = 0.0


func release_charge() -> void:
	if not charging:
		return
	charging = false
	if can_throw:
		_throw_from_edge(charge)


# ---------- 擲 ----------

func _throw_from_edge(power: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_begin_record()
	var speed := lerpf(THROW_SPEED.x, THROW_SPEED.y, clampf(power, 0.0, 1.0))
	var n := 0
	for i in _dice.size():
		_rolling[i] = not _kept[i]
		if not _rolling[i]:
			continue
		var d := _dice[i]
		d.freeze = false
		d.transform = Transform3D(random_basis(rng),
			Vector3(-PLAY.x / 2.0 + 1.0 + (n % 2) * 1.1, 1.5 + float(n / 2) * 1.1, rng.randf_range(-1.6, 1.6)))
		d.linear_velocity = _g(Vector3(speed * rng.randf_range(0.85, 1.1), rng.randf_range(2.0, 5.0), rng.randf_range(-0.25, 0.25) * speed))
		d.angular_velocity = Vector3(rng.randf_range(-18, 18), rng.randf_range(-18, 18), rng.randf_range(-18, 18))
		d.sleeping = false
		n += 1
	_start_rolling()


func _start_rolling() -> void:
	state = State.ROLLING
	_rest_frames = 0
	_nudges = 0
	_roll_time = 0.0
	_suspense_t = 0.0   # 每丟一次最多放慢一次
	thrown.emit()


func _gui_input(event: InputEvent) -> void:
	if not world_mode and _pointer(event):
		accept_event()


# 放進遊戲世界時 DicePanel 把滑鼠事件轉過來（座標是遊戲畫面的）；回傳有沒有處理
func world_input(event: InputEvent) -> bool:
	return world_mode and _pointer(event)


func _pointer(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit := _pick_die(event.position)
			if hit >= 0 and (can_pick or _kept[hit]) and state != State.ROLLING and state != State.AIM:
				die_clicked.emit(hit)
			elif can_throw and state != State.ROLLING:
				if cup_mode:
					_begin_cup(event.position)
				else:
					begin_charge()
		else:
			if state == State.AIM:
				_release_cup()
			elif charging:
				release_charge()
		return true
	if event is InputEventMouseMotion and state == State.AIM:
		_cup_target = _table_point(event.position, CUP_HEIGHT * 0.05)
		return true
	return false


func _to_view(p: Vector2) -> Vector2:
	return p * Vector2(VIEW_SIZE) / size if size.x > 0.0 else p


func _table_point(p: Vector2, h: float) -> Vector3:
	var ray := _ray(p)
	var from: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	if absf(dir.y) < 1e-4:
		return Vector3.ZERO
	var t := (h - from.y) / dir.y
	var at := from + dir * t
	var lim := Vector2(PLAY.x / 2.0 - CUP_RADIUS - CUP_WALL - 0.1, PLAY.y / 2.0 - CUP_RADIUS - CUP_WALL - 0.1)
	return Vector3(clampf(at.x, -lim.x, lim.x), h, clampf(at.z, -lim.y, lim.y))


func _pick_die(p: Vector2) -> int:
	var cam := _ext_cam if world_mode else _camera
	var vp := p if world_mode else _to_view(p)
	var space := _root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(cam.project_ray_origin(vp), cam.project_ray_origin(vp) + cam.project_ray_normal(vp) * 200.0, DICE_LAYER)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -1
	for i in _dice.size():   # 打到桌子、牆也會回傳：只認骰子
		if _dice[i] == hit.collider:
			return i
	return -1


# 骰盅：罩住要丟的骰子（在骰盅裡排好），之後跟著滑鼠
func _begin_cup(p: Vector2) -> void:
	state = State.AIM
	_begin_record()
	_cup_target = _table_point(p, CUP_HEIGHT * 0.05)
	_cup.collision_layer = 0
	_cup.position = _cup_target
	_cup_prev = _cup_target
	_cup_vel = Vector3.ZERO
	_cup_arming = 2
	_cup.visible = true
	var n := 0
	for i in _dice.size():
		_rolling[i] = not _kept[i]
		if not _rolling[i]:
			continue
		var d := _dice[i]
		d.freeze = false
		# 兩層各 3 顆、平放（隨機一面朝上 + 隨機水平轉向：一樣公平），間距大過骰子對角線，一開始不會互相卡進去被物理彈飛
		var a := TAU * (n / 2) / 3.0 + (PI / 3.0 if n % 2 == 1 else 0.0)
		var at := _cup_target + Vector3(cos(a) * 0.85, 0.52 + (n % 2) * 1.06, sin(a) * 0.85)
		var up := NORMALS[randi_range(0, NORMALS.size() - 1)]
		var flat := Basis(Quaternion(up, Vector3.UP)) if up != Vector3.DOWN else Basis(Vector3.RIGHT, PI)
		d.transform = Transform3D(Basis(Vector3.UP, randf() * TAU) * flat, at)
		d.linear_velocity = Vector3.ZERO
		d.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		d.sleeping = false
		n += 1


func _release_cup() -> void:
	var v := _cup_vel
	v.y = 0.0
	var speed := clampf(v.length(), THROW_SPEED.x, THROW_SPEED.y)
	var dir := v.normalized() if v.length() > 0.5 else Vector3.RIGHT
	var side := Vector3(-dir.z, 0, dir.x)   # 往兩側散開一點：輕輕丟也不會整團堆在牆邊疊起來
	for i in _dice.size():
		if not _rolling[i]:
			continue
		var d := _dice[i]
		d.linear_velocity = _g(dir * speed * randf_range(0.8, 1.05) + side * speed * randf_range(-0.3, 0.3) + Vector3(0, randf_range(2.0, 4.5), 0))
		d.angular_velocity += Vector3(randf_range(-14, 14), randf_range(-14, 14), randf_range(-14, 14))
		d.sleeping = false
	_hide_cup()
	_start_rolling()


# 甩的時候的保險：骰子碰到盅壁內緣就拉回裡面、往內反彈（甩太快物理偶爾會讓骰子穿過盅壁；骰盅不透明，看不出來）
func _keep_in_cup() -> void:
	var inner := CUP_RADIUS - 0.6
	for i in _dice.size():
		if not _rolling[i]:
			continue
		var d := _dice[i]
		var off := d.position - _cup.position
		var flat := Vector2(off.x, off.z)
		var fixed := false
		if flat.length() > inner:
			var n := flat.normalized()
			flat = n * inner
			var lv := _l(d.linear_velocity)
			var v := Vector2(lv.x, lv.z)
			if v.dot(n) > 0.0:
				v -= n * v.dot(n) * 1.5
			d.linear_velocity = _g(Vector3(v.x, lv.y, v.y))
			fixed = true
		var y := clampf(off.y, 0.5, CUP_HEIGHT - 0.6)
		if fixed or y != off.y:
			d.position = _cup.position + Vector3(flat.x, y, flat.y)


func _hide_cup() -> void:
	_cup.collision_layer = 0
	_cup.visible = false
	_cup.position = Vector3(0, -20, 0)


func _physics_process(delta: float) -> void:
	_update_camera(delta)
	if replaying:
		_step_replay(delta)
		return
	_step_physics(delta)
	if _rec_id != 0:
		_record_frame()


func _step_physics(delta: float) -> void:
	if charging:
		_charge_t += delta
		charge = 1.0 - absf(fposmod(_charge_t / CHARGE_PERIOD, 2.0) - 1.0)   # 0 → 1 → 0 來回
	if state == State.AIM:
		if _cup_arming > 0:
			_cup_arming -= 1
			if _cup_arming == 0:
				_cup.collision_layer = 1
			return
		var step := _cup_target - _cup.position
		if step.length() > CUP_MAX_STEP:
			step = step.normalized() * CUP_MAX_STEP
		_cup.position += step
		_cup_vel = _cup_vel.lerp((_cup.position - _cup_prev) / delta, 0.35)
		_cup_prev = _cup.position
		_keep_in_cup()
		return
	if state != State.ROLLING:
		return
	_roll_time += delta * _slow   # 放慢時照慢動作的時間算（逾時、停好的判斷都一樣）
	var resting := true
	for i in _dice.size():
		if not _rolling[i]:
			continue
		var d := _dice[i]
		if d.position.y < -3.0:   # 掉出桌子（不該發生）：放回中間
			_place(d, Vector3(0, 1.5, 0), 0, false)
		if not _die_resting(d, 1.0):
			resting = false
	_update_suspense(delta)
	_rest_frames = _rest_frames + 1 if resting else 0
	if _rest_frames < REST_FRAMES and _roll_time < SETTLE_TIMEOUT:
		return
	if _roll_time < SETTLE_TIMEOUT:
		var cocked := false
		for i in _dice.size():
			var d := _dice[i]
			if not _rolling[i] or (up_dot(d) >= FLAT_DOT and d.position.y <= ON_TABLE_Y):
				continue
			cocked = true
			d.sleeping = false
			if _nudges < MAX_NUDGES:   # 往桌子中間推：靠牆的不會又倒回同一面牆、疊著的會滑下來
				var to_mid := -Vector3(d.position.x, 0, d.position.z).normalized() * 1.5
				d.apply_central_impulse(_g(Vector3(to_mid.x + randf_range(-1, 1), 5.5, to_mid.z + randf_range(-1, 1))))
				d.apply_torque_impulse(Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)))
			else:   # 推不開：從桌子中間附近的半空重新丟下來
				d.transform = Transform3D(random_basis(null), _free_spot(i))   # 低一點、轉慢一點：1 秒內落定，不要拖到逾時
				d.linear_velocity = Vector3.ZERO
				d.angular_velocity = Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5))
		if cocked:
			_nudges += 1
			_rest_frames = 0
			return
	if _roll_time >= SETTLE_TIMEOUT:
		for i in _dice.size():
			var d := _dice[i]
			if _rolling[i] and (up_dot(d) < FLAT_DOT or d.position.y > ON_TABLE_Y or d.linear_velocity.length() > REST_LIN):
				var spot := _free_spot(i) if d.position.y > ON_TABLE_Y else d.position
				_place(d, Vector3(spot.x, 0.5, spot.z), up_face(d), false)
	state = State.SETTLED
	_end_suspense()
	var faces := up_faces()
	settled.emit(faces)


# 平均分布的隨機轉向（4 個常態分布正規化成四元數）：Basis.from_euler 三個角各自隨機不平均，輕輕丟時某幾面會比較常朝上
static func random_basis(rng: RandomNumberGenerator) -> Basis:
	var r := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	var q := Quaternion(r.randfn(), r.randfn(), r.randfn(), r.randfn())
	return Basis(q.normalized() if q.length_squared() > 1e-8 else Quaternion.IDENTITY)


# 重新丟下來的位置：桌子中間附近、離其他骰子夠遠（找 12 次，都不夠遠就用最遠的）
func _free_spot(skip: int) -> Vector3:
	var best := Vector3(0, 1.6, 0)
	var best_gap := -1.0
	for t in 12:
		var at := Vector3(randf_range(-PLAY.x / 2.0 + 1.5, PLAY.x / 2.0 - 1.5), 1.6, randf_range(-PLAY.y / 2.0 + 1.2, PLAY.y / 2.0 - 1.2))
		var gap := INF
		for j in _dice.size():
			if j != skip:
				gap = minf(gap, Vector2(_dice[j].position.x - at.x, _dice[j].position.z - at.z).length())
		if gap > best_gap:
			best_gap = gap
			best = at
		if gap > 2.0:
			break
	return best


# 一顆擺到 at、照 face 那面朝上（隨機轉一下水平方向）；frozen = 固定不動（保留區）
func _place(d: RigidBody3D, at: Vector3, face: int, frozen: bool) -> void:
	d.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	d.freeze = frozen
	d.linear_velocity = Vector3.ZERO
	d.angular_velocity = Vector3.ZERO
	var up := Basis(Quaternion(NORMALS[face], Vector3.UP)) if NORMALS[face] != Vector3.DOWN else Basis(Vector3.RIGHT, PI)
	d.transform = Transform3D(up, at)   # 骰子都掛在原點的 root 下：本地 = 世界
	d.sleeping = false


# 一排擺在桌子中間，第 i 顆露出第 i 面（還沒擲時看得出骰子上有什麼）
func _line_up() -> void:
	for i in _dice.size():
		_rolling[i] = false
		_place(_dice[i], Vector3(-PLAY.x / 2.0 + 1.6 + i * 1.75, 0.5, 0.8), i % NORMALS.size(), false)


# ---------- 連線：錄影與播放 ----------
# 一段的格式：u32 編號、u8 是不是最後一段、u8 幾幀，接著每幀：u8 骰盅看得到、u8 撞擊聲（0~255）、u8 鏡頭盯哪一顆（255 = 沒有）、
# 骰盅位置（3 個 half）、6 顆各 [位置 3 個 half、轉向四元數 4 個 half]；一幀 93 bytes，30 幀 / 秒約 2.8 KB / 秒

func _begin_record() -> void:
	if not record_enabled:
		return
	_rec_id = randi() | 1
	_rec_buf.clear()
	_rec_frames = 0
	_rec_tick = 0
	_frame_clack = 0.0


func _record_frame() -> void:
	_rec_tick += 1
	var done := state == State.SETTLED
	if _rec_tick % REC_EVERY != 0 and not done:
		return
	_rec_buf.put_u8(1 if _cup.visible else 0)
	_rec_buf.put_u8(roundi(clampf(_frame_clack, 0.0, 1.0) * 255.0))
	_rec_buf.put_u8(_suspense_die if _suspense_die >= 0 else 255)
	_frame_clack = 0.0
	_put_vec(_rec_buf, _cup.position)
	for d in _dice:
		_put_vec(_rec_buf, d.position)
		var q := d.quaternion
		for v: float in [q.x, q.y, q.z, q.w]:
			_rec_buf.put_half(v)
	_rec_frames += 1
	if _rec_frames >= REC_CHUNK or done:
		var out := StreamPeerBuffer.new()
		out.put_u32(_rec_id)
		out.put_u8(1 if done else 0)
		out.put_u8(_rec_frames)
		out.put_data(_rec_buf.data_array)
		_rec_buf.clear()
		_rec_frames = 0
		if done:
			_rec_id = 0
		frames_recorded.emit(out.data_array)


static func _put_vec(b: StreamPeerBuffer, v: Vector3) -> void:
	b.put_half(v.x)
	b.put_half(v.y)
	b.put_half(v.z)


static func _get_vec(b: StreamPeerBuffer) -> Vector3:
	return Vector3(b.get_half(), b.get_half(), b.get_half())


# 收到隊友擲的一段：新的編號就從頭播；收夠 PLAY_LEAD 幀（或最後一段到了）才開始播。自己正在擲時不收
func play_frames(data: PackedByteArray) -> void:
	if _rec_id != 0 or state == State.AIM or (state == State.ROLLING and not replaying):
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var id := b.get_u32()
	var final := b.get_u8() == 1
	var n := b.get_u8()
	if id != _play_id:
		_stop_replay()
		_play_id = id
	for k in n:
		var cup_seen := b.get_u8() == 1
		var clack := b.get_u8() / 255.0
		var focus := b.get_u8()
		var cup := _get_vec(b)
		var dice := []
		for i in _dice.size():
			var at := _get_vec(b)
			dice.append([at, Quaternion(b.get_half(), b.get_half(), b.get_half(), b.get_half()).normalized()])
		_play.append([cup_seen, clack, cup, dice, focus if focus < _dice.size() else -1])
	_play_final = _play_final or final
	if not replaying and not _play.is_empty() and (_play.size() >= PLAY_LEAD or _play_final):
		replaying = true
		state = State.ROLLING
		charging = false
		_cup.collision_layer = 0
		for d in _dice:
			d.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			d.freeze = true


func _stop_replay() -> void:
	if replaying:
		_set_focus(-1)
	replaying = false
	_play.clear()
	_play_t = 0.0
	_play_done = -1
	_play_final = false
	_play_id = 0


# 播放：照錄影的時間走（兩幀之間補間），落後太多加快；播完最後一幀就算停好（不送 settled：結果以房主的為準）
func _step_replay(delta: float) -> void:
	var last := _play.size() - 1
	var rate := 60.0 / REC_EVERY * (1.25 if last - _play_t > PLAY_CATCH_UP else 1.0)
	_play_t = minf(_play_t + delta * rate, float(last))
	var i := floori(_play_t)
	var j := mini(i + 1, last)
	var t := _play_t - i
	var a: Array = _play[i]
	var b: Array = _play[j]
	_cup.visible = a[0]
	_cup.position = (a[2] as Vector3).lerp(b[2], t) if a[0] else Vector3(0, -20, 0)
	for k in _dice.size():
		var d := _dice[k]
		if not d.freeze:
			d.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			d.freeze = true
		var pa: Array = a[3][k]
		var pb: Array = b[3][k]
		d.transform = Transform3D(Basis((pa[1] as Quaternion).slerp(pb[1], t)), (pa[0] as Vector3).lerp(pb[0], t))
	while _play_done < i:
		_play_done += 1
		if _play[_play_done][1] > 0.0:
			clacked.emit(_play[_play_done][1])
	_set_focus(a[4])
	if _play_t >= last and _play_final:
		replaying = false
		replays_done += 1
		state = State.SETTLED
		_set_focus(-1)
		_hide_cup()



# ---------- 演出：最後一顆放慢、鏡頭推近 ----------

# 停住了嗎（速度照放慢的倍速換回正常速度再比；loose > 1 = 放寬，用來判斷「差不多停了」）
func _die_resting(d: RigidBody3D, loose: float) -> bool:
	if d.sleeping:
		return true
	var tumble := Vector2(d.angular_velocity.x, d.angular_velocity.z).length() / _slow
	return d.linear_velocity.length() / _slow <= REST_LIN * loose and tumble <= REST_ANG * loose


func _update_suspense(delta: float) -> void:
	if _suspense_die >= 0:
		_suspense_t += delta
		if _suspense_t >= DiceDefs.SUSPENSE_MAX or _die_resting(_dice[_suspense_die], 1.0):
			_end_suspense()
		return
	if _slow == 1.0 and _roll_time > 0.5 and _suspense_t == 0.0:
		var k := suspense_candidate()
		if k >= 0:
			_begin_suspense(k)


# 只剩一顆還在滾（其他的差不多停了），而且它停在某一面就能讓同一招湊到 3 個以上：回傳那一顆，否則 -1
func suspense_candidate() -> int:
	var moving := -1
	for i in _dice.size():
		if _rolling[i] and not _die_resting(_dice[i], 3.0):
			if moving >= 0:
				return -1
			moving = i
	if moving < 0 or _faces.size() < _dice.size():
		return -1
	var counts := {}
	for i in _dice.size():
		if i == moving:
			continue
		var face: StringName = _faces[i][up_face(_dice[i])]
		if DiceDefs.skill_fits(face, _weapon_id):
			counts[face] = counts.get(face, 0) + 1
	for face: StringName in counts:
		if counts[face] >= 2 and (_faces[moving] as Array).has(face):
			return moving
	return -1


func _begin_suspense(k: int) -> void:
	_suspense_die = k
	_suspense_t = 0.0
	_set_slow(DiceDefs.SUSPENSE_SLOW)
	_set_focus(k)


func _end_suspense() -> void:
	if _suspense_die < 0:
		return
	_suspense_die = -1
	_set_slow(1.0)
	_set_focus(-1)


# 慢動作：速度乘上倍速的比例、重力乘上倍速平方，軌跡跟原本一樣、只是走得慢
func _set_slow(v: float) -> void:
	var ratio := v / _slow
	for i in _dice.size():
		var d := _dice[i]
		if _rolling[i] and not d.freeze:
			d.linear_velocity *= ratio
			d.angular_velocity *= ratio
	_slow = v
	if is_inside_tree():
		PhysicsServer3D.area_set_param(_root.get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, GRAVITY * v * v)


# 鏡頭盯哪一顆（-1 = 回原位）；換了就送 suspense_changed（播隊友錄影時也送，音樂一起收小）
func _set_focus(k: int) -> void:
	if k == _cam_focus:
		return
	var was := _cam_focus >= 0
	_cam_focus = k
	if was != (k >= 0):
		suspense_changed.emit(k >= 0)


func _update_camera(delta: float) -> void:
	var want := _cam_home
	if _cam_focus >= 0 and _cam_focus < _dice.size():
		var at := _dice[_cam_focus].position
		want = Transform3D.IDENTITY.translated(at + Vector3(0, 6.5, 4.2)).looking_at(at, Vector3.UP)
	_camera.transform = _camera.transform.interpolate_with(want, clampf(delta * 5.0, 0.0, 1.0))



# ---------- 放進遊戲的 3D 世界（骰子模式：戰場旁的骰盤）----------

# 桌子的 3D 節點搬到 parent 底下（遊戲的 3D 世界）、用 cam（遊戲的鏡頭）看；自己的光與環境關掉（遊戲世界有自己的），自己的畫面不再畫
# 用搬節點、不是換 SubViewport 的世界：執行中換世界引擎會報錯（scenario 是 null）
func use_world(parent: Node3D, cam: Camera3D) -> void:
	world_mode = true
	_ext_cam = cam
	_sun.visible = false
	_env.environment = null
	_felt.material_override = _mat(WORLD_FELT)
	# 放在戰場旁的地上：底下墊一塊厚木座（地面高低不一，桌子墊高後看起來像一個擺在桌上的骰盒，不是浮在半空）
	_root.add_child(_box(Vector3(PLAY.x + 1.8, 1.6, PLAY.y + 1.8), Vector3(0, -1.2, 0), Color("4a3020")))
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_root.remove_child(_camera)   # 桌子自己的鏡頭留在自己的畫面裡：跟著搬過去會變成遊戲畫面的鏡頭
	_viewport.add_child(_camera)
	_viewport.remove_child(_root)
	parent.add_child(_root)
	_root.visible = false
	PhysicsServer3D.area_set_param(_root.get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, GRAVITY * _slow * _slow)


# 搬出去的節點不在自己底下：桌子被釋放時一起放掉
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and world_mode and is_instance_valid(_root):
		_root.queue_free()


# 桌子擺在哪（只繞 Y 轉、不縮放：剛體不能縮放）；丟出去之後就不要再搬
func set_origin(t: Transform3D) -> void:
	_root.transform = t


func set_shown(v: bool) -> void:
	_root.visible = v


# 骰盤在遊戲世界的中心；放慢時鏡頭要推近的那顆的位置（沒有回傳 null）
func center() -> Vector3:
	return _root.global_position


func focus_point() -> Variant:
	if _cam_focus < 0 or _cam_focus >= _dice.size():
		return null
	return _dice[_cam_focus].global_position


# 螢幕座標 → 桌面本地的射線 [起點, 方向]
func _ray(p: Vector2) -> Array:
	var cam := _ext_cam if world_mode else _camera
	var vp := p if world_mode else _to_view(p)
	var from := cam.project_ray_origin(vp)
	var dir := cam.project_ray_normal(vp)
	if world_mode:
		var inv := _root.global_transform.affine_inverse()
		from = inv * from
		dir = (inv.basis * dir).normalized()
	return [from, dir]


# 桌面本地的方向 ↔ 世界的方向（速度、衝量）
func _g(v: Vector3) -> Vector3:
	return _root.global_transform.basis * v if world_mode else v


func _l(v: Vector3) -> Vector3:
	return _root.global_transform.basis.inverse() * v if world_mode else v
