# 背包介面（D3 / D4，Tab 開關）：上方 2 格裝備欄、下方 8 × 6 背包、右邊「腳邊」欄（按得到 F 的地上道具）
# 滑鼠拖曳搬動、拖著時按 R 旋轉、拖到腳邊或面板外面丟在地上；武器拖到同種同稀有度的武器上就合成，拖到裝備欄就裝上
# 腳邊的道具拖進背包 = 撿起放在那一格；撿不下時（show_full）標出那一件、建議拿掉哪件就放得下
# 滑鼠停著（或拖著）的東西在下方顯示名稱、稀有度、效果 / 詞條
# 只送操作（op_requested → InputCollector → InputCmd.inv_ops），實際擺放由權威端決定，畫面照本機玩家的狀態畫
class_name InventoryPanel
extends Control

signal op_requested(op: Array)

const CELL := 52
const PAD := 14
const TITLE_H := 50   # 標題 + 一行操作說明
const SLOT_LABEL_H := 20
const SLOTS_H := CELL * 2 + SLOT_LABEL_H + 12   # 裝備欄一格 = 4 × 2 個背包格子大
const INFO_H := 110
const FEET_W := 220      # 腳邊欄的寬度
const FEET_HEAD := 26    # 腳邊欄標題的高度
const FEET_ROW := 46     # 腳邊欄每一列的高度
const FEET_CELL := 8.0   # 腳邊欄形狀小圖每格的大小
const HINT := "拖曳搬動 · 拖著按 R 旋轉 · 拖到腳邊丟掉 · 拖到同種同色武器上合成 · 腳邊的拖進背包撿起"

var world: World
var local_peer := World.HOST_PEER_ID

var _drag: Dictionary = {}   # 拖曳中：{ uid, id, rot, anchor（形狀格子的索引，對齊滑鼠所在格）, weapon（武器實例或 {}）, pickup_id（從腳邊拖的才有） }
var _hover_uid := &""
var _hover_pickup := 0
var _feet: Array[ItemPickup] = []   # 腳邊欄的地上道具（每幀照本機玩家的位置更新）
var _full_pickup := 0               # 撿不下的地上道具（show_full）；不在腳邊了就不顯示
var _suggest := &""                 # 建議拿掉的背包條目
var _suggest_key := 0               # 算 _suggest 時的背包與目標，有變才重算


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bag: Vector2i = ItemDefs.BAG_SIZE
	custom_minimum_size = Vector2(bag.x * CELL + PAD * 3 + FEET_W, PAD * 2 + TITLE_H + SLOTS_H + bag.y * CELL + INFO_H)
	visibility_changed.connect(func() -> void:
		_drag = {}
		_full_pickup = 0)


# 撿不下 pickup_id 那個地上道具：腳邊標出它，提示拿掉哪件就放得下（面板要先打開，關掉就清除）
func show_full(pickup_id: int) -> void:
	_full_pickup = pickup_id
	_suggest_key = 0


func _player() -> Player:
	return world.players.get(local_peer) if world != null else null


func _grid_origin() -> Vector2:
	return Vector2(PAD, PAD + TITLE_H + SLOTS_H)


func _slot_rect(i: int) -> Rect2:
	return Rect2(Vector2(PAD + i * CELL * 4 + 4, PAD + TITLE_H + SLOT_LABEL_H), Vector2(CELL * 4 - 8, CELL * 2 - 4))


func _slot_at(local: Vector2) -> int:
	for i in 2:
		if _slot_rect(i).has_point(local):
			return i
	return -1


func _cell_at(local: Vector2) -> Vector2i:
	var p := (local - _grid_origin()) / CELL
	return Vector2i(floori(p.x), floori(p.y))


func _in_grid(local: Vector2) -> bool:
	var c := _cell_at(local)
	var bag: Vector2i = ItemDefs.BAG_SIZE
	return c.x >= 0 and c.y >= 0 and c.x < bag.x and c.y < bag.y


func _process(_delta: float) -> void:
	if not visible:
		return
	var me := _player()
	_feet.clear()
	if me != null:
		world.reachable_pickups(me, _feet)
	_update_suggestion(me)
	queue_redraw()


# 撿不下的那一件還在腳邊時，算拿掉哪一件就放得下；背包或目標有變才重算
func _update_suggestion(me: Player) -> void:
	var target := _full_target()
	if target == null or me == null:
		_suggest = &""
		_suggest_key = 0
		return
	var key := hash([target.id, me.inventory.entries])
	if key != _suggest_key:
		_suggest_key = key
		_suggest = me.inventory.suggest_removal(target.item_id)


func _full_target() -> ItemPickup:
	for ip in _feet:
		if ip.id == _full_pickup:
			return ip
	return null


