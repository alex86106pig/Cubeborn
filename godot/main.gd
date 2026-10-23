# 組合根：建立 World、輸入、畫面、HUD、音效與連線；固定步長主迴圈、通關慢動作、暫停 / 選單、靜音、重新開始、離開遊戲
# 三種模式（15.18）：單機（= 沒有連線的房主）、房主（跑唯一的 World、收輸入、送快照與事件）、客戶端（鏡像 World + 本機預測）
# 指令列參數（放在 -- 之後）：--seconds=S --screenshot=路徑 --auto-move=x,y（螢幕方向）--auto-move-seconds=S（幾秒後停止移動）
#   --auto-attack（一直按住左鍵）--auto-special（開場按一次右鍵，之後每 5.1 秒再按一次）--auto-interact（一直按住 F）--weapon=staff（開場武器）
#   --wave=N（直接從第 N 波開始）--player-hp=N（開場血量）--items=id,id（開場放進身上的道具，見 defs/item_defs.gd）--no-spawn（不生怪）
#   連線：--host（開房）--join=IP（加入）--net-port=N --net-autostart=N（房主：滿 N 人自動開始）
#   --net-latency=毫秒（模擬單程延遲）--net-loss=0.1（模擬掉包）
extends Node3D

enum Mode { SINGLE, HOST, CLIENT }

const HUD_SCENE := preload("res://ui/hud.tscn")

var mode := Mode.SINGLE
var world := World.new()      # 單機 / 房主：權威的 World；客戶端：net_client.world（快照的鏡像）
var is_paused := false        # 單機暫停（連線時 Esc 只開選單，遊戲不停）
var is_menu_open := false     # 連線時的選單
var is_in_lobby := false      # 開房 / 加入後、開始遊戲前

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
var _net_port: int = Config.NET.port
var _autostart_players := 0


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
	hud.quit_requested.connect(get_tree().quit)
	add_child(hud)
	sound.setup(world)
	add_child(sound)
	net.name = &"Net"
	add_child(net)
	_connect_net()
	_emit_muted()
	GameEvents.event_emitted.connect(_on_event)
	restart()
	if _arg_host:
		start_hosting()
	elif _arg_join != "":
		start_joining(_arg_join)


func _exit_tree() -> void:
	world.clear()   # 切斷實體與 World 的循環參照（連線在 NetSession 離開場景樹時關閉）
	if net_client != null:
		net_client.world.clear()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
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
		elif arg.begins_with("--net-port="):
			_net_port = value.to_int()
		elif arg.begins_with("--net-autostart="):
			_autostart_players = value.to_int()
		elif arg.begins_with("--net-latency="):
			net.latency_ms = value.to_int()
		elif arg.begins_with("--net-loss="):
			net.loss = value.to_float()


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
	if paused and (mode != Mode.SINGLE or world.is_over or player == null or player.is_dead):
		return
	if is_paused == paused:
		return
	is_paused = paused
	world_view.effects.paused = paused
	GameEvents.event_emitted.emit("game:paused", {"name": "game:paused", "paused": paused})


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
	net.connection_failed.connect(func() -> void: leave_net("連不上房主（IP 或防火牆？）"))
	net.disconnected.connect(func() -> void: leave_net("和房主斷線了"))
	hud.net_panel.host_pressed.connect(start_hosting)
	hud.net_panel.join_pressed.connect(start_joining)
	hud.net_panel.start_pressed.connect(start_net_game)
	hud.net_panel.leave_pressed.connect(leave_net.bind(""))


func start_hosting() -> void:
	var err := net.host(_net_port)
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
	var err := net.join(address, _net_port)
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
	_open_menu(false)
	restart()
	_refresh_net_panel()


func _on_game_started(_peers: Array) -> void:
	_local_peer = net.local_peer_id()
	net_client = NetClient.new(_local_peer)
	_use_world(net_client.world)
	is_in_lobby = false
	_elapsed = 0.0
	_open_menu(false)
	_refresh_net_panel()


func _on_lobby_changed(peers: Array) -> void:
	_refresh_net_panel()
	if mode == Mode.HOST and is_in_lobby and _autostart_players > 0 and peers.size() >= _autostart_players:
		start_net_game()


