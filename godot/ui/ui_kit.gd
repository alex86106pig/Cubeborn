# HUD 共用的小工具：建立有陰影的文字、色塊，以及樣式顏色（照搬網頁版 css/style.css）
class_name UiKit

const SHADOW := Color(0, 0, 0, 1)
const HP_BG := Color("2a1414")
const HP_FILL := Color("e0443e")
const GHOST := Color("f5d36b")
const MANA_BG := Color("101a2e")
const MANA_FILL := Color("4a8dff")   # 魔力條、技能欄的耗魔數字、魔力詞條
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
const ITEM_WEAPON_FILL := Color("4a4f57")   # 物品畫法（draw_item）：武器的底色（鐵灰）
const ITEM_SKILL_FILL := Color("6a3f8f")    # 技能、修飾的底色
const ITEM_BAG_FILL := Color("6b5236")      # 倉庫裡的觸發袋（皮革色）
const ITEM_BIG_CELL := 60.0                 # 格子這麼大以上字大一級（背包）
const ITEM_TEXT_CELL := 40.0                # 格子這麼大以上才寫名稱（遺物卡片的小圖不寫，卡片右邊有字）
const BUTTON_CARD := {"size": Vector2(440, 230), "font": 24}   # 卡片：遺物的 N 選 1（RelicPanel；3 張約 1344 寬）
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
static func item_info(id: StringName, weapon: Dictionary, level := 1) -> Dictionary:
	if not weapon.is_empty():
		var b := WeaponDropDefs.base_stats(weapon)
		var wd: Dictionary = WeaponDefs.WEAPONS[ItemDefs.ITEMS[weapon.base].weapon]
		var hands: String = HANDS_TEXT[wd.hands] + ("，也能當副手" if wd.get("offhand", false) else "")
		var stats_line: String = ("%s · 攻擊力 %.1f · 攻速 %.2f 次/秒 · 範圍 %.1f" % [hands, b.damage, b.attack_speed, b.range]) if not b.is_empty() else hands + " · " + wd.special.name
		var lines: Array[String] = [stats_line, "普攻 %s · 右鍵 %s" % [wd.attack.get("name", "—"), wd.special.get("name", "—")] if wd.has("attack") else wd.special.get("name", "")]
		return {"title": WeaponDropDefs.display_name(weapon), "color": ItemDefs.RARITIES[weapon.rarity].color, "lines": lines}
	var def: Dictionary = ItemDefs.ITEMS[id]
	var r: Dictionary = ItemDefs.RARITIES[def.rarity]
	if def.kind == &"skill":
		var title := "%s（技能 · %d 級）" % [def.name, level] if level > 1 else "%s（技能）" % def.name
		var lines: Array[String] = [def.desc]
		if SkillDefs.SKILLS[id].has("damage_pct"):
			lines.append(skill_damage_line(id, level))
		lines.append(skill_line(id, level))
		return {"title": title, "color": GOLD, "lines": lines}
	var desc: String = def.get("desc", "")
	if not def.get("effects", []).all(ItemDefs.is_implemented):
		desc += "（效果尚未實作）"
	var bond_names: Array[String] = []
	for bond: StringName in def.get("bonds", []):
		bond_names.append(BondDefs.BONDS[bond].name)
	if def.kind == &"item":
		desc += "　· 羈絆：" + ("、".join(bond_names) if not bond_names.is_empty() else "沒有")
	var item_lines: Array[String] = [desc]
	var damage := effect_damage_line(id)
	if damage != "":
		item_lines.append(damage)
	if def.kind == &"item":
		item_lines.append(role_line(id))
	var kind_name := "技能 · " if ItemDefs.role_of(id) == ItemDefs.ROLE_EFFECT else ""
	return {"title": "%s（%s%s）" % [def.name, kind_name, r.name], "color": r.color, "lines": item_lines}


# 道具放哪裡（觸發袋的分類，ItemDefs.role_of）：數值放主袋；效果放觸發袋（寫原本的時機當建議、耗魔）；修飾放跟技能同一袋
static func role_line(id: StringName) -> String:
	match ItemDefs.role_of(id):
		ItemDefs.ROLE_EFFECT:
			var bag := ItemDefs.default_bag_of(id)
			return "技能：放進袋子，時機到了發動（適合%s）· 每次耗魔 %d" % [BagDefs.BAGS[bag].name if bag != &"" else "任何袋子", roundi(BagTriggers.effect_mana(id))]
		ItemDefs.ROLE_MOD:
			return "修飾：放進技能所在的袋子，作用在同一袋的技能"
	return "數值：放進主袋或袋子都生效"


