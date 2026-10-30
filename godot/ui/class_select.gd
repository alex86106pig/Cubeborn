# 選角畫面（參考雨中冒險 2，2026-10-27 使用者選方案 A）：左職業格、中 3D 角色（可拖動旋轉）、右資訊（數值條、技能），下方難度 / 名單 / 開始
# 多人時名單在左欄職業格下方（底下那排塞不下，2026-10-27 截圖確認超出 1920）
# 單人：主選單「單人遊戲」打開，點職業只是選，按「開始」才開局；多人：進大廳後顯示（main.gd 依連線狀態呼叫 show_lobby）
# 角色結構和遊戲共用：模型 DarkFantasy.player_character + Animator 擺待機姿勢，數值讀 Player.apply_class 後的屬性，技能格用技能欄的 SkillBar.Slot
# 只發訊號，流程由 main.gd 處理
class_name ClassSelect
extends ColorRect

signal start_pressed(class_id: StringName, difficulty: StringName)   # 單人「開始」
signal back_pressed                                 # 單人「返回」
signal class_chosen(class_id: StringName)           # 大廳：選職業
signal difficulty_chosen(mode: StringName)          # 大廳：房主選難度
signal ready_toggled(ready: bool)                   # 大廳：客戶端「準備好了」/「取消準備」
signal net_start_pressed                            # 大廳：房主「開始遊戲」
signal leave_pressed                                # 大廳：「離開」

const TILE_SIZE := Vector2(160, 100)
# 舞台與資訊欄固定大小（2026-10-27 使用者：畫面不要隨字數變化）；資訊欄放不下的會被切掉，檢查「主選單」擋
const STAGE_SIZE := Vector2(800, 860)
const INFO_SIZE := Vector2(640, 860)
const INFO_PAD := 24.0
const BG := Color(6 / 255.0, 8 / 255.0, 14 / 255.0, 0.97)
const STAGE_BG := Color("151a28")
const PANEL_BG := Color(0.09, 0.11, 0.16, 0.95)
const PICKED := Color("ffd84a")     # 自己選的那格的框、自己頭上的字
# 數值條：屬性、短名稱、顯示範圍（固定，加職業不會讓其他人的條子變；2026-10-27 對比頁提案）
const CHART := [
	[&"max_hp", "生命", 60.0, 140.0],
	[&"phys_damage", "物攻", 0.7, 1.3],
	[&"elem_damage", "屬攻", 0.7, 1.3],
	[&"armor", "護甲", 0.0, 30.0],
	[&"resist_all", "抗性", 0.0, 0.25],
	[&"attack_speed", "攻速", 0.7, 1.3],
	[&"move_speed", "移速", 5.5, 7.5],
	[&"treasure", "運氣", 0.0, 0.5],
]
const EXTRA: Array[StringName] = [&"hp_regen", &"dodge", &"crit_damage"]   # 不上圖，和基準不同時列在圖下方
const ROLL_DESC := "朝移動方向翻滾，翻滾中不會受傷。"
# 多人時其他人站的位置（自己在原點、比較大）
const OTHER_SPOTS: Array[Vector3] = [Vector3(-1.7, 0, -1.2), Vector3(1.8, 0, -1.2), Vector3(3.1, 0, -2.6)]
const OTHER_SCALE := 0.8
const DRAG_TURN := 0.01   # 拖動旋轉：每像素轉幾弧度
const FACE_TURN := -0.35  # 預設側一點朝鏡頭
const HINT_MARGIN := Vector2(40, 16)   # 「拖動旋轉」提示離舞台右下角多遠

