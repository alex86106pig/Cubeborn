# 守墓人（第 1 層 Boss）：開局假裝友善的 NPC（狀態名沿用 patrol：HUD 不顯示 Boss 血條、頭上是綠色血條）
#   在王族墓附近慢慢掃地，看到玩家也不追。玩家按 F 說話（talk）→ 頭上冒「又一頭肥羊……」reveal 秒後開打；
#   被打、或有人開挖墳墓 → 不說話直接開打（Boss.aggro）。多人一人觸發全隊開打（Boss 只有一隻）
# 開打時 grow.time 秒內慢慢變大到 grow.size 倍（半徑、身高、模型；不出招），狼人維持這個大小
# 第一型態「老守墓人」：鐵鏟揮擊、瘋狂鏟土（整個競技場落石，看地上的影子）、提燈噴火（追著噴、最後轉一圈，留下殘火）、
#   口哨叫屍犬、鏟起連段（A 拋飛 → 落石；B 埋地 → 噴火）
# 半血轉型態（取代狂暴，設計方向「Boss 半血轉型態」）：transform 狀態無敵 transform.time 秒 → form = 1「墓園狼人」：
#   嚎叫震退身邊的玩家、提燈掉在地上變成火堆（Torch：照亮的範圍全隊看得到）、移速 wolf.move_speed
#   狼人：三連爪（每下 3 條紅色爪痕）、飛撲（看影子、要靠反應翻滾）、隱入黑暗（跑到目標背後再撲）、狼嚎（叫魔法屍犬、自己加速）
class_name Gravekeeper
extends Boss

var spoke := false   # 這次揭穿是被說話觸發的（畫面層顯示台詞）
var form := 0        # 0 = 老守墓人、1 = 墓園狼人（動畫欄位 form，畫面層換模型）
var howl_left := 0.0 # 狼嚎加速剩幾秒（到了拿掉移速來源 &"howl"）
var size := 1.0      # 體型倍率（NPC = 1，開打後長到 grow.size；動畫欄位 size，客戶端照這個設半徑與身高）
var rocks: Array[Dictionary] = []   # 還在空中的石頭：{ at, left, hit }（瘋狂鏟土、鏟起 A；換狀態照樣落地）
var _base_radius := 0.0
var _base_body := 0.0


func update(dt: float) -> void:
	if howl_left > 0.0:
		howl_left -= dt
		if howl_left <= 0.0:
			remove_stat_source(&"howl")
	_update_rocks(dt)
	super(dt)


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	super(p_world, p_type, at, mul, {
		&"patrol": Npc.new(), &"reveal": Reveal.new(), &"grow": Grow.new(), &"chase": KeeperChase.new(),
		&"shovel": Shovel.new(), &"dig": Dig.new(), &"lantern": Lantern.new(), &"whistle": Whistle.new(), &"scoop": Scoop.new(),
		&"transform": Transform.new(), &"wolf_chase": WolfChase.new(), &"claw": Claw.new(), &"leap": Leap.new(),
		&"stalk": Stalk.new(), &"howl": Howl.new(),
	})


func _anim_extra(a: Dictionary) -> void:
	var d := fsm.data
	if form > 0:
		a["form"] = form
	if size != 1.0:
		a["size"] = size
	if fsm.is_in(&"reveal") and spoke:
		a["spoke"] = true
	if fsm.is_in(&"dig") or fsm.is_in(&"lantern") or fsm.is_in(&"leap") or fsm.is_in(&"scoop"):
		a["phase"] = d.phase
		a["phase_time"] = d.phase_time


# 體型倍率：半徑與身高跟著變（客戶端的鏡像收到動畫欄位 size 也呼叫這個）
func set_size(s: float) -> void:
	if _base_radius == 0.0:
		_base_radius = radius
		_base_body = body_height
	size = s
	radius = _base_radius * s
	body_height = _base_body * s


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


# 被打、開挖墳墓、說完話：開打（NPC 狀態才有作用）。被打時不說話，直接開打；先變大再追
func aggro() -> void:
	if is_dead or not (is_npc() or fsm.is_in(&"reveal")):
		return
	if is_npc():
		world.emit_event("boss:revealed", {"boss_id": id, "spoke": false})
	on_added()
	fsm.change(&"grow" if size < def.grow.size else &"chase")
	world.emit_event("boss:aggro", {"boss_id": id, "pos": pos})


