# 玩家雙層狀態機定義：移動層（位移）與動作層（攻擊、技能、硬直）；照搬網頁版 playerStates.js
# 只處理規則與時間；腿部、上半身姿勢在畫面層 view/animator.gd 依 player.anim 計算
class_name PlayerStates

const PHASES: Array[StringName] = [&"windup", &"active", &"recovery"]
const DIG_MASS := 1000.0   # 挖墳中的質量（D6）：碰撞分離時幾乎推不動


static func locomotion_states() -> Dictionary:
	return {&"idle": Idle.new(), &"move": Move.new(), &"downed": Dead.new(), &"dead": Dead.new()}


static func action_states() -> Dictionary:
	return {
		&"ready": Ready.new(),
		&"attack": TimedAction.new(&"attack"),
		&"special": TimedAction.new(&"special"),
		&"useItem": UseItem.new(),
		&"stagger": Stagger.new(),
		&"roll": Roll.new(),
		&"revive": Revive.new(),
		&"dig": Dig.new(),
	}


# 緩衝中的是翻滾：有充能就翻（回傳 true），沒有就提示冷卻並丟掉緩衝
static func try_roll(p: Player, fsm: StateMachine) -> bool:
	if p.buffered_action.get("type") != &"roll":
		return false
	p.buffered_action = {}
	if p.roll_charges > 0:
		fsm.change(&"roll")
		return true
	p.world.emit_event("skill:onCooldown", {"key": Player.ROLL_CD, "player_id": p.id})
	return false


# ───────── 移動層 ─────────

class Idle:
	func update(p: Player, _dt: float, fsm: StateMachine) -> void:
		if p.move_input.length_squared() > 0.01:
			fsm.change(&"move")


class Move:
	func update(p: Player, _dt: float, fsm: StateMachine) -> void:
		if p.move_input.length_squared() <= 0.01:
			fsm.change(&"idle")


# 終止狀態（dead）與倒地假死（downed，救起後回到 idle）：倒地動畫由畫面層依 locomotion 時間播放
class Dead:
	pass


# ───────── 動作層 ─────────

class Ready:
	func enter(_p: Player, data: Dictionary, _fsm: StateMachine) -> void:
		data.move_speed_mul = 1.0

	func update(p: Player, _dt: float, fsm: StateMachine) -> void:
		if PlayerStates.try_roll(p, fsm):
			return
		if p.is_interact_held:
			var target := p.find_revive_target()
			if target != null:
				fsm.change(&"revive", {"target_id": target.id})
				return
			if p.world.event.can_dig(p.world, p):
				fsm.change(&"dig")
				return
		var buffered := p.buffered_action
		if not buffered.is_empty():
			p.buffered_action = {}
			if buffered.type == &"special":
				if p.world.cooldowns.is_ready(p.cd("player.special")):
					fsm.change(&"special")
					return
				p.world.emit_event("skill:onCooldown", {"key": "player.special", "player_id": p.id})
			elif buffered.type == &"slot":
				if p.slots.can_use(p, buffered.index):
					fsm.change(&"useItem", {"index": buffered.index})
					return
				p.slots.notify_blocked(p, buffered.index)
		if p.is_attack_held:
			fsm.change(&"attack")


# 攻擊與特殊技共用的三段式動作狀態
class TimedAction:
	var kind: StringName

	func _init(p_kind: StringName) -> void:
		kind = p_kind

	func enter(p: Player, data: Dictionary, _fsm: StateMachine) -> void:
		var def: Dictionary = p.weapon[kind]
		data.def = def
		data.behavior = WeaponBehaviors.BEHAVIORS[def.behavior]
		data.durations = [def.windup, def.active, def.recovery]
		data.phase_index = 0
		data.phase_time = 0.0
		data.k = 0.0
		data.move_speed_mul = def.get("move_speed_mul", 1.0)
		data.lock_facing = false
		if kind == &"special":
			p.world.cooldowns.start(p.cd("player.special"), def.cooldown * p.stats.value(&"cooldown"))
			p.world.emit_event("skill:used", {"key": "player.special", "player_id": p.id})
		data.behavior.enter(p, def, data)
		# 攻速只影響普攻三個階段（在武器行為調整終結技後搖之後套用）；特殊技由冷卻限制
		if kind == &"attack":
			var attack_speed := p.stats.value(&"attack_speed")
			for i in data.durations.size():
				data.durations[i] /= attack_speed
		_enter_phase(p, data, 0)

	func update(p: Player, dt: float, fsm: StateMachine) -> void:
		var d := fsm.data
		d.phase_time += dt
		while d.phase_index < PHASES.size() and d.phase_time >= d.durations[d.phase_index]:
			d.phase_time -= d.durations[d.phase_index]
			d.phase_index += 1
			if d.phase_index < PHASES.size():
				_enter_phase(p, d, d.phase_index)
		if d.phase_index >= PHASES.size():
			fsm.change(&"ready")
			return
		var name := PHASES[d.phase_index]
		# 普攻的前搖與後搖可以用翻滾取消（揮下去的 active 不行，按鍵留在緩衝等 active 結束）
		# 有 roll_cancel 的特殊技（格擋）任何階段都能用翻滾結束
		var roll_cancelable: bool = (kind == &"attack" and name != &"active") or d.def.get("roll_cancel", false)
		if roll_cancelable and p.buffered_action.get("type") == &"roll" and p.roll_charges > 0:
			PlayerStates.try_roll(p, fsm)
			return
		# 有 press_cancel 的特殊技（格擋）：維持中再按一次同一個鍵就提前進入收招
		if d.def.get("press_cancel", false) and name != &"recovery" and p.buffered_action.get("type") == &"special":
			p.buffered_action = {}
			d.phase_index = PHASES.find(&"recovery")
			d.phase_time = 0.0
			_enter_phase(p, d, d.phase_index)
			return
		var duration: float = d.durations[d.phase_index]
		d.k = d.phase_time / duration if duration > 0.0 else 1.0
		d.behavior.update(p, d.def, d, name, d.k, dt)
		# 後搖可被緩衝中的技能取消，手感較跟手
		if name == &"recovery" and not p.buffered_action.is_empty():
			fsm.change(&"ready")

	func exit(p: Player, fsm: StateMachine) -> void:
		fsm.data.behavior.exit(p, fsm.data.def, fsm.data)

	# 進入階段：呼叫武器行為；進入 active 時播放武器資料指定的音效（終結技優先用 sfx_heavy）
	func _enter_phase(p: Player, data: Dictionary, index: int) -> void:
		var name := PHASES[index]
		data.behavior.phase(p, data.def, data, name)
		if name == &"active":
			var sfx: String = data.def.get("sfx_heavy", data.def.sfx) if data.get("is_finisher", false) else data.def.get("sfx", "")
			if sfx != "":
				p.world.emit_event("sfx:cue", {"cue": sfx})


