# 組合根：建立 World、輸入、畫面、HUD、音效與連線；主選單、固定步長主迴圈、通關慢動作、暫停 / 選單、靜音、重新開始、離開遊戲
# 三種模式（docs/系統說明.md §8）：單機（= 沒有連線的房主）、房主（跑唯一的 World、收輸入、送快照與事件）、客戶端（鏡像 World + 本機預測）
# 指令列參數（自動驗證、截圖、量效能、連線測試）在 debug/launch_args.gd；--perf 在 debug/perf_meter.gd；除錯鍵與開場布置在 debug/debug_tools.gd
extends Node3D

enum Mode { SINGLE, HOST, CLIENT }

const HUD_SCENE := preload("res://ui/hud.tscn")
const QUIT_AUDIO_DELAY := 0.2   # 結束前停音效後等幾秒（quit_game）：音效伺服器下一次混音才放掉播放物件

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
var args: LaunchArgs          # 啟動參數（正常遊玩全部是預設值）
var perf: PerfMeter           # --perf 才有
var in_weapon_test := false   # 在武器測試場裡（主選單入口，2026-10-27）
var debug_tools := DebugTools.new()
var profile := Profile.new()  # 局外存檔（v0.45）：累計金幣

var _local_peer := World.HOST_PEER_ID
var _net_message := ""
var _sim_accumulator := 0.0
var _stepped_this_tick := false
var _elapsed := 0.0
var _lobby_elapsed := 0.0
var _start_pos := Vector2.INF
var _allies_seen := {}   # 自動驗證：這一局看過的玩家方骷髏僕從 id（G 連線檢查）
var _warming := false                 # 開場預熱中（蓋著「準備中」）
var _spectate := 0                     # 本機陣亡後觀戰的隊友 peer id（0 = 沒在觀戰；_update_spectate）


func _ready() -> void:
	# RPC 的節點路徑以 main 為根：直接執行與在 tests/capture.tscn 裡執行的兩個程序也能互連
	get_tree().set_multiplayer(SceneMultiplayer.new(), get_path())
	InputCollector.register_actions()
	_apply_args()
	if perf != null:
		perf.mark("ready")
	add_child(camera_rig)
	add_child(world_view)
	add_child(arena_view)
	arena_view.build(world.half_extents, world.terrain)
	input_collector.camera_rig = camera_rig
	add_child(input_collector)
	hud = HUD_SCENE.instantiate()
	hud.setup(world, camera_rig.camera)
	hud.health_bars.hidden_ids = world_view.hidden_ids   # 同一個字典，WorldView 每個 tick 原地更新
	hud.run_log.net_info = _net_report
	hud.run_log.frame_context = _frame_context
	hud.quit_requested.connect(quit_game)
	get_tree().auto_accept_quit = false   # 關視窗也走 quit_game（先停音效）
	hud.title_requested.connect(return_to_title)
	hud.main_menu.single_pressed.connect(start_single)
	hud.main_menu.weapon_test_pressed.connect(start_weapon_test)
	hud.weapon_test_equip.connect(_weapon_test_equip)
	hud.weapon_test_reset.connect(_reset_training_dummies)
	hud.main_menu.back_pressed.connect(_on_title_back)
	hud.inventory_panel.op_requested.connect(input_collector.queue_inventory_op)
	if args.run_seconds > 0.0:
		hud.hints.save_path = ""   # 自動驗證（截圖、量效能）不記「看過的提示」，免得使用者自己玩時提示不跳
		profile.save_path = ""     # 也不把自動驗證拿到的金幣算進使用者的存檔
		hud.settings_panel.save_path = ""   # 量效能用預設設定（再用 --shadows / --lights 蓋），不讀使用者的
	profile.load_file()
	hud.profile = profile
	add_child(hud)
	sound.setup(world)
	add_child(sound)
	_load_settings()
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
	if args.menu_flow or not args.auto_start():
		show_title(&"multi" if args.host or args.join != "" else &"home")
		if args.menu_flow and not (args.host or args.join != ""):
			start_single(args.start_class if args.start_class != &"" else ClassDefs.ORDER[0])   # --menu-flow 單人：主選單「單人遊戲」→ 選職業（F2）
		elif args.weapon_test:
			start_weapon_test()   # --weapon-test（網頁版 ?weapon-test）：跳過主選單直接進武器測試場，?weapon= 指定武器
	if args.room:
		hud.net_panel.set_method(&"room")
	if args.host:
		start_hosting()
	elif args.join != "":
		start_joining(args.join)


