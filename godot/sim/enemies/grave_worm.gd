# 噬墓巨蟲（第 3 層 Boss，數值 Claude 暫定）：大部分時間鑽在地底（打不到、不能當目標、不擋路），冒出來 surface.time 秒才打得到。
# 循環：surface（冒在地面、紮在原地出招）→ dive 鑽下去 → tunnel 在地底追 track_time 秒（地面一路冒土）→ lurk 停下、地面鼓起 warn 秒
#   → 衝出地面（半徑 radius、擊飛、擋不住）→ surface
# 地面上的招式：噴酸（往 lobs 個方向吐酸，落地留酸池）、吞噬（張嘴把前方的人吸過來，吸到嘴邊咬一口）、產卵（留幾顆卵，hatch_time 秒後孵屍甲蟲）
# 巡邏時在地面上慢慢爬（Boss.Patrol），發現玩家後第一輪直接從地面開始
class_name GraveWorm
extends Boss

var _surface_left := 0.0   # 這次冒出來還剩幾秒（出招中照樣倒數；到 0 而且回到 surface 才鑽下去）
var _lobs: Array[Dictionary] = []   # 飛在空中的酸液 { at, left }
var _eggs: Array[Dictionary] = []   # 還沒孵的卵 { at, left }


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	super(p_world, p_type, at, mul, {
		&"patrol": Boss.Patrol.new(), &"chase": Surface.new(), &"dive": Dive.new(), &"tunnel": Tunnel.new(), &"lurk": Lurk.new(),
		&"acid": Acid.new(), &"devour": Devour.new(), &"eggs": Eggs.new(),
	})
	_surface_left = def.surface.time


func is_burrowed() -> bool:
	return not is_dead and (fsm.is_in(&"tunnel") or fsm.is_in(&"lurk"))


# 鑽在地底：打不到（投射物穿過）、不能被當成目標、不跟別人互推
func is_dodging() -> bool:
	return is_burrowed()


func is_targetable() -> bool:
	return super() and not is_burrowed()


func passes_through() -> bool:
	return super() or is_burrowed()


func _can_jump() -> bool:
	return false


func _anim_extra(a: Dictionary) -> void:
	if is_burrowed():
		a["burrowed"] = true
	if fsm.is_in(&"devour"):
		a["phase"] = fsm.data.phase


func aggro() -> void:
	if is_patrolling() and not is_dead:
		_surface_left = def.surface.time
	super()


func _on_damaged(_amount: float, _source_id: int) -> void:
	aggro()


func resume() -> void:
	fsm.change(&"chase")


func update(dt: float) -> void:
	super(dt)
	if is_dead or dormant or not world.is_authority:
		return
	if not is_burrowed():
		_surface_left -= dt
	_update_lobs(dt)
	_update_eggs(dt)


# 酸液落地：落點 radius 內受傷（擋不住），留下酸池 pool_time 秒
func _update_lobs(dt: float) -> void:
	var a: Dictionary = def.acid
	for i in range(_lobs.size() - 1, -1, -1):
		var lob := _lobs[i]
		lob.left -= dt
		if lob.left > 0.0:
			continue
		_lobs.remove_at(i)
		var at: Vector2 = lob.at
		var ground := world.terrain.ground_at(at)
		Hitbox.strike(world, self, at, facing, {"shape": &"circle", "radius": a.radius}, {
			"damage": a.damage * damage_mul, "knockback": 0.0, "origin": at, "blockable": false, "color": a.color,
			"band": Vector2(ground - Config.HEIGHT.reach_below, ground + Config.HEIGHT.slam_height),
		})
		world.emit_event("fx:explosion", {"pos": at, "height": ground, "radius": a.radius, "color": a.color})
		GroundZones.add(world, {
			"pos": at, "radius": a.radius, "duration": a.pool_time, "owner_id": id, "color": a.color,
			"damage_per_sec": a.pool_dps * damage_mul, "damage_type": &"poison", "visual": &"gas",
		})


