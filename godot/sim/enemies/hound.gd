# 屍犬（第 1 層，怪物圖鑑）：不正面衝，靠群體與視野外偷襲
# - 沒被目標看著（在視野外，含側面）：直接靠近，pounce.trigger_distance 內就飛撲（擊倒）
# - 被目標看著：最近的那隻正面牽制（逼近到 pin 範圍、每 0.5~0.8 秒左右側跳），其他的在 orbit 外圈往目標背後繞
# - 繞了 patience 秒還沒撲到（一直被看著）就從正面撲；貼近 snap.trigger_distance 就快咬（輕），咬完往後跳
# - 目標在 roll_punish.radius 內翻滾 → 飛撲到翻滾終點（跟飛撲共用冷卻）
# - 同時最多 pack.max_attackers 隻在出招（快咬、飛撲）；撲完沿圈退到內圈才准再撲
class_name Hound
extends Enemy

const ATTACK_STATES: Array[StringName] = [&"pounce", &"snap"]

var unreached := 0.0   # 上次出招後在繞圈 / 牽制的秒數（側跳不歸零）；到 prowl.patience 就從正面撲


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	var states := Enemy.base_states()
	states[&"chase"] = Prowl.new()
	states[&"pounce"] = Pounce.new()
	states[&"snap"] = Snap.new()
	states[&"hop"] = Hop.new()
	states[&"dazed"] = Dazed.new()
	super(p_world, p_type, at, mul, states)


func _anim_extra(a: Dictionary) -> void:
	if fsm.is_in(&"pounce") or fsm.is_in(&"snap"):
		a["phase"] = fsm.data.phase
		a["phase_time"] = fsm.data.phase_time


func _can_jump() -> bool:
	return fsm.is_in(&"chase")


func is_attacking() -> bool:
	return not is_dead and fsm.current_name in ATTACK_STATES


# 自己相對於目標的方位（目標朝向 0、正後方 PI）
static func bearing_from(target: Entity, at: Vector2) -> float:
	return absf(angle_difference(target.facing, MathUtil.angle_to(target.pos, at)))


# 在目標的視野扇形內（看得到）
func is_watched_by(target: Entity) -> bool:
	return bearing_from(target, pos) <= Config.VISION.angle / 2.0 and pos.distance_to(target.pos) <= Config.VISION.range


# 群體：同時出招的屍犬不超過 pack.max_attackers 隻
func pack_allows() -> bool:
	var n := 0
	for o: Entity in world.enemies:
		if o is Hound and (o as Hound).is_attacking():
			n += 1
	return n < def.pack.max_attackers


# 被目標看著的屍犬裡最近的那隻負責正面牽制
func is_pinner(target: Entity) -> bool:
	if not is_watched_by(target):
		return false
	var mine := pos.distance_squared_to(target.pos)
	for o: Entity in world.enemies:
		if o != self and o is Hound and not o.is_dead and (o as Hound).fsm.is_in(&"chase") and (o as Hound).is_watched_by(target) \
				and o.pos.distance_squared_to(target.pos) < mine:
			return false
	return true


# 目標正在翻滾：回傳翻滾的終點；沒在翻滾回傳 null
static func roll_end(target: Entity) -> Variant:
	if not (target is Player) or not (target as Player).action.is_in(&"roll"):
		return null
	var p := target as Player
	return p.pos + p.velocity * maxf(0.0, Config.ROLL.duration - p.action.time)


# 這一步有沒有被盾擋下（Hitbox.strike 之後看新事件）
static func was_blocked(world: World, events_before: int) -> bool:
	for i in range(events_before, world.events.size()):
		if world.events[i].name == "player:blocked":
			return true
	return false


