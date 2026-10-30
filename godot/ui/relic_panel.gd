# 遺物的 N 選 1（Build 改版第 6 步）：畫面下方中間一排卡片（左邊畫物品長怎樣，右邊名稱、羈絆、效果；稀有度看顏色），遊戲不暫停
# 自己的角色打開了遺物（Player.relic_id，連線時看快照）就顯示，選項讀遺物上的 offers；點卡片或按數字鍵選、R 重骰、Esc 先不選
# 鍵盤由 InputCollector 接（relic_open 時數字鍵、R、Esc 不給技能、重新開始、暫停）；操作走 op_requested → InputCmd.inv_ops，結果等權威端
class_name RelicPanel
extends VBoxContainer

signal op_requested(op: Array)

const PREVIEW_W := 140.0          # 卡片左邊畫物品的區塊寬（文字從這裡之後開始）
const PREVIEW_MAX := 112.0        # 物品小圖最長邊不超過這麼長
const PREVIEW_CELL := 36.0        # 多格道具每格最大
const PREVIEW_SINGLE := 72.0      # 單格（技能、白色道具）畫大一點

var _cards := HBoxContainer.new()
var _title := UiKit.label("", UiKit.FONT_BODY, UiKit.GOLD)
var _footer := UiKit.label("", 22, Color(1, 1, 1, 0.85))
var relic_id := 0                # 正在顯示的遺物（0 = 沒顯示）
var choice_count := 0
var _shown_key := []             # 目前卡片對應的選項（變了才重建）
var _dismissed := 0              # 本機已經按了選 / 關掉的遺物：等權威端關掉前先不顯示，免得閃一下


func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override(&"separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards.add_theme_constant_override(&"separation", 12)
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
	if choices != _shown_key:
		_shown_key = choices.duplicate()
		_rebuild(choices, me)
	_footer.text = ("骰子 %d 顆 · R 重骰（用掉 1 顆）" % me.dice if me.dice > 0 else "沒有骰子了") + " · Esc 先不選"


func _rebuild(choices: Array, me: Player) -> void:
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	for i in choices.size():
		var id: StringName = choices[i]
		var def: Dictionary = ItemDefs.ITEMS[id]
		if def.kind == &"skill":
			_cards.add_child(_skill_card(i, id, me))
			continue
		# 稀有度看文字顏色與小圖外框，不另外寫；有羈絆才寫一行
		var bonds: Array[String] = []
		for b: StringName in def.get("bonds", []):
			bonds.append(BondDefs.BONDS[b].name)
		var rarity: Dictionary = ItemDefs.RARITIES[def.rarity]
		var lines: Array[String] = ["%d　%s" % [i + 1, def.name]]
		if not bonds.is_empty():
			lines.append("%s羈絆" % "、".join(bonds))
		lines.append(def.desc)
		var b := UiKit.button("\n".join(lines), UiKit.BUTTON_CARD)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_color_override(&"font_color", rarity.color)
		b.add_theme_color_override(&"font_hover_color", rarity.color.lightened(0.3))
		b.pressed.connect(pick.bind(i))
		_add_preview(b, id)
		_cards.add_child(b)


# 技能卡：名稱、能用的武器與冷卻、說明；身上已經有就寫會升到幾級
func _skill_card(i: int, id: StringName, me: Player) -> Button:
	var def: Dictionary = ItemDefs.ITEMS[id]
	var lv: int = me.skill_levels.get(id, 1)
	var head := "%d　%s" % [i + 1, def.name]
	if me.loadout.has_item(id) and lv < SkillDefs.LEVEL.max:
		head += "（已有：升到 %d 級）" % (lv + 1)
	var b := UiKit.button("%s\n%s\n%s" % [head, UiKit.skill_line(id), def.desc], UiKit.BUTTON_CARD)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_color_override(&"font_color", UiKit.GOLD)
	b.pressed.connect(pick.bind(i))
	_add_preview(b, id)
	return b


# 卡片左邊留 PREVIEW_W 畫物品（和背包同一套畫法 UiKit.draw_item），文字靠左排在右邊
func _add_preview(b: Button, id: StringName) -> void:
	for state: StringName in UiKit.BUTTON_BG.keys() + [&"hover_pressed"]:
		var box := b.get_theme_stylebox(state).duplicate() as StyleBox
		box.content_margin_left = PREVIEW_W
		b.add_theme_stylebox_override(state, box)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.draw.connect(_draw_preview.bind(b, id))


func _draw_preview(b: Button, id: StringName) -> void:
	var cells := Inventory.cells_of(id, 0)
	var extent := UiKit.shape_size(id, 1.0)
	var cell := PREVIEW_SINGLE if cells.size() == 1 else minf(PREVIEW_CELL, PREVIEW_MAX / maxf(extent.x, extent.y))
	var at := Vector2(PREVIEW_W, b.size.y) / 2.0 - extent * cell / 2.0
	UiKit.draw_item(b, b.get_theme_default_font(), id, at, cell, 0, ItemDefs.ITEMS[id].rarity, 1.0)


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
