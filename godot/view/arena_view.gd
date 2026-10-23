# 場地外觀：依造型建立場地，並提供場景建構工具（照搬網頁版 render/environment.js：低多邊形地面、邊界點位、外圍裝飾散佈）
# 只負責外觀，碰撞邊界與地形由 World 決定（這裡依 world.terrain 畫出石台）；裝飾位置用畫面層自己的隨機，與模擬無關
class_name ArenaView
extends Node3D


# 石台顏色（側面、頂面）：頂面較亮，看得出可以站；牆是深色石頭、墓碑是灰白、高台是土色
const BLOCK_COLORS := {
	&"wall": [Color("3d3a35"), Color("57524a")],
	&"tomb": [Color("7d786d"), Color("9a9487")],
	&"platform": [Color("3b4152"), Color("596178")],
}


# half：場地的一半大小（World.half_extents）
func build(half: Vector2, terrain: Terrain) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	add_child(DarkFantasy.build_arena(maxf(half.x, half.y), rng))
	if not terrain.blocks.is_empty():
		add_child(create_blocks(terrain.blocks))


# 所有地形石台合併成一個網格（每個石台 5 面：頂面 + 四個側面；頂點色），地圖上有上百個石台也只畫 1 次
static func create_blocks(blocks: Array[Dictionary]) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for b in blocks:
		var c: Array = BLOCK_COLORS.get(b.kind, BLOCK_COLORS[&"platform"])
		var x0: float = b.min.x
		var z0: float = b.min.y
		var x1: float = b.max.x
		var z1: float = b.max.y
		var t: float = b.top
		_quad(verts, normals, colors, [Vector3(x0, t, z0), Vector3(x1, t, z0), Vector3(x1, t, z1), Vector3(x0, t, z1)], Vector3.UP, c[1])
		_quad(verts, normals, colors, [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, t, z0), Vector3(x0, t, z0)], Vector3.FORWARD, c[0])
		_quad(verts, normals, colors, [Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3(x1, t, z1), Vector3(x0, t, z1)], Vector3.BACK, c[0])
		_quad(verts, normals, colors, [Vector3(x0, 0, z0), Vector3(x0, 0, z1), Vector3(x0, t, z1), Vector3(x0, t, z0)], Vector3.LEFT, c[0])
		_quad(verts, normals, colors, [Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x1, t, z1), Vector3(x1, t, z0)], Vector3.RIGHT, c[0])
	var mi := MeshInstance3D.new()
	mi.mesh = PartKit.array_mesh(verts, normals, colors)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	mi.material_override = m
	return mi


# 四邊形拆成兩個三角形；依法線調整頂點順序（Godot 的正面：cross(b - a, c - a) 與法線反向）
static func _quad(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, q: Array, n: Vector3, color: Color) -> void:
	var a: Vector3 = q[0]
	var b: Vector3 = q[1]
	var c: Vector3 = q[2]
	var d: Vector3 = q[3]
	if (b - a).cross(c - a).dot(n) > 0.0:
		var tmp := b
		b = d
		d = tmp
	for v: Vector3 in [a, b, c, a, c, d]:
		verts.append(v)
		normals.append(n)
		colors.append(color)


# 平滑的偽隨機雜訊（0~1）
static func soft_noise(x: float, z: float) -> float:
	return 0.5 \
		+ 0.25 * sin(x * 0.35 + 1.3) * cos(z * 0.27 - 0.4) \
		+ 0.25 * sin((x + z) * 0.15 + 2.1)


## 每個三角形單色的低多邊形地面：依雜訊在 colors 間漸變，並帶 ±jitter 的隨機深淺
static func create_ground(size: float, colors: Array[Color], cell: float, jitter: float, rng: RandomNumberGenerator) -> MeshInstance3D:
	var segs := maxi(1, roundi(size / cell))
	var step := size / segs
	var h := size / 2.0
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var vcolors := PackedColorArray()
	for iz in segs:
		for ix in segs:
			var x0 := -h + ix * step
			var z0 := -h + iz * step
			var p00 := Vector3(x0, 0.0, z0)
			var p10 := Vector3(x0 + step, 0.0, z0)
			var p01 := Vector3(x0, 0.0, z0 + step)
			var p11 := Vector3(x0 + step, 0.0, z0 + step)
			for tri in [[p00, p10, p01], [p10, p11, p01]]:   # 順時針（Godot 正面朝上）
				var center: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
				var color := _pick(colors, soft_noise(center.x, center.z))
				var shade := 1.0 + (rng.randf() - 0.5) * 2.0 * jitter
				color = Color(color.r * shade, color.g * shade, color.b * shade)
				for v: Vector3 in tri:
					verts.append(v)
					normals.append(Vector3.UP)
					vcolors.append(color)
	var mi := MeshInstance3D.new()
	mi.mesh = PartKit.array_mesh(verts, normals, vcolors)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _pick(colors: Array[Color], t: float) -> Color:
	var scaled := clampf(t, 0.0, 0.999) * (colors.size() - 1)
	var i := floori(scaled)
	return colors[i].lerp(colors[mini(i + 1, colors.size() - 1)], scaled - i)


# 沿著正方形場地邊界的等距點位（offset 為離邊界向外的距離）
static func perimeter_points(half: float, spacing: float, offset := 0.5) -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	var e := half + offset
	var count := maxi(1, roundi(e * 2.0 / spacing))
	for i in count:
		var t := lerpf(-e, e, float(i) / count)
		points.append({"x": t, "z": -e, "ry": 0.0})
		points.append({"x": e, "z": t, "ry": PI / 2.0})
		points.append({"x": -t, "z": e, "ry": PI})
		points.append({"x": -e, "z": -t, "ry": -PI / 2.0})
	return points


# 場地外圍環帶中的隨機點位（inner 為離邊界最近距離，outer 為最遠）
static func scatter_outside(rng: RandomNumberGenerator, half: float, count: int, inner := 1.5, outer := 9.0) -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	while points.size() < count:
		var x := (rng.randf() * 2.0 - 1.0) * (half + outer)
		var z := (rng.randf() * 2.0 - 1.0) * (half + outer)
		if maxf(absf(x), absf(z)) < half + inner:
			continue
		points.append({"x": x, "z": z, "ry": rng.randf() * TAU, "s": 0.7 + rng.randf() * 0.6})
	return points


# 場地內的少量裝飾點位（不影響碰撞，只放小東西）
static func scatter_inside(rng: RandomNumberGenerator, half: float, count: int, margin := 1.5) -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	for i in count:
		points.append({
			"x": (rng.randf() * 2.0 - 1.0) * (half - margin),
			"z": (rng.randf() * 2.0 - 1.0) * (half - margin),
			"ry": rng.randf() * TAU,
			"s": 0.6 + rng.randf() * 0.6,
		})
	return points