# 技能的一行：怎麼用、標籤、耗魔（插火把這種次數制的寫次數），耗魔照等級算
static func skill_line(id: StringName, level := 1) -> String:
	var sk: Dictionary = SkillDefs.SKILLS[id]
	var tags: Array[String] = []
	for t: StringName in sk.tags:
		tags.append(SkillDefs.TAGS[t])
	var cost := "耗魔 %d" % roundi(sk.mana * SkillDefs.level_mana_mul(level)) if sk.has("mana") else "每層 %d 次" % sk.get("charges", 0)
	return "按鍵袋按數字鍵放、觸發袋自動放 · %s · %s" % ["、".join(tags) if not tags.is_empty() else "—", cost]


# 技能的傷害倍率（武器傷害的 %，已乘等級；袋子的強化另外乘）：照 SkillDefs 的資料組字，沒傷害的技能回空字串
# 例：「傷害：武器傷害 175% × 5 發」「傷害：武器傷害 150%，火堆每秒 100%（4 秒）」
static func skill_damage_line(id: StringName, level := 1) -> String:
	var sk: Dictionary = SkillDefs.SKILLS[id]
	if not sk.has("damage_pct"):
		return ""
	var mul := SkillDefs.level_damage_mul(level)
	var main := pct_text(sk.damage_pct * mul)
	var text := "傷害：武器傷害 " + main
	match sk.behavior:
		&"rain":
			text = "傷害：每 %s 秒武器傷害 %s，共 %d 次" % [String.num(sk.tick), main, roundi(sk.duration / sk.tick)]
		&"chain":
			text = "傷害：武器傷害 %s，最多打 %d 隻" % [main, sk.jumps + 1]
		_:
			if sk.get("count", 1) > 1:
				text += " × %d 發" % sk.count
	if sk.has("chain"):
		text += "，再電 %d 隻各 %s" % [sk.chain.jumps, pct_text(sk.damage_pct * mul * sk.chain.ratio)]
	if sk.has("pool"):
		text += "，火堆每秒 %s（%s 秒）" % [pct_text(sk.pool.dps_pct * mul), String.num(sk.pool.duration)]
	if sk.has("trail"):
		text += "，火痕每秒 %s（%s 秒）" % [pct_text(sk.trail.dps_pct * mul), String.num(sk.trail.duration)]
	return text


# 效果型技能（觸發道具改寫，ItemDefs.ROLE_EFFECT）的傷害：照道具資料與 ItemDefs.PROCS 組字，沒傷害的（冰冷、回血、回魔…）回空字串
# 「觸發那一下」= 命中 / 擊殺袋是那一下的傷害、受傷袋是受到的傷害；計時、翻滾、出手、按鍵袋沒有那一下，用武器傷害 100%（BagTriggers.run_effect）
static func effect_damage_line(id: StringName) -> String:
	if ItemDefs.role_of(id) != ItemDefs.ROLE_EFFECT:
		return ""
	for e: Dictionary in ItemDefs.ITEMS[id].effects:
		var p: Dictionary = ItemDefs.PROCS.get(e.get("do", &""), {})
		match e.get("do", &""):
			&"explode":
				return "傷害：觸發那一下的 %s（半徑 %s）" % [pct_text(e.get("damage_ratio", p.damage_ratio)), String.num(p.radius)]
			&"chain_lightning":
				return "傷害：觸發那一下的 %s，跳 %d 隻" % [pct_text(p.damage_ratio), e.targets]
			&"poison":
				return "傷害：%s 秒共觸發那一下的 %s" % [String.num(p.duration), pct_text(p.total_ratio)]
			&"ignite":
				return "傷害：每秒觸發那一下的 %s，%s 秒" % [pct_text(p.pct_per_sec), String.num(p.duration)]
			&"wisp":
				return "傷害：觸發那一下的 %s" % pct_text(p.damage_ratio)
			&"reflect":
				return "傷害：受到傷害的 %s" % pct_text(e.ratio)
			&"throw_knife":
				return "傷害：武器傷害 %s" % pct_text(p.damage_pct)
			&"slash_wave":
				return "傷害：武器傷害 %s × %d 道" % [pct_text(e.damage_ratio), e.count]
			&"lightning_strike":
				return "傷害：武器傷害 %s，最多 %d 隻" % [pct_text(p.damage_pct), p.targets]
	return ""