func _feet_rect() -> Rect2:
	return Rect2(Vector2(PAD * 2 + ItemDefs.BAG_SIZE.x * CELL, PAD + TITLE_H), Vector2(FEET_W, SLOTS_H + ItemDefs.BAG_SIZE.y * CELL))


func _feet_rows() -> int:
	return mini(_feet.size(), floori((_feet_rect().size.y - FEET_HEAD) / FEET_ROW))


func _feet_row_rect(i: int) -> Rect2:
	var r := _feet_rect()
	return Rect2(r.position + Vector2(0, FEET_HEAD + i * FEET_ROW), Vector2(FEET_W, FEET_ROW - 6))


func _pickup_at(local: Vector2) -> ItemPickup:
	for i in _feet_rows():
		if _feet_row_rect(i).has_point(local):
			return _feet[i]
	return null


func _gui_input(event: InputEvent) -> void:
	var me := _player()
	if me == null:
		return
	if event is InputEventMouseMotion:
		_hover_uid = _uid_at(me, event.position)
		var ip := _pickup_at(event.position)
		_hover_pickup = ip.id if ip != null else 0
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_drag(me, event.position)
		elif not _drag.is_empty():
			_finish_drag(me, event.position)
		accept_event()


# R 旋轉在 _input 處理：拖曳中搶先接走，不會觸發重新開始
func _input(event: InputEvent) -> void:
	if visible and not _drag.is_empty() and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_R:
		_drag.rot = (_drag.rot + 1) % 4
		get_viewport().set_input_as_handled()


# 滑鼠下面是哪個東西（裝備欄的武器或背包的條目）
func _uid_at(me: Player, local: Vector2) -> StringName:
	var slot := _slot_at(local)
	if slot >= 0:
		return me.weapon_slots[slot].get("uid", &"")
	if _in_grid(local):
		return me.inventory.occupied().get(_cell_at(local), &"")
	return &""


func _start_drag(me: Player, local: Vector2) -> void:
	var ip := _pickup_at(local)
	if ip != null:
		_drag = {"uid": &"", "id": ip.item_id, "rot": 0, "anchor": 0, "weapon": ip.weapon, "pickup_id": ip.id}
		return
	var slot := _slot_at(local)
	if slot >= 0:
		var inst: Dictionary = me.weapon_slots[slot]
		if not inst.is_empty():
			_drag = {"uid": inst.uid, "id": inst.base, "rot": 0, "anchor": 0, "weapon": inst}
		return
	var uid: StringName = me.inventory.occupied().get(_cell_at(local), &"")
	if uid == &"":
		return
	var e := me.inventory.find(uid)
	var cells := Inventory.cells_of(e.id, e.rot)
	_drag = {"uid": uid, "id": e.id, "rot": e.rot, "anchor": maxi(0, cells.find(_cell_at(local) - e.cell)), "weapon": e.get("weapon", {})}


func _drag_cell(local: Vector2) -> Vector2i:
	var cells := Inventory.cells_of(_drag.id, _drag.rot)
	return _cell_at(local) - cells[mini(_drag.anchor, cells.size() - 1)]


# 放開滑鼠時：拖到武器上 = 合成、拖到裝備欄 = 裝上、拖到背包 = 搬動、拖到面板外 = 丟掉
func _merge_target(me: Player, local: Vector2) -> Dictionary:
	if _drag.weapon.is_empty() or _drag.has("pickup_id"):
		return {}
	var slot := _slot_at(local)
	var target: Dictionary = {}
	if slot >= 0:
		target = me.weapon_slots[slot]
	elif _in_grid(local):
		var uid: StringName = me.inventory.occupied().get(_cell_at(local), &"")
		target = me.inventory.find(uid).get("weapon", {}) if uid != &"" else {}
	return target if WeaponDropDefs.can_merge(_drag.weapon, target) else {}


