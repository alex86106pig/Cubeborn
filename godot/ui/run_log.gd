# 遊玩紀錄：只記本機玩家這一局的擊殺、受到的傷害（依攻擊者種類分）、被看不見的攻擊打中幾次、每次倒下被誰打倒；
# 結算畫面顯示（ui/hud.gd）。只讀事件與模擬狀態，不修改模擬；連線時客戶端用房主送來的事件各記各的
# 「看不見」：被打中那一刻攻擊者不在自己的視野裡（sim/vision.gd，牆擋視線也算看不見；攻擊者已經消失時用攻擊的出發點判斷），
#   或是身邊 TRACK_RANGE 內的攻擊者在打中前才剛進視野、連續看得到不到 REACT 秒（2026-11-02 使用者同意：屍犬在背後伏低、撲進身邊 4 單位才看得到，
#   打中那一刻一定看得到，原本永遠算 0）。追蹤靠 track() 每幀更新；沒追蹤到的（太遠、剛出現）只看打中那一刻
# 武器（2026-11-02 使用者要求，看掉落率合不合適）：掉了幾把（分稀有度，全隊共用的掉落）、自己撿了幾把、背包第一次撿不下的時間、現在的武器幾分換上
# 回報：report_text() 是結算畫面「複製遊玩紀錄」的精簡文字（貼到聊天軟體），另含版本、平台、配裝、效能、連線數據
# 效能另記顯示卡、解析度與畫面設定（2026-10-27）：一局中切換過陰影 / 光源時依設定分開統計，內顯玩一局就有對照組
class_name RunLog
extends RefCounted

const MAX_DOWNS_SHOWN := 5
const HITCH := 0.05   # 一幀超過這麼多秒算卡頓
const HITCH_AFTER_CHANGE := 1.0   # 換小關 / 換層 / 開局後這麼多秒內的卡頓算在那一下（換地圖那一步之後的下一幀才量到）
const MAX_HITCHES_SHOWN := 20     # 回報列出前幾次卡頓的時間點
const REACT := 0.4         # 攻擊者連續看得到不到這麼多秒就打中，算「看不見」（來不及反應）
const TRACK_RANGE := 8.0   # 這麼近的怪每幀記錄看不看得到（遠的只看打中那一刻，省效能）
const RARITY_ORDER: Array[StringName] = [&"gray", &"white", &"green", &"blue", &"purple", &"orange"]
# Boss 名字同 HUD.BOSS_NAME；不直接引用 HUD：check.gd（-s 腳本）會用到本檔，引用 HUD 會連帶要求 autoload GameEvents 而編譯失敗
const NAMES := {
	&"grunt": "骷髏戰士", &"archer": "骷髏弓手", &"zombie": "腐屍", &"bloater": "膨脹屍", &"hound": "屍犬", &"spider": "墓穴蜘蛛", &"beetle": "屍甲蟲", &"bone_wheel": "骨輪", &"spearman": "骷髏盾槍兵", &"boss": "亡骸騎士", &"bone_general": "骸骨將軍", &"gravekeeper": "守墓人", &"ghost": "冤魂", &"minion": "骷髏僕從",
	&"projectile": "投射物（射手已死）", &"player": "隊友（誤傷）",
}
const ALLY_PREFIX := "ally:"   # 隊友誤傷依隊友當時拿的武器分開記：種類寫成「ally:劍盾」

