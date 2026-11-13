# 動畫檢視器（除錯用）：選角色、選動作，播放 / 暫停 / 逐格 / 慢動作、拖時間軸、轉視角，修動畫時用。
# 開法：Godot 編輯器開 debug/anim_viewer.tscn 按 F6（執行中改 view/ 的動畫程式存檔就會套用，重錄才會重跑模擬）；
# 網頁版 ?anim-viewer（main.gd 不開遊戲，只開這個）。動作用 AnimRecorder 錄（跟動作表 PoseGallery 同一套）。
# 特效也照錄到的放：持續性的（噴火、蓄力粒子）照每一步的動作冒，事件型的（揮砍弧光、爆炸、命中火花）照錄到的事件放；慢動作時特效也跟著慢
# 一打開就選好：AnimViewer.new("enemy-gravekeeper:lantern")（網址 ?anim-viewer=enemy-gravekeeper:lantern；動作寫英文 id；
# 第三段是腳步：enemy-gravekeeper:lantern:原地 / 走 / 跑）
# 操作：空白鍵 播放 / 暫停、← → 逐格、↑ ↓ 換動作、R 重錄、滑鼠拖曳轉視角、滾輪縮放
# 視角換動作、換角色、重錄都留著，只有按視角按鈕才換
# 接著演：拆成好幾段的招式（AnimRecorder.SPLITS）一段演完接下一段，清單反白跟著走；關掉只循環選的那一段
# 循環時角色從停下的地方接著演（地板不重置），走跑類不重建角色、步伐不斷
class_name AnimViewer
extends Node3D

const DT := Config.FIXED_DT
const SPEEDS := [0.1, 0.25, 0.5, 1.0]
# 腳步：照錄到的（跟遊戲一樣）/ 原地 / 走 / 跑；走、跑的速度照腿長換算（Froude 數 0.3 = 走、4 = 跑，同 BodyPose 的走跑分界）
const FEET := {"照錄到的": -1.0, "原地": 0.0, "走": 0.3, "跑": 4.0}
const GRID_HALF := 15            # 地板格線的範圍（± 公尺），1 公尺一格
const FLOOR_SNAP := 5.0          # 地板跟著角色移動的單位（= 亮線的間隔，看起來是同一片地板）
const PANEL_WIDTH := 360
const ORBIT_SPEED := 0.008       # 拖曳轉視角：每像素幾弧度
const DIST_RANGE := Vector2(2.5, 30.0)
# 視角：[相對角色朝向的方位角（0 = 正前方）, 仰角, 正交]；遊戲 = Config.CAMERA 的世界方位
const VIEWS := {"側面": [-PI / 2.0, 0.12, false], "正面": [0.0, 0.12, false], "背面": [PI, 0.12, false], "遊戲": [0.0, 0.0, true]}

var _recorder := AnimRecorder.new()
var _subjects: Array[Dictionary] = AnimRecorder.subjects()
var _rows: Array = []
var _row: Dictionary = {}
var _made: Dictionary = {}       # { rig, anim }：正在播的角色
var _frame := 0                  # 已經餵給動畫器到第幾步
var _lo := 0                     # 播放範圍 [_lo, _hi)
var _hi := 1
var _chain := true               # 接著演
var _shift := Vector2.ZERO       # 循環、換動作累積的位移
var _shown := Vector2.ZERO       # 角色現在畫在哪（地面座標）
var _raw := Vector2.ZERO         # 角色錄到的位置（上一步）
var _step_move := Vector2.ZERO   # 上一步走了多少
var _carry := 0.0
var _playing := true
var _speed := 1.0
var _loop := true
var _follow := true              # 角色照錄到的位置移動；關掉就原地
var _feet := "照錄到的"
var _yaw_rel := -PI / 2.0        # 相對動作開頭的角色朝向
var _yaw_game: float = Config.CAMERA.azimuth
var _pitch := 0.12
var _dist := 7.0
var _ortho := false
var _game_view := false
var _dragging := false
var _view := "側面"
var _speed_buttons := {}         # 值 → 按鈕（同組只亮一個）
var _feet_buttons := {}
var _view_buttons := {}

