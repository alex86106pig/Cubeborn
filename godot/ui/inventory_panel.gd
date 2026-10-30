# 背包介面（D3 / D4，Tab 開關；Build 改版第 3 步起照對比頁 A：畫面右半邊、中間可以用滑鼠滾輪捲動）
# 由上到下：標題與操作說明（固定）→ 主手、副手的武器格子（道具鑲在這裡才生效）→ 羈絆件數 → 8 × 6 背包（只放東西）；右邊「腳邊」欄（按得到 F 的地上道具）
# → 滑鼠停著的說明（固定在底部）
# 滑鼠拖曳搬動、拖著時按 R 旋轉、拖到腳邊或面板外面丟在地上；道具拖到武器格子 = 鑲上、拖到背包 = 拿下來；
# 武器拖到主手 / 副手的名稱框就換上（拿不動的由權威端拒絕），拖到同種同稀有度的武器上合成；腳邊的拖進背包或武器格子 = 撿起放在那一格
# 撿不下時（show_full）標出那一件、建議拿掉背包裡哪件就放得下
# 只送操作（op_requested → InputCollector → InputCmd.inv_ops），實際擺放由權威端決定，畫面照本機玩家的狀態畫
class_name InventoryPanel
extends Control

signal op_requested(op: Array)
signal merge_choice(a: Dictionary, b: Dictionary)   # 在鍛造祭壇旁把有詞條的武器拖到另一把上：讓玩家挑要留的詞條（ForgePanel，第 8 步）

const CELL := 52          # 背包一格
const WCELL := 40         # 武器格子一格
const GRID_COLS := 5      # 武器格子最寬 5 格（WeaponDefs grid）
const GRID_W := GRID_COLS * WCELL
const HAND_GAP := 16      # 兩隻手之間；主手＋副手剛好和背包一樣寬（2 × 200 + 16 = 8 × 52）
const PAD := 14
const TITLE_H := 50       # 標題 + 一行操作說明（固定在上面）
const INFO_H := 110       # 說明（固定在下面）
const LABEL_H := 20
const HEAD_H := 50        # 主手 / 副手的名稱框（拖武器到這裡換上）
const SLOT_NAMES: Array[String] = ["主手", "副手（雙手武器不能拿）"]
const BOND_H := 44        # 羈絆一列（每個羈絆一格：名稱與件數、各階門檻）
const BOND_GAP := 6
const FEET_W := 220       # 腳邊欄的寬度
const FEET_HEAD := 26     # 腳邊欄標題的高度
const FEET_ROW := 46      # 腳邊欄每一列的高度
const FEET_CELL := 8.0    # 腳邊欄形狀小圖每格的大小
const SCROLL_STEP := 60.0
const MIN_VIEW_H := 360.0   # 捲動區至少這麼高（最小尺寸用）
const HINT := "拖到武器格子鑲上 · 拖進背包拿下來 · 拖著按 R 旋轉 · 拖到腳邊丟掉 · 武器拖到主手 / 副手換上 · 滾輪捲動"
# 武器格子的部位顏色（WeaponDefs.PARTS）：淡淡的底色，鑲上的道具畫在上面
const PART_COLORS := {"A": Color("5f7487"), "E": Color("9aa4ab"), "D": Color("8e6a33"), "H": Color("5e4433"), "G": Color("6a3f8f")}

var world: World
var local_peer := World.HOST_PEER_ID

var _drag: Dictionary = {}   # 拖曳中：{ uid, id, rot, anchor（形狀格子的索引，對齊滑鼠所在格）, weapon（武器實例或 {}）, pickup_id（從腳邊拖的才有） }
var _hover_uid := &""
var _hover_pickup := 0
var _hover_bond := &""
var _feet: Array[ItemPickup] = []   # 腳邊欄的地上道具（每幀照本機玩家的位置更新）
var _full_pickup := 0               # 撿不下的地上道具（show_full）；不在腳邊了就不顯示
var _suggest := &""                 # 建議拿掉的背包條目
var _suggest_key := 0               # 算 _suggest 時的背包與目標，有變才重算
var _scroll := 0.0                  # 中間捲動區往下捲了多少


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(PAD * 3 + GRID_W * 2 + HAND_GAP + FEET_W, PAD * 2 + TITLE_H + MIN_VIEW_H + INFO_H)
	visibility_changed.connect(func() -> void:
		_drag = {}
		_full_pickup = 0)


