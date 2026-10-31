# 背包介面（D3 / D4，Tab 開關；Build 改版第 3 步起照對比頁 A：畫面右半邊、中間可以用滑鼠滾輪捲動）
# 由上到下：標題與操作說明（固定）→ 主手、副手的武器格子（道具鑲在這裡才生效），右邊並排收集到的羈絆 → 8 × 6 背包（只放東西）
# → 滑鼠停著的說明（固定在底部）。腳邊（按得到 F 的地上道具）是另一個浮在背包左邊的框（FeetPanel），內容與操作都在這裡處理
# 左鍵點一下拿起、再點一下放下（按住拖曳也可以）；拿著時按 R 旋轉、右鍵或 Esc 放回原處，放到腳邊或面板外面丟在地上；
# 道具放到武器格子 = 鑲上、放到背包 = 拿下來；武器放到主手 / 副手的名稱框就換上（拿不動的由權威端拒絕），放到同種同稀有度的武器上合成；
# 腳邊的放進背包或武器格子 = 撿起放在那一格。右鍵點一下 = 直接裝上 / 拿下來（_quick_equip）
# 物品的畫法（UiKit.draw_item）：底色看種類、外框看稀有度、道具畫羈絆色點；滑鼠停在羈絆上時只亮那個羈絆的東西
# 撿不下時（show_full）標出那一件、建議拿掉背包裡哪件就放得下
# 只送操作（op_requested → InputCollector → InputCmd.inv_ops），實際擺放由權威端決定，畫面照本機玩家的狀態畫
class_name InventoryPanel
extends Control

signal op_requested(op: Array)

const CELL := 97          # 背包一格：8 格撐滿主手＋副手＋羈絆欄的寬度（8 × 97 = 2 × 250 + 12 + 18 + 246）
const WCELL := 50         # 武器格子一格
const GRID_COLS := 5      # 武器格子最寬 5 格（WeaponDefs grid）
const GRID_W := GRID_COLS * WCELL
const HAND_GAP := 12      # 兩隻手之間
const PAD := 18
const TITLE_H := 64       # 標題 + 一行操作說明（固定在上面）
const INFO_H := 150       # 說明（固定在下面）
const INFO_FONT := 17     # 說明的內文字級；標題在 INFO_TITLE_Y、內文從 INFO_TITLE_Y + INFO_BODY_DY 的基線開始（檢查「背包介面」量最長的說明塞不塞得下）
const INFO_TITLE_Y := 30
const INFO_BODY_DY := 28
const LABEL_H := 24
const HEAD_H := 62        # 主手 / 副手的名稱框（拖武器到這裡換上）
const SLOT_NAMES: Array[String] = ["主手", "副手"]
const BOND_W := 246       # 右上的羈絆欄，和主手 / 副手並排；只列收集到的（件數 > 0）。改這個值要一起改 CELL（背包右緣對齊羈絆欄）
const BOND_H := 56        # 羈絆一格：名稱與件數、各階門檻
const BOND_GAP := 8
const FEET_W := 280       # 腳邊框（FeetPanel）的寬度
const FEET_HEAD := 32     # 腳邊框標題的高度
const FEET_ROW := 54      # 腳邊框每一列的高度
const FEET_CELL := 10.0   # 腳邊框形狀小圖每格的大小
const FEET_MAX_ROWS := 6  # 腳邊框最多列幾件（再多的走近一點才看得到）
const FEET_GAP := 16      # 腳邊框和背包之間的空隙（貼齊背包下緣）
const SCROLL_STEP := 72.0
const MIN_VIEW_H := 420.0   # 捲動區至少這麼高（最小尺寸用）
const HINT := "左鍵拿起 / 放下 · 右鍵直接裝上 / 拿下來 · 拿著按 R 旋轉、右鍵放回 · 放到腳邊丟掉 · 武器放到主手 / 副手換上 · 滾輪捲動"
const CLICK_SLOP := 6.0     # 按下到放開移動不超過這麼多像素算「點一下」（拿在手上），超過算拖曳
const NOTICE_MS := 2000     # 右鍵裝不上時的提示顯示多久
const DIM_ALPHA := 0.25                # 滑鼠停在羈絆上時，不屬於那個羈絆的東西變淡
# 武器格子的部位顏色（WeaponDefs.PARTS）：淡淡的底色，鑲上的道具畫在上面
const PART_COLORS := {"A": Color("5f7487"), "E": Color("9aa4ab"), "D": Color("8e6a33"), "H": Color("5e4433"), "G": Color("6a3f8f")}