# 卵孵化：每顆孵 per_egg 隻（自己孵的同時最多 max_alive 隻），孵出來的不給靈魂
func _update_eggs(dt: float) -> void:
	var g: Dictionary = def.eggs
	for i in range(_eggs.size() - 1, -1, -1):
		var egg := _eggs[i]
		egg.left -= dt
		if egg.left > 0.0:
			continue
		_eggs.remove_at(i)
		var nav := world.nav_for(EnemyDefs.ENEMIES[g.hatch].radius)
		for j in mini(g.per_egg, g.max_alive - hatched_alive()):
			var a := world.rng.randf() * TAU
			var bug := world.spawner.spawn_at(world, g.hatch, nav.nearest_walkable((egg.at as Vector2) + Vector2(sin(a), cos(a)) * 0.5))
			bug.summoner_id = id
			bug.no_souls = true


func hatched_alive() -> int:
	var alive := 0
	for e in world.enemies:
		if e is Enemy and (e as Enemy).summoner_id == id and not e.is_dead:
			alive += 1
	return alive


# 在 at 留一顆卵（畫面靠 fx:worm_egg）
func lay_egg(at: Vector2) -> void:
	var g: Dictionary = def.eggs
	_eggs.append({"at": at, "left": g.hatch_time})
	world.emit_event("fx:worm_egg", {"pos": at, "height": world.terrain.ground_at(at), "life": g.hatch_time})


# 冒在地面：紮在原地、慢慢轉向目標；隔 decide_delay 選一招；時間到就鑽下去
class Surface:
	func update(e: GraveWorm, dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		if e._surface_left <= 0.0:
			fsm.change(&"dive")
			return
		var target := e.nearest_player()
		if target == null:
			return
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * dt)
		if fsm.time < e.def.decide_delay:
			return
		var dist := e.pos.distance_to(target.pos)
		var cds := e.world.cooldowns
		if dist <= e.def.devour.trigger_distance and cds.is_ready(e.cd("devour")):
			fsm.change(&"devour")
		elif dist >= e.def.acid.min_distance and cds.is_ready(e.cd("acid")):
			fsm.change(&"acid")
		elif cds.is_ready(e.cd("eggs")) and e.hatched_alive() < e.def.eggs.max_alive:
			fsm.change(&"eggs")


# 鑽下去：dive 秒內還打得到，之後進地底
class Dive:
	func enter(e: GraveWorm, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.emit_event("fx:burrow_out", {"pos": e.pos, "height": e.ground_height})

	func update(e: GraveWorm, _dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		if fsm.time >= e.def.tunnel.dive:
			fsm.change(&"tunnel")


# 地底追蹤：朝目標鑽（會繞牆），track_time 秒到或已經到腳下就停
class Tunnel:
	func update(e: GraveWorm, dt: float, fsm: StateMachine) -> void:
		var t: Dictionary = e.def.tunnel
		var target := e.nearest_player()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		if fsm.time >= t.track_time or e.pos.distance_to(target.pos) <= t.stop_distance:
			fsm.change(&"lurk")
			return
		var aim := e.steer_point(target.pos)
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), t.turn_rate * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * t.speed * (e.speed / e.def.move_speed)


# 停在地底、地面鼓起 warn 秒（目標還來得及跑開）→ 衝出地面：radius 內受傷、擊飛，擋不住
class Lurk:
	func enter(e: GraveWorm, _data: Dictionary, _fsm: StateMachine) -> void:
		var t: Dictionary = e.def.tunnel
		e.velocity = Vector2.ZERO
		e.world.emit_event("fx:burrow_warn", {"pos": e.pos, "height": e.ground_height, "life": t.warn, "radius": t.radius})
		e.world.emit_event("camera:shake", {"amount": t.shake * 0.4, "duration": t.warn})

	func update(e: GraveWorm, _dt: float, fsm: StateMachine) -> void:
		var t: Dictionary = e.def.tunnel
		e.velocity = Vector2.ZERO
		if fsm.time < t.warn:
			return
		e._surface_left = e.def.surface.time
		fsm.change(&"chase")   # 先離開地底，這一下才算得到自己的位置與陣營
		var band := Vector2(e.ground_height - Config.HEIGHT.reach_below, e.ground_height + Config.HEIGHT.slam_height)
		var hits := Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"circle", "radius": t.radius}, {
			"damage": t.damage * e.damage_mul, "knockback": t.knockback, "origin": e.pos, "band": band, "blockable": false,
			"is_heavy": true, "color": e.def.hit_color,
		})
		for h in hits:
			if h is Player:
				(h as Player).knock_up(t.knockup)
		e.world.emit_event("fx:burrow_out", {"pos": e.pos, "height": e.ground_height})
		e.world.emit_event("fx:boss_slam", {"pos": e.pos, "height": e.ground_height, "radius": t.radius})
		e.world.emit_event("camera:shake", {"amount": t.shake, "duration": 0.35})
		e.world.emit_event("sfx:cue", {"cue": "bossSlam", "pos": e.pos})


