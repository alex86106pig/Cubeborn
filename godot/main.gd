# 組合根：建立 World、輸入、畫面、HUD、音效與連線；主選單、固定步長主迴圈、通關慢動作、暫停 / 選單、靜音、重新開始、離開遊戲
# 三種模式（15.18）：單機（= 沒有連線的房主）、房主（跑唯一的 World、收輸入、送快照與事件）、客戶端（鏡像 World + 本機預測）
# 指令列參數（放在 -- 之後）：--seconds=S --screenshot=路徑 --auto-move=x,y（螢幕方向）--auto-move-seconds=S（幾秒後停止移動）
#   --auto-attack（一直按住左鍵）--auto-special（開場按一次右鍵，之後每 5.1 秒再按一次）--auto-interact（一直按住 F）--weapon=staff（開場武器）
#   --wave=N（直接從第 N 波開始）--player-hp=N（開場血量）--items=id,id（開場放進身上的道具，見 defs/item_defs.gd）--no-spawn（不生怪）
#   連線：--host（開房）--join=IP（加入）--room（改用房號：--join=房號）--net-port=N --net-autostart=N（房主：滿 N 人自動開始）
#   --net-latency=毫秒（模擬單程延遲）--net-loss=0.1（模擬掉包）
#   效能量測：--horde=N（開場在玩家周圍生 N 隻醒著的小怪）--perf（關垂直同步，結束時印出 FPS 與各段耗時）
#   --elites（畫面上方生 1 隻稀有、2 隻魔法骷髏，截圖確認外觀）
#   挖墳（D6）：--at-dig（開場站在挖墳點旁邊）--exit-open（開場出口就打開）--ghost（畫面上方生一隻冤魂）
#   --player-at=x,y（開場站在地圖座標 x, y，v0.32.0）
extends Node3D

enum Mode { SINGLE, HOST, CLIENT }

const HUD_SCENE := preload("res://ui/hud.tscn")
const PERF_WARMUP := 2.0   # --perf：開場幾秒不記錄（建模與第一次編譯著色器）
const HITCH_MS := 33.0     # --perf：超過這麼久的幀算卡頓（30 FPS 以下）
# 網頁版可以從網址帶的參數（url_query_args）；v0.36.3 加自動移動 / 攻擊，用來量「第一次出現」的卡頓
const WEB_URL_ARGS: Array[String] = ["seconds", "horde", "perf", "elites", "player-hp", "auto-move", "auto-move-seconds", "auto-attack"]

var mode := Mode.SINGLE
var world := World.new()      # 單機 / 房主：權威的 World；客戶端：net_client.world（快照的鏡像）
var is_paused := false        # 單機暫停（連線時 Esc 只開選單，遊戲不停）
var is_menu_open := false     # 連線時的選單
var is_in_lobby := false      # 開房 / 加入後、開始遊戲前
var is_at_title := false      # 停在主選單（v0.39.0）：遊戲不跑、不收遊戲輸入

var camera_rig := CameraRig.new()
var world_view := WorldView.new()
var arena_view := ArenaView.new()
var input_collector := InputCollector.new()
var sound := Sound.new()
var net := NetSession.new()
var net_host: NetHost
var net_client: NetClient
var hud: HUD

