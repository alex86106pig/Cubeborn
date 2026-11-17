# 小怪的出手名額：每位玩家身上，同時在對他出招的小怪有上限（近戰、遠程分開算，他看不到的另有上限）；拿不到名額的先不出招
# 上限在 World.attack_quota（開局照 Config.ATTACK_QUOTA；0 = 不限，全部不限時行為跟沒有名額一樣）
# 不用登記歸還：每步第一次要用時數一遍「正在出招的小怪」（Enemy.is_attacking_now），招式結束、被打斷、死掉自然就不算
# Boss、魔法 / 稀有怪、玩家方的僕從不佔名額也不受限；目標不是玩家（追著骷髏僕從打）也不算
class_name AttackQuota

const KINDS: Array[StringName] = [&"melee", &"ranged", &"unseen"]


# 這隻怪受不受名額限制
static func bound(e: Enemy) -> bool:
	return not e.is_boss() and e.rarity == MonsterRarityDefs.NORMAL and not (e is Minion)


# 有沒有任何一種上限開著
static func active(world: World) -> bool:
	for k in KINDS:
		if int(world.attack_quota.get(k, 0)) > 0:
			return true
	return false


# e 要對 target 開始出招：拿得到名額回傳 true（同一步問第二次直接給，不重複算）
static func take(e: Enemy, target: Entity) -> bool:
	e.attack_target_id = target.id if target != null else 0
	var world := e.world
	if e.quota_tick == world.tick or not active(world) or not bound(e) or not (target is Player):
		return true
	var c := counts(world, target.id)
	var kind := e.attack_kind()
	var unseen := not watched(target as Player, e)
	var lim: Dictionary = world.attack_quota
	if int(lim.get(kind, 0)) > 0 and c[kind] >= int(lim[kind]):
		return false
	if unseen and int(lim.get(&"unseen", 0)) > 0 and c[&"unseen"] >= int(lim[&"unseen"]):
		return false
	c[kind] += 1
	if unseen:
		c[&"unseen"] += 1
	e.quota_tick = world.tick
	return true


# 這一步正在對 target_id 出招的小怪數：{ melee, ranged, unseen }（一步數一次，之後拿到名額的直接加上去）
static func counts(world: World, target_id: int) -> Dictionary:
	if world.attack_counts.get("tick", -1) != world.tick:
		var by := {}
		for x in world.enemies:
			var o := x as Enemy
			if o == null or not bound(o) or not o.is_attacking_now():
				continue
			var p := world.entities.get(o.attack_target_id) as Player
			if p == null:
				continue
			var c: Dictionary = by.get_or_add(p.id, {&"melee": 0, &"ranged": 0, &"unseen": 0})
			c[o.attack_kind()] += 1
			if not watched(p, o):
				c[&"unseen"] += 1
		world.attack_counts = {"tick": world.tick, "by": by}
	return (world.attack_counts.by as Dictionary).get_or_add(target_id, {&"melee": 0, &"ranged": 0, &"unseen": 0})


# 玩家看不看得到這隻怪（只看距離與扇形、身邊一圈，不管牆）
static func watched(p: Player, e: Enemy) -> bool:
	return Vision.in_view_cone(p, e.pos, e.radius)
