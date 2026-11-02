# 怪物稀有度、詞條與怪群（D5）的自動檢查，由 tests/check.gd 呼叫；每個函式回傳 "" = 通過，否則是失敗原因
class_name MonsterChecks

const DT := 1.0 / 60.0
const EPS := 1e-3

static var _made: Array[World] = []   # 建立過的 World：檢查中途失敗也能在最後 cleanup() 切斷循環參照


static func cleanup() -> void:
	for w in _made:
		w.clear()
	_made.clear()


static func _world(map_id: StringName = &"test_arena", packs := false, seed_value := 12345, spawner := false) -> World:
	var w := World.new(map_id)
	w.spawn_packs = packs
	w.reset(seed_value)
	w.spawner.finished = not spawner
	_made.append(w)
	return w


static func _step(w: World, n: int, keep_hp := false) -> void:
	var p: Player = w.players[World.HOST_PEER_ID]
	for i in n:
		w.step({World.HOST_PEER_ID: InputCmd.new()}, DT)
		if keep_hp:
			p.hp = p.max_hp


static func _grunt(w: World, at: Vector2, rarity: StringName, affixes: Array = []) -> Enemy:
	var e := w.spawner.spawn_at(w, &"grunt", at)
	e.set_rarity(rarity, affixes, "")
	e.apply_rarity_stats()
	return e


# ───────── 稀有度 ─────────

# 怪物種類只靠資料表區分（v0.42.1 重構）：behavior 對應得到行為類別、建出來的類別一致；is_boss / freeze_immune 照資料
static func check_enemy_defs() -> String:
	var w := _world()
	for type: StringName in EnemyDefs.ENEMIES:
		var d: Dictionary = EnemyDefs.ENEMIES[type]
		if Spawner.behavior_class(d.get("behavior", &"")) == null:
			return "%s 的 behavior「%s」沒有對應的類別" % [type, d.get("behavior", "")]
		var e := w.add_enemy(Spawner.create(w, type, Vector2.ZERO, WaveDefs.NO_SCALING.duplicate()))   # 加進 World：clear() 才會切斷循環參照（不加會洩漏）
		if e.get_script() != Spawner.behavior_class(d.behavior):
			return "%s 建出來的類別不對" % type
		if e.is_boss() != d.get("is_boss", false):
			return "%s 的 is_boss() 跟資料表不一致" % type
		e.apply_freeze(1.0)
		var immune: bool = d.get("freeze_immune", false)
		if (e.frozen_timer > 0.0) == immune:
			return "%s 冰凍：資料表 freeze_immune=%s，實際 frozen_timer=%.1f" % [type, immune, e.frozen_timer]
	if not EnemyDefs.ENEMIES.has(EventDefs.DIG.boss_type) or not EnemyDefs.is_boss(EventDefs.DIG.boss_type):
		return "挖墳事件的 boss_type 不是 Boss：%s" % EventDefs.DIG.boss_type
	return ""


static func check_rarity() -> String:
	var w := _world()
	var gd: Dictionary = EnemyDefs.ENEMIES.grunt
	var body: float = Config.HEIGHT.body.grunt
	var rd: Dictionary = MonsterRarityDefs.RARITIES[MonsterRarityDefs.RARE]
	var rare := _grunt(w, Vector2(0, 10), MonsterRarityDefs.RARE)
	var rare_hp: float = gd.max_hp * rd.hp
	if absf(rare.max_hp - rare_hp) > EPS or absf(rare.hp - rare_hp) > EPS or absf(rare.damage_mul - rd.damage) > EPS:
		return "稀有骷髏：生命 %.1f / %.1f、攻擊力 ×%.2f，預期 %.0f / %.0f、×%.1f" % [rare.hp, rare.max_hp, rare.damage_mul, rare_hp, rare_hp, rd.damage]
	if absf(rare.radius - gd.radius * rd.scale) > EPS or absf(rare.body_height - body * rd.scale) > EPS:
		return "稀有骷髏體型：半徑 %.3f、身高 %.3f，預期 %.2f、%.2f" % [rare.radius, rare.body_height, gd.radius * rd.scale, body * rd.scale]
	var md: Dictionary = MonsterRarityDefs.RARITIES[MonsterRarityDefs.MAGIC]
	var magic := _grunt(w, Vector2(5, 10), MonsterRarityDefs.MAGIC)
	var magic_hp: float = gd.max_hp * md.hp
	if absf(magic.max_hp - magic_hp) > EPS or absf(magic.damage_mul - md.damage) > EPS or absf(magic.radius - gd.radius * md.scale) > EPS:
		return "魔法骷髏：生命 %.1f、攻擊力 ×%.2f、半徑 %.2f，預期 %.0f、×%.1f、%.2f" % [magic.max_hp, magic.damage_mul, magic.radius, magic_hp, md.damage, gd.radius * md.scale]
	# 詞條數：魔法 1~2（每種條數都會出現）、稀有 3，不重複；稀有怪有名字
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 2000:
		for r: StringName in [MonsterRarityDefs.MAGIC, MonsterRarityDefs.RARE]:
			var list := MonsterRarityDefs.roll_affixes(MonsterRarityDefs.affix_count(r, rng), rng)
			var want: Array = MonsterRarityDefs.RARITIES[r].affixes
			if list.size() < want[0] or list.size() > want[1]:
				return "%s 抽到 %d 條詞條" % [r, list.size()]
			var uniq := {}
			for id in list:
				uniq[id] = true
			if uniq.size() != list.size():
				return "詞條重複：%s" % [list]
			if r == MonsterRarityDefs.MAGIC:
				seen[list.size()] = true
	var magic_range: Array = md.affixes
	for k in range(magic_range[0], magic_range[1] + 1):
		if not seen.has(k):
			return "魔法怪 2000 次只抽到 %s 條" % [seen.keys()]
	var named := w.spawner.spawn_at(w, &"grunt", Vector2(-5, 10))
	Spawner.roll_rarity(w, named, MonsterRarityDefs.RARE)
	var rare_range: Array = rd.affixes
	if named.rare_name == "" or named.affixes.size() < rare_range[0] or named.affixes.size() > rare_range[1]:
		return "稀有怪應有名字與 %d 條詞條：「%s」%s" % [rare_range[0], named.rare_name, named.affixes]
	# 每群：魔法 magic_per_pack 隻（取平均）、稀有 rare_chance 機率最多 1 隻（20000 群，誤差 ±1.5%）
	var pc: Dictionary = MonsterRarityDefs.PACKS
	var per_pack: Array = pc.magic_per_pack
	var magic_avg: float = (per_pack[0] + per_pack[1]) / 2.0
	var rares := 0
	var magics := 0
	for i in 20000:
		var list := MonsterRarityDefs.roll_pack_rarities(10, rng)
		var m := list.count(MonsterRarityDefs.MAGIC)
		var r := list.count(MonsterRarityDefs.RARE)
		if m < per_pack[0] or m > per_pack[1] or r > 1:
			return "一群有 %d 隻魔法、%d 隻稀有" % [m, r]
		magics += m
		rares += r
	if absf(rares / 20000.0 - pc.rare_chance) > 0.015 or absf(magics / 20000.0 - magic_avg) > 0.03:
		return "20000 群：稀有 %.1f%%（預期 %.0f%%）、每群魔法 %.2f 隻（預期 %.1f）" % [rares / 200.0, pc.rare_chance * 100.0, magics / 20000.0, magic_avg]
	return ""


# ───────── 詞條 ─────────

# ───────── 第 1 層怪物 ─────────

