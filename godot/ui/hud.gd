# HUD（照搬網頁版 legacy/src/ui/HUD.js 與 css/style.css）：血條、武器、波次 / 擊殺 / 時間、FPS、版號、Boss 血條、
# 技能欄、屬性面板、橫幅、受擊暗角、浮動數字、暫停與結算畫面。只讀模擬狀態與事件，不修改模擬
class_name HUD
extends CanvasLayer

signal quit_requested   # 暫停畫面或主選單按下「離開遊戲」
signal title_requested  # 暫停畫面按下「回主選單」

# 手動分行（中文自動折行會斷在詞中間）
const CONTROLS_TEXT := "WASD 移動 · 滑鼠瞄準 · 左鍵攻擊 · 右鍵特殊技（劍盾：按住格擋，格擋中左鍵招架） · 空白鍵 跳躍 · Shift 翻滾\n1~5 道具 · F 撿道具 / 開寶箱 / 按住救援隊友 · Tab 背包與屬性 · Esc 選單 · M 靜音 · R 重新開始\nX / 滾輪 切換武器 · F2 顯示判定 · F3 除錯移速 +50% · F4 放入下一個道具 · F5 清空道具（F3~F5 單機才有）"
const FPS_INTERVAL := 0.5
const HP_GHOST_SPEED := 0.5      # 殘影每秒縮短的比例
const BOSS_GHOST_SPEED := 0.3
const BOSS_BAR_DELAY := 0.3      # Boss 爬出後多久才顯示血條
const BANNER_TIME := 1.6
const VIGNETTE_TIME := 0.45
const GAME_OVER_DELAY := 0.7     # 死亡後幾秒顯示結算
const BOSS_NAME := "亡骸騎士"     # darkFantasy.js 的 names.boss
# 介面程式碼裡寫死的中文字（橫幅、浮動文字、場上文字、連線面板、遊玩紀錄…；資料表以外的）：開場預熱用（v0.37.2）
# check.gd 會掃 ui/ 的字串，缺字就列出來，加到這裡
const UI_CHARS := "　！才湧先（），、：·…一了人入力上下亡口士已弓不中之內化友手主出功加包去外打未生用示穴丟全合同在多成曳有次死色西住作你利完投攻沒狂見走足使來到受始尚往怪或房拖明東果武波版物的空近金前屍度按挖活看秒美背要重面音頁個倒冤員害射效時格能起陣停動區啟基帶掉救敗旋條殺現第被設通速連備勝圍單選腦和玩返擇方式缺少虛擬只就復提援稀等著詞越進開間隊傷搬新會準落號裝裡路遊墓實幣滿種網需魂墳層撐暫暴獎碼範線靠骷器戰撿擋輸靜骸勵戲擊礎轉離騎關難繼續髏顯體"

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
var local_peer := World.HOST_PEER_ID   # 這台電腦的玩家（連線時由 main.gd 設定）
var net_panel := NetPanel.new()
var main_menu := MainMenu.new()   # 開場的主選單（v0.39.0）

