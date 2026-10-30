# 遺物的 N 選 1（Build 改版第 6 步）：畫面下方中間一排卡片（名稱、稀有度與羈絆、效果），遊戲不暫停
# 自己的角色打開了遺物（Player.relic_id，連線時看快照）就顯示，選項讀遺物上的 offers；點卡片或按數字鍵選、R 重骰、Esc 先不選
# 鍵盤由 InputCollector 接（relic_open 時數字鍵、R、Esc 不給技能、重新開始、暫停）；操作走 op_requested → InputCmd.inv_ops，結果等權威端
class_name RelicPanel
extends VBoxContainer

signal op_requested(op: Array)

var _cards := HBoxContainer.new()
var _title := UiKit.label("選一個道具（按數字鍵或點卡片）", UiKit.FONT_NOTE, UiKit.GOLD)
var _footer := UiKit.label("", 18, Color(1, 1, 1, 0.85))
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
	if choices != _shown_key:
		_shown_key = choices.duplicate()
		_rebuild(choices)
	_footer.text = ("骰子 %d 顆 · R 重骰（用掉 1 顆）" % me.dice if me.dice > 0 else "沒有骰子了") + " · Esc 先不選"


func _rebuild(choices: Array) -> void:
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	for i in choices.size():
		var id: StringName = choices[i]
		var def: Dictionary = ItemDefs.ITEMS[id]
		var bonds: Array[String] = []
		for b: StringName in def.get("bonds", []):
			bonds.append(BondDefs.BONDS[b].name)
		var rarity: Dictionary = ItemDefs.RARITIES[def.rarity]
		var b := UiKit.button("%d　%s\n%s · %s\n%s" % [i + 1, def.name, rarity.name, "、".join(bonds) if not bonds.is_empty() else "沒有羈絆", def.desc], UiKit.BUTTON_CARD)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_color_override(&"font_color", rarity.color)
		b.add_theme_color_override(&"font_hover_color", rarity.color.lightened(0.3))
		b.pressed.connect(pick.bind(i))
		_cards.add_child(b)


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