# 遺物卡的升級預覽：「升級：傷害 600% → 720% · 耗魔 27 → 24」（傷害寫主段；沒傷害的技能只寫耗魔）
static func skill_upgrade_line(id: StringName, level: int) -> String:
	var sk: Dictionary = SkillDefs.SKILLS[id]
	var parts: Array[String] = []
	if sk.has("damage_pct"):
		parts.append("傷害 %s → %s" % [pct_text(sk.damage_pct * SkillDefs.level_damage_mul(level)), pct_text(sk.damage_pct * SkillDefs.level_damage_mul(level + 1))])
	if sk.has("mana"):
		parts.append("耗魔 %d → %d" % [roundi(sk.mana * SkillDefs.level_mana_mul(level)), roundi(sk.mana * SkillDefs.level_mana_mul(level + 1))])
	return "升級：" + " · ".join(parts)


# 倍數寫成 %：6.0 → 600%、3.375 → 337.5%（不寫多餘的 0）
static func pct_text(ratio: float) -> String:
	return String.num(snappedf(ratio * 100.0, 0.1)) + "%"


# 道具形狀的小圖（不轉向）：每格 cell px，左上角在 at
static func draw_shape(ci: CanvasItem, id: StringName, at: Vector2, cell: float, color: Color, alpha := 1.0) -> void:
	for c in Inventory.cells_of(id, 0):
		var r := Rect2(at + Vector2(c) * cell, Vector2(cell, cell)).grow(-1)
		ci.draw_rect(r, Color(color.darkened(0.4), 0.9 * alpha))
		ci.draw_rect(r, Color(color, alpha), false, 1.0)


# 一件物品（背包、武器格子、遺物卡片共用）：at = 形狀外框的左上角，rot 轉向
# 底色看種類（武器鐵灰＋「武器」、技能紫色寶石＋圖示字、輔助深紫虛線框＋「輔助」、道具稀有度色）、外框看稀有度；
# 道具與有「羈絆 +1」詞條的武器在右上角畫羈絆色點（hover_bond 那個畫大一點）；格子 ≥ ITEM_BIG_CELL 時字大一級
static func draw_item(ci: CanvasItem, font: Font, id: StringName, at: Vector2, cell_px: float, rot: int, rarity: StringName, alpha: float, weapon: Dictionary = {}, hover_bond: StringName = &"") -> void:
	var def: Dictionary = ItemDefs.ITEMS[id]
	var color: Color = ItemDefs.RARITIES[rarity].color
	var kind := item_kind(id)
	var bonds := item_bonds(id, weapon)
	var rects: Array[Rect2] = []
	for c in Inventory.cells_of(id, rot):
		rects.append(Rect2(at + Vector2(c) * cell_px, Vector2(cell_px, cell_px)))
	draw_item_cells(ci, font, id, rects, rarity, alpha, weapon, hover_bond)


