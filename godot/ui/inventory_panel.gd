# 背包介面（Tab 開關：畫面右半邊、中間可以用滑鼠滾輪捲動；規則在 docs/設計方向.md「觸發袋」）
# 左邊是盤（主袋在中間，四邊接觸發袋，袋子外側的標題條寫什麼時候發動）；右欄由上到下是主手、副手的名稱框、羈絆欄、倉庫（每格一件，不管形狀）
# 上面的標題與操作說明、下面滑鼠停著的說明都固定不捲。腳邊（按得到 F 的地上道具）是另一個浮在左邊的框（FeetPanel）
# 空的邊平常不畫：拿起袋子才亮出能接的位置並預覽標題；拿起道具時放不下的地方變暗
# 左鍵點一下拿起、再點一下放下（按住拖曳也可以）；拿著時按 R 旋轉、右鍵或 Esc 放回原處，放到腳邊或面板外面丟在地上；
# 數值道具放主袋、效果 / 技能 / 修飾放袋子才生效，放到倉庫 = 拿下來；抓住袋子的標題條或空格拖到主袋的另一邊或另一個位置 = 換邊 / 滑動，拖到倉庫 = 拿下來；
# 武器放到主手 / 副手的名稱框就換上，放到同種同稀有度的武器上合成；放到只被 1 件東西佔住的位置 = 互換；沒做成時 HUD 跳原因（inventory:denied）
# 接在側邊的袋子是轉過的：袋子的格子 x 沿著邊、y 往外（BagDefs），畫在盤上的位置照 Loadout.board_cell
# 只送操作（op_requested → InputCollector → InputCmd.inv_ops），實際擺放由權威端決定，畫面照本機玩家的狀態畫
class_name InventoryPanel
extends Control

signal op_requested(op: Array)

const CELL := 60          # 倉庫一格
const BCELL := 60         # 盤上一格（主袋與袋子）
const BAG_HEAD := 26      # 袋子外側的標題條寬度（盤的四邊各留這麼多）
const SIDE_GAP := 24      # 盤和右欄之間
const DEPTH := 2          # 盤的四邊留給袋子的格數（BagDefs.TIERS 的 depth 都是 2）
const HEAD_W := 174       # 主手 / 副手的名稱框
const HAND_GAP := 12      # 兩隻手之間
const PAD := 18
const TITLE_H := 64       # 標題 + 一行操作說明（固定在上面）
const TIP_W := 420.0              # 浮動說明的寬度（檢查「背包介面」量最長的說明塞不塞得進畫面）
const TIP_PAD := 12.0
const TIP_FONT := 17
const TIP_TITLE_FONT := 20
const TIP_MARGIN := 8.0           # 離畫面邊緣至少這麼遠
const TIP_OFFSET := Vector2(18, 18)   # 離滑鼠的距離，不蓋住指著的東西
const LABEL_H := 24
const HEAD_H := 62        # 主手 / 副手的名稱框（拖武器到這裡換上）
const SLOT_NAMES: Array[String] = ["主手", "副手"]
const BOND_W := 360       # 右欄的寬度（羈絆欄、倉庫 6 格）；只列有的（格數 > 0）
const BOND_H := 56        # 羈絆一格：名稱與格數、各階門檻
const BOND_GAP := 8
const FEET_W := 280       # 腳邊框（FeetPanel）的寬度
const FEET_HEAD := 32     # 腳邊框標題的高度
const FEET_ROW := 54      # 腳邊框每一列的高度
const FEET_CELL := 10.0   # 腳邊框形狀小圖每格的大小
const FEET_MAX_ROWS := 6  # 腳邊框最多列幾件（再多的走近一點才看得到）
const FEET_GAP := 16      # 腳邊框和背包之間的空隙（貼齊背包下緣）
const SCROLL_STEP := 72.0
const MIN_VIEW_H := 420.0   # 捲動區至少這麼高（最小尺寸用）
const HINT := "左鍵拿起 / 放下 · 右鍵直接裝上 / 拿下來 · 拿著按 R 旋轉 · 抓袋子的標題換位置 · 放到腳邊丟掉"
const CLICK_SLOP := 6.0     # 按下到放開移動不超過這麼多像素算「點一下」（拿在手上），超過算拖曳
const NOTICE_MS := 2000     # 右鍵裝不上時的提示顯示多久
const DIM_ALPHA := 0.25                # 滑鼠停在羈絆上時，不屬於那個羈絆的東西變淡
const SIDE_COLORS := {&"top": Color("6a3f8f"), &"left": Color("3f6a8f"), &"right": Color("8f5a3f"), &"bottom": Color("4f7a4f")}   # 袋子的標題條
const SIDE_FILLS := {&"top": Color("2a2140"), &"left": Color("1d2d42"), &"right": Color("3a2a24"), &"bottom": Color("22332a")}    # 袋子的底色（不透明，背後的東西才不會透出來）
const SHADE := Color(0.05, 0.07, 0.11, 0.68)   # 放不下的地方、滑鼠沒停著的袋子蓋上這層
const OK_TINT := Color(0.49, 1.0, 0.6)        # 拿著袋子時亮起來的位置

var world: World
var local_peer := World.HOST_PEER_ID
var feet_panel := FeetPanel.new()   # HUD 加進畫面；位置與大小每幀由這裡算
var feet_avoid: Control             # 腳邊框不能蓋到的介面（HUD 給技能欄）：水平有重疊時腳邊框的下緣停在它上面
var forge: ForgePanel               # 鍛造祭壇旁開著時：武器拖過去 / 右鍵 / 拖到另一把上 = 放進鍛造格子（HUD 設定）

# 拖曳中 / 拿在手上：{ uid, id, rot, anchor（形狀格子的索引，對齊滑鼠所在格）, weapon（武器實例或 {}）, pickup_id?（從腳邊拖的）,
# bag?（拖的是袋子：袋子實例）, bag_anchor?（抓住袋子的第幾格，沿著邊算） }
var _drag: Dictionary = {}
var _held := false           # _drag 是點一下拿起來的（下一次左鍵放下）；false = 按住拖曳中（放開就放下）
var _press_at := Vector2.ZERO
var _notice := ""
var _notice_until := 0
var _tip_layer := Control.new()
var _hover_uid := &""
var _hover_pickup := 0
var _hover_bond := &""
var _feet: Array[ItemPickup] = []   # 腳邊框的地上道具（每幀照本機玩家的位置更新）
var _full_pickup := 0               # 撿不下的地上道具（show_full）；不在腳邊了就不顯示
var _suggest := &""                 # 建議拿掉的倉庫條目
var _suggest_key := 0               # 算 _suggest 時的倉庫與目標，有變才重算
var _scroll := 0.0                  # 中間捲動區往下捲了多少


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(_side_x() + BOND_W + PAD, PAD * 2 + TITLE_H + MIN_VIEW_H)
	_tip_layer.top_level = true   # 面板要裁掉捲動內容，浮動說明卻要能超出面板，所以畫在不受裁切的子節點上
	_tip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_layer.draw.connect(_draw_tip)
	add_child(_tip_layer)
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
	return Rect2(Vector2(0, PAD + TITLE_H), Vector2(size.x, size.y - PAD * 2 - TITLE_H))


