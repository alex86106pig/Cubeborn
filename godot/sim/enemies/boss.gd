# Boss（照搬網頁版 Boss.js）：霸體（不硬直、擊退大幅減免），招式有地面預警（畫面層依 anim 畫）
# 招式：重砸（近身範圍）、衝鋒（直線，撞牆會暈眩）、召喚小怪；血量低於一半進入狂暴
class_name Boss
extends Enemy

var is_enraged := false


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	var states := Enemy.base_states()
	states.erase(&"hurt")   # 霸體：受擊不進入硬直
	states[&"chase"] = Chase.new()
	states[&"slam"] = Slam.new()
	states[&"charge"] = Charge.new()
	states[&"summon"] = Summon.new()
	super(p_world, p_type, at, mul, states)


func is_boss() -> bool:
	return true


func on_added() -> void:
	var first: Dictionary = def.first_cooldowns
	for name: String in first:
		world.cooldowns.start(cd(name), first[name])


# 衝鋒中不跳（撞到石台就暈眩）
func _can_jump() -> bool:
	return not fsm.is_in(&"charge")


func enrage_mul(key: String) -> float:
	return def.enrage[key] if is_enraged else 1.0


func _anim_extra(a: Dictionary) -> void:
	a["enraged"] = is_enraged
	var d := fsm.data
	if fsm.is_in(&"charge"):
		a["phase"] = d.phase
		a["phase_time"] = d.phase_time
		a["origin"] = d.origin   # 衝鋒預警線的起點（世界座標）


func slam_impact() -> void:
	world.emit_event("sfx:cue", {"cue": "bossSlam"})
	var s: Dictionary = def.slam
	# 貼地的衝擊：腳底高於 HEIGHT.slam_height 的目標（跳起來）打不到
	var band := Vector2(height - Config.HEIGHT.reach_below, height + Config.HEIGHT.slam_height)
	Hitbox.strike(world, self, pos, facing, {"shape": &"circle", "radius": s.radius}, {
		"damage": s.damage * damage_mul, "knockback": s.knockback, "hit_stop": s.hit_stop, "band": band,
		"blockable": s.blockable, "color": def.hit_color,
	})
	world.emit_event("camera:shake", {"amount": s.shake, "duration": s.shake_duration})
	world.emit_event("fx:boss_slam", {"pos": pos, "height": height, "radius": s.radius})


func summon_minions() -> void:
	var s: Dictionary = def.summon
	var n: int = s.count
	var limit: Vector2 = world.half_extents - Vector2(s.edge_margin, s.edge_margin)
	for i in n:
		var a: float = facing + PI + (i - (n - 1) / 2.0) * s.spread
		var x := clampf(pos.x + sin(a) * s.distance, -limit.x, limit.x)
		var z := clampf(pos.y + cos(a) * s.distance, -limit.y, limit.y)
		# 落在牆或墓碑上就移到最近的空地（D1）
		world.spawner.spawn_at(world, &"grunt", world.nav.nearest_walkable(Vector2(x, z)))


func _on_damaged(_amount: int, _source_id: int) -> void:
	var e: Dictionary = def.enrage
	if not is_enraged and not is_dead and hp / max_hp <= e.hp_threshold:
		is_enraged = true
		world.emit_event("boss:enraged", {"boss_id": id})
		world.emit_event("camera:shake", {"amount": e.shake, "duration": e.shake_duration})


func _on_died(source_id: int) -> void:
	super(source_id)
	world.on_boss_defeated(self)


class Chase:
	func update(e: Boss, dt: float, fsm: StateMachine) -> void:
		var target := e.nearest_player()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		var dist := e.pos.distance_to(target.pos)
		var cds := e.world.cooldowns
		var d := e.def
		if fsm.time > d.decide_delay:
			if dist <= d.slam.trigger_distance and cds.is_ready(e.cd("slam")):
				fsm.change(&"slam")
				return
			if dist >= d.charge.min_distance and cds.is_ready(e.cd("charge")) and e.has_direct_path():
				fsm.change(&"charge")
				return
			if e.hp / e.max_hp <= d.summon.hp_threshold and cds.is_ready(e.cd("summon")):
				fsm.change(&"summon")
				return
		var aim := e.steer_point(target.pos)   # 被牆擋住時繞路（D1）
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), d.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * (e.speed * e.enrage_mul("speed_mul"))