var _local_peer := World.HOST_PEER_ID
var _net_message := ""
var _sim_accumulator := 0.0
var _stepped_this_tick := false
var _run_seconds := 0.0
var _screenshot_path := ""
var _elapsed := 0.0
var _lobby_elapsed := 0.0
var _auto_move_seconds := 0.0
var _start_weapon: StringName = &""
var _start_wave := 0
var _start_hp := 0.0
var _start_items: Array[StringName] = []
var _no_spawn := false
var _debug_item_index := 0
var _arg_host := false
var _arg_join := ""
var _menu_flow := false
var _arg_room := false   # --room：--host / --join 改用房號連線（--join=房號；房主開房後印出 net room=房號）
var _start_pos := Vector2.INF
var _prev_first: Array[String] = []   # --perf：前一幀第一次畫出來的東西
var _hitches: Array[float] = []       # --perf：超過 HITCH_MS 的幀（毫秒）
var _warming := false                 # 開場預熱中（蓋著「準備中」）
var _warm_ms := 0.0                   # --perf：預熱那幾幀合計多久
var _net_port: int = Config.NET.port
var _autostart_players := 0
# 效能量測（D5）：--horde=N 開場在玩家周圍生 N 隻醒著的小怪；--perf 關垂直同步、2 秒後開始記錄幀時間，結束時印出
var _horde := 0
var _elites := false   # --elites：畫面上方生 1 隻稀有、2 隻魔法骷髏（截圖確認外觀用）
var _at_dig := false     # --at-dig：開場站在挖墳點旁邊（D6，配合 --auto-interact 挖墳）
var _player_at := Vector2.INF   # --player-at=x,y：開場站在地圖座標 (x, y)（v0.32.0 牆後剪影截圖）
var _exit_open := false  # --exit-open：開場事件就開始、出口已打開（D6 截圖）
var _ghost := false      # --ghost：畫面上方生一隻冤魂（D6 截圖，不對應任何玩家）
var _perf := false
var _perf_frames := PackedFloat32Array()
var _perf_step_usec := 0
var _perf_steps := 0
var _perf_sync_usec := 0
var _perf_syncs := 0


func _ready() -> void:
	# RPC 的節點路徑以 main 為根：直接執行與在 tests/capture.tscn 裡執行的兩個程序也能互連
	get_tree().set_multiplayer(SceneMultiplayer.new(), get_path())
	InputCollector.register_actions()
	_parse_args()
	add_child(camera_rig)
	add_child(world_view)
	add_child(arena_view)
	arena_view.build(world.half_extents, world.terrain)
	input_collector.camera_rig = camera_rig
	add_child(input_collector)
	hud = HUD_SCENE.instantiate()
	hud.setup(world, camera_rig.camera)
	hud.health_bars.hidden_ids = world_view.hidden_ids   # 同一個字典，WorldView 每個 tick 原地更新
	hud.quit_requested.connect(get_tree().quit)
	hud.title_requested.connect(return_to_title)
	hud.main_menu.single_pressed.connect(start_single)
	hud.main_menu.back_pressed.connect(_on_title_back)
	hud.inventory_panel.op_requested.connect(input_collector.queue_inventory_op)
	if _run_seconds > 0.0:
		hud.hints.save_path = ""   # 自動驗證（截圖、量效能）不記「看過的提示」，免得使用者自己玩時提示不跳
	add_child(hud)
	sound.setup(world)
	add_child(sound)
	net.name = &"Net"
	add_child(net)
	_connect_net()
	_emit_muted()
	GameEvents.event_emitted.connect(_on_event)
	restart()
	# 開場預熱（v0.37.0）：每種模型、剪影、特效、會出現的中文字先在鏡頭前畫幾幀，避免第一次出現時卡一下
	world_view.warm_up(_player_view_position(1.0))
	hud.set_loading(true)
	_warming = true
	# 自動驗證（--seconds、--host、--join）直接開局；--menu-flow 照玩家的操作順序從主選單走（v0.39.0）
	var auto_start := _run_seconds > 0.0 or _arg_host or _arg_join != ""
	if _menu_flow or not auto_start:
		show_title(&"multi" if _arg_host or _arg_join != "" else &"home")
		if _menu_flow and not (_arg_host or _arg_join != ""):
			start_single()   # --menu-flow 單人：在主選單按「單人遊戲」
	if _arg_room:
		hud.net_panel.set_method(&"room")
	if _arg_host:
		start_hosting()
	elif _arg_join != "":
		start_joining(_arg_join)


