# 零件組：低多邊形形狀工廠、依顏色共用材質、受擊閃白、靜態零件合併（對應網頁版 render/rig.js 的 PartKit 與 G）
# 零件的位置與旋轉照網頁版 Three.js 數值填寫：旋轉順序為 XYZ，圓環在 XY 平面，與 Three.js 相同
# 合併時改成每個面各自的法線（flat shading），做出網頁版硬朗多面體的效果
class_name PartKit
extends RefCounted

var _materials: Dictionary = {}                 # "顏色|glow" -> StandardMaterial3D
var _flash_materials: Array[StandardMaterial3D] = []


# 依顏色取得材質；glow 為不受光照的自發光材質，不受閃白影響
func mat(color: Color, glow := false) -> StandardMaterial3D:
	var key := "%s|%s" % [color.to_html(false), glow]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		# 接近網頁版 MeshLambertMaterial：只有漫反射、沒有高光
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.roughness = 1.0
		# 自發光一開始就打開（平常為黑色）：閃白時切換開關會換著色器，第一次命中會即時編譯而卡頓
		m.emission_enabled = true
		m.emission = Color.BLACK
		_flash_materials.append(m)
	_materials[key] = m
	return m


# t：x / y / z、rx / ry / rz、s 或 sx / sy / sz、shadow（預設 true）
func add(parent: Node3D, mesh: Mesh, material: Material, t := {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.rotation_order = EULER_ORDER_XYZ
	mi.position = Vector3(t.get("x", 0.0), t.get("y", 0.0), t.get("z", 0.0))
	mi.rotation = Vector3(t.get("rx", 0.0), t.get("ry", 0.0), t.get("rz", 0.0))
	var s: float = t.get("s", 1.0)
	mi.scale = Vector3(t.get("sx", s), t.get("sy", s), t.get("sz", s))
	if not t.get("shadow", true):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# 受擊閃白，k 為 0~1；只改自發光顏色，不切換 emission_enabled（見 mat()）
func set_flash(k: float) -> void:
	for m in _flash_materials:
		m.emission = Color(k, k, k)


## 合併靜態零件以減少繪製次數：anchors 是會各自移動的節點（關節、武器根節點），
## 每個零件依「最近的 anchor 祖先 + 材質 + 陰影設定」分組，合併成一個 mesh 掛回該 anchor。
## keep 內的零件（例如會自轉的寶石）不合併，只換成平面法線。anchor 以下的非 anchor 節點視為固定不動。
func merge_static(root: Node3D, anchors: Array, keep: Array = []) -> void:
	var buckets: Dictionary = {}   # key -> { anchor, material, shadow, verts, normals }
	var merged: Array[MeshInstance3D] = []
	for mi in mesh_instances(root):
		if keep.has(mi):
			mi.mesh = flat_mesh(mi.mesh, Transform3D.IDENTITY)
			continue
		var anchor: Node = mi.get_parent()
		var rel := mi.transform
		while anchor != null and not anchors.has(anchor):
			rel = (anchor as Node3D).transform * rel
			anchor = anchor.get_parent()
		if anchor == null:
			continue
		var key := "%d|%d|%d" % [anchor.get_instance_id(), mi.material_override.get_instance_id(), mi.cast_shadow]
		if not buckets.has(key):
			buckets[key] = {
				"anchor": anchor, "material": mi.material_override, "shadow": mi.cast_shadow,
				"verts": PackedVector3Array(), "normals": PackedVector3Array(),
			}
		_append_flat(mi.mesh, rel, buckets[key].verts, buckets[key].normals)
		merged.append(mi)

	for mi in merged:
		mi.get_parent().remove_child(mi)
		mi.free()
	for b: Dictionary in buckets.values():
		var mi := MeshInstance3D.new()
		mi.mesh = array_mesh(b.verts, b.normals)
		mi.material_override = b.material
		mi.cast_shadow = b.shadow
		(b.anchor as Node3D).add_child(mi)
	_prune_empty(root, anchors)


static func mesh_instances(node: Node, out: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		mesh_instances(child, out)
	return out


# 移除合併後留下的空群組（anchor 除外）
static func _prune_empty(node: Node, anchors: Array) -> void:
	for child in node.get_children():
		_prune_empty(child, anchors)
		if not child is MeshInstance3D and child.get_child_count() == 0 and not anchors.has(child):
			node.remove_child(child)
			child.free()


# 單一零件換成平面法線的 ArrayMesh（xform 套用到頂點）
static func flat_mesh(mesh: Mesh, xform: Transform3D) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	_append_flat(mesh, xform, verts, normals)
	return array_mesh(verts, normals)


static func array_mesh(verts: PackedVector3Array, normals: PackedVector3Array, colors := PackedColorArray()) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


# 把 mesh 的每個三角形套上 xform 後拆成獨立頂點，法線用面法線。
# 方向以原本頂點法線為準，並把頂點順序調成 Godot 的正面（順時針），所以來源的繞序不影響結果
static func _append_flat(mesh: Mesh, xform: Transform3D, verts: PackedVector3Array, normals: PackedVector3Array) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var src_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var src_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count := idx.size() if not idx.is_empty() else src_v.size()
	var nbasis := xform.basis.inverse().transposed()
	for i in range(0, count, 3):
		var ia := idx[i] if not idx.is_empty() else i
		var ib := idx[i + 1] if not idx.is_empty() else i + 1
		var ic := idx[i + 2] if not idx.is_empty() else i + 2
		var a := xform * src_v[ia]
		var b := xform * src_v[ib]
		var c := xform * src_v[ic]
		var face := (b - a).cross(c - a)
		if face.length_squared() < 1e-12:
			continue   # 圓錐尖端等退化三角形
		var ref := nbasis * (src_n[ia] + src_n[ib] + src_n[ic])
		if face.dot(ref) > 0.0:   # Godot 正面為順時針：(b-a)×(c-a) 應朝內
			var tmp := b
			b = c
			c = tmp
		else:
			face = -face
		var n := face.normalized()
		verts.append_array([a, b, c])
		normals.append_array([n, n, n])


# ───────── 形狀工廠（低多邊形，分段數刻意偏低，參數同網頁版 G） ─────────

static func box(w: float, h: float, d: float) -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3(w, h, d)
	return m


static func cyl(rt: float, rb: float, h: float, seg := 8) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = seg
	m.rings = 0
	return m


static func cone(r: float, h: float, seg := 8) -> Mesh:
	return cyl(0.0, r, h, seg)


static func sphere(r: float, w := 8, h := 6) -> Mesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = w
	m.rings = h - 1
	return m


# 上半球（開口朝下）
static func dome(r: float, w := 10, h := 5) -> Mesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r
	m.is_hemisphere = true
	m.radial_segments = w
	m.rings = h - 1
	return m


# 二十面體；detail 為每條邊再細分的次數（同 Three.js IcosahedronGeometry）
static func ico(r: float, detail := 0) -> Mesh:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var base: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	var faces := [
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
	]
	var n := detail + 1
	var verts := PackedVector3Array()
	for f in range(0, faces.size(), 3):
		var a := base[faces[f]]
		var b := base[faces[f + 1]]
		var c := base[faces[f + 2]]
		var p := func(i: int, j: int) -> Vector3:
			return (a + (b - a) * float(i) / n + (c - a) * float(j) / n).normalized() * r
		for i in n:
			for j in n - i:
				verts.append_array([p.call(i, j), p.call(i + 1, j), p.call(i, j + 1)])
				if j < n - 1 - i:
					verts.append_array([p.call(i + 1, j), p.call(i + 1, j + 1), p.call(i, j + 1)])
	var normals := PackedVector3Array()
	for v in verts:
		normals.append(v.normalized())
	return array_mesh(verts, normals)


# 圓環：在 XY 平面、繞 Z 軸，arc 可只畫一段（同 Three.js TorusGeometry）
static func torus(r: float, tube: float, radial := 6, tubular := 12, arc := TAU) -> Mesh:
	var pts: Array[Vector3] = []
	var nrm: Array[Vector3] = []
	for j in radial + 1:
		var v := float(j) / radial * TAU
		for i in tubular + 1:
			var u := float(i) / tubular * arc
			var p := Vector3((r + tube * cos(v)) * cos(u), (r + tube * cos(v)) * sin(u), tube * sin(v))
			pts.append(p)
			nrm.append((p - Vector3(r * cos(u), r * sin(u), 0.0)).normalized())
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for j in range(1, radial + 1):
		for i in range(1, tubular + 1):
			var a := (tubular + 1) * j + i - 1
			var b := (tubular + 1) * (j - 1) + i - 1
			var c := (tubular + 1) * (j - 1) + i
			var d := (tubular + 1) * j + i
			for k in [a, b, d, b, c, d]:
				verts.append(pts[k])
				normals.append(nrm[k])
	return array_mesh(verts, normals)
