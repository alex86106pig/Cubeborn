# 畫面層：依實體 id 建立 / 移除模型並補間位置、驅動角色動畫；燈光與背景；特效（view/effects.gd）；命中定格；F2 判定顯示（碰撞圈與攻擊判定形狀）
# 角色用 DarkFantasy 造型的 Rig + 動畫，法杖魔彈用發光球體、敵人箭矢用 DarkFantasy 造型，其他暫用方塊
class_name WorldView
extends Node3D

const HITBOX_COLOR := Color(1.0, 0.93, 0.0, 0.8)
const STRIKE_PLAYER_COLOR := Color(1.0, 0.93, 0.0)   # F2：玩家攻擊判定
const STRIKE_ENEMY_COLOR := Color(1.0, 0.25, 0.2)    # F2：怪物攻擊判定
const STRIKE_FADE := 0.3                             # 判定形狀顯示後淡出的秒數
const STRIKE_ALPHA := 0.45
const BLOCK_FAN_COLOR := Color("ffd36b")   # 格擋範圍（v0.23.0）：腳下前方的金色扇形，角度 = 盾的 block_arc
const BLOCK_FAN_RANGE := 2.2
const BLOCK_FAN_ALPHA := 0.32
const WEAPON_GLOW_RANGE := 1.6     # 武器稀有度光：所有稀有度同樣亮度，只差顏色（使用者決定）
const WEAPON_GLOW_ENERGY := 1.2
const RARITY_GLOW_RANGE := 3.0     # 魔法 / 稀有怪身上的光（D5）
const RARITY_GLOW_ENERGY := 1.5
const GRAVE_SOIL := Color("4a3a2a")          # 挖墳點（D6）
const GRAVE_STONE := Color("6a6d72")
const EXIT_COLOR := Color("8fd0ff")
const CHEST_LID_OPEN := -1.9                # 寶箱打開時箱蓋往後翻的角度（弧度）
const GHOST_TINT := Color(0.55, 0.8, 1.0)   # 冤魂（D6）的顏色與透明度
const GHOST_TRANSPARENCY := 0.45
const MINION_TINT := Color(0.55, 1.0, 0.6)   # 骷髏僕從（G6）的顏色
const FROZEN_TINT := Color(0.35, 0.75, 1.8)   # 道具狀態（v0.33.0）：冰凍偏藍、中毒偏綠（乘在模型顏色上；場景偏暗，要染重一點才看得出來）
const POISON_TINT := Color(0.4, 1.5, 0.3)
const SHADOW_MAX_DISTANCE := 70.0  # 陰影範圍（從相機算；相機距離 40，畫面最遠的地面約 60）
const LOS_INTERVAL := 3           # 視野的牆擋判斷每隻每幾個 tick 重算一次（50 毫秒）
const ENEMY_ANIM_STEP := 1.0 / 60.0 - 1e-4   # 敵人四肢動畫的最短間隔（略小於 1/60，60 FPS 時每幀都更新）
# 牆後透視剪影（v0.32.0 使用者選定）：角色被牆、石台擋住的部分畫成半透明純色（自己藍、隊友綠、怪紅）
# 作法：角色自己的材質畫的時候寫入模板值 XRAY_STENCIL；疊加材質（material_overlay）不做深度測試、只畫在模板值不是它的地方
# → 被牆擋住的部分（那裡最後畫的是牆，沒有寫模板）才看得到，被自己或其他角色擋住的不會變色
const XRAY_STENCIL := 1
const XRAY_SELF := Color(0.31, 0.64, 1.0, 0.55)
const XRAY_ALLY := Color(0.42, 1.0, 0.48, 0.5)
const XRAY_ENEMY := Color(1.0, 0.3, 0.3, 0.45)
const XRAY_SKIP := [&"Hitbox", &"BlockFan", &"RarityRing"]   # 這些子節點（地上的圈、扇形）不畫剪影
const XRAY_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, blend_mix, shadows_disabled;
stencil_mode read, compare_not_equal, 1;
uniform vec4 color : source_color;
void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
"""
const XRAY_PROBE_STEP := 0.5   # 判斷「相機方向有沒有東西擋住」的取樣間隔（單位）
static var _xray_materials: Dictionary = {}   # 顏色 -> ShaderMaterial
static var _orb_materials: Dictionary = {}    # 顏色 -> 魔彈的 StandardMaterial3D（_create_projectile）
static var _xray_shader: Shader
var _xray_on: Dictionary = {}   # 怪物 id -> 剪影是否打開（只有被擋住的才畫，省繪製次數）
var _xray_dir := Vector2(sin(Config.CAMERA.azimuth), cos(Config.CAMERA.azimuth))   # 地面上往相機的方向
var _xray_slope := tan(Config.CAMERA.elevation)   # 往相機每走 1 單位，視線升高多少

var show_hitboxes := false
var effects := Effects.new()
var _nodes: Dictionary = {}       # entity id -> Node3D
var _animators: Dictionary = {}   # entity id -> Animator（有骨架的實體）
var _frozen: Dictionary = {}           # entity id -> 剩餘定格秒數（命中定格）
var _strikes: Array[Dictionary] = []   # F2 顯示中的攻擊判定 { node, life }
var _last_strike_tick := -1
# 角色視野（D2，sim/vision.gd）：只畫本機玩家看得到的怪物、攻擊、隊友；視野外的地面蓋一層暗色
var local_peer := World.HOST_PEER_ID
var spectate_peer := 0                 # 本機陣亡後觀戰的隊友（0 = 不觀戰，由 main.gd 決定）：視野改用他的
var hidden_ids: Dictionary = {}        # 這一幀看不到的實體 id（Effects 的持續性粒子也跳過）
var _vision_key := []                  # 上次算視野時的 tick 與觀看者狀態（沒變就沿用 hidden_ids）
var _los_blocked: Dictionary = {}      # entity id -> 視線被牆擋住（分批更新，見 sync）
var _fade_level: Dictionary = {}       # entity id -> 顯示程度 0~1（視野的淡入淡出，view/fade.gd）
var _anim_pending: Dictionary = {}     # entity id -> 還沒拿去擺姿勢的秒數（敵人動畫每秒最多 60 次）
var _grave: Node3D = null              # 挖墳點（D6）
var _hitboxes_shown := false
var first_seen: Array[String] = []     # 這一幀第一次被畫出來的模型種類（main.gd 的卡頓紀錄取走後清空，v0.36.3）
var created := 0                       # 這一幀新建的模型數（--perf 的卡頓紀錄，main.gd 取走後歸零）
var _seen_keys: Dictionary = {}
var _warm_nodes: Array[Node3D] = []   # 開場預熱的模型（WARM_FRAMES 幀後移除）
var warm_keys: Array[String] = []     # 預熱過的模型種類（check.gd 確認每一種都有）
var _warm_left := 0
var profile := false                   # main 的 --perf：各段累計耗時（微秒）放進 profile_usec
var profile_usec: Dictionary = {}
var _world: World
var _vision_overlay := _create_vision_overlay()
var _sun: DirectionalLight3D
var lights_on := true                  # 設定頁「光源」：關掉時新建的點光源也不亮


func _init() -> void:
	add_child(effects)   # 建立時就掛上，WorldView 沒進場景樹就被釋放時也會一起釋放
	add_child(_vision_overlay)
	effects.hidden_ids = hidden_ids


func _ready() -> void:
	_setup_environment()


# 換了一個 World（加入 / 離開連線）：id 會重複使用，舊模型全部拿掉
func clear_views() -> void:
	for node: Node3D in _nodes.values():
		node.queue_free()
	_nodes.clear()
	_animators.clear()
	_frozen.clear()
	_fade_level.clear()
	effects.clear()


# 事件由 main.gd 轉過來：特效交給 Effects；重新開始時清掉場上的特效
func on_event(name: String, p: Dictionary) -> void:
	if name == "game:restart":
		effects.clear()
	# 視野外的特效（怪物的攻擊、命中粒子、預警圈…）不畫
	if name.begins_with("fx:") and p.has("pos"):
		var me := viewer()
		if me != null and not me.is_dead and not Vision.point_visible(_world, me, p.pos):
			return
	effects.on_event(name, p)
	_freeze_on_hit(name, p)


# 命中定格（v0.18.3，取代模擬時間放慢）：打中時攻擊者與目標的模型停住 hit_stop 秒，期間不更新位置與姿勢，之後跟上實際狀態
# 只是畫面效果，模擬照常進行；多人時其他玩家的遊戲不受影響
# v0.19.1 起預設關閉（Config.FEEL.hit_freeze）
func _freeze_on_hit(name: String, p: Dictionary) -> void:
	if name != "entity:damaged" or not Config.FEEL.hit_freeze:
		return
	var duration: float = p.get("hit_stop", 0.0)
	if duration <= 0.0:
		return
	for id: int in [p.source_id, p.target_id]:
		_frozen[id] = maxf(_frozen.get(id, 0.0), duration)


# 設定頁「陰影」（2026-10-27）：太陽開影子時每個模型多畫一次、另外畫一次陰影深度（相容渲染器）
func set_shadows(on: bool) -> void:
	_sun.shadow_enabled = on


# 設定頁「光源」（2026-10-27）：精英怪、武器、出口的點光源一起開關；腳下發光環不受影響
func set_lights(on: bool) -> void:
	lights_on = on
	for light: Light3D in _point_lights():
		light.visible = on   # 武器光拿白色武器時下一次 sync 再關掉


# 鏡頭裡亮著的點光源數（遊玩紀錄的最慢一幀附上）
func lights_on_screen(camera: Camera3D) -> int:
	var n := 0
	for light: Light3D in _point_lights():
		n += int(light.is_visible_in_tree() and camera.is_position_in_frustum(light.global_position))
	return n


# 模型上的點光源（精英怪、武器、出口）；太陽是平行光不算
func _point_lights() -> Array[Node]:
	return find_children("*", "OmniLight3D", true, false)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Config.ENVIRONMENT.background
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Config.ENVIRONMENT.hemi_sky.lerp(Config.ENVIRONMENT.hemi_ground, 0.35)
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.light_color = Config.ENVIRONMENT.sun_color
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	# 正交等距相機看得到的深度範圍很固定，一張陰影圖就夠（預設分 4 層，每個投影物要畫 4 次；D5 效能）
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = SHADOW_MAX_DISTANCE
	add_child(sun)
	sun.look_at_from_position(Vector3(-10.0, 22.0, 8.0), Vector3.ZERO)


# alpha：上一步到這一步之間的補間比例（0~1）；dt：渲染幀秒數（動畫用）
func sync(world: World, alpha: float, dt: float) -> void:
	_world = world
	_tick_warm_up()
	var me := viewer()
	# 視野只依模擬層的位置與朝向決定：同一個 tick 不必重算（D5：200 隻怪時每幀做視線判斷太慢）
	var vision_key := [world.tick, world.run_id, world.entities.size(), me, me.pos if me else Vector2.ZERO, me.facing if me else 0.0, me.is_dead if me else false]
	var t0 := Time.get_ticks_usec()
	if vision_key != _vision_key:
		_vision_key = vision_key
		hidden_ids.clear()
		var lights := Vision.lights(world)   # 火把照亮的範圍全隊看得到（F8）
		for id: int in world.entities:
			var e: Entity = world.entities[id]
			if e is Player and (e as Player).descended:   # 走進出口的玩家（D6，含自己）不畫
				hidden_ids[id] = true
				continue
			if e is Projectile:
				_xray_on[id] = _xray_needed(world, e)   # 投射物飛得快、數量少：每個 tick 都判斷牆後剪影
			if not Vision.is_hideable(me, e):
				continue
			if not lights.is_empty() and Vision.lit(lights, e.pos, Vision.view_radius(e)):
				_los_blocked.erase(id)
				continue
			if not Vision.in_view_cone(me, e.pos, Vision.view_radius(e)):
				hidden_ids[id] = true
				_los_blocked.erase(id)
				continue
			# 牆擋視線：剛進入視野時立刻判斷，之後每隻每 LOS_INTERVAL 個 tick 才重算（依 id 錯開，D5 效能）
			if not _los_blocked.has(id) or (world.tick + id) % LOS_INTERVAL == 0:
				_los_blocked[id] = Vision.line_blocked(world, me, e.pos)
				if e is Enemy:
					_xray_on[id] = _xray_needed(world, e)   # 同樣分批：每隻每 LOS_INTERVAL 個 tick 判斷一次
			if _los_blocked[id]:
				hidden_ids[id] = true
	if show_hitboxes != _hitboxes_shown:
		_hitboxes_shown = show_hitboxes
		for node: Node3D in _nodes.values():
			node.get_node(^"Hitbox").visible = show_hitboxes
	var t1 := Time.get_ticks_usec()
	var anim_usec := 0
	for id: int in _nodes.keys():
		# 實體不在了，或同一個 id 已經是另一個實體（重新開始後 id 從 1 重來，客戶端可能在同一幀就換掉）
		var e: Entity = world.entities.get(id)
		if e == null or _nodes[id].get_meta(&"entity") != e.get_instance_id():
			_nodes[id].queue_free()
			_nodes.erase(id)
			_animators.erase(id)
			_frozen.erase(id)
			_los_blocked.erase(id)
			_anim_pending.erase(id)
			_xray_on.erase(id)
			_fade_level.erase(id)
	var grabbed: Array[int] = []   # 被鐵鏟舉著的怪（迴圈後放到鏟面上）
	for id: int in world.entities:
		var e: Entity = world.entities[id]
		if not _nodes.has(id):
			_nodes[id] = _create_view(e)
			created += 1
		var node: Node3D = _nodes[id]
		if not _sync_fade(id, node, e, me, dt):
			continue   # 看不到的不必擺位置與姿勢（D5 效能）；淡出中的照常擺
		var key := _view_key(e)
		if not _seen_keys.has(key):   # --perf 的卡頓紀錄：這種模型第一次被畫出來（v0.36.3）
			_seen_keys[key] = true
			first_seen.append(key)
		if _frozen.has(id):
			_frozen[id] -= dt
			if _frozen[id] > 0.0:
				continue
			_frozen.erase(id)
		if node.has_meta(&"xray") and not Fade.is_fading(node) and node.get_meta(&"xray_shown") != _xray_on.get(id, e is Player):
			node.set_meta(&"xray_shown", _xray_on.get(id, e is Player))
			apply_xray(node, node.get_meta(&"xray"), node.get_meta(&"xray_shown"))
		var p := e.prev_pos.lerp(e.pos, alpha)
		# 位置與朝向一次寫入（分兩次寫會更新兩次子節點的變換，D5 效能）
		node.transform = Transform3D(Basis(Vector3.UP, lerp_angle(e.prev_facing, e.facing, alpha)),
			Vector3(p.x, lerpf(e.prev_height, e.height, alpha), p.y))
		if e is Enemy and (e as Enemy).anim.has("buried"):
			node.position.y -= BURIED_DEPTH    # 被鐵鏟埋進土裡（F9）：只露半身
		elif e is Enemy and (e as Enemy).anim.has("grabbed"):
			grabbed.append(id)   # 被鐵鏟舉著（F9）：等玩家的手臂姿勢算好，迴圈後放到鏟面上
		if e is Player:
			_sync_block_fan(node.get_node(^"BlockFan"), e as Player)
			var glow: OmniLight3D = node.get_meta(&"glow")
			var inst := (e as Player).active_weapon()
			glow.visible = lights_on and not inst.is_empty() and inst.rarity != &"white"
			if glow.visible:
				glow.light_color = ItemDefs.RARITIES[inst.rarity].color
		elif e is Chest:
			var lid: Node3D = node.get_node(^"Lid")
			lid.rotation.x = lerpf(lid.rotation.x, CHEST_LID_OPEN if (e as Chest).opened else 0.0, minf(1.0, dt * 8.0))
		elif e is ItemPickup or e is Coin:
			var gem: Node3D = node.get_node(^"Gem")
			var t := Time.get_ticks_msec() / 1000.0 + id * 0.7
			gem.position.y = 0.55 + 0.12 * sin(t * 2.5)
			gem.rotation.y = t * 1.6
		if _animators.has(id):
			var ta := Time.get_ticks_usec()
			var anim_dt := dt
			if e is Enemy:
				# 敵人的四肢動畫最多每秒 60 次（同模擬步）：144 FPS 時不必每幀擺姿勢；位置照樣每幀補間（D5 效能）
				anim_dt += _anim_pending.get(id, 0.0)
				if anim_dt < ENEMY_ANIM_STEP:
					_anim_pending[id] = anim_dt
					anim_dt = -1.0
				else:
					_anim_pending[id] = 0.0
			if anim_dt >= 0.0:
				_animators[id].update(e, anim_dt)
			anim_usec += Time.get_ticks_usec() - ta
			if node is SkinnedRig:
				var a: Dictionary = (e as Enemy).anim
				(node as SkinnedRig).set_status_tint(FROZEN_TINT if a.get("frozen", false) else (POISON_TINT if a.get("poisoned", false) else Color.WHITE))
			if e is Player and not Fade.is_fading(node) and node.get_meta(&"xray_weapon", &"") != (e as Player).weapon_id:
				# 換了武器：新的武器模型也要寫模板值，否則身體的剪影會畫在擋在身體前面的武器上
				node.set_meta(&"xray_weapon", (e as Player).weapon_id)
				apply_xray(node, node.get_meta(&"xray"), node.get_meta(&"xray_shown"))
	for id: int in grabbed:
		_place_on_shovel(world, world.entities[id] as Enemy, _nodes[id])
	var t2 := Time.get_ticks_usec()
	_sync_grave(world)
	_sync_strikes(world, dt)
	_sync_vision_overlay(me)
	if is_warming_up():
		_vision_overlay.visible = true
	effects.sync(world, dt)
	if profile:
		_add_profile(&"vision", t1 - t0)
		_add_profile(&"nodes", t2 - t1 - anim_usec)
		_add_profile(&"animators", anim_usec)
		_add_profile(&"effects", Time.get_ticks_usec() - t2)


# 視野的淡入淡出（view/fade.gd）：顯示程度每幀往目標（看得到 1、看不到 0）靠近，0 就整個不畫；回傳這一幀要不要畫
# 直接到位、不淡：剛建立的模型（開場、爬出來的怪）、走進出口的玩家、沒有本機角色或已陣亡（全部看得到）
func _sync_fade(id: int, node: Node3D, e: Entity, me: Player, dt: float) -> bool:
	var target := 0.0 if hidden_ids.has(id) else 1.0
	var old: float = _fade_level.get(id, -1.0)
	var level := target if old < 0.0 else old
	if me == null or me.is_dead or (e is Player and (e as Player).descended):
		level = target
	elif level != target:
		var v: Dictionary = Config.VISION
		level = move_toward(level, target, dt / (v.fade_in if target > level else v.fade_out))
	if level != old:
		_fade_level[id] = level
		if Fade.apply(node, level) and node.has_meta(&"xray"):
			# 淡入完成：接回牆後剪影（淡入淡出中不畫）
			var on: bool = _xray_on.get(id, e is Player)
			node.set_meta(&"xray_shown", on)
			apply_xray(node, node.get_meta(&"xray"), on)
	node.visible = level > 0.0
	return node.visible


func _add_profile(key: StringName, usec: int) -> void:
	profile_usec[key] = profile_usec.get(key, 0) + usec


func local_player() -> Player:
	return _world.players.get(local_peer) if _world != null else null


# 觀戰對象（多人時本機真的陣亡才觀戰；倒地假死不算）：站著、沒走進出口的隊友依 peer id 排序，
# current 不能看了（死了、走進出口、離線）就換第一位，step = ±1 換上一位 / 下一位；本機沒死或沒人可看回傳 0
static func spectate_target(world: World, local_peer: int, current: int, step := 0) -> int:
	var me: Player = world.players.get(local_peer)
	var targets: Array[int] = []
	for peer_id: int in world.players:
		var p: Player = world.players[peer_id]
		if peer_id != local_peer and not p.is_dead and not p.descended:
			targets.append(peer_id)
	if me == null or not me.is_dead or targets.is_empty():
		return 0
	targets.sort()
	var i := targets.find(current)
	return targets[0] if i < 0 else targets[posmod(i + step, targets.size())]


# 視野以誰為準：本機角色；陣亡後觀戰時是被觀戰的隊友（他的扇形、牆擋視線、變暗遮罩）
func viewer() -> Player:
	var me := local_player()
	if spectate_peer != 0 and me != null and me.is_dead:
		var target: Player = _world.players.get(spectate_peer)
		if target != null:
			return target
	return me


# 視野外（不畫）的敵人數，效能量測用
func hidden_enemy_count(world: World) -> int:
	var n := 0
	for e in world.enemies:
		n += 1 if hidden_ids.has(e.id) else 0
	return n


# 視野外變暗：蓋滿畫面的四邊形，從深度貼圖算出每個像素的世界位置，在視野扇形與身邊一圈之外蓋上暗色
# 高台、牆的頂面也照它們自己的位置判斷；牆擋住的區域不畫暗（只隱藏牆後的怪物）
const BURIED_DEPTH := 0.9   # 被埋的怪往下沉多少（F9）
const GRABBED_TILT := -0.45   # 被舉著的怪身體往後仰（弧度）
const MAX_LIGHTS := 16   # 視野遮罩最多畫幾個火把的光（F8；4 人 × 3 支 + 舉著的 4 支）

const VISION_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec2 viewer;
uniform float facing;
uniform float half_angle;
uniform float range;
uniform float near_radius;
uniform float near_edge;
uniform float range_edge;
uniform float darkness;
uniform float inner_darkness;
uniform float edge;
uniform vec3 lights[16];   // 火把的光（F8）：xz 位置 + 半徑
uniform int light_count;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	vec2 p = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xz;
	vec2 d = p - viewer;
	float dist = length(d);
	float diff = abs(mod(atan(d.x, d.y) - facing + 3.14159265, 6.2831853) - 3.14159265);
	float ang_soft = edge / max(dist, 0.5);
	float cone = (1.0 - smoothstep(range - range_edge, range, dist)) * (1.0 - smoothstep(half_angle - ang_soft, half_angle, diff));
	float near = 1.0 - smoothstep(near_radius - near_edge, near_radius, dist);
	float lit = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= light_count) {
			break;
		}
		float ld = length(p - lights[i].xy);
		lit = max(lit, 1.0 - smoothstep(lights[i].z - near_edge, lights[i].z, ld));
	}
	ALBEDO = vec3(0.0);
	ALPHA = mix(darkness, inner_darkness, max(max(cone, near), lit));
}
"""


