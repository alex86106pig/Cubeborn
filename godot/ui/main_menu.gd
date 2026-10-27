# 主選單（v0.39.0，想法清單 #14）：開場畫面。首頁有單人遊戲、多人遊戲、離開遊戲（網頁版不顯示）；
# 選連線方式頁（v0.40.0，只有桌面版）：房號連線（網路，可和網頁版一起玩）/ IP 連線（區網）；
# 多人頁放連線面板（開房 / 加入 / 大廳，HUD 把 net_panel 搬進 net_slot）與返回。只發訊號，流程由 main.gd 處理
# 單人遊戲先到選職業頁（F2）：每個職業一張卡（起始武器、介紹、被動、和基準不同的數值），按職業名稱開始
class_name MainMenu
extends ColorRect

signal single_pressed(class_id: StringName)
signal method_chosen(method: StringName)   # 選了連線方式（&"room" / &"ip"），接著顯示多人頁
signal back_pressed   # 多人頁按「返回」（還在大廳時 main.gd 先離開連線）
signal quit_pressed
signal weapon_test_pressed   # 首頁「武器測試場」（2026-10-27）
signal settings_pressed      # 首頁「設定」（2026-10-27，HUD 打開設定頁）

const CARD_COLUMNS := 4   # 選職業頁：每排幾張、卡片寬、間距（寬度 = 4 × 400 + 3 × 40 = 1720，檢查用它算介面最大檔放不放得下）
const CARD_WIDTH := 400
const CARD_GAP := 40

var page: StringName = &"home"   # &"home" | &"class" | &"method" | &"multi"
var net_slot := VBoxContainer.new()   # 多人頁放連線面板的位置
var single_button := _button("單人遊戲")
var multi_button := _button("多人遊戲")
var quit_button := _button("離開遊戲")
var weapon_test_button := _button("武器測試場")
var settings_button := _button("設定")
var room_button := _button("房號連線")
var ip_button := _button("IP 連線")
var method_back_button := _button("返回")
var back_button := _button("返回")
var class_back_button := _button("返回")
var class_buttons: Dictionary = {}   # 職業 id → 按鈕
var _home := VBoxContainer.new()
var _class := VBoxContainer.new()
var _method := VBoxContainer.new()
var _multi := VBoxContainer.new()


func _init() -> void:
	color = Color(5 / 255.0, 8 / 255.0, 16 / 255.0, 0.82)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # 按鈕與輸入框要能點，也擋住底下的遊戲
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 12)
	var title := UiKit.label("Cubeborn", 96, Color.WHITE, 5)
	var version := UiKit.label("v" + GameVersion.VERSION, UiKit.FONT_NOTE, Color(1, 1, 1, 0.6), 1)
	for l: Label in [title, version]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	box.add_child(_spacer(40))
	for b: Button in [single_button, multi_button, weapon_test_button, settings_button, quit_button]:
		_home.add_child(b)
	quit_button.visible = not OS.has_feature("web")   # 瀏覽器不允許網頁自己關閉

	_class.add_child(_heading("選擇職業"))
	var cards := GridContainer.new()   # 每排 4 張（7 個職業排兩排，塞得進 1920 寬）
	cards.columns = CARD_COLUMNS
	cards.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cards.add_theme_constant_override(&"h_separation", CARD_GAP)
	cards.add_theme_constant_override(&"v_separation", 24)
	for id: StringName in ClassDefs.ORDER:
		cards.add_child(_class_card(id))
	_class.add_child(cards)
	_class.add_child(_spacer(12))
	_class.add_child(class_back_button)

	_method.add_child(_heading("選擇連線方式"))
	var room_ok := NetSession.room_supported()
	room_button.disabled = not room_ok
	_method.add_child(room_button)
	_method.add_child(_note("要連上網路；輸入 4 碼房號加入，電腦版和網頁版可以一起玩" if room_ok else "缺少 WebRTC 擴充（addons/webrtc_native），不能用房號"))
	_method.add_child(_spacer(8))
	_method.add_child(ip_button)
	_method.add_child(_note("區網或虛擬區網（Radmin VPN、ZeroTier…）；輸入房主的 IP 加入，只有電腦版"))
	_method.add_child(_spacer(12))
	_method.add_child(method_back_button)

	_multi.add_child(_heading("多人遊戲"))
	_multi.add_child(net_slot)
	_multi.add_child(_spacer(12))
	_multi.add_child(back_button)
	for v: VBoxContainer in [_home, _class, _method, _multi]:
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override(&"separation", 14)
		box.add_child(v)
	add_child(box)
	single_button.pressed.connect(show_page.bind(&"class"))
	class_back_button.pressed.connect(show_page.bind(&"home"))
	# 網頁版只有房號，直接進多人頁
	multi_button.pressed.connect(func() -> void:
		if NetSession.ip_supported():
			show_page(&"method")
		else:
			_choose(&"room"))
	room_button.pressed.connect(_choose.bind(&"room"))
	ip_button.pressed.connect(_choose.bind(&"ip"))
	method_back_button.pressed.connect(show_page.bind(&"home"))
	quit_button.pressed.connect(quit_pressed.emit)
	weapon_test_button.pressed.connect(weapon_test_pressed.emit)
	settings_button.pressed.connect(settings_pressed.emit)
	back_button.pressed.connect(back_pressed.emit)
	show_page(&"home")


func show_page(p: StringName) -> void:
	page = p
	_home.visible = p == &"home"
	_class.visible = p == &"class"
	_method.visible = p == &"method"
	_multi.visible = p == &"multi"


func _choose(m: StringName) -> void:
	method_chosen.emit(m)
	show_page(&"multi")


# 職業卡：按鈕（職業名稱）+ 起始武器、介紹、被動、和基準不同的數值
func _class_card(id: StringName) -> VBoxContainer:
	var c: Dictionary = ClassDefs.CLASSES[id]
	var card := VBoxContainer.new()
	card.add_theme_constant_override(&"separation", 8)
	var b := _button(c.name)
	b.pressed.connect(single_pressed.emit.bind(id))
	class_buttons[id] = b
	card.add_child(b)
	var lines: Array[String] = ["起始武器：" + WeaponDefs.WEAPONS[c.weapon].name, c.pitch, "被動：" + c.passive.desc]
	var stat_parts: Array[String] = []
	for stat: StringName in c.stats:
		stat_parts.append("%s %s" % [StatDefs.STATS[stat].name, StatDefs.format_value(stat, c.stats[stat])])
	lines.append("、".join(stat_parts))
	for line in lines:
		var l := _note(line)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(CARD_WIDTH, 0)   # 360 時「。」「）」會被折到下一行單獨掛著（2026-10-27 網頁版實測）
		card.add_child(l)
	return card


static func _heading(text: String) -> Label:
	var l := UiKit.label(text, UiKit.FONT_TITLE, Color.WHITE, 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func _note(text: String) -> Label:
	var l := UiKit.label(text, UiKit.FONT_NOTE, Color(1, 1, 1, 0.75), 1)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func _button(text: String) -> Button:
	return UiKit.button(text)


static func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
