# 傷害結算與命中判定查詢（扇形、圓形）；照搬網頁版 legacy/src/combat/Combat.js
class_name Combat


# team 的敵對陣營中仍存活的實體
static func hostiles_of(world: World, team: StringName) -> Array[Entity]:
	var out: Array[Entity] = []
	if team == &"player":
		for e in world.enemies:
			if not e.is_dead:
				out.append(e)
	else:
		for p: Player in world.players.values():
			if not p.is_dead:
				out.append(p)
	return out


# hit：damage（已含攻擊者的攻擊力，由發動招式的一方計算）、knockback、origin（預設 source.pos，擊退方向為 origin → target）、
#      hit_stop、shake、is_heavy（重擊：第三段、盾擊、爆炸，只影響顯示與音效）
# 這裡套用攻擊者的爆擊與擊退屬性；護甲與受傷倍率在 Entity.take_damage
# 回傳是否實際命中
static func apply_damage(world: World, source: Entity, target: Entity, hit: Dictionary) -> bool:
	if target == null or not target.can_be_hit():
		return false
	var origin: Vector2 = hit.get("origin", source.pos)
	var dir := target.pos - origin
	if dir.length_squared() < 1e-6:
		dir = MathUtil.dir_from_angle(source.facing)
	dir = dir.normalized()

	var damage: float = hit.damage
	var is_crit := false
	var crit_chance := source.stats.value(&"crit_chance")
	# 爆擊率 0 時不擲骰，不消耗亂數（沒有爆擊道具時與網頁版的亂數序列相同）
	if crit_chance > 0.0 and world.rng.randf() < crit_chance:
		is_crit = true
		damage *= source.stats.value(&"crit_damage")
	var knockback: float = hit.get("knockback", 0.0) * source.stats.value(&"knockback")
	var dealt := target.take_damage(damage, dir, knockback, source.id)
	if dealt < 0:
		return false

	world.emit_event("entity:damaged", {
		"target_id": target.id, "amount": dealt, "source_id": source.id,
		"knockback": knockback, "is_heavy": hit.get("is_heavy", false), "is_crit": is_crit,
	})
	var hit_stop: float = hit.get("hit_stop", 0.0)
	if hit_stop > 0.0:
		world.hit_stop(hit_stop)
	var shake: float = hit.get("shake", 0.0)
	if shake > 0.0:
		world.emit_event("camera:shake", {"amount": shake, "duration": Config.COMBAT.hit_shake_duration})
	return true


# 扇形判定：考慮目標半徑，貼身目標一律命中
static func query_sector(origin: Vector2, facing: float, range_: float, arc: float, candidates: Array[Entity]) -> Array[Entity]:
	var out: Array[Entity] = []
	for c in candidates:
		var d := c.pos - origin
		var dist := d.length()
		if dist > range_ + c.radius:
			continue
		if dist <= c.radius + 0.3:
			out.append(c)
			continue
		var diff := absf(MathUtil.wrap_angle(atan2(d.x, d.y) - facing))
		var allowance := arc / 2.0 + asin(minf(1.0, c.radius / dist))
		if diff <= allowance:
			out.append(c)
	return out


static func query_circle(center: Vector2, radius: float, candidates: Array[Entity]) -> Array[Entity]:
	var out: Array[Entity] = []
	for c in candidates:
		var r := radius + c.radius
		if c.pos.distance_squared_to(center) <= r * r:
			out.append(c)
	return out
