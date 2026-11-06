# 武器測試場的測試面板（左上，平常收起只剩分頁與工具列；開背包時 HUD 把它藏起來）：分頁選職業與背包模式、做武器（稀有度）、道具、技能、袋子 / 開格、怪物（含稀有度）；
# 按鈕只發訊號，main.gd 交給 Practice 改模擬狀態。怪物停手 / 攻擊也可以按 T
class_name TestPanel
extends PanelContainer

signal class_chosen(id: StringName)                       # ClassDefs.NONE = 無職業（基準數值）
signal weapon_requested(base: StringName, rarity: StringName)
signal bag_requested(kind: StringName, tier: StringName)   # 袋子分開的模式
signal unlock_requested(action: StringName)                # 背包合併：random / pick / all
signal bag_mode_toggled                                    # 換背包模式（重新開始測試場）
signal item_requested(id: StringName)                     # 道具與技能都走這個
signal enemy_requested(type: StringName, rarity: StringName)
signal hold_toggled
signal clear_enemies
signal reset_dummies

const WIDTH := 660.0           # 放在左上，畫面中央留給角色
const LIST_HEIGHT := 380.0
const TAB_BUTTON := {"size": Vector2(96, 44), "font": 20}   # 分頁 6 顆排一排要塞進 WIDTH（BUTTON_S 120 寬會超出）
const TABS: Array[StringName] = [&"class", &"weapon", &"item", &"skill", &"bag", &"enemy"]
const TAB_NAMES := {&"class": "職業", &"weapon": "武器", &"item": "道具", &"skill": "技能", &"bag": "袋子", &"enemy": "怪物"}

var hold_button := UiKit.button("怪物：攻擊中（T）", UiKit.BUTTON_M)
var note := UiKit.label("", UiKit.FONT_NOTE, UiKit.GOLD)
var active := false        # 在武器測試場（main.gd 設）；HUD 照它與背包開沒開決定顯示
var tab_buttons := {}      # 分頁 → Button
var pages := {}            # 分頁 → Control
var weapon_base := &""
var weapon_rarity := &"white"
var enemy_rarity := MonsterRarityDefs.NORMAL
var mode_button := UiKit.button("換成背包合併", UiKit.BUTTON_M)
var mode_label := UiKit.label("背包：袋子分開", UiKit.FONT_NOTE, UiKit.GOLD)
var _body := VBoxContainer.new()
var _weapon_buttons := {}
var _rarity_buttons := {}
var _enemy_rarity_buttons := {}
var _bag_page := VBoxContainer.new()
var _merged := false       # 現在的背包模式（main.gd 設，袋子分頁照它換內容）


func _init() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.05, 0.09, 0.88)
	bg.border_color = Color(1, 1, 1, 0.2)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(10)
	add_theme_stylebox_override(&"panel", bg)
	custom_minimum_size.x = WIDTH
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 8)
	add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 8)
	for t: StringName in TABS:
		var b := UiKit.button(TAB_NAMES[t], TAB_BUTTON)
		b.toggle_mode = true
		b.pressed.connect(show_tab.bind(t))
		tab_buttons[t] = b
		head.add_child(b)
	root.add_child(head)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override(&"separation", 8)
	hold_button.pressed.connect(hold_toggled.emit)
	tools.add_child(hold_button)
	tools.add_child(_action("清除怪物", clear_enemies.emit, UiKit.BUTTON_S))
	tools.add_child(_action("重置木樁", reset_dummies.emit, UiKit.BUTTON_S))
	tools.add_child(UiKit.label("Esc 回主選單", UiKit.FONT_NOTE, Color(1, 1, 1, 0.8)))
	root.add_child(tools)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(note)
	_build_class_page()
	_build_weapon_page()
	_build_list_page(&"item", _ids_of(&"item"), func(id: StringName) -> void: item_requested.emit(id))
	_build_list_page(&"skill", _ids_of(&"skill"), func(id: StringName) -> void: item_requested.emit(id))
	_build_bag_page()
	_build_enemy_page()
	root.add_child(_body)
	set_collapsed(true)


static func _action(text: String, fn: Callable, kind: Dictionary = UiKit.BUTTON_M) -> Button:
	var b := UiKit.button(text, kind)
	b.pressed.connect(fn)
	return b


