# 怪物尋路（D1）：把地圖切成 NAV.cell 的格子，牆與墓碑（往外擴 margin）是障礙，高台照常可走（怪物會跳上去，見 Enemy）
# 依體型建兩張（World.nav / nav_large）：margin = 身體半徑 + 一點餘裕，大隻的不會去擠窄縫
# 路徑用引擎內建的 AStarGrid2D（八方向、不切牆角）；只在權威端使用，客戶端的怪物照快照移動
# 不持有 World（避免循環參照）
class_name Nav
extends RefCounted

var astar := AStarGrid2D.new()
var cell := 1.0
var margin := 0.6               # 障礙往外擴的距離，也是「直線走得過去」要離牆多遠
var origin := Vector2.ZERO      # 格子 (0, 0) 的左上角（世界座標）
var size := Vector2i.ZERO
var region := PackedInt32Array()   # 每格所屬的連通區塊編號（-1 = 障礙）；生成怪物時確認走得到玩家
var terrain: Terrain


func _init(p_terrain: Terrain, half: Vector2, p_margin: float) -> void:
	terrain = p_terrain
	margin = p_margin
	cell = Config.NAV.cell
	origin = -half
	size = Vector2i(ceili(half.x * 2.0 / cell), ceili(half.y * 2.0 / cell))
	astar.region = Rect2i(Vector2i.ZERO, size)
	astar.cell_size = Vector2(cell, cell)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	# 障礙格 = 格子中心落在 [min − margin, max + margin] 裡（同 Terrain.blocks_nav）：每個石台換算成格子範圍一次填，不逐格查
	# 石台座標是 1/4 單位、格子中心是 0.5 的倍數、margin 不是 1/4 的倍數，邊界不會剛好壓在格子中心上，換算沒有誤差
	var solid := PackedByteArray()
	solid.resize(size.x * size.y)
	# 場地邊緣一圈也當障礙（實體會被限制在場地內）：|中心| > half − margin
	var ex := _first_center_above(half.x - margin, origin.x)
	var ey := _first_center_above(half.y - margin, origin.y)
	var wx := ceili((-(half.x - margin) - origin.x) / cell - 0.5)   # 中心 < −(half − margin) 的格數（從 0 開始）
	var wy := ceili((-(half.y - margin) - origin.y) / cell - 0.5)
	_fill(solid, Rect2i(0, 0, wx, size.y))
	_fill(solid, Rect2i(0, 0, size.x, wy))
	_fill(solid, Rect2i(ex, 0, size.x - ex, size.y))
	_fill(solid, Rect2i(0, ey, size.x, size.y - ey))
	for b in terrain.blocks:
		if b.kind == MapDefs.PLATFORM:
			continue
		var lo := Vector2i(ceili((b.min.x - margin - origin.x) / cell - 0.5), ceili((b.min.y - margin - origin.y) / cell - 0.5))
		var hi := Vector2i(floori((b.max.x + margin - origin.x) / cell - 0.5), floori((b.max.y + margin - origin.y) / cell - 0.5))
		_fill(solid, Rect2i(lo, hi - lo + Vector2i.ONE))
	_build_regions(solid)


# 中心座標 > limit 的第一格（往正方向）：格子中心 = origin + (i + 0.5) × cell
func _first_center_above(limit: float, o: float) -> int:
	return floori((limit - o) / cell - 0.5) + 1


func _fill(solid: PackedByteArray, r: Rect2i) -> void:
	r = r.intersection(Rect2i(Vector2i.ZERO, size))
	if r.size.x <= 0 or r.size.y <= 0:
		return
	astar.fill_solid_region(r, true)
	for y in range(r.position.y, r.end.y):
		var row := y * size.x
		for x in range(r.position.x, r.end.x):
			solid[row + x] = 1


func to_cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((p.x - origin.x) / cell), 0, size.x - 1), clampi(floori((p.y - origin.y) / cell), 0, size.y - 1))


func cell_center(c: Vector2i) -> Vector2:
	return origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell


func is_walkable_cell(c: Vector2i) -> bool:
	return astar.is_in_boundsv(c) and not astar.is_point_solid(c)


func is_walkable(p: Vector2) -> bool:
	return is_walkable_cell(to_cell(p))


# 直線 a → b 離牆與墓碑都至少 margin（精確的線段判斷，v0.23.0 前用格子取樣會擦到牆角）= 可以直接走過去
func has_los(a: Vector2, b: Vector2) -> bool:
	return not terrain.segment_blocked(a, b, margin)


# 離 c 最近的可走格（一圈一圈往外找，找不到回傳 (-1, -1)）
func nearest_walkable_cell(c: Vector2i) -> Vector2i:
	if is_walkable_cell(c):
		return c
	for r in range(1, Config.NAV.nearest_search + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := c + Vector2i(dx, dy)
				if is_walkable_cell(q) and Vector2(dx, dy).length_squared() < best_d:
					best_d = Vector2(dx, dy).length_squared()
					best = q
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func nearest_walkable(p: Vector2) -> Vector2:
	var c := nearest_walkable_cell(to_cell(p))
	if c.x < 0 or c == to_cell(p):
		return p
	return cell_center(c)


func same_region(a: Vector2, b: Vector2) -> bool:
	var ca := nearest_walkable_cell(to_cell(a))
	var cb := nearest_walkable_cell(to_cell(b))
	if ca.x < 0 or cb.x < 0:
		return false
	return region[ca.y * size.x + ca.x] == region[cb.y * size.x + cb.x]


# 從 a 走到 b 的路徑點（世界座標，不含起點、最後一點是 b）；省略看得到的中間點（拉直）。走不到回傳空陣列
func find_path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var from := nearest_walkable_cell(to_cell(a))
	var to := nearest_walkable_cell(to_cell(b))
	var out := PackedVector2Array()
	if from.x < 0 or to.x < 0:
		return out
	var ids := astar.get_id_path(from, to)
	if ids.is_empty():
		return out
	var points := PackedVector2Array()
	for i in range(1, ids.size()):
		points.append(cell_center(ids[i]))
	points.append(b)
	# 拉直：從目前的點往後找最遠一個看得到的點（最多看 smooth_lookahead 個）
	var at := a
	var i := 0
	var look: int = Config.NAV.smooth_lookahead
	while i < points.size():
		var far := i
		for j in range(mini(points.size() - 1, i + look), i, -1):
			if has_los(at, points[j]):
				far = j
				break
		out.append(points[far])
		at = points[far]
		i = far + 1
	return out


# 連通區塊（四方向）：照障礙格的 byte 陣列做，不逐格呼叫 astar；格子用一維索引
func _build_regions(solid: PackedByteArray) -> void:
	var w := size.x
	var n := size.x * size.y
	region.resize(n)
	region.fill(-1)
	var next := 0
	var stack := PackedInt32Array()
	for start in n:
		if region[start] != -1 or solid[start] != 0:
			continue
		region[start] = next
		stack.append(start)
		while not stack.is_empty():
			var i: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var x := i % w
			if x + 1 < w and solid[i + 1] == 0 and region[i + 1] == -1:
				region[i + 1] = next
				stack.append(i + 1)
			if x > 0 and solid[i - 1] == 0 and region[i - 1] == -1:
				region[i - 1] = next
				stack.append(i - 1)
			if i + w < n and solid[i + w] == 0 and region[i + w] == -1:
				region[i + w] = next
				stack.append(i + w)
			if i >= w and solid[i - w] == 0 and region[i - w] == -1:
				region[i - w] = next
				stack.append(i - w)
		next += 1
