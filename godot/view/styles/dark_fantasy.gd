# 造型「暗黑幻想」（照搬網頁版 render/styles/darkFantasy.js）：寫實比例、硬朗多面體（flat shading）、月夜墓地
# 騎士：黑鋼重甲；敵人：骷髏戰士、骷髏弓手、亡骸騎士。零件尺寸、位置、角度與網頁版逐一對應
class_name DarkFantasy
extends RefCounted

const C := {
	"steel": Color("8a93a3"), "steel_dark": Color("4a505c"), "iron": Color("2a2d33"), "cape": Color("6b1d24"),
	"leather": Color("3b2a20"), "bone": Color("d8d2bf"), "bone_dark": Color("a39d88"), "socket": Color("1a1612"),
	"eye_red": Color("ff3b2f"), "hood": Color("2c2a35"), "rust": Color("8a6a4a"), "death_armor": Color("23262e"),
	"death_eye": Color("55e0ff"), "wood": Color("4a3526"),
}

const KNIGHT_JOINTS := {
	"neck": 1.6, "shoulder_y": 1.55, "shoulder_x": 0.36, "arm_len": 0.7,
	"hip_y": 0.95, "hip_x": 0.14, "height": 2.1,
}
const SKELETON_JOINTS := {
	"neck": 1.5, "shoulder_y": 1.45, "shoulder_x": 0.3, "arm_len": 0.68,
	"hip_y": 0.92, "hip_x": 0.12, "height": 1.95,
}
const BOSS_SCALE := 1.85

const BLOOD := Color("d8d2bf")        # 骷髏死亡碎骨（網頁版 colors.blood）
const BOSS_BLOOD := Color("55e0ff")   # 亡骸騎士的死亡、狂暴、召喚（網頁版 colors.bossBlood）

const GROUND_COLORS: Array[Color] = [Color("2b3528"), Color("3a4431"), Color("4a4a3a")]
const ROCK_COLORS: Array[Color] = [Color("55585e"), Color("6a6d72"), Color("46484d")]


static var _templates: Dictionary = {}   # kind -> Rig.to_template()


# 依實體種類建立角色（player / grunt / archer / boss）。
# 同種角色第二次起直接用第一次合併好的零件（一次合併約 3~6 ms，波次一次生成十幾隻會卡頓）
static func character(kind: StringName) -> Rig:
	if _templates.has(kind):
		return Rig.from_template(_templates[kind])
	var rig: Rig
	match kind:
		&"grunt":
			rig = skeleton()
		&"archer":
			rig = skeleton_archer()
		&"boss":
			rig = death_knight()
		_:
			rig = knight()
	_templates[kind] = rig.to_template()
	return rig


# ───────── 角色 ─────────

static func _armored_body(rig: Rig, armor: Color, trim: Color, cape: Color, eye: Variant = null, horns := false) -> void:
	var k := rig.kit
	k.add(rig.body, PartKit.cyl(0.3, 0.24, 0.62, 6), k.mat(armor), {"y": 1.28})
	k.add(rig.body, PartKit.cyl(0.25, 0.3, 0.26, 6), k.mat(trim), {"y": 0.9})
	k.add(rig.body, PartKit.box(0.56, 0.95, 0.04), k.mat(cape), {"y": 1.05, "z": -0.22, "rx": 0.08})
	k.add(rig.body, PartKit.box(0.28, 0.5, 0.02), k.mat(cape), {"y": 0.98, "z": 0.2})

	k.add(rig.head, PartKit.cyl(0.19, 0.21, 0.38, 7), k.mat(armor), {"y": 0.2})
	k.add(rig.head, PartKit.box(0.3, 0.035, 0.03), k.mat(eye, true) if eye != null else k.mat(C.socket), {"y": 0.24, "z": 0.19})
	k.add(rig.head, PartKit.box(0.035, 0.12, 0.42), k.mat(trim), {"y": 0.42})
	if horns:
		for s in [-1.0, 1.0]:
			k.add(rig.head, PartKit.cone(0.06, 0.4, 5), k.mat(C.bone_dark), {"x": s * 0.24, "y": 0.42, "rz": -s * 0.9})

	for pair in [[rig.arm_r, -1.0], [rig.arm_l, 1.0]]:
		var arm: Node3D = pair[0]
		k.add(arm, PartKit.ico(0.17, 0), k.mat(armor), {"x": pair[1] * 0.04, "y": 0.02, "sy": 0.8})
		k.add(arm, PartKit.cyl(0.085, 0.075, 0.4, 6), k.mat(armor), {"y": -0.22})
		k.add(arm, PartKit.box(0.14, 0.17, 0.14), k.mat(trim), {"y": -0.58})
	for leg in [rig.leg_r, rig.leg_l]:
		k.add(leg, PartKit.cyl(0.1, 0.09, 0.45, 6), k.mat(trim), {"y": -0.22})
		k.add(leg, PartKit.cyl(0.095, 0.11, 0.42, 6), k.mat(armor), {"y": -0.64})
		k.add(leg, PartKit.box(0.16, 0.12, 0.27), k.mat(C.iron), {"y": -0.9, "z": 0.04})