var me_id := 0          # 本機玩家的實體 id（HUD 每次有角色時更新；倒下 / 陣亡後角色還在，id 不變）
const KILLS_PER_LINE := 6   # 擊殺一行最多幾種
var kills := {}         # 種類 → 隻數（只算自己打死的）
var damage_taken := 0.0
var hits_taken := 0
var unseen_hits := 0
var unseen_damage := 0.0
var by_source := {}     # 種類 → {damage, hits, unseen}
const DEALT_ROWS := 6   # 結算畫面「你造成的傷害」最多列幾項，其餘併成「其他」（畫面高度有限）
const DEALT_PER_LINE := 2
var damage_dealt := 0.0
var by_credit := {}     # 傷害來源（Combat.credit_scope 的代號；左右鍵另帶武器名「p|劍盾」）→ {damage, hits}
var downs: Array[Dictionary] = []   # 每次倒下 / 死亡：{kind, unseen}
var result := ""       # 結算標題（HUD._set_game_over）
var floors: Array[Dictionary] = []   # 每層：{ floor, map, start, event_start, event_open, layout }（時間是這局第幾秒；-1 = 還沒）
var weapon_drops := {}       # 稀有度 → 掉了幾把（全隊共用）
var weapons_picked := 0      # 自己撿起殺怪掉的武器幾把
var bag_full_at := -1.0      # 第一次有東西撿不下的時間（秒，-1 = 沒有）
var weapon_since := 0.0      # 現在的主手武器幾秒時換上
var _weapon_uid := ""
const MANA_LOW := 0.1        # 魔力低於最大值的這個比例算「見底」
var mana_low_time := 0.0     # 這局魔力見底的累計秒數（每幀看本機玩家的魔力，客戶端用快照的）
var mana_low_first := -1.0   # 第一次見底是第幾秒（-1 = 沒有）
var _last_track := -1.0
var _dropped := {}           # 殺怪掉的武器 uid（撿起時才算進 weapons_picked，開場的武器不算）
var _visible_since := {}     # 身邊的怪 id → 從幾秒開始連續看得到（看不到就移除）
var _pending_floor := {}     # 客戶端：已收到換層 / 換小關事件、鏡像還沒換好（floor、stage）
# 效能：遊戲進行中每幀的秒數（HUD 交給這裡）
var frames := 0
var frame_time := 0.0
var worst_frame := 0.0
var worst_at := 0.0     # 最慢那一幀在這局第幾秒
var hitches := 0
var hitch_list: Array[Dictionary] = []   # 每次卡頓：{at: 這局第幾秒, ms, phase: 開局 / 換小關 / 換層 / 一般}（只存前 MAX_HITCHES_SHOWN 次）
var video := ""         # 目前的畫面設定（設定頁 video_text，main.gd 每次改動時設定）
var by_video := {}      # 畫面設定 → {frames, time, hitches}
var worst_context := "" # 最慢那一幀當時的畫面狀況（frame_context 回傳）
var frame_context := Callable()   # main.gd 接上：回傳「光 N 盞、怪 N 隻」，只在出現新的最慢一幀時呼叫
# 連線數據：main.gd 接上，回傳 { role, players, rtt_ms: Array[int], snapshot_gap_max_ms, input_gap_max_ms: {peer_id: 毫秒} }
var net_info := Callable()


func reset() -> void:
	kills.clear()
	damage_taken = 0.0
	hits_taken = 0
	unseen_hits = 0
	unseen_damage = 0.0
	by_source.clear()
	damage_dealt = 0.0
	by_credit.clear()
	downs.clear()
	result = ""
	floors.clear()
	weapon_drops.clear()
	weapons_picked = 0
	bag_full_at = -1.0
	weapon_since = 0.0
	_weapon_uid = ""
	mana_low_time = 0.0
	mana_low_first = -1.0
	_last_track = -1.0
	_dropped.clear()
	_visible_since.clear()
	_pending_floor = {}
	frames = 0
	frame_time = 0.0
	worst_frame = 0.0
	worst_at = 0.0
	hitches = 0
	hitch_list.clear()
	by_video.clear()
	worst_context = ""


func add_frame(delta: float, run_time: float) -> void:
	frames += 1
	frame_time += delta
	if delta > worst_frame:
		worst_frame = delta
		worst_at = run_time
		worst_context = frame_context.call() if frame_context.is_valid() else ""
	if delta > HITCH:
		hitches += 1
		if hitch_list.size() < MAX_HITCHES_SHOWN:
			hitch_list.append({"at": run_time, "ms": roundi(delta * 1000.0), "phase": _hitch_phase(run_time)})
	var v: Dictionary = by_video.get_or_add(video, {"frames": 0, "time": 0.0, "hitches": 0})
	v.frames += 1
	v.time += delta
	v.hitches += int(delta > HITCH)


# 卡頓當時在做什麼：這一層 / 這一小關開始後 HITCH_AFTER_CHANGE 秒內 → 開局（第一筆）/ 換層 / 換小關，其他算一般
func _hitch_phase(run_time: float) -> String:
	if floors.is_empty() or run_time - floors[-1].start > HITCH_AFTER_CHANGE:
		return "一般"
	if floors.size() == 1:
		return "開局"
	return "換層" if floors[-1].floor != floors[-2].floor else "換小關"


