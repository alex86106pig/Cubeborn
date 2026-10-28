# Boss（原本照搬網頁版 Boss.js，v0.27.0 起使用者要求加強）：霸體（不硬直、擊退大幅減免），招式有地面預警（畫面層依 anim 畫）
# 招式：直劈（沒有預警，看舉劍動作）、砸地（紅圈一圈圈往外擴散，擊飛＋緩速）、衝鋒（撞到暈眩，撞牆自己暈眩）、召喚骷髏戰士 / 弓手
# 狂暴（血量一半以下）：全部更快；衝鋒連續 3 次；召喚完的骷髏戰士衝撞一次；砸地不管多遠都放（玩家腳下預警 → 瞬移過去 → 砸）
class_name Boss
extends Enemy

var is_enraged := false
var patrol_rect := Rect2()   # 巡邏範圍（世界座標；空的 = 原地附近）


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	var states := Enemy.base_states()
	states.erase(&"hurt")   # 霸體：受擊不進入硬直
	states[&"patrol"] = Patrol.new()
	states[&"chase"] = Chase.new()
	states[&"slam"] = Slam.new()
	states[&"charge"] = Charge.new()
	states[&"summon"] = Summon.new()
	states[&"cleave"] = Cleave.new()
	super(p_world, p_type, at, mul, states)


func on_added() -> void:
	var first: Dictionary = def.first_cooldowns
	for name: String in first:
		world.cooldowns.start(cd(name), first[name])


# 衝鋒中不跳（撞到石台就暈眩）
func _can_jump() -> bool:
	return not fsm.is_in(&"charge")


func enrage_mul(key: String) -> float:
	return def.enrage[key] if is_enraged else 1.0


# 招式的預備秒數（狂暴時 × windup_mul）
func windup_of(move: Dictionary) -> float:
	return move.windup * enrage_mul("windup_mul")


func _anim_extra(a: Dictionary) -> void:
	a["enraged"] = is_enraged
	var d := fsm.data
	if fsm.is_in(&"charge"):
		a["phase"] = d.phase
		a["phase_time"] = d.phase_time
		a["origin"] = d.origin   # 衝鋒預警線的起點（世界座標）
		a["windup"] = d.windup
	elif fsm.is_in(&"slam"):
		a["phase"] = d.phase
		a["phase_time"] = d.phase_time
		a["windup"] = d.windup
	elif fsm.is_in(&"cleave"):
		a["windup"] = d.windup


# 砸地的第 i 圈：打到這一圈範圍內（上一圈半徑 ~ 這一圈半徑）、這次砸地還沒被打過的目標
func slam_ring(i: int, hit: Dictionary) -> void:
	var s: Dictionary = def.slam
	var rings: Array = s.rings
	var outer: float = rings[i]
	var inner: float = rings[i - 1] if i > 0 else 0.0
	if i == 0:
		world.emit_event("sfx:cue", {"cue": "bossSlam", "pos": pos})
		world.emit_event("camera:shake", {"amount": s.shake, "duration": s.shake_duration})
	# 內圈裡面的目標這一圈不打（已經過去的波）
	var skip := hit.duplicate()
	if inner > 0.0:
		for t in Hitbox.query(world, team, pos, facing, {"shape": &"circle", "radius": inner}, id):
			if pos.distance_to(t.pos) < inner:
				skip[t.id] = true
	# 貼地的衝擊（v0.23.0）：範圍內站在任何地面上（含旁邊的高台）的目標都打得到；跳起來（腳底離自己腳下的地面超過 slam_height）躲得過
	var reach: float = Config.NAV.climb_height
	var band := Vector2(height - reach - Config.HEIGHT.reach_below, height + reach + Config.HEIGHT.slam_height)
	var hits := Hitbox.strike(world, self, pos, facing, {"shape": &"circle", "radius": outer}, {
		"damage": s.damage * damage_mul, "knockback": s.knockback, "hit_stop": s.hit_stop, "band": band,
		"max_air": Config.HEIGHT.slam_height, "blockable": s.blockable, "color": def.hit_color,
	}, skip)
	for t in hits:
		hit[t.id] = true
		if t is Player:
			(t as Player).knock_up(s.knockup)
			(t as Player).add_buff(&"boss_slow", s.slow_time, {"stats": [[&"move_speed", Stats.MUL, s.slow_mul]]})
	world.emit_event("fx:boss_slam", {"pos": pos, "height": height, "radius": outer})


