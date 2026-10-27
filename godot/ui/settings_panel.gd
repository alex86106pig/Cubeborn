# 設定頁（2026-10-27）：畫面（陰影、光源開關）與音量（總音量、音樂、音效）；主選單首頁與暫停畫面的「設定」打開，返回或 Esc 關掉
# 值存在 user://settings.cfg（和靜音、看過的提示同一個檔）；只發 changed 訊號，套用到音效與畫面由 main.gd 做
# 光源與陰影開關是給內顯掉幀時用的，也是遊玩紀錄的對照組：效能依設定分開統計（ui/run_log.gd）
class_name SettingsPanel
extends ColorRect

signal changed(key: String, value: Variant)

const DEFAULTS := {"shadows": true, "lights": true, "master": 1.0, "music": 1.0, "sfx": 1.0}
const SECTION := {"shadows": "video", "lights": "video", "master": "audio", "music": "audio", "sfx": "audio"}
const VOLUME_NAMES := {"master": "總音量", "music": "音樂", "sfx": "音效"}
const ROW_FONT := 28
const ROW_WIDTH := 640
const SWITCH_SCALE := 1.6   # 預設的開關圖示太小不好點，放大
const SWITCH_BORDER := 2    # 開關外框粗細（像素）
const SWITCH_BORDER_COLOR := Color(1, 1, 1, 0.75)

static var _switch_icons: Dictionary = {}   # 放大加框後的開關圖示（_scale_switch）
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
	box.add_child(_centered(UiKit.label("設定", 52, Color.WHITE, 3)))
	# 每一行同寬：名稱靠左，開關 / 滑桿 + 百分比靠右，右邊對齊（2026-10-27 使用者：用原本的切換開關、靠右對齊、好點、字大）
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rows.add_theme_constant_override(&"separation", 16)
	rows.add_child(UiKit.label("畫面", 32, UiKit.GOLD, 2))
	for key: String in ["shadows", "lights"]:
		var t := CheckButton.new()   # 文字在左、開關在右，整行都點得到
		t.text = "陰影" if key == "shadows" else "光源"
		t.add_theme_font_size_override(&"font_size", ROW_FONT)
		t.custom_minimum_size = Vector2(ROW_WIDTH, 56)
		t.focus_mode = Control.FOCUS_NONE
		_scale_switch(t)
		t.toggled.connect(func(on: bool) -> void: set_value(key, on))
		toggles[key] = t
		rows.add_child(t)
	rows.add_child(UiKit.label("音量", 32, UiKit.GOLD, 2))
	for key: String in VOLUME_NAMES:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(ROW_WIDTH, 56)
		row.add_theme_constant_override(&"separation", 20)
		var name_label := UiKit.label(VOLUME_NAMES[key], ROW_FONT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.custom_minimum_size = Vector2(380, 56)
		sl.focus_mode = Control.FOCUS_NONE
		sl.value_changed.connect(func(v: float) -> void: set_value(key, v))
		var pct := UiKit.label("", ROW_FONT)
		pct.custom_minimum_size.x = 84
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sliders[key] = sl
		_percent[key] = pct
		for c: Control in [name_label, sl, pct]:
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(c)
		rows.add_child(row)
	box.add_child(rows)
	box.add_child(_centered(UiKit.label("光源 = 精英怪、稀有武器、出口的光；內顯畫面卡頓時可以關掉陰影或光源試試", 20, Color(1, 1, 1, 0.7), 1)))
	back_button.text = "返回"
	back_button.add_theme_font_size_override(&"font_size", 28)
	back_button.custom_minimum_size = Vector2(220, 60)
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


# 開關圖示放大 SWITCH_SCALE 倍並加外框（預設主題的圖示換成處理過的複本；使用者：關掉時太不明顯）
# 做一次存起來，之後每個面板共用
static func _scale_switch(t: CheckButton) -> void:
	for icon: StringName in [&"checked", &"unchecked"]:
		if not _switch_icons.has(icon):
			var img := t.get_theme_icon(icon).get_image()
			if img == null:
				continue
			img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(roundi(img.get_width() * SWITCH_SCALE), roundi(img.get_height() * SWITCH_SCALE), Image.INTERPOLATE_BILINEAR)
			_switch_icons[icon] = ImageTexture.create_from_image(_outlined(img))
		t.add_theme_icon_override(icon, _switch_icons[icon])


# 沿著圖示的形狀（不透明的部分）往外描 SWITCH_BORDER 像素的框：純色圖用圖示當遮罩、往四周各偏移貼一次，再把圖示疊回中間
static func _outlined(src: Image) -> Image:
	var pad := SWITCH_BORDER
	var rect := Rect2i(Vector2i.ZERO, src.get_size())
	var out := Image.create(src.get_width() + pad * 2, src.get_height() + pad * 2, false, Image.FORMAT_RGBA8)
	var solid := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	solid.fill(SWITCH_BORDER_COLOR)
	for dy in range(-pad, pad + 1):
		for dx in range(-pad, pad + 1):
			if dx * dx + dy * dy <= pad * pad:
				out.blit_rect_mask(solid, src, rect, Vector2i(pad + dx, pad + dy))
	out.blend_rect(src, rect, Vector2i(pad, pad))
	return out


static func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
