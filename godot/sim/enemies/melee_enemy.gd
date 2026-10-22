# 近戰小怪（骷髏戰士）：追擊玩家，靠近且冷卻好時舉刀 → 揮下 → 收招（v0.17.0 取代網頁版的接觸傷害）
# 舉刀時站定，前半段轉向玩家、後半段鎖定方向；揮下用通用判定（sim/hitbox.gd）的扇形
class_name MeleeEnemy
extends Enemy


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	var states := Enemy.base_states()
	states[&"chase"] = Chase.new()
	states[&"swing"] = Swing.new()
	super(p_world, p_type, at, mul, states)


class Chase:
	func update(e: MeleeEnemy, dt: float, fsm: StateMachine) -> void:
		var target := e.nearest_player()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		var s: Dictionary = e.def.swing
		if e.pos.distance_to(target.pos) <= s.trigger_distance and e.world.cooldowns.is_ready(e.cd("swing")):
			fsm.change(&"swing")
			return
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed


class Swing:
	func enter(e: MeleeEnemy, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("swing"), e.def.swing.cooldown)
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
