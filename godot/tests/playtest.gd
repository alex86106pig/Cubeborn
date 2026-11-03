# 自動試玩：headless 的機器人照真實地圖玩一層（或好幾層），量殺怪數、武器掉落、背包佔用、靈魂，給「調掉落 / 怪量 / 節奏」當依據
# 平常用 `node tools/release.mjs --playtest` 跑；直接跑：在 godot/ 內 <Godot> --headless --path . -s res://tests/playtest.gd -- 參數
# 參數：--floors=N（幾層，預設 1）、--seeds=1,2,3（每個種子各玩一場，預設 1,2,3）、--class=guardian（職業，預設守墓騎士）、
#       --style=full|rush（full：清完怪群 → 打 Boss → 挖墳；rush：直接挖墳，只打靠近的怪，預設 full）、--out=檔案（另存 Markdown）
# 機器人不會死（每步補滿血），量的是「打完一層會拿到多少東西」；難度看「會倒幾次」：另外扣一條虛擬血（最大生命），照受到的傷害扣到 0 就記一次、補滿再扣
# 機器人不閃不擋、不喝藥水，比真人容易倒，當成「不會玩的人」的上限看。武器全撿（背包放不下才留在地上）
# 靈魂夠就開祭壇 / 石棺（石棺優先），開出來的 3 選 1 跟地上的遺物、鐵砧一樣去選（優先主手武器能鑲的技能，已經有就升級），打怪時魔力夠、目標在範圍內就放技能與耗魔的右鍵
extends SceneTree

const DT := 1.0 / 60.0
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


func _initialize() -> void:
	var opts := _args()
	var seeds: Array = []
	for s in String(opts.get("seeds", "1,2,3")).split(","):
		seeds.append(int(s))
	var floors := int(opts.get("floors", "1"))
	var cls := StringName(opts.get("class", "guardian"))
	var style := String(opts.get("style", "full"))
	var lines: Array[String] = ["# 自動試玩", "", "職業 %s、打法 %s、%d 層、種子 %s；背包 %d × %d = %d 格" % [cls, style, floors, str(seeds), ItemDefs.BAG_SIZE.x, ItemDefs.BAG_SIZE.y, ItemDefs.BAG_SIZE.x * ItemDefs.BAG_SIZE.y], "",
		"| 種子 | 層 | 時間 | 殺怪（怪群 / 事件 / Boss / 召喚） | 掉武器（白綠藍紫橘） | 撿到 | 背包武器格 | 背包滿的時間 | 地上沒撿 | 靈魂 賺到 / 花掉（開幾箱） | 技能（等級）· 放幾次 | 受傷 / 會倒幾次（最多被誰） |", "|---|---|---|---|---|---|---|---|---|---|---|---|"]
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
	while t < MAX_FLOOR_TIME:
		var cmd := _decide(style, reach)
		_p.hp = _p.max_hp   # 不會死：量的是拿到多少東西
		_w.step({World.HOST_PEER_ID: cmd}, DT)
		t += DT
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
					if ev.get("player_id", 0) == _p.id and ev.get("key", "") != ActiveSlots.cd_key(ActiveSlots.HEAL_INDEX):
						_casts += 1
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
	return "| %d | %d | %s%s | %d（%d / %d / %d / %d） | %s | %d | %d | %s | %d | %s | %s | %s |" % [seed_value, _w.floor_num, _mmss(t), timeout,
		kills.pack + kills.event + kills.boss + kills.summon, kills.pack, kills.event, kills.boss, kills.summon, rarity, picked, cells,
		"—" if full_at < 0.0 else _mmss(full_at), left, souls, skills, downs]


func _mmss(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


# 這一步要做什麼：身邊有怪先打 → 附近有武器去撿 → 照打法找下一個目標（怪群 → Boss → 挖墳）
func _decide(style: String, reach: float) -> InputCmd:
	var cmd := InputCmd.new()
	cmd.aim = _p.pos + Vector2(0, 1)
	_tap = not _tap
	if _p.grabbed_by != 0:   # 被腐屍抓住：照畫面的提示按翻滾掙脫（不然一直被抓著不能打，又不會死）
		if _tap:
			cmd.buttons |= InputCmd.BTN_ROLL
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
	if _p.pos.distance_to(e.pos) > reach + e.radius:
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


# 走過去按 F 打開，打開了就選：鐵砧第一步的詞條選第一個；技能優先選主手武器能鑲的（已經有就是升級），沒有就選第一個
func _use_relic(cmd: InputCmd, r: Relic) -> InputCmd:
	if r.id != _relic_target:
		_relic_target = r.id
		_relic_time = 0.0
	_relic_time += DT
	if _relic_time > STUCK_TIME:
		_relic_skip[r.id] = true
	if _p.relic_id == r.id:
		cmd.inv_ops.append([InputCmd.OP_RELIC_PICK, r.id, _relic_choice(r)])
		return cmd
	_walk(cmd, r.pos)
	if _w.can_reach(_p, r) and _tap:
		cmd.buttons |= InputCmd.BTN_INTERACT
	return cmd


func _relic_choice(r: Relic) -> int:
	var opts: Array = r.offers.get(_p.peer_id, [])
	var base := Loadout.weapon_of(_p.weapon_slots[Loadout.MAIN])
	var fallback := 0
	for i in opts.size():
		var id: StringName = opts[i]
		if not ItemDefs.is_skill(id):
			continue
		if SkillDefs.can_socket(id, base) and _p.skill_levels.get(id, 1) < SkillDefs.LEVEL.max:
			return i
		fallback = i if fallback == 0 else fallback
	return fallback


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