# 撿不下 pickup_id 那個地上道具：腳邊標出它，提示拿掉哪件就放得下（面板要先打開，關掉就清除）
func show_full(pickup_id: int) -> void:
	_full_pickup = pickup_id
	_suggest_key = 0


func _player() -> Player:
	return world.players.get(local_peer) if world != null else null


# ── 版面（面板座標；中間區塊往上捲 _scroll） ──

func _view_rect() -> Rect2:
	return Rect2(Vector2(0, PAD + TITLE_H), Vector2(size.x, size.y - PAD * 2 - TITLE_H - INFO_H))


func _content_top() -> float:
	return PAD + TITLE_H - _scroll


func _in_view(local: Vector2) -> bool:
	return _view_rect().has_point(local)


# 兩隻手的武器格子最多幾列（至少 4 列，空手時也留位置）
func _grid_rows(me: Player) -> int:
	var rows := 4
	if me != null:
		for inst in me.weapon_slots:
			if not inst.is_empty():
				rows = maxi(rows, WeaponDefs.grid_size(Loadout.weapon_of(inst)).y)
	return rows


func _hand_x(i: int) -> float:
	return PAD + i * (GRID_W + HAND_GAP)


func _slot_rect(i: int) -> Rect2:
	return Rect2(Vector2(_hand_x(i), _content_top() + LABEL_H), Vector2(GRID_W, HEAD_H))


# 那隻手的武器格子左上角（格子置中在 GRID_W 裡）
func _wgrid_origin(me: Player, i: int) -> Vector2:
	var cols := GRID_COLS
	var inst: Dictionary = me.weapon_slots[i]
	if not inst.is_empty():
		cols = WeaponDefs.grid_size(Loadout.weapon_of(inst)).x
	return Vector2(_hand_x(i) + (GRID_W - cols * WCELL) / 2.0, _content_top() + LABEL_H + HEAD_H + 8)


func _bonds_origin() -> Vector2:
	var me := _player()
	return Vector2(PAD, _content_top() + LABEL_H + HEAD_H + 8 + _grid_rows(me) * WCELL + 18 + LABEL_H)


func _bond_rect(i: int) -> Rect2:
	var w := (GRID_W * 2 + HAND_GAP - BOND_GAP * (BondDefs.BONDS.size() - 1)) / float(BondDefs.BONDS.size())
	return Rect2(_bonds_origin() + Vector2(i * (w + BOND_GAP), 0), Vector2(w, BOND_H))


func _bond_at(local: Vector2) -> StringName:
	if not _in_view(local):
		return &""
	var i := 0
	for bond: StringName in BondDefs.BONDS:
		if _bond_rect(i).has_point(local):
			return bond
		i += 1
	return &""


func _grid_origin() -> Vector2:
	return Vector2(PAD, _bonds_origin().y + BOND_H + 18 + LABEL_H)


func _content_height(me: Player) -> float:
	return _grid_origin().y - _content_top() + ItemDefs.BAG_SIZE.y * CELL + PAD


func _slot_at(local: Vector2) -> int:
	if not _in_view(local):
		return -1
	for i in 2:
		if _slot_rect(i).has_point(local):
			return i
	return -1


# 滑鼠下面是哪隻手的哪一格武器格子（外框內就算，能不能放由 Inventory 的 mask 判斷）：{ hand, cell } 或 {}
func _wcell_at(me: Player, local: Vector2) -> Dictionary:
	if me == null or not _in_view(local):
		return {}
	for i in 2:
		var inst: Dictionary = me.weapon_slots[i]
		if inst.is_empty():
			continue
		var gs := WeaponDefs.grid_size(Loadout.weapon_of(inst))
		var p := (local - _wgrid_origin(me, i)) / WCELL
		var c := Vector2i(floori(p.x), floori(p.y))
		if c.x >= 0 and c.y >= 0 and c.x < gs.x and c.y < gs.y:
			return {"hand": i, "cell": c}
	return {}


func _cell_at(local: Vector2) -> Vector2i:
	var p := (local - _grid_origin()) / CELL
	return Vector2i(floori(p.x), floori(p.y))


func _in_grid(local: Vector2) -> bool:
	var c := _cell_at(local)
	var bag: Vector2i = ItemDefs.BAG_SIZE
	return _in_view(local) and c.x >= 0 and c.y >= 0 and c.x < bag.x and c.y < bag.y


