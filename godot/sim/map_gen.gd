# 小關地圖產生器（地圖改版）：照種子拼出一關，輸出跟 MapDefs.MAPS 同格式的地圖資料（blocks、出生點、挖墳點…）與固定要素的位置
# 做法照 mockups/map_layouts.html 的「拼形＋不規則邊緣」：區域用拼形小格接成主線＋支線 → 區域之間開口、沿小格中心拉走道 →
# 1 單位格子從邊界往內吃（雜訊決定深度，形成崖壁）→ 每塊依主題放障礙物 → 確認起點走得到出口 / 鐵砧 / 寶箱 / 挖墳點 → 怪群、小寶箱
# 客戶端照同一個種子自己算這張地圖，不同平台要一模一樣：亂數只用 randi_range，座標是整數或 1/4 單位（二進位表示得出來），
# 距離一律比平方；只用 GDScript 的四則運算（每一步分開算，不會被合成乘加），不用三角函數、開根號、randf、Vector2 的長度與距離
# 規則與數字在 defs/map_gen_defs.gd
class_name MapGen
extends RefCounted

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const SIDE := {Vector2i(1, 0): &"E", Vector2i(-1, 0): &"W", Vector2i(0, 1): &"S", Vector2i(0, -1): &"N"}
const NOISE_N := 32

var rng: RandomNumberGenerator
var cfg: Dictionary
var stage := 1
# 區域：{ id, role（start / fight / exit / boss / branch）, sub: Array[Vector2i] 小格, hub 中心小格, obs: 障礙物, themes, box: [x, y, 寬, 深], square, gate }
var regions: Array[Dictionary] = []
var occ := {}                          # 小格 Vector2i → 區域 id
var links: Array[Dictionary] = []      # { a, b, pt: 開口位置 }
var segs: Array[PackedFloat64Array] = []   # 走道中心線 [x0, y0, x1, y1]
var keep: Array[PackedFloat64Array] = []   # 保留點 [x, y, 半徑]：不放障礙物、不吃邊
var start := Vector2.ZERO
var anvil := Vector2.INF
var big_chest := Vector2.INF
var dig := Vector2.INF
var boss_room: Array = []
var doors: Array[Dictionary] = []      # { side, at: 門, reach: 門前站的位置, reward }
var chests: Array[Vector2] = []
var packs: Array[Array] = []           # [x, y, 隻數]
# 1 單位格子：區域 id，-1 = 實心（崖壁、外面）
var gx0 := 0
var gy0 := 0
var gw := 0
var gh := 0
var grid := PackedInt32Array()
var reach := PackedByteArray()         # 從起點走得到的格子


func _init(p_stage: int, p_rng: RandomNumberGenerator) -> void:
	stage = p_stage
	rng = p_rng
	cfg = MapGenDefs.STAGES[p_stage]


# 第 stage 小關的地圖：base 是 MapDefs 裡 generator 地圖的資料（名稱、主題、怪群 / 挖墳開關），這裡蓋上產生的部分；ATTEMPTS 次都失敗回傳空的
static func build_map(base: Dictionary, p_stage: int, p_rng: RandomNumberGenerator) -> Dictionary:
	for attempt in range(1, MapGenDefs.ATTEMPTS + 1):
		var g := MapGen.new(p_stage, p_rng)
		if g._build_regions() and g._finish():
			return g._output(base, attempt)
	return {}


# ---------- 亂數（只用整數） ----------

func _int(a: int, b: int) -> int:
	return rng.randi_range(a, b)


func _chance(pct: int) -> bool:
	return rng.randi_range(0, 99) < pct


# lo ~ hi 之間 1/4 單位的格點；hi < lo 時就是 lo 附近
func _q(lo: float, hi: float) -> float:
	var a := ceili(lo * 4.0)
	var b := maxi(a, floori(hi * 4.0))
	return float(rng.randi_range(a, b)) / 4.0


func _pick(arr: Array) -> Variant:
	return arr[rng.randi_range(0, arr.size() - 1)]


# 東西寬 size 放在 total 裡、兩邊至少留 lo
func _span(lo: float, size: float, total: float) -> float:
	return _q(lo, maxf(lo, total - lo - size))


# 最多試 max_tries 次，放成功 k 個就停（fn 回傳有沒有放成功）
static func _try_n(k: int, max_tries: int, fn: Callable) -> void:
	var placed := 0
	for i in max_tries:
		if placed >= k:
			return
		if fn.call():
			placed += 1


# ---------- 區域與走道 ----------

func _shape_for(role: StringName) -> Array[Vector2i]:
	if role == &"boss":
		return _cells(MapGenDefs.SHAPES[&"O4"])
	var base: Array = MapGenDefs.SHAPES[_pick(MapGenDefs.SHAPE_POOL)]
	var rot := _int(0, 3)
	var mirror := _chance(50)
	var out: Array[Vector2i] = []
	for c: Array in base:
		var p := Vector2i(-c[0] if mirror else c[0], c[1])
		for i in rot:
			p = Vector2i(-p.y, p.x)
		out.append(p)
	var lo := out[0]
	for p in out:
		lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
	for i in out.size():
		out[i] -= lo
	return out


