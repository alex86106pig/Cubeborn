# 冤魂的操作（只在權威端）：每步替冤魂（Player.is_ghost）產生一筆 InputCmd，像玩家一樣用死者的武器、右鍵、技能（袋子照常觸發）
# 追最近的玩家：近戰貼上去打、遠程保持距離邊退邊射；魔力夠就放技能與右鍵；玩家出招時偶爾翻滾；不喝藥水、不撿東西
class_name GhostBrain
extends RefCounted

const DT := Config.FIXED_DT
const T := EventDefs.GHOST_BRAIN

var _path := PackedVector2Array()
var _path_goal := Vector2.INF
var _path_timer := 0.0
var _roll_timer := 0.0
var _block_timer := 0.0
var _strafe := 1.0
var _strafe_timer := 0.0


func decide(g: Player, dt: float) -> InputCmd:
	var cmd := InputCmd.new()
	cmd.aim = g.pos + MathUtil.dir_from_angle(g.facing) * 5.0
	_roll_timer -= dt
	_strafe_timer -= dt
	if _strafe_timer <= 0.0:
		_strafe_timer = T.strafe_switch
		_strafe = -1.0 if g.world.rng.randf() < 0.5 else 1.0
	var e := _nearest_target(g)
	if e == null:
		return cmd
	cmd.aim = e.pos
	var ranged: bool = g.weapon.get("type", &"melee") == &"ranged"
	var reach := _reach(g)
	var d := g.pos.distance_to(e.pos) - e.radius
	if ranged:
		var want: float = minf(reach * T.ranged_keep, T.ranged_max_keep)
		if d > reach * 0.9:
			_walk(g, cmd, e.pos)
		elif d < want - T.ranged_band:
			_walk(g, cmd, g.pos + (g.pos - e.pos).normalized() * 3.0)   # 太近：往後退著打
		else:
			cmd.move = (e.pos - g.pos).normalized().orthogonal() * _strafe   # 繞著走，不站樁
		cmd.buttons |= InputCmd.BTN_ATTACK
	else:
		if d > reach * T.melee_keep:
			_walk(g, cmd, e.pos)
		if d <= reach + 0.3:
			cmd.buttons |= InputCmd.BTN_ATTACK
	if _defend(g, cmd, e, d):
		return cmd
	_cast(g, cmd, d)
	return cmd


# 敵對陣營裡最近、打得到的（玩家；骷髏僕從也算）
func _nearest_target(g: Player) -> Entity:
	var best: Entity = null
	var best_d: float = T.sight * T.sight
	for e in Combat.hostiles_of(g.world, g.team):
		var dd := e.pos.distance_squared_to(g.pos)
		if dd < best_d:
			best_d = dd
			best = e
	return best


# 普攻打得到多遠：招式的 range（近戰揮砍、遠程射程）× 武器的範圍倍率
func _reach(g: Player) -> float:
	var atk: Dictionary = g.weapon.get("attack", {})
	return float(atk.get("range", 2.0)) * g.weapon_range_mul()


# 對方在出招、離得近：有盾（盾擊，推盾期間格擋）照機率推盾，block_time 秒內不再試；否則照機率往側面翻滾；有動作回傳 true
func _defend(g: Player, cmd: InputCmd, e: Entity, d: float) -> bool:
	_block_timer -= DT
	var attacking := e is Player and (e as Player).action.current_name != &"ready" and not (e as Player).is_dead
	if not attacking or d > T.defend_range:
		return false
	var special: Dictionary = g.weapon.get("special", {})
	if special.get("behavior", &"") == &"shieldBash":
		if _block_timer > 0.0 or not g.has_mana(g.mana_cost_of(special)):
			return false
		_block_timer = T.block_time
		if g.world.rng.randf() < T.block_chance:
			cmd.aim = e.pos
			cmd.buttons |= InputCmd.BTN_SPECIAL
			cmd.buttons &= ~InputCmd.BTN_ATTACK
			return true
		return false
	if _roll_timer <= 0.0 and g.roll_charges > 0:
		_roll_timer = T.roll_cooldown
		if g.world.rng.randf() < T.roll_chance:
			cmd.move = (e.pos - g.pos).normalized().orthogonal() * _strafe
			cmd.buttons |= InputCmd.BTN_ROLL
			return true
	return false


# 數字鍵的技能：放得出來、目標在技能範圍內就放（一步一個）；再看耗魔的右鍵（按住類、鐵鏟的鏟拋不用）
func _cast(g: Player, cmd: InputCmd, d: float) -> void:
	for i in ActiveSlots.GEM_SLOTS:
		var slot: Variant = g.slots.get_slot(g, i)
		if slot == null or not slot.def.has("mana") or not g.slots.can_use(g, i):
			continue
		if d <= _skill_range(g, slot.def):
			cmd.buttons |= InputCmd.slot_bit(i)
			return
	var special: Dictionary = g.weapon.get("special", {})
	if special.get("hold", false) or special.get("behavior", &"") in T.skip_specials:
		return
	if special.has("mana") and g.has_mana(g.mana_cost_of(special)) and d <= _skill_range(g, special):
		cmd.buttons |= InputCmd.BTN_SPECIAL


# 技能打得到多遠：資料的 range / distance / radius 的 90%，都沒有就用普攻距離
func _skill_range(g: Player, def: Dictionary) -> float:
	for k in ["range", "distance", "radius"]:
		if def.has(k):
			return float(def[k]) * 0.9
	return _reach(g) + 1.0


# 走向 goal：看得到就直走，被牆擋就照尋路走；前面高一個台階就跳（同怪物的規則）
func _walk(g: Player, cmd: InputCmd, goal: Vector2) -> void:
	_path_timer -= DT
	var nav := g.world.nav_for(g.radius)
	if _path_timer <= 0.0 or goal.distance_to(_path_goal) > 1.0:
		_path_timer = T.path_refresh
		_path_goal = goal
		_path = PackedVector2Array() if nav.has_los(g.pos, goal) else nav.find_path(g.pos, goal)
	while _path.size() > 1 and g.pos.distance_to(_path[0]) < 0.6:
		_path.remove_at(0)
	var to := goal if _path.is_empty() else _path[0]
	cmd.move = (to - g.pos).normalized()
	var ahead := g.pos + cmd.move * (g.radius + Config.NAV.jump_lookahead)
	var rise := g.world.terrain.ground_at(ahead) - g.ground_height
	if g.is_grounded() and rise > Config.HEIGHT.step and rise <= Config.NAV.climb_height:
		cmd.buttons |= InputCmd.BTN_JUMP