var _hp: Dictionary
var _hp_ghost := 1.0
var _weapon := UiKit.label("", 16)
var _gold := UiKit.label("", 18, UiKit.GOLD)
var _world_labels := WorldLabels.new()
var inventory_panel := InventoryPanel.new()   # I 開關（main.gd 接到輸入）
var _wave := UiKit.label("", 22)
var _kills := UiKit.label("", 16)
var _time := UiKit.label("", 16)
var _fps := UiKit.label("", 12)
var _mute := UiKit.label("", 12, Color(1, 1, 1, 0.75))
var _boss_box := VBoxContainer.new()
var _boss_name := UiKit.label("", 18)
var _boss: Dictionary
var _boss_ghost := 1.0
var _dig_box := VBoxContainer.new()   # 挖墳進度條（v0.38.0）：事件進行中所有人都看得到
var _dig_name := UiKit.label("", 20, UiKit.GOLD)
var _dig: Dictionary
var _skill_bar := SkillBar.new()
var _stats_panel := StatsPanel.new()
var _floaters := Floaters.new()
var _banner := UiKit.label("", 48, Color.WHITE, 4)
var _vignette := ColorRect.new()
var _game_over := ColorRect.new()
var _game_over_title := UiKit.label("", 56, UiKit.ALERT, 3)
var _game_over_stats := UiKit.label("", 20)
var _game_over_log := UiKit.label("", 18, Color(1, 1, 1, 0.85))   # 遊玩紀錄（v0.34.0）
var run_log := RunLog.new()
var _pause := ColorRect.new()
var _pause_title := UiKit.label("已暫停", 56, Color.WHITE, 3)
var _pause_hint := UiKit.label("按 Esc 繼續", 20)
var _quit_button := Button.new()
var _title_button := Button.new()
var _pause_net_slot := VBoxContainer.new()   # 暫停畫面放連線面板的位置（連線中顯示人數與離開連線）
var _reset_hints_button := Button.new()
var hints := Hints.new()   # 新手提示框（v0.31.0）
var _loading := ColorRect.new()   # 開場預熱時蓋住畫面（v0.37.0）；底下先畫一次會用到的中文字，字形在這時候產生
var _tags := PlayerTags.new()
var _fps_timer := 0.0
var _fps_frames := 0
var _game_over_delay := -1.0     # 死亡後倒數顯示結算；負數 = 沒有在倒數（重新開始時取消）
var _banner_tween: Tween
var _vignette_tween: Tween


func setup(p_world: World, p_camera: Camera3D) -> void:
	world = p_world
	camera = p_camera
	_floaters.camera = p_camera
	_tags.world = p_world
	_tags.camera = p_camera
	_world_labels.world = p_world
	_world_labels.camera = p_camera
	inventory_panel.world = p_world


func set_local_peer(peer_id: int) -> void:
	local_peer = peer_id
	_tags.local_peer = peer_id
	_world_labels.local_peer = peer_id
	inventory_panel.local_peer = peer_id


func local_player() -> Player:
	return world.players.get(local_peer) if world != null else null


# 選單（Esc）：單機時是暫停畫面；連線時遊戲不會停，標題改成「選單」
func show_menu(visible_: bool, title: String = "已暫停", hint: String = "按 Esc 繼續") -> void:
	_reset_hints_button.text = "重新顯示提示"
	_pause_title.text = title
	_pause_hint.text = hint
	_pause.visible = visible_
	# 單機的暫停畫面不放連線面板（開房 / 加入改從主選單），連線中才顯示人數與離開連線
	net_panel.visible = net_panel.mode != &"single" or net_panel.get_parent() != _pause_net_slot