func _on_damaged(amount: float, source_id: int) -> void:
	aggro()
	if fsm.is_in(&"scoop"):
		Scoop.new().on_damaged(self, amount, source_id, fsm)
	if form == 0 and not is_dead and not fsm.is_in(&"transform") and hp / max_hp <= def.transform.hp_threshold:
		fsm.change(&"transform")


# 變身完成：換型態、加移速、嚎叫震退身邊的玩家、提燈掉在地上變成火堆
func _become_wolf() -> void:
	var tr: Dictionary = def.transform
	form = 1
	set_stat_source(&"form", [[&"move_speed", Stats.MUL, def.wolf.move_speed / def.move_speed]])
	set_resists(def.wolf.resists)
	for p in world.player_list:
		if p.is_targetable() and p.pos.distance_to(pos) <= tr.roar_radius + p.radius:
			Combat.apply_damage(world, self, p, {"damage": tr.roar_damage * damage_mul, "knockback": tr.roar_knockback, "blockable": false,
				"color": def.hit_color, "tier": tr.roar_tier})
	if world.is_authority:
		var lamp := Torch.new(world, world.nav.nearest_walkable(pos + MathUtil.dir_from_angle(facing + PI * 0.75) * (radius + 0.5)))
		world.add_entity(lamp)
		world.torches.append(lamp)
	world.emit_event("boss:transformed", {"boss_id": id, "form": form, "pos": pos})
	world.emit_event("camera:shake", {"amount": tr.shake, "duration": tr.shake_duration})
	world.emit_event("sfx:cue", {"cue": "enrage", "pos": pos})
	on_added()   # 狼人的招式冷卻從現在起算
	resume()


# 丟一批石頭：每顆 fall 秒後落地；hit 是落地時的傷害資料（_land）。發一個 fx:dirt_lob（from_sky：從天上直直掉、地上影子越來越大）
func drop_rocks(targets: Array, fall: float, hit: Dictionary) -> void:
	if targets.is_empty():
		return
	for at: Vector2 in targets:
		rocks.append({"at": at, "left": fall, "hit": hit})
	world.emit_event("fx:dirt_lob", {"pos": pos, "height": height, "targets": targets.duplicate(), "flight": fall,
		"radius": hit.radius, "from_sky": true})


func _update_rocks(dt: float) -> void:
	for i in range(rocks.size() - 1, -1, -1):
		var r: Dictionary = rocks[i]
		r.left -= dt
		if r.left <= 0.0:
			rocks.remove_at(i)
			_land(r.at, r.hit)


# 半徑內（含旁邊的高台）的玩家受到地面衝擊：石頭落地。hit：radius、damage、knockback、slow_mul、slow_time、tier、color、pierce_invuln?
func _land(at: Vector2, l: Dictionary) -> void:
	var ground := world.terrain.ground_at(at)
	var band := Vector2(ground - Config.HEIGHT.reach_below, ground + Config.HEIGHT.slam_height)
	var hits := Hitbox.strike(world, self, at, facing, {"shape": &"circle", "radius": l.radius}, {
		"damage": l.damage * damage_mul, "knockback": l.knockback, "origin": at, "band": band, "blockable": false, "color": l.color,
		"tier": l.tier, "pierce_invuln": l.get("pierce_invuln", false),
	})
	for t in hits:
		if t is Player:
			(t as Player).add_buff(&"dirt_slow", l.slow_time, {"stats": [[&"move_speed", Stats.MUL, l.slow_mul]]})
	world.emit_event("sfx:cue", {"cue": "hit", "pos": at})


# 瘋狂鏟土的落點：競技場（巡邏範圍，Boss 在裡面時）裡隨機一點；Boss 跑出去了就是身邊 fallback_radius 內
func random_arena_point(l: Dictionary) -> Vector2:
	var rng := world.rng
	if patrol_rect.has_area() and patrol_rect.has_point(pos):
		return patrol_rect.position + Vector2(rng.randf() * patrol_rect.size.x, rng.randf() * patrol_rect.size.y)
	return pos + MathUtil.dir_from_angle(rng.randf() * TAU) * l.fallback_radius * sqrt(rng.randf())


# 往目標轉（每秒最多 rate 弧度）
func face_towards(at: Vector2, rate: float, dt: float) -> void:
	facing = MathUtil.turn_towards(facing, MathUtil.angle_to(pos, at), rate * dt)


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
			e.face_towards(target.pos, e.def.turn_speed, dt)
		if fsm.time >= e.def.npc.reveal_time:
			e.aggro()


