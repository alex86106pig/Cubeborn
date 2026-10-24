# 網頁連線的配對（v0.36.0，想法清單 #12）：借 PeerJS 的免費公開配對伺服器（Config.NET.web_signal_url），只用來交換 WebRTC 的
# OFFER / ANSWER / CANDIDATE；伺服器原樣轉送 payload，兩端都是本遊戲，不必相容 PeerJS 函式庫的資料格式。連上之後遊戲資料走 WebRTC 直連。
# 協定：WebSocket 連 <url>?key=&id=&token=&version= → 伺服器回 OPEN（註冊成功）/ ID-TAKEN / ERROR；
# 送 {type, dst, payload}、收 {type, src, payload}；每 web_heartbeat 秒送 HEARTBEAT；對方不在線時伺服器回 EXPIRE
# NetSession._process 每幀呼叫 poll()
class_name PeerJsSignaling
extends RefCounted

signal opened                                            # 註冊成功，可以收發
signal id_taken                                          # 這個 ID 有人用了（房主換房號重試）
signal failed(reason: String)                            # 連不上伺服器、伺服器回錯誤
signal expired(dst: String)                              # 要送的對象不在線（房號不存在）
signal message_received(type: String, src: String, payload: Dictionary)   # OFFER / ANSWER / CANDIDATE

const PEERJS_VERSION := "1.5.4"
const RELAYED := ["OFFER", "ANSWER", "CANDIDATE"]

var id := ""
var _ws := WebSocketPeer.new()
var _is_open := false
var _heartbeat := 0.0
var _last_state := WebSocketPeer.STATE_CLOSED


static func url_for(peer_id: String, token: String) -> String:
	var n: Dictionary = Config.NET
	return "%s?key=%s&id=%s&token=%s&version=%s" % [n.web_signal_url, n.web_signal_key, peer_id.uri_encode(), token, PEERJS_VERSION]


# 房號：web_room_length 個 web_room_chars 裡的字（不含容易看錯的 0 / O、1 / I）
static func random_room_code(rng: RandomNumberGenerator) -> String:
	var chars: String = Config.NET.web_room_chars
	var out := ""
	for i in Config.NET.web_room_length:
		out += chars[rng.randi_range(0, chars.length() - 1)]
	return out


static func host_id(room_code: String) -> String:
	return Config.NET.web_id_prefix + room_code.to_upper()


static func encode(type: String, dst: String, payload: Dictionary) -> String:
	return JSON.stringify({"type": type, "dst": dst, "payload": payload})


# 伺服器送來的一則訊息 → {type, src, payload}；格式不對回傳空的
static func decode(text: String) -> Dictionary:
	var json := JSON.new()   # 不用 JSON.parse_string：格式錯時會印錯誤
	if json.parse(text) != OK:
		return {}
	var v: Variant = json.data
	if not v is Dictionary or not (v as Dictionary).has("type"):
		return {}
	var d: Dictionary = v
	var payload: Variant = d.get("payload", {})
	return {"type": str(d.type), "src": str(d.get("src", "")), "payload": payload if payload is Dictionary else {}}


func open(peer_id: String) -> Error:
	close()
	id = peer_id
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var token := "%08x%08x" % [rng.randi(), rng.randi()]
	_last_state = WebSocketPeer.STATE_CONNECTING
	return _ws.connect_to_url(url_for(peer_id, token))


func close() -> void:
	if _ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_ws.close()
	_is_open = false
	_last_state = WebSocketPeer.STATE_CLOSED


func is_open() -> bool:
	return _is_open


func send(type: String, dst: String, payload: Dictionary) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(encode(type, dst, payload))


func poll(delta: float) -> void:
	if _last_state == WebSocketPeer.STATE_CLOSED:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		var was_open := _is_open
		_is_open = false
		_last_state = state
		failed.emit("和配對伺服器斷線" if was_open else "連不上配對伺服器（%d）" % _ws.get_close_code())
		return
	_last_state = state
	if state != WebSocketPeer.STATE_OPEN:
		return
	while _ws.get_available_packet_count() > 0:
		_handle(decode(_ws.get_packet().get_string_from_utf8()))
	if _is_open:
		_heartbeat -= delta
		if _heartbeat <= 0.0:
			_heartbeat = Config.NET.web_heartbeat
			_ws.send_text(JSON.stringify({"type": "HEARTBEAT"}))


func _handle(m: Dictionary) -> void:
	if m.is_empty():
		return
	match m.type:
		"OPEN":
			_is_open = true
			_heartbeat = Config.NET.web_heartbeat
			opened.emit()
		"ID-TAKEN":
			close()
			id_taken.emit()
		"ERROR", "INVALID-KEY":
			close()
			failed.emit("配對伺服器錯誤：%s" % m.payload.get("msg", m.type))
		"EXPIRE":
			expired.emit(m.src)
		_:
			if m.type in RELAYED:
				message_received.emit(m.type, m.src, m.payload)
