# 武器測試場的測試面板（左上，平常收起只剩分頁與工具列；開背包時 HUD 把它藏起來）：分頁選職業、做武器（稀有度 + 詞條）、道具、技能、怪物；
# 按鈕只發訊號，main.gd 交給 Practice 改模擬狀態。怪物停手 / 攻擊也可以按 T
class_name TestPanel
extends PanelContainer

signal class_chosen(id: StringName)                       # ClassDefs.NONE = 無職業（基準數值）
signal weapon_requested(base: StringName, rarity: StringName, affixes: Array[StringName])
signal item_requested(id: StringName)                     # 道具與技能都走這個
signal enemy_requested(type: StringName)
signal hold_toggled
signal clear_enemies
signal reset_dummies

const WIDTH := 660.0           # 放在左上，畫面中央留給角色
const LIST_HEIGHT := 380.0
const AFFIX_SIZE := Vector2(310, 44)   # 一排 2 顆
const TABS: Array[StringName] = [&"class", &"weapon", &"item", &"skill", &"enemy"]
const TAB_NAMES := {&"class": "職業", &"weapon": "武器", &"item": "道具", &"skill": "技能", &"enemy": "怪物"}

var hold_button := UiKit.button("怪物：攻擊中（T）", UiKit.BUTTON_M)
var note := UiKit.label("", UiKit.FONT_NOTE, UiKit.GOLD)
var active := false        # 在武器測試場（main.gd 設）；HUD 照它與背包開沒開決定顯示
var tab_buttons := {}      # 分頁 → Button
var pages := {}            # 分頁 → Control
var weapon_base := &""
var weapon_rarity := &"white"
var _body := VBoxContainer.new()
var _weapon_buttons := {}
var _rarity_buttons := {}
var _affix_buttons := {}   # 詞條 id → Button（切換鈕）


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
		var b := UiKit.button(TAB_NAMES[t], UiKit.BUTTON_S)
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
	box.add_child(f)
	box.add_child(UiKit.label("換職業會重新開始測試場（背包清空）", UiKit.FONT_NOTE, Color(1, 1, 1, 0.7)))
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
	for r: StringName in WeaponDropDefs.RARITY_ORDER:
		var b := UiKit.button(ItemDefs.RARITIES[r].name, UiKit.BUTTON_S)
		b.toggle_mode = true
		_rarity_color(b, r)
		b.pressed.connect(_pick_rarity.bind(r))
		_rarity_buttons[r] = b
		rarities.add_child(b)
	rarities.add_child(_action("放進背包", _request_weapon))
	box.add_child(rarities)
	var affix_box := _flow()
	box.add_child(affix_box)
	for id: StringName in WeaponDropDefs.AFFIXES:
		var b := UiKit.button(WeaponDropDefs.AFFIXES[id].desc, {"size": AFFIX_SIZE, "font": 16})
		b.toggle_mode = true
		b.clip_text = true
		b.tooltip_text = WeaponDropDefs.AFFIXES[id].desc
		b.toggled.connect(func(_on: bool) -> void: _refresh_affix_note())
		_affix_buttons[id] = b
		affix_box.add_child(b)
	_scroll_page(&"weapon", box)
	_pick_base(_ids_of(&"weapon")[0])
	_pick_rarity(&"white")


func _pick_base(id: StringName) -> void:
	weapon_base = id
	for k: StringName in _weapon_buttons:
		_weapon_buttons[k].set_pressed_no_signal(k == id)


# 換稀有度：這個稀有度不能出的詞條藏起來、取消勾選
func _pick_rarity(r: StringName) -> void:
	weapon_rarity = r
	for k: StringName in _rarity_buttons:
		_rarity_buttons[k].set_pressed_no_signal(k == r)
	for id: StringName in _affix_buttons:
		var ok := WeaponDropDefs.allowed(id, r) and WeaponDropDefs.affix_count(r) > 0
		_affix_buttons[id].visible = ok
		if not ok:
			_affix_buttons[id].set_pressed_no_signal(false)
	_refresh_affix_note()


func chosen_affixes() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _affix_buttons:
		if _affix_buttons[id].button_pressed:
			out.append(id)
	return out


func _refresh_affix_note() -> void:
	var err := Practice.affix_error(weapon_rarity, chosen_affixes())
	set_note(err if err != "" else "詞條 %d / %d" % [chosen_affixes().size(), WeaponDropDefs.affix_count(weapon_rarity)])


func _request_weapon() -> void:
	var affixes := chosen_affixes()
	var err := Practice.affix_error(weapon_rarity, affixes)
	if err != "":
		set_note(err)
		return
	weapon_requested.emit(weapon_base, weapon_rarity, affixes)


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
		b.pressed.connect(func() -> void: enemy_requested.emit(id))
		f.add_child(b)
	var box := VBoxContainer.new()
	box.add_child(f)
	box.add_child(UiKit.label("點一下在面前生一隻（紅字是 Boss）", UiKit.FONT_NOTE, Color(1, 1, 1, 0.7)))
	_scroll_page(&"enemy", box)
