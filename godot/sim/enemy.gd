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
		if p.is_dead:
			continue
		var d := p.pos.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = p
	return best


func update(dt: float) -> void:
	fsm.update(dt)
	_update_anim()


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