func _content_top() -> float:
	return PAD + TITLE_H - _scroll


func _in_view(local: Vector2) -> bool:
	return _view_rect().has_point(local)


# 右欄（主手 / 副手、羈絆、倉庫）的左邊
func _side_x() -> float:
	return PAD + _board_size().x + BAG_HEAD * 2 + SIDE_GAP


func _hand_x(i: int) -> float:
	return _side_x() + i * (HEAD_W + HAND_GAP)


func _slot_rect(i: int) -> Rect2:
	return Rect2(Vector2(_hand_x(i), _content_top() + LABEL_H), Vector2(HEAD_W, HEAD_H))


func _board_top() -> float:
	return _content_top() + 4


# 主袋左上角（盤座標 (0, 0)）
func _core_origin() -> Vector2:
	return Vector2(PAD + BAG_HEAD + DEPTH * BCELL, _board_top() + BAG_HEAD + DEPTH * BCELL)


func _board_size() -> Vector2:
	return Vector2(BagDefs.MAIN_SIZE + Vector2i(DEPTH, DEPTH) * 2) * BCELL


func _board_rect() -> Rect2:
	return Rect2(_core_origin() - Vector2(DEPTH, DEPTH) * BCELL, _board_size())


# 盤上一格的畫面範圍
func _bcell_rect(bc: Vector2i) -> Rect2:
	return Rect2(_core_origin() + Vector2(bc) * BCELL, Vector2(BCELL, BCELL))


# 羈絆欄：右欄裡主手 / 副手的名稱框下面，由上往下
func _bonds_origin() -> Vector2:
	return Vector2(_side_x(), _content_top() + LABEL_H + HEAD_H + 12 + LABEL_H)


func _bond_rect(i: int) -> Rect2:
	return Rect2(_bonds_origin() + Vector2(0, i * (BOND_H + BOND_GAP)), Vector2(BOND_W, BOND_H))


# 有的羈絆（最大同色區塊 > 0 格），照 BondDefs 的順序
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


# 盤（含標題條）的高度；右欄的倉庫貼齊盤的下緣
func _top_height() -> float:
	return _board_top() - _content_top() + _board_size().y + BAG_HEAD * 2


func _grid_origin() -> Vector2:
	return Vector2(_side_x(), _content_top() + _top_height() - ItemDefs.BAG_SIZE.y * CELL)


func _content_height(_me: Player) -> float:
	return _top_height() + PAD


func _slot_at(local: Vector2) -> int:
	if not _in_view(local):
		return -1
	for i in 2:
		if _slot_rect(i).has_point(local):
			return i
	return -1


# 滑鼠下面是盤上哪一格（盤座標）；不在盤上回傳 null
func _bcell_at(local: Vector2) -> Variant:
	if not _in_view(local) or not _board_rect().has_point(local):
		return null
	var p := (local - _core_origin()) / BCELL
	return Vector2i(floori(p.x), floori(p.y))


# 盤上一格屬於誰：主袋 { where: CORE, cell }、接著的袋子 { where: 第幾個, cell（袋子座標） }；空的邊回傳 {}
static func board_target(me: Player, bc: Vector2i) -> Dictionary:
	if Rect2i(Vector2i.ZERO, BagDefs.MAIN_SIZE).has_point(bc):
		return {"where": Loadout.CORE, "cell": bc}
	for i in me.loadout.bags.size():
		var b: Dictionary = me.loadout.bags[i]
		var c := bag_cell(b, bc)
		if c.x >= 0 and c.y >= 0 and c.x < b.length and c.y < b.depth:
			return {"where": i, "cell": c}
	return {}


# 盤座標 → 袋子 b 的格子座標（Loadout.board_cell 的反過來）
static func bag_cell(b: Dictionary, bc: Vector2i) -> Vector2i:
	match b.side:
		&"top":
			return Vector2i(bc.x - b.offset, -1 - bc.y)
		&"bottom":
			return Vector2i(bc.x - b.offset, bc.y - BagDefs.MAIN_SIZE.y)
		&"left":
			return Vector2i(bc.y - b.offset, -1 - bc.x)
	return Vector2i(bc.y - b.offset, bc.x - BagDefs.MAIN_SIZE.x)


# 盤座標在哪一邊的空地、沿著邊第幾格：{ side, along }；在主袋裡或角落回傳 {}
static func board_side(bc: Vector2i) -> Dictionary:
	var m := BagDefs.MAIN_SIZE
	if bc.y < 0 and bc.x >= 0 and bc.x < m.x:
		return {"side": &"top", "along": bc.x}
	if bc.y >= m.y and bc.x >= 0 and bc.x < m.x:
		return {"side": &"bottom", "along": bc.x}
	if bc.x < 0 and bc.y >= 0 and bc.y < m.y:
		return {"side": &"left", "along": bc.y}
	if bc.x >= m.x and bc.y >= 0 and bc.y < m.y:
		return {"side": &"right", "along": bc.y}
	return {}


# 放東西的格子在畫面上的範圍：倉庫照倉庫的格子、主袋與袋子照盤
func _cell_rect(me: Player, where: int, c: Vector2i) -> Rect2:
	if where == Loadout.BAG:
		return Rect2(_grid_origin() + Vector2(c) * CELL, Vector2(CELL, CELL))
	if where == Loadout.CORE:
		return _bcell_rect(c)
	return _bcell_rect(Loadout.board_cell(me.loadout.bags[where], c))


# 滑鼠下面可以放東西的地方：{ where, cell }（倉庫、主袋、袋子）；都不是回傳 {}
func _target_at(me: Player, local: Vector2) -> Dictionary:
	var bc: Variant = _bcell_at(local)
	if bc != null:
		return board_target(me, bc)
	if _in_grid(local):
		return {"where": Loadout.BAG, "cell": _cell_at(local)}
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
	feet_panel.visible = not _feet.is_empty()   # 腳邊沒東西就不顯示腳邊欄
	_layout_feet()
	queue_redraw()


# 撿不下的那一件還在腳邊時，算拿掉倉庫裡哪一件就放得下；倉庫或目標有變才重算
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


# 袋子在畫面上的範圍（不含標題條）
func _bag_area(b: Dictionary) -> Rect2:
	return _bcell_rect(Loadout.board_cell(b, Vector2i.ZERO)).merge(_bcell_rect(Loadout.board_cell(b, Vector2i(b.length - 1, b.depth - 1))))