var _cam := Camera3D.new()
var _floor := Node3D.new()
var _fx := Effects.new()
var _fx_world := World.new(&"test_arena")   # 只放正在播的那隻（Effects 照 world.entities 冒持續性的特效）
var _subject_pick := OptionButton.new()
var _action_list := ItemList.new()
var _slider := HSlider.new()
var _info: Label
var _play_button: Button
var _panel := PanelContainer.new()
var _syncing_slider := false
var _initial := ""
var back_to_game := false        # 從遊戲主選單進來的：多一顆「回主選單」（編輯器 F6 開的沒有遊戲可以回）


func _init(pick := "") -> void:
	_initial = pick


func _ready() -> void:
	_build_stage()
	_build_ui()
	var feet := _initial.get_slice(":", 2) if _initial.count(":") >= 2 else ""
	if FEET.has(feet):
		_feet = feet
		_mark_buttons()
	select(_initial.get_slice(":", 0), _initial.get_slice(":", 1) if _initial.contains(":") else "")
	print("anim viewer ready subjects=%d" % _subjects.size())


func _exit_tree() -> void:
	_free_rig()
	_fx_world.entities = {}   # 角色是錄的 World 的，不在這裡拆
	_fx_world.clear()
	_recorder.clear()


# ───────── 場景 ─────────

func _build_stage() -> void:
	add_child(_cam)
	add_child(_fx)
	add_child(_floor)
	_cam.current = true
	_cam.fov = 40.0
	_cam.far = 200.0
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.95, 0.6, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.13, 0.14, 0.17)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	# 地板：深色地面 + 1 公尺一條的格線（每 5 公尺一條比較亮）
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * GRID_HALF * 2.0
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.24, 0.26, 0.24)
	floor_mesh.material_override = fm
	_floor.add_child(floor_mesh)
	var line := BoxMesh.new()
	line.size = Vector3(GRID_HALF * 2.0, 0.004, 0.02)
	for i in range(-GRID_HALF, GRID_HALF + 1):
		var bright := i % 5 == 0
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.55, 0.58, 0.5) if bright else Color(0.36, 0.38, 0.34)
		for along_x: bool in [true, false]:
			var l := MeshInstance3D.new()
			l.mesh = line
			l.material_override = m
			l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			l.position = Vector3(0.0, 0.003, i) if along_x else Vector3(i, 0.003, 0.0)
			l.rotation.y = 0.0 if along_x else PI / 2.0
			_floor.add_child(l)


