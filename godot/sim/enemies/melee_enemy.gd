# 近戰小怪（骷髏戰士）：追擊玩家，靠近且冷卻好時舉刀 → 揮下 → 收招（v0.17.0 取代網頁版的接觸傷害）
# 舉刀時站定，前半段轉向玩家、後半段鎖定方向；揮下用通用判定（sim/hitbox.gd）的扇形
# v0.27.0：狂暴的 Boss 召喚出來的骷髏戰士（pending_rush）爬出來後先衝撞一次（rush，同 Boss 衝鋒的模式）
class_name MeleeEnemy
extends Enemy

var pending_rush := false


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	var states := Enemy.base_states()
	states[&"chase"] = Chase.new()
	states[&"swing"] = Swing.new()
	states[&"rush"] = Rush.new()
	super(p_world, p_type, at, mul, states)


func _anim_extra(a: Dictionary) -> void:
	if fsm.is_in(&"rush"):
		a["phase"] = fsm.data.phase
		a["phase_time"] = fsm.data.phase_time


# 衝撞中不跳
func _can_jump() -> bool:
	return not fsm.is_in(&"rush")


class Chase:
	func update(e: MeleeEnemy, dt: float, fsm: StateMachine) -> void:
		var target := e.nearest_player()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		if e.pending_rush:
			e.pending_rush = false
			fsm.change(&"rush")
			return
		var s: Dictionary = e.def.swing
		if e.pos.distance_to(target.pos) <= s.trigger_distance and e.world.cooldowns.is_ready(e.cd("swing")):
			fsm.change(&"swing")
			return
		var aim := e.steer_point(target.pos)   # 被牆擋住時繞路（D1）
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), e.def.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed


class Swing:
	func enter(e: MeleeEnemy, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("swing"), e.cd_time(e.def.swing.cooldown))
		data.hit = {}

	func update(e: MeleeEnemy, dt: float, fsm: StateMachine) -> void:
		var s: Dictionary = e.def.swing
		var t := fsm.time
		e.velocity = Vector2.ZERO
		var target := e.nearest_player()
		if t < s.windup * s.track and target != null:
			e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * dt)
		if t >= s.windup and t < s.windup + s.active:
			Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"sector", "range": s.range, "arc": s.arc}, {
				"damage": s.damage * e.damage_mul, "knockback": s.knockback, "blockable": s.blockable,
			}, fsm.data.hit)
		if t >= s.windup + s.active + s.recovery:
			fsm.change(&"chase")


# 衝撞：面向玩家蓄力 → 直線衝刺（撞牆就停）→ 收招；只打中一次
class Rush:
	func enter(e: MeleeEnemy, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		var target := e.nearest_player()
		if target != null:
			e.facing = MathUtil.angle_to(e.pos, target.pos)
		data.dir = MathUtil.dir_from_angle(e.facing)
		data.phase = &"windup"
		data.phase_time = 0.0
		data.hit = {}

	func update(e: MeleeEnemy, dt: float, fsm: StateMachine) -> void:
		var r: Dictionary = e.def.rush
		var d := fsm.data
		d.phase_time += dt
		e.velocity = Vector2.ZERO
		if d.phase == &"windup":
			if d.phase_time >= r.windup:
				d.phase = &"dash"
				d.phase_time = 0.0
			return
		if d.phase == &"dash":
			e.velocity = d.dir * r.speed
			if d.hit.is_empty():
				Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"circle", "radius": e.radius + r.hit_reach}, {
					"damage": r.damage * e.damage_mul, "knockback": r.knockback, "blockable": r.blockable,
				}, d.hit)
			var ahead: Vector2 = e.pos + d.dir * (e.radius + 0.05)
			if d.phase_time >= r.duration or e.world.terrain.ground_at(ahead) > e.height + Config.HEIGHT.step:
				e.velocity = Vector2.ZERO
				d.phase = &"recovery"
				d.phase_time = 0.0
			return
		if d.phase_time >= r.recovery:
			fsm.change(&"chase")