# 長劍：劍身沿局部 +Y，整組轉 2.8 弧度
static func _long_sword(k: PartKit, parent: Node3D, blade: Color, guard: Color, length := 1.0, glow: Variant = null) -> Node3D:
	var g := Node3D.new()
	k.add(g, PartKit.cyl(0.03, 0.03, 0.25, 5), k.mat(C.leather))
	k.add(g, PartKit.ico(0.05), k.mat(guard), {"y": -0.15})
	k.add(g, PartKit.box(0.36, 0.05, 0.07), k.mat(guard), {"y": 0.14})
	k.add(g, PartKit.cyl(0.018, 0.055, length, 4), k.mat(glow, true) if glow != null else k.mat(blade),
		{"y": 0.16 + length / 2.0, "sz": 0.35})
	g.rotation.x = 2.8
	parent.add_child(g)
	return g


static func _bow(k: PartKit, parent: Node3D, color: Color) -> void:
	var r := 0.45
	var g := Node3D.new()
	g.rotation.y = PI / 2.0
	g.position.y = r * 0.85
	k.add(g, PartKit.torus(r, 0.025, 4, 9, PI), k.mat(color), {"rx": PI})
	k.add(g, PartKit.cyl(0.005, 0.005, r * 2.0, 3), k.mat(Color("cccccc")), {"rx": PI / 2.0})
	parent.add_child(g)


static func knight() -> Rig:
	var rig := Rig.new(KNIGHT_JOINTS)
	_armored_body(rig, C.steel, C.steel_dark, C.cape)
	return rig.optimize()


