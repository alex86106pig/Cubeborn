# 挖墳事件、難度、換層、Boss 獎勵、屍體與冤魂（D6）的自動檢查，由 tests/check.gd 呼叫；每個函式回傳 "" = 通過，否則是失敗原因
class_name EventChecks

const DT := 1.0 / 60.0
const EPS := 1e-3

static var _made: Array[World] = []


static func cleanup() -> void:
	for w in _made:
		w.clear()
	_made.clear()


# 地圖 A（不放怪群）；spawn = false 時事件不生怪（只測挖墳本身）
static func _world(peers: Array[int] = [World.HOST_PEER_ID], spawn := false) -> World:
	var w := World.new(&"graveyard_a")
	w.spawn_packs = false
	w.reset(12345, peers)
	w.spawner.finished = not spawn
	_made.append(w)
	return w


static func _cmd(buttons := 0, move := Vector2.ZERO) -> InputCmd:
	var c := InputCmd.new()
	c.buttons = buttons
	c.move = move
	c.aim = Vector2(0, 5)
	return c


# 所有人同一個輸入跑 n 步（keep_hp：每步補滿血）
static func _step(w: World, n: int, cmds: Dictionary = {}, keep_hp := true) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in n:
		var c := {}
		for peer: int in w.players:
			c[peer] = cmds.get(peer, _cmd())
		w.step(c, DT)
		events.append_array(w.events)
		if keep_hp:
			for p in w.player_list:
				if not p.is_dead and not p.is_downed:
					p.hp = p.max_hp
	return events


static func _named(events: Array[Dictionary], name: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.name == name)


static func _p(w: World, peer: int = World.HOST_PEER_ID) -> Player:
	return w.players[peer]


# ───────── 挖墳 ─────────

