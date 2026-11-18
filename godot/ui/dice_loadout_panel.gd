# 骰子模式的「骰子與武器」面板（Tab，取代背包；docs/系統說明.md §55）：手上的武器、這場帶的 6 顆、備用骰子、備用武器
# 換骰子：先點「這場帶的」其中一顆，再點一顆備用骰子（換上）或另一顆帶著的（互換位置）；換武器：點備用武器的「換上」
# 只在逛地圖時能換（DiceRun 也只在 EXPLORE 收 OP_DICE_CARRY / OP_DICE_WEAPON）；操作走 op_requested → InputCmd.inv_ops
class_name DiceLoadoutPanel
extends PanelContainer

signal op_requested(op: Array)

const FACE := 40.0
const ROW_W := 420.0
const LOOSE_MAX_H := 270.0        # 沒帶的骰子超過這麼高就捲（獎勵骰會一直變多）

var _body := VBoxContainer.new()
var _title := UiKit.label("骰子與武器（Tab 關閉）", UiKit.FONT_HEADING, UiKit.GOLD)
var _weapon := UiKit.label("", UiKit.FONT_BODY)
var _carry_head := UiKit.label("", UiKit.FONT_NOTE, Color(1, 1, 1, 0.8))
var _carry_rows := VBoxContainer.new()
var _loose_head := UiKit.label("", UiKit.FONT_NOTE, Color(1, 1, 1, 0.8))
var _loose_rows := VBoxContainer.new()
var _loose_scroll := ScrollContainer.new()
var _spare_head := UiKit.label("", UiKit.FONT_NOTE, Color(1, 1, 1, 0.8))
var _spare_rows := VBoxContainer.new()
var _hint := UiKit.label("", UiKit.FONT_NOTE, Color(1, 1, 1, 0.7))
var selected := -1                # 選起來的「這場帶的」第幾顆（-1 = 沒選）
var _key := []
var _can_change := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.08, 0.11, 0.94)
	box.border_color = Color(1, 1, 1, 0.16)
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(18)
	add_theme_stylebox_override(&"panel", box)
	_body.add_theme_constant_override(&"separation", 8)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	_loose_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_loose_scroll.add_child(_loose_rows)
	for c: Control in [_title, _weapon, _carry_head, _carry_rows, _loose_head, _loose_scroll, _spare_head, _spare_rows, _hint]:
		_body.add_child(c)
	for v: VBoxContainer in [_carry_rows, _loose_rows, _spare_rows]:
		v.add_theme_constant_override(&"separation", 4)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = ROW_W
	visible = false