# 「卡頓的時間點：1:05 換小關 190 ms、…」；沒卡頓回傳空字串
func hitch_text() -> String:
	if hitch_list.is_empty():
		return ""
	var parts: Array[String] = []
	for h in hitch_list:
		parts.append("%s %s %d ms" % [UiKit.format_time(h.at), h.phase, h.ms])
	var more := "…等共 %d 次" % hitches if hitches > hitch_list.size() else ""
	return "卡頓的時間點：%s%s" % ["、".join(PackedStringArray(parts)), more]


# 每幀（HUD，和 add_frame 同時）：身邊的怪從幾秒開始看得到、主手武器換了沒
func track(world: World, now: float) -> void:
	if not _pending_floor.is_empty() and world != null and world.floor_num == _pending_floor.floor and world.stage_num == _pending_floor.stage:
		_begin_floor(world, _pending_floor)
	var me: Player = world.entities.get(me_id) as Player if world != null else null
	if me == null:
		return
	var inst := me.active_weapon()
	var uid := String(inst.get("uid", ""))
	if uid != _weapon_uid:
		_weapon_uid = uid
		weapon_since = now
	var dt := now - _last_track if _last_track >= 0.0 else 0.0
	_last_track = now
	if not me.is_dead and not me.is_downed and me.max_mana() > 0.0 and me.mana < me.max_mana() * MANA_LOW:
		mana_low_time += maxf(0.0, dt)
		if mana_low_first < 0.0:
			mana_low_first = now
	var seen := {}
	for e: Entity in world.enemies:
		if e.is_dead or e.pos.distance_squared_to(me.pos) > TRACK_RANGE * TRACK_RANGE:
			continue
		if Vision.point_visible(world, me, e.pos, e.radius):
			seen[e.id] = _visible_since.get(e.id, now)
	_visible_since = seen


func on_event(world: World, name: String, p: Dictionary) -> void:
	match name:
		"entity:damaged":
			if me_id != 0 and p.has("credit") and p.get("by", p.get("source_id", 0)) == me_id:
				_add_dealt(world, String(p.credit), p.get("amount", 0.0))
			if me_id == 0 or p.get("target_id", 0) != me_id:
				return
			var kind: StringName = p.get("source_kind", &"")
			if kind == &"player":
				var ally := world.entities.get(p.get("source_id", 0)) as Player if world != null else null
				if ally != null and ally.weapon.has("name"):
					kind = StringName(ALLY_PREFIX + String(ally.weapon.name))
			var amount: float = p.get("amount", 0.0)
			var unseen := not _attacker_seen(world, p) or _too_sudden(world, p)
			var s: Dictionary = by_source.get(kind, {"damage": 0.0, "hits": 0, "unseen": 0})
			s.damage += amount
			s.hits += 1
			hits_taken += 1
			damage_taken += amount
			if unseen:
				s.unseen += 1
				unseen_hits += 1
				unseen_damage += amount
			by_source[kind] = s
			if p.get("lethal", false):
				downs.append({"kind": kind, "unseen": unseen})
		"entity:died":
			var kind: StringName = p.get("kind", &"")
			if me_id != 0 and p.get("source_id", 0) == me_id and kind != &"player":
				kills[kind] = kills.get(kind, 0) + 1
		"weapon:dropped":
			var r := StringName(p.get("rarity", ""))
			weapon_drops[r] = weapon_drops.get(r, 0) + 1
			_dropped[p.get("uid", "")] = true
		"weapon:added":
			if me_id != 0 and p.get("player_id", 0) == me_id and _dropped.has(p.get("uid", "")):
				_dropped.erase(p.uid)
				weapons_picked += 1
		"inventory:full":
			if me_id != 0 and p.get("player_id", 0) == me_id and p.get("pickup_id", 0) != 0 and bag_full_at < 0.0:
				bag_full_at = world.stats.time if world != null else 0.0
		"game:restart":
			reset()
			_begin_floor(world)
		"floor:started", "stage:started":
			_begin_floor(world, p)
		"event:started":
			if not floors.is_empty() and world != null:
				floors[-1].event_start = world.stats.time
		"event:exit_open":
			if not floors.is_empty() and world != null:
				floors[-1].event_open = world.stats.time


