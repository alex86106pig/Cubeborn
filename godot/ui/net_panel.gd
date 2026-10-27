# 連線面板：開房、加入（房號或 IP，看 method）、大廳名單、開始遊戲、離開連線
# 平常放在主選單的多人頁；遊戲中放在 Esc 選單（只有連線中才顯示，v0.39.0）
# 大廳的選職業、準備、開始遊戲在選角畫面（ui/class_select.gd）；這裡只顯示房號 / 人數與離開連線
# 只發訊號，實際連線由 main.gd 處理
class_name NetPanel
extends VBoxContainer

signal host_pressed
signal join_pressed(address: String)
signal leave_pressed

var room_code := ""   # 房號連線：房主的房號（main.gd 在 show_state 前設定）
var mode: StringName = &"single"   # 最後一次 show_state 的狀態
var method: StringName = &"room"   # 連線方式（v0.40.0，主選單選）：&"room" 房號 | &"ip" 區網 IP
var _status := UiKit.label("", UiKit.FONT_NOTE, Color(1, 1, 1, 0.9))
var _address := LineEdit.new()
var _host_button := _button("開房")
var _join_button := _button("加入")
var _leave_button := _button("離開連線")
var _connect_row := HBoxContainer.new()


func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override(&"separation", 8)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status)
	_address.custom_minimum_size = Vector2(220, UiKit.BUTTON_M.size.y)
	_address.add_theme_font_size_override(&"font_size", UiKit.BUTTON_M.font)
	_connect_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_connect_row.add_theme_constant_override(&"separation", 8)
	for c: Control in [_host_button, _address, _join_button]:
		_connect_row.add_child(c)
	add_child(_connect_row)
	_leave_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_leave_button)
	_host_button.pressed.connect(host_pressed.emit)
	_join_button.pressed.connect(func() -> void: join_pressed.emit(_address.text.strip_edges()))
	_address.text_submitted.connect(func(t: String) -> void: join_pressed.emit(t.strip_edges()))
	_leave_button.pressed.connect(leave_pressed.emit)
	set_method(&"room" if not NetSession.ip_supported() else &"ip")


# 換連線方式：輸入框的提示與預設值跟著換（房號 4 碼 / 房主 IP）
func set_method(m: StringName) -> void:
	method = m
	_host_button.text = "開房（房號）" if m == &"room" else "開房（區網）"
	_address.text = "" if m == &"room" else "127.0.0.1"
	_address.placeholder_text = "房號（4 碼）" if m == &"room" else "房主 IP"
	show_state(&"single", [], 1, "")


# 輸入框打字中：main.gd 暫停收集遊戲輸入
func is_typing() -> bool:
	return _address.has_focus()


# mode：&"single" | &"lobby_host" | &"lobby_client" | &"connecting" | &"playing"
# choices：大廳選擇（NetSession.lobby_choices，peer id → [職業, 準備好了]）；沒有就只列名字
func show_state(p_mode: StringName, peers: Array, local_peer: int, message: String, choices: Dictionary = {}) -> void:
	mode = p_mode
	var room := method == &"room"
	var in_lobby := mode == &"lobby_host" or mode == &"lobby_client"
	var names := ", ".join(peers.map(func(id: int) -> String: return _peer_name(peers, id, local_peer, choices if in_lobby else {})))
	match mode:
		&"single":
			if message != "":
				_status.text = message
			elif room:
				_status.text = "房號連線（要連上網路，電腦版和網頁版可以一起玩）：開房，或輸入房主的房號加入"
			else:
				_status.text = "區網連線：開房，或輸入房主的 IP 加入"
		&"connecting":
			_status.text = "連線中…（房號 %s）" % room_code if room and room_code != "" else "連線中…"
		&"lobby_host":
			if room:
				_status.text = "房號 %s（%d / %d 人）：%s\n其他人選「房號連線」輸入這 4 碼加入（電腦版、網頁版都可以）" % [room_code, peers.size(), Config.NET.max_players, names]
				if OS.has_feature("web"):
					_status.text += "\n房主不要切換分頁或縮小視窗，不然所有人都會停住"
			else:
				_status.text = "已開房（%d / %d 人）：%s\n其他人輸入這台電腦的區網 IP 加入" % [peers.size(), Config.NET.max_players, names]
		&"lobby_client":
			_status.text = "已加入（%d 人）：%s\n等待房主開始遊戲" % [peers.size(), names]
		&"playing":
			_status.text = "連線中（%d 人）：%s" % [peers.size(), names]
	_connect_row.visible = mode == &"single"
	if not _connect_row.visible and _address.has_focus():
		_address.release_focus()   # 打完房號 / IP 按加入後輸入框還有焦點的話，is_typing() 會一直擋住遊戲輸入
	_leave_button.visible = mode != &"single"


# 「P2 祕術師（準備好了）（你）」：大廳時帶職業與準備狀態（房主一律算準備好）
static func _peer_name(peers: Array, id: int, local_peer: int, choices: Dictionary = {}) -> String:
	var label := "P%d" % (peers.find(id) + 1)
	if choices.has(id) and ClassDefs.CLASSES.has(StringName(choices[id][0])):
		label += " " + ClassDefs.CLASSES[StringName(choices[id][0])].name
		label += "（準備好了）" if id == World.HOST_PEER_ID or choices[id][1] else "（還沒準備）"
	return label + ("（你）" if id == local_peer else "")


static func _button(text: String) -> Button:
	return UiKit.button(text, UiKit.BUTTON_M)
