# 守墓人（第 1 層 Boss）：開局假裝友善的 NPC（狀態名沿用 patrol：HUD 不顯示 Boss 血條、頭上是綠色血條）
#   在王族墓附近慢慢掃地，看到玩家也不追。玩家按 F 說話（talk）→ 頭上冒「又一頭肥羊……」reveal 秒後開打；
#   被打、或有人開挖墳墓 → 不說話直接開打（Boss.aggro）。多人一人觸發全隊開打（Boss 只有一隻）
# 第一型態「老守墓人」（慢、靠道具）：鐵鏟揮擊、鏟土拋擲（看地上的影子）、提燈噴火（留下殘火）、口哨叫屍犬
# 半血變身狼人在第 5 步做；這一步半血不狂暴（覆寫 Boss._on_damaged）
class_name Gravekeeper
extends Boss

var spoke := false   # 這次揭穿是被說話觸發的（畫面層顯示台詞）


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	super(p_world, p_type, at, mul, {
		&"patrol": Npc.new(), &"reveal": Reveal.new(), &"chase": KeeperChase.new(),
		&"shovel": Shovel.new(), &"lob": Lob.new(), &"lantern": Lantern.new(), &"whistle": Whistle.new(),
	})


func _anim_extra(a: Dictionary) -> void:
	var d := fsm.data
	if fsm.is_in(&"reveal") and spoke:
		a["spoke"] = true
	if fsm.is_in(&"lob") or fsm.is_in(&"lantern"):
		a["phase"] = d.phase
		a["phase_time"] = d.phase_time


func is_npc() -> bool:
	return is_patrolling()


func can_talk(p: Player) -> bool:
	return is_npc() and not is_dead and pos.distance_to(p.pos) - radius - p.radius <= def.npc.talk_range


# 玩家按 F 說話：說完台詞才開打
func talk() -> void:
	if not is_npc():
		return
	spoke = true
	fsm.change(&"reveal")
	world.emit_event("boss:revealed", {"boss_id": id, "spoke": true})


# 被打、開挖墳墓、說完話：開打（NPC 狀態才有作用）。被打時不說話，直接開打
func aggro() -> void:
	if is_dead or not (is_npc() or fsm.is_in(&"reveal")):
		return
	if is_npc():
		world.emit_event("boss:revealed", {"boss_id": id, "spoke": false})
	on_added()
	fsm.change(&"chase")
	world.emit_event("boss:aggro", {"boss_id": id, "pos": pos})


func _on_damaged(_amount: float, _source_id: int) -> void:
	aggro()


# 半徑內（含旁邊的高台）的玩家受到地面衝擊：鏟土落地
func _land(at: Vector2, l: Dictionary) -> void:
	var band := Vector2(world.terrain.ground_at(at) - Config.HEIGHT.reach_below, world.terrain.ground_at(at) + Config.HEIGHT.slam_height)
	var hits := Hitbox.strike(world, self, at, facing, {"shape": &"circle", "radius": l.radius}, {
		"damage": l.damage * damage_mul, "knockback": l.knockback, "origin": at, "band": band, "blockable": false, "color": l.color,
	})
	for t in hits:
		if t is Player:
			(t as Player).add_buff(&"dirt_slow", l.slow_time, {"stats": [[&"move_speed", Stats.MUL, l.slow_mul]]})
	world.emit_event("sfx:cue", {"cue": "hit", "pos": at})


class Npc:
	func enter(e: Gravekeeper, data: Dictionary, _fsm: StateMachine) -> void:
		data.wait = e.world.rng.randf_range(e.def.npc.pause[0], e.def.npc.pause[1])
		data.goal = e.pos

	# 掃地：在 patrol_rect 裡慢慢走、停下來掃一陣子；看到玩家不追
	func update(e: Gravekeeper, dt: float, fsm: StateMachine) -> void:
		var s: Dictionary = e.def.npc
		var data := fsm.data
		if data.wait > 0.0:
			data.wait -= dt
			e.velocity = Vector2.ZERO
			if data.wait <= 0.0:
				data.goal = Boss.Patrol.new()._pick_goal(e)
			return
		if e.pos.distance_to(data.goal) < 0.6:
			data.wait = e.world.rng.randf_range(s.pause[0], s.pause[1])
			e.velocity = Vector2.ZERO
			return
		var aim := e.steer_point(data.goal)
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), e.def.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * (e.speed * s.speed_mul)


