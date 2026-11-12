# 屍巫（第 4 層的怪，第 3 層的巨繭噴出來；數值 Claude 暫定）：同骷髏弓手保持距離、橫移；停下雙手合攏唸咒 aim_time 秒 →
# 放出 bolts.count 顆追蹤紫火（飛得慢、轉得慢、life 秒後消失，擋得住）；目標貼近到 blink.trigger_distance 內就閃現到 blink.distance 外
class_name Lich
extends RangedEnemy


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	super(p_world, p_type, at, mul)
	fsm.states[&"kite"] = BlinkKite.new()


func fire() -> void:
	var b: Dictionary = def.bolts
	world.emit_event("sfx:cue", {"cue": "arrowShot", "pos": pos})
	for i in int(b.count):
		var dir := MathUtil.dir_from_angle(facing + (i - (b.count - 1) / 2.0) * b.spread)
		world.spawn_projectile(Projectile.new(world, {
			"owner": self, "pos": pos + dir * def.projectile_offset, "direction": dir,
			"speed": def.projectile_speed, "range": def.projectile_speed * b.life, "radius": def.projectile_radius,
			"damage": def.projectile_damage * damage_mul, "knockback": def.projectile_knockback,
			"color": def.projectile_color, "visual": &"orb", "altitude": height + Config.HEIGHT.arrow_altitude,
			"blockable": def.projectile_blockable, "homing": b.homing, "seek_range": b.seek_range, "damage_type": &"shadow",
		}))


# 閃到離 target 剛好 blink.distance 的地方：先試正後方，被牆擋住就往兩邊偏；都不行就留在原地（冷卻照算）
func blink_away(target: Entity) -> void:
	var k: Dictionary = def.blink
	world.cooldowns.start(cd("blink"), cd_time(k.cooldown))
	var from := pos
	var base := MathUtil.angle_to(target.pos, pos)
	var nav := world.nav_for(radius)
	for off: float in [0.0, 0.6, -0.6, 1.2, -1.2, 1.9, -1.9, PI]:
		var at: Vector2 = target.pos + MathUtil.dir_from_angle(base + off) * float(k.distance)
		if nav.is_walkable(at) and nav.same_region(at, from) and world.terrain.clear_at(at, radius):
			pos = at
			break
	velocity = Vector2.ZERO
	facing = MathUtil.angle_to(pos, target.pos)
	world.emit_event("fx:boss_teleport", {"pos": from, "height": ground_height, "to": pos})


# 保持距離（同弓手），多一條：目標貼近、閃現冷卻好就閃走
class BlinkKite extends RangedEnemy.Kite:
	func update(e: RangedEnemy, dt: float, fsm: StateMachine) -> void:
		var target: Entity = e.nearest_target()
		if target != null and e.world.cooldowns.is_ready(e.cd("blink")) and e.pos.distance_to(target.pos) <= e.def.blink.trigger_distance:
			(e as Lich).blink_away(target)
			return
		super(e, dt, fsm)
