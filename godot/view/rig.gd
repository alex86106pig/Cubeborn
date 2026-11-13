# 角色骨架（Rig）：動畫只轉動關節
#   root（位置/朝向）→ body（整體姿勢，樞紐在腳底）→ head / arm_r / arm_l（上臂）/ leg_r / leg_l（大腿）
#   arm_* → forearm_*（手肘，只彎 rotation.x，負的往前彎）→ 手掌掛點 hand_*（拳頭中心）→ 手持 held_*；leg_* → shin_*（膝蓋，正的往後彎）
# 拳頭模型掛在手掌掛點、手持武器掛在手持關節（平常跟手掌重合，武器的 grip 對齊，見 DarkFantasy._hold）；要轉武器就轉手掌掛點，
# 死掉時武器從手上掉下去就動手持關節（HeldDrop）
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
var forearm_r := Node3D.new()
var forearm_l := Node3D.new()
var shin_r := Node3D.new()
var shin_l := Node3D.new()
var held_r := Node3D.new()   # 右手、左手拿的東西掛這裡（平常是單位矩陣）
var held_l := Node3D.new()
var height := 2.0
var kit := PartKit.new()
var weapon_main: Node3D = null      # 掛在 held_r
var weapon_offhand: Node3D = null   # 掛在左前臂掛點 forearm_l（盾）
var weapon_left: Node3D = null      # 掛在 held_l（弓、左手的匕首）
var weapon_back: Node3D = null       # 背在身上的（弓的箭袋），掛在背部掛點 back
var weapon_quiver_arrows: Array = []   # 箭袋裡露出的箭（照剩幾發顯示）
var weapon_nock: Node3D = null       # 掛在 hand_r 的搭弦箭（弓），拉弓時才顯示
var weapon_hold_point: Node3D = null   # 武器上的托舉點（鐵鏟鏟起的怪放這裡），沒有就是 null
var weapon_gem: Node3D = null       # 法杖寶石（自轉）
var weapon_model: StringName = &""          # 主手的模型
var weapon_offhand_model: StringName = &""  # 副手的模型（沒有副手是空的）
# 身上的掛點（關節資料的 mounts：名稱 → 位置）：back / hip_l / hip_r 在 body、head 在 head、forearm_l 在前臂 forearm_l（前臂座標）。
# 用法同手掌掛點：東西用 DarkFantasy._hold 掛上去。沒有設 mounts 的骨架（骷髏）就是空的
var mount_nodes: Dictionary = {}

var _weapon_kits: Array[PartKit] = []
var _joints: Dictionary
var _flash := 0.0


# 關節位置 j：{ neck, shoulder_y, shoulder_x, grip（肩膀到拳頭中心）, elbow（肩膀到手肘）, hip_y, hip_x, knee（髖關節到膝蓋）,
#   height, scale?, mounts?, neck_z?, shoulder_z?, hip_z? }（_z：前後位移，四足的屍犬把前腳（arm）放前面、後腳（leg）放後面）
# 腳伸直時腳底在 body 的 y = 0（hip_y = 大腿 + 小腿的長度，BodyPose 的 IK 照這個算）
# Godot 預設的 rotation_order 就是 YXZ（先前後抬起，再水平揮動），與網頁版關節相同
func _init(j: Dictionary) -> void:
	_joints = j
	add_child(body)
	for joint: Node3D in [head, arm_r, arm_l, leg_r, leg_l]:
		body.add_child(joint)
	arm_r.add_child(forearm_r)
	arm_l.add_child(forearm_l)
	forearm_r.add_child(hand_r)
	forearm_l.add_child(hand_l)
	hand_r.add_child(held_r)
	hand_l.add_child(held_l)
	leg_r.add_child(shin_r)
	leg_l.add_child(shin_l)
	head.position = Vector3(0.0, j.neck, j.get("neck_z", 0.0))
	arm_r.position = Vector3(-j.shoulder_x, j.shoulder_y, j.get("shoulder_z", 0.0))
	arm_l.position = Vector3(j.shoulder_x, j.shoulder_y, j.get("shoulder_z", 0.0))
	leg_r.position = Vector3(-j.hip_x, j.hip_y, j.get("hip_z", 0.0))
	leg_l.position = Vector3(j.hip_x, j.hip_y, j.get("hip_z", 0.0))
	var elbow := elbow_of(j)
	var knee := knee_of(j)
	forearm_r.position.y = -elbow
	forearm_l.position.y = -elbow
	hand_r.position.y = elbow - j.grip
	hand_l.position.y = elbow - j.grip
	shin_r.position.y = -knee
	shin_l.position.y = -knee
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
			return forearm_l
	return body


# 上臂長（肩膀到手肘）、大腿長（髖關節到膝蓋）；關節資料沒寫就取一半
static func elbow_of(j: Dictionary) -> float:
	return j.get("elbow", j.grip * 0.5)