# 袋子的標題條：貼在袋子外側
func _bag_head_rect(b: Dictionary) -> Rect2:
	var a := _bag_area(b)
	match b.side:
		&"top":
			return Rect2(a.position - Vector2(0, BAG_HEAD), Vector2(a.size.x, BAG_HEAD))
		&"bottom":
			return Rect2(Vector2(a.position.x, a.end.y), Vector2(a.size.x, BAG_HEAD))
		&"left":
			return Rect2(a.position - Vector2(BAG_HEAD, 0), Vector2(BAG_HEAD, a.size.y))
	return Rect2(Vector2(a.end.x, a.position.y), Vector2(BAG_HEAD, a.size.y))


# 滑鼠在第幾個接著的袋子的標題條上；不在回傳 -1
func _head_at(me: Player, local: Vector2) -> int:
	if not _in_view(local):
		return -1
	for i in me.loadout.bags.size():
		if _bag_head_rect(me.loadout.bags[i]).has_point(local):
			return i
	return -1


# 滑鼠下面是哪個東西（主手 / 副手的武器、主袋與袋子裡的道具、袋子本身（空格或標題條）、倉庫的條目）
func _uid_at(me: Player, local: Vector2) -> StringName:
	var slot := _slot_at(local)
	if slot >= 0:
		return me.weapon_slots[slot].get("uid", &"")
	var head := _head_at(me, local)
	if head >= 0:
		return me.loadout.bags[head].uid
	var t := _target_at(me, local)
	if t.is_empty():
		return &""
	var inv := me.loadout.container(t.where)
	var uid: StringName = inv.occupied().get(t.cell, &"")
	if uid == &"" and t.where >= 0:
		return me.loadout.bags[t.where].uid
	return uid


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
	var head := _head_at(me, local)
	if head >= 0:   # 標題條：拿起整個袋子（裝滿的袋子沒有空格可以抓）
		var held: Dictionary = me.loadout.bags[head]
		var area := _bag_area(held)
		var along := (local.x - area.position.x) if held.side in [&"top", &"bottom"] else (local.y - area.position.y)
		_drag = {"uid": held.uid, "id": BagDefs.BAGS[held.kind].item, "rot": 0, "anchor": 0, "weapon": {}, "bag": held, "bag_anchor": clampi(int(along / BCELL), 0, held.length - 1)}
		return
	var t := _target_at(me, local)
	if t.is_empty():
		return
	var inv := me.loadout.container(t.where)
	var uid: StringName = inv.occupied().get(t.cell, &"")
	if uid == &"":
		if t.where >= 0:   # 袋子的空格：拿起整個袋子
			var b: Dictionary = me.loadout.bags[t.where]
			_drag = {"uid": b.uid, "id": BagDefs.BAGS[b.kind].item, "rot": 0, "anchor": 0, "weapon": {}, "bag": b, "bag_anchor": t.cell.x}
		return
	var e := inv.find(uid)
	var cells := Inventory.cells_of(e.id, e.rot)
	_drag = {"uid": uid, "id": e.id, "rot": e.rot, "anchor": maxi(0, cells.find(t.cell - e.cell)), "weapon": e.get("weapon", {})}
	if e.has("bag"):
		_drag["bag"] = e.bag
		_drag["bag_anchor"] = 0


# 拖著的東西左上角要放在哪一格（滑鼠所在格對齊抓住的那一格；倉庫不管形狀，就是滑鼠所在格）
func _drag_cell(at: Vector2i, where: int) -> Vector2i:
	if where == Loadout.BAG:
		return at
	var cells := Inventory.cells_of(_drag.id, _drag.rot)
	return at - cells[mini(_drag.anchor, cells.size() - 1)]


# 拖著的袋子放在滑鼠這裡會接到哪：{ side, offset }；不在主袋的邊上回傳 {}
func _bag_drop(local: Vector2) -> Dictionary:
	var board := _board_rect()
	if board.grow(BAG_HEAD).has_point(local):   # 標題條也算那一邊
		local = local.clamp(board.position, board.end - Vector2.ONE)
	var bc: Variant = _bcell_at(local)
	if bc == null:
		return {}
	var s := board_side(bc)
	if s.is_empty():
		return {}
	var length: int = _drag.bag.length
	var offset := clampi(s.along - int(_drag.get("bag_anchor", 0)), 0, maxi(0, BagDefs.edge_length(s.side) - length))
	return {"side": s.side, "offset": offset}


# 放開滑鼠時：拖到武器上 = 合成、拖到主手 / 副手 = 換上；道具拖到主袋 / 袋子 / 倉庫 = 搬動；袋子拖到主袋的邊 = 接上；拖到腳邊或面板外 = 丟掉
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
	var t := _target_at(me, local)
	if _drag.has("pickup_id"):   # 從腳邊拖進來 = 撿起放在那一格；放在別處就留在地上
		if not t.is_empty():
			var at := _drag_cell(t.cell, t.where)
			op_requested.emit([InputCmd.OP_PICKUP, _drag.pickup_id, at.x, at.y, _drag.rot, t.where])
		_cancel()
		return
	var uid := String(_drag.uid)
	if _drag.has("bag"):
		var spot := _bag_drop(local)
		if not spot.is_empty():
			op_requested.emit([InputCmd.OP_BAG, uid, String(spot.side), spot.offset])
		elif _in_grid(local):
			var cell := _cell_at(local)
			if _drag.bag.side != &"":
				op_requested.emit([InputCmd.OP_BAG, uid, "", 0, cell.x, cell.y, _drag.rot])
			else:
				op_requested.emit([InputCmd.OP_MOVE, uid, cell.x, cell.y, _drag.rot, Loadout.BAG])
		elif _feet_rect().has_point(local) or not Rect2(Vector2.ZERO, size).has_point(local):
			op_requested.emit([InputCmd.OP_DROP, uid])   # 連同裡面的東西一起丟
		_cancel()
		return
	var at_global := get_global_transform() * local
	if forge != null and forge.visible and forge.get_global_rect().has_point(at_global):
		if not _drag.weapon.is_empty():   # 拖到鍛造面板上放開：放進格子（其他東西拖過去不動）
			forge.drop_weapon(_drag.uid, at_global)
		_cancel()
		return
	var merge := _merge_target(me, local)
	var slot := _slot_at(local)
	if not merge.is_empty():
		# 鍛造祭壇旁：兩把一起放進鍛造格子（按合成才送）；不在祭壇旁直接送（權威端回「要站在鍛造祭壇旁」）
		if forge != null and forge.visible:
			forge.put(_drag.uid)
			forge.put(merge.uid)
		else:
			op_requested.emit([InputCmd.OP_MERGE, uid, String(merge.uid)])
	elif slot >= 0:
		if not _drag.weapon.is_empty():
			op_requested.emit([InputCmd.OP_EQUIP, uid, slot])
	elif not t.is_empty():
		var at := _drag_cell(t.cell, t.where)
		op_requested.emit([InputCmd.OP_MOVE, uid, at.x, at.y, _drag.rot, t.where])
	elif _feet_rect().has_point(local) or not Rect2(Vector2.ZERO, size).has_point(local):
		op_requested.emit([InputCmd.OP_DROP, uid])
	_cancel()


