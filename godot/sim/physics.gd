# 平面圓形碰撞：存活實體依質量比例互相推開（高度不重疊的不推），並限制在場地內；地形石台在 sim/terrain.gd
# 碰撞分離用格子切分（作法同 stress_test）：只比對相鄰 3×3 格內的實體，敵人多時不會變成 N² 次比對
# 介面維持「輸入陣列 → 就地修改位置」，之後要改 C++ 只換這裡（PROJECT_GUIDELINES.md 第 15 節）
class_name SimPhysics


# D5 起改成先把位置、半徑、質量、高度抄進 Packed 陣列計算，最後才寫回實體（200 隻怪時 GDScript 讀寫物件屬性太慢）
# 格子用攤平的鏈結串列（head / next），每步不配置 Dictionary 與 Array；計算順序與 _resolve 兩兩比對相同
static func separate(entities: Array[Entity], rng: RandomNumberGenerator) -> void:
	var cell: float = Config.WORLD.physics_cell
	var n := entities.size()
	if n < 2:
		return
	var px := PackedFloat64Array()
	var pz := PackedFloat64Array()
	var rad := PackedFloat64Array()
	var mass := PackedFloat64Array()
	var low := PackedFloat64Array()    # 腳底高度
	var high := PackedFloat64Array()   # 頭頂高度
	var cx := PackedInt32Array()
	var cz := PackedInt32Array()
	var fix := PackedByteArray()      # 1 = 固定不動（Entity.fixed）
	fix.resize(n)
	px.resize(n)   # Packed 陣列是複製寫入，不能放進陣列用迴圈 resize
	pz.resize(n)
	rad.resize(n)
	mass.resize(n)
	low.resize(n)
	high.resize(n)
	cx.resize(n)
	cz.resize(n)
	var min_x := 1 << 30
	var min_z := 1 << 30
	var max_x := -(1 << 30)
	var max_z := -(1 << 30)
	for i in n:
		var e := entities[i]
		px[i] = e.pos.x
		pz[i] = e.pos.y
		rad[i] = e.radius
		mass[i] = -1.0 if e.is_dead else e.mass   # 質量 < 0 = 已死亡，不參與
		fix[i] = 1 if e.fixed else 0
		low[i] = e.height
		high[i] = e.height + e.body_height
		cx[i] = floori(px[i] / cell)
		cz[i] = floori(pz[i] / cell)
		min_x = mini(min_x, cx[i])
		min_z = mini(min_z, cz[i])
		max_x = maxi(max_x, cx[i])
		max_z = maxi(max_z, cz[i])
	var gw := max_x - min_x + 1
	var gh := max_z - min_z + 1
	var head := PackedInt32Array()
	head.resize(gw * gh)
	head.fill(-1)
	var next := PackedInt32Array()
	next.resize(n)
	for i in range(n - 1, -1, -1):   # 倒著插入，每格的串列由小到大
		var k := (cz[i] - min_z) * gw + (cx[i] - min_x)
		next[i] = head[k]
		head[k] = i

	var moved := false
	var neighbors := PackedInt32Array()
	for i in n:
		if mass[i] < 0.0 or fix[i] == 1:
			continue   # 固定的不主動找鄰居：和會動的那一對由會動的那一方處理，兩個都固定的不必比（v0.30.0 效能）
		# 收集相鄰格內索引比 i 大、或固定不動的實體，排序後依序處理（與兩兩比對的處理順序相同）
		neighbors.clear()
		for dz in range(maxi(cz[i] - 1, min_z), mini(cz[i] + 1, max_z) + 1):
			for dx in range(maxi(cx[i] - 1, min_x), mini(cx[i] + 1, max_x) + 1):
				var j := head[(dz - min_z) * gw + (dx - min_x)]
				while j >= 0:
					if j > i or fix[j] == 1:
						neighbors.append(j)
					j = next[j]
		if neighbors.is_empty():
			continue
		neighbors.sort()
		for j in neighbors:
			if mass[j] < 0.0 or not (low[i] < high[j] and high[i] > low[j]):
				continue   # 死亡、或高度不重疊（例如跳過怪物頭頂）就不互推
			var dx := px[j] - px[i]
			var dz := pz[j] - pz[i]
			var min_dist := rad[i] + rad[j]
			var dist_sq := dx * dx + dz * dz
			if dist_sq >= min_dist * min_dist:
				continue
			if dist_sq < 1e-8:
				dx = rng.randf() - 0.5
				dz = rng.randf() - 0.5
				dist_sq = dx * dx + dz * dz
			var dist := sqrt(dist_sq)
			var overlap := min_dist - dist
			var ka := overlap / dist   # j 固定不動：i 自己退開全部重疊
			var kb := 0.0
			if fix[j] == 0:
				var total := mass[i] + mass[j]
				ka = overlap * mass[j] / total / dist
				kb = overlap * mass[i] / total / dist
			px[i] -= dx * ka
			pz[i] -= dz * ka
			px[j] += dx * kb
			pz[j] += dz * kb
			moved = true
	if not moved:
		return
	for i in n:
		var e := entities[i]
		if e.pos.x != px[i] or e.pos.y != pz[i]:
			e.pos = Vector2(px[i], pz[i])


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
	if b.fixed:   # b 固定不動：a 退開全部重疊
		a.pos -= normal * overlap
		return
	var total := a.mass + b.mass
	a.pos -= normal * (overlap * b.mass / total)
	b.pos += normal * (overlap * a.mass / total)


# 兩兩比對版本：只給 tests/check.gd 驗證格子版結果一致（處理順序同格子版：會動的 i 依序比對 j > i 或固定的 j）
static func separate_brute_force(entities: Array[Entity], rng: RandomNumberGenerator) -> void:
	var n := entities.size()
	for i in n:
		if entities[i].is_dead or entities[i].fixed:
			continue
		for j in n:
			if j != i and (j > i or entities[j].fixed) and not entities[j].is_dead:
				_resolve(entities[i], entities[j], rng)


# half：場地的一半大小（World.half_extents）
static func clamp_to_arena(e: Entity, half: Vector2) -> void:
	var limit := half - Vector2(e.radius, e.radius)
	e.pos.x = clampf(e.pos.x, -limit.x, limit.x)
	e.pos.y = clampf(e.pos.y, -limit.y, limit.y)