func _exit_tree() -> void:
	world.clear()   # 切斷實體與 World 的循環參照（連線在 NetSession 離開場景樹時關閉）
	if net_client != null:
		net_client.world.clear()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		args.append_array(url_query_args(str(JavaScriptBridge.eval("window.location.search", true))))
	for arg in args:
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--seconds="):
			_run_seconds = value.to_float()
		elif arg.begins_with("--screenshot="):
			_screenshot_path = value
		elif arg.begins_with("--auto-move="):
			var xy := value.split(",")
			input_collector.auto_move = Vector2(xy[0].to_float(), xy[1].to_float())
		elif arg.begins_with("--auto-move-seconds="):
			_auto_move_seconds = value.to_float()
		elif arg == "--auto-attack":
			input_collector.auto_attack = true
		elif arg == "--auto-special":
			input_collector.auto_special = true
		elif arg == "--auto-interact":
			input_collector.auto_interact = true
		elif arg.begins_with("--weapon="):
			_start_weapon = StringName(value)
		elif arg.begins_with("--wave="):
			_start_wave = value.to_int()
		elif arg.begins_with("--player-hp="):
			_start_hp = value.to_float()
		elif arg == "--no-spawn":
			_no_spawn = true
		elif arg.begins_with("--items="):
			for item in value.split(",", false):
				if ItemDefs.ITEMS.has(StringName(item)):
					_start_items.append(StringName(item))
				else:
					push_warning("--items: 沒有這個道具 %s" % item)
		elif arg == "--host":
			_arg_host = true
		elif arg.begins_with("--join="):
			_arg_join = value
		elif arg == "--menu-flow":
			_menu_flow = true
		elif arg == "--room":
			_arg_room = true
		elif arg.begins_with("--net-port="):
			_net_port = value.to_int()
		elif arg.begins_with("--net-autostart="):
			_autostart_players = value.to_int()
		elif arg.begins_with("--net-latency="):
			net.latency_ms = value.to_int()
		elif arg.begins_with("--net-loss="):
			net.loss = value.to_float()
		elif arg.begins_with("--horde="):
			_horde = value.to_int()
		elif arg == "--elites":
			_elites = true
		elif arg == "--at-dig":
			_at_dig = true
		elif arg.begins_with("--player-at="):
			var xy := value.split(",")
			_player_at = Vector2(xy[0].to_float(), xy[1].to_float())
		elif arg == "--exit-open":
			_exit_open = true
		elif arg == "--ghost":
			_ghost = true
		elif arg == "--perf":
			_perf = true
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0


# 網頁版沒有指令列：網址的查詢參數轉成同樣的 --參數（例如 ?horde=200&perf&seconds=20 → --horde=200 --perf --seconds=20）；
# 只開放量效能用的 WEB_URL_ARGS（v0.34.3，量網頁版當房主跑不跑得動，見想法清單 #12），朋友正常開網站不受影響
static func url_query_args(query: String) -> PackedStringArray:
	var out := PackedStringArray()
	for pair in query.trim_prefix("?").split("&", false):
		var key := pair.get_slice("=", 0).uri_decode()
		var value := pair.get_slice("=", 1).uri_decode() if pair.contains("=") else ""
		if key in WEB_URL_ARGS:
			out.append("--" + key + ("=" + value if value != "" else ""))   # ?perf= 與 ?perf 一樣
	return out


func local_player() -> Player:
	return world.players.get(_local_peer)


# 單機與房主：重新開始一局（房主帶著大廳裡所有人；客戶端看到 run_id 變了就清掉鏡像）
func restart() -> void:
	if mode == Mode.CLIENT:
		return
	var peers: Array[int] = [World.HOST_PEER_ID]
	if mode == Mode.HOST:
		peers.assign(net.lobby_peers)
		peers.sort()
	world.spawn_packs = not _no_spawn
	world.reset(randi(), peers)
	world.spawner.finished = _no_spawn
	var me := local_player()
	if _start_weapon != &"":
		me.equip_weapon(_start_weapon)
	if _start_wave > 1:
		world.spawner.wave = _start_wave - 1
	for item in _start_items:
		me.add_item(item)
	if _start_hp > 0.0:
		me.hp = _start_hp
	_spawn_horde(me)
	_sim_accumulator = 0.0
	input_collector.consume_latched()
	GameEvents.emit_all(world.events)
	if mode == Mode.HOST:
		net.send_events(world.run_id, world.tick, world.events.duplicate())
	set_paused(false)
	camera_rig.follow(_player_view_position(1.0), 0.0, true)


# 單機才會真的暫停；只在遊戲進行中可以暫停（死亡、通關畫面已經停在結算）
func set_paused(paused: bool) -> void:
	var player := local_player()
	if paused and (is_at_title or mode != Mode.SINGLE or world.is_over or player == null or player.is_dead):
		return
	if is_paused == paused:
		return
	is_paused = paused
	world_view.effects.paused = paused
	GameEvents.event_emitted.emit("game:paused", {"name": "game:paused", "paused": paused})


