# 本機輸入：把 InputMap 動作轉成 InputCmd（螢幕方向轉世界方向、滑鼠投射到地面、鎖存本步按下）
class_name InputCollector
extends Node

# 動作名稱 -> 預設按鍵（Key 或 MouseButton）；在程式中註冊，headless 檢查也能用
const ACTIONS := {
	&"move_up": KEY_W, &"move_down": KEY_S, &"move_left": KEY_A, &"move_right": KEY_D,
	&"attack": MOUSE_BUTTON_LEFT, &"special": MOUSE_BUTTON_RIGHT, &"roll": KEY_SHIFT, &"jump": KEY_SPACE, &"run": KEY_CTRL,
	&"slot_1": KEY_1, &"slot_2": KEY_2, &"slot_3": KEY_3, &"slot_4": KEY_4, &"slot_5": KEY_5,
	&"interact": KEY_F,
	&"pause": KEY_ESCAPE, &"mute": KEY_M, &"restart": KEY_R,
	&"stats_panel": KEY_TAB,
	&"swap_weapon": KEY_X, &"debug_hitbox": KEY_F2, &"debug_speed": KEY_F3,
	&"debug_item": KEY_F4, &"debug_clear_items": KEY_F5,
}
const MOUSE_ACTIONS: Array[StringName] = [&"attack", &"special"]

var camera_rig: CameraRig
var auto_move := Vector2.ZERO   # 測試用：螢幕方向的固定移動輸入（--auto-move）
var auto_attack := false        # 測試用：一直按住左鍵（--auto-attack）
var auto_special := false       # 測試用：開場按一次右鍵，之後每 AUTO_SPECIAL_INTERVAL 秒再按一次（--auto-special）
const AUTO_SPECIAL_INTERVAL := 5.1   # 比法杖的特殊技冷卻（5 秒）長；劍盾的格擋要按住（v0.41.0），這裡只按一下不會舉盾
var _auto_special_steps := 0
var auto_interact := false      # 測試用：一直按住 F（--auto-interact）
var enabled := true             # 關掉時（大廳、輸入框打字中）送出空輸入
var mouse_captured := false     # 背包開著（D3）：滑鼠只給背包用，不攻擊、不格擋、瞄準點不動；WASD 照常
var spectate := 0               # 陣亡後觀戰的隊友 peer id（main.gd 設定），跟著每筆輸入送給房主（InputCmd.spectate）
var _inv_ops: Array = []        # 背包介面送出的操作，下一筆輸入帶走

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
		if not mouse_captured and not _mouse_over_button():
			_latched |= InputCmd.BTN_ATTACK
	elif event.is_action_pressed(&"special"):
		if not mouse_captured and not _mouse_over_button():
			_latched |= InputCmd.BTN_SPECIAL
	elif event.is_action_pressed(&"roll"):
		_latched |= InputCmd.BTN_ROLL
	elif event.is_action_pressed(&"jump"):
		_latched |= InputCmd.BTN_JUMP
	elif event.is_action_pressed(&"run"):
		_latched |= InputCmd.BTN_RUN
	elif event.is_action_pressed(&"swap_weapon"):
		_latched |= InputCmd.BTN_SWAP_WEAPON
	elif event is InputEventMouseButton and event.pressed and not mouse_captured \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_latched |= InputCmd.BTN_SWAP_WEAPON   # 滑鼠滾輪也能切換武器（D4，兩把之間切換，上下都一樣）
	else:
		for i in InputCmd.SLOT_COUNT:
			if event.is_action_pressed(StringName("slot_%d" % (i + 1))):
				_latched |= InputCmd.slot_bit(i)


# 滑鼠在遊戲中的按鈕上（武器測試場的按鈕列）：點按鈕不算攻擊（左鍵在介面之前就收到）
func _mouse_over_button() -> bool:
	return get_viewport().gui_get_hovered_control() is BaseButton


# 背包介面的操作（InputCmd.OP_*），隨下一筆輸入送出
func queue_inventory_op(op: Array) -> void:
	_inv_ops.append(op)


func build_cmd(tick: int) -> InputCmd:
	var cmd := InputCmd.new()
	cmd.tick = tick
	cmd.aim = _aim
	cmd.spectate = spectate
	if not enabled:
		return cmd
	var screen := Input.get_vector(&"move_left", &"move_right", &"move_down", &"move_up")
	if auto_move != Vector2.ZERO:
		screen = auto_move
	cmd.move = (camera_rig.screen_right * screen.x + camera_rig.screen_forward * screen.y).limit_length(1.0)

	var ground: Variant = camera_rig.screen_to_ground(get_viewport().get_mouse_position())
	if ground != null and not mouse_captured:
		_aim = Vector2(ground.x, ground.z)
	cmd.aim = _aim

	cmd.buttons = _latched
	cmd.inv_ops = _inv_ops.duplicate()
	var over_button := _mouse_over_button()
	if auto_attack or (Input.is_action_pressed(&"attack") and not mouse_captured and not over_button):
		cmd.buttons |= InputCmd.BTN_ATTACK
	if Input.is_action_pressed(&"special") and not mouse_captured and not over_button:
		cmd.buttons |= InputCmd.BTN_SPECIAL_HELD
	if auto_special:
		if _auto_special_steps % roundi(AUTO_SPECIAL_INTERVAL / Config.FIXED_DT) == 0:
			cmd.buttons |= InputCmd.BTN_SPECIAL
		_auto_special_steps += 1
	if auto_interact or Input.is_action_pressed(&"interact"):
		cmd.buttons |= InputCmd.BTN_INTERACT
	return cmd


# 模擬步實際執行後呼叫
func consume_latched() -> void:
	_latched = 0
	_inv_ops.clear()
