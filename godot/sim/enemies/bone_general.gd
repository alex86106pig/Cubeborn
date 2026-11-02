# 骸骨將軍（第 2 層 Boss，數值 Claude 暫定）：第一型態「重甲將軍」= 亡骸騎士的招式（砸地、衝鋒、召喚、直劈），不狂暴；
# 半血轉型態（設計方向「Boss 半血轉型態」）：transform 跪地無敵 transform.time 秒，盔甲碎片往外飛（有傷害、擋得住），
#   場上的骷髏屍體全部被吸過來 → form = 1「萬骨聚合體」：模型放大 colossus.scale、受到的傷害 × damage_taken、換一組招式：
#   骨刺陣（沿 6 個方向竄出骨刺，擋不住）、多臂橫掃（先低掃要跳、再高掃要滾或擋）、巨骨輪（同骨輪，撞牆暈 stun 秒）、
#   吞屍（radius 內的骷髏屍體與活著的骷髏都吸進去，每具回 heal_per 最大生命）
class_name BoneGeneral
extends Boss

var form := 0   # 0 = 重甲將軍、1 = 萬骨聚合體（動畫欄位 form，畫面層照 form_models 換模型）


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	super(p_world, p_type, at, mul, {
		&"patrol": Boss.Patrol.new(), &"chase": Boss.Chase.new(), &"slam": Boss.Slam.new(), &"charge": Boss.Charge.new(),
		&"summon": Boss.Summon.new(), &"cleave": Boss.Cleave.new(),
		&"transform": Transform.new(), &"colossus_chase": ColossusChase.new(), &"spikes": Spikes.new(), &"sweep": Sweep.new(),
		&"wheel": Wheel.new(), &"wheel_stun": WheelStun.new(), &"devour": Devour.new(),
	})


func on_added() -> void:
	var first: Dictionary = def.colossus.first_cooldowns if form > 0 else def.first_cooldowns
	for name: String in first:
		world.cooldowns.start(cd(name), first[name])


func _anim_extra(a: Dictionary) -> void:
	if form > 0:
		a["form"] = form
		var d := fsm.data
		if fsm.is_in(&"sweep") or fsm.is_in(&"wheel"):
			a["phase"] = d.phase
			a["phase_time"] = d.phase_time
	else:
		super(a)


# 半血就轉型態（取代亡骸騎士的狂暴）；轉型態中無敵（Transform 每步設 invuln_timer）
func _on_damaged(_amount: float, _source_id: int) -> void:
	aggro()
	if form == 0 and not is_dead and not fsm.is_in(&"transform") and hp / max_hp <= def.transform.hp_threshold:
		fsm.change(&"transform")


func resume() -> void:
	fsm.change(&"colossus_chase" if form > 0 else &"chase")


static func is_skeleton(e: Entity) -> bool:
	return e is Enemy and EnemyDefs.SKELETONS.has((e as Enemy).type) and (e as Enemy).ghost_of == 0


# 吸掉骷髏：屍體（死了還沒移除的）全部算；include_alive = 連活著的骷髏也吸（吞屍）。回傳吸了幾具
func absorb_skeletons(radius: float, include_alive: bool) -> int:
	var count := 0
	for e: Entity in world.enemies.duplicate():
		if e == self or not is_skeleton(e) or e.pos.distance_to(pos) > radius:
			continue
		if not e.is_dead and not include_alive:
			continue
		world.emit_event("boss:absorbed", {"boss_id": id, "from": e.pos, "height": e.ground_height, "pos": pos})
		(e as Enemy).no_death_effect = true
		e.remove()
		count += 1
	return count


func _become_colossus() -> void:
	var c: Dictionary = def.colossus
	form = 1
	set_stat_source(&"form", [[&"move_speed", Stats.MUL, c.move_speed / def.move_speed], [&"damage_taken", Stats.MUL, c.damage_taken]])
	world.emit_event("boss:transformed", {"boss_id": id, "form": form, "pos": pos})
	world.emit_event("sfx:cue", {"cue": "enrage", "pos": pos})
	on_added()
	resume()


func _crash(stun: bool) -> void:
	velocity = Vector2.ZERO
	world.emit_event("enemy:crashed", {"enemy_id": id, "pos": pos, "height": ground_height})
	world.emit_event("camera:shake", {"amount": def.colossus.wheel.shake, "duration": 0.3})
	world.emit_event("sfx:cue", {"cue": "hitHeavy", "pos": pos})
	if stun:
		fsm.change(&"wheel_stun")
	else:
		resume()


