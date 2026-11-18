# 地形石台的造型（ArtStyle 試做用）：碰撞照舊是 World.terrain 的長方體，畫面照種類換成看得出是什麼的樣子
# - 崖壁（地圖邊界：MapGen 把吃進來的邊與地圖外面都記成牆，排在 blocks 最前面 edge_count 個）：外露的邊排一圈高低不一的岩柱、
#   畫成矮土坡，每 6 ~ 12 單位一段各自是鐵柵欄、岩崖、灌木叢或殘牆，碰撞照舊（YangHsu 2026-11-18：墓園用牆框起來很怪、可以做隱形牆、不用全是樹跟柵欄）
# - 牆（地圖裡的障礙物：廢墟殘牆、陵墓）：一段一段砌、每段高低不齊、段與段之間立柱、頂上壓一條蓋石、側面凸出幾塊石頭、底部一圈苔、少數段崩掉一截（腳邊碎石）
#   厚的牆（> WIDE）當成圍起來的一塊：四邊砌牆、中間填土頂
# - 墓碑：圓頂、十字、尖頂、斷碑、肩頂 5 種（照位置挑，大家看到的一樣），底座、刻字面、往鏡頭那邊一塊墳土，微微傾斜
# - 高台：台身 + 外凸的頂石 + 四角石墩
# 全部疊進同一個頂點色網格，一張圖只畫 1 次（同 ArenaView.create_blocks）
class_name BlockDressing
extends RefCounted

const WIDE := 2.6          # 比這個厚的牆當成圍起來的一塊
const SEG_LEN := 2.0       # 牆每段大約多長
const PLINTH_H := 0.35     # 牆腳那圈石的高度
const CAP_T := 0.16        # 蓋石厚度
const BANK_H := 0.9        # 邊界土坡畫多高（碰撞照舊是牆的高度，隱形）
const FENCE_IN := 0.45     # 鐵柵欄離邊界多遠（往內）

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var _rng := RandomNumberGenerator.new()
var _style: Dictionary
var _to_cam := Vector2(sin(Config.CAMERA.azimuth), cos(Config.CAMERA.azimuth))   # 地面上往鏡頭的方向
var _walls: Array[Dictionary] = []   # 全部的牆（算哪一邊跟別的牆貼著、不用砌）


# edge_count：blocks 最前面幾個是地圖邊界（World.map.edge_blocks）
static func build(blocks: Array[Dictionary], style: Dictionary, seed_value: int, edge_count := 0) -> MeshInstance3D:
	var d := BlockDressing.new()
	d._style = style
	d._rng.seed = seed_value
	for b in blocks:
		if b.kind == &"wall":
			d._walls.append(b)
	for i in blocks.size():
		var b := blocks[i]
		if i < edge_count:
			d._cliff(b)
			continue
		var c: Array = style.blocks.get(b.kind, style.blocks[&"platform"])
		match b.kind:
			&"wall":
				d._wall(b, c)
			&"tomb":
				d._tomb(b, c)
			_:
				d._platform(b, c)
	var mi := MeshInstance3D.new()
	mi.mesh = PartKit.array_mesh(d.verts, d.normals, d.colors)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	mi.material_override = m
	return mi


# ---------- 牆 ----------

func _wall(b: Dictionary, c: Array) -> void:
	var size: Vector2 = b.max - b.min
	if minf(size.x, size.y) > WIDE:
		_enclosure(b, c)
		return
	var along_x := size.x >= size.y
	var length := size.x if along_x else size.y
	var thick := size.y if along_x else size.x
	var mid: Vector2 = (b.min + b.max) / 2.0
	var axis := Vector2(1, 0) if along_x else Vector2(0, 1)
	var side := Vector2(0, 1) if along_x else Vector2(1, 0)
	_wall_run(mid - axis * length / 2.0, axis, side, length, thick, b.top, c)