# 主選單：打開時連線面板搬到多人頁，關掉時搬回暫停畫面
func show_title(on: bool, page: StringName = &"home") -> void:
	main_menu.visible = on
	main_menu.show_page(page)
	var slot: Control = main_menu.net_slot if on else _pause_net_slot
	if net_panel.get_parent() != slot:
		net_panel.reparent(slot, false)
	if on:
		_pause.visible = false
		net_panel.visible = true


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
	root.add_child(_tags)
	root.add_child(_world_labels)
	root.add_child(_floaters)

	# 左上：血條、武器、操作說明
	var tl := VBoxContainer.new()
	tl.position = Vector2(16, 16)
	tl.add_theme_constant_override(&"separation", 8)
	_hp = UiKit.bar(Vector2(280, 26), UiKit.HP_BG, UiKit.HP_FILL, 3)
	tl.add_child(_hp.root)
	tl.add_child(_weapon)
	tl.add_child(_gold)
	_hp.root.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN   # 說明文字較寬時血條不跟著拉長
	tl.add_child(UiKit.label(CONTROLS_TEXT, 12, Color(1, 1, 1, 0.55), 1))
	root.add_child(tl)

	# 右上：波次、擊殺、時間、FPS、版號
	var tr := VBoxContainer.new()
	tr.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.add_theme_constant_override(&"separation", 2)
	var version := UiKit.label("v" + GameVersion.VERSION, 12, Color(1, 1, 1, 0.6), 1)
	for l: Label in [_wave, _kills, _time, _fps, version, _mute]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tr.add_child(l)
	_fps.modulate.a = 0.6
	root.add_child(tr)

	# 上方中央：挖墳進度條，下面是 Boss 血條（兩個都有時往下排）
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 18)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.add_theme_constant_override(&"separation", 14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dig_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dig_box.add_child(_dig_name)
	_dig = UiKit.bar(Vector2(560, 22), UiKit.DIG_BG, UiKit.GOLD, 3)
	_dig.text.add_theme_font_size_override(&"font_size", 16)
	_dig_box.add_child(_dig.root)
	_dig_box.visible = false
	top.add_child(_dig_box)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_name)
	_boss = UiKit.bar(Vector2(560, 16), UiKit.BOSS_BG, UiKit.BOSS_FILL, 3)
	_boss_box.add_child(_boss.root)
	_boss_box.visible = false
	top.add_child(_boss_box)
	root.add_child(top)

	# 下方中央：技能欄
	_skill_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 20)
	_skill_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_skill_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_skill_bar)

	# 下方中央、技能欄上面：新手提示（v0.31.0）
	hints.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 150)
	hints.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(hints)

	# 左側中央：屬性面板（Tab 開關）
	_stats_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	_stats_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_stats_panel.visible = false
	root.add_child(_stats_panel)

	# 右側中央：背包（I 開關，D3）
	inventory_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	inventory_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	inventory_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	inventory_panel.visible = false
	root.add_child(inventory_panel)

	# 橫幅（畫面 22% 高處）
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.anchor_top = 0.22
	_banner.anchor_bottom = 0.22
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	root.add_child(_banner)

	_build_overlay(_game_over, Color(40 / 255.0, 0, 0, 0.55), [_game_over_title, _game_over_stats, _game_over_log, _pulse(UiKit.label("按 R 重新開始", 20))])
	root.add_child(_game_over)
	var pause_controls := UiKit.label(CONTROLS_TEXT, 14, Color(1, 1, 1, 0.75))
	# 離開遊戲按鈕：網頁版不顯示（瀏覽器不允許網頁自己關閉）
	_quit_button.text = "離開遊戲"
	_quit_button.add_theme_font_size_override(&"font_size", 20)
	_quit_button.custom_minimum_size = Vector2(180, 44)
	_quit_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_quit_button.focus_mode = Control.FOCUS_NONE
	_quit_button.visible = not OS.has_feature("web")
	_quit_button.pressed.connect(quit_requested.emit)
	_title_button.text = "回主選單"
	_title_button.add_theme_font_size_override(&"font_size", 20)
	_title_button.custom_minimum_size = Vector2(180, 44)
	_title_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title_button.focus_mode = Control.FOCUS_NONE
	_title_button.pressed.connect(title_requested.emit)
	_pause_net_slot.add_child(net_panel)
	_reset_hints_button.text = "重新顯示提示"
	_reset_hints_button.add_theme_font_size_override(&"font_size", 18)
	_reset_hints_button.custom_minimum_size = Vector2(180, 40)
	_reset_hints_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_reset_hints_button.focus_mode = Control.FOCUS_NONE
	_reset_hints_button.pressed.connect(func() -> void:
		hints.reset_seen()
		_reset_hints_button.text = "提示已重設")
	_build_overlay(_pause, Color(5 / 255.0, 8 / 255.0, 16 / 255.0, 0.65), [_pause_title, _pause_hint, pause_controls, _pause_net_slot, _reset_hints_button, _title_button, _quit_button])
	_pause.mouse_filter = Control.MOUSE_FILTER_STOP   # 選單的按鈕與輸入框要能點
	root.add_child(_pause)
	main_menu.visible = false
	main_menu.quit_pressed.connect(quit_requested.emit)
	main_menu.method_chosen.connect(net_panel.set_method)
	root.add_child(main_menu)
	_build_overlay(_loading, Color(0.03, 0.03, 0.05, 1.0), [UiKit.label("準備中…", 28)])
	root.add_child(_loading)


