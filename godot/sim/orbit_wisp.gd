# 繞著玩家轉的鬼火（鬼火羈絆，BondEffects.sync_wisps 建立與移除）：碰到怪造成武器基礎傷害 pct 倍（道具效果的傷害，不爆擊）；
# 同一隻怪每 hit_interval 秒最多打一次。第 2 階起每 dash_interval 秒衝向 dash_range 內最近的怪，打到或目標不見了就飛回來
# 是 Projectile 的子類別：連線照一般投射物進快照（客戶端只補間位置），畫面照 visual 畫成發光球
class_name OrbitWisp
extends Projectile

const ORBIT := 0
const DASH := 1
const BACK := 2

var slot := 0
var total := 1
var angle := 0.0
var state := ORBIT
var dash_timer := 0.0
var forced_dash := false          # 招魂幡：不管階數，下一步就衝
var _target_id := 0
var _hit_cd := {}                 # 怪的 id → 還要幾秒才能再打


func _init(p_world: World, p: Player, type: StringName, p_slot: int, p_total: int) -> void:
	var c: Dictionary = BondDefs.BONDS.wisp.params
	super(p_world, {
		"owner": p, "pos": p.pos, "direction": Vector2(0, 1), "speed": 0.0, "range": INF, "radius": c.radius,
		"damage_type": type, "color": StatDefs.DAMAGE_TYPES[type].color, "visual": &"orb", "proc": true,
		"no_stagger": true, "blockable": false, "altitude": p.height + 1.1,
	})
	slot = p_slot
	total = p_total
	dash_timer = c.dash_interval


func update(dt: float) -> void:
	if is_removed:
		return
	var p := world.entities.get(owner_id) as Player
	if p == null or p.is_dead:
		remove()
		return
	var c: Dictionary = BondDefs.BONDS.wisp.params
	angle = wrapf(angle + c.orbit_speed * dt, 0.0, TAU)
	var home: Vector2 = p.pos + MathUtil.dir_from_angle(angle + TAU * slot / total) * c.orbit_radius
	for id: int in _hit_cd.keys():
		_hit_cd[id] -= dt
		if _hit_cd[id] <= 0.0:
			_hit_cd.erase(id)
	match state:
		ORBIT:
			pos = home
			dash_timer -= dt
			if (forced_dash or BondEffects.tier(p, &"wisp") >= 2) and dash_timer <= 0.0:
				dash_timer = c.dash_interval
				forced_dash = false
				var t := _nearest(c.dash_range)
				if t != null:
					_target_id = t.id
					state = DASH
		DASH:
			var t := world.entities.get(_target_id) as Enemy
			if t == null or t.is_dead:
				state = BACK
			else:
				_move_to(t.pos, c.dash_speed * dt)
		BACK:
			if _move_to(home, c.dash_speed * dt):
				state = ORBIT
	height = p.height + 1.1
	_touch(p, c)


# 往 to 移動最多 step；到了回傳 true
func _move_to(to: Vector2, step: float) -> bool:
	var d := to - pos
	if d.length() <= step:
		pos = to
		return true
	direction = d.normalized()
	facing = atan2(direction.x, direction.y)
	pos += direction * step
	return false


func _nearest(r: float) -> Enemy:
	var best: Enemy = null
	var best_d := r * r
	for e in world.enemies:
		if e.is_dead or e.team == team:
			continue
		var d := e.pos.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = e as Enemy
	return best


func _touch(p: Player, c: Dictionary) -> void:
	for e in world.enemies:
		if e.is_dead or e.team == team or _hit_cd.has(e.id):
			continue
		var r := radius + e.radius
		if e.pos.distance_squared_to(pos) > r * r:
			continue
		_hit_cd[e.id] = c.hit_interval
		var dmg := BondEffects.elem_damage(p, c.pct) * p.stats.value(&"wisp_damage")
		if damage_type == &"phys":
			dmg = p.weapon.base_damage * c.pct * p.damage_mul * p.stats.value(&"phys_damage") * p.stats.value(&"wisp_damage")
		if p.wisp_frenzy_timer > 0.0:
			dmg *= ItemDefs.PROCS.wisp_frenzy.damage_mul
		var hit := ItemEffects.proc_hit(dmg, e, color, 0.0, damage_type)
		if Combat.apply_damage(world, p, e, hit):
			ItemEffects.on_wisp_hit(world, p, e, dmg)
			if e.is_dead:
				ItemEffects.on_wisp_kill(p)
		if state == DASH and e.id == _target_id:
			state = BACK
