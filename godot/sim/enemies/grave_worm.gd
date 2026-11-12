# 噬墓巨蟲（第 3 層 Boss，數值 Claude 暫定）：大部分時間鑽在地底（打不到、不能當目標、不擋路），冒出來 surface.time 秒才打得到。
# 循環：surface（冒在地面、紮在原地出招）→ dive 鑽下去 → tunnel 在地底追 track_time 秒（地面一路冒土）→ lurk 停下、地面鼓起 warn 秒
#   → 衝出地面（半徑 radius、擊飛、擋不住）→ surface
# 地面上的招式：噴酸（往 lobs 個方向吐酸，落地留酸池）、吞噬（張嘴把前方的人吸過來，吸到嘴邊咬一口）、產卵（留幾顆卵，hatch_time 秒後孵屍甲蟲）
# 巡邏時在地面上慢慢爬（Boss.Patrol），發現玩家後第一輪直接從地面開始
# 半血轉型態：pupate 結蛹 transform.time 秒（打得到，受到的傷害 × transform.damage_taken）→ form = 1「屍蛾女王」：
#   會飛（is_flying：只有投射物與跳起來的攻擊打得到，見 out_of_reach；不擋路），每 land.interval 秒落地 land.time 秒產卵（這時近戰打得到）；
#   鱗粉雲（幾團粉霧，站在裡面視野縮成 dust.vision，拿火把的不受影響）、俯衝（鎖定方向直線衝過去，擊倒）、
#   拍翅狂風（前方扇形把人吹退、吹散蛛網）
class_name GraveWorm
extends Boss

var form := 0   # 0 = 噬墓巨蟲、1 = 屍蛾女王（動畫欄位 form，畫面層照 form_models 換模型）
var _land_timer := 0.0   # 屍蛾女王離下次落地還有幾秒（飛著才倒數）

