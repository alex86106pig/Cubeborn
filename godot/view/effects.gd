# 畫面層特效（照搬網頁版 render/Effects.js）：方塊粒子、揮砍弧光、衝擊環、預警圈
# 一次性的特效由模擬層的事件觸發（fx:* 與 entity:damaged / entity:died / boss:enraged，見 PROJECT_GUIDELINES 第 9 節）
# 持續性的粒子（投射物拖尾、蓄力、爬出塵土、衝鋒揚塵、暈眩星星、召喚、疾跑殘影）依模擬層的狀態每幀產生，不佔網路
# 網頁版每個邏輯步以機率 p 產生一顆 → 這裡換算成每秒 p × 60 顆，和幀率無關
# 粒子全部畫在一個 MultiMesh（一次繪製）；弧光與環各自一個網格，數量都有上限
class_name Effects
extends Node3D

const MAX_PARTICLES := 600
const MAX_TRANSIENTS := 64
const STEPS_PER_SECOND := 60.0   # 網頁版每步一次的特效換算成每秒次數
const RING_INNER := 0.85
const RING_SEGMENTS := 48
const SLASH_SEGMENTS := 24

# 會處理的事件 → 處理函式；check.gd 會確認模擬層發出的每個 fx:* 都在這裡
const HANDLERS := {
	"entity:damaged": &"_on_damaged",
	"entity:died": &"_on_died",
	"boss:enraged": &"_on_enraged",
	"fx:slash": &"_fx_slash",
	"fx:muzzle": &"_fx_muzzle",
	"fx:telegraph": &"_fx_telegraph",
	"fx:fizzle": &"_fx_fizzle",
	"fx:explosion": &"_fx_explosion",
	"fx:parry": &"_fx_parry",
	"fx:heal": &"_fx_heal",
	"fx:sprint": &"_fx_sprint",
	"fx:boss_slam": &"_fx_boss_slam",
	"fx:boss_wall": &"_fx_boss_wall",
}

const DUST_COLOR := Color("6b4f2e")         # 骷髏爬出的泥土
const CHARGE_DUST_COLOR := Color("8a7a5a")  # Boss 衝鋒揚塵、砸地碎石
const WALL_DEBRIS_COLOR := Color("9a9a9a")
const SLAM_RING_COLOR := Color("9a8a6a")
const STUN_STAR_COLOR := Color("ffe14a")

var world: World                  # 由 sync 設定；事件處理時用來查實體位置
var paused := false               # 遊戲暫停時粒子停住、不產生新的持續性粒子
var spawned_total := 0            # 累計產生過的粒子數（檢查用）
var hidden_ids: Dictionary = {}   # 本機玩家看不到的實體 id（WorldView 每幀更新）：不產生它們的持續性粒子（D2）
var _rng := RandomNumberGenerator.new()
var _particles: Array[Dictionary] = []
var _transients: Array[Dictionary] = []
var _multimesh := MultiMesh.new()
var _ring_mesh: ArrayMesh
var _slash_meshes: Dictionary = {}   # "range|arc" -> ArrayMesh
var _carry: Dictionary = {}          # 持續性粒子的小數累積：產生源 key -> 不滿一顆的部分
var _next_carry: Dictionary = {}     # 這一幀用到的 key（沒用到的產生源下一幀就丟掉）


# 網格在建立時就準備好（不在場景樹裡也能用，檢查會直接建立 Effects / WorldView）
func _init() -> void:
	_rng.randomize()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.instance_count = MAX_PARTICLES
	_multimesh.visible_instance_count = 0
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	box.material = mat
	_multimesh.mesh = box
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _multimesh
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -10, -200), Vector3(400, 60, 400))   # 粒子散在整個場地，不讓整組被視錐剔除
	add_child(mmi)
	_ring_mesh = _make_ring_mesh()


func _ready() -> void:
	_warm_up()


# 開場先各畫一次（透明度 0），讓粒子與半透明材質的著色器在載入時就編譯，避免第一次出現時卡頓
func _warm_up() -> void:
	burst(Vector3(0, 0.05, 0), {"count": 1, "life": 0.05, "size": 0.001})
	ring(Vector3.ZERO, 1.0, {"life": 0.05, "opacity": 0.0})
	slash(Vector3.ZERO, 0.0, 1.0, 1.0, {"life": 0.05, "opacity": 0.0})


