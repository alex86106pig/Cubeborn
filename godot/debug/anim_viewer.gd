# 動畫檢視器（除錯用）：選角色、選動作，播放 / 暫停 / 逐格 / 慢動作、拖時間軸、轉視角，修動畫時用。
# 開法：Godot 編輯器開 debug/anim_viewer.tscn 按 F6（執行中改 view/ 的動畫程式存檔就會套用，重錄才會重跑模擬）；
# 網頁版 ?anim-viewer（main.gd 不開遊戲，只開這個）。動作用 AnimRecorder 錄（跟動作表 PoseGallery 同一套）。
# 特效也照錄到的放：持續性的（噴火、蓄力粒子）照每一步的動作冒，事件型的（揮砍弧光、爆炸、命中火花）照錄到的事件放；慢動作時特效也跟著慢
# 一打開就選好：AnimViewer.new("enemy-gravekeeper:lantern")（網址 ?anim-viewer=enemy-gravekeeper:lantern；動作寫英文 id；
# 第三段是腳步：enemy-gravekeeper:lantern:原地 / 走 / 跑）
# 操作：空白鍵 播放 / 暫停、← → 逐格、↑ ↓ 換動作、R 重錄、滑鼠拖曳轉視角、滾輪縮放
# 視角（方位相對角色朝向、仰角、距離）換動作、換角色、重錄都留著，只有按視角按鈕才換（YangHsu 2026-11-12）
class_name AnimViewer
extends Node3D

const DT := Config.FIXED_DT
const SPEEDS := [0.1, 0.25, 0.5, 1.0]
# 腳步：照錄到的（跟遊戲一樣）/ 原地 / 走 / 跑；走、跑的速度照腿長換算（Froude 數 0.3 = 走、4 = 跑，同 BodyPose 的走跑分界）
const FEET := {"照錄到的": -1.0, "原地": 0.0, "走": 0.3, "跑": 4.0}
const GRID_HALF := 10            # 地板格線的範圍（± 公尺），1 公尺一格
const PANEL_WIDTH := 360
const ORBIT_SPEED := 0.008       # 拖曳轉視角：每像素幾弧度
const DIST_RANGE := Vector2(2.5, 30.0)
# 視角：[相對角色朝向的方位角（0 = 正前方、-PI/2 = 角色右手邊）, 仰角, 正交]；game 是遊戲的鏡頭（Config.CAMERA，世界方位、不跟著角色）
# 正面、背面是正前方 / 正後方（原本偏 0.4~0.45 弧度的斜角，YangHsu 2026-11-12：「前方也不是真的前方」）
const VIEWS := {"側面": [-PI / 2.0, 0.12, false], "正面": [0.0, 0.12, false], "背面": [PI, 0.12, false], "遊戲": [0.0, 0.0, true]}

var _recorder := AnimRecorder.new()
var _subjects: Array[Dictionary] = AnimRecorder.subjects()
var _rows: Array = []
var _row: Dictionary = {}
var _made: Dictionary = {}       # { rig, anim }：正在播的角色
var _frame := 0                  # 已經餵給動畫器到第幾步
var _start := 0                  # 這段動作從第幾步開始（前面是讓動畫器接得上的暖身）
var _carry := 0.0
var _playing := true
var _speed := 1.0
var _loop := true
var _follow := true              # 角色照錄到的位置移動（看得出腳有沒有在地上滑）；關掉就原地
var _feet := "照錄到的"
var _yaw_rel := -PI / 2.0        # 相對這段動作開頭的角色朝向（換動作時角色朝向不同，看的角度照樣）
var _yaw_game: float = Config.CAMERA.azimuth   # 遊戲視角是世界方位，不跟著角色
var _pitch := 0.12
var _dist := 7.0
var _ortho := false
var _game_view := false
var _dragging := false
var _view := "側面"
var _speed_buttons := {}         # 速度 / 腳步 / 視角按鈕：按下去一直亮著，看得出現在選的是哪個
var _feet_buttons := {}
var _view_buttons := {}

var _cam := Camera3D.new()
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


func _init(pick := "") -> void:
	_initial = pick