# 右鍵：直接裝上 / 拿下來，位置照撿東西的自動擺放（Loadout.auto_place：數值 → 主袋、效果 → 原本時機的袋子優先）；送的是一般的搬動 / 換上 / 撿起操作
# 倉庫的道具 → 主袋或袋子；倉庫的武器 → 換上；倉庫的袋子 → 接上；主袋與袋子裡的道具、袋子本身、拿著的武器 → 倉庫；腳邊的 → 先試主袋與袋子、再倉庫
func _quick_equip(me: Player, local: Vector2) -> void:
	var ip := _pickup_at(local)
	if ip != null:
		var spot := {} if not ip.weapon.is_empty() or ItemDefs.ITEMS[ip.item_id].kind != &"item" else me.loadout.auto_place(ip.item_id)
		if spot.is_empty():
			var bag_spot := me.inventory.find_spot(ip.item_id)
			spot = {"where": Loadout.BAG, "spot": bag_spot} if not bag_spot.is_empty() else {}
		if spot.is_empty():
			_say("放不下「%s」" % ip.display_name())
		else:
			op_requested.emit([InputCmd.OP_PICKUP, ip.id, spot.spot.cell.x, spot.spot.cell.y, spot.spot.rot, spot.where])
		return
	var slot := _slot_at(local)
	if slot >= 0:
		var inst: Dictionary = me.weapon_slots[slot]
		if slot == Loadout.MAIN and not inst.is_empty():
			_say("主手不能空著：在倉庫的武器上按右鍵換上")
		elif not inst.is_empty():
			_to_storage(me, inst.uid, inst.base, WeaponDropDefs.display_name(inst))
		return
	var head := _head_at(me, local)
	if head >= 0:
		op_requested.emit([InputCmd.OP_BAG, String(me.loadout.bags[head].uid), "", 0])
		return
	var t := _target_at(me, local)
	if t.is_empty():
		return
	var inv := me.loadout.container(t.where)
	var e := inv.find(inv.occupied().get(t.cell, &""))
	if t.where != Loadout.BAG:
		if not e.is_empty():
			_to_storage(me, e.uid, e.id, ItemDefs.ITEMS[e.id].name)
		elif t.where >= 0:
			op_requested.emit([InputCmd.OP_BAG, String(me.loadout.bags[t.where].uid), "", 0])
		return
	if e.is_empty() or e.id == &"corpse":
		return
	if not e.get("weapon", {}).is_empty():
		var off: bool = WeaponDefs.WEAPONS[Loadout.weapon_of(e.weapon)].hands == &"off"
		op_requested.emit([InputCmd.OP_EQUIP, String(e.uid), Loadout.OFF if off else Loadout.MAIN])
		return
	if e.has("bag"):
		var at := me.loadout.attach_spot(e.bag)
		if at.is_empty():
			_say("主袋的邊接不下「%s」" % BagDefs.bag_name(e.bag))
		else:
			op_requested.emit([InputCmd.OP_BAG, String(e.uid), String(at.side), at.offset])
		return
	var found := me.loadout.auto_place(e.id)
	if found.is_empty():
		_say(("主袋放不下「%s」：可以拖到袋子" if ItemDefs.role_of(e.id) == ItemDefs.ROLE_STAT else "沒有袋子放得下「%s」") % ItemDefs.ITEMS[e.id].name)
		return
	op_requested.emit([InputCmd.OP_MOVE, String(e.uid), found.spot.cell.x, found.spot.cell.y, found.spot.rot, found.where])


func _to_storage(me: Player, uid: StringName, id: StringName, item_name: String) -> void:
	var found := me.inventory.find_spot(id)
	if found.is_empty():
		_say("倉庫放不下「%s」" % item_name)
		return
	op_requested.emit([InputCmd.OP_MOVE, String(uid), found.cell.x, found.cell.y, found.rot, Loadout.BAG])


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
		_draw_board(font, me)
		_draw_bonds(font, me)
		_draw_storage(font, me)
		_draw_drag(font, me)
	# 固定的上下兩塊蓋在捲動區上面
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, PAD + TITLE_H)), UiKit.SLOT_BG)
	draw_rect(Rect2(Vector2(0, size.y - PAD), Vector2(size.x, PAD)), UiKit.SLOT_BG)
	draw_line(Vector2(PAD, PAD + TITLE_H - 2), Vector2(size.x - PAD, PAD + TITLE_H - 2), UiKit.SLOT_OUTLINE)
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.SLOT_OUTLINE, false, 1.0)
	draw_string(font, Vector2(PAD, PAD + 26), "背包（遊戲不暫停）", HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	if me != null:
		draw_string(font, Vector2(PAD, PAD + 24), "主袋生效 %d 件 · 袋子 %d 個 · 倉庫 %d 件" % [me.items.size(), me.loadout.bags.size(), me.inventory.entries.size()], HORIZONTAL_ALIGNMENT_RIGHT, size.x - PAD * 2, 16, Color(1, 1, 1, 0.6))
	if full != null:
		draw_string(font, Vector2(PAD, PAD + 52), _full_text(me, full), HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, 17, UiKit.DENY)
	elif Time.get_ticks_msec() < _notice_until:
		draw_string(font, Vector2(PAD, PAD + 52), _notice, HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, 17, UiKit.ALERT)
	else:
		draw_string(font, Vector2(PAD, PAD + 52), _hint_text(), HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, 15, Color(1, 1, 1, 0.6))
	if me != null:
		_draw_scrollbar(me)
	_tip_layer.queue_redraw()


func _hint_text() -> String:
	if _drag.is_empty():
		return HINT
	if _drag.has("bag"):
		return "放到亮起的位置就接上 · 放回倉庫 · 放到腳邊連同裡面的東西一起丟"
	return "放到沒變暗的地方 · 拿著按 R 旋轉（倉庫不管形狀）· 放到腳邊丟掉"


func _draw_scrollbar(me: Player) -> void:
	var view := _view_rect()
	var total := _content_height(me)
	if total <= view.size.y:
		return
	var h := view.size.y * view.size.y / total
	var y := view.position.y + (view.size.y - h) * _scroll / (total - view.size.y)
	draw_rect(Rect2(Vector2(size.x - 6, y), Vector2(3, h)), Color(1, 1, 1, 0.35))


# 羈絆欄（右邊）：只列有的，每個一格（名稱與最大同色區塊的格數、各階門檻，到門檻的數字變亮）；一個都沒有時寫怎麼才會出現
func _draw_bonds(font: Font, me: Player) -> void:
	var o := _bonds_origin()
	draw_string(font, o + Vector2(0, -6), "羈絆（同色連成一塊的格數）", HORIZONTAL_ALIGNMENT_LEFT, BOND_W, 16, Color(1, 1, 1, 0.6))
	var shown := _shown_bonds(me)
	if shown.is_empty():
		draw_string(font, o + Vector2(0, 30), "有羈絆顏色的道具貼在一起才會出現", HORIZONTAL_ALIGNMENT_LEFT, BOND_W, 16, Color(1, 1, 1, 0.35))
		return
	for i in shown.size():
		var bond := shown[i]
		var def: Dictionary = BondDefs.BONDS[bond]
		var count: int = me.loadout.bond_counts.get(bond, 0)
		var on := BondDefs.tier(bond, count) > 0
		var r := _bond_rect(i)
		draw_rect(r, Color(def.color, 0.22 if on else 0.08))
		draw_rect(r, Color(def.color, 0.9 if on else 0.45), false, 2.0 if on or bond == _hover_bond else 1.0)
		draw_string(font, r.position + Vector2(10, 23), "%s %d 格" % [def.name, count], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16, 19, Color(def.color, 1.0 if on else 0.75))
		UiKit.draw_bond_mark(self, bond, Vector2(r.end.x - 18.0, r.position.y + 18.0), 12.0, 1.0 if on else 0.75)
		var x := r.position.x + 10
		for need: int in def.thresholds:
			var t := str(need)
			draw_string(font, Vector2(x, r.position.y + 46), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.9 if count >= need else 0.3))
			x += font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 8