static func _cells(raw: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Array in raw:
		out.append(Vector2i(c[0], c[1]))
	return out


func _put(cells: Array[Vector2i], role: StringName) -> int:
	var id := regions.size()
	regions.append({"id": id, "role": role, "sub": cells, "obs": [], "themes": []})
	for c in cells:
		occ[c] = id
	return id


# 在區域 pi 旁邊接一塊新的：挑 pi 的一格往外一步當新塊的某一格，整塊不能壓到已經有的
func _attach(pi: int, role: StringName) -> bool:
	for k in 40:
		var shape := _shape_for(role)
		var p: Vector2i = _pick(regions[pi].sub)
		var d: Vector2i = _pick(DIRS)
		var q := p + d
		if occ.has(q):
			continue
		var anchor: Vector2i = _pick(shape)
		var cells: Array[Vector2i] = []
		var free := true
		for c in shape:
			var cell := c - anchor + q
			if occ.has(cell):
				free = false
				break
			cells.append(cell)
		if not free:
			continue
		links.append({"a": pi, "b": _put(cells, role)})
		return true
	return false


func _role_at(i: int, n: int) -> StringName:
	if i == 0:
		return &"start"
	if i == n - 1:
		return &"boss" if cfg.get("boss", false) else &"exit"
	return &"fight"


static func _center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * MapGenDefs.SUB, (c.y + 0.5) * MapGenDefs.SUB)