func clear() -> void:
	_particles.clear()
	_multimesh.visible_instance_count = 0
	for t in _transients:
		t.node.queue_free()
	_transients.clear()


func particle_count() -> int:
	return _particles.size()


func transient_count() -> int:
	return _transients.size()


# ───────── 基本形狀（同網頁版 Effects.js 的參數與預設值） ─────────

# 方塊粒子爆發；pos 的 y 就是起始高度
func burst(pos: Vector3, o: Dictionary = {}) -> void:
	var color: Color = o.get("color", Color.WHITE)
	var count: int = o.get("count", 8)
	var speed: float = o.get("speed", 4.0)
	var size: float = o.get("size", 0.14)
	var life: float = o.get("life", 0.45)
	var gravity: float = o.get("gravity", 14.0)
	var up: float = o.get("up", 3.0)
	for i in count:
		if _particles.size() >= MAX_PARTICLES:
			return
		var angle := _rng.randf() * TAU
		var s := speed * _rng.randf_range(0.4, 1.0)
		var max_life := life * _rng.randf_range(0.6, 1.2)
		spawned_total += 1
		_particles.append({
			"pos": pos, "vel": Vector3(sin(angle) * s, up * _rng.randf_range(0.5, 1.2), cos(angle) * s),
			"rot": Vector2(_rng.randf() * 3.0, _rng.randf() * 3.0), "gravity": gravity, "color": color,
			"size": size * _rng.randf_range(0.7, 1.3), "life": max_life, "max_life": max_life,
		})


# 單顆漂浮粒子（拖尾、蓄力）
func mote(pos: Vector3, o: Dictionary = {}) -> void:
	var vy: float = o.get("vy", 0.5)
	burst(pos, {"color": o.get("color", Color.WHITE), "count": 1, "speed": 0.3, "size": o.get("size", 0.1),
		"life": o.get("life", 0.3), "gravity": -vy * 2.0, "up": vy})


# 近戰弧光：扇形面片朝 facing 展開，swing_dir = -1 時左右翻轉（反手）
func slash(pos: Vector3, facing: float, range_: float, arc: float, o: Dictionary = {}) -> void:
	var key := "%.2f|%.2f" % [range_, arc]
	if not _slash_meshes.has(key):
		_slash_meshes[key] = _make_sector_mesh(range_ * 0.35, range_, arc)
	var opacity: float = o.get("opacity", 0.75)
	var node := _transient_mesh(_slash_meshes[key], o.get("color", Color.WHITE), opacity)
	node.position = pos
	node.rotation.y = facing
	var swing: float = o.get("swing_dir", 1)
	_add_transient(node, o.get("life", 0.16), func(k: float) -> void:
		_set_alpha(node, opacity * (1.0 - k))
		node.scale = Vector3(swing, 1.0, 0.85 + 0.15 * k))


# 衝擊環：由小擴張到 radius 並淡出
func ring(pos: Vector3, radius: float, o: Dictionary = {}) -> void:
	var opacity: float = o.get("opacity", 0.8)
	var node := _transient_mesh(_ring_mesh, o.get("color", Color.WHITE), opacity)
	node.position = pos + Vector3(0, o.get("y", 0.05), 0)
	_add_transient(node, o.get("life", 0.35), func(k: float) -> void:
		var s := radius * (0.25 + 0.75 * sqrt(k))
		node.scale = Vector3(s, 1.0, s)
		_set_alpha(node, opacity * (1.0 - k)))


# 預警圈：固定大小、閃爍，用於範圍技落點
func telegraph(pos: Vector3, radius: float, o: Dictionary = {}) -> void:
	var node := _transient_mesh(_ring_mesh, o.get("color", Color.WHITE), 0.5)
	node.position = pos + Vector3(0, 0.05, 0)
	node.scale = Vector3(radius, 1.0, radius)
	_add_transient(node, o.get("life", 0.4), func(k: float) -> void:
		_set_alpha(node, 0.35 + 0.35 * pow(sin(k * PI * 6.0), 2.0)))