# ───────── 主選單 ─────────

func show_title(page: StringName = &"home") -> void:
	set_paused(false)
	is_at_title = true
	is_menu_open = false
	hud.show_menu(false)
	hud.show_title(true, page)
	_refresh_net_panel()


func _leave_title() -> void:
	is_at_title = false
	hud.show_title(false)


# 主選單按「單人遊戲」：開一局新的
func start_single() -> void:
	_net_message = ""
	restart()
	_leave_title()


# 多人頁按「返回」：還在大廳就先離開連線
func _on_title_back() -> void:
	if mode != Mode.SINGLE:
		leave_net("")
	_net_message = ""
	show_title(&"method" if NetSession.ip_supported() else &"home")   # 桌面版回到選連線方式


# 暫停 / 選單按「回主選單」：連線中先離開連線，單機直接結束這局
func return_to_title() -> void:
	if mode != Mode.SINGLE:
		leave_net("")
	else:
		restart()
	_net_message = ""
	show_title(&"home")


# ───────── 連線 ─────────

func _connect_net() -> void:
	net.lobby_changed.connect(_on_lobby_changed)
	net.game_started.connect(_on_game_started)
	net.inputs_received.connect(func(peer_id: int, arrays: Array) -> void:
		if net_host != null:
			net_host.receive_inputs(peer_id, arrays))
	net.snapshot_received.connect(func(snap: Array) -> void:
		if net_client != null:
			net_client.receive_snapshot(snap))
	net.events_received.connect(func(run: int, tick: int, events: Array) -> void:
		if net_client != null:
			net_client.receive_events(run, tick, events))
	net.peer_left.connect(_on_peer_left)
	net.connection_failed.connect(func() -> void:
		leave_net(net.last_error if net.last_error != "" else ("連不上房主" if hud.net_panel.method == &"room" else "連不上房主（IP 或防火牆？）")))
	net.disconnected.connect(func() -> void: leave_net("和房主斷線了"))
	hud.net_panel.host_pressed.connect(start_hosting)
	hud.net_panel.join_pressed.connect(start_joining)
	hud.net_panel.start_pressed.connect(start_net_game)
	hud.net_panel.leave_pressed.connect(leave_net.bind(""))


# 網頁版用房號（WebRTC + 配對伺服器），桌面版用 IP（ENet）
func start_hosting() -> void:
	set_paused(false)   # 從單機的暫停選單開房：連線時遊戲不會暫停（v0.36.2 修正）
	var err := net.host_room() if hud.net_panel.method == &"room" else net.host(_net_port)
	if err != OK:
		_net_message = "開房失敗（連接埠 %d 被占用？錯誤 %d）" % [_net_port, err]
		_refresh_net_panel()
		return
	mode = Mode.HOST
	net_host = NetHost.new(world)
	is_in_lobby = true
	_open_menu(true)
	_refresh_net_panel()


func start_joining(address: String) -> void:
	if address == "":
		return
	# 從單機的暫停選單加入：先解除暫停，不然連線後一直停在暫停（不收輸入、特效凍住；v0.36.2 修正）
	set_paused(false)
	var err := net.join_room(address) if hud.net_panel.method == &"room" else net.join(address, _net_port)
	if err != OK:
		_net_message = "加入失敗（錯誤 %d）" % err
		_refresh_net_panel()
		return
	mode = Mode.CLIENT
	is_in_lobby = true
	_open_menu(true)
	_refresh_net_panel()


# 房主按下開始：大廳裡的人一起開局，之後不再接受加入
func start_net_game() -> void:
	if mode != Mode.HOST or not is_in_lobby:
		return
	net.start_game()
	is_in_lobby = false
	_leave_title()
	_open_menu(false)
	restart()
	_refresh_net_panel()


func _on_game_started(_peers: Array) -> void:
	set_paused(false)
	_local_peer = net.local_peer_id()
	net_client = NetClient.new(_local_peer)
	_use_world(net_client.world)
	is_in_lobby = false
	_elapsed = 0.0
	_leave_title()
	_open_menu(false)
	_refresh_net_panel()