func _create_vision_overlay() -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var shader := Shader.new()
	shader.code = VISION_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var v: Dictionary = Config.VISION
	mat.set_shader_parameter(&"half_angle", v.angle / 2.0)
	mat.set_shader_parameter(&"range", v.range)
	mat.set_shader_parameter(&"near_radius", v.near_radius)
	mat.set_shader_parameter(&"darkness", v.darkness)
	mat.set_shader_parameter(&"inner_darkness", v.inner_darkness)
	mat.set_shader_parameter(&"edge", v.edge)
	mat.set_shader_parameter(&"near_edge", v.near_edge)
	mat.set_shader_parameter(&"range_edge", v.range_edge)
	# 最先畫（半透明物件裡）：半透明的東西不在深度貼圖裡，這層會讀到它們後面的地面來判斷壓不壓暗，
	# 淡入淡出中的怪物、冤魂會被切成上下兩半（頭頂對到較遠的地面）。最先畫 = 半透明的一律畫在上面、不被壓暗
	mat.render_priority = Material.RENDER_PRIORITY_MIN
	var mi := MeshInstance3D.new()
	mi.name = "VisionOverlay"
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0   # 頂點在著色器裡直接放到整個畫面，不能被視錐剔除
	mi.visible = false
	return mi


# 跟著本機角色畫面上的（補間後）位置與朝向；沒有角色或已陣亡時不蓋
func _sync_vision_overlay(me: Player) -> void:
	var node: Node3D = _nodes.get(me.id) if me != null else null
	_vision_overlay.visible = node != null and not me.is_dead
	if _vision_overlay.visible:
		var mat: ShaderMaterial = _vision_overlay.material_override
		mat.set_shader_parameter(&"viewer", Vector2(node.position.x, node.position.z))
		mat.set_shader_parameter(&"facing", node.rotation.y)
		mat.set_shader_parameter(&"range", Vision.view_range(me))          # 火把傭兵被動（F8）、守夜蠟燭（G1）
		mat.set_shader_parameter(&"half_angle", Vision.view_angle(me) / 2.0)
		mat.set_shader_parameter(&"near_radius", Vision.near_radius(me))
		var lights := Vision.lights(_world) if _world != null else ([] as Array[Vector3])
		var packed := PackedVector3Array()
		for l in lights.slice(0, MAX_LIGHTS):
			packed.append(l)
		packed.resize(MAX_LIGHTS)
		mat.set_shader_parameter(&"lights", packed)
		mat.set_shader_parameter(&"light_count", mini(lights.size(), MAX_LIGHTS))


