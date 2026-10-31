# 遺物的 N 選 1（Build 改版第 6 步）：卡片直排在背包左邊（打開時 HUD 自動打開背包，看得到格子與羈絆欄），遊戲不暫停
# 卡片（2026-10-31 使用者從對比頁 mockups/relic-cards.html 選 A）：左邊畫物品長怎樣；右邊名稱（稀有度色、大字）→ 羈絆標籤（羈絆色 + 目前件數）→ 效果（數字金色）
# 技能卡：名稱後面「升到 N 級」標籤（已經有時）、第二行鑲在哪 / 範圍 / 冷卻；外框是稀有度色（技能是金色）
# 自己的角色打開了遺物（Player.relic_id，連線時看快照）就顯示，選項讀遺物上的 offers；點卡片或按數字鍵選、R 重骰、Esc 先不選
# 鍵盤由 InputCollector 接（relic_open 時數字鍵、R、Esc 不給技能、重新開始、暫停）；操作走 op_requested → InputCmd.inv_ops，結果等權威端
class_name RelicPanel
extends VBoxContainer

signal op_requested(op: Array)

const CARD_W := 440.0
const PREVIEW_W := 120.0          # 卡片左邊畫物品的區塊
const PREVIEW_MAX := 104.0        # 物品小圖最長邊不超過這麼長
const PREVIEW_CELL := 34.0        # 多格道具每格最大
const PREVIEW_SINGLE := 64.0      # 單格（技能、白色道具）畫大一點
const NAME_FONT := 30
const CHIP_FONT := 18
const EFFECT_FONT := 21
const CARD_BG := Color(0.11, 0.12, 0.16, 0.95)
const CARD_HOVER_BG := Color(0.17, 0.19, 0.25, 0.97)
# 效果文字裡的數字（含單位）用金色
const NUMBER_PATTERN := "([+\\-]?\\d+(?:\\.\\d+)?\\s*(?:%|秒|格|倍|層|次|點|件)?)"

var _cards := VBoxContainer.new()
var _title := UiKit.label("", UiKit.FONT_BODY, UiKit.GOLD)
var _footer := UiKit.label("", 22, Color(1, 1, 1, 0.85))
var relic_id := 0                # 正在顯示的遺物（0 = 沒顯示）
var choice_count := 0
var _shown_key := []             # 目前卡片對應的選項與羈絆件數（變了才重建）
var _dismissed := 0              # 本機已經按了選 / 關掉的遺物：等權威端關掉前先不顯示，免得閃一下
var _number := RegEx.create_from_string(NUMBER_PATTERN)


func _init() -> void:
	add_theme_constant_override(&"separation", 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = CARD_W
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.custom_minimum_size.x = CARD_W
	_cards.add_theme_constant_override(&"separation", 14)
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	add_child(_cards)
	add_child(_footer)
	visible = false


# 每幀（HUD._process）：照本機玩家打開的遺物顯示或藏起來
func refresh(world: World, me: Player) -> void:
	var r: Relic = null
	if me != null and me.relic_id != 0 and me.relic_id != _dismissed:
		r = world.entities.get(me.relic_id) as Relic
	if me != null and me.relic_id == 0:
		_dismissed = 0
	var choices: Array = r.offers.get(me.peer_id, []) if r != null and not r.is_removed else []
	visible = not choices.is_empty()
	relic_id = r.id if visible else 0
	choice_count = choices.size()
	if not visible:
		return
	_title.text = "選一個%s（按數字鍵或點卡片）" % ("技能" if r.relic_kind == &"skill" else "道具")
	var key := [choices.duplicate(), me.loadout.bond_counts.duplicate(), me.skill_levels.duplicate()]
	if key != _shown_key:
		_shown_key = key
		_rebuild(choices, me)
	_footer.text = ("骰子 %d 顆 · R 重骰（用掉 1 顆）" % me.dice if me.dice > 0 else "沒有骰子了") + " · Esc 先不選"


func _rebuild(choices: Array, me: Player) -> void:
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	for i in choices.size():
		_cards.add_child(_card(i, choices[i], me))


func _card(i: int, id: StringName, me: Player) -> PanelContainer:
	var def: Dictionary = ItemDefs.ITEMS[id]
	var skill := ItemDefs.is_skill(id)
	var color: Color = UiKit.GOLD if skill else ItemDefs.RARITIES[def.rarity].color
	var card := PanelContainer.new()
	card.custom_minimum_size.x = CARD_W
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override(&"panel", _card_box(color, CARD_BG))
	card.mouse_entered.connect(func() -> void: card.add_theme_stylebox_override(&"panel", _card_box(color, CARD_HOVER_BG)))
	card.mouse_exited.connect(func() -> void: card.add_theme_stylebox_override(&"panel", _card_box(color, CARD_BG)))
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pick(i)
			card.accept_event())
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	card.add_child(row)
	var pic := Control.new()
	pic.custom_minimum_size = Vector2(PREVIEW_W, PREVIEW_W)
	pic.draw.connect(_draw_preview.bind(pic, id))
	row.add_child(pic)
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(body)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 10)
	head.add_child(_key_badge(i, color))
	head.add_child(UiKit.label(def.name, NAME_FONT, color))
	var lv: int = me.skill_levels.get(id, 1)
	if skill and me.loadout.has_item(id) and lv < SkillDefs.LEVEL.max:
		head.add_child(_chip("升到 %d 級" % (lv + 1), UiKit.GOLD, true))
	body.add_child(head)
	if skill:
		body.add_child(UiKit.label(UiKit.skill_line(id), CHIP_FONT, Color(1, 1, 1, 0.6)))
	var bonds: Array = def.get("bonds", [])
	if not bonds.is_empty():
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override(&"h_separation", 8)
		chips.add_theme_constant_override(&"v_separation", 6)
		for b: StringName in bonds:
			chips.add_child(_chip("%s %d" % [BondDefs.BONDS[b].name, me.loadout.bond_counts.get(b, 0)], BondDefs.BONDS[b].color))
		body.add_child(chips)
	var eff := RichTextLabel.new()
	eff.bbcode_enabled = true
	eff.fit_content = true
	eff.scroll_active = false
	eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eff.custom_minimum_size.x = CARD_W - PREVIEW_W - 16 - 36
	eff.add_theme_font_size_override(&"normal_font_size", EFFECT_FONT)
	eff.text = effect_bbcode(def.desc)
	body.add_child(eff)
	_ignore_mouse(row)
	return card