# 盤：四邊的空地（寫是哪個按鍵）、接著的袋子（邊的顏色、名稱、按鍵袋寫數字）、主袋，再畫裡面的東西
func _draw_board(font: Font, me: Player) -> void:
	var m := BagDefs.MAIN_SIZE
	if _drag.has("bag"):
		_draw_bag_spots(me)
	var core := Rect2(_core_origin(), Vector2(m) * BCELL)
	draw_rect(core, Color(0.11, 0.13, 0.19))
	for y in m.y:
		for x in m.x:
			draw_rect(_bcell_rect(Vector2i(x, y)).grow(-1), Color(1, 1, 1, 0.05))
	draw_rect(core, UiKit.GOLD, false, 2.0)
	for e: Dictionary in me.loadout.core.entries:
		_draw_entry(font, me, Loadout.CORE, e)
	var keys := me.loadout.key_bags()
	var focus := _focus_bag(me)
	for b in me.loadout.bags:
		_draw_bag(font, me, b, keys, b == focus)
	# 拿著道具時放不下的地方變暗；滑鼠停在袋子上時其他的變暗
	if _drag.has("bag"):
		draw_rect(core, SHADE)
		for b in me.loadout.bags:
			draw_rect(_bag_area(b).merge(_bag_head_rect(b)), SHADE)
	elif not _drag.is_empty():
		var bag_ok := ItemDefs.role_of(_drag.id) in [ItemDefs.ROLE_STAT, ItemDefs.ROLE_EFFECT, ItemDefs.ROLE_SKILL, ItemDefs.ROLE_MOD]
		if not me.loadout.core.accepts(_drag.id):
			draw_rect(core, SHADE)
			if bag_ok:
				draw_string(font, core.position + Vector2(0, core.size.y / 2.0 + 8), "主袋只放數值道具", HORIZONTAL_ALIGNMENT_CENTER, core.size.x, 22, Color(1, 1, 1, 0.8))
		if not bag_ok:
			for b in me.loadout.bags:
				draw_rect(_bag_area(b).merge(_bag_head_rect(b)), SHADE)
	elif not focus.is_empty():
		draw_rect(core, SHADE)
		for b in me.loadout.bags:
			if b != focus:
				draw_rect(_bag_area(b).merge(_bag_head_rect(b)), SHADE)


# 滑鼠停著的那個接著的袋子（停在空格或標題條上）；沒有回傳 {}
func _focus_bag(me: Player) -> Dictionary:
	if not _drag.is_empty() or _hover_uid == &"":
		return {}
	for b in me.loadout.bags:
		if b.uid == _hover_uid:
			return b
	return {}


# 一個接著的袋子：不透明的底、格線、裡面的東西、外側的標題條
func _draw_bag(font: Font, me: Player, b: Dictionary, keys: Array, focused: bool) -> void:
	var dragged: bool = not _drag.is_empty() and _drag.uid == b.uid
	var area := _bag_area(b)
	var head := _bag_head_rect(b)
	draw_rect(area, SIDE_FILLS[b.side])
	for y in b.depth:
		for x in b.length:
			draw_rect(_bcell_rect(Loadout.board_cell(b, Vector2i(x, y))).grow(-1), Color(1, 1, 1, 0.04))
	var where: int = me.loadout.bags.find(b)
	# 修飾最後畫：透明格蓋在技能上面才看得到虛線（第 8 步 f）
	var mods: Array[Dictionary] = []
	for e: Dictionary in b.entries:
		if ItemDefs.is_mod(e.id):
			mods.append(e)
		else:
			_draw_entry(font, me, where, e)
	_draw_skill_marks(font, me, where, b)
	for e in mods:
		_draw_entry(font, me, where, e)
	draw_rect(head, SIDE_COLORS[b.side])
	_draw_bag_head(font, b, head, keys.find(b) + 1, _bag_mana(me, b))
	var outline: Color = UiKit.ALERT if BagDefs.TIERS[b.tier].has("curse_desc") else SIDE_COLORS[b.side].lightened(0.3)
	draw_rect(area.merge(head), UiKit.GOLD if focused else outline, false, 3.0 if focused else 1.5)
	if dragged:
		draw_rect(area.merge(head), SHADE)


