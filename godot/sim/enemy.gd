# 敵人基底（照搬網頁版 Enemy.js）：數值套用（屬性 + 波次倍率來源 &"wave"）、共用狀態（爬出 / 受擊 / 死亡）
# v0.17.0 起沒有接觸傷害（設計方向：每種怪物都靠自己的招式攻擊，見 sim/hitbox.gd）
# 子類別把自己的狀態合併進 base_states()，並指定 main_state（爬出與受擊結束後回到哪個狀態）
# 姿勢由畫面層依 anim 計算；這裡只記錄狀態名稱、經過秒數與少量動畫參數
class_name Enemy
extends Entity

var def: Dictionary
var type: StringName
var speed: float:   # 移速屬性的捷徑（基礎值含個體隨機差異，波次倍率是 &"wave" 來源）
	get:
		return stats.value(&"move_speed")
var main_state: StringName = &"chase"
var fsm: StateMachine
var anim: Dictionary = {}
var _cd_names: Array[String] = []   # 移除時要 reset 的 CD（enemy<id>.<名稱>）
# 尋路與跳躍（D1，只在權威端；見 sim/nav.gd）
var _nav_timer := 0.0
var _path := PackedVector2Array()   # 空 = 看得到目標，直接走過去
var _jump_windup := 0.0


# mul：波次倍率 { hp, damage, speed }
func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary, states: Dictionary) -> void:
	var d: Dictionary = EnemyDefs.ENEMIES[p_type]
	super(p_world, p_type, &"enemy", d.radius, d.max_hp, d.mass)
	def = d
	type = p_type
	var variance: float = d.speed_variance
	stats.set_base(&"move_speed", d.move_speed * p_world.rng.randf_range(1.0 - variance, 1.0 + variance))
	stats.set_base(&"knockback_taken", d.get("knockback_mul", 1.0))
	stats.set_source(&"wave", [
		[&"max_hp", Stats.MUL, mul.hp], [&"damage", Stats.MUL, mul.damage], [&"move_speed", Stats.MUL, mul.speed],
	])
	hp = max_hp
	pos = at
	height = p_world.terrain.ground_at(at)
	var target := nearest_player()
	if target != null:
		facing = MathUtil.angle_to(pos, target.pos)
	fsm = StateMachine.new(self, states, &"spawn")
	_update_anim()


func is_boss() -> bool:
	return false


func is_spawning() -> bool:
	return fsm.is_in(&"spawn")


func cd(name: String) -> String:
	if not name in _cd_names:
		_cd_names.append(name)
	return "enemy%d.%s" % [id, name]


# 由 World.add_entity 在取得 id 之後呼叫（CD key 需要 id）
func on_added() -> void:
	pass


func nearest_player() -> Player:
	var best: Player = null
	var best_d := INF
	for p: Player in world.players.values():
		if not p.is_targetable():   # 倒地的玩家不追
			continue
		var d := p.pos.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = p
	return best


func update(dt: float) -> void:
	_nav_timer -= dt
	fsm.update(dt)
	_update_jump(dt)
	_update_anim()


# 往 target 走時下一步要朝向的點：看得到就是 target 本身，被牆或墓碑擋住就走路徑點（每 repath_interval 秒重新判斷）
func steer_point(target: Vector2) -> Vector2:
	var n: Dictionary = Config.NAV
	if _nav_timer <= 0.0:
		_nav_timer = n.repath_interval
		_path = PackedVector2Array() if world.nav.has_los(pos, target) else world.nav.find_path(pos, target)
		_on_nav_refresh(target)
	if _path.is_empty():
		return target
	var reach: float = n.waypoint_reach
	while _path.size() > 1 and pos.distance_squared_to(_path[0]) < reach * reach:
		_path.remove_at(0)
	return _path[0]


# 目前是否直接看得到目標（沒有在繞路）
func has_direct_path() -> bool:
	return _path.is_empty()


func _can_jump() -> bool:
	return true


# 子類別在重新判斷路線時順便更新自己的資料（例如弓手的射線）
func _on_nav_refresh(_target: Vector2) -> void:
	pass


# 跳上高台：站在地上往前走、前方的地面比腳下高（超過 step、不超過 climb_height）就先蹲 jump_windup 秒再起跳（同玩家的跳躍速度）
func _update_jump(dt: float) -> void:
	if _jump_windup > 0.0:
		velocity = Vector2.ZERO
		_jump_windup -= dt
		if _jump_windup <= 0.0 and not is_dead:
			vz = 4.0 * Config.JUMP.height / Config.JUMP.air_time
		return
	if is_dead or velocity == Vector2.ZERO or not is_grounded() or not _can_jump():
		return
	var ahead := pos + velocity.normalized() * (radius + Config.NAV.jump_lookahead)
	var rise := world.terrain.ground_at(ahead) - ground_height
	if rise > Config.HEIGHT.step and rise <= Config.NAV.climb_height:
		_jump_windup = Config.NAV.jump_windup
		velocity = Vector2.ZERO


func _update_anim() -> void:
	anim = {"state": fsm.current_name, "time": fsm.time}
	_anim_extra(anim)


# 子類別補上自己的動畫參數
func _anim_extra(_a: Dictionary) -> void:
	pass


func _on_damaged(_amount: int, _source_id: int) -> void:
	if not is_dead and not is_spawning() and fsm.states.has(&"hurt"):
		fsm.change(&"hurt")


func _on_died(_source_id: int) -> void:
	fsm.change(&"dead")
	world.on_enemy_died(self)


func remove() -> void:
	if world != null:
		for name in _cd_names:
			world.cooldowns.reset("enemy%d.%s" % [id, name])
	super()


func detach() -> void:
	super()
	fsm = null


# ───────── 共用狀態 ─────────

static func base_states() -> Dictionary:
	return {&"spawn": Spawn.new(), &"hurt": Hurt.new(), &"dead": Dead.new()}


class Spawn:
	func enter(e: Enemy, _data: Dictionary, _fsm: StateMachine) -> void:
		e.world.emit_event("sfx:cue", {"cue": "enemySpawn"})
		if e.def.has("spawn_shake"):
			e.world.emit_event("camera:shake", {"amount": e.def.spawn_shake, "duration": e.def.spawn_time})

	func update(e: Enemy, _dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		if fsm.time >= e.def.spawn_time:
			fsm.change(e.main_state)


class Hurt:
	func enter(e: Enemy, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO

	func update(e: Enemy, _dt: float, fsm: StateMachine) -> void:
		if fsm.time >= e.def.hurt_time:
			fsm.change(e.main_state)


# 終止狀態：倒下、沉入地面後移除（動畫在畫面層）
class Dead:
	func enter(e: Enemy, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO

	func update(e: Enemy, _dt: float, fsm: StateMachine) -> void:
		if fsm.time >= e.def.corpse_time:
			e.remove()
