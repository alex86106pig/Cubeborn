# 傳輸層（docs/系統說明.md §8）：建立房間 / 加入 / 斷線、大廳名單、RPC 收送；對外只用訊號與 send_* 函式
# 兩種連線方式（玩家在主選單選）：IP = Godot 內建 ENet（區網 / 虛擬區網，只有桌面版）；房號 = WebRTC 直連，經 PeerJS 公開配對伺服器牽線
# （net/peerjs_signaling.gd，網頁版 v0.36.0）。桌面版的 WebRTC 來自 addons/webrtc_native（v0.40.0），所以桌面版與網頁版用房號可以互連。
# 兩種都是 MultiplayerPeer，RPC、快照、輸入的程式相同
# 上架前換成 Steam 連線只改這個檔案
# 模擬延遲 / 掉包（除錯用）：送出前排隊 latency_ms 再真的送；掉包只套用在 unreliable（輸入與快照）
class_name NetSession
extends Node

signal lobby_changed(peer_ids: Array)          # 大廳名單（含房主 1），房主與客戶端都會收到
signal game_started(peer_ids: Array)           # 客戶端：房主按下開始
signal inputs_received(peer_id: int, arrays: Array)
signal snapshot_received(snap: Array)
signal events_received(run: int, tick: int, events: Array)
signal peer_left(peer_id: int)                 # 房主：有人斷線
signal connection_failed
signal disconnected                            # 客戶端：和房主斷線

const CHANNEL_RELIABLE := 0
const CHANNEL_UNRELIABLE := 1

var is_host := false
var is_started := false
var lobby_peers: Array[int] = []
var lobby_choices: Dictionary = {}   # 大廳選擇（F3）：peer id → [職業 id（String）, 準備好了]；房主決定、廣播給所有人
var lobby_difficulty := String(EventDefs.DEFAULT_MODE)   # 大廳的難度（EventDefs.MODES）：房主選、跟名單一起廣播
var latency_ms: int = Config.NET.debug_latency_ms
var loss: float = Config.NET.debug_loss

var room_code := ""              # 房號連線：房號（房主開房後、客戶端輸入的）
var last_error := ""             # connection_failed 的原因（房號配對失敗時才有；空的 = 用預設說明）

var _outbox: Array = []          # [送出時間 ms, Callable]（模擬延遲用）
var _rng := RandomNumberGenerator.new()
var _signal: PeerJsSignaling     # 房號配對（連上之後客戶端就關掉；房主開始遊戲時關掉）
var _rtc: WebRTCMultiplayerPeer
var _conns := {}                 # 對方的配對 ID → WebRTCPeerConnection
var _web_peer_id := 0            # 房號連線客戶端自己的 peer id（2 ~ 2^31-2 隨機）
var _join_timer := 0.0
var _room_tries := 0


func _ready() -> void:
	_rng.randomize()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: close(); connection_failed.emit())
	multiplayer.server_disconnected.connect(func() -> void: close(); disconnected.emit())


# 結束遊戲時關閉連線（對方會馬上收到斷線，資源也會釋放）
func _exit_tree() -> void:
	close()


func is_active() -> bool:
	if not is_inside_tree():   # 不在場景樹（檢查直接建的）讀不到 multiplayer，當作沒連線
		return false
	var p := multiplayer.multiplayer_peer
	return p != null and not p is OfflineMultiplayerPeer


# IP 連線：網頁版不能用（瀏覽器不能開 UDP）
static func ip_supported() -> bool:
	return not OS.has_feature("web")


# 房號連線：網頁版用瀏覽器內建的 WebRTC；桌面版要載入 webrtc-native 擴充（缺檔時沒有這個類別）
static func room_supported() -> bool:
	return OS.has_feature("web") or ClassDB.class_exists(&"WebRTCLibPeerConnection")


func local_peer_id() -> int:
	return multiplayer.get_unique_id() if is_active() else World.HOST_PEER_ID


func host(port: int = Config.NET.port) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, Config.NET.max_players - 1, 2)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	is_started = false
	lobby_peers = [World.HOST_PEER_ID]
	lobby_choices = {World.HOST_PEER_ID: default_choice(true)}
	lobby_difficulty = String(EventDefs.DEFAULT_MODE)
	lobby_changed.emit(lobby_peers.duplicate())
	return OK


