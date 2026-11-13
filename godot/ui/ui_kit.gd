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
const RICH_TYPES := {"閃電": Color("e8e06a"), "中毒": Color("8fd35f")}   # 說明文字染色：不是羈絆的傷害類型（羈絆名稱用 BondDefs 的顏色）
const RICH_ATTRS: Array[String] = ["移速", "攻速", "攻擊力", "最大生命", "生命", "最大魔力", "回魔", "魔力", "耗魔", "傷害", "爆擊", "閃避", "範圍"]
const RICH_ATTR_COLOR := Color("9fd8c8")
static var _rich_re: RegEx
static var _rich_colors := {}
const ITEM_WEAPON_FILL := Color("2b2d33")   # 物品畫法（draw_item）：武器的底色，剪影才看得清楚
const WEAPON_GLOW := {&"green": 3.0, &"blue": 4.0, &"purple": 5.0, &"orange": 7.0}   # 武器外圈光暈的粗細：越稀有越粗，白色不發光
const ITEM_TINT_DARK := 0.65               # 數值、技能、袋子的底色：稀有度色壓暗這麼多
const ITEM_MOD_DARK := 0.82                 # 修飾的底色比較暗，虛線才明顯
const ITEM_FADE_BG := Color("17181c")       # 技能變淡時混向的底色（圓和線會重疊，不能用半透明）
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


# 一段文字裡要染色的字：數字（金色）、羈絆與傷害類型（各自的顏色）、屬性（淺青）；回傳 [[文字, 顏色], ...]
static func rich_runs(text: String, base: Color) -> Array:
	if _rich_re == null:
		for bond: StringName in BondDefs.BONDS:
			_rich_colors[String(BondDefs.BONDS[bond].name)] = BondDefs.BONDS[bond].color
		_rich_colors.merge(RICH_TYPES)
		for word: String in RICH_ATTRS:
			_rich_colors[word] = RICH_ATTR_COLOR
		var words: Array = _rich_colors.keys()
		words.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())   # 長的先比：「最大生命」不會被拆成「生命」
		_rich_re = RegEx.create_from_string("[+\\-−×]?\\d+(?:\\.\\d+)?\\s*(?:%|秒|格|倍|層|次|點|件)?|" + "|".join(words))   # 單位跟著數字一起染
	var runs: Array = []
	var from := 0
	for m in _rich_re.search_all(text):
		if m.get_start() > from:
			runs.append([text.substr(from, m.get_start() - from), base])
		runs.append([m.get_string(), _rich_colors.get(m.get_string(), GOLD)])
		from = m.get_end()
	if from < text.length():
		runs.append([text.substr(from), base])
	return runs


# 畫染色的多行文字（中文可以在任何字換行），at 是左上角；ci 給 null 時只量高度。回傳總高度
static func draw_rich_lines(ci: CanvasItem, font: Font, at: Vector2, lines: Array, width: float, font_size: int, base := Color(1, 1, 1, 0.88)) -> float:
	var line_h := font.get_height(font_size)
	var y := 0.0
	for line: String in "\n".join(lines).split("\n"):
		var x := 0.0
		y += line_h
		for run: Array in rich_runs(line, base):
			var rest: String = run[0]
			while rest != "":
				var n := _fit_chars(font, rest, width - x, font_size)
				if n == 0 and x > 0.0:
					x = 0.0
					y += line_h
					continue
				n = maxi(n, 1)
				var part := rest.substr(0, n)
				if ci != null:
					ci.draw_string(font, at + Vector2(x, y - font.get_descent(font_size)), part, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, run[1])
				x += font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				rest = rest.substr(n)
				if rest != "":
					x = 0.0
					y += line_h
	return y