func _on_lobby_changed(peers: Array) -> void:
	_refresh_net_panel()
	if _run_seconds > 0.0 and mode == Mode.HOST and peers.size() == 1 and net.room_code != "":
		print("net room=%s" % net.room_code)   # --room 自動驗證：另一個程序用這個房號加入
	if mode == Mode.HOST and is_in_lobby and _autostart_players > 0 and peers.size() >= _autostart_players:
		start_net_game()


# 房主：有人斷線就把他的角色移除
func _on_peer_left(peer_id: int) -> void:
	if net_host != null:
		net_host.remove_peer(peer_id)
	var p: Player = world.players.get(peer_id)
	if p != null:
		p.remove()


# 離開連線（自己按的、連不上、房主斷線）：回到主選單的多人頁，顯示原因
func leave_net(message: String) -> void:
	net.close()
	mode = Mode.SINGLE
	net_host = null
	_local_peer = World.HOST_PEER_ID
	if net_client != null:
		net_client.world.clear()
		net_client = null
		_use_world(World.new())
	is_in_lobby = false
	_net_message = message
	restart()
	show_title(&"multi")


func _use_world(w: World) -> void:
	if w != world:
		world.clear()
	world = w
	world_view.clear_views()
	hud.setup(world, camera_rig.camera)
	hud.set_local_peer(_local_peer)
	world_view.local_peer = _local_peer
	sound.setup(world)
	sound.local_peer = _local_peer   # 音效距離衰減以本機角色為準（v0.44.0）


func _open_menu(open: bool) -> void:
	if is_at_title:
		is_menu_open = false   # 從主選單開房 / 加入：大廳就顯示在主選單的多人頁
		return
	if mode == Mode.SINGLE:
		is_menu_open = false
		set_paused(open)
		return
	is_menu_open = open or is_in_lobby
	hud.show_menu(is_menu_open, "連線大廳" if is_in_lobby else "選單", "" if is_in_lobby else "按 Esc 關閉（連線中遊戲不會暫停）")


func _refresh_net_panel() -> void:
	var state := &"single"
	if mode == Mode.HOST:
		if not net.is_active():
			state = &"connecting"   # 網頁版：還在向配對伺服器註冊房號
		else:
			state = &"lobby_host" if is_in_lobby else &"playing"
	elif mode == Mode.CLIENT:
		# 網頁版的 WebRTC 在連上前就有自己的 peer id，所以也看「收到房主的大廳名單了沒」
		if not net.is_active() or net.local_peer_id() == World.HOST_PEER_ID or net.lobby_peers.is_empty():
			state = &"connecting"
		else:
			state = &"lobby_client" if is_in_lobby else &"playing"
	var peers: Array = net.lobby_peers.duplicate()
	peers.sort()
	hud.net_panel.room_code = net.room_code
	hud.net_panel.show_state(state, peers, net.local_peer_id(), _net_message)


# ───────── 主迴圈 ─────────

func _physics_process(_delta: float) -> void:
	_stepped_this_tick = false
	input_collector.enabled = not (is_at_title or is_menu_open or is_paused or hud.net_panel.is_typing())
	if mode == Mode.CLIENT:
		_client_physics()
	else:
		_authority_physics()


func _authority_physics() -> void:
	if is_paused or is_in_lobby or is_at_title:
		input_collector.consume_latched()   # 暫停中的點擊與按鍵不留到繼續之後
		return
	# 通關慢動作：真實時間照走，邏輯時間放慢到 5%，每步仍是 FIXED_DT（v0.18.3 起只剩打倒 Boss 時用；一般命中改成畫面層的命中定格）
	_sim_accumulator += Config.FIXED_DT * world.consume_hit_stop(Config.FIXED_DT)
	while _sim_accumulator >= Config.FIXED_DT - 1e-9:
		_sim_accumulator -= Config.FIXED_DT
		var cmds := net_host.take_cmds() if net_host != null else {}
		cmds[World.HOST_PEER_ID] = input_collector.build_cmd(world.tick + 1)
		var t0 := Time.get_ticks_usec()
		world.step(cmds, Config.FIXED_DT)
		if _perf and _elapsed >= PERF_WARMUP:
			_perf_step_usec += Time.get_ticks_usec() - t0
			_perf_steps += 1
		input_collector.consume_latched()
		GameEvents.emit_all(world.events)
		if mode == Mode.HOST:
			_broadcast_step()
		_stepped_this_tick = true