var world: World
var local_peer := World.HOST_PEER_ID
var feet_panel := FeetPanel.new()   # HUD 加進畫面；位置與大小每幀由這裡算
var feet_avoid: Control             # 腳邊框不能蓋到的介面（HUD 給技能欄）：水平有重疊時腳邊框的下緣停在它上面
var forge: ForgePanel               # 鍛造祭壇旁開著時：武器拖過去 / 右鍵 / 拖到另一把上 = 放進鍛造格子（HUD 設定）

var _drag: Dictionary = {}   # 拖曳中 / 拿在手上：{ uid, id, rot, anchor（形狀格子的索引，對齊滑鼠所在格）, weapon（武器實例或 {}）, pickup_id（從腳邊拖的才有） }
var _held := false           # _drag 是點一下拿起來的（下一次左鍵放下）；false = 按住拖曳中（放開就放下）
var _press_at := Vector2.ZERO
var _notice := ""
var _notice_until := 0
var _hover_uid := &""
var _hover_pickup := 0
var _hover_bond := &""
var _feet: Array[ItemPickup] = []   # 腳邊框的地上道具（每幀照本機玩家的位置更新）
var _full_pickup := 0               # 撿不下的地上道具（show_full）；不在腳邊了就不顯示
var _suggest := &""                 # 建議拿掉的背包條目
var _suggest_key := 0               # 算 _suggest 時的背包與目標，有變才重算
var _scroll := 0.0                  # 中間捲動區往下捲了多少


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(PAD * 3 + GRID_W * 2 + HAND_GAP + BOND_W, PAD * 2 + TITLE_H + MIN_VIEW_H + INFO_H)
	feet_panel.bag = self
	visibility_changed.connect(func() -> void:
		_cancel()
		_full_pickup = 0
		feet_panel.visible = visible and not _feet.is_empty())   # 打開後每幀照腳邊有沒有東西更新


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


# 右上的羈絆欄：和主手 / 副手的名稱框同高開始，由上往下
func _bonds_origin() -> Vector2:
	return Vector2(PAD * 2 + GRID_W * 2 + HAND_GAP, _content_top() + LABEL_H)


func _bond_rect(i: int) -> Rect2:
	return Rect2(_bonds_origin() + Vector2(0, i * (BOND_H + BOND_GAP)), Vector2(BOND_W, BOND_H))


# 收集到的羈絆（件數 > 0），照 BondDefs 的順序
func _shown_bonds(me: Player) -> Array[StringName]:
	var out: Array[StringName] = []
	if me == null:
		return out
	for bond: StringName in BondDefs.BONDS:
		if me.loadout.bond_counts.get(bond, 0) > 0:
			out.append(bond)
	return out


func _bond_at(local: Vector2) -> StringName:
	if not _in_view(local):
		return &""
	var shown := _shown_bonds(_player())
	for i in shown.size():
		if _bond_rect(i).has_point(local):
			return shown[i]
	return &""


# 主手 / 副手與羈絆欄那一塊的高度（取兩邊較高的）
func _top_height(me: Player) -> float:
	var hands := LABEL_H + HEAD_H + 8 + _grid_rows(me) * WCELL
	var bonds := LABEL_H + maxi(1, _shown_bonds(me).size()) * (BOND_H + BOND_GAP)
	return maxf(hands, bonds)


