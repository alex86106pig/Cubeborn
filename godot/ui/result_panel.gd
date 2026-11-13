# 結算畫面（失敗 / 通關）：先看墓碑頁——中間的墓碑刻著結果與被誰打倒、左邊隊友的小墓碑、右邊自己傷害最高的幾招與打自己最痛的幾種怪；
# 點墓碑、隊友的小墓碑或「詳細統計」進分頁：左邊點誰看誰，右邊切傷害來源 / 受到傷害 / 每一關 / 遊玩紀錄。
# 資料是結算事件帶來的 RunStats.to_wire（每位玩家一份），不讀模擬狀態；按鈕只發訊號，HUD / main.gd 處理
class_name ResultPanel
extends Control

signal retry_requested    # 同一關重來（開發用）
signal copy_requested     # 複製遊玩紀錄
signal title_requested    # 回主選單

const PLAYER_COLORS: Array[Color] = [Color("6fb7ff"), Color("ffb35c"), Color("8fe08f"), Color("d79bff")]
const TAKEN_COLOR := Color("ff6b6b")
const STONE := Color("4b4a50")           # 墓碑
const STONE_GOLD := Color("6a5a2a")      # 通關時的墓碑
const STONE_TEXT := Color("e9e4d8")
const STONE_SIZE := Vector2(520, 600)
const STONE_ROUND := 240                 # 墓碑上緣的圓角
const MINI_SIZE := Vector2(72, 88)       # 隊友的小墓碑
const SIDE_WIDTH := 460.0                # 墓碑頁左右兩欄
const TOP_DEALT := 4                     # 墓碑頁右邊列幾招
const TOP_TAKEN := 3
const DETAIL_ROWS := 12                  # 分頁裡一頁最多幾列，其餘併成「其他」
const LIST_WIDTH := 360.0                # 詳細統計左邊的隊員名單
const NAME_WIDTH := 300.0
const BAR_WIDTH := 420.0
const TABS: Array[StringName] = [&"dealt", &"taken", &"stages", &"log"]
const TAB_NAMES := {&"dealt": "傷害來源", &"taken": "受到傷害", &"stages": "每一關", &"log": "遊玩紀錄"}
const DIM := Color(1, 1, 1, 0.7)

var title := UiKit.label("", 56, UiKit.ALERT, 3)
var subtitle := UiKit.label("", UiKit.FONT_NOTE)
var log_label := UiKit.label("", 18, Color(1, 1, 1, 0.85))   # 遊玩紀錄的文字（只有自己的，RunLog.summary_text）
var copy_button := UiKit.button("複製遊玩紀錄", UiKit.BUTTON_M)
var copy_note := UiKit.label("", 16, UiKit.GOLD)
var retry_button := UiKit.button("同一關重來（Y）", UiKit.BUTTON_M)
var retry_note := UiKit.label("", UiKit.FONT_NOTE, Color(1, 1, 1, 0.85))
var restart_hint := UiKit.label("按 R 重新開始", UiKit.FONT_NOTE)
var detail_button := UiKit.button("詳細統計", UiKit.BUTTON_M)
var title_button := UiKit.button("回主選單", UiKit.BUTTON_M)
var tomb_page := HBoxContainer.new()
var detail_page := HBoxContainer.new()
var stone := PanelContainer.new()
var run := {}              # 這次結算的資料（RunStats.to_wire）
var me_peer := 0
var shown_peer := 0        # 詳細統計正在看誰
var shown_tab := &"dealt"
var _victory := false
var _place := ""
var _stone_box := VBoxContainer.new()
var _mates := VBoxContainer.new()
var _mine := VBoxContainer.new()
var _list := VBoxContainer.new()
var _tab_buttons := {}
var _content := VBoxContainer.new()
var _log_box := VBoxContainer.new()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	root.add_theme_constant_override(&"separation", 8)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	for l: Label in [title, subtitle, retry_note, restart_hint, copy_note]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	root.add_child(subtitle)
	var pages := MarginContainer.new()   # 兩頁疊在同一塊（一次只顯示一頁）；用容器才會把頁面需要的大小往上報
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pages)
	_build_tomb_page()
	_build_detail_page()
	for page: Control in [tomb_page, detail_page]:
		page.alignment = BoxContainer.ALIGNMENT_CENTER
		page.add_theme_constant_override(&"separation", 40)
		pages.add_child(page)
	root.add_child(retry_note)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 16)
	retry_button.pressed.connect(retry_requested.emit)
	detail_button.pressed.connect(func() -> void: show_detail(not detail_page.visible))
	title_button.pressed.connect(title_requested.emit)
	copy_button.pressed.connect(copy_requested.emit)
	for b: Button in [retry_button, detail_button, title_button]:
		buttons.add_child(b)
	root.add_child(buttons)
	root.add_child(restart_hint)
	show_detail(false)