# 一道牆：起點 start、沿 axis 走 length、厚 thick（side 是厚的方向）
func _wall_run(start: Vector2, axis: Vector2, side: Vector2, length: float, thick: float, top: float, c: Array) -> void:
	var n := maxi(1, roundi(length / SEG_LEN))
	var seg := length / n
	var side_col: Color = c[0]
	var top_col: Color = c[1]
	# 牆腳一圈（比牆身外凸一點、暗一點）
	_obox(start + axis * length / 2.0, 0.0, PLINTH_H, axis, length + 0.1, thick + 0.12, _shade(side_col, 0.82), _shade(top_col, 0.8))
	# 苔：牆腳上緣一圈薄的
	_obox(start + axis * length / 2.0, PLINTH_H - 0.05, 0.18, axis, length + 0.02, thick + 0.06, _style.moss, _style.moss)
	for i in n:
		var center := start + axis * (seg * (i + 0.5))
		var broken := n >= 2 and _rng.randf() < 0.12
		var h := top - 0.2 + _rng.randf_range(-0.08, 0.08)
		if broken:
			h = top * _rng.randf_range(0.5, 0.7)
		var col := _jitter(side_col, 0.07)
		_obox(center, PLINTH_H, h - PLINTH_H, axis, seg - 0.04, thick, col, _jitter(top_col, 0.06))
		if broken:
			# 崩掉的頂：兩塊高低不一的殘石，腳邊幾顆碎石
			for k in 2:
				var off := _rng.randf_range(-seg * 0.3, seg * 0.3)
				_obox(center + axis * off, h, _rng.randf_range(0.2, 0.6), axis, _rng.randf_range(0.4, 0.7), thick * 0.8, col, _jitter(top_col, 0.08))
			for k in _rng.randi_range(3, 5):
				var p := center + axis * _rng.randf_range(-seg / 2.0, seg / 2.0) + side * (thick / 2.0 + _rng.randf_range(0.1, 0.6)) * (1.0 if _rng.randf() < 0.5 else -1.0)
				var s := _rng.randf_range(0.18, 0.4)
				_obox(p, 0.0, s * 0.7, Vector2.from_angle(_rng.randf() * TAU), s, s, _jitter(side_col, 0.1), _jitter(top_col, 0.1))
		else:
			# 蓋石：比牆身寬一點、亮一點
			_obox(center, h, CAP_T, axis, seg - 0.02, thick + 0.16, _shade(top_col, 0.9), _shade(top_col, 1.12))
		# 側面凸出的石塊（像砌的磚）
		for k in _rng.randi_range(0, 2):
			var sgn := 1.0 if _rng.randf() < 0.5 else -1.0
			var p := center + axis * _rng.randf_range(-seg * 0.4, seg * 0.4) + side * sgn * (thick / 2.0 + 0.03)
			var y := _rng.randf_range(PLINTH_H + 0.1, h - 0.4)
			_obox(p, y, _rng.randf_range(0.18, 0.3), axis, _rng.randf_range(0.35, 0.7), 0.1, _jitter(side_col, 0.12), _jitter(side_col, 0.12))
	# 立柱：兩端與段之間，比牆高、外凸，頂上一塊方帽
	var pillar_every := 2 if n >= 3 else 1
	for i in range(0, n + 1, pillar_every):
		var p := start + axis * (seg * i)
		var ph := top + 0.2
		_obox(p, 0.0, ph, axis, 0.55, thick + 0.28, _shade(side_col, 1.05), _shade(top_col, 1.05))
		_obox(p, ph, 0.14, axis, 0.7, thick + 0.42, _shade(top_col, 0.95), _shade(top_col, 1.15))