# 召喚：每隻隨機是骷髏戰士或弓手；狂暴時召喚出來的骷髏戰士爬出來後衝撞一次
func summon_minions() -> void:
	var s: Dictionary = def.summon
	var n: int = s.count
	var limit: Vector2 = world.half_extents - Vector2(s.edge_margin, s.edge_margin)
	for i in n:
		var type := &"archer" if world.rng.randf() < s.archer_chance else &"grunt"
		var a: float = facing + PI + (i - (n - 1) / 2.0) * s.spread
		var x := clampf(pos.x + sin(a) * s.distance, -limit.x, limit.x)
		var z := clampf(pos.y + cos(a) * s.distance, -limit.y, limit.y)
		# 落在牆或墓碑上就移到最近的空地（D1）
		var e := world.spawner.spawn_at(world, type, world.nav_for(EnemyDefs.ENEMIES[type].radius).nearest_walkable(Vector2(x, z)))
		e.no_souls = true
		if is_enraged and e is MeleeEnemy:
			(e as MeleeEnemy).pending_rush = true


func is_patrolling() -> bool:
	return fsm.is_in(&"patrol")


# 巡邏中發現玩家：開始追，招式冷卻從這時起算（和出生時一樣給玩家一點時間）
func aggro() -> void:
	if not is_patrolling() or is_dead:
		return
	on_added()
	fsm.change(&"chase")
	world.emit_event("boss:aggro", {"boss_id": id, "pos": pos})


# 看得到的玩家：前方扇形內或貼得很近，而且沒被牆擋住
func sees_player() -> bool:
	var s: Dictionary = def.patrol
	var nav := world.nav_for(radius)
	for p in world.player_list:
		if not p.is_targetable():
			continue
		var d := pos.distance_to(p.pos)
		if d > s.sight_radius:
			continue
		var half_arc: float = s.sight_arc * 0.5
		var in_arc := absf(angle_difference(facing, MathUtil.angle_to(pos, p.pos))) <= half_arc
		if (in_arc or d <= s.notice_radius) and nav.has_los(pos, p.pos):
			return true
	return false


func _on_damaged(_amount: float, _source_id: int) -> void:
	aggro()
	var e: Dictionary = def.enrage
	if not is_enraged and not is_dead and hp / max_hp <= e.hp_threshold:
		is_enraged = true
		world.emit_event("boss:enraged", {"boss_id": id})
		world.emit_event("camera:shake", {"amount": e.shake, "duration": e.shake_duration})


func _on_died(source_id: int) -> void:
	super(source_id)
	world.on_boss_defeated(self)


# 巡邏：在 patrol_rect 裡挑一個走得到的點慢慢走過去，到了停 pause 秒再挑下一個；看到玩家就 aggro
class Patrol:
	func enter(e: Boss, data: Dictionary, _fsm: StateMachine) -> void:
		data.wait = e.world.rng.randf_range(e.def.patrol.pause[0], e.def.patrol.pause[1])
		data.goal = e.pos

	func update(e: Boss, dt: float, fsm: StateMachine) -> void:
		if e.sees_player():
			e.aggro()
			return
		var s: Dictionary = e.def.patrol
		var data := fsm.data
		if data.wait > 0.0:
			data.wait -= dt
			e.velocity = Vector2.ZERO
			if data.wait <= 0.0:
				data.goal = _pick_goal(e)
			return
		if e.pos.distance_to(data.goal) < 0.6:
			data.wait = e.world.rng.randf_range(s.pause[0], s.pause[1])
			e.velocity = Vector2.ZERO
			return
		var aim := e.steer_point(data.goal)
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), e.def.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * (e.speed * s.speed_mul)

	func _pick_goal(e: Boss) -> Vector2:
		var nav := e.world.nav_for(e.radius)
		var r := e.patrol_rect if e.patrol_rect.has_area() else Rect2(e.pos - Vector2(4.0, 4.0), Vector2(8.0, 8.0))
		for attempt in 8:
			var c := r.position + Vector2(e.world.rng.randf(), e.world.rng.randf()) * r.size
			if nav.is_walkable(c) and nav.same_region(c, e.pos):
				return c
		return e.pos


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
			if dist <= d.cleave.trigger_distance and cds.is_ready(e.cd("cleave")):
				fsm.change(&"cleave")
				return
			# 狂暴時砸地不管多遠都放（瞬移過去）
			if (dist <= d.slam.trigger_distance or e.is_enraged) and cds.is_ready(e.cd("slam")):
				fsm.change(&"slam", {"target": target.pos if dist > d.slam.trigger_distance else Vector2.INF})
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