func join(address: String, port: int = Config.NET.port) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port, 2)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	is_started = false
	lobby_peers = []
	lobby_choices = {}
	lobby_difficulty = String(EventDefs.DEFAULT_MODE)
	return OK


# 房號開房：先抽房號向配對伺服器註冊（撞到別人就重抽），註冊成功才建立 WebRTC 房間並發 lobby_changed
func host_room() -> Error:
	close()
	last_error = ""
	is_host = true
	lobby_peers = [World.HOST_PEER_ID]
	lobby_choices = {World.HOST_PEER_ID: default_choice(true)}
	lobby_difficulty = String(EventDefs.DEFAULT_MODE)
	_room_tries = 0
	return _open_room()


func _open_room() -> Error:
	room_code = PeerJsSignaling.random_room_code(_rng)
	_signal = _new_signal()
	_signal.opened.connect(_on_room_opened)
	_signal.id_taken.connect(func() -> void:
		_room_tries += 1
		if _room_tries < Config.NET.web_room_retries:
			_open_room()
		else:
			_fail("開房失敗：房號一直撞到別人"))
	return _signal.open(PeerJsSignaling.host_id(room_code))


func _on_room_opened() -> void:
	_rtc = WebRTCMultiplayerPeer.new()
	var err := _rtc.create_server([MultiplayerPeer.TRANSFER_MODE_UNRELIABLE])   # 頻道 1 = unreliable（同 ENet 的 CHANNEL_UNRELIABLE）
	if err != OK:
		_fail("開房失敗（WebRTC 錯誤 %d）" % err)
		return
	multiplayer.multiplayer_peer = _rtc
	lobby_changed.emit(lobby_peers.duplicate())


# 房號加入：用隨機 ID 註冊 → 建立連到房主（peer 1）的 WebRTC 連線、送出 OFFER；web_join_timeout 秒內沒連上就放棄
func join_room(code: String) -> Error:
	close()
	last_error = ""
	is_host = false
	lobby_peers = []
	room_code = code.strip_edges().to_upper()
	_web_peer_id = _rng.randi_range(2, 2147483646)
	_join_timer = Config.NET.web_join_timeout
	_signal = _new_signal()
	_signal.opened.connect(_on_join_opened)
	return _signal.open("%sc-%08x%08x" % [Config.NET.web_id_prefix, _rng.randi(), _rng.randi()])


func _on_join_opened() -> void:
	_rtc = WebRTCMultiplayerPeer.new()
	var err := _rtc.create_client(_web_peer_id, [MultiplayerPeer.TRANSFER_MODE_UNRELIABLE])
	if err != OK:
		_fail("加入失敗（WebRTC 錯誤 %d）" % err)
		return
	multiplayer.multiplayer_peer = _rtc
	var conn := _new_conn(PeerJsSignaling.host_id(room_code), PeerJsSignaling.random_connection_id(_rng))
	_rtc.add_peer(conn, World.HOST_PEER_ID)
	conn.create_offer()


func _new_signal() -> PeerJsSignaling:
	var s := PeerJsSignaling.new()
	s.failed.connect(_fail)
	s.expired.connect(func(_dst: String) -> void:
		if not is_host:
			_fail("找不到房號 %s（房主還沒開房，或已經關掉了）" % room_code))
	s.message_received.connect(_on_signal_message)
	return s


# 一條 WebRTC 連線：自己的 SDP 與候選位址都經配對伺服器送給對方（PeerJS 格式，同一條連線用同一個 connection_id）
func _new_conn(remote_id: String, connection_id: String) -> WebRTCPeerConnection:
	var conn := WebRTCPeerConnection.new()
	conn.initialize({"iceServers": Config.NET.ice_servers})
	conn.session_description_created.connect(func(type: String, sdp: String) -> void:
		conn.set_local_description(type, sdp)
		if _signal == null:
			return
		if type == "offer":
			_signal.send("OFFER", remote_id, PeerJsSignaling.offer_payload(sdp, connection_id, _web_peer_id))
		else:
			_signal.send("ANSWER", remote_id, PeerJsSignaling.answer_payload(sdp, connection_id)))
	conn.ice_candidate_created.connect(func(mid: String, index: int, candidate: String) -> void:
		if _signal != null:
			_signal.send("CANDIDATE", remote_id, PeerJsSignaling.candidate_payload(mid, index, candidate, connection_id)))
	_conns[remote_id] = conn
	return conn


