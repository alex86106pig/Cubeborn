# 玩家：讀取 InputCmd、雙層狀態機（移動層 / 動作層）、武器、輸入緩衝、主動欄位與增益效果；照搬網頁版 Player.js
class_name Player
extends Entity

var peer_id := 0
var move_input := Vector2.ZERO
var aim_point := Vector2(0.0, 5.0)
var is_attack_held := false
var weapon: Dictionary = {}
var weapon_id: StringName = &""
var combo_step := 0
var combo_timer := 0.0
var buffered_action: Dictionary = {}   # { type: &"special" | &"slot", index?, time }；空 = 沒有緩衝
var slots := ActiveSlots.new(Config.PLAYER.slots)
var buffs: Dictionary = {}             # id -> { remaining, speed_mul?, trail_color? }
var forced_velocity := Vector2.ZERO
var has_forced_velocity := false
var locomotion: StateMachine
var action: StateMachine
# 畫面層算姿勢用的資料（15.5）：只放名稱與數值，連線時同步這份就能畫出同樣動作
var anim: Dictionary = {}

var _pressed := 0   # 本步按下的按鈕；讀過就清除，沒收到新輸入時不會重複觸發


func _init(p_world: World, p_peer_id: int) -> void:
	super(p_world, &"player", &"player", Config.PLAYER.radius, Config.PLAYER.max_hp, Config.PLAYER.mass)
	peer_id = p_peer_id
	locomotion = StateMachine.new(self, PlayerStates.locomotion_states(), &"idle")
	action = StateMachine.new(self, PlayerStates.action_states())
	equip_weapon(Config.PLAYER.start_weapon)
	_update_anim()


# 權威端不信任輸入：移動向量長度一律限制在 1 以內
func apply_cmd(cmd: InputCmd) -> void:
	move_input = cmd.move.limit_length(1.0)
	aim_point = cmd.aim
	is_attack_held = cmd.has(InputCmd.BTN_ATTACK)
	_pressed |= cmd.buttons


func equip_weapon(id: StringName) -> void:
	assert(WeaponDefs.WEAPONS.has(id), "Unknown weapon: %s" % id)
	weapon = WeaponDefs.WEAPONS[id]
	weapon_id = id
	combo_step = 0
	combo_timer = 0.0
	action.change(&"ready")


func add_buff(id: StringName, duration: float, mods: Dictionary) -> void:
	var buff := mods.duplicate()
	buff["remaining"] = duration
	buffs[id] = buff


func speed_mul() -> float:
	var mul := 1.0
	for buff: Dictionary in buffs.values():
		mul *= buff.get("speed_mul", 1.0)
	return mul


func update(dt: float) -> void:
	_tick_timers(dt)
	if is_dead:
		locomotion.update(dt)
		_update_anim()
		return

	_read_input()
	action.update(dt)

	var data := action.data
	if has_forced_velocity:
		velocity = forced_velocity
	else:
		velocity = move_input * (Config.PLAYER.move_speed * data.get("move_speed_mul", 1.0) * speed_mul())

	if not data.get("lock_facing", false):
		var target := MathUtil.angle_to(pos, aim_point)
		facing = MathUtil.turn_towards(facing, target, Config.PLAYER.turn_speed * dt)

	locomotion.update(dt)
	_update_anim()


func _tick_timers(dt: float) -> void:
	combo_timer = maxf(0.0, combo_timer - dt)
	for id: StringName in buffs.keys():
		buffs[id].remaining -= dt
		if buffs[id].remaining <= 0.0:
			buffs.erase(id)
	if not buffered_action.is_empty():
		buffered_action.time -= dt
		if buffered_action.time <= 0.0:
			buffered_action = {}


func _read_input() -> void:
	var buffer_time: float = Config.PLAYER.action_buffer_time
	if _pressed & InputCmd.BTN_SPECIAL:
		buffered_action = {"type": &"special", "time": buffer_time}
	for i in ActiveSlots.SLOT_COUNT:
		if _pressed & InputCmd.slot_bit(i):
			buffered_action = {"type": &"slot", "index": i, "time": buffer_time}
	_pressed = 0


# 目前的殘影顏色（最後加上的增益優先）；沒有則為 null
func trail_color() -> Variant:
	var color: Variant = null
	for buff: Dictionary in buffs.values():
		if buff.has("trail_color"):
			color = buff.trail_color
	return color


func _update_anim() -> void:
	var d := action.data
	var timed := d.has("phase_index")
	anim = {
		"loco": locomotion.current_name,
		"loco_time": locomotion.time,
		"action": action.current_name,
		"action_time": action.time,
		"behavior": d.def.behavior if timed else &"",
		"phase": PlayerStates.PHASES[d.phase_index] if timed and d.phase_index < PlayerStates.PHASES.size() else &"",
		"k": d.get("k", 0.0),
		"swing_dir": d.get("swing_dir", 1),
		"is_finisher": d.get("is_finisher", false),
		"trail_color": trail_color(),   # 疾跑殘影（特效里程碑再畫）
	}


func _on_damaged(amount: int, _source_id: int) -> void:
	if is_dead or amount <= 0:
		return
	invuln_timer = Config.PLAYER.invuln_time
	world.emit_event("camera:shake", {"amount": Config.PLAYER.hurt_shake, "duration": Config.PLAYER.hurt_shake_duration})
	# 特殊技期間有霸體，不會被打斷
	if not action.is_in(&"special"):
		action.change(&"stagger")


# 狀態機的 ctx 指回玩家，也要切斷
func detach() -> void:
	super()
	locomotion = null
	action = null


func _on_died(_source_id: int) -> void:
	action.change(&"ready")   # 讓進行中的動作執行 exit 清理
	has_forced_velocity = false
	locomotion.change(&"dead")
	world.emit_event("player:died", {"player_id": id})
