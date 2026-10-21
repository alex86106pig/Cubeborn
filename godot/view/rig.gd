# 角色骨架（Rig）：與網頁版 render/rig.js 相同的關節階層，動畫只轉動關節
#   root（位置/朝向）→ body（整體姿勢，樞紐在腳底）→ head / arm_r / arm_l / leg_r / leg_l；手掌掛點 hand_r / hand_l
# 角色面向 +Z，右側為 -X；四肢往 -Y 延伸。目前零件是暫用方塊，里程碑 5 換成暗黑幻想造型
class_name Rig
extends Node3D

# 關節位置（照搬 darkFantasy.js 的 KNIGHT_JOINTS / SKELETON_JOINTS）
const KNIGHT_JOINTS := {
	"neck": 1.6, "shoulder_y": 1.55, "shoulder_x": 0.36, "arm_len": 0.7,
	"hip_y": 0.95, "hip_x": 0.14, "height": 2.1,
}
const SKELETON_JOINTS := {
	"neck": 1.5, "shoulder_y": 1.45, "shoulder_x": 0.3, "arm_len": 0.68,
	"hip_y": 0.92, "hip_x": 0.12, "height": 1.95,
}
const BOSS_SCALE := 1.85

# 暗黑幻想配色（darkFantasy.js 的 C）
const C := {
	"steel": Color("8a93a3"), "steel_dark": Color("4a505c"), "iron": Color("2a2d33"), "cape": Color("6b1d24"),
	"leather": Color("3b2a20"), "bone": Color("d8d2bf"), "bone_dark": Color("a39d88"), "socket": Color("1a1612"),
	"eye_red": Color("ff3b2f"), "hood": Color("2c2a35"), "rust": Color("8a6a4a"), "death_armor": Color("23262e"),
	"death_eye": Color("55e0ff"), "wood": Color("4a3526"),
}

var body := Node3D.new()
var head := Node3D.new()
var arm_r := Node3D.new()
var arm_l := Node3D.new()
var leg_r := Node3D.new()
var leg_l := Node3D.new()
var hand_r := Node3D.new()
var hand_l := Node3D.new()
var height := 2.0
var weapon_main: Node3D = null      # 掛在 hand_r
var weapon_offhand: Node3D = null   # 掛在 arm_l（盾）
var weapon_model: StringName = &""

var _materials: Array[StandardMaterial3D] = []
var _body_material_count := -1   # 角色本體的材質數，換武器時只保留這些


# Godot 預設的 rotation_order 就是 YXZ（先前後抬起，再水平揮動），與網頁版關節相同
func _init(j: Dictionary = KNIGHT_JOINTS) -> void:
	add_child(body)
	for joint: Node3D in [head, arm_r, arm_l, leg_r, leg_l]:
		body.add_child(joint)
	arm_r.add_child(hand_r)
	arm_l.add_child(hand_l)
	head.position.y = j.neck
	arm_r.position = Vector3(-j.shoulder_x, j.shoulder_y, 0.0)
	arm_l.position = Vector3(j.shoulder_x, j.shoulder_y, 0.0)
	leg_r.position = Vector3(-j.hip_x, j.hip_y, 0.0)
	leg_l.position = Vector3(j.hip_x, j.hip_y, 0.0)
	hand_r.position.y = -j.arm_len
	hand_l.position.y = -j.arm_len
	var s: float = j.get("scale", 1.0)
	body.scale = Vector3.ONE * s
	height = j.height * s


static func knight_placeholder() -> Rig:
	var rig := Rig.new()
	var armor := Color("8a93a3")
	var trim := Color("4a505c")
	rig.box(rig.body, Vector3(0.56, 0.62, 0.36), Vector3(0, 1.28, 0), armor)
	rig.box(rig.body, Vector3(0.5, 0.26, 0.32), Vector3(0, 0.9, 0), trim)
	rig.box(rig.body, Vector3(0.56, 0.95, 0.04), Vector3(0, 1.05, -0.22), Color("6b1d24"))
	rig.box(rig.head, Vector3(0.38, 0.38, 0.38), Vector3(0, 0.2, 0), armor)
	rig.box(rig.head, Vector3(0.3, 0.04, 0.03), Vector3(0, 0.24, 0.2), Color("1a1612"))
	for arm in [rig.arm_r, rig.arm_l]:
		rig.box(arm, Vector3(0.17, 0.62, 0.17), Vector3(0, -0.3, 0), armor)
	for leg in [rig.leg_r, rig.leg_l]:
		rig.box(leg, Vector3(0.2, 0.9, 0.2), Vector3(0, -0.45, 0), trim)
		rig.box(leg, Vector3(0.16, 0.12, 0.27), Vector3(0, -0.9, 0.04), Color("2a2d33"))
	return rig