# 厚的一塊：中間填土頂（比牆低一點、長苔），只在外露的邊砌牆（跟別的牆貼著的那段不砌，不然接縫處會冒出一堆內牆）
func _enclosure(b: Dictionary, c: Array) -> void:
	var x0: float = b.min.x
	var z0: float = b.min.y
	var x1: float = b.max.x
	var z1: float = b.max.y
	var t: float = b.top
	var w := 0.8
	var fill_top := t - 0.45
	_obox(Vector2((x0 + x1) / 2.0, (z0 + z1) / 2.0), 0.0, fill_top, Vector2(1, 0), x1 - x0, z1 - z0, _shade(c[0], 0.75), _style.moss)
	# 填土上零星幾塊土堆與石頭
	var area := (x1 - x0) * (z1 - z0)
	for k in mini(20, int(area / 14.0)):
		var p := Vector2(_rng.randf_range(x0 + 1.2, x1 - 1.2), _rng.randf_range(z0 + 1.2, z1 - 1.2))
		var s := _rng.randf_range(0.4, 0.9)
		_obox(p, fill_top, s * 0.3, Vector2.from_angle(_rng.randf() * TAU), s, s * 0.8, _jitter(_style.dirt, 0.1), _jitter(_style.dirt, 0.1).lightened(0.05))
	for seg in _exposed(b, &"N"):
		_wall_run(Vector2(seg.x, z0 + w / 2.0), Vector2(1, 0), Vector2(0, 1), seg.y - seg.x, w, t, c)
	for seg in _exposed(b, &"S"):
		_wall_run(Vector2(seg.x, z1 - w / 2.0), Vector2(1, 0), Vector2(0, 1), seg.y - seg.x, w, t, c)
	for seg in _exposed(b, &"W"):
		_wall_run(Vector2(x0 + w / 2.0, seg.x), Vector2(0, 1), Vector2(1, 0), seg.y - seg.x, w, t, c)
	for seg in _exposed(b, &"E"):
		_wall_run(Vector2(x1 - w / 2.0, seg.x), Vector2(0, 1), Vector2(1, 0), seg.y - seg.x, w, t, c)


# 這塊牆某一邊（N = min.y、S = max.y、W = min.x、E = max.x）沒有被別的牆貼住的區段 [起, 迄]（沿那一邊的座標）
func _exposed(b: Dictionary, edge: StringName) -> Array[Vector2]:
	var horizontal := edge == &"N" or edge == &"S"
	var lo: float = b.min.x if horizontal else b.min.y
	var hi: float = b.max.x if horizontal else b.max.y
	var outside: float
	match edge:
		&"N": outside = b.min.y - 0.05
		&"S": outside = b.max.y + 0.05
		&"W": outside = b.min.x - 0.05
		_: outside = b.max.x + 0.05
	var free: Array[Vector2] = [Vector2(lo, hi)]
	for o: Dictionary in _walls:
		if o == b:
			continue
		var o_perp_lo: float = o.min.y if horizontal else o.min.x
		var o_perp_hi: float = o.max.y if horizontal else o.max.x
		if outside <= o_perp_lo or outside >= o_perp_hi:
			continue
		var c0: float = o.min.x if horizontal else o.min.y
		var c1: float = o.max.x if horizontal else o.max.y
		var next: Array[Vector2] = []
		for f in free:
			if c1 <= f.x or c0 >= f.y:
				next.append(f)
				continue
			if c0 > f.x:
				next.append(Vector2(f.x, c0))
			if c1 < f.y:
				next.append(Vector2(c1, f.y))
		free = next
	return free.filter(func(f: Vector2) -> bool: return f.y - f.x > 0.6)


# ---------- 崖壁 ----------