# 房主：事件每步送（reliable）、快照每 snapshot_interval 步送（unreliable）
func _broadcast_step() -> void:
	if not world.events.is_empty():
		net.send_events(world.run_id, world.tick, world.events.duplicate())
	if world.tick % Config.NET.snapshot_interval == 0:
		var snaps := net_host.snapshots()
		for peer_id: int in snaps:
			net.send_snapshot(peer_id, snaps[peer_id])


func _client_physics() -> void:
	if net_client == null:
		input_collector.consume_latched()
		return
	var events := net_client.step(input_collector.build_cmd(0), Config.FIXED_DT)
	input_collector.consume_latched()
	net.send_inputs(net_client.outgoing_inputs())
	GameEvents.emit_all(events)
	_stepped_this_tick = true


func _process(delta: float) -> void:
	if _perf:
		_log_hitch(delta)
	var alpha := Engine.get_physics_interpolation_fraction() if _stepped_this_tick else 1.0
	var t0 := Time.get_ticks_usec()
	world_view.sync(world, alpha, delta)
	if _perf:
		# 這一幀第一次畫的東西，成本（編譯著色器、產生字形）會算在下一幀的 delta 裡
		_prev_first = world_view.first_seen + world_view.effects.first_seen
	world_view.first_seen.clear()
	world_view.effects.first_seen.clear()
	if _warming and not world_view.is_warming_up():
		_warming = false
		hud.set_loading(false)
	if _perf and _elapsed >= PERF_WARMUP:
		_perf_sync_usec += Time.get_ticks_usec() - t0
		_perf_syncs += 1
		_perf_frames.append(delta)
	world_view.profile = _perf and _elapsed >= PERF_WARMUP
	camera_rig.follow(_player_view_position(alpha), delta)
	_check_auto_quit(delta)


# --perf 的卡頓紀錄（v0.36.3）：超過 HITCH_MS 的幀印出來，附上前一幀第一次畫出來的東西（模型種類、特效）
func _log_hitch(delta: float) -> void:
	var ms := delta * 1000.0
	if _warming:
		_warm_ms += ms   # 預熱那幾幀本來就會慢（蓋著「準備中」），另外記、不算卡頓
		return
	if ms < HITCH_MS or _elapsed <= 0.0:
		return
	_hitches.append(ms)
	print("perf hitch t=%.2f ms=%.1f first=%s" % [_elapsed, ms, ", ".join(_prev_first) if not _prev_first.is_empty() else "-"])


func _player_view_position(alpha: float) -> Vector3:
	var player := local_player()
	if player == null:
		return Vector3.ZERO
	var p := player.prev_pos.lerp(player.pos, alpha)
	return Vector3(p.x, 0.0, p.y)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if is_at_title and not event.is_action_pressed(&"mute"):
		return   # 主選單只用滑鼠點按鈕；M 靜音照常
	if event.is_action_pressed(&"pause"):
		if mode == Mode.SINGLE:
			set_paused(not is_paused)
		elif not is_in_lobby:
			_open_menu(not is_menu_open)
	elif event.is_action_pressed(&"restart"):
		var player := local_player()
		if mode != Mode.CLIENT and (world.is_over or world.is_defeated or player == null or player.is_dead):
			restart()
	elif event.is_action_pressed(&"mute"):
		sound.toggle_mute()
		_emit_muted()
	elif event.is_action_pressed(&"debug_hitbox"):
		world_view.show_hitboxes = not world_view.show_hitboxes
	elif event.is_action_pressed(&"stats_panel"):
		# Tab 同時開關背包與屬性面板（v0.27.0 使用者決定，取代 I）；開著時不暫停、角色照常移動，滑鼠只給背包用
		hud.toggle_stats_panel()
		hud.inventory_panel.visible = hud.is_stats_panel_open()
		input_collector.mouse_captured = hud.inventory_panel.visible
	elif mode != Mode.SINGLE:
		return   # 以下除錯鍵直接改模擬狀態、不經過 InputCmd，單機才有
	elif event.is_action_pressed(&"debug_speed"):
		toggle_debug_speed()
	elif event.is_action_pressed(&"debug_item"):
		debug_add_next_item()
	elif event.is_action_pressed(&"debug_clear_items"):
		var player := local_player()
		if player != null:
			player.clear_items()