func _finish_drag(me: Player, local: Vector2) -> void:
	if _drag.has("pickup_id"):   # 從腳邊拖進背包 = 撿起放在那一格；放在別處就留在地上
		if _in_grid(local):
			var cell := _drag_cell(local)
			op_requested.emit([InputCmd.OP_PICKUP, _drag.pickup_id, cell.x, cell.y, _drag.rot])
		_drag = {}
		return
	var uid := String(_drag.uid)
	var merge := _merge_target(me, local)
	var slot := _slot_at(local)
	if not merge.is_empty():
		op_requested.emit([InputCmd.OP_MERGE, uid, String(merge.uid)])
	elif slot >= 0:
		if not _drag.weapon.is_empty():
			op_requested.emit([InputCmd.OP_EQUIP, uid, slot])
	elif _in_grid(local):
		var target := _drag_cell(local)
		op_requested.emit([InputCmd.OP_MOVE, uid, target.x, target.y, _drag.rot])
	elif _feet_rect().has_point(local) or not Rect2(Vector2.ZERO, size).has_point(local):
		op_requested.emit([InputCmd.OP_DROP, uid])
	_drag = {}


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.SLOT_BG)
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.SLOT_OUTLINE, false, 1.0)
	draw_string(font, Vector2(PAD, PAD + 22), "背包", HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	var me := _player()
	var full := _full_target()
	if full != null:
		draw_string(font, Vector2(PAD, PAD + 42), _full_text(me, full), HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, 14, UiKit.DENY)
	else:
		draw_string(font, Vector2(PAD, PAD + 42), HINT, HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, 12, Color(1, 1, 1, 0.55))
	_draw_slots(font, me)
	_draw_feet(font, full)
	var bag: Vector2i = ItemDefs.BAG_SIZE
	var o := _grid_origin()
	for y in bag.y:
		for x in bag.x:
			draw_rect(Rect2(o + Vector2(x, y) * CELL, Vector2(CELL, CELL)).grow(-1), Color(1, 1, 1, 0.05))
	if me == null:
		return
	for e: Dictionary in me.inventory.entries:
		var dim: bool = not _drag.is_empty() and _drag.uid == e.uid
		_draw_item(font, e.id, e.cell, e.rot, _rarity_of(e), 0.35 if dim else 1.0)
	if _suggest != &"":
		_draw_suggestion(me.inventory.find(_suggest))
	if not _drag.is_empty():
		var local := get_local_mouse_position()
		if not _merge_target(me, local).is_empty():
			var r := _hover_rect(me, local)
			draw_rect(r, Color(1, 0.85, 0.3, 0.35))
			draw_string(font, r.position + Vector2(6, r.size.y - 8), "合成", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.GOLD)
		elif _in_grid(local):
			var target := _drag_cell(local)
			var ok := me.inventory.fits(_drag.id, target, _drag.rot, _drag.uid)
			for c in Inventory.cells_of(_drag.id, _drag.rot):
				var r := Rect2(o + Vector2(target + c) * CELL, Vector2(CELL, CELL)).grow(-2)
				draw_rect(r, Color(0.3, 1, 0.4, 0.35) if ok else Color(1, 0.3, 0.3, 0.35))
			_draw_item(font, _drag.id, target, _drag.rot, _drag_rarity(), 0.85)
	_draw_info(font, me)


# 撿不下時取代操作說明的那一行
func _full_text(me: Player, target: ItemPickup) -> String:
	var e := me.inventory.find(_suggest) if me != null and _suggest != &"" else {}
	if e.is_empty():
		return "放不下「%s」：拿掉一件也不夠，要整理背包" % target.display_name()
	var item_name: String = WeaponDropDefs.display_name(e.weapon) if e.has("weapon") else ItemDefs.ITEMS[e.id].name
	return "放不下「%s」：拿掉「%s」就放得下" % [target.display_name(), item_name]


# 建議拿掉的那一件：每格閃爍的紅色虛線框
func _draw_suggestion(e: Dictionary) -> void:
	if e.is_empty():
		return
	var color := Color(UiKit.DENY, 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008))
	for c in Inventory.cells_of(e.id, e.rot):
		var r := Rect2(_grid_origin() + Vector2(e.cell + c) * CELL, Vector2(CELL, CELL)).grow(-1)
		var corners: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for i in 4:
			draw_dashed_line(corners[i], corners[(i + 1) % 4], color, 2.0, 6.0)


# 腳邊欄：按得到 F 的地上道具，撿不下的那一件金框
func _draw_feet(font: Font, target: ItemPickup) -> void:
	var r := _feet_rect()
	draw_string(font, r.position + Vector2(0, 14), "腳邊（拖進背包撿起）", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.55))
	if _feet.is_empty():
		draw_string(font, r.position + Vector2(0, FEET_HEAD + 20), "（附近沒有東西）", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.3))
		return
	for i in _feet_rows():
		var ip := _feet[i]
		var row := _feet_row_rect(i)
		var color: Color = ItemDefs.RARITIES[ip.rarity()].color
		var alpha := 0.35 if _drag.get("pickup_id", 0) == ip.id else 1.0
		draw_rect(row, Color(1, 1, 1, 0.05))
		draw_rect(row, UiKit.GOLD if ip == target else UiKit.SLOT_OUTLINE, false, 3.0 if ip == target else 1.0)
		var shape := UiKit.shape_size(ip.item_id, FEET_CELL)
		UiKit.draw_shape(self, ip.item_id, row.position + Vector2(6, (row.size.y - shape.y) / 2.0), FEET_CELL, color, alpha)
		draw_string(font, row.position + Vector2(46, row.size.y / 2.0 + 6), ip.display_name(), HORIZONTAL_ALIGNMENT_LEFT, FEET_W - 52, 15, Color(color, alpha))