# 骷髏戰士 / 骷髏弓手（hood = true 時加兜帽與弓）
static func skeleton_placeholder(hood: bool) -> Rig:
	var rig := Rig.new(SKELETON_JOINTS)
	var bone: Color = C.bone
	rig.box(rig.body, Vector3(0.36, 0.5, 0.2), Vector3(0, 1.2, 0), bone)
	rig.box(rig.body, Vector3(0.3, 0.12, 0.16), Vector3(0, 0.92, 0), bone)
	rig.box(rig.head, Vector3(0.3, 0.32, 0.32), Vector3(0, 0.17, 0), bone)
	rig.box(rig.head, Vector3(0.22, 0.05, 0.03), Vector3(0, 0.2, 0.17), C.eye_red, true)
	if hood:
		rig.box(rig.head, Vector3(0.38, 0.36, 0.38), Vector3(0, 0.22, -0.03), C.hood)
		rig.box(rig.body, Vector3(0.5, 0.9, 0.03), Vector3(0, 1.0, -0.16), C.hood)
	for arm in [rig.arm_r, rig.arm_l]:
		rig.box(arm, Vector3(0.08, 0.62, 0.08), Vector3(0, -0.3, 0), bone)
	for leg in [rig.leg_r, rig.leg_l]:
		rig.box(leg, Vector3(0.09, 0.88, 0.09), Vector3(0, -0.44, 0), bone)
	if hood:
		var bow := Node3D.new()   # 弓掛在左手，弓身沿 Z
		bow.position.y = 0.38
		rig.box(bow, Vector3(0.05, 0.05, 0.9), Vector3.ZERO, C.wood)
		rig.hand_l.add_child(bow)
	else:
		rig.add_sword(rig.hand_r, C.rust, 0.8, false)
	return rig


# 亡骸騎士（Boss）：騎士骨架放大 1.85 倍、黑甲、發光長劍
static func boss_placeholder() -> Rig:
	var j := KNIGHT_JOINTS.duplicate()
	j["scale"] = BOSS_SCALE
	var rig := Rig.new(j)
	var armor: Color = C.death_armor
	rig.box(rig.body, Vector3(0.56, 0.62, 0.36), Vector3(0, 1.28, 0), armor)
	rig.box(rig.body, Vector3(0.5, 0.26, 0.32), Vector3(0, 0.9, 0), C.iron)
	rig.box(rig.body, Vector3(0.56, 0.95, 0.04), Vector3(0, 1.05, -0.22), Color("1c1a22"))
	rig.box(rig.head, Vector3(0.38, 0.38, 0.38), Vector3(0, 0.2, 0), armor)
	rig.box(rig.head, Vector3(0.3, 0.04, 0.03), Vector3(0, 0.24, 0.2), C.death_eye, true)
	for s in [-1.0, 1.0]:
		var horn := rig.box(rig.head, Vector3(0.08, 0.4, 0.08), Vector3(s * 0.24, 0.42, 0), C.bone_dark)
		horn.rotation.z = -s * 0.9
	for arm in [rig.arm_r, rig.arm_l]:
		rig.box(arm, Vector3(0.17, 0.62, 0.17), Vector3(0, -0.3, 0), armor)
	for leg in [rig.leg_r, rig.leg_l]:
		rig.box(leg, Vector3(0.2, 0.9, 0.2), Vector3(0, -0.45, 0), C.iron)
	rig.add_sword(rig.hand_r, Color("7fe8ff"), 1.35, true)
	return rig


# 長劍：掛在手掌，劍身沿局部 +Y，整組轉 2.8 弧度（darkFantasy.js 的 longSword）
func add_sword(parent: Node3D, blade: Color, length: float, glow: bool) -> Node3D:
	var g := Node3D.new()
	g.rotation.x = 2.8
	box(g, Vector3(0.06, 0.25, 0.06), Vector3.ZERO, C.leather)
	box(g, Vector3(0.36, 0.05, 0.07), Vector3(0, 0.14, 0), C.iron)
	box(g, Vector3(0.09, length, 0.035), Vector3(0, 0.16 + length / 2.0, 0), blade, glow)
	parent.add_child(g)
	return g


func box(parent: Node3D, size: Vector3, at: Vector3, color: Color, glow := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if glow:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		_materials.append(mat)
	mesh.material_override = mat
	parent.add_child(mesh)
	return mesh


# 換武器外觀（照搬 darkFantasy.js 的 swordShield / staff 掛點與角度）
func set_weapon(model: StringName) -> void:
	if model == weapon_model:
		return
	weapon_model = model
	if _body_material_count < 0:
		_body_material_count = _materials.size()
	_materials.resize(_body_material_count)   # 舊武器的材質不再閃白
	for n in [weapon_main, weapon_offhand]:
		if n != null:
			n.queue_free()
	weapon_main = null
	weapon_offhand = null
	match model:
		&"swordShield":
			weapon_main = add_sword(hand_r, Color("b8c0cc"), 0.95, false)
			weapon_offhand = Node3D.new()
			weapon_offhand.position = Vector3(0.18, -0.4, 0)
			box(weapon_offhand, Vector3(0.07, 0.75, 0.46), Vector3(0, 0, 0), Color("6b1d24"))
			box(weapon_offhand, Vector3(0.09, 0.6, 0.05), Vector3(0, 0, 0), Color("8a93a3"))
			arm_l.add_child(weapon_offhand)
		&"staff":
			weapon_main = Node3D.new()
			box(weapon_main, Vector3(0.07, 1.8, 0.07), Vector3(0, 0.3, 0), Color("4a3526"))
			box(weapon_main, Vector3(0.18, 0.18, 0.18), Vector3(0, 1.3, 0), Color("b48cff"), true)
			hand_r.add_child(weapon_main)


# 受擊閃白，k 為 0~1（自發光零件不受影響）
func set_flash(k: float) -> void:
	for m in _materials:
		m.emission_enabled = k > 0.0
		m.emission = Color(k, k, k)