var _surface_left := 0.0   # 這次冒出來還剩幾秒（出招中照樣倒數；到 0 而且回到 surface 才鑽下去）
var _lobs: Array[Dictionary] = []   # 飛在空中的酸液 { at, left }
var _eggs: Array[Dictionary] = []   # 還沒孵的卵 { at, left }


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	super(p_world, p_type, at, mul, {
		&"patrol": Boss.Patrol.new(), &"chase": Surface.new(), &"dive": Dive.new(), &"tunnel": Tunnel.new(), &"lurk": Lurk.new(),
		&"acid": Acid.new(), &"devour": Devour.new(), &"eggs": Eggs.new(),
		&"pupate": Pupate.new(), &"moth_chase": MothChase.new(), &"dust": Dust.new(), &"swoop": Swoop.new(), &"gust": Gust.new(),
		&"land": Land.new(),
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
	return super() or is_burrowed() or is_flying()


func _can_jump() -> bool:
	return false


func on_added() -> void:
	var first: Dictionary = def.moth.first_cooldowns if form > 0 else def.first_cooldowns
	for name: String in first:
		world.cooldowns.start(cd(name), first[name])


# 屍蛾女王飛在空中：盤旋、撒鱗粉、拍翅、俯衝前拉高的時候（俯衝衝下來與落地時不算）
func is_flying() -> bool:
	if form == 0 or is_dead:
		return false
	if fsm.is_in(&"swoop"):
		return fsm.data.phase == &"windup"
	return fsm.is_in(&"moth_chase") or fsm.is_in(&"dust") or fsm.is_in(&"gust")


# 飛著的時候夠不到：只有投射物、或跳起來（腳離地 jump_reach 以上）的玩家打得到
func out_of_reach(source: Entity, hit: Dictionary) -> bool:
	if not is_flying() or hit.get("projectile", false):
		return false
	return not (source is Player and source.height - source.ground_height >= def.moth.jump_reach)


func _anim_extra(a: Dictionary) -> void:
	if form > 0:
		a["form"] = form
		if is_flying():
			a["flying"] = true
		if fsm.is_in(&"swoop"):
			a["phase"] = fsm.data.phase
		return
	if is_burrowed():
		a["burrowed"] = true
	if fsm.is_in(&"devour"):
		a["phase"] = fsm.data.phase


func aggro() -> void:
	if is_patrolling() and not is_dead:
		_surface_left = def.surface.time
	super()


# 半血就結蛹（在地底時打不到，所以一定是在地面上）
func _on_damaged(_amount: float, _source_id: int) -> void:
	aggro()
	if form == 0 and not is_dead and not fsm.is_in(&"pupate") and hp / max_hp <= def.transform.hp_threshold:
		fsm.change(&"pupate")


func resume() -> void:
	fsm.change(&"moth_chase" if form > 0 else &"chase")


func _become_moth() -> void:
	var m: Dictionary = def.moth
	form = 1
	_lobs.clear()
	set_stat_source(&"form", [[&"move_speed", Stats.MUL, m.move_speed / def.move_speed]])
	stats.set_base(&"knockback_taken", m.knockback_mul)
	_land_timer = m.land.interval
	world.emit_event("boss:transformed", {"boss_id": id, "form": form, "pos": pos})
	world.emit_event("sfx:cue", {"cue": "enrage", "pos": pos})
	on_added()
	resume()


func update(dt: float) -> void:
	super(dt)
	if is_dead or dormant or not world.is_authority:
		return
	if not is_burrowed():
		_surface_left -= dt
	if is_flying():
		_land_timer -= dt
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


# 結蛹：原地縮成蛹 transform.time 秒，打得到、受到的傷害 × damage_taken；時間到破蛹變成屍蛾女王
class Pupate:
	func enter(e: GraveWorm, _data: Dictionary, _fsm: StateMachine) -> void:
		var tr: Dictionary = e.def.transform
		e.velocity = Vector2.ZERO
		e.set_stat_source(&"pupa", [[&"damage_taken", Stats.MUL, tr.damage_taken]])
		e.world.emit_event("boss:transforming", {"boss_id": e.id})
		e.world.emit_event("camera:shake", {"amount": tr.shake, "duration": tr.shake_duration})
		e.world.emit_event("sfx:cue", {"cue": "hitHeavy", "pos": e.pos})

	func update(e: GraveWorm, _dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		if fsm.time >= e.def.transform.time:
			e.set_stat_source(&"pupa", [])
			e._become_moth()


# 飛著盤旋：太遠就靠近、太近就退開；隔 decide_delay 選一招；該落地了就落地
class MothChase:
	func update(e: GraveWorm, dt: float, fsm: StateMachine) -> void:
		var m: Dictionary = e.def.moth
		var target := e.nearest_player()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		var dist := e.pos.distance_to(target.pos)
		if fsm.time >= m.decide_delay:
			var cds := e.world.cooldowns
			if e._land_timer <= 0.0:
				fsm.change(&"land")
				return
			if dist <= m.gust.trigger_distance and cds.is_ready(e.cd("gust")):
				fsm.change(&"gust")
				return
			if dist >= m.swoop.min_distance and cds.is_ready(e.cd("swoop")) and e.world.nav.has_los(e.pos, target.pos):
				fsm.change(&"swoop")
				return
			if cds.is_ready(e.cd("dust")):
				fsm.change(&"dust")
				return
		var aim := e.steer_point(target.pos)
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), m.turn_speed * dt)
		if dist > m.hover[1]:
			e.velocity = (aim - e.pos).normalized() * e.speed
		elif dist < m.hover[0]:
			e.velocity = (e.pos - target.pos).normalized() * e.speed * 0.6
		else:
			e.velocity = Vector2.ZERO


# 鱗粉雲：停在空中抖翅膀 windup 秒 → 在目標身邊撒 clouds 團粉霧（GroundZones 的 vision_cap）
class Dust:
	func enter(e: GraveWorm, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("dust"), e.def.moth.dust.cooldown)
		data.done = false

	func update(e: GraveWorm, _dt: float, fsm: StateMachine) -> void:
		var u: Dictionary = e.def.moth.dust
		e.velocity = Vector2.ZERO
		if not fsm.data.done and fsm.time >= u.windup:
			fsm.data.done = true
			var target := e.nearest_player()
			var center := target.pos if target != null else e.pos
			var turn := e.world.rng.randf() * TAU
			for i in int(u.clouds):
				var at := e.world.nav.nearest_walkable(center + MathUtil.dir_from_angle(turn + TAU * i / u.clouds) * u.offset)
				GroundZones.add(e.world, {
					"pos": at, "radius": u.radius, "duration": u.time, "owner_id": e.id, "color": u.color, "visual": &"gas",
					"vision_cap": u.vision,
				})
		if fsm.time >= u.windup + u.recovery:
			e.resume()


# 俯衝：拉高、收翅 windup 秒（前 track 比例跟著目標轉，之後鎖定方向）→ 沿鎖定的方向衝 length（撞牆就停），
# 路上 width 內的人各打一次、擊倒 → recovery
class Swoop:
	func enter(e: GraveWorm, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("swoop"), e.def.moth.swoop.cooldown)
		data.phase = &"windup"
		data.traveled = 0.0
		data.hit = {}
		e.world.emit_event("sfx:cue", {"cue": "enrage", "pos": e.pos})

	func update(e: GraveWorm, dt: float, fsm: StateMachine) -> void:
		var s: Dictionary = e.def.moth.swoop
		var d := fsm.data
		match d.phase:
			&"windup":
				e.velocity = Vector2.ZERO
				var target := e.nearest_player()
				if target != null and fsm.time < s.windup * s.track:
					e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.moth.turn_speed * 2.0 * dt)
				if fsm.time >= s.windup:
					d.phase = &"dash"
			&"dash":
				var dir := MathUtil.dir_from_angle(e.facing)
				var ahead := e.pos + dir * (e.radius + 0.05)
				var lim := e.world.half_extents - Vector2(e.radius, e.radius)
				var blocked := absf(ahead.x) > lim.x or absf(ahead.y) > lim.y or e.world.terrain.ground_at(ahead) > e.height + Config.HEIGHT.step
				if blocked or d.traveled >= s.length:
					e.velocity = Vector2.ZERO
					d.phase = &"recovery"
					d.recover_from = fsm.time
					return
				e.velocity = dir * s.speed
				d.traveled += s.speed * dt
				Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"circle", "radius": s.width}, {
					"damage": s.damage * e.damage_mul, "knockback": s.knockback, "origin": e.pos - dir, "blockable": false,
					"is_heavy": true, "tier": s.tier, "color": e.def.hit_color,
				}, d.hit)
			&"recovery":
				e.velocity = Vector2.ZERO
				if fsm.time >= d.recover_from + s.recovery:
					e.resume()