# 每幀（HUD._process，開著時）：照本機玩家的 Seat 畫；內容變了才重建
func refresh(world: World, me: Player) -> void:
	if world == null or world.dice == null or me == null:
		return
	var dice := world.dice
	var s := dice.seat_of(me)
	_can_change = dice.phase == DiceRun.EXPLORE
	if not _can_change:
		selected = -1
	var key := [s.carry.duplicate(), s.all_dice().duplicate(true), s.spares.map(func(w: Dictionary) -> String: return String(w.uid)), s.weapon_uid, selected, _can_change]
	if key == _key:
		return
	_key = key
	var inst := me.active_weapon()
	_weapon.text = "手上：%s" % (WeaponDropDefs.display_name(inst) if not inst.is_empty() else "（沒有）")
	_weapon.add_theme_color_override(&"font_color", ItemDefs.RARITIES[inst.rarity].color if not inst.is_empty() else Color.WHITE)
	_carry_head.text = "這場帶的 6 顆"
	_clear(_carry_rows)
	for i in DiceDefs.DICE_COUNT:
		var k: int = s.carry[i]
		var tag := "武器骰 %d" % (k + 1) if k < DiceDefs.DICE_COUNT else "備用骰 %d" % (k - DiceDefs.DICE_COUNT + 1)
		var row := _die_row(tag, s.pool[i], me.weapon_id, i == selected)
		row.gui_input.connect(_on_row_input.bind(row, func() -> void: _click_carry(s, i)))
		_carry_rows.add_child(row)
	var loose_free := 0
	_clear(_loose_rows)
	for j in s.loose.size():
		var k := DiceDefs.DICE_COUNT + j
		if s.carry.has(k):
			continue
		loose_free += 1
		var row := _die_row("備用骰 %d" % (j + 1), s.loose[j], me.weapon_id, false)
		row.gui_input.connect(_on_row_input.bind(row, func() -> void: _click_other(k)))
		_loose_rows.add_child(row)
	for k in DiceDefs.DICE_COUNT:   # 沒帶著的武器骰也列在備用（換回來用）
		if s.carry.has(k):
			continue
		loose_free += 1
		var row := _die_row("武器骰 %d" % (k + 1), s.wdice[k], me.weapon_id, false)
		row.gui_input.connect(_on_row_input.bind(row, func() -> void: _click_other(k)))
		_loose_rows.add_child(row)
	_loose_head.text = "沒帶的骰子 %d 顆" % loose_free
	_loose_head.visible = loose_free > 0
	_loose_scroll.visible = loose_free > 0
	_loose_scroll.custom_minimum_size = Vector2(0, minf(LOOSE_MAX_H, _loose_rows.get_combined_minimum_size().y))
	_spare_head.text = "備用武器 %d / %d（換上後右鍵要重擲）" % [s.spares.size(), DiceDefs.SPARE_WEAPONS]
	_clear(_spare_rows)
	for w in s.spares.size():
		_spare_rows.add_child(_spare_row(s.spares[w], w))
	if not _can_change:
		_hint.text = "只能在逛地圖時換"
	elif selected >= 0:
		_hint.text = "已選第 %d 顆：再點要換上的那顆" % (selected + 1)
	else:
		_hint.text = "先點一顆帶著的，再點要換上的那顆"


func _click_carry(s: DiceRun.Seat, i: int) -> void:
	if not _can_change:
		return
	if selected < 0 or selected == i:
		selected = -1 if selected == i else i
	else:
		op_requested.emit([InputCmd.OP_DICE_CARRY, selected, s.carry[i]])
		selected = -1
	_key = []


func _click_other(k: int) -> void:
	if not _can_change or selected < 0:
		return
	op_requested.emit([InputCmd.OP_DICE_CARRY, selected, k])
	selected = -1
	_key = []


func _on_row_input(event: InputEvent, row: Control, action: Callable) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		action.call()
		row.accept_event()


static func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


# 一顆骰子一列：名稱 + 6 面（小圖）；選起來的金框
func _die_row(tag: String, die: Array, weapon_id: StringName, picked: bool) -> PanelContainer:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _can_change else Control.CURSOR_ARROW
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.1) if picked else Color(1, 1, 1, 0.03)
	box.border_color = UiKit.GOLD if picked else Color(1, 1, 1, 0.08)
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(4)
	row.add_theme_stylebox_override(&"panel", box)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var l := UiKit.label(tag, UiKit.FONT_NOTE, Color(1, 1, 1, 0.75))
	l.custom_minimum_size.x = 110
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	for f: StringName in die:
		var v := DicePanel.DieView.new(-1, FACE)
		v.show_face(f, weapon_id, false, false)
		h.add_child(v)
	return row


func _spare_row(inst: Dictionary, w: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := UiKit.label(WeaponDropDefs.display_name(inst), UiKit.FONT_NOTE, ItemDefs.RARITIES[inst.rarity].color)
	v.add_child(name_l)
	var faces := HBoxContainer.new()
	faces.add_theme_constant_override(&"separation", 4)
	faces.mouse_filter = Control.MOUSE_FILTER_IGNORE
	DiceRun.ensure_dice(inst)
	for f: StringName in inst.dice[0]:
		var d := DicePanel.DieView.new(-1, 32.0)
		d.show_face(f, Loadout.weapon_of(inst), false, false)
		faces.add_child(d)
	v.add_child(faces)
	h.add_child(v)
	var b := UiKit.button("換上", UiKit.BUTTON_S)
	b.disabled = not _can_change
	b.pressed.connect(func() -> void: op_requested.emit([InputCmd.OP_DICE_WEAPON, w]))
	h.add_child(b)
	return h
