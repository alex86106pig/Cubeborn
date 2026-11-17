# 自動試玩：headless 的機器人（tests/playtest_bot.gd）照真實地圖玩一層或好幾層，量殺怪數、武器掉落、背包、每小關結束的主袋與袋子填滿率、靈魂、受傷與倒下，給調掉落 / 怪量 / 難度 / 經濟當依據
# 平常用 `node tools/release.mjs --playtest` 跑；直接跑：在 godot/ 內 <Godot> --headless --path . -s res://tests/playtest.gd -- 參數
# 參數：--floors=N（幾層，預設 1）、--seeds=1,2,3（每個種子各玩一場，預設 1,2,3）、--out=檔案（另存 Markdown）
#       --class=guardian（職業，預設守墓騎士；逗號分隔就是組隊，一個職業一個機器人，例：guardian,arcanist）
#       --style=full|rush（full：清完怪群 → 打 Boss → 挖墳；rush：直接挖墳，只打靠近的怪，預設 full）
#       --play=smart|dumb（smart：躲招、舉盾招架、遠程拉開、喝藥水、換武器、整理背包、走出地面效果、救隊友；dumb：都不做，預設 smart）
#       --react=秒（smart 看到怪物出招後最快多久反應，預設 0.25；高手 0.15、新手 0.4）
#       --pick=smart|random（3 選 1：smart 照技能 / 羈絆挑、沒得挑就用骰子重擲；random 隨機選、不用骰子，確認隨機的 Build 也打得完，預設 smart）
#       --death=revive|real（revive：倒下記一次、原地滿血救起，一定打完，比「哪幾招最痛」；real：真的會死，全員倒下這場就結束，看撐到哪，預設 revive）
#       --trace=1（倒下時印出之前最後 10 下：時間、哪一招、多少、剩多少血、在做什麼、翻滾充能、身邊 3 內幾隻怪）
#       --bag-mode=merged（背包合併模式：袋子不掉、過關與獎勵開格）
#       --quota=近戰,遠程,看不到的（小怪的出手名額 AttackQuota，0 = 不限；例 --quota=2,1,1。不寫 = 照 Config.ATTACK_QUOTA）
#       --real-from=N（第 1 層第 N 小關起才真的會死，之前倒下原地救起、配裝照正常打過來；進那一關補滿血。--real-from=5 量帶著正常配裝的 Boss 戰）
#       --start=N（直接從第 1 層第 N 小關開始，跳過的每一關給一個技能遺物；--start=5 只量 Boss 戰）
#       --crowd=N（近戰身邊 2.5 內醒著的怪到 N 隻就往外退，預設 0 = 不退；做實驗用）
#       --count-from=N（第 1 層第 N 小關起才算受傷、倒下、被打中與最痛的招，時間欄也從那時算；配裝照正常打過來。--real-from=5 --count-from=5 量帶著正常配裝的 Boss 戰）
#       --shield=0（有盾也不舉盾、只滾；做實驗用，比機器人的舉盾時機跟職業本身）
# 血量照遊戲的規則走（自然回血、吸血、藥水、生命低於 X% 的道具都會發動）；revive 救起時有 REVIVE.revive_invuln 秒無敵
extends SceneTree

const Bot := preload("res://tests/playtest_bot.gd")
const DT := 1.0 / 60.0
const MAX_FLOOR_TIME := 30.0 * 60.0   # 一層最多模擬這麼久（卡住時不會一直跑）

var _moments := {}          # 觸發袋的時機（Player.trigger_moments 的「種類:按鍵」）全部場次加總
var _moment_time := 0.0     # 這些時機量了幾秒（每個機器人各算一份）
var _opts := {}             # 命令列參數（_args）
var _taken := {"time": 0.0, "hits": 0, "damage": 0.0, "unseen_damage": 0.0}   # 全部場次與機器人加總的被打中（照遊玩紀錄 RunLog 的「看不見」算）
# 挖墳事件進行中（DigEvent.ACTIVE）全部場次加總：幾秒、有人在挖的秒數、怪潮 / 挖墳點噴出各生幾隻、各殺幾隻、每場場上醒著最多幾隻的合計、幾場
var _dig := {"time": 0.0, "digging": 0.0, "horde": 0, "erupt": 0, "horde_killed": 0, "erupt_killed": 0, "peak": 0, "runs": 0}


