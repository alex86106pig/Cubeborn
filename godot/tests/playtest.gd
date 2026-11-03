# 自動試玩：headless 的機器人照真實地圖玩一層（或好幾層），量殺怪數、武器掉落、背包佔用、靈魂，給「調掉落 / 怪量 / 節奏」當依據
# 平常用 `node tools/release.mjs --playtest` 跑；直接跑：在 godot/ 內 <Godot> --headless --path . -s res://tests/playtest.gd -- 參數
# 參數：--floors=N（幾層，預設 1）、--seeds=1,2,3（每個種子各玩一場，預設 1,2,3）、--class=guardian（職業，預設守墓騎士）、
#       --style=full|rush（full：清完怪群 → 打 Boss → 挖墳；rush：直接挖墳，只打靠近的怪，預設 full）、--out=檔案（另存 Markdown）
#       --play=smart|dumb（smart：躲招、舉盾、遠程拉開、喝藥水、換更好的武器；dumb：都不做，當「不會玩的人」那一端，預設 smart）
#       --react=秒（smart 看到怪物出招後多久才反應，預設 0.25；高手 0.15、新手 0.4）
#       --pick=smart|random（3 選 1：smart 照技能 / 羈絆挑、沒得挑就用骰子重擲；random 隨機選、不用骰子，確認隨機的 Build 也打得完，預設 smart）
# 機器人不會死（每步補滿血），量的是「打完一層會拿到多少東西」；難度看「會倒幾次」：另外扣一條虛擬血（最大生命），照受到的傷害扣到 0 就記一次、補滿再扣
# 虛擬血照遊戲的規則自然回血（受傷後 regen_delay 內不回）、喝藥水加回藥水的量；真實血一直是滿的，吸血、招架回血這類回在滿血上的算不到
# 武器全撿（背包放不下才留在地上）；靈魂夠就開祭壇 / 石棺（石棺優先），開出來的 3 選 1 跟地上的遺物、鐵砧一樣去選，打怪時魔力夠、目標在範圍內就放技能與耗魔的右鍵
extends SceneTree

const DT := 1.0 / 60.0
# 躲招：怪物在這些狀態以外就當成正在出招（新怪的狀態不用登記也會躲）；瞄準（aim）不躲人，改躲射出來的投射物
const SAFE_STATES: Array[StringName] = [&"chase", &"patrol", &"spawn", &"hurt", &"dead", &"train", &"dormant", &"dazed", &"fallen",
	&"collapse", &"guard_broken", &"stagger", &"fetch", &"kite", &"aim", &"stalk", &"wolf_chase", &"colossus_chase", &"reveal", &"grow",
	&"transform", &"wheel_stun", &"burrow", &"surface", &"summon", &"whistle", &"howl"]
const LUNGE_STATES: Array[StringName] = [&"charge", &"leap", &"pounce", &"lunge", &"rush", &"roll", &"wheel", &"hop"]   # 衝過來的招：往側面滾
const THREAT_REACH := 3.0              # 一般招式：雙方身體邊緣距離這麼近才躲
const LUNGE_REACH := 8.0               # 衝刺類的招
const BOSS_EXTRA := 2.0                # Boss 的招大一圈
const DODGE_ANGLE := 0.7               # 一般招式往「遠離怪物」偏這麼多弧度滾（斜後方，比正後方不容易被追上）
const PROJ_WARN := 0.35                # 投射物這麼多秒內會打到就躲
const ROLL_LEAD := 0.15                # 預兆結束前這麼多秒才滾（無敵 0.2 秒蓋住打下來那一刻）；太早滾，會轉向追人的招照樣打到
const COMMIT_TIME := 0.6               # 躲完之後這麼久只躲 Boss 的招，先打一輪（一群屍犬輪流撲時才不會一直滾、打不到 Boss）
const EVADE_MAX := 1.2                 # 躲過一招後最多退這麼久就回去打（慢動作、連續出招的 Boss 不會一直退）
const DEATH_BLAST := 1.0               # 死後會爆的怪：死後這麼多秒內都算威脅（膨脹屍 0.5、死亡爆炸詞條 0.8 秒後爆）
const KITE_DIST := 3.5                 # 遠程職業：怪貼到這麼近就往後退
const POTION_AT := 0.4                 # 虛擬血低於最大生命的這個比例就喝藥水
const REROLL_BELOW := 0.5              # 3 選 1 最好的選項分數低於這個、還有骰子就重擲
const MAX_FLOOR_TIME := 30.0 * 60.0   # 一層最多模擬這麼久（卡住時不會一直跑）
const PATH_REFRESH := 0.5             # 每隔幾秒重新找路
const STUCK_TIME := 25.0              # 追同一個目標這麼久、血都沒掉（打不到）就放棄它；有在掉血就繼續打（Boss 血多，25 秒打不完）
const LOOT_RANGE := INF               # 多遠的武器都去撿（量「全撿」的上限；身邊沒怪才去）
const SAFE_RANGE := 5.0               # 身邊這麼近有怪就先打怪
const DIG_GUARD := 3.5                # 挖墳時身邊這麼近有怪就停下來打
const SUMMONER_RANGE := 15.0          # 這麼近有帶召喚詞條的怪就先打它（不然叫出來的打不完）
const RANGED := [&"staff", &"shortbow", &"longbow"]