# 區域內小格到小格的路（四方向 BFS）：走道沿著小格中心走，不會穿出區域
func _sub_path(reg: Dictionary, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var inside := {}
	for c: Vector2i in reg.sub:
		inside[c] = true
	var prev := {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if c == to:
			break
		for d in DIRS:
			var nb := c + d
			if inside.has(nb) and not prev.has(nb):
				prev[nb] = c
				queue.append(nb)
	var out: Array[Vector2i] = []
	var c := to
	while true:
		out.append(c)
		if c == from:
			break
		c = prev[c]
	out.reverse()
	return out


# 從 pt 沿著小格中心拉走道到區域中心
func _corridor(reg: Dictionary, cell: Vector2i, pt: Vector2) -> void:
	var last := pt
	for c in _sub_path(reg, cell, reg.hub):
		var p := _center(c)
		segs.append(PackedFloat64Array([last.x, last.y, p.x, p.y]))
		last = p


func _keep(p: Vector2, r: float) -> void:
	keep.append(PackedFloat64Array([p.x, p.y, r]))


# 小格 c 往 d 那一邊的外緣上、距離小格左上 off 的點
static func _edge_point(c: Vector2i, d: Vector2i, off: float) -> Vector2:
	var s := MapGenDefs.SUB
	if d.x != 0:
		return Vector2((c.x + (1 if d.x > 0 else 0)) * s, c.y * s + off)
	return Vector2(c.x * s + off, (c.y + (1 if d.y > 0 else 0)) * s)


func _build_regions() -> bool:
	var main_range: Array = cfg.main
	var n := _int(main_range[0], main_range[1]) + (1 if cfg.get("boss", false) else 0)
	_put(_shape_for(&"start"), &"start")
	for i in range(1, n):
		if not _attach(i - 1, _role_at(i, n)):
			return false
	if n >= 3 and _chance(cfg.branch):
		_attach(_int(1, n - 2), &"branch")
	for reg in regions:
		var mx := 0.0
		var my := 0.0
		for c: Vector2i in reg.sub:
			mx += c.x
			my += c.y
		mx /= reg.sub.size()
		my /= reg.sub.size()
		var hub: Vector2i = reg.sub[0]
		for c: Vector2i in reg.sub:
			if (c.x - mx) * (c.x - mx) + (c.y - my) * (c.y - my) < (hub.x - mx) * (hub.x - mx) + (hub.y - my) * (hub.y - my):
				hub = c
		reg.hub = hub
	# 區域之間的開口：相鄰的小格邊上隨機一段
	var s := MapGenDefs.SUB
	for l in links:
		var a: Dictionary = regions[l.a]
		var b: Dictionary = regions[l.b]
		var pairs := []
		for p: Vector2i in a.sub:
			for d in DIRS:
				if occ.get(p + d, -1) == b.id:
					pairs.append([p, p + d, d])
		var pair: Array = _pick(pairs)
		var d: Vector2i = pair[2]
		var pt := _edge_point(pair[0], d, _int(10, s - 10))
		l.pt = pt
		_keep(pt, MapGenDefs.KEEP.opening)
		if a.role != &"boss":
			_corridor(a, pair[0], pt)
		if b.role != &"boss":
			_corridor(b, pair[1], pt)
		else:
			# 王族墓：圍牆的門對著來的方向、位置對齊開口
			var ox := s * 99999
			var oy := s * 99999
			for c: Vector2i in b.sub:
				ox = mini(ox, c.x * s)
				oy = mini(oy, c.y * s)
			var size := s * 2
			var ring: float = MapGenDefs.BOSS.ring
			var inset := (size - ring) / 2.0
			b.square = [ox, oy, size]
			var along := pt.y - oy if d.x != 0 else pt.x - ox
			b.gate = {"side": SIDE[-d], "off": clampf(along, inset + 5.0, inset + ring - 5.0)}
			segs.append(PackedFloat64Array([pt.x, pt.y, pt.x + d.x * 5, pt.y + d.y * 5]))
	# 固定要素
	start = _center(regions[0].hub)
	_keep(start, MapGenDefs.KEEP.start)
	if cfg.get("anvil", false):
		anvil = start + Vector2(MapGenDefs.ANVIL_OFFSET if _chance(50) else -MapGenDefs.ANVIL_OFFSET, 0)
		_keep(anvil, MapGenDefs.KEEP.anvil)
	if not cfg.get("boss", false) and not _place_doors(n):
		return false
	for br in regions:
		if br.role != &"branch":
			continue
		var in_pt: Vector2 = _link_into(br.id).pt
		var far: Vector2i = br.sub[0]
		for c: Vector2i in br.sub:
			if _dist2(_center(c), in_pt) > _dist2(_center(far), in_pt):
				far = c
		big_chest = _center(far)
		_keep(big_chest, MapGenDefs.KEEP.big_chest)
		var last := _center(br.hub)
		for c in _sub_path(br, br.hub, far):
			var p := _center(c)
			segs.append(PackedFloat64Array([last.x, last.y, p.x, p.y]))
			last = p
	_build_grid()
	return true


func _link_into(id: int) -> Dictionary:
	for l in links:
		if l.b == id:
			return l
	return {}


# 出口的門：最後一塊離入口最遠的外緣（前 3 名抽一個），1 或 2 扇；兩扇時各抽一種獎勵（不重複）
func _place_doors(n: int) -> bool:
	var last: Dictionary = regions[n - 1]
	var in_pt: Vector2 = _link_into(last.id).pt
	var cands := []
	for c: Vector2i in last.sub:
		for d in DIRS:
			if not occ.has(c + d):
				cands.append([_dist2(_center(c), in_pt), cands.size(), c, d])
	if cands.is_empty():
		return false
	cands.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0] or (x[0] == y[0] and x[1] < y[1]))
	var pick: Array = cands[_int(0, mini(3, cands.size()) - 1)]
	var c: Vector2i = pick[2]
	var d: Vector2i = pick[3]
	var two: bool = cfg.doors == 2
	var offs: Array = MapGenDefs.DOOR_OFFSETS_TWO if two else [MapGenDefs.SUB / 2]
	var pool: Array = MapGenDefs.DOOR_REWARDS.duplicate()
	for off: int in offs:
		var e := _edge_point(c, d, off)
		var stand := e - Vector2(d) * MapGenDefs.DOOR_REACH
		var at := e - Vector2(d) * 0.5
		var reward: StringName = &""
		if two:
			reward = pool.pop_at(_int(0, pool.size() - 1))
		doors.append({"side": SIDE[d], "at": at, "reach": stand, "reward": reward})
		_keep(stand, MapGenDefs.KEEP.door_reach)
		_keep(at, MapGenDefs.KEEP.door)
		_corridor(last, c, stand)
	return true


static func _dist2(a: Vector2, b: Vector2) -> float:
	var dx := a.x - b.x
	var dy := a.y - b.y
	return dx * dx + dy * dy


# ---------- 格子與不規則邊緣 ----------

func _cell(x: int, y: int) -> int:
	var i := x - gx0
	var j := y - gy0
	if i < 0 or j < 0 or i >= gw or j >= gh:
		return -1
	return j * gw + i


func _id_at(x: int, y: int) -> int:
	var i := _cell(x, y)
	return -1 if i < 0 else grid[i]