# 地圖邊界的一塊（碰撞照舊是隱形的長方體）：矮土坡（BANK_H，頂上長草）；外露的邊每 6 ~ 12 單位一段，
# 各自是鐵柵欄（+ 枯樹）、岩崖（高岩柱 + 灌木）、灌木叢、殘牆（+ 稀疏的樹），見 _border；石頭最多凸出碰撞邊界 0.25
func _cliff(b: Dictionary) -> void:
	var rock: Color = _style.cliff[0]
	var grass: Color = _style.cliff[1]
	var mid: Vector2 = (b.min + b.max) / 2.0
	var size: Vector2 = b.max - b.min
	_obox(mid, 0.0, BANK_H, Vector2(1, 0), size.x, size.y, _shade(rock, 0.8), grass)
	for edge: StringName in [&"N", &"S", &"W", &"E"]:
		var horizontal := edge == &"N" or edge == &"S"
		var line: float
		var inward: Vector2
		match edge:
			&"N":
				line = b.min.y
				inward = Vector2(0, 1)
			&"S":
				line = b.max.y
				inward = Vector2(0, -1)
			&"W":
				line = b.min.x
				inward = Vector2(1, 0)
			_:
				line = b.max.x
				inward = Vector2(-1, 0)
		var along := Vector2(1, 0) if horizontal else Vector2(0, 1)
		for seg in _exposed(b, edge):
			# 每 6 ~ 12 單位一段，各自抽一種邊界（剩不到 3 的併進這段）
			var cs := seg.x
			while cs < seg.y - 0.01:
				var ce := minf(seg.y, cs + _rng.randf_range(6.0, 12.0))
				if seg.y - ce < 3.0:
					ce = seg.y
				var kind := _pick_border()
				_border(kind, cs, ce, line, horizontal, inward, along, rock, grass, b.top)
				cs = ce


# 邊界的種類（YangHsu 2026-11-18：不用全部都是樹跟柵欄）：柵欄 35%、岩崖 25%、灌木叢 20%、殘牆 20%
func _pick_border() -> StringName:
	var r := _rng.randf()
	if r < 0.35:
		return &"fence"
	if r < 0.6:
		return &"cliff"
	if r < 0.8:
		return &"hedge"
	return &"ruin"


# 邊界的一段 [a, b]（沿 line 那條邊；inward 往碰撞裡面、along 沿著邊）
func _border(kind: StringName, a: float, b: float, line: float, horizontal: bool, inward: Vector2, along: Vector2, rock: Color, grass: Color, top: float) -> void:
	var at_edge := func(u: float) -> Vector2: return Vector2(u, line) if horizontal else Vector2(line, u)
	# 腳下一排石頭：岩崖是高的岩柱，其他是矮的護坡
	var tall := kind == &"cliff"
	var u := a + _rng.randf_range(0.0, 0.4)
	while u < b - 0.2:
		var r := _rng.randf_range(0.55, 0.95) if tall else _rng.randf_range(0.4, 0.7)
		var p: Vector2 = at_edge.call(u) + inward * (r - 0.25)
		var h := top * _rng.randf_range(0.8, 1.08) if tall else BANK_H * _rng.randf_range(0.85, 1.15)
		_rock(p, r, h, _jitter(rock, 0.1), _jitter(grass, 0.08))
		if _rng.randf() < 0.35:   # 腳邊碎石
			var q := p - inward * (r + _rng.randf_range(-0.1, 0.1)) + along * _rng.randf_range(-0.4, 0.4)
			var s := _rng.randf_range(0.12, 0.25)
			_rock(q, s, s * 0.9, _jitter(rock, 0.12), _jitter(rock, 0.12).lightened(0.08))
		u += r * _rng.randf_range(1.1, 1.6)
	match kind:
		&"fence":
			_fence(at_edge.call(a) + inward * FENCE_IN, along, b - a)
			_border_plants(a, b, at_edge, inward, 0.6, 1.2, 2.4)
		&"cliff":
			_border_plants(a, b, at_edge, inward, 0.15, 1.6, 3.0)
		&"hedge":
			# 一排密的灌木（高 1.2 ~ 1.9），零星幾棵樹
			var v := a + _rng.randf_range(0.0, 0.3)
			while v < b - 0.2:
				var s := _rng.randf_range(0.5, 0.8)
				var q: Vector2 = at_edge.call(v) + inward * (s + 0.2)
				_rock(q, s, _rng.randf_range(1.2, 1.9) - BANK_H, _jitter(_style.foliage, 0.14), _jitter(_style.foliage, 0.12).lightened(0.08), BANK_H)
				v += s * _rng.randf_range(0.9, 1.3)
			_border_plants(a, b, at_edge, inward, 0.3, 2.5, 3.0)
		_:
			# 矮的崩塌石牆（立在土坡上，總高約 2），後面稀疏的樹
			var c: Array = _style.blocks[&"wall"]
			_wall_run(at_edge.call(a) + inward * 0.55, along, inward, b - a, 0.6, BANK_H + _rng.randf_range(0.9, 1.3), c)
			_border_plants(a, b, at_edge, inward, 0.4, 1.6, 3.2)