# 噴酸：頭後仰 windup 秒（跟著目標轉）→ 往目標方向與左右各 spread 吐一團，flight 秒後落地（看影子躲）
class Acid:
	func enter(e: GraveWorm, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("acid"), e.def.acid.cooldown)
		data.fired = false

	func update(e: GraveWorm, dt: float, fsm: StateMachine) -> void:
		var a: Dictionary = e.def.acid
		e.velocity = Vector2.ZERO
		var target := e.nearest_player()
		if not fsm.data.fired:
			if target != null:
				e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * dt)
			if fsm.time >= a.windup:
				fsm.data.fired = true
				var dist: float = clampf(e.pos.distance_to(target.pos) if target != null else a.distance[0], a.distance[0], a.distance[1])
				var targets: Array[Vector2] = []
				for i in int(a.lobs):
					var angle: float = e.facing + (i - (a.lobs - 1) / 2.0) * a.spread
					var at := e.world.nav.nearest_walkable(e.pos + MathUtil.dir_from_angle(angle) * dist)
					targets.append(at)
					e._lobs.append({"at": at, "left": a.flight})
				e.world.emit_event("fx:dirt_lob", {"pos": e.pos, "height": e.height + 2.0, "targets": targets, "flight": a.flight,
					"radius": a.radius, "color": a.color})
				e.world.emit_event("sfx:cue", {"cue": "enemySpawn", "pos": e.pos})
		elif fsm.time >= a.windup + a.recovery:
			e.resume()


# 吞噬：嘴巴張開 windup 秒（方向鎖定）→ 吸 pull_time 秒：前方 arc、radius 內沒在翻滾的玩家被往嘴邊拉；
# 拉到嘴邊（bite_reach）咬一口（每人一次、擋不住）→ recovery
class Devour:
	func enter(e: GraveWorm, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("devour"), e.def.devour.cooldown)
		var target := e.nearest_player()
		if target != null:
			e.facing = MathUtil.angle_to(e.pos, target.pos)
		data.phase = &"windup"
		data.bitten = {}
		e.world.emit_event("sfx:cue", {"cue": "enrage", "pos": e.pos})

	func update(e: GraveWorm, _dt: float, fsm: StateMachine) -> void:
		var v: Dictionary = e.def.devour
		var d := fsm.data
		e.velocity = Vector2.ZERO
		if fsm.time < v.windup:
			return
		if fsm.time >= v.windup + v.pull_time:
			d.phase = &"recovery"
			if fsm.time >= v.windup + v.pull_time + v.recovery:
				e.resume()
			return
		d.phase = &"pull"
		for p in e.world.player_list:
			if not p.is_targetable() or p.is_dodging() or d.bitten.has(p.id):
				continue
			var dist := e.pos.distance_to(p.pos)
			if dist > v.radius or absf(angle_difference(e.facing, MathUtil.angle_to(e.pos, p.pos))) > v.arc * 0.5:
				continue
			if dist <= e.radius + p.radius + v.bite_reach:
				d.bitten[p.id] = true
				Combat.apply_damage(e.world, e, p, {"damage": v.damage * e.damage_mul, "knockback": v.knockback, "origin": e.pos,
					"blockable": false, "is_heavy": true, "color": e.def.hit_color})
			else:
				p.knockback = (e.pos - p.pos).normalized() * v.pull_speed


# 產卵：尾巴翹起 windup 秒 → 在身後留 count 顆卵 → recovery
class Eggs:
	func enter(e: GraveWorm, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("eggs"), e.def.eggs.cooldown)
		data.laid = false

	func update(e: GraveWorm, _dt: float, fsm: StateMachine) -> void:
		var g: Dictionary = e.def.eggs
		e.velocity = Vector2.ZERO
		if not fsm.data.laid and fsm.time >= g.windup:
			fsm.data.laid = true
			for i in int(g.count):
				var angle: float = e.facing + PI + (i - (g.count - 1) / 2.0) * g.spread
				e.lay_egg(e.world.nav.nearest_walkable(e.pos + MathUtil.dir_from_angle(angle) * g.distance))
		if fsm.time >= g.windup + g.recovery:
			e.resume()