# 腐屍：站著不動被撲中 → 抓住 grab_time 秒、撲 1 下 + 每 bite_interval 咬一口；被抓時按翻滾立刻掙脫；
# 隊友打它就鬆手；舉盾擋下撲抱 → 不被抓、腐屍踉蹌 blocked_stagger 秒
static func check_zombie() -> String:
	var l: Dictionary = EnemyDefs.ENEMIES.zombie.lunge
	var bites := roundi(l.grab_time / l.bite_interval)
	for mode: StringName in [&"stand", &"roll", &"teammate", &"block"]:
		var w := _world()
		var p: Player = w.players[World.HOST_PEER_ID]
		p.pos = Vector2.ZERO
		p.stats.set_base(&"max_hp", 9999.0)
		p.hp = p.max_hp
		var z := w.spawner.spawn_at(w, &"zombie", Vector2(0, 1.2))
		var grabbed_at := -1
		var released_at := -1
		var hits := 0
		var staggered := false
		for i in 240:
			var cmd := InputCmd.new()
			cmd.aim = Vector2(0, 5)
			if mode == &"block":
				cmd.buttons = InputCmd.BTN_SPECIAL_HELD
			if grabbed_at >= 0 and released_at < 0:
				if mode == &"roll" and i == grabbed_at + 3:
					cmd.buttons = InputCmd.BTN_ROLL
				if mode == &"teammate" and i == grabbed_at + 3:
					Combat.apply_damage(w, p, z, {"damage": 1.0, "knockback": 0.0})   # 當成隊友打它（傷害來源是玩家）
			w.step({World.HOST_PEER_ID: cmd}, DT)
			for ev in w.events:
				if ev.name == "entity:damaged" and ev.target_id == p.id and ev.source_id == z.id:
					hits += 1
			if z.fsm.is_in(&"stagger"):
				staggered = true
			if grabbed_at < 0 and p.grabbed_by == z.id:
				grabbed_at = i
			elif grabbed_at >= 0 and released_at < 0 and p.grabbed_by == 0:
				released_at = i
				break   # 之後冷卻好又會再撲，不算進這次
			if mode == &"block" and staggered:
				break
		match mode:
			&"stand":
				if grabbed_at < 0 or released_at < 0:
					return "腐屍：站著不動應被撲中抓住再放開（抓住第 %d 步、放開第 %d 步）" % [grabbed_at, released_at]
				var held := (released_at - grabbed_at) * DT
				if absf(held - l.grab_time) > DT * 2.5:
					return "腐屍：抓住 %.3f 秒，預期 %.2f" % [held, l.grab_time]
				if hits != 1 + bites:
					return "腐屍：撲 1 下 + 咬 %d 口應有 %d 次傷害，實際 %d" % [bites, 1 + bites, hits]
			&"roll", &"teammate":
				if grabbed_at < 0 or released_at != grabbed_at + 3 or p.stun_timer > 0.0:
					return "腐屍：%s 應在第 %d 步放開（實際 %d、剩暈眩 %.2f）" % ["按翻滾" if mode == &"roll" else "隊友打它", grabbed_at + 3, released_at, p.stun_timer]
			&"block":
				if grabbed_at >= 0 or not staggered:
					return "腐屍：舉盾擋下撲抱應不被抓、腐屍踉蹌（被抓 %s、踉蹌 %s）" % [grabbed_at >= 0, staggered]
	return ""


# 膨脹屍：走到 trigger_distance 內停下脹大 swell_time 秒（被打不硬直）→ 自爆：玩家與旁邊的怪都受傷、不給靈魂、
# 留下腐氣（玩家與怪都持續受傷、不畫圈）；被打死的 death_delay 秒後照樣炸、給靈魂
static func check_bloater() -> String:
	var b: Dictionary = EnemyDefs.ENEMIES.bloater.burst
	var w := _world()
	var p: Player = w.players[World.HOST_PEER_ID]
	p.pos = Vector2.ZERO
	p.stats.set_base(&"max_hp", 9999.0)
	p.hp = p.max_hp
	var dummy := w.spawner.spawn_at(w, &"zombie", Vector2(1.2, 0.8))
	dummy.main_state = &"train"   # 旁邊站著不動的怪：看爆炸與腐氣會不會傷到它
	dummy.stats.set_base(&"knockback_taken", 0.0)   # 不被炸飛出腐氣範圍（這裡只看腐氣傷不傷得到怪）
	var bl := w.spawner.spawn_at(w, &"bloater", Vector2(0, 4))
	var swell_at := -1
	var burst_at := -1
	var stagger_tested := false
	var grabbed := false                      # 脹大開始時玩家被抱住了（撲抱撲中）
	var knocked := false
	var burst_damage := 0.0
	var hurt := {p.id: 0, dummy.id: 0}       # 爆炸那一步的傷害次數
	var gassed := {p.id: 0, dummy.id: 0}     # 之後腐氣的傷害次數
	var all_events: Array[Dictionary] = []
	for i in 60 * 10:
		w.step({World.HOST_PEER_ID: InputCmd.new()}, DT)
		all_events.append_array(w.events)
		if swell_at < 0 and bl.fsm.is_in(&"swell"):
			swell_at = i
			grabbed = p.grabbed_by == bl.id
		if swell_at >= 0 and not stagger_tested and i == swell_at + 10:
			stagger_tested = true
			Combat.apply_damage(w, p, bl, {"damage": 1.0, "knockback": 0.0})
			if not bl.fsm.is_in(&"swell"):
				return "膨脹屍：脹大中被打不應中斷（變成 %s）" % bl.fsm.current_name
		for ev in w.events:
			if ev.name == "entity:damaged" and ev.source_id == bl.id and hurt.has(ev.target_id):
				if burst_at < 0 or i == burst_at:
					hurt[ev.target_id] += 1
				else:
					gassed[ev.target_id] += 1
		if burst_at < 0 and (bl as Bloater).has_burst:
			burst_at = i
			knocked = p.knock_time > 0.0
			for ev in w.events:
				if ev.name == "entity:damaged" and ev.source_id == bl.id and hurt.has(ev.target_id):
					hurt[ev.target_id] = 1
					if ev.target_id == p.id:
						burst_damage = ev.amount
		if burst_at >= 0 and i > burst_at + roundi(EnemyDefs.ENEMIES.bloater.gas.duration / DT) + 5:
			break
	if swell_at < 0 or burst_at < 0:
		return "膨脹屍：10 秒內沒有脹大自爆（脹大第 %d 步、爆炸第 %d 步）" % [swell_at, burst_at]
	# 站著不動的玩家會被撲抱抱住：抱住時脹 hold_swell_time 就炸、多受 hold_bonus、擊倒（怪物圖鑑）
	if not grabbed:
		return "膨脹屍：站著不動的玩家應被撲抱抱住（脹大開始時 grabbed_by = %d）" % p.grabbed_by
	if absf((burst_at - swell_at) * DT - b.hold_swell_time) > DT * 2.5:
		return "膨脹屍：抱住後脹大 %.3f 秒才炸，預期 %.2f" % [(burst_at - swell_at) * DT, b.hold_swell_time]
	if absf(burst_damage - (b.damage + b.hold_bonus)) > 0.01 or not knocked:
		return "膨脹屍：抱住的玩家應受 %.0f 傷害並被擊倒：%.1f、擊倒 %s" % [b.damage + b.hold_bonus, burst_damage, knocked]
	if hurt[p.id] < 1 or hurt[dummy.id] < 1:
		return "膨脹屍：爆炸應炸到玩家與旁邊的怪（玩家 %d 次、怪 %d 次）" % [hurt[p.id], hurt[dummy.id]]
	if gassed[p.id] < 3 or gassed[dummy.id] < 3:
		return "膨脹屍：腐氣應持續傷害玩家與怪（玩家 %d 次、怪 %d 次）" % [gassed[p.id], gassed[dummy.id]]
	if not bl.is_dead or not bl.no_souls:
		return "膨脹屍：自爆後應死掉、不給靈魂"
	if all_events.any(func(ev: Dictionary) -> bool: return ev.name == "fx:telegraph") or not all_events.any(func(ev: Dictionary) -> bool: return ev.name == "fx:gas_cloud"):
		return "膨脹屍：腐氣不應畫圈（fx:telegraph），要冒煙（fx:gas_cloud）"
	# 被打死：death_delay 秒後照樣炸、給靈魂
	var w2 := _world()
	var p2: Player = w2.players[World.HOST_PEER_ID]
	var bl2 := w2.spawner.spawn_at(w2, &"bloater", Vector2(0, 12))
	_step(w2, roundi(EnemyDefs.ENEMIES.bloater.spawn_time / DT) + 2, true)
	Combat.apply_damage(w2, p2, bl2, {"damage": 9999.0, "knockback": 0.0})
	var died_tick := w2.tick
	for i in 120:
		_step(w2, 1, true)
		if (bl2 as Bloater).has_burst:
			break
	var delay := (w2.tick - died_tick) * DT
	if not (bl2 as Bloater).has_burst or absf(delay - b.death_delay) > DT * 2.5 or bl2.no_souls:
		return "膨脹屍：被打死後應 %.1f 秒炸（實際 %.3f、炸了 %s）、給靈魂（no_souls %s）" % [b.death_delay, delay, (bl2 as Bloater).has_burst, bl2.no_souls]
	# 魔法 / 稀有膨脹屍不抽死亡爆炸（自己就會炸，抽到會炸兩次）
	for i in 200:
		var bl3 := w2.spawner.spawn_at(w2, &"bloater", Vector2(0, 20))
		Spawner.roll_rarity(w2, bl3, MonsterRarityDefs.RARE)
		if bl3.has_affix(&"volatile"):
			return "膨脹屍不應抽到死亡爆炸詞條"
		bl3.remove()
	return ""