# 邊界後面（碰撞裡面 1.3 ~ 4.5）：每 step_min ~ step_max 放一棵枯樹（機率 tree_p）或一叢灌木
func _border_plants(a: float, b: float, at_edge: Callable, inward: Vector2, tree_p: float, step_min: float, step_max: float) -> void:
	var u := a + _rng.randf_range(0.3, 1.5)
	while u < b - 0.3:
		var q: Vector2 = at_edge.call(u) + inward * _rng.randf_range(1.3, 4.5)
		if _rng.randf() < tree_p:
			_dead_tree(q, _rng.randf_range(2.0, 3.4))
		else:
			var s := _rng.randf_range(0.35, 0.6)
			_rock(q, s, s * 1.2, _jitter(_style.foliage, 0.12), _jitter(_style.foliage, 0.12).lightened(0.06), BANK_H)
		u += _rng.randf_range(step_min, step_max)


# 尖頭鐵柵欄：從 start 沿 along 走 length，立在坡頂；每 2 單位一根粗柱，中間每 0.28 一根細欄杆，上下兩條橫桿
func _fence(start: Vector2, along: Vector2, length: float) -> void:
	var iron: Color = _style.iron
	var y0 := BANK_H
	var a := Vector3(along.x, 0.0, along.y)
	var s0 := Vector3(start.x, y0, start.y)
	for h in [0.22, 1.35]:
		_beam(s0 + Vector3(0, h, 0), s0 + a * length + Vector3(0, h, 0), 0.07, iron)
	var n := maxi(1, roundi(length / 0.28))
	for k in n + 1:
		var p := s0 + a * (length * k / n)
		var post := k % 7 == 0 or k == n
		var h := 1.75 if post else 1.55
		_beam(p, p + Vector3(0, h, 0), 0.14 if post else 0.06, iron)
		# 尖頭：一個小菱形
		var tip := p + Vector3(0, h, 0)
		_beam(tip, tip + Vector3(0, 0.16 if post else 0.12, 0), 0.1 if post else 0.07, iron)


# 枯樹：主幹（底粗頂細兩截）＋ 3 ~ 4 根往上斜的枝、枝上再分一小枝
func _dead_tree(at: Vector2, h: float) -> void:
	var bark: Color = _jitter(_style.bark, 0.1)
	var base := Vector3(at.x, BANK_H, at.y)
	var lean := Vector3(_rng.randf_range(-0.15, 0.15), 0.0, _rng.randf_range(-0.15, 0.15))
	var mid := base + Vector3(0, h * 0.55, 0) + lean * 0.5
	var top := base + Vector3(0, h, 0) + lean
	_beam(base, mid, 0.26, bark)
	_beam(mid, top, 0.16, bark)
	for k in _rng.randi_range(3, 4):
		var from := base.lerp(top, _rng.randf_range(0.45, 0.9))
		var ang := _rng.randf() * TAU
		var len := h * _rng.randf_range(0.25, 0.4)
		var to := from + Vector3(cos(ang) * len, len * _rng.randf_range(0.5, 0.9), sin(ang) * len)
		_beam(from, to, 0.09, bark)
		var twig := to + Vector3(cos(ang + 0.8) * len * 0.4, len * 0.35, sin(ang + 0.8) * len * 0.4)
		_beam(to.lerp(from, 0.3), twig, 0.05, bark)