class Prowl:
	func enter(_e: Hound, data: Dictionary, fsm: StateMachine) -> void:
		data.side = 0        # 繞圈方向（+1 逆時針 / -1 順時針），0 = 還沒決定
		data.radius = -1.0   # 現在要繞的半徑（往目標半徑平滑移動），-1 = 還沒決定
		data.retreat = fsm.previous_name == &"pounce"   # 撲完：先沿圈退到內圈，退到之前不撲
		data.hop_timer = 0.0

	func update(e: Hound, dt: float, fsm: StateMachine) -> void:
		var target: Entity = e.nearest_target()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		var p: Dictionary = e.def.prowl
		var d := fsm.data
		e.unreached += dt
		var dist := e.pos.distance_to(target.pos)
		if d.retreat and dist >= p.orbit[0] - p.retreat_slack:
			d.retreat = false
		var watched := e.is_watched_by(target)
		var impatient: bool = e.unreached >= p.patience
		if not d.retreat and _try_attack(e, target, dist, watched, impatient, fsm):
			return
		var goal := target.pos
		var pinning: bool = not d.retreat and not impatient and e.is_pinner(target)
		if pinning:
			goal = _pin_goal(e, target, dist, dt, d, fsm)
			if fsm.current_name != &"chase":
				return
		elif d.retreat or (dist <= p.orbit[1] and watched and not impatient):   # 沒被看著：已經在視野外，直接靠近撲
			goal = _orbit_goal(e, target, dist, dt, d, p)
		var aim := e.steer_point(goal)
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), e.def.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed if e.pos.distance_to(goal) > 0.2 else Vector2.ZERO

	# 依序：抓翻滾 → 快咬 → 飛撲（視野外，或等不及了）
	func _try_attack(e: Hound, target: Entity, dist: float, watched: bool, impatient: bool, fsm: StateMachine) -> bool:
		if not e.pack_allows():
			return false
		var pounce_ready := e.world.cooldowns.is_ready(e.cd("pounce"))
		var end: Variant = Hound.roll_end(target)
		if end != null and pounce_ready and dist <= e.def.roll_punish.radius:
			fsm.change(&"pounce", {"at": end})
			return true
		if dist <= e.def.snap.trigger_distance and e.world.cooldowns.is_ready(e.cd("snap")):
			fsm.change(&"snap")
			return true
		if dist <= e.def.pounce.trigger_distance and pounce_ready and (not watched or impatient):
			fsm.change(&"pounce")
			return true
		return false

	# 正面牽制：逼近到 pin 範圍（內外圈中間），到了之後每隔一段時間左右側跳
	func _pin_goal(e: Hound, target: Entity, dist: float, dt: float, d: Dictionary, fsm: StateMachine) -> Vector2:
		var c: Dictionary = e.def.pin
		var away := (e.pos - target.pos).normalized() if dist > 0.01 else MathUtil.dir_from_angle(target.facing)
		if dist >= c.range[0] - 0.3 and dist <= c.range[1] + 0.3:
			d.hop_timer -= dt
			if d.hop_timer <= 0.0:
				var side := 1.0 if e.world.rng.randf() < 0.5 else -1.0
				fsm.change(&"hop", {"dir": away.orthogonal() * side, "distance": c.hop_distance, "time": c.hop_time,
					"hop_timer": e.world.rng.randf_range(c.hop_interval[0], c.hop_interval[1])})
				return target.pos
		else:
			d.hop_timer = maxf(d.hop_timer, c.hop_interval[0])
		return target.pos + away * clampf(dist, c.range[0], c.range[1])

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


