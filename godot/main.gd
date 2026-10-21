# 組合根：建立 World、輸入、畫面與 HUD；固定步長主迴圈、命中停頓、暫停、重新開始
# 指令列參數（放在 -- 之後）：--seconds=S --screenshot=路徑 --auto-move=x,y（螢幕方向）
extends Node3D

const HUD_SCENE := preload("res://ui/hud.tscn")

var world := World.new()
var is_paused := false

var camera_rig := CameraRig.new()
var world_view := WorldView.new()
var arena_view := ArenaView.new()
var input_collector := InputCollector.new()

var _sim_accumulator := 0.0
var _stepped_this_tick := false
var _run_seconds := 0.0
var _screenshot_path := ""
var _elapsed := 0.0


func _ready() -> void:
	InputCollector.register_actions()
	_parse_args()
	add_child(camera_rig)
	add_child(world_view)
	add_child(arena_view)
	arena_view.build(world.arena_half_size)
	input_collector.camera_rig = camera_rig
	add_child(input_collector)
	add_child(HUD_SCENE.instantiate())
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


func local_player() -> Player:
	return world.players.get(World.HOST_PEER_ID)


func restart() -> void:
	world.reset(randi())
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
	# 命中停頓：真實時間照走，邏輯時間放慢到 5%，每步仍是 FIXED_DT（同網頁版）
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
	world_view.sync(world, alpha)
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
	elif event.is_action_pressed(&"debug_hitbox"):
		world_view.show_hitboxes = not world_view.show_hitboxes


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
	print("tick=%d player_pos=(%.2f, %.2f) facing=%.2f" % [world.tick, player.pos.x, player.pos.y, player.facing])
	if _screenshot_path != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_screenshot_path)
		print("screenshot: ", _screenshot_path)
	get_tree().quit()
