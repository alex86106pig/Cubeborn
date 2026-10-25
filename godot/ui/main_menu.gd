# 主選單（v0.39.0，想法清單 #14）：開場畫面。首頁有單人遊戲、多人遊戲、離開遊戲（網頁版不顯示）；
# 多人頁放連線面板（開房 / 加入 / 大廳，HUD 把 net_panel 搬進 net_slot）與返回。只發訊號，流程由 main.gd 處理
class_name MainMenu
extends ColorRect

signal single_pressed
signal back_pressed   # 多人頁按「返回」（還在大廳時 main.gd 先離開連線）
signal quit_pressed

var page: StringName = &"home"   # &"home" | &"multi"
var net_slot := VBoxContainer.new()   # 多人頁放連線面板的位置
var single_button := _button("單人遊戲")
var multi_button := _button("多人遊戲")
var quit_button := _button("離開遊戲")
var back_button := _button("返回")
var _home := VBoxContainer.new()
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
	var version := UiKit.label("v" + GameVersion.VERSION, 16, Color(1, 1, 1, 0.6), 1)
	for l: Label in [title, version]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	box.add_child(_spacer(40))
	for b: Button in [single_button, multi_button, quit_button]:
		_home.add_child(b)
	quit_button.visible = not OS.has_feature("web")   # 瀏覽器不允許網頁自己關閉
	var multi_title := UiKit.label("多人遊戲", 36, Color.WHITE, 3)
	multi_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_multi.add_child(multi_title)
	_multi.add_child(net_slot)
	_multi.add_child(_spacer(12))
	_multi.add_child(back_button)
	for v: VBoxContainer in [_home, _multi]:
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override(&"separation", 14)
		box.add_child(v)
	add_child(box)
	single_button.pressed.connect(single_pressed.emit)
	multi_button.pressed.connect(show_page.bind(&"multi"))
	quit_button.pressed.connect(quit_pressed.emit)
	back_button.pressed.connect(back_pressed.emit)
	show_page(&"home")


func show_page(p: StringName) -> void:
	page = p
	_home.visible = p == &"home"
	_multi.visible = p == &"multi"


static func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override(&"font_size", 26)
	b.custom_minimum_size = Vector2(280, 56)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	return b


static func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