func _grid_origin() -> Vector2:
	return Vector2(PAD, _content_top() + _top_height(_player()) + 22 + LABEL_H)


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


# 腳邊框在背包座標裡的範圍（FeetPanel 是 HUD 上另一個節點；滑鼠判斷一律換成背包座標）
func _feet_rect() -> Rect2:
	return Rect2(get_global_transform().affine_inverse() * feet_panel.global_position, feet_panel.size)


func _feet_rows() -> int:
	return mini(_feet.size(), FEET_MAX_ROWS)


func _feet_row_local(i: int) -> Rect2:
	return Rect2(Vector2(8, FEET_HEAD + i * FEET_ROW), Vector2(FEET_W - 16, FEET_ROW - 6))


func _feet_row_rect(i: int) -> Rect2:
	var r := _feet_row_local(i)
	r.position += _feet_rect().position
	return r


# 腳邊框的大小跟著件數變，貼在背包左邊、下緣固定往上長：下緣對齊背包，水平碰到 feet_avoid（技能欄）時停在它上面
func _layout_feet() -> void:
	var h := FEET_HEAD + maxi(1, _feet_rows()) * FEET_ROW + 8
	var x := global_position.x - FEET_GAP - FEET_W
	var bottom := global_position.y + size.y
	if feet_avoid != null and feet_avoid.visible:
		var avoid := feet_avoid.get_global_rect()
		if avoid.position.x < x + FEET_W and avoid.end.x > x:
			bottom = minf(bottom, avoid.position.y - FEET_GAP)
	feet_panel.size = Vector2(FEET_W, h)
	feet_panel.global_position = Vector2(x, bottom - h)
	feet_panel.queue_redraw()


