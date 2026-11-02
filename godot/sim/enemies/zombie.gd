# 腐屍（第 1 層主力）：慢慢追，靠近時舉手後仰（lunge windup）→ 往前撲（dash）→ 撲中就抓住玩家持續啃咬（bite）
# 抓住 = 玩家暈眩並標 grabbed_by（Player.stun）：玩家按翻滾立刻掙脫；腐屍被任何人打到就鬆手；盾擋下撲抱時踉蹌（stagger）
# 撿武器（怪物圖鑑）：沒拿武器時，pickup.radius 內有地上的武器就走過去彎腰撿（被打中斷）；撿到後不再撲抱，
# 改用那把武器的普攻與技能（EnemyDefs.ARMED_ZOMBIE，招式在 sim/enemies/armed_moves.gd），死掉時武器原樣掉回地上
class_name Zombie
extends Enemy

const GRAB_MARGIN := 0.1

var armed_weapon: Dictionary = {}   # 撿到的武器實例（WeaponDropDefs）；空 = 空手
var shielding := false              # 劍盾腐屍舉盾中：正面 shield.arc 內的攻擊擋下（take_damage）


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	var states := Enemy.base_states()
	states[&"chase"] = Chase.new()
	states[&"lunge"] = Lunge.new()
	states[&"bite"] = Bite.new()
	states[&"stagger"] = Stagger.new()
	states[&"fetch"] = Fetch.new()
	states[&"armed_move"] = ArmedMoves.Move.new()
	super(p_world, p_type, at, mul, states)


func _anim_extra(a: Dictionary) -> void:
	if fsm.is_in(&"lunge") or fsm.is_in(&"fetch"):
		a["phase"] = fsm.data.phase
		a["phase_time"] = fsm.data.phase_time
	if fsm.is_in(&"armed_move"):
		a["move"] = fsm.data.kind      # &"attack" / &"skill"
		a["move_type"] = fsm.data.move.type
		a["phase"] = fsm.data.phase
		a["phase_time"] = fsm.data.phase_time
	if not armed_weapon.is_empty():
		a["weapon"] = armed_weapon.base
	if shielding:
		a["shielding"] = true


func is_armed() -> bool:
	return not armed_weapon.is_empty()


func kit() -> Dictionary:
	return EnemyDefs.armed_kit(armed_weapon.base)


# 撿起地上的武器：武器從地上消失，換成持武器的腐屍（移速倍率、名字）
func arm(ip: ItemPickup) -> void:
	armed_weapon = ip.weapon
	ip.remove()
	set_stat_source(&"armed", [[&"move_speed", Stats.MUL, kit().get("move_mul", 1.0)]])
	world.emit_event("enemy:armed", {"enemy_id": id, "weapon": armed_weapon.base, "pos": pos})


# 名字：撿到武器變「持〇腐屍」
func display_name() -> String:
	return "持%s腐屍" % kit().name if is_armed() else def.get("name", "腐屍")


# 劍盾腐屍舉盾：正面 arc 內打來的攻擊整下擋掉（含爆炸、技能），只被推一點點
func take_damage(amount: float, dir: Vector2, p_knockback: float, source_id: int, damage_type := &"phys") -> float:
	if shielding and can_be_hit() and not is_dead:
		var from := -dir if dir.length_squared() > 1e-6 else MathUtil.dir_from_angle(facing)
		if absf(angle_difference(facing, atan2(from.x, from.y))) <= kit().skill.arc / 2.0:
			knockback += dir * (p_knockback * kit().skill.block_push * knockback_mul / mass)
			world.emit_event("enemy:blocked", {"enemy_id": id, "pos": pos, "source_id": source_id})
			return -1.0
	return super(amount, dir, p_knockback, source_id, damage_type)


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
	shielding = false
	if is_armed() and world.is_authority:
		world.drop_item(armed_weapon.base, pos, armed_weapon)   # 武器原樣掉回地上
		armed_weapon = {}
	super(source_id)


# 範圍內最近的地上武器（沒有回傳 null）
func nearest_weapon_pickup(radius: float) -> ItemPickup:
	var best: ItemPickup = null
	var best_d := radius * radius
	for ip: Entity in world.pickups:
		if ip.is_removed or not (ip as ItemPickup).is_weapon() or not EnemyDefs.has_armed_kit((ip as ItemPickup).weapon.base):
			continue
		var d := ip.pos.distance_squared_to(pos)
		if d <= best_d:
			best_d = d
			best = ip
	return best


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
		if e.is_armed():
			ArmedMoves.chase(e, target, dt)   # 拿武器：用武器的招式（armed_moves.gd）
			return
		var pk: Dictionary = e.def.pickup
		if e.summoner_id == 0 and e.world.cooldowns.is_ready(e.cd("pickup")):
			e.world.cooldowns.start(e.cd("pickup"), pk.scan_interval)
			var ip := e.nearest_weapon_pickup(pk.radius)
			if ip != null:
				fsm.change(&"fetch", {"pickup_id": ip.id})
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
					"damage": l.damage * e.damage_mul, "knockback": 0.0, "blockable": l.blockable, "tier": &"light",
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
			Combat.apply_damage(e.world, e, p, {"damage": l.bite_damage * e.damage_mul, "knockback": 0.0, "blockable": false, "tier": &"none"})
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


# 撿武器：走到武器旁（reach 內）→ 彎腰 bend 秒 → 撿起；被打（進受擊硬直）就中斷，武器被別人撿走就回去追
class Fetch:
	func enter(_e: Zombie, data: Dictionary, _fsm: StateMachine) -> void:
		data.phase = &"walk"
		data.phase_time = 0.0

	func update(e: Zombie, dt: float, fsm: StateMachine) -> void:
		var pk: Dictionary = e.def.pickup
		var d := fsm.data
		d.phase_time += dt
		var ip := e.world.entities.get(d.pickup_id) as ItemPickup
		if ip == null or ip.is_removed:
			fsm.change(&"chase")
			return
		if d.phase == &"walk":
			if e.pos.distance_to(ip.pos) <= pk.reach + e.radius:
				d.phase = &"bend"
				d.phase_time = 0.0
				e.velocity = Vector2.ZERO
				return
			if d.phase_time >= pk.give_up:
				fsm.change(&"chase")
				return
			var aim := e.steer_point(ip.pos)
			e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), e.def.turn_speed * dt)
			e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed
			return
		e.velocity = Vector2.ZERO
		if d.phase_time >= pk.bend:
			e.arm(ip)
			fsm.change(&"chase")