func _exit_tree() -> void:
	world.clear()   # 切斷實體與 World 的循環參照（連線在 NetSession 離開場景樹時關閉）
	if net_client != null:
		net_client.world.clear()


func _apply_args() -> void:
	args = LaunchArgs.from_os()
	input_collector.auto_move = args.auto_move
	input_collector.auto_attack = args.auto_attack
	input_collector.auto_special = args.auto_special
	input_collector.auto_interact = args.auto_interact
	if args.net_latency_ms >= 0:
		net.latency_ms = args.net_latency_ms
	if args.net_loss >= 0.0:
		net.loss = args.net_loss
	if args.perf:
		perf = PerfMeter.new()


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
	var no_spawn := args.no_spawn or in_weapon_test
	world.spawn_packs = not no_spawn
	if mode == Mode.HOST:
		world.player_classes = net.classes()   # 大廳選的職業（F3）
	if args.start_class != &"":
		world.player_classes[World.HOST_PEER_ID] = args.start_class
	world.reset(randi(), peers)
	world.spawner.finished = no_spawn
	var me := local_player()
	if args.start_weapon != &"":
		me.equip_weapon(args.start_weapon)
	if args.start_wave > 1:
		world.spawner.wave = args.start_wave - 1
	for item in args.start_items:
		me.add_item(item)
	if args.start_hp > 0.0:
		me.hp = args.start_hp
	DebugTools.setup_run(world, me, args)
	if in_weapon_test and not args.weapon_test:
		Spawner.spawn_training_dummies(world, me.pos)
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


# 武器測試場（2026-10-27，主選單入口）：沒有怪群與波次，玩家旁邊擺木樁；上方按鈕列換武器、重置木樁，Esc 回主選單
func start_weapon_test() -> void:
	_net_message = ""
	in_weapon_test = true
	world.player_classes.erase(World.HOST_PEER_ID)   # 共用基準數值，看武器本身
	restart()
	_leave_title()
	hud.weapon_test_bar.visible = true


func leave_weapon_test() -> void:
	in_weapon_test = false
	hud.weapon_test_bar.visible = false
	restart()
	show_title(&"home")


# 武器測試場換武器：換成白色的那把，技能冷卻歸零、箭袋與這關的火把補滿（2026-10-27 使用者：換完要重置技能時間）
func _weapon_test_equip(id: StringName) -> void:
	var me := local_player()
	if not in_weapon_test or me == null:
		return
	me.equip_weapon(id)
	for key in ["player.special", "player.parry", "player.torch"]:
		world.cooldowns.reset(me.cd(key))
	me.torches_left = WeaponDefs.WEAPONS[&"torch"].stance.attack.per_floor


# 木樁被打飛、埋掉後擺回原位：清掉場上的木樁，在玩家旁邊重擺
func _reset_training_dummies() -> void:
	var me := local_player()
	if not in_weapon_test or me == null:
		return
	if me.held_enemy_id != 0:
		me.release_enemy()
	for e in world.enemies:
		if (e as Enemy).main_state == &"train":
			e.remove()   # World 下一步清掉已移除的實體
	Spawner.spawn_training_dummies(world, me.pos)