# FeetPanel 收到的滑鼠事件：換成背包座標後照背包的規則處理（點、拖、右鍵撿起；按下後在背包放開也接得上）
func feet_input(source: Control, event: InputEvent) -> void:
	if not event is InputEventMouse:
		return
	var e: InputEventMouse = event.duplicate()
	e.position = get_global_transform().affine_inverse() * (source.get_global_transform() * event.position)
	_gui_input(e)


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
	feet_panel.visible = not _feet.is_empty()   # 腳邊沒東西就不顯示腳邊欄（2026-10-31 使用者要求）
	_layout_feet()
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
			if _held:
				_finish_drag(me, event.position)
			else:
				_start_drag(me, event.position)
				_press_at = event.position
		elif not _drag.is_empty() and not _held:
			if event.position.distance_to(_press_at) <= CLICK_SLOP:
				_held = true   # 點一下：拿在手上，下一次左鍵放下
			else:
				_finish_drag(me, event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and _drag.is_empty():
		if not _forge_put(me, _uid_at(me, event.position)):
			_quick_equip(me, event.position)
		accept_event()


# 鍛造祭壇開著時，右鍵武器 = 放進鍛造格子；不是武器就照一般右鍵
func _forge_put(me: Player, uid: StringName) -> bool:
	if forge == null or not forge.visible or uid == &"" or ForgePanel._find(me, uid).is_empty():
		return false
	forge.put(uid)
	return true


# 拖著或拿著東西（R 旋轉、Esc 放回；遺物面板這時不收 R / Esc）
func is_holding() -> bool:
	return visible and not _drag.is_empty()


# 鍛造格子要接走手上拿著的武器（點一下拿起來的）：回傳 uid 並放回原處；沒拿著武器回傳 &""
func take_held_weapon() -> StringName:
	if not _held or _drag.is_empty() or _drag.weapon.is_empty() or _drag.has("pickup_id"):
		return &""
	var uid: StringName = _drag.uid
	_cancel()
	return uid


# 拿著東西時在 _input 搶先處理：R 旋轉（不會觸發重新開始）、右鍵 / Esc 放回原處（Esc 不開選單）、
# 點在面板外面丟在地上（點在其他介面上不算，例如鍛造祭壇的面板）
func _input(event: InputEvent) -> void:
	if not visible or _drag.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			_drag.rot = (_drag.rot + 1) % 4
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_ESCAPE:
			_cancel()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT and _held and not get_global_rect().has_point(event.position) \
				and get_viewport().gui_get_hovered_control() == null:
			var me := _player()
			if me != null:
				_finish_drag(me, get_global_transform().affine_inverse() * event.position)
			get_viewport().set_input_as_handled()


func _cancel() -> void:
	_drag = {}
	_held = false


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
		_cancel()
		return
	var uid := String(_drag.uid)
	var at_global := get_global_transform() * local
	if forge != null and forge.visible and forge.get_global_rect().has_point(at_global):
		if not _drag.weapon.is_empty():   # 拖到鍛造面板上放開：放進格子（其他東西拖過去不動）
			forge.drop_weapon(_drag.uid, at_global)
		_cancel()
		return
	var merge := _merge_target(me, local)
	var slot := _slot_at(local)
	if not merge.is_empty():
		# 鍛造祭壇旁：兩把一起放進鍛造格子（挑詞條、按合成才送）；不在祭壇旁直接送（權威端回「要站在鍛造祭壇旁」）
		if forge != null and forge.visible:
			forge.put(_drag.uid)
			forge.put(merge.uid)
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
	_cancel()


# 右鍵：直接裝上 / 拿下來，位置照撿東西的自動擺放（Inventory.find_spot：武器格子先找合部位偏好的）；送的是一般的搬動 / 換上 / 撿起操作
# 背包的道具、技能 → 主手、再副手的武器格子；背包的武器 → 換上（副手武器到副手）；鑲著的道具、拿著的武器 → 背包；腳邊的 → 先試武器格子、再背包
func _quick_equip(me: Player, local: Vector2) -> void:
	var ip := _pickup_at(local)
	if ip != null:
		var hands := [Loadout.BAG] if not ip.weapon.is_empty() else [Loadout.MAIN, Loadout.OFF, Loadout.BAG]
		var ground_spot := _auto_spot(me, ip.item_id, hands)
		if ground_spot.is_empty():
			_say("放不下「%s」" % ip.display_name())
		else:
			var op: Array = [InputCmd.OP_PICKUP, ip.id, ground_spot.cell.x, ground_spot.cell.y, ground_spot.rot]
			if ground_spot.hand != Loadout.BAG:
				op.append(ground_spot.hand)
			op_requested.emit(op)
		return
	var slot := _slot_at(local)
	if slot >= 0:
		var inst: Dictionary = me.weapon_slots[slot]
		if slot == Loadout.MAIN and not inst.is_empty():
			_say("主手不能空著：在背包的武器上按右鍵換上")
		elif not inst.is_empty():
			_to_bag(me, inst.uid, inst.base, WeaponDropDefs.display_name(inst))
		return
	var wc := _wcell_at(me, local)
	if not wc.is_empty():
		var inv := me.loadout.container(wc.hand)
		var socketed := inv.find(inv.occupied().get(wc.cell, &""))
		if not socketed.is_empty():
			_to_bag(me, socketed.uid, socketed.id, ItemDefs.ITEMS[socketed.id].name)
		return
	if not _in_grid(local):
		return
	var e := me.inventory.find(me.inventory.occupied().get(_cell_at(local), &""))
	if e.is_empty() or e.id == &"corpse":
		return
	if not e.get("weapon", {}).is_empty():
		var off: bool = WeaponDefs.WEAPONS[Loadout.weapon_of(e.weapon)].hands == &"off"
		op_requested.emit([InputCmd.OP_EQUIP, String(e.uid), Loadout.OFF if off else Loadout.MAIN])
		return
	var found := _auto_spot(me, e.id, [Loadout.MAIN, Loadout.OFF])
	if found.is_empty():
		var item_name: String = ItemDefs.ITEMS[e.id].name
		_say(("沒有能鑲「%s」的寶石座" if ItemDefs.is_skill(e.id) else "武器格子放不下「%s」") % item_name)
		return
	op_requested.emit([InputCmd.OP_MOVE, String(e.uid), found.cell.x, found.cell.y, found.rot, found.hand])


func _to_bag(me: Player, uid: StringName, id: StringName, item_name: String) -> void:
	var found := _auto_spot(me, id, [Loadout.BAG])
	if found.is_empty():
		_say("背包放不下「%s」" % item_name)
		return
	op_requested.emit([InputCmd.OP_MOVE, String(uid), found.cell.x, found.cell.y, found.rot])


# 依序試 hands 裡的容器（沒拿武器的手跳過）：{ hand, cell, rot } 或 {}
func _auto_spot(me: Player, id: StringName, hands: Array) -> Dictionary:
	for hand: int in hands:
		var inv: Inventory = me.inventory if hand == Loadout.BAG else me.loadout.container(hand)
		if inv == null:
			continue
		var spot := inv.find_spot(id)
		if not spot.is_empty():
			return {"hand": hand, "cell": spot.cell, "rot": spot.rot}
	return {}


func _say(text: String) -> void:
	_notice = text
	_notice_until = Time.get_ticks_msec() + NOTICE_MS


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
	# 固定的上下兩塊蓋在捲動區上面
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, PAD + TITLE_H)), UiKit.SLOT_BG)
	draw_rect(Rect2(Vector2(0, size.y - PAD - INFO_H), Vector2(size.x, PAD + INFO_H)), UiKit.SLOT_BG)
	draw_line(Vector2(PAD, PAD + TITLE_H - 2), Vector2(size.x - PAD, PAD + TITLE_H - 2), UiKit.SLOT_OUTLINE)
	draw_line(Vector2(PAD, size.y - PAD - INFO_H + 2), Vector2(size.x - PAD, size.y - PAD - INFO_H + 2), UiKit.SLOT_OUTLINE)
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.SLOT_OUTLINE, false, 1.0)
	draw_string(font, Vector2(PAD, PAD + 26), "背包（遊戲不暫停）", HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	if full != null:
		draw_string(font, Vector2(PAD, PAD + 52), _full_text(me, full), HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, 17, UiKit.DENY)
	elif Time.get_ticks_msec() < _notice_until:
		draw_string(font, Vector2(PAD, PAD + 52), _notice, HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, 17, UiKit.ALERT)
	else:
		draw_string(font, Vector2(PAD, PAD + 52), HINT, HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, 15, Color(1, 1, 1, 0.6))
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


# 羈絆欄（右上）：只列收集到的，每個一格（名稱與件數、各階門檻，到門檻的數字變亮）；一個都沒有時寫怎麼才會出現
func _draw_bonds(font: Font, me: Player) -> void:
	var o := _bonds_origin()
	draw_string(font, o + Vector2(0, -6), "羈絆（同一種只算 1 件）", HORIZONTAL_ALIGNMENT_LEFT, BOND_W, 16, Color(1, 1, 1, 0.6))
	var shown := _shown_bonds(me)
	if shown.is_empty():
		draw_string(font, o + Vector2(0, 30), "鑲上有羈絆的道具才會出現", HORIZONTAL_ALIGNMENT_LEFT, BOND_W, 16, Color(1, 1, 1, 0.35))
		return
	for i in shown.size():
		var bond := shown[i]
		var def: Dictionary = BondDefs.BONDS[bond]
		var count: int = me.loadout.bond_counts.get(bond, 0)
		var on := BondDefs.tier(bond, count) > 0
		var r := _bond_rect(i)
		draw_rect(r, Color(def.color, 0.22 if on else 0.08))
		draw_rect(r, Color(def.color, 0.9 if on else 0.45), false, 2.0 if on or bond == _hover_bond else 1.0)
		draw_string(font, r.position + Vector2(10, 23), "%s %d" % [def.name, count], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16, 19, Color(def.color, 1.0 if on else 0.75))
		var x := r.position.x + 10
		for need: int in def.thresholds:
			var t := str(need)
			draw_string(font, Vector2(x, r.position.y + 46), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.9 if count >= need else 0.3))
			x += font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 8