# 變大：站著轉向最近的玩家，grow.time 秒內體型從現在長到 grow.size（不出招）
class Grow:
	func enter(e: Gravekeeper, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		data.from = e.size
		e.world.emit_event("sfx:cue", {"cue": "bossSummon", "pos": e.pos})

	func update(e: Gravekeeper, dt: float, fsm: StateMachine) -> void:
		var g: Dictionary = e.def.grow
		e.velocity = Vector2.ZERO
		var target := e.nearest_player()
		if target != null:
			e.face_towards(target.pos, e.def.turn_speed, dt)
		var k := clampf(fsm.time / g.time, 0.0, 1.0)
		e.set_size(lerpf(fsm.data.from, g.size, MathUtil.ease_out_cubic(k)))
		if k >= 1.0:
			fsm.change(&"chase")


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
			if dist <= d.scoop.trigger_distance and cds.is_ready(e.cd("scoop")):
				fsm.change(&"scoop")
				return
			if dist <= d.shovel.trigger_distance and cds.is_ready(e.cd("shovel")):
				fsm.change(&"shovel")
				return
			if dist <= d.lantern.trigger_distance and cds.is_ready(e.cd("lantern")):
				fsm.change(&"lantern")
				return
			if cds.is_ready(e.cd("whistle")) and _hounds(e) < d.whistle.max_alive:
				fsm.change(&"whistle")
				return
			if dist <= d.dig.max_distance and cds.is_ready(e.cd("dig")):
				fsm.change(&"dig")
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
			e.face_towards(target.pos, e.def.turn_speed, dt)
		if t >= s.windup and t < s.windup + s.active:
			Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"sector", "range": s.range, "arc": s.arc}, {
				"damage": s.damage * e.damage_mul, "knockback": s.knockback, "blockable": true, "is_heavy": true, "color": e.def.hit_color,
				"tier": s.tier,
			}, fsm.data.hit)
		if t >= s.windup + s.active + s.recovery:
			fsm.change(&"chase")


# 瘋狂鏟土：windup（彎腰把鏟子插進地裡）→ dig：狂鏟 duration 秒，每 interval 秒在競技場隨機落一顆石頭、
# 每位玩家每 player_interval 秒腳邊必定落一顆（drop_rocks，fall_time 秒落地）→ recovery
class Dig:
	func enter(e: Gravekeeper, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("dig"), e.def.dig.cooldown)
		data.phase = &"windup"
		data.phase_time = 0.0
		data.spawned = 0
		data.aimed = 0

	func update(e: Gravekeeper, dt: float, fsm: StateMachine) -> void:
		var l: Dictionary = e.def.dig
		var d := fsm.data
		d.phase_time += dt
		e.velocity = Vector2.ZERO
		if d.phase == &"windup":
			var target := e.nearest_player()
			if target != null:
				e.face_towards(target.pos, e.def.turn_speed, dt)
			if d.phase_time >= l.windup:
				d.phase = &"dig"
				d.phase_time = 0.0
				e.world.emit_event("sfx:cue", {"cue": "bossSlamWindup", "pos": e.pos})
			return
		if d.phase == &"dig":
			var targets := []
			var t: float = minf(d.phase_time, l.duration)
			while d.spawned < floori(t / l.interval + 1e-6):
				d.spawned += 1
				targets.append(e.random_arena_point(l))
			while d.aimed < floori(t / l.player_interval + 1e-6) + 1:   # 一開始就先砸一顆在每個人腳邊
				d.aimed += 1
				for p in e.world.player_list:
					if p.is_targetable():
						targets.append(p.pos + MathUtil.dir_from_angle(e.world.rng.randf() * TAU) * l.aim_jitter * e.world.rng.randf())
			e.drop_rocks(targets, l.fall_time, l)
			if d.phase_time >= l.duration:
				d.phase = &"recovery"
				d.phase_time = 0.0
			return
		if d.phase_time >= l.recovery:
			fsm.change(&"chase")