# 寶箱（D3）：木箱 + 鐵條，大寶箱較大、鑲金邊；箱蓋（Lid）以後緣為軸，打開時往後翻
func _create_chest(c: Chest) -> Node3D:
	var root := Node3D.new()
	var big := c.tier == &"big"
	var s := 1.35 if big else 1.0
	var wood := _flat_material(Color("5a3a22"))
	var band := _flat_material(Color("c9a227") if big else Color("6b6e75"))
	var body := Vector3(1.1, 0.6, 0.75) * s
	root.add_child(_box(body, Vector3(0, body.y / 2.0, 0), wood))
	root.add_child(_box(Vector3(body.x + 0.04, 0.08 * s, body.z + 0.04), Vector3(0, body.y * 0.75, 0), band))
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(0, body.y, -body.z / 2.0)
	lid.add_child(_box(Vector3(body.x, 0.28 * s, body.z), Vector3(0, 0.14 * s, body.z / 2.0), wood))
	lid.add_child(_box(Vector3(body.x + 0.04, 0.06 * s, 0.1 * s), Vector3(0, 0.2 * s, body.z / 2.0), band))
	lid.add_child(_box(Vector3(0.16, 0.18, 0.06) * s, Vector3(0, 0.0, body.z + 0.02), band))   # 鎖扣
	# 已經開過的（連線時離開視野再回來會重建模型）直接是打開的，不重播開蓋
	lid.rotation.x = CHEST_LID_OPEN if c.opened else 0.0
	root.add_child(lid)
	return root