func _build_grid() -> void:
	var s := MapGenDefs.SUB
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := -lo
	for reg in regions:
		for c: Vector2i in reg.sub:
			lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
			hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	gx0 = lo.x * s - MapGenDefs.EDGE_PAD
	gy0 = lo.y * s - MapGenDefs.EDGE_PAD
	gw = (hi.x + 1) * s + MapGenDefs.EDGE_PAD - gx0
	gh = (hi.y + 1) * s + MapGenDefs.EDGE_PAD - gy0
	grid.resize(gw * gh)
	grid.fill(-1)
	for reg in regions:
		for c: Vector2i in reg.sub:
			for y in range(c.y * s, (c.y + 1) * s):
				for x in range(c.x * s, (c.x + 1) * s):
					grid[_cell(x, y)] = reg.id
	# 走道與保留點附近不吃
	var protect := PackedByteArray()
	protect.resize(gw * gh)
	var pad := 0.6
	for sg in segs:
		var r := MapGenDefs.CORRIDOR + pad
		for y in range(floori(minf(sg[1], sg[3]) - r), ceili(maxf(sg[1], sg[3]) + r) + 1):
			for x in range(floori(minf(sg[0], sg[2]) - r), ceili(maxf(sg[0], sg[2]) + r) + 1):
				var i := _cell(x, y)
				if i >= 0 and _seg_dist2(x + 0.5, y + 0.5, sg) < r * r:
					protect[i] = 1
	for k in keep:
		var r := k[2] + pad
		for y in range(floori(k[1] - r), ceili(k[1] + r) + 1):
			for x in range(floori(k[0] - r), ceili(k[0] + r) + 1):
				var i := _cell(x, y)
				var dx := x + 0.5 - k[0]
				var dy := y + 0.5 - k[1]
				if i >= 0 and dx * dx + dy * dy < r * r:
					protect[i] = 1
	# 每格離自己區域邊界幾格（四方向）
	var dist := PackedInt32Array()
	dist.resize(gw * gh)
	dist.fill(999)
	var queue := PackedInt32Array()
	for i in grid.size():
		if grid[i] < 0:
			continue
		var x := i % gw
		var y := i / gw
		for d in DIRS:
			var nx := x + d.x
			var ny := y + d.y
			if nx < 0 or ny < 0 or nx >= gw or ny >= gh or grid[ny * gw + nx] != grid[i]:
				dist[i] = 0
				queue.append(i)
				break
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % gw
		var y := i / gw
		for d in DIRS:
			var nx := x + d.x
			var ny := y + d.y
			if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
				continue
			var j := ny * gw + nx
			if grid[j] == grid[i] and dist[j] > dist[i] + 1:
				dist[j] = dist[i] + 1
				queue.append(j)
	var table := PackedInt32Array()
	table.resize(NOISE_N * NOISE_N)
	for i in table.size():
		table[i] = rng.randi_range(0, 1023)
	var eaten := grid.duplicate()
	for i in grid.size():
		if grid[i] < 0 or protect[i]:
			continue
		var depth := 1
		if regions[grid[i]].role != &"boss":
			depth = 1 + floori(_noise(table, gx0 + i % gw, gy0 + i / gw) * MapGenDefs.EAT_MAX)
		if dist[i] < depth:
			eaten[i] = -1
	grid = eaten


# 平滑的格點雜訊（0 ≤ 值 < 1）：表格是整數、在整數座標上算，內插只用四則運算
static func _noise(table: PackedInt32Array, x: int, y: int) -> float:
	var s := MapGenDefs.NOISE_SCALE
	var fx := posmod(x, s)
	var fy := posmod(y, s)
	var xi := (x - fx) / s
	var yi := (y - fy) / s
	var tx := float(fx) / s
	var ty := float(fy) / s
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := _lattice(table, xi, yi)
	var b := _lattice(table, xi + 1, yi)
	var c := _lattice(table, xi, yi + 1)
	var d := _lattice(table, xi + 1, yi + 1)
	var top := a + (b - a) * tx
	var bottom := c + (d - c) * tx
	return top + (bottom - top) * ty


static func _lattice(table: PackedInt32Array, i: int, j: int) -> float:
	return table[posmod(j, NOISE_N) * NOISE_N + posmod(i, NOISE_N)] / 1024.0


# ---------- 幾何（全部比平方） ----------

static func _seg_dist2(px: float, py: float, sg: PackedFloat64Array) -> float:
	var dx := sg[2] - sg[0]
	var dy := sg[3] - sg[1]
	var l2 := dx * dx + dy * dy
	var t := 0.0
	if l2 > 0.0:
		t = clampf(((px - sg[0]) * dx + (py - sg[1]) * dy) / l2, 0.0, 1.0)
	var ex := px - sg[0] - t * dx
	var ey := py - sg[1] - t * dy
	return ex * ex + ey * ey


static func _point_rect_dist2(px: float, py: float, o: Dictionary) -> float:
	var dx := maxf(maxf(o.x - px, 0.0), px - (o.x + o.w))
	var dy := maxf(maxf(o.y - py, 0.0), py - (o.y + o.h))
	return dx * dx + dy * dy


# 線段與長方形的最短距離平方：相交 = 0；否則是兩端點到長方形、四個角到線段的最小值
static func _seg_rect_dist2(sg: PackedFloat64Array, o: Dictionary) -> float:
	if _seg_hits_rect(sg, o):
		return 0.0
	var best := minf(_point_rect_dist2(sg[0], sg[1], o), _point_rect_dist2(sg[2], sg[3], o))
	for corner: Vector2 in [Vector2(o.x, o.y), Vector2(o.x + o.w, o.y), Vector2(o.x, o.y + o.h), Vector2(o.x + o.w, o.y + o.h)]:
		best = minf(best, _seg_dist2(corner.x, corner.y, sg))
	return best