func _feet_rect() -> Rect2:
	return Rect2(Vector2(PAD * 2 + GRID_W * 2 + HAND_GAP, _view_rect().position.y), Vector2(FEET_W, _view_rect().size.y))


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


func _process(_delta: float) -> void:
	if not visible:
		return
	var me := _player()
	_feet.clear()
	if me != null:
		world.reachable_pickups(me, _feet)
		_scroll = clampf(_scroll, 0.0, maxf(0.0, _content_height(me) - _view_rect().size.y))
	_update_suggestion(me)
	queue_redraw()


# 撿不下的那一件還在腳邊時，算拿掉背包裡哪一件就放得下；背包或目標有變才重算
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


func _gui_input(event: InputEvent) -> void:
	var me := _player()
	if me == null:
		return
	if event is InputEventMouseMotion:
		_hover_uid = _uid_at(me, event.position)
		_hover_bond = _bond_at(event.position)
		var ip := _pickup_at(event.position)
		_hover_pickup = ip.id if ip != null else 0
	elif event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if event.pressed:
			_scroll += SCROLL_STEP * (1.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0)
			_scroll = clampf(_scroll, 0.0, maxf(0.0, _content_height(me) - _view_rect().size.y))
		accept_event()
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


# 滑鼠下面是哪個東西（主手 / 副手的武器、武器格子裡的道具、背包的條目）
func _uid_at(me: Player, local: Vector2) -> StringName:
	var slot := _slot_at(local)
	if slot >= 0:
		return me.weapon_slots[slot].get("uid", &"")
	var wc := _wcell_at(me, local)
	if not wc.is_empty():
		return me.loadout.container(wc.hand).occupied().get(wc.cell, &"")
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
	var inv: Inventory = null
	var cell := Vector2i.ZERO
	var wc := _wcell_at(me, local)
	if not wc.is_empty():
		inv = me.loadout.container(wc.hand)
		cell = wc.cell
	elif _in_grid(local):
		inv = me.inventory
		cell = _cell_at(local)
	if inv == null:
		return
	var uid: StringName = inv.occupied().get(cell, &"")
	if uid == &"":
		return
	var e := inv.find(uid)
	var cells := Inventory.cells_of(e.id, e.rot)
	_drag = {"uid": uid, "id": e.id, "rot": e.rot, "anchor": maxi(0, cells.find(cell - e.cell)), "weapon": e.get("weapon", {})}


# 拖著的東西左上角要放在哪一格（滑鼠所在格對齊抓住的那一格）
func _drag_cell(at: Vector2i) -> Vector2i:
	var cells := Inventory.cells_of(_drag.id, _drag.rot)
	return at - cells[mini(_drag.anchor, cells.size() - 1)]


# 放開滑鼠時：拖到武器上 = 合成、拖到主手 / 副手 = 換上；道具拖到武器格子 = 鑲上、拖到背包 = 搬動；拖到腳邊或面板外 = 丟掉
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
	var wc := _wcell_at(me, local) if _drag.weapon.is_empty() and _drag.get("id", &"") != &"corpse" else {}
	if _drag.has("pickup_id"):   # 從腳邊拖進背包 / 武器格子 = 撿起放在那一格；放在別處就留在地上
		if not wc.is_empty():
			var at := _drag_cell(wc.cell)
			op_requested.emit([InputCmd.OP_PICKUP, _drag.pickup_id, at.x, at.y, _drag.rot, wc.hand])
		elif _in_grid(local):
			var cell := _drag_cell(_cell_at(local))
			op_requested.emit([InputCmd.OP_PICKUP, _drag.pickup_id, cell.x, cell.y, _drag.rot])
		_drag = {}
		return
	var uid := String(_drag.uid)
	var merge := _merge_target(me, local)
	var slot := _slot_at(local)
	if not merge.is_empty():
		# 兩把都有詞條、站在鍛造祭壇旁：先挑要留的詞條；白色沒得挑、不在祭壇旁直接送（權威端回「要站在鍛造祭壇旁」）
		if not merge.affixes.is_empty() and world != null and world.near_forge(me):
			merge_choice.emit(_drag.weapon, merge)
		else:
			op_requested.emit([InputCmd.OP_MERGE, uid, String(merge.uid)])
	elif slot >= 0:
		if not _drag.weapon.is_empty():
			op_requested.emit([InputCmd.OP_EQUIP, uid, slot])
	elif not wc.is_empty():
		var at := _drag_cell(wc.cell)
		op_requested.emit([InputCmd.OP_MOVE, uid, at.x, at.y, _drag.rot, wc.hand])
	elif _in_grid(local):
		var target := _drag_cell(_cell_at(local))
		op_requested.emit([InputCmd.OP_MOVE, uid, target.x, target.y, _drag.rot])
	elif _feet_rect().has_point(local) or not Rect2(Vector2.ZERO, size).has_point(local):
		op_requested.emit([InputCmd.OP_DROP, uid])
	_drag = {}