# 提燈噴火：windup（打開燈罩、燈火轉藍、吸氣；前 track 比例轉向）→ flame：邊噴邊追目標 duration 秒（前方扇形每 tick 一下，擋得住；
# 每 ember_every 秒在火焰中段留一團殘火）→ spin_windup：預備動作，來得及翻滾或跑開 → spin：原地轉一圈噴 spin_time 秒（每 spin_tick 一下，範圍 spin_range），身邊留 spin_embers 團殘火 → recovery
class Lantern:
	func enter(e: Gravekeeper, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("lantern"), e.def.lantern.cooldown)
		data.phase = &"windup"
		data.phase_time = 0.0
		data.ticks = 0
		data.embers = 0
		e.world.emit_event("sfx:cue", {"cue": "bossChargeWindup", "pos": e.pos})

	func update(e: Gravekeeper, dt: float, fsm: StateMachine) -> void:
		var f: Dictionary = e.def.lantern
		var d := fsm.data
		d.phase_time += dt
		e.velocity = Vector2.ZERO
		var target := e.nearest_player()
		if d.phase == &"windup":
			if d.phase_time < f.windup * f.track and target != null:
				e.face_towards(target.pos, e.def.turn_speed, dt)
			if d.phase_time >= f.windup:
				d.phase = &"flame"
				d.phase_time = 0.0
			return
		if d.phase == &"flame":
			if target != null:   # 追著噴：轉得比平常慢，繞到側面躲得掉
				var aim := e.steer_point(target.pos)
				e.face_towards(aim, e.def.turn_speed * f.turn_mul, dt)
				if e.pos.distance_to(target.pos) > e.radius + target.radius + 0.5:
					e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed * f.chase_mul
			while d.ticks < floori((minf(d.phase_time, f.duration) + 1e-6) / f.tick):
				d.ticks += 1
				_burn(e, f, f.range)
			while d.embers < floori((minf(d.phase_time, f.duration) + 1e-6) / f.ember_every):
				d.embers += 1
				_ember(e, f, e.pos + MathUtil.dir_from_angle(e.facing) * f.ember_at)
			if d.phase_time >= f.duration:
				d.phase = &"spin_windup"
				d.phase_time = 0.0
			return
		if d.phase == &"spin_windup":
			if d.phase_time >= f.spin_windup:
				d.phase = &"spin"
				d.phase_time = 0.0
				d.ticks = 0
				d.start_facing = e.facing
			return
		if d.phase == &"spin":
			var k := clampf(d.phase_time / f.spin_time, 0.0, 1.0)
			e.facing = wrapf(d.start_facing + TAU * k, -PI, PI)
			while d.ticks < floori((minf(d.phase_time, f.spin_time) + 1e-6) / f.spin_tick):
				d.ticks += 1
				_burn(e, f, f.spin_range)
			if d.phase_time >= f.spin_time:
				for i in f.spin_embers:
					_ember(e, f, e.pos + MathUtil.dir_from_angle(d.start_facing + TAU * i / f.spin_embers) * f.ember_at * 0.6)
				d.phase = &"recovery"
				d.phase_time = 0.0
			return
		if d.phase_time >= f.recovery:
			fsm.change(&"chase")

	# 前方扇形噴一下：一直站在火裡就一直被燒，火焰範圍內的玩家不吃受傷後的無敵時間（同腐屍的啃咬）
	func _burn(e: Gravekeeper, f: Dictionary, reach: float) -> void:
		var shape := {"shape": &"sector", "range": reach, "arc": f.arc}
		for t in Hitbox.query(e.world, e.team, e.pos, e.facing, shape, e.id):
			if t is Player:
				t.invuln_timer = 0.0
		Hitbox.strike(e.world, e, e.pos, e.facing, shape, {
			"damage": f.damage * e.damage_mul, "knockback": 0.0, "blockable": true, "color": f.color, "damage_type": &"fire", "tier": f.tier,
		})

	func _ember(e: Gravekeeper, f: Dictionary, at: Vector2) -> void:
		GroundZones.add(e.world, {
			"pos": e.world.nav.nearest_walkable(at), "radius": f.ember_radius, "duration": f.ember_time,
			"owner_id": e.id, "color": f.color, "damage_per_sec": f.ember_dps * e.damage_mul, "damage_type": &"fire", "visual": &"fire",
		})


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