# 新的一層（開局或換層）：記地圖、開始時間與這一層的地形（同一個種子重開也看得到，回報不必重玩就知道長怎樣）
# p：事件內容（floor、stage）。客戶端的事件可能比快照先到，鏡像還是上一關：先記著，等 track 看到換好了再記
func _begin_floor(world: World, p: Dictionary = {}) -> void:
	if world == null:
		return
	_pending_floor = {}
	if p.get("floor", world.floor_num) != world.floor_num or p.get("stage", world.stage_num) != world.stage_num:
		_pending_floor = {"floor": p.floor, "stage": p.stage}
		return
	floors.append({"floor": world.floor_num, "stage": world.stage_num, "map": world.map.get("name", String(world.map_id)), "start": world.stats.time,
		"event_start": -1.0, "event_open": -1.0, "layout": MapDefs.layout_text(world.layout)})


# 「第 1 層 墓園 A 8:17（撬開 1:52）門 北；區塊 …」一層一行；最後一層算到 now
func floors_text(now: float) -> Array[String]:
	var out: Array[String] = []
	for i in floors.size():
		var f: Dictionary = floors[i]
		var end: float = floors[i + 1].start if i + 1 < floors.size() else now
		var line := "%s %s %s" % [World.level_name(f.floor, f.get("stage", 0)), f.map, UiKit.format_time(end - f.start)]
		if f.event_start >= 0.0:
			line += "（出口事件 %s）" % (UiKit.format_time(f.event_open - f.event_start) if f.event_open >= 0.0 else "進行中")
		if f.layout != "":
			line += " " + f.layout
		out.append(line)
	return out


func _attacker_seen(world: World, p: Dictionary) -> bool:
	var me: Player = world.entities.get(me_id) if world != null else null
	if me == null:
		return true
	# 不用 Vision.entity_visible：致命的那一下自己已經倒地，那個函式會把所有東西都當成看得到
	var src: Entity = world.entities.get(p.get("source_id", 0))
	if src != null and not src.is_removed and src != me:
		return Vision.point_visible(world, me, src.pos, src.radius)
	return Vision.point_visible(world, me, p.get("origin", me.pos))


# 身邊的攻擊者打中前連續看得到不到 REACT 秒（屍犬從背後撲進來）；沒追蹤到的不算
func _too_sudden(world: World, p: Dictionary) -> bool:
	var id: int = p.get("source_id", 0)
	if world == null or not _visible_since.has(id):
		return false
	return world.stats.time - _visible_since[id] < REACT


static func name_of(kind: StringName) -> String:
	if String(kind).begins_with(ALLY_PREFIX):
		return "%s · %s" % [NAMES[&"player"], String(kind).trim_prefix(ALLY_PREFIX)]
	return NAMES.get(kind, String(kind) if kind != &"" else "不明")


func total_kills() -> int:
	var n := 0
	for k: StringName in kills:
		n += kills[k]
	return n


