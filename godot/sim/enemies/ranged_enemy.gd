# 遠程小怪（照搬網頁版 RangedEnemy.js）：與玩家保持距離並橫移，冷卻好時停下瞄準（有預備動作）後發射投射物；沒有近身攻擊
class_name RangedEnemy
extends Enemy

var strafe_dir := 1.0
var strafe_timer := 0.0


func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary) -> void:
	var states := Enemy.base_states()
	states[&"kite"] = Kite.new()
	states[&"aim"] = Aim.new()
	super(p_world, p_type, at, mul, states)
	main_state = &"kite"


# 剛出生時給一點延遲才第一次射擊
func on_added() -> void:
	var delay: Array = def.first_fire_delay
	world.cooldowns.start(cd("fire"), world.rng.randf_range(delay[0], delay[1]))


func fire() -> void:
	world.emit_event("sfx:cue", {"cue": "arrowShot"})
	var dir := MathUtil.dir_from_angle(facing)
	world.spawn_projectile(Projectile.new(world, {
		"owner": self, "pos": pos + dir * def.projectile_offset, "direction": dir,
		"speed": def.projectile_speed, "range": def.projectile_range, "radius": def.projectile_radius,
		"damage": def.projectile_damage * damage_mul, "knockback": def.projectile_knockback,
		"color": def.projectile_color, "visual": &"arrow", "altitude": height + Config.HEIGHT.arrow_altitude,
		"blockable": def.projectile_blockable,
	}))


class Kite:
	func update(e: RangedEnemy, dt: float, _fsm: StateMachine) -> void:
		var target := e.nearest_player()
		if target == null:
			e.velocity = Vector2.ZERO
			return
		var to_target := MathUtil.angle_to(e.pos, target.pos)
		var dist := e.pos.distance_to(target.pos)
		var range_: Array = e.def.preferred_range
		var rng := e.world.rng

		e.strafe_timer -= dt
		if e.strafe_timer <= 0.0:
			e.strafe_dir = -1.0 if rng.randf() < 0.5 else 1.0
			var t: Array = e.def.strafe_time
			e.strafe_timer = rng.randf_range(t[0], t[1])

		var move_angle := to_target
		var speed_mul := 1.0
		if dist > range_[1]:
			move_angle = to_target
		elif dist < range_[0]:
			move_angle = to_target + PI
		else:
			move_angle = to_target + PI / 2.0 * e.strafe_dir
			speed_mul = e.def.strafe_speed_mul
		e.velocity = MathUtil.dir_from_angle(move_angle) * (e.speed * speed_mul)
		e.facing = MathUtil.turn_towards(e.facing, to_target, e.def.turn_speed * dt)

		var key := e.cd("fire")
		if dist <= range_[1] + e.def.fire_reach and e.world.cooldowns.is_ready(key):
			var j: Array = e.def.fire_interval_jitter
			e.world.cooldowns.start(key, e.def.fire_interval * rng.randf_range(j[0], j[1]))
			e.fsm.change(&"aim")


class Aim:
	func enter(e: RangedEnemy, _data: Dictionary, _fsm: StateMachine) -> void:
		e.world.emit_event("sfx:cue", {"cue": "bowDraw"})
		e.velocity = Vector2.ZERO

	func update(e: RangedEnemy, dt: float, fsm: StateMachine) -> void:
		var k: float = fsm.time / e.def.aim_time
		# 前 75% 追蹤玩家，之後鎖定方向，讓玩家有閃避的機會
		var target := e.nearest_player()
		if k < e.def.aim_track and target != null:
			var turn: float = e.def.turn_speed * e.def.aim_turn_mul * dt
			e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), turn)
		if k >= 1.0:
			e.fire()
			fsm.change(&"kite")
