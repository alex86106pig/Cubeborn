# 背包介面（D3，I 開關）：8 × 6 格，滑鼠拖曳搬動、拖著時按 R 旋轉、拖到面板外面丟在地上；滑鼠停在道具上顯示名稱與效果
# 只送操作（op_requested → InputCollector → InputCmd.inv_ops），實際擺放由權威端決定，畫面照本機玩家的 inventory 畫
class_name InventoryPanel
extends Control

signal op_requested(op: Array)

const CELL := 52
const PAD := 14
const TITLE_H := 34
const INFO_H := 84

var world: World
var local_peer := World.HOST_PEER_ID

var _drag: Dictionary = {}   # 拖曳中：{ uid, id, rot, anchor（形狀格子的索引，對齊滑鼠所在格） }
var _hover_uid := &""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bag: Vector2i = ItemDefs.BAG_SIZE
	custom_minimum_size = Vector2(bag.x * CELL + PAD * 2, bag.y * CELL + PAD * 2 + TITLE_H + INFO_H)
	visibility_changed.connect(func() -> void: _drag = {})


func _player() -> Player:
	return world.players.get(local_peer) if world != null else null


func _grid_origin() -> Vector2:
	return Vector2(PAD, PAD + TITLE_H)


func _cell_at(local: Vector2) -> Vector2i:
	var p := (local - _grid_origin()) / CELL
	return Vector2i(floori(p.x), floori(p.y))


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var me := _player()
	if me == null:
		return
	if event is InputEventMouseMotion:
		var c := _cell_at(event.position)
		_hover_uid = me.inventory.occupied().get(c, &"")
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_drag(me, _cell_at(event.position))
		elif not _drag.is_empty():
			_finish_drag(event.position)
		accept_event()


# R 旋轉在 _input 處理：拖曳中搶先接走，不會觸發重新開始
func _input(event: InputEvent) -> void:
	if visible and not _drag.is_empty() and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_R:
		_drag.rot = (_drag.rot + 1) % 4
		get_viewport().set_input_as_handled()


func _start_drag(me: Player, cell: Vector2i) -> void:
	var uid: StringName = me.inventory.occupied().get(cell, &"")
	if uid == &"":
		return
	var e := me.inventory.find(uid)
	var cells := Inventory.cells_of(e.id, e.rot)
	_drag = {"uid": uid, "id": e.id, "rot": e.rot, "anchor": maxi(0, cells.find(cell - e.cell))}


func _drag_cell(local: Vector2) -> Vector2i:
	var cells := Inventory.cells_of(_drag.id, _drag.rot)
	return _cell_at(local) - cells[mini(_drag.anchor, cells.size() - 1)]


func _finish_drag(local: Vector2) -> void:
	if Rect2(Vector2.ZERO, size).has_point(local):
		var target := _drag_cell(local)
		op_requested.emit([InputCmd.OP_MOVE, String(_drag.uid), target.x, target.y, _drag.rot])
	else:
		op_requested.emit([InputCmd.OP_DROP, String(_drag.uid)])
	_drag = {}


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.SLOT_BG)
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.SLOT_OUTLINE, false, 1.0)
	draw_string(font, Vector2(PAD, PAD + 22), "背包", HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	draw_string(font, Vector2(PAD + 60, PAD + 22), "拖曳搬動 · 拖著按 R 旋轉 · 拖到外面丟掉", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.55))
	var bag: Vector2i = ItemDefs.BAG_SIZE
	var o := _grid_origin()
	for y in bag.y:
		for x in bag.x:
			draw_rect(Rect2(o + Vector2(x, y) * CELL, Vector2(CELL, CELL)).grow(-1), Color(1, 1, 1, 0.05))
	var me := _player()
	if me == null:
		return
	for e: Dictionary in me.inventory.entries:
		var dim: bool = not _drag.is_empty() and _drag.uid == e.uid
		_draw_item(font, e.id, e.cell, e.rot, 0.35 if dim else 1.0)
	if not _drag.is_empty():
		var local := get_local_mouse_position()
		var target := _drag_cell(local)
		var ok := me.inventory.fits(_drag.id, target, _drag.rot, _drag.uid)
		var inside := Rect2(Vector2.ZERO, size).has_point(local)
		for c in Inventory.cells_of(_drag.id, _drag.rot):
			var r := Rect2(o + Vector2(target + c) * CELL, Vector2(CELL, CELL)).grow(-2)
			draw_rect(r, (Color(0.3, 1, 0.4, 0.35) if ok else Color(1, 0.3, 0.3, 0.35)) if inside else Color(1, 1, 1, 0.15))
		_draw_item(font, _drag.id, target, _drag.rot, 0.85)
	_draw_info(font, me)


func _draw_item(font: Font, id: StringName, cell: Vector2i, rot: int, alpha: float) -> void:
	var def: Dictionary = ItemDefs.ITEMS[id]
	var color: Color = ItemDefs.RARITIES[def.rarity].color
	var o := _grid_origin()
	var cells := Inventory.cells_of(id, rot)
	for c in cells:
		var r := Rect2(o + Vector2(cell + c) * CELL, Vector2(CELL, CELL)).grow(-3)
		draw_rect(r, Color(color.darkened(0.55), 0.9 * alpha))
		draw_rect(r, Color(color, alpha), false, 2.0)
	var first: Vector2 = o + Vector2(cell + cells[0]) * CELL
	draw_string(font, first + Vector2(5, 20), String(def.name).substr(0, 2), HORIZONTAL_ALIGNMENT_LEFT, CELL - 6, 15, Color(1, 1, 1, alpha))


# 下方說明：滑鼠停著（或拖著）的道具名稱、稀有度、效果
func _draw_info(font: Font, me: Player) -> void:
	var id := &""
	if not _drag.is_empty():
		id = _drag.id
	elif _hover_uid != &"":
		var e := me.inventory.find(_hover_uid)
		if not e.is_empty():
			id = e.id
	var y := PAD + TITLE_H + ItemDefs.BAG_SIZE.y * CELL + 26
	if id == &"":
		draw_string(font, Vector2(PAD, y), "%d 個道具" % me.inventory.entries.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.55))
		return
	var def: Dictionary = ItemDefs.ITEMS[id]
	var rarity: Dictionary = ItemDefs.RARITIES[def.rarity]
	draw_string(font, Vector2(PAD, y), "%s（%s）" % [def.name, rarity.name], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, rarity.color)
	var desc: String = def.desc
	if not def.effects.all(ItemDefs.is_implemented):
		desc += "（效果尚未實作）"
	draw_string(font, Vector2(PAD, y + 24), desc, HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, 14, Color(1, 1, 1, 0.85))