# 房主：有人斷線就把他的角色移除
func _on_peer_left(peer_id: int) -> void:
	if net_host != null:
		net_host.remove_peer(peer_id)
	var p: Player = world.players.get(peer_id)
	if p != null:
		p.remove()


# 離開連線回到單機（自己按的、連不上、房主斷線）
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
	_open_menu(message != "")
	_refresh_net_panel()


func _use_world(w: World) -> void:
	if w != world:
		world.clear()
	world = w
	world_view.clear_views()
	hud.setup(world, camera_rig.camera)
	hud.set_local_peer(_local_peer)
	world_view.local_peer = _local_peer
	sound.setup(world)


func _open_menu(open: bool) -> void:
	if mode == Mode.SINGLE:
		is_menu_open = false
		set_paused(open)
		return
	is_menu_open = open or is_in_lobby
	hud.show_menu(is_menu_open, "連線大廳" if is_in_lobby else "選單", "" if is_in_lobby else "按 Esc 關閉（連線中遊戲不會暫停）")


func _refresh_net_panel() -> void:
	var state := &"single"
	if mode == Mode.HOST:
		state = &"lobby_host" if is_in_lobby else &"playing"
	elif mode == Mode.CLIENT:
		if not net.is_active() or net.local_peer_id() == World.HOST_PEER_ID:
			state = &"connecting"
		else:
			state = &"lobby_client" if is_in_lobby else &"playing"
	var peers: Array = net.lobby_peers.duplicate()
	peers.sort()
	hud.net_panel.show_state(state, peers, net.local_peer_id(), _net_message)


# ───────── 主迴圈 ─────────

func _physics_process(_delta: float) -> void:
	_stepped_this_tick = false
	input_collector.enabled = not (is_menu_open or is_paused or hud.net_panel.is_typing())
	if mode == Mode.CLIENT:
		_client_physics()
	else:
		_authority_physics()


func _authority_physics() -> void:
	if is_paused or is_in_lobby:
		input_collector.consume_latched()   # 暫停中的點擊與按鍵不留到繼續之後
		return
	# 通關慢動作：真實時間照走，邏輯時間放慢到 5%，每步仍是 FIXED_DT（v0.18.3 起只剩打倒 Boss 時用；一般命中改成畫面層的命中定格）
	_sim_accumulator += Config.FIXED_DT * world.consume_hit_stop(Config.FIXED_DT)
	while _sim_accumulator >= Config.FIXED_DT - 1e-9:
		_sim_accumulator -= Config.FIXED_DT
		var cmds := net_host.take_cmds() if net_host != null else {}
		cmds[World.HOST_PEER_ID] = input_collector.build_cmd(world.tick + 1)
		world.step(cmds, Config.FIXED_DT)
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
	var alpha := Engine.get_physics_interpolation_fraction() if _stepped_this_tick else 1.0
	world_view.sync(world, alpha, delta)
	camera_rig.follow(_player_view_position(alpha), delta)
	_check_auto_quit(delta)


func _player_view_position(alpha: float) -> Vector3:
	var player := local_player()
	if player == null:
		return Vector3.ZERO
	var p := player.prev_pos.lerp(player.pos, alpha)
	return Vector3(p.x, 0.0, p.y)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
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
		hud.toggle_stats_panel()
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


# 除錯用（非正式系統，單機才有）：依道具清單順序，每按一次 F4 放一個道具進身上（循環）
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
	if net_client != null:
		print("net corrections=%d max_error=%.4f" % [net_client.corrections, net_client.max_error])
	var boss: Enemy = world.entities.get(world.boss_id)
	if boss != null:
		print("boss state=%s hp=%.0f" % [boss.fsm.current_name if boss.fsm else &"", boss.hp])
	if _screenshot_path != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_screenshot_path)
		print("screenshot: ", _screenshot_path)
	if mode != Mode.SINGLE:
		# 連線時晚 1 秒才結束：另一個程序也印完之前不要斷線（斷線會移除角色）
		await get_tree().create_timer(1.0).timeout
	get_tree().quit()
