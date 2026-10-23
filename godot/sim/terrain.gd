# 地形：場地內的長方體石台。查某一點的地面高度、把腳底低於石台頂面的實體推出石台（當牆）、投射物撞牆
# 腳底高度 ≥ 頂面 − HEIGHT.step 的實體可以站在上面；圓心在石台範圍內時地面高度就是頂面
# 石台資料來自 defs/map_defs.gd（MapDefs.world_blocks）；查詢用格子分桶，地圖上有上百個石台也只比對附近幾個
class_name Terrain
extends RefCounted

const BUCKET := 4.0     # 分桶格子邊長
const REACH := 1.5      # 石台放進桶子時往外擴的距離（≥ 最大實體半徑），實體只要查自己圓心所在的那一格

var blocks: Array[Dictionary] = []   # { min: Vector2, max: Vector2, top: float, kind: StringName }
var _buckets: Dictionary = {}        # Vector2i -> PackedInt32Array（石台索引，遞增 = 資料順序）


func _init(p_blocks: Array[Dictionary] = []) -> void:
	blocks = p_blocks
	for i in blocks.size():
		var b := blocks[i]
		var lo := _cell(b.min - Vector2(REACH, REACH))
		var hi := _cell(b.max + Vector2(REACH, REACH))
		for cx in range(lo.x, hi.x + 1):
			for cz in range(lo.y, hi.y + 1):
				var key := Vector2i(cx, cz)
				var list: PackedInt32Array = _buckets.get(key, PackedInt32Array())
				list.append(i)
				_buckets[key] = list


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET))


func _near(p: Vector2) -> PackedInt32Array:
	return _buckets.get(_cell(p), PackedInt32Array())


func ground_at(p: Vector2) -> float:
	var ground := 0.0
	for i in _near(p):
		var b := blocks[i]
		if p.x >= b.min.x and p.x <= b.max.x and p.y >= b.min.y and p.y <= b.max.y:
			ground = maxf(ground, b.top)
	return ground


# 高度 altitude 的點是否在某個石台裡面（投射物撞牆用）
func is_solid(p: Vector2, altitude: float) -> bool:
	return ground_at(p) > altitude


# 怪物尋路當障礙的石台（牆、墓碑）是否蓋到 p（往外擴 margin）；高台不算，怪物會跳上去
func blocks_nav(p: Vector2, margin: float) -> bool:
	for i in _near(p):
		var b := blocks[i]
		if b.kind == MapDefs.PLATFORM:
			continue
		if p.x >= b.min.x - margin and p.x <= b.max.x + margin and p.y >= b.min.y - margin and p.y <= b.max.y + margin:
			return true
	return false


# 線段 a → b 是否會擦到怪物尋路的障礙（牆、墓碑往外擴 clearance）：精確的線段與長方形相交，不是取樣格子
# 每 0.5 取一個點查附近的桶子（桶子裡的石台已往外擴 REACH，clearance ≤ 1.25 時不會漏）
func segment_blocked(a: Vector2, b: Vector2, clearance: float) -> bool:
	var seen := {}
	var d := b - a
	var n := maxi(1, ceili(d.length() / 0.5))
	for s in n + 1:
		for i in _near(a + d * (float(s) / n)):
			if seen.has(i):
				continue
			seen[i] = true
			var blk := blocks[i]
			if blk.kind == MapDefs.PLATFORM:
				continue
			var c := Vector2(clearance, clearance)
			var lo: Vector2 = blk.min - c
			var hi: Vector2 = blk.max + c
			# 起點已經貼在牆邊（被推到半徑距離）：往離開牆的方向走不算擋住
			if a.x >= lo.x and a.x <= hi.x and a.y >= lo.y and a.y <= hi.y:
				var closest := Vector2(clampf(a.x, blk.min.x, blk.max.x), clampf(a.y, blk.min.y, blk.max.y))
				if (a - closest).dot(d) > 0.0:
					continue
				return true
			if _segment_hits_rect(a, b, lo, hi):
				return true
	return false


# 視線 a → b 是否被牆擋住（D2）：只有 wall 種類擋，墓碑與高台不擋；不往外擴
func sight_blocked(a: Vector2, b: Vector2) -> bool:
	var seen := {}
	var d := b - a
	var n := maxi(1, ceili(d.length() / 0.5))
	for s in n + 1:
		for i in _near(a + d * (float(s) / n)):
			if seen.has(i):
				continue
			seen[i] = true
			var blk := blocks[i]
			if blk.kind == MapDefs.WALL and _segment_hits_rect(a, b, blk.min, blk.max):
				return true
	return false


# 線段與長方形（含邊）是否相交：slab 法
static func _segment_hits_rect(a: Vector2, b: Vector2, lo: Vector2, hi: Vector2) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for axis in 2:
		if absf(d[axis]) < 1e-9:
			if a[axis] < lo[axis] or a[axis] > hi[axis]:
				return false
			continue
		var ta := (lo[axis] - a[axis]) / d[axis]
		var tb := (hi[axis] - a[axis]) / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return false
	return true


# 腳底低於頂面的石台當牆：圓與長方形重疊時，沿最近點方向推出去
func push_out(e: Entity) -> void:
	var step: float = Config.HEIGHT.step
	for i in _near(e.pos):
		var b := blocks[i]
		if e.height >= b.top - step:
			continue
		var closest := Vector2(clampf(e.pos.x, b.min.x, b.max.x), clampf(e.pos.y, b.min.y, b.max.y))
		var d := e.pos - closest
		var dist_sq := d.length_squared()
		if dist_sq >= e.radius * e.radius:
			continue
		if dist_sq > 1e-8:
			var dist := sqrt(dist_sq)
			e.pos += d / dist * (e.radius - dist)
			continue
		# 圓心在石台裡面：往最近的一邊推出去
		var exits := [
			[e.pos.x - b.min.x, Vector2(b.min.x - e.radius, e.pos.y)],
			[b.max.x - e.pos.x, Vector2(b.max.x + e.radius, e.pos.y)],
			[e.pos.y - b.min.y, Vector2(e.pos.x, b.min.y - e.radius)],
			[b.max.y - e.pos.y, Vector2(e.pos.x, b.max.y + e.radius)],
		]
		exits.sort_custom(func(a: Array, c: Array) -> bool: return a[0] < c[0])
		e.pos = exits[0][1]