# 地上的道具（D3）：稀有度顏色的發光寶石（Gem，畫面層上下浮動與旋轉）+ 一道淡淡的光柱，遠處也看得到
func _create_pickup(p: ItemPickup) -> Node3D:
	var root := Node3D.new()
	var color: Color = ItemDefs.RARITIES[p.rarity()].color
	var gem := MeshInstance3D.new()
	gem.name = "Gem"
	if p.is_weapon():
		# 武器（D4）：斜放的發光長條，和道具的寶石分得出來
		var blade := BoxMesh.new()
		blade.size = Vector3(0.14, 0.95, 0.14)
		gem.mesh = blade
		gem.rotation.z = 0.5
	else:
		var mesh := SphereMesh.new()
		mesh.radius = 0.28
		mesh.height = 0.7
		mesh.radial_segments = 4
		mesh.rings = 2
		gem.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.6
	gem.material_override = m
	root.add_child(gem)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.2
	cyl.height = 2.4
	cyl.radial_segments = 8
	beam.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(color, 0.22)
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 1.2
	root.add_child(beam)
	return root


# 地上的金幣（v0.45）：立起來的金色圓片（Gem，和道具一樣上下浮動與旋轉）+ 細細的金色光柱
# 插在地上的火把（F8）：木柄 + 發光的火焰（不放點光源：網頁版點光源很貴，照亮的範圍由視野遮罩畫）
func _create_torch() -> Node3D:
	var root := Node3D.new()
	var model: Dictionary = DarkFantasy.weapon(&"torch")
	var g: Node3D = model.main
	g.position.y = 0.0
	root.add_child(g)
	return root


