# 鍛造祭壇的合成（Build 改版第 8 步，2026-10-30 許家慶決定：兩把各挑一條詞條留下、其他重抽；2026-10-31 使用者要求改成兩格放武器）
# 站在祭壇旁、背包開著時顯示在背包左邊：兩個武器格 → 結果。放進格子：背包裡拖過來、拿著點格子、對武器按右鍵、把武器拖到另一把上（兩把一起放）；
# 點格子拿出來。放了一把後背包裡能和它合的武器發亮、其他變暗（InventoryPanel 讀 glow / dims）。
# 兩把同種、同稀有度、不是橘色才能合：上面寫合成成什麼，兩把各點一條詞條留下，按「合成」送 [OP_MERGE, a, b, 留 a 的, 留 b 的]；結果等權威端
# 條件不符時寫原因、按鈕不能按；離開祭壇、背包關掉就清空
class_name ForgePanel
extends PanelContainer

signal op_requested(op: Array)

const ROW := {"size": Vector2(300, 40), "font": UiKit.FONT_NOTE}
const SLOT_SIZE := Vector2(140, 140)
const SLOT_NAMES := ["武器 1", "武器 2"]

var bag: InventoryPanel                 # 拿著的武器從這裡接過來（HUD 設定）
var uids: Array[StringName] = [&"", &""]   # 兩個格子放的武器（背包或手上的 uid）
var _keep: Array[StringName] = [&"", &""]  # 兩把各自選中的詞條
var _me: Player
var _shown := []                        # 目前畫的格子與詞條（變了才重建按鈕）
var _slots: Array[Control] = []
var _rows: Array[VBoxContainer] = []
var _heads: Array[Label] = []
var _title := UiKit.label("鍛造祭壇", UiKit.FONT_BODY, UiKit.GOLD)
var _result := UiKit.label("", UiKit.FONT_NOTE)
var _status := UiKit.label("", UiKit.FONT_NOTE, UiKit.ALERT)
var _ok := UiKit.button("合成", {"size": Vector2(300, 48), "font": UiKit.FONT_NOTE})


func _init() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = UiKit.SLOT_BG
	bg.border_color = UiKit.GOLD
	bg.set_border_width_all(1)
	bg.set_content_margin_all(14)
	add_theme_stylebox_override(&"panel", bg)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	box.add_child(_title)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override(&"separation", 10)
	for i in 2:
		var s := Control.new()
		s.custom_minimum_size = SLOT_SIZE
		s.mouse_filter = Control.MOUSE_FILTER_STOP
		s.draw.connect(_draw_slot.bind(i))
		s.gui_input.connect(_slot_input.bind(i))
		_slots.append(s)
		slots.add_child(s)
		if i == 0:
			slots.add_child(UiKit.label("+", UiKit.FONT_HEADING, UiKit.GOLD))
	box.add_child(slots)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size.x = SLOT_SIZE.x * 2 + 40
	box.add_child(_result)
	for i in 2:
		var head := UiKit.label("", UiKit.FONT_NOTE, Color(1, 1, 1, 0.8))
		_heads.append(head)
		box.add_child(head)
		var row := VBoxContainer.new()
		row.add_theme_constant_override(&"separation", 4)
		_rows.append(row)
		box.add_child(row)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = SLOT_SIZE.x * 2 + 40
	box.add_child(_status)
	_ok.pressed.connect(confirm)
	box.add_child(_ok)
	add_child(box)
	visible = false


# 放進第一個空格（已經放了就不動）；回傳有沒有放
func put(uid: StringName) -> bool:
	if uid == &"" or uids.has(uid) or _me == null or _find(_me, uid).is_empty():
		return false
	var i := uids.find(&"")
	if i < 0:
		return false
	_set_slot(i, uid)
	return true


func take(i: int) -> void:
	_set_slot(i, &"")