# ───────── 事件 ─────────

func on_event(name: String, p: Dictionary) -> void:
	var handler: StringName = HANDLERS.get(name, &"")
	if handler != &"":
		call(handler, p)


static func _at(p: Dictionary, y_offset: float = 0.0) -> Vector3:
	var pos: Vector2 = p.pos
	return Vector3(pos.x, p.get("height", 0.0) + y_offset, pos.y)


func _entity(id: int) -> Entity:
	return world.entities.get(id) if world != null else null


static func _entity_at(e: Entity, y_offset: float) -> Vector3:
	return Vector3(e.pos.x, e.height + y_offset, e.pos.y)


func _on_damaged(p: Dictionary) -> void:
	var target := _entity(p.target_id)
	if target == null:
		return
	var heavy: bool = p.get("is_heavy", false) or p.get("is_crit", false)
	burst(_entity_at(target, 1.1), {"color": p.get("color", Color.WHITE), "count": 12 if heavy else 6, "speed": 6.0 if heavy else 4.0})


func _on_died(p: Dictionary) -> void:
	var e := _entity(p.entity_id)
	if e == null or e is Projectile or e is Player:
		return
	var boss := e is Boss
	burst(_entity_at(e, e.body_height * 0.5), {
		"color": DarkFantasy.BOSS_BLOOD if boss else DarkFantasy.BLOOD,
		"count": 40 if boss else 14, "speed": 8.0 if boss else 4.0, "up": 4.0, "size": 0.3 if boss else 0.18,
	})


func _on_enraged(p: Dictionary) -> void:
	var e := _entity(p.boss_id)
	if e != null:
		ring(_entity_at(e, 0.0), 4.0, {"color": DarkFantasy.BOSS_BLOOD, "life": 0.5})


func _fx_slash(p: Dictionary) -> void:
	slash(_at(p, 1.0), p.facing, p.range, p.arc, {"color": p.color, "swing_dir": p.swing_dir})


func _fx_muzzle(p: Dictionary) -> void:
	burst(_at(p), {"color": p.color, "count": 5, "speed": 2.5, "up": 1.5, "size": 0.1, "life": 0.25})


func _fx_telegraph(p: Dictionary) -> void:
	telegraph(_at(p), p.radius, {"color": p.color, "life": p.life})


func _fx_fizzle(p: Dictionary) -> void:
	burst(_at(p), {"color": p.color, "count": 4, "speed": 2.0, "size": 0.1})


func _fx_explosion(p: Dictionary) -> void:
	ring(_at(p), p.radius, {"color": p.color, "life": 0.4})
	ring(_at(p), p.radius * 0.6, {"color": Color.WHITE, "life": 0.25})
	burst(_at(p, 0.6), {"color": p.color, "count": 26, "speed": 9.0, "up": 6.0, "size": 0.2, "life": 0.6})


# 盾反（v0.23.0）：閃一下實際打得到的扇形範圍（距離 radius、角度 arc），外緣噴金色碎光
func _fx_parry(p: Dictionary) -> void:
	var pos := _at(p, 0.08)
	var key := "parry|%.2f|%.2f" % [p.radius, p.arc]
	if not _slash_meshes.has(key):
		_slash_meshes[key] = _make_sector_mesh(0.3, p.radius, p.arc, 32)
	var node := _transient_mesh(_slash_meshes[key], p.color, 0.6)
	node.position = pos
	node.rotation.y = p.facing
	_add_transient(node, 0.35, func(k: float) -> void:
		_set_alpha(node, 0.6 * (1.0 - k) * (1.0 - k))
		var s := 0.8 + 0.2 * sqrt(k)
		node.scale = Vector3(s, 1.0, s))
	slash(pos + Vector3(0, 0.02, 0), p.facing, p.radius, p.arc, {"color": Color.WHITE, "opacity": 0.5, "life": 0.18})
	for i in 7:
		var a: float = p.facing - p.arc / 2.0 + p.arc * i / 6.0
		burst(pos + Vector3(sin(a), 0.4, cos(a)) * Vector3(p.radius, 1.0, p.radius), {"color": p.color, "count": 3, "speed": 2.5, "up": 2.0, "size": 0.12, "life": 0.3})