# 鏟起（怪物圖鑑備註 2）：windup（鏟面貼地往前滑 slide）→ 前方扇形抓最近的一位玩家（擋不住）→ 隨機一種連段：
#   A（throw）：往守墓人背後拋 distance（flight 秒、暈眩中）→ 落地 land_damage、擊倒（受身躲得掉後面的土）→ rock_delay 秒後 rocks 顆土落在落點周圍
#   B（bury）：Player.bury 埋 bury 秒（連按翻滾提早）→ 守墓人退一步（step）→ 開燈罩（open）→ 直噴 flame 秒（窄扇形，擋得住）
# 連段中的傷害不吃受傷無敵；被抓的人以外的人打守墓人累積 break_damage → 中斷（埋著的立刻爬出）
class Scoop:
	func enter(e: Gravekeeper, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.cooldowns.start(e.cd("scoop"), e.def.scoop.cooldown)
		data.phase = &"windup"
		data.phase_time = 0.0
		data.victim = 0
		data.taken = 0.0
		data.ticks = 0

	func exit(e: Gravekeeper, fsm: StateMachine) -> void:
		_release(e, fsm.data)

	func update(e: Gravekeeper, dt: float, fsm: StateMachine) -> void:
		var s: Dictionary = e.def.scoop
		var d := fsm.data
		d.phase_time += dt
		e.velocity = Vector2.ZERO
		match d.phase:
			&"windup":
				var target := e.nearest_player()
				if d.phase_time < s.windup * s.track and target != null:
					e.face_towards(target.pos, e.def.turn_speed, dt)
				e.velocity = MathUtil.dir_from_angle(e.facing) * (s.slide / s.windup)   # 鏟面貼地往前滑一步
				if d.phase_time >= s.windup:
					_grab(e, s, d)
			&"miss":
				if d.phase_time >= s.miss_recovery:
					fsm.change(&"chase")
			&"throw":
				_update_throw(e, s.throw, d, fsm)
			&"bury":
				_update_bury(e, s, d, dt, fsm)

	func _grab(e: Gravekeeper, s: Dictionary, d: Dictionary) -> void:
		var best: Player = null
		for t in Hitbox.query(e.world, e.team, e.pos, e.facing, {"shape": &"sector", "range": s.range, "arc": s.arc}, e.id):
			if t is Player and (t as Player).is_targetable() and (best == null or e.pos.distance_squared_to(t.pos) < e.pos.distance_squared_to(best.pos)):
				best = t
		d.phase_time = 0.0
		if best == null or not Combat.apply_damage(e.world, e, best, {"damage": s.damage * e.damage_mul, "knockback": 0.0, "blockable": false,
				"color": s.color, "tier": &"none", "pierce_invuln": true}):
			d.phase = &"miss"
			return
		d.victim = best.id
		e.world.emit_event("sfx:cue", {"cue": "hit", "pos": best.pos})
		if e.world.rng.randf() < 0.5:
			var th: Dictionary = s.throw
			d.phase = &"throw"
			d.from = best.pos
			d.to = _throw_end(e, best.pos, th.distance)
			d.landed = false
			best.stun(th.flight)
			best.knockback = Vector2.ZERO
			best.vz = Entity.gravity() * th.flight / 2.0   # 剛好 flight 秒落回地面
		else:
			d.phase = &"bury"
			d.phase_time = 0.0
			best.bury(s.bury.bury)

	# 拋到哪裡：從被抓的位置往守墓人背後 distance；中間有牆就停在牆前（找得到的最遠可走點）
	func _throw_end(e: Gravekeeper, from: Vector2, distance: float) -> Vector2:
		var dir := MathUtil.dir_from_angle(e.facing + PI)
		var nav := e.world.nav
		var step := distance
		while step > 0.5:
			var to := from + dir * step
			if nav.has_los(from, to):
				return nav.nearest_walkable(to)
			step -= 0.5
		return from

	func _update_throw(e: Gravekeeper, th: Dictionary, d: Dictionary, fsm: StateMachine) -> void:
		var p := e.world.entities.get(d.victim) as Player
		if not d.landed:
			if p != null and not p.is_dead and not p.is_downed:
				var k := clampf(d.phase_time / th.flight, 0.0, 1.0)
				p.pos = (d.from as Vector2).lerp(d.to, k)   # 直接帶著飛（穿過守墓人的身體，不被推開）
				p.knockback = Vector2.ZERO
			if d.phase_time >= th.flight:
				d.landed = true
				d.phase_time = 0.0
				if p != null and p.is_targetable():
					Combat.apply_damage(e.world, e, p, {"damage": th.land_damage * e.damage_mul, "knockback": 0.0, "blockable": false,
						"color": e.def.scoop.color, "tier": &"knockdown", "pierce_invuln": true})
				var targets := [d.to]
				for i in th.rocks - 1:
					targets.append((d.to as Vector2) + MathUtil.dir_from_angle(TAU * i / (th.rocks - 1) + e.world.rng.randf() * 0.5) * th.rock_spread)
				var hit: Dictionary = e.def.dig.duplicate()
				hit.pierce_invuln = true
				e.drop_rocks(targets, th.rock_delay, hit)
			return
		if d.phase_time >= th.rock_delay + th.recovery:
			fsm.change(&"chase")

	func _update_bury(e: Gravekeeper, s: Dictionary, d: Dictionary, dt: float, fsm: StateMachine) -> void:
		var b: Dictionary = s.bury
		var p := e.world.entities.get(d.victim) as Player
		var t: float = d.phase_time
		if p != null:
			e.face_towards(p.pos, e.def.turn_speed, dt)
		if t < b.step_time:
			e.velocity = -MathUtil.dir_from_angle(e.facing) * (b.step_back / b.step_time)   # 退一步
			return
		var flame_at: float = b.step_time + b.open
		if t >= flame_at:
			while d.ticks < mini(floori((t - flame_at + 1e-6) / b.tick) + 1, roundi(b.flame / b.tick)):
				d.ticks += 1
				var shape := {"shape": &"sector", "range": b.range, "arc": b.arc}
				for x in Hitbox.query(e.world, e.team, e.pos, e.facing, shape, e.id):
					if x is Player:
						x.invuln_timer = 0.0
				Hitbox.strike(e.world, e, e.pos, e.facing, shape, {
					"damage": b.damage * e.damage_mul, "knockback": 0.0, "blockable": true, "color": e.def.lantern.color,
					"damage_type": &"fire", "tier": &"light", "pierce_invuln": true,
				})
		if t >= flame_at + b.flame + b.recovery:
			fsm.change(&"chase")

	# 被抓的人以外的人打守墓人：累積 break_damage 就中斷連段
	func on_damaged(e: Gravekeeper, amount: float, source_id: int, fsm: StateMachine) -> void:
		var d := fsm.data
		if d.victim == 0 or source_id == d.victim:
			return
		d.taken += amount
		if d.taken >= e.def.scoop.break_damage:
			e.world.emit_event("boss:scoop_broken", {"boss_id": e.id})
			fsm.change(&"chase")

	# 結束（中斷、變身）時埋著的人立刻爬出
	func _release(e: Gravekeeper, d: Dictionary) -> void:
		var p := e.world.entities.get(d.get("victim", 0)) as Player
		if p != null and p.bury_mash >= 0.0:
			p.stun_timer = 0.0
			p.bury_mash = -1.0


# ───────── 第二型態：墓園狼人 ─────────

# 變身：站著不動、無敵 transform.time 秒（畫面層：抖動、撐破衣服）→ _become_wolf
class Transform:
	func enter(e: Gravekeeper, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.set_size(e.def.grow.size)   # 還在變大中就被打到半血：直接長滿
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


# 三連爪：雙爪往後拉 windup（轉向）→ 每 interval 秒抓一下（扇形，發 fx:claw 畫 3 條紅色爪痕），第三下往前撲 lunge（擋不住）→ recovery
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
				"blockable": not last, "is_heavy": last, "color": e.def.hit_color, "pierce_invuln": d.swipes > 1, "tier": c.tiers[d.swipes - 1],
			})
			# 爪痕：第一下右爪、第二下左爪（斜的方向相反），第三下雙爪一起（side 0）
			e.world.emit_event("fx:claw", {"pos": e.pos, "height": e.height, "facing": e.facing, "range": c.range, "arc": c.arc,
				"side": [1, -1, 0][d.swipes - 1], "color": c.color})
		var last_at: float = c.windup + c.interval * 2.0
		if t >= last_at and t < last_at + c.lunge_time:
			e.velocity = MathUtil.dir_from_angle(e.facing) * (c.lunge / c.lunge_time)   # 第三下往前撲
		if t >= last_at + c.recovery:
			e.resume()


# 飛撲：四肢著地蹲低 windup（轉向）→ 跳到目標當時的位置（flight 秒，fx:dirt_lob 只畫影子）→ 落地範圍傷害（擋不住、擊倒）→ recovery
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
					"is_heavy": true, "color": e.def.hit_color, "tier": l.tier,
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
				var dog := e.world.spawner.spawn_at(e.world, &"hound", nav.nearest_walkable(e.pos + MathUtil.dir_from_angle(a) * (e.radius + 1.5)))
				Spawner.roll_rarity(e.world, dog, MonsterRarityDefs.MAGIC)
				dog.no_souls = true
				dog.summoner_id = e.id
			e.set_stat_source(&"howl", [[&"move_speed", Stats.MUL, h.speed_mul]])
			e.howl_left = h.buff_time
		if fsm.time >= h.windup + h.recovery:
			e.resume()