func _initialize() -> void:
	var opts := _args()
	_opts = opts
	var seeds: Array = []
	for s in String(opts.get("seeds", "1,2,3")).split(","):
		seeds.append(int(s))
	var floors := int(opts.get("floors", "1"))
	var classes: Array[StringName] = []
	for c in String(opts.get("class", "guardian")).split(","):
		classes.append(StringName(c))
	var how := "玩法 %s（反應 %s 秒）、3 選 1 %s、%s" % [opts.get("play", "smart"), opts.get("react", "0.25"), opts.get("pick", "smart"),
		"真的會死" if opts.get("death", "revive") == "real" else ("第 %s 小關起真的會死" % opts["real-from"] if opts.has("real-from") else "倒下原地救起")]
	var lines: Array[String] = ["# 自動試玩", "", "職業 %s、打法 %s、%s、%d 層、種子 %s；背包 %d × %d = %d 格" % [",".join(PackedStringArray(classes)),
		opts.get("style", "full"), how, floors, str(seeds), ItemDefs.BAG_SIZE.x, ItemDefs.BAG_SIZE.y, ItemDefs.BAG_SIZE.x * ItemDefs.BAG_SIZE.y], "",
		"| 種子 | 層 | 時間 | 殺怪（怪群 / 事件 / Boss / 召喚） | 掉武器（白綠藍紫橘） | 撿到 | 背包武器格 | 背包滿的時間 | 地上沒撿 | 靈魂 賺到 / 花掉（開幾箱） | 主袋 / 袋子填滿率（每小關結束） | 技能（等級）· 放幾次 | 羈絆 | 翻滾 / 跳 / 擋 / 喝藥 / 換武器 / 合成 / 丟 / 搬進袋子 / 重擲 / 救人 | 受傷 / 倒下（最多被哪招）· 被打中幾下（每分鐘）· 看不見的傷害 % | 結果 | 最痛的招 |",
		"|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
	var cleared := 0
	var total := 0
	for s in seeds:
		var rows := _play(int(s), floors, classes, opts)
		lines.append_array(rows)
		total += 1
		if not rows.any(func(r: String) -> bool: return r.contains("死在")):
			cleared += 1
	lines.append("")
	if opts.get("death", "revive") == "real" or opts.has("real-from"):
		lines.append("打完 %d 層：%d / %d 場" % [floors, cleared, total])
	lines.append("被打中：每分鐘 %.1f 下、看不見的傷害 %d%%（全部場次與機器人，共 %.0f 秒；看不見 = 攻擊者不在視野裡或剛進視野不到 %s 秒，同遊玩紀錄）" % [_taken.hits / maxf(_taken.time, 1.0) * 60.0, roundi(100.0 * _taken.unseen_damage / maxf(_taken.damage, 1.0)), _taken.time, str(RunLog.REACT)])
	if _dig.runs > 0:
		var per_min := func(n: int) -> float: return n / maxf(_dig.time, 1.0) * 60.0
		lines.append("挖墳期間：每分鐘生 怪潮 %.1f、噴出 %.1f 隻，殺 怪潮 %.1f、噴出 %.1f 隻；有人在挖 %d%% 的時間；場上醒著最多平均 %.1f 隻（%d 場共 %.0f 秒，從開挖到挖完或全員倒下）" % [
			per_min.call(_dig.horde), per_min.call(_dig.erupt), per_min.call(_dig.horde_killed), per_min.call(_dig.erupt_killed),
			roundi(100.0 * _dig.digging / maxf(_dig.time, 1.0)), float(_dig.peak) / _dig.runs, _dig.runs, _dig.time])
	lines.append("觸發袋的時機每分鐘幾次（不管有沒有那種袋子、同一步算一次；全部場次與機器人平均，共 %.0f 秒）：%s" % [_moment_time, _moment_text()])
	lines.append("背包武器格 = 這層結束時背包裡武器占的格數（不含裝備中的）；背包滿的時間 = 第一次有武器撿不下（— = 沒滿過）；組隊時殺怪、掉落、靈魂是全隊的")
	var text := "\n".join(lines)
	print(text)
	if opts.has("out"):
		var f := FileAccess.open(String(opts.out), FileAccess.WRITE)
		f.store_string(text + "\n")
		f.close()
		print("寫入 %s" % opts.out)
	quit()


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func _play(seed_value: int, floors: int, classes: Array[StringName], opts: Dictionary) -> Array[String]:
	var w := World.new()
	var peers: Array[int] = []
	for i in classes.size():
		var peer := World.HOST_PEER_ID + i
		peers.append(peer)
		w.player_classes[peer] = classes[i]
	if opts.has("quota"):   # 小怪的出手名額：近戰,遠程,看不到的（0 = 不限）
		var q := String(opts["quota"]).split(",")
		for i in mini(q.size(), AttackQuota.KINDS.size()):
			w.attack_quota[AttackQuota.KINDS[i]] = int(q[i])
	if opts.get("bag-mode", "") == String(BagDefs.MODE_MERGED):
		w.bag_mode = BagDefs.MODE_MERGED
	w.reset(seed_value, peers)
	var start := int(opts.get("start", "0"))
	while start > 0 and w.stage_num < start:   # 直接跳到第 1 層第 start 小關（量 Boss 戰用）：每跳過一關給一個技能遺物，接近正常打過來的配裝
		w.next_stage(&"skill")
	var bots: Array = []
	for peer in peers:
		bots.append(Bot.new(w, w.players[peer], opts, seed_value))
	var rows: Array[String] = []
	for f in floors:
		rows.append_array(_play_floor(w, bots, seed_value))
		if bots.all(func(b: Variant) -> bool: return b.is_out) or w.is_defeated:
			break
		if f < floors - 1:
			w.next_floor()
	for b in bots:
		for k: StringName in b.p.trigger_moments:
			if not String(k).begins_with("tick:"):
				_moments[k] = _moments.get(k, 0) + b.p.trigger_moments[k]
		_moment_time += w.tick * DT
	w.clear()
	return rows


func _moment_text() -> String:
	var keys := _moments.keys()
	keys.sort()
	return "、".join(PackedStringArray(keys.map(func(k: StringName) -> String: return "%s %.1f" % [k, _moments[k] / maxf(_moment_time, 1.0) * 60.0])))


func _play_floor(w: World, bots: Array, seed_value: int) -> Array[String]:
	var kills := {"pack": 0, "event": 0, "boss": 0, "summon": 0}
	var drops := {&"white": 0, &"green": 0, &"blue": 0, &"purple": 0, &"orange": 0}
	var full_at := {}
	var fills := {}   # peer → 每小關結束時的「小關 主袋 / 袋子」
	var last_stage := w.stage_num
	var souls_start := w.souls
	var t := 0.0
	var logs := {}   # peer → 這一層的遊玩紀錄（被打中幾下、看不見的）
	var count_from := int(_opts.get("count-from", "0")) if w.floor_num == 1 else 0
	var t0 := 0.0   # 從第幾秒開始算受傷（--count-from）
	var dig_seen := {}   # 挖墳事件的怪 id → &"horde" / &"erupt"（第一次看到時還在飛 = 挖墳點噴出的）
	var dig_peak := 0
	for b in bots:
		b.begin_floor()
		var log := RunLog.new()
		log.me_id = b.p.id
		logs[b.peer] = log
	while t < MAX_FLOOR_TIME:
		var cmds := {}
		for b in bots:
			cmds[b.peer] = b.decide()
		w.step(cmds, DT)
		t += DT
		if w.stage_num != last_stage and w.stage_num == count_from:
			t0 = t
			for b in bots:
				b.reset_taken()
				logs[b.peer].reset()
				logs[b.peer].me_id = b.p.id
		if w.stage_num != last_stage:
			for b in bots:
				_note_fill(fills, b, w.floor_num, last_stage)
			last_stage = w.stage_num
		for log: RunLog in logs.values():
			log.track(w, t)
			for ev in w.events:
				log.on_event(w, ev.name, ev)
		if w.event.state == DigEvent.ACTIVE:
			_note_dig(w, bots, dig_seen)
			dig_peak = maxi(dig_peak, bots[0].awake_count())
		for ev in w.events:
			match ev.name:
				"entity:died":
					var e := w.entities.get(ev.get("entity_id", 0)) as Enemy
					if e != null and dig_seen.has(e.id) and w.event.state == DigEvent.ACTIVE:
						_dig[String(dig_seen[e.id]) + "_killed"] += 1
					if e != null and e.team != &"player":
						kills["boss" if e.is_boss() else ("summon" if e.no_souls else ("event" if e.wave_member else "pack"))] += 1
				"weapon:dropped":
					drops[StringName(ev.rarity)] += 1
		for b in bots:
			b.after_step(t)
			if b.full_seen and not full_at.has(b.peer):
				full_at[b.peer] = t
		if w.is_defeated:
			break
		if w.event.state == DigEvent.OPEN and bots.all(func(b: Variant) -> bool: return b.is_out or b.nearest_loot() == null):
			break
	for b in bots:
		_note_fill(fills, b, w.floor_num, last_stage)
	if not dig_seen.is_empty():
		_dig.runs += 1
		_dig.peak += dig_peak
	var total := 0
	for r in drops:
		total += drops[r]
	var rarity := "%d（%s）" % [total, " ".join(drops.values().map(func(v: int) -> String: return str(v)))]
	var timeout := " 逾時" if t >= MAX_FLOOR_TIME else ""
	var left := w.pickups.filter(func(x: Entity) -> bool: return not x.is_dead and not (x as ItemPickup).weapon.is_empty()).size()
	var spent_all := 0
	for b in bots:
		spent_all += b.spent
	var opened_all := 0
	for b in bots:
		opened_all += b.opened
	var souls := "%d / %d（%d）" % [w.souls - souls_start + spent_all, spent_all, opened_all]
	var rows: Array[String] = []
	for b in bots:
		var log: RunLog = logs[b.peer]
		_taken.time += t - t0
		_taken.hits += log.hits_taken
		_taken.damage += log.damage_taken
		_taken.unseen_damage += log.unseen_damage
		rows.append(_row(w, b, seed_value, t, timeout, kills, rarity, left, souls, full_at, bots.size() > 1, " ".join(PackedStringArray(fills.get(b.peer, []))), log, t0))
	return rows


# 挖墳事件進行中的這一步：記時間、有沒有人在挖、新出現的事件怪是怪潮還是噴出的
func _note_dig(w: World, bots: Array, seen: Dictionary) -> void:
	_dig.time += DT
	if bots.any(func(b: Variant) -> bool: return b.p.is_digging()):
		_dig.digging += DT
	for e in w.enemies:
		if e is Enemy and (e as Enemy).wave_member and not seen.has(e.id):
			var kind := &"erupt" if (e as Enemy).fsm.is_in(&"launch") else &"horde"
			seen[e.id] = kind
			_dig[String(kind)] += 1


# 記下這個機器人現在的主袋與袋子填滿率（佔了幾成）
func _note_fill(fills: Dictionary, b: Variant, floor_num: int, stage: int) -> void:
	var lo: Loadout = b.p.loadout
	var core_used := lo.core.occupied().size()
	var core_size := BagDefs.MAIN_SIZE.x * BagDefs.MAIN_SIZE.y
	var bag_used := 0
	var bag_size := 0
	for bag in lo.bags:
		bag_used += Inventory.for_bag(bag).occupied().size()
		bag_size += bag.length * bag.depth
	var list: Array = fills.get(b.peer, [])
	var opened := ""   # 背包合併：這時開了幾格（全部 - 鎖著）
	if lo.merged:
		opened = " 開%d" % (core_size + bag_size - lo.locked_spots().size())
	list.append("%d-%d %d%%/%d%%%s" % [floor_num, stage, roundi(100.0 * core_used / core_size), roundi(100.0 * bag_used / maxi(bag_size, 1)), opened])
	fills[b.peer] = list


func _row(w: World, b: Variant, seed_value: int, t: float, timeout: String, kills: Dictionary, rarity: String, left: int, souls: String,
		full_at: Dictionary, team: bool, fill_text: String, log: RunLog, t0 := 0.0) -> String:
	var p: Player = b.p
	var picked := 0
	var cells := 0
	for x in p.inventory.entries:
		if not x.get("weapon", {}).is_empty():
			picked += 1
			cells += Inventory.cells_of(x.id, x.rot).size()
	var gems: Array[String] = []
	var casts := 0   # 袋子裡的技能實際放出幾次（按鍵袋與觸發袋都算，Player.cast_log）
	for bag in p.loadout.bags:
		for e in bag.entries:
			if ItemDefs.is_skill(e.id) and SkillDefs.SKILLS[e.id].has("mana"):
				gems.append("%s %d" % [ItemDefs.ITEMS[e.id].name, p.skill_levels.get(e.id, 1)])
	for id: StringName in p.cast_log:
		if ItemDefs.is_skill(id):
			casts += p.cast_log[id][0]
	var skills := "%s · %d" % ["、".join(PackedStringArray(gems)) if not gems.is_empty() else "無", casts]
	var top := ""
	var top_n := 0
	for k: String in b.down_by:
		if b.down_by[k] > top_n:
			top = k
			top_n = b.down_by[k]
	var downs := "%d / %d%s · %d 下（%.1f）· %d%%" % [roundi(b.taken), b.downs, "（%s %d）" % [top, top_n] if top_n > 0 else "", log.hits_taken,
		log.hits_taken / maxf(t - t0, 1.0) * 60.0, roundi(100.0 * log.unseen_damage / maxf(log.damage_taken, 1.0))]
	var bonds: Array[String] = []
	for bond: StringName in p.loadout.bond_counts:
		bonds.append("%s %d" % [BondDefs.BONDS[bond].name, p.loadout.bond_counts[bond]])
	var a: Dictionary = b.acts
	var acts := "%d / %d / %d / %d / %d / %d / %d / %d / %d / %d" % [a.roll, a.jump, a.block, a.potion, a.swap, a.merge, a.drop, a.socket, a.reroll, a.rescue]
	var moves: Array = b.hit_by.keys()
	moves.sort_custom(func(x: String, y: String) -> bool: return b.hit_by[x] > b.hit_by[y])
	var worst: Array[String] = []
	for m: String in moves.slice(0, 3):
		worst.append("%s %d" % [m, roundi(b.hit_by[m])])
	var result: String = "死在 " + b.died_at if b.died_at != "" else ("逾時" if timeout != "" else "打完")
	var who := "%d" % seed_value if not team else "%d %s" % [seed_value, ClassDefs.CLASSES[p.class_id].name]
	return "| %s | %d | %s%s | %d（%d / %d / %d / %d） | %s | %d | %d | %s | %d | %s | %s | %s | %s | %s | %s | %s | %s |" % [who, w.floor_num,
		Bot._mmss(t), timeout, kills.pack + kills.event + kills.boss + kills.summon, kills.pack, kills.event, kills.boss, kills.summon, rarity,
		picked, cells, Bot._mmss(full_at[p.peer_id]) if full_at.has(p.peer_id) else "—", left, souls, fill_text, skills,
		"、".join(PackedStringArray(bonds)) if not bonds.is_empty() else "無", acts, downs, result, "、".join(PackedStringArray(worst))]
