# 自動試玩：headless 的機器人照真實地圖玩一層（或好幾層），量殺怪數、武器掉落、背包佔用、靈魂，給「調掉落 / 怪量 / 節奏」當依據
# 平常用 `node tools/release.mjs --playtest` 跑；直接跑：在 godot/ 內 <Godot> --headless --path . -s res://tests/playtest.gd -- 參數
# 參數：--floors=N（幾層，預設 1）、--seeds=1,2,3（每個種子各玩一場，預設 1,2,3）、--class=guardian（職業，預設守墓騎士）、
#       --style=full|rush（full：清完怪群 → 打 Boss → 挖墳；rush：直接挖墳，只打靠近的怪，預設 full）、--out=檔案（另存 Markdown）
# 機器人不會死（每步補滿血），量的是「打完一層會拿到多少東西」，不是難度；武器全撿（背包放不下才留在地上），不開祭壇 / 石棺（靈魂另外列）
extends SceneTree

const DT := 1.0 / 60.0
const MAX_FLOOR_TIME := 30.0 * 60.0   # 一層最多模擬這麼久（卡住時不會一直跑）
const PATH_REFRESH := 0.5             # 每隔幾秒重新找路
const STUCK_TIME := 25.0              # 追同一個目標這麼久還沒解決就放棄它
const LOOT_RANGE := INF               # 多遠的武器都去撿（量「全撿」的上限；身邊沒怪才去）
const SAFE_RANGE := 5.0               # 身邊這麼近有怪就先打怪
const DIG_GUARD := 3.5                # 挖墳時身邊這麼近有怪就停下來打
const SUMMONER_RANGE := 15.0          # 這麼近有帶召喚詞條的怪就先打它（不然叫出來的打不完）
const RANGED := [&"staff", &"shortbow", &"longbow"]
const JUMP_LOOK := 0.6                # 前方這麼遠的地面比腳底高出一個台階（高台）就跳
const STILL_JUMP := 0.3               # 有在走但這麼久都沒動（卡在邊緣）也跳一下

var _w: World
var _p: Player
var _path := PackedVector2Array()
var _path_goal := Vector2.INF
var _path_timer := 0.0
var _target_id := 0
var _target_time := 0.0
var _skip: Dictionary = {}            # 放棄的目標 id
var _tap := false                     # F 要放開再按才算「剛按下」
var _full_seen := false               # 附近有武器但背包放不下
var _last_pos := Vector2.INF
var _still_time := 0.0


func _initialize() -> void:
	var opts := _args()
	var seeds: Array = []
	for s in String(opts.get("seeds", "1,2,3")).split(","):
		seeds.append(int(s))
	var floors := int(opts.get("floors", "1"))
	var cls := StringName(opts.get("class", "guardian"))
	var style := String(opts.get("style", "full"))
	var lines: Array[String] = ["# 自動試玩", "", "職業 %s、打法 %s、%d 層、種子 %s；背包 %d × %d = %d 格" % [cls, style, floors, str(seeds), ItemDefs.BAG_SIZE.x, ItemDefs.BAG_SIZE.y, ItemDefs.BAG_SIZE.x * ItemDefs.BAG_SIZE.y], "",
		"| 種子 | 層 | 時間 | 殺怪（怪群 / 事件 / Boss / 召喚） | 掉武器（白綠藍紫橘） | 撿到 | 背包武器格 | 背包滿的時間 | 地上沒撿 | 靈魂 |", "|---|---|---|---|---|---|---|---|---|---|"]
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
	return "| %d | %d | %s%s | %d（%d / %d / %d / %d） | %s | %d | %d | %s | %d | %d |" % [seed_value, _w.floor_num, _mmss(t), timeout,
		kills.pack + kills.event + kills.boss + kills.summon, kills.pack, kills.event, kills.boss, kills.summon, rarity, picked, cells,
		"—" if full_at < 0.0 else _mmss(full_at), left, _w.souls - souls_start]


func _mmss(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


# 這一步要做什麼：身邊有怪先打 → 附近有武器去撿 → 照打法找下一個目標（怪群 → Boss → 挖墳）
func _decide(style: String, reach: float) -> InputCmd:
	var cmd := InputCmd.new()
	cmd.aim = _p.pos + Vector2(0, 1)
	_tap = not _tap
	var summoner := _nearest_summoner()
	if summoner != null:
		return _fight(cmd, summoner, reach)
	var near := _nearest_enemy(SAFE_RANGE, false)
	var digging_phase := style == "rush" or (_nearest_enemy(INF, false) == null and _boss_done())
	if near != null and not (digging_phase and _p.pos.distance_to(near.pos) > DIG_GUARD):
		return _fight(cmd, near, reach)
	var loot := _nearest_loot()
	if loot != null:
		_walk(cmd, loot.pos)
		if _w.can_reach(_p, loot) and _tap:
			cmd.buttons |= InputCmd.BTN_INTERACT
		return cmd
	var boss := _boss()
	if boss != null and _boss_awake(boss):
		return _fight(cmd, boss, reach)   # Boss 醒了先打它（不然它一直叫小怪，機器人會打不完）
	if not digging_phase:
		var e := _nearest_enemy(INF, false)
		if e == null:
			e = _boss()
		if e != null:
			return _fight(cmd, e, reach)
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
	_target_time += DT
	if _target_time > STUCK_TIME:
		_skip[e.id] = true
	cmd.aim = e.pos
	if _p.pos.distance_to(e.pos) > reach + e.radius:
		_walk(cmd, e.pos)
	cmd.buttons |= InputCmd.BTN_ATTACK
	return cmd


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
	# 高台：尋路把它當可走（怪物會跳上去），玩家要按跳；前面高起來、或走了一陣子都沒動就跳
	var moved := _last_pos != Vector2.INF and _p.pos.distance_to(_last_pos) > 0.01
	_still_time = 0.0 if moved else _still_time + DT
	_last_pos = _p.pos
	var ahead := _w.terrain.ground_at(_p.pos + cmd.move * JUMP_LOOK)
	if _p.is_grounded() and (ahead > _p.height + Config.HEIGHT.step or _still_time > STILL_JUMP):
		cmd.buttons |= InputCmd.BTN_JUMP
		_still_time = 0.0
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
		_target_time += DT
		if _target_time > STUCK_TIME:
			_skip[best.id] = true
	return best
