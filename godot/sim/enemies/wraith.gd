# 尖嘯幽影（第 4 層的怪，第 3 層的巨繭噴出來；數值 Claude 暫定）：穿牆浮空（phases：不被地形推開、不照地面升降），筆直飄向目標；
# 飄到 shriek.trigger_distance 內就縮身吸氣 windup 秒 → 尖嘯：radius 內沒在翻滾的玩家受傷並恐懼 fear 秒
# （不能出招，被迫往反方向跑，Player.fear）；擋不住，先走出範圍就沒事。物理抗性高、怕神聖
class_name Wraith
extends Enemy


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	var states := Enemy.base_states()
	states[&"chase"] = Chase.new()
	states[&"shriek"] = Shriek.new()
	super(p_world, p_type, at, mul, states)
	phases = true


func _can_jump() -> bool:
	return false


# 筆直飄過去（不繞牆）；貼到 trigger_distance 的 hover 比例就停下來等冷卻
class Chase:
	func update(e: Wraith, dt: float, fsm: StateMachine) -> void:
		var target: Entity = e.nearest_target()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		var s: Dictionary = e.def.shriek
		var dist := e.pos.distance_to(target.pos)
		if dist <= s.trigger_distance and e.world.cooldowns.is_ready(e.cd("shriek")):
			fsm.change(&"shriek")
			return
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed if dist > s.trigger_distance * s.hover else Vector2.ZERO


class Shriek:
	func enter(e: Wraith, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("shriek"), e.cd_time(e.def.shriek.cooldown))
		data.done = false

	func update(e: Wraith, _dt: float, fsm: StateMachine) -> void:
		var s: Dictionary = e.def.shriek
		e.velocity = Vector2.ZERO
		if not fsm.data.done and fsm.time >= s.windup:
			fsm.data.done = true
			e.world.emit_event("fx:shriek", {"pos": e.pos, "height": e.height, "radius": s.radius})
			e.world.emit_event("sfx:cue", {"cue": "enrage", "pos": e.pos})
			var hits := Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"circle", "radius": s.radius}, {
				"damage": s.damage * e.damage_mul, "knockback": 0.0, "origin": e.pos, "blockable": false, "damage_type": &"shadow",
				"tier": &"none", "band": Vector2(-INF, INF),
			})
			for t in hits:
				if t is Player:
					(t as Player).fear(s.fear, e.pos, s.flee_speed_mul)
		if fsm.time >= s.windup + s.recovery:
			fsm.change(&"chase")