static func knee_of(j: Dictionary) -> float:
	return j.get("knee", j.hip_y * 0.5)


# 角色建好後呼叫：每個關節的零件合併成少數幾個 mesh
func optimize() -> Rig:
	kit.merge_static(self, _anchors() + mount_nodes.values())   # 掛點也當 anchor：還沒掛東西時是空節點，不列進來會被合併清掉
	return self


# 順序 = SkinnedRig.BONE_NAMES（模板的 anchor 編號、蒙皮的骨頭編號都照這個）
func _anchors() -> Array[Node3D]:
	return [self, body, head, arm_r, arm_l, leg_r, leg_l, hand_r, hand_l, forearm_r, forearm_l, shin_r, shin_l, held_r, held_l]


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


# 換武器外觀：主手 DarkFantasy.weapon（main 掛右手、left 掛左手）、副手 DarkFantasy.offhand（盾掛左臂、匕首掛左手）
func set_weapon(model: StringName, off_model: StringName = &"") -> void:
	if model == weapon_model and off_model == weapon_offhand_model:
		return
	weapon_model = model
	weapon_offhand_model = off_model
	for n in [weapon_main, weapon_offhand, weapon_left, weapon_nock, weapon_back]:
		if n != null:
			n.queue_free()
	var w := DarkFantasy.weapon(model)
	var off := DarkFantasy.offhand(off_model) if off_model != &"" else {}
	_weapon_kits.clear()
	for k: Variant in [w.get("kit"), off.get("kit")]:
		if k != null:
			_weapon_kits.append(k)
	weapon_main = w.get("main")
	weapon_offhand = off.get("offhand")
	weapon_left = w.get("left", off.get("left"))
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
		held_r.add_child(weapon_main)
	if weapon_offhand != null:
		(mount_nodes.get(&"forearm_l", forearm_l) as Node3D).add_child(weapon_offhand)
	if weapon_left != null:
		held_l.add_child(weapon_left)
	if _ghost_overlay != null:
		set_ghost(_ghost_overlay, _ghost_transparency)   # 新的武器零件也要半透明


# 冤魂（Player.is_ghost）：整隻半透明、蓋一層顏色、不投影。材質是同種角色共用的，所以顏色用每個零件自己的 material_overlay
var _ghost_overlay: Material = null
var _ghost_transparency := 0.0


func set_ghost(overlay: Material, transparency: float) -> void:
	_ghost_overlay = overlay
	_ghost_transparency = transparency
	for mi in PartKit.mesh_instances(self):
		mi.transparency = transparency
		mi.material_overlay = overlay
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# 武器掛點（DarkFantasy._hold 記的 mounts，例如 grip、string）的世界座標；model 要在場景樹裡
static func mount_point(model: Node3D, mount: StringName) -> Vector3:
	return model.to_global(model.get_meta(&"mounts")[mount])


# 受擊閃白，k 為 0~1（自發光零件不受影響）
func set_flash(k: float) -> void:
	if k == _flash:   # 和上次一樣就不動材質（每幀改材質參數很慢，D5）
		return
	_flash = k
	kit.set_flash(k)
	for wk in _weapon_kits:
		wk.set_flash(k)


# 零件（MeshInstance3D）數量，供效能檢查
func mesh_count() -> int:
	return PartKit.mesh_instances(self).size()


## 骨架裡某個節點在世界座標的 transform：沿父節點乘到骨架根節點，再接上骨架本身（不靠場景樹的 global_transform，不在樹裡也能算）
func to_world(node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != self and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return (global_transform if is_inside_tree() else transform) * t


# 角色本體的頂點（去掉重複的）：[[關節, 關節座標的頂點], …]，第一次用到才算（本體零件建好就不變）。
# 用頂點不用外框：外框的角轉斜時比零件低，貼地會留縫
var _shape: Array = []


## 角色本體最低點在角色座標的高度（照目前的關節角度；不在場景樹裡也能算）。
## 只算 body ~ shin 底下的零件：手上的武器（held_*）、掛點上的盾與箭袋、搭弦箭都不算
func body_bottom() -> float:
	if _shape.is_empty():
		for joint: Node3D in _anchors().slice(1, 13):
			var seen := {}
			for child in joint.get_children():
				if child is MeshInstance3D and child != weapon_nock:
					var t := (child as Node3D).transform
					for v: Vector3 in (child as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
						seen[(t * v).snappedf(0.001)] = true
			if not seen.is_empty():
				_shape.append([joint, PackedVector3Array(seen.keys())])
	var low := INF
	for entry: Array in _shape:
		var t := Transform3D.IDENTITY
		var n: Node3D = entry[0]
		while n != self:
			t = n.transform * t
			n = n.get_parent()
		for c: Vector3 in entry[1]:
			low = minf(low, (t * c).y)
	return low
