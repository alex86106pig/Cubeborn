# 骰子模式的桌邊配件（docs/系統說明.md §55「桌邊配件」；對比頁方案 1，YangHsu 2026-11-20 選）：
#   上方中央：階段條（帶隊 → 擲骰 → 開打 → 清場 → 獎勵），現在那一步亮起、左邊寫第幾場（track，HUD 放進上方中央那一欄）
#   左下：角色卡：武器名稱、血量是紅籌碼（每枚 = 最大生命的 1/10）、護盾是藍籌碼、下面寫數字；骰子模式取代左上的血條
#   右下：這一場的牌：普攻卡、右鍵技能卡（骰到的招、幾個、威力、組合），下面一排效果籌碼與重擲券
# 擲骰、倒數、選獎勵時卡片收起來（擲骰畫面自己會寫結果）；開著骰子與武器面板（Tab）時也收起來，免得疊在一起
# 字級只用開場預熱過的（HUD.set_loading：16 / 18 / 20 / 28），第一次出現才不會卡
class_name DiceProps
extends Control

const STEPS := ["帶隊", "擲骰", "開打", "清場", "獎勵"]
const CHIPS := 10                     # 血量籌碼總數（每枚 = 最大生命的 1/10）
const CHIP_STACK := 5                 # 一疊幾枚
const PAPER := Color("efe4cc")        # 卡片紙色
const PAPER_LIT := Color("fff3cf")    # 骰到技能的右鍵卡
const PAPER_EDGE := Color("7a5a38")
const INK := Color("3a2a1a")          # 卡片上的字
const INK_SUB := Color("6b4a2a")
const HP_CHIP := Color("c23b3b")
const SHIELD_CHIP := Color("3f7fc0")
const EFFECT_CHIP := Color("2f6f9a")
const TICKET_CHIP := Color("5b3f8f")

var track := PhaseTrack.new()
var hero := PanelContainer.new()
var hand := VBoxContainer.new()       # 右下：牌與籌碼
var hero_name := UiKit.label("", 20, INK, 0)
var hp_chips := ChipStacks.new(HP_CHIP)
var shield_chips := ChipStacks.new(SHIELD_CHIP)
var hp_text := UiKit.label("", 18, INK_SUB, 0)
var skill_card := PanelContainer.new()
var skill_name := UiKit.label("", 28, INK, 0)
var skill_sub := UiKit.label("", 16, INK_SUB, 0)
var basic_card := PanelContainer.new()
var basic_sub := UiKit.label("", 16, INK_SUB, 0)
var chips_row := HFlowContainer.new()
var chip_texts: Array[String] = []    # 這一幀擺了哪些籌碼（效果與重擲券，檢查讀）
var _chips_key := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# 左下：角色卡
	hero.add_theme_stylebox_override(&"panel", paper_box(PAPER))
	hero.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	hero.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hbox := VBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 4)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(hero_name)
	var stacks := HBoxContainer.new()
	stacks.add_theme_constant_override(&"separation", 10)
	stacks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stacks.add_child(hp_chips)
	stacks.add_child(shield_chips)
	hbox.add_child(stacks)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(hp_text)
	hero.add_child(hbox)
	add_child(hero)

	# 右下：右鍵技能卡、普攻卡，下面效果籌碼與重擲券
	hand.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	hand.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hand.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hand.add_theme_constant_override(&"separation", 8)
	hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override(&"separation", 10)
	cards.alignment = BoxContainer.ALIGNMENT_END
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	basic_card.add_child(_card_body("左鍵　普攻", basic_sub, null))
	skill_card.add_child(_card_body("右鍵", skill_sub, skill_name))
	for c: PanelContainer in [basic_card, skill_card]:
		c.custom_minimum_size = Vector2(140, 0)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cards.add_child(c)
	basic_card.add_theme_stylebox_override(&"panel", paper_box(PAPER))
	hand.add_child(cards)
	chips_row.alignment = FlowContainer.ALIGNMENT_END
	chips_row.custom_minimum_size.x = 310
	chips_row.add_theme_constant_override(&"h_separation", 6)
	chips_row.add_theme_constant_override(&"v_separation", 6)
	chips_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand.add_child(chips_row)
	add_child(hand)