func _set_slot(i: int, uid: StringName) -> void:
	uids[i] = uid
	var inst := _find(_me, uid) if _me != null else {}
	_keep[i] = inst.affixes[0] if not inst.is_empty() and not inst.affixes.is_empty() else &""
	_update()


# 背包拖著武器在面板上放開（拖曳放開時滑鼠事件還在背包）：放在哪一格就放那格，放在面板其他地方放進空格
func drop_weapon(uid: StringName, global_at: Vector2) -> void:
	for i in 2:
		if _slots[i].get_global_rect().has_point(global_at) and not uids.has(uid):
			_set_slot(i, uid)
			return
	put(uid)


# 點格子：手上拿著背包的武器就放進來，否則把格子裡的拿出來
func _slot_input(event: InputEvent, i: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var held := bag.take_held_weapon() if bag != null else &""
	if held != &"":
		if not uids.has(held):
			_set_slot(i, held)
	elif uids[i] != &"":
		take(i)
	_slots[i].accept_event()


# 能不能合；不能時回傳原因（給玩家看）
func reason() -> String:
	var a := _find(_me, uids[0]) if _me != null else {}
	var b := _find(_me, uids[1]) if _me != null else {}
	if a.is_empty() and b.is_empty():
		return "放進兩把同種、同稀有度的武器（拖過來、點格子或右鍵）"
	if a.is_empty() or b.is_empty():
		var one := b if a.is_empty() else a
		return "再放一把%s %s" % [ItemDefs.RARITIES[one.rarity].name, ItemDefs.ITEMS[one.base].name]
	if a.base != b.base:
		return "要同種武器（%s / %s）" % [ItemDefs.ITEMS[a.base].name, ItemDefs.ITEMS[b.base].name]
	if a.rarity != b.rarity:
		return "稀有度要一樣（%s / %s）" % [ItemDefs.RARITIES[a.rarity].name, ItemDefs.RARITIES[b.rarity].name]
	if WeaponDropDefs.next_rarity(a.rarity) == &"":
		return "%s武器不能再合成" % ItemDefs.RARITIES[a.rarity].name
	return ""


# 放了一把、另一格空著時：背包裡能和它合的武器（InventoryPanel 畫發亮；其他變暗）
func glow(inst: Dictionary) -> bool:
	if not visible or _me == null or inst.is_empty() or uids.has(inst.uid) or not uids.has(&""):
		return false
	var placed := _find(_me, uids[0] if uids[0] != &"" else uids[1])
	return not placed.is_empty() and WeaponDropDefs.can_merge(placed, inst)


func dims(inst: Dictionary) -> bool:
	if not visible or not uids.has(&"") or uids == [&"", &""]:
		return false
	return inst.is_empty() or (not uids.has(inst.uid) and not glow(inst))


func slot_of(uid: StringName) -> int:
	return uids.find(uid) if visible and uid != &"" else -1


func confirm() -> void:
	if not visible or reason() != "":
		return
	op_requested.emit([InputCmd.OP_MERGE, String(uids[0]), String(uids[1]), String(_keep[0]), String(_keep[1])])
	uids = [&"", &""]
	_keep = [&"", &""]
	_update()


func close() -> void:
	visible = false
	uids = [&"", &""]
	_keep = [&"", &""]
	_shown = []


# 每幀（HUD._process）：站在鍛造祭壇旁、背包開著才顯示；格子裡的武器不見了就清掉那格
func refresh(world: World, me: Player, inventory_open: bool) -> void:
	_me = me
	if me == null or me.is_dead or not inventory_open or not world.near_forge(me):
		if visible:
			close()
		return
	visible = true
	for i in 2:
		if uids[i] != &"" and _find(me, uids[i]).is_empty():
			uids[i] = &""
	_update()


func _update() -> void:
	if _me == null:
		return
	var a := _find(_me, uids[0])
	var b := _find(_me, uids[1])
	var why := reason()
	var key := [uids.duplicate(), _keep.duplicate(), a.get("rarity", &""), b.get("rarity", &""), why]
	if key == _shown:
		return
	_shown = key
	for s in _slots:
		s.queue_redraw()
	_status.text = why
	_status.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.7) if uids.has(&"") else UiKit.ALERT)
	_ok.disabled = why != ""
	var ok := why == ""
	_result.visible = ok
	if ok:
		var to: Dictionary = ItemDefs.RARITIES[WeaponDropDefs.next_rarity(b.rarity)]
		_result.text = "→ 合成成%s %s：兩把各點一條詞條留下，其他重抽" % [to.name, ItemDefs.ITEMS[b.base].name]
		_result.add_theme_color_override(&"font_color", to.color)
	for i in 2:
		var inst: Dictionary = [a, b][i]
		_heads[i].visible = ok
		_heads[i].text = "%s 留哪一條：%s" % [SLOT_NAMES[i], "" if inst.is_empty() or not inst.affixes.is_empty() else "（沒有詞條）"]
		_rebuild_row(i, inst if ok else {})