func _create_coin() -> Node3D:
	var root := Node3D.new()
	var gem := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = Coin.RADIUS
	disc.bottom_radius = Coin.RADIUS
	disc.height = 0.06
	disc.radial_segments = 12
	gem.mesh = disc
	gem.rotation.x = PI / 2.0
	var m := StandardMaterial3D.new()
	m.albedo_color = UiKit.GOLD
	m.emission_enabled = true
	m.emission = UiKit.GOLD
	m.emission_energy_multiplier = 1.2
	m.metallic = 0.8
	gem.material_override = m
	gem.name = "Disc"
	var spin := Node3D.new()   # Gem 的旋轉繞 y 軸；圓片本身先立起來（rotation.x）再放進會轉的節點
	spin.name = "Gem"
	spin.add_child(gem)
	root.add_child(spin)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.1
	cyl.height = 1.6
	cyl.radial_segments = 8
	beam.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(UiKit.GOLD, 0.2)
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 0.8
	root.add_child(beam)
	return root


static func _flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	return m


static func _box(size_: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size_
	mi.mesh = box
	mi.material_override = mat
	mi.position = at
	return mi


# 格擋範圍：格擋中顯示（輕微呼吸閃爍），跟著角色的位置與朝向
func _create_block_fan() -> MeshInstance3D:
	var arc: float = WeaponDefs.WEAPONS[&"swordShield"].special.block_arc
	var fan := MeshInstance3D.new()
	fan.name = "BlockFan"
	fan.mesh = Effects._make_sector_mesh(0.45, BLOCK_FAN_RANGE, arc, 24)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(BLOCK_FAN_COLOR, BLOCK_FAN_ALPHA)
	fan.material_override = mat
	fan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fan.position.y = 0.06
	fan.visible = false
	return fan


func _sync_block_fan(fan: MeshInstance3D, p: Player) -> void:
	fan.visible = p.anim.get("blocking", false) and not p.is_dead
	if fan.visible:
		var pulse := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.008)
		(fan.material_override as StandardMaterial3D).albedo_color.a = BLOCK_FAN_ALPHA * pulse


# F2：模擬層記錄的攻擊判定（world.hitboxes）畫成地上的扇形 / 圓形，出現後淡出
func _sync_strikes(world: World, dt: float) -> void:
	if show_hitboxes and world.tick != _last_strike_tick:
		_last_strike_tick = world.tick
		for h in world.hitboxes:
			var node := _create_strike(h, world.terrain.ground_at(h.origin))
			add_child(node)
			_strikes.append({"node": node, "life": STRIKE_FADE})
	for i in range(_strikes.size() - 1, -1, -1):
		var s := _strikes[i]
		s.life -= dt
		if s.life <= 0.0 or not show_hitboxes:
			s.node.queue_free()
			_strikes.remove_at(i)
			continue
		var m: StandardMaterial3D = s.node.material_override
		m.albedo_color.a = STRIKE_ALPHA * s.life / STRIKE_FADE