static func check_dig() -> String:
	var w := _world()
	var p := _p(w)
	p.pos = w.event.point + Vector2(1.5, 0.0)
	var dig := {World.HOST_PEER_ID: _cmd(InputCmd.BTN_INTERACT)}
	var ev := _step(w, 1, dig)
	if w.event.state != DigEvent.ACTIVE or _named(ev, "event:started").is_empty() or not p.is_digging():
		return "按住 F 第一步應開始事件並進入挖墳（狀態 %s、動作 %s）" % [w.event.state, p.action.current_name]
	# 挖墳中不能移動、不能跳
	var at := p.pos
	ev.append_array(_step(w, 30, {World.HOST_PEER_ID: _cmd(InputCmd.BTN_INTERACT | InputCmd.BTN_JUMP, Vector2(1, 0))}))
	if p.pos.distance_to(at) > EPS or p.height > EPS:
		return "挖墳中移動了 %.3f、高度 %.2f" % [p.pos.distance_to(at), p.height]
	# 挖墳中照樣跟著滑鼠轉向（v0.38.0 使用者要求）：瞄準正東 → facing = π/2
	var look := _cmd(InputCmd.BTN_INTERACT)
	look.aim = p.pos + Vector2(10, 0)
	ev.append_array(_step(w, 20, {World.HOST_PEER_ID: look}))
	if not p.is_digging() or absf(angle_difference(p.facing, PI / 2.0)) > 0.01:
		return "挖墳中應跟著滑鼠轉向：挖墳 %s、朝向 %.2f（預期 %.2f）" % [p.is_digging(), p.facing, PI / 2.0]
	# 一人挖 30 秒 = 30 / DIG.time，加上這段時間每次噴怪的 +ERUPT.progress（前面已經挖了 51 步）
	var dig_time: float = EventDefs.DIG.time
	ev.append_array(_step(w, roundi(dig_time / 2.0 / DT) - 51, dig))
	var erupts := _named(ev, "event:erupted").size()
	var want_half: float = 0.5 + erupts * EventDefs.ERUPT.progress
	if erupts != floori(dig_time / 2.0 / EventDefs.ERUPT.interval) or absf(w.event.progress - want_half) > 0.01:
		return "挖 %.0f 秒（噴怪 %d 次）進度 %.3f，預期 %.3f" % [dig_time / 2.0, erupts, w.event.progress, want_half]
	# 被打不中斷、不會被擊退出挖墳範圍
	var hit_at := p.pos
	p.take_damage(10.0, Vector2(1, 0), 20.0, 0)
	_step(w, 20, dig)
	if not p.is_digging() or p.pos.distance_to(hit_at) > 0.05:
		return "挖墳中被打就中斷了或被擊退（動作 %s、移動 %.2f）" % [p.action.current_name, p.pos.distance_to(hit_at)]
	# 一圈骷髏擠過來也推不走（3 秒）
	for i in 8:
		var a := TAU * i / 8.0
		w.spawner.spawn_at(w, &"grunt", p.pos + Vector2(sin(a), cos(a)) * 1.2)
	_step(w, 180, dig)
	var crowd_ok := p.is_digging() and p.pos.distance_to(hit_at) < 0.1
	for e in w.enemies:
		e.remove()
	if not crowd_ok:
		return "被骷髏圍住時被擠走 %.2f 或中斷挖墳" % p.pos.distance_to(hit_at)
	# 放手 10 秒進度不掉，只有噴怪的 +ERUPT.progress
	var before := w.event.progress
	var ev_idle := _step(w, 600)
	var want_idle: float = before + _named(ev_idle, "event:erupted").size() * EventDefs.ERUPT.progress
	if p.is_digging() or absf(w.event.progress - want_idle) > 0.002:
		return "放手 10 秒進度 %.3f → %.3f，預期 %.3f（不掉，噴怪 %d 次）" % [before, w.event.progress, want_idle, _named(ev_idle, "event:erupted").size()]
	# 兩人：總量 DIG.time × 2，一起挖 10 秒 = 1 / 6；只有一人挖是一半（還沒到第一次噴怪）
	var w2 := _world([1, 2])
	_p(w2, 1).pos = w2.event.point + Vector2(1.5, 0.0)
	_p(w2, 2).pos = w2.event.point + Vector2(-1.5, 0.0)
	_step(w2, 590, {1: _cmd(InputCmd.BTN_INTERACT), 2: _cmd(InputCmd.BTN_INTERACT)})
	var two := 2.0 * (590 * DT) / (dig_time * 2.0)
	if absf(w2.event.progress - two) > 0.002:
		return "兩人一起挖 %.2f 秒進度 %.3f，預期 %.3f（總量 × 人數）" % [590 * DT, w2.event.progress, two]
	var w2b := _world([1, 2])
	_p(w2b, 1).pos = w2b.event.point + Vector2(1.5, 0.0)
	_step(w2b, 590, {1: _cmd(InputCmd.BTN_INTERACT)})
	if absf(w2b.event.progress - two / 2.0) > 0.002:
		return "兩人只有一人挖 %.2f 秒進度 %.3f，預期 %.3f" % [590 * DT, w2b.event.progress, two / 2.0]
	# 挖完：出口打開，不能再挖（一直挖 + 噴怪，DIG.time 秒內一定挖完）
	var w3 := _world()
	_p(w3).pos = w3.event.point + Vector2(1.5, 0.0)
	var ev3: Array[Dictionary] = []
	var open_steps := 0
	for i in roundi(dig_time / DT) + 2:
		ev3.append_array(_step(w3, 1, {World.HOST_PEER_ID: _cmd(InputCmd.BTN_INTERACT)}))
		if open_steps == 0 and w3.event.state == DigEvent.OPEN:
			open_steps = i + 1
	if w3.event.state != DigEvent.OPEN or _named(ev3, "event:exit_open").size() != 1 or _p(w3).is_digging():
		return "挖滿 %.0f 秒應打開出口並停止挖墳（狀態 %s）" % [dig_time, w3.event.state]
	CheckKit._note("一人一直挖：%.2f 秒挖完（DIG.time %.0f 秒 + 每 %.0f 秒噴怪 +%d%%）" % [open_steps * DT, dig_time, EventDefs.ERUPT.interval, roundi(EventDefs.ERUPT.progress * 100.0)])
	# 太遠挖不到
	var w4 := _world()
	_p(w4).pos = w4.event.point + Vector2(EventDefs.DIG.range + 0.3, 0.0)
	_step(w4, 10, {World.HOST_PEER_ID: _cmd(InputCmd.BTN_INTERACT)})
	if w4.event.state != DigEvent.IDLE:
		return "離挖墳點 %.1f 也挖得到" % (EventDefs.DIG.range + 0.3)
	return ""


# ───────── 難度與生怪 ─────────

