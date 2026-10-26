# 角色骨架（Rig）：與網頁版 render/rig.js 相同的關節階層，動畫只轉動關節
#   root（位置/朝向）→ body（整體姿勢，樞紐在腳底）→ head / arm_r / arm_l / leg_r / leg_l；手掌掛點 hand_r / hand_l
# 角色面向 +Z，右側為 -X；四肢往 -Y 延伸。造型由 view/styles/ 建立，零件透過 kit 加入
class_name Rig
extends Node3D

var body := Node3D.new()
var head := Node3D.new()
var arm_r := Node3D.new()
var arm_l := Node3D.new()
var leg_r := Node3D.new()
var leg_l := Node3D.new()
var hand_r := Node3D.new()
var hand_l := Node3D.new()
var height := 2.0
var kit := PartKit.new()
var weapon_main: Node3D = null      # 掛在 hand_r
var weapon_offhand: Node3D = null   # 掛在 arm_l（盾）
var weapon_left: Node3D = null      # 掛在 hand_l（弓、左手的匕首）
var weapon_gem: Node3D = null       # 法杖寶石（自轉）
var weapon_model: StringName = &""

var _weapon_kit: PartKit = null
var _joints: Dictionary
var _flash := 0.0


# 關節位置 j：{ neck, shoulder_y, shoulder_x, arm_len, hip_y, hip_x, height, scale? }
# Godot 預設的 rotation_order 就是 YXZ（先前後抬起，再水平揮動），與網頁版關節相同
func _init(j: Dictionary) -> void:
	_joints = j
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


# 角色建好後呼叫：每個關節的零件合併成少數幾個 mesh
func optimize() -> Rig:
	kit.merge_static(self, _anchors())
	return self


func _anchors() -> Array[Node3D]:
	return [self, body, head, arm_r, arm_l, leg_r, leg_l, hand_r, hand_l]


## 記下合併後的零件（共用 mesh，材質只記顏色），之後同種角色用 from_template 直接組出，不必重新合併
func to_template() -> Dictionary:
	var parts: Array[Dictionary] = []
	var anchors := _anchors()
	for i in anchors.size():
		for child in anchors[i].get_children():
			if child is MeshInstance3D:
				var m: StandardMaterial3D = child.material_override
				parts.append({
					"anchor": i, "mesh": child.mesh, "color": m.albedo_color,
					"glow": m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "shadow": child.cast_shadow,
				})
	return {"joints": _joints, "parts": parts}


# 每個角色仍有自己的材質，受擊閃白互不影響
static func from_template(t: Dictionary) -> Rig:
	var rig := Rig.new(t.joints)
	var anchors := rig._anchors()
	for p: Dictionary in t.parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		mi.material_override = rig.kit.mat(p.color, p.glow)
		mi.cast_shadow = p.shadow
		anchors[p.anchor].add_child(mi)
	return rig


# 換武器外觀（DarkFantasy.weapon 建立，main 掛右手、offhand 掛左臂）
func set_weapon(model: StringName) -> void:
	if model == weapon_model:
		return
	weapon_model = model
	for n in [weapon_main, weapon_offhand, weapon_left]:
		if n != null:
			n.queue_free()
	var w := DarkFantasy.weapon(model)
	_weapon_kit = w.get("kit")
	weapon_main = w.get("main")
	weapon_offhand = w.get("offhand")
	weapon_left = w.get("left")
	weapon_gem = w.get("gem")
	if weapon_main != null:
		hand_r.add_child(weapon_main)
	if weapon_offhand != null:
		arm_l.add_child(weapon_offhand)
	if weapon_left != null:
		hand_l.add_child(weapon_left)


# 受擊閃白，k 為 0~1（自發光零件不受影響）
func set_flash(k: float) -> void:
	if k == _flash:   # 和上次一樣就不動材質（每幀改材質參數很慢，D5）
		return
	_flash = k
	kit.set_flash(k)
	if _weapon_kit != null:
		_weapon_kit.set_flash(k)


# 零件（MeshInstance3D）數量，供效能檢查
func mesh_count() -> int:
	return PartKit.mesh_instances(self).size()
