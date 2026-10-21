# 平面圓形碰撞：存活實體依質量比例互相推開，並限制在場地內
# 目前照搬網頁版的兩兩比對；里程碑 3 敵人變多時改成格子切分（作法同 stress_test）
class_name SimPhysics


static func separate(entities: Array[Entity], rng: RandomNumberGenerator) -> void:
	var n := entities.size()
	for i in n:
		var a := entities[i]
		if a.is_dead:
			continue
		for j in range(i + 1, n):
			var b := entities[j]
			if b.is_dead:
				continue
			var d := b.pos - a.pos
			var min_dist := a.radius + b.radius
			var dist_sq := d.length_squared()
			if dist_sq >= min_dist * min_dist:
				continue
			if dist_sq < 1e-8:
				d = Vector2(rng.randf() - 0.5, rng.randf() - 0.5)
				dist_sq = d.length_squared()
			var dist := sqrt(dist_sq)
			var overlap := min_dist - dist
			var normal := d / dist
			var total := a.mass + b.mass
			a.pos -= normal * (overlap * b.mass / total)
			b.pos += normal * (overlap * a.mass / total)


static func clamp_to_arena(e: Entity, half_size: float) -> void:
	var limit := half_size - e.radius
	e.pos.x = clampf(e.pos.x, -limit, limit)
	e.pos.y = clampf(e.pos.y, -limit, limit)