func _create_strike(h: Dictionary, ground: float) -> MeshInstance3D:
	var shape: Dictionary = h.shape
	var radius: float = shape.range if shape.shape == &"sector" else shape.radius
	var arc: float = shape.arc if shape.shape == &"sector" else TAU
	var segs := 24
	var verts := PackedVector3Array()
	var center := Vector3(h.origin.x, 0.0, h.origin.y)
	for i in segs:
		var a0: float = h.facing - arc / 2.0 + arc * i / segs
		var a1: float = h.facing - arc / 2.0 + arc * (i + 1) / segs
		verts.append_array([center, center + Vector3(sin(a0), 0.0, cos(a0)) * radius, center + Vector3(sin(a1), 0.0, cos(a1)) * radius])
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position.y = ground + 0.06
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var color := STRIKE_PLAYER_COLOR if h.team == &"player" else STRIKE_ENEMY_COLOR
	m.albedo_color = Color(color, STRIKE_ALPHA)
	mi.material_override = m
	return mi


# 開場預熱（v0.37.0）：每一種模型（玩家含武器光、各種怪、魔法 / 稀有怪的光環與點光源、冤魂、Boss、寶箱、道具、武器、投射物）
# 各放一個在 center 附近（一定要在鏡頭裡，顯示卡才會真的畫、才會編譯著色器），疊上三種剪影，畫 WARM_FRAMES 幀後移除。
# 用一個暫時的 World 建實體，不影響真正的遊戲；要在第一次 sync 之前呼叫（_create_view 會用實體 id 登記動畫器，之後就清掉）
# 前一半的幀關掉預熱模型上的點光源、後一半打開：Compatibility（網頁版）依「有沒有被點光源照到」把同一個材質編成兩個版本，
# 只預熱有光的版本時，遊戲中第一次畫到沒被照到的怪會當場編譯（每個 35~75 ms）。視野遮罩預熱期間也強制畫
const WARM_FRAMES := 4
var _warm_lights: Array[Light3D] = []
# 預熱用過的材質整場留著（2026-10-27）：BaseMaterial3D 的著色器依「還有幾個材質在用」保留，用到 0 就連編譯好的程式一起釋放
# （Godot material.cpp ~BaseMaterial3D）。只在預熱出現過的外觀（金幣、地上的道具）刪掉預熱模型後就被釋放，
# 遊戲中第一次出現又要重新編譯，網頁版卡 60~90 ms
var _warm_materials: Array[Material] = []
var _warm_center := Vector3.ZERO


func warm_up(center: Vector3) -> void:
	var tw := World.new(&"test_arena")
	tw.reset(1, [World.HOST_PEER_ID])
	tw.spawner.finished = true
	var c := Vector2(center.x, center.z)
	var ents: Array[Entity] = [tw.players[World.HOST_PEER_ID]]
	for kind: StringName in [&"grunt", &"archer", &"zombie", &"bloater", &"boss", &"ghost", &"minion"]:
		ents.append(tw.spawner.spawn_at(tw, kind, c))
	for rarity: StringName in [MonsterRarityDefs.MAGIC, MonsterRarityDefs.RARE]:
		var e := tw.spawner.spawn_at(tw, &"grunt", c)
		Spawner.roll_rarity(tw, e, rarity)
		ents.append(e)
	for tier: StringName in [&"small", &"big"]:
		ents.append(Chest.new(tw, tier, c))
	ents.append(tw.drop_coin(c))
	# 道具與武器每種稀有度都要：白色沒有發光，材質組合不同（v0.37.1：只預熱綠色時，第一把白色武器仍卡 70.8 ms）
	var item_of := {}
	for id: StringName in ItemDefs.ITEMS:
		var rarity: StringName = ItemDefs.ITEMS[id].rarity
		if not item_of.has(rarity) and not WeaponDefs.WEAPONS.has(id) and id != &"corpse":
			item_of[rarity] = id
	for rarity: StringName in ItemDefs.RARITIES:
		if item_of.has(rarity):
			ents.append(tw.drop_item(item_of[rarity], c))
		ents.append(tw.drop_weapon(WeaponDropDefs.make(tw.new_weapon_uid(), WeaponDefs.WEAPONS.keys()[0], rarity, tw.rng), c))
	for visual: StringName in [&"arrow", &"orb"]:
		ents.append(Projectile.new(tw, {"owner": ents[0], "pos": c, "direction": Vector2.UP, "speed": 0.0, "range": 0.0,
			"radius": 0.25, "color": Color.ORANGE, "visual": visual}))
	var colors := [XRAY_SELF, XRAY_ALLY, XRAY_ENEMY]
	var count := ents.size() * 2
	for i in count:
		var e := ents[i / 2]
		var faded := i % 2 == 1   # 每種模型再一個淡入淡出中的（半透明材質是另一組著色器，見 view/fade.gd）
		var node := _create_view(e)
		_animators.erase(e.id)
		# 排成一圈（半徑 3），都在鏡頭裡
		var a := TAU * i / count
		node.position = center + Vector3(sin(a), 0.0, cos(a)) * 3.0
		if node.has_meta(&"xray"):
			apply_xray(node, colors[i % colors.size()], true)
		if faded:
			Fade.prepare(node)   # 每一階的半透明材質都先建好，遊戲中轉身時不必新建
			Fade.apply(node, 0.5)
		_warm_nodes.append(node)
		warm_keys.append(("fade:" if faded else "") + _view_key(e))
	for node in _warm_nodes:
		for light: Light3D in node.find_children("*", "Light3D", true, false):
			_warm_lights.append(light)
			light.visible = false
	_warm_left = WARM_FRAMES
	_warm_center = center
	effects.warm_up(center)
	tw.clear()


func is_warming_up() -> bool:
	return _warm_left > 0


func _tick_warm_up() -> void:
	if _warm_left <= 0:
		return
	_warm_left -= 1
	if _warm_left == WARM_FRAMES / 2:
		for light in _warm_lights:
			light.visible = true
		effects.warm_up(_warm_center)   # 粒子也要有光、沒光各畫一次
	if _warm_left == 0:
		for node in _warm_nodes:
			_keep_materials(node)
			node.queue_free()
		_warm_nodes.clear()
		_warm_lights.clear()