var mode: StringName = &"single"   # &"single" | &"lobby_host" | &"lobby_client"
var selected: StringName = ClassDefs.ORDER[0]
var difficulty: StringName = EventDefs.DEFAULT_MODE
var class_buttons: Dictionary = {}       # 職業 id（含佔位）→ 按鈕
var difficulty_buttons: Dictionary = {}  # 難度 → 按鈕
var title := UiKit.label("選擇角色", UiKit.FONT_TITLE, Color.WHITE, 3)
var room_label := UiKit.label("", UiKit.FONT_BODY, Color(1, 1, 1, 0.85), 2)
var copy_button := UiKit.button("複製房號", UiKit.BUTTON_S)   # 大廳右上角：把房號放進剪貼簿
var info_box := VBoxContainer.new()   # 資訊欄的內容（固定大小的框裡，檢查用它量放不放得下）
var _copy_text := ""
var copied := ""   # 最後一次「複製房號」放進剪貼簿的文字（沒有剪貼簿的環境也記，檢查用）
var back_button := UiKit.button("返回", UiKit.BUTTON_M)
var start_button := UiKit.button("開始", UiKit.BUTTON_L)
var ready_button := UiKit.button("準備好了", UiKit.BUTTON_L)
var name_label := UiKit.label("", 44, Color.WHITE, 3)
var pitch_label := UiKit.label("", UiKit.FONT_NOTE, Color(1, 1, 1, 0.8), 1)
var weapon_label := UiKit.label("", UiKit.FONT_NOTE, Color(1, 1, 1, 0.8), 1)
var extra_label := UiKit.label("", UiKit.FONT_NOTE, Color(1, 1, 1, 0.65), 1)
var chart := StatChart.new()
var roster := VBoxContainer.new()   # 大廳名單：左欄職業格下方
var tags: Array[Label] = []          # 角色頭上的「P1 守墓騎士」
var drag_hint := UiKit.label("↔ 拖動旋轉", UiKit.FONT_NOTE, Color(1, 1, 1, 0.45), 1)
var _skills := VBoxContainer.new()
var _diff_note := UiKit.label("房主選", UiKit.FONT_NOTE, Color(1, 1, 1, 0.6), 1)
var _ready := false
var _lineup: Array = []              # 舞台上要站的人：[職業, 標籤文字]，第一個是自己
var _sim_world: World = null         # 預覽用的 Player 要有 World（換武器拿 uid）；只建一次，不碰遊戲的 World
var _previews: Dictionary = {}       # 職業 → Player（套好職業的預覽角色，數值條也讀它）
var _baseline: Player = null         # 沒選職業的基準
var _viewport := SubViewport.new()
var _camera := Camera3D.new()
var _stage_root := Node3D.new()
var _rigs: Array[Rig] = []
var _animators: Array[Animator] = []
var _turn := FACE_TURN
var _stage := SubViewportContainer.new()
var _tag_layer := Control.new()


func _init() -> void:
	color = BG
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var page := VBoxContainer.new()
	page.add_theme_constant_override(&"separation", 16)
	center.add_child(page)

	var head := HBoxContainer.new()
	head.add_child(title)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	room_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(room_label)
	copy_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy_button.custom_minimum_size.x = 140
	copy_button.pressed.connect(_copy_room)
	head.add_child(copy_button)
	page.add_child(head)

	var main := HBoxContainer.new()
	main.add_theme_constant_override(&"separation", 24)
	var left := VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 24)
	left.add_child(_build_tiles())
	roster.add_theme_constant_override(&"separation", 10)
	left.add_child(roster)
	main.add_child(left)
	main.add_child(_build_stage())
	main.add_child(_build_info())
	page.add_child(main)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override(&"separation", 20)
	bottom.custom_minimum_size = Vector2(0, UiKit.BUTTON_L.size.y)
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(back_button)
	var diff_label := UiKit.label("難度", UiKit.FONT_BODY, Color.WHITE, 2)
	diff_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(diff_label)
	for m: StringName in EventDefs.MODE_ORDER:
		var b := UiKit.button("%s（上升 ×%s）" % [EventDefs.MODES[m].name, String.num(EventDefs.MODES[m].rate)], UiKit.BUTTON_M)
		b.custom_minimum_size.x = 230
		b.toggle_mode = true
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(_on_difficulty.bind(m))
		difficulty_buttons[m] = b
		bottom.add_child(b)
	_diff_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(_diff_note)
	var fill_bottom := Control.new()
	fill_bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(fill_bottom)
	for b: Button in [ready_button, start_button]:
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bottom.add_child(b)
	page.add_child(bottom)

	back_button.pressed.connect(func() -> void:
		if mode == &"single":
			back_pressed.emit()
		else:
			leave_pressed.emit())
	start_button.pressed.connect(func() -> void:
		if mode == &"single":
			start_pressed.emit(selected, difficulty)
		else:
			net_start_pressed.emit())
	ready_button.pressed.connect(func() -> void: ready_toggled.emit(not _ready))