# 效能量測用（--horde=N）：玩家周圍 4~16 隨機生 N 隻（骷髏戰士 80%、弓手 20%），照常爬出後追玩家
func _spawn_horde(me: Player) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5   # 固定位置，每次量測可以比較
	if _player_at != Vector2.INF:   # 先移動玩家，--horde 才會生在新位置周圍
		me.pos = MapDefs.to_world(world.map, _player_at)
		me.prev_pos = me.pos
	for i in _horde:
		var type := &"archer" if rng.randf() < 0.2 else &"grunt"
		var a := rng.randf() * TAU
		var at := world.nav.nearest_walkable(me.pos + Vector2(sin(a), cos(a)) * rng.randf_range(4.0, 16.0))
		world.spawner.spawn_at(world, type, at)
	if _at_dig:
		me.pos = world.event.point + (world.spawn_point - world.event.point).normalized() * 1.5
		me.prev_pos = me.pos
	if _exit_open:
		world.event._start(world)
		world.event.state = DigEvent.OPEN
		world.event.progress = 1.0
	if _ghost:
		var g := world.spawner.spawn_at(world, &"ghost", world.nav.nearest_walkable(me.pos + Vector2(-1.0, -1.0).normalized() * 5.0))
		g.ghost_of = -1
	if _elites:
		var up := Vector2(-1.0, -1.0).normalized()   # 等距相機的畫面上方
		var side := Vector2(1.0, -1.0).normalized()
		var list := [[MonsterRarityDefs.RARE, up * 5.0], [MonsterRarityDefs.MAGIC, up * 4.0 + side * 3.0], [MonsterRarityDefs.MAGIC, up * 4.0 - side * 3.0]]
		for r: Array in list:
			var e := world.spawner.spawn_at(world, &"grunt", world.nav.nearest_walkable(me.pos + r[1]))
			Spawner.roll_rarity(world, e, r[0])


# 除錯用（非正式系統，單機才有）：依道具清單順序，每按一次 F4 放一個道具進背包（循環；放不下就提示背包滿了）
func debug_add_next_item() -> void:
	var player := local_player()
	if player == null or player.is_dead:
		return
	var ids := ItemDefs.item_ids()
	var before := world.events.size()   # 上一步的事件已經送過，只送這次新增的
	player.add_item(ids[_debug_item_index % ids.size()])
	_debug_item_index += 1
	GameEvents.emit_all(world.events.slice(before))


# 除錯用（非正式系統，單機才有）：切換玩家「移速 +50%」，驗證屬性系統用
func toggle_debug_speed() -> void:
	var player := local_player()
	if player == null:
		return
	if player.stats.has_source(&"debug"):
		player.remove_stat_source(&"debug")
	else:
		player.set_stat_source(&"debug", [[&"move_speed", Stats.PCT, Config.DEBUG.speed_bonus]])


# 靜音狀態給 HUD 顯示（開場時也送一次：上次關遊戲前可能是靜音）
func _emit_muted() -> void:
	GameEvents.event_emitted.emit("audio:muted", {"name": "audio:muted", "muted": sound.is_muted})


func _on_event(name: String, payload: Dictionary) -> void:
	if name == "camera:shake":
		# 玩家被打的震動只給那位玩家（player_id）；Boss 招式、通關等照常
		var me := local_player()
		if not payload.has("player_id") or (me != null and payload.player_id == me.id):
			camera_rig.shake(payload.amount, payload.duration)
	world_view.on_event(name, payload)


