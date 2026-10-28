# 角色骨架（Rig）：與網頁版 render/rig.js 相同的關節階層，動畫只轉動關節
#   root（位置/朝向）→ body（整體姿勢，樞紐在腳底）→ head / arm_r / arm_l / leg_r / leg_l；手掌掛點 hand_r / hand_l 在拳頭中心
# 拳頭模型與手持武器都掛在手掌掛點上（武器的 grip 對齊掛點，見 DarkFantasy._hold），要轉武器就轉手掌掛點
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
var weapon_offhand: Node3D = null   # 掛在左前臂掛點 forearm_l（盾）
var weapon_left: Node3D = null      # 掛在 hand_l（弓、左手的匕首）
var weapon_back: Node3D = null       # 背在身上的（弓的箭袋），掛在背部掛點 back
var weapon_quiver_arrows: Array = []   # 箭袋裡露出的箭（照剩幾發顯示）
var weapon_nock: Node3D = null       # 掛在 hand_r 的搭弦箭（弓），拉弓時才顯示
var weapon_hold_point: Node3D = null   # 武器上的托舉點（鐵鏟鏟起的怪放這裡），沒有就是 null
var weapon_gem: Node3D = null       # 法杖寶石（自轉）
var weapon_model: StringName = &""
# 身上的掛點（關節資料的 mounts：名稱 → 位置）：back / hip_l / hip_r 在 body、head 在 head、forearm_l 在 arm_l。
# 用法同手掌掛點：東西用 DarkFantasy._hold 掛上去。沒有設 mounts 的骨架（骷髏）就是空的
var mount_nodes: Dictionary = {}

var _weapon_kit: PartKit = null
var _joints: Dictionary
var _flash := 0.0


# 關節位置 j：{ neck, shoulder_y, shoulder_x, grip（肩膀到拳頭中心）, hip_y, hip_x, height, scale?, mounts?, neck_z?, shoulder_z?, hip_z? }
# （_z：前後位移，四足的屍犬把前腳（arm）放前面、後腳（leg）放後面）
# Godot 預設的 rotation_order 就是 YXZ（先前後抬起，再水平揮動），與網頁版關節相同
func _init(j: Dictionary) -> void:
	_joints = j
	add_child(body)
	for joint: Node3D in [head, arm_r, arm_l, leg_r, leg_l]:
		body.add_child(joint)
	arm_r.add_child(hand_r)
	arm_l.add_child(hand_l)
	head.position = Vector3(0.0, j.neck, j.get("neck_z", 0.0))
	arm_r.position = Vector3(-j.shoulder_x, j.shoulder_y, j.get("shoulder_z", 0.0))
	arm_l.position = Vector3(j.shoulder_x, j.shoulder_y, j.get("shoulder_z", 0.0))
	leg_r.position = Vector3(-j.hip_x, j.hip_y, j.get("hip_z", 0.0))
	leg_l.position = Vector3(j.hip_x, j.hip_y, j.get("hip_z", 0.0))
	hand_r.position.y = -j.grip
	hand_l.position.y = -j.grip
	var s: float = j.get("scale", 1.0)
	body.scale = Vector3.ONE * s
	height = j.height * s
	var mounts: Dictionary = j.get("mounts", {})
	for mount: StringName in mounts:
		var n := Node3D.new()
		n.position = mounts[mount]
		_mount_parent(mount).add_child(n)
		mount_nodes[mount] = n


func _mount_parent(mount: StringName) -> Node3D:
	match mount:
		&"head":
			return head
		&"forearm_l":
			return arm_l
	return body


# 角色建好後呼叫：每個關節的零件合併成少數幾個 mesh
func optimize() -> Rig:
	kit.merge_static(self, _anchors() + mount_nodes.values())   # 掛點也當 anchor：還沒掛東西時是空節點，不列進來會被合併清掉
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
	for n in [weapon_main, weapon_offhand, weapon_left, weapon_nock, weapon_back]:
		if n != null:
			n.queue_free()
	var w := DarkFantasy.weapon(model)
	_weapon_kit = w.get("kit")
	weapon_main = w.get("main")
	weapon_offhand = w.get("offhand")
	weapon_left = w.get("left")
	weapon_hold_point = w.get("hold_point")
	weapon_back = w.get("back")
	weapon_quiver_arrows = w.get("quiver_arrows", [])
	if weapon_back != null:
		(mount_nodes.get(&"back", body) as Node3D).add_child(weapon_back)
	weapon_nock = w.get("nock")
	if weapon_nock != null:
		hand_r.add_child(weapon_nock)
	weapon_gem = w.get("gem")
	if weapon_main != null:
		hand_r.add_child(weapon_main)
	if weapon_offhand != null:
		(mount_nodes.get(&"forearm_l", arm_l) as Node3D).add_child(weapon_offhand)
	if weapon_left != null:
		hand_l.add_child(weapon_left)


# 武器掛點（DarkFantasy._hold 記的 mounts，例如 grip、string）的世界座標；model 要在場景樹裡
static func mount_point(model: Node3D, mount: StringName) -> Vector3:
	return model.to_global(model.get_meta(&"mounts")[mount])


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
