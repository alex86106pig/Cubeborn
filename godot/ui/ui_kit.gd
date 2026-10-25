# HUD 共用的小工具：建立有陰影的文字、色塊，以及樣式顏色（照搬網頁版 css/style.css）
class_name UiKit

const SHADOW := Color(0, 0, 0, 1)
const HP_BG := Color("2a1414")
const HP_FILL := Color("e0443e")
const GHOST := Color("f5d36b")
const BORDER := Color("111111")
const BOSS_BG := Color("1a0a0a")
const BOSS_FILL := Color("8f3ad8")
const BOSS_FILL_ENRAGED := Color("d03030")
const BOSS_NAME_ENRAGED := Color("ff7070")
const ALERT := Color("ff6b6b")
const GOLD := Color("ffd84a")
const DIG_BG := Color("241c0c")   # 挖墳進度條的底色
const HEAL := Color("6cff7a")
const PLAYER_HURT := Color("ff5050")
const CHARGES := Color("9cff9c")
const SLOT_BG := Color(20 / 255.0, 24 / 255.0, 36 / 255.0, 0.85)
const SLOT_OUTLINE := Color(1, 1, 1, 0.15)
const DENY := Color("ff4040")


static func label(text: String, size: int, color: Color = Color.WHITE, shadow_px: int = 2) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_shadow_color", SHADOW)
	l.add_theme_constant_override(&"shadow_offset_x", 0)
	l.add_theme_constant_override(&"shadow_offset_y", shadow_px)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func rect(color: Color, size: Vector2 = Vector2.ZERO) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# 水平條（底色 + 殘影 + 實際值 + 置中文字）；回傳 { root, ghost, fill, text }
static func bar(size: Vector2, bg: Color, fill: Color, border: int) -> Dictionary:
	var root := rect(BORDER, size + Vector2(border, border) * 2.0)
	var inner := rect(bg)
	inner.position = Vector2(border, border)
	inner.size = size
	root.add_child(inner)
	var ghost := rect(GHOST)
	ghost.size = size
	inner.add_child(ghost)
	var fill_rect := rect(fill)
	fill_rect.size = size
	inner.add_child(fill_rect)
	var text := label("", 14)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.size = size
	inner.add_child(text)
	return {"root": root, "ghost": ghost, "fill": fill_rect, "text": text, "width": size.x}


static func format_time(seconds: float) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), floori(fmod(seconds, 60.0))]