static func check_difficulty() -> String:
	var dd: Dictionary = EventDefs.DIFFICULTY
	var sp: Dictionary = EventDefs.SPAWN
	var mul60: float = 1.0 + dd.stat_per_point * 60.0
	if absf(EventDefs.difficulty_mul(60.0).hp - mul60) > EPS:
		return "難度 60 怪物生命 ×%.2f，預期 ×%.2f" % [EventDefs.difficulty_mul(60.0).hp, mul60]
	# 生怪間隔：難度 0 = interval_start、每點 −interval_per_point，夾在 interval_min（取到夾住前的 1/4 處與夾住後）
	var clamp_at: float = (sp.interval_start - sp.interval_min) / sp.interval_per_point
	for c: Array in [[0.0, sp.interval_start], [clamp_at / 4.0, sp.interval_start - sp.interval_per_point * clamp_at / 4.0], [clamp_at * 1.125, sp.interval_min]]:
		if absf(EventDefs.spawn_interval(c[0]) - c[1]) > EPS:
			return "難度 %d 生怪間隔 %.2f，預期 %.2f" % [c[0], EventDefs.spawn_interval(c[0]), c[1]]
	# 每批數量：group_base + 難度 × group_per_point（捨去），每多 1 人 × (1 + per_extra_player)
	var d2: float = 2.0 / sp.group_per_point   # 多 2 隻的難度
	for c: Array in [[0.0, 1, sp.group_base], [d2, 1, sp.group_base + 2], [d2, 2, int((sp.group_base + 2) * (1.0 + sp.per_extra_player))]]:
		if EventDefs.group_size(c[0], c[1]) != c[2]:
			return "難度 %d、%d 人每批 %d 隻，預期 %d" % [c[0], c[1], EventDefs.group_size(c[0], c[1]), c[2]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var d200 := 200.0
	for c: Array in [[0.0, sp.magic_base, sp.rare_base],
			[d200, minf(sp.magic_max, sp.magic_base + sp.magic_per_point * d200), minf(sp.rare_max, sp.rare_base + sp.rare_per_point * d200)]]:
		var m := 0
		var r := 0
		for i in 20000:
			var x := EventDefs.roll_rarity(c[0], rng)
			m += 1 if x == MonsterRarityDefs.MAGIC else 0
			r += 1 if x == MonsterRarityDefs.RARE else 0
		if absf(m / 20000.0 - c[1]) > 0.015 or absf(r / 20000.0 - c[2]) > 0.015:
			return "難度 %d：魔法 %.1f%%、稀有 %.1f%%，預期 %.0f%% / %.0f%%" % [c[0], m / 200.0, r / 200.0, c[1] * 100, c[2] * 100]
	# 事件還沒開始：不冒怪、難度不漲（Boss 在巡邏，另外檢查）
	var w := _world([World.HOST_PEER_ID], true)
	var p := _p(w)
	var spawned := func() -> Array:
		return w.enemies.filter(func(e: Entity) -> bool: return e is Enemy and (e as Enemy).wave_member)
	_step(w, roundi(20.0 / DT))   # 玩家在出生點、每步補滿血，只等時間
	if not spawned.call().is_empty() or w.event.horde or absf(w.difficulty() - w.base_difficulty) > EPS:
		return "還沒挖墳的 20 秒內不應冒怪、難度不漲：冒了 %d 隻、怪潮 %s、難度 %.1f" % [spawned.call().size(), w.event.horde, w.difficulty()]
	# 開挖就開始怪潮（不等 Boss 倒下）：interval_start 秒後第一批 group_base 隻、難度每秒 +per_second
	(w.entities.get(w.boss_id) as Enemy).remove()   # Boss 會走過來打人、召喚，這裡只數事件生的怪
	p.pos = w.event.point + Vector2(1.5, 0.0)
	_step(w, 1, {World.HOST_PEER_ID: _cmd(InputCmd.BTN_INTERACT)})
	if not w.event.horde or w.event.state != DigEvent.ACTIVE:
		return "開挖後應立刻開始怪潮（狀態 %s、怪潮 %s）" % [w.event.state, w.event.horde]
	var first := roundi(EventDefs.SPAWN.interval_start / DT)
	_step(w, first - 3)
	if not spawned.call().is_empty():
		return "怪潮開始後 %.1f 秒前就冒怪了" % EventDefs.SPAWN.interval_start
	_step(w, 4)
	if spawned.call().size() != EventDefs.SPAWN.group_base:
		return "怪潮開始 %.1f 秒後應冒 %d 隻，實際 %d" % [EventDefs.SPAWN.interval_start, EventDefs.SPAWN.group_base, spawned.call().size()]
	if absf(w.difficulty() - (w.base_difficulty + EventDefs.SPAWN.interval_start)) > 0.1:
		return "事件 %.1f 秒時難度 %.2f，預期約 %.1f（每秒 +1）" % [EventDefs.SPAWN.interval_start, w.difficulty(), w.base_difficulty + EventDefs.SPAWN.interval_start]
	w.event.time = 60.0
	var g := w.spawner.spawn_at(w, &"grunt", w.event.point + Vector2(0, 6))
	var diff60: float = 60.0 * dd.per_second
	var hp60 := roundf(EnemyDefs.ENEMIES.grunt.max_hp * EventDefs.difficulty_mul(diff60).hp)   # 最大生命取整：46.8 → 47
	if absf(w.difficulty() - diff60) > 0.01 or absf(g.max_hp - hp60) > EPS:
		return "難度 %.1f 時骷髏生命 %.1f，預期 %.0f / %.0f" % [w.difficulty(), g.max_hp, diff60, hp60]
	# 選角畫面的難度（2026-10-27）：同樣 60 秒，簡單 / 普通 / 困難的難度是 ×rate；重新開始保留選的檔位
	for m: StringName in EventDefs.MODE_ORDER:
		w.difficulty_mode = m
		var want: float = w.base_difficulty + 60.0 * dd.per_second * EventDefs.MODES[m].rate
		if absf(w.difficulty() - want) > 0.01:
			return "難度「%s」怪潮 60 秒時應是 %.1f，實際 %.1f" % [EventDefs.MODES[m].name, want, w.difficulty()]
	w.difficulty_mode = &"hard"
	w.reset(7)
	var kept := w.difficulty_mode
	w.difficulty_mode = EventDefs.DEFAULT_MODE
	if kept != &"hard":
		return "重新開始應保留選的難度，實際 %s" % kept
	# 怪群不擋事件生怪：放滿怪群（休眠）也照樣冒
	var w2 := World.new(&"graveyard_a")
	_made.append(w2)
	w2.reset(12345)
	var before := w2.enemies.size()
	w2.event._start(w2)
	_step(w2, roundi(EventDefs.SPAWN.interval_start / DT) + 3)
	var horde := w2.enemies.filter(func(e: Entity) -> bool: return e is Enemy and (e as Enemy).wave_member and not e.is_dead).size()
	var min_packed: int = MonsterRarityDefs.PACKS.count[0] * MonsterRarityDefs.PACKS.size[0]
	if before < min_packed or horde < EventDefs.SPAWN.group_base:
		return "有 %d 隻怪群時事件沒有冒怪（冒了 %d 隻）" % [before, horde]
	return _check_erupt()


# 挖墳點噴怪：每 interval 秒（前 warning 秒墳土隆起，不畫圈）噴出 erupt_count 隻下一層難度的怪、進度 +progress；
# 噴出的怪照拋物線飛到 land_distance 外、空中不行動，落地後開始追；挖完就不再冒怪、難度不再漲，場上的怪留著
static func _check_erupt() -> String:
	var c: Dictionary = EventDefs.ERUPT
	for t: Array in [[0.0, 1, c.count_base], [20.0, 1, c.count_base + 1], [20.0, 2, int((c.count_base + 1) * (1.0 + EventDefs.SPAWN.per_extra_player))]]:
		if EventDefs.erupt_count(t[0], t[1]) != t[2]:
			return "難度漲 %d、%d 人一次噴 %d 隻，預期 %d" % [t[0], t[1], EventDefs.erupt_count(t[0], t[1]), t[2]]
	var w := _world([World.HOST_PEER_ID], true)
	var p := _p(w)
	_step(w, 1)
	(w.entities.get(w.boss_id) as Enemy).remove()
	w.event._start(w)
	w.event.spawn_timer = 1e9   # 只看噴怪（怪潮另外檢查）
	var steps := roundi(c.interval / DT)
	var warn := roundi((c.interval - c.warning) / DT)
	var ev := _step(w, warn + 1)
	var warns := _named(ev, "fx:erupt_warn").filter(func(e: Dictionary) -> bool: return e.pos.distance_to(w.event.point) < EPS)
	if warns.size() != 1 or absf(warns[0].life - c.warning) > EPS or not _named(ev, "event:erupted").is_empty():
		return "噴怪前 %.1f 秒挖墳點的墳土應開始隆起一次（隆起 %d 次、已噴 %d 次）" % [c.warning, warns.size(), _named(ev, "event:erupted").size()]
	if not _named(ev, "fx:telegraph").is_empty():
		return "噴怪前不應畫預警圈"
	var before := w.event.progress
	ev = _step(w, steps - warn)
	var launched := w.enemies.filter(func(e: Entity) -> bool: return (e as Enemy).is_launching())
	var want := EventDefs.erupt_count(w.difficulty() - w.base_difficulty, 1)
	if _named(ev, "event:erupted").size() != 1 or launched.size() != want or absf(w.event.progress - before - c.progress) > EPS:
		return "第 %.0f 秒應噴 %d 隻、進度 +%.2f（噴 %d 次、%d 隻在空中、進度 +%.3f）" % [c.interval, want, c.progress, _named(ev, "event:erupted").size(), launched.size(), w.event.progress - before]
	var g: Enemy = launched[0]
	var hp_next := roundf(EnemyDefs.ENEMIES[g.type].max_hp * EventDefs.difficulty_mul(w.difficulty() + EventDefs.DIFFICULTY.per_floor).hp)
	if g.rarity == MonsterRarityDefs.NORMAL and absf(g.max_hp - hp_next) > 1.0:
		return "噴出的怪生命 %.0f，預期下一層難度的 %.0f" % [g.max_hp, hp_next]
	var top := 0.0
	for i in roundi(c.flight_time / DT) + 10:
		_step(w, 1)
		top = maxf(top, g.height)
		if g.is_launching() and g.anim.state != &"launch":
			return "空中的怪動畫狀態應是 launch"
	var flown := g.pos.distance_to(w.event.point)
	if g.is_launching() or not g.is_grounded() or top < 2.0 or flown < c.land_distance[0] - 1.0 or flown > c.land_distance[1] + 1.0:
		return "噴出的怪應飛起 2 以上、落在 %.0f~%.0f 外並開始行動（最高 %.2f、落點 %.1f、狀態 %s）" % [c.land_distance[0], c.land_distance[1], top, flown, g.fsm.current_name]
	CheckKit._note("噴怪：一次 %d 隻、最高 %.2f、飛 %.1f 秒落在挖墳點 %.1f 外" % [want, top, c.flight_time, flown])
	# 挖完：不再冒怪、難度不漲，場上的留著
	w.event.progress = 0.99
	p.pos = w.event.point + Vector2(1.5, 0.0)
	_step(w, 60, {World.HOST_PEER_ID: _cmd(InputCmd.BTN_INTERACT)})
	if w.event.state != DigEvent.OPEN or w.event.horde:
		return "挖到 100%% 應打開出口、停止怪潮（狀態 %s、怪潮 %s）" % [w.event.state, w.event.horde]
	var left := w.enemies.size()
	var diff := w.difficulty()
	w.event.spawn_timer = 0.0
	ev = _step(w, roundi((c.interval + 6.0) / DT))
	if _named(ev, "event:erupted").size() != 0 or w.enemies.size() > left or absf(w.difficulty() - diff) > EPS:
		return "挖完後不應再冒怪、難度不漲（噴 %d 次、怪 %d → %d、難度 %.1f → %.1f）" % [_named(ev, "event:erupted").size(), left, w.enemies.size(), diff, w.difficulty()]
	if left < want:
		return "挖完時場上的怪不該消失（剩 %d 隻）" % left
	return ""


# ───────── 出口與換層 ─────────

static func _open(w: World) -> void:
	w.event._start(w)
	w.event.state = DigEvent.OPEN
	w.event.horde = false
	w.event.progress = 1.0


static func check_next_floor() -> String:
	# 單人：挖完後走到墳墓旁不會自動走；離太遠按 F 沒用；在旁邊按 F，最後一層（last_floor）直接通關
	var w := _world()
	var p := _p(w)
	_open(w)
	var f := {World.HOST_PEER_ID: _cmd(InputCmd.BTN_INTERACT)}
	p.pos = w.event.point + Vector2(EventDefs.DIG.range + 0.5, 0.0)
	_step(w, 1, f)
	_step(w, 1)
	p.pos = w.event.point
	_step(w, 30)
	if w.is_over or w.floor_num != 1 or w.event.is_voting():
		return "沒在墳墓旁按 F 就通關 / 換層了"
	var ev := _step(w, 1, f)
	if not w.is_over or w.floor_num != 1 or w.event.is_voting() or not _named(ev, "vote:started").is_empty():
		return "單人第 %d 層（last_floor %d）按 F 應直接通關、不跳投票（通關 %s）" % [w.floor_num, EventDefs.DIG.last_floor, w.is_over]
	ev = _step(w, roundi(Config.WORLD.victory_delay / DT) + 2)
	if _named(ev, "game:victory").size() != 1:
		return "通關後 victory_delay 秒應發出 game:victory"
	var vote_err := _check_vote()
	if vote_err != "":
		return vote_err
	# 換層本身（不是最後一層時由投票通過呼叫 World.next_floor）
	w = _world()
	p = _p(w)
	w.souls = 40
	p.add_item(&"whetstone")
	_open(w)
	w.drop_item(&"worn_boots", w.event.point + Vector2(5, 5))
	(w.chests[0] as Chest).opened = true
	p.pos = w.event.point
	w.next_floor()
	ev = w.events.duplicate()   # 不跑下一步：下一步會放新一層的 Boss
	var per_floor: float = EventDefs.DIFFICULTY.per_floor
	if w.floor_num != 2 or absf(w.base_difficulty - per_floor) > EPS or _named(ev, "floor:started").is_empty():
		return "換層後應到第 2 層、基礎難度 %.0f（實際第 %d 層、%.1f）" % [per_floor, w.floor_num, w.base_difficulty]
	if p.pos.distance_to(w.spawn_point) > EPS or p.descended:
		return "新的一層應回到出生點"
	if w.souls != 40 or CheckKit._held_items(p).size() != 1:
		return "換層後靈魂 %d、拿著的道具 %d 件，應保留 40 / 1" % [w.souls, CheckKit._held_items(p).size()]
	var want_chests := 0
	for n: int in w.map.chest_count.values():
		want_chests += n
	if not w.pickups.is_empty() or w.event.state != DigEvent.IDLE or w.chests.size() != want_chests or (w.chests[0] as Chest).opened:
		return "換層後地上的東西要清掉、寶箱重放（%d / %d 個）、事件歸零（地上 %d、事件 %s）" % [w.chests.size(), want_chests, w.pickups.size(), w.event.state]
	if not w.enemies.is_empty():
		return "換層後還有 %d 隻怪" % w.enemies.size()
	# 第 2 層的怪群用基礎難度 per_floor 的生命倍率
	var w5 := World.new(&"graveyard_a")
	_made.append(w5)
	w5.reset(7)
	w5.next_floor()
	var normal: Enemy = null
	for e in w5.enemies:
		if (e as Enemy).rarity == MonsterRarityDefs.NORMAL and e.kind == &"grunt":
			normal = e
			break
	var hp2 := roundf(EnemyDefs.ENEMIES.grunt.max_hp * EventDefs.difficulty_mul(per_floor).hp)   # 37.8 取整 38
	if normal == null or absf(normal.max_hp - hp2) > EPS:
		return "第 2 層普通骷髏生命 %.2f，預期 %.0f" % [normal.max_hp if normal else 0.0, hp2]
	return ""


# 多人投票：一人在墳墓旁按 F 發起（他算同意）；別人 Esc 反對就取消；全員 Enter 同意或 VOTE.time 秒到就走；死掉的不用投
static func _check_vote() -> String:
	var w := _world([1, 2, 3])
	_open(w)
	_p(w, 1).pos = w.event.point
	var ev := _step(w, 1, {1: _cmd(InputCmd.BTN_INTERACT)})
	if not w.event.is_voting() or w.event.vote_by != 1 or w.event.vote_yes != [1] or _named(ev, "vote:started").size() != 1 or w.is_over:
		return "多人在墳墓按 F 應發起投票（投票中 %s、同意 %s、通關 %s）" % [w.event.is_voting(), w.event.vote_yes, w.is_over]
	if w.event.awaits_vote(1) or not w.event.awaits_vote(2):
		return "發起人算同意、其他人要回答"
	_step(w, 1, {2: _cmd(InputCmd.BTN_VOTE_YES)})
	ev = _step(w, 1, {3: _cmd(InputCmd.BTN_VOTE_NO)})
	if w.event.is_voting() or w.is_over or _named(ev, "vote:canceled").size() != 1:
		return "有人按 Esc 反對應取消投票（投票中 %s、通關 %s）" % [w.event.is_voting(), w.is_over]
	# 再發起：全員同意就走
	_step(w, 1)
	_step(w, 1, {1: _cmd(InputCmd.BTN_INTERACT)})
	_step(w, 1, {2: _cmd(InputCmd.BTN_VOTE_YES)})
	if w.is_over:
		return "還有一人沒同意就走了"
	ev = _step(w, 1, {3: _cmd(InputCmd.BTN_VOTE_YES)})
	if not w.is_over or _named(ev, "vote:passed").size() != 1:
		return "全員同意應前往下一層（最後一層 = 通關）"
	# 時間到：沒人回答也走
	var w2 := _world([1, 2])
	_open(w2)
	_p(w2, 2).pos = w2.event.point
	_step(w2, 1, {2: _cmd(InputCmd.BTN_INTERACT)})
	_step(w2, roundi(EventDefs.VOTE.time / DT) - 5)
	if w2.is_over or not w2.event.is_voting():
		return "投票 %.0f 秒還沒到就結束了" % EventDefs.VOTE.time
	_step(w2, 10)
	if not w2.is_over:
		return "投票 %.0f 秒到了應前往下一層" % EventDefs.VOTE.time
	# 死掉的不用投：另一人陣亡時，按 F 直接走
	var w3 := _world([1, 2])
	_open(w3)
	_p(w3, 2).die()
	_p(w3, 2).die()
	_p(w3, 1).pos = w3.event.point
	_step(w3, 1, {1: _cmd(InputCmd.BTN_INTERACT)}, false)
	if not w3.is_over:
		return "隊友陣亡時活著的人按 F 應直接走"
	return ""


# ───────── Boss 獎勵 ─────────

static func check_boss_reward() -> String:
	var w := _world([World.HOST_PEER_ID], true)
	_step(w, 1)   # 第一步放 Boss
	var boss: Enemy = w.entities.get(w.boss_id)
	var souls := w.souls
	boss.take_damage(1e6, Vector2(1, 0), 0.0, 0)
	var ev := _step(w, 3)
	var weapons := 0
	var items := 0
	for pk in w.pickups:
		if (pk as ItemPickup).is_weapon():
			weapons += 1
		elif ItemDefs.ITEMS[(pk as ItemPickup).item_id].kind == &"item":
			items += 1
	if w.is_over or not _named(ev, "game:victory").is_empty():
		return "挖墳地圖打倒 Boss 不該通關"
	var relics := w.relics.filter(func(r: Entity) -> bool: return (r as Relic).tier == &"big").size()
	if weapons != 1 or items != 0 or relics != 1 or w.souls != souls + LootDefs.KILL_SOULS.boss:   # v0.44.0 Boss 靈魂 50 → 30
		return "Boss 應掉 1 把武器、1 個石棺的遺物、%d 靈魂（實際 %d / 遺物 %d、道具 %d / %d）" % [LootDefs.KILL_SOULS.boss, weapons, relics, items, w.souls - souls]
	return _check_boss_patrol()


static func _check_boss_patrol() -> String:
	var w := _world([World.HOST_PEER_ID], true)
	var p := _p(w)   # 在出生點（王族墓外、南邊很遠）
	_step(w, 1)
	var room: Array = w.map.boss_room
	var rect := Rect2(MapDefs.to_world(w.map, Vector2(room[0], room[1])), Vector2(room[2], room[3])).grow(1.0)
	# 第 1 層的守墓人假裝 NPC、看到人不追（另有檢查）；「看到就追」的巡邏是亡骸騎士的（第 2 層用），換成它來檢查
	var keeper: Enemy = w.entities.get(w.boss_id)
	var at := keeper.pos
	keeper.remove()
	var boss := w.spawner.spawn_at(w, &"boss", w.nav_for(EnemyDefs.ENEMIES.boss.radius).nearest_walkable(at), {"initial_state": &"patrol"}) as Boss
	boss.patrol_rect = Rect2(MapDefs.to_world(w.map, Vector2(room[0], room[1])), Vector2(room[2], room[3]))
	if boss == null or not boss.is_patrolling() or not rect.has_point(boss.pos):
		return "開局 Boss 應在 boss_room 裡巡邏（Boss %s、狀態 %s）" % [boss != null, boss.fsm.current_name if boss else &""]
	var walked := 0.0
	for i in roundi(40.0 / DT):
		var before := boss.pos
		_step(w, 1)
		walked += boss.pos.distance_to(before)
		if not boss.is_patrolling() or not rect.has_point(boss.pos):
			return "沒看到玩家時 Boss 應一直在範圍內巡邏（第 %.1f 秒：狀態 %s、位置 %s）" % [i * DT, boss.fsm.current_name, boss.pos]
	if walked < 5.0:
		return "Boss 巡邏 40 秒只走了 %.1f" % walked
	# 走到 Boss 面前（視野內、沒被牆擋）：開始追，之後跟著玩家走出範圍
	p.pos = boss.pos + MathUtil.dir_from_angle(boss.facing) * 6.0
	p.pos = w.nav.nearest_walkable(p.pos)
	var ev := _step(w, 2)
	if boss.is_patrolling() or _named(ev, "boss:aggro").size() != 1:
		return "玩家在 Boss 前方 6 應被發現（狀態 %s）" % boss.fsm.current_name
	p.pos = w.spawn_point
	var left := false
	for i in roundi(30.0 / DT):
		_step(w, 1)
		if not rect.has_point(boss.pos):
			left = true
			break
	if not left:
		return "Boss 開始追之後應能離開巡邏範圍追玩家"
	# 被打也會開始追（玩家在背後、看不到）
	var w2 := _world([World.HOST_PEER_ID], true)
	_step(w2, 1)
	var b2: Boss = w2.entities.get(w2.boss_id)
	b2.take_damage(1.0, Vector2.ZERO, 0.0, _p(w2).id)
	_step(w2, 1)
	if b2.is_patrolling():
		return "Boss 被打應開始追"
	CheckKit._note("Boss 巡邏 40 秒走了 %.1f" % walked)
	return ""


# ───────── 屍體與冤魂 ─────────

static func check_corpse_ghost() -> String:
	var w := _world([1, 2])
	var a := _p(w, 1)
	var b := _p(w, 2)
	b.pos = a.pos + Vector2(3, 0)
	b.die()
	b.die()   # 倒地後再死一次 = 真的死亡
	_step(w, 1, {}, false)
	if not b.is_dead:
		return "第二次 die 後應死亡"
	var corpse: ItemPickup = null
	for pk in w.pickups:
		if (pk as ItemPickup).corpse_of == 2:
			corpse = pk
	if corpse == null:
		return "多人時死亡應留下屍體"
	# 撿起：占屍體形狀的格數、沒有效果
	a.pos = corpse.pos + Vector2(0.6, 0)
	_step(w, 1, {1: _cmd(InputCmd.BTN_INTERACT)})
	var entry := a.inventory.find(Player.corpse_uid(2))
	var cells: int = ItemDefs.SHAPES[ItemDefs.ITEMS.corpse.shape].size()
	if entry.is_empty() or Inventory.cells_of(entry.id, entry.rot).size() != cells or not a.items.is_empty():
		return "撿起屍體應放進背包占 %d 格、不算生效道具" % cells
	# 換層：出現冤魂（離出生點 GHOST.distance）
	w.next_floor()
	var ghost: Enemy = null
	for e in w.enemies:
		if (e as Enemy).ghost_of == 2:
			ghost = e
	if w.floor_num != 2 or ghost == null or ghost.kind != &"ghost":
		return "背著屍體換層後應出現冤魂"
	var d := ghost.pos.distance_to(w.spawn_point)
	if d < EventDefs.GHOST.distance[0] - 1.0 or d > EventDefs.GHOST.distance[1] + 1.0:
		return "冤魂離出生點 %.1f，預期 %.0f~%.0f" % [d, EventDefs.GHOST.distance[0], EventDefs.GHOST.distance[1]]
	# 打倒冤魂：在那裡復活 revive_hp_ratio 的血、屍體從背包消失
	var at := ghost.pos
	ghost.take_damage(1e6, Vector2(1, 0), 0.0, a.id)
	_step(w, 1, {}, false)
	var ratio: float = EventDefs.GHOST.revive_hp_ratio
	if b.is_dead or absf(b.hp - roundf(b.max_hp * ratio)) > EPS or b.pos.distance_to(at) > 0.5:
		return "打倒冤魂後應在冤魂位置復活、%.0f%% 血（死亡 %s、血 %.0f）" % [ratio * 100.0, b.is_dead, b.hp]
	if not a.inventory.find(Player.corpse_uid(2)).is_empty():
		return "復活後屍體應從背包消失"
	# 沒人帶屍體：下一層沒有冤魂
	var w2 := _world([1, 2])
	_p(w2, 2).die()
	_p(w2, 2).die()
	w2.next_floor()
	for e in w2.enemies:
		if (e as Enemy).ghost_of != 0:
			return "沒人帶屍體也出現冤魂"
	return ""


# 連線：層數、事件狀態、進度、走進出口、屍體的主人傳到客戶端
static func check_net_event() -> String:
	var w := _world([1, 2])
	_open(w)
	w.event.progress = 1.0
	w.event.time = 12.5
	w.floor_num = 3
	w.base_difficulty = 20.0
	_p(w, 1).descended = true
	var pk := w.drop_corpse(2, Vector2(3, 3))
	var snap: Array = bytes_to_var(var_to_bytes(NetCodec.make_snapshot(w, NetCodec.encode_entities(w), 0)))
	NetCodec.decode_snapshot(snap)
	var cw := World.new(&"graveyard_a")
	cw.is_authority = false
	_made.append(cw)
	NetCodec.apply_world(cw, snap)
	for a: Array in snap[NetCodec.S_ENTITIES]:
		NetCodec.create_entity(cw, a)
	var diff: float = 20.0 + 12.5 * EventDefs.DIFFICULTY.per_second
	if cw.floor_num != 3 or cw.event.state != DigEvent.OPEN or absf(cw.difficulty() - diff) > EPS:
		return "客戶端層數 %d、事件 %s、難度 %.1f，預期 3 / open / %.1f" % [cw.floor_num, cw.event.state, cw.difficulty(), diff]
	# 怪潮開始了沒（v0.38.0，HUD 進度條的說明文字要用）
	if cw.event.horde != w.event.horde:
		return "客戶端的怪潮狀態 %s，房主 %s" % [cw.event.horde, w.event.horde]
	w.event.horde = true
	var snap2: Array = bytes_to_var(var_to_bytes(NetCodec.make_snapshot(w, NetCodec.encode_entities(w), 0)))
	NetCodec.decode_snapshot(snap2)
	NetCodec.apply_world(cw, snap2)
	if not cw.event.horde:
		return "房主怪潮開始後，客戶端應同步 horde = true"
	var mp: Player = cw.players.get(1)
	var mc: ItemPickup = cw.entities.get(pk.id)
	if mp == null or not mp.descended or mc == null or mc.corpse_of != 2:
		return "客戶端的「已進出口」或屍體主人沒同步"
	if cw.event.point.distance_to(w.event.point) > EPS:
		return "客戶端的挖墳點不同"
	# 投票（HUD 的橫幅與 Enter / Esc 提示要用）
	w.event.vote_by = 2
	w.event.vote_left = 7.5
	w.event.vote_yes.assign([2, 1])
	var snap3: Array = bytes_to_var(var_to_bytes(NetCodec.make_snapshot(w, NetCodec.encode_entities(w), 0)))
	NetCodec.decode_snapshot(snap3)
	NetCodec.apply_world(cw, snap3)
	if cw.event.vote_by != 2 or absf(cw.event.vote_left - 7.5) > EPS or cw.event.vote_yes != [2, 1] or cw.event.awaits_vote(1):
		return "客戶端的投票狀態沒同步（發起 %d、剩 %.1f、同意 %s）" % [cw.event.vote_by, cw.event.vote_left, cw.event.vote_yes]
	return ""