func _draw_bag(font: Font, me: Player) -> void:
	var o := _grid_origin()
	draw_string(font, o + Vector2(0, -6), "背包（只放東西，沒有效果）", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))
	var bag: Vector2i = ItemDefs.BAG_SIZE
	for y in bag.y:
		for x in bag.x:
			draw_rect(Rect2(o + Vector2(x, y) * CELL, Vector2(CELL, CELL)).grow(-1), Color(1, 1, 1, 0.05))
	for e: Dictionary in me.inventory.entries:
		var dim: bool = (not _drag.is_empty() and _drag.uid == e.uid) or (forge != null and forge.dims(e.get("weapon", {})))
		_draw_item(font, e.id, o, CELL, e.cell, e.rot, _rarity_of(e), 0.35 if dim else 1.0, e.get("weapon", {}))
		var rects: Array[Rect2] = []
		for c in Inventory.cells_of(e.id, e.rot):
			rects.append(Rect2(o + Vector2(e.cell + c) * CELL, Vector2(CELL, CELL)))
		_draw_forge_mark(font, e.get("weapon", {}), rects)
	if _suggest != &"":
		_draw_suggestion(me.inventory.find(_suggest))


func _draw_drag(font: Font, me: Player) -> void:
	if _drag.is_empty():
		return
	var local := get_local_mouse_position()
	if not _merge_target(me, local).is_empty():
		var r := _hover_rect(local)
		draw_rect(r, Color(1, 0.85, 0.3, 0.35))
		var near := world != null and world.near_forge(me)
		draw_string(font, r.position + Vector2(6, r.size.y - 8), "放進鍛造" if near else "合成（要在鍛造祭壇旁）", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiKit.GOLD if near else UiKit.ALERT)
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
	if inv == null:   # 不在格子上：東西跟著滑鼠（抓住的那一格在滑鼠下）
		var shape := Inventory.cells_of(_drag.id, _drag.rot)
		var anchor: Vector2i = shape[mini(_drag.anchor, shape.size() - 1)]
		_draw_item(font, _drag.id, local - (Vector2(anchor) + Vector2(0.5, 0.5)) * CELL, CELL, Vector2i.ZERO, _drag.rot, _drag_rarity(), 0.85, _drag.weapon)
		return
	var ok := inv.fits(_drag.id, at, _drag.rot, _drag.uid)
	for c in Inventory.cells_of(_drag.id, _drag.rot):
		draw_rect(Rect2(o + Vector2(at + c) * cell_px, Vector2(cell_px, cell_px)).grow(-2), Color(0.3, 1, 0.4, 0.35) if ok else Color(1, 0.3, 0.3, 0.35))
	_draw_item(font, _drag.id, o, cell_px, at, _drag.rot, _drag_rarity(), 0.85, _drag.weapon)


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
		UiKit.draw_dashed_rect(self, Rect2(_grid_origin() + Vector2(e.cell + c) * CELL, Vector2(CELL, CELL)).grow(-1), color)


