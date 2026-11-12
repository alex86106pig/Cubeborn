# 小怪用的蒙皮角色（D5 效能）：同種角色的零件（Rig 合併後的模板）合成一個網格，用 15 根骨頭的 Skeleton3D 擺姿勢
# 每隻怪只剩 1~2 次繪製（原本每個關節、每種顏色各一次，約 13~16 次）；顏色放在頂點色
# 關節（body / head / arm_r…）是只存數值的 Joint，介面同 Node3D 的 position / rotation / scale，EnemyAnimator 不必改；
# 畫面層每幀呼叫 flush() 把關節寫進骨架。頂點存在各自關節的座標系，綁定姿勢用單位矩陣（骨架姿勢 × 頂點 = 位置）
class_name SkinnedRig
extends Node3D

# 骨頭順序 = Rig._anchors()：0 root、1 body、2 head、3 arm_r、4 arm_l、5 leg_r、6 leg_l、7 hand_r、8 hand_l、
# 9 forearm_r、10 forearm_l、11 shin_r、12 shin_l、13 held_r、14 held_l（手掌掛在前臂下、手持掛在手掌下）
const BONE_NAMES: Array[String] = ["root", "body", "head", "arm_r", "arm_l", "leg_r", "leg_l", "hand_r", "hand_l",
	"forearm_r", "forearm_l", "shin_r", "shin_l", "held_r", "held_l"]
const BONE_PARENTS: Array[int] = [-1, 0, 1, 1, 1, 1, 1, 9, 10, 3, 4, 5, 6, 7, 8]
const CULL_MARGIN := 2.5   # 自訂外框：倒下、舉手的姿勢都在這個範圍內

var body := Joint.new()
var head := Joint.new()
var arm_r := Joint.new()
var arm_l := Joint.new()
var leg_r := Joint.new()
var leg_l := Joint.new()
var hand_r := Joint.new()
var hand_l := Joint.new()
var forearm_r := Joint.new()
var forearm_l := Joint.new()
var shin_r := Joint.new()
var shin_l := Joint.new()
var held_r := Joint.new()
var held_l := Joint.new()
var height := 2.0
var skeleton := Skeleton3D.new()

var _joints: Array[Joint] = []
var _lit_material: StandardMaterial3D
var _flash := 0.0
var _base_tint := Color.WHITE     # 冤魂的底色（set_ghost）
var _status_tint := Color.WHITE   # 冰凍 / 中毒的染色（set_status_tint）
var _held_model := &""                # 手上拿的武器（set_held_weapon）
var _held_nodes: Array[Node3D] = []

static var _built: Dictionary = {}   # 種類 -> { meshes, skin }（同種只合成一次）


class Joint:
	var position := Vector3.ZERO
	var rotation := Vector3.ZERO   # 順序 YXZ，同 Node3D 預設
	var scale := Vector3.ONE
	var flushed_position := Vector3.INF   # 上次寫進骨架的值（flush 比對用）
	var flushed_rotation := Vector3.INF
	var flushed_scale := Vector3.INF


# t：Rig.to_template() 的結果（DarkFantasy 依種類快取）
func _init(kind: StringName, t: Dictionary) -> void:
	var j: Dictionary = t.joints
	_joints = [body, head, arm_r, arm_l, leg_r, leg_l, hand_r, hand_l, forearm_r, forearm_l, shin_r, shin_l, held_r, held_l]
	head.position = Vector3(0.0, j.neck, j.get("neck_z", 0.0))
	arm_r.position = Vector3(-j.shoulder_x, j.shoulder_y, j.get("shoulder_z", 0.0))
	arm_l.position = Vector3(j.shoulder_x, j.shoulder_y, j.get("shoulder_z", 0.0))
	leg_r.position = Vector3(-j.hip_x, j.hip_y, j.get("hip_z", 0.0))
	leg_l.position = Vector3(j.hip_x, j.hip_y, j.get("hip_z", 0.0))
	var elbow := Rig.elbow_of(j)
	var knee := Rig.knee_of(j)
	forearm_r.position.y = -elbow
	forearm_l.position.y = -elbow
	hand_r.position.y = elbow - j.grip
	hand_l.position.y = elbow - j.grip
	shin_r.position.y = -knee
	shin_l.position.y = -knee
	var s: float = j.get("scale", 1.0)
	body.scale = Vector3.ONE * s
	height = j.height * s

	for i in BONE_NAMES.size():
		skeleton.add_bone(BONE_NAMES[i])
		if BONE_PARENTS[i] >= 0:
			skeleton.set_bone_parent(i, BONE_PARENTS[i])
	skeleton.name = &"Skeleton"
	add_child(skeleton)
	var built := _build(kind, t)
	var aabb := AABB(Vector3(-CULL_MARGIN, -1.0, -CULL_MARGIN), Vector3(CULL_MARGIN * 2.0, height + 2.0, CULL_MARGIN * 2.0))
	for m: Dictionary in built.meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = m.mesh
		mi.skin = built.skin
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if m.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = aabb
		if m.glow:
			mi.material_override = _glow_material()
		else:
			# 每隻有自己的材質，受擊閃白互不影響；自發光一開始就打開（同 PartKit.mat）
			if _lit_material == null:
				_lit_material = StandardMaterial3D.new()
				_lit_material.vertex_color_use_as_albedo = true
				_lit_material.vertex_color_is_srgb = true
				_lit_material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
				_lit_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				_lit_material.roughness = 1.0
				_lit_material.emission_enabled = true
				_lit_material.emission = Color.BLACK
			mi.material_override = _lit_material
		skeleton.add_child(mi)
		mi.skeleton = mi.get_path_to(skeleton)
	flush()


