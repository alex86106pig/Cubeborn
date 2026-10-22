# 畫面層：依實體 id 建立 / 移除模型並補間位置、驅動角色動畫；燈光與背景；特效（view/effects.gd）；命中定格；F2 判定顯示（碰撞圈與攻擊判定形狀）
# 角色用 DarkFantasy 造型的 Rig + 動畫，法杖魔彈用發光球體、敵人箭矢用 DarkFantasy 造型，其他暫用方塊
class_name WorldView
extends Node3D

const HITBOX_COLOR := Color(1.0, 0.93, 0.0, 0.8)
const STRIKE_PLAYER_COLOR := Color(1.0, 0.93, 0.0)   # F2：玩家攻擊判定
const STRIKE_ENEMY_COLOR := Color(1.0, 0.25, 0.2)    # F2：怪物攻擊判定
const STRIKE_FADE := 0.3                             # 判定形狀顯示後淡出的秒數
const STRIKE_ALPHA := 0.45

var show_hitboxes := false
var effects := Effects.new()
var _nodes: Dictionary = {}       # entity id -> Node3D
var _animators: Dictionary = {}   # entity id -> Animator（有骨架的實體）
var _frozen: Dictionary = {}           # entity id -> 剩餘定格秒數（命中定格）
var _strikes: Array[Dictionary] = []   # F2 顯示中的攻擊判定 { node, life }
var _last_strike_tick := -1


func _init() -> void:
	add_child(effects)   # 建立時就掛上，WorldView 沒進場景樹就被釋放時也會一起釋放


func _ready() -> void:
	_setup_environment()


# 換了一個 World（加入 / 離開連線）：id 會重複使用，舊模型全部拿掉
func clear_views() -> void:
	for node: Node3D in _nodes.values():
		node.queue_free()
	_nodes.clear()
	_animators.clear()
	_frozen.clear()
	effects.clear()


# 事件由 main.gd 轉過來：特效交給 Effects；重新開始時清掉場上的特效
func on_event(name: String, p: Dictionary) -> void:
	if name == "game:restart":
		effects.clear()
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
	sun.light_color = Config.ENVIRONMENT.sun_color
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	sun.look_at_from_position(Vector3(-10.0, 22.0, 8.0), Vector3.ZERO)


# alpha：上一步到這一步之間的補間比例（0~1）；dt：渲染幀秒數（動畫用）
func sync(world: World, alpha: float, dt: float) -> void:
	for id: int in _nodes.keys():
		# 實體不在了，或同一個 id 已經是另一個實體（重新開始後 id 從 1 重來，客戶端可能在同一幀就換掉）
		var e: Entity = world.entities.get(id)
		if e == null or _nodes[id].get_meta(&"entity") != e.get_instance_id():
			_nodes[id].queue_free()
			_nodes.erase(id)
			_animators.erase(id)
			_frozen.erase(id)
	for id: int in world.entities:
		var e: Entity = world.entities[id]
		if not _nodes.has(id):
			_nodes[id] = _create_view(e)
		var node: Node3D = _nodes[id]
		if _frozen.has(id):
			_frozen[id] -= dt
			if _frozen[id] > 0.0:
				continue
			_frozen.erase(id)
		var p := e.prev_pos.lerp(e.pos, alpha)
		node.position = Vector3(p.x, lerpf(e.prev_height, e.height, alpha), p.y)
		node.rotation.y = lerp_angle(e.prev_facing, e.facing, alpha)
		node.get_node(^"Hitbox").visible = show_hitboxes
		if _animators.has(id):
			_animators[id].update(e, dt)
	_sync_strikes(world, dt)
	effects.sync(world, dt)


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


func _create_view(e: Entity) -> Node3D:
	var root: Node3D
	match e.kind:
		&"player":
			var rig := DarkFantasy.character(e.kind)
			_animators[e.id] = Animator.new(rig)
			root = rig
		&"grunt", &"archer", &"boss":
			var rig := DarkFantasy.character(e.kind)
			_animators[e.id] = EnemyAnimator.new(rig, e as Enemy)
			root = rig
		&"projectile":
			var proj := e as Projectile
			root = _create_arrow(proj) if proj.visual == &"arrow" else _create_projectile(proj)
		_:
			root = _create_placeholder(e)
	root.add_child(_create_hitbox_ring(e.radius))
	root.set_meta(&"entity", e.get_instance_id())
	add_child(root)
	return root


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
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = e.color
	ball.material_override = mat
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
