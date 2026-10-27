# 啟動參數：自動驗證、截圖、量效能、連線測試與除錯用；正常遊玩全部是預設值（2026-10-25 從 main.gd 搬出來）
# 指令列（放在 -- 之後）：--seconds=S --screenshot=路徑 --auto-move=x,y（螢幕方向）--auto-move-seconds=S（幾秒後停止移動）
#   --auto-attack（一直按住左鍵）--auto-special（開場按一次右鍵，之後每 5.1 秒再按一次）--auto-interact（一直按住 F）--weapon=staff（開場武器）--class=arcanist（職業，ClassDefs）
#   --wave=N（直接從第 N 波開始）--player-hp=N（開場血量）--items=id,id（開場放進身上的道具，見 defs/item_defs.gd）--no-spawn（不生怪）
#   連線：--host（開房）--join=IP（加入）--room（改用房號：--join=房號）--net-port=N --net-autostart=N（房主：滿 N 人自動開始）
#   --net-latency=毫秒（模擬單程延遲）--net-loss=0.1（模擬掉包）--menu-flow（照玩家的操作順序從主選單走，v0.39.0）
#   效能量測：--horde=N（開場在玩家周圍生 N 隻醒著的小怪）--perf（關垂直同步，結束時印出 FPS 與各段耗時，見 PerfMeter）
#   --elites（畫面上方生 1 隻稀有、2 隻魔法骷髏，截圖確認外觀）
#   --weapon-test（武器測試場景：不生怪；畫面右邊貼身 1 隻、往右 5 / 7 / 9 一排、上方 4 一隻木樁，不動不打、血很多）
#   挖墳（D6）：--at-dig（開場站在挖墳點旁邊）--exit-open（開場出口就打開）--ghost（畫面上方生一隻冤魂）
#   --player-at=x,y（開場站在地圖座標 x, y，v0.32.0）
#   畫面設定（2026-10-27）：--shadows=0 / --lights=0 蓋掉設定頁的陰影 / 光源（不存檔），內顯量效能時當對照組
# 網頁版沒有指令列：網址的查詢參數轉成同樣的 --參數，只開放 WEB_URL_ARGS
class_name LaunchArgs
extends RefCounted

# 網頁版可以從網址帶的參數（url_query_args）；v0.36.3 加自動移動 / 攻擊，用來量「第一次出現」的卡頓
const WEB_URL_ARGS: Array[String] = ["seconds", "horde", "perf", "elites", "player-hp", "auto-move", "auto-move-seconds", "auto-attack", "weapon", "class", "difficulty", "no-spawn", "weapon-test", "items", "shadows", "lights", "host", "join", "room", "net-autostart"]   # host / join / room / net-autostart：網頁版多人自動測試、之後的邀請連結（2026-10-27 使用者同意開放；?host&room 開房印 net room=房號，?join=房號&room 加入）；shadows / lights：內顯量效能的對照組（2026-10-27）；weapon / class / no-spawn / weapon-test：網頁版逐把看武器（2026-10-27）；difficulty：選角畫面的難度；items：帶道具量效能（G7）

var run_seconds := 0.0           # > 0：跑這麼多秒後印出狀態並結束（自動驗證）
var screenshot_path := ""
var auto_move := Vector2.ZERO
var auto_move_seconds := 0.0
var auto_attack := false
var auto_special := false
var auto_interact := false
var start_weapon: StringName = &""
var start_class: StringName = &""
var difficulty: StringName = &""   # --difficulty=easy|normal|hard（選角畫面的難度，EventDefs.MODES）
var start_wave := 0
var start_hp := 0.0
var start_items: Array[StringName] = []
var no_spawn := false
var host := false
var join := ""
var menu_flow := false
var room := false                # --host / --join 改用房號連線（--join=房號；房主開房後印出 net room=房號）
var net_port: int = Config.NET.port
var autostart_players := 0
var net_latency_ms := -1         # -1 = 沒指定（用 Config.NET 的預設）
var net_loss := -1.0
var horde := 0
var elites := false
var weapon_test := false        # 武器測試場景：不生怪群與波次，玩家旁邊擺木樁（DebugTools.setup_run）
var at_dig := false
var player_at := Vector2.INF
var exit_open := false
var ghost := false
var perf := false
var video: Dictionary = {}       # --shadows= / --lights=：設定頁的鍵 → bool（沒指定就不放）