# 屍犬：玩家背對它 → 在視野外（含側面）就飛撲，patience 秒內做到；
# 玩家一直轉身看著它 → 正面牽制（側跳）、patience 秒內都不撲，之後才從正面撲；飛撲撲中擊倒
static func check_hound() -> String:
	var hd: Dictionary = EnemyDefs.ENEMIES.hound
	var start: float = hd.spawn_time + hd.prowl.patience
	for watch: bool in [false, true]:
		var w := _world()
		var p: Player = w.players[World.HOST_PEER_ID]
		p.pos = Vector2.ZERO
		p.stats.set_base(&"max_hp", 9999.0)
		p.hp = p.max_hp
		var h := w.spawner.spawn_at(w, &"hound", Vector2(0, 9))
		var pounce_at := -1
		var bearing := 0.0
		var hit := false
		var hopped := false
		var knocked := false
		for i in 60 * 12:
			var cmd := InputCmd.new()
			cmd.aim = h.pos if watch else Vector2(0, -5)
			w.step({World.HOST_PEER_ID: cmd}, DT)
			hopped = hopped or h.fsm.is_in(&"hop")
			if pounce_at < 0 and h.fsm.is_in(&"pounce"):
				pounce_at = i
				bearing = Hound.bearing_from(p, h.pos)
			for ev in w.events:
				if ev.name == "entity:damaged" and ev.target_id == p.id and ev.source_id == h.id and h.fsm.is_in(&"pounce"):
					hit = true
					knocked = p.knock_time > 0.0
			if hit:
				break
		var label := "一直轉身看著它" if watch else "背對它"
		if pounce_at < 0 or not hit:
			return "屍犬（%s）：12 秒內沒有撲中（撲第 %d 步）" % [label, pounce_at]
		if not knocked:
			return "屍犬（%s）：飛撲撲中應擊倒" % label
		var at := pounce_at * DT
		if not watch and (bearing <= Config.VISION.angle / 2.0 or at > start):
			return "屍犬（背對它）：在視野外應在 %.1f 秒內就撲，實際 %.2f 秒、相對朝向 %.0f°" % [start, at, rad_to_deg(bearing)]
		if watch and (at < start - DT * 2 or not hopped):
			return "屍犬（一直轉身看著它）：%.1f 秒前不該撲、牽制時要側跳：實際 %.2f 秒就撲（相對朝向 %.0f°）、側跳 %s" % [start, at, rad_to_deg(bearing), hopped]
	return ""


# 屍犬的其他招式：貼近時快咬（輕級）後往後跳；在 roll_punish.radius 內翻滾 → 撲向翻滾終點；4 隻圍著時同時出招不超過 pack.max_attackers
static func check_hound_moves() -> String:
	var hd: Dictionary = EnemyDefs.ENEMIES.hound
	# 快咬
	var w := _world()
	var p: Player = w.players[World.HOST_PEER_ID]
	p.pos = Vector2.ZERO
	p.stats.set_base(&"max_hp", 9999.0)
	p.hp = p.max_hp
	var h := w.spawner.spawn_at(w, &"hound", Vector2(0, 1.5)) as Hound
	var tier := &""
	var hopped_away := false
	for i in 120:
		var cmd := InputCmd.new()
		cmd.aim = h.pos
		w.step({World.HOST_PEER_ID: cmd}, DT)
		for ev in w.events:
			if ev.name == "entity:damaged" and ev.target_id == p.id and ev.source_id == h.id and tier == &"":
				tier = StringName(ev.get("tier", ""))
		if tier != &"" and h.fsm.is_in(&"hop") and h.velocity.dot(h.pos - p.pos) > 0.0:
			hopped_away = true
			break
	if tier != &"light" or not hopped_away:
		return "屍犬：貼近應快咬（輕級）後往後跳：級別 %s、後跳 %s" % [tier, hopped_away]
	# 抓翻滾：被看著（不會一般飛撲）時玩家在 3 內翻滾 → 撲向翻滾終點
	w = _world()
	p = w.players[World.HOST_PEER_ID]
	p.pos = Vector2.ZERO
	p.stats.set_base(&"max_hp", 9999.0)
	h = w.spawner.spawn_at(w, &"hound", Vector2(0, 2.7)) as Hound
	_step(w, roundi(hd.spawn_time / DT) + 1, true)
	var end := Vector2.INF
	var rolled_at := -1
	var roll_from := Vector2.ZERO
	for i in 180:
		var cmd := InputCmd.new()
		cmd.aim = h.pos
		# 被看著的狗牽制在 pin.range（2.5~4）、側跳會往外飄，站著等不到它進 radius：玩家先走近，
		# 等狗站在地上（側跳中不能出招）、在 radius 內才翻滾
		if rolled_at < 0 and h.fsm.is_in(&"chase") and h.pos.distance_to(p.pos) <= hd.roll_punish.radius - 0.2:
			rolled_at = i
			roll_from = p.pos
			cmd.buttons = InputCmd.BTN_ROLL
		if rolled_at >= 0 and i < rolled_at + 20:
			cmd.move = Vector2(1, 0)
		elif rolled_at < 0:
			cmd.move = (h.pos - p.pos).normalized()
		w.step({World.HOST_PEER_ID: cmd}, DT)
		p.hp = p.max_hp
		if h.fsm.is_in(&"pounce") and h.fsm.data.has("at"):
			end = h.fsm.data.at
			break
	var roll_end := roll_from + Vector2(Config.ROLL.distance, 0.0)
	if end == Vector2.INF or end.distance_to(roll_end) > 0.6:
		return "屍犬：%.0f 內有玩家翻滾應撲向翻滾終點 %s：%s" % [hd.roll_punish.radius, roll_end, end]
	# 群體：4 隻圍著背對的玩家，同時出招不超過 max_attackers
	w = _world()
	p = w.players[World.HOST_PEER_ID]
	p.pos = Vector2.ZERO
	p.stats.set_base(&"max_hp", 99999.0)
	p.hp = p.max_hp
	var dogs: Array[Hound] = []
	for k in 4:
		dogs.append(w.spawner.spawn_at(w, &"hound", Vector2.from_angle(PI * 0.25 + k * 0.4) * 5.0) as Hound)
	var most := 0
	for i in 60 * 6:
		var cmd := InputCmd.new()
		cmd.aim = Vector2(0, -5)
		w.step({World.HOST_PEER_ID: cmd}, DT)
		p.hp = p.max_hp
		most = maxi(most, dogs.filter(func(d: Hound) -> bool: return d.is_attacking()).size())
	if most > hd.pack.max_attackers or most == 0:
		return "屍犬：4 隻同時出招最多應 %d 隻：%d" % [hd.pack.max_attackers, most]
	return ""


