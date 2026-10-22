# 組合根：建立 World、輸入、畫面、HUD 與音效；固定步長主迴圈、通關慢動作、暫停、靜音、重新開始、離開遊戲
# 指令列參數（放在 -- 之後）：--seconds=S --screenshot=路徑 --auto-move=x,y（螢幕方向）
#   --auto-attack（一直按住左鍵）--weapon=staff（開場武器）--wave=N（直接從第 N 波開始）--player-hp=N（開場血量）
#   --items=id,id（開場放進身上的道具，見 defs/item_defs.gd），後三者除錯用
extends Node3D

const HUD_SCENE := preload("res://ui/hud.tscn")

var world := World.new()
var is_paused := false

var camera_rig := CameraRig.new()
var world_view := WorldView.new()
var arena_view := ArenaView.new()
var input_collector := InputCollector.new()
var sound := Sound.new()
var hud: HUD

var _sim_accumulator := 0.0
var _stepped_this_tick := false
var _run_seconds := 0.0
var _screenshot_path := ""
var _elapsed := 0.0
var _start_weapon: StringName = &""
var _start_wave := 0
var _start_hp := 0.0
var _start_items: Array[StringName] = []
var _debug_item_index := 0


func _ready() -> void:
	InputCollector.register_actions()
	_parse_args()
	add_child(camera_rig)
	add_child(world_view)
	add_child(arena_view)
	arena_view.build(world.arena_half_size, world.terrain)
	input_collector.camera_rig = camera_rig
	add_child(input_collector)
	hud = HUD_SCENE.instantiate()
	hud.setup(world, camera_rig.camera)
	hud.quit_requested.connect(get_tree().quit)
	add_child(hud)
	sound.setup(world)
	add_child(sound)
	_emit_muted()
	GameEvents.event_emitted.connect(_on_event)
	restart()


func _exit_tree() -> void:
	world.clear()   # 切斷實體與 World 的循環參照


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			_run_seconds = arg.get_slice("=", 1).to_float()
		elif arg.begins_with("--screenshot="):
			_screenshot_path = arg.get_slice("=", 1)
		elif arg.begins_with("--auto-move="):
			var xy := arg.get_slice("=", 1).split(",")
			input_collector.auto_move = Vector2(xy[0].to_float(), xy[1].to_float())
		elif arg == "--auto-attack":
			input_collector.auto_attack = true
		elif arg.begins_with("--weapon="):
			_start_weapon = StringName(arg.get_slice("=", 1))
		elif arg.begins_with("--wave="):
			_start_wave = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--player-hp="):
			_start_hp = arg.get_slice("=", 1).to_float()
		elif arg.begins_with("--items="):
			for item in arg.get_slice("=", 1).split(",", false):
				if ItemDefs.ITEMS.has(StringName(item)):
					_start_items.append(StringName(item))
				else:
					push_warning("--items: 沒有這個道具 %s" % item)


func local_player() -> Player:
	return world.players.get(World.HOST_PEER_ID)


func restart() -> void:
	world.reset(randi())
	if _start_weapon != &"":
		local_player().equip_weapon(_start_weapon)
	if _start_wave > 1:
		world.spawner.wave = _start_wave - 1
	for item in _start_items:
		local_player().add_item(item)
	if _start_hp > 0.0:
		local_player().hp = _start_hp
	_sim_accumulator = 0.0
	input_collector.consume_latched()
	GameEvents.emit_all(world.events)
	set_paused(false)
	camera_rig.follow(_player_view_position(1.0), 0.0, true)


# 只在遊戲進行中可以暫停（死亡、通關畫面已經停在結算）
func set_paused(paused: bool) -> void:
	var player := local_player()
	if paused and (world.is_over or player == null or player.is_dead):
		return
	if is_paused == paused:
		return
	is_paused = paused
	GameEvents.event_emitted.emit("game:paused", {"name": "game:paused", "paused": paused})


func _physics_process(_delta: float) -> void:
	_stepped_this_tick = false
	if is_paused:
		input_collector.consume_latched()   # 暫停中的點擊與按鍵不留到繼續之後
		return
	# 通關慢動作：真實時間照走，邏輯時間放慢到 5%，每步仍是 FIXED_DT（v0.18.3 起只剩打倒 Boss 時用；一般命中改成畫面層的命中定格）
	_sim_accumulator += Config.FIXED_DT * world.consume_hit_stop(Config.FIXED_DT)
	while _sim_accumulator >= Config.FIXED_DT - 1e-9:
		_sim_accumulator -= Config.FIXED_DT
		var cmd := input_collector.build_cmd(world.tick + 1)
		world.step({World.HOST_PEER_ID: cmd}, Config.FIXED_DT)
		input_collector.consume_latched()
		GameEvents.emit_all(world.events)
		_stepped_this_tick = true