# 主選單選好職業：開一局新的單人遊戲（F2）
func start_single(class_id: StringName) -> void:
	_net_message = ""
	in_weapon_test = false
	hud.weapon_test_bar.visible = false
	world.player_classes[World.HOST_PEER_ID] = class_id
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
	hud.net_panel.class_chosen.connect(func(id: StringName) -> void: net.set_choice(id, net.is_ready(net.local_peer_id())))
	hud.net_panel.ready_toggled.connect(func(on: bool) -> void: net.set_choice(net.class_of(net.local_peer_id()), on))


# 網頁版用房號（WebRTC + 配對伺服器），桌面版用 IP（ENet）
func start_hosting() -> void:
	set_paused(false)   # 從單機的暫停選單開房：連線時遊戲不會暫停（v0.36.2 修正）
	var err := net.host_room() if hud.net_panel.method == &"room" else net.host(args.net_port)
	if err != OK:
		_net_message = "開房失敗（連接埠 %d 被占用？錯誤 %d）" % [args.net_port, err]
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
	var err := net.join_room(address) if hud.net_panel.method == &"room" else net.join(address, args.net_port)
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
	net_client.world.player_classes = net.classes()   # 快照建立角色時套用職業（F3）
	_use_world(net_client.world)
	is_in_lobby = false
	_elapsed = 0.0
	_leave_title()
	_open_menu(false)
	_refresh_net_panel()


func _on_lobby_changed(peers: Array) -> void:
	_refresh_net_panel()
	if args.run_seconds > 0.0 and mode == Mode.HOST and peers.size() == 1 and net.room_code != "":
		print("net room=%s" % net.room_code)   # --room 自動驗證：另一個程序用這個房號加入
	if mode == Mode.HOST and is_in_lobby and args.autostart_players > 0 and peers.size() >= args.autostart_players:
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


# 設定頁（2026-10-27）：讀檔、套上啟動參數的蓋掉值，之後每次改動都套到音效與畫面
func _load_settings() -> void:
	var panel := hud.settings_panel
	panel.load_file()
	for key: String in args.video:
		panel.set_value(key, args.video[key], false)
	for key: String in panel.values:
		_apply_setting(key, panel.values[key])
	panel.changed.connect(_apply_setting)


func _apply_setting(key: String, value: Variant) -> void:
	match key:
		"shadows":
			world_view.set_shadows(value)
		"lights":
			world_view.set_lights(value)
		"master":
			Sound.set_volume(&"Master", value)
		"music":
			Sound.set_volume(Sound.MUSIC_BUS, value)
		"sfx":
			Sound.set_volume(Sound.SFX_BUS, value)
		"ui_scale":
			get_tree().root.content_scale_factor = value * SettingsPanel.BASE_UI_SCALE   # 乘在 canvas_items 的視窗縮放上
	hud.run_log.video = hud.settings_panel.video_text()


# 遊玩紀錄的最慢一幀：當時鏡頭裡亮著幾盞點光源、看得到幾隻怪
func _frame_context() -> String:
	var shown := world.enemies.size() - world_view.hidden_enemy_count(world)
	return "光 %d 盞、怪 %d 隻" % [world_view.lights_on_screen(camera_rig.camera), shown]