# 關節的數值寫進骨架（畫面層在動畫更新後呼叫；看不到的怪不必呼叫）
# 和上次寫進去的一樣就跳過（手掌、頭大多不動；站著的怪幾乎全部不動）
func flush() -> void:
	for i in _joints.size():
		var jt := _joints[i]
		if jt.position == jt.flushed_position and jt.rotation == jt.flushed_rotation and jt.scale == jt.flushed_scale:
			continue
		jt.flushed_position = jt.position
		jt.flushed_rotation = jt.rotation
		jt.flushed_scale = jt.scale
		skeleton.set_bone_pose(i + 1, Transform3D(Basis.from_euler(jt.rotation, EULER_ORDER_YXZ) * Basis.from_scale(jt.scale), jt.position))


# 受擊閃白，k 為 0~1；和上次一樣就不動材質（每幀改材質參數很慢）
func set_flash(k: float) -> void:
	if k == _flash or _lit_material == null:
		return
	_flash = k
	_lit_material.emission = Color(k, k, k)


# 道具狀態的染色（v0.33.0：冰凍偏藍、中毒偏綠，Color.WHITE = 沒有）；乘在冤魂的底色上；和上次一樣就不動材質
func set_status_tint(tint: Color) -> void:
	if tint == _status_tint or _lit_material == null:
		return
	_status_tint = tint
	_lit_material.albedo_color = _base_tint * tint


# 冤魂（D6）：整隻半透明、偏藍，不投影
func set_ghost(tint: Color, transparency: float) -> void:
	_base_tint = tint
	if _lit_material != null:
		_lit_material.albedo_color = tint * _status_tint
	for mi in PartKit.mesh_instances(self):
		mi.transparency = transparency
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# 手上拿的武器（持武器的腐屍）：主手掛右手骨頭、副手盾掛左前臂骨頭；model = &"" 拿掉
func set_held_weapon(model: StringName, off_model: StringName = &"") -> void:
	if model == _held_model:
		return
	_held_model = model
	for n in _held_nodes:
		n.queue_free()
	_held_nodes.clear()
	if model == &"":
		return
	var w := DarkFantasy.weapon(model)
	_attach(w.get("main"), "held_r")
	_attach(w.get("left"), "held_l")
	if off_model != &"":
		_attach(DarkFantasy.offhand(off_model).get("offhand"), "forearm_l")


func _attach(node: Variant, bone: String) -> void:
	if node == null:
		return
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skeleton.add_child(ba)
	ba.add_child(node as Node3D)
	_held_nodes.append(ba)


func mesh_count() -> int:
	return PartKit.mesh_instances(self).size()


# 同一個模板只合成一次：依（自發光、投影）分組，每組一個網格；頂點帶骨頭編號（= 關節）與權重 1
static func _build(kind: StringName, t: Dictionary) -> Dictionary:
	if _built.has(kind):
		return _built[kind]
	var groups: Dictionary = {}   # "glow|shadow" -> { verts, normals, colors, bones, glow, shadow }
	for p: Dictionary in t.parts:
		var shadow: bool = p.shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var gk := "%s|%s" % [p.glow, shadow]
		if not groups.has(gk):
			groups[gk] = {"verts": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray(),
				"bones": PackedInt32Array(), "glow": p.glow, "shadow": shadow}
		# Packed 陣列放在 Dictionary 裡是複本，取出來改完要放回去
		var g: Dictionary = groups[gk]
		var arrays := (p.mesh as Mesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var gv: PackedVector3Array = g.verts
		var gn: PackedVector3Array = g.normals
		var gc: PackedColorArray = g.colors
		var gb: PackedInt32Array = g.bones
		gv.append_array(verts)
		gn.append_array(arrays[Mesh.ARRAY_NORMAL])
		for v in verts.size():
			gc.append(p.color)
			gb.append_array([p.anchor, 0, 0, 0])
		g.verts = gv
		g.normals = gn
		g.colors = gc
		g.bones = gb
	var meshes := []
	for g: Dictionary in groups.values():
		var weights := PackedFloat32Array()
		weights.resize(g.verts.size() * 4)
		for v in g.verts.size():
			weights[v * 4] = 1.0
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.verts
		arrays[Mesh.ARRAY_NORMAL] = g.normals
		arrays[Mesh.ARRAY_COLOR] = g.colors
		arrays[Mesh.ARRAY_BONES] = g.bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		meshes.append({"mesh": am, "glow": g.glow, "shadow": g.shadow})
	var skin := Skin.new()
	for i in BONE_NAMES.size():
		skin.add_bind(i, Transform3D.IDENTITY)
	_built[kind] = {"meshes": meshes, "skin": skin}
	return _built[kind]


static var _glow: StandardMaterial3D = null


static func _glow_material() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.vertex_color_use_as_albedo = true
		_glow.vertex_color_is_srgb = true
	return _glow
