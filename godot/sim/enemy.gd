# 敵人基底（照搬網頁版 Enemy.js）：數值套用（含波次倍率）、共用狀態（爬出 / 受擊 / 死亡）、接觸傷害
# 子類別把自己的狀態合併進 base_states()，並指定 main_state（爬出與受擊結束後回到哪個狀態）
# 姿勢由畫面層依 anim 計算；這裡只記錄狀態名稱、經過秒數與少量動畫參數
class_name Enemy
extends Entity

var def: Dictionary
var type: StringName
var damage_mul := 1.0
var speed := 0.0
var main_state: StringName = &"chase"
var contact_timer := 0.0
var fsm: StateMachine
var anim: Dictionary = {}
var _cd_names: Array[String] = []   # 移除時要 reset 的 CD（enemy<id>.<名稱>）


# mul：波次倍率 { hp, damage, speed }
func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary, states: Dictionary) -> void:
	var d: Dictionary = EnemyDefs.ENEMIES[p_type]
	super(p_world, p_type, &"enemy", d.radius, roundf(d.max_hp * mul.hp), d.mass)
	def = d
	type = p_type
	damage_mul = mul.damage
	var variance: float = d.speed_variance
	speed = d.move_speed * mul.speed * p_world.rng.randf_range(1.0 - variance, 1.0 + variance)
	knockback_mul = d.get("knockback_mul", 1.0)
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
	contact_timer = maxf(0.0, contact_timer - dt)
	fsm.update(dt)
	_update_anim()


# 接觸傷害：貼到玩家時每隔一段時間造成傷害，回傳是否命中
func try_contact_damage(target: Player) -> bool:
	if contact_timer > 0.0 or target == null or target.is_dead:
		return false
	if pos.distance_to(target.pos) > radius + target.radius + def.contact_reach:
		return false
	var hit := Combat.apply_damage(world, self, target, {
		"damage": def.contact_damage * damage_mul, "knockback": def.contact_knockback,
	})
	if hit:
		contact_timer = def.contact_interval
	return hit


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
