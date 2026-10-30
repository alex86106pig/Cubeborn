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
const SOUL := Color("7fe3ff")     # 靈魂（局內貨幣）的字色；金幣（局外）用 GOLD
const DIG_BG := Color("241c0c")   # 挖墳進度條的底色
const HEAL := Color("6cff7a")
const PLAYER_HURT := Color("ff5050")
const CHARGES := Color("9cff9c")
const SLOT_BG := Color(20 / 255.0, 24 / 255.0, 36 / 255.0, 0.85)
const SLOT_OUTLINE := Color(1, 1, 1, 0.15)
const DENY := Color("ff4040")
# 選單類畫面（主選單、暫停、設定、連線面板）的字級，各畫面共用（2026-10-27 使用者：標題畫面、Esc 選單的字有大有小）
const FONT_TITLE := 52     # 頁面標題（已暫停、選擇職業、設定）
const FONT_HEADING := 32   # 段落標題（畫面、音量）
const FONT_BODY := 28      # 按鈕、選項、主要文字
const FONT_NOTE := 20      # 說明、提示、版號
# 選單的壓黑底色（暫停、主選單、設定頁共用；2026-10-27 使用者：Esc → 回主選單時背景又暗一次，原本 0.65 / 0.82 / 0.9 各不同）
const MENU_DIM := Color(5 / 255.0, 8 / 255.0, 16 / 255.0, 0.8)
# 按鈕三種尺寸（2026-10-27 使用者：按鈕標準化）：UiKit.button(文字, UiKit.BUTTON_?)
const BUTTON_L := {"size": Vector2(280, 60), "font": FONT_BODY}   # 選單：主選單、暫停畫面、設定頁、結算畫面
const BUTTON_M := {"size": Vector2(200, 52), "font": 24}          # 面板裡的操作：連線面板（開房、加入、選職業、準備）
const BUTTON_S := {"size": Vector2(120, 44), "font": FONT_NOTE}   # 一排很多顆的：武器測試場的武器列
const BUTTON_CARD := {"size": Vector2(320, 150), "font": FONT_NOTE}   # 卡片：遺物的 N 選 1（RelicPanel）
const BUTTON_BG := {&"normal": Color(0.12, 0.14, 0.2, 0.85), &"hover": Color(0.22, 0.26, 0.36, 0.95),
	&"pressed": Color(0.32, 0.38, 0.52, 1.0), &"disabled": Color(0.1, 0.1, 0.12, 0.6)}


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


# 標準按鈕：kind 是 BUTTON_L / BUTTON_M / BUTTON_S；有底色與框（原本武器測試場的樣式，預設的太淡像文字）、置中、不搶鍵盤焦點
static func button(text: String, kind: Dictionary = BUTTON_L) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override(&"font_size", kind.font)
	b.custom_minimum_size = kind.size
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	for state: StringName in BUTTON_BG:
		var box := StyleBoxFlat.new()
		box.bg_color = BUTTON_BG[state]
		box.border_color = Color(1, 1, 1, 0.35 if state != &"disabled" else 0.15)
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.set_content_margin_all(8)
		b.add_theme_stylebox_override(state, box)
	b.add_theme_stylebox_override(&"hover_pressed", b.get_theme_stylebox(&"pressed"))
	return b


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


# 傷害、治療、統計數字的顯示（v0.41.0）：模擬保留小數，畫面四捨五入；0.4 這種還有傷害的至少顯示 1
static func dmg_text(amount: float) -> String:
	return str(maxi(roundi(amount), 1 if amount > 0.0 else 0))


# 血量的顯示：無條件進位，還活著（剩 0.4）就不會顯示 0；1e-4 以下的浮點誤差不進位
static func hp_text(hp: float) -> String:
	return str(ceili(hp - 1e-4))


static func format_time(seconds: float) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), floori(fmod(seconds, 60.0))]


const HANDS_TEXT := {&"one": "單手", &"two": "雙手", &"off": "副手"}


# 道具 / 武器的說明（地上的道具卡、背包的說明欄共用）：{ title, color, lines }
# weapon 是武器實例（WeaponDropDefs）時顯示拿法、基本數值與詞條，否則顯示道具效果
static func item_info(id: StringName, weapon: Dictionary) -> Dictionary:
	if not weapon.is_empty():
		var b := WeaponDropDefs.base_stats(weapon)
		var affixes: Array[String] = []
		for a: StringName in weapon.affixes:
			affixes.append(WeaponDropDefs.AFFIXES[a].desc)
		var wd: Dictionary = WeaponDefs.WEAPONS[ItemDefs.ITEMS[weapon.base].weapon]
		var hands: String = HANDS_TEXT[wd.hands] + ("，也能當副手" if wd.get("offhand", false) else "")
		var stats_line: String = ("%s · 攻擊力 %.1f · 攻速 %.2f 次/秒 · 範圍 %.1f" % [hands, b.damage, b.attack_speed, b.range]) if not b.is_empty() else hands + " · " + wd.special.name
		var lines: Array[String] = [stats_line, "沒有詞條" if affixes.is_empty() else "詞條：" + " · ".join(affixes)]
		return {"title": WeaponDropDefs.display_name(weapon), "color": ItemDefs.RARITIES[weapon.rarity].color, "lines": lines}
	var def: Dictionary = ItemDefs.ITEMS[id]
	var r: Dictionary = ItemDefs.RARITIES[def.rarity]
	var desc: String = def.get("desc", "")
	if not def.get("effects", []).all(ItemDefs.is_implemented):
		desc += "（效果尚未實作）"
	var bond_names: Array[String] = []
	for bond: StringName in def.get("bonds", []):
		bond_names.append(BondDefs.BONDS[bond].name)
	if def.kind == &"item":
		desc += "　· 羈絆：" + ("、".join(bond_names) if not bond_names.is_empty() else "沒有")
	var item_lines: Array[String] = [desc]
	return {"title": "%s（%s）" % [def.name, r.name], "color": r.color, "lines": item_lines}


# 道具形狀的小圖（不轉向）：每格 cell px，左上角在 at
static func draw_shape(ci: CanvasItem, id: StringName, at: Vector2, cell: float, color: Color, alpha := 1.0) -> void:
	for c in Inventory.cells_of(id, 0):
		var r := Rect2(at + Vector2(c) * cell, Vector2(cell, cell)).grow(-1)
		ci.draw_rect(r, Color(color.darkened(0.4), 0.9 * alpha))
		ci.draw_rect(r, Color(color, alpha), false, 1.0)


# 形狀小圖的大小（px）
static func shape_size(id: StringName, cell: float) -> Vector2:
	var hi := Vector2i.ZERO
	for c in Inventory.cells_of(id, 0):
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	return Vector2(hi + Vector2i.ONE) * cell