func _rebuild_row(i: int, inst: Dictionary) -> void:
	var row := _rows[i]
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()
	for id: StringName in inst.get("affixes", []):
		var a: Dictionary = WeaponDropDefs.AFFIXES[id]
		var b := UiKit.button(("● " if _keep[i] == id else "○ ") + a.desc, ROW)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_FILL   # 說明長短不一：同一排都撐滿面板寬，左緣對齊
		var color: Color = BondDefs.BONDS[a.bond].color
		b.add_theme_color_override(&"font_color", color if _keep[i] == id else color.darkened(0.35))
		b.add_theme_color_override(&"font_hover_color", color.lightened(0.3))
		b.pressed.connect(choose.bind(i, id))
		row.add_child(b)


func choose(i: int, id: StringName) -> void:
	_keep[i] = id
	_update()


func _draw_slot(i: int) -> void:
	var s := _slots[i]
	var r := Rect2(Vector2.ZERO, s.size)
	var font := s.get_theme_default_font()
	var inst := _find(_me, uids[i]) if _me != null and uids[i] != &"" else {}
	s.draw_rect(r, Color(0, 0, 0, 0.35))
	s.draw_rect(r.grow(-1), UiKit.GOLD if not inst.is_empty() else Color(1, 1, 1, 0.35), false, 2.0)
	s.draw_string(font, Vector2(8, 22), SLOT_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))
	if inst.is_empty():
		s.draw_string(font, Vector2(0, r.size.y / 2.0 + 8), "放武器", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, Color(1, 1, 1, 0.35))
		return
	var cells := Inventory.cells_of(inst.base, 0)
	var ext := Vector2i.ZERO
	for c in cells:
		ext = Vector2i(maxi(ext.x, c.x + 1), maxi(ext.y, c.y + 1))
	var area := Vector2(r.size.x - 20, r.size.y - 60)
	var cell_px := minf(area.x / ext.x, area.y / ext.y)
	var at := Vector2((r.size.x - cell_px * ext.x) / 2.0, 30 + (area.y - cell_px * ext.y) / 2.0)
	UiKit.draw_item(s, font, inst.base, at, cell_px, 0, inst.rarity, 1.0, inst)
	s.draw_string(font, Vector2(0, r.size.y - 10), "%s %s" % [ItemDefs.RARITIES[inst.rarity].name, ItemDefs.ITEMS[inst.base].name],
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 16, ItemDefs.RARITIES[inst.rarity].color)


static func _find(me: Player, uid: StringName) -> Dictionary:
	if me == null or uid == &"":
		return {}
	for w: Dictionary in me.weapon_slots:
		if not w.is_empty() and w.uid == uid:
			return w
	for e: Dictionary in me.inventory.entries:
		if e.uid == uid:
			return e.get("weapon", {})
	return {}