# 腳邊框（FeetPanel._draw 叫）：按得到 F 的地上道具，撿不下的那一件金框；座標是腳邊框自己的
func draw_feet(canvas: Control) -> void:
	var font := canvas.get_theme_default_font()
	var target := _full_target()
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), UiKit.SLOT_BG)
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), UiKit.SLOT_OUTLINE, false, 1.0)
	canvas.draw_string(font, Vector2(8, 22), "腳邊（放進格子撿起 · 右鍵直接撿）", HORIZONTAL_ALIGNMENT_LEFT, FEET_W - 16, 16, Color(1, 1, 1, 0.6))
	if _feet.is_empty():
		canvas.draw_string(font, Vector2(8, FEET_HEAD + 30), "（附近沒有東西）", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1, 0.35))
		return
	for i in _feet_rows():
		var ip := _feet[i]
		var row := _feet_row_local(i)
		var color: Color = ItemDefs.RARITIES[ip.rarity()].color
		var alpha := 0.35 if _drag.get("pickup_id", 0) == ip.id else 1.0
		canvas.draw_rect(row, Color(1, 1, 1, 0.08 if ip.id == _hover_pickup else 0.05))
		canvas.draw_rect(row, UiKit.GOLD if ip == target else UiKit.SLOT_OUTLINE, false, 3.0 if ip == target else 1.0)
		var shape := UiKit.shape_size(ip.item_id, FEET_CELL)
		UiKit.draw_shape(canvas, ip.item_id, row.position + Vector2(8, (row.size.y - shape.y) / 2.0), FEET_CELL, color, alpha)
		canvas.draw_string(font, row.position + Vector2(56, row.size.y / 2.0 + 7), ip.display_name(), HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 62, 18, Color(color, alpha))