func _on_signal_message(type: String, src: String, payload: Dictionary) -> void:
	if _rtc == null:
		return
	match type:
		"OFFER":
			# 只有房主收 OFFER；開始了或滿了就不回應（對方逾時）
			var pid := PeerJsSignaling.peer_id_of(payload)
			if not is_host or is_started or lobby_peers.size() >= Config.NET.max_players or pid < 2 or _conns.has(src):
				return
			var conn := _new_conn(src, str(payload.get("connectionId", "")))
			_rtc.add_peer(conn, pid)
			conn.set_remote_description("offer", PeerJsSignaling.sdp_of(payload))
		"ANSWER":
			var conn: WebRTCPeerConnection = _conns.get(src)
			if conn != null:
				conn.set_remote_description("answer", PeerJsSignaling.sdp_of(payload))
		"CANDIDATE":
			var conn: WebRTCPeerConnection = _conns.get(src)
			if conn != null:
				var c := PeerJsSignaling.candidate_of(payload)
				conn.add_ice_candidate(c[0], c[1], c[2])


func _fail(reason: String) -> void:
	last_error = reason
	close()
	connection_failed.emit()


func close() -> void:
	var api := multiplayer
	if api != null:
		if api.multiplayer_peer != null:
			api.multiplayer_peer.close()
		api.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _signal != null:
		_signal.close()
		_signal = null
	_rtc = null
	_conns.clear()
	room_code = ""
	_join_timer = 0.0
	is_host = false
	is_started = false
	lobby_peers = []
	lobby_choices = {}
	lobby_difficulty = String(EventDefs.DEFAULT_MODE)
	_outbox.clear()


# 房主：開始遊戲，之後不再接受加入（中途加入先不開放，使用者決定）；房號連線也不再需要配對伺服器
func start_game() -> void:
	is_started = true
	if _signal != null:
		_signal.close()
		_signal = null
	_send(func() -> void: _rpc_start.rpc(lobby_peers, lobby_choices, lobby_difficulty), false)


func send_inputs(arrays: Array) -> void:
	_send(func() -> void: _rpc_inputs.rpc_id(World.HOST_PEER_ID, arrays), true)


func send_snapshot(peer_id: int, snap: Array) -> void:
	_send(func() -> void: _rpc_snapshot.rpc_id(peer_id, snap), true)


func send_events(run: int, tick: int, events: Array) -> void:
	_send(func() -> void: _rpc_events.rpc(run, tick, events), false)


func _send(fn: Callable, unreliable: bool) -> void:
	if not is_active():
		return
	if unreliable and loss > 0.0 and _rng.randf() < loss:
		return
	if latency_ms <= 0:
		fn.call()
	else:
		_outbox.append([Time.get_ticks_msec() + latency_ms, fn])


func _process(delta: float) -> void:
	if _signal != null:
		_signal.poll(delta)
	if _join_timer > 0.0 and not is_host and lobby_peers.is_empty():
		_join_timer -= delta
		if _join_timer <= 0.0:
			_fail("連不上房主（房號 %s 逾時；對方的網路可能擋住直連）" % room_code)
	var now := Time.get_ticks_msec()
	while not _outbox.is_empty() and _outbox[0][0] <= now and is_active():
		_outbox.pop_front()[1].call()


func _on_peer_connected(peer_id: int) -> void:
	if not is_host:
		return
	if is_started or lobby_peers.size() >= Config.NET.max_players:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	lobby_peers.append(peer_id)
	lobby_choices[peer_id] = default_choice(false)
	_broadcast_lobby()


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host:
		return
	lobby_peers.erase(peer_id)
	lobby_choices.erase(peer_id)
	peer_left.emit(peer_id)
	_broadcast_lobby()