class UseItem:
	func enter(p: Player, data: Dictionary, _fsm: StateMachine) -> void:
		data.move_speed_mul = 1.0
		p.slots.use(p, data.index)

	func update(_p: Player, _dt: float, fsm: StateMachine) -> void:
		if fsm.time >= Config.PLAYER.use_item_time:
			fsm.change(&"ready")


# 翻滾：往移動方向（沒按方向就往面對方向）固定時間位移，開始後一段時間無敵；速度隨移速屬性放大
class Roll:
	func enter(p: Player, data: Dictionary, _fsm: StateMachine) -> void:
		var dir := p.move_input.normalized() if p.move_input.length_squared() > 0.01 else MathUtil.dir_from_angle(p.facing)
		data.dir = dir
		data.lock_facing = true
		data.move_speed_mul = 1.0
		p.facing = atan2(dir.x, dir.y)
		p.forced_velocity = dir * p.roll_speed()
		p.has_forced_velocity = true
		p.dodge_timer = Config.ROLL.invuln_time
		p.consume_roll_charge()
		p.world.emit_event("skill:used", {"key": Player.ROLL_CD, "player_id": p.id})
		p.world.emit_event("sfx:cue", {"cue": Config.ROLL.sfx})

	func update(_p: Player, _dt: float, fsm: StateMachine) -> void:
		if fsm.time >= Config.ROLL.duration - 1e-6:
			fsm.change(&"ready")

	func exit(p: Player, _fsm: StateMachine) -> void:
		p.has_forced_velocity = false


# 救援（C4）：按住互動鍵、倒地隊友在範圍內就一直救；期間不能移動、攻擊、用技能（按鍵不留緩衝）
# 救援進度由 World._update_downed 依 revive_target_id 累積
class Revive:
	func enter(p: Player, data: Dictionary, _fsm: StateMachine) -> void:
		data.move_speed_mul = 0.0
		data.lock_facing = true
		p.revive_target_id = data.target_id
		_face(p, data.target_id)

	func update(p: Player, _dt: float, fsm: StateMachine) -> void:
		p.buffered_action = {}
		var target := p.world.entities.get(fsm.data.target_id) as Player
		var in_range := target != null and target.is_downed and target.pos.distance_to(p.pos) <= Config.REVIVE.range
		if not p.is_interact_held or not in_range:
			fsm.change(&"ready")

	func exit(p: Player, _fsm: StateMachine) -> void:
		p.revive_target_id = 0

	func _face(p: Player, target_id: int) -> void:
		var t: Entity = p.world.entities.get(target_id)
		if t != null:
			p.facing = MathUtil.angle_to(p.pos, t.pos)


# 挖墳（D6）：在挖墳點附近按住互動鍵；期間不能移動、攻擊、用技能（同救援），被打不中斷（Player._on_damaged、stun）
# 進度由 DigEvent 依 is_digging() 累積；放開、離開範圍、出口打開就結束
class Dig:
	func enter(p: Player, data: Dictionary, _fsm: StateMachine) -> void:
		data.move_speed_mul = 0.0
		data.lock_facing = true
		p.facing = MathUtil.angle_to(p.pos, p.world.event.point)
		# 被打不中斷：挖墳中不會被擊退、也不會被怪擠走（不然會被推出挖墳範圍）
		p.set_stat_source(&"digging", [[&"knockback_taken", Stats.MUL, 0.0]])
		data.mass = p.mass
		p.mass = PlayerStates.DIG_MASS

	func update(p: Player, _dt: float, fsm: StateMachine) -> void:
		p.buffered_action = {}
		if not p.is_interact_held or not p.world.event.can_dig(p.world, p):
			fsm.change(&"ready")

	func exit(p: Player, fsm: StateMachine) -> void:
		p.remove_stat_source(&"digging")
		p.mass = fsm.data.mass


class Stagger:
	func enter(_p: Player, data: Dictionary, _fsm: StateMachine) -> void:
		data.move_speed_mul = Config.PLAYER.stagger_move_speed_mul

	func update(_p: Player, _dt: float, fsm: StateMachine) -> void:
		if fsm.time >= Config.PLAYER.stagger_time:
			fsm.change(&"ready")