static func _ids_of(kind: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in ItemDefs.ITEMS:
		if ItemDefs.ITEMS[id].kind == kind and (kind != &"item" or ItemDefs.item_implemented(id)):
			out.append(id)
	return out


# 點分頁展開那一頁；點開著的那一頁收起（只剩分頁與工具列）
func show_tab(t: StringName) -> void:
	if _body.visible and pages[t].visible:
		set_collapsed(true)
		return
	for k: StringName in pages:
		pages[k].visible = k == t
		tab_buttons[k].set_pressed_no_signal(k == t)
	_body.visible = true


func set_collapsed(on: bool) -> void:
	_body.visible = not on
	if on:
		for k: StringName in tab_buttons:
			tab_buttons[k].set_pressed_no_signal(false)


func set_hold(on: bool) -> void:
	hold_button.text = "怪物：停手（T）" if on else "怪物：攻擊中（T）"


func set_note(text: String) -> void:
	note.text = text


func _scroll_page(t: StringName, content: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH - 20.0, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	pages[t] = scroll
	_body.add_child(scroll)


static func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override(&"h_separation", 6)
	f.add_theme_constant_override(&"v_separation", 6)
	return f


static func _rarity_color(b: Button, rarity: StringName) -> void:
	b.add_theme_color_override(&"font_color", ItemDefs.RARITIES[rarity].color)
	b.add_theme_color_override(&"font_hover_color", ItemDefs.RARITIES[rarity].color)


func _build_class_page() -> void:
	var f := _flow()
	var none := UiKit.button("無職業", UiKit.BUTTON_M)
	none.pressed.connect(func() -> void: class_chosen.emit(ClassDefs.NONE))
	f.add_child(none)
	for id: StringName in ClassDefs.CLASSES:
		var b := UiKit.button(ClassDefs.CLASSES[id].name, UiKit.BUTTON_M)
		b.pressed.connect(func() -> void: class_chosen.emit(id))
		f.add_child(b)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	box.add_child(f)
	box.add_child(UiKit.label("換職業會重新開始測試場（背包清空）", UiKit.FONT_NOTE, Color(1, 1, 1, 0.7)))
	mode_button.pressed.connect(bag_mode_toggled.emit)
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override(&"separation", 12)
	mode_row.add_child(mode_label)
	mode_row.add_child(mode_button)
	box.add_child(mode_row)
	box.add_child(UiKit.label("換背包模式也會重新開始；正式遊戲在設定頁切換", UiKit.FONT_NOTE, Color(1, 1, 1, 0.7)))
	_scroll_page(&"class", box)


func _build_weapon_page() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	var bases := _flow()
	for id in _ids_of(&"weapon"):
		var b := UiKit.button(ItemDefs.ITEMS[id].name, UiKit.BUTTON_S)
		b.toggle_mode = true
		b.pressed.connect(_pick_base.bind(id))
		_weapon_buttons[id] = b
		bases.add_child(b)
	box.add_child(bases)
	var rarities := _flow()
	for r: StringName in [WeaponDropDefs.START_RARITY] + WeaponDropDefs.RARITY_ORDER:
		var b := UiKit.button(ItemDefs.RARITIES[r].name, UiKit.BUTTON_S)
		b.toggle_mode = true
		_rarity_color(b, r)
		b.pressed.connect(_pick_rarity.bind(r))
		_rarity_buttons[r] = b
		rarities.add_child(b)
	rarities.add_child(_action("放進背包", _request_weapon))
	box.add_child(rarities)
	box.add_child(UiKit.label("灰色 = 起始武器（數值固定）；其他稀有度照掉落的規則擲數值", UiKit.FONT_NOTE, Color(1, 1, 1, 0.7)))
	_scroll_page(&"weapon", box)
	_pick_base(_ids_of(&"weapon")[0])
	_pick_rarity(&"white")


func _pick_base(id: StringName) -> void:
	weapon_base = id
	for k: StringName in _weapon_buttons:
		_weapon_buttons[k].set_pressed_no_signal(k == id)


func _pick_rarity(r: StringName) -> void:
	weapon_rarity = r
	for k: StringName in _rarity_buttons:
		_rarity_buttons[k].set_pressed_no_signal(k == r)


func _request_weapon() -> void:
	weapon_requested.emit(weapon_base, weapon_rarity)


func _build_list_page(t: StringName, ids: Array[StringName], fn: Callable) -> void:
	var f := _flow()
	for id in ids:
		var b := UiKit.button(ItemDefs.ITEMS[id].name, UiKit.BUTTON_S)
		_rarity_color(b, ItemDefs.ITEMS[id].rarity)
		b.tooltip_text = ItemDefs.ITEMS[id].get("desc", "")
		b.pressed.connect(fn.bind(id))
		f.add_child(b)
	_scroll_page(t, f)


func _build_enemy_page() -> void:
	var f := _flow()
	for id in Practice.enemy_types():
		var def := EnemyDefs.def_of(id)
		var b := UiKit.button(def.get("name", String(id)), UiKit.BUTTON_S)
		if EnemyDefs.is_boss(id):
			b.add_theme_color_override(&"font_color", UiKit.BOSS_NAME_ENRAGED)
		b.pressed.connect(func() -> void: enemy_requested.emit(id, enemy_rarity))
		f.add_child(b)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	var rf := _flow()
	for r: StringName in MonsterRarityDefs.RARITIES:
		var rb := UiKit.button(MonsterRarityDefs.RARITIES[r].name, UiKit.BUTTON_S)
		rb.toggle_mode = true
		rb.pressed.connect(_pick_enemy_rarity.bind(r))
		_enemy_rarity_buttons[r] = rb
		rf.add_child(rb)
	box.add_child(rf)
	box.add_child(f)
	box.add_child(UiKit.label("先選稀有度再點怪，生在面前（紅字是 Boss，不套稀有度）", UiKit.FONT_NOTE, Color(1, 1, 1, 0.7)))
	_pick_enemy_rarity(MonsterRarityDefs.NORMAL)
	_scroll_page(&"enemy", box)


func _pick_enemy_rarity(r: StringName) -> void:
	enemy_rarity = r
	for k: StringName in _enemy_rarity_buttons:
		_enemy_rarity_buttons[k].set_pressed_no_signal(k == r)


# 袋子分頁：袋子分開的模式列每種袋子 × 大小；背包合併列開格（照 set_bag_mode 重建）
func _build_bag_page() -> void:
	_bag_page.add_theme_constant_override(&"separation", 8)
	_scroll_page(&"bag", _bag_page)
	_fill_bag_page()


func _fill_bag_page() -> void:
	for c in _bag_page.get_children():
		_bag_page.remove_child(c)
		c.queue_free()
	if _merged:
		var f := _flow()
		f.add_child(_action("隨機開 1 格", func() -> void: unlock_requested.emit(&"random"), UiKit.BUTTON_S))
		f.add_child(_action("自選 +1", func() -> void: unlock_requested.emit(&"pick"), UiKit.BUTTON_S))
		f.add_child(_action("全部打開", func() -> void: unlock_requested.emit(&"all"), UiKit.BUTTON_S))
		_bag_page.add_child(f)
		_bag_page.add_child(UiKit.label("背包合併：隨機 = 過小關、門的開格；自選 = Boss、鐵砧", UiKit.FONT_NOTE, Color(1, 1, 1, 0.7)))
		return
	for tier: StringName in BagDefs.TIERS:
		var f := _flow()
		for kind: StringName in BagDefs.BAGS:
			var b := UiKit.button(BagDefs.bag_name({"kind": kind, "tier": tier}), UiKit.BUTTON_S)
			if BagDefs.TIERS[tier].has("curse_desc"):
				b.add_theme_color_override(&"font_color", UiKit.ALERT)
			b.pressed.connect(func() -> void: bag_requested.emit(kind, tier))
			f.add_child(b)
		_bag_page.add_child(f)
	_bag_page.add_child(UiKit.label("照撿到的規則接上，接不下進倉庫（紅字是詛咒袋）", UiKit.FONT_NOTE, Color(1, 1, 1, 0.7)))


# 背包模式（main.gd 開局時設）：模式按鈕的字、袋子分頁的內容
func set_bag_mode(merged: bool) -> void:
	mode_label.text = "背包：合併" if merged else "背包：袋子分開"
	mode_button.text = "換成袋子分開" if merged else "換成背包合併"
	if merged == _merged and _bag_page.get_child_count() > 0:
		return
	_merged = merged
	_fill_bag_page()