# 開場預熱（v0.37.0）：on 時蓋住畫面；第一次打開時在蓋板上畫一次道具、怪物、提示會用到的字（幾乎透明），
# 動態字型的字形在這時候產生，之後第一次出現就不會卡
func set_loading(on: bool) -> void:
	if on and _loading.get_child_count() < 2:
		var box := VBoxContainer.new()
		box.modulate.a = 0.02
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var text := warm_text()
		for style: Array in [[16, 0], [18, 0], [20, 2], [28, 2], [48, 4]]:
			var l := UiKit.label(text, style[0], Color.WHITE, style[1])
			l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
			l.custom_minimum_size.x = 1800
			box.add_child(l)
		_loading.add_child(box)
	_loading.visible = on
	_world_labels.warm = warm_text() if on else ""   # 場上文字是描邊字，字形另外快取，用它自己的畫法預熱


# 會在遊戲中途第一次出現的字：道具名稱與說明、稀有度、怪物詞條與名字、武器詞條、新手提示
static func warm_text() -> String:
	var chars := {}
	for script: Script in [ItemDefs, MonsterRarityDefs, WeaponDropDefs, HintDefs, StatDefs, LootDefs]:
		_collect_chars(script.get_script_constant_map(), chars)
	_collect_chars(UI_CHARS, chars)
	var out := ""
	for ch: String in chars:
		out += ch
	return out


static func _collect_chars(v: Variant, chars: Dictionary) -> void:
	if v is String or v is StringName:
		for ch in String(v):
			if ch.unicode_at(0) > 127:
				chars[ch] = true
	elif v is Dictionary:
		for k: Variant in v:
			_collect_chars(v[k], chars)
	elif v is Array:
		for x: Variant in v:
			_collect_chars(x, chars)


func _ready() -> void:
	GameEvents.event_emitted.connect(_on_event)


func toggle_stats_panel() -> void:
	_stats_panel.visible = not _stats_panel.visible


func is_stats_panel_open() -> bool:
	return _stats_panel.visible


func _build_overlay(panel: ColorRect, color: Color, children: Array) -> void:
	panel.color = color
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 8)
	for c: Control in children:
		if c is Label:
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
	var player := local_player()
	if player == null:
		return
	_skill_bar.refresh(world, player)
	if not _pause.visible and not _game_over.visible and not main_menu.visible:   # 暫停、結算、主選單時提示不倒數
		hints.update(delta, world, player, inventory_panel.visible)
	if _stats_panel.visible:
		_stats_panel.refresh(player)

	var ratio := player.hp / player.max_hp
	_hp_ghost = maxf(ratio, _hp_ghost - delta * HP_GHOST_SPEED)
	_set_bar(_hp, ratio, _hp_ghost)
	_hp.text.text = "%s / %s" % [UiKit.hp_text(player.hp), UiKit.hp_text(player.max_hp)]
	var inst := player.active_weapon()
	var other: Dictionary = player.weapon_slots[1 - player.active_slot]
	_weapon.text = "武器：" + (WeaponDropDefs.display_name(inst) if not inst.is_empty() else player.weapon.name)
	if not other.is_empty():
		_weapon.text += "　（X：%s）" % WeaponDropDefs.display_name(other)
	_weapon.add_theme_color_override(&"font_color", ItemDefs.RARITIES[inst.rarity].color if not inst.is_empty() else Color.WHITE)
	_gold.text = "金幣 %d" % world.gold
	var s := world.stats
	if DigEvent.enabled(world):   # 挖墳地圖（D6）：層數與難度
		_wave.text = "第 %d 層 · 難度 %d" % [world.floor_num, floori(world.difficulty())]
	else:
		_wave.text = "第 %d / %d 波" % [s.wave, world.spawner.total_waves()] if s.wave > 0 else "準備中"
	_kills.text = "擊殺 %d" % s.kills
	_time.text = UiKit.format_time(s.time)
	_update_boss(delta)
	_update_dig()


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