# 袋子裡的技能（含原本的效果）：右上角寫蓋了幾個有作用的修飾；拿著修飾時，它有作用的技能亮金框（蓋得到）
func _draw_skill_marks(font: Font, me: Player, where: int, b: Dictionary) -> void:
	var holding_mod := not _drag.is_empty() and ItemDefs.is_mod(_drag.id)
	for e: Dictionary in b.entries:
		if not ItemDefs.is_coverable(e.id):
			continue
		var rects: Array[Rect2] = []
		for c in Inventory.cells_of(e.id, e.rot):
			rects.append(_cell_rect(me, where, e.cell + c))
		if holding_mod and ItemDefs.mod_applies(_drag.id, e.id):
			var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008)
			for r in rects:
				draw_rect(r.grow(-2), Color(UiKit.GOLD, 0.18 * pulse))
				draw_rect(r.grow(-2), Color(UiKit.GOLD, pulse), false, 2.0)
		var n := ActiveSlots.mod_ids_on(b, e).size()
		if n > 0:
			var corner := rects[0].position + Vector2(rects[0].size.x - 15.0, 3.0)
			draw_circle(corner + Vector2(6, 8), 8.0, Color(0, 0, 0, 0.8))
			draw_string(font, corner + Vector2(0, 14), str(n), HORIZONTAL_ALIGNMENT_CENTER, 12, 14, UiKit.GOLD)


# 標題條的字：一句話講什麼時候發動；左右兩邊的直著寫，下面照魔力與倍率
func _draw_bag_head(font: Font, b: Dictionary, head: Rect2, key_number: int, mana: int) -> void:
	var tail := ""
	if b.mul != 1.0:
		tail = "×%s" % str(b.mul)
	var mana_text := "魔 %d" % mana if mana > 0 else ""
	if b.side in [&"top", &"bottom"]:
		var x := head.position.x + 8
		var y := head.position.y + 19
		if b.kind == &"key":
			draw_string(font, Vector2(x, y), "按", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
			var cap := Rect2(x + 19, head.position.y + 4, 19, 18)
			draw_rect(cap, Color(0.07, 0.05, 0.11))
			draw_rect(cap, Color(1, 1, 1, 0.7), false, 1.0)
			draw_string(font, Vector2(cap.position.x, y), str(key_number), HORIZONTAL_ALIGNMENT_CENTER, cap.size.x, 14, Color.WHITE)
		else:
			draw_string(font, Vector2(x, y), head_text(b) + (" " + tail if tail != "" else ""), HORIZONTAL_ALIGNMENT_LEFT, head.size.x - 60, 15, Color.WHITE)
		draw_string(font, Vector2(head.position.x, y), mana_text, HORIZONTAL_ALIGNMENT_RIGHT, head.size.x - 7, 12, Color(1, 1, 1, 0.75))
		return
	var cy := head.position.y + 20
	for ch in head_text(b):
		draw_string(font, Vector2(head.position.x, cy), ch, HORIZONTAL_ALIGNMENT_CENTER, head.size.x, 15, Color.WHITE)
		cy += 17.0
	var bottom := head.end.y - 7
	if mana > 0:
		draw_string(font, Vector2(head.position.x, bottom), str(mana), HORIZONTAL_ALIGNMENT_CENTER, head.size.x, 12, Color(1, 1, 1, 0.75))
		draw_string(font, Vector2(head.position.x, bottom - 14), "魔", HORIZONTAL_ALIGNMENT_CENTER, head.size.x, 12, Color(1, 1, 1, 0.75))
		bottom -= 30
	if tail != "":
		draw_string(font, Vector2(head.position.x, bottom), tail, HORIZONTAL_ALIGNMENT_CENTER, head.size.x, 11, UiKit.GOLD)


# 拿著袋子：這種袋子能接的邊上，放得下的位置都亮起來（不能接的邊不亮）；滑鼠指著的位置在 _draw_drag 畫
func _draw_bag_spots(me: Player) -> void:
	var b: Dictionary = _drag.bag
	for side: StringName in BagDefs.BAGS[b.kind].sides:
		var probe: Dictionary = b.duplicate()
		probe.side = side
		for offset in BagDefs.edge_length(side) - b.length + 1:
			probe.offset = offset
			if not me.loadout.bag_fits(probe, side, offset, b.uid):
				continue
			for y in b.depth:
				for x in b.length:
					var r := _bcell_rect(Loadout.board_cell(probe, Vector2i(x, y)))
					draw_rect(r.grow(-1), Color(OK_TINT, 0.1))


# 這個袋子放一次全部要多少魔力（含蓋在技能上的修飾的倍率）
static func _bag_mana(me: Player, b: Dictionary) -> int:
	var total := 0.0
	for e: Dictionary in b.entries:
		match ItemDefs.role_of(e.id):
			ItemDefs.ROLE_EFFECT:
				total += BagTriggers.effect_cost(b, e)
			ItemDefs.ROLE_SKILL:
				total += ActiveSlots.mana_cost(me, ActiveSlots.slot_of(me, b, e))
	return roundi(total)


# 袋子的標題：一句話講什麼時候發動（按鍵袋的數字鍵另外畫）
static func head_text(b: Dictionary) -> String:
	var who: String = {&"left": "左鍵", &"right": "右鍵"}.get(b.side, "")
	match b.kind:
		&"cast":
			return "%s出手時" % who
		&"hit":
			return "%s打中時" % who
		&"kill":
			return "%s擊殺時" % who
		&"hurt":
			return "受傷時"
		&"roll":
			return "翻滾時"
		&"timer":
			return "每 %d 秒" % int(BagDefs.BAGS.timer.period)
	return "按鍵"


func _draw_entry(font: Font, me: Player, where: int, e: Dictionary) -> void:
	var rects: Array[Rect2] = []
	for c in Inventory.cells_of(e.id, e.rot):
		rects.append(_cell_rect(me, where, e.cell + c))
	var dim: bool = not _drag.is_empty() and _drag.uid == e.uid
	_draw_item(font, e.id, rects, ItemDefs.ITEMS[e.id].rarity, 0.35 if dim else 1.0)


func _draw_storage(font: Font, me: Player) -> void:
	var o := _grid_origin()
	var bag: Vector2i = ItemDefs.BAG_SIZE
	draw_string(font, o + Vector2(0, -6), "倉庫 %d / %d（每格一件，不生效）" % [me.inventory.entries.size(), bag.x * bag.y], HORIZONTAL_ALIGNMENT_LEFT, BOND_W, 16, Color(1, 1, 1, 0.6))
	for y in bag.y:
		for x in bag.x:
			var cell := Rect2(o + Vector2(x, y) * CELL, Vector2(CELL, CELL)).grow(-1)
			draw_rect(cell, Color(1, 1, 1, 0.05))
			draw_rect(cell, Color(1, 1, 1, 0.12), false, 1.0)
	for e: Dictionary in me.inventory.entries:
		var dim: bool = (not _drag.is_empty() and _drag.uid == e.uid) or (forge != null and forge.dims(e.get("weapon", {})))
		var rects: Array[Rect2] = [Rect2(o + Vector2(e.cell) * CELL, Vector2(CELL, CELL))]
		_draw_item(font, e.id, rects, _rarity_of(e), 0.35 if dim else 1.0, e.get("weapon", {}))
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
	if _drag.has("bag"):
		var spot := _bag_drop(local)
		if not spot.is_empty():
			var probe: Dictionary = _drag.bag.duplicate()
			probe.side = spot.side
			probe.offset = spot.offset
			var ok := me.loadout.bag_fits(probe, spot.side, spot.offset, _drag.uid)
			for y in probe.depth:
				for x in probe.length:
					draw_rect(_bcell_rect(Loadout.board_cell(probe, Vector2i(x, y))).grow(-2), Color(OK_TINT, 0.4) if ok else Color(1, 0.3, 0.3, 0.35))
			if ok:   # 預覽接上後的標題
				var head := _bag_head_rect(probe)
				draw_rect(head, Color(0.11, 0.23, 0.16))
				draw_rect(head, OK_TINT, false, 2.0)
				_draw_bag_head(font, probe, head, me.loadout.key_bags().size() + 1, 0)
			return
	var t := _target_at(me, local)
	if t.is_empty() or _drag.has("bag") and t.where != Loadout.BAG:   # 不在格子上：東西跟著滑鼠（抓住的那一格在滑鼠下）
		var shape := Inventory.cells_of(_drag.id, _drag.rot)
		var anchor: Vector2i = shape[mini(_drag.anchor, shape.size() - 1)]
		var o := local - (Vector2(anchor) + Vector2(0.5, 0.5)) * BCELL
		var rects: Array[Rect2] = []
		for c in shape:
			rects.append(Rect2(o + Vector2(c) * BCELL, Vector2(BCELL, BCELL)))
		_draw_item(font, _drag.id, rects, _drag_rarity(), 0.85, _drag.weapon)
		return
	var inv := me.loadout.container(t.where)
	var at := _drag_cell(t.cell, t.where)
	var ok := inv.fits(_drag.id, at, _drag.rot, _drag.uid)
	# 放不下但蓋住的只有 1 件、那件換得回去：金色 + 「互換」（規則在 Loadout.swap_partner，跟權威端同一套）
	var partner := &"" if ok or _drag.has("pickup_id") else me.loadout.swap_partner(_drag.uid, t.where, at, _drag.rot)
	var tint := Color(0.3, 1, 0.4, 0.35) if ok else (Color(1, 0.85, 0.3, 0.35) if partner != &"" else Color(1, 0.3, 0.3, 0.35))
	var rects: Array[Rect2] = []
	for c in inv.cells(_drag.id, _drag.rot):
		rects.append(_cell_rect(me, t.where, at + c))
	_draw_item(font, _drag.id, rects, _drag_rarity(), 0.85, _drag.weapon)
	for r in rects:   # 畫在物品上面：放得下（綠）、互換（金）、放不下（紅）才看得出來
		draw_rect(r.grow(-2), tint)
	if partner != &"":
		var swap_text := "換上" if not _drag.weapon.is_empty() and me.inventory.find(_drag.uid).is_empty() else "互換"
		draw_string(font, rects[0].position + Vector2(6, 24), swap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiKit.GOLD)
	elif not ok and not inv.accepts(_drag.id):
		draw_string(font, rects[0].position + Vector2(6, 24), "主袋只放數值" if t.where == Loadout.CORE else "袋子不放武器", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.DENY)


# 撿不下時取代操作說明的那一行
func _full_text(me: Player, target: ItemPickup) -> String:
	var e := me.inventory.find(_suggest) if me != null and _suggest != &"" else {}
	if e.is_empty():
		return "放不下「%s」：主袋、袋子和倉庫都滿了，要整理一下" % target.display_name()
	var item_name: String = WeaponDropDefs.display_name(e.weapon) if e.has("weapon") else ItemDefs.ITEMS[e.id].name
	return "放不下「%s」：拿掉倉庫裡的「%s」就放得下" % [target.display_name(), item_name]


# 建議拿掉的那一件：每格閃爍的紅色虛線框
func _draw_suggestion(e: Dictionary) -> void:
	if e.is_empty():
		return
	var color := Color(UiKit.DENY, 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008))
	UiKit.draw_dashed_rect(self, Rect2(_grid_origin() + Vector2(e.cell) * CELL, Vector2(CELL, CELL)).grow(-1), color)


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


