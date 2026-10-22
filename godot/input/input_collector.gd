# 本機輸入：把 InputMap 動作轉成 InputCmd（螢幕方向轉世界方向、滑鼠投射到地面、鎖存本步按下）
class_name InputCollector
extends Node

# 動作名稱 -> 預設按鍵（Key 或 MouseButton）；在程式中註冊，headless 檢查也能用
const ACTIONS := {
	&"move_up": KEY_W, &"move_down": KEY_S, &"move_left": KEY_A, &"move_right": KEY_D,
	&"attack": MOUSE_BUTTON_LEFT, &"special": MOUSE_BUTTON_RIGHT, &"roll": KEY_SHIFT, &"jump": KEY_SPACE,
	&"slot_1": KEY_1, &"slot_2": KEY_2, &"slot_3": KEY_3, &"slot_4": KEY_4, &"slot_5": KEY_5,
	&"interact": KEY_F,
	&"pause": KEY_ESCAPE, &"mute": KEY_M, &"restart": KEY_R,
	&"stats_panel": KEY_TAB,
	&"debug_weapon": KEY_F1, &"debug_hitbox": KEY_F2, &"debug_speed": KEY_F3,
	&"debug_item": KEY_F4, &"debug_clear_items": KEY_F5,
}
const MOUSE_ACTIONS: Array[StringName] = [&"attack", &"special"]

var camera_rig: CameraRig
var auto_move := Vector2.ZERO   # 測試用：螢幕方向的固定移動輸入（--auto-move）
var auto_attack := false        # 測試用：一直按住左鍵（--auto-attack）
var auto_special := false       # 測試用：每步都按右鍵，冷卻好就放特殊技（--auto-special）
var auto_interact := false      # 測試用：一直按住 F（--auto-interact）
var enabled := true             # 關掉時（大廳、輸入框打字中）送出空輸入

var _latched := 0               # 兩次模擬步之間按過的按鈕，步驟執行後才清除
var _aim := Vector2(0.0, 5.0)


static func register_actions() -> void:
	for action: StringName in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev: InputEvent
		if action in MOUSE_ACTIONS:
			var mb := InputEventMouseButton.new()
			mb.button_index = ACTIONS[action]
			ev = mb
		else:
			var key := InputEventKey.new()
			key.physical_keycode = ACTIONS[action]
			ev = key
		InputMap.action_add_event(action, ev)


func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(&"attack"):
		_latched |= InputCmd.BTN_ATTACK
	elif event.is_action_pressed(&"special"):
		_latched |= InputCmd.BTN_SPECIAL
	elif event.is_action_pressed(&"roll"):
		_latched |= InputCmd.BTN_ROLL
	elif event.is_action_pressed(&"jump"):
		_latched |= InputCmd.BTN_JUMP
	elif event.is_action_pressed(&"debug_weapon"):
		_latched |= InputCmd.BTN_SWAP_WEAPON
	else:
		for i in InputCmd.SLOT_COUNT:
			if event.is_action_pressed(StringName("slot_%d" % (i + 1))):
				_latched |= InputCmd.slot_bit(i)


func build_cmd(tick: int) -> InputCmd:
	var cmd := InputCmd.new()
	cmd.tick = tick
	cmd.aim = _aim
	if not enabled:
		return cmd
	var screen := Input.get_vector(&"move_left", &"move_right", &"move_down", &"move_up")
	if auto_move != Vector2.ZERO:
		screen = auto_move
	cmd.move = (camera_rig.screen_right * screen.x + camera_rig.screen_forward * screen.y).limit_length(1.0)

	var ground: Variant = camera_rig.screen_to_ground(get_viewport().get_mouse_position())
	if ground != null:
		_aim = Vector2(ground.x, ground.z)
	cmd.aim = _aim

	cmd.buttons = _latched
	if auto_attack or Input.is_action_pressed(&"attack"):
		cmd.buttons |= InputCmd.BTN_ATTACK
	if auto_special:
		cmd.buttons |= InputCmd.BTN_SPECIAL
	if auto_interact or Input.is_action_pressed(&"interact"):
		cmd.buttons |= InputCmd.BTN_INTERACT
	return cmd


# 模擬步實際執行後呼叫
func consume_latched() -> void:
	_latched = 0