func _ready() -> void:
	_build_stage()
	_build_ui()
	var subject := 0
	var feet := _initial.get_slice(":", 2) if _initial.count(":") >= 2 else ""
	if FEET.has(feet):
		_feet = feet
		_mark_buttons()
	for i in _subjects.size():
		if _subjects[i].id == _initial.get_slice(":", 0):
			subject = i
	_pick_subject(subject)
	var action := _initial.get_slice(":", 1) if _initial.contains(":") else ""
	for i in _rows.size():
		if _rows[i].key == action:
			_action_list.select(i)
			_pick_action(i)
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
	add_child(floor_mesh)
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
			add_child(l)


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
	loop.focus_mode = Control.FOCUS_NONE   # 拿到焦點的話空白鍵會變成切勾選，不是播放 / 暫停
	loop.toggled.connect(func(on: bool) -> void: _loop = on)
	toggles.add_child(loop)
	var follow := CheckBox.new()
	follow.text = "跟著走（關 = 原地）"
	follow.button_pressed = _follow
	follow.focus_mode = Control.FOCUS_NONE
	follow.toggled.connect(func(on: bool) -> void: _follow = on; _place_rig())
	toggles.add_child(follow)
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
	box.add_child(UiKit.label("空白鍵 播放 / 暫停　← → 逐格　↑ ↓ 換動作\n滑鼠拖曳轉視角　滾輪縮放", UiKit.FONT_NOTE, Color(1, 1, 1, 0.6)))
	_subject_pick.focus_mode = Control.FOCUS_NONE
	_slider.focus_mode = Control.FOCUS_NONE
	_mark_buttons()


# 同一組只亮一個的按鈕（ButtonGroup）：key 是這顆代表的值，_mark_buttons 照現在的值按下去
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

# 換角色時新角色也有同一個動作（例如換武器看普攻）就停在那個動作
func _pick_subject(i: int) -> void:
	var keep: String = _row.get("key", "")
	_free_rig()
	_recorder.clear()
	_rows = _recorder.rows(_subjects[i].id)
	_action_list.clear()
	for r: Dictionary in _rows:
		_action_list.add_item(r.name if r.name == r.key else "%s  %s" % [r.name, r.key])
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
	_row = _rows[i]
	_start = _row.get("start", 0)
	_restart()
	_update_camera()   # 不重設視角：方位照舊相對角色朝向、仰角與距離不變


func _rerecord() -> void:
	var action: int = _action_list.get_selected_items()[0] if not _action_list.get_selected_items().is_empty() else 0
	var subject := _subject_pick.selected
	_pick_subject(subject)
	if action < _rows.size():
		_action_list.select(action)
		_pick_action(action)


# 從頭建一隻角色、重播到 _start（之後一步一步往前）
func _restart() -> void:
	_seek(_start)


# 跳到第 target 步：重建角色、從第 0 步重播（動畫器有平滑，倒退只能重播）
func _seek(target: int) -> void:
	_free_rig()
	_fx.clear()
	_fx_world.entities = {(_row.subject as Entity).id: _row.subject}
	_made = (_row.make as Callable).call()
	add_child(_made.rig)
	var frames: Array = _row.frames
	_frame = clampi(target, _start, frames.size() - 1)
	AnimRecorder.replay(_row, _made, _frame, _foot_speed())
	_carry = 0.0
	_place_rig()
	_sync_slider()


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
	var frames: Array = _row.frames
	if _frame + 1 < frames.size():
		_frame += 1
		AnimRecorder.step(_row, _made, _frame, _foot_speed())
		for ev: Dictionary in _row.frames[_frame].get("events", []):
			_fx.on_event(ev.name, ev)
		_place_rig()
		_sync_slider()
	elif _loop:
		_restart()
	else:
		_playing = false
		_refresh_info()


func _step_by(n: int) -> void:
	_playing = false
	if n > 0:
		for i in n:
			_advance()
	else:
		_seek(_frame + n)
	_refresh_info()


func _toggle_play() -> void:
	_playing = not _playing
	_refresh_info()


