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

var show_hitboxes := false
var effects := Effects.new()
var _nodes: Dictionary = {}       # entity id -> Node3D
var _animators: Dictionary = {}   # entity id -> Animator（有骨架的實體）
var _frozen: Dictionary = {}           # entity id -> 剩餘定格秒數（命中定格）
var _strikes: Array[Dictionary] = []   # F2 顯示中的攻擊判定 { node, life }
var _last_strike_tick := -1
# 角色視野（D2，sim/vision.gd）：只畫本機玩家看得到的怪物、攻擊、隊友；視野外的地面蓋一層暗色
var local_peer := World.HOST_PEER_ID
var hidden_ids: Dictionary = {}        # 這一幀看不到的實體 id（Effects 的持續性粒子也跳過）
var _world: World
var _vision_overlay := _create_vision_overlay()


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
	effects.clear()


# 事件由 main.gd 轉過來：特效交給 Effects；重新開始時清掉場上的特效
func on_event(name: String, p: Dictionary) -> void:
	if name == "game:restart":
		effects.clear()
	# 視野外的特效（怪物的攻擊、命中粒子、預警圈…）不畫
	if name.begins_with("fx:") and p.has("pos"):
		var me := local_player()
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
	_world = world
	var me := local_player()
	hidden_ids.clear()
	for id: int in world.entities:
		if not Vision.entity_visible(world, me, world.entities[id]):
			hidden_ids[id] = true
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
		node.visible = not hidden_ids.has(id)
		if _frozen.has(id):
			_frozen[id] -= dt
			if _frozen[id] > 0.0:
				continue
			_frozen.erase(id)
		var p := e.prev_pos.lerp(e.pos, alpha)
		node.position = Vector3(p.x, lerpf(e.prev_height, e.height, alpha), p.y)
		node.rotation.y = lerp_angle(e.prev_facing, e.facing, alpha)
		node.get_node(^"Hitbox").visible = show_hitboxes
		if e is Player:
			_sync_block_fan(node.get_node(^"BlockFan"), e as Player)
			var glow: OmniLight3D = node.get_meta(&"glow")
			var inst := (e as Player).active_weapon()
			glow.visible = not inst.is_empty() and inst.rarity != &"white"
			if glow.visible:
				glow.light_color = ItemDefs.RARITIES[inst.rarity].color
		elif e is Chest:
			var lid: Node3D = node.get_node(^"Lid")
			lid.rotation.x = lerpf(lid.rotation.x, -1.9 if (e as Chest).opened else 0.0, minf(1.0, dt * 8.0))
		elif e is ItemPickup:
			var gem: Node3D = node.get_node(^"Gem")
			var t := Time.get_ticks_msec() / 1000.0 + id * 0.7
			gem.position.y = 0.55 + 0.12 * sin(t * 2.5)
			gem.rotation.y = t * 1.6
		if _animators.has(id):
			_animators[id].update(e, dt)
	_sync_strikes(world, dt)
	_sync_vision_overlay(me)
	effects.sync(world, dt)


func local_player() -> Player:
	return _world.players.get(local_peer) if _world != null else null


# 視野外變暗：蓋滿畫面的四邊形，從深度貼圖算出每個像素的世界位置，在視野扇形與身邊一圈之外蓋上暗色
# 高台、牆的頂面也照它們自己的位置判斷；牆擋住的區域不畫暗（只隱藏牆後的怪物）
const VISION_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec2 viewer;
uniform float facing;
uniform float half_angle;
uniform float range;
uniform float near_radius;
uniform float darkness;
uniform float inner_darkness;
uniform float edge;

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
	float cone = (1.0 - smoothstep(range - edge, range, dist)) * (1.0 - smoothstep(half_angle - ang_soft, half_angle, diff));
	float near = 1.0 - smoothstep(near_radius - edge, near_radius, dist);
	ALBEDO = vec3(0.0);
	ALPHA = mix(darkness, inner_darkness, max(cone, near));
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


func _create_view(e: Entity) -> Node3D:
	var root: Node3D
	match e.kind:
		&"player":
			var rig := DarkFantasy.character(e.kind)
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
		&"grunt", &"archer", &"boss":
			var rig := DarkFantasy.character(e.kind)
			_animators[e.id] = EnemyAnimator.new(rig, e as Enemy)
			root = rig
		&"projectile":
			var proj := e as Projectile
			root = _create_arrow(proj) if proj.visual == &"arrow" else _create_projectile(proj)
		&"chest":
			root = _create_chest(e as Chest)
		&"pickup":
			root = _create_pickup(e as ItemPickup)
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
