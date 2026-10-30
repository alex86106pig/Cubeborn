# 祭壇 / 石棺（D3，程式裡沿用 Chest / chest；v0.45 起改名）：地圖上的固定位置，靠近按 F、共用的靈魂夠就開；
# 開出一個遺物（Relic，Build 改版第 6 步）：每個玩家各自 N 選 1，稀有度依 LootDefs.CHESTS
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


# 這位玩家開要多少（G1 撬鎖工具看開的人）；by 為 null 時是原價
func price_for(by: Player) -> int:
	return price() if by == null else roundi(price() * by.stats.value(&"chest_price"))


func can_be_hit() -> bool:
	return false


func try_open(by: Player) -> bool:
	if opened:
		return false
	var cost := price_for(by)
	if world.souls < cost:
		world.emit_event("chest:denied", {"chest_id": id, "player_id": by.id, "price": cost})
		world.emit_event("sfx:cue", {"cue": "denied", "pos": pos})
		return false
	world.souls -= cost
	opened = true
	var to_player := by.pos - pos
	var dir := to_player.normalized() if to_player.length() > 1e-3 else Vector2(0.0, 1.0)
	var relic := world.drop_relic(tier, pos + dir * LootDefs.DROP_DISTANCE)
	world.emit_event("chest:opened", {"chest_id": id, "player_id": by.id, "relic_id": relic.id, "pos": pos})
	world.emit_event("sfx:cue", {"cue": "potion", "pos": pos})
	return true