# ───────── 介面 ─────────

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.9)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override(&"panel", style)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.anchor_bottom = 1.0
	_panel.offset_right = PANEL_WIDTH
	layer.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	_panel.add_child(box)
	box.add_child(UiKit.label("動畫檢視器", UiKit.FONT_BODY))
	box.add_child(UiKit.label("角色", UiKit.FONT_NOTE))
	for s in _subjects:
		_subject_pick.add_item(s.name)
	_subject_pick.add_theme_font_size_override(&"font_size", UiKit.FONT_NOTE)
	_subject_pick.item_selected.connect(_pick_subject)
	box.add_child(_subject_pick)
	box.add_child(UiKit.label("動作", UiKit.FONT_NOTE))
	_action_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_action_list.add_theme_font_size_override(&"font_size", UiKit.FONT_NOTE)
	_action_list.item_selected.connect(_pick_action)
	box.add_child(_action_list)
	_info = UiKit.label("", UiKit.FONT_NOTE)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(PANEL_WIDTH - 24, 96)
	box.add_child(_info)
	_slider.step = 1.0
	_slider.value_changed.connect(_on_slider)
	box.add_child(_slider)
	var transport := HBoxContainer.new()
	box.add_child(transport)
	var back := UiKit.button("◀", UiKit.BUTTON_S)
	back.custom_minimum_size.x = 60
	back.pressed.connect(func() -> void: _step_by(-1))
	transport.add_child(back)
	_play_button = UiKit.button("暫停", UiKit.BUTTON_S)
	_play_button.pressed.connect(_toggle_play)
	transport.add_child(_play_button)
	var fwd := UiKit.button("▶", UiKit.BUTTON_S)
	fwd.custom_minimum_size.x = 60
	fwd.pressed.connect(func() -> void: _step_by(1))
	transport.add_child(fwd)
	var speeds := HBoxContainer.new()
	box.add_child(speeds)
	for sp: float in SPEEDS:
		var b := _toggle(UiKit.button("%s×" % ("%.2f" % sp).trim_suffix("0").trim_suffix(".") if sp < 1.0 else "1×", UiKit.BUTTON_S), _speed_buttons, sp)
		b.custom_minimum_size.x = 76
		b.pressed.connect(func() -> void: _speed = sp; _refresh_info())
		speeds.add_child(b)
	var toggles := HBoxContainer.new()
	box.add_child(toggles)
	var loop := CheckBox.new()
	loop.text = "循環"
	loop.button_pressed = _loop
	loop.focus_mode = Control.FOCUS_NONE   # 不然空白鍵會切勾選
	loop.toggled.connect(func(on: bool) -> void: _loop = on)
	toggles.add_child(loop)
	var follow := CheckBox.new()
	follow.text = "跟著走"
	follow.tooltip_text = "關掉 = 角色留在原地"
	follow.button_pressed = _follow
	follow.focus_mode = Control.FOCUS_NONE
	follow.toggled.connect(func(on: bool) -> void: _follow = on; _place_rig())
	toggles.add_child(follow)
	var chain := CheckBox.new()
	chain.text = "接著演"
	chain.tooltip_text = "拆成好幾段的招式一段演完接下一段；關掉只循環選的那一段"
	chain.button_pressed = _chain
	chain.focus_mode = Control.FOCUS_NONE
	chain.toggled.connect(set_chain)
	toggles.add_child(chain)
	var feet := HBoxContainer.new()
	box.add_child(feet)
	feet.add_child(UiKit.label("腳步", UiKit.FONT_NOTE))
	for name: String in FEET:
		var b := _toggle(UiKit.button(name, UiKit.BUTTON_S), _feet_buttons, name)
		b.custom_minimum_size.x = 64 if name.length() <= 2 else 96
		b.pressed.connect(func() -> void: _feet = name; _seek(_frame))
		feet.add_child(b)
	var views := HBoxContainer.new()
	box.add_child(views)
	for v: String in VIEWS:
		var b := _toggle(UiKit.button(v, UiKit.BUTTON_S), _view_buttons, v)
		b.custom_minimum_size.x = 76
		b.pressed.connect(func() -> void: _set_view(v))
		views.add_child(b)
	var rerec := UiKit.button("重錄（R）", UiKit.BUTTON_M)
	rerec.pressed.connect(_rerecord)
	box.add_child(rerec)
	if back_to_game:
		var to_menu := UiKit.button("回主選單", UiKit.BUTTON_M)
		to_menu.pressed.connect(func() -> void: LaunchArgs.relaunch(get_tree(), false))
		box.add_child(to_menu)
	box.add_child(UiKit.label("空白鍵 播放 / 暫停　← → 逐格　↑ ↓ 換動作\n滑鼠拖曳轉視角　滾輪縮放", UiKit.FONT_NOTE, Color(1, 1, 1, 0.6)))
	_subject_pick.focus_mode = Control.FOCUS_NONE
	_slider.focus_mode = Control.FOCUS_NONE
	_mark_buttons()


# 同組只亮一個的按鈕
func _toggle(b: Button, group: Dictionary, key: Variant) -> Button:
	b.toggle_mode = true
	if not group.is_empty():
		b.button_group = (group.values()[0] as Button).button_group
	else:
		b.button_group = ButtonGroup.new()
	group[key] = b
	return b


func _mark_buttons() -> void:
	for pair in [[_speed_buttons, _speed], [_feet_buttons, _feet], [_view_buttons, _view]]:
		var b: Button = (pair[0] as Dictionary).get(pair[1])
		if b != null:
			b.set_pressed_no_signal(true)


