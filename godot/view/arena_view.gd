# 場地外觀：依造型建立場地，並提供場景建構工具（照搬網頁版 render/environment.js：低多邊形地面、邊界點位、外圍裝飾散佈）
# 只負責外觀，碰撞邊界與地形由 World 決定（這裡依 world.terrain 畫出石台）；裝飾位置用畫面層自己的隨機，與模擬無關
class_name ArenaView
extends Node3D


# 石台顏色（側面、頂面）：頂面較亮，看得出可以站。墓園：牆是深色石頭、墓碑是灰白、高台是土色；
# 墓窟：岩壁偏黑褐、壁龕 / 棺材是骨白、高台是舊石磚
const BLOCK_COLORS := {
	&"graveyard": {
		&"wall": [Color("3d3a35"), Color("57524a")],
		&"tomb": [Color("7d786d"), Color("9a9487")],
		&"platform": [Color("3b4152"), Color("596178")],
	},
	&"catacomb": {
		&"wall": [Color("2a2420"), Color("3d352d")],
		&"tomb": [Color("8a8170"), Color("a89e88")],
		&"platform": [Color("4a4238"), Color("6a5f50")],
	},
	# 蟲蝕墓道：岩壁是濕土色、高台是結了殼的卵丘
	&"burrow": {
		&"wall": [Color("2b2a1f"), Color("3e3d2c")],
		&"tomb": [Color("7f8468"), Color("9da283")],
		&"platform": [Color("4b4a30"), Color("6f6c44")],
	},
}

var layout_key := []   # 現在畫的是哪份地形（main.gd 比對 World.layout_key：換層、換種子就重建）

# 小關出口的門：兩根石柱＋橫樑＋發光的門洞（顏色同出口的字 WorldLabels.EXIT_COLOR）
const DOOR_STONE := Color("6b6e75")
const DOOR_GLOW := Color("8fd0ff")
const DOOR_WIDTH := 4.4
const DOOR_HEIGHT := 3.2


# half：場地的一半大小（World.half_extents）；theme：MapDefs 的 theme
# doors：小關出口的門 [{ pos: 世界座標, side: N / E / S / W }]（DigEvent.doors，main.gd 換算）
func build(half: Vector2, terrain: Terrain, theme: StringName = &"graveyard", doors: Array = []) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	add_child(DarkFantasy.build_arena(half, rng, theme))
	if not terrain.blocks.is_empty():
		add_child(create_blocks(terrain.blocks, theme))
	if not doors.is_empty():
		add_child(create_doors(doors))


# 出口的門貼著關卡邊緣的崖壁：門洞寬沿著那一邊（北 / 南沿 x、東 / 西沿 z）
static func create_doors(doors: Array) -> Node3D:
	var k := PartKit.new()
	var group := Node3D.new()
	var stone := k.mat(DOOR_STONE)
	var glow := k.mat(DOOR_GLOW, true)
	var half := DOOR_WIDTH / 2.0
	for d: Dictionary in doors:
		var gate := Node3D.new()
		gate.position = Vector3(d.pos.x, 0.0, d.pos.y)
		gate.rotation.y = 0.0 if d.side == &"N" or d.side == &"S" else PI / 2.0
		k.add(gate, PartKit.box(0.7, DOOR_HEIGHT, 0.7), stone, {"x": -half, "y": DOOR_HEIGHT / 2.0})
		k.add(gate, PartKit.box(0.7, DOOR_HEIGHT, 0.7), stone, {"x": half, "y": DOOR_HEIGHT / 2.0})
		k.add(gate, PartKit.box(DOOR_WIDTH + 1.0, 0.6, 0.8), stone, {"y": DOOR_HEIGHT + 0.1})
		k.add(gate, PartKit.box(DOOR_WIDTH - 0.7, DOOR_HEIGHT - 0.3, 0.08), glow, {"y": (DOOR_HEIGHT - 0.3) / 2.0, "shadow": false})
		group.add_child(gate)
	return group


# 所有地形石台合併成一個網格（每個石台 5 面：頂面 + 四個側面；頂點色），地圖上有上百個石台也只畫 1 次
static func create_blocks(blocks: Array[Dictionary], theme: StringName = &"graveyard") -> MeshInstance3D:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var palette: Dictionary = BLOCK_COLORS.get(theme, BLOCK_COLORS[&"graveyard"])
	for b in blocks:
		var c: Array = palette.get(b.kind, palette[&"platform"])
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