# 挖墳進度條：事件開始後、出口打開前顯示（客戶端讀快照同步的進度）
func _update_dig() -> void:
	var ev := world.event
	_dig_box.visible = DigEvent.enabled(world) and ev.state == DigEvent.ACTIVE
	if not _dig_box.visible:
		return
	_set_bar(_dig, ev.progress, ev.progress)
	_dig.text.text = "%d%%" % floori(ev.progress * 100.0)
	_dig_name.text = "挖墳進度" + ("　·　打倒 Boss 後怪物才會湧出" if not ev.horde else "　·　怪物越來越多")


func _set_bar(bar: Dictionary, value: float, ghost: float) -> void:
	bar.fill.size.x = bar.width * clampf(value, 0.0, 1.0)
	bar.ghost.size.x = bar.width * clampf(ghost, 0.0, 1.0)


func _on_event(name: String, p: Dictionary) -> void:
	var me := local_player()
	if me != null:
		run_log.me_id = me.id
	run_log.on_event(world, name, p)
	match name:
		"entity:damaged":
			var target: Entity = world.entities.get(p.target_id) if world else null
			if target == null:
				return
			if not Vision.entity_visible(world, local_player(), target):   # 視野外的傷害數字不顯示（D2）
				return
			var is_player := target is Player
			var big: bool = p.get("is_heavy", false) or p.get("is_crit", false)
			_floaters.spawn(target, UiKit.dmg_text(p.amount),&"player" if is_player else (&"crit" if big else &"dmg"))
			if target == local_player():
				_flash_vignette()
		"player:blocked":
			var player: Entity = world.entities.get(p.player_id) if world else null
			if player != null:
				_floaters.spawn(player, "招架！" if p.perfect else "格擋", &"crit" if p.perfect else &"dmg")
		"entity:healed":
			var target: Entity = world.entities.get(p.target_id) if world else null
			if target != null and p.amount > 0:
				_floaters.spawn(target, "+" + UiKit.dmg_text(p.amount), &"heal")
		"inventory:full":
			if _is_local(p.player_id):
				_floaters.spawn(local_player(), "背包滿了", &"dmg")
		"chest:denied":
			if _is_local(p.player_id):
				_floaters.spawn(local_player(), "金幣不足（需要 %d）" % p.price, &"dmg")
		"chest:opened":
			var item_name: String = ItemDefs.ITEMS[StringName(p.item)].name
			var rarity: Dictionary = ItemDefs.RARITIES[StringName(p.rarity)]
			if _is_local(p.player_id):
				_show_banner("開出：%s（%s）" % [item_name, rarity.name], false, rarity.color)
		"skill:onCooldown":
			if _is_local(p.get("player_id", 0)):
				_skill_bar.flash(p.key, true)
		"skill:used":
			if _is_local(p.get("player_id", 0)):
				_skill_bar.flash(p.key, false)
		"player:downed":
			if _is_local(p.player_id):
				_show_banner("你倒下了！%d 秒內等隊友救援" % roundi(Config.REVIVE.down_time), true)
			else:
				_show_banner("%s 倒下了！靠近按住 F 救援" % _tag_of(p.player_id), true)
		"player:revived":
			_show_banner(("你被救起了" if _is_local(p.player_id) else "%s 被救起了" % _tag_of(p.player_id)), false, UiKit.GOLD)
		"wave:started":
			_show_banner("BOSS 戰：" + BOSS_NAME if p.is_boss else "第 %d / %d 波" % [p.wave, p.total], p.is_boss)
		"boss:enraged":
			_show_banner("狂暴化！", true)
		"weapon:merged":
			if _is_local(p.player_id):
				var rarity: Dictionary = ItemDefs.RARITIES[StringName(p.rarity)]
				_show_banner("合成成功：%s %s" % [rarity.name, ItemDefs.ITEMS[StringName(p.base)].name], false, rarity.color)
		"weapon:merge_denied":
			if _is_local(p.player_id):
				_floaters.spawn(local_player(), "不能合成（要同種、同稀有度）", &"dmg")
		"item:added":
			if _is_local(p.player_id):   # 別人撿到的不跳（連線時事件全廣播）
				var item: Dictionary = ItemDefs.ITEMS[StringName(p.item)]
				_show_banner("獲得 %s\n%s" % [item.name, item.desc], false, ItemDefs.RARITIES[item.rarity].color)
		"player:died":
			# 多人時有人真的死亡但隊友還在：只提示（全員倒下才是結算，見 game:defeat）
			if world.players.size() > 1 and world.is_any_player_alive():
				_show_banner(("你陣亡了：隊友撿起你的屍體帶到下一層，打倒冤魂就能復活" if _is_local(p.player_id) else "%s 陣亡了：撿起屍體帶到下一層" % _tag_of(p.player_id)), true)
		"event:started":
			_show_banner("開始挖墳！先打倒 Boss，之後怪物會越來越多", true)
		"event:horde":   # Boss 倒下的下一步（同時有 boss:reward，橫幅合在這裡）
			if p.get("after_boss", false):
				_show_banner("擊敗 %s！掉落獎勵\n怪物開始湧出，越來越多" % BOSS_NAME, true)
		"event:exit_open":
			_show_banner("墓穴挖開了：全員走進去前往下一層", false, UiKit.GOLD)
		"floor:started":
			_show_banner("第 %d 層（基礎難度 %d）" % [p.floor, p.difficulty], false, UiKit.GOLD)
		"ghost:spawned":
			_show_banner("%s 的冤魂出現了：打倒就能復活" % _tag_of(p.player_id), true)
		"game:defeat":
			var s: Dictionary = p.stats
			_set_game_over("你倒下了" if world.players.size() <= 1 else "全員倒下", ("撐到第 %d 層" % s.get("floor", 1) if DigEvent.enabled(world) else "撐到第 %d 波" % s.wave) + " · 擊殺 %d · 時間 %s" % [s.kills, UiKit.format_time(s.time)], false)
			_game_over_delay = GAME_OVER_DELAY
		"game:victory":
			var s: Dictionary = p.stats
			_set_game_over("勝利！", "擊敗 %s · 擊殺 %d · 通關時間 %s" % [BOSS_NAME, s.kills, UiKit.format_time(s.time)], true)
			_game_over.visible = true
		"game:paused":
			show_menu(p.paused)
		"audio:muted":
			_mute.text = "靜音（M）" if p.muted else ""
		"game:restart":
			_game_over_delay = -1.0
			_game_over.visible = false
			_pause.visible = false
			_hp_ghost = 1.0
			_boss_ghost = 1.0
			_skill_bar.reset()
			_floaters.clear()


# 事件的 player_id 是實體 id
func _is_local(player_id: int) -> bool:
	var me := local_player()
	return me != null and me.id == player_id


func _tag_of(player_id: int) -> String:
	var peers: Array = world.players.keys()
	peers.sort()
	for i in peers.size():
		if world.players[peers[i]].id == player_id:
			return "P%d" % (i + 1)
	return "隊友"


func _set_game_over(title: String, stats: String, victory: bool) -> void:
	_game_over_title.text = title
	_game_over_title.add_theme_color_override(&"font_color", UiKit.GOLD if victory else UiKit.ALERT)
	_game_over_stats.text = stats
	_game_over_log.text = run_log.summary_text()
	_game_over.color = Color(40 / 255.0, 30 / 255.0, 0, 0.5) if victory else Color(40 / 255.0, 0, 0, 0.55)


# 網頁版 @keyframes banner：0~15% 由 1.3 倍縮回並淡入，75% 後淡出
func _show_banner(text: String, alert: bool, color := Color.WHITE) -> void:
	_banner.text = text
	_banner.add_theme_color_override(&"font_color", UiKit.ALERT if alert else color)
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
