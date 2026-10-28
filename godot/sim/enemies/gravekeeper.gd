# 守墓人（第 1 層 Boss）：開局假裝友善的 NPC（狀態名沿用 patrol：HUD 不顯示 Boss 血條、頭上是綠色血條）
#   在王族墓附近慢慢掃地，看到玩家也不追。玩家按 F 說話（talk）→ 頭上冒「又一頭肥羊……」reveal 秒後開打；
#   被打、或有人開挖墳墓 → 不說話直接開打（Boss.aggro）。多人一人觸發全隊開打（Boss 只有一隻）
# 第一型態「老守墓人」（慢、靠道具）：鐵鏟揮擊、鏟土拋擲（看地上的影子）、提燈噴火（留下殘火）、口哨叫屍犬
# 半血轉型態（取代狂暴，設計方向「Boss 半血轉型態」）：transform 狀態無敵 transform.time 秒 → form = 1「墓園狼人」：
#   嚎叫震退身邊的玩家、提燈掉在地上變成火堆（Torch：照亮的範圍全隊看得到）、移速 wolf.move_speed
#   狼人：三連爪、飛撲（看影子）、隱入黑暗（跑到目標背後再撲）、狼嚎（叫魔法屍犬、自己加速）
class_name Gravekeeper
extends Boss

var spoke := false   # 這次揭穿是被說話觸發的（畫面層顯示台詞）
var form := 0        # 0 = 老守墓人、1 = 墓園狼人（動畫欄位 form，畫面層換模型）
var howl_left := 0.0 # 狼嚎加速剩幾秒（到了拿掉移速來源 &"howl"）


func update(dt: float) -> void:
	if howl_left > 0.0:
		howl_left -= dt
		if howl_left <= 0.0:
			remove_stat_source(&"howl")
	super(dt)


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	super(p_world, p_type, at, mul, {
		&"patrol": Npc.new(), &"reveal": Reveal.new(), &"chase": KeeperChase.new(),
		&"shovel": Shovel.new(), &"lob": Lob.new(), &"lantern": Lantern.new(), &"whistle": Whistle.new(),
		&"transform": Transform.new(), &"wolf_chase": WolfChase.new(), &"claw": Claw.new(), &"leap": Leap.new(),
		&"stalk": Stalk.new(), &"howl": Howl.new(),
	})


func _anim_extra(a: Dictionary) -> void:
	var d := fsm.data
	if form > 0:
		a["form"] = form
	if fsm.is_in(&"reveal") and spoke:
		a["spoke"] = true
	if fsm.is_in(&"lob") or fsm.is_in(&"lantern") or fsm.is_in(&"leap"):
		a["phase"] = d.phase
		a["phase_time"] = d.phase_time


func on_added() -> void:
	var first: Dictionary = def.wolf.first_cooldowns if form > 0 else def.first_cooldowns
	for name: String in first:
		world.cooldowns.start(cd(name), first[name])


func turn_rate() -> float:
	return def.wolf.turn_speed if form > 0 else def.turn_speed


# 回到追擊：哪個型態就回哪個
func resume() -> void:
	fsm.change(&"wolf_chase" if form > 0 else &"chase")


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
	if form == 0 and not is_dead and not fsm.is_in(&"transform") and hp / max_hp <= def.transform.hp_threshold:
		fsm.change(&"transform")


# 變身完成：換型態、加移速、嚎叫震退身邊的玩家、提燈掉在地上變成火堆
func _become_wolf() -> void:
	var tr: Dictionary = def.transform
	form = 1
	set_stat_source(&"form", [[&"move_speed", Stats.MUL, def.wolf.move_speed / def.move_speed]])
	for p in world.player_list:
		if p.is_targetable() and p.pos.distance_to(pos) <= tr.roar_radius + p.radius:
			Combat.apply_damage(world, self, p, {"damage": tr.roar_damage * damage_mul, "knockback": tr.roar_knockback, "blockable": false, "color": def.hit_color})
	if world.is_authority:
		var lamp := Torch.new(world, world.nav.nearest_walkable(pos + MathUtil.dir_from_angle(facing + PI * 0.75) * 1.2))
		world.add_entity(lamp)
		world.torches.append(lamp)
	world.emit_event("boss:transformed", {"boss_id": id, "form": form, "pos": pos})
	world.emit_event("camera:shake", {"amount": tr.shake, "duration": tr.shake_duration})
	world.emit_event("sfx:cue", {"cue": "enrage", "pos": pos})
	on_added()   # 狼人的招式冷卻從現在起算
	resume()


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