func _on_slider(v: float) -> void:
	if _syncing_slider or _row.is_empty():
		return
	_playing = false
	_seek(int(v))


func _sync_slider() -> void:
	_syncing_slider = true
	_slider.min_value = _start
	_slider.max_value = maxf((_row.frames as Array).size() - 1, _start + 1)
	_slider.value = _frame
	_syncing_slider = false
	_refresh_info()


# 角色的位置與朝向照錄到的（跟著走）或留在原點（原地）；遊戲的根節點就是這樣擺（WorldView）
func _place_rig() -> void:
	if _made.is_empty():
		return
	var f: Dictionary = _row.frames[_frame]
	var origin: Vector2 = _row.frames[_start].pos
	var rig: Node3D = _made.rig
	var now: Vector2 = (_row.subject as Entity).pos   # 腳步改過時位置也跟著改（AnimRecorder.step 擺好了）
	var p: Vector2 = now - origin if _follow else Vector2.ZERO
	rig.position = Vector3(p.x, f.height, p.y)
	rig.rotation.y = f.facing
	# 特效是世界座標：整組跟角色一樣平移（原地時跟著角色現在的位置）
	var shift: Vector2 = origin if _follow else now
	_fx.position = Vector3(-shift.x, 0.0, -shift.y)


func _refresh_info() -> void:
	if _row.is_empty():
		return
	var a: Dictionary = _row.frames[_frame].anim
	var t := (_frame - _start) * DT
	var total := ((_row.frames as Array).size() - 1 - _start) * DT
	var what := ""
	if a.has("loco"):   # 玩家
		what = "移動 %s　動作 %s %s" % [a.loco, a.action, a.get("phase", "")]
		if a.get("skill", &"") != &"":
			what += "\n戰技 %s %.2f 秒" % [a.skill, a.skill_time]
	else:
		what = "狀態 %s %s" % [a.get("state", ""), a.get("phase", "")]
	_info.text = "%.2f / %.2f 秒（第 %d 步）　%s　%s　腳步：%s\n%s" % [t, total, _frame - _start, "播放" if _playing else "暫停", "%s×" % _speed, _feet, what]
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


# 鏡頭的方位：遊戲視角是世界方位；其他照這段動作開頭的角色朝向 + 相對角度
func yaw() -> float:
	if _game_view:
		return _yaw_game
	return (_row.frames[_start].facing if not _row.is_empty() else 0.0) + _yaw_rel


func _update_camera() -> void:
	var target := Vector3.ZERO
	var height := 2.0
	if not _made.is_empty():
		var rig: Node3D = _made.rig
		height = rig.height if "height" in rig else 2.0
		target = rig.position + Vector3(0.0, height * 0.5, 0.0)
	var y := yaw()
	var offset := Vector3(cos(_pitch) * sin(y), sin(_pitch), cos(_pitch) * cos(y))
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL if _ortho else Camera3D.PROJECTION_PERSPECTIVE
	_cam.size = _dist * 0.75
	_cam.look_at_from_position(target + offset * (_dist if not _ortho else 40.0), target, Vector3.UP)
	# 角色放在面板右邊那塊的正中間：鏡頭往左平移半個面板寬（換算成角色那個距離的世界寬度）
	var view := get_viewport().get_visible_rect().size
	var half_h := _cam.size / 2.0 if _ortho else _dist * tan(deg_to_rad(_cam.fov) / 2.0)
	_cam.h_offset = -half_h * (view.x / maxf(view.y, 1.0)) * (PANEL_WIDTH / maxf(view.x, 1.0))


# 快捷鍵在 _input 先接（介面拿到焦點時不會被吃掉，例如點過動作清單後空白鍵照樣播放 / 暫停）；滑鼠留給 _unhandled_input（面板上的不轉視角）
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
			_dragging = false   # 在面板上放開的按鍵事件被介面接走了：沒按著就不轉
			return
		if _game_view:
			_yaw_game -= mm.relative.x * ORBIT_SPEED
		else:
			_yaw_rel -= mm.relative.x * ORBIT_SPEED
		_pitch = clampf(_pitch + mm.relative.y * ORBIT_SPEED, -0.2, 1.45)