# ── 畫 ──

func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.SLOT_BG)
	var me := _player()
	var full := _full_target()
	if me != null:
		_draw_slots(font, me)
		_draw_bonds(font, me)
		_draw_bag(font, me)
		_draw_drag(font, me)
	_draw_feet(font, full)
	# 固定的上下兩塊蓋在捲動區上面
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, PAD + TITLE_H)), UiKit.SLOT_BG)
	draw_rect(Rect2(Vector2(0, size.y - PAD - INFO_H), Vector2(size.x, PAD + INFO_H)), UiKit.SLOT_BG)
	draw_line(Vector2(PAD, PAD + TITLE_H - 2), Vector2(size.x - PAD, PAD + TITLE_H - 2), UiKit.SLOT_OUTLINE)
	draw_line(Vector2(PAD, size.y - PAD - INFO_H + 2), Vector2(size.x - PAD, size.y - PAD - INFO_H + 2), UiKit.SLOT_OUTLINE)
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.SLOT_OUTLINE, false, 1.0)
	draw_string(font, Vector2(PAD, PAD + 22), "背包（遊戲不暫停）", HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	if full != null:
		draw_string(font, Vector2(PAD, PAD + 42), _full_text(me, full), HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, 14, UiKit.DENY)
	else:
		draw_string(font, Vector2(PAD, PAD + 42), HINT, HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, 12, Color(1, 1, 1, 0.55))
	if me != null:
		_draw_scrollbar(me)
		_draw_info(font, me)


func _draw_scrollbar(me: Player) -> void:
	var view := _view_rect()
	var total := _content_height(me)
	if total <= view.size.y:
		return
	var h := view.size.y * view.size.y / total
	var y := view.position.y + (view.size.y - h) * _scroll / (total - view.size.y)
	draw_rect(Rect2(Vector2(size.x - 6, y), Vector2(3, h)), Color(1, 1, 1, 0.35))


# 羈絆：每個一格，件數到第一個門檻就亮起來；門檻數字到了的變亮
func _draw_bonds(font: Font, me: Player) -> void:
	draw_string(font, _bonds_origin() + Vector2(0, -6), "羈絆（鑲在武器上的道具，同一種只算 1 件）", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.55))
	var i := 0
	for bond: StringName in BondDefs.BONDS:
		var def: Dictionary = BondDefs.BONDS[bond]
		var count: int = me.loadout.bond_counts.get(bond, 0)
		var on := BondDefs.tier(bond, count) > 0
		var r := _bond_rect(i)
		draw_rect(r, Color(def.color, 0.22 if on else 0.05))
		draw_rect(r, Color(def.color, 0.9 if on else 0.3), false, 2.0 if on or bond == _hover_bond else 1.0)
		draw_string(font, r.position + Vector2(8, 18), "%s %d" % [def.name, count], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12, 15, Color(def.color, 1.0 if on else 0.6))
		var x := r.position.x + 8
		for need: int in def.thresholds:
			var t := str(need)
			draw_string(font, Vector2(x, r.position.y + 36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.9 if count >= need else 0.3))
			x += font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 6
		i += 1


func _draw_bag(font: Font, me: Player) -> void:
	var o := _grid_origin()
	draw_string(font, o + Vector2(0, -6), "背包（只放東西，沒有效果）", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.55))
	var bag: Vector2i = ItemDefs.BAG_SIZE
	for y in bag.y:
		for x in bag.x:
			draw_rect(Rect2(o + Vector2(x, y) * CELL, Vector2(CELL, CELL)).grow(-1), Color(1, 1, 1, 0.05))
	for e: Dictionary in me.inventory.entries:
		var dim: bool = not _drag.is_empty() and _drag.uid == e.uid
		_draw_item(font, e.id, o, CELL, e.cell, e.rot, _rarity_of(e), 0.35 if dim else 1.0)
	if _suggest != &"":
		_draw_suggestion(me.inventory.find(_suggest))