func _fx_heal(p: Dictionary) -> void:
	ring(_at(p), 1.6, {"color": p.color, "life": 0.4})
	burst(_at(p, 0.4), {"color": p.color, "count": 14, "speed": 1.5, "up": 4.0, "gravity": -2.0, "life": 0.7})


func _fx_sprint(p: Dictionary) -> void:
	ring(_at(p), 1.3, {"color": p.color, "life": 0.3})


func _fx_boss_slam(p: Dictionary) -> void:
	ring(_at(p), p.radius, {"color": Color.WHITE, "life": 0.35})
	ring(_at(p), p.radius * 1.3, {"color": SLAM_RING_COLOR, "life": 0.5, "opacity": 0.5})
	burst(_at(p, 0.2), {"color": CHARGE_DUST_COLOR, "count": 30, "speed": 7.0, "up": 6.0, "size": 0.25})


func _fx_boss_wall(p: Dictionary) -> void:
	ring(_at(p), 2.5, {"color": Color.WHITE, "life": 0.35})
	burst(_at(p, 1.0), {"color": WALL_DEBRIS_COLOR, "count": 20, "speed": 6.0, "up": 5.0, "size": 0.22})


# ───────── 每幀：持續性粒子 + 更新 ─────────

func sync(p_world: World, dt: float) -> void:
	world = p_world
	if paused:
		return
	if dt > 0.0:
		_emit_continuous(dt)
	_update_particles(dt)
	_update_transients(dt)


# 網頁版每步機率 chance 產生一顆 → 這一幀要產生幾顆：每秒 chance × 60 顆，不滿一顆的小數留到下一幀（key 區分每個產生源）
func _count(key: String, chance: float, dt: float) -> int:
	var total: float = _carry.get(key, 0.0) + chance * STEPS_PER_SECOND * dt
	var n := int(total)
	_next_carry[key] = total - n
	return n


func _jitter(e: Entity, spread: float, y: float) -> Vector3:
	return Vector3(e.pos.x + _rng.randf_range(-spread, spread), y, e.pos.y + _rng.randf_range(-spread, spread))


func _emit_continuous(dt: float) -> void:
	_next_carry = {}
	for e: Entity in world.entities.values():
		if e.is_removed or hidden_ids.has(e.id):
			continue
		if e is Projectile:
			var pr := e as Projectile
			for i in _count("%d" % e.id, 1.0, dt):
				mote(_entity_at(pr, 0.0), {"color": pr.color, "size": pr.radius * 0.6, "life": 0.25})
		elif e is Player:
			_emit_player(e, dt)
		elif e is Enemy:
			_emit_enemy(e, dt)
	_carry = _next_carry


func _emit_player(p: Player, dt: float) -> void:
	var a := p.anim
	# 奧術爆裂蓄力：魔力粒子往杖頭聚集
	if a.get("behavior") == &"arcaneBurst" and a.get("phase") == &"windup":
		var c: Dictionary = p.weapon.special
		var head := p.pos + MathUtil.dir_from_angle(p.facing) * 0.3
		for i in _count("%d:charge" % p.id, 1.0, dt):
			mote(Vector3(head.x + _rng.randf_range(-0.8, 0.8), p.height + _rng.randf_range(1.6, 2.8), head.y + _rng.randf_range(-0.8, 0.8)),
				{"color": c.color, "size": 0.12, "life": 0.3, "vy": 0.8})
	# 疾跑殘影：移動中每 0.04 秒一顆
	var trail: Variant = a.get("trail_color")
	if trail != null and p.velocity.length_squared() >= 1.0:
		for i in _count("%d:trail" % p.id, 1.0 / (0.04 * STEPS_PER_SECOND), dt):
			burst(_entity_at(p, 0.3), {"color": trail, "count": 1, "speed": 0.5, "up": 0.5, "gravity": 0.0, "size": 0.18, "life": 0.35})


