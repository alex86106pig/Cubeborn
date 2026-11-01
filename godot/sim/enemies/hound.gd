# 屍犬（第 1 層）：不正面衝。在目標 orbit 半徑外繞圈、往目標背後（視野外）移動，繞到背後才靠近飛撲（pounce）
# 被目標看著（在目標的視野扇形內）時猶豫：拉開到 orbit 半徑繼續繞；繞了 patience 秒還繞不到背後，就從正面撲
# 撲完沿圈退到內圈（orbit[0]）才准再撲；繞圈方向不跟著目標的小幅轉身換邊
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
	func enter(_e: Hound, data: Dictionary, fsm: StateMachine) -> void:
		data.prowl_time = 0.0
		data.side = 0        # 繞圈方向（+1 逆時針 / -1 順時針），0 = 還沒決定
		data.radius = -1.0   # 現在要繞的半徑（往目標半徑平滑移動），-1 = 還沒決定
		data.retreat = fsm.previous_name == &"pounce"   # 撲完：先沿圈退到內圈，退到之前不撲

	func update(e: Hound, dt: float, fsm: StateMachine) -> void:
		var target: Entity = e.nearest_target()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		var p: Dictionary = e.def.prowl
		var d := fsm.data
		d.prowl_time += dt
		var dist := e.pos.distance_to(target.pos)
		if d.retreat and dist >= p.orbit[0] - p.retreat_slack:
			d.retreat = false
		var behind: bool = Hound.bearing_from(target, e.pos) >= p.behind_angle
		var impatient: bool = d.prowl_time >= p.patience
		if not d.retreat and dist <= e.def.pounce.trigger_distance and (behind or impatient) and e.world.cooldowns.is_ready(e.cd("pounce")):
			fsm.change(&"pounce")
			return
		var goal := target.pos
		if d.retreat or (dist <= p.orbit[1] and not behind and not impatient):
			goal = _orbit_goal(e, target, dist, dt, d, p)
		var aim := e.steer_point(goal)
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), e.def.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed if e.pos.distance_to(goal) > 0.2 else Vector2.ZERO

	# 繞圈的目標點：沿著目標周圍往正後方轉 step 弧度
	# 方向第一次繞時選近的那邊，之後照目前方向要繞的角度超過 PI + reverse_margin 才換邊；
	# 每幀重選的話，狗在玩家正前方時兩邊差不多遠，滑鼠一晃就換邊，狗會左右來回
	# 半徑：撲完退到內圈；被看著拉到外圈、沒被看著維持現在的距離，以 radius_speed 平滑移動，不在內外圈之間跳
	func _orbit_goal(e: Hound, target: Entity, dist: float, dt: float, d: Dictionary, p: Dictionary) -> Vector2:
		var here := MathUtil.angle_to(target.pos, e.pos)
		var diff := angle_difference(here, target.facing + PI)
		if d.side == 0:
			d.side = 1 if diff >= 0.0 else -1
		var left := fposmod(diff * d.side, TAU)   # 照目前方向還要繞多少弧度才到正後方
		if left > PI + p.reverse_margin:
			d.side = -d.side
			left = TAU - left
		var want: float = clampf(dist, p.orbit[0], p.orbit[1])
		if d.retreat:
			want = p.orbit[0]
		elif e.is_watched_by(target):
			want = p.orbit[1]
		if d.radius < 0.0:
			d.radius = clampf(dist, p.orbit[0], p.orbit[1])
		d.radius = move_toward(d.radius, want, p.radius_speed * dt)
		return target.pos + MathUtil.dir_from_angle(here + d.side * minf(p.step, left)) * d.radius


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
