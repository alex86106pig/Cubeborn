# 武器測試場的測試面板（左上，平常收起只剩分頁與工具列；開背包時 HUD 把它藏起來）：分頁選職業與背包模式、做武器（稀有度）、道具、技能（可選等級）、袋子 / 開格、
# 怪物（照層分組、稀有度、一次幾隻、照第幾層第幾小關的成長、木樁的擺法）；工具列有怪物停手、作弊開關、清空背包與傷害統計；
# 按鈕只發訊號，main.gd 交給 Practice 改模擬狀態。怪物停手 / 攻擊也可以按 T
class_name TestPanel
extends PanelContainer

signal class_chosen(id: StringName)                       # ClassDefs.NONE = 無職業（基準數值）
signal weapon_requested(base: StringName, rarity: StringName)
signal bag_requested(kind: StringName, tier: StringName)   # 袋子分開的模式
signal unlock_requested(action: StringName)                # 背包合併：random / pick / all
signal bag_mode_toggled                                    # 換背包模式（重新開始測試場）
signal item_requested(id: StringName, level: int)         # 道具與技能都走這個；level 0 = 照遺物的規則（有了就升 1 級），技能可以指定等級
signal enemy_requested(type: StringName, rarity: StringName, count: int)
signal stage_chosen(floor_num: int, stage: int)           # 生怪照第幾層第幾小關的成長，場地換成那一層的外觀
signal dummies_requested(kind: StringName)                # 木樁重擺成這種（Spawner.TRAINING_KINDS）；「重置木樁」送目前選的那種
signal cheat_toggled(id: StringName, on: bool)            # Practice.CHEATS
signal inventory_cleared
signal meter_reset
signal hold_toggled
signal clear_enemies

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
var enemy_count := 1
var enemy_floor := 1
var enemy_stage := 1
var skill_level := 0       # 技能分頁選的等級；0 = 點一次升 1 級
var dummy_kind := Spawner.TRAINING_DEFAULT
var meter := UiKit.label("", UiKit.FONT_NOTE)
var mode_button := UiKit.button("換成背包合併", UiKit.BUTTON_M)
var mode_label := UiKit.label("背包：袋子分開", UiKit.FONT_NOTE, UiKit.GOLD)
var _body := VBoxContainer.new()
var _weapon_buttons := {}
var _rarity_buttons := {}
var _enemy_rarity_buttons := {}
var _count_buttons := {}
var _floor_buttons := {}
var _stage_buttons := {}
var _level_buttons := {}
var _dummy_buttons := {}
var _cheat_buttons := {}
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
	tools.add_child(_action("重置木樁", func() -> void: dummies_requested.emit(dummy_kind), UiKit.BUTTON_S))
	tools.add_child(UiKit.label("Esc 回主選單", UiKit.FONT_NOTE, Color(1, 1, 1, 0.8)))
	root.add_child(tools)
	var cheats := HBoxContainer.new()
	cheats.add_theme_constant_override(&"separation", 8)
	for id: StringName in Practice.CHEATS:
		var b := UiKit.button(Practice.CHEATS[id], UiKit.BUTTON_S)
		b.toggle_mode = true
		b.toggled.connect(func(on: bool) -> void: cheat_toggled.emit(id, on))
		_cheat_buttons[id] = b
		cheats.add_child(b)
	cheats.add_child(_action("清空背包", inventory_cleared.emit, UiKit.BUTTON_S))
	cheats.add_child(_action("統計歸零", meter_reset.emit, UiKit.BUTTON_S))   # 這一排 5 顆 BUTTON_S 剛好塞進 WIDTH，再加要換排
	root.add_child(cheats)
	meter.clip_text = true   # 傷害統計的數字會變長：超出就截掉，不把面板撐寬
	root.add_child(meter)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(note)
	_build_class_page()
	_build_weapon_page()
	_build_group_page(&"item", Practice.item_groups(), func(id: StringName) -> void: item_requested.emit(id, 0))
	_build_group_page(&"skill", Practice.skill_groups(), func(id: StringName) -> void: item_requested.emit(id, skill_level), _level_row())
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


func set_meter(text: String) -> void:
	if meter.text != text:
		meter.text = text


# 進測試場時回到預設：作弊全關、第 1 層第 1 小關、一次 1 隻、一般木樁、技能點一次升 1 級（不發訊號，main.gd 那邊也同時歸零）
func reset_choices() -> void:
	for id: StringName in _cheat_buttons:
		_cheat_buttons[id].set_pressed_no_signal(false)
	enemy_floor = 1
	enemy_stage = 1
	_mark(_floor_buttons, 1)
	_mark(_stage_buttons, 1)
	_pick_count(1)
	_pick_level(0)
	dummy_kind = Spawner.TRAINING_DEFAULT
	_mark(_dummy_buttons, dummy_kind)
	_pick_enemy_rarity(MonsterRarityDefs.NORMAL)


# 一排單選按鈕（前面一個小標題）：ids 與各自顯示的字，按了呼叫 pick(id)。回傳 id → Button，選中的那顆用 _mark 標
func _choices(parent: Control, title: String, ids: Array, names: Array, pick: Callable) -> Dictionary:
	var f := _flow()
	var buttons := {}
	f.add_child(UiKit.label(title, UiKit.FONT_NOTE, Color(1, 1, 1, 0.7)))
	for i in ids.size():
		var b := UiKit.button(names[i], UiKit.BUTTON_S)
		b.toggle_mode = true
		b.pressed.connect(pick.bind(ids[i]))
		buttons[ids[i]] = b
		f.add_child(b)
	parent.add_child(f)
	return buttons