# 遊玩紀錄的連線數據（ui/run_log.gd）；單機回傳空的
func _net_report() -> Dictionary:
	if mode == Mode.SINGLE:
		return {}
	var out := {"role": "房主" if mode == Mode.HOST else "客戶端", "players": world.players.size()}
	if net_client != null:
		out.rtt_ms = net_client.rtt_ms
		out.snapshot_gap_max_ms = net_client.snapshot_gap_max_ms
	if net_host != null:
		out.input_gap_max_ms = net_host.input_gap_max_ms
	return out


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
	hud.net_panel.show_state(state, peers, net.local_peer_id(), _net_message, net.lobby_choices)


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
		var t1 := Time.get_ticks_usec()
		input_collector.consume_latched()
		GameEvents.emit_all(world.events)
		if perf != null:
			perf.add_step(t1 - t0, _elapsed, Time.get_ticks_usec() - t1)
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
	if perf != null:
		perf.log_hitch(delta, _elapsed, _warming)
	var alpha := Engine.get_physics_interpolation_fraction() if _stepped_this_tick else 1.0
	var step := 0
	if _spectate != 0 and not is_menu_open and not hud.is_stats_panel_open():
		if Input.is_action_just_pressed(&"attack") or Input.is_action_just_pressed(&"move_left"):
			step = -1
		elif Input.is_action_just_pressed(&"special") or Input.is_action_just_pressed(&"move_right"):
			step = 1
	_update_spectate(step)
	var t0 := Time.get_ticks_usec()
	world_view.sync(world, alpha, delta)
	if perf != null:
		# 這一幀第一次畫的東西，成本（編譯著色器、產生字形）會算在下一幀的 delta 裡
		perf.prev_first = world_view.first_seen + world_view.effects.first_seen
		perf.prev_sync_usec = Time.get_ticks_usec() - t0
		perf.prev_created = world_view.created
	world_view.created = 0
	world_view.first_seen.clear()
	world_view.effects.first_seen.clear()
	if _warming and not world_view.is_warming_up():
		_warming = false
		hud.set_loading(false)
		if perf != null:
			perf.mark("warm_done")
	if perf != null:
		perf.add_frame(delta, Time.get_ticks_usec() - t0, _elapsed)
	world_view.profile = perf != null and perf.recording(_elapsed)
	camera_rig.follow(_player_view_position(alpha), delta)
	_check_auto_quit(delta)


# 觀戰（規則見 WorldView.spectate_target）：step = −1 換上一位（滑鼠左鍵、A）、+1 下一位（右鍵、D）；
# 視野、鏡頭、場上文字跟著換人，房主也改送他附近的實體（InputCmd.spectate）；復活後回到自己
func _update_spectate(step := 0) -> void:
	_spectate = WorldView.spectate_target(world, _local_peer, _spectate, step)
	world_view.spectate_peer = _spectate
	input_collector.spectate = _spectate
	hud.set_spectating(_spectate)


func _player_view_position(alpha: float) -> Vector3:
	var player: Player = world.players.get(_spectate) if _spectate != 0 else local_player()   # 觀戰時鏡頭跟著隊友
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
		if in_weapon_test:
			leave_weapon_test()   # 武器測試場：Esc 直接回主選單
		elif mode == Mode.SINGLE:
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
	elif event.is_action_pressed(&"stats_panel") and not (is_paused or is_menu_open):   # 暫停 / 選單開著時不開關（2026-10-27 使用者回報）
		# Tab 同時開關背包與屬性面板（v0.27.0 使用者決定，取代 I）；開著時不暫停、角色照常移動，滑鼠只給背包用
		hud.toggle_stats_panel()
		hud.inventory_panel.visible = hud.is_stats_panel_open()
		input_collector.mouse_captured = hud.inventory_panel.visible
	elif mode != Mode.SINGLE:
		return   # 以下除錯鍵直接改模擬狀態、不經過 InputCmd，單機才有
	elif event.is_action_pressed(&"debug_speed"):
		DebugTools.toggle_speed(local_player())
	elif event.is_action_pressed(&"debug_item"):
		debug_tools.add_next_item(world, local_player())
	elif event.is_action_pressed(&"debug_clear_items"):
		DebugTools.clear_items(local_player())


# 靜音狀態給 HUD 顯示（開場時也送一次：上次關遊戲前可能是靜音）
func _emit_muted() -> void:
	GameEvents.event_emitted.emit("audio:muted", {"name": "audio:muted", "muted": sound.is_muted})