# 這次執行的參數：指令列，網頁版再加上網址的查詢參數
static func from_os() -> LaunchArgs:
	var args := OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		args.append_array(url_query_args(str(JavaScriptBridge.eval("window.location.search", true))))
	return parse(args)


static func parse(args: PackedStringArray) -> LaunchArgs:
	var a := LaunchArgs.new()
	for arg in args:
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--seconds="):
			a.run_seconds = value.to_float()
		elif arg.begins_with("--screenshot="):
			a.screenshot_path = value
		elif arg.begins_with("--auto-move="):
			a.auto_move = _vec2(value)
		elif arg.begins_with("--auto-move-seconds="):
			a.auto_move_seconds = value.to_float()
		elif arg == "--auto-attack":
			a.auto_attack = true
		elif arg == "--auto-special":
			a.auto_special = true
		elif arg == "--auto-interact":
			a.auto_interact = true
		elif arg.begins_with("--class="):
			a.start_class = StringName(value)
		elif arg.begins_with("--difficulty="):
			a.difficulty = StringName(value)
		elif arg.begins_with("--weapon="):
			a.start_weapon = StringName(value)
		elif arg.begins_with("--wave="):
			a.start_wave = value.to_int()
		elif arg.begins_with("--player-hp="):
			a.start_hp = value.to_float()
		elif arg == "--no-spawn":
			a.no_spawn = true
		elif arg.begins_with("--items="):
			for item in value.split(",", false):
				if ItemDefs.ITEMS.has(StringName(item)):
					a.start_items.append(StringName(item))
				else:
					push_warning("--items: 沒有這個道具 %s" % item)
		elif arg == "--host":
			a.host = true
		elif arg.begins_with("--join="):
			a.join = value
		elif arg == "--menu-flow":
			a.menu_flow = true
		elif arg == "--room":
			a.room = true
		elif arg.begins_with("--net-port="):
			a.net_port = value.to_int()
		elif arg.begins_with("--net-autostart="):
			a.autostart_players = value.to_int()
		elif arg.begins_with("--net-latency="):
			a.net_latency_ms = value.to_int()
		elif arg.begins_with("--net-loss="):
			a.net_loss = value.to_float()
		elif arg.begins_with("--horde="):
			a.horde = value.to_int()
		elif arg == "--elites":
			a.elites = true
		elif arg == "--weapon-test":
			a.weapon_test = true
			a.no_spawn = true
		elif arg == "--at-dig":
			a.at_dig = true
		elif arg.begins_with("--player-at="):
			a.player_at = _vec2(value)
		elif arg == "--exit-open":
			a.exit_open = true
		elif arg == "--ghost":
			a.ghost = true
		elif arg == "--perf":
			a.perf = true
		elif arg.begins_with("--shadows=") or arg.begins_with("--lights="):
			a.video[arg.get_slice("=", 0).trim_prefix("--")] = value != "0"
	return a


static func _vec2(value: String) -> Vector2:
	var xy := value.split(",")
	return Vector2(xy[0].to_float(), xy[1].to_float())


# 網址的查詢參數轉成 --參數（例如 ?horde=200&perf&seconds=20 → --horde=200 --perf --seconds=20）；
# 只開放 WEB_URL_ARGS（v0.34.3 起量效能用；2026-10-27 加上連線參數），朋友正常開網站（沒帶參數）不受影響
static func url_query_args(query: String) -> PackedStringArray:
	var out := PackedStringArray()
	for pair in query.trim_prefix("?").split("&", false):
		var key := pair.get_slice("=", 0).uri_decode()
		var value := pair.get_slice("=", 1).uri_decode() if pair.contains("=") else ""
		if key in WEB_URL_ARGS:
			out.append("--" + key + ("=" + value if value != "" else ""))   # ?perf= 與 ?perf 一樣
	return out


# 自動驗證（--seconds、--host、--join）：不經過主選單直接開局
func auto_start() -> bool:
	return run_seconds > 0.0 or host or join != ""