# 合成提示框：滑鼠下面那個武器所在的名稱框或倉庫格
func _hover_rect(local: Vector2) -> Rect2:
	var slot := _slot_at(local)
	if slot >= 0:
		return _slot_rect(slot)
	return Rect2(_grid_origin() + Vector2(_cell_at(local)) * CELL, Vector2(CELL, CELL))


# 主手 / 副手的名稱框（拖武器到這裡換上）
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
			draw_string(font, r.position + Vector2(10, r.size.y / 2.0 + 7), "雙手武器：不能拿副手", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16, 15, Color(1, 1, 1, 0.55))
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
		draw_string(font, r.position + Vector2(10, 50), ("攻擊力 %.1f" % b.damage) if not b.is_empty() else "副手", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.7))


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


# 一件東西（畫法在 UiKit.draw_item_cells，和遺物卡片共用）；滑鼠停在羈絆上時，不屬於那個羈絆的變淡
func _draw_item(font: Font, id: StringName, rects: Array[Rect2], rarity: StringName, alpha: float, weapon: Dictionary = {}) -> void:
	if _drag.is_empty() and _hover_bond != &"" and not UiKit.item_bonds(id, weapon).has(_hover_bond):
		alpha *= DIM_ALPHA
	UiKit.draw_item_cells(self, font, id, rects, rarity, alpha, weapon, _hover_bond if _drag.is_empty() else &"")


# 浮動說明：跟著滑鼠，寫滑鼠停著（或拖著）的東西：道具的效果與放在哪、袋子的時機、武器的數值（腳邊的道具也一樣）
func _draw_tip() -> void:
	var me := _player()
	if me == null:
		return
	var info := _info_of(me)
	if info.is_empty():
		return
	var font := get_theme_default_font()
	var text_w := TIP_W - TIP_PAD * 2.0
	var title_h := font.get_multiline_string_size(info.title, HORIZONTAL_ALIGNMENT_LEFT, text_w, TIP_TITLE_FONT).y
	var body_h := UiKit.draw_rich_lines(null, font, Vector2.ZERO, info.lines, text_w, TIP_FONT)
	var tip_size := Vector2(TIP_W, TIP_PAD * 2.0 + title_h + 6.0 + body_h)
	var box := tip_rect(get_global_mouse_position(), tip_size, get_viewport_rect().size)
	_tip_layer.draw_rect(box, Color(0.04, 0.05, 0.08, 0.96))
	_tip_layer.draw_rect(box, Color(info.color, 0.8), false, 1.5)
	var inner := box.position + Vector2(TIP_PAD, TIP_PAD)
	_tip_layer.draw_multiline_string(font, inner + Vector2(0, font.get_ascent(TIP_TITLE_FONT)), info.title, HORIZONTAL_ALIGNMENT_LEFT, text_w, TIP_TITLE_FONT, -1, info.color)
	UiKit.draw_rich_lines(_tip_layer, font, inner + Vector2(0, title_h + 6.0), info.lines, text_w, TIP_FONT)


