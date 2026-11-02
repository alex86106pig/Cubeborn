# 骷髏盾槍兵（第 2 層，數值 Claude 暫定）：舉著盾慢慢逼近，正面 shield.arc 內的攻擊全部擋下（含平常擋不住的爆炸、技能）；
# 重攻擊（hit.is_heavy）打在盾上破防 shield.break_time 秒（這一下照樣打到）；直刺時盾往旁邊偏，正面也打得到
class_name Spearman
extends Enemy


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	var states := Enemy.base_states()
	states[&"chase"] = Chase.new()
	states[&"thrust"] = Thrust.new()
	states[&"guard_broken"] = GuardBroken.new()
	super(p_world, p_type, at, mul, states)


# 破防中被打不換成受傷：破防的那一下（重攻擊）接著就扣血，不然破防只維持一瞬間
func _on_damaged(amount: float, source_id: int) -> void:
	if fsm.is_in(&"guard_broken"):
		return
	super(amount, source_id)


# 舉著盾：追擊與休眠中、沒被暈 / 凍 / 失衡 / 埋 / 抓
func is_guarding() -> bool:
	if is_dead or not (fsm.is_in(&"chase") or fsm.is_in(&"dormant")):
		return false
	return stun_timer <= 0.0 and frozen_timer <= 0.0 and stagger_timer <= 0.0 and buried_timer <= 0.0 and grabbed_by == 0


# Combat._apply_damage 在格擋與閃避之前問：擋下回傳 true（不扣血、不疊狀態）。以自己為中心的範圍攻擊（origin 在身上）不算正面
func shield_blocks(origin: Vector2, hit: Dictionary) -> bool:
	if not is_guarding():
		return false
	var to := origin - pos
	if to.length_squared() < 1e-6 or absf(angle_difference(facing, atan2(to.x, to.y))) > def.shield.arc / 2.0:
		return false
	if dormant and pack_id >= 0:
		world.wake_pack(pack_id)
	if hit.get("is_heavy", false):
		fsm.change(&"guard_broken")
		world.emit_event("enemy:guard_broken", {"enemy_id": id, "pos": pos, "height": ground_height, "facing": facing, "broken": true})
		world.emit_event("sfx:cue", {"cue": def.shield.sfx_break, "pos": pos})
		return false
	knockback -= to.normalized() * (hit.get("knockback", 0.0) * def.shield.push_mul / mass)
	world.emit_event("enemy:blocked", {"enemy_id": id, "pos": pos, "height": ground_height, "facing": facing})
	world.emit_event("sfx:cue", {"cue": def.shield.sfx_block, "pos": pos})
	return true


# 舉盾時轉身慢（turn_speed），繞到側面或背後就打得到；冷卻好、目標在 trigger_distance 內就直刺
class Chase:
	func update(e: Spearman, dt: float, fsm: StateMachine) -> void:
		var target: Entity = e.nearest_target()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		var t: Dictionary = e.def.thrust
		if e.pos.distance_to(target.pos) <= t.trigger_distance and e.world.cooldowns.is_ready(e.cd("thrust")):
			fsm.change(&"thrust")
			return
		var aim := e.steer_point(target.pos)
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), e.def.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed


# 直刺：盾往旁邊偏、槍收到腰間（windup，前 track 比例轉向目標）→ 往前刺出細長的直線（active）→ 收槍（recovery）
class Thrust:
	func enter(e: Spearman, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("thrust"), e.cd_time(e.def.thrust.cooldown))
		data.hit = {}

	func update(e: Spearman, dt: float, fsm: StateMachine) -> void:
		var s: Dictionary = e.def.thrust
		var t := fsm.time
		e.velocity = Vector2.ZERO
		var target: Entity = e.nearest_target()
		if t < s.windup * s.track and target != null:
			e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * 2.0 * dt)
		if t >= s.windup and t < s.windup + s.active:
			Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"sector", "range": s.range, "arc": 2.0 * atan(s.width / s.range)}, {
				"damage": s.damage * e.damage_mul, "knockback": s.knockback, "blockable": s.blockable,
			}, fsm.data.hit)
		if t >= s.windup + s.active + s.recovery:
			fsm.change(&"chase")


# 破防：盾甩開、往後仰，break_time 秒不舉盾也不出招
class GuardBroken:
	func enter(e: Spearman, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO

	func update(e: Spearman, _dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		if fsm.time >= e.def.shield.break_time:
			fsm.change(&"chase")