# 主手拿雙手武器：副手不能拿東西
func _offhand_blocked(me: Player) -> bool:
	var main: Dictionary = me.weapon_slots[Loadout.MAIN]
	return not main.is_empty() and WeaponDefs.WEAPONS[Loadout.weapon_of(main)].hands == &"two"


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
		draw_string(font, r.position + Vector2(0, -6), SLOT_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.GOLD if main else Color(1, 1, 1, 0.6))
		if i == Loadout.OFF and _offhand_blocked(me):   # 主手是雙手武器：副手畫成斜線、寫明不能拿（看起來不像空格）
			draw_rect(r, Color(0, 0, 0, 0.35))
			var step := 14.0
			var k := 0.0
			while k < r.size.x + r.size.y:
				var a := r.position + Vector2(minf(k, r.size.x), maxf(0.0, k - r.size.x))
				var b := r.position + Vector2(maxf(0.0, k - r.size.y), minf(k, r.size.y))
				draw_line(a, b, Color(1, 1, 1, 0.1), 2.0)
				k += step
			draw_string(font, r.position + Vector2(10, r.size.y / 2.0 + 7), "雙手武器：不能拿副手", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16, 17, Color(1, 1, 1, 0.55))
			continue
		draw_rect(r, Color(1, 1, 1, 0.05))
		if inst.is_empty():
			draw_string(font, r.position + Vector2(10, r.size.y / 2.0 + 7), "（空）", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.3))
			continue
		var color: Color = ItemDefs.RARITIES[inst.rarity].color
		var dim: bool = (not _drag.is_empty() and _drag.uid == inst.uid) or (forge != null and forge.dims(inst))
		draw_rect(r.grow(-3), Color(color.darkened(0.55), 0.4 if dim else 0.9))
		draw_rect(r.grow(-3), UiKit.GOLD if main else color, false, 3.0 if main else 2.0)
		draw_string(font, r.position + Vector2(10, 26), WeaponDropDefs.display_name(inst), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16, 20, Color(color, 0.4 if dim else 1.0))
		_draw_forge_mark(font, inst, [r])
		var b := WeaponDropDefs.base_stats(inst)
		var stat_text := ("攻擊力 %.1f" % b.damage) if not b.is_empty() else "副手"
		draw_string(font, r.position + Vector2(10, 50), "%s · 詞條 %d 條" % [stat_text, inst.affixes.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.7))
		var o := _wgrid_origin(me, i)
		var cells := WeaponDefs.grid_cells(Loadout.weapon_of(inst))
		for c: Vector2i in cells:
			var cr := Rect2(o + Vector2(c) * WCELL, Vector2(WCELL, WCELL)).grow(-1)
			draw_rect(cr, Color(PART_COLORS[cells[c]], 0.45))
			if cells[c] == "G":   # 寶石座：中間畫一個圈；拿著這把武器能用的技能時發亮
				var fits_skill: bool = not _drag.is_empty() and ItemDefs.is_skill(_drag.id) and SkillDefs.can_socket(_drag.id, Loadout.weapon_of(inst))
				if fits_skill:
					draw_rect(cr, Color(UiKit.GOLD, 0.3))
				draw_arc(cr.get_center(), WCELL * 0.22, 0.0, TAU, 16, UiKit.GOLD if fits_skill else Color(1, 1, 1, 0.35), 3.0 if fits_skill else 1.5)
		for im: Dictionary in inst.get("imprints", []):   # 印記格（第 8b 步）：羈絆顏色的粗框＋角落一個菱形
			var ir := Rect2(o + Vector2(im.cell) * WCELL, Vector2(WCELL, WCELL)).grow(-1)
			var bc: Color = BondDefs.BONDS[im.bond].color
			draw_rect(ir, bc, false, 3.0)
			var tip := ir.position + Vector2(ir.size.x - 8, 8)
			draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -5), tip + Vector2(5, 0), tip + Vector2(0, 5), tip + Vector2(-5, 0)]), bc)
		for e: Dictionary in me.loadout.container(i).entries:
			var edim: bool = not _drag.is_empty() and _drag.uid == e.uid
			_draw_item(font, e.id, o, WCELL, e.cell, e.rot, _rarity_of(e), 0.35 if edim else 1.0)