# --perf：平均 FPS、最慢 1% 的幀、每步邏輯與每幀畫面同步的平均耗時、活著的敵人與畫出來的數量
func _print_perf() -> void:
	var frames := _perf_frames.duplicate()
	frames.sort()
	var n := frames.size()
	if n == 0:
		return
	var total := 0.0
	for f in frames:
		total += f
	var alive := 0
	for e in world.enemies:
		alive += 0 if e.is_dead else 1
	print("perf frames=%d avg_fps=%.1f p99_ms=%.2f worst_ms=%.2f logic_ms_per_step=%.3f view_sync_ms=%.3f enemies=%d visible=%d draw_calls=%d" % [
		n, n / total, frames[mini(n - 1, int(n * 0.99))] * 1000.0, frames[n - 1] * 1000.0,
		_perf_step_usec / 1000.0 / maxi(1, _perf_steps), _perf_sync_usec / 1000.0 / maxi(1, _perf_syncs),
		alive, world.enemies.size() - world_view.hidden_enemy_count(world),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	var over50 := _hitches.filter(func(ms: float) -> bool: return ms >= 50.0).size()
	var over100 := _hitches.filter(func(ms: float) -> bool: return ms >= 100.0).size()
	print("perf hitches over33=%d over50=%d over100=%d worst_hitch_ms=%.1f warmup_ms=%.1f" % [_hitches.size(), over50, over100, _hitches.max() if not _hitches.is_empty() else 0.0, _warm_ms])
	var parts := ""
	for k: StringName in world_view.profile_usec:
		parts += " %s=%.3f" % [k, world_view.profile_usec[k] / 1000.0 / maxi(1, _perf_syncs)]
	print("perf view_sync_parts_ms:" + parts)


# 切到其他視窗時自動暫停（單機才會），避免回來時已經被打死
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _run_seconds <= 0.0:
		set_paused(true)


func _check_auto_quit(delta: float) -> void:
	if _run_seconds <= 0.0:
		return
	if is_in_lobby or (mode == Mode.CLIENT and net_client == null):
		# 連線時從開始遊戲才計時；一直沒開始（大廳截圖）也在 --seconds 後結束
		_lobby_elapsed += delta
		if _lobby_elapsed < _run_seconds:
			return
	else:
		_elapsed += delta
		var me := local_player()
		if _start_pos == Vector2.INF and me != null:
			_start_pos = me.pos   # 開始遊戲後自己角色的第一個位置（結束時印出移動了多遠）
	if _auto_move_seconds > 0.0 and _elapsed >= _auto_move_seconds:
		input_collector.auto_move = Vector2.ZERO
	if _elapsed < _run_seconds and _lobby_elapsed < _run_seconds:
		return
	_run_seconds = 0.0
	var player := local_player()
	if player != null:
		print("tick=%d player_pos=(%.2f, %.2f) hp=%.0f weapon=%s action=%s wave=%d enemies=%d projectiles=%d kills=%d" % [
			world.tick, player.pos.x, player.pos.y, player.hp, player.weapon_id, player.action.current_name,
			world.stats.wave, world.enemies.size(), world.projectiles.size(), world.stats.kills])
	# 連線檢查用：每位玩家（依 peer id）的位置，房主與客戶端各印一行比對
	var line := "players mode=%d" % mode
	var peers: Array = world.players.keys()
	peers.sort()
	for peer_id: int in peers:
		var p: Player = world.players[peer_id]
		line += " %d=(%.3f,%.3f)" % [peer_id, p.pos.x, p.pos.y]
	print(line)
	var me := local_player()
	var moved := me.pos.distance_to(_start_pos) if me != null and _start_pos != Vector2.INF else -1.0
	print("state title=%d paused=%d input=%d effects_paused=%d self_moved=%.2f" % [int(is_at_title), int(is_paused), int(input_collector.enabled), int(world_view.effects.paused), moved])
	if net_client != null:
		print("net corrections=%d max_error=%.4f" % [net_client.corrections, net_client.max_error])
	var boss: Enemy = world.entities.get(world.boss_id)
	if boss != null:
		print("boss state=%s hp=%.0f" % [boss.fsm.current_name if boss.fsm else &"", boss.hp])
	if _perf:
		_print_perf()
	if _screenshot_path != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_screenshot_path)
		print("screenshot: ", _screenshot_path)
	if mode != Mode.SINGLE:
		# 連線時晚 1 秒才結束：另一個程序也印完之前不要斷線（斷線會移除角色）
		await get_tree().create_timer(1.0).timeout
	get_tree().quit()