# 線段穿過長方形（slab 法）
static func _seg_hits_rect(sg: PackedFloat64Array, o: Dictionary) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var d := [sg[2] - sg[0], sg[3] - sg[1]]
	var p := [sg[0], sg[1]]
	var lo := [o.x, o.y]
	var hi := [o.x + o.w, o.y + o.h]
	for k in 2:
		if d[k] == 0.0:
			if p[k] < lo[k] or p[k] > hi[k]:
				return false
			continue
		var a: float = (lo[k] - p[k]) / d[k]
		var b: float = (hi[k] - p[k]) / d[k]
		if a > b:
			var t := a
			a = b
			b = t
		t0 = maxf(t0, a)
		t1 = minf(t1, b)
		if t0 > t1:
			return false
	return true


static func _overlap(a: Dictionary, b: Dictionary, m: float) -> bool:
	return a.x < b.x + b.w + m and b.x < a.x + a.w + m and a.y < b.y + b.h + m and b.y < a.y + a.h + m


# ---------- 主題與障礙物 ----------

func _finish() -> bool:
	for reg in regions:
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := -lo
		for i in grid.size():
			if grid[i] == reg.id:
				var x := gx0 + i % gw
				var y := gy0 + i / gw
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
		if hi.x < lo.x:
			return false
		reg.box = [lo.x, lo.y, hi.x - lo.x + 1, hi.y - lo.y + 1]
	var prev: StringName = &""
	var group := 0
	for reg in regions:
		if reg.role == &"boss":
			_boss_ring(reg)
			continue
		var names: Array[StringName] = []
		if reg.role == &"start":
			names = [&"open"]
		elif reg.role == &"branch":
			names = [_pick(MapGenDefs.BRANCH_THEMES)]
		else:
			var main_pool := MapGenDefs.THEMES.filter(func(t: StringName) -> bool: return t != prev and t != &"open")
			var main: StringName = _pick(main_pool)
			names = [main]
			if _chance(MapGenDefs.SECOND_THEME):
				names.append(_pick(MapGenDefs.THEMES.filter(func(t: StringName) -> bool: return t != main and t != &"hill")))
			prev = main
		for t in names:
			group += 1
			_theme(t, reg, group)
		reg.themes = names
	return _check_paths()


# 放一個障礙物（區域外框內的座標）：整個在這塊的地面上（留 mg）、不擋走道（高台可以）、不壓保留點、不貼著別的主題的東西
func _add(reg: Dictionary, group: int, lx: float, ly: float, w: float, h: float, top: float, kind: StringName) -> bool:
	var box: Array = reg.box
	var o := {"x": box[0] + lx, "y": box[1] + ly, "w": w, "h": h, "top": top, "kind": kind, "grp": group}
	var plat := kind == &"plat"
	if not _on_floor(o, reg.id, 0.5 if plat else 1.5):
		return false
	if not plat:
		var r2 := MapGenDefs.CORRIDOR * MapGenDefs.CORRIDOR
		for sg in segs:
			if _seg_rect_dist2(sg, o) < r2:
				return false
	for k in keep:
		if _point_rect_dist2(k[0], k[1], o) < k[2] * k[2]:
			return false
	for q: Dictionary in reg.obs:
		if q.grp != group and _overlap(o, q, 0.8):
			return false
	reg.obs.append(o)
	return true


func _on_floor(o: Dictionary, id: int, mg: float) -> bool:
	var y := floori(o.y - mg)
	while y < o.y + o.h + mg:
		var x := floori(o.x - mg)
		while x < o.x + o.w + mg:
			if _id_at(x, y) != id:
				return false
			x += 1
		y += 1
	return true


