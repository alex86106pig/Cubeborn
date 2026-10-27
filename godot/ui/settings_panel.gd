# 設定頁（2026-10-27）：畫面（陰影、光源開關）與音量（總音量、音樂、音效）；主選單首頁與暫停畫面的「設定」打開，返回或 Esc 關掉
# 值存在 user://settings.cfg（和靜音、看過的提示同一個檔）；只發 changed 訊號，套用到音效與畫面由 main.gd 做
# 光源與陰影開關是給內顯掉幀時用的，也是遊玩紀錄的對照組：效能依設定分開統計（ui/run_log.gd）
class_name SettingsPanel
extends ColorRect

signal changed(key: String, value: Variant)

const DEFAULTS := {"shadows": true, "lights": true, "master": 1.0, "music": 1.0, "sfx": 1.0}
const SECTION := {"shadows": "video", "lights": "video", "master": "audio", "music": "audio", "sfx": "audio"}
const VOLUME_NAMES := {"master": "總音量", "music": "音樂", "sfx": "音效"}

var save_path := "user://settings.cfg"   # 測試與自動驗證設成 "" 就不讀寫檔案
var values := DEFAULTS.duplicate()
var back_button := Button.new()
var toggles: Dictionary = {}   # "shadows" / "lights" → CheckButton
var sliders: Dictionary = {}   # "master" / "music" / "sfx" → HSlider
var _percent: Dictionary = {}  # 同上 → 百分比文字


func _init() -> void:
	color = Color(5 / 255.0, 8 / 255.0, 16 / 255.0, 0.9)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 14)
	box.add_child(_centered(UiKit.label("設定", 48, Color.WHITE, 3)))
	box.add_child(_centered(UiKit.label("畫面", 28, UiKit.GOLD, 2)))
	for key: String in ["shadows", "lights"]:
		var t := CheckButton.new()
		t.text = "陰影" if key == "shadows" else "光源（精英怪、武器、出口的光）"
		t.add_theme_font_size_override(&"font_size", 22)
		t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		t.focus_mode = Control.FOCUS_NONE
		t.toggled.connect(func(on: bool) -> void: set_value(key, on))
		toggles[key] = t
		box.add_child(t)
	box.add_child(_centered(UiKit.label("內顯畫面卡頓時可以關掉試試", 16, Color(1, 1, 1, 0.7), 1)))
	box.add_child(_centered(UiKit.label("音量", 28, UiKit.GOLD, 2)))
	for key: String in VOLUME_NAMES:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override(&"separation", 16)
		var name_label := UiKit.label(VOLUME_NAMES[key], 22)
		name_label.custom_minimum_size.x = 100
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.custom_minimum_size = Vector2(360, 32)
		s.focus_mode = Control.FOCUS_NONE
		s.value_changed.connect(func(v: float) -> void: set_value(key, v))
		var pct := UiKit.label("", 22)
		pct.custom_minimum_size.x = 80
		sliders[key] = s
		_percent[key] = pct
		for c: Control in [name_label, s, pct]:
			row.add_child(c)
		box.add_child(row)
	back_button.text = "返回"
	back_button.add_theme_font_size_override(&"font_size", 22)
	back_button.custom_minimum_size = Vector2(180, 44)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.pressed.connect(hide)
	box.add_child(back_button)
	add_child(box)
	_refresh()


# 開著時 Esc 只關設定頁（不要同時切換暫停）
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"pause"):
		hide()
		get_viewport().set_input_as_handled()


func load_file() -> void:
	var cfg := ConfigFile.new()
	if save_path != "" and cfg.load(save_path) == OK:
		for key: String in DEFAULTS:
			values[key] = cfg.get_value(SECTION[key], key, DEFAULTS[key])
	_refresh()


# 改一個值：發 changed、存檔；save = false 用在啟動參數蓋掉（--shadows=0 / --lights=0，量效能用，不記住）
func set_value(key: String, value: Variant, save := true) -> void:
	if values[key] == value:
		return
	values[key] = value
	_refresh()
	changed.emit(key, value)
	if save and save_path != "":
		var cfg := ConfigFile.new()
		cfg.load(save_path)
		cfg.set_value(SECTION[key], key, value)
		cfg.save(save_path)


# 遊玩紀錄用的設定摘要：「陰影開・光源開」
func video_text() -> String:
	return "陰影%s・光源%s" % ["開" if values.shadows else "關", "開" if values.lights else "關"]


func _refresh() -> void:
	for key: String in toggles:
		toggles[key].set_pressed_no_signal(values[key])
	for key: String in sliders:
		sliders[key].set_value_no_signal(values[key])
		_percent[key].text = "%d%%" % roundi(values[key] * 100.0)


static func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