# room 寬度放得下 text 的前幾個字
static func _fit_chars(font: Font, text: String, room: float, font_size: int) -> int:
	var low := 0
	var high := text.length()
	while low < high:
		var mid := (low + high + 1) / 2
		if font.get_string_size(text.substr(0, mid), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= room:
			low = mid
		else:
			high = mid - 1
	return low


# 道具 / 武器的說明（地上的道具卡、背包的浮動說明共用）：{ title, color, lines }；標題 = 名稱（種類 · 稀有度）
# weapon 是武器實例（WeaponDropDefs）時顯示近戰 / 遠程、基本數值與詞條，否則顯示道具效果
static func item_info(id: StringName, weapon: Dictionary, level := 1) -> Dictionary:
	if not weapon.is_empty():
		var b := WeaponDropDefs.base_stats(weapon)
		var wd: Dictionary = WeaponDefs.WEAPONS[ItemDefs.ITEMS[weapon.base].weapon]
		var hands := weapon_tags_text(wd)
		var stats_line: String = ("%s · 攻擊力 %.1f · 攻速 %.2f 次/秒 · 範圍 %.1f" % [hands, b.damage, b.attack_speed, b.range]) if not b.is_empty() else hands + " · " + wd.special.name
		var lines: Array[String] = [stats_line]
		if not b.is_empty():
			lines.append("法術強度 %.1f · 最大魔力 %d · 回魔 %.1f/秒" % [b.spell_power, roundi(b.max_mana), b.mana_regen])
		lines.append("普攻 %s · 右鍵 %s" % [wd.attack.get("name", "—"), wd.special.get("name", "—")] if wd.has("attack") else wd.special.get("name", ""))
		lines.append("左鍵每 %d 下觸發一次命中 / 出手袋" % wd.get("trigger_every", 1))
		var hung: Array = Loadout.weapon_bags(weapon)
		if not hung.is_empty():   # 倉庫 / 地上的武器帶著的左右鍵袋子：換上時接回左右兩邊
			lines.append("掛著：" + "、".join(PackedStringArray(hung.map(func(x: Dictionary) -> String: return "%s（%s）" % [BagDefs.bag_name(x), BagDefs.SIDES[x.side].name]))))
		return {"title": "%s（武器 · %s）" % [WeaponDropDefs.display_name(weapon), ItemDefs.RARITIES[weapon.rarity].name], "color": ItemDefs.RARITIES[weapon.rarity].color, "lines": lines}
	var def: Dictionary = ItemDefs.ITEMS[id]
	var r: Dictionary = ItemDefs.RARITIES[def.rarity]
	if def.kind == &"skill":
		var title := "%s（技能 · %s · %d 級）" % [def.name, r.name, level] if level > 1 else "%s（技能 · %s）" % [def.name, r.name]
		var lines: Array[String] = [def.desc]
		if SkillDefs.SKILLS[id].has("damage_pct"):
			lines.append(skill_damage_line(id, level))
		lines.append(skill_line(id, level))
		return {"title": title, "color": r.color, "lines": lines}
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
	var kind_name: String = {ItemDefs.ROLE_STAT: "數值 · ", ItemDefs.ROLE_EFFECT: "技能 · ", ItemDefs.ROLE_MOD: "修飾 · "}.get(ItemDefs.role_of(id), "袋子 · " if def.kind == &"bag" else "")
	return {"title": "%s（%s%s）" % [def.name, kind_name, r.name], "color": r.color, "lines": item_lines}


# 武器的標籤（WeaponDefs.TAGS）：說明的第一欄，例「近戰、盾」
static func weapon_tags_text(wd: Dictionary) -> String:
	var names: Array[String] = []
	for t: StringName in wd.tags:
		names.append(WeaponDefs.TAGS[t])
	return "、".join(names)


# 道具放哪裡（觸發袋的分類，ItemDefs.role_of）：數值放主袋；效果放觸發袋（寫原本的時機當建議、耗魔）；修飾的透明格蓋在技能上
static func role_line(id: StringName) -> String:
	match ItemDefs.role_of(id):
		ItemDefs.ROLE_EFFECT:
			var bag := ItemDefs.default_bag_of(id)
			return "技能：放進袋子，時機到了發動（適合%s）· 每次耗魔 %d" % [BagDefs.BAGS[bag].name if bag != &"" else "任何袋子", roundi(BagTriggers.effect_mana(id))]
		ItemDefs.ROLE_MOD:
			return "修飾：%s蓋在技能上，只強化蓋住的那個（拿起來時亮起的技能蓋得到）" % ("整件是透明格，" if Inventory.cells_of(id, 0).size() == 1 else "左上角有三角的那格是透明格，")
	return "數值：放進主袋或袋子都生效"


# 手上的武器放不出這個技能時的一行（放得出來、或不是技能回空字串）
static func weapon_miss_line(id: StringName, player: Player) -> String:
	if not ItemDefs.is_skill(id) or SkillDefs.fits_weapon(SkillDefs.SKILLS[id], player.weapon):
		return ""
	return "手上的%s放不出來：要%s武器" % [player.weapon.name, WeaponDefs.TAGS[SkillDefs.SKILLS[id].needs]]


# 武器不符、蓋著幻影時的一行（ActiveSlots.slot_of 的 phantom）
static func phantom_line() -> String:
	var mana := ItemDefs.ITEMS[ActiveSlots.PHANTOM_ID].power * SkillDefs.SUPPORT_MANA
	return "幻影放出：傷害 %d%%、耗魔 +%d%%" % [roundi(SkillDefs.PHANTOM_MUL * 100.0), roundi(mana * 100.0)]


# 技能的一行：怎麼用、類別與武器需求、標籤、耗魔（次數制的寫次數），耗魔照等級算
static func skill_line(id: StringName, level := 1) -> String:
	var sk: Dictionary = SkillDefs.SKILLS[id]
	var tags: Array[String] = []
	for t: StringName in sk.tags:
		tags.append(SkillDefs.TAGS[t])
	var cost := "耗魔 %d" % roundi(sk.mana * SkillDefs.level_mana_mul(level)) if sk.has("mana") else "每層 %d 次" % sk.get("charges", 0)
	var kind: String = SkillDefs.CATEGORIES[sk.category]
	if sk.has("needs"):
		kind += "（要%s武器）" % WeaponDefs.TAGS[sk.needs]
	return "按鍵袋按數字鍵放、觸發袋自動放 · %s · %s · %s" % [kind, "、".join(tags) if not tags.is_empty() else "—", cost]


# 技能的傷害倍率（已乘等級與稀有度；袋子的強化另外乘）：照 SkillDefs 的資料組字，沒傷害的技能回空字串；% 前面寫吃什麼（skill_source_text）
# 例：「傷害：武器傷害 175% × 5 發」「傷害：法術強度 150%，火堆每秒 100%（4 秒）」「傷害：武器傷害 80% + 法術強度 20% 的 250%」
static func skill_damage_line(id: StringName, level := 1) -> String:
	var sk: Dictionary = SkillDefs.SKILLS[id]
	if not sk.has("damage_pct"):
		return ""
	var mul := SkillDefs.damage_mul(id, level)
	var main := pct_text(sk.damage_pct * mul)
	var src := skill_source_text(id)
	var text := "傷害：%s %s" % [src, main]
	match sk.behavior:
		&"rain":
			text = "傷害：每 %s 秒%s %s，共 %d 次" % [String.num(sk.tick), src, main, roundi(sk.duration / sk.tick)]
		&"chain":
			text = "傷害：%s %s，最多打 %d 隻" % [src, main, sk.jumps + 1]
		&"storm":
			text = "傷害：每 %s 秒%s %s，共 %d 次" % [String.num(sk.tick), src, main, roundi(sk.duration / sk.tick)]
		&"smite":
			text = "傷害：每隻%s %s，最多 %d 隻" % [src, main, sk.targets]
		&"star":
			text = "傷害：3 顆星的三角形裡每 %s 秒%s %s" % [String.num(sk.tick), src, main]
		&"reaver":
			text = "傷害：%s %s（這一層每殺一隻 +%d%%，最多 %s）" % [src, main, roundi(sk.per_kill * 100.0), pct_text(sk.damage_pct * mul * (1.0 + sk.per_kill * sk.max_stacks))]
		&"grudge":
			text = "傷害：%s %s 起，或受到傷害的 %s 倍（取大的）" % [src, main, String.num(snappedf(sk.grudge_mul * mul, 0.1))]
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


# 技能的傷害吃什麼（SkillDefs.scale_of）：「武器傷害」「法術強度」，混合的寫「武器傷害 80% + 法術強度 20% 的」
static func skill_source_text(id: StringName) -> String:
	var scale := SkillDefs.scale_of(id)
	if scale.spell <= 0.0:
		return "武器傷害"
	if scale.weapon <= 0.0:
		return "法術強度"
	return "武器傷害 %s + 法術強度 %s 的" % [pct_text(scale.weapon), pct_text(scale.spell)]


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
		parts.append("傷害 %s → %s" % [pct_text(sk.damage_pct * SkillDefs.damage_mul(id, level)), pct_text(sk.damage_pct * SkillDefs.damage_mul(id, level + 1))])
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
# 外形看種類（數值方塊、技能圓形或膠囊、修飾虛線、武器剪影、袋子標題條）、顏色看稀有度；
# 道具在右下角畫羈絆徽章（hover_bond 那個畫大一點）；格子 ≥ ITEM_BIG_CELL 時字大一級
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
	var first: Vector2 = rects[0].position
	var big := cell_px >= ITEM_BIG_CELL
	var line := Color(color, alpha)
	var text_color := Color(1, 1, 1, alpha)
	var tint := color.darkened(ITEM_TINT_DARK)
	if kind == &"skill" or ItemDefs.role_of(id) == ItemDefs.ROLE_EFFECT:
		_draw_skill_shape(ci, rects, color, tint, alpha)
		ci.draw_string(font, first + Vector2(0, cell_px / 2.0 + (12 if big else 7)), SkillDefs.SKILLS.get(id, {}).get("icon", String(def.name).substr(0, 1)),
				HORIZONTAL_ALIGNMENT_CENTER, cell_px, 34 if big else 20, text_color)
	elif kind == &"support":
		# 透明格（ItemDefs.MOD_CLEAR_INDEX）只畫虛線框和角落的小三角，底下的技能看得到；實心格照舊有底色
		for i in rects.size():
			var clear := i == ItemDefs.MOD_CLEAR_INDEX
			_draw_item_cell(ci, rects[i], rects, Color(color.darkened(ITEM_MOD_DARK), (0.12 if clear else 0.9) * alpha), line, true)
			if clear:
				var r := rects[i]
				var k := cell_px * 0.22
				ci.draw_colored_polygon(PackedVector2Array([r.position + Vector2(3, 3), r.position + Vector2(3 + k, 3), r.position + Vector2(3, 3 + k)]), line)
		var letter_at := first if rects.size() == 1 else rects[(ItemDefs.MOD_CLEAR_INDEX + 1) % rects.size()].position   # 字寫在實心格，不蓋住底下的技能
		var small := rects.size() == 1
		ci.draw_string(font, letter_at + Vector2(0, cell_px * (0.85 if small else 0.5) + (9 if big else 6) * (0.0 if small else 1.0)), String(def.name).substr(0, 1), HORIZONTAL_ALIGNMENT_CENTER if not small else HORIZONTAL_ALIGNMENT_RIGHT, cell_px - (4.0 if small else 0.0), (16 if big else 12) if small else (26 if big else 16), line)
	elif kind == &"weapon":
		var glow: float = WEAPON_GLOW.get(rarity, 0.0)
		if glow > 0.0:
			for cr in rects:
				ci.draw_rect(cr.grow(1.0), Color(color, 0.3 * alpha), false, glow)
		for cr in rects:
			_draw_item_cell(ci, cr, rects, Color(ITEM_WEAPON_FILL, 0.9 * alpha), line, false)
		draw_weapon_mark(ci, id, rects[0], line)
	elif kind == &"bag":
		for cr in rects:
			_draw_item_cell(ci, cr, rects, Color(tint, 0.9 * alpha), line, false)
		ci.draw_rect(Rect2(first + Vector2(3, 3), Vector2(cell_px - 6.0, cell_px * 0.28)), line)
		if cell_px >= ITEM_TEXT_CELL:
			ci.draw_string(font, first + Vector2(0, cell_px * 0.8), String(def.name).substr(0, 2), HORIZONTAL_ALIGNMENT_CENTER, cell_px, 18 if big else 13, text_color)
	else:
		for cr in rects:
			_draw_item_cell(ci, cr, rects, Color(tint, 0.9 * alpha), line, false)
		if cell_px >= ITEM_TEXT_CELL:
			var label_text := String(def.name).substr(0, 4 if big else 2)
			ci.draw_string(font, first + Vector2(5, cell_px * 0.36), label_text, HORIZONTAL_ALIGNMENT_LEFT, cell_px - 6, 13 if big else 15, text_color)   # 大格的字級放得下 4 個字，每件都一樣大
	var badge_r := clampf(cell_px * 0.16, 5.0, 10.0)
	for i in bonds.size():
		var center := first + Vector2(cell_px - badge_r - 3.0 - i * badge_r * 2.1, cell_px - badge_r - 3.0)
		draw_bond_mark(ci, bonds[i], center, badge_r * 1.25 if bonds[i] == hover_bond else badge_r, alpha)


# 技能的外形：單格是圓，占多格時沿著格子中心連成膠囊。圓和線會重疊，變淡時改混底色，不用半透明
static func _draw_skill_shape(ci: CanvasItem, rects: Array[Rect2], color: Color, tint: Color, alpha: float) -> void:
	var step := rects[0].size.x
	var layers: Array = [[color.lerp(ITEM_FADE_BG, 1.0 - alpha), step - 4.0], [tint.lerp(ITEM_FADE_BG, 1.0 - alpha), step - 9.0]]
	for layer: Array in layers:
		for i in rects.size():
			ci.draw_circle(rects[i].get_center(), layer[1] / 2.0, layer[0])
			for j in range(i + 1, rects.size()):
				if is_equal_approx(rects[i].position.distance_to(rects[j].position), step):
					ci.draw_line(rects[i].get_center(), rects[j].get_center(), layer[0], layer[1])


# 羈絆徽章：黑底圓加圖示，形狀不同，顏色和稀有度撞色時還分得出來（背包格子與羈絆欄共用）
# 門的獎勵名稱（MapGenDefs.REWARDS）：背包合併模式沒有袋子，「袋子」寫成「開格」（Relic 給隨機開 1 格）
static func reward_name(world: World, reward: StringName) -> String:
	if reward == &"bag" and world != null and world.player_list.any(func(p: Player) -> bool: return p.loadout.merged):
		return "開格"
	return MapGenDefs.REWARDS[reward].name


# 鎖頭圖示（背包合併的鎖格；字型沒有鎖的字，用向量畫）：r 是鎖身半寬
static func draw_lock(ci: CanvasItem, center: Vector2, r: float, color: Color) -> void:
	var body := Rect2(center + Vector2(-r, -r * 0.2), Vector2(r * 2.0, r * 1.5))
	ci.draw_arc(center + Vector2(0, -r * 0.2), r * 0.62, PI, TAU, 12, color, maxf(2.0, r * 0.22))
	ci.draw_rect(body, color)
	ci.draw_circle(body.get_center() + Vector2(0, -r * 0.1), r * 0.2, Color(0, 0, 0, 0.7))


static func draw_bond_mark(ci: CanvasItem, bond: StringName, center: Vector2, r: float, alpha: float) -> void:
	var color := Color(BondDefs.BONDS[bond].color, alpha)
	var s := r * 0.6
	var width := maxf(1.0, r * 0.2)
	ci.draw_circle(center, r, Color(0, 0, 0, 0.85 * alpha))
	match bond:
		&"phys":
			ci.draw_line(center + Vector2(-s, s), center + Vector2(s, -s), color, width)
			ci.draw_line(center + Vector2(-s * 0.7, -s * 0.1), center + Vector2(s * 0.1, s * 0.7), color, width)
		&"fire":
			ci.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -s), center + Vector2(s * 0.5, -s * 0.2), center + Vector2(s * 0.8, s * 0.4), center + Vector2(s * 0.4, s), center + Vector2(-s * 0.4, s), center + Vector2(-s * 0.8, s * 0.4), center + Vector2(-s * 0.5, -s * 0.2)]), color)
		&"cold":
			for a: float in [PI / 2.0, PI / 6.0, -PI / 6.0]:
				var d := Vector2.from_angle(a) * s
				ci.draw_line(center - d, center + d, color, width)
		&"guard":
			ci.draw_colored_polygon(PackedVector2Array([center + Vector2(-s, -s * 0.8), center + Vector2(s, -s * 0.8), center + Vector2(s, s * 0.1), center + Vector2(0, s), center + Vector2(-s, s * 0.1)]), color)
		&"wisp":
			ci.draw_arc(center, s, 0.0, TAU, 16, color, width)
			ci.draw_circle(center, s * 0.35, color)