# 揭穿：站著轉向說話的玩家，reveal_time 秒後開打（期間被打就直接開打）
class Reveal:
	func enter(e: Gravekeeper, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO

	func update(e: Gravekeeper, dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		var target := e.nearest_player()
		if target != null:
			e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * dt)
		if fsm.time >= e.def.npc.reveal_time:
			e.aggro()


class KeeperChase:
	func update(e: Gravekeeper, dt: float, fsm: StateMachine) -> void:
		var target := e.nearest_player()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		var d := e.def
		var dist := e.pos.distance_to(target.pos)
		var cds := e.world.cooldowns
		if fsm.time > d.decide_delay:
			if dist <= d.shovel.trigger_distance and cds.is_ready(e.cd("shovel")):
				fsm.change(&"shovel")
				return
			if dist <= d.lantern.trigger_distance and cds.is_ready(e.cd("lantern")):
				fsm.change(&"lantern")
				return
			if cds.is_ready(e.cd("whistle")) and _hounds(e) < d.whistle.max_alive:
				fsm.change(&"whistle")
				return
			if dist >= d.lob.min_distance and dist <= d.lob.max_distance and cds.is_ready(e.cd("lob")):
				fsm.change(&"lob")
				return
		var aim := e.steer_point(target.pos)
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), d.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed

	func _hounds(e: Gravekeeper) -> int:
		var n := 0
		for x in e.world.enemies:
			if x is Enemy and (x as Enemy).summoner_id == e.id and not x.is_dead:
				n += 1
		return n


# 鐵鏟揮擊：扛鏟 windup（前 track 比例轉向）→ 橫掃扇形一次 → 收招；擋得住
class Shovel:
	func enter(e: Gravekeeper, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("shovel"), e.def.shovel.cooldown)
		data.hit = {}

	func update(e: Gravekeeper, dt: float, fsm: StateMachine) -> void:
		var s: Dictionary = e.def.shovel
		var t := fsm.time
		e.velocity = Vector2.ZERO
		var target := e.nearest_player()
		if t < s.windup * s.track and target != null:
			e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * dt)
		if t >= s.windup and t < s.windup + s.active:
			Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"sector", "range": s.range, "arc": s.arc}, {
				"damage": s.damage * e.damage_mul, "knockback": s.knockback, "blockable": true, "is_heavy": true, "color": e.def.hit_color,
			}, fsm.data.hit)
		if t >= s.windup + s.active + s.recovery:
			fsm.change(&"chase")


# 鏟土拋擲：windup（鏟子插地、往後撬）→ throw：往目標附近丟 count 坨土（發 fx:dirt_lob，畫面畫土塊與影子）
# → 每坨 flight_time 秒後落地（_land）→ 全部落地後 recovery
class Lob:
	func enter(e: Gravekeeper, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("lob"), e.def.lob.cooldown)
		data.phase = &"windup"
		data.phase_time = 0.0
		data.targets = []

	func update(e: Gravekeeper, dt: float, fsm: StateMachine) -> void:
		var l: Dictionary = e.def.lob
		var d := fsm.data
		d.phase_time += dt
		e.velocity = Vector2.ZERO
		var target := e.nearest_player()
		if d.phase == &"windup":
			if target != null:
				e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * dt)
			if d.phase_time >= l.windup:
				d.phase = &"throw"
				d.phase_time = 0.0
				var center: Vector2 = target.pos if target != null else e.pos + MathUtil.dir_from_angle(e.facing) * 6.0
				var nav := e.world.nav
				for i in l.count:
					var off := Vector2.ZERO if i == 0 else MathUtil.dir_from_angle(e.world.rng.randf() * TAU) * e.world.rng.randf_range(l.spread * 0.5, l.spread)
					d.targets.append(nav.nearest_walkable(center + off))
				e.world.emit_event("fx:dirt_lob", {"pos": e.pos, "height": e.height + 1.6, "targets": d.targets.duplicate(),
					"flight": l.flight_time, "radius": l.radius})
				e.world.emit_event("sfx:cue", {"cue": "bossSlamWindup", "pos": e.pos})
			return
		if d.phase == &"throw":
			if d.phase_time >= l.flight_time:
				for at: Vector2 in d.targets:
					e._land(at, l)
				d.phase = &"recovery"
				d.phase_time = 0.0
			return
		if d.phase_time >= l.recovery:
			fsm.change(&"chase")