# ───────── 第二型態：墓園狼人 ─────────

# 變身：站著不動、無敵 transform.time 秒（畫面層：抖動、撐破衣服）→ _become_wolf
class Transform:
	func enter(e: Gravekeeper, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.emit_event("boss:transforming", {"boss_id": e.id})
		e.invuln_timer = 0.1   # 進入的那一下就無敵（同一步後面的攻擊打不動）

	func update(e: Gravekeeper, _dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.invuln_timer = 0.1   # 變身中無敵
		if fsm.time >= e.def.transform.time:
			e._become_wolf()


class WolfChase:
	func update(e: Gravekeeper, dt: float, fsm: StateMachine) -> void:
		var target := e.nearest_player()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		var w: Dictionary = e.def.wolf
		var dist := e.pos.distance_to(target.pos)
		var cds := e.world.cooldowns
		if fsm.time > w.decide_delay:
			if dist <= w.claw.trigger_distance and cds.is_ready(e.cd("claw")):
				fsm.change(&"claw")
				return
			if dist >= w.leap.min_distance and dist <= w.leap.max_distance and cds.is_ready(e.cd("leap")):
				fsm.change(&"leap")
				return
			if cds.is_ready(e.cd("howl")) and _hounds(e) < w.howl.max_alive:
				fsm.change(&"howl")
				return
			if dist <= w.stalk.max_distance and cds.is_ready(e.cd("stalk")):
				fsm.change(&"stalk")
				return
		var aim := e.steer_point(target.pos)
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), e.turn_rate() * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed

	func _hounds(e: Gravekeeper) -> int:
		return KeeperChase.new()._hounds(e)


# 三連爪：雙爪往後拉 windup（轉向）→ 每 interval 秒抓一下（扇形），第三下往前撲 lunge（擋不住）→ recovery
class Claw:
	func enter(e: Gravekeeper, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("claw"), e.def.wolf.claw.cooldown)
		data.swipes = 0

	func update(e: Gravekeeper, dt: float, fsm: StateMachine) -> void:
		var c: Dictionary = e.def.wolf.claw
		var d := fsm.data
		var t := fsm.time
		e.velocity = Vector2.ZERO
		var target := e.nearest_player()
		if t < c.windup and target != null:
			e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.turn_rate() * dt)
		var due := 0 if t < c.windup else mini(3, floori((t - c.windup + 1e-6) / c.interval) + 1)
		while d.swipes < due:
			d.swipes += 1
			var last: bool = d.swipes == 3
			Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"sector", "range": c.range, "arc": c.arc}, {
				"damage": (c.last_damage if last else c.damage) * e.damage_mul, "knockback": c.knockback * (2.0 if last else 1.0),
				"blockable": not last, "is_heavy": last, "color": e.def.hit_color, "pierce_invuln": d.swipes > 1,
			})
		var last_at: float = c.windup + c.interval * 2.0
		if t >= last_at and t < last_at + c.lunge_time:
			e.velocity = MathUtil.dir_from_angle(e.facing) * (c.lunge / c.lunge_time)   # 第三下往前撲
		if t >= last_at + c.recovery:
			e.resume()