# 結算畫面「複製遊玩紀錄」：一行一項的精簡文字，貼到聊天軟體回報（不用 JSON 符號）
func report_text(world: World) -> String:
	var lines: Array[String] = []
	var platform := "網頁版" if OS.has_feature("web") else "%s（%s）" % [OS.get_name(), RenderingServer.get_current_rendering_method()]
	lines.append("Cubeborn v%s · %s · %s · 種子 %d" % [GameVersion.VERSION, platform, Time.get_datetime_string_from_system(false, true), world.run_seed])
	var screen := DisplayServer.window_get_size()
	lines.append("顯示卡：%s · %d×%d · %s" % [RenderingServer.get_video_adapter_name(), screen.x, screen.y, video])
	var s := world.stats
	var mode_name: String = EventDefs.MODES[world.difficulty_mode].name
	var where := "%s · 難度 %d（%s）" % [World.level_name(world.floor_num, world.stage_num), floori(world.difficulty()), mode_name] if world.has_floors() else "第 %d 波" % s.wave
	var boss: Enemy = world.entities.get(world.boss_id) as Enemy
	if boss != null and not boss.is_dead:
		var forms: Array = boss.def.get("form_names", [])
		var boss_name: String = forms[clampi(boss.anim.get("form", 0), 0, forms.size() - 1)] if not forms.is_empty() else name_of(boss.kind)
		where += " · %s剩 %d%% 血" % [boss_name, roundi(100.0 * boss.hp / boss.max_hp)]
	lines.append("結果：%s · %s · %s" % [result if result != "" else "進行中", where, UiKit.format_time(s.time)])
	lines.append_array(floors_text(s.time))
	var me: Player = world.entities.get(me_id) as Player
	if me != null:
		var inst := me.active_weapon()
		var items: Array[String] = []
		for it: Dictionary in me.items:
			items.append(ItemDefs.ITEMS[it.id].name)
		lines.append("武器：%s；道具：%s；靈魂 %d；本局金幣 %d" % [WeaponDropDefs.display_name(inst) if not inst.is_empty() else me.weapon.name,
			"、".join(PackedStringArray(items)) if not items.is_empty() else "無", world.souls, world.run_coins])
		lines.append(bags_text(me))
		lines.append(mana_text(me, world.is_authority))
	lines.append_array(summary_text().split("
"))
	if frames > 0:
		var at := UiKit.format_time(worst_at) + ("，" + worst_context if worst_context != "" else "")
		lines.append("效能：平均 %d FPS · 最慢一幀 %d ms（%s）· 卡頓（超過 %d ms）%d 次" % [
			roundi(frames / maxf(frame_time, 1e-6)), roundi(worst_frame * 1000.0), at, roundi(HITCH * 1000.0), hitches])
		if not hitch_list.is_empty():
			lines.append("  " + hitch_text())
		if by_video.size() > 1:   # 一局中切換過畫面設定：各設定分開列，就是對照組
			for key: String in by_video:
				var v: Dictionary = by_video[key]
				lines.append("  %s：平均 %d FPS · 卡頓 %d 次（%s）" % [key, roundi(v.frames / maxf(v.time, 1e-6)), v.hitches, UiKit.format_time(v.time)])
	var n: Dictionary = net_info.call() if net_info.is_valid() else {}
	if not n.is_empty():   # 單機時 main.gd 回傳空的
		lines.append(net_text(n))
	return "
".join(lines)


# 「袋子：左鍵打中時（旋風斬、雷鳴符文）· 按鍵 1（冰霜新星）…」：每個接著的袋子和裡面的技能 / 效果
static func bags_text(me: Player) -> String:
	var parts: Array[String] = []
	for b in me.loadout.bags:
		var names: Array[String] = []
		for e in BagTriggers.contents(b):
			if ItemDefs.role_of(e.id) in [ItemDefs.ROLE_SKILL, ItemDefs.ROLE_EFFECT]:
				names.append(String(ItemDefs.ITEMS[e.id].name))
		if not names.is_empty():
			parts.append("%s（%s）" % [InventoryPanel.head_text(b), "、".join(PackedStringArray(names))])
	var head := "袋子（背包合併，還鎖著 %d 格）：" % me.loadout.locked_spots().size() if me.loadout.merged else "袋子："
	return head + (" · ".join(PackedStringArray(parts)) if not parts.is_empty() else "沒有放技能或效果")


# 「魔力：最大 120 · 見底（低於 10%）共 1:23，第一次 2:05；放出 / 魔力不夠：旋風斬 40 / 12 …」；放出次數只有房主與單機記得到
func mana_text(me: Player, is_authority: bool) -> String:
	var low := "沒有見底過" if mana_low_first < 0.0 else "見底（低於 %d%%）共 %s，第一次 %s" % [roundi(MANA_LOW * 100.0), UiKit.format_time(mana_low_time), UiKit.format_time(mana_low_first)]
	var text := "魔力：最大 %d · %s" % [roundi(me.max_mana()), low]
	if not is_authority:
		return text + "（放出次數只有房主看得到）"
	var ids := me.cast_log.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return me.cast_log[a][0] > me.cast_log[b][0])
	var parts: Array[String] = []
	for id: StringName in ids:
		parts.append("%s %d / %d" % [ItemDefs.ITEMS[id].name, me.cast_log[id][0], me.cast_log[id][1]])
	if not parts.is_empty():
		text += "；放出 / 魔力不夠：" + "、".join(PackedStringArray(parts))
	return text


static func net_text(n: Dictionary) -> String:
	var parts: Array[String] = ["連線：%s · %d 人" % [n.role, n.players]]
	if n.get("layout_mismatch", 0) > 0:
		parts.append("怪群配置跟房主不同 %d 次" % n.layout_mismatch)
	var rtt: Array = n.get("rtt_ms", []).duplicate()
	if not rtt.is_empty():
		rtt.sort()
		var sum := 0
		for x: int in rtt:
			sum += x
		parts.append("回應 平均 %d / 最低 %d / 90%% %d / 最高 %d ms（%d 次）" % [
			roundi(float(sum) / rtt.size()), rtt[0], rtt[mini(rtt.size() - 1, floori(rtt.size() * 0.9))], rtt[-1], rtt.size()])
	if n.get("snapshot_gap_max_ms", 0) > 0:
		parts.append("快照最長間隔 %d ms" % n.snapshot_gap_max_ms)
	var gaps: Dictionary = n.get("input_gap_max_ms", {})
	if not gaps.is_empty():
		var g: Array[String] = []
		for peer: int in gaps:
			g.append("%d ms" % gaps[peer])
		parts.append("隊友輸入最長間隔 " + "、".join(PackedStringArray(g)))
	var text := " · ".join(PackedStringArray(parts))
	# 「卡住的時間點：4:28 1-3 快照斷 1383 ms、…」另起一行（NetClient.stalls）
	var stalls: Array = n.get("stalls", [])
	if not stalls.is_empty():
		var s: Array[String] = []
		for x: Dictionary in stalls:
			s.append("%s %s %s %d ms" % [UiKit.format_time(x.at), x.stage, x.what, x.ms])
		var count: int = n.get("stall_count", stalls.size())
		text += "\n  卡住的時間點：" + "、".join(PackedStringArray(s)) + ("…等共 %d 次" % count if count > stalls.size() else "")
	return text


# 武器那一行：掉落（分稀有度）、撿了幾把、背包第一次撿不下、現在的武器幾分換上
# 自己打出的一下：左右鍵依當時的武器分開記
func _add_dealt(world: World, credit: String, amount: float) -> void:
	if credit == "p" or credit == "s":
		var me: Player = world.entities.get(me_id) as Player if world != null else null
		if me != null and me.weapon.has("name"):
			credit += "|" + String(me.weapon.name)
	var s: Dictionary = by_credit.get(credit, {"damage": 0.0, "hits": 0})
	s.damage += amount
	s.hits += 1
	by_credit[credit] = s
	damage_dealt += amount


# 結算的「你造成的傷害」：依傷害高到低，前 DEALT_ROWS 項各一行，其餘併成「其他」
func dealt_lines() -> Array[String]:
	var lines: Array[String] = []
	if damage_dealt <= 0.0:
		return lines
	var keys := by_credit.keys().filter(func(k: String) -> bool: return k != "?")   # 認不出來源的併進「其他」
	keys.sort_custom(func(a: String, b: String) -> bool: return by_credit[a].damage > by_credit[b].damage)
	var rest: Dictionary = by_credit.get("?", {"damage": 0.0, "hits": 0}).duplicate()
	var parts: Array[String] = []
	for i in keys.size():
		var s: Dictionary = by_credit[keys[i]]
		if i < DEALT_ROWS or (keys.size() == DEALT_ROWS + 1 and rest.hits == 0):
			parts.append(_dealt_part(credit_name(keys[i]), s))
		else:
			rest.damage += s.damage
			rest.hits += s.hits
	if rest.hits > 0:
		parts.append(_dealt_part("其他", rest))
	for i in range(0, parts.size(), DEALT_PER_LINE):   # 一行兩項（結算畫面高度有限）
		var row := "　".join(PackedStringArray(parts.slice(i, i + DEALT_PER_LINE)))
		lines.append(("你造成的傷害 %s：" % UiKit.dmg_text(damage_dealt) if i == 0 else "　　") + row)
	return lines


func _dealt_part(label: String, s: Dictionary) -> String:
	return "%s %s（%d%%，%d 次）" % [label, UiKit.dmg_text(s.damage), roundi(100.0 * s.damage / damage_dealt), s.hits]


# 傷害來源代號（Combat.credit_scope 的說明）→ 結算畫面的名稱
static func credit_name(credit: String) -> String:
	var parts := credit.split("|")
	var weapon := "（%s）" % parts[1] if parts.size() > 1 else ""
	var key := parts[0]
	var id := StringName(key.get_slice(":", 1))
	match key.get_slice(":", 0):
		"p":
			return "左鍵" + weapon
		"s":
			return "右鍵" + weapon
		"k":
			return "技能 " + String(ItemDefs.ITEMS[id].name) if ItemDefs.ITEMS.has(id) else "技能"
		"i":
			return String(ItemDefs.ITEMS[id].name) if ItemDefs.ITEMS.has(id) else "道具"
		"b":
			return "羈絆 " + String(BondDefs.BONDS[id].name) if BondDefs.BONDS.has(id) else "羈絆"
		"add":
			return "附加%s傷害" % StatDefs.DAMAGE_TYPES[id].name if StatDefs.DAMAGE_TYPES.has(id) else "附加傷害"
		"burn":
			return "燃燒"
		"poison":
			return "中毒"
		"wisp":
			return "鬼火"
		"minion":
			return "骷髏僕從"
		"parry":
			return "招架"
	return "其他"


func weapon_text() -> String:
	var n := 0
	var parts: Array[String] = []
	for r: StringName in RARITY_ORDER:
		var c: int = weapon_drops.get(r, 0)
		n += c
		if c > 0:
			parts.append("%s %d" % [ItemDefs.RARITIES[r].name, c])
	var drops := "武器掉落 %d 把" % n + ("（%s）" % " · ".join(PackedStringArray(parts)) if not parts.is_empty() else "")
	var full := "背包沒滿過" if bag_full_at < 0.0 else "背包 %s 第一次撿不下" % UiKit.format_time(bag_full_at)
	return "%s · 撿了 %d 把 · %s · 現在的武器 %s 換上" % [drops, weapons_picked, full, UiKit.format_time(weapon_since)]


# 結算畫面的文字（中文自動折行會斷在詞中間，每項一行）
func summary_text() -> String:
	var lines: Array[String] = []
	var kill_kinds := kills.keys()
	kill_kinds.sort_custom(func(a: StringName, b: StringName) -> bool: return kills[a] > kills[b])
	var kill_parts := kill_kinds.map(func(k: StringName) -> String: return "%s %d" % [name_of(k), kills[k]])
	var head := "你的擊殺 %d" % total_kills()
	if kill_parts.is_empty():
		lines.append(head)
	for i in range(0, kill_parts.size(), KILLS_PER_LINE):   # 種類多時換行（結算畫面寬度有限）
		var row := " · ".join(PackedStringArray(kill_parts.slice(i, i + KILLS_PER_LINE)))
		lines.append((head + "：" if i == 0 else "　　") + row)
	lines.append(weapon_text())
	lines.append_array(dealt_lines())
	if hits_taken == 0:
		lines.append("沒有受到傷害")
	else:
		lines.append("受到傷害 %s（被打中 %d 次）" % [UiKit.dmg_text(damage_taken), hits_taken])
		lines.append("被看不見的攻擊打中 %d 次 / %s 傷害（%d%%）" % [unseen_hits, UiKit.dmg_text(unseen_damage), roundi(100.0 * unseen_damage / maxf(1.0, damage_taken))])
		var kinds := by_source.keys()
		kinds.sort_custom(func(a: StringName, b: StringName) -> bool: return by_source[a].damage > by_source[b].damage)
		for k: StringName in kinds:
			var s: Dictionary = by_source[k]
			lines.append("%s：%s 傷害 · %d 次" % [name_of(k), UiKit.dmg_text(s.damage), s.hits] + ("（看不見 %d 次）" % s.unseen if s.unseen > 0 else ""))
	if not downs.is_empty():
		var parts: Array[String] = []
		for d in downs.slice(0, MAX_DOWNS_SHOWN):
			parts.append(name_of(d.kind) + ("（看不見）" if d.unseen else ""))
		lines.append("倒下 %d 次：被 %s 打倒" % [downs.size(), "、".join(parts)] + ("…" if downs.size() > MAX_DOWNS_SHOWN else ""))
	return "\n".join(lines)