func _emit_enemy(e: Enemy, dt: float) -> void:
	var a := e.anim
	var key := "%d" % e.id
	match a.get("state"):
		&"spawn":
			for i in _count(key, 0.4, dt):
				burst(_entity_at(e, 0.1), {"color": DUST_COLOR, "count": 1, "speed": 2.0, "up": 3.0, "size": 0.15})
		&"aim":
			var tip := e.pos + MathUtil.dir_from_angle(e.facing) * 0.7
			for i in _count(key, 0.5, dt):
				mote(Vector3(tip.x, e.height + e.body_height * 0.65, tip.y),
					{"color": e.def.projectile_color, "size": 0.08, "life": 0.25, "vy": 0.6})
		&"charge":
			if a.get("phase") == &"dash":
				for i in _count(key, 0.6, dt):
					burst(_entity_at(e, 0.1), {"color": CHARGE_DUST_COLOR, "count": 1, "speed": 2.0, "up": 2.0, "size": 0.2})
			elif a.get("phase") == &"stunned":
				for i in _count(key, 0.2, dt):
					mote(_jitter(e, 0.5, e.height + e.body_height + 0.2), {"color": STUN_STAR_COLOR, "size": 0.15, "life": 0.4, "vy": 0.4})
		&"summon":
			for i in _count(key, 0.7, dt):
				mote(_jitter(e, 1.5, e.height + _rng.randf_range(0.2, 1.0)), {"color": DarkFantasy.BOSS_BLOOD, "size": 0.15, "life": 0.5, "vy": 2.0})


func _update_particles(dt: float) -> void:
	for i in range(_particles.size() - 1, -1, -1):
		var p := _particles[i]
		p.life -= dt
		if p.life <= 0.0:
			_particles.remove_at(i)
			continue
		p.vel.y -= p.gravity * dt
		var pos: Vector3 = p.pos + p.vel * dt
		pos.y = maxf(0.05, pos.y)
		p.pos = pos
		p.rot.x += dt * 6.0
	_multimesh.visible_instance_count = _particles.size()
	for i in _particles.size():
		var p := _particles[i]
		var s: float = p.size * (p.life / p.max_life)
		var basis := Basis.from_euler(Vector3(p.rot.x, p.rot.y, 0.0)).scaled(Vector3.ONE * s)
		_multimesh.set_instance_transform(i, Transform3D(basis, p.pos))
		_multimesh.set_instance_color(i, p.color)


func _update_transients(dt: float) -> void:
	for i in range(_transients.size() - 1, -1, -1):
		var t := _transients[i]
		t.life -= dt
		if t.life <= 0.0:
			t.node.queue_free()
			_transients.remove_at(i)
			continue
		t.update.call(1.0 - t.life / t.max_life)


# ───────── 網格與材質 ─────────

func _add_transient(node: MeshInstance3D, life: float, update: Callable) -> void:
	if _transients.size() >= MAX_TRANSIENTS:   # 滿了就先結束最舊的
		_transients[0].node.queue_free()
		_transients.remove_at(0)
	add_child(node)
	update.call(0.0)
	_transients.append({"node": node, "life": life, "max_life": life, "update": update})


func _transient_mesh(mesh: Mesh, color: Color, opacity: float) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color, opacity)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func _set_alpha(node: MeshInstance3D, alpha: float) -> void:
	var mat: StandardMaterial3D = node.material_override
	mat.albedo_color.a = alpha


# 平放的圓環（內徑 0.85、外徑 1），縮放 = 半徑
static func _make_ring_mesh() -> ArrayMesh:
	return _make_sector_mesh(RING_INNER, 1.0, TAU, RING_SEGMENTS)


# 平放的扇環：中心線朝 +Z（facing = 0），角度 arc、內徑 inner、外徑 outer
static func _make_sector_mesh(inner: float, outer: float, arc: float, segments: int = SLASH_SEGMENTS) -> ArrayMesh:
	var verts := PackedVector3Array()
	for i in segments:
		var a0 := -arc / 2.0 + arc * i / segments
		var a1 := -arc / 2.0 + arc * (i + 1) / segments
		var d0 := Vector3(sin(a0), 0.0, cos(a0))
		var d1 := Vector3(sin(a1), 0.0, cos(a1))
		verts.append_array([d0 * inner, d0 * outer, d1 * outer, d0 * inner, d1 * outer, d1 * inner])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