var _w: World
var _p: Player
var _path := PackedVector2Array()
var _path_goal := Vector2.INF
var _path_timer := 0.0
var _target_id := 0
var _target_time := 0.0
var _target_hp := 0.0                 # 這次開始計時時目標的血
var _skip: Dictionary = {}            # 放棄的目標 id
var _tap := false                     # F 要放開再按才算「剛按下」
var _full_seen := false               # 附近有武器但背包放不下
var _casts := 0                       # 這一層放了幾次技能（數字鍵）與耗魔的右鍵
var _relic_skip: Dictionary = {}      # 走不到的遺物 id
var _relic_time := 0.0
var _relic_target := 0
var _spent := 0                       # 這一層開寶箱花掉的靈魂
var _opened := 0                      # 這一層開了幾個寶箱
var _vhp := 0.0                       # 虛擬血：照受到的傷害扣，到 0 記一次「會倒」
var _downs := 0
var _down_by := {}                    # 打出最後一下的種類 → 次數
var _taken := 0.0                     # 這一層受到的傷害
var _smart_play := true
var _smart_pick := true
var _react := 0.25
var _rng := RandomNumberGenerator.new()   # --pick=random 用，跟著種子
var _reacted := {}                    # 怪物 id → 已經躲過的出招狀態（同一招只躲一次）
var _proj_seen := {}                  # 已經躲過的投射物 id
var _rerolled := {}                   # 重擲過的遺物 id
var _block_id := 0                    # 正在對著舉盾的怪（0 = 沒有）
var _block_broken := false            # 舉盾還被那隻怪打到（那招擋不住）
var _evade_id := 0                    # 正在躲的那隻怪：那招結束前不走回去
var _evade_time := 0.0                # 這次已經退了幾秒
var _commit := 0.0                    # 躲完後先打的剩餘秒數
var _evade_side := 1.0                # 往哪一邊偏（跟翻滾同一邊）
var _windups := {}                    # 「怪物種類·狀態」→ 資料裡的預兆秒數（-1 = 查不到），查過就記著
var _unblockable := {}                # 舉盾還被打到的「怪物種類·狀態」：之後這招改滾（每個種子重新學）
var _block_time := 0.0                # 對著投射物舉盾剩幾秒
var _drinking := false                # 這一步按了喝藥水：真實血先扣 1，藥水才喝得下去
var _hands := ["", ""]                # 主手 / 副手武器的 uid：變了就是換過武器
var _acts := {"roll": 0, "block": 0, "potion": 0, "swap": 0, "reroll": 0}
var _hit_by := {}                     # 「怪物·招式」→ 受到的傷害


