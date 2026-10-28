# 遊玩紀錄：只記本機玩家這一局的擊殺、受到的傷害（依攻擊者種類分）、被看不見的攻擊打中幾次、每次倒下被誰打倒；
# 結算畫面顯示（ui/hud.gd）。只讀事件與模擬狀態，不修改模擬；連線時客戶端用房主送來的事件各記各的
# 「看不見」：被打中那一刻攻擊者在不在自己的視野裡（sim/vision.gd，牆擋視線也算看不見）；攻擊者已經消失時用攻擊的出發點判斷
# 回報：report_text() 是結算畫面「複製遊玩紀錄」的精簡文字（貼到聊天軟體），另含版本、平台、配裝、效能、連線數據
# 效能另記顯示卡、解析度與畫面設定（2026-10-27）：一局中切換過陰影 / 光源時依設定分開統計，內顯玩一局就有對照組
class_name RunLog
extends RefCounted

const MAX_DOWNS_SHOWN := 5
const HITCH := 0.05   # 一幀超過這麼多秒算卡頓
# Boss 名字同 HUD.BOSS_NAME；不直接引用 HUD：check.gd（-s 腳本）會用到本檔，引用 HUD 會連帶要求 autoload GameEvents 而編譯失敗
const NAMES := {
	&"grunt": "骷髏戰士", &"archer": "骷髏弓手", &"zombie": "腐屍", &"boss": "亡骸騎士", &"ghost": "冤魂", &"minion": "骷髏僕從",
	&"projectile": "投射物（射手已死）",
}

var me_id := 0          # 本機玩家的實體 id（HUD 每次有角色時更新；倒下 / 陣亡後角色還在，id 不變）
var kills := {}         # 種類 → 隻數（只算自己打死的）
var damage_taken := 0.0
var hits_taken := 0
var unseen_hits := 0
var unseen_damage := 0.0
var by_source := {}     # 種類 → {damage, hits, unseen}
var downs: Array[Dictionary] = []   # 每次倒下 / 死亡：{kind, unseen}
var result := ""       # 結算標題（HUD._set_game_over）
# 效能：遊戲進行中每幀的秒數（HUD 交給這裡）
var frames := 0
var frame_time := 0.0
var worst_frame := 0.0
var worst_at := 0.0     # 最慢那一幀在這局第幾秒
var hitches := 0
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
	downs.clear()
	result = ""
	frames = 0
	frame_time = 0.0
	worst_frame = 0.0
	worst_at = 0.0
	hitches = 0
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
	var v: Dictionary = by_video.get_or_add(video, {"frames": 0, "time": 0.0, "hitches": 0})
	v.frames += 1
	v.time += delta
	v.hitches += int(delta > HITCH)


func on_event(world: World, name: String, p: Dictionary) -> void:
	match name:
		"entity:damaged":
			if me_id == 0 or p.get("target_id", 0) != me_id:
				return
			var kind: StringName = p.get("source_kind", &"")
			var amount: float = p.get("amount", 0.0)
			var unseen := not _attacker_seen(world, p)
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
		"game:restart":
			reset()


func _attacker_seen(world: World, p: Dictionary) -> bool:
	var me: Player = world.entities.get(me_id) if world != null else null
	if me == null:
		return true
	# 不用 Vision.entity_visible：致命的那一下自己已經倒地，那個函式會把所有東西都當成看得到
	var src: Entity = world.entities.get(p.get("source_id", 0))
	if src != null and not src.is_removed and src != me:
		return Vision.point_visible(world, me, src.pos, src.radius)
	return Vision.point_visible(world, me, p.get("origin", me.pos))


static func name_of(kind: StringName) -> String:
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
	lines.append("Cubeborn v%s · %s · %s" % [GameVersion.VERSION, platform, Time.get_datetime_string_from_system(false, true)])
	var screen := DisplayServer.window_get_size()
	lines.append("顯示卡：%s · %d×%d · %s" % [RenderingServer.get_video_adapter_name(), screen.x, screen.y, video])
	var s := world.stats
	var mode_name: String = EventDefs.MODES[world.difficulty_mode].name
	var where := "第 %d 層 · 難度 %d（%s）" % [world.floor_num, floori(world.difficulty()), mode_name] if DigEvent.enabled(world) else "第 %d 波" % s.wave
	var boss: Enemy = world.entities.get(world.boss_id) as Enemy
	if boss != null and not boss.is_dead:
		where += " · %s剩 %d%% 血" % [name_of(boss.kind), roundi(100.0 * boss.hp / boss.max_hp)]
	lines.append("結果：%s · %s · %s" % [result if result != "" else "進行中", where, UiKit.format_time(s.time)])
	var me: Player = world.entities.get(me_id) as Player
	if me != null:
		var inst := me.active_weapon()
		var items: Array[String] = []
		for it: Dictionary in me.items:
			items.append(ItemDefs.ITEMS[it.id].name)
		lines.append("武器：%s；道具：%s；靈魂 %d；本局金幣 %d" % [WeaponDropDefs.display_name(inst) if not inst.is_empty() else me.weapon.name,
			"、".join(PackedStringArray(items)) if not items.is_empty() else "無", world.souls, world.run_coins])
	lines.append_array(summary_text().split("
"))
	if frames > 0:
		var at := UiKit.format_time(worst_at) + ("，" + worst_context if worst_context != "" else "")
		lines.append("效能：平均 %d FPS · 最慢一幀 %d ms（%s）· 卡頓（超過 %d ms）%d 次" % [
			roundi(frames / maxf(frame_time, 1e-6)), roundi(worst_frame * 1000.0), at, roundi(HITCH * 1000.0), hitches])
		if by_video.size() > 1:   # 一局中切換過畫面設定：各設定分開列，就是對照組
			for key: String in by_video:
				var v: Dictionary = by_video[key]
				lines.append("  %s：平均 %d FPS · 卡頓 %d 次（%s）" % [key, roundi(v.frames / maxf(v.time, 1e-6)), v.hitches, UiKit.format_time(v.time)])
	var n: Dictionary = net_info.call() if net_info.is_valid() else {}
	if not n.is_empty():   # 單機時 main.gd 回傳空的
		lines.append(net_text(n))
	return "
".join(lines)


static func net_text(n: Dictionary) -> String:
	var parts: Array[String] = ["連線：%s · %d 人" % [n.role, n.players]]
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
	return " · ".join(PackedStringArray(parts))


# 結算畫面的文字（中文自動折行會斷在詞中間，每項一行）
func summary_text() -> String:
	var lines: Array[String] = []
	var kill_kinds := kills.keys()
	kill_kinds.sort_custom(func(a: StringName, b: StringName) -> bool: return kills[a] > kills[b])
	var kill_parts := kill_kinds.map(func(k: StringName) -> String: return "%s %d" % [name_of(k), kills[k]])
	lines.append("你的擊殺 %d" % total_kills() + ("：" + " · ".join(PackedStringArray(kill_parts)) if not kill_parts.is_empty() else ""))
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