func _rarity_of(e: Dictionary) -> StringName:
	return e.weapon.rarity if e.has("weapon") else ItemDefs.ITEMS[e.id].rarity


func _drag_rarity() -> StringName:
	return _drag.weapon.rarity if not _drag.weapon.is_empty() else ItemDefs.ITEMS[_drag.id].rarity


# 合成提示框：滑鼠下面那個武器所在的裝備欄或背包格
func _hover_rect(me: Player, local: Vector2) -> Rect2:
	var slot := _slot_at(local)
	if slot >= 0:
		return _slot_rect(slot)
	return Rect2(_grid_origin() + Vector2(_cell_at(local)) * CELL, Vector2(CELL, CELL))


func _draw_slots(font: Font, me: Player) -> void:
	for i in 2:
		var r := _slot_rect(i)
		var inst: Dictionary = me.weapon_slots[i] if me != null else {}
		var active := me != null and me.active_slot == i and not inst.is_empty()
		draw_string(font, r.position + Vector2(0, -6), "裝備 %d%s" % [i + 1, "（使用中）" if active else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			UiKit.GOLD if active else Color(1, 1, 1, 0.55))
		draw_rect(r, Color(1, 1, 1, 0.05))
		if inst.is_empty():
			draw_string(font, r.position + Vector2(10, r.size.y / 2.0 + 6), "（空）", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.3))
			continue
		var color: Color = ItemDefs.RARITIES[inst.rarity].color
		var dim: bool = not _drag.is_empty() and _drag.uid == inst.uid
		draw_rect(r.grow(-3), Color(color.darkened(0.55), 0.4 if dim else 0.9))
		draw_rect(r.grow(-3), UiKit.GOLD if active else color, false, 3.0 if active else 2.0)
		draw_string(font, r.position + Vector2(12, 30), WeaponDropDefs.display_name(inst), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 17, color)
		var b := WeaponDropDefs.base_stats(inst)
		draw_string(font, r.position + Vector2(12, 54), "攻擊力 %.1f · 詞條 %d 條" % [b.damage, inst.affixes.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.7))


func _draw_item(font: Font, id: StringName, cell: Vector2i, rot: int, rarity: StringName, alpha: float) -> void:
	var def: Dictionary = ItemDefs.ITEMS[id]
	var color: Color = ItemDefs.RARITIES[rarity].color
	var o := _grid_origin()
	var cells := Inventory.cells_of(id, rot)
	for c in cells:
		var r := Rect2(o + Vector2(cell + c) * CELL, Vector2(CELL, CELL)).grow(-3)
		draw_rect(r, Color(color.darkened(0.55), 0.9 * alpha))
		draw_rect(r, Color(color, alpha), false, 2.0)
	var first: Vector2 = o + Vector2(cell + cells[0]) * CELL
	draw_string(font, first + Vector2(5, 20), String(def.name).substr(0, 2), HORIZONTAL_ALIGNMENT_LEFT, CELL - 6, 15, Color(1, 1, 1, alpha))


# 下方說明：滑鼠停著（或拖著）的東西：道具的效果、武器的詞條（腳邊的道具也一樣）
func _draw_info(font: Font, me: Player) -> void:
	var y := _grid_origin().y + ItemDefs.BAG_SIZE.y * CELL + 26
	var info := _info_of(me)
	if info.is_empty():
		draw_string(font, Vector2(PAD, y), "%d 個東西" % me.inventory.entries.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.55))
		return
	draw_string(font, Vector2(PAD, y), info.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, info.color)
	draw_multiline_string(font, Vector2(PAD, y + 22), "\n".join(info.lines), HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, 14, -1, Color(1, 1, 1, 0.85))


func _info_of(me: Player) -> Dictionary:
	var pickup_id: int = _drag.get("pickup_id", 0) if not _drag.is_empty() else _hover_pickup
	if pickup_id != 0:
		var ip := world.entities.get(pickup_id) as ItemPickup
		if ip == null:
			return {}
		var on_ground := UiKit.item_info(ip.item_id, ip.weapon)
		on_ground.title += "（在地上）"
		return on_ground
	var uid: StringName = _drag.uid if not _drag.is_empty() else _hover_uid
	if uid == &"":
		return {}
	for s in me.weapon_slots:
		if s.get("uid", &"") == uid:
			return UiKit.item_info(s.base, s)
	var e := me.inventory.find(uid)
	if e.is_empty():
		return {}
	var info := UiKit.item_info(e.id, e.get("weapon", {}))
	if e.has("weapon"):
		info.title += "（在背包裡不生效）"
	return info