# 預覽角色和 World 有循環參照（狀態機 ↔ 角色），離開時切斷，免得結束時洩漏
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for p: Player in _previews.values():
			p.detach()
		_previews.clear()
		_baseline = null
		if _sim_world != null:
			_sim_world.clear()


# 主選單「單人遊戲」：選上次選的職業與難度
func open_single() -> void:
	mode = &"single"
	_lineup = []
	visible = true
	_refresh()


# 大廳（main.gd 每次名單變動都呼叫）：choices = NetSession.lobby_choices（peer id → [職業, 準備好了]）
# copy_text：「複製房號」放進剪貼簿的文字（區網連線沒有房號就是空的，按鈕不顯示）
func show_lobby(p_mode: StringName, peers: Array, local_peer: int, choices: Dictionary, p_difficulty: StringName, room_text: String, copy_text: String = "") -> void:
	mode = p_mode
	difficulty = p_difficulty
	room_label.text = room_text
	_copy_text = copy_text
	var mine: Array = choices.get(local_peer, NetSession.default_choice(local_peer == World.HOST_PEER_ID))
	selected = StringName(mine[0]) if ClassDefs.is_pickable(StringName(mine[0])) else ClassDefs.ORDER[0]
	_ready = mine[1]
	_lineup = []
	for c in roster.get_children():
		c.free()
	var all_ready := true
	for i in peers.size():
		var id: int = peers[i]
		var choice: Array = choices.get(id, NetSession.default_choice(id == World.HOST_PEER_ID))
		var cls := StringName(choice[0]) if ClassDefs.is_pickable(StringName(choice[0])) else ClassDefs.ORDER[0]
		var ready: bool = id == World.HOST_PEER_ID or choice[1]
		all_ready = all_ready and ready
		var who := "P%d" % (i + 1)
		var tag := "%s %s" % [who, ClassDefs.CLASSES[cls].name] if id == local_peer else "%s %s" % [who, "✓" if ready else "…"]
		if id == local_peer:
			_lineup.push_front([cls, tag])
		else:
			_lineup.append([cls, tag])
		var line := "%s %s%s\n%s" % [who, "房主" if id == World.HOST_PEER_ID else "玩家", "（你）" if id == local_peer else "", ClassDefs.CLASSES[cls].name]
		var chip := UiKit.label(line + ("　準備好了" if ready else "　還沒準備"), UiKit.FONT_NOTE, PICKED if id == local_peer else Color.WHITE, 1)
		roster.add_child(chip)
	start_button.disabled = not all_ready
	start_button.text = "開始遊戲" if all_ready else "等待全員準備"
	ready_button.text = "取消準備" if _ready else "準備好了"
	visible = true
	_refresh()


func close() -> void:
	visible = false


# 選了哪個職業的預覽角色（數值條、檢查用）
func preview_player(id: StringName) -> Player:
	if not _previews.has(id):
		if _sim_world == null:
			_sim_world = World.new(&"test_arena")
		var p := Player.new(_sim_world, 0)
		p.apply_class(id)
		_previews[id] = p
	return _previews[id]


func baseline_player() -> Player:
	if _baseline == null:
		_baseline = preview_player(ClassDefs.NONE)
	return _baseline


func _on_tile(id: StringName) -> void:
	if not ClassDefs.is_pickable(id):
		_shake(class_buttons[id])
		_refresh()
		return
	if mode == &"single":
		selected = id
		_refresh()
	else:
		class_chosen.emit(id)   # 等房主廣播回來才更新（show_lobby）


func _on_difficulty(m: StringName) -> void:
	if mode == &"single":
		difficulty = m
		_refresh()
	elif mode == &"lobby_host":
		difficulty_chosen.emit(m)
	else:
		_refresh()   # 客戶端不能改：把按下去的狀態還原


