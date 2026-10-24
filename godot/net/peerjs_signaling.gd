# 網頁連線的配對（v0.36.0，想法清單 #12）：借 PeerJS 的免費公開配對伺服器（Config.NET.web_signal_url），只用來交換 WebRTC 的
# OFFER / ANSWER / CANDIDATE；連上之後遊戲資料走 WebRTC 直連。
# v0.36.1：公開的 0.peerjs.com 會檢查 payload 是不是 PeerJS 函式庫的格式（含真的 SDP），不是就直接斷線（開源版伺服器沒有這個檢查），
# 所以 payload 照 PeerJS 1.5.4 的樣子包（offer_payload / answer_payload / candidate_payload），我們自己的 peer id 放在 metadata。
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


static func random_connection_id(rng: RandomNumberGenerator) -> String:
	const CHARS := "abcdefghijklmnopqrstuvwxyz0123456789"
	var out := "dc_"
	for i in 10:
		out += CHARS[rng.randi_range(0, CHARS.length() - 1)]
	return out


# PeerJS 1.5.4 的 payload 格式（伺服器會檢查）
static func offer_payload(sdp: String, connection_id: String, peer_id: int) -> Dictionary:
	return {"sdp": {"sdp": sdp, "type": "offer"}, "type": "data", "connectionId": connection_id, "metadata": {"peer_id": peer_id},
		"label": connection_id, "reliable": false, "serialization": "binary"}


static func answer_payload(sdp: String, connection_id: String) -> Dictionary:
	return {"sdp": {"sdp": sdp, "type": "answer"}, "type": "data", "connectionId": connection_id}


static func candidate_payload(mid: String, index: int, candidate: String, connection_id: String) -> Dictionary:
	return {"candidate": {"candidate": candidate, "sdpMid": mid, "sdpMLineIndex": index}, "type": "data", "connectionId": connection_id}


static func sdp_of(payload: Dictionary) -> String:
	var sdp: Variant = payload.get("sdp", {})
	return str(sdp.get("sdp", "")) if sdp is Dictionary else ""


static func peer_id_of(payload: Dictionary) -> int:
	var meta: Variant = payload.get("metadata", {})
	return int(meta.get("peer_id", 0)) if meta is Dictionary else 0


# → [mid, index, candidate]
static func candidate_of(payload: Dictionary) -> Array:
	var c: Variant = payload.get("candidate", {})
	if not c is Dictionary:
		return ["", 0, ""]
	return [str(c.get("sdpMid", "")), int(c.get("sdpMLineIndex", 0)), str(c.get("candidate", ""))]


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
