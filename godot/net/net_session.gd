# 傳輸層（15.18）：建立房間 / 加入 / 斷線、大廳名單、RPC 收送；對外只用訊號與 send_* 函式
# 開發期用 Godot 內建 ENet（區網），上架前換成 Steam 連線只改這個檔案
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
var latency_ms: int = Config.NET.debug_latency_ms
var loss: float = Config.NET.debug_loss

var _outbox: Array = []          # [送出時間 ms, Callable]（模擬延遲用）
var _rng := RandomNumberGenerator.new()


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
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer


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
	return OK


func close() -> void:
	var api := multiplayer
	if api != null:
		if api.multiplayer_peer != null:
			api.multiplayer_peer.close()
		api.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_host = false
	is_started = false
	lobby_peers = []
	_outbox.clear()


# 房主：開始遊戲，之後不再接受加入（中途加入先不開放，使用者決定）
func start_game() -> void:
	is_started = true
	_send(func() -> void: _rpc_start.rpc(lobby_peers), false)


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


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	while not _outbox.is_empty() and _outbox[0][0] <= now and is_active():
		_outbox.pop_front()[1].call()


func _on_peer_connected(peer_id: int) -> void:
	if not is_host:
		return
	if is_started or lobby_peers.size() >= Config.NET.max_players:
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)
		return
	lobby_peers.append(peer_id)
	_broadcast_lobby()


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host:
		return
	lobby_peers.erase(peer_id)
	peer_left.emit(peer_id)
	_broadcast_lobby()


func _on_connected() -> void:
	lobby_changed.emit(lobby_peers.duplicate())


func _broadcast_lobby() -> void:
	lobby_changed.emit(lobby_peers.duplicate())
	_send(func() -> void: _rpc_lobby.rpc(lobby_peers), false)


@rpc("authority", "call_remote", "reliable", CHANNEL_RELIABLE)
func _rpc_lobby(peers: Array) -> void:
	lobby_peers.assign(peers)
	lobby_changed.emit(peers)


@rpc("authority", "call_remote", "reliable", CHANNEL_RELIABLE)
func _rpc_start(peers: Array) -> void:
	is_started = true
	lobby_peers.assign(peers)
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
