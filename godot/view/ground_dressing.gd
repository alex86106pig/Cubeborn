# 地面的造型（ArtStyle 試做用，YangHsu 2026-11-18：「地面風格不喜歡」，做三種挑）：
# - smooth 平滑草皮：顏色照頂點算（相鄰三角形共用同一點的顏色），沒有一格一格的三角形；大片深淺漸變，幾塊泥土
# - tuft 模型底座草：平滑草皮 + 一小叢一小叢的草、小石子、落葉（像桌遊小模型底座的植絨）
# - hex 六角地板：平滑草皮壓暗當縫，上面鋪微微凸起的六角形板塊（像桌遊的地圖板）
# 繼承 BlockDressing 只為了共用幾何工具（_prism、_obox、_rock、_quad）
class_name GroundDressing
extends BlockDressing

const CELL := 1.0          # 草皮的格子（只影響漸變多細，看不到格子）
const HEX_R := 1.0         # 六角板的外接圓半徑
const HEX_GAP := 0.07


static func build_ground(size: Vector2, style: Dictionary, seed_value: int) -> MeshInstance3D:
	var g := GroundDressing.new()
	g._style = style
	g._rng.seed = seed_value
	var mode: StringName = style.ground_mode
	g._turf(size, 0.55 if mode == &"hex" else 1.0, -0.02 if mode == &"hex" else 0.0)
	if mode == &"tuft":
		g._tufts(size)
	elif mode == &"hex":
		g._hexes(size)
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


# 某一點的草色：大片雜訊挑草色，另一層雜訊高的地方混泥土；再照座標雜湊加一點深淺（同一點永遠同一色，三角形之間才會平滑）
func _turf_color(x: float, z: float) -> Color:
	var grass: Array = _style.grass
	var t := clampf(ArenaView.soft_noise(x * 0.3, z * 0.3), 0.0, 0.999) * (grass.size() - 1)
	var i := floori(t)
	var c: Color = (grass[i] as Color).lerp(grass[mini(i + 1, grass.size() - 1)], t - i)
	var d := ArenaView.soft_noise(x * 0.45 + 40.0, z * 0.45 - 13.0)
	c = c.lerp(_style.ground_dirt, smoothstep(0.7, 0.86, d) * 0.85)
	var h := float(absi(hash(Vector2i(roundi(x * 4.0), roundi(z * 4.0)))) % 1000) / 1000.0
	return _shade(c, 0.97 + h * 0.06)


func _turf(size: Vector2, shade: float, y: float) -> void:
	var nx := maxi(1, roundi(size.x / CELL))
	var nz := maxi(1, roundi(size.y / CELL))
	var sx := size.x / nx
	var sz := size.y / nz
	for iz in nz:
		for ix in nx:
			var x0 := -size.x / 2.0 + ix * sx
			var z0 := -size.y / 2.0 + iz * sz
			var p := [Vector3(x0, y, z0), Vector3(x0 + sx, y, z0), Vector3(x0 + sx, y, z0 + sz), Vector3(x0, y, z0 + sz)]
			var c: Array[Color] = []
			for v: Vector3 in p:
				c.append(_shade(_turf_color(v.x, v.z), shade))
			# 兩個三角形，正面朝上（Godot 正面 = cross(b − a, c − a) 跟法線反向）：[0, 1, 2]、[0, 2, 3]
			for tri: Array in [[0, 1, 2], [0, 2, 3]]:
				for k: int in tri:
					verts.append(p[k])
					normals.append(Vector3.UP)
					colors.append(c[k])


# 草叢、小石子、落葉：每 3 平方單位約一處，最多 5000
func _tufts(size: Vector2) -> void:
	var count := mini(5000, int(size.x * size.y / 3.0))
	var tuft: Array = _style.tuft
	var leaves: Array[Color] = [Color("a0602a"), Color("8a4a20"), Color("b8862e")]
	for n in count:
		var at := Vector2(_rng.randf_range(-size.x / 2.0, size.x / 2.0), _rng.randf_range(-size.y / 2.0, size.y / 2.0))
		var r := _rng.randf()
		if r < 0.62:   # 一叢草：3 ~ 5 根往外斜的細葉
			var col: Color = tuft[_rng.randi_range(0, tuft.size() - 1)]
			for k in _rng.randi_range(3, 5):
				var ang := _rng.randf() * TAU
				var h := _rng.randf_range(0.14, 0.3)
				var basis := Basis(Vector3.UP, ang) * Basis(Vector3.RIGHT, _rng.randf_range(0.15, 0.5)) * Basis(Vector3.RIGHT, -PI / 2.0)
				var off := Vector2.from_angle(ang) * _rng.randf_range(0.0, 0.08)
				var blade := PackedVector2Array([Vector2(-0.04, 0.0), Vector2(0.04, 0.0), Vector2(0.0, 0.05)])
				_prism(blade, Vector2(0.0, 0.015), h, Transform3D(basis, Vector3(at.x + off.x, h * 0.45, at.y + off.y)), _jitter(col, 0.1), _jitter(col, 0.1).lightened(0.1))
		elif r < 0.82:   # 小石子
			var s := _rng.randf_range(0.05, 0.1)
			var grey := _jitter(Color("9a9488"), 0.12)
			_rock(at, s, s * 0.6, grey, grey.lightened(0.1))
		else:   # 落葉：平的一小片
			var col := leaves[_rng.randi_range(0, leaves.size() - 1)]
			_obox(at, 0.0, 0.012, Vector2.from_angle(_rng.randf() * TAU), _rng.randf_range(0.1, 0.15), _rng.randf_range(0.06, 0.09), col, _jitter(col, 0.08))


# 六角板（平頂朝上）：鋪滿整片，每塊顏色照中心的草色、少數是泥土板
func _hexes(size: Vector2) -> void:
	var w := 1.5 * HEX_R
	var hgt := sqrt(3.0) * HEX_R
	var cols := ceili(size.x / w) + 2
	var rows := ceili(size.y / hgt) + 2
	var outline := PackedVector2Array()
	for k in 6:
		var a := TAU * k / 6.0
		outline.append(Vector2(cos(a), sin(a)) * (HEX_R - HEX_GAP / 2.0))
	var up := Basis(Vector3.RIGHT, -PI / 2.0)   # 輪廓 → 地面，擠出方向 → 往上
	for q in cols:
		for r in rows:
			var cx := -size.x / 2.0 + q * w
			var cz := -size.y / 2.0 + r * hgt + (hgt / 2.0 if q % 2 == 1 else 0.0)
			var col := _jitter(_turf_color(cx, cz), 0.06)
			_prism(outline, Vector2.ZERO, 0.06, Transform3D(up, Vector3(cx, -0.015, cz)), _shade(col, 0.8), col)