static func _skeleton_base(rig: Rig, hood := false) -> void:
	var k := rig.kit
	var bone := k.mat(C.bone)
	k.add(rig.body, PartKit.cyl(0.04, 0.04, 0.55, 5), bone, {"y": 1.15})
	for i in 3:
		k.add(rig.body, PartKit.torus(0.19 - i * 0.02, 0.025, 4, 8), bone, {"y": 1.38 - i * 0.1, "rx": PI / 2.0, "sy": 0.7})
	k.add(rig.body, PartKit.cyl(0.03, 0.03, 0.62, 4), bone, {"y": 1.47, "rz": PI / 2.0})
	k.add(rig.body, PartKit.box(0.3, 0.1, 0.15), bone, {"y": 0.92})
	k.add(rig.body, PartKit.box(0.3, 0.32, 0.02), k.mat(C.hood), {"y": 0.78, "z": 0.09})

	k.add(rig.head, PartKit.ico(0.18, 1), bone, {"y": 0.2, "sy": 1.1})
	k.add(rig.head, PartKit.box(0.17, 0.07, 0.14), k.mat(C.bone_dark), {"y": 0.03, "z": 0.04})
	for s in [-1.0, 1.0]:
		k.add(rig.head, PartKit.sphere(0.05, 5, 4), k.mat(C.socket), {"x": s * 0.07, "y": 0.22, "z": 0.14})
		k.add(rig.head, PartKit.sphere(0.025, 4, 3), k.mat(C.eye_red, true), {"x": s * 0.07, "y": 0.22, "z": 0.17, "shadow": false})
	if hood:
		k.add(rig.head, PartKit.dome(0.24, 7, 4), k.mat(C.hood), {"y": 0.22, "z": -0.03, "rx": -0.3})
		k.add(rig.body, PartKit.box(0.5, 0.9, 0.03), k.mat(C.hood), {"y": 1.0, "z": -0.16, "rx": 0.06})

	for arm in [rig.arm_r, rig.arm_l]:
		k.add(arm, PartKit.cyl(0.03, 0.03, 0.3, 4), bone, {"y": -0.17})
		k.add(arm, PartKit.sphere(0.04, 5, 4), bone, {"y": -0.33})
		k.add(arm, PartKit.cyl(0.028, 0.025, 0.28, 4), bone, {"y": -0.48})
		k.add(arm, PartKit.box(0.07, 0.1, 0.04), bone, {"y": -0.65})
	for leg in [rig.leg_r, rig.leg_l]:
		k.add(leg, PartKit.cyl(0.035, 0.03, 0.42, 4), bone, {"y": -0.22})
		k.add(leg, PartKit.sphere(0.045, 5, 4), bone, {"y": -0.45})
		k.add(leg, PartKit.cyl(0.03, 0.028, 0.4, 4), bone, {"y": -0.67})
		k.add(leg, PartKit.box(0.08, 0.05, 0.18), bone, {"y": -0.9, "z": 0.04})


static func skeleton() -> Rig:
	var rig := Rig.new(SKELETON_JOINTS)
	_skeleton_base(rig)
	_long_sword(rig.kit, rig.hand_r, C.rust, C.iron, 0.8)
	return rig.optimize()


static func skeleton_archer() -> Rig:
	var rig := Rig.new(SKELETON_JOINTS)
	_skeleton_base(rig, true)
	_bow(rig.kit, rig.hand_l, C.wood)
	return rig.optimize()


static func death_knight() -> Rig:
	var j := KNIGHT_JOINTS.duplicate()
	j["scale"] = BOSS_SCALE
	var rig := Rig.new(j)
	_armored_body(rig, C.death_armor, C.iron, Color("1c1a22"), C.death_eye, true)
	_long_sword(rig.kit, rig.hand_r, Color("9aa4b4"), C.iron, 1.35, Color("7fe8ff"))
	return rig.optimize()


# ───────── 玩家武器 ─────────

# → { kit, main（掛右手）, offhand（掛左臂，可為 null）, gem（會自轉，可為 null） }
static func weapon(model: StringName) -> Dictionary:
	match model:
		&"swordShield":
			return _sword_shield()
		&"staff":
			return _staff()
	return {}


static func _sword_shield() -> Dictionary:
	var k := PartKit.new()
	var holder := Node3D.new()
	_long_sword(k, holder, Color("b8c0cc"), C.steel_dark, 0.95)

	var shield := Node3D.new()
	k.add(shield, PartKit.box(0.07, 0.42, 0.46), k.mat(C.cape), {"y": 0.1})
	k.add(shield, PartKit.cone(0.33, 0.42, 4), k.mat(C.cape), {"y": -0.31, "rx": PI, "ry": PI / 4.0, "sx": 0.15, "sz": 0.98})
	k.add(shield, PartKit.box(0.09, 0.44, 0.05), k.mat(C.steel), {"y": 0.1})
	k.add(shield, PartKit.ico(0.07), k.mat(C.steel), {"x": 0.05, "y": 0.1})
	shield.position = Vector3(0.18, -0.4, 0.0)
	k.merge_static(holder, [holder])
	k.merge_static(shield, [shield])
	return {"kit": k, "main": holder, "offhand": shield, "gem": null}


