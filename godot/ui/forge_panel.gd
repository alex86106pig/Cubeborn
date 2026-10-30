# 鍛造祭壇的合成（Build 改版第 8 步，2026-10-30 許家慶決定：兩把各挑一條詞條留下、其他重抽）
# 在背包裡把武器拖到同種、同稀有度的武器上，兩把都有詞條時打開（InventoryPanel.merge_choice）；放在背包左邊，滑鼠點
# 兩把各點一條（預設各自第一條），按「合成」送 [OP_MERGE, a, b, 留 a 的, 留 b 的]；結果等權威端
# 背包關掉、離開鍛造祭壇、兩把有一把不見了（或不能合了）就自動關掉
class_name ForgePanel
extends PanelContainer

signal op_requested(op: Array)

const ROW := {"size": Vector2(300, 40), "font": UiKit.FONT_NOTE}

var uid_a := &""
var uid_b := &""
var _keep := [&"", &""]               # 兩把各自選中的詞條
var _rows: Array[VBoxContainer] = []  # 兩把各一列詞條按鈕
var _title := UiKit.label("", UiKit.FONT_NOTE, UiKit.GOLD)
var _heads: Array[Label] = []


func _init() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = UiKit.SLOT_BG
	bg.border_color = UiKit.GOLD
	bg.set_border_width_all(1)
	bg.set_content_margin_all(14)
	add_theme_stylebox_override(&"panel", bg)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	box.add_child(_title)
	for i in 2:
		var head := UiKit.label("", UiKit.FONT_NOTE, Color(1, 1, 1, 0.8))
		_heads.append(head)
		box.add_child(head)
		var row := VBoxContainer.new()
		row.add_theme_constant_override(&"separation", 4)
		_rows.append(row)
		box.add_child(row)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	var ok := UiKit.button("合成", {"size": Vector2(146, 44), "font": UiKit.FONT_NOTE})
	ok.pressed.connect(confirm)
	var cancel := UiKit.button("取消", {"size": Vector2(146, 44), "font": UiKit.FONT_NOTE})
	cancel.pressed.connect(close)
	buttons.add_child(ok)
	buttons.add_child(cancel)
	box.add_child(buttons)
	add_child(box)
	visible = false


# 打開：a 拖到 b 上（InventoryPanel 已經確認可以合成、站在鍛造祭壇旁）
func open(a: Dictionary, b: Dictionary) -> void:
	uid_a = a.uid
	uid_b = b.uid
	var to: Dictionary = ItemDefs.RARITIES[WeaponDropDefs.next_rarity(b.rarity)]
	_title.text = "合成成%s %s：兩把各留一條詞條，其他重抽" % [to.name, ItemDefs.ITEMS[b.base].name]
	for i in 2:
		var inst: Dictionary = [a, b][i]
		_heads[i].text = "%s留哪一條：" % ("拖過來的那把" if i == 0 else "被拖到的那把")
		_keep[i] = inst.affixes[0] if not inst.affixes.is_empty() else &""
		_rebuild_row(i, inst)
	visible = true


func _rebuild_row(i: int, inst: Dictionary) -> void:
	var row := _rows[i]
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()
	for id: StringName in inst.affixes:
		var a: Dictionary = WeaponDropDefs.AFFIXES[id]
		var b := UiKit.button(("● " if _keep[i] == id else "○ ") + a.desc, ROW)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var color: Color = BondDefs.BONDS[a.bond].color
		b.add_theme_color_override(&"font_color", color if _keep[i] == id else color.darkened(0.35))
		b.add_theme_color_override(&"font_hover_color", color.lightened(0.3))
		b.pressed.connect(choose.bind(i, id, inst))
		row.add_child(b)


func choose(i: int, id: StringName, inst: Dictionary) -> void:
	_keep[i] = id
	_rebuild_row(i, inst)


func confirm() -> void:
	if visible:
		op_requested.emit([InputCmd.OP_MERGE, String(uid_a), String(uid_b), String(_keep[0]), String(_keep[1])])
	close()


func close() -> void:
	visible = false
	uid_a = &""
	uid_b = &""


# 每幀（HUD._process）：背包關了、離開鍛造祭壇、兩把有一把不見了或不能合了就關掉
func refresh(world: World, me: Player, inventory_open: bool) -> void:
	if not visible:
		return
	if me == null or not inventory_open or not world.near_forge(me):
		close()
		return
	var a := _find(me, uid_a)
	var b := _find(me, uid_b)
	if not WeaponDropDefs.can_merge(a, b):
		close()


static func _find(me: Player, uid: StringName) -> Dictionary:
	for w: Dictionary in me.weapon_slots:
		if not w.is_empty() and w.uid == uid:
			return w
	for e: Dictionary in me.inventory.entries:
		if e.uid == uid:
			return e.get("weapon", {})
	return {}
