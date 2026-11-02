# 屍甲蟲（第 3 層的怪，第 2 層的石棺噴出來；數值 Claude 暫定）：成群、血少。大部分時間鑽在地底（打不到、不能當目標）往目標爬，
# 地面冒土（畫面）；爬到跟目標碰在一起（+ strike_reach）就停下、土塊跳動 emerge 秒（預兆）→ 冒出來咬一口並小擊飛（擋不住）→
# 在地面停 surface 秒（打得到）→ 再鑽下去
class_name Beetle
extends Enemy


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	var states := Enemy.base_states()
	states.erase(&"hurt")   # 不硬直：被打一下就回主狀態（鑽地）會縮短露頭的空檔
	states[&"burrow"] = Burrow.new()
	states[&"emerge"] = Emerge.new()
	states[&"surface"] = Surface.new()
	super(p_world, p_type, at, mul, states)
	main_state = &"burrow"


func is_burrowed() -> bool:
	return not is_dead and (fsm.is_in(&"burrow") or fsm.is_in(&"emerge"))


# 鑽在地底：打不到（投射物穿過）、不能被當成目標
func is_dodging() -> bool:
	return is_burrowed()


func is_targetable() -> bool:
	return super() and not is_burrowed()


func _anim_extra(a: Dictionary) -> void:
	if is_burrowed():
		a["burrowed"] = true


class Burrow:
	func update(e: Beetle, dt: float, fsm: StateMachine) -> void:
		var target: Entity = e.nearest_target()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		var b: Dictionary = e.def.burrow
		if fsm.time >= b.min_time and e.pos.distance_to(target.pos) <= e.radius + target.radius + b.strike_reach:
			fsm.change(&"emerge")
			return
		var aim := e.steer_point(target.pos)
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), e.def.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed


# 停在腳下、土塊跳動（目標還來得及走開）→ 冒出來咬：以自己為中心 bite_radius 內，擋不住、小擊飛
class Emerge:
	func enter(e: Beetle, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.emit_event("fx:burrow_warn", {"pos": e.pos, "height": e.ground_height, "life": e.def.burrow.emerge})

	func update(e: Beetle, _dt: float, fsm: StateMachine) -> void:
		var b: Dictionary = e.def.burrow
		e.velocity = Vector2.ZERO
		if fsm.time >= b.emerge:
			var hits := Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"circle", "radius": b.bite_radius}, {
				"damage": b.damage * e.damage_mul, "knockback": b.knockback, "origin": e.pos, "blockable": false,
			})
			for t in hits:
				if t is Player:
					(t as Player).vz = maxf((t as Player).vz, b.knockup)
			e.world.emit_event("fx:burrow_out", {"pos": e.pos, "height": e.ground_height})
			fsm.change(&"surface")


class Surface:
	func enter(e: Beetle, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO

	func update(e: Beetle, _dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		if fsm.time >= e.def.burrow.surface:
			fsm.change(&"burrow")
