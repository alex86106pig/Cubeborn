# 近戰小怪（照搬網頁版 MeleeEnemy.js）：追擊玩家，貼身時以接觸傷害攻擊
class_name MeleeEnemy
extends Enemy

var swing_timer := 0.0   # 接觸命中後的揮擊動畫剩餘秒數（畫面用）


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	var states := Enemy.base_states()
	states[&"chase"] = Chase.new()
	super(p_world, p_type, at, mul, states)


func _anim_extra(a: Dictionary) -> void:
	a["swing"] = swing_timer


class Chase:
	func update(e: MeleeEnemy, dt: float, _fsm: StateMachine) -> void:
		var target := e.nearest_player()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed
		if e.try_contact_damage(target):
			e.swing_timer = e.def.swing_time
		if e.swing_timer > 0.0:
			e.swing_timer -= dt