func _on_event(name: String, payload: Dictionary) -> void:
	if name == "coins:gained":
		profile.add_coins(payload.amount)   # 多人時全員各拿一份：每台電腦收到同一個事件，各自存自己的
	if name == "camera:shake":
		# 玩家被打的震動只給那位玩家（player_id）；Boss 招式、通關等照常
		var me := local_player()
		if not payload.has("player_id") or (me != null and payload.player_id == me.id):
			camera_rig.shake(payload.amount, payload.duration)
	world_view.on_event(name, payload)


# 切到其他視窗時自動暫停（單機才會），避免回來時已經被打死
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and args.run_seconds <= 0.0:
		set_paused(true)
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()   # auto_accept_quit 關掉了：關視窗也先停音效再結束


func _check_auto_quit(delta: float) -> void:
	if args.run_seconds <= 0.0:
		return
	if is_in_lobby or (mode == Mode.CLIENT and net_client == null):
		# 連線時從開始遊戲才計時；一直沒開始（大廳截圖）也在 --seconds 後結束
		_lobby_elapsed += delta
		if _lobby_elapsed < args.run_seconds:
			return
	else:
		_elapsed += delta
		var me := local_player()
		if _start_pos == Vector2.INF and me != null:
			_start_pos = me.pos   # 開始遊戲後自己角色的第一個位置（結束時印出移動了多遠）
		for a in world.allies:   # 連線檢查用（G）：這一局看過的玩家方骷髏僕從（結束時不一定還活著）
			_allies_seen[a.id] = true
	if args.auto_move_seconds > 0.0 and _elapsed >= args.auto_move_seconds:
		input_collector.auto_move = Vector2.ZERO
	if _elapsed < args.run_seconds and _lobby_elapsed < args.run_seconds:
		return
	args.run_seconds = 0.0
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
	# 連線檢查用（G 道具）：玩家方的骷髏僕從、追蹤鬼火的數量，每位玩家的護盾（占最大生命的比例）
	var items_line := "items allies_seen=%d allies=%d wisps=%d" % [_allies_seen.size(),
		world.allies.filter(func(e: Entity) -> bool: return not e.is_dead).size(),
		world.projectiles.filter(func(e: Entity) -> bool: return (e as Projectile).homing > 0.0).size()]
	for peer_id: int in peers:
		items_line += " shield%d=%.3f" % [peer_id, (world.players[peer_id] as Player).anim.get("shield", 0.0)]
	print(items_line)
	var me := local_player()
	var moved := me.pos.distance_to(_start_pos) if me != null and _start_pos != Vector2.INF else -1.0
	print("state title=%d paused=%d input=%d effects_paused=%d self_moved=%.2f" % [int(is_at_title), int(is_paused), int(input_collector.enabled), int(world_view.effects.paused), moved])
	if net_client != null:
		print("net corrections=%d max_error=%.4f" % [net_client.corrections, net_client.max_error])
	var boss: Enemy = world.entities.get(world.boss_id)
	if boss != null:
		print("boss state=%s hp=%.0f" % [boss.fsm.current_name if boss.fsm else &"", boss.hp])
	if perf != null:
		print("perf settings %s" % hud.settings_panel.video_text())   # 開場就印會被 release.mjs 當成遊戲開始跑
		perf.print_report(world, world_view)
	if args.screenshot_path != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args.screenshot_path)
		print("screenshot: ", args.screenshot_path)
	if mode != Mode.SINGLE:
		# 連線時晚 1 秒才結束：另一個程序也印完之前不要斷線（斷線會移除角色）
		await get_tree().create_timer(1.0).timeout
	quit_game()


# 結束程式（離開遊戲按鈕、關視窗、自動驗證跑完）：先停音效、等音效伺服器放掉播放物件再結束，
# 直接 quit 時還在播的音效會被回報「ObjectDB instances leaked」
func quit_game() -> void:
	sound.stop_all()
	await get_tree().create_timer(QUIT_AUDIO_DELAY, true, false, true).timeout
	get_tree().quit()