# 提燈噴火：windup（打開燈罩、燈火轉藍、吸氣；前 track 比例轉向）→ flame：前方扇形每 tick 秒打一次（擋得住）
# → 結束時沿噴火方向留下 embers 團殘火（擋不住）→ recovery
class Lantern:
	func enter(e: Gravekeeper, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("lantern"), e.def.lantern.cooldown)
		data.phase = &"windup"
		data.phase_time = 0.0
		data.ticks = 0
		e.world.emit_event("sfx:cue", {"cue": "bossChargeWindup", "pos": e.pos})

	func update(e: Gravekeeper, dt: float, fsm: StateMachine) -> void:
		var f: Dictionary = e.def.lantern
		var d := fsm.data
		d.phase_time += dt
		e.velocity = Vector2.ZERO
		if d.phase == &"windup":
			var target := e.nearest_player()
			if d.phase_time < f.windup * f.track and target != null:
				e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * dt)
			if d.phase_time >= f.windup:
				d.phase = &"flame"
				d.phase_time = 0.0
			return
		if d.phase == &"flame":
			while d.ticks < floori((d.phase_time + 1e-6) / f.tick) and d.ticks < roundi(f.duration / f.tick):
				d.ticks += 1
				# 一直站在火裡就一直被燒：火焰範圍內的玩家不吃受傷後的無敵時間（同腐屍的啃咬）
				for t in Hitbox.query(e.world, e.team, e.pos, e.facing, {"shape": &"sector", "range": f.range, "arc": f.arc}, e.id):
					if t is Player:
						t.invuln_timer = 0.0
				Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"sector", "range": f.range, "arc": f.arc}, {
					"damage": f.damage * e.damage_mul, "knockback": 0.0, "blockable": true, "color": f.color,
				})
			if d.phase_time >= f.duration:
				var dir := MathUtil.dir_from_angle(e.facing)
				for dist: float in f.embers:
					GroundZones.add(e.world, {
						"pos": e.world.nav.nearest_walkable(e.pos + dir * dist), "radius": f.ember_radius, "duration": f.ember_time,
						"owner_id": e.id, "color": f.color, "damage_per_sec": f.ember_dps * e.damage_mul, "damage_type": &"phys", "visual": &"fire",
					})
				d.phase = &"recovery"
				d.phase_time = 0.0
			return
		if d.phase_time >= f.recovery:
			fsm.change(&"chase")


# 口哨：windup 後在身邊叫 count 隻屍犬（不給靈魂、算守墓人叫的）
class Whistle:
	func enter(e: Gravekeeper, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("whistle"), e.def.whistle.cooldown)
		e.world.emit_event("sfx:cue", {"cue": "bossSummon", "pos": e.pos})

	func update(e: Gravekeeper, _dt: float, fsm: StateMachine) -> void:
		var w: Dictionary = e.def.whistle
		e.velocity = Vector2.ZERO
		if fsm.time >= w.windup and not fsm.data.get("done", false):
			fsm.data.done = true
			var nav := e.world.nav_for(EnemyDefs.ENEMIES.hound.radius)
			for i in w.count:
				var a: float = e.facing + PI + (i - (w.count - 1) / 2.0) * 0.9
				var h := e.world.spawner.spawn_at(e.world, &"hound", nav.nearest_walkable(e.pos + MathUtil.dir_from_angle(a) * w.distance))
				h.no_souls = true
				h.summoner_id = e.id
		if fsm.time >= w.windup + w.recovery:
			fsm.change(&"chase")