# 直劈：舉劍（前半段用一半的轉身速度跟著玩家、之後鎖定）→ 往前劈下細長扇形 → 收招；沒有地面預警
class Cleave:
	func enter(e: Boss, data: Dictionary, _fsm: StateMachine) -> void:
		var c: Dictionary = e.def.cleave
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("cleave"), c.cooldown * e.enrage_mul("cooldown_mul"))
		data.windup = e.windup_of(c)
		data.hit = {}

	func update(e: Boss, dt: float, fsm: StateMachine) -> void:
		var c: Dictionary = e.def.cleave
		var t := fsm.time
		var windup: float = fsm.data.windup
		e.velocity = Vector2.ZERO
		var target := e.nearest_player()
		if t < windup * c.track and target != null:
			e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * c.track_turn_mul * dt)
		if t >= windup and t < windup + c.active:
			Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"sector", "range": c.range, "arc": c.arc}, {
				"damage": c.damage * e.damage_mul, "knockback": c.knockback, "hit_stop": c.hit_stop,
				"shake": c.shake, "blockable": c.blockable, "is_heavy": true, "color": e.def.hit_color,
			}, fsm.data.hit)
		if t >= windup + c.active + c.recovery:
			fsm.change(&"chase")


# 砸地：（狂暴且離得遠時：玩家腳下預警 teleport_warn 秒 → 瞬移過去）→ 舉起雙手 → 落地，紅圈依序往外擴散
class Slam:
	func enter(e: Boss, data: Dictionary, _fsm: StateMachine) -> void:
		var s: Dictionary = e.def.slam
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("slam"), s.cooldown * e.enrage_mul("cooldown_mul"))
		data.hit = {}
		data.next_ring = 0
		data.phase_time = 0.0
		var target: Vector2 = data.get("target", Vector2.INF)
		if target != Vector2.INF:
			data.phase = &"warn"
			data.target = e.world.nav_for(e.radius).nearest_walkable(target)
			data.windup = e.def.enrage.teleport_windup
			e.world.emit_event("fx:telegraph", {"pos": data.target, "height": e.world.terrain.ground_at(data.target),
				"radius": e.radius + 1.0, "color": Color("b36bff"), "life": e.def.enrage.teleport_warn})
			e.world.emit_event("sfx:cue", {"cue": "bossChargeWindup", "pos": e.pos})
		else:
			data.phase = &"windup"
			data.windup = e.windup_of(s)
			e.world.emit_event("sfx:cue", {"cue": "bossSlamWindup", "pos": e.pos})

	func update(e: Boss, dt: float, fsm: StateMachine) -> void:
		var s: Dictionary = e.def.slam
		var d := fsm.data
		d.phase_time += dt
		e.velocity = Vector2.ZERO
		if d.phase == &"warn":
			if d.phase_time >= e.def.enrage.teleport_warn:
				e.world.emit_event("fx:boss_teleport", {"pos": e.pos, "height": e.height, "to": d.target})
				e.pos = d.target
				e.prev_pos = d.target   # 瞬移：畫面不要補間滑過去
				e.height = e.world.terrain.ground_at(d.target)
				e.world.emit_event("sfx:cue", {"cue": "bossSlamWindup", "pos": e.pos})
				d.phase = &"windup"
				d.phase_time = 0.0
			return
		if d.phase == &"windup":
			if d.phase_time >= d.windup:
				d.phase = &"impact"
				d.phase_time = 0.0
			return
		var rings: Array = s.rings
		while d.next_ring < rings.size() and d.phase_time >= d.next_ring * s.ring_delay - 1e-6:
			e.slam_ring(d.next_ring, d.hit)
			d.next_ring += 1
		if d.phase_time >= (rings.size() - 1) * s.ring_delay + s.recovery:
			fsm.change(&"chase")