# 重砸：舉起雙手 → 落地造成圓形範圍傷害
class Slam:
	func enter(e: Boss, data: Dictionary, _fsm: StateMachine) -> void:
		e.world.emit_event("sfx:cue", {"cue": "bossSlamWindup"})
		var s: Dictionary = e.def.slam
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("slam"), s.cooldown * e.enrage_mul("cooldown_mul"))
		data.has_hit = false

	func update(e: Boss, _dt: float, fsm: StateMachine) -> void:
		var s: Dictionary = e.def.slam
		if fsm.time < s.windup:
			return
		if not fsm.data.has_hit:
			fsm.data.has_hit = true
			e.slam_impact()
		if fsm.time >= s.windup + s.recovery:
			fsm.change(&"chase")


# 衝鋒：鎖定方向蓄力 → 直線衝刺；撞牆會暈眩（玩家的輸出時機）
class Charge:
	func enter(e: Boss, data: Dictionary, _fsm: StateMachine) -> void:
		e.world.emit_event("sfx:cue", {"cue": "bossChargeWindup"})
		var c: Dictionary = e.def.charge
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("charge"), c.cooldown * e.enrage_mul("cooldown_mul"))
		var target := e.nearest_player()
		if target != null:
			e.facing = MathUtil.angle_to(e.pos, target.pos)
		data.dir = MathUtil.dir_from_angle(e.facing)
		data.origin = e.pos
		data.phase = &"windup"
		data.phase_time = 0.0
		data.has_hit = false
		data.blocked = {}   # 已擋下這次衝鋒的玩家 id（之後不再判定，不會連續跳「格擋」）

	func update(e: Boss, dt: float, fsm: StateMachine) -> void:
		var c: Dictionary = e.def.charge
		var d := fsm.data
		d.phase_time += dt

		if d.phase == &"windup":
			if d.phase_time >= c.windup:
				d.phase = &"dash"
				d.phase_time = 0.0
			return

		if d.phase == &"dash":
			e.velocity = d.dir * c.speed
			# 衝鋒的判定：Boss 身體外擴 hit_reach 的圓，整段衝鋒只打中一次（無敵中碰到的目標之後仍可能被打中，同網頁版）
			# 擋下這次衝鋒的玩家之後不再判定
			if not d.has_hit:
				var events_before := e.world.events.size()
				var hits := Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"circle", "radius": e.radius + c.hit_reach}, {
					"damage": c.damage * e.damage_mul, "knockback": c.knockback,
					"shake": c.shake, "hit_stop": c.hit_stop, "blockable": c.blockable,
					"block_knockback_mul": c.block_knockback_mul, "color": e.def.hit_color,
				}, d.blocked.duplicate())
				d.has_hit = not hits.is_empty()
				for i in range(events_before, e.world.events.size()):
					if e.world.events[i].name == "player:blocked":
						d.blocked[e.world.events[i].player_id] = true   # 事件的 player_id 就是實體 id
			var limit: Vector2 = e.world.half_extents - Vector2(e.radius + c.wall_margin, e.radius + c.wall_margin)
			# 撞到場地邊緣，或前方是比腳下高的石台（牆、墓碑、高台；D1）
			var ahead: Vector2 = e.pos + d.dir * (e.radius + c.wall_margin)
			var blocked: bool = e.world.terrain.ground_at(ahead) > e.height + Config.HEIGHT.step
			if absf(e.pos.x) >= limit.x or absf(e.pos.y) >= limit.y or blocked:
				e.world.emit_event("sfx:cue", {"cue": "bossWallHit"})
				e.world.emit_event("camera:shake", {"amount": c.wall_shake, "duration": c.wall_shake_duration})
				e.world.emit_event("fx:boss_wall", {"pos": e.pos, "height": e.height})
				d.phase = &"stunned"
				d.phase_time = 0.0
				e.velocity = Vector2.ZERO
			elif d.phase_time >= c.duration:
				d.phase = &"recovery"
				d.phase_time = 0.0
				e.velocity = Vector2.ZERO
			return

		# 後搖或撞牆暈眩
		e.velocity = Vector2.ZERO
		var duration: float = c.wall_stun if d.phase == &"stunned" else c.recovery
		if d.phase_time >= duration:
			fsm.change(&"chase")


# 召喚：高舉雙手後在身邊召喚小怪
class Summon:
	func enter(e: Boss, data: Dictionary, _fsm: StateMachine) -> void:
		e.world.emit_event("sfx:cue", {"cue": "bossSummon"})
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("summon"), e.def.summon.cooldown * e.enrage_mul("cooldown_mul"))
		data.done = false

	func update(e: Boss, _dt: float, fsm: StateMachine) -> void:
		var s: Dictionary = e.def.summon
		if fsm.time >= s.windup and not fsm.data.done:
			fsm.data.done = true
			e.summon_minions()
		if fsm.time >= s.windup + s.recovery:
			fsm.change(&"chase")
