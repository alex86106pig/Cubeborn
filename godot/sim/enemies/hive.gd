# 蟲巢（第 3 層，數值 Claude 暫定）：不會動的一團卵囊。醒著時每 hatch.interval 秒孵 hatch.count 隻屍甲蟲（自己孵的同時最多 max_alive 隻）；
# 目標走進 acid.trigger_distance 內就抽搐、鼓起酸泡 windup 秒 → 往周圍 acid.radius 噴酸（擋不住，先走開就噴不到）；
# 被打破時再孵 hatch.on_death 隻。孵出來的不給靈魂、不掉東西（同召喚詞條）。不會硬直、推不動
class_name Hive
extends Enemy

var _hatch_timer := 0.0


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	var states := Enemy.base_states()
	states.erase(&"hurt")
	states[&"brood"] = Brood.new()
	states[&"spit"] = Spit.new()
	super(p_world, p_type, at, mul, states)
	main_state = &"brood"
	_hatch_timer = def.hatch.first
	fixed = true


# 一直固定不動（互推時只推開別人、不積分）：怪群醒來時 dormant 的 setter 會把 fixed 放開，每步設回來
func update(dt: float) -> void:
	fixed = true
	super(dt)


func hatched_alive() -> int:
	var alive := 0
	for e in world.enemies:
		if e is Enemy and (e as Enemy).summoner_id == id and not e.is_dead:
			alive += 1
	return alive


# 在身邊 hatch.spread 的一圈上孵 count 隻
func hatch(count: int) -> void:
	var h: Dictionary = def.hatch
	var nav := world.nav_for(EnemyDefs.ENEMIES[h.type].radius)
	for i in count:
		var a := world.rng.randf() * TAU
		var at := nav.nearest_walkable(pos + Vector2(sin(a), cos(a)) * h.spread)
		var bug := world.spawner.spawn_at(world, h.type, at)
		bug.summoner_id = id
		bug.no_souls = true
		bug.wave_member = wave_member


# 孵化的倒數：孵卵與噴酸時都在跑（狀態機的時間，狂暴、緩速照比例）
func _tick_hatch(dt: float) -> void:
	_hatch_timer -= dt
	if _hatch_timer > 0.0:
		return
	var h: Dictionary = def.hatch
	_hatch_timer = h.interval
	hatch(mini(h.count, h.max_alive - hatched_alive()))


func _on_died(source_id: int) -> void:
	super(source_id)
	if world.is_authority and not no_death_effect and not world.is_over:
		hatch(def.hatch.on_death)


class Brood:
	func update(e: Hive, dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e._tick_hatch(dt)
		var target: Entity = e.nearest_target()
		if target != null and e.world.cooldowns.is_ready(e.cd("acid")) and e.pos.distance_to(target.pos) <= e.def.acid.trigger_distance:
			fsm.change(&"spit")


# 抽搐、鼓起酸泡 windup 秒 → 以自己為中心噴一圈酸
class Spit:
	func enter(e: Hive, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e.world.emit_event("sfx:cue", {"cue": e.def.acid.sfx_windup, "pos": e.pos})

	func update(e: Hive, dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		e._tick_hatch(dt)
		var a: Dictionary = e.def.acid
		if fsm.time < a.windup:
			return
		Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"circle", "radius": a.radius}, {
			"damage": a.damage * e.damage_mul, "knockback": a.knockback, "origin": e.pos, "blockable": false, "color": a.color,
		})
		e.world.emit_event("fx:explosion", {"pos": e.pos, "height": e.ground_height, "radius": a.radius, "color": a.color})
		e.world.emit_event("sfx:cue", {"cue": a.sfx_burst, "pos": e.pos})
		e.world.cooldowns.start(e.cd("acid"), e.cd_time(a.cooldown))
		fsm.change(&"brood")