func _refresh() -> void:
	var single := mode == &"single"
	title.text = "選擇角色" if single else "連線大廳 · 選擇角色"
	room_label.visible = not single
	copy_button.visible = not single and _copy_text != ""
	back_button.text = "返回" if single else "離開"
	start_button.visible = mode != &"lobby_client"
	if single:
		start_button.disabled = false
		start_button.text = "開始"
	ready_button.visible = mode == &"lobby_client"
	roster.visible = not single
	_diff_note.visible = not single
	for m: StringName in difficulty_buttons:
		var b: Button = difficulty_buttons[m]
		b.set_pressed_no_signal(m == difficulty)
		b.disabled = mode == &"lobby_client" and m != difficulty
	for id: StringName in class_buttons:
		(class_buttons[id] as Button).set_pressed_no_signal(id == selected)
	var c: Dictionary = ClassDefs.CLASSES[selected]
	name_label.text = c.name
	pitch_label.text = c.pitch
	weapon_label.text = "起始武器：" + ClassDefs.start_weapon_def(selected).name
	var p := preview_player(selected)
	var base := baseline_player()
	chart.values.clear()
	for row: Array in CHART:
		chart.values.append([row[1], p.stats.base(row[0]), base.stats.base(row[0]), row[2], row[3], StatDefs.format_value(row[0], p.stats.base(row[0]))])
	chart.queue_redraw()
	var extra: Array[String] = []
	for stat: StringName in EXTRA:
		if not is_equal_approx(p.stats.base(stat), base.stats.base(stat)):
			extra.append("%s %s" % [StatDefs.STATS[stat].name, StatDefs.format_value(stat, p.stats.base(stat))])
	extra_label.text = "　·　".join(extra)
	extra_label.visible = not extra.is_empty()
	_fill_skills(c)
	if _lineup.is_empty():
		_lineup = [[selected, ""]]
	elif single:
		_lineup[0][0] = selected
	_build_lineup()


# 被動 / 左鍵 / 右鍵 / 翻滾：圖示和技能欄同一種格子（SkillBar.Slot）
func _fill_skills(c: Dictionary) -> void:
	for n in _skills.get_children():
		n.free()
	var w: Dictionary = ClassDefs.start_weapon_def(ClassDefs.CLASSES.find_key(c))
	_skills.add_child(_skill_row(SkillBar.Slot.new("passive", "被動", -1), "職業被動", c.passive.desc))
	_skills.add_child(_skill_row(SkillBar.Slot.new(w.attack.icon, "左鍵", -1), w.attack.name, w.attack.get("desc", "")))
	_skills.add_child(_skill_row(SkillBar.Slot.new(w.special.icon, "右鍵", -1), w.special.name, w.special.get("desc", "")))
	if w.has("slot_skill"):   # 武器帶的技能欄技能（火把傭兵的插火把）
		var s: Dictionary = SkillDefs.SKILLS[w.slot_skill]
		_skills.add_child(_skill_row(SkillBar.Slot.new(s.icon, "數字鍵", -1), s.name, s.desc))
	_skills.add_child(_skill_row(SkillBar.Slot.new(SkillBar.ROLL_ICON, "Shift", -1), "翻滾", ROLL_DESC))