# ───────── 選角色、選動作 ─────────

# 選角色（id 同 AnimRecorder.subjects）與動作（英文 key）；找不到的那一項不變
func select(subject_id: String, action := "") -> void:
	var at := maxi(_subject_pick.selected, 0)
	for i in _subjects.size():
		if _subjects[i].id == subject_id:
			at = i
	_pick_subject(at)
	for i in _rows.size():
		if action != "" and _rows[i].key == action:
			_action_list.select(i)
			_pick_action(i)


func set_chain(on: bool) -> void:
	_chain = on
	if not _made.is_empty():
		_seek(_frame)


# 往前演 n 步
func advance(n: int) -> void:
	for i in n:
		_advance()


# 現在演到哪：{ key（哪一段）, frame, range, pos（角色畫在哪）, floor, view（[相對方位, 仰角, 距離]）, rig }
func status() -> Dictionary:
	return {"key": _segment(_frame)[0] if not _row.is_empty() else "", "frame": _frame, "range": Vector2i(_lo, _hi), "pos": _shown,
		"floor": Vector2(_floor.position.x, _floor.position.z), "view": [_yaw_rel, _pitch, _dist], "rig": _made.get("rig")}


# 新角色也有同一個動作就停在那個動作
func _pick_subject(i: int) -> void:
	var keep: String = _segment(_frame)[0] if not _row.is_empty() else ""
	_free_rig()
	_recorder.clear()
	_rows = _recorder.rows(_subjects[i].id)
	_action_list.clear()
	for r: Dictionary in _rows:
		var depth: int = r.get("depth", 0)
		var name: String = r.name if r.name == r.key else "%s  %s" % [r.name, r.key]
		_action_list.add_item("　".repeat(depth) + ("└ " if depth > 0 else "") + name)
	if _subject_pick.selected != i:
		_subject_pick.select(i)
	if not _rows.is_empty():
		var at := 0
		for k in _rows.size():
			if _rows[k].key == keep:
				at = k
		_action_list.select(at)
		_action_list.ensure_current_is_visible()
		_pick_action(at)


func _pick_action(i: int) -> void:
	var at := _shown
	_row = _rows[i]
	_seek(_row.get("start", 0))
	_shift += at - _shown   # 從角色原本站的地方接著演
	_place_rig()
	_update_camera()


func _rerecord() -> void:
	_pick_subject(maxi(_subject_pick.selected, 0))


# 這一列同一次錄的全部段落 [[key, 起, 迄（不含）], ...]；沒拆的動作只有一段
func _path() -> Array:
	return _row.get("path", [[_row.key, _row.get("start", 0), (_row.frames as Array).size()]])


# 第 i 步在哪一段
func _segment(i: int) -> Array:
	var path := _path()
	for seg: Array in path:
		if i < seg[2]:
			return seg
	return path[-1]


# 第 i 步的播放範圍：接著演 = 整條，否則只有那一段
func _range(i: int) -> Vector2i:
	var path := _path()
	var seg := _segment(i)
	return Vector2i(path[0][1], path[-1][2]) if _chain else Vector2i(seg[1], seg[2])


# 跳到第 target 步：重建角色、從第 0 步重播（動畫器有平滑，倒退只能重播）
func _seek(target: int) -> void:
	_free_rig()
	_fx.clear()
	_fx_world.entities = {(_row.subject as Entity).id: _row.subject}
	_made = (_row.make as Callable).call()
	add_child(_made.rig)
	if _row.subject is Player:   # 揮砍的劍尖拖尾（遊戲裡由 WorldView 掛）
		(_made.rig as Node).add_child(BladeTrail.new())
	var r := _range(target)
	_lo = r.x
	_hi = r.y
	_frame = clampi(target, _lo, _hi - 1)
	AnimRecorder.replay(_row, _made, _frame, _foot_speed(), _lo)
	_raw = (_row.subject as Entity).pos
	_step_move = Vector2.ZERO
	_carry = 0.0
	_place_rig()
	_sync()