func _keep_materials(node: Node) -> void:
	for gi: GeometryInstance3D in node.find_children("*", "GeometryInstance3D", true, false):
		for m: Material in [gi.material_override, gi.material_overlay]:
			if m != null:
				_warm_materials.append(m)
		var mi := gi as MeshInstance3D
		if mi != null and mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				for m: Material in [mi.mesh.surface_get_material(i), mi.get_surface_override_material(i)]:
					if m != null:
						_warm_materials.append(m)


# 被鐵鏟舉著的怪（2026-10-27 網頁版實測：原本只抬高 0.8、維持站姿，看起來浮在空中）：
# 腳放在舉著它的玩家武器上的托舉點（Rig.weapon_hold_point，跟著手臂動），身體往後仰。舉著的人：房主看 grabbed_by，客戶端找附近正在舉的玩家
func _place_on_shovel(world: World, e: Enemy, node: Node3D) -> void:
	var holder: Entity = world.entities.get(e.grabbed_by)
	if holder == null:
		var best := INF
		for p in world.player_list:
			var d := p.pos.distance_to(e.pos)
			if p.anim.get("holding", false) and d < best:
				best = d
				holder = p
	var rig := _nodes.get(holder.id) as Rig if holder != null else null
	if rig == null or rig.weapon_hold_point == null:
		return
	node.global_position = rig.weapon_hold_point.global_position
	node.rotate_object_local(Vector3.RIGHT, GRABBED_TILT)


# 卡頓紀錄用的模型種類：材質或光不同的分開算（稀有怪有光環與點光源、寶箱分大小、道具分武器與稀有度、投射物分外觀）
static func _view_key(e: Entity) -> String:
	if e is Enemy and (e as Enemy).rarity != MonsterRarityDefs.NORMAL:
		return "%s:%s" % [e.kind, (e as Enemy).rarity]
	if e is Chest:
		return "chest:%s" % (e as Chest).tier
	if e is ItemPickup:
		var p := e as ItemPickup
		return "%s:%s" % ["weapon" if p.is_weapon() else "item", p.rarity()]
	if e is Projectile:
		return "projectile:%s" % (e as Projectile).visual
	if e is Player and (e as Player).class_id != ClassDefs.NONE:
		return "player:%s" % (e as Player).class_id
	return String(e.kind)


func _create_view(e: Entity) -> Node3D:
	var root: Node3D
	match e.kind:
		&"player":
			var rig := DarkFantasy.player_character((e as Player).class_id)
			_animators[e.id] = Animator.new(rig)
			root = rig
			root.add_child(_create_block_fan())
			var glow := OmniLight3D.new()   # 武器稀有度的光（D4 回饋）：不是白色的武器發出淡淡的稀有度顏色光
			glow.name = "WeaponGlow"
			glow.omni_range = WEAPON_GLOW_RANGE
			glow.light_energy = WEAPON_GLOW_ENERGY
			glow.shadow_enabled = false
			glow.visible = false
			rig.hand_r.add_child(glow)
			root.set_meta(&"glow", glow)
		&"grunt", &"archer", &"zombie", &"bloater", &"boss", &"ghost", &"minion":
			# 小怪用蒙皮版本（D5 效能：每隻 1~2 次繪製）；Boss 只有一隻，照舊用關節節點
			# 冤魂（D6）：半透明的騎士（玩家的模型，不拿武器）
			var rig: Node3D
			if (e as Enemy).is_boss():
				rig = DarkFantasy.character(e.kind)
			elif e.kind == &"ghost":
				rig = DarkFantasy.skinned_character(&"player")
				(rig as SkinnedRig).set_ghost(GHOST_TINT, GHOST_TRANSPARENCY)
			elif e.kind == &"minion":   # 骷髏僕從（G6）：染綠的骷髏戰士（不透明）
				rig = DarkFantasy.skinned_character(&"grunt")
				(rig as SkinnedRig).set_ghost(MINION_TINT, 0.0)
			else:
				rig = DarkFantasy.skinned_character(e.kind)
			_animators[e.id] = EnemyAnimator.new(rig, e as Enemy)
			root = rig
			_add_rarity_marks(rig, e as Enemy)
		&"projectile":
			var proj := e as Projectile
			root = _create_arrow(proj) if proj.visual == &"arrow" else _create_projectile(proj)
		&"chest":
			root = _create_chest(e as Chest)
		&"pickup":
			root = _create_pickup(e as ItemPickup)
		&"coin":
			root = _create_coin()
		&"torch":
			root = _create_torch()
		_:
			root = _create_placeholder(e)
	var ring := _create_hitbox_ring(e.radius)
	ring.visible = show_hitboxes
	ring.name = &"Hitbox"
	root.add_child(ring)
	root.set_meta(&"entity", e.get_instance_id())
	if e is Player or e is Enemy or e is Projectile:
		# 投射物（箭、魔彈）飛到牆後也畫剪影，顏色看發射的人：自己藍、隊友綠、怪物紅
		var source: Entity = e
		if e is Projectile and _world != null:
			source = _world.entities.get((e as Projectile).owner_id)
		var color := XRAY_ENEMY
		if source is Player:
			color = XRAY_SELF if source == local_player() else XRAY_ALLY
		var on := e is Player   # 怪物與投射物等判斷過有東西擋住才打開（_xray_needed）
		root.set_meta(&"xray", color)
		root.set_meta(&"xray_shown", on)
		apply_xray(root, color, on)
	add_child(root)
	return root


# 角色的每個網格：自己的材質寫入模板值；on 時疊上剪影材質（換武器、怪物被擋住 / 不再被擋住時再呼叫，見 sync）
static func apply_xray(node: Node, color: Color, on: bool) -> void:
	for child in node.get_children():
		if XRAY_SKIP.has(child.name):
			continue
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var m := mi.material_override as BaseMaterial3D
			if m != null and m.stencil_mode != BaseMaterial3D.STENCIL_MODE_CUSTOM:
				m.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
				m.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
				m.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
				m.stencil_reference = XRAY_STENCIL
			mi.material_overlay = xray_material(color) if on else null
		apply_xray(child, color, on)


# 怪物和相機之間有沒有牆或石台擋住：沿著往相機的方向取樣，地形頂面高過「腳底往相機的視線」就算擋住
# 腳底被擋住才開剪影（被擋住的通常從腳開始）；最遠取樣到最高的牆擋得到的距離
func _xray_needed(world: World, e: Entity) -> bool:
	var reach := MapDefs.WALL_TOP / _xray_slope
	var d := e.radius
	while d <= reach:
		if world.terrain.ground_at(e.pos + _xray_dir * d) > e.height + d * _xray_slope + 0.1:
			return true
		d += XRAY_PROBE_STEP
	return false