# 拍翅狂風：翅膀後張 windup 秒 → 前方扇形把人吹退（擋不住）、吹散範圍內的蛛網 → recovery
class Gust:
	func enter(e: GraveWorm, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("gust"), e.def.moth.gust.cooldown)
		var target := e.nearest_player()
		if target != null:
			e.facing = MathUtil.angle_to(e.pos, target.pos)
		data.done = false

	func update(e: GraveWorm, _dt: float, fsm: StateMachine) -> void:
		var g: Dictionary = e.def.moth.gust
		e.velocity = Vector2.ZERO
		if not fsm.data.done and fsm.time >= g.windup:
			fsm.data.done = true
			Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"sector", "range": g.range, "arc": g.arc}, {
				# 擊退的總位移 = 力道 ÷ 質量 ÷ knockback_damping，反推出吹退 push_distance 要的力道
				"damage": g.damage * e.damage_mul, "knockback": g.push_distance * Config.COMBAT.knockback_damping * Config.PLAYER.mass,
				"origin": e.pos, "blockable": false, "tier": &"heavy",
				"color": e.def.hit_color,
			})
			for i in range(e.world.zones.size() - 1, -1, -1):
				var z: Dictionary = e.world.zones[i]
				var to: Vector2 = z.pos
				if z.has("web_id") and e.pos.distance_to(to) <= g.range and absf(angle_difference(e.facing, MathUtil.angle_to(e.pos, to))) <= g.arc * 0.5:
					e.world.emit_event("fx:web_burned", {"web_id": z.web_id, "pos": to, "height": e.world.terrain.ground_at(to)})
					e.world.zones.remove_at(i)
			e.world.emit_event("fx:gust", {"pos": e.pos, "height": e.ground_height, "facing": e.facing, "range": g.range, "arc": g.arc})
		if fsm.time >= g.windup + g.recovery:
			e.resume()


# 落地產卵：descend 秒降下來 → 落地 time 秒（近戰打得到），一落地就在身邊留 eggs 顆卵 → 飛起來
class Land:
	func enter(e: GraveWorm, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		data.laid = false

	func update(e: GraveWorm, _dt: float, fsm: StateMachine) -> void:
		var l: Dictionary = e.def.moth.land
		e.velocity = Vector2.ZERO
		if not fsm.data.laid and fsm.time >= l.descend:
			fsm.data.laid = true
			for i in int(l.eggs):
				var angle: float = e.facing + PI + TAU * i / l.eggs
				e.lay_egg(e.world.nav.nearest_walkable(e.pos + MathUtil.dir_from_angle(angle) * l.egg_distance))
		if fsm.time >= l.descend + l.time:
			e._land_timer = l.interval
			e.resume()