## 每個三角形單色的低多邊形地面（size：寬 x 深）：依雜訊在 colors 間漸變，並帶 ±jitter 的隨機深淺
static func create_ground(size: Vector2, colors: Array[Color], cell: float, jitter: float, rng: RandomNumberGenerator) -> MeshInstance3D:
	var segs_x := maxi(1, roundi(size.x / cell))
	var segs_z := maxi(1, roundi(size.y / cell))
	var step_x := size.x / segs_x
	var step_z := size.y / segs_z
	# 每格兩個三角形、各 3 個頂點：先配置好再照索引寫（地面有幾萬個三角形，逐個 append 與建暫時陣列太慢）
	var count := segs_x * segs_z * 6
	var verts := PackedVector3Array()
	verts.resize(count)
	var normals := PackedVector3Array()
	normals.resize(count)
	normals.fill(Vector3.UP)
	var vcolors := PackedColorArray()
	vcolors.resize(count)
	var i := 0
	for iz in segs_z:
		for ix in segs_x:
			var x0 := -size.x / 2.0 + ix * step_x
			var z0 := -size.y / 2.0 + iz * step_z
			var p00 := Vector3(x0, 0.0, z0)
			var p10 := Vector3(x0 + step_x, 0.0, z0)
			var p01 := Vector3(x0, 0.0, z0 + step_z)
			var p11 := Vector3(x0 + step_x, 0.0, z0 + step_z)
			# 順時針（Godot 正面朝上）：[p00, p10, p01]、[p10, p11, p01]；顏色看三角形中心
			var ca := _ground_color(colors, x0 + step_x / 3.0, z0 + step_z / 3.0, jitter, rng)
			var cb := _ground_color(colors, x0 + step_x * 2.0 / 3.0, z0 + step_z * 2.0 / 3.0, jitter, rng)
			verts[i] = p00
			verts[i + 1] = p10
			verts[i + 2] = p01
			verts[i + 3] = p10
			verts[i + 4] = p11
			verts[i + 5] = p01
			vcolors[i] = ca
			vcolors[i + 1] = ca
			vcolors[i + 2] = ca
			vcolors[i + 3] = cb
			vcolors[i + 4] = cb
			vcolors[i + 5] = cb
			i += 6
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


static func _ground_color(colors: Array[Color], x: float, z: float, jitter: float, rng: RandomNumberGenerator) -> Color:
	var color := _pick(colors, soft_noise(x, z))
	var shade := 1.0 + (rng.randf() - 0.5) * 2.0 * jitter
	return Color(color.r * shade, color.g * shade, color.b * shade)


static func _pick(colors: Array[Color], t: float) -> Color:
	var scaled := clampf(t, 0.0, 0.999) * (colors.size() - 1)
	var i := floori(scaled)
	return colors[i].lerp(colors[mini(i + 1, colors.size() - 1)], scaled - i)


# 沿著長方形場地邊界（half：寬、深的一半）的等距點位（offset 為離邊界向外的距離）
static func perimeter_points(half: Vector2, spacing: float, offset := 0.5) -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	var ex := half.x + offset
	var ez := half.y + offset
	var count_x := maxi(1, roundi(ex * 2.0 / spacing))
	var count_z := maxi(1, roundi(ez * 2.0 / spacing))
	for i in count_x:
		var t := lerpf(-ex, ex, float(i) / count_x)
		points.append({"x": t, "z": -ez, "ry": 0.0})
		points.append({"x": -t, "z": ez, "ry": PI})
	for i in count_z:
		var t := lerpf(-ez, ez, float(i) / count_z)
		points.append({"x": ex, "z": t, "ry": PI / 2.0})
		points.append({"x": -ex, "z": -t, "ry": -PI / 2.0})
	return points


# 場地外圍環帶中的隨機點位（inner 為離邊界最近距離，outer 為最遠）
static func scatter_outside(rng: RandomNumberGenerator, half: Vector2, count: int, inner := 1.5, outer := 9.0) -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	while points.size() < count:
		var x := (rng.randf() * 2.0 - 1.0) * (half.x + outer)
		var z := (rng.randf() * 2.0 - 1.0) * (half.y + outer)
		if absf(x) < half.x + inner and absf(z) < half.y + inner:
			continue
		points.append({"x": x, "z": z, "ry": rng.randf() * TAU, "s": 0.7 + rng.randf() * 0.6})
	return points


# 場地內的少量裝飾點位（不影響碰撞，只放小東西）
static func scatter_inside(rng: RandomNumberGenerator, half: Vector2, count: int, margin := 1.5) -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	for i in count:
		points.append({
			"x": (rng.randf() * 2.0 - 1.0) * (half.x - margin),
			"z": (rng.randf() * 2.0 - 1.0) * (half.y - margin),
			"ry": rng.randf() * TAU,
			"s": 0.6 + rng.randf() * 0.6,
		})
	return points
