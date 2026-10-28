# 腐屍（第 1 層主力）：慢慢追，靠近時舉手後仰（lunge windup）→ 往前撲（dash）→ 撲中就抓住玩家持續啃咬（bite）
# 抓住 = 玩家暈眩並標 grabbed_by（Player.stun）：玩家按翻滾立刻掙脫；腐屍被任何人打到就鬆手；盾擋下撲抱時踉蹌（stagger）
class_name Zombie
extends Enemy

const GRAB_MARGIN := 0.1


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	var states := Enemy.base_states()
	states[&"chase"] = Chase.new()
	states[&"lunge"] = Lunge.new()
	states[&"bite"] = Bite.new()
	states[&"stagger"] = Stagger.new()
	super(p_world, p_type, at, mul, states)


func _anim_extra(a: Dictionary) -> void:
	if fsm.is_in(&"lunge"):
		a["phase"] = fsm.data.phase
		a["phase_time"] = fsm.data.phase_time


# 撲中、啃咬中不跳
func _can_jump() -> bool:
	return fsm.is_in(&"chase")


# 被打就鬆手（隊友救援）；之後照常進入受擊硬直
func _on_damaged(amount: float, source_id: int) -> void:
	if fsm.is_in(&"bite"):
		release(fsm.data.get("target_id", 0))
	super(amount, source_id)


func _on_died(source_id: int) -> void:
	if fsm.is_in(&"bite"):
		release(fsm.data.get("target_id", 0))
	super(source_id)


func release(target_id: int) -> void:
	var p := world.entities.get(target_id) as Player
	if p != null and p.grabbed_by == id:
		p.release_grab()


class Chase:
	func update(e: Zombie, dt: float, fsm: StateMachine) -> void:
		var target: Entity = e.nearest_target()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		var l: Dictionary = e.def.lunge
		if e.pos.distance_to(target.pos) <= l.trigger_distance and e.world.cooldowns.is_ready(e.cd("lunge")):
			fsm.change(&"lunge")
			return
		var aim := e.steer_point(target.pos)
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), e.def.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed


# 撲抱：windup（舉手後仰，前 track 比例轉向目標）→ dash（往前撲 distance，判定只打一次）→ recovery
# 撲中玩家（沒擋下）→ 抓住、切到 bite；擋下 → 踉蹌 blocked_stagger 秒
class Lunge:
	func enter(e: Zombie, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("lunge"), e.cd_time(e.def.lunge.cooldown))
		data.phase = &"windup"
		data.phase_time = 0.0
		data.hit = {}

	func update(e: Zombie, dt: float, fsm: StateMachine) -> void:
		var l: Dictionary = e.def.lunge
		var d := fsm.data
		d.phase_time += dt
		e.velocity = Vector2.ZERO
		if d.phase == &"windup":
			var target: Entity = e.nearest_target()
			if d.phase_time < l.windup * l.track and target != null:
				e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * dt)
			if d.phase_time >= l.windup:
				d.phase = &"dash"
				d.phase_time = 0.0
				d.dir = MathUtil.dir_from_angle(e.facing)
			return
		if d.phase == &"dash":
			e.velocity = d.dir * (l.distance / l.duration)
			if d.hit.is_empty():
				var events_before := e.world.events.size()
				var hits := Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"circle", "radius": e.radius + l.hit_reach}, {
					"damage": l.damage * e.damage_mul, "knockback": 0.0, "blockable": l.blockable,
				}, d.hit)
				for i in range(events_before, e.world.events.size()):
					if e.world.events[i].name == "player:blocked":
						fsm.change(&"stagger")
						return
				for t in hits:
					if t is Player and not t.is_dead and not (t as Player).is_downed:
						fsm.change(&"bite", {"target_id": t.id})
						return
			if d.phase_time >= l.duration:
				d.phase = &"recovery"
				d.phase_time = 0.0
			return
		if d.phase_time >= l.recovery:
			fsm.change(&"chase")


# 啃咬：抓住目標 grab_time 秒，每 bite_interval 秒咬一口；目標掙脫（翻滾）、倒下或時間到就放開
class Bite:
	func enter(e: Zombie, data: Dictionary, _fsm: StateMachine) -> void:
		var l: Dictionary = e.def.lunge
		e.velocity = Vector2.ZERO
		data.bites = 0
		var p := e.world.entities.get(data.target_id) as Player
		if p != null:
			p.stun(l.grab_time + GRAB_MARGIN, e.id)   # 放開由腐屍決定（咬完最後一口才放），玩家的暈眩不先到期
			e.facing = MathUtil.angle_to(e.pos, p.pos)

	func update(e: Zombie, _dt: float, fsm: StateMachine) -> void:
		var l: Dictionary = e.def.lunge
		var d := fsm.data
		e.velocity = Vector2.ZERO
		var p := e.world.entities.get(d.target_id) as Player
		if p == null or p.grabbed_by != e.id or p.is_dead or p.is_downed:
			fsm.change(&"chase")
			return
		# 第 n 口在 n × bite_interval 秒（用次數算，不累加浮點數，最後一口才不會因為誤差漏掉）
		var t := fsm.time + 1e-6
		if d.bites < floori(t / l.bite_interval) and d.bites < roundi(l.grab_time / l.bite_interval):
			d.bites += 1
			p.invuln_timer = 0.0   # 抓住時的啃咬不吃受傷後的無敵時間（0.6 秒），每口都咬得到；放開後照常有無敵可以逃
			Combat.apply_damage(e.world, e, p, {"damage": l.bite_damage * e.damage_mul, "knockback": 0.0, "blockable": false})
		if t >= l.grab_time:
			e.release(p.id)
			fsm.change(&"chase")


class Stagger:
	func enter(e: Zombie, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO

	func update(e: Zombie, _dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		if fsm.time >= e.def.lunge.blocked_stagger:
			fsm.change(&"chase")