static func paper_box(color: Color, edge: Color = PAPER_EDGE, width: int = 2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = edge
	box.set_border_width_all(width)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(10)
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 4
	box.shadow_offset = Vector2(0, 3)
	return box


func _card_body(head: String, sub: Label, big: Label) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UiKit.label(head, 16, INK_SUB, 0)
	v.add_child(h)
	if big != null:
		v.add_child(big)
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.add_child(sub)
	return v


# 每幀（HUD）：panels_open = 屬性面板 / 骰子與武器面板開著
func refresh(world: World, me: Player, panels_open: bool) -> void:
	var dice := world.dice if world != null else null
	visible = dice != null and me != null
	track.visible = visible
	if not visible:
		return
	track.set_step(step_of(dice.phase), dice.fights + (1 if dice.phase == DiceRun.EXPLORE else 0))
	var cards_on := (dice.phase == DiceRun.EXPLORE or dice.phase == DiceRun.FIGHT or dice.phase == DiceRun.CLEAR) and not panels_open
	hero.visible = cards_on
	hand.visible = cards_on
	if not cards_on:
		return
	var inst := me.active_weapon()
	hero_name.text = WeaponDropDefs.display_name(inst) if not inst.is_empty() else me.weapon.name
	var unit := me.max_hp / CHIPS
	hp_chips.set_count(ceili(me.hp / unit - 1e-4) if me.hp > 0.0 else 0, CHIPS)
	var shields := mini(ceili(me.shield / unit - 1e-4), CHIPS) if me.shield >= 0.5 else 0
	shield_chips.visible = shields > 0
	shield_chips.set_count(shields, shields)
	hp_text.text = "%s / %s" % [UiKit.hp_text(me.hp), UiKit.hp_text(me.max_hp)] + ("　盾 %s" % UiKit.hp_text(me.shield) if shields > 0 else "")
	var s := dice.seat_of(me)
	_show_skill(s.result)
	_show_chips(s.result.get("effects", {}), dice.charges_of(me))


# 階段條第幾步（DiceRun 的階段）
static func step_of(phase: StringName) -> int:
	match phase:
		DiceRun.ROLL, DiceRun.COUNTDOWN:
			return 1
		DiceRun.FIGHT:
			return 2
		DiceRun.CLEAR:
			return 3
		DiceRun.REWARD:
			return 4
	return 0


func _show_skill(res: Dictionary) -> void:
	var lit: bool = not res.is_empty() and res.count > 0
	if res.is_empty():
		skill_name.text = "還沒擲"
		skill_sub.text = "碰到怪就擲骰"
	elif res.count <= 0:
		skill_name.text = "沒中"
		skill_sub.text = "這場只能普攻"
	else:
		var tier := DiceDefs.tier_of(res.tier_count)
		skill_name.text = DiceDefs.name_of(res.skill)
		var sub := "×%d　%s ×%s" % [res.count, tier.name, str(tier.mul)]
		for c: StringName in res.get("combos", []):
			sub += "\n" + DiceDefs.COMBOS[c].name
		skill_sub.text = sub
	skill_card.add_theme_stylebox_override(&"panel", paper_box(PAPER_LIT if lit else PAPER, UiKit.GOLD if lit else PAPER_EDGE, 3 if lit else 2))
	basic_sub.text = "×%s" % str(DiceDefs.BASIC_ATTACK_MUL)


# 效果籌碼一枚一種效果（寫效果與數值），最後一枚是重擲券（寫幾張，0 張變淡）；內容變了才重建
func _show_chips(effects: Dictionary, charges: int) -> void:
	var texts: Array[String] = []
	var colors: Array[Color] = []
	for id: StringName in effects:
		texts.append(DiceDefs.effect_text(id, effects[id]))
		colors.append(EFFECT_CHIP)
	texts.append("重擲券 ×%d" % charges)
	colors.append(TICKET_CHIP if charges > 0 else Color(TICKET_CHIP, 0.4))
	var key := "|".join(texts)
	if key == _chips_key:
		return
	_chips_key = key
	chip_texts = texts
	for c in chips_row.get_children():
		c.queue_free()
	for i in texts.size():
		chips_row.add_child(Chip.new(texts[i], colors[i]))


# 上方中央的階段條：五個點連成一條線、下面寫名稱，現在那一步放大塗金；左邊寫第幾場
class PhaseTrack extends Control:
	const W := 560.0
	const H := 64.0
	const LEFT := 96.0       # 左邊「第 N 場」的寬度
	var step := 0
	var fight := 0
	var _labels: Array[Label] = []
	var _fight_label := UiKit.label("", 20, UiKit.GOLD, 2)

	func _init() -> void:
		custom_minimum_size = Vector2(W + LEFT, H)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fight_label.position = Vector2(0, 10)
		_fight_label.size = Vector2(LEFT - 8, 28)
		_fight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(_fight_label)
		for i in STEPS.size():
			var l := UiKit.label(STEPS[i], 16, Color(1, 1, 1, 0.6), 2)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.size = Vector2(80, 22)
			l.position = Vector2(_x(i) - 40.0, 38)
			add_child(l)
			_labels.append(l)

	func _x(i: int) -> float:
		return LEFT + 40.0 + (W - 80.0) * i / (STEPS.size() - 1)

	func set_step(p_step: int, p_fight: int) -> void:
		var text := "第 %d 場" % maxi(p_fight, 1)
		if p_step == step and _fight_label.text == text:
			return
		step = p_step
		fight = p_fight
		_fight_label.text = text
		for i in _labels.size():
			_labels[i].add_theme_color_override(&"font_color", UiKit.GOLD if i == step else Color(1, 1, 1, 0.6))
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(LEFT, 6, W, 28)
		draw_style_box(DiceProps.paper_box(Color(0.14, 0.10, 0.07, 0.85), Color("8a6240"), 2), r)
		draw_line(Vector2(_x(0), 20), Vector2(_x(STEPS.size() - 1), 20), Color("5a4532"), 3.0)
		for i in STEPS.size():
			if i == step:
				draw_circle(Vector2(_x(i), 20), 10.0, UiKit.GOLD)
				draw_circle(Vector2(_x(i), 20), 4.0, Color("241a12"))
			else:
				draw_circle(Vector2(_x(i), 20), 5.0, Color("a08060") if i < step else Color("5a4532"))


# 疊起來的籌碼：count 枚，每疊 CHIP_STACK 枚、由下往上疊；slots = 總共的位置（沒有的畫成淡淡的空位）
class ChipStacks extends Control:
	const CW := 34.0     # 一枚的寬
	const CH := 7.0      # 一枚往上疊的高度
	var color: Color
	var count := 0
	var slots := 0

	func _init(p_color: Color) -> void:
		color = p_color
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_count(n: int, p_slots: int) -> void:
		if n == count and p_slots == slots:
			return
		count = n
		slots = p_slots
		var stacks := ceili(float(maxi(slots, 1)) / CHIP_STACK)
		custom_minimum_size = Vector2(stacks * (CW + 6.0) - 6.0, CH * CHIP_STACK + 14.0)
		queue_redraw()

	func _draw() -> void:
		for i in slots:
			var col := i / CHIP_STACK
			var row := i % CHIP_STACK
			var c := Vector2(col * (CW + 6.0) + CW / 2.0, size.y - 8.0 - row * CH)
			if i < count:
				_chip(c, color)
			else:
				_chip(c, Color(color, 0.18), false)

	func _chip(c: Vector2, col: Color, solid: bool = true) -> void:
		var side := PackedVector2Array()
		var top := PackedVector2Array()
		for k in 25:
			var a := TAU * k / 24.0
			top.append(c + Vector2(cos(a) * CW / 2.0, sin(a) * 5.0 - 3.0))
		for k in 13:
			var a := PI * k / 12.0
			side.append(c + Vector2(cos(a) * CW / 2.0, sin(a) * 5.0 + 1.0))
		for k in range(12, -1, -1):
			var a := PI * k / 12.0
			side.append(c + Vector2(cos(a) * CW / 2.0, sin(a) * 5.0 - 3.0))
		draw_colored_polygon(side, col.darkened(0.35))
		draw_colored_polygon(top, col)
		if solid:
			draw_polyline(top, col.darkened(0.5), 1.0)
			draw_arc(c + Vector2(0, -3), CW * 0.3, 0.0, TAU, 20, Color(1, 1, 1, 0.35), 1.5)


# 一枚籌碼：圓片 + 旁邊的字（效果、重擲券）
class Chip extends HBoxContainer:
	var color: Color

	func _init(text: String, p_color: Color) -> void:
		color = p_color
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override(&"separation", 4)
		var disc := Control.new()
		disc.custom_minimum_size = Vector2(24, 24)
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.draw.connect(func() -> void:
			disc.draw_circle(Vector2(12, 12), 11.0, color.darkened(0.45))
			disc.draw_circle(Vector2(12, 11), 10.0, color)
			disc.draw_arc(Vector2(12, 11), 6.5, 0.0, TAU, 16, Color(1, 1, 1, 0.45), 1.5))
		add_child(disc)
		add_child(UiKit.label(text, 16, Color(1, 1, 1, 0.95), 2))