# 效果文字：數字（含單位）包成金色
func effect_bbcode(desc: String) -> String:
	return _number.sub(desc.replace("[", "[lb]"), "[color=#%s]$1[/color]" % UiKit.GOLD.to_html(false), true)


static func _card_box(border: Color, bg: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(3)
	box.set_corner_radius_all(10)
	box.content_margin_left = 16
	box.content_margin_right = 18
	box.content_margin_top = 14
	box.content_margin_bottom = 16
	return box


# 數字鍵：圓形小標（稀有度色的框）
static func _key_badge(i: int, color: Color) -> Label:
	var l := UiKit.label(str(i + 1), CHIP_FONT, color, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(32, 32)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.6)
	box.border_color = color
	box.set_border_width_all(2)
	box.set_corner_radius_all(16)
	l.add_theme_stylebox_override(&"normal", box)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


# 小標籤：羈絆（羈絆色的框 + 字）、升級（金底黑字）
static func _chip(text: String, color: Color, filled := false) -> Label:
	var l := UiKit.label(text, CHIP_FONT, Color(0.07, 0.07, 0.07) if filled else color, 0)
	var box := StyleBoxFlat.new()
	box.bg_color = color if filled else Color(1, 1, 1, 0.06)
	box.border_color = color
	box.set_border_width_all(1)
	box.set_corner_radius_all(14)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 2
	box.content_margin_bottom = 3
	l.add_theme_stylebox_override(&"normal", box)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


static func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_ignore_mouse(c)


# 物品長怎樣（和背包同一套畫法 UiKit.draw_item），置中在左邊的區塊
func _draw_preview(pic: Control, id: StringName) -> void:
	var cells := Inventory.cells_of(id, 0)
	var extent := UiKit.shape_size(id, 1.0)
	var cell := PREVIEW_SINGLE if cells.size() == 1 else minf(PREVIEW_CELL, PREVIEW_MAX / maxf(extent.x, extent.y))
	var at := pic.size / 2.0 - extent * cell / 2.0
	UiKit.draw_item(pic, pic.get_theme_default_font(), id, at, cell, 0, ItemDefs.ITEMS[id].rarity, 1.0)


func pick(index: int) -> void:
	if relic_id == 0 or index < 0 or index >= choice_count:
		return
	op_requested.emit([InputCmd.OP_RELIC_PICK, relic_id, index])
	_dismissed = relic_id
	visible = false


func reroll() -> void:
	if relic_id != 0:
		op_requested.emit([InputCmd.OP_RELIC_REROLL, relic_id])


func close() -> void:
	if relic_id == 0:
		return
	op_requested.emit([InputCmd.OP_RELIC_CLOSE])
	_dismissed = relic_id
	visible = false