func _process(delta: float) -> void:
	var alpha := Engine.get_physics_interpolation_fraction() if _stepped_this_tick else 1.0
	world_view.sync(world, alpha, delta)
	camera_rig.follow(_player_view_position(alpha), delta)
	_check_auto_quit(delta)


func _player_view_position(alpha: float) -> Vector3:
	var player := local_player()
	if player == null:
		return Vector3.ZERO
	var p := player.prev_pos.lerp(player.pos, alpha)
	return Vector3(p.x, 0.0, p.y)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(&"pause"):
		set_paused(not is_paused)
	elif event.is_action_pressed(&"restart"):
		var player := local_player()
		if world.is_over or player == null or player.is_dead:
			restart()
	elif event.is_action_pressed(&"mute"):
		sound.toggle_mute()
		_emit_muted()
	elif event.is_action_pressed(&"debug_hitbox"):
		world_view.show_hitboxes = not world_view.show_hitboxes
	elif event.is_action_pressed(&"debug_weapon"):
		# 除錯用武器切換（非正式系統，單機才有）；正式的切換在階段二要改成 InputCmd
		var player := local_player()
		if player != null and not player.is_dead:
			player.equip_weapon(&"staff" if player.weapon_id == &"swordShield" else &"swordShield")
	elif event.is_action_pressed(&"stats_panel"):
		hud.toggle_stats_panel()
	elif event.is_action_pressed(&"debug_speed"):
		toggle_debug_speed()
	elif event.is_action_pressed(&"debug_item"):
		debug_add_next_item()
	elif event.is_action_pressed(&"debug_clear_items"):
		var player := local_player()
		if player != null:
			player.clear_items()


# 除錯用（非正式系統，單機才有）：依道具清單順序，每按一次 F4 放一個道具進身上（循環）
func debug_add_next_item() -> void:
	var player := local_player()
	if player == null or player.is_dead:
		return
	var ids := ItemDefs.item_ids()
	var before := world.events.size()   # 上一步的事件已經送過，只送這次新增的
	player.add_item(ids[_debug_item_index % ids.size()])
	_debug_item_index += 1
	GameEvents.emit_all(world.events.slice(before))


# 除錯用（非正式系統，單機才有）：切換玩家「移速 +50%」，驗證屬性系統用
func toggle_debug_speed() -> void:
	var player := local_player()
	if player == null:
		return
	if player.stats.has_source(&"debug"):
		player.remove_stat_source(&"debug")
	else:
		player.set_stat_source(&"debug", [[&"move_speed", Stats.PCT, Config.DEBUG.speed_bonus]])


# 靜音狀態給 HUD 顯示（開場時也送一次：上次關遊戲前可能是靜音）
func _emit_muted() -> void:
	GameEvents.event_emitted.emit("audio:muted", {"name": "audio:muted", "muted": sound.is_muted})


func _on_event(name: String, payload: Dictionary) -> void:
	if name == "camera:shake":
		camera_rig.shake(payload.amount, payload.duration)
	world_view.on_event(name, payload)


# 切到其他視窗時自動暫停，避免回來時已經被打死
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _run_seconds <= 0.0:
		set_paused(true)


func _check_auto_quit(delta: float) -> void:
	if _run_seconds <= 0.0:
		return
	_elapsed += delta
	if _elapsed < _run_seconds:
		return
	_run_seconds = 0.0
	var player := local_player()
	print("tick=%d player_pos=(%.2f, %.2f) hp=%.0f weapon=%s action=%s wave=%d enemies=%d projectiles=%d kills=%d" % [
		world.tick, player.pos.x, player.pos.y, player.hp, player.weapon_id, player.action.current_name,
		world.stats.wave, world.enemies.size(), world.projectiles.size(), world.stats.kills])
	var boss: Enemy = world.entities.get(world.boss_id)
	if boss != null:
		print("boss state=%s hp=%.0f" % [boss.fsm.current_name if boss.fsm else &"", boss.hp])
	if _screenshot_path != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_screenshot_path)
		print("screenshot: ", _screenshot_path)
	get_tree().quit()