# 脫甲：跪地無敵；一進來就把盔甲碎片往外射、吸掉場上的骷髏屍體
class Transform:
	func enter(e: BoneGeneral, _data: Dictionary, _fsm: StateMachine) -> void:
		var tr: Dictionary = e.def.transform
		e.velocity = Vector2.ZERO
		e.invuln_timer = 0.1
		e.world.emit_event("boss:transforming", {"boss_id": e.id})
		e.world.emit_event("camera:shake", {"amount": tr.shake, "duration": tr.shake_duration})
		e.world.emit_event("sfx:cue", {"cue": "hitHeavy", "pos": e.pos})
		for i in int(tr.shards):
			var dir := MathUtil.dir_from_angle(e.facing + TAU * i / tr.shards)
			e.world.spawn_projectile(Projectile.new(e.world, {
				"owner": e, "pos": e.pos + dir * (e.radius + 0.3), "direction": dir, "speed": tr.shard_speed, "range": tr.shard_range,
				"radius": 0.3, "damage": tr.shard_damage * e.damage_mul, "knockback": tr.shard_knockback, "color": tr.shard_color,
				"altitude": e.height + 1.0, "blockable": true,
			}))
		e.absorb_skeletons(INF, false)

	func update(e: BoneGeneral, _dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.invuln_timer = 0.1
		if fsm.time >= e.def.transform.time:
			e._become_colossus()


class ColossusChase:
	func update(e: BoneGeneral, dt: float, fsm: StateMachine) -> void:
		var target := e.nearest_player()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		var c: Dictionary = e.def.colossus
		var dist := e.pos.distance_to(target.pos)
		var cds := e.world.cooldowns
		if fsm.time > c.decide_delay:
			if dist <= c.sweep.trigger_distance and cds.is_ready(e.cd("sweep")):
				fsm.change(&"sweep")
				return
			if cds.is_ready(e.cd("devour")) and _bodies(e) >= c.devour.min_bodies:
				fsm.change(&"devour")
				return
			if dist >= c.wheel.min_distance and cds.is_ready(e.cd("wheel")) and e.has_direct_path():
				fsm.change(&"wheel")
				return
			if cds.is_ready(e.cd("spikes")):
				fsm.change(&"spikes")
				return
		var aim := e.steer_point(target.pos)
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), c.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed

	# 吞得到的骷髏（屍體 + 活的）
	func _bodies(e: BoneGeneral) -> int:
		var n := 0
		for o: Entity in e.world.enemies:
			if o != e and BoneGeneral.is_skeleton(o) and o.pos.distance_to(e.pos) <= e.def.colossus.devour.radius:
				n += 1
		return n


# 骨刺陣：windup 時地面沿 lines 個方向隆起（fx:spike_warn）；之後每條線從 start 往外每 step 一根，第 k 根在 windup + k × delay_per 竄出
class Spikes:
	func enter(e: BoneGeneral, data: Dictionary, _fsm: StateMachine) -> void:
		var s: Dictionary = e.def.colossus.spikes
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("spikes"), s.cooldown)
		var target := e.nearest_player()
		if target != null:
			e.facing = MathUtil.angle_to(e.pos, target.pos)
		data.fired = 0
		data.hit = {}
		data.dirs = []
		for i in int(s.lines):
			(data.dirs as Array).append(MathUtil.dir_from_angle(e.facing + TAU * i / s.lines))
		e.world.emit_event("fx:spike_warn", {"pos": e.pos, "height": e.ground_height, "facing": e.facing, "lines": s.lines,
			"start": s.start, "length": s.length, "life": s.windup})

	func update(e: BoneGeneral, _dt: float, fsm: StateMachine) -> void:
		var s: Dictionary = e.def.colossus.spikes
		var d := fsm.data
		e.velocity = Vector2.ZERO
		var per_line := int(floor((s.length - s.start) / s.step)) + 1
		while d.fired < per_line and fsm.time >= s.windup + d.fired * s.delay_per:
			var dist: float = s.start + d.fired * s.step
			for dir: Vector2 in d.dirs:
				var at: Vector2 = e.pos + dir * dist
				if e.world.terrain.ground_at(at) > e.ground_height + Config.NAV.climb_height:
					continue   # 牆裡不竄
				var band := Vector2(e.world.terrain.ground_at(at) - Config.HEIGHT.reach_below, e.world.terrain.ground_at(at) + Config.HEIGHT.slam_height)
				var hits := Hitbox.strike(e.world, e, at, e.facing, {"shape": &"circle", "radius": s.radius}, {
					"damage": s.damage * e.damage_mul, "knockback": s.knockback, "origin": at, "band": band, "blockable": false,
					"color": e.def.hit_color,
				}, d.hit)
				for t in hits:
					if t is Player:
						(t as Player).vz = maxf((t as Player).vz, s.knockup)
				e.world.emit_event("fx:bone_spike", {"pos": at, "height": e.world.terrain.ground_at(at)})
			d.fired += 1
		if fsm.time >= s.windup + per_line * s.delay_per + s.recovery:
			e.resume()


