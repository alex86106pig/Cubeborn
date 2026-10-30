# 鍛造祭壇（Build 改版第 8 步，2026-10-30 許家慶決定）：武器只能在這裡合成（Loadout.merge 看 World.near_forge）
# 每層照 map 的 forge_count 隨機放（World._place_chests，放在祭壇 / 石棺之後）；不擋路、不能被打、可以一直用
# 按 F 打開背包（事件 forge:opened，本機玩家的畫面打開 Tab）；合成免費
class_name Forge
extends Entity


func _init(p_world: World, at: Vector2) -> void:
	super(p_world, &"forge", &"neutral", LootDefs.FORGE.radius, 1.0)
	pos = at
	height = p_world.terrain.ground_at(at)


func can_be_hit() -> bool:
	return false