# 墓碑頁：左 隊友、中 墓碑（整塊可以點）、右 自己的摘要
func _build_tomb_page() -> void:
	_mates.custom_minimum_size.x = SIDE_WIDTH
	_mates.alignment = BoxContainer.ALIGNMENT_CENTER
	_mates.add_theme_constant_override(&"separation", 14)
	tomb_page.add_child(_mates)
	stone.custom_minimum_size = STONE_SIZE
	stone.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stone.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	stone.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			show_detail(true, me_peer))
	_stone_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_stone_box.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 裡面的字、格線、分隔線都不攔：點墓碑哪裡都算
	_stone_box.add_theme_constant_override(&"separation", 6)
	stone.add_child(_stone_box)
	tomb_page.add_child(stone)
	_mine.custom_minimum_size.x = SIDE_WIDTH
	_mine.alignment = BoxContainer.ALIGNMENT_CENTER
	_mine.add_theme_constant_override(&"separation", 6)
	tomb_page.add_child(_mine)


# 詳細統計：左 隊員名單（點誰看誰）、右 分頁與內容；遊玩紀錄那一頁是固定的一塊（文字 + 複製按鈕）
func _build_detail_page() -> void:
	_list.custom_minimum_size.x = LIST_WIDTH
	_list.add_theme_constant_override(&"separation", 8)
	detail_page.add_child(_list)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = NAME_WIDTH + BAR_WIDTH + 420.0
	right.add_theme_constant_override(&"separation", 10)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 8)
	for t: StringName in TABS:
		var b := UiKit.button(TAB_NAMES[t], UiKit.BUTTON_M)
		b.toggle_mode = true
		b.pressed.connect(show_tab.bind(t))
		_tab_buttons[t] = b
		tabs.add_child(b)
	right.add_child(tabs)
	_content.add_theme_constant_override(&"separation", 6)
	right.add_child(_content)
	_log_box.add_theme_constant_override(&"separation", 8)
	_log_box.add_child(log_label)
	_log_box.add_child(copy_button)
	_log_box.add_child(copy_note)
	right.add_child(_log_box)
	detail_page.add_child(right)


# 顯示一次結算。p_run：RunStats.to_wire；place：「2-3」「第 4 波」這種倒下 / 通過的地方；log_text：自己的遊玩紀錄
func show_result(p_title: String, p_subtitle: String, victory: bool, p_run: Dictionary, p_me: int, place: String, can_retry: bool, log_text: String) -> void:
	run = p_run
	me_peer = p_me
	_victory = victory
	_place = place
	title.text = p_title
	title.add_theme_color_override(&"font_color", UiKit.GOLD if victory else UiKit.ALERT)
	var tries: int = run.get("tries", 0)
	subtitle.text = p_subtitle + ("　重來 %d 次" % tries if tries > 0 else "")
	log_label.text = log_text
	copy_note.text = ""
	# 同一關重來（開發用）：只有失敗、而且是單機或房主才有按鈕；客戶端看提示
	retry_button.visible = not victory and can_retry
	retry_note.visible = not victory
	retry_note.text = "開發用：背包與武器回到進這一關時，生命魔力補滿" if can_retry else "等房主決定：同一關重來，或重新開始"
	restart_hint.visible = can_retry
	_fill_tomb()
	_fill_list()
	show_detail(false)


func show_detail(on: bool, peer: int = 0) -> void:
	tomb_page.visible = not on
	detail_page.visible = on
	detail_button.text = "返回" if on else "詳細統計"
	if on:
		shown_peer = peer if peer != 0 else (shown_peer if _stats(shown_peer) != null else me_peer)
		_fill_list()
		show_tab(shown_tab)


func show_tab(t: StringName) -> void:
	shown_tab = t
	for k: StringName in _tab_buttons:
		_tab_buttons[k].set_pressed_no_signal(k == t)
	_log_box.visible = t == &"log"
	_content.visible = t != &"log"
	_clear(_content)
	var s: Variant = _stats(shown_peer)
	if s == null or t == &"log":
		return
	match t:
		&"dealt":
			_fill_dealt(s)
		&"taken":
			_fill_taken(s)
		&"stages":
			_fill_stages(s)


# ───────── 資料 ─────────