# 兩點之間的方柱（寬 w）：枝幹、欄杆
func _beam(a: Vector3, b: Vector3, w: float, color: Color) -> void:
	var dir := b - a
	if dir.length_squared() < 1e-8:
		return
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized() * (w / 2.0)
	var z := y.cross(x).normalized() * (w / 2.0)
	var inside := (a + b) / 2.0
	var c := [a - x - z, a + x - z, a + x + z, a - x + z]
	var d := [b - x - z, b + x - z, b + x + z, b - x + z]
	for k in 4:
		_quad(c[k], c[(k + 1) % 4], d[(k + 1) % 4], d[k], color, inside)
	_quad(d[0], d[1], d[2], d[3], color, inside)


# 一塊岩石：不規則的多邊形（7 點）往上擠出 h，上半截再縮小一層；base_y 是底的高度
func _rock(center: Vector2, r: float, h: float, side: Color, top: Color, base_y := 0.0) -> void:
	var pts := PackedVector2Array()
	var a0 := _rng.randf() * TAU
	for k in 7:
		var a := a0 + TAU * k / 7.0 + _rng.randf_range(-0.25, 0.25)
		pts.append(Vector2(cos(a), sin(a)) * r * _rng.randf_range(0.75, 1.0))
	var lower := h * _rng.randf_range(0.55, 0.75)
	var up_basis := Basis(Vector3.RIGHT, -PI / 2.0)   # 輪廓的 (x, y) → 地面的 (x, −z)，擠出方向 → 往上
	_prism(pts, Vector2.ZERO, lower, Transform3D(up_basis, Vector3(center.x, base_y + lower / 2.0, center.y)), side, top)
	var shrink := PackedVector2Array()
	for p in pts:
		shrink.append(p * 0.72)
	_prism(shrink, Vector2.ZERO, h - lower, Transform3D(up_basis, Vector3(center.x, base_y + lower + (h - lower) / 2.0, center.y)), side, top)


# ---------- 墓碑 ----------

