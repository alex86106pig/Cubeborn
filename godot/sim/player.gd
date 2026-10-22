# 玩家：讀取 InputCmd、雙層狀態機（移動層 / 動作層）、武器、輸入緩衝、主動欄位與增益效果；照搬網頁版 Player.js
class_name Player
extends Entity

const ROLL_CD := "player.roll"
const PARRY_ANIM_TIME := 0.2

var peer_id := 0
var move_input := Vector2.ZERO
var aim_point := Vector2(0.0, 5.0)
var is_attack_held := false
var weapon: Dictionary = {}
var weapon_id: StringName = &""
var combo_step := 0
var combo_timer := 0.0
var buffered_action: Dictionary = {}   # { type: &"special" | &"slot" | &"roll", index?, time }；空 = 沒有緩衝
var slots := ActiveSlots.new(Config.PLAYER.slots)
var buffs: Dictionary = {}             # id -> { remaining, stats?（屬性加成，見 sim/stats.gd）, trail_color? }
var roll_charges := 0                  # 目前可用的翻滾次數（上限為 roll_charges 屬性）
var dodge_timer := 0.0                 # 翻滾無敵剩餘秒數
var block_time := -1.0                 # 格擋開始後經過的秒數；< 0 = 沒有在格擋（weapon_behaviors 的 ShieldBlock）
var pending_parry := false             # 本步完美格擋，下一步開頭執行盾反
var parry_timer := 0.0                 # 盾反動作剩餘秒數（畫面用）
var forced_velocity := Vector2.ZERO
var has_forced_velocity := false
var locomotion: StateMachine
var action: StateMachine
# 畫面層算姿勢用的資料（15.5）：只放名稱與數值，連線時同步這份就能畫出同樣動作
var anim: Dictionary = {}

var _pressed := 0   # 本步按下的按鈕；讀過就清除，沒收到新輸入時不會重複觸發


func _init(p_world: World, p_peer_id: int) -> void:
	super(p_world, &"player", &"player", Config.PLAYER.radius, Config.PLAYER.max_hp, Config.PLAYER.mass)
	stats.set_base(&"move_speed", Config.PLAYER.move_speed)
	peer_id = p_peer_id
	locomotion = StateMachine.new(self, PlayerStates.locomotion_states(), &"idle")
	action = StateMachine.new(self, PlayerStates.action_states())
	equip_weapon(Config.PLAYER.start_weapon)
	roll_charges = roll_max()
	_update_anim()


# 跳躍：站在地面上隨時可以跳（攻擊、翻滾中也行），受擊硬直與倒地時不行；只有一段跳
func try_jump() -> bool:
	if is_dead or not is_grounded() or action.is_in(&"stagger"):
		return false
	vz = 4.0 * Config.JUMP.height / Config.JUMP.air_time
	return true


# 由 Combat.apply_damage 對能格擋的攻擊呼叫：格擋中、攻擊來自正前方 block_arc 內就擋下（不扣血、自己被推退一點）
# from 是攻擊來的位置（近戰為攻擊者、投射物為飛來的方向）；按下格擋後 perfect_window 內擋下 = 完美格擋，下一步盾反
func try_block(from: Vector2, hit: Dictionary) -> bool:
	if block_time < 0.0:
		return false
	var def: Dictionary = weapon.special
	var to_source := from - pos
	if to_source.length_squared() > 1e-6:
		if absf(angle_difference(facing, atan2(to_source.x, to_source.y))) > def.block_arc / 2.0:
			return false
		# 攻擊可以指定擋下時的推退比例（Boss 衝鋒 100%），沒指定就用盾的 block_knockback_mul（30%）
		var push_mul: float = hit.get("block_knockback_mul", def.block_knockback_mul)
		knockback -= to_source.normalized() * (hit.get("knockback", 0.0) * push_mul / mass)
	var perfect: bool = block_time <= def.perfect_window + 1e-6
	world.emit_event("player:blocked", {"player_id": id, "perfect": perfect})
	world.emit_event("sfx:cue", {"cue": def.sfx_parry if perfect else def.sfx_block})
	if perfect:
		pending_parry = true
	return true


