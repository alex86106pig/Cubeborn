# 掉在地上的道具或武器（D3 / D4）：寶箱開出來、殺怪掉的武器、從背包丟出來；靠近按 F 撿起（多人時先撿先得），放不下就留在地上
# 畫面是一個依稀有度上色的發光物
class_name ItemPickup
extends Entity

const RADIUS := 0.4

var item_id: StringName          # 道具 id；武器時是武器種類（ItemDefs 的武器 id）
var weapon: Dictionary = {}      # 武器實例（WeaponDropDefs）；空 = 一般道具


func _init(p_world: World, p_item_id: StringName, at: Vector2, p_weapon: Dictionary = {}) -> void:
	super(p_world, &"pickup", &"neutral", RADIUS, 1.0)
	item_id = p_item_id
	weapon = p_weapon
	pos = at
	height = p_world.terrain.ground_at(at)


func can_be_hit() -> bool:
	return false


func is_weapon() -> bool:
	return not weapon.is_empty()


func rarity() -> StringName:
	return weapon.rarity if is_weapon() else ItemDefs.ITEMS[item_id].rarity


func display_name() -> String:
	return WeaponDropDefs.display_name(weapon) if is_weapon() else ItemDefs.ITEMS[item_id].name