# 武器的 2D 剪影，畫在一格 r 裡；座標是格子寬的比例（沒畫過的武器畫成一把劍）
static func draw_weapon_mark(ci: CanvasItem, id: StringName, r: Rect2, color: Color) -> void:
	var c := r.size.x
	var at := func(x: float, y: float) -> Vector2: return r.position + Vector2(x, y) * c
	var thin := maxf(1.5, c * 0.06)
	var thick := maxf(2.0, c * 0.09)
	match id:
		&"dagger":   # 雙匕首：交叉的兩把
			ci.draw_line(at.call(0.26, 0.74), at.call(0.66, 0.3), color, thick)
			ci.draw_line(at.call(0.74, 0.74), at.call(0.34, 0.3), color, thick)
			ci.draw_line(at.call(0.2, 0.6), at.call(0.38, 0.8), color, thin)
			ci.draw_line(at.call(0.8, 0.6), at.call(0.62, 0.8), color, thin)
		&"swordShield":   # 劍盾：右上斜的劍 + 左下的盾
			ci.draw_line(at.call(0.38, 0.62), at.call(0.84, 0.16), color, thick)
			ci.draw_line(at.call(0.48, 0.42), at.call(0.62, 0.56), color, thin)
			ci.draw_colored_polygon(PackedVector2Array([at.call(0.14, 0.4), at.call(0.5, 0.4), at.call(0.5, 0.62), at.call(0.32, 0.86), at.call(0.14, 0.62)]), color)
		&"staff":
			ci.draw_line(at.call(0.24, 0.8), at.call(0.7, 0.32), color, thin)
			ci.draw_circle(at.call(0.74, 0.26), c * 0.11, color)
		&"scepter":
			ci.draw_line(at.call(0.26, 0.78), at.call(0.66, 0.38), color, thin)
			ci.draw_line(at.call(0.58, 0.28), at.call(0.84, 0.28), color, thick)
			ci.draw_line(at.call(0.71, 0.15), at.call(0.71, 0.41), color, thick)
		&"shortbow":
			ci.draw_arc(at.call(0.28, 0.5), c * 0.3, -PI / 2.0, PI / 2.0, 14, color, thick)
			ci.draw_line(at.call(0.28, 0.2), at.call(0.28, 0.8), color, 1.0)
		&"longbow":
			ci.draw_arc(at.call(0.2, 0.5), c * 0.38, -PI / 2.0, PI / 2.0, 16, color, thick)
			ci.draw_line(at.call(0.2, 0.12), at.call(0.2, 0.88), color, 1.0)
		&"torch":
			ci.draw_line(at.call(0.3, 0.84), at.call(0.54, 0.46), color, thick)
			ci.draw_colored_polygon(PackedVector2Array([at.call(0.68, 0.14), at.call(0.76, 0.34), at.call(0.66, 0.5), at.call(0.5, 0.44), at.call(0.5, 0.28)]), color)
		&"shovel":
			ci.draw_line(at.call(0.22, 0.2), at.call(0.56, 0.58), color, thin)
			ci.draw_colored_polygon(PackedVector2Array([at.call(0.5, 0.56), at.call(0.66, 0.44), at.call(0.84, 0.76), at.call(0.8, 0.84), at.call(0.68, 0.82)]), color)
		_:
			ci.draw_line(at.call(0.22, 0.8), at.call(0.78, 0.22), color, thick)
			ci.draw_line(at.call(0.2, 0.58), at.call(0.44, 0.82), color, thin)


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
