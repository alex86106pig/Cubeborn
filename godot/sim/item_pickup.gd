# 掉在地上的道具（D3）：寶箱開出來或從背包丟出來；靠近按 F 撿起放進背包（多人時先撿先得），背包放不下就留在地上
# 畫面是一個依稀有度上色的發光物
class_name ItemPickup
extends Entity

const RADIUS := 0.4

var item_id: StringName


func _init(p_world: World, p_item_id: StringName, at: Vector2) -> void:
	super(p_world, &"pickup", &"neutral", RADIUS, 1.0)
	item_id = p_item_id
	pos = at
	height = p_world.terrain.ground_at(at)


func can_be_hit() -> bool:
	return false


func rarity() -> StringName:
	return ItemDefs.ITEMS[item_id].rarity
