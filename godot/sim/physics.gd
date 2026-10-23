# 平面圓形碰撞：存活實體依質量比例互相推開（高度不重疊的不推），並限制在場地內；地形石台在 sim/terrain.gd
# 碰撞分離用格子切分（作法同 stress_test）：只比對相鄰 3×3 格內的實體，敵人多時不會變成 N² 次比對
# 介面維持「輸入陣列 → 就地修改位置」，之後要改 C++ 只換這裡（15.4）
class_name SimPhysics


static func separate(entities: Array[Entity], rng: RandomNumberGenerator) -> void:
	var cell: float = Config.WORLD.physics_cell
	var n := entities.size()
	var cells := PackedVector2Array()   # 每個實體所在的格子 (cx, cz)，在分離前一次算好
	cells.resize(n)
	var grid: Dictionary = {}           # Vector2i -> Array（實體索引，遞增；Packed 陣列放進 Dictionary 是複本，不能就地 append）
	for i in n:
		var c := Vector2i(floori(entities[i].pos.x / cell), floori(entities[i].pos.y / cell))
		cells[i] = Vector2(c)
		if not grid.has(c):
			grid[c] = []
		grid[c].append(i)

	var neighbors := PackedInt32Array()
	for i in n:
		var a := entities[i]
		if a.is_dead:
			continue
		# 收集相鄰格內索引比 i 大的實體，排序後依序處理（與兩兩比對的處理順序相同）
		neighbors.clear()
		var ci := Vector2i(cells[i])
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var key := ci + Vector2i(dx, dz)
				if not grid.has(key):
					continue
				for j in grid[key]:
					if j > i:
						neighbors.append(j)
		neighbors.sort()
		for j in neighbors:
			var b := entities[j]
			if b.is_dead:
				continue
			_resolve(a, b, rng)


static func _resolve(a: Entity, b: Entity, rng: RandomNumberGenerator) -> void:
	# 高度不重疊（例如跳過怪物頭頂）就不互推
	if not a.overlaps_height(b.height, b.height + b.body_height):
		return
	var d := b.pos - a.pos
	var min_dist := a.radius + b.radius
	var dist_sq := d.length_squared()
	if dist_sq >= min_dist * min_dist:
		return
	if dist_sq < 1e-8:
		d = Vector2(rng.randf() - 0.5, rng.randf() - 0.5)
		dist_sq = d.length_squared()
	var dist := sqrt(dist_sq)
	var overlap := min_dist - dist
	var normal := d / dist
	var total := a.mass + b.mass
	a.pos -= normal * (overlap * b.mass / total)
	b.pos += normal * (overlap * a.mass / total)


# 兩兩比對版本：只給 tests/check.gd 驗證格子版結果一致
static func separate_brute_force(entities: Array[Entity], rng: RandomNumberGenerator) -> void:
	var n := entities.size()
	for i in n:
		if entities[i].is_dead:
			continue
		for j in range(i + 1, n):
			if not entities[j].is_dead:
				_resolve(entities[i], entities[j], rng)


# half：場地的一半大小（World.half_extents）
static func clamp_to_arena(e: Entity, half: Vector2) -> void:
	var limit := half - Vector2(e.radius, e.radius)
	e.pos.x = clampf(e.pos.x, -limit.x, limit.x)
	e.pos.y = clampf(e.pos.y, -limit.y, limit.y)