static func _staff() -> Dictionary:
	var k := PartKit.new()
	var g := Node3D.new()
	k.add(g, PartKit.cyl(0.03, 0.045, 1.8, 5), k.mat(C.wood), {"y": 0.3})
	for s in [-1.0, 1.0]:
		k.add(g, PartKit.cone(0.03, 0.3, 4), k.mat(C.wood), {"x": s * 0.08, "y": 1.28, "rz": -s * 0.4})
	var gem := k.add(g, PartKit.ico(0.1), k.mat(Color("b48cff"), true), {"y": 1.3})
	k.merge_static(g, [g], [gem])
	return {"kit": k, "main": g, "offhand": null, "gem": gem}


# ───────── 投射物 ─────────

# 敵人箭矢：沿 +Z 建模，箭頭發光（color 為投射物顏色）
static func enemy_projectile(color: Color) -> Node3D:
	var k := PartKit.new()
	var g := Node3D.new()
	k.add(g, PartKit.cyl(0.018, 0.018, 0.7, 4), k.mat(Color("2a2420")), {"rx": PI / 2.0, "shadow": false})
	k.add(g, PartKit.cone(0.05, 0.16, 4), k.mat(color, true), {"z": 0.42, "rx": PI / 2.0, "shadow": false})
	k.merge_static(g, [g])
	return g


# ───────── 場地 ─────────

# 只負責外觀，碰撞邊界由 World 決定
static func build_arena(half: float, rng: RandomNumberGenerator) -> Node3D:
	var k := PartKit.new()
	var group := Node3D.new()

	var rocks: Array[StandardMaterial3D] = []
	for c in ROCK_COLORS:
		rocks.append(k.mat(c))
	for p in ArenaView.perimeter_points(half, 1.1, 0.6):
		var s := 0.45 + rng.randf() * 0.45
		k.add(group, PartKit.ico(s, 0), rocks[rng.randi_range(0, 2)], {
			"x": p.x + (rng.randf() - 0.5) * 0.4, "y": s * 0.5, "z": p.z + (rng.randf() - 0.5) * 0.4,
			"rx": rng.randf() * 3.0, "ry": rng.randf() * 3.0, "sy": 0.8 + rng.randf() * 0.6,
		})

	var stone := k.mat(Color("6b6e75"))
	for p in ArenaView.scatter_outside(rng, half, 26, 1.8, 9.0):
		var grave := Node3D.new()
		grave.rotation_order = EULER_ORDER_XYZ
		grave.position = Vector3(p.x, 0.0, p.z)
		grave.rotation = Vector3((rng.randf() - 0.5) * 0.25, p.ry, (rng.randf() - 0.5) * 0.2)
		k.add(grave, PartKit.box(0.5, 0.6, 0.12), stone, {"y": 0.3})
		k.add(grave, PartKit.cyl(0.25, 0.25, 0.12, 6), stone, {"y": 0.6, "rx": PI / 2.0})
		group.add_child(grave)
	var bark := k.mat(Color("2e241c"))
	for p in ArenaView.scatter_outside(rng, half, 16, 3.0, 11.0):
		var tree := Node3D.new()
		tree.position = Vector3(p.x, 0.0, p.z)
		tree.scale = Vector3.ONE * p.s * 1.4
		tree.rotation.y = p.ry
		k.add(tree, PartKit.cyl(0.07, 0.15, 2.0, 5), bark, {"y": 1.0})
		k.add(tree, PartKit.cyl(0.03, 0.06, 0.9, 4), bark, {"x": 0.25, "y": 1.6, "rz": -0.8})
		k.add(tree, PartKit.cyl(0.03, 0.05, 0.7, 4), bark, {"x": -0.2, "y": 1.9, "rz": 0.9})
		group.add_child(tree)
	var bone := k.mat(C.bone_dark)
	for p in ArenaView.scatter_inside(rng, half, 18):
		k.add(group, PartKit.cyl(0.03, 0.03, 0.35, 4), bone, {"x": p.x, "y": 0.03, "z": p.z, "rz": PI / 2.0, "ry": p.ry, "shadow": false})
	k.merge_static(group, [group])

	# 地面有頂點色，不參與合併
	group.add_child(ArenaView.create_ground((half + 14.0) * 2.0, GROUND_COLORS, 1.8, 0.1, rng))
	return group
