# 膨脹屍（第 1 層，怪物圖鑑）：走近後先撲抱一次（hug：挺肚子張手 → 往前撲），撲中抱住玩家並開始脹（swell，較短）；
# 沒撲中（或已經撲過）就走到 burst.trigger_distance 內停下脹大 → 自爆死亡。抱住時玩家同暈眩，按翻滾掙脫（膨脹屍照樣脹完炸）
# 撲抱被盾擋下 → 倒地 hug.blocked_fall 秒。脹大中是霸體（被打不硬直、抱住不鬆手）
# 被打死的話 burst.death_delay 秒後照樣炸。爆炸擋不住、擊倒並彈起，玩家與其他怪都炸得到（Boss 只推開），
# 炸完原地留下腐氣（GroundZones，hits_all：玩家與怪都會受持續傷害）。自爆的不給靈魂（不是被玩家打死的）
class_name Bloater
extends Enemy

const GRAB_MARGIN := 0.1

var has_burst := false
var hugged := false    # 撲抱只用一次
var held_id := 0       # 抱住的玩家 id（0 = 沒抱住）


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	var states := Enemy.base_states()
	states[&"chase"] = Chase.new()
	states[&"hug"] = Hug.new()
	states[&"fallen"] = Fallen.new()
	states[&"swell"] = Swell.new()
	states[&"dead"] = BloaterDead.new()
	super(p_world, p_type, at, mul, states)


func _anim_extra(a: Dictionary) -> void:
	if has_burst:
		a["burst"] = true
	if fsm.is_in(&"hug"):
		a["phase"] = fsm.data.phase
		a["phase_time"] = fsm.data.phase_time
	if fsm.is_in(&"swell"):
		a["swell_time"] = fsm.data.time   # 抱住時脹得比較快（畫面的脹大進度照這個）
	if held_id != 0:
		a["hugging"] = true


func _can_jump() -> bool:
	return fsm.is_in(&"chase")


# 脹大中是霸體：照樣扣血，但不進受擊硬直（一定會炸）
func _on_damaged(amount: float, source_id: int) -> void:
	suppress_stagger = suppress_stagger or fsm.is_in(&"swell")
	super(amount, source_id)


func _on_died(source_id: int) -> void:
	release()
	super(source_id)


func release() -> void:
	var p := world.entities.get(held_id) as Player
	if p != null and p.grabbed_by == id:
		p.release_grab()
	held_id = 0


# 還抱著（玩家沒掙脫、沒倒下）
func is_holding() -> bool:
	var p := world.entities.get(held_id) as Player
	return p != null and p.grabbed_by == id and not p.is_dead and not p.is_downed


# 爆炸：半徑內的玩家與其他怪都受傷（不分隊伍），擋不住、擊倒並彈起（Boss 只推開）；抱著的玩家多受 hold_bonus；接著留下腐氣
func burst() -> void:
	if has_burst:
		return
	has_burst = true
	var b: Dictionary = def.burst
	var held := held_id if is_holding() else 0
	release()
	var hit := {
		"damage": b.damage * damage_mul, "knockback": b.knockback, "origin": pos, "is_heavy": true, "blockable": false, "tier": &"knockdown",
		"band": Vector2(ground_height - Config.HEIGHT.reach_below, ground_height + Config.HEIGHT.explosion_height), "color": b.color,
	}
	world.record_hitbox({"shape": {"shape": &"circle", "radius": b.radius}, "origin": pos, "facing": facing, "band": hit.band, "team": &"all"})
	var targets: Array[Entity] = []
	targets.append_array(world.player_list)
	targets.append_array(world.enemies)
	for t in targets:
		if t == self or t.is_dead or t.pos.distance_to(pos) > b.radius + t.radius:
			continue
		var h := hit
		if t.id == held:
			h = hit.duplicate()
			h.damage = (b.damage + b.hold_bonus) * damage_mul
		if not Combat.apply_damage(world, self, t, h):
			continue
		if t is Player:
			(t as Player).knock_up(b.knockup)
		elif t is Enemy and not (t as Enemy).is_boss() and t.is_grounded():
			t.vz = b.knockup
	world.emit_event("sfx:cue", {"cue": "explosion", "pos": pos})
	world.emit_event("fx:explosion", {"pos": pos, "height": ground_height, "radius": b.radius, "color": b.color})
	var g: Dictionary = def.gas
	GroundZones.add(world, {
		"pos": pos, "radius": g.radius, "duration": g.duration, "owner_id": id, "color": g.color,
		"damage_per_sec": g.damage_per_sec * damage_mul, "damage_type": &"poison", "hits_all": true, "visual": &"gas",
	})


