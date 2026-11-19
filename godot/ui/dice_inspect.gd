# 骰子模式的「拿起來看」（畫面層，docs/系統說明.md §55「獎勵畫面看骰子」）：一排 3D 骰子，按住一顆拖曳就轉著看每一面，放開慢慢轉回原位
# 獎勵畫面用：你帶的 6 顆，後面接獎勵裡的新骰子（新骰子會換掉的那顆抬高、標紅、箭頭指過去）、新武器的骰子
# 自己一個 3D 世界（不碰遊戲世界）；骰子外觀與擲骰桌同一套（DiceTable.build_die_visual / paint_die）
class_name DiceInspect
extends SubViewportContainer

const VIEW_SIZE := Vector2i(1240, 260)
const GAP := 1.45                # 骰子間距（世界單位，骰子邊長 1）
const EXTRA_GAP := 1.0           # 你帶的骰子與獎勵的骰子之間多空一點（放箭頭）
const DRAG_SPEED := 0.012        # 拖曳 1 像素轉幾弧度
const SPRING := 4.0              # 放開後轉回原位的快慢
const LIFT := 0.35               # 會被換掉的那顆抬高多少
# 平常的擺法：轉 45 度、鏡頭從斜上方看，看得到上面與前面兩個側面（三面）；其他面拖曳轉過來看
const REST := Vector3(0.0, PI / 4.0, 0.0)
const REPLACE_COLOR := Color("ff6b5a")

var _viewport := SubViewport.new()
var _camera := Camera3D.new()
var _root := Node3D.new()
var _font: Font
var _dice: Array[Node3D] = []
var _faces: Array = []           # 每顆的面（StringName × 6），檢查讀
var _tags: Array[Label3D] = []
var _arrow := Label3D.new()
var _drag := -1
var _last := Vector2.ZERO
var _key: Array = []
var replace_slot := -1           # 標成會被換掉的是第幾顆（-1 = 沒有）


func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(VIEW_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = VIEW_SIZE
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	_font = load("res://assets/fonts/hud_font.tres")
	_viewport.add_child(_root)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 3.4
	_root.add_child(_camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.light_energy = 1.15
	_root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.76, 0.7)
	env.environment.ambient_light_energy = 0.8
	_root.add_child(env)
	_arrow.text = "→"
	_arrow.font = _font
	_arrow.font_size = 96
	_arrow.pixel_size = 0.008
	_arrow.modulate = REPLACE_COLOR
	_arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_arrow.visible = false
	_root.add_child(_arrow)


# 你帶的骰子 carried（每顆 6 面）照 weapon_id 上色；extras：[[面, 上色看的武器, 標籤], …]（獎勵裡的骰子）；
# replace：拿新骰子會換掉帶著的第幾顆（-1 = 沒有）。內容沒變不重建（拖到一半不會被打斷）
func show_dice(carried: Array, weapon_id: StringName, extras: Array, replace: int) -> void:
	var key := [carried, weapon_id, extras, replace]
	if key == _key:
		return
	_key = key.duplicate(true)
	for d in _dice:
		d.queue_free()
	for t in _tags:
		t.queue_free()
	_dice.clear()
	_tags.clear()
	_faces.clear()
	_drag = -1
	replace_slot = replace
	var x := 0.0
	for i in carried.size():
		var tag := "會被換掉" if i == replace else "第 %d 顆" % (i + 1)
		_add_die(carried[i], weapon_id, Vector3(x, LIFT if i == replace else 0.0, 0), tag, REPLACE_COLOR if i == replace else Color(1, 1, 1, 0.8))
		x += GAP
	_arrow.visible = false
	for e: Array in extras:
		x += EXTRA_GAP
		if replace >= 0 and not _arrow.visible:
			_arrow.visible = true
			_arrow.position = Vector3(x - (GAP + EXTRA_GAP) / 2.0, 0.1, 0.6)
		_add_die(e[0], e[1], Vector3(x, 0, 0), e[2], Color("ffd45a"))
		x += GAP
	var width := x - GAP
	_camera.size = maxf(2.4, (width + 1.6) * float(VIEW_SIZE.y) / float(VIEW_SIZE.x))
	_camera.look_at_from_position(Vector3(width / 2.0, 4.0, 5.0), Vector3(width / 2.0, -0.05, 0))


func _add_die(die: Array, weapon_id: StringName, at: Vector3, tag: String, color: Color) -> void:
	var d := Node3D.new()
	d.position = at
	d.basis = Basis.from_euler(REST)
	_root.add_child(d)
	DiceTable.paint_die(DiceTable.build_die_visual(d, _font), die, weapon_id)
	_dice.append(d)
	_faces.append(die.duplicate())
	var lab := Label3D.new()
	lab.text = tag
	lab.font = _font
	lab.font_size = 40
	lab.pixel_size = 0.008
	lab.outline_size = 10
	lab.modulate = color
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position = at + Vector3(0, -0.95, 0.4)
	_root.add_child(lab)
	_tags.append(lab)


func die_count() -> int:
	return _dice.size()


# 第 i 顆的面（檢查用）與現在的轉向
func faces_of(i: int) -> Array:
	return _faces[i]


func basis_of(i: int) -> Basis:
	return _dice[i].basis


func tag_of(i: int) -> String:
	return _tags[i].text


# 螢幕座標 → 最近的那顆（投影到畫面上離骰子中心 60 像素內）
func pick(p: Vector2) -> int:
	var vp := p * Vector2(VIEW_SIZE) / size if size.x > 0.0 else p
	var best := -1
	var best_d := 60.0
	for i in _dice.size():
		var d := _camera.unproject_position(_dice[i].global_position).distance_to(vp)
		if d < best_d:
			best_d = d
			best = i
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag = pick(event.position)
			_last = event.position
		else:
			_drag = -1
		accept_event()
	elif event is InputEventMouseMotion and _drag >= 0:
		rotate_die(_drag, event.position - _last)
		_last = event.position
		accept_event()


# 拖曳 delta 像素：左右繞直立軸、上下繞水平軸轉（照畫面的方向，不是骰子自己的軸）
func rotate_die(i: int, delta: Vector2) -> void:
	var d := _dice[i]
	d.basis = (Basis(Vector3.UP, delta.x * DRAG_SPEED) * Basis(Vector3.RIGHT, delta.y * DRAG_SPEED) * d.basis).orthonormalized()


func _process(dt: float) -> void:
	var rest := Quaternion(Basis.from_euler(REST))
	for i in _dice.size():
		if i == _drag:
			continue
		var q := Quaternion(_dice[i].basis.orthonormalized())
		_dice[i].basis = Basis(q.slerp(rest, clampf(dt * SPRING, 0.0, 1.0)))