# 飛撲：伏低 windup（鎖定方向）→ 直線撲 distance（跳起來）→ recovery；擊倒、擋得住
# data.at：抓翻滾時撲向的位置（翻滾終點），距離照那一點（最多 roll_punish.max_distance）
class Pounce:
	func enter(e: Hound, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.unreached = 0.0
		e.world.cooldowns.start(e.cd("pounce"), e.cd_time(e.def.pounce.cooldown))
		var c: Dictionary = e.def.pounce
		data.distance = c.distance
		if data.has("at"):
			e.facing = MathUtil.angle_to(e.pos, data.at)
			data.distance = minf(e.pos.distance_to(data.at), e.def.roll_punish.max_distance)
			data.windup = e.def.roll_punish.windup
		else:
			var target: Entity = e.nearest_target()
			if target != null:
				e.facing = MathUtil.angle_to(e.pos, target.pos)
			data.windup = c.windup
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
			if d.phase_time >= d.windup:
				d.phase = &"dash"
				d.phase_time = 0.0
				if e.is_grounded():
					e.vz = c.leap_vz
			return
		if d.phase == &"dash":
			e.velocity = d.dir * (d.distance / c.duration)
			if d.hit.is_empty():
				var events_before := e.world.events.size()
				Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"circle", "radius": e.radius + c.hit_reach}, {
					"damage": c.damage * e.damage_mul, "knockback": c.knockback, "blockable": c.blockable, "tier": &"knockdown",
				}, d.hit)
				if Hound.was_blocked(e.world, events_before):
					fsm.change(&"dazed", {"time": c.blocked_daze})
					return
			var ahead: Vector2 = e.pos + d.dir * (e.radius + 0.05)
			if d.phase_time >= c.duration or e.world.terrain.ground_at(ahead) > e.height + Config.HEIGHT.step:
				d.phase = &"recovery"
				d.phase_time = 0.0
			return
		if d.phase_time >= c.recovery:
			fsm.change(&"chase")


# 快咬：低頭齜牙 windup（前 track 比例轉向）→ 往前竄 distance → 咬完往後跳 back_hop；輕級、擋下自己暈 blocked_daze
class Snap:
	func enter(e: Hound, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.unreached = 0.0
		e.world.cooldowns.start(e.cd("snap"), e.cd_time(e.def.snap.cooldown))
		data.phase = &"windup"
		data.phase_time = 0.0
		data.hit = {}

	func update(e: Hound, dt: float, fsm: StateMachine) -> void:
		var c: Dictionary = e.def.snap
		var d := fsm.data
		d.phase_time += dt
		e.velocity = Vector2.ZERO
		if d.phase == &"windup":
			var target: Entity = e.nearest_target()
			if d.phase_time < c.windup * c.track and target != null:
				e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * dt)
			if d.phase_time >= c.windup:
				d.phase = &"dash"
				d.phase_time = 0.0
				d.dir = MathUtil.dir_from_angle(e.facing)
			return
		e.velocity = d.dir * (c.distance / c.duration)
		if d.hit.is_empty():
			var events_before := e.world.events.size()
			Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"circle", "radius": e.radius + c.hit_reach}, {
				"damage": c.damage * e.damage_mul, "knockback": 0.0, "blockable": c.blockable, "tier": &"light",
			}, d.hit)
			if Hound.was_blocked(e.world, events_before):
				fsm.change(&"dazed", {"time": c.blocked_daze})
				return
		if d.phase_time >= c.duration:
			fsm.change(&"hop", {"dir": -d.dir, "distance": c.back_hop, "time": c.back_hop_time})


# 跳開（側跳、咬完後跳）：time 秒內往 dir 移動 distance、小跳；data.hop_timer 帶回繞圈（下次側跳的倒數）
class Hop:
	func enter(e: Hound, data: Dictionary, _fsm: StateMachine) -> void:
		if e.is_grounded():
			e.vz = e.def.pin.hop_vz

	func update(e: Hound, _dt: float, fsm: StateMachine) -> void:
		var d := fsm.data
		e.velocity = d.dir * (d.distance / d.time)
		var ahead: Vector2 = e.pos + (d.dir as Vector2) * (e.radius + 0.05)
		if fsm.time >= d.time or e.world.terrain.ground_at(ahead) > e.height + Config.HEIGHT.step:
			var hop_timer: float = d.get("hop_timer", 0.0)
			fsm.change(&"chase")
			fsm.data.hop_timer = hop_timer


# 被盾擋下：站著暈 time 秒
class Dazed:
	func enter(e: Hound, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO

	func update(e: Hound, _dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		if fsm.time >= fsm.data.time:
			fsm.change(&"chase")
