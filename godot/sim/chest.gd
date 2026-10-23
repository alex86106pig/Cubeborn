# 寶箱（D3）：地圖上的固定位置，靠近按 F、共用的錢夠就開；開出一個道具掉在地上（ItemPickup），稀有度依 LootDefs.CHESTS
# 不擋路、不能被打；開過的寶箱留在原地（畫面顯示打開的箱蓋）
class_name Chest
extends Entity

var tier: StringName = &"small"
var opened := false


func _init(p_world: World, p_tier: StringName, at: Vector2) -> void:
	super(p_world, &"chest", &"neutral", LootDefs.CHESTS[p_tier].radius, 1.0)
	tier = p_tier
	pos = at
	height = p_world.terrain.ground_at(at)


func price() -> int:
	return LootDefs.CHESTS[tier].price


func can_be_hit() -> bool:
	return false


func try_open(by: Player) -> bool:
	if opened:
		return false
	if world.gold < price():
		world.emit_event("chest:denied", {"chest_id": id, "player_id": by.id, "price": price()})
		world.emit_event("sfx:cue", {"cue": "denied"})
		return false
	world.gold -= price()
	opened = true
	var rarity := LootDefs.roll_rarity(tier, world.rng)
	var pool := LootDefs.drop_pool(rarity)
	var item_id: StringName = pool[world.rng.randi_range(0, pool.size() - 1)]
	var to_player := by.pos - pos
	var dir := to_player.normalized() if to_player.length() > 1e-3 else Vector2(0.0, 1.0)
	world.drop_item(item_id, pos + dir * LootDefs.DROP_DISTANCE)
	world.emit_event("chest:opened", {"chest_id": id, "player_id": by.id, "item": String(item_id), "rarity": String(rarity), "pos": pos})
	world.emit_event("sfx:cue", {"cue": "potion"})
	return true