# 衝鋒：鎖定方向蓄力 → 直線衝刺；撞到的玩家暈眩；撞牆自己暈眩（玩家的輸出時機）。狂暴時連衝 charge_count 次（中間重新瞄準）
class Charge:
	func enter(e: Boss, data: Dictionary, _fsm: StateMachine) -> void:
		var c: Dictionary = e.def.charge
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("charge"), c.cooldown * e.enrage_mul("cooldown_mul"))
		data.remaining = int(e.def.enrage.charge_count) if e.is_enraged else 1
		_aim(e, data, e.windup_of(c))

	static func _aim(e: Boss, data: Dictionary, windup: float) -> void:
		e.world.emit_event("sfx:cue", {"cue": "bossChargeWindup", "pos": e.pos})
		var target := e.nearest_player()
		if target != null:
			e.facing = MathUtil.angle_to(e.pos, target.pos)
		data.dir = MathUtil.dir_from_angle(e.facing)
		data.origin = e.pos
		data.phase = &"windup"
		data.phase_time = 0.0
		data.windup = windup
		data.has_hit = false
		data.blocked = {}   # 已擋下這次衝鋒的玩家 id（之後不再判定，不會連續跳「格擋」）
		data.remaining -= 1

	func update(e: Boss, dt: float, fsm: StateMachine) -> void:
		var c: Dictionary = e.def.charge
		var d := fsm.data
		d.phase_time += dt

		if d.phase == &"windup":
			if d.phase_time >= d.windup:
				d.phase = &"dash"
				d.phase_time = 0.0
			return

		if d.phase == &"dash":
			e.velocity = d.dir * c.speed
			# 衝鋒的判定：Boss 身體外擴 hit_reach 的圓，每次衝刺只打中一次；擋下的玩家之後不再判定，沒擋下的會暈眩
			if not d.has_hit:
				var events_before := e.world.events.size()
				var hits := Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"circle", "radius": e.radius + c.hit_reach}, {
					"damage": c.damage * e.damage_mul, "knockback": c.knockback,
					"shake": c.shake, "hit_stop": c.hit_stop, "blockable": c.blockable,
					"block_knockback_mul": c.block_knockback_mul, "color": e.def.hit_color,
				}, d.blocked.duplicate())
				d.has_hit = not hits.is_empty()
				for t in hits:
					if t is Player:
						(t as Player).stun(c.stun)
				for i in range(events_before, e.world.events.size()):
					if e.world.events[i].name == "player:blocked":
						d.blocked[e.world.events[i].player_id] = true   # 事件的 player_id 就是實體 id
			var limit: Vector2 = e.world.half_extents - Vector2(e.radius + c.wall_margin, e.radius + c.wall_margin)
			# 前方的高台（高低差 ≤ climb_height）衝鋒中直接跳上去、不停下（v0.23.0）；更高的牆與墓碑、場地邊緣才撞停暈眩
			var ahead: Vector2 = e.pos + d.dir * (e.radius + c.wall_margin)
			var top := e.world.terrain.ground_at(ahead)
			var rise := top - e.ground_height
			var hop: bool = rise > Config.HEIGHT.step and rise <= Config.NAV.climb_height
			if hop and e.is_grounded():
				e.vz = 4.0 * Config.JUMP.height / Config.JUMP.air_time
			var blocked: bool = top > e.height + Config.HEIGHT.step and not hop
			if absf(e.pos.x) >= limit.x or absf(e.pos.y) >= limit.y or blocked:
				e.world.emit_event("sfx:cue", {"cue": "bossWallHit", "pos": e.pos})
				e.world.emit_event("camera:shake", {"amount": c.wall_shake, "duration": c.wall_shake_duration})
				e.world.emit_event("fx:boss_wall", {"pos": e.pos, "height": e.height})
				d.phase = &"stunned"
				d.phase_time = 0.0
				e.velocity = Vector2.ZERO
			elif d.phase_time >= c.duration:
				e.velocity = Vector2.ZERO
				if d.remaining > 0:
					_aim(e, d, e.def.enrage.charge_rewindup)   # 狂暴連衝：重新瞄準再衝
				else:
					d.phase = &"recovery"
					d.phase_time = 0.0
			return

		# 後搖或撞牆暈眩
		e.velocity = Vector2.ZERO
		var duration: float = c.wall_stun if d.phase == &"stunned" else c.recovery
		if d.phase_time >= duration:
			fsm.change(&"chase")


# 召喚：高舉雙手後在身邊召喚小怪
class Summon:
	func enter(e: Boss, data: Dictionary, _fsm: StateMachine) -> void:
		e.world.emit_event("sfx:cue", {"cue": "bossSummon", "pos": e.pos})
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
