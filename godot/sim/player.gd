# 玩家：讀取 InputCmd、移動與轉向（雙層狀態機與武器在里程碑 2 加入）
class_name Player
extends Entity

var peer_id := 0
var move_input := Vector2.ZERO
var aim_point := Vector2(0.0, 5.0)


func _init(p_world: World, p_peer_id: int) -> void:
	super(p_world, &"player", &"player", Config.PLAYER.radius, Config.PLAYER.max_hp, Config.PLAYER.mass)
	peer_id = p_peer_id


# 權威端不信任輸入：移動向量長度一律限制在 1 以內
func apply_cmd(cmd: InputCmd) -> void:
	move_input = cmd.move.limit_length(1.0)
	aim_point = cmd.aim


func update(dt: float) -> void:
	if is_dead:
		return
	velocity = move_input * Config.PLAYER.move_speed
	var target := MathUtil.angle_to(pos, aim_point)
	facing = MathUtil.turn_towards(facing, target, Config.PLAYER.turn_speed * dt)