# 多臂橫掃：windup → low（低掃一圈，max_air 以上躲得過，擋不住）→ gap 秒後 high（高掃一圈，擋得住）→ recovery
class Sweep:
	func enter(e: BoneGeneral, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("sweep"), e.def.colossus.sweep.cooldown)
		data.phase = &"windup"
		data.phase_time = 0.0
		data.low_hit = {}
		data.high_hit = {}

	func update(e: BoneGeneral, dt: float, fsm: StateMachine) -> void:
		var s: Dictionary = e.def.colossus.sweep
		var d := fsm.data
		d.phase_time += dt
		e.velocity = Vector2.ZERO
		var shape := {"shape": &"circle", "radius": s.range}
		match d.phase:
			&"windup":
				if d.phase_time >= s.windup:
					d.phase = &"low"
					d.phase_time = 0.0
					Hitbox.strike(e.world, e, e.pos, e.facing, shape, {"damage": s.low_damage * e.damage_mul, "knockback": s.knockback,
						"max_air": s.low_max_air, "blockable": false, "color": e.def.hit_color}, d.low_hit)
					e.world.emit_event("fx:sweep", {"pos": e.pos, "height": e.ground_height, "radius": s.range, "low": true})
			&"low":
				if d.phase_time >= s.gap:
					d.phase = &"high"
					d.phase_time = 0.0
					Hitbox.strike(e.world, e, e.pos, e.facing, shape, {"damage": s.high_damage * e.damage_mul, "knockback": s.knockback,
						"blockable": true, "color": e.def.hit_color}, d.high_hit)
					e.world.emit_event("fx:sweep", {"pos": e.pos, "height": e.ground_height, "radius": s.range, "low": false})
			&"high":
				if d.phase_time >= s.recovery:
					e.resume()


# 巨骨輪：windup 蜷成球（轉向目標）→ roll 追著目標滾（同骨輪：撞到的各打一次、往側面撞開），撞牆或被擋下 → wheel_stun
class Wheel:
	func enter(e: BoneGeneral, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("wheel"), e.def.colossus.wheel.cooldown)
		data.phase = &"windup"
		data.phase_time = 0.0
		data.hit = {}

	func update(e: BoneGeneral, dt: float, fsm: StateMachine) -> void:
		var w: Dictionary = e.def.colossus.wheel
		var d := fsm.data
		d.phase_time += dt
		var target := e.nearest_player()
		if d.phase == &"windup":
			e.velocity = Vector2.ZERO
			if target != null:
				e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), 4.0 * dt)
			if d.phase_time >= w.windup:
				d.phase = &"roll"
				d.phase_time = 0.0
			return
		if target != null:
			e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), w.turn_rate * dt)
		var dir := MathUtil.dir_from_angle(e.facing)
		var ahead := e.pos + dir * (e.radius + 0.05)
		var lim := e.world.half_extents - Vector2(e.radius, e.radius)
		if absf(ahead.x) > lim.x or absf(ahead.y) > lim.y or e.world.terrain.ground_at(ahead) > e.height + Config.HEIGHT.step:
			e._crash(true)
			return
		e.velocity = dir * w.speed
		var shape := {"shape": &"circle", "radius": e.radius + w.hit_reach}
		var events_before := e.world.events.size()
		for t in Hitbox.query(e.world, e.team, e.pos, e.facing, shape, e.id):
			if d.hit.has(t.id):
				continue
			d.hit[t.id] = true
			var side := 1.0 if dir.cross(t.pos - e.pos) >= 0.0 else -1.0
			var push: Vector2 = (Vector2(-dir.y, dir.x) * side * w.side_push + dir * (1.0 - w.side_push)).normalized()
			Combat.apply_damage(e.world, e, t, {"damage": w.damage * e.damage_mul, "knockback": w.knockback, "blockable": w.blockable,
				"push_dir": push, "color": e.def.hit_color})
		for i in range(events_before, e.world.events.size()):
			if e.world.events[i].name == "player:blocked":
				e._crash(true)
				return
		if d.phase_time >= w.max_time:
			e._crash(false)


class WheelStun:
	func enter(e: BoneGeneral, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO

	func update(e: BoneGeneral, _dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		if fsm.time >= e.def.colossus.wheel.stun:
			e.resume()


# 吞屍：胸腔打開（windup）→ 吸進 radius 內的骷髏（屍體與活的），每具回 heal_per 最大生命 → recovery
class Devour:
	func enter(e: BoneGeneral, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("devour"), e.def.colossus.devour.cooldown)
		data.done = false

	func update(e: BoneGeneral, _dt: float, fsm: StateMachine) -> void:
		var v: Dictionary = e.def.colossus.devour
		e.velocity = Vector2.ZERO
		if not fsm.data.done and fsm.time >= v.windup:
			fsm.data.done = true
			var n := e.absorb_skeletons(v.radius, true)
			if n > 0:
				e.hp = minf(e.max_hp, e.hp + e.max_hp * v.heal_per * n)
				e.world.emit_event("boss:devoured", {"boss_id": e.id, "count": n, "pos": e.pos})
		if fsm.time >= v.windup + v.recovery:
			e.resume()
