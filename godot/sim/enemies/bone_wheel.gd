# 骨輪（第 2 層，數值 Claude 暫定）：一圈骨頭組成的輪子。目標在 roll.trigger_distance 內、看得到時原地喀啦晃（windup）→
# 直線滾過去（每秒最多轉 turn_rate 追著目標），一路滾到撞牆 / 高台 / 場地邊緣（被盾擋下也算）→ 散成骨堆暈 collapse 秒再組起來。
# 不會受傷硬直；滾的途中撞到的每個目標各打一次，打中了照樣往前滾
class_name BoneWheel
extends Enemy


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	var states := Enemy.base_states()
	states.erase(&"hurt")   # 不會硬直
	states[&"chase"] = Chase.new()
	states[&"windup"] = Windup.new()
	states[&"roll"] = Roll.new()
	states[&"collapse"] = Collapse.new()
	super(p_world, p_type, at, mul, states)


func is_rolling() -> bool:
	return fsm.is_in(&"roll")


# 前方 radius + 0.05 的地面比腳下高出一階、或出了場地邊緣 = 撞牆
func _wall_ahead(dir: Vector2) -> bool:
	var ahead := pos + dir * (radius + 0.05)
	var lim := world.half_extents - Vector2(radius, radius)
	if absf(ahead.x) > lim.x or absf(ahead.y) > lim.y:
		return true
	return world.terrain.ground_at(ahead) > height + Config.HEIGHT.step


# 沒在滾：慢慢滾向目標（會繞牆）；冷卻好、距離夠近、中間沒有牆就開始蓄力
class Chase:
	func update(e: BoneWheel, dt: float, fsm: StateMachine) -> void:
		var target: Entity = e.nearest_target()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		var r: Dictionary = e.def.roll
		if e.world.cooldowns.is_ready(e.cd("roll")) and e.pos.distance_to(target.pos) <= r.trigger_distance \
				and e.world.nav.has_los(e.pos, target.pos):
			fsm.change(&"windup")
			return
		var aim := e.steer_point(target.pos)
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), e.def.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed


# 原地喀啦晃、骨頭收緊：一直轉向目標
class Windup:
	func enter(e: BoneWheel, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.emit_event("sfx:cue", {"cue": e.def.roll.sfx_windup, "pos": e.pos})

	func update(e: BoneWheel, dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		var target: Entity = e.nearest_target()
		if target != null:
			e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * 2.0 * dt)
		if fsm.time >= e.def.roll.windup:
			fsm.change(&"roll")


class Roll:
	func enter(e: BoneWheel, data: Dictionary, _fsm: StateMachine) -> void:
		data.hit = {}

	func update(e: BoneWheel, dt: float, fsm: StateMachine) -> void:
		var r: Dictionary = e.def.roll
		var target: Entity = e.nearest_target()
		if target != null:
			e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), r.turn_rate * dt)
		var dir := MathUtil.dir_from_angle(e.facing)
		if e._wall_ahead(dir):
			_crash(e, fsm)
			return
		e.velocity = dir * r.speed * (e.speed / e.def.move_speed)   # 迅捷詞條、緩速照比例
		var events_before := e.world.events.size()
		_strike(e, dir, fsm.data.hit)
		for i in range(events_before, e.world.events.size()):
			if e.world.events[i].name == "player:blocked":   # 被盾擋下算撞牆
				_crash(e, fsm)
				return
		if fsm.time >= r.max_time:
			e.velocity = Vector2.ZERO
			e.world.cooldowns.start(e.cd("roll"), e.cd_time(r.cooldown))
			fsm.change(&"chase")

	# 撞到的每個目標打一次，擊退往輪子的側面（偏前）：把人撞開到一邊、輪子滾過去，不會推著人一路滾到牆
	func _strike(e: BoneWheel, dir: Vector2, already: Dictionary) -> void:
		var r: Dictionary = e.def.roll
		var shape := {"shape": &"circle", "radius": e.radius + r.hit_reach}
		e.world.record_hitbox({"shape": shape, "origin": e.pos, "facing": e.facing, "band": Combat.body_band(e), "team": e.team})
		for target in Hitbox.query(e.world, e.team, e.pos, e.facing, shape, e.id):
			if already.has(target.id):
				continue
			already[target.id] = true
			var side := 1.0 if dir.cross(target.pos - e.pos) >= 0.0 else -1.0
			var push: Vector2 = (Vector2(-dir.y, dir.x) * side * r.side_push + dir * (1.0 - r.side_push)).normalized()
			Combat.apply_damage(e.world, e, target, {
				"damage": r.damage * e.damage_mul, "knockback": r.knockback, "blockable": r.blockable, "push_dir": push,
			})

	func _crash(e: BoneWheel, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.emit_event("enemy:crashed", {"enemy_id": e.id, "pos": e.pos, "height": e.ground_height})
		e.world.emit_event("sfx:cue", {"cue": e.def.roll.sfx_crash, "pos": e.pos})
		e.world.emit_event("camera:shake", {"amount": e.def.roll.shake, "duration": 0.2})
		fsm.change(&"collapse")


# 撞牆：散成骨堆暈 collapse 秒（最後 reform 秒組回去），之後冷卻 cooldown 秒才再滾
class Collapse:
	func enter(e: BoneWheel, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO

	func update(e: BoneWheel, _dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		if fsm.time >= e.def.roll.collapse:
			e.world.cooldowns.start(e.cd("roll"), e.cd_time(e.def.roll.cooldown))
			fsm.change(&"chase")