# 持武器的腐屍：4 內地上有武器就走過去彎腰撿（地上的武器消失、改拿那把、名字變持〇腐屍、不再撲抱）；彎腰中被打中斷；
# 死掉時武器原樣掉回地上；劍盾舉盾時正面擋下、背後打得到；每種武器的招式 8 秒內打得到站在旁邊的玩家
static func check_armed_zombie() -> String:
	var w := _world()
	var p: Player = w.players[World.HOST_PEER_ID]
	p.pos = Vector2(0, 30)
	var rng := RandomNumberGenerator.new()
	var inst := WeaponDropDefs.make(&"w_test", &"longsword", &"white", rng)
	var ip := w.drop_item(&"longsword", Vector2(2.5, 0), inst)
	var z := w.spawner.spawn_at(w, &"zombie", Vector2.ZERO) as Zombie
	var bent := false
	for i in 60 * 4:
		_step(w, 1, true)
		bent = bent or (z.fsm.is_in(&"fetch") and z.fsm.data.phase == &"bend")
		if z.is_armed():
			break
	if not z.is_armed() or not ip.is_removed or not bent or z.display_name() != "持劍盾腐屍" or z.armed_weapon.uid != &"w_test":
		return "腐屍應走過去彎腰撿起 4 內的武器：拿到 %s、地上消失 %s、彎腰 %s、名字 %s" % [z.armed_weapon.get("base", "無"), ip.is_removed, bent, z.display_name()]
	# 舉盾：正面擋下、背後打得到
	z.shielding = true
	z.facing = 0.0
	var hp := z.hp
	Combat.apply_damage(w, p, z, {"damage": 5.0, "knockback": 0.0, "origin": z.pos + Vector2(0, 3)})
	var front := z.hp
	Combat.apply_damage(w, p, z, {"damage": 5.0, "knockback": 0.0, "origin": z.pos + Vector2(0, -3)})
	z.shielding = false
	if front != hp or z.hp >= front:
		return "劍盾腐屍舉盾：正面應擋下（%.1f → %.1f）、背後打得到（→ %.1f）" % [hp, front, z.hp]
	# 死掉：武器原樣掉回地上
	Combat.apply_damage(w, p, z, {"damage": 9999.0, "knockback": 0.0})
	var back := w.pickups.filter(func(e: Entity) -> bool: return not e.is_removed and (e as ItemPickup).weapon.get("uid", &"") == &"w_test")
	if back.size() != 1:
		return "持武器的腐屍死掉應把同一把武器掉回地上：%d 把" % back.size()
	# 彎腰中被打：中斷、沒拿到
	var w2 := _world()
	w2.players[World.HOST_PEER_ID].pos = Vector2(0, 30)
	var ip2 := w2.drop_item(&"staff", Vector2(1.0, 0), WeaponDropDefs.make(&"w2", &"staff", &"white", rng))
	var z2 := w2.spawner.spawn_at(w2, &"zombie", Vector2.ZERO) as Zombie
	var interrupted := false
	for i in 60 * 3:
		_step(w2, 1, true)
		if z2.fsm.is_in(&"fetch") and z2.fsm.data.phase == &"bend" and not interrupted:
			Combat.apply_damage(w2, w2.players[World.HOST_PEER_ID], z2, {"damage": 1.0, "knockback": 0.0})
			interrupted = true
			if z2.is_armed() or ip2.is_removed:
				return "彎腰中被打應中斷"
			break
	if not interrupted:
		return "腐屍應去撿 1 單位外的法杖"
	# 每種武器：站在 2 單位外的玩家 8 秒內被打到
	for base: StringName in EnemyDefs.ARMED_ZOMBIE:
		var w3 := _world()
		var p3: Player = w3.players[World.HOST_PEER_ID]
		p3.pos = Vector2.ZERO
		p3.stats.set_base(&"max_hp", 99999.0)
		p3.hp = p3.max_hp
		var z3 := w3.spawner.spawn_at(w3, &"zombie", Vector2(0, 2.0)) as Zombie
		z3.armed_weapon = WeaponDropDefs.make(&"w3", base, &"white", rng)
		var hurt := false
		var lunged := false
		for i in 60 * 8:
			_step(w3, 1, true)
			lunged = lunged or z3.fsm.is_in(&"lunge")
			for ev in w3.events:
				if ev.name == "entity:damaged" and ev.target_id == p3.id and ev.source_id == z3.id:
					hurt = true
			if hurt:
				break
		if not hurt or lunged:
			return "持%s腐屍：8 秒內應用武器打到旁邊的玩家、不再撲抱（打到 %s、撲抱 %s）" % [EnemyDefs.armed_kit(base).name, hurt, lunged]
	return ""


# 屍犬繞圈不跟著玩家的小幅轉身換邊：玩家大致對著狗、每 0.1 秒亂晃 ±15°，14 秒內繞圈方向反轉不超過 2 次
# （改之前每幀選最近的一邊，狗在正前方時兩邊一樣遠，同樣情境反轉 25 次）
static func check_hound_steady_side() -> String:
	var w := _world()
	var p: Player = w.players[World.HOST_PEER_ID]
	p.pos = Vector2.ZERO
	p.stats.set_base(&"max_hp", 9999.0)
	p.hp = p.max_hp
	var h := w.spawner.spawn_at(w, &"hound", Vector2(0, 9))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var aim_dir := Vector2(0, 1)
	var last_side := 0
	var flips := 0
	for i in 60 * 14:
		if i % 6 == 0:
			aim_dir = (h.pos - p.pos).normalized().rotated(deg_to_rad(rng.randf_range(-15.0, 15.0)))
		var cmd := InputCmd.new()
		cmd.aim = p.pos + aim_dir * 5.0
		w.step({World.HOST_PEER_ID: cmd}, DT)
		if not h.fsm.is_in(&"chase") or h.velocity.length() < 0.1:
			continue
		var cross := (h.pos - p.pos).cross(h.velocity)
		var side := 1 if cross > 0.5 else (-1 if cross < -0.5 else 0)
		if side != 0 and last_side != 0 and side != last_side:
			flips += 1
		if side != 0:
			last_side = side
	CheckKit._note("屍犬：玩家晃動滑鼠 14 秒，繞圈方向反轉 %d 次" % flips)
	if flips > 2:
		return "屍犬：玩家大致對著它小幅晃動，繞圈方向 14 秒內反轉 %d 次（應 ≤ 2）" % flips
	return ""