func _on_connected() -> void:
	if _signal != null and not is_host:   # 房號連線的客戶端連上房主後就不需要配對伺服器
		_signal.close()
		_signal = null
	lobby_changed.emit(lobby_peers.duplicate())


func _broadcast_lobby() -> void:
	lobby_changed.emit(lobby_peers.duplicate())
	_send(func() -> void: _rpc_lobby.rpc(lobby_peers, lobby_choices, lobby_difficulty), false)


# ───────── 大廳選職業與準備（F3） ─────────

# 新加入的人預設選第一個職業、還沒準備好；房主一律算準備好（按開始就是準備好了）
static func default_choice(ready: bool) -> Array:
	return [String(ClassDefs.ORDER[0]), ready]


func class_of(peer_id: int) -> StringName:
	return StringName(lobby_choices[peer_id][0]) if lobby_choices.has(peer_id) else ClassDefs.ORDER[0]


func is_ready(peer_id: int) -> bool:
	return peer_id == World.HOST_PEER_ID or (lobby_choices.has(peer_id) and lobby_choices[peer_id][1])


# 房主的「開始遊戲」要全員準備好才能按
func all_ready() -> bool:
	for id in lobby_peers:
		if not is_ready(id):
			return false
	return true


# 開局時每個人的職業（World.player_classes）
func classes() -> Dictionary:
	var out := {}
	for id in lobby_peers:
		out[id] = class_of(id)
	return out


# 自己選職業 / 切換準備：房主直接改、廣播；客戶端送給房主，等房主廣播回來才更新
func set_choice(class_id: StringName, ready: bool) -> void:
	if is_started or not ClassDefs.is_pickable(class_id):
		return
	if is_host:
		lobby_choices[World.HOST_PEER_ID] = [String(class_id), true]
		_broadcast_lobby()
	else:
		_send(func() -> void: _rpc_choice.rpc_id(World.HOST_PEER_ID, String(class_id), ready), false)


@rpc("any_peer", "call_remote", "reliable", CHANNEL_RELIABLE)
func _rpc_choice(class_id: String, ready: bool) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if not is_host or is_started or not lobby_peers.has(pid) or not ClassDefs.is_pickable(StringName(class_id)):
		return
	lobby_choices[pid] = [class_id, ready]
	_broadcast_lobby()


# 房主選難度：所有客戶端的「準備好了」重設（大家是在舊難度下按的）
func set_difficulty(mode: StringName) -> void:
	if not is_host or is_started or not EventDefs.MODES.has(mode) or String(mode) == lobby_difficulty:
		return
	lobby_difficulty = String(mode)
	for id: int in lobby_choices:
		if id != World.HOST_PEER_ID:
			lobby_choices[id][1] = false
	_broadcast_lobby()


# 大廳的難度（收到不認得的值就當預設）
func difficulty() -> StringName:
	var m := StringName(lobby_difficulty)
	return m if EventDefs.MODES.has(m) else EventDefs.DEFAULT_MODE


@rpc("authority", "call_remote", "reliable", CHANNEL_RELIABLE)
func _rpc_lobby(peers: Array, choices: Dictionary, p_difficulty: String) -> void:
	lobby_peers.assign(peers)
	lobby_choices = choices
	lobby_difficulty = p_difficulty
	lobby_changed.emit(peers)


@rpc("authority", "call_remote", "reliable", CHANNEL_RELIABLE)
func _rpc_start(peers: Array, choices: Dictionary, p_difficulty: String) -> void:
	is_started = true
	lobby_peers.assign(peers)
	lobby_choices = choices
	lobby_difficulty = p_difficulty
	game_started.emit(peers)


@rpc("any_peer", "call_remote", "unreliable", CHANNEL_UNRELIABLE)
func _rpc_inputs(arrays: Array) -> void:
	if is_host:
		inputs_received.emit(multiplayer.get_remote_sender_id(), arrays)


@rpc("authority", "call_remote", "unreliable", CHANNEL_UNRELIABLE)
func _rpc_snapshot(snap: Array) -> void:
	snapshot_received.emit(snap)


@rpc("authority", "call_remote", "reliable", CHANNEL_RELIABLE)
func _rpc_events(run: int, tick: int, events: Array) -> void:
	events_received.emit(run, tick, events)