func _tomb(b: Dictionary, c: Array) -> void:
	var size: Vector2 = b.max - b.min
	var mid: Vector2 = (b.min + b.max) / 2.0
	var along_x := size.x >= size.y
	var width := maxf(size.x, size.y)
	var thick := minf(size.x, size.y)
	var axis := Vector2(1, 0) if along_x else Vector2(0, 1)
	var face := Vector2(0, 1) if along_x else Vector2(1, 0)
	if face.dot(_to_cam) < 0.0:
		face = -face   # 刻字面朝鏡頭
	var shape := absi(hash(Vector2i(roundi(mid.x * 10.0), roundi(mid.y * 10.0)))) % 5
	var stone := _jitter(c[0], 0.06)
	var light := _jitter(c[1], 0.06)
	var top: float = b.top
	# 墳土：刻字面那一側，低矮一塊
	_obox(mid + face * (thick / 2.0 + 0.75), 0.0, 0.14, axis, width * 0.85, 1.3, _jitter(_style.dirt, 0.08), _jitter(_style.dirt, 0.08).lightened(0.06))
	# 底座
	_obox(mid, 0.0, 0.2, axis, width, thick, _shade(stone, 0.85), _shade(light, 0.9))
	var w := width * 0.82
	var t := thick * 0.55
	var tilt := _rng.randf_range(-0.07, 0.07)
	var lean := _rng.randf_range(-0.05, 0.05)
	var basis := Basis(Vector3.UP, -atan2(axis.y, axis.x)) * Basis(Vector3.BACK, lean) * Basis(Vector3.RIGHT, tilt)
	var origin := Vector3(mid.x, 0.2, mid.y)
	var h := top - 0.2
	match shape:
		0:   # 圓頂
			var pts := PackedVector2Array([Vector2(-w / 2.0, 0.0), Vector2(w / 2.0, 0.0)])
			var r := w / 2.0
			for k in range(0, 9):
				var a := PI * k / 8.0
				pts.append(Vector2(cos(a) * r, h - r + sin(a) * r))
			_prism(pts, Vector2(0, h * 0.4), t, Transform3D(basis, origin), stone, light)
		1:   # 十字
			var bw := w * 0.3
			_prism(_rect(-bw / 2.0, 0.0, bw / 2.0, h), Vector2(0, h / 2.0), t, Transform3D(basis, origin), stone, light)
			_prism(_rect(-w / 2.0, h * 0.58, w / 2.0, h * 0.58 + bw), Vector2(0, h * 0.58 + bw / 2.0), t, Transform3D(basis, origin), stone, light)
		2:   # 尖頂
			var pts := PackedVector2Array([Vector2(-w / 2.0, 0.0), Vector2(w / 2.0, 0.0), Vector2(w / 2.0, h * 0.7), Vector2(0.0, h), Vector2(-w / 2.0, h * 0.7)])
			_prism(pts, Vector2(0, h * 0.4), t, Transform3D(basis, origin), stone, light)
		3:   # 斷碑：上緣參差，斷下來的一塊倒在旁邊
			var pts := PackedVector2Array([Vector2(-w / 2.0, 0.0), Vector2(w / 2.0, 0.0), Vector2(w / 2.0, h * 0.5), Vector2(w * 0.15, h * 0.68), Vector2(-w * 0.1, h * 0.55), Vector2(-w / 2.0, h * 0.74)])
			_prism(pts, Vector2(0, h * 0.3), t, Transform3D(basis, origin), stone, light)
			var piece := mid + face * (thick / 2.0 + 0.45) + axis * (w * 0.3)
			_obox(piece, 0.14, 0.12, axis.rotated(0.5), w * 0.45, 0.35, stone, light)
		_:   # 肩頂：中間高、兩肩低
			var s := w * 0.18
			var pts := PackedVector2Array([Vector2(-w / 2.0, 0.0), Vector2(w / 2.0, 0.0), Vector2(w / 2.0, h * 0.78), Vector2(w / 2.0 - s, h * 0.86), Vector2(w / 2.0 - s * 1.4, h), Vector2(-w / 2.0 + s * 1.4, h), Vector2(-w / 2.0 + s, h * 0.86), Vector2(-w / 2.0, h * 0.78)])
			_prism(pts, Vector2(0, h * 0.4), t, Transform3D(basis, origin), stone, light)
	# 刻字面：深一點的長方形貼在朝鏡頭那面（斷碑與十字不畫）
	if shape == 0 or shape == 2 or shape == 4:
		var plate := Transform3D(basis, origin + basis * Vector3(0.0, 0.0, 0.0))
		var sgn := signf(face.dot(Vector2(-axis.y, axis.x)))   # face 在 basis 的 +z 還是 −z
		var z := (t / 2.0 + 0.012) * (sgn if sgn != 0.0 else 1.0)
		_prism(_rect(-w * 0.3, h * 0.3, w * 0.3, h * 0.62), Vector2(0, h * 0.46), 0.02, plate.translated_local(Vector3(0, 0, z)), _shade(stone, 0.72), _shade(stone, 0.72))


# ---------- 高台 ----------

func _platform(b: Dictionary, c: Array) -> void:
	var size: Vector2 = b.max - b.min
	var mid: Vector2 = (b.min + b.max) / 2.0
	var t: float = b.top
	_obox(mid, 0.0, t - 0.12, Vector2(1, 0), size.x, size.y, _jitter(c[0], 0.05), c[1])
	_obox(mid, t - 0.12, 0.12, Vector2(1, 0), size.x + 0.12, size.y + 0.12, _shade(c[1], 0.92), _shade(c[1], 1.08))
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var p: Vector2 = mid + Vector2(corner.x * (size.x / 2.0), corner.y * (size.y / 2.0))
		_obox(p, 0.0, t + 0.12, Vector2(1, 0), 0.45, 0.45, _shade(c[0], 1.1), _shade(c[1], 1.15))