# 屍犬撲完先沿圈退到內圈（orbit[0]）才再撲：玩家站著不動，14 秒內每兩次撲之間都退到 orbit[0] 附近，而且撲得到第二次以上
static func check_hound_retreat() -> String:
	var hd: Dictionary = EnemyDefs.ENEMIES.hound
	var w := _world()
	var p: Player = w.players[World.HOST_PEER_ID]
	p.pos = Vector2.ZERO
	p.stats.set_base(&"max_hp", 9999.0)
	p.hp = p.max_hp
	var h := w.spawner.spawn_at(w, &"hound", Vector2(0, 9))
	var gaps: Array[float] = []   # 每兩次撲之間離玩家最遠的距離
	var farthest := -1.0          # < 0 = 還沒撲過
	var was_pounce := false
	for i in 60 * 14:
		w.step({World.HOST_PEER_ID: CheckKit._cmd(Vector2.ZERO)}, DT)
		p.hp = p.max_hp
		var now := h.fsm.is_in(&"pounce")
		if now and not was_pounce and farthest >= 0.0:
			gaps.append(farthest)
		if now:
			farthest = 0.0
		elif farthest >= 0.0:
			farthest = maxf(farthest, h.pos.distance_to(p.pos))
		was_pounce = now
	CheckKit._note("屍犬：站著不動 14 秒，每兩次撲之間退到的最遠距離 %s" % str(gaps))
	var low: float = hd.prowl.orbit[0] - hd.prowl.retreat_slack - hd.move_speed * (1.0 + hd.speed_variance) * DT * 2.0
	if gaps.is_empty():
		return "屍犬：站著不動 14 秒應撲 2 次以上（撲完退開後還要再撲），實際 %d 次" % (gaps.size() + (1 if farthest >= 0.0 else 0))
	for g in gaps:
		if g < low:
			return "屍犬：撲完應先退到 %.1f 再撲，實際只退到 %.2f（每次 %s）" % [hd.prowl.orbit[0], g, str(gaps)]
	return ""


# 守墓人（假裝 NPC）：玩家站在前面 3 秒也不開打、不打人；按 F 說話 → reveal（說台詞）→ reveal_time 後開打；
# 被打 → 不說話直接開打；有人開挖 → 開打。開挖距離內按 F 先說話、不會同時開挖
static func check_gravekeeper_npc() -> String:
	var npc: Dictionary = EnemyDefs.ENEMIES.gravekeeper.npc
	for how: StringName in [&"talk", &"hit", &"dig"]:
		var w := _world(&"graveyard_a")
		var p: Player = w.players[World.HOST_PEER_ID]
		var k := w.spawner.spawn_at(w, &"gravekeeper", w.event.point, {"initial_state": &"patrol"}) as Gravekeeper
		p.pos = w.nav.nearest_walkable(k.pos + MathUtil.dir_from_angle(k.facing) * 2.5)
		var hp := p.hp
		var events: Array[Dictionary] = []
		for i in 180:
			var cmd := InputCmd.new()
			cmd.aim = k.pos
			w.step({World.HOST_PEER_ID: cmd}, DT)
			events.append_array(w.events)
		if not k.is_npc() or p.hp < hp:
			return "守墓人：玩家在旁邊 3 秒應該還是 NPC、不打人（狀態 %s、玩家扣血 %.0f）" % [k.fsm.current_name, hp - p.hp]
		match how:
			&"talk":
				p.pos = w.nav.nearest_walkable(k.pos + (p.pos - k.pos).normalized() * (k.radius + p.radius + npc.talk_range * 0.5))
				var cmd := InputCmd.new()
				cmd.aim = k.pos
				cmd.buttons = InputCmd.BTN_INTERACT
				w.step({World.HOST_PEER_ID: cmd}, DT)
				events.append_array(w.events)
				if not k.fsm.is_in(&"reveal") or not k.anim.get("spoke", false) or w.event.state != DigEvent.IDLE:
					return "守墓人：按 F 說話應進入揭穿、冒台詞、不開挖（狀態 %s、挖墳 %s）" % [k.fsm.current_name, w.event.state]
				var steps := 0
				while k.fsm.is_in(&"reveal") and steps < 200:
					w.step({World.HOST_PEER_ID: InputCmd.new()}, DT)
					events.append_array(w.events)
					steps += 1
				if not k.fsm.is_in(&"chase") or absf(steps * DT - npc.reveal_time) > DT * 3:
					return "守墓人：說完台詞 %.1f 秒後應開打，實際 %.2f 秒後狀態 %s" % [npc.reveal_time, steps * DT, k.fsm.current_name]
			&"hit":
				Combat.apply_damage(w, p, k, {"damage": 1.0, "knockback": 0.0})
				if not k.fsm.is_in(&"chase") or k.anim.get("spoke", false):
					return "守墓人：被打應不說話直接開打（狀態 %s）" % k.fsm.current_name
			&"dig":
				w.event._start(w)
				if not k.fsm.is_in(&"chase"):
					return "守墓人：有人開挖應直接開打（狀態 %s）" % k.fsm.current_name
	return ""


# 守墓人第一型態四招：站在合適距離的玩家被打到；鏟土落地時間 = windup + flight_time；噴火每 tick 打一次、留下殘火（只燒玩家）；
# 口哨叫 count 隻屍犬（不給靈魂）；全程不畫預警圈
static func check_gravekeeper_moves() -> String:
	var d: Dictionary = EnemyDefs.ENEMIES.gravekeeper
	for move: StringName in [&"shovel", &"lob", &"lantern", &"whistle"]:
		var w := _world()
		var p: Player = w.players[World.HOST_PEER_ID]
		p.stats.set_base(&"max_hp", 9999.0)
		p.hp = p.max_hp
		var k := w.spawner.spawn_at(w, &"gravekeeper", Vector2.ZERO) as Gravekeeper
		_step(w, roundi(d.spawn_time / DT) + 2, true)
		var dist: float = {&"shovel": 2.0, &"lob": 8.0, &"lantern": 3.5, &"whistle": 6.0}[move]
		p.pos = Vector2(0, dist)
		k.facing = 0.0
		k.fsm.change(move)
		var hits := 0
		var first_hit := -1
		var events: Array[Dictionary] = []
		for i in 240:
			w.step({World.HOST_PEER_ID: InputCmd.new()}, DT)
			events.append_array(w.events)
			for ev in w.events:
				if ev.name == "entity:damaged" and ev.target_id == p.id and ev.source_id == k.id:
					hits += 1
					if first_hit < 0:
						first_hit = i + 1
			p.pos = Vector2(0, dist)
			if not k.fsm.is_in(move) and i > 30 and move != &"lantern":
				break
		if events.any(func(ev: Dictionary) -> bool: return ev.name == "fx:telegraph"):
			return "守墓人 %s 不應畫預警圈" % move
		match move:
			&"shovel":
				if hits != 1 or absf(first_hit * DT - d.shovel.windup) > DT * 2.5:
					return "守墓人鐵鏟：應在 %.1f 秒打中一次（第 %d 步、%d 次）" % [d.shovel.windup, first_hit, hits]
			&"lob":
				var land: float = d.lob.windup + d.lob.flight_time
				if hits < 1 or absf(first_hit * DT - land) > DT * 2.5 or not events.any(func(ev: Dictionary) -> bool: return ev.name == "fx:dirt_lob"):
					return "守墓人鏟土：應在 %.2f 秒落地打中（第 %d 步、%d 次）並發 fx:dirt_lob" % [land, first_hit, hits]
			&"lantern":
				var ticks := roundi(d.lantern.duration / d.lantern.tick)
				if hits < ticks + 1 or absf(first_hit * DT - d.lantern.windup - d.lantern.tick) > DT * 2.5:
					return "守墓人噴火：站在前面應被噴 %d 下再被殘火燒（共 %d 次、第一下第 %d 步）" % [ticks, hits, first_hit]
				if not events.any(func(ev: Dictionary) -> bool: return ev.name == "fx:gas_cloud" and ev.get("fire", false)):
					return "守墓人噴火：殘火應冒火苗（fx:gas_cloud fire）"
			&"whistle":
				var dogs := w.enemies.filter(func(e: Entity) -> bool: return e is Hound and (e as Enemy).summoner_id == k.id and (e as Enemy).no_souls)
				if dogs.size() != d.whistle.count:
					return "守墓人口哨：應叫出 %d 隻不給靈魂的屍犬，實際 %d" % [d.whistle.count, dogs.size()]
	return ""


