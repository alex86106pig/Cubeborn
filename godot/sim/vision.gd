# 角色視野（D2）：判斷某位玩家看不看得到一個位置 / 實體。只影響畫面（每個人只畫自己看得到的），模擬照常進行
# 使用者決定（2026-10-23）：前方 120°、18 單位；身邊 4 單位不管方向都看得到；牆擋視線（墓碑、高台不擋）；地形照常看得到（視野外變暗）
# 視野外完全看不見：怪物、怪物的攻擊與特效、隊友（多人時不共享視野）；自己和自己發出的投射物一律看得到
class_name Vision


static func point_visible(world: World, viewer: Player, p: Vector2, target_radius: float = 0.0) -> bool:
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
	return dist < 1e-4 or not world.terrain.sight_blocked(viewer.pos, p)


# viewer 為 null（例如還沒有角色）或已陣亡時什麼都看得到
static func entity_visible(world: World, viewer: Player, e: Entity) -> bool:
	if viewer == null or viewer.is_dead or e == viewer:
		return true
	if e is Projectile:
		if (e as Projectile).owner_id == viewer.id:
			return true
		return point_visible(world, viewer, e.pos, e.radius)
	if e is Enemy or e is Player:
		return point_visible(world, viewer, e.pos, e.radius)
	return true
