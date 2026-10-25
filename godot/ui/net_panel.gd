# 連線面板：開房、輸入 IP 加入（網頁版：房號，v0.36.0）、大廳名單、開始遊戲、離開連線
# 平常放在主選單的多人頁；遊戲中放在 Esc 選單（只有連線中才顯示，v0.39.0）
# 只發訊號，實際連線由 main.gd 處理
class_name NetPanel
extends VBoxContainer

signal host_pressed
signal join_pressed(address: String)
signal start_pressed
signal leave_pressed

var room_code := ""   # 網頁版：房主的房號（main.gd 在 show_state 前設定）
var mode: StringName = &"single"   # 最後一次 show_state 的狀態
var _web := NetSession.uses_webrtc()
var _status := UiKit.label("", 18, Color(1, 1, 1, 0.9))
var _address := LineEdit.new()
var _host_button := _button("開房（網路）" if NetSession.uses_webrtc() else "開房（區網）")
var _join_button := _button("加入")
var _start_button := _button("開始遊戲")
var _leave_button := _button("離開連線")
var _connect_row := HBoxContainer.new()


func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override(&"separation", 8)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status)
	_address.text = "" if _web else "127.0.0.1"
	_address.placeholder_text = "房號（4 碼）" if _web else "房主 IP"
	_address.custom_minimum_size = Vector2(200, 44)
	_address.add_theme_font_size_override(&"font_size", 20)
	_connect_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_connect_row.add_theme_constant_override(&"separation", 8)
	for c: Control in [_host_button, _address, _join_button]:
		_connect_row.add_child(c)
	add_child(_connect_row)
	for b: Button in [_start_button, _leave_button]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		add_child(b)
	_host_button.pressed.connect(host_pressed.emit)
	_join_button.pressed.connect(func() -> void: join_pressed.emit(_address.text.strip_edges()))
	_address.text_submitted.connect(func(t: String) -> void: join_pressed.emit(t.strip_edges()))
	_start_button.pressed.connect(start_pressed.emit)
	_leave_button.pressed.connect(leave_pressed.emit)
	show_state(&"single", [], 1, "")


# 輸入框打字中：main.gd 暫停收集遊戲輸入
func is_typing() -> bool:
	return _address.has_focus()


# mode：&"single" | &"lobby_host" | &"lobby_client" | &"connecting" | &"playing"
func show_state(p_mode: StringName, peers: Array, local_peer: int, message: String) -> void:
	mode = p_mode
	var names := ", ".join(peers.map(func(id: int) -> String: return _peer_name(peers, id, local_peer)))
	match mode:
		&"single":
			if message != "":
				_status.text = message
			elif _web:
				_status.text = "多人連線（網頁版之間）：開房，或輸入房主的房號加入"
			else:
				_status.text = "多人連線（區網）：開房，或輸入房主的 IP 加入"
		&"connecting":
			_status.text = "連線中…（房號 %s）" % room_code if _web and room_code != "" else "連線中…"
		&"lobby_host":
			if _web:
				_status.text = "房號 %s（%d / %d 人）：%s\n其他人在網頁版輸入這 4 碼加入；到齊後按「開始遊戲」\n房主不要切換分頁或縮小視窗，不然所有人都會停住" % [room_code, peers.size(), Config.NET.max_players, names]
			else:
				_status.text = "已開房（%d / %d 人）：%s\n其他人輸入這台電腦的區網 IP 加入；到齊後按「開始遊戲」" % [peers.size(), Config.NET.max_players, names]
		&"lobby_client":
			_status.text = "已加入（%d 人）：%s\n等待房主開始遊戲" % [peers.size(), names]
		&"playing":
			_status.text = "連線中（%d 人）：%s" % [peers.size(), names]
	_connect_row.visible = mode == &"single"
	if not _connect_row.visible and _address.has_focus():
		_address.release_focus()   # 打完房號 / IP 按加入後輸入框還有焦點的話，is_typing() 會一直擋住遊戲輸入
	_start_button.visible = mode == &"lobby_host"
	_leave_button.visible = mode != &"single"


static func _peer_name(peers: Array, id: int, local_peer: int) -> String:
	var label := "P%d" % (peers.find(id) + 1)
	return label + ("（你）" if id == local_peer else "")


static func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override(&"font_size", 20)
	b.custom_minimum_size = Vector2(160, 44)
	b.focus_mode = Control.FOCUS_NONE
	return b