func peers() -> Array:
	var out: Array = run.get("info", {}).keys()
	out.sort_custom(func(a: int, b: int) -> bool: return run.info[a].order < run.info[b].order)
	return out


# 這位玩家的統計；沒有這個人回傳 null
func _stats(peer: int) -> Variant:
	return run.get("players", {}).get(peer)


func _color(peer: int) -> Color:
	return PLAYER_COLORS[int(run.info[peer].order) % PLAYER_COLORS.size()]


func _class_name_of(peer: int) -> String:
	var id := StringName(run.info[peer].get("class", ""))
	return ClassDefs.CLASSES[id].name if ClassDefs.CLASSES.has(id) else "無職業"


# 「你」或「P2」
func tag_of(peer: int) -> String:
	return "你" if peer == me_peer else "P%d" % (int(run.info[peer].order) + 1)


static func num(v: float) -> String:
	var digits := UiKit.dmg_text(v)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


# 字典（key → 陣列，第 0 欄是傷害）照傷害高到低排的 key
static func _sorted_keys(table: Dictionary) -> Array:
	var keys := table.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return table[a][0] > table[b][0] or (table[a][0] == table[b][0] and str(a) < str(b)))
	return keys


static func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


# ───────── 墓碑頁 ─────────

func _fill_tomb() -> void:
	_clear(_stone_box)
	_clear(_mates)
	_clear(_mine)
	var style := StyleBoxFlat.new()
	style.bg_color = STONE_GOLD if _victory else STONE
	style.border_color = Color(0, 0, 0, 0.6)
	style.set_border_width_all(4)
	style.corner_radius_top_left = STONE_ROUND
	style.corner_radius_top_right = STONE_ROUND
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 48
	style.content_margin_right = 48
	style.content_margin_top = 56
	style.content_margin_bottom = 24
	stone.add_theme_stylebox_override(&"panel", style)
	var mine: Variant = _stats(me_peer)
	if mine == null:
		_stone_line(_place, UiKit.FONT_HEADING)
		return
	_stone_line("凱 旋" if _victory else "長 眠 於 此", UiKit.FONT_NOTE, DIM)
	_stone_line(_class_name_of(me_peer), 48)
	_stone_line(("通過 %s" if _victory else "倒在 %s") % _place, UiKit.FONT_BODY)
	var downs: Array = mine.downs
	if not _victory and not downs.is_empty():
		_stone_line("被 %s 打倒" % RunLog.name_of(StringName(downs[-1])), UiKit.FONT_NOTE, DIM)
	_stone_box.add_child(_rule())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 24)
	grid.add_theme_constant_override(&"v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for pair: Array in [["時間", UiKit.format_time(run.get("time", 0.0))], ["擊殺", num(mine.kills)], ["造成傷害", num(mine.damage)],
			["受到傷害", num(mine.taken)], ["倒下", "%d 次" % downs.size()], ["金幣", "+%d" % run.get("coins", 0)]]:
		grid.add_child(UiKit.label(pair[0], UiKit.FONT_NOTE, DIM))
		var v := UiKit.label(pair[1], 24, STONE_TEXT)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.custom_minimum_size.x = 150
		grid.add_child(v)
	_stone_box.add_child(grid)
	_stone_box.add_child(_rule())
	_stone_line("點墓碑看詳細統計", 16, DIM)
	# 左：隊友（單人時沒有）
	for peer: int in peers():
		if peer != me_peer:
			_mates.add_child(_mate_row(peer))
	if _mates.get_child_count() > 0:
		_mates.add_child(UiKit.label("同行的人", UiKit.FONT_NOTE, UiKit.GOLD))
		_mates.move_child(_mates.get_child(_mates.get_child_count() - 1), 0)
	# 右：自己傷害最高的幾招、打自己最痛的幾種
	_mine.add_child(UiKit.label("你造成的傷害", UiKit.FONT_NOTE, UiKit.GOLD))
	_top_rows(_mine, mine.dealt, TOP_DEALT, _color(me_peer), RunLog.credit_name, SIDE_WIDTH)
	_mine.add_child(UiKit.label("你受到的傷害", UiKit.FONT_NOTE, UiKit.GOLD))
	_top_rows(_mine, mine.by_source, TOP_TAKEN, TAKEN_COLOR, func(k: String) -> String: return RunLog.name_of(StringName(k)), SIDE_WIDTH)