# 三種顏色共用一個 Shader，只用參數換顏色（v0.37.0：以前每種顏色各建一個 Shader，各自要編譯一次）
static func xray_material(color: Color) -> ShaderMaterial:
	if not _xray_materials.has(color):
		if _xray_shader == null:
			_xray_shader = Shader.new()
			_xray_shader.code = XRAY_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = _xray_shader
		mat.set_shader_parameter(&"color", color)
		_xray_materials[color] = mat
	return _xray_materials[color]


# 挖墳點（D6）：土堆 + 墓碑，挖的進度越多土堆越矮；挖完變成發光的墓穴（出口）
func _sync_grave(world: World) -> void:
	if not DigEvent.enabled(world):
		if _grave != null:
			_grave.visible = false
		return
	if _grave == null:
		_grave = _create_grave()
		add_child(_grave)
	_grave.visible = true
	var ev := world.event
	_grave.position = Vector3(ev.point.x, world.terrain.ground_at(ev.point), ev.point.y)
	var open := ev.state == DigEvent.OPEN
	var mound: Node3D = _grave.get_node(^"Mound")
	mound.visible = not open
	mound.scale.y = maxf(0.08, 1.0 - ev.progress)
	_grave.get_node(^"Hole").visible = open
	_grave.get_node(^"ExitRing").visible = open
	_grave.get_node(^"Headstone").visible = not open


func _create_grave() -> Node3D:
	var root := Node3D.new()
	root.name = "Grave"
	var mound := MeshInstance3D.new()
	mound.name = "Mound"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 0.9
	sphere.radial_segments = 10
	sphere.rings = 4
	mound.mesh = sphere
	mound.scale = Vector3(1.1, 1.0, 0.75)
	mound.material_override = _flat_material(GRAVE_SOIL)
	root.add_child(mound)
	var stone := _box(Vector3(0.9, 1.3, 0.25), Vector3(0.0, 0.65, -0.95), _flat_material(GRAVE_STONE))
	stone.name = "Headstone"
	root.add_child(stone)
	var hole := MeshInstance3D.new()
	hole.name = "Hole"
	var cyl := CylinderMesh.new()
	cyl.top_radius = EventDefs.DIG.exit_radius
	cyl.bottom_radius = EventDefs.DIG.exit_radius * 0.8
	cyl.height = 0.06
	hole.mesh = cyl
	hole.position.y = 0.03
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color("07060a")
	hole.material_override = dark
	root.add_child(hole)
	var ring := MeshInstance3D.new()
	ring.name = "ExitRing"
	var torus := TorusMesh.new()
	torus.inner_radius = EventDefs.DIG.exit_radius
	torus.outer_radius = EventDefs.DIG.exit_radius + 0.18
	ring.mesh = torus
	ring.scale.y = 0.2
	ring.position.y = 0.06
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = EXIT_COLOR
	ring.material_override = glow
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var light := OmniLight3D.new()
	light.name = "ExitLight"
	light.light_color = EXIT_COLOR
	light.omni_range = 4.0
	light.light_energy = 1.5
	light.position.y = 0.8
	light.visible = lights_on
	ring.add_child(light)
	return root


# 魔法 / 稀有怪（D5）：體型（稀有 ×1.2）、身上稀有度顏色的光、腳下一圈發光環
func _add_rarity_marks(rig: Node3D, e: Enemy) -> void:
	if e.rarity == MonsterRarityDefs.NORMAL:
		return
	var r: Dictionary = MonsterRarityDefs.RARITIES[e.rarity]
	rig.body.scale *= r.scale
	rig.height *= r.scale
	var glow := OmniLight3D.new()
	glow.light_color = r.color
	glow.omni_range = RARITY_GLOW_RANGE
	glow.light_energy = RARITY_GLOW_ENERGY
	glow.shadow_enabled = false
	glow.position.y = e.body_height * 0.6
	glow.visible = lights_on
	rig.add_child(glow)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = e.radius + 0.12
	torus.outer_radius = e.radius + 0.24
	torus.rings = 24
	torus.ring_segments = 4
	ring.mesh = torus
	ring.scale.y = 0.15
	ring.position.y = 0.04
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = r.color
	ring.material_override = mat
	ring.name = &"RarityRing"
	rig.add_child(ring)


# 發光球體（網頁版 Projectile 的預設外觀）；飛行高度由模擬層的 height 決定
func _create_projectile(e: Projectile) -> Node3D:
	var root := Node3D.new()
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = e.radius
	sphere.height = e.radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	ball.mesh = sphere
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 同顏色的魔彈共用材質（同 DarkFantasy.enemy_projectile：寫模板值後各自的材質會各編一次著色器）
	if not _orb_materials.has(e.color):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = e.color
		_orb_materials[e.color] = mat
	ball.material_override = _orb_materials[e.color]
	root.add_child(ball)
	return root


# 敵人箭矢：細長箭身沿 +Z、發光箭頭（DarkFantasy.enemy_projectile）；飛行高度由模擬層決定（HEIGHT.arrow_altitude）
func _create_arrow(e: Projectile) -> Node3D:
	var root := Node3D.new()
	root.add_child(DarkFantasy.enemy_projectile(e.color))
	return root


func _create_placeholder(e: Entity) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(e.radius * 2.0, 1.8, e.radius * 1.4)
	body.mesh = box
	body.position.y = 0.9
	body.material_override = _mat(Color("6f86b8"))
	root.add_child(body)

	var nose := MeshInstance3D.new()   # 標示面向（+Z）
	var nose_box := BoxMesh.new()
	nose_box.size = Vector3(0.2, 0.2, 0.4)
	nose.mesh = nose_box
	nose.position = Vector3(0.0, 1.4, e.radius * 0.7 + 0.2)
	nose.material_override = _mat(Color("dfe8ff"))
	root.add_child(nose)
	return root


func _create_hitbox_ring(radius: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = &"Hitbox"
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.92
	torus.outer_radius = radius
	torus.rings = 32
	ring.mesh = torus
	ring.scale.y = 0.05
	ring.position.y = 0.03
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = HITBOX_COLOR
	ring.material_override = ring_mat
	return ring


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m