# ---------- 幾何工具 ----------

# 有朝向的長方體：底面中心 center（地面座標）、底面高度 y、高 h、沿 axis 長 len、垂直方向寬 wid；頂面 top、側面 side 色（不畫底面）
func _obox(center: Vector2, y: float, h: float, axis: Vector2, len: float, wid: float, side: Color, top: Color) -> void:
	var a := Vector3(axis.x, 0.0, axis.y).normalized() * (len / 2.0)
	var s := Vector3(-axis.y, 0.0, axis.x).normalized() * (wid / 2.0)
	var o := Vector3(center.x, y, center.y)
	var up := Vector3(0.0, h, 0.0)
	var p00 := o - a - s
	var p10 := o + a - s
	var p11 := o + a + s
	var p01 := o - a + s
	var inside := o + up / 2.0
	_quad(p00 + up, p10 + up, p11 + up, p01 + up, top, inside)
	_quad(p00, p10, p10 + up, p00 + up, side, inside)
	_quad(p10, p11, p11 + up, p10 + up, side, inside)
	_quad(p11, p01, p01 + up, p11 + up, side, inside)
	_quad(p01, p00, p00 + up, p01 + up, side, inside)


# 平面輪廓 pts（x 橫、y 往上，對 fan_at 是星形）沿 z 擠出厚 depth；朝上的側面用 top 色
func _prism(pts: PackedVector2Array, fan_at: Vector2, depth: float, xf: Transform3D, side: Color, top: Color) -> void:
	var hz := depth / 2.0
	var n := pts.size()
	var cf := xf * Vector3(fan_at.x, fan_at.y, hz)
	var cb := xf * Vector3(fan_at.x, fan_at.y, -hz)
	var z_up := (xf.basis * Vector3(0, 0, 1)).normalized().y
	var front_col := top if z_up > 0.5 else side
	var back_col := top if z_up < -0.5 else side
	for i in n:
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[(i + 1) % n]
		var pf := xf * Vector3(p.x, p.y, hz)
		var qf := xf * Vector3(q.x, q.y, hz)
		var pb := xf * Vector3(p.x, p.y, -hz)
		var qb := xf * Vector3(q.x, q.y, -hz)
		var inside := xf * Vector3(fan_at.x, fan_at.y, 0.0)
		_tri(cf, pf, qf, front_col, inside)
		_tri(cb, qb, pb, back_col, inside)
		var nrm := _outward(pf, qf, qb, inside)
		_quad(pf, qf, qb, pb, top if nrm.y > 0.5 else side, inside)


static func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


# 四邊形：兩個三角形；inside 是零件內部的一點，法線一律朝離開它的那邊
func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, inside: Vector3) -> void:
	_tri(a, b, c, color, inside)
	_tri(a, c, d, color, inside)


# 三角形：法線朝外（離開 inside）；Godot 的正面是 cross(b − a, c − a) 跟法線反向，所以照這個排頂點順序
func _tri(a: Vector3, b: Vector3, c: Vector3, color: Color, inside: Vector3) -> void:
	var raw := (b - a).cross(c - a)
	if raw.length_squared() < 1e-10:
		return
	var nrm := _outward(a, b, c, inside)
	verts.append(a)
	if raw.dot(nrm) > 0.0:
		verts.append(c)
		verts.append(b)
	else:
		verts.append(b)
		verts.append(c)
	for k in 3:
		normals.append(nrm)
		colors.append(color)


static func _outward(a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> Vector3:
	var nrm := (b - a).cross(c - a).normalized()
	return -nrm if nrm.dot((a + b + c) / 3.0 - inside) < 0.0 else nrm


func _jitter(c: Color, amount: float) -> Color:
	return _shade(c, 1.0 + _rng.randf_range(-amount, amount))


static func _shade(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k)