static func _rule() -> HSeparator:
	var r := HSeparator.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _stone_line(text: String, size: int, color: Color = STONE_TEXT) -> void:
	var l := UiKit.label(text, size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stone_box.add_child(l)


# 隊友的一列：小墓碑 + 兩行字；整列可以點（進詳細統計看他）
func _mate_row(peer: int) -> Control:
	var s: Dictionary = _stats(peer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			show_detail(true, peer))
	var mini := PanelContainer.new()
	mini.custom_minimum_size = MINI_SIZE
	mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = STONE
	style.border_color = Color(0, 0, 0, 0.6)
	style.set_border_width_all(2)
	style.corner_radius_top_left = int(MINI_SIZE.x / 2)
	style.corner_radius_top_right = int(MINI_SIZE.x / 2)
	mini.add_theme_stylebox_override(&"panel", style)
	var tag := UiKit.label(tag_of(peer), 24, _color(peer))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mini.add_child(tag)
	row.add_child(mini)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(UiKit.label("%s · %s" % [tag_of(peer), _class_name_of(peer)], 24, _color(peer)))
	var downs: int = (s.downs as Array).size()
	text.add_child(UiKit.label("傷害 %s · 擊殺 %s · %s" % [num(s.damage), num(s.kills), "倒下 %d 次" % downs if downs > 0 else "沒倒過"], 18, DIM))
	row.add_child(text)
	return row


# 前 limit 名各一列：名稱、長條、數字
func _top_rows(box: Control, table: Dictionary, limit: int, color: Color, name_fn: Callable, width: float) -> void:
	var keys := _sorted_keys(table)
	if keys.is_empty():
		box.add_child(UiKit.label("沒有", 18, DIM))
		return
	var top: float = table[keys[0]][0]
	for i in mini(limit, keys.size()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		row.add_child(_cell(name_fn.call(keys[i]), width * 0.42, 18))
		row.add_child(_bar(table[keys[i]][0] / top, color, width * 0.34))
		row.add_child(_cell(num(table[keys[i]][0]), width * 0.2, 18, true))
		box.add_child(row)


# ───────── 詳細統計 ─────────

func _fill_list() -> void:
	_clear(_list)
	for peer: int in peers():
		var s: Variant = _stats(peer)
		if s == null:
			continue
		var b := UiKit.button("%s · %s　%s" % [tag_of(peer), _class_name_of(peer), num(s.damage)], UiKit.BUTTON_M)
		b.custom_minimum_size.x = LIST_WIDTH
		b.toggle_mode = true
		b.set_pressed_no_signal(peer == shown_peer)
		b.add_theme_color_override(&"font_color", _color(peer))
		b.add_theme_color_override(&"font_pressed_color", _color(peer))
		b.pressed.connect(func() -> void: show_detail(true, peer))
		_list.add_child(b)


func _head(text: String) -> void:
	_content.add_child(UiKit.label(text, 24, _color(shown_peer)))


# 一列：名稱、長條、幾個靠右的數字欄
func _row(name: String, frac: float, color: Color, cells: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	row.add_child(_cell(name, NAME_WIDTH, UiKit.FONT_NOTE))
	row.add_child(_bar(frac, color, BAR_WIDTH))
	for c: Array in cells:
		row.add_child(_cell(c[0], c[1], UiKit.FONT_NOTE, true, c[2] if c.size() > 2 else Color.WHITE))
	_content.add_child(row)


static func _cell(text: String, width: float, size: int, right := false, color := Color.WHITE) -> Label:
	var l := UiKit.label(text, size, color)
	l.custom_minimum_size.x = width
	l.clip_text = true
	if right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


static func _bar(frac: float, color: Color, width: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = clampf(frac, 0.0, 1.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override(&"background", bg)
	bar.add_theme_stylebox_override(&"fill", fill)
	return bar


# 傷害來源：每一招的傷害、佔比、打中幾下、最高一擊；超過 DETAIL_ROWS 的併成「其他」
func _fill_dealt(s: Dictionary) -> void:
	_head("%s · %s　造成 %s　最高一擊 %s" % [tag_of(shown_peer), _class_name_of(shown_peer), num(s.damage), num(s.peak)])
	var keys := _sorted_keys(s.dealt)
	if keys.is_empty():
		_content.add_child(UiKit.label("這一局沒有打出傷害", UiKit.FONT_NOTE, DIM))
		return
	_row("", 0.0, Color.TRANSPARENT, [["傷害", 110.0, DIM], ["佔比", 80.0, DIM], ["次數", 80.0, DIM], ["最高", 90.0, DIM]])
	var top: float = s.dealt[keys[0]][RunStats.D_DAMAGE]
	var rest := [0.0, 0, 0.0]
	for i in keys.size():
		var r: Array = s.dealt[keys[i]]
		if i < DETAIL_ROWS - 1 or keys.size() == DETAIL_ROWS:
			_dealt_row(RunLog.credit_name(keys[i]), r, top, s.damage)
		else:
			rest = [rest[0] + r[RunStats.D_DAMAGE], rest[1] + r[RunStats.D_HITS], maxf(rest[2], r[RunStats.D_PEAK])]
	if rest[0] > 0.0:
		_dealt_row("其他", rest, top, s.damage)


func _dealt_row(name: String, r: Array, top: float, total: float) -> void:
	_row(name, r[RunStats.D_DAMAGE] / top, _color(shown_peer), [[num(r[RunStats.D_DAMAGE]), 110.0], ["%d%%" % roundi(100.0 * r[RunStats.D_DAMAGE] / total), 80.0, DIM],
		["%d 下" % r[RunStats.D_HITS], 80.0, DIM], [num(r[RunStats.D_PEAK]), 90.0, DIM]])


# 受到傷害：依攻擊者；下面是倒下被誰打倒、回復的生命、救人次數
func _fill_taken(s: Dictionary) -> void:
	_head("%s · %s　受到 %s" % [tag_of(shown_peer), _class_name_of(shown_peer), num(s.taken)])
	var keys := _sorted_keys(s.by_source)
	if not keys.is_empty():
		_row("", 0.0, Color.TRANSPARENT, [["傷害", 110.0, DIM], ["佔比", 80.0, DIM], ["次數", 80.0, DIM]])
		var top: float = s.by_source[keys[0]][0]
		var rest := [0.0, 0]
		for i in keys.size():
			var r: Array = s.by_source[keys[i]]
			if i < DETAIL_ROWS - 3 or keys.size() == DETAIL_ROWS - 2:
				_row(RunLog.name_of(StringName(keys[i])), r[0] / top, TAKEN_COLOR, [[num(r[0]), 110.0], ["%d%%" % roundi(100.0 * r[0] / s.taken), 80.0, DIM], ["%d 下" % r[1], 80.0, DIM]])
			else:
				rest = [rest[0] + r[0], rest[1] + r[1]]
		if rest[0] > 0.0:
			_row("其他", rest[0] / top, TAKEN_COLOR, [[num(rest[0]), 110.0], ["%d%%" % roundi(100.0 * rest[0] / s.taken), 80.0, DIM], ["%d 下" % rest[1], 80.0, DIM]])
	var downs: Array = s.downs
	var who := {}
	for k: String in downs:
		who[k] = who.get(k, 0) + 1
	var parts: Array[String] = []
	for k: String in who:
		parts.append(RunLog.name_of(StringName(k)) + (" ×%d" % who[k] if who[k] > 1 else ""))
	_content.add_child(UiKit.label("倒下 %d 次" % downs.size() + ("：被 %s 打倒" % "、".join(PackedStringArray(parts)) if not parts.is_empty() else ""), UiKit.FONT_NOTE))
	_content.add_child(UiKit.label("回復生命 %s　救起隊友 %d 次" % [num(s.healed), s.revives], UiKit.FONT_NOTE, DIM))


# 每一關：這位玩家在那一關造成的傷害，旁邊寫全隊的
func _fill_stages(s: Dictionary) -> void:
	_head("%s · %s　每一關造成的傷害" % [tag_of(shown_peer), _class_name_of(shown_peer)])
	var team := {}
	for peer: int in peers():
		var other: Variant = _stats(peer)
		if other != null:
			for k: int in other.stages:
				team[k] = team.get(k, 0.0) + other.stages[k]
	var keys := team.keys()
	keys.sort()
	if keys.is_empty():
		_content.add_child(UiKit.label("這一局沒有打出傷害", UiKit.FONT_NOTE, DIM))
		return
	var top := 0.0
	for k: int in keys:
		top = maxf(top, s.stages.get(k, 0.0))
	_row("", 0.0, Color.TRANSPARENT, [["傷害", 110.0, DIM], ["全隊", 130.0, DIM], ["佔全隊", 100.0, DIM]])
	for k: int in keys.slice(maxi(keys.size() - DETAIL_ROWS, 0)):
		var mine: float = s.stages.get(k, 0.0)
		@warning_ignore("integer_division")
		_row(World.level_name(k / 100, k % 100), mine / top if top > 0.0 else 0.0, _color(shown_peer),
			[[num(mine), 110.0], [num(team[k]), 130.0, DIM], ["%d%%" % roundi(100.0 * mine / team[k]), 100.0, DIM]])