# 鍛造祭壇開著時：放在鍛造格子裡的武器標「鍛造 1 / 2」、能和已放的那把合成的發亮（變暗由 ForgePanel.dims 決定）
func _draw_forge_mark(font: Font, inst: Dictionary, rects: Array[Rect2]) -> void:
	if forge == null or inst.is_empty() or rects.is_empty():
		return
	var n := forge.slot_of(inst.uid)
	var glow := n < 0 and forge.glow(inst)
	if n < 0 and not glow:
		return
	for r in rects:
		if glow:
			draw_rect(r.grow(-2), Color(UiKit.GOLD, 0.22))
		draw_rect(r.grow(-2), UiKit.GOLD, false, 3.0)
	if n >= 0:
		draw_string(font, rects[0].position + Vector2(6, rects[0].size.y - 8), "鍛造 %d" % (n + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.GOLD)


# 一件東西（畫法在 UiKit.draw_item，和遺物卡片共用）；滑鼠停在羈絆上時，不屬於那個羈絆的變淡
func _draw_item(font: Font, id: StringName, o: Vector2, cell_px: float, cell: Vector2i, rot: int, rarity: StringName, alpha: float, weapon: Dictionary = {}) -> void:
	if _drag.is_empty() and _hover_bond != &"" and not UiKit.item_bonds(id, weapon).has(_hover_bond):
		alpha *= DIM_ALPHA
	UiKit.draw_item(self, font, id, o + Vector2(cell) * cell_px, cell_px, rot, rarity, alpha, weapon, _hover_bond if _drag.is_empty() else &"")


# 下方說明（固定）：滑鼠停著（或拖著）的東西：道具的效果與放在哪、武器的詞條（腳邊的道具也一樣）
func _draw_info(font: Font, me: Player) -> void:
	var y := size.y - PAD - INFO_H + INFO_TITLE_Y
	var info := _info_of(me)
	if info.is_empty():
		draw_string(font, Vector2(PAD, y), "生效 %d 件（鑲在武器上）· 背包 %d 件" % [me.items.size(), me.inventory.entries.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, INFO_FONT, Color(1, 1, 1, 0.6))
		return
	draw_string(font, Vector2(PAD, y), info.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, info.color)
	draw_multiline_string(font, Vector2(PAD, y + INFO_BODY_DY), "\n".join(info.lines), HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, INFO_FONT, -1, Color(1, 1, 1, 0.85))


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
		if WeaponDropDefs.imprint_mul(me.weapon_slots[found.where], found.entry) > 1.0:
			info.lines.append("在印記格上：效果 ×%s（屬性數值與發動機率）" % WeaponDropDefs.IMPRINT.mul)
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