# 腳步選項換成速度（-1 = 照錄到的）
func _foot_speed() -> float:
	var fr: float = FEET[_feet]
	if fr < 0.0 or fr == 0.0 or _made.is_empty():
		return fr
	return sqrt(fr * BodyPose.G * BodyPose.leg_length(_made.rig))


func _free_rig() -> void:
	if not _made.is_empty() and is_instance_valid(_made.rig):
		(_made.rig as Node).queue_free()
	_made = {}


# ───────── 播放 ─────────

func _process(delta: float) -> void:
	if _made.is_empty():
		return
	if _playing:
		_carry += delta * _speed
		while _carry >= DT:
			_carry -= DT
			_advance()
	_fx.sync(_fx_world, delta * _speed if _playing else 0.0)
	_update_camera()


func _advance() -> void:
	if _frame + 1 < _hi:
		_step_to(_frame + 1)
	elif _loop:
		_wrap()
	else:
		_playing = false
		_refresh_info()


func _step_to(i: int) -> void:
	_frame = i
	AnimRecorder.step(_row, _made, _frame, _foot_speed(), _lo)
	var now: Vector2 = (_row.subject as Entity).pos
	_step_move = now - _raw
	_raw = now
	for ev: Dictionary in _row.frames[_frame].get("events", []):
		_fx.on_event(ev.name, ev)
	_place_rig()
	var trail := (_made.rig as Node).get_node_or_null(^"BladeTrail") as BladeTrail
	if trail != null:
		trail.update(_made.rig, _row.subject, DT)
	_sync()


# 循環：回到範圍開頭，角色從現在的位置接著演；走跑類（row.cycle）不重建角色
func _wrap() -> void:
	var before := _raw
	var move := _step_move
	if _row.get("cycle", false):
		_step_to(_lo)
	else:
		_seek(_lo)
	_shift += before + move - _raw
	_step_move = move
	_place_rig()


func _step_by(n: int) -> void:
	_playing = false
	if n > 0:
		advance(n)
	else:
		_seek(maxi(_frame + n, _lo))
	_refresh_info()


func _toggle_play() -> void:
	_playing = not _playing
	_refresh_info()


func _on_slider(v: float) -> void:
	if _syncing_slider or _row.is_empty():
		return
	_playing = false
	_seek(int(v))


# 時間軸、清單反白（跟著現在演到的那一段）、說明
func _sync() -> void:
	_syncing_slider = true
	_slider.min_value = _lo
	_slider.max_value = maxi(_hi - 1, _lo + 1)
	_slider.value = _frame
	_syncing_slider = false
	var key: String = _segment(_frame)[0]
	for k in _rows.size():
		if _rows[k].key == key and not _action_list.is_selected(k):
			_action_list.select(k)
			_action_list.ensure_current_is_visible()
	_refresh_info()


# 角色照錄到的位置走（加上循環累積的位移）或留在原點；特效、地板跟著
func _place_rig() -> void:
	if _made.is_empty():
		return
	var f: Dictionary = _row.frames[_frame]
	var origin: Vector2 = _row.frames[_path()[0][1]].pos
	var rig: Node3D = _made.rig
	var now: Vector2 = (_row.subject as Entity).pos
	_shown = now - origin + _shift if _follow else Vector2.ZERO
	rig.position = Vector3(_shown.x, f.height, _shown.y)
	rig.rotation.y = f.facing
	_fx.position = Vector3(_shown.x - now.x, 0.0, _shown.y - now.y)   # 特效是世界座標，整組跟角色一樣平移
	_floor.position = Vector3(snappedf(_shown.x, FLOOR_SNAP), 0.0, snappedf(_shown.y, FLOOR_SNAP))


