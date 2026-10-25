# 角色視野（D2）：判斷某位玩家看不看得到一個位置 / 實體。只影響畫面（每個人只畫自己看得到的），模擬照常進行
# 使用者決定（2026-10-23）：前方 120°、18 單位；身邊 4 單位不管方向都看得到；牆擋視線（墓碑、高台不擋）；地形照常看得到（視野外變暗）
# 視野外完全看不見：怪物、怪物的攻擊與特效、隊友（多人時不共享視野）；自己和自己發出的投射物一律看得到
class_name Vision


static func point_visible(world: World, viewer: Player, p: Vector2, target_radius: float = 0.0) -> bool:
	return in_view_cone(viewer, p, target_radius) and not line_blocked(world, viewer, p)


# 只看距離與角度（不管牆）：畫面層每幀都判斷，牆擋視線（line_blocked）比較貴，分批更新（D5）
static func in_view_cone(viewer: Player, p: Vector2, target_radius: float = 0.0) -> bool:
	var v: Dictionary = Config.VISION
	var d := p - viewer.pos
	var dist := d.length()
	if dist > v.range + target_radius:
		return false
	if dist > v.near_radius + target_radius:
		# 身體邊緣進入扇形就算看得到（不會半個身子在視野內卻整隻消失）
		var allowance: float = v.angle / 2.0 + (asin(minf(1.0, target_radius / dist)) if dist > 1e-4 else 0.0)
		if absf(MathUtil.wrap_angle(atan2(d.x, d.y) - viewer.facing)) > allowance:
			return false
	return true


static func line_blocked(world: World, viewer: Player, p: Vector2) -> bool:
	return viewer.pos.distance_squared_to(p) > 1e-8 and world.terrain.sight_blocked(viewer.pos, p)


# 會被視野隱藏的實體（怪物、玩家、祭壇 / 石棺、地上的道具與金幣、別人的投射物）；其他的一律看得到
static func is_hideable(viewer: Player, e: Entity) -> bool:
	if viewer == null or viewer.is_dead or e == viewer:
		return false
	if e is Projectile:
		return (e as Projectile).owner_id != viewer.id
	return e is Enemy or e is Player or e is Chest or e is ItemPickup or e is Coin


# 判斷看不看得到時用的半徑：祭壇 / 石棺、地上的道具與金幣看中心（露一角不算）；
# 怪物、玩家、投射物看身體邊緣（不會半個身子在眼前卻整隻消失）
static func view_radius(e: Entity) -> float:
	return 0.0 if e is Chest or e is ItemPickup or e is Coin else e.radius


# viewer 為 null（例如還沒有角色）或已陣亡時什麼都看得到
static func entity_visible(world: World, viewer: Player, e: Entity) -> bool:
	return not is_hideable(viewer, e) or point_visible(world, viewer, e.pos, view_radius(e))