# 守墓人半血轉型態：血量剛好過門檻前不變；過門檻 → 變身（無敵 time 秒）→ form 1、移速 wolf.move_speed、
# 嚎叫震退身邊的玩家、提燈掉在地上變成火堆（Torch）；狼人三連爪站著不動吃滿 3 下（後兩下不被受傷無敵擋掉）、
# 飛撲在 windup + flight 落地打中、狼嚎叫 count 隻魔法屍犬並加速
static func check_gravekeeper_transform() -> String:
	var d: Dictionary = EnemyDefs.ENEMIES.gravekeeper
	var tr: Dictionary = d.transform
	var w := _world()
	var p: Player = w.players[World.HOST_PEER_ID]
	p.stats.set_base(&"max_hp", 9999.0)
	p.hp = p.max_hp
	var k := w.spawner.spawn_at(w, &"gravekeeper", Vector2.ZERO) as Gravekeeper
	_step(w, roundi(d.spawn_time / DT) + 2, true)
	p.pos = Vector2(0, 2.5)
	k.hp = k.max_hp * tr.hp_threshold + 2.0
	Combat.apply_damage(w, p, k, {"damage": 1.0, "knockback": 0.0})
	if k.fsm.is_in(&"transform"):
		return "守墓人：血量還在 %.0f%% 以上就變身了" % (tr.hp_threshold * 100.0)
	k.invuln_timer = 0.0
	Combat.apply_damage(w, p, k, {"damage": 5.0, "knockback": 0.0})
	if not k.fsm.is_in(&"transform"):
		return "守墓人：血量低於 %.0f%% 應開始變身（狀態 %s）" % [tr.hp_threshold * 100.0, k.fsm.current_name]
	var hp_before := k.hp
	var events: Array[Dictionary] = []
	var done_at := -1
	var roared := false
	for i in roundi((tr.time + 0.5) / DT):
		k.invuln_timer = maxf(k.invuln_timer, 0.0)
		Combat.apply_damage(w, p, k, {"damage": 50.0, "knockback": 0.0})   # 變身中打不動
		w.step({World.HOST_PEER_ID: InputCmd.new()}, DT)
		events.append_array(w.events)
		for ev in w.events:
			if ev.name == "entity:damaged" and ev.target_id == p.id and ev.source_id == k.id:
				roared = true
		if done_at < 0 and k.form == 1:
			done_at = i + 1
			break
	if k.hp < hp_before:
		return "守墓人：變身中應無敵（血 %.0f → %.0f）" % [hp_before, k.hp]
	if done_at < 0 or absf(done_at * DT - tr.time) > DT * 2.5:
		return "守墓人：應在 %.1f 秒後變成狼人（第 %d 步）" % [tr.time, done_at]
	if not roared or w.torches.size() != 1 or not events.any(func(ev: Dictionary) -> bool: return ev.name == "boss:transformed"):
		return "守墓人：變身完成應嚎叫打到身邊的玩家（%s）、掉下提燈火堆（%d 個）、發 boss:transformed" % [roared, w.torches.size()]
	if absf(k.speed - d.wolf.move_speed) > 0.01:
		return "狼人移速 %.2f，預期 %.1f" % [k.speed, d.wolf.move_speed]
	# 狼人三招
	var wd: Dictionary = d.wolf
	for move: StringName in [&"claw", &"leap", &"howl"]:
		var dist: float = {&"claw": 1.8, &"leap": 8.0, &"howl": 6.0}[move]
		p.pos = Vector2(0, dist)
		p.invuln_timer = 0.0
		k.pos = Vector2.ZERO
		k.facing = 0.0
		k.fsm.change(move)
		var hits := 0
		var first := -1
		for i in 180:
			w.step({World.HOST_PEER_ID: InputCmd.new()}, DT)
			p.pos = Vector2(0, dist)
			for ev in w.events:
				if ev.name == "entity:damaged" and ev.target_id == p.id and ev.source_id == k.id:
					hits += 1
					if first < 0:
						first = i + 1
			if not k.fsm.is_in(move):
				break
		match move:
			&"claw":
				if hits != 3:
					return "狼人三連爪：站著不動應吃滿 3 下，實際 %d 下" % hits
			&"leap":
				var land: float = wd.leap.windup + wd.leap.flight
				if hits != 1 or absf(first * DT - land) > DT * 2.5:
					return "狼人飛撲：應在 %.2f 秒落地打中一次（第 %d 步、%d 次）" % [land, first, hits]
			&"howl":
				var dogs := w.enemies.filter(func(e: Entity) -> bool: return e is Hound and (e as Enemy).summoner_id == k.id and (e as Enemy).rarity == MonsterRarityDefs.MAGIC)
				if dogs.size() < wd.howl.count or absf(k.speed - wd.move_speed * wd.howl.speed_mul) > 0.01:
					return "狼嚎：應叫出 %d 隻魔法屍犬（%d）、移速 ×%.1f（%.2f）" % [wd.howl.count, dogs.size(), wd.howl.speed_mul, k.speed]
	return ""


static func check_floor_mix() -> String:
	var w := _world(&"graveyard_a", true)
	var first: Dictionary = EnemyDefs.floor_mix(1)
	var next: Dictionary = EnemyDefs.floor_mix(2)
	for e in w.enemies:
		if e is Enemy and (e as Enemy).pack_id >= 0 and not first.has((e as Enemy).type):
			return "第 1 層的怪群出現 %s（應只有 %s）" % [(e as Enemy).type, first.keys()]
	for i in 50:
		var horde: StringName = w.event._roll_type(w)
		var erupt: StringName = w.event._roll_type(w, 1)
		if not first.has(horde) or not next.has(erupt):
			return "第 1 層怪潮抽到 %s、挖墳點噴 %s（應是 %s / %s）" % [horde, erupt, first.keys(), next.keys()]
	var w2 := _world()
	var z := w2.spawner.spawn_at(w2, &"zombie", Vector2(0, 6))
	z.set_rarity(MonsterRarityDefs.RARE, [&"summoner"], "")
	z.apply_rarity_stats()
	_step(w2, roundi((EnemyDefs.ENEMIES.zombie.spawn_time + MonsterRarityDefs.AFFIXES.summoner.interval) / DT) + 3, true)
	var called := w2.enemies.filter(func(e: Entity) -> bool: return e is Enemy and (e as Enemy).summoner_id == z.id)
	if called.is_empty() or called.any(func(e: Entity) -> bool: return (e as Enemy).type != &"zombie"):
		return "召喚詞條的腐屍應叫出腐屍：%s" % [called.map(func(e: Entity) -> StringName: return (e as Enemy).type)]
	return ""