func _draw_drag(font: Font, me: Player) -> void:
	if _drag.is_empty():
		return
	var local := get_local_mouse_position()
	if not _merge_target(me, local).is_empty():
		var r := _hover_rect(local)
		draw_rect(r, Color(1, 0.85, 0.3, 0.35))
		var forge := world != null and world.near_forge(me)
		draw_string(font, r.position + Vector2(6, r.size.y - 8), "合成" if forge else "合成（要在鍛造祭壇旁）", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.GOLD if forge else UiKit.ALERT)
		return
	var wc := _wcell_at(me, local) if _drag.weapon.is_empty() and _drag.id != &"corpse" else {}
	var inv: Inventory = null
	var o := Vector2.ZERO
	var cell_px := 0.0
	var at := Vector2i.ZERO
	if not wc.is_empty():
		inv = me.loadout.container(wc.hand)
		o = _wgrid_origin(me, wc.hand)
		cell_px = WCELL
		at = _drag_cell(wc.cell)
	elif _in_grid(local):
		inv = me.inventory
		o = _grid_origin()
		cell_px = CELL
		at = _drag_cell(_cell_at(local))
	if inv == null:
		return
	var ok := inv.fits(_drag.id, at, _drag.rot, _drag.uid)
	for c in Inventory.cells_of(_drag.id, _drag.rot):
		draw_rect(Rect2(o + Vector2(at + c) * cell_px, Vector2(cell_px, cell_px)).grow(-2), Color(0.3, 1, 0.4, 0.35) if ok else Color(1, 0.3, 0.3, 0.35))
	_draw_item(font, _drag.id, o, cell_px, at, _drag.rot, _drag_rarity(), 0.85)


# 撿不下時取代操作說明的那一行
func _full_text(me: Player, target: ItemPickup) -> String:
	var e := me.inventory.find(_suggest) if me != null and _suggest != &"" else {}
	if e.is_empty():
		return "放不下「%s」：武器格子和背包都滿了，要整理一下" % target.display_name()
	var item_name: String = WeaponDropDefs.display_name(e.weapon) if e.has("weapon") else ItemDefs.ITEMS[e.id].name
	return "放不下「%s」：拿掉背包裡的「%s」就放得下" % [target.display_name(), item_name]


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


# 腳邊欄：按得到 F 的地上道具，撿不下的那一件金框（固定不捲動）
func _draw_feet(font: Font, target: ItemPickup) -> void:
	var r := _feet_rect()
	draw_rect(r, UiKit.SLOT_BG)
	draw_string(font, r.position + Vector2(0, 14), "腳邊（拖進格子撿起）", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.55))
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


# 合成提示框：滑鼠下面那個武器所在的名稱框或背包格
func _hover_rect(local: Vector2) -> Rect2:
	var slot := _slot_at(local)
	if slot >= 0:
		return _slot_rect(slot)
	return Rect2(_grid_origin() + Vector2(_cell_at(local)) * CELL, Vector2(CELL, CELL))


# 主手 / 副手：名稱框（拖武器到這裡換上）＋武器格子（部位底色、鑲上的道具）
func _draw_slots(font: Font, me: Player) -> void:
	for i in 2:
		var r := _slot_rect(i)
		var inst: Dictionary = me.weapon_slots[i]
		var main := i == Loadout.MAIN and not inst.is_empty()
		draw_string(font, r.position + Vector2(0, -6), SLOT_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.GOLD if main else Color(1, 1, 1, 0.55))
		draw_rect(r, Color(1, 1, 1, 0.05))
		if inst.is_empty():
			draw_string(font, r.position + Vector2(10, r.size.y / 2.0 + 6), "（空）", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.3))
			continue
		var color: Color = ItemDefs.RARITIES[inst.rarity].color
		var dim: bool = not _drag.is_empty() and _drag.uid == inst.uid
		draw_rect(r.grow(-3), Color(color.darkened(0.55), 0.4 if dim else 0.9))
		draw_rect(r.grow(-3), UiKit.GOLD if main else color, false, 3.0 if main else 2.0)
		draw_string(font, r.position + Vector2(10, 22), WeaponDropDefs.display_name(inst), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16, 16, color)
		var b := WeaponDropDefs.base_stats(inst)
		var stat_text := ("攻擊力 %.1f" % b.damage) if not b.is_empty() else "副手"
		draw_string(font, r.position + Vector2(10, 40), "%s · 詞條 %d 條" % [stat_text, inst.affixes.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.7))
		var o := _wgrid_origin(me, i)
		var cells := WeaponDefs.grid_cells(Loadout.weapon_of(inst))
		for c: Vector2i in cells:
			var cr := Rect2(o + Vector2(c) * WCELL, Vector2(WCELL, WCELL)).grow(-1)
			draw_rect(cr, Color(PART_COLORS[cells[c]], 0.45))
			if cells[c] == "G":   # 寶石座：中間畫一個圈（第 7 步放技能）
				draw_arc(cr.get_center(), WCELL * 0.22, 0.0, TAU, 16, Color(1, 1, 1, 0.35), 1.5)
		for e: Dictionary in me.loadout.container(i).entries:
			var edim: bool = not _drag.is_empty() and _drag.uid == e.uid
			_draw_item(font, e.id, o, WCELL, e.cell, e.rot, _rarity_of(e), 0.35 if edim else 1.0)