# 盾反：對前方扇形造成傷害（隨攻擊力），然後結束格擋
func _parry() -> void:
	var pr: Dictionary = weapon.special.parry
	Hitbox.strike(world, self, pos, facing, {"shape": &"sector", "range": pr.range, "arc": pr.arc}, {
		"damage": pr.damage * damage_mul, "knockback": pr.knockback, "hit_stop": pr.hit_stop,
		"shake": pr.shake, "is_heavy": true, "blockable": false,
	})
	parry_timer = PARRY_ANIM_TIME
	action.change(&"ready")


func roll_max() -> int:
	return int(stats.value(&"roll_charges"))


func is_dodging() -> bool:
	return dodge_timer > 1e-6


# 翻滾的位移速度：基礎距離 ÷ 時間，再依移速屬性相對基礎移速等比放大（動作中的走路減速不算）
func roll_speed() -> float:
	return Config.ROLL.distance / Config.ROLL.duration * stats.value(&"move_speed") / Config.PLAYER.move_speed


# 充能：回充中（ROLL_CD 計時）結束就加 1 次，還沒滿就接著回充下一次；上限提高時立刻補 1 次
func _tick_roll_charges() -> void:
	var max_charges := roll_max()
	roll_charges = mini(roll_charges, max_charges)
	if roll_charges < max_charges and world.cooldowns.is_ready(ROLL_CD):
		roll_charges += 1
		if roll_charges < max_charges:
			world.cooldowns.start(ROLL_CD, roll_cooldown())


func roll_cooldown() -> float:
	return Config.ROLL.cooldown * stats.value(&"roll_cooldown")


# 消耗 1 次充能；沒有在回充時開始回充
func consume_roll_charge() -> void:
	roll_charges -= 1
	if world.cooldowns.is_ready(ROLL_CD):
		world.cooldowns.start(ROLL_CD, roll_cooldown())


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


# 增益：同一個 id 再加一次會重新計時；mods.stats 以增益 id 為來源套上屬性加成，到期時移除
func add_buff(id: StringName, duration: float, mods: Dictionary) -> void:
	var buff := mods.duplicate()
	buff["remaining"] = duration
	buffs[id] = buff
	if buff.has("stats"):
		set_stat_source(id, buff.stats)


func update(dt: float) -> void:
	_tick_timers(dt)
	if is_dead:
		locomotion.update(dt)
		_update_anim()
		return

	_read_input()
	if pending_parry:
		pending_parry = false
		if block_time >= 0.0:
			_parry()
	action.update(dt)

	var data := action.data
	if has_forced_velocity:
		velocity = forced_velocity
	else:
		velocity = move_input * (stats.value(&"move_speed") * data.get("move_speed_mul", 1.0))

	if not data.get("lock_facing", false):
		var target := MathUtil.angle_to(pos, aim_point)
		facing = MathUtil.turn_towards(facing, target, Config.PLAYER.turn_speed * dt)

	locomotion.update(dt)
	_update_anim()


func _tick_timers(dt: float) -> void:
	combo_timer = maxf(0.0, combo_timer - dt)
	dodge_timer = maxf(0.0, dodge_timer - dt)
	parry_timer = maxf(0.0, parry_timer - dt)
	_tick_roll_charges()
	for id: StringName in buffs.keys():
		buffs[id].remaining -= dt
		if buffs[id].remaining <= 0.0:
			if buffs[id].has("stats"):
				remove_stat_source(id)
			buffs.erase(id)
	if not buffered_action.is_empty():
		buffered_action.time -= dt
		if buffered_action.time <= 0.0:
			buffered_action = {}


func _read_input() -> void:
	var buffer_time: float = Config.PLAYER.action_buffer_time
	if _pressed & InputCmd.BTN_SPECIAL:
		buffered_action = {"type": &"special", "time": buffer_time}
	if _pressed & InputCmd.BTN_ROLL:
		buffered_action = {"type": &"roll", "time": buffer_time}
	if _pressed & InputCmd.BTN_JUMP:
		try_jump()
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
		"airborne": not is_grounded(),
		"blocking": block_time >= 0.0,
		"parry": parry_timer / PARRY_ANIM_TIME,   # 1 → 0（盾反剛發動到結束）
		"vz": vz,
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
