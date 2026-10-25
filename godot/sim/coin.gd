# 地上的金幣（v0.45，局外貨幣）：殺怪極低機率掉 1 枚（LootDefs.RUN_COINS），活著的玩家走近自動撿（World._collect_coins）
# 不擋路、不能被打；換層時和其他地上的東西一起清掉
class_name Coin
extends Entity

const RADIUS := 0.3


func _init(p_world: World, at: Vector2) -> void:
	super(p_world, &"coin", &"neutral", RADIUS, 1.0)
	pos = at
	height = p_world.terrain.ground_at(at)


func can_be_hit() -> bool:
	return false