func _theme(t: StringName, reg: Dictionary, g: int) -> void:
	var w: float = reg.box[2]
	var h: float = reg.box[3]
	var add := func(lx: float, ly: float, ow: float, oh: float, top: float, kind: StringName) -> bool:
		return _add(reg, g, lx, ly, ow, oh, top, kind)
	var tomb_top: float = MapGenDefs.OBSTACLE_TOP[&"tomb"]
	var wall_top: float = MapGenDefs.OBSTACLE_TOP[&"wall"]
	var ts: Vector2 = MapDefs.TOMB_SIZE
	match t:
		&"tombs":
			var rows := _int(3, 6)
			var cols := _int(4, 9)
			var sa := _q(2.6, 3.6)
			var sb := _q(3.5, 5.0)
			var vert := _chance(30)
			var a0 := _span(4.0, cols * sa, h if vert else w)
			var b0 := _span(4.0, rows * sb, w if vert else h)
			for i in rows:
				for j in cols:
					if _chance(12):
						continue
					var a := a0 + j * sa
					var b := b0 + i * sb
					if vert:
						add.call(b, a, ts.y, ts.x, tomb_top, &"tomb")
					else:
						add.call(a, b, ts.x, ts.y, tomb_top, &"tomb")
		&"ruins":
			var rw := minf(_q(14.0, 22.0), w - 8.0)
			var rh := minf(_q(12.0, 20.0), h - 8.0)
			var th: float = MapGenDefs.RUIN_WALL
			if rw < 8.0 or rh < 8.0:
				return
			var x0 := _span(4.0, rw, w)
			var y0 := _span(4.0, rh, h)
			var sides := [[x0, y0, rw, true], [x0, y0 + rh - th, rw, true], [x0, y0, rh, false], [x0 + rw - th, y0, rh, false]]
			var gaps := 0
			for k in sides.size():
				var side: Array = sides[k]
				var g_count := _int(0, 2)
				if k == 3 and gaps == 0:
					g_count = 1   # 至少一個缺口進得去
				gaps += g_count
				var cuts: Array[float] = []
				for i in g_count:
					cuts.append(_q(3.0, side[2] - 3.0))
				cuts.sort()
				var p := 0.0
				for c in cuts:
					var gap := _q(4.0, 6.0)
					if c - gap / 2.0 - p > 1.0:
						_ruin_wall(add, side, p, c - gap / 2.0, th, wall_top)
					p = maxf(p, c + gap / 2.0)
				if side[2] - p > 1.0:
					_ruin_wall(add, side, p, side[2], th, wall_top)
			for i in _int(2, 4):
				var s := _q(1.5, 2.5)
				var px := x0 + _q(2.0, rw - 2.0 - s)
				var py := y0 + _q(2.0, rh - 2.0 - s)
				add.call(px, py, s, s, 0.5, &"plat")
		&"pits":
			_try_n(_int(3, 6), 24, func() -> bool:
				var length := _q(8.0, 11.0)
				var vert := _chance(30)
				var px := _q(3.0, w - 6.0)
				var py := _q(3.0, h - 6.0)
				return add.call(px, py, 3.0 if vert else length, length if vert else 3.0, 0.5, &"plat"))
		&"mausoleums":
			_try_n(_int(3, 6), 30, func() -> bool:
				var mw := _q(5.0, 7.0)
				var mh := _q(4.0, 6.0)
				var px := _span(3.0, mw, w)
				var py := _span(3.0, mh, h)
				return add.call(px, py, mw, mh, wall_top, &"wall"))
		&"hill":
			var hw := minf(_q(16.0, 26.0), w - 6.0)
			var hh := minf(_q(12.0, 20.0), h - 6.0)
			var s := _q(3.0, 6.0)
			if hw < 10.0 or hh < 10.0:
				return
			var x0 := _span(3.0, hw, w)
			var y0 := _span(3.0, hh, h)
			if add.call(x0, y0, hw, hh, 0.5, &"plat"):
				add.call(x0 + s, y0 + s, hw - 2.0 * s, hh - 2.0 * s, 1.0, &"plat")
		&"open":
			_try_n(_int(4, 9), 30, func() -> bool:
				var flat := _chance(50)
				var px := _q(3.0, w - 4.0)
				var py := _q(3.0, h - 4.0)
				return add.call(px, py, ts.x if flat else ts.y, ts.y if flat else ts.x, tomb_top, &"tomb"))
			if _chance(40):
				_try_n(1, 10, func() -> bool:
					var px := _q(3.0, w - 9.0)
					var py := _q(3.0, h - 9.0)
					var mw := _q(5.0, 7.0)
					var mh := _q(4.0, 6.0)
					return add.call(px, py, mw, mh, wall_top, &"wall"))


# 廢墟的一段牆（side 從 a 到 b）：擋到走道就對半切再試，走道經過的地方自然變成缺口
func _ruin_wall(add: Callable, side: Array, a: float, b: float, th: float, top: float) -> void:
	var ok: bool = add.call(side[0] + a, side[1], b - a, th, top, &"wall") if side[3] else add.call(side[0], side[1] + a, th, b - a, top, &"wall")
	if ok or b - a <= 3.0:
		return
	_ruin_wall(add, side, a, (a + b) / 2.0, th, top)
	_ruin_wall(add, side, (a + b) / 2.0, b, th, top)