func _draw_item(font: Font, id: StringName, o: Vector2, cell_px: float, cell: Vector2i, rot: int, rarity: StringName, alpha: float) -> void:
	var def: Dictionary = ItemDefs.ITEMS[id]
	var color: Color = ItemDefs.RARITIES[rarity].color
	var cells := Inventory.cells_of(id, rot)
	for c in cells:
		var r := Rect2(o + Vector2(cell + c) * cell_px, Vector2(cell_px, cell_px)).grow(-3)
		draw_rect(r, Color(color.darkened(0.55), 0.9 * alpha))
		draw_rect(r, Color(color, alpha), false, 2.0)
	var first: Vector2 = o + Vector2(cell + cells[0]) * cell_px
	draw_string(font, first + Vector2(4, cell_px * 0.4), String(def.name).substr(0, 2), HORIZONTAL_ALIGNMENT_LEFT, cell_px - 4, 15 if cell_px >= CELL else 12, Color(1, 1, 1, alpha))


# 下方說明（固定）：滑鼠停著（或拖著）的東西：道具的效果與放在哪、武器的詞條（腳邊的道具也一樣）
func _draw_info(font: Font, me: Player) -> void:
	var y := size.y - PAD - INFO_H + 26
	var info := _info_of(me)
	if info.is_empty():
		draw_string(font, Vector2(PAD, y), "生效 %d 件（鑲在武器上）· 背包 %d 件" % [me.items.size(), me.inventory.entries.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.55))
		return
	draw_string(font, Vector2(PAD, y), info.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, info.color)
	draw_multiline_string(font, Vector2(PAD, y + 22), "\n".join(info.lines), HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, 14, -1, Color(1, 1, 1, 0.85))


func _info_of(me: Player) -> Dictionary:
	if _drag.is_empty() and _hover_bond != &"":
		return _bond_info(me, _hover_bond)
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
	var found := me.loadout.find_item(uid)
	if not found.is_empty() and found.where != Loadout.BAG:
		var info := UiKit.item_info(found.entry.id, {})
		var part: String = WeaponDefs.PARTS[WeaponDefs.grid_cells(Loadout.weapon_of(me.weapon_slots[found.where]))[found.entry.cell + Inventory.cells_of(found.entry.id, found.entry.rot)[0]]]
		info.title += "（鑲在%s · %s）" % ["主手" if found.where == Loadout.MAIN else "副手", part]
		var timing := ItemDefs.timing_line(found.entry.id, (found.inv as Inventory).parts_of(found.entry))
		if timing != "":
			info.lines.append(timing)
		return info
	var e := me.inventory.find(uid)
	if e.is_empty():
		return {}
	var bag_info := UiKit.item_info(e.id, e.get("weapon", {}))
	bag_info.title += "（在背包裡不生效）"
	return bag_info


# 滑鼠停在羈絆上：現在第幾階、已啟動的那一階與下一階的效果
func _bond_info(me: Player, bond: StringName) -> Dictionary:
	var def: Dictionary = BondDefs.BONDS[bond]
	var count: int = me.loadout.bond_counts.get(bond, 0)
	var t := BondDefs.tier(bond, count)
	var lines: Array[String] = []
	if t > 0:
		lines.append("第 %d 階（%d 件）：%s" % [t, def.thresholds[t - 1], def.tiers[t - 1]])
	var next := BondDefs.next_threshold(bond, count)
	if next > 0:
		lines.append("下一階（%d 件）：%s" % [next, def.tiers[t]])
	return {"title": "%s羈絆 %d 件" % [def.name, count], "color": def.color, "lines": lines}
