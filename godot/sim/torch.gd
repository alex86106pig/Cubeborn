# 插在地上的火把（F8 火把傭兵）：這一關都不熄，照亮的範圍全隊都看得到（Vision.lights）；換層時跟其他地上的東西一起清掉
# 不擋路、不能被打；只在權威端產生，客戶端看快照
class_name Torch
extends Entity

const RADIUS := 0.2


func _init(p_world: World, at: Vector2, p_owner_id: int = 0) -> void:
	super(p_world, &"torch", &"neutral", RADIUS, 1.0)
	pos = at
	height = p_world.terrain.ground_at(at)
	owner_id = p_owner_id


var owner_id := 0


func can_be_hit() -> bool:
	return false
