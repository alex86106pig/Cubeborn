# 屍犬（第 1 層）：不正面衝。在目標 orbit 半徑外繞圈、往目標背後（視野外）移動，繞到背後才靠近飛撲（pounce）
# 被目標看著（在目標的視野扇形內）時猶豫：拉開到 orbit 半徑繼續繞；繞了 patience 秒還繞不到背後，就從正面撲
# 飛撲：伏低 windup 秒（鎖定方向）→ 直線撲 distance（跳起來）→ recovery；判定只打一次、擋得住
class_name Hound
extends Enemy


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	var states := Enemy.base_states()
	states[&"chase"] = Prowl.new()
	states[&"pounce"] = Pounce.new()
	super(p_world, p_type, at, mul, states)


func _anim_extra(a: Dictionary) -> void:
	if fsm.is_in(&"pounce"):
		a["phase"] = fsm.data.phase
		a["phase_time"] = fsm.data.phase_time


func _can_jump() -> bool:
	return fsm.is_in(&"chase")


# 自己相對於目標的方位（目標朝向 0、正後方 PI）
static func bearing_from(target: Entity, at: Vector2) -> float:
	return absf(angle_difference(target.facing, MathUtil.angle_to(target.pos, at)))


# 在目標的視野扇形內（看得到）
func is_watched_by(target: Entity) -> bool:
	return bearing_from(target, pos) <= Config.VISION.angle / 2.0 and pos.distance_to(target.pos) <= Config.VISION.range


class Prowl:
	func enter(_e: Hound, data: Dictionary, _fsm: StateMachine) -> void:
		data.prowl_time = 0.0

	func update(e: Hound, dt: float, fsm: StateMachine) -> void:
		var target: Entity = e.nearest_target()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		var p: Dictionary = e.def.prowl
		var d := fsm.data
		d.prowl_time += dt
		var dist := e.pos.distance_to(target.pos)
		var behind: bool = Hound.bearing_from(target, e.pos) >= p.behind_angle
		var impatient: bool = d.prowl_time >= p.patience
		if dist <= e.def.pounce.trigger_distance and (behind or impatient) and e.world.cooldowns.is_ready(e.cd("pounce")):
			fsm.change(&"pounce")
			return
		var goal := target.pos
		if dist <= p.orbit[1] and not behind and not impatient:
			# 繞圈：沿著目標周圍往正後方轉 step 弧度，半徑夾在 orbit 內；被看著時退回外圈
			var here := MathUtil.angle_to(target.pos, e.pos)
			var back: float = target.facing + PI
			var turn := clampf(angle_difference(here, back), -p.step, p.step)
			var r: float = p.orbit[1] if e.is_watched_by(target) else clampf(dist, p.orbit[0], p.orbit[1])
			goal = target.pos + MathUtil.dir_from_angle(here + turn) * r
		var aim := e.steer_point(goal)
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), e.def.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed if e.pos.distance_to(goal) > 0.2 else Vector2.ZERO


class Pounce:
	func enter(e: Hound, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("pounce"), e.cd_time(e.def.pounce.cooldown))
		var target: Entity = e.nearest_target()
		if target != null:
			e.facing = MathUtil.angle_to(e.pos, target.pos)
		data.dir = MathUtil.dir_from_angle(e.facing)
		data.phase = &"windup"
		data.phase_time = 0.0
		data.hit = {}

	func update(e: Hound, dt: float, fsm: StateMachine) -> void:
		var c: Dictionary = e.def.pounce
		var d := fsm.data
		d.phase_time += dt
		e.velocity = Vector2.ZERO
		if d.phase == &"windup":
			if d.phase_time >= c.windup:
				d.phase = &"dash"
				d.phase_time = 0.0
				if e.is_grounded():
					e.vz = c.leap_vz
			return
		if d.phase == &"dash":
			e.velocity = d.dir * (c.distance / c.duration)
			if d.hit.is_empty():
				Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"circle", "radius": e.radius + c.hit_reach}, {
					"damage": c.damage * e.damage_mul, "knockback": c.knockback, "blockable": c.blockable,
				}, d.hit)
			var ahead: Vector2 = e.pos + d.dir * (e.radius + 0.05)
			if d.phase_time >= c.duration or e.world.terrain.ground_at(ahead) > e.height + Config.HEIGHT.step:
				d.phase = &"recovery"
				d.phase_time = 0.0
			return
		if d.phase_time >= c.recovery:
			fsm.change(&"chase")