static func check_affixes() -> String:
	var af: Dictionary = MonsterRarityDefs.AFFIXES
	var w := _world()
	var g := w.spawner.spawn_at(w, &"grunt", Vector2(0, 10))
	var s0 := g.speed
	var swift: float = af.swift.mods[0][2]
	var mighty: float = af.mighty.mods[0][2]
	g.set_rarity(MonsterRarityDefs.NORMAL, [&"swift", &"mighty"])
	g.apply_rarity_stats()
	if absf(g.speed - s0 * swift) > EPS or absf(g.damage_mul - mighty) > EPS:
		return "迅捷 / 強壯：移速 %.3f（預期 %.3f）、攻擊力 ×%.2f（預期 ×%.2f）" % [g.speed, s0 * swift, g.damage_mul, mighty]
	var armored := _grunt(w, Vector2(5, 10), MonsterRarityDefs.NORMAL, [&"armored"])
	var dealt := armored.take_damage(20.0, Vector2(0, 1), 0.0, 0)
	var armored_want := roundi(20.0 * af.armored.mods[0][2])
	if dealt != armored_want:
		return "厚皮：受到 20 傷害扣 %d，預期 %d" % [dealt, armored_want]
	# 再生：每秒 regen_ratio × 最大生命
	var regen := _grunt(w, Vector2(-5, 10), MonsterRarityDefs.NORMAL, [&"regen"])
	regen.hp = 10.0
	_step(w, 60)
	var regen_want: float = 10.0 + regen.max_hp * af.regen.regen_ratio
	if absf(regen.hp - regen_want) > 0.01:
		return "再生：1 秒後生命 %.3f，預期 %.2f" % [regen.hp, regen_want]

	# 吸血：揮砍傷害 × lifesteal 回血
	var w2 := _world()
	var vamp := _grunt(w2, Vector2(0, 1.2), MonsterRarityDefs.NORMAL, [&"vampiric"])
	vamp.hp = 20.0
	var p2: Player = w2.players[World.HOST_PEER_ID]
	for i in 300:
		_step(w2, 1)
		if p2.hp < p2.max_hp:
			break
	var swing: float = EnemyDefs.ENEMIES.grunt.swing.damage
	var vamp_want: float = 20.0 + swing * af.vampiric.lifesteal
	if p2.hp >= p2.max_hp or absf(vamp.hp - vamp_want) > 0.01:
		return "吸血：玩家生命 %.0f、骷髏生命 %.2f（預期打中 %.0f 後回到 %.2f）" % [p2.hp, vamp.hp, swing, vamp_want]

	# 狂暴：生命低於 threshold 時移速、狀態機速度 × speed
	var fz: Dictionary = af.frenzy
	var w3 := _world()
	var fr := _grunt(w3, Vector2(0, 12), MonsterRarityDefs.NORMAL, [&"frenzy"])
	_step(w3, 50)
	var fs := fr.speed
	fr.hp = fr.max_hp * fz.threshold + 0.5
	_step(w3, 1)
	if fr.action_speed != 1.0:
		return "狂暴：生命 %.0f%% 就觸發了" % (fr.hp / fr.max_hp * 100.0)
	fr.hp = fr.max_hp * fz.threshold - 0.5
	_step(w3, 1)
	if absf(fr.action_speed - fz.speed) > EPS or absf(fr.speed - fs * fz.speed) > EPS:
		return "狂暴：生命 %.0f%% 時狀態機速度 ×%.2f、移速 %.3f（預期 ×%.1f、%.3f）" % [fr.hp / fr.max_hp * 100.0, fr.action_speed, fr.speed, fz.speed, fs * fz.speed]

	# 死亡爆炸：死時不畫預警圈（畫面上屍體脹大、閃白）、delay 秒後半徑 radius 爆炸；半徑內 0.7 炸得到、半徑外 0.8 炸不到
	var vd: Dictionary = af.volatile
	var boom_step := roundi(vd.delay / DT)
	for dist: float in [vd.radius - 0.7, vd.radius + 0.8]:
		var w4 := _world()
		var p4: Player = w4.players[World.HOST_PEER_ID]
		var vol := _grunt(w4, Vector2(0, dist), MonsterRarityDefs.NORMAL, [&"volatile"])
		vol.die()
		if w4.events.any(func(ev: Dictionary) -> bool: return ev.name == "fx:telegraph"):
			return "死亡爆炸：死的時候不應畫預警圈"
		var mid := EnemyAnimator.volatile_swell(vol, vd.delay * 0.6)
		if mid <= 0.0 or EnemyAnimator.volatile_swell(vol, vd.delay) != 0.0 or EnemyAnimator.volatile_flash(vol, vd.delay * 0.9) <= 0.0:
			return "死亡爆炸：爆開前屍體應脹大、閃白（%.1f 秒時膨脹 %.2f）" % [vd.delay * 0.6, mid]
		var hit_step := -1
		for i in boom_step + 12:
			_step(w4, 1)
			for ev in w4.events:
				if ev.name == "entity:damaged" and ev.target_id == p4.id:
					if ev.amount != roundi(vd.damage):
						return "死亡爆炸傷害 %d，預期 %.0f" % [ev.amount, vd.damage]
					hit_step = i + 1
			if hit_step > 0:
				break
		if dist < vd.radius and (hit_step < boom_step - 1 or hit_step > boom_step + 2):
			return "死亡爆炸：第 %d 步炸到玩家，預期約第 %d 步（%.1f 秒）" % [hit_step, boom_step, vd.delay]
		if dist > vd.radius and hit_step > 0:
			return "死亡爆炸：距離 %.1f 的玩家也被炸到" % dist

	# 召喚：爬出後 interval 秒叫 count 隻骷髏戰士，同時最多 max_alive 隻
	var sd: Dictionary = af.summoner
	var w5 := _world()
	var sm := _grunt(w5, Vector2(0, 12), MonsterRarityDefs.NORMAL, [&"summoner"])
	var minions := func() -> int:
		var n := 0
		for e in w5.enemies:
			if e is Enemy and (e as Enemy).summoner_id == sm.id and not e.is_dead:
				n += 1
		return n
	var first: float = EnemyDefs.ENEMIES.grunt.spawn_time + sd.interval
	_step(w5, roundi(first / DT) - 3, true)
	if minions.call() != 0:
		return "召喚：%.1f 秒前就叫出 %d 隻" % [first, minions.call()]
	_step(w5, 6, true)
	if minions.call() != sd.count:
		return "召喚：%.1f 秒後應有 %d 隻，實際 %d" % [first, sd.count, minions.call()]
	# 再等到上限之後多一輪：一直叫到 max_alive 就停
	var more: float = ceili(float(sd.max_alive) / sd.count) * sd.interval + 1.0
	_step(w5, roundi(more / DT), true)
	if minions.call() != sd.max_alive:
		return "召喚：%.1f 秒後應有 %d 隻（上限），實際 %d" % [first + more, sd.max_alive, minions.call()]
	return ""


# ───────── 怪群 ─────────