class Chase:
	func update(e: Bloater, dt: float, fsm: StateMachine) -> void:
		var target: Entity = e.nearest_target()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		var dist := e.pos.distance_to(target.pos)
		if not e.hugged and dist <= e.def.hug.trigger_distance:
			fsm.change(&"hug")
			return
		if dist <= e.def.burst.trigger_distance:
			fsm.change(&"swell", {"time": e.def.burst.swell_time})
			return
		var aim := e.steer_point(target.pos)
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), e.def.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed


# 撲抱：windup（挺肚子、張手，前 track 比例轉向）→ dash（往前撲 distance，只判定到第一個玩家）→ recovery
# 撲中（沒擋下、沒在翻滾）→ 抱住並開始脹（swell 時間 burst.hold_swell_time）；擋下 → 倒地
class Hug:
	func enter(e: Bloater, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.hugged = true
		data.phase = &"windup"
		data.phase_time = 0.0

	func update(e: Bloater, dt: float, fsm: StateMachine) -> void:
		var h: Dictionary = e.def.hug
		var d := fsm.data
		d.phase_time += dt
		e.velocity = Vector2.ZERO
		if d.phase == &"windup":
			var target: Entity = e.nearest_target()
			if d.phase_time < h.windup * h.track and target != null:
				e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * dt)
			if d.phase_time >= h.windup:
				d.phase = &"dash"
				d.phase_time = 0.0
				d.dir = MathUtil.dir_from_angle(e.facing)
			return
		if d.phase == &"dash":
			e.velocity = d.dir * (h.distance / h.duration)
			var band := Combat.body_band(e)
			e.world.record_hitbox({"shape": {"shape": &"circle", "radius": e.radius + h.hit_reach}, "origin": e.pos, "facing": e.facing, "band": band, "team": e.team})
			for t in Hitbox.query(e.world, e.team, e.pos, e.facing, {"shape": &"circle", "radius": e.radius + h.hit_reach}, e.id):
				if not (t is Player) or not t.can_be_hit() or not t.overlaps_height(band.x, band.y):
					continue
				var p := t as Player
				if p.try_block(e.pos, {"blockable": true}):
					fsm.change(&"fallen")
					return
				e.held_id = p.id
				p.stun(e.def.burst.hold_swell_time + GRAB_MARGIN, e.id)   # 放開由膨脹屍決定（炸的時候放），暈眩不先到期
				fsm.change(&"swell", {"time": e.def.burst.hold_swell_time})
				return
			if d.phase_time >= h.duration:
				d.phase = &"recovery"
				d.phase_time = 0.0
			return
		if d.phase_time >= h.recovery:
			fsm.change(&"chase")


# 撲抱被盾擋下：倒地 blocked_fall 秒
class Fallen:
	func enter(e: Bloater, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO

	func update(e: Bloater, _dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		if fsm.time >= e.def.hug.blocked_fall:
			fsm.change(&"chase")


# 脹大 data.time 秒（站定；抱住時面向玩家）→ 自爆：先炸再死（自己不算被炸死，不給靈魂）
class Swell:
	func enter(e: Bloater, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO

	func update(e: Bloater, _dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		if e.held_id != 0 and not e.is_holding():
			e.held_id = 0   # 被翻滾掙脫：照樣脹完炸
		if fsm.time >= fsm.data.time:
			e.no_souls = true
			e.burst()
			e.die(e.id)


# 死亡：被打死的還沒炸 → death_delay 秒後炸；屍體留到腐氣散掉（腐氣的傷害來源是自己）
class BloaterDead:
	func enter(e: Bloater, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO

	func update(e: Bloater, _dt: float, fsm: StateMachine) -> void:
		if not e.has_burst and not e.no_death_effect and not e.world.is_over and fsm.time >= e.def.burst.death_delay:
			e.burst()
		if fsm.time >= e.def.corpse_time:
			e.remove()