func _refresh_info() -> void:
	if _row.is_empty():
		return
	var a: Dictionary = _row.frames[_frame].anim
	var t := (_frame - _lo) * DT
	var total := (_hi - 1 - _lo) * DT
	var what := ""
	if a.has("loco"):   # 玩家
		what = "移動 %s　動作 %s %s" % [a.loco, a.action, a.get("phase", "")]
		if a.get("skill", &"") != &"":
			what += "\n戰技 %s %.2f 秒" % [a.skill, a.skill_time]
	else:
		what = "狀態 %s %s" % [a.get("state", ""), a.get("phase", "")]
	var path := _path()
	if path.size() > 1:
		what += "　第 %d / %d 段" % [path.find(_segment(_frame)) + 1, path.size()]
	_info.text = "%.2f / %.2f 秒（第 %d 步）　%s　%s　腳步：%s\n%s" % [t, total, _frame - _lo, "播放" if _playing else "暫停", "%s×" % _speed, _feet, what]
	_play_button.text = "暫停" if _playing else "播放"


# ───────── 視角 ─────────

func _set_view(v: String) -> void:
	_view = v
	var spec: Array = VIEWS[v]
	_game_view = spec[2]
	_ortho = _game_view
	if _game_view:
		_yaw_game = Config.CAMERA.azimuth
		_pitch = Config.CAMERA.elevation
	else:
		_yaw_rel = spec[0]
		_pitch = spec[1]
	_mark_buttons()
	_update_camera()


# 鏡頭方位
func yaw() -> float:
	if _game_view:
		return _yaw_game
	return (_row.frames[_path()[0][1]].facing if not _row.is_empty() else 0.0) + _yaw_rel


func _update_camera() -> void:
	var target := Vector3.ZERO
	var height := 2.0
	if not _made.is_empty():
		var rig: Node3D = _made.rig
		height = rig.height if "height" in rig else 2.0
		target = rig.position + Vector3(0.0, height * 0.5, 0.0)
	var y := yaw()
	var offset := Vector3(cos(_pitch) * sin(y), sin(_pitch), cos(_pitch) * cos(y))
	var trail := (_made.rig as Node).get_node_or_null(^"BladeTrail") as BladeTrail if not _made.is_empty() else null
	if trail != null:
		trail.to_camera = offset
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL if _ortho else Camera3D.PROJECTION_PERSPECTIVE
	_cam.size = _dist * 0.75
	_cam.look_at_from_position(target + offset * (_dist if not _ortho else 40.0), target, Vector3.UP)
	# 角色放在面板右邊那塊的正中間：鏡頭往左平移半個面板寬（換算成角色那個距離的世界寬度）
	var view := get_viewport().get_visible_rect().size
	var half_h := _cam.size / 2.0 if _ortho else _dist * tan(deg_to_rad(_cam.fov) / 2.0)
	_cam.h_offset = -half_h * (view.x / maxf(view.y, 1.0)) * (PANEL_WIDTH / maxf(view.x, 1.0))


# 快捷鍵在 _input 先接，不被拿到焦點的介面吃掉
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo):
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE:
			_toggle_play()
		KEY_LEFT:
			_step_by(-1)
		KEY_RIGHT:
			_step_by(1)
		KEY_UP, KEY_DOWN:
			var n := _rows.size()
			if n > 0:
				var cur: int = _action_list.get_selected_items()[0] if not _action_list.get_selected_items().is_empty() else 0
				var next: int = (cur + (1 if (event as InputEventKey).keycode == KEY_DOWN else -1) + n) % n
				_action_list.select(next)
				_action_list.ensure_current_is_visible()
				_pick_action(next)
		KEY_R:
			_rerecord()
		_:
			return
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = clampf(_dist * 0.9, DIST_RANGE.x, DIST_RANGE.y)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = clampf(_dist * 1.1, DIST_RANGE.x, DIST_RANGE.y)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT) == 0:
			_dragging = false   # 放開事件被面板接走時
			return
		if _game_view:
			_yaw_game -= mm.relative.x * ORBIT_SPEED
		else:
			_yaw_rel -= mm.relative.x * ORBIT_SPEED
		_pitch = clampf(_pitch + mm.relative.y * ORBIT_SPEED, -0.2, 1.45)