func _initialize() -> void:
	var opts := _args()
	var seeds: Array = []
	for s in String(opts.get("seeds", "1,2,3")).split(","):
		seeds.append(int(s))
	var floors := int(opts.get("floors", "1"))
	var cls := StringName(opts.get("class", "guardian"))
	var style := String(opts.get("style", "full"))
	_smart_play = String(opts.get("play", "smart")) != "dumb"
	_smart_pick = String(opts.get("pick", "smart")) != "random"
	_react = float(opts.get("react", "0.25"))
	var how := "玩法 %s（反應 %.2f 秒）、3 選 1 %s" % ["smart" if _smart_play else "dumb", _react, "smart" if _smart_pick else "random"]
	var lines: Array[String] = ["# 自動試玩", "", "職業 %s、打法 %s、%s、%d 層、種子 %s；背包 %d × %d = %d 格" % [cls, style, how, floors, str(seeds), ItemDefs.BAG_SIZE.x, ItemDefs.BAG_SIZE.y, ItemDefs.BAG_SIZE.x * ItemDefs.BAG_SIZE.y], "",
		"| 種子 | 層 | 時間 | 殺怪（怪群 / 事件 / Boss / 召喚） | 掉武器（白綠藍紫橘） | 撿到 | 背包武器格 | 背包滿的時間 | 地上沒撿 | 靈魂 賺到 / 花掉（開幾箱） | 技能（等級）· 放幾次 | 羈絆 | 翻滾 / 擋 / 喝藥 / 換武器 / 重擲 | 受傷 / 會倒幾次（最多被誰） | 最痛的招 |", "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
	for s in seeds:
		lines.append_array(_play(int(s), floors, cls, style))
	lines.append("")
	lines.append("背包武器格 = 這層結束時背包裡武器占的格數（不含裝備中的）；背包滿的時間 = 第一次有武器撿不下（— = 沒滿過）")
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


func _play(seed_value: int, floors: int, cls: StringName, style: String) -> Array[String]:
	_w = World.new()
	_w.player_classes[World.HOST_PEER_ID] = cls
	_w.reset(seed_value)
	_p = _w.players[World.HOST_PEER_ID]
	# 每場從乾淨的機器人狀態開始（同一個程序連跑好幾個種子）
	_path = PackedVector2Array()
	_path_goal = Vector2.INF
	_path_timer = 0.0
	_target_id = 0
	_target_time = 0.0
	_skip.clear()
	_tap = false
	_full_seen = false
	_relic_skip.clear()
	_relic_target = 0
	_rerolled.clear()
	_unblockable.clear()
	_rng.seed = seed_value
	_hands = [_p.weapon_slots[Loadout.MAIN].get("uid", ""), _p.weapon_slots[Loadout.OFF].get("uid", "")]
	var reach: float = 6.0 if ClassDefs.CLASSES[cls].weapon in RANGED else 1.4
	var rows: Array[String] = []
	for f in floors:
		rows.append(_play_floor(seed_value, style, reach))
		if f < floors - 1:
			_w.next_floor()
	_w.clear()
	return rows


func _play_floor(seed_value: int, style: String, reach: float) -> String:
	var kills := {"pack": 0, "event": 0, "boss": 0, "summon": 0}
	var drops := {&"white": 0, &"green": 0, &"blue": 0, &"purple": 0, &"orange": 0}
	var picked := 0
	var full_at := -1.0
	var souls_start := _w.souls
	var t := 0.0
	_skip.clear()
	_target_id = 0
	_full_seen = false
	_casts = 0
	_spent = 0
	_opened = 0
	_vhp = _p.max_hp
	_downs = 0
	_down_by.clear()
	_taken = 0.0
	_reacted.clear()
	_proj_seen.clear()
	_block_id = 0
	_block_broken = false
	_evade_id = 0
	_commit = 0.0
	_block_time = 0.0
	_hit_by.clear()
	for k: String in _acts:
		_acts[k] = 0
	while t < MAX_FLOOR_TIME:
		var cmd := _decide(style, reach)
		_p.hp = _p.max_hp - (1.0 if _drinking else 0.0)   # 不會死：量的是拿到多少東西
		_w.step({World.HOST_PEER_ID: cmd}, DT)
		t += DT
		if _p.regen_block_timer <= 0.0:   # 同 Entity 的自然回血：受傷後 regen_delay 內不回
			_vhp = minf(_p.max_hp, _vhp + _p.stats.value(&"hp_regen") * DT)
		for i in Loadout.OFF + 1:
			var uid: Variant = _p.weapon_slots[i].get("uid", "")
			if uid != _hands[i]:
				_hands[i] = uid
				_acts.swap += 1
		for ev in _w.events:
			match ev.name:
				"entity:died":
					var e := _w.entities.get(ev.get("entity_id", 0)) as Enemy
					if e != null and e.team != &"player":
						kills["boss" if e.is_boss() else ("summon" if e.no_souls else ("event" if e.wave_member else "pack"))] += 1
				"weapon:dropped":
					drops[StringName(ev.rarity)] += 1
				"entity:damaged":
					if ev.get("target_id", 0) == _p.id:
						_taken += ev.amount
						_vhp -= ev.amount
						if _block_id != 0 and ev.get("source_id", 0) == _block_id:
							var blocker := _w.entities.get(_block_id) as Enemy
							if blocker != null:
								_unblockable[_move_key(blocker)] = true
							_block_broken = true
						var move := _move_name(ev)
						_hit_by[move] = _hit_by.get(move, 0.0) + ev.amount
						if _vhp <= 0.0:
							_downs += 1
							var k: String = RunLog.name_of(ev.get("source_kind", &""))
							_down_by[k] = _down_by.get(k, 0) + 1
							_vhp = _p.max_hp
				"chest:opened":
					var c := _w.entities.get(ev.get("chest_id", 0)) as Chest
					if ev.get("player_id", 0) == _p.id and c != null:
						_spent += c.price_for(_p)
						_opened += 1
				"skill:used":
					if ev.get("player_id", 0) != _p.id:
						pass
					elif ev.get("key", "") == ActiveSlots.cd_key(ActiveSlots.HEAL_INDEX):
						_vhp = minf(_p.max_hp, _vhp + float(SkillDefs.SKILLS.heal.amount))   # 真實血是滿的，喝到的量照藥水的資料加回虛擬血
						_acts.potion += 1
					elif ev.get("key", "") == Player.ROLL_CD:
						_acts.roll += 1
					else:
						_casts += 1
				"player:blocked":
					if ev.get("player_id", 0) == _p.id:
						_acts.block += 1
				"relic:rerolled":
					if ev.get("player_id", 0) == _p.id:
						_acts.reroll += 1
		if full_at < 0.0 and _full_seen:
			full_at = t
		picked = _p.inventory.entries.filter(func(x: Dictionary) -> bool: return not x.get("weapon", {}).is_empty()).size()
		if _w.event.state == DigEvent.OPEN and _nearest_loot() == null:
			break
	var cells := 0
	for x in _p.inventory.entries:
		if not x.get("weapon", {}).is_empty():
			cells += Inventory.cells_of(x.id, x.rot).size()
	var total := 0
	for r in drops:
		total += drops[r]
	var rarity := "%d（%s）" % [total, " ".join(drops.values().map(func(v: int) -> String: return str(v)))]
	var timeout := " 逾時" if t >= MAX_FLOOR_TIME else ""
	var left := _w.pickups.filter(func(x: Entity) -> bool: return not x.is_dead and not (x as ItemPickup).weapon.is_empty()).size()
	var gems: Array[String] = []
	for g in _p.slots.gems(_p):
		if g.def.has("mana"):
			gems.append("%s %d" % [ItemDefs.ITEMS[g.id].name, _p.skill_levels.get(g.id, 1)])
	var skills := "%s · %d" % ["、".join(PackedStringArray(gems)) if not gems.is_empty() else "無", _casts]
	var souls := "%d / %d（%d）" % [_w.souls - souls_start + _spent, _spent, _opened]
	var top := ""
	var top_n := 0
	for k: String in _down_by:
		if _down_by[k] > top_n:
			top = k
			top_n = _down_by[k]
	var downs := "%d / %d%s" % [roundi(_taken), _downs, "（%s %d）" % [top, top_n] if top_n > 0 else ""]
	var bonds: Array[String] = []
	for b: StringName in _p.loadout.bond_counts:
		bonds.append("%s %d" % [BondDefs.BONDS[b].name, _p.loadout.bond_counts[b]])
	var acts := "%d / %d / %d / %d / %d" % [_acts.roll, _acts.block, _acts.potion, _acts.swap, _acts.reroll]
	var moves := _hit_by.keys()
	moves.sort_custom(func(a: String, b: String) -> bool: return _hit_by[a] > _hit_by[b])
	var worst: Array[String] = []
	for m: String in moves.slice(0, 3):
		worst.append("%s %d" % [m, roundi(_hit_by[m])])
	return "| %d | %d | %s%s | %d（%d / %d / %d / %d） | %s | %d | %d | %s | %d | %s | %s | %s | %s | %s | %s |" % [seed_value, _w.floor_num, _mmss(t), timeout,
		kills.pack + kills.event + kills.boss + kills.summon, kills.pack, kills.event, kills.boss, kills.summon, rarity, picked, cells,
		"—" if full_at < 0.0 else _mmss(full_at), left, souls, skills, "、".join(PackedStringArray(bonds)) if not bonds.is_empty() else "無",
		acts, downs, "、".join(PackedStringArray(worst))]


# 受傷事件是哪一招打的：「怪物·狀態」；打到時怪物已經不在出招（射完箭在拉開距離、地上的毒霧）記成「射出的」，怪物不在了記種類
func _move_name(ev: Dictionary) -> String:
	var who: String = RunLog.name_of(ev.get("source_kind", &""))
	var src := _w.entities.get(ev.get("source_id", 0)) as Enemy
	if src == null or src.fsm == null:
		return who
	return "%s·%s" % [who, "射出的" if src.fsm.current_name in SAFE_STATES and not src.is_dead else String(src.fsm.current_name)]


func _mmss(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


# 這一步要做什麼：身邊有怪先打 → 附近有武器去撿 → 照打法找下一個目標（怪群 → Boss → 挖墳）
func _decide(style: String, reach: float) -> InputCmd:
	var cmd := InputCmd.new()
	cmd.aim = _p.pos + Vector2(0, 1)
	_tap = not _tap
	_drinking = false
	if _p.grabbed_by != 0:   # 被腐屍抓住：照畫面的提示按翻滾掙脫（不然一直被抓著不能打，又不會死）
		if _tap:
			cmd.buttons |= InputCmd.BTN_ROLL
		return cmd
	if _smart_play:
		_drink(cmd)
		_swap(cmd)
		if _guard(cmd):
			return cmd
	var summoner := _nearest_summoner()
	if summoner != null:
		return _fight(cmd, summoner, reach)
	var near := _nearest_enemy(SAFE_RANGE, false)
	var digging_phase := style == "rush" or (_nearest_enemy(INF, false) == null and _boss_done())
	var boss := _boss()
	if near != null and not (digging_phase and _p.pos.distance_to(near.pos) > DIG_GUARD):
		# Boss 叫出來的小怪（不給靈魂）：Boss 醒著就直接打 Boss，不然 Boss 一直叫、小怪打不完
		if near.no_souls and near.summoner_id == 0 and boss != null and _boss_awake(boss):
			return _fight(cmd, boss, reach)
		return _fight(cmd, _summoner_of(near), reach)
	var loot := _nearest_loot()
	if loot != null:
		_walk(cmd, loot.pos)
		if _w.can_reach(_p, loot) and _tap:
			cmd.buttons |= InputCmd.BTN_INTERACT
		return cmd
	var relic := _next_relic()
	if relic != null:
		return _use_relic(cmd, relic)
	var chest := _next_chest()
	if chest != null:
		_walk(cmd, chest.pos)
		if _w.can_reach(_p, chest) and _tap:
			cmd.buttons |= InputCmd.BTN_INTERACT
		return cmd
	if boss != null and _boss_awake(boss):
		return _fight(cmd, boss, reach)   # Boss 醒了先打它（不然它一直叫小怪，機器人會打不完）
	if not digging_phase:
		var e := _nearest_enemy(INF, false)
		if e == null:
			e = _boss()
		if e != null:
			return _fight(cmd, _summoner_of(e), reach)
	if _w.event.state == DigEvent.OPEN:
		return cmd
	var point := _w.event.point
	if _p.pos.distance_to(point) > EventDefs.DIG.range * 0.6:
		_walk(cmd, point)
	else:
		cmd.buttons |= InputCmd.BTN_INTERACT
	return cmd


func _fight(cmd: InputCmd, e: Entity, reach: float) -> InputCmd:
	if e.id != _target_id:
		_target_id = e.id
		_target_time = 0.0
		_target_hp = e.hp
	_target_time += DT
	if _target_time > STUCK_TIME:
		if e.hp < _target_hp - 0.5:   # 有在掉血：重新計時
			_target_time = 0.0
			_target_hp = e.hp
		else:
			_skip[e.id] = true
	cmd.aim = e.pos
	# 舉盾的盾槍兵：正面 shield.arc 內全部擋下、舉盾時轉身慢，站在正面就先往牠身側繞（不出手），繞出盾的範圍再打
	var sp := e as Spearman
	if sp != null and sp.is_guarding():
		var to_me := _p.pos - sp.pos
		if absf(angle_difference(sp.facing, atan2(to_me.x, to_me.y))) <= sp.def.shield.arc / 2.0 + 0.2:
			var front := Vector2(sin(sp.facing), cos(sp.facing))
			var side := front.orthogonal() * (1.0 if front.orthogonal().dot(to_me) >= 0.0 else -1.0)
			_walk(cmd, sp.pos + side * (reach + sp.radius + 0.5) - front * 0.5)
			cmd.aim = sp.pos
			return cmd
	var close := _nearest_enemy(KITE_DIST, true) if _smart_play and reach > KITE_DIST else null
	if close != null and (close.dormant or not _w.nav_for(_p.radius).has_los(_p.pos, close.pos)):
		close = null   # 休眠的、隔著牆的不退：不然走向目標途中經過牠旁邊會來回打轉
	if close != null:   # 遠程：怪貼上來就往後退著打（瞄準不變）
		var away := (_p.pos - close.pos).normalized()
		_walk(cmd, _p.pos + away * 4.0)
		cmd.aim = e.pos
	elif _p.pos.distance_to(e.pos) > reach + e.radius:
		_walk(cmd, e.pos)
	cmd.buttons |= InputCmd.BTN_ATTACK
	_cast(cmd, e, reach)
	return cmd


# 數字鍵 1~4 的技能：放得出來（魔力、冷卻、次數）、目標在技能的範圍內就放（一步放一個）；再看耗魔的右鍵
func _cast(cmd: InputCmd, e: Entity, reach: float) -> void:
	var d := _p.pos.distance_to(e.pos) - e.radius
	for i in ActiveSlots.GEM_SLOTS:
		var slot: Variant = _p.slots.get_slot(_p, i)
		if slot == null or not slot.def.has("mana") or not _p.slots.can_use(_p, i):
			continue
		if d <= _skill_range(slot.def, reach):
			cmd.buttons |= InputCmd.slot_bit(i)
			return
	var special: Dictionary = _p.weapon.get("special", {})
	if special.has("mana") and _p.has_mana(_p.mana_cost_of(special)) and d <= _skill_range(special, reach):
		cmd.buttons |= InputCmd.BTN_SPECIAL


# 技能打得到多遠：資料的 range（射出去）/ distance（衝刺）/ radius（身邊一圈），都沒有就用普攻距離
static func _skill_range(def: Dictionary, reach: float) -> float:
	for k in ["range", "distance", "radius"]:
		if def.has(k):
			return maxf(float(def[k]) * 0.9, reach)
	return reach + 1.0


# 躲招：怪物出招（不在 SAFE_STATES，或死後會爆的剛死）超過反應時間、我在牠的範圍內就反應，同一招只反應一次：
#   手上有盾、這招沒被記成擋不住、不是衝刺類 → 對著牠舉盾到那招結束；舉盾還被這招打到 → 記成擋不住（下次改滾），有充能就馬上滾開
#   其他 → 翻滾（沒充能就用走的），之後那招沒結束、人還在範圍內就繼續往外退，不走回去吃下一下
# 投射物 PROJ_WARN 秒內會打到 → 有盾就舉盾，沒有就往側面滾。這一步有動作就回傳 true（不做別的事）
func _guard(cmd: InputCmd) -> bool:
	if _p.action.current_name == &"roll":
		return false
	var has_shield: bool = _p.weapon.get("special", {}).get("behavior", &"") == &"shieldBlock"
	if _block_time > 0.0:
		_block_time -= DT
		cmd.buttons |= InputCmd.BTN_SPECIAL_HELD
		return true
	_commit = maxf(0.0, _commit - DT)
	if _evade_id != 0:
		if _keep_evading(cmd):
			return true
		_commit = COMMIT_TIME
	_evade_id = 0
	_block_id = 0
	for x in _w.enemies:
		var e := x as Enemy
		if e == null or e.team == &"player" or e.fsm == null:
			continue
		var reach := _threat_reach(e)
		if reach < 0.0:
			_reacted.erase(e.id)
			continue
		if _commit > 0.0 and not e.is_boss():
			continue
		var state := e.fsm.current_name
		if _reacted.get(e.id, &"") == state or e.fsm.time < _react:
			continue
		if _p.pos.distance_to(e.pos) - e.radius - _p.radius > reach:
			continue
		var can_block := has_shield and not e.is_dead and not (state in LUNGE_STATES) and not _unblockable.has(_move_key(e))
		if not can_block and e.fsm.time < _windup_of(e) - ROLL_LEAD * e.action_speed:   # fsm.time 已經乘過 action_speed
			continue   # 看到了，等快打下來才滾（舉盾不用等，早舉沒損失）
		_reacted[e.id] = state
		_evade_id = e.id
		_evade_time = 0.0
		if can_block:
			_block_id = e.id
			cmd.aim = e.pos
			_hold_shield(cmd)
			return true
		var away := (_p.pos - e.pos).normalized()
		if _p.roll_charges > 0:
			_roll(cmd, away, PI / 2.0 if state in LUNGE_STATES else DODGE_ANGLE)
		else:
			cmd.move = away.rotated(DODGE_ANGLE * _evade_side)
		return true
	for x in _w.projectiles:
		var pr := x as Projectile
		if pr == null or pr.is_removed or pr.team == &"player" or _proj_seen.has(pr.id) or pr.speed <= 0.0:
			continue
		if pr.traveled / pr.speed < _react:
			continue
		var rel := _p.pos - pr.pos
		var along := rel.dot(pr.direction)
		if along <= 0.0 or along / pr.speed > PROJ_WARN or absf(rel.cross(pr.direction)) > _p.radius + pr.radius + 0.2:
			continue
		_proj_seen[pr.id] = true
		if has_shield and pr.blockable:
			cmd.aim = pr.pos
			cmd.buttons |= InputCmd.BTN_SPECIAL_HELD
			_block_time = along / pr.speed + 0.1
			return true
		if _p.roll_charges > 0:
			_roll(cmd, pr.direction, PI / 2.0)
			return true
	return false


# 正在躲的那招還沒結束、人還在範圍內：舉盾的繼續舉（被打穿就滾），其他往外退；招結束或離開範圍回傳 false
func _keep_evading(cmd: InputCmd) -> bool:
	var e := _w.entities.get(_evade_id) as Enemy
	_evade_time += DT
	if e == null or e.is_removed or _evade_time > EVADE_MAX or _threat_reach(e) < 0.0 or _reacted.get(e.id, &"") != e.fsm.current_name:
		return false
	var reach := _threat_reach(e) + 1.0
	if _p.pos.distance_to(e.pos) - e.radius - _p.radius > reach:
		return false
	var away := (_p.pos - e.pos).normalized()
	cmd.aim = e.pos
	if _block_id == e.id:
		if not _block_broken:
			_hold_shield(cmd)
			return true
		_block_id = 0
		_block_broken = false
		if _p.roll_charges > 0:
			_roll(cmd, away, DODGE_ANGLE)
			return true
	_walk(cmd, _p.pos + away.rotated(DODGE_ANGLE * _evade_side) * 3.0)   # 斜著退：直直往後退會順著放射狀的招（骨刺陣）一路被打
	cmd.aim = e.pos
	return true


# 這隻怪現在的威脅範圍（身體邊緣距離）；沒在出招回傳 -1。死後會爆的（膨脹屍、死亡爆炸詞條）剛死的 DEATH_BLAST 秒內也算
func _threat_reach(e: Enemy) -> float:
	var extra := BOSS_EXTRA if e.is_boss() else 0.0
	if e.is_dead:
		var blasts := (e.type == &"bloater" or e.has_affix(&"volatile")) and not e.no_death_effect
		return THREAT_REACH if blasts and e.fsm.time < DEATH_BLAST else -1.0
	var state := e.fsm.current_name
	if state in SAFE_STATES:
		return -1.0
	return (LUNGE_REACH if state in LUNGE_STATES else THREAT_REACH) + extra


# 舉盾，同時連按左鍵招架（WeaponBehaviors.ShieldBlock：時機對就盾反、不對打出半傷的盾擊，按了不會白按）
func _hold_shield(cmd: InputCmd) -> void:
	cmd.buttons |= InputCmd.BTN_SPECIAL_HELD
	if _tap:
		cmd.buttons |= InputCmd.BTN_ATTACK


# 這招資料裡的預兆秒數：怪物資料（含變身後的子表，一層）裡跟狀態同名、有 windup 的那一項；查不到回傳 -1（照反應時間滾）
func _windup_of(e: Enemy) -> float:
	var key := _move_key(e)
	if not _windups.has(key):
		var found := -1.0
		var tables: Array = [e.def]
		for v: Variant in e.def.values():
			if v is Dictionary:
				tables.append(v)
		for t: Dictionary in tables:
			var move: Variant = t.get(String(e.fsm.current_name), null)
			if move is Dictionary and (move as Dictionary).has("windup"):
				found = float(move.windup)
				break
		_windups[key] = found
	return _windups[key]


func _move_key(e: Enemy) -> String:
	return "%s·%s" % [e.type, e.fsm.current_name]


# 往 base 轉 ±angle 的方向滾：先挑落點看得到（不會滾進牆）的那一邊，兩邊都不行就照 base 滾
func _roll(cmd: InputCmd, base: Vector2, angle: float) -> void:
	var nav := _w.nav_for(_p.radius)
	var dir := base
	for a: float in [angle, -angle]:
		var d := base.rotated(a)
		if nav.has_los(_p.pos, _p.pos + d * Config.ROLL.distance):
			dir = d
			_evade_side = signf(a)
			break
	cmd.move = dir
	cmd.buttons |= InputCmd.BTN_ROLL


# 虛擬血低於 POTION_AT、藥水還有次數又不在冷卻就按 Q
func _drink(cmd: InputCmd) -> void:
	if _vhp >= _p.max_hp * POTION_AT or _p.slots.heal.charges <= 0:
		return
	if not _w.cooldowns.is_ready(_p.cd(ActiveSlots.cd_key(ActiveSlots.HEAL_INDEX))):
		return
	cmd.buttons |= InputCmd.slot_bit(ActiveSlots.HEAL_INDEX)
	_drinking = true


# 背包裡有跟主手 / 副手同一種、稀有度更高的武器就換上（鑲的道具由 Loadout 搬過去）；一步換一把
func _swap(cmd: InputCmd) -> void:
	for x in _p.inventory.entries:
		var inst: Dictionary = x.get("weapon", {})
		if inst.is_empty():
			continue
		for i in Loadout.OFF + 1:
			var hand: Dictionary = _p.weapon_slots[i]
			if hand.is_empty() or Loadout.weapon_of(hand) != Loadout.weapon_of(inst):
				continue
			if WeaponDropDefs.RARITY_ORDER.find(inst.rarity) > WeaponDropDefs.RARITY_ORDER.find(hand.rarity):
				cmd.inv_ops.append([InputCmd.OP_EQUIP, x.uid, i])
				return


# 靈魂買得起、還沒開的寶箱：石棺優先（3 選 1 的稀有度比較高），同種取最近的；走 STUCK_TIME 秒到不了就放棄
func _next_chest() -> Chest:
	var best: Chest = null
	var best_score := INF
	for x in _w.chests:
		var c := x as Chest
		if c == null or c.is_removed or c.opened or _relic_skip.has(c.id) or _w.souls < c.price_for(_p):
			continue
		var score := _p.pos.distance_to(c.pos) - (1000.0 if c.tier == &"big" else 0.0)
		if score < best_score:
			best_score = score
			best = c
	if best != null:
		if best.id != _relic_target:
			_relic_target = best.id
			_relic_time = 0.0
		_relic_time += DT
		if _relic_time > STUCK_TIME:
			_relic_skip[best.id] = true
	return best


# 還沒選過的遺物 / 鐵砧（最近的、走得到的）
func _next_relic() -> Relic:
	var best: Relic = null
	var best_d := INF
	for x in _w.relics:
		var r := x as Relic
		if r == null or r.is_removed or r.taken.has(_p.peer_id) or _relic_skip.has(r.id):
			continue
		var d := _p.pos.distance_to(r.pos)
		if d < best_d:
			best_d = d
			best = r
	return best


# 走過去按 F 打開，打開了就選（_relic_choice）；最好的選項分數太低、還有骰子就先重擲
func _use_relic(cmd: InputCmd, r: Relic) -> InputCmd:
	if r.id != _relic_target:
		_relic_target = r.id
		_relic_time = 0.0
	_relic_time += DT
	if _relic_time > STUCK_TIME:
		_relic_skip[r.id] = true
	if _p.relic_id == r.id:
		var opts: Array = r.offers.get(_p.peer_id, [])
		if opts.is_empty():
			return cmd
		if not _smart_pick:
			cmd.inv_ops.append([InputCmd.OP_RELIC_PICK, r.id, _rng.randi_range(0, maxi(0, opts.size() - 1))])
			return cmd
		var best := _relic_choice(opts)
		if _choice_score(opts[best]) < REROLL_BELOW and _p.dice > 0 and not _rerolled.has(r.id):
			_rerolled[r.id] = true   # 一個寶箱最多重擲一次，不把骰子全花在同一個上
			cmd.inv_ops.append([InputCmd.OP_RELIC_REROLL, r.id])
		else:
			cmd.inv_ops.append([InputCmd.OP_RELIC_PICK, r.id, best])
		return cmd
	_walk(cmd, r.pos)
	if _w.can_reach(_p, r) and _tap:
		cmd.buttons |= InputCmd.BTN_INTERACT
	return cmd


func _relic_choice(opts: Array) -> int:
	var best := 0
	for i in opts.size():
		if _choice_score(opts[i]) > _choice_score(opts[best]):
			best = i
	return best


# 3 選 1 每個選項的分數（越高越想要，< 0 = 拿了沒用）：
#   技能：已經有、還沒滿級（再選一次升級）10；手上武器能鑲、還沒有 9；其他（鑲不上、滿級）-1
#   道具：每個羈絆 1 + 現有件數（在走的羈絆優先），補上這件剛好湊到下一階再 +3；同一種已經鑲著（不多算羈絆）-1；沒有羈絆 0.1
#   鐵砧第一步的詞條：「羈絆 +1」照道具的算法，其他詞條 0.2
func _choice_score(id: StringName) -> float:
	if WeaponDropDefs.AFFIXES.has(id):
		var a: Dictionary = WeaponDropDefs.AFFIXES[id]
		return _bond_score(a.bond) if a.kind == &"bond" else 0.2
	if ItemDefs.is_skill(id):
		var owned := _p.loadout.has_item(id)
		if _p.skill_levels.get(id, 1) >= SkillDefs.LEVEL.max:
			return -1.0
		if owned:
			return 10.0
		return 9.0 if _fits_hands(id) else -1.0
	if _p.loadout.items.any(func(it: Dictionary) -> bool: return it.id == id):
		return -1.0
	var bonds: Array = ItemDefs.ITEMS.get(id, {}).get("bonds", [])
	if bonds.is_empty():
		return 0.1
	var s := 0.0
	for b: StringName in bonds:
		s += _bond_score(b)
	return s


func _bond_score(bond: StringName) -> float:
	var have: int = _p.loadout.bond_counts.get(bond, 0)
	return 1.0 + have + (3.0 if BondDefs.next_threshold(bond, have) == have + 1 else 0.0)


func _fits_hands(skill: StringName) -> bool:
	for i in Loadout.OFF + 1:
		var w := Loadout.weapon_of(_p.weapon_slots[i])
		if w != &"" and SkillDefs.can_socket(skill, w):
			return true
	return false


func _walk(cmd: InputCmd, goal: Vector2) -> void:
	_path_timer -= DT
	if _path_timer <= 0.0 or goal.distance_to(_path_goal) > 1.0:
		_path_timer = PATH_REFRESH
		_path_goal = goal
		var nav := _w.nav_for(_p.radius)
		_path = PackedVector2Array() if nav.has_los(_p.pos, goal) else nav.find_path(_p.pos, goal)
	while _path.size() > 1 and _p.pos.distance_to(_path[0]) < 0.6:
		_path.remove_at(0)
	var to := goal if _path.is_empty() else _path[0]
	cmd.move = (to - _p.pos).normalized()
	# 高台：尋路的格子把高台當可走（怪物會跳上去），路線會經過高台，玩家要自己跳。照怪物的規則（Enemy._update_jump）看地圖：
	# 沿著要走的方向、身體邊緣再往前 jump_lookahead 的地面比腳下高出一個台階、又不超過 climb_height（墓碑太高不跳）就起跳
	var ahead := _p.pos + cmd.move * (_p.radius + Config.NAV.jump_lookahead)
	var rise := _w.terrain.ground_at(ahead) - _p.ground_height
	if _p.is_grounded() and rise > Config.HEIGHT.step and rise <= Config.NAV.climb_height:
		cmd.buttons |= InputCmd.BTN_JUMP
	if cmd.aim.distance_to(_p.pos + Vector2(0, 1)) < 0.01:
		cmd.aim = _p.pos + cmd.move * 5.0


func _nearest_enemy(radius: float, include_boss: bool) -> Enemy:
	var best: Enemy = null
	var best_d := radius
	for x in _w.enemies:
		var e := x as Enemy
		if e == null or e.is_dead or e.team == &"player" or _skip.has(e.id) or (e.is_boss() and not include_boss):
			continue
		var d := _p.pos.distance_to(e.pos)
		if d < best_d:
			best_d = d
			best = e
	return best


# 被召喚出來的怪：召喚者還活著就去打召喚者（只打送上門的會打不完，召喚者每隔幾秒又叫一批）
func _summoner_of(e: Enemy) -> Enemy:
	var s := _w.entities.get(e.summoner_id) as Enemy if e.summoner_id != 0 else null
	return s if s != null and not s.is_dead and not _skip.has(s.id) else e


func _nearest_summoner() -> Enemy:
	var best: Enemy = null
	var best_d := SUMMONER_RANGE
	for x in _w.enemies:
		var e := x as Enemy
		if e == null or e.is_dead or e.team == &"player" or _skip.has(e.id) or not e.affixes.has(&"summoner"):
			continue
		var d := _p.pos.distance_to(e.pos)
		if d < best_d:
			best_d = d
			best = e
	return best


func _boss() -> Enemy:
	var b := _w.entities.get(_w.boss_id) as Enemy
	return null if b == null or b.is_dead or _skip.has(b.id) else b


func _boss_awake(b: Enemy) -> bool:
	return not (b.has_method(&"is_npc") and b.call(&"is_npc"))


func _boss_done() -> bool:
	return _boss() == null


# 附近還沒撿、背包放得下的武器
func _nearest_loot() -> ItemPickup:
	var best: ItemPickup = null
	var best_d := LOOT_RANGE
	for x in _w.pickups:
		var ip := x as ItemPickup
		if ip == null or ip.is_dead or ip.weapon.is_empty() or _skip.has(ip.id):
			continue
		var d := _p.pos.distance_to(ip.pos)
		if _p.inventory.find_spot(ip.item_id).is_empty():
			_full_seen = true
			continue
		if d < best_d:
			best_d = d
			best = ip
	if best != null:
		if best.id != _target_id:
			_target_id = best.id
			_target_time = 0.0
			_target_hp = 0.0
		_target_time += DT
		if _target_time > STUCK_TIME:
			_skip[best.id] = true
	return best