# 王族墓（1-5 最後一塊，固定）：方形中間的圍牆，門對著來的方向；四角石座；中央挖墳點
func _boss_ring(reg: Dictionary) -> void:
	var c: Dictionary = MapGenDefs.BOSS
	var ox: float = reg.square[0]
	var oy: float = reg.square[1]
	var size: float = reg.square[2]
	var th: float = MapGenDefs.RUIN_WALL
	var ring: float = c.ring
	var a := (size - ring) / 2.0
	var top: float = MapGenDefs.OBSTACLE_TOP[&"wall"]
	var walls := {&"N": [a, a, ring, true], &"S": [a, a + ring - th, ring, true], &"W": [a, a, ring, false], &"E": [a + ring - th, a, ring, false]}
	for side: StringName in walls:
		var wdef: Array = walls[side]
		var g: float = reg.gate.off - a
		var parts := [[0.0, g - c.gate / 2.0], [g + c.gate / 2.0, ring]] if side == reg.gate.side else [[0.0, ring]]
		for part: Array in parts:
			if part[1] - part[0] <= 0.5:
				continue
			if wdef[3]:
				reg.obs.append({"x": ox + wdef[0] + part[0], "y": oy + wdef[1], "w": part[1] - part[0], "h": th, "top": top, "kind": &"wall", "grp": 0})
			else:
				reg.obs.append({"x": ox + wdef[0], "y": oy + wdef[1] + part[0], "w": th, "h": part[1] - part[0], "top": top, "kind": &"wall", "grp": 0})
	var far: float = ring - c.corner_inset - c.corner
	for corner: Vector2 in [Vector2(c.corner_inset, c.corner_inset), Vector2(far, c.corner_inset), Vector2(c.corner_inset, far), Vector2(far, far)]:
		reg.obs.append({"x": ox + a + corner.x, "y": oy + a + corner.y, "w": c.corner, "h": c.corner, "top": c.corner_top, "kind": &"plat", "grp": 0})
	dig = Vector2(ox + size / 2.0, oy + size / 2.0)
	var inner: float = th + c.patrol_margin
	boss_room = [ox + a + inner, oy + a + inner, ring - 2.0 * inner, ring - 2.0 * inner]
	reg.themes = [&"boss"]


# ---------- 走得到嗎、怪群、小寶箱 ----------

# 起點走得到哪些格子：照怪物尋路（Nav）的規則算——牆、墓碑、實心格往外擴 NAV.margin 算擋住（高台不擋），四方向連通；
# 走不到的地面填成實心（崖壁邊緣吃出來的小塊、障礙物圍住的角落），地圖上的可走格才會連成一片、怪物到得了每個地方。
# 填了之後旁邊的格子可能也變得太窄，重算到沒有要填的為止；出口 / 挖墳點 / 鐵砧 / 大寶箱有一個走不到就整張重來
func _check_paths() -> bool:
	var s0 := _cell(floori(start.x), floori(start.y))
	if s0 < 0:
		return false
	for round in 8:
		var free := _nav_free()
		if not free[s0]:
			return false
		_flood(free, s0)
		var filled := 0
		for i in grid.size():
			if grid[i] >= 0 and free[i] and not reach[i]:
				grid[i] = -1
				filled += 1
		if filled == 0:
			break
	var targets: Array[Vector2] = []
	if cfg.get("boss", false):
		targets.append(dig)
	for d in doors:
		targets.append(d.reach)
	if anvil != Vector2.INF:
		targets.append(anvil)
	if big_chest != Vector2.INF:
		targets.append(big_chest)
	for p in targets:
		if not _reachable(p):
			return false
	_place_packs_and_chests()
	return true


# 每格在尋路眼中能不能走：是地面、不貼著實心格（八方向，邊長 1 > margin 的一半以上）、離牆與墓碑的外框超過 margin
func _nav_free() -> PackedByteArray:
	var m: float = Config.NAV.margin
	var free := PackedByteArray()
	free.resize(gw * gh)
	for i in grid.size():
		if grid[i] < 0:
			continue
		var x := i % gw
		var y := i / gw
		var ok := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or ny < 0 or nx >= gw or ny >= gh or grid[ny * gw + nx] < 0:
					ok = false
		free[i] = 1 if ok else 0
	for reg in regions:
		for o: Dictionary in reg.obs:
			if o.kind == &"plat":
				continue
			for y in range(floori(o.y - m - 1.0), ceili(o.y + o.h + m) + 1):
				for x in range(floori(o.x - m - 1.0), ceili(o.x + o.w + m) + 1):
					var i := _cell(x, y)
					var cx := x + 0.5
					var cy := y + 0.5
					if i >= 0 and cx >= o.x - m and cx <= o.x + o.w + m and cy >= o.y - m and cy <= o.y + o.h + m:
						free[i] = 0
	return free


func _flood(free: PackedByteArray, s0: int) -> void:
	reach.resize(gw * gh)
	reach.fill(0)
	reach[s0] = 1
	var queue := PackedInt32Array([s0])
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % gw
		var y := i / gw
		for d in DIRS:
			var nx := x + d.x
			var ny := y + d.y
			if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
				continue
			var j := ny * gw + nx
			if free[j] and not reach[j]:
				reach[j] = 1
				queue.append(j)


func _reachable(p: Vector2) -> bool:
	var i := _cell(floori(p.x), floori(p.y))
	return i >= 0 and reach[i] == 1


func _ok_spot(p: Vector2, id: int, far: float) -> bool:
	return _id_at(floori(p.x), floori(p.y)) == id and _reachable(p) and _dist2(p, start) >= far * far


func _near_obstacle(reg: Dictionary, p: Vector2, r: float) -> bool:
	for o: Dictionary in reg.obs:
		if _point_rect_dist2(p.x, p.y, o) < r * r:
			return true
	return false