# 飛撲：四肢著地蹲低 windup（轉向）→ 跳到目標當時的位置（flight 秒，fx:dirt_lob 只畫影子）→ 落地範圍傷害（擋不住）→ recovery
class Leap:
	func enter(e: Gravekeeper, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("leap"), e.def.wolf.leap.cooldown)
		data.phase = &"windup"
		data.phase_time = 0.0

	func update(e: Gravekeeper, dt: float, fsm: StateMachine) -> void:
		var l: Dictionary = e.def.wolf.leap
		var d := fsm.data
		d.phase_time += dt
		e.velocity = Vector2.ZERO
		var target := e.nearest_player()
		if d.phase == &"windup":
			if target != null:
				e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.turn_rate() * dt)
			if d.phase_time >= l.windup:
				var to: Vector2 = target.pos if target != null else e.pos + MathUtil.dir_from_angle(e.facing) * 6.0
				d.to = e.world.nav_for(e.radius).nearest_walkable(to)
				d.from = e.pos
				d.phase = &"air"
				d.phase_time = 0.0
				e.facing = MathUtil.angle_to(e.pos, d.to)
				if e.is_grounded():
					e.vz = Entity.gravity() * l.flight / 2.0   # 剛好 flight 秒落回地面
				e.world.emit_event("fx:dirt_lob", {"pos": e.pos, "height": e.height, "targets": [d.to], "flight": l.flight,
					"radius": l.radius, "shadow_only": true})
			return
		if d.phase == &"air":
			e.velocity = (d.to - d.from) / l.flight
			if d.phase_time >= l.flight:
				e.velocity = Vector2.ZERO
				var band := Vector2(e.ground_height - Config.HEIGHT.reach_below, e.ground_height + Config.HEIGHT.slam_height)
				Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"circle", "radius": l.radius}, {
					"damage": l.damage * e.damage_mul, "knockback": l.knockback, "band": band, "blockable": false,
					"is_heavy": true, "color": e.def.hit_color,
				})
				e.world.emit_event("camera:shake", {"amount": l.shake, "duration": 0.25})
				e.world.emit_event("fx:boss_slam", {"pos": e.pos, "height": e.height, "radius": l.radius})
				d.phase = &"recovery"
				d.phase_time = 0.0
			return
		if d.phase_time >= l.recovery:
			e.resume()


# 隱入黑暗：低吼一聲往目標的正後方跑（離 behind 遠），到了或超過 time 秒就飛撲
class Stalk:
	func enter(e: Gravekeeper, _data: Dictionary, _fsm: StateMachine) -> void:
		e.world.cooldowns.start(e.cd("stalk"), e.def.wolf.stalk.cooldown)

	func update(e: Gravekeeper, dt: float, fsm: StateMachine) -> void:
		var s: Dictionary = e.def.wolf.stalk
		var target := e.nearest_player()
		if target == null:
			e.resume()
			return
		var goal: Vector2 = target.pos - MathUtil.dir_from_angle(target.facing) * s.behind
		var arrived := e.pos.distance_to(goal) < 1.0
		if arrived or fsm.time >= s.time:
			e.world.cooldowns.reset(e.cd("leap"))
			fsm.change(&"leap")
			return
		var aim := e.steer_point(goal)
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), e.turn_rate() * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed * s.speed_mul


# 狼嚎：仰頭 windup 秒（站著不動，輸出空檔）→ 叫 count 隻魔法屍犬（不給靈魂）、自己移速 ×speed_mul buff_time 秒
class Howl:
	func enter(e: Gravekeeper, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("howl"), e.def.wolf.howl.cooldown)
		e.world.emit_event("sfx:cue", {"cue": "bossSummon", "pos": e.pos})
		data.done = false

	func update(e: Gravekeeper, _dt: float, fsm: StateMachine) -> void:
		var h: Dictionary = e.def.wolf.howl
		e.velocity = Vector2.ZERO
		if fsm.time >= h.windup and not fsm.data.done:
			fsm.data.done = true
			var nav := e.world.nav_for(EnemyDefs.ENEMIES.hound.radius)
			for i in h.count:
				var a: float = e.facing + PI + (i - (h.count - 1) / 2.0) * 0.8
				var dog := e.world.spawner.spawn_at(e.world, &"hound", nav.nearest_walkable(e.pos + MathUtil.dir_from_angle(a) * 2.5))
				Spawner.roll_rarity(e.world, dog, MonsterRarityDefs.MAGIC)
				dog.no_souls = true
				dog.summoner_id = e.id
			e.set_stat_source(&"howl", [[&"move_speed", Stats.MUL, h.speed_mul]])
			e.howl_left = h.buff_time
		if fsm.time >= h.windup + h.recovery:
			e.resume()
