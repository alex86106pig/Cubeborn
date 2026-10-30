# 膨脹屍（第 1 層）：慢慢走近，burst.trigger_distance 內停下脹大（swell，霸體，不會被打斷）→ 自爆死亡
# 被打死的話 burst.death_delay 秒後照樣炸。爆炸擋不住，玩家與其他怪都炸得到（引進殭屍群可以清一片），
# 炸完原地留下腐氣（GroundZones，hits_all：玩家與怪都會受持續傷害）。自爆的不給靈魂（不是被玩家打死的）
class_name Bloater
extends Enemy

var has_burst := false


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	var states := Enemy.base_states()
	states[&"chase"] = Chase.new()
	states[&"swell"] = Swell.new()
	states[&"dead"] = BloaterDead.new()
	super(p_world, p_type, at, mul, states)


func _anim_extra(a: Dictionary) -> void:
	if has_burst:
		a["burst"] = true


func _can_jump() -> bool:
	return fsm.is_in(&"chase")


# 脹大中是霸體：照樣扣血，但不進受擊硬直（一定會炸）
func _on_damaged(amount: float, source_id: int) -> void:
	suppress_stagger = suppress_stagger or fsm.is_in(&"swell")
	super(amount, source_id)


# 爆炸：半徑內的玩家與其他怪都受傷（不分隊伍），擋不住；接著留下腐氣
func burst() -> void:
	if has_burst:
		return
	has_burst = true
	var b: Dictionary = def.burst
	var hit := {
		"damage": b.damage * damage_mul, "knockback": b.knockback, "origin": pos, "is_heavy": true, "blockable": false,
		"band": Vector2(ground_height - Config.HEIGHT.reach_below, ground_height + Config.HEIGHT.explosion_height), "color": b.color,
	}
	world.record_hitbox({"shape": {"shape": &"circle", "radius": b.radius}, "origin": pos, "facing": facing, "band": hit.band, "team": &"all"})
	var targets: Array[Entity] = []
	targets.append_array(world.player_list)
	targets.append_array(world.enemies)
	for t in targets:
		if t == self or t.is_dead or t.pos.distance_to(pos) > b.radius + t.radius:
			continue
		Combat.apply_damage(world, self, t, hit)
	world.emit_event("sfx:cue", {"cue": "explosion", "pos": pos})
	world.emit_event("fx:explosion", {"pos": pos, "height": ground_height, "radius": b.radius, "color": b.color})
	var g: Dictionary = def.gas
	GroundZones.add(world, {
		"pos": pos, "radius": g.radius, "duration": g.duration, "owner_id": id, "color": g.color,
		"damage_per_sec": g.damage_per_sec * damage_mul, "damage_type": &"poison", "hits_all": true, "visual": &"gas",
	})


class Chase:
	func update(e: Bloater, dt: float, fsm: StateMachine) -> void:
		var target: Entity = e.nearest_target()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		if e.pos.distance_to(target.pos) <= e.def.burst.trigger_distance:
			fsm.change(&"swell")
			return
		var aim := e.steer_point(target.pos)
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), e.def.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed


# 脹大 swell_time 秒（站定）→ 自爆：先炸再死（自己不算被炸死，不給靈魂）
class Swell:
	func enter(e: Bloater, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO

	func update(e: Bloater, _dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		if fsm.time >= e.def.burst.swell_time:
			e.no_souls = true
			e.burst()
			e.die(e.id)


# 死亡：被打死的還沒炸 → death_delay 秒後炸；屍體留到腐氣散掉（腐氣的傷害來源是自己）
class BloaterDead:
	func enter(e: Bloater, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO

	func update(e: Bloater, _dt: float, fsm: StateMachine) -> void:
		if not e.has_burst and not e.no_death_effect and not e.world.is_over and fsm.time >= e.def.burst.death_delay:
			e.burst()
		if fsm.time >= e.def.corpse_time:
			e.remove()