func _place_packs_and_chests() -> void:
	var pc: Dictionary = MapGenDefs.PACKS
	var cc: Dictionary = MapGenDefs.CHESTS
	for reg in regions:
		if reg.role == &"start" or reg.role == &"boss":
			continue
		var box: Array = reg.box
		var range_n: Array = pc.per_branch if reg.role == &"branch" else pc.per_region
		_try_n(_int(range_n[0], range_n[1]), pc.attempts, func() -> bool:
			var px: float = box[0] + _q(pc.margin, box[2] - pc.margin)
			var py: float = box[1] + _q(pc.margin, box[3] - pc.margin)
			var p := Vector2(px, py)
			if not _ok_spot(p, reg.id, pc.min_start):
				return false
			for q: Array in packs:
				if _dist2(Vector2(q[0], q[1]), p) < pc.min_gap * pc.min_gap:
					return false
			packs.append([p.x, p.y, _int(pc.size[0], pc.size[1])])
			return true)
		if reg.role != &"fight":
			continue
		_try_n(_int(cc.per_region[0], cc.per_region[1]), cc.attempts, func() -> bool:
			var px: float = box[0] + _q(cc.margin, box[2] - cc.margin)
			var py: float = box[1] + _q(cc.margin, box[3] - cc.margin)
			var p := Vector2(px, py)
			if not _ok_spot(p, reg.id, cc.min_start) or _near_obstacle(reg, p, 1.0):
				return false
			for q: Array in packs:
				if _dist2(Vector2(q[0], q[1]), p) < cc.min_pack * cc.min_pack:
					return false
			chests.append(p)
			return true)


# ---------- 輸出 ----------

# 實心的地方（崖壁與地圖外面）全部是牆，合併成長方形（先往右延伸、再整排往下）：外面沒有可走格，尋路與生怪不會跑到牆外
func _solid_rects() -> Array[Rect2i]:
	var edge := PackedByteArray()
	edge.resize(gw * gh)
	for i in grid.size():
		edge[i] = 1 if grid[i] < 0 else 0
	var used := PackedByteArray()
	used.resize(gw * gh)
	var out: Array[Rect2i] = []
	for y in gh:
		for x in gw:
			var i := y * gw + x
			if used[i] or not edge[i]:
				continue
			var w := 1
			while x + w < gw and not used[i + w] and edge[i + w]:
				w += 1
			var h := 1
			var grow := true
			while grow and y + h < gh:
				for k in w:
					var j := (y + h) * gw + x + k
					if used[j] or not edge[j]:
						grow = false
						break
				if grow:
					h += 1
			for yy in h:
				for k in w:
					used[(y + yy) * gw + x + k] = 1
			out.append(Rect2i(x, y, w, h))
	return out


func _output(base: Dictionary, attempt: int) -> Dictionary:
	var shift := Vector2(-gx0, -gy0)   # 產生時的座標 → 地圖座標（左上角 (0, 0)）
	var kinds := {&"tomb": MapDefs.TOMB, &"wall": MapDefs.WALL, &"plat": MapDefs.PLATFORM}
	var blocks := []
	var edges := _solid_rects()
	for r in edges:
		blocks.append([float(r.position.x), float(r.position.y), float(r.size.x), float(r.size.y), MapDefs.WALL_TOP, MapDefs.WALL])
	var region_info := []
	for reg in regions:
		for o: Dictionary in reg.obs:
			blocks.append([o.x + shift.x, o.y + shift.y, o.w, o.h, o.top, kinds[o.kind]])
		region_info.append({"role": reg.role, "themes": reg.themes})
	var m := base.duplicate()
	m.erase("generator")
	var size := Vector2(gw, gh)
	m.size = size
	m.origin = size / 2.0
	m.spawn = start + shift
	m.stage = stage
	m.blocks = blocks
	m.tomb_rows = []
	m.edge_blocks = edges.size()
	m.regions = region_info
	m.attempts = attempt
	m.dig_event = cfg.get("boss", false)
	m.dig = (dig if dig != Vector2.INF else doors[0].reach) + shift
	if not boss_room.is_empty():
		m.boss_room = [boss_room[0] + shift.x, boss_room[1] + shift.y, boss_room[2], boss_room[3]]
	var out_doors := []
	for d in doors:
		out_doors.append({"side": d.side, "at": d.at + shift, "reach": d.reach + shift, "reward": d.reward})
	m.stage_doors = out_doors
	if anvil != Vector2.INF:
		m.anvil = anvil + shift
	var spots := []
	for p in chests:
		spots.append([p.x + shift.x, p.y + shift.y, &"small"])
	if big_chest != Vector2.INF:
		spots.append([big_chest.x + shift.x, big_chest.y + shift.y, &"big"])
	m.chest_spots = spots
	var pack_spots := []
	for pk in packs:
		pack_spots.append([pk[0] + shift.x, pk[1] + shift.y, pk[2]])
	m.pack_spots = pack_spots
	return m