static func check_packs() -> String:
	var w := _world(&"graveyard_a", true)
	var c: Dictionary = MonsterRarityDefs.PACKS
	var n := w.packs.size()
	if n < c.count[0] or n > c.count[1]:
		return "地圖 A 有 %d 群，預期 %d~%d" % [n, c.count[0], c.count[1]]
	for ev in w.events:
		if ev.name == "sfx:cue" and ev.cue == "enemySpawn":
			return "開場散放怪群時播了爬出音效"
	var start := {}
	var total := 0
	for i in n:
		var pk: Dictionary = w.packs[i]
		var center: Vector2 = pk.center
		if center.distance_to(w.spawn_point) < c.min_spawn_distance - EPS:
			return "第 %d 群離出生點只有 %.1f" % [i, center.distance_to(w.spawn_point)]
		for j in i:
			if center.distance_to(w.packs[j].center) < c.min_pack_distance - EPS:
				return "第 %d、%d 群只相距 %.1f" % [j, i, center.distance_to(w.packs[j].center)]
		var ids: Array = pk.ids
		if ids.size() < c.size[0] or ids.size() > c.size[1]:
			return "第 %d 群有 %d 隻，預期 %d~%d" % [i, ids.size(), c.size[0], c.size[1]]
		var magic := 0
		var rare := 0
		for id: int in ids:
			var e: Enemy = w.entities[id]
			if e.pack_id != i or not e.dormant or not e.fsm.is_in(&"dormant") or e.wave_member:
				return "第 %d 群的 %d 號：pack_id %d、休眠 %s、狀態 %s" % [i, id, e.pack_id, e.dormant, e.fsm.current_name]
			if not w.nav.is_walkable(e.pos) or not w.nav.same_region(e.pos, w.spawn_point):
				return "第 %d 群的 %d 號在 %s：不可走或走不到出生點" % [i, id, e.pos]
			magic += 1 if e.rarity == MonsterRarityDefs.MAGIC else 0
			rare += 1 if e.rarity == MonsterRarityDefs.RARE else 0
			start[id] = e.pos
		if magic < c.magic_per_pack[0] or magic > c.magic_per_pack[1] or rare > 1:
			return "第 %d 群有 %d 隻魔法、%d 隻稀有" % [i, magic, rare]
		total += ids.size()
	# 玩家沒靠近：3 秒都不走（速度 0）；成員一開始若有重疊，碰撞分離推開後就完全靜止
	_step(w, 120)
	var settled := {}
	for id: int in start:
		settled[id] = (w.entities[id] as Enemy).pos
	_step(w, 60)
	for id: int in start:
		var e: Enemy = w.entities[id]
		if not e.dormant or e.velocity != Vector2.ZERO or e.pos.distance_to(settled[id]) > EPS:
			return "玩家沒靠近，%d 號就醒了或在走（第 2~3 秒移動 %.3f）" % [id, e.pos.distance_to(settled[id])]
	# 走到第 0 群 wake_distance − 1 內：中心 wake_distance 以內的群整群醒來，其他的照睡
	var p: Player = w.players[World.HOST_PEER_ID]
	var near := w.nav.nearest_walkable(w.packs[0].center + Vector2(0, c.wake_distance - 1.0))
	if near.distance_to(w.packs[0].center) > c.wake_distance:
		near = w.packs[0].center
	p.pos = near
	_step(w, 1)
	for i in n:
		var should: bool = w.packs[i].center.distance_to(p.pos) <= c.wake_distance
		if w.packs[i].awake != should:
			return "玩家離第 %d 群 %.1f，醒來 = %s" % [i, w.packs[i].center.distance_to(p.pos), w.packs[i].awake]
		for id: int in w.packs[i].ids:
			var e: Enemy = w.entities.get(id)
			if e != null and e.dormant == should:
				return "第 %d 群的 %d 號沒跟著整群%s" % [i, id, "醒來" if should else "休眠"]
			if e != null and e.fixed == should:
				return "第 %d 群的 %d 號 fixed 應跟著休眠（v0.30.0）：%s" % [i, id, e.fixed]
			if e != null and should and e.fsm.is_in(&"dormant"):
				return "第 %d 群醒來同一步就該開始追，%d 號還在 dormant" % [i, id]
	# 遠處被打：整群醒來
	for i in n:
		if not w.packs[i].awake:
			var first: Enemy = w.entities[w.packs[i].ids[0]]
			first.take_damage(1.0, Vector2(0, 1), 0.0, p.id)
			for id: int in w.packs[i].ids:
				if (w.entities[id] as Enemy).dormant:
					return "第 %d 群被打一隻，%d 號沒醒" % [i, id]
			break
	# 決定性：同種子散放的位置一樣
	var w2 := _world(&"graveyard_a", true)
	if w2.packs.size() != n or w2.packs[n - 1].center != w.packs[n - 1].center:
		return "同種子兩次散放的怪群不同"
	return ""


# 蒙皮小怪（D5 效能）：骷髏戰士 / 弓手每隻 ≤ 2 個網格、三角形數與原本的零件相同；關節寫進骨架
static func check_skinned_rig() -> String:
	for kind: StringName in [&"grunt", &"archer", &"zombie", &"bloater", &"hound"]:
		var old := DarkFantasy.character(kind)
		var rig := DarkFantasy.skinned_character(kind)
		var before := 0
		var after := 0
		for mi in PartKit.mesh_instances(old):
			before += (mi.mesh as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		for mi in PartKit.mesh_instances(rig):
			after += (mi.mesh as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		var count := rig.mesh_count()
		rig.arm_r.rotation = Vector3(-1.2, 0.3, 0.0)
		rig.flush()
		var want := Basis.from_euler(Vector3(-1.2, 0.3, 0.0), EULER_ORDER_YXZ)
		var got := rig.skeleton.get_bone_pose(3).basis
		var pos := rig.skeleton.get_bone_pose(3).origin
		var want_pos: Vector3 = rig.arm_r.position
		old.free()
		rig.free()
		if count > 2:
			return "%s 蒙皮版有 %d 個網格（應 ≤ 2）" % [kind, count]
		if before != after:
			return "%s 蒙皮版頂點 %d，原本零件 %d" % [kind, after, before]
		if not got.is_equal_approx(want) or not pos.is_equal_approx(want_pos):
			return "%s 右臂的骨頭姿勢沒跟著關節" % kind
	return ""


# 連線：稀有度、詞條、名字、體型傳到客戶端；最大生命用快照的數字（不重複乘稀有度）
static func check_net_rarity() -> String:
	var w := _world()
	var e := w.spawner.spawn_at(w, &"grunt", Vector2(0, 8))
	Spawner.roll_rarity(w, e, MonsterRarityDefs.RARE)
	var rec := NetCodec.encode_entity(e)
	var wire: Array = bytes_to_var(var_to_bytes([rec[0], rec[1]]))   # 紀錄的第 3 格是實體本身，不上網路
	var cw := World.new(&"test_arena")
	cw.is_authority = false
	_made.append(cw)
	var m := NetCodec.create_entity(cw, NetCodec.decode_entity(wire)) as Enemy
	if m == null or m.rarity != e.rarity or m.affixes != e.affixes or m.rare_name != e.rare_name:
		return "客戶端的稀有度 / 詞條 / 名字不同：%s %s「%s」" % [m.rarity if m else &"", m.affixes if m else [], m.rare_name if m else ""]
	if absf(m.radius - e.radius) > EPS or absf(m.max_hp - e.max_hp) > EPS:
		return "客戶端半徑 %.3f / 最大生命 %.1f，房主 %.3f / %.1f" % [m.radius, m.max_hp, e.radius, e.max_hp]
	var plain := w.spawner.spawn_at(w, &"grunt", Vector2(3, 8))
	if NetCodec.encode_entity(plain)[1] != null:   # v0.35.0 起普通怪的 extra 整格不送（null）
		return "普通怪的快照不該帶稀有度欄位"
	return ""


# 怪物屍體：死後擊退照樣往後滑（平地滑得開），但不滑下高台：在高台邊緣帶著往台外的擊退死掉，留在死掉時的高度（使用者回報死亡動畫掉到台下）
static func check_corpse_ledge() -> String:
	var kb := Vector2.RIGHT * 7.0
	var flat := _world()
	var z := flat.spawner.spawn_at(flat, &"zombie", Vector2(0, 6))
	flat.step({}, DT)
	var at := z.pos
	z.knockback = kb
	z.die()
	for i in 30:
		flat.step({}, DT)
	if z.pos.distance_to(at) < 0.3:
		return "平地上屍體應被擊退滑開，只移動了 %.2f" % z.pos.distance_to(at)
	var w := _world(&"graveyard_a")
	var spot := Vector2.INF
	var out := Vector2.ZERO
	for x in range(-80, 81):
		for y in range(-80, 81):
			var pt := Vector2(x, y) * 0.5
			var g := w.terrain.ground_at(pt)
			if g < 0.4 or g > Config.NAV.climb_height:
				continue
			for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				if w.terrain.ground_at(pt + d * 1.2) < g - 0.3 and w.terrain.ground_at(pt - d * 1.0) >= g - 0.01:
					spot = pt
					out = d
					break
			if spot != Vector2.INF:
				break
		if spot != Vector2.INF:
			break
	if spot == Vector2.INF:
		return "地圖 A 找不到高台邊緣（地圖改了，檢查要換地方找）"
	var e := w.spawner.spawn_at(w, &"zombie", spot)
	e.pos = spot
	e.height = w.terrain.ground_at(spot)
	w.step({}, DT)
	var h0 := e.height
	e.knockback = out * kb.length()
	e.die()
	for i in 60:
		w.step({}, DT)
	CheckKit._note("屍體：高台 %s 高 %.2f 往台外擊退死掉，1 秒後高 %.2f" % [spot, h0, e.height])
	if absf(e.height - h0) > 0.05:
		return "高台邊緣 %s（高 %.2f）帶著往台外的擊退死掉，屍體應留在台上，1 秒後高 %.2f" % [spot, h0, e.height]
	return ""
