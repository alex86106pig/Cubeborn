# 骷髏僕從（G6 亡者大軍）：玩家方的骷髏戰士。隊伍是 &"player"：打怪、不打玩家（Combat.hostiles_of 看隊伍），怪的攻擊打得到它
# 追 seek_range 內最近的怪，沒有就跟著召喚者；life 秒後自己倒下。怪物的 AI 不會主動追它（只追玩家）
# 放在 world.enemies 照常更新、碰撞、進快照（種類 &"minion"）；不給靈魂、不算擊殺（World.on_enemy_died）
class_name Minion
extends MeleeEnemy

var owner_id := 0      # 召喚者（玩家實體 id）
var life := 0.0


func _init(p_world: World, at: Vector2, summoner: Player) -> void:
	super(p_world, &"minion", at, WaveDefs.NO_SCALING.duplicate())
	team = &"player"
	owner_id = summoner.id
	no_souls = true
	life = def.life
	fsm.states[&"chase"] = MinionChase.new()


func update(dt: float) -> void:
	super(dt)
	if is_dead:
		return
	life -= dt
	if life <= 0.0:
		die(0)


# 範圍內最近、還活著的怪（休眠的怪群不主動去打）
func nearest_target() -> Entity:
	var best: Entity = null
	var best_d: float = def.seek_range * def.seek_range
	for e in world.enemies:
		if e.team == team or e.is_dead or (e as Enemy).dormant:
			continue
		var d := e.pos.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = e
	return best


class MinionChase:
	func update(e: Minion, dt: float, fsm: StateMachine) -> void:
		var target := e.nearest_target()
		if target == null:
			var owner: Entity = e.world.entities.get(e.owner_id)
			if owner == null or owner.pos.distance_to(e.pos) <= e.def.follow_distance:
				e.velocity = Vector2.ZERO
				return
			target = owner
		elif e.pos.distance_to(target.pos) <= e.def.swing.trigger_distance and e.world.cooldowns.is_ready(e.cd("swing")):
			fsm.change(&"swing")
			return
		var aim := e.steer_point(target.pos)
		e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), e.def.turn_speed * dt)
		e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed
