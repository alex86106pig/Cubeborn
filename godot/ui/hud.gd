# HUD（照搬網頁版 src/ui/HUD.js 與 css/style.css）：血條、武器、波次 / 擊殺 / 時間、FPS、版號、Boss 血條、
# 技能欄、橫幅、受擊暗角、浮動數字、暫停與結算畫面。只讀模擬狀態與事件，不修改模擬
class_name HUD
extends CanvasLayer

const CONTROLS_TEXT := "WASD 移動 · 滑鼠瞄準 · 左鍵攻擊 · 右鍵特殊技 · 1~5 道具 · Esc 暫停 · F1 切換武器 · F2 顯示判定 · R 重新開始"
const FPS_INTERVAL := 0.5
const HP_GHOST_SPEED := 0.5      # 殘影每秒縮短的比例
const BOSS_GHOST_SPEED := 0.3
const BOSS_BAR_DELAY := 0.3      # Boss 爬出後多久才顯示血條
const BANNER_TIME := 1.6
const VIGNETTE_TIME := 0.45
const GAME_OVER_DELAY := 0.7     # 死亡後幾秒顯示結算
const BOSS_NAME := "亡骸騎士"     # darkFantasy.js 的 names.boss

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	vec2 d = abs(UV - 0.5) * 2.0;
	float edge = smoothstep(0.55, 1.05, max(d.x, d.y));
	COLOR = vec4(1.0, 0.0, 0.0, edge * 0.55 * strength);
}
"""

var world: World
var camera: Camera3D

var _hp: Dictionary
var _hp_ghost := 1.0
var _weapon := UiKit.label("", 16)
var _wave := UiKit.label("", 22)
var _kills := UiKit.label("", 16)
var _time := UiKit.label("", 16)
var _fps := UiKit.label("", 12)
var _boss_box := VBoxContainer.new()
var _boss_name := UiKit.label("", 18)
var _boss: Dictionary
var _boss_ghost := 1.0
var _skill_bar := SkillBar.new()
var _floaters := Floaters.new()
var _banner := UiKit.label("", 48, Color.WHITE, 4)
var _vignette := ColorRect.new()
var _game_over := ColorRect.new()
var _game_over_title := UiKit.label("", 56, UiKit.ALERT, 3)
var _game_over_stats := UiKit.label("", 20)
var _pause := ColorRect.new()
var _fps_timer := 0.0
var _fps_frames := 0
var _game_over_delay := -1.0     # 死亡後倒數顯示結算；負數 = 沒有在倒數（重新開始時取消）
var _banner_tween: Tween
var _vignette_tween: Tween


func setup(p_world: World, p_camera: Camera3D) -> void:
	world = p_world
	camera = p_camera
	_floaters.camera = p_camera


# 在建構時就建好介面（不等 _ready），HUD 一建立就能更新與接收事件
func _init() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = VIGNETTE_SHADER
	_vignette.material = mat
	root.add_child(_vignette)
	root.add_child(_floaters)

	# 左上：血條、武器、操作說明
	var tl := VBoxContainer.new()
	tl.position = Vector2(16, 16)
	tl.add_theme_constant_override(&"separation", 8)
	_hp = UiKit.bar(Vector2(280, 26), UiKit.HP_BG, UiKit.HP_FILL, 3)
	tl.add_child(_hp.root)
	tl.add_child(_weapon)
	var help := UiKit.label(CONTROLS_TEXT, 12, Color(1, 1, 1, 0.55), 1)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 300
	tl.add_child(help)
	root.add_child(tl)

	# 右上：波次、擊殺、時間、FPS、版號
	var tr := VBoxContainer.new()
	tr.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.add_theme_constant_override(&"separation", 2)
	var version := UiKit.label("v" + GameVersion.VERSION, 12, Color(1, 1, 1, 0.6), 1)
	for l: Label in [_wave, _kills, _time, _fps, version]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tr.add_child(l)
	_fps.modulate.a = 0.6
	root.add_child(tr)

	# 上方中央：Boss 血條
	_boss_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 18)
	_boss_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_name)
	_boss = UiKit.bar(Vector2(560, 16), UiKit.BOSS_BG, UiKit.BOSS_FILL, 3)
	_boss_box.add_child(_boss.root)
	_boss_box.visible = false
	root.add_child(_boss_box)

	# 下方中央：技能欄
	_skill_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 20)
	_skill_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_skill_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_skill_bar)

	# 橫幅（畫面 22% 高處）
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.anchor_top = 0.22
	_banner.anchor_bottom = 0.22
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	root.add_child(_banner)

	_build_overlay(_game_over, Color(40 / 255.0, 0, 0, 0.55), [_game_over_title, _game_over_stats, _pulse(UiKit.label("按 R 重新開始", 20))])
	root.add_child(_game_over)
	var pause_controls := UiKit.label(CONTROLS_TEXT, 14, Color(1, 1, 1, 0.75))
	pause_controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pause_controls.custom_minimum_size.x = 520
	_build_overlay(_pause, Color(5 / 255.0, 8 / 255.0, 16 / 255.0, 0.65), [UiKit.label("已暫停", 56, Color.WHITE, 3), UiKit.label("按 Esc 繼續", 20), pause_controls])
	root.add_child(_pause)


func _ready() -> void:
	GameEvents.event_emitted.connect(_on_event)


func _build_overlay(panel: ColorRect, color: Color, children: Array) -> void:
	panel.color = color
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 8)
	for c: Label in children:
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(c)
	panel.add_child(box)


func _pulse(l: Label) -> Label:
	var t := l.create_tween().set_loops()
	t.tween_property(l, ^"modulate:a", 0.4, 0.6)
	t.tween_property(l, ^"modulate:a", 1.0, 0.6)
	return l


func _process(delta: float) -> void:
	_update_fps(delta)
	if _game_over_delay >= 0.0:
		_game_over_delay -= delta
		if _game_over_delay < 0.0:
			_game_over.visible = true
	if world == null:
		return
	var player: Player = world.players.get(World.HOST_PEER_ID)
	if player == null:
		return
	_skill_bar.refresh(world, player)

	var ratio := player.hp / player.max_hp
	_hp_ghost = maxf(ratio, _hp_ghost - delta * HP_GHOST_SPEED)
	_set_bar(_hp, ratio, _hp_ghost)
	_hp.text.text = "%d / %d" % [player.hp, player.max_hp]
	_weapon.text = "武器：" + player.weapon.name
	var s := world.stats
	_wave.text = "第 %d / %d 波" % [s.wave, world.spawner.total_waves()] if s.wave > 0 else "準備中"
	_kills.text = "擊殺 %d" % s.kills
	_time.text = UiKit.format_time(s.time)
	_update_boss(delta)


func _update_fps(delta: float) -> void:
	_fps_timer += delta
	_fps_frames += 1
	if _fps_timer >= FPS_INTERVAL:
		_fps.text = "FPS %d" % roundi(_fps_frames / _fps_timer)
		_fps_timer = 0.0
		_fps_frames = 0


func _update_boss(delta: float) -> void:
	var boss: Boss = world.entities.get(world.boss_id) as Boss
	_boss_box.visible = boss != null and not (boss.is_spawning() and boss.fsm.time < BOSS_BAR_DELAY)
	if boss == null:
		return
	var r := boss.hp / boss.max_hp
	_boss_ghost = maxf(r, _boss_ghost - delta * BOSS_GHOST_SPEED)
	_set_bar(_boss, r, _boss_ghost)
	_boss_name.text = BOSS_NAME + ("（狂暴）" if boss.is_enraged else "")
	_boss_name.add_theme_color_override(&"font_color", UiKit.BOSS_NAME_ENRAGED if boss.is_enraged else Color.WHITE)
	_boss.fill.color = UiKit.BOSS_FILL_ENRAGED if boss.is_enraged else UiKit.BOSS_FILL


func _set_bar(bar: Dictionary, value: float, ghost: float) -> void:
	bar.fill.size.x = bar.width * clampf(value, 0.0, 1.0)
	bar.ghost.size.x = bar.width * clampf(ghost, 0.0, 1.0)


func _on_event(name: String, p: Dictionary) -> void:
	match name:
		"entity:damaged":
			var target: Entity = world.entities.get(p.target_id) if world else null
			if target == null:
				return
			var is_player := target is Player
			_floaters.spawn(target, str(p.amount), &"player" if is_player else (&"crit" if p.is_crit else &"dmg"))
			if is_player:
				_flash_vignette()
		"entity:healed":
			var target: Entity = world.entities.get(p.target_id) if world else null
			if target != null and p.amount > 0:
				_floaters.spawn(target, "+%d" % p.amount, &"heal")
		"skill:onCooldown":
			_skill_bar.flash(p.key, true)
		"skill:used":
			_skill_bar.flash(p.key, false)
		"wave:started":
			_show_banner("BOSS 戰：" + BOSS_NAME if p.is_boss else "第 %d / %d 波" % [p.wave, p.total], p.is_boss)
		"boss:enraged":
			_show_banner("狂暴化！", true)
		"player:died":
			var s := world.stats
			_set_game_over("你倒下了", "撐到第 %d 波 · 擊殺 %d · 時間 %s" % [s.wave, s.kills, UiKit.format_time(s.time)], false)
			_game_over_delay = GAME_OVER_DELAY
		"game:victory":
			var s: Dictionary = p.stats
			_set_game_over("勝利！", "擊敗 %s · 擊殺 %d · 通關時間 %s" % [BOSS_NAME, s.kills, UiKit.format_time(s.time)], true)
			_game_over.visible = true
		"game:paused":
			_pause.visible = p.paused
		"game:restart":
			_game_over_delay = -1.0
			_game_over.visible = false
			_pause.visible = false
			_hp_ghost = 1.0
			_boss_ghost = 1.0
			_skill_bar.reset()
			_floaters.clear()


func _set_game_over(title: String, stats: String, victory: bool) -> void:
	_game_over_title.text = title
	_game_over_title.add_theme_color_override(&"font_color", UiKit.GOLD if victory else UiKit.ALERT)
	_game_over_stats.text = stats
	_game_over.color = Color(40 / 255.0, 30 / 255.0, 0, 0.5) if victory else Color(40 / 255.0, 0, 0, 0.55)


# 網頁版 @keyframes banner：0~15% 由 1.3 倍縮回並淡入，75% 後淡出
func _show_banner(text: String, alert: bool) -> void:
	_banner.text = text
	_banner.add_theme_color_override(&"font_color", UiKit.ALERT if alert else Color.WHITE)
	_banner.pivot_offset = _banner.size / 2.0
	if _banner_tween:
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_banner.scale = Vector2.ONE * 1.3
	_banner_tween = create_tween()
	_banner_tween.set_parallel()
	_banner_tween.tween_property(_banner, ^"modulate:a", 1.0, BANNER_TIME * 0.15)
	_banner_tween.tween_property(_banner, ^"scale", Vector2.ONE, BANNER_TIME * 0.15).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_property(_banner, ^"modulate:a", 0.0, BANNER_TIME * 0.25).set_delay(BANNER_TIME * 0.75)


func _flash_vignette() -> void:
	var mat: ShaderMaterial = _vignette.material
	if _vignette_tween:
		_vignette_tween.kill()
	mat.set_shader_parameter(&"strength", 1.0)
	_vignette_tween = create_tween()
	_vignette_tween.tween_method(func(v: float) -> void: mat.set_shader_parameter(&"strength", v), 1.0, 0.0, VIGNETTE_TIME).set_ease(Tween.EASE_OUT)