static func _skill_row(slot: Control, skill_name: String, desc: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(slot)
	var text := VBoxContainer.new()
	text.add_theme_constant_override(&"separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UiKit.label(skill_name, 24, Color.WHITE, 2))
	if desc != "":
		var d := UiKit.label(desc, UiKit.FONT_NOTE, Color(1, 1, 1, 0.75), 1)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = INFO_SIZE.x - 120
		text.add_child(d)
	row.add_child(text)
	return row


func _build_tiles() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var tile := {"size": TILE_SIZE, "font": 24}
	for id: StringName in ClassDefs.ORDER:
		var b := UiKit.button(ClassDefs.CLASSES[id].name, tile)
		b.toggle_mode = true
		b.pressed.connect(_on_tile.bind(id))
		class_buttons[id] = b
		grid.add_child(b)
	for id: StringName in ClassDefs.PLACEHOLDERS:
		var b := UiKit.button("？\n" + ClassDefs.PLACEHOLDERS[id].unlock, tile)
		b.modulate.a = 0.5
		b.pressed.connect(_on_tile.bind(id))
		class_buttons[id] = b
		grid.add_child(b)
	for id: StringName in ClassDefs.ORDER:
		if ClassDefs.CLASSES[id].get("locked", false):
			(class_buttons[id] as Button).text = "%s\n%s" % [ClassDefs.CLASSES[id].name, ClassDefs.CLASSES[id].get("unlock", "")]
			(class_buttons[id] as Button).modulate.a = 0.5
	return grid


func _build_stage() -> Control:
	_stage.custom_minimum_size = STAGE_SIZE
	_stage.stretch = true
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.gui_input.connect(_on_stage_input)
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_stage.add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = STAGE_BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Config.ENVIRONMENT.hemi_sky.lerp(Config.ENVIRONMENT.hemi_ground, 0.35)
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Config.ENVIRONMENT.sun_color
	sun.light_energy = 1.2
	_viewport.add_child(sun)
	sun.look_at_from_position(Vector3(-4.0, 8.0, 6.0), Vector3.ZERO)
	_viewport.add_child(_camera)
	_viewport.add_child(_stage_root)
	_tag_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_layer.add_child(drag_hint)
	# 往左上長：字級第一幀才套上，往右長會超出舞台
	drag_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	drag_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	drag_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	drag_hint.offset_right = -HINT_MARGIN.x
	drag_hint.offset_bottom = -HINT_MARGIN.y
	drag_hint.offset_left = -HINT_MARGIN.x
	drag_hint.offset_top = -HINT_MARGIN.y
	var wrap := Control.new()   # 標籤疊在 3D 舞台上（SubViewportContainer 只能放 SubViewport）
	wrap.custom_minimum_size = STAGE_SIZE
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(_stage)
	wrap.add_child(_tag_layer)
	return wrap


func _build_info() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = INFO_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_corner_radius_all(10)
	style.set_content_margin_all(INFO_PAD)
	panel.add_theme_stylebox_override(&"panel", style)
	# 內容放在固定大小、會裁切的框裡：字多字少面板都一樣大（PanelContainer 會跟著內容長大）
	var clip := Control.new()
	clip.custom_minimum_size = INFO_SIZE - Vector2.ONE * INFO_PAD * 2.0
	clip.clip_contents = true
	panel.add_child(clip)
	var box := info_box
	box.add_theme_constant_override(&"separation", 10)
	clip.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var w := INFO_SIZE.x - INFO_PAD * 2.0
	box.add_child(name_label)
	for l: Label in [pitch_label, weapon_label]:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = w
		box.add_child(l)
	chart.custom_minimum_size = Vector2(w, CHART.size() * StatChart.ROW_HEIGHT)
	box.add_child(chart)
	extra_label.custom_minimum_size.x = w
	extra_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(extra_label)
	_skills.add_theme_constant_override(&"separation", 8)   # 火把傭兵多一格插火把（5 格）也塞得進資訊欄
	box.add_child(_skills)
	return panel


# 大廳「複製房號」：放進剪貼簿（網頁版要 https 或 localhost），按鈕短暫顯示「已複製」
func _copy_room() -> void:
	copied = _copy_text
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(_copy_text)
	copy_button.text = "已複製"
	get_tree().create_timer(1.5).timeout.connect(_reset_copy_text)   # 方法連線：畫面先被釋放時會自動斷開


func _reset_copy_text() -> void:
	copy_button.text = "複製房號"


# 舞台上的角色：自己在中間、比較大，其他人往後站、縮小
# 只重建職業換了的那一格：整排重建會讓其他人的待機動畫一起從頭播
func _build_lineup() -> void:
	while _rigs.size() > _lineup.size():
		_rigs.pop_back().queue_free()
		_animators.pop_back()
	for i in _lineup.size():
		var want: StringName = _lineup[i][0]
		if i < _rigs.size() and _rigs[i].get_meta(&"class") == want:
			continue
		var rig := DarkFantasy.player_character(want)
		rig.set_meta(&"class", want)
		var anim := Animator.new(rig)
		anim.update(preview_player(want), 0.0)
		_stage_root.add_child(rig)
		if i > 0:
			rig.position = OTHER_SPOTS[(i - 1) % OTHER_SPOTS.size()]
			rig.scale = Vector3.ONE * OTHER_SCALE
			rig.rotation.y = FACE_TURN
		if i < _rigs.size():
			_rigs[i].queue_free()
			_rigs[i] = rig
			_animators[i] = anim
		else:
			_rigs.append(rig)
			_animators.append(anim)
	while tags.size() < _lineup.size():
		var l := UiKit.label("", UiKit.FONT_BODY, Color.WHITE, 2)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tag_layer.add_child(l)
		tags.append(l)
	for i in tags.size():
		tags[i].visible = i < _lineup.size() and _lineup[i][1] != ""
		if i < _lineup.size():
			tags[i].text = _lineup[i][1]
			tags[i].add_theme_color_override(&"font_color", PICKED if i == 0 else Color.WHITE)
	# 多人時鏡頭拉遠一點，四個人才站得下
	var multi := _lineup.size() > 1
	var x := 0.55 if multi else 0.0   # 第三個人站右後方，鏡頭往右偏一點
	_camera.fov = 50.0 if multi else 34.0
	_camera.look_at_from_position(Vector3(x, 1.6, 6.4), Vector3(x, 1.0, 0.0))


func _process(dt: float) -> void:
	if not visible:
		return
	for i in _rigs.size():
		_animators[i].update(preview_player(_rigs[i].get_meta(&"class")), dt)
	if not _rigs.is_empty():
		_rigs[0].rotation.y = _turn
	for i in mini(tags.size(), _rigs.size()):
		var head := _rigs[i].global_position + Vector3.UP * (_rigs[i].height * _rigs[i].scale.y + 0.35)
		tags[i].reset_size()
		tags[i].position = _camera.unproject_position(head) - Vector2(tags[i].size.x / 2.0, tags[i].size.y)


func _on_stage_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		_turn += (event as InputEventMouseMotion).relative.x * DRAG_TURN


# 點到鎖住的格子：左右抖一下
func _shake(b: Control) -> void:
	var x := b.position.x
	var t := create_tween()
	for dx: float in [8.0, -8.0, 5.0, 0.0]:
		t.tween_property(b, ^"position:x", x + dx, 0.05)


# 數值條：灰 = 到基準為止、綠 = 高於基準的部分、紅 = 低於基準少掉的部分，白線 = 基準；右邊是實際數字（和屬性面板同格式）
class StatChart extends Control:
	const ROW_HEIGHT := 36.0
	const LABEL_W := 70.0
	const VALUE_W := 220.0
	const BAR_H := 14.0
	const BASE_COLOR := Color(1, 1, 1, 0.35)
	const UP := Color("6cd27a")
	const DOWN := Color("e0605a")
	const TRACK := Color(1, 1, 1, 0.08)
	var values: Array = []   # [名稱, 值, 基準, 下限, 上限, 顯示文字]

	func _draw() -> void:
		var font := get_theme_default_font()
		var bar_w := size.x - LABEL_W - VALUE_W - 16.0
		for i in values.size():
			var v: Array = values[i]
			var y := i * ROW_HEIGHT
			var mid := y + ROW_HEIGHT / 2.0
			draw_string(font, Vector2(0, mid + 8), v[0], HORIZONTAL_ALIGNMENT_LEFT, LABEL_W, 22, Color.WHITE)
			var x0 := LABEL_W
			var k := clampf((v[1] - v[3]) / (v[4] - v[3]), 0.0, 1.0)
			var kb := clampf((v[2] - v[3]) / (v[4] - v[3]), 0.0, 1.0)
			var top := mid - BAR_H / 2.0
			draw_rect(Rect2(x0, top, bar_w, BAR_H), TRACK)
			draw_rect(Rect2(x0, top, bar_w * minf(k, kb), BAR_H), BASE_COLOR)
			if k > kb:
				draw_rect(Rect2(x0 + bar_w * kb, top, bar_w * (k - kb), BAR_H), UP)
			elif k < kb:
				draw_rect(Rect2(x0 + bar_w * k, top, bar_w * (kb - k), BAR_H), Color(DOWN, 0.45))
			draw_line(Vector2(x0 + bar_w * kb, top - 4), Vector2(x0 + bar_w * kb, top + BAR_H + 4), Color.WHITE, 2.0)
			var col := UP if v[1] > v[2] + 1e-6 else (DOWN if v[1] < v[2] - 1e-6 else Color.WHITE)
			draw_string(font, Vector2(x0 + bar_w + 16.0, mid + 8), v[5], HORIZONTAL_ALIGNMENT_LEFT, VALUE_W, 20, col)
