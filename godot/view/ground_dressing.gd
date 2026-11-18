# 地面的造型（桌上模型風格，YangHsu 2026-11-18 選定；目前只有墓園）：平滑的土地，顏色照頂點算（相鄰三角形共用同一點的顏色），
# 沒有一格一格的三角形；大片深淺漸變，幾塊稍深的土。草叢不長在空地上（BlockDressing._base_tufts 長在牆腳、墓碑腳、土坡腳）
# 繼承 BlockDressing 只為了共用配色與 _shade
class_name GroundDressing
extends BlockDressing

const CELL := 1.0          # 格子大小（只影響漸變多細，看不到格子）


static func build_ground(size: Vector2, style: Dictionary, seed_value: int) -> MeshInstance3D:
	var g := GroundDressing.new()
	g._style = style
	g._rng.seed = seed_value
	g._turf(size)
	var mi := MeshInstance3D.new()
	mi.mesh = PartKit.array_mesh(g.verts, g.normals, g.colors)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# 某一點的地面色：大片雜訊在 grass 幾種土色間漸變，另一層雜訊高的地方混深一點的土（ground_dirt）；再照座標雜湊加一點深淺（同一點永遠同一色，三角形之間才會平滑）
func _turf_color(x: float, z: float) -> Color:
	var grass: Array = _style.grass
	var t := clampf(ArenaView.soft_noise(x * 0.3, z * 0.3), 0.0, 0.999) * (grass.size() - 1)
	var i := floori(t)
	var c: Color = (grass[i] as Color).lerp(grass[mini(i + 1, grass.size() - 1)], t - i)
	var d := ArenaView.soft_noise(x * 0.45 + 40.0, z * 0.45 - 13.0)
	c = c.lerp(_style.ground_dirt, smoothstep(0.7, 0.86, d) * float(_style.get("dirt_mix", 0.85)))
	var h := float(absi(hash(Vector2i(roundi(x * 4.0), roundi(z * 4.0)))) % 1000) / 1000.0
	return _shade(c, 0.97 + h * 0.06)


func _turf(size: Vector2) -> void:
	var nx := maxi(1, roundi(size.x / CELL))
	var nz := maxi(1, roundi(size.y / CELL))
	var sx := size.x / nx
	var sz := size.y / nz
	# 每個格點的顏色只算一次（相鄰 4 格共用；逐格算要多算 4 倍，墓園一張 2 ~ 3 萬次 _turf_color）
	var grid := PackedColorArray()
	grid.resize((nx + 1) * (nz + 1))
	for iz in nz + 1:
		for ix in nx + 1:
			grid[iz * (nx + 1) + ix] = _turf_color(-size.x / 2.0 + ix * sx, -size.y / 2.0 + iz * sz)
	for iz in nz:
		for ix in nx:
			var x0 := -size.x / 2.0 + ix * sx
			var z0 := -size.y / 2.0 + iz * sz
			var p := [Vector3(x0, 0.0, z0), Vector3(x0 + sx, 0.0, z0), Vector3(x0 + sx, 0.0, z0 + sz), Vector3(x0, 0.0, z0 + sz)]
			var row := iz * (nx + 1) + ix
			var c := [grid[row], grid[row + 1], grid[row + nx + 2], grid[row + nx + 1]]
			# 兩個三角形，正面朝上（Godot 正面 = cross(b − a, c − a) 跟法線反向）：[0, 1, 2]、[0, 2, 3]
			for tri: Array in [[0, 1, 2], [0, 2, 3]]:
				for k: int in tri:
					verts.append(p[k])
					normals.append(Vector3.UP)
					colors.append(c[k])