# 同上，但每一格的位置自己給（rects，第一格寫字）：接在主袋側邊的袋子是轉過的，格子不一定照形狀排
static func draw_item_cells(ci: CanvasItem, font: Font, id: StringName, rects: Array[Rect2], rarity: StringName, alpha: float, weapon: Dictionary = {}, hover_bond: StringName = &"") -> void:
	var def: Dictionary = ItemDefs.ITEMS[id]
	var color: Color = ItemDefs.RARITIES[rarity].color
	var kind := item_kind(id)
	var bonds := item_bonds(id, weapon)
	var cell_px := rects[0].size.x
	var round_mark := kind == &"skill" or ItemDefs.role_of(id) == ItemDefs.ROLE_EFFECT   # 大技能、小技能（原本的效果）都畫圓框：有圓框的放袋子
	var fill: Color = {&"weapon": ITEM_WEAPON_FILL, &"skill": ITEM_SKILL_FILL, &"support": ITEM_SKILL_FILL.darkened(0.4), &"bag": ITEM_BAG_FILL}.get(kind, ITEM_SKILL_FILL if round_mark else color.darkened(0.55))
	for cr in rects:
		_draw_item_cell(ci, cr, rects, Color(fill, 0.9 * alpha), Color(color, alpha), kind == &"support")
	var first: Vector2 = rects[0].position
	var big := cell_px >= ITEM_BIG_CELL
	if round_mark:
		var center := first + Vector2(cell_px, cell_px) / 2.0
		ci.draw_arc(center, cell_px * 0.34, 0.0, TAU, 20, Color(1, 1, 1, 0.45 * alpha), 1.5)
		ci.draw_string(font, first + Vector2(0, cell_px / 2.0 + (12 if big else 7)), SkillDefs.SKILLS.get(id, {}).get("icon", String(def.name).substr(0, 1)),
				HORIZONTAL_ALIGNMENT_CENTER, cell_px, 34 if big else 20, Color(1, 1, 1, alpha))
	elif cell_px >= ITEM_TEXT_CELL:
		var label_text := String(def.name).substr(0, 4 if big else 2)
		ci.draw_string(font, first + Vector2(5, cell_px * 0.36), label_text, HORIZONTAL_ALIGNMENT_LEFT, cell_px - 6, 13 if big else 15, Color(1, 1, 1, alpha))   # 大格的字級放得下 4 個字，每件都一樣大
	if kind in [&"weapon", &"support", &"bag"] and cell_px >= ITEM_TEXT_CELL:
		ci.draw_string(font, first + Vector2(6, cell_px - 9), {&"weapon": "武器", &"support": "修飾", &"bag": "袋子"}[kind], HORIZONTAL_ALIGNMENT_LEFT, -1, 13 if big else 11, Color(1, 1, 1, 0.6 * alpha))
	var dot_scale := 1.5 if big else 1.0
	for i in bonds.size():
		var dot_r := (5.0 if bonds[i] == hover_bond else 3.5) * dot_scale
		var dot_y := cell_px - 9.0 * dot_scale if big else 9.0 * dot_scale   # 大格的名稱佔滿上面一行，色點放下面
		ci.draw_circle(first + Vector2(cell_px - 9.0 * dot_scale * (i + 1), dot_y), dot_r, Color(BondDefs.BONDS[bonds[i]].color, alpha))


# 物品的一格：相鄰的邊不留縫、外圈才描邊，多格物品看起來是一整塊
static func _draw_item_cell(ci: CanvasItem, cr: Rect2, rects: Array[Rect2], fill: Color, line: Color, dashed: bool) -> void:
	const INSET := 3.0
	var step := cr.size.x
	var l := 0.0 if _has_cell(rects, cr.position - Vector2(step, 0)) else INSET
	var r := 0.0 if _has_cell(rects, cr.position + Vector2(step, 0)) else INSET
	var t := 0.0 if _has_cell(rects, cr.position - Vector2(0, step)) else INSET
	var b := 0.0 if _has_cell(rects, cr.position + Vector2(0, step)) else INSET
	var body := Rect2(cr.position + Vector2(l, t), cr.size - Vector2(l + r, t + b))
	ci.draw_rect(body, fill)
	var corners: Array[Vector2] = [body.position, Vector2(body.end.x, body.position.y), body.end, Vector2(body.position.x, body.end.y)]
	for side: int in [0, 1, 2, 3]:
		if [t, r, b, l][side] <= 0.0:
			continue
		if dashed:
			ci.draw_dashed_line(corners[side], corners[(side + 1) % 4], line, 2.0, 6.0)
		else:
			ci.draw_line(corners[side], corners[(side + 1) % 4], line, 2.0)


static func _has_cell(rects: Array[Rect2], at: Vector2) -> bool:
	for x in rects:
		if x.position.is_equal_approx(at):
			return true
	return false


# 畫法用的種類：weapon / skill / support（修飾是 kind item、有 skill_support 能力）/ item / bag / corpse
static func item_kind(id: StringName) -> StringName:
	var kind: StringName = ItemDefs.ITEMS[id].kind
	if kind == &"item" and not ItemDefs.support_of(id).is_empty():
		return &"support"
	return kind


# 物品屬於哪些羈絆（道具資料；武器沒有）
static func item_bonds(id: StringName, weapon: Dictionary = {}) -> Array:
	return [] if not weapon.is_empty() else ItemDefs.ITEMS[id].get("bonds", [])


static func draw_dashed_rect(ci: CanvasItem, r: Rect2, color: Color) -> void:
	var corners: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		ci.draw_dashed_line(corners[i], corners[(i + 1) % 4], color, 2.0, 6.0)


# 形狀小圖的大小（px）
static func shape_size(id: StringName, cell: float) -> Vector2:
	var hi := Vector2i.ZERO
	for c in Inventory.cells_of(id, 0):
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	return Vector2(hi + Vector2i.ONE) * cell