static func _mark(buttons: Dictionary, id: Variant) -> void:
	for k: Variant in buttons:
		buttons[k].set_pressed_no_signal(k == id)


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


# 道具 / 技能分頁：groups = [[標題, [id…]]…]（Practice.item_groups / skill_groups），每組一個小標題、一顆一個；head 放最上面（技能的等級選擇）
func _build_group_page(t: StringName, groups: Array, fn: Callable, head: Control = null) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	if head != null:
		box.add_child(head)
	for g: Array in groups:
		if (g[1] as Array).is_empty():
			continue
		box.add_child(UiKit.label("%s（%d）" % [g[0], (g[1] as Array).size()], UiKit.FONT_NOTE, UiKit.GOLD))
		var f := _flow()
		for id: StringName in g[1]:
			var b := UiKit.button(ItemDefs.ITEMS[id].name, UiKit.BUTTON_S)
			_rarity_color(b, ItemDefs.ITEMS[id].rarity)
			b.tooltip_text = ItemDefs.ITEMS[id].get("desc", "")
			b.pressed.connect(fn.bind(id))
			f.add_child(b)
		box.add_child(f)
	_scroll_page(t, box)


# 技能分頁最上面的等級選擇：0 = 點一次升 1 級（同遺物）；1 ~ 最高級 = 點了直接變那一級
func _level_row() -> Control:
	var box := VBoxContainer.new()
	var levels: Array = range(0, SkillDefs.LEVEL.max + 1)
	_level_buttons = _choices(box, "等級", levels, levels.map(func(lv: int) -> String: return "＋1" if lv == 0 else "%d 級" % lv), _pick_level)
	_pick_level(0)
	return box


func _pick_level(lv: int) -> void:
	skill_level = lv
	_mark(_level_buttons, lv)


# 怪物分頁：照第幾層第幾小關的成長、稀有度、一次幾隻，下面照層分組列怪（紅字是 Boss），最後是木樁的擺法
func _build_enemy_page() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	var floors: Array = range(1, MapDefs.PRACTICE_MAPS.size() + 1)
	_floor_buttons = _choices(box, "成長", floors, floors.map(func(f: int) -> String: return "第 %d 層" % f),
		func(f: int) -> void: _pick_stage(f, enemy_stage))
	var stages: Array = MapGenDefs.STAGES.keys()
	_stage_buttons = _choices(box, "小關", stages, stages.map(func(s: int) -> String: return "%d" % s),
		func(s: int) -> void: _pick_stage(enemy_floor, s))
	var rarities: Array = MonsterRarityDefs.RARITIES.keys()
	_enemy_rarity_buttons = _choices(box, "稀有度", rarities, rarities.map(func(r: StringName) -> String: return MonsterRarityDefs.RARITIES[r].name), _pick_enemy_rarity)
	var counts: Array = Practice.SPAWN_COUNTS
	_count_buttons = _choices(box, "一次", counts, counts.map(func(n: int) -> String: return "%d 隻" % n), _pick_count)
	for g: Array in Practice.enemy_groups():
		if (g[1] as Array).is_empty():
			continue
		box.add_child(UiKit.label(g[0], UiKit.FONT_NOTE, UiKit.GOLD))
		var f := _flow()
		for id: StringName in g[1]:
			var b := UiKit.button(EnemyDefs.def_of(id).get("name", String(id)), UiKit.BUTTON_S)
			if EnemyDefs.is_boss(id):
				b.add_theme_color_override(&"font_color", UiKit.BOSS_NAME_ENRAGED)
			b.pressed.connect(func() -> void: enemy_requested.emit(id, enemy_rarity, enemy_count))
			f.add_child(b)
		box.add_child(f)
	box.add_child(UiKit.label("生在面前；紅字是 Boss（不套稀有度、一次 1 隻）。成長只影響之後生的怪", UiKit.FONT_NOTE, Color(1, 1, 1, 0.7)))
	var kinds: Array = Spawner.TRAINING_KINDS.keys()
	_dummy_buttons = _choices(box, "木樁", kinds, kinds.map(func(k: StringName) -> String: return Spawner.TRAINING_KINDS[k]), _pick_dummies)
	box.add_child(UiKit.label("護甲 = 物理傷害減半；會動 = 來回走；一群 = 方陣（範圍、穿透）", UiKit.FONT_NOTE, Color(1, 1, 1, 0.7)))
	_scroll_page(&"enemy", box)
	reset_choices()


func _pick_enemy_rarity(r: StringName) -> void:
	enemy_rarity = r
	_mark(_enemy_rarity_buttons, r)


func _pick_count(n: int) -> void:
	enemy_count = n
	_mark(_count_buttons, n)


func _pick_stage(floor_num: int, stage: int) -> void:
	enemy_floor = floor_num
	enemy_stage = stage
	_mark(_floor_buttons, floor_num)
	_mark(_stage_buttons, stage)
	stage_chosen.emit(floor_num, stage)


func _pick_dummies(kind: StringName) -> void:
	dummy_kind = kind
	_mark(_dummy_buttons, kind)
	dummies_requested.emit(kind)


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