# 浮動說明放哪（畫面座標）：預設在滑鼠右下，右邊放不下翻到左邊，下面放不下往上推，不超出畫面
static func tip_rect(mouse: Vector2, tip_size: Vector2, screen: Vector2) -> Rect2:
	var p := mouse + TIP_OFFSET
	if p.x + tip_size.x > screen.x - TIP_MARGIN:
		p.x = mouse.x - TIP_OFFSET.x - tip_size.x
	p.y = minf(p.y, screen.y - TIP_MARGIN - tip_size.y)
	return Rect2(p.clamp(Vector2(TIP_MARGIN, TIP_MARGIN), screen - tip_size - Vector2(TIP_MARGIN, TIP_MARGIN)), tip_size)


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
	if _drag.has("bag"):
		var spot := _bag_drop(get_local_mouse_position())
		if not spot.is_empty() and me.loadout.bag_fits(_drag.bag, spot.side, spot.offset, _drag.uid):
			var probe: Dictionary = _drag.bag.duplicate()
			probe.side = spot.side
			probe.offset = spot.offset
			var preview := bag_info(probe, me)
			preview.title = "放這裡 → %s" % preview.title
			return preview
	for s in me.weapon_slots:
		if s.get("uid", &"") == uid:
			return UiKit.item_info(s.base, s)
	var bag := me.loadout.find_bag(uid)
	if not bag.is_empty():
		return bag_info(bag, me)
	var found := me.loadout.find_item(uid)
	if not found.is_empty() and found.where != Loadout.BAG:
		var info := UiKit.item_info(found.entry.id, {}, me.skill_levels.get(found.entry.id, 1))
		if found.where == Loadout.CORE:
			info.title += "（在主袋 · 生效中）"
		else:
			var b: Dictionary = me.loadout.bags[found.where]
			if ItemDefs.role_of(found.entry.id) == ItemDefs.ROLE_STAT:
				info.title += "（在%s · 生效中）" % BagDefs.bag_name(b)
			else:
				info.title += "（在%s · %s發動）" % [BagDefs.bag_name(b), head_text(b) if b.kind != &"key" else "按數字鍵"]
				info.lines.append("發動：%s" % when_text(b))
		return info
	var e := me.inventory.find(uid)
	if e.is_empty():
		return {}
	var bag_entry := UiKit.item_info(e.id, e.get("weapon", {}), me.skill_levels.get(e.id, 1))
	bag_entry.title += "（在倉庫裡不生效）"
	return bag_entry


# 袋子什麼時候發動（看種類與接的邊）：左邊「普攻打中時」、右邊「右鍵招式打中時」、按鍵袋「按 N」
static func when_text(b: Dictionary) -> String:
	var who: String = {&"left": "普攻", &"right": "右鍵招式"}.get(b.side, "")
	match b.kind:
		&"cast":
			return "%s出手時" % who
		&"hit":
			return "%s打中時（劍盾的右鍵 = 招架成功；同一袋 %s 秒最多一次）" % [who, str(BagDefs.BAGS.hit.icd)] if b.side == &"right" else "%s打中時（同一袋 %s 秒最多一次）" % [who, str(BagDefs.BAGS.hit.icd)]
		&"kill":
			return "%s打死怪時" % who
		&"key":
			return "按數字鍵"
	return BagDefs.BAGS[b.kind].desc


# 袋子的說明：什麼時候、在哪裡、放什麼（完整一句話），下一行大小、耗魔、內部冷卻與倍率，詛咒另一行
static func bag_info(b: Dictionary, me: Player = null) -> Dictionary:
	var lines: Array[String] = [fire_sentence(b)]
	var size_line := "%d × %d 格" % [b.length, b.depth]
	if me != null and not b.entries.is_empty():
		size_line += " · 每次耗魔 %d" % _bag_mana(me, b)
	var icd: float = BagDefs.BAGS[b.kind].get("icd", 0.0)
	if icd > 0.0:
		size_line += " · 同一袋 %s 秒最多一次" % str(icd)
	if b.mul != 1.0:
		size_line += " · 傷害 ×%s" % str(b.mul)
	lines.append(size_line)
	var t: Dictionary = BagDefs.TIERS[b.tier]
	if t.has("curse_desc"):
		lines.append("詛咒：%s" % t.curse_desc)
	var title := "%s · %s" % [head_text(b) if b.kind != &"key" else "按數字鍵", BagDefs.bag_name(b)] if b.side != &"" else "%s（在倉庫裡不生效）" % BagDefs.bag_name(b)
	return {"title": title, "color": SIDE_COLORS.get(b.side, UiKit.GOLD).lightened(0.4), "lines": lines}


# 一句話講這個袋子怎麼發動：「右鍵招式打中怪時，在那隻怪身上一起放：雷霆鈴、閃電鏈。」
static func fire_sentence(b: Dictionary) -> String:
	if b.side == &"":
		return "接上主袋才會發動：%s。" % String(BagDefs.BAGS[b.kind].desc).get_slice("（", 0)
	var when := when_text(b).get_slice("（", 0)
	var where: String = {&"hit": "在那隻怪身上", &"kill": "在怪死的位置", &"hurt": "在打你的怪身上"}.get(b.kind, "")
	var names: Array[String] = []
	for e: Dictionary in BagTriggers.contents(b):
		if ItemDefs.role_of(e.id) in [ItemDefs.ROLE_EFFECT, ItemDefs.ROLE_SKILL]:   # 數值與修飾不會被放出來
			names.append(String(ItemDefs.ITEMS[e.id].name))
	if names.is_empty():
		return "%s，%s放裡面的東西（還沒放東西）。" % [when, where]
	return "%s，%s一起放：%s。" % [when, where, "、".join(names)]


# 滑鼠停在羈絆上：現在第幾階、已啟動的那一階與下一階的效果
func _bond_info(me: Player, bond: StringName) -> Dictionary:
	var def: Dictionary = BondDefs.BONDS[bond]
	var count: int = me.loadout.bond_counts.get(bond, 0)
	var t := BondDefs.tier(bond, count)
	var lines: Array[String] = []
	if t > 0:
		lines.append("第 %d 階（%d 格）：%s" % [t, def.thresholds[t - 1], def.tiers[t - 1]])
	var next := BondDefs.next_threshold(bond, count)
	if next > 0:
		lines.append("下一階（%d 格）：%s" % [next, def.tiers[t]])
	return {"title": "%s羈絆：最大一塊 %d 格" % [def.name, count], "color": def.color, "lines": lines}
