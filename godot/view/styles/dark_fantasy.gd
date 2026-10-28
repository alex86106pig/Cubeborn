# 造型「暗黑幻想」（照搬網頁版 render/styles/darkFantasy.js）：寫實比例、硬朗多面體（flat shading）、月夜墓地
# 騎士：黑鋼重甲；敵人：骷髏戰士、骷髏弓手、亡骸騎士。零件尺寸、位置、角度與網頁版逐一對應
class_name DarkFantasy
extends RefCounted

const C := {
	"steel": Color("8a93a3"), "steel_dark": Color("4a505c"), "iron": Color("2a2d33"), "cape": Color("6b1d24"),
	"leather": Color("3b2a20"), "bone": Color("d8d2bf"), "bone_dark": Color("a39d88"), "socket": Color("1a1612"),
	"eye_red": Color("ff3b2f"), "hood": Color("2c2a35"), "rust": Color("8a6a4a"), "death_armor": Color("23262e"),
	"death_eye": Color("55e0ff"), "wood": Color("4a3526"),
	"rot_skin": Color("7a8463"), "rot_dark": Color("4a5238"), "rag": Color("4a4238"), "rag_dark": Color("2e2a2c"),
	"rot_eye": Color("d8e05a"), "bloat_skin": Color("8c946a"), "bloat_glow": Color("a8e04a"),
	"hound_fur": Color("2e2a28"), "hound_snout": Color("5a4a42"),
}

# 騎士身上的掛點（Rig.mount_nodes）：back 在披風外、hip_l / hip_r 在腰帶外側（身體座標），head 在頭盔頂（頭的座標），
# forearm_l 在左前臂外側（左手臂座標）。目前 forearm_l 掛盾、back 掛箭袋，hip_l / hip_r / head 預留
const KNIGHT_MOUNTS := {
	&"back": Vector3(0.0, 1.35, -0.4),
	&"hip_l": Vector3(0.32, 0.9, 0.0),
	&"hip_r": Vector3(-0.32, 0.9, 0.0),
	&"head": Vector3(0.0, 0.5, 0.0),
	&"forearm_l": Vector3(0.1, -0.4, 0.0),
}
const KNIGHT_JOINTS := {
	"neck": 1.6, "shoulder_y": 1.55, "shoulder_x": 0.36, "grip": 0.58,
	"hip_y": 0.95, "hip_x": 0.14, "height": 2.1, "mounts": KNIGHT_MOUNTS,
}
const SKELETON_JOINTS := {
	"neck": 1.5, "shoulder_y": 1.45, "shoulder_x": 0.3, "grip": 0.65,
	"hip_y": 0.92, "hip_x": 0.12, "height": 1.95,
}
const ZOMBIE_JOINTS := {
	"neck": 1.42, "shoulder_y": 1.4, "shoulder_x": 0.3, "grip": 0.58,
	"hip_y": 0.92, "hip_x": 0.13, "height": 1.85,
}
const HOUND_JOINTS := {
	"neck": 0.8, "neck_z": 0.48, "shoulder_y": 0.55, "shoulder_x": 0.12, "shoulder_z": 0.3, "grip": 0.5,
	"hip_y": 0.55, "hip_x": 0.12, "hip_z": -0.3, "height": 1.0,
}
const BOSS_SCALE := 1.85
static var _projectile_kit: PartKit   # 箭的材質（enemy_projectile）

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
		&"zombie":
			rig = zombie()
		&"bloater":
			rig = bloater()
		&"hound":
			rig = hound()
		&"boss":
			rig = death_knight()
		_:
			rig = knight()
	_templates[kind] = rig.to_template()
	return rig


# 玩家依職業換配色（F2 demo：同一套騎士模型，ClassDefs 的 colors）；沒選職業 = 原本的騎士
static func player_character(class_id: StringName) -> Rig:
	if class_id == ClassDefs.NONE:
		return character(&"player")
	var key := StringName("player:%s" % class_id)
	if _templates.has(key):
		return Rig.from_template(_templates[key])
	var c: Dictionary = ClassDefs.CLASSES[class_id].colors
	var rig := Rig.new(KNIGHT_JOINTS)
	_armored_body(rig, c.armor, c.trim, c.cape)
	rig = rig.optimize()
	_templates[key] = rig.to_template()
	return rig


# 小怪（骷髏戰士、弓手）的蒙皮版本（D5 效能，view/skinned_rig.gd）：同樣的零件與關節，每隻只剩 1~2 次繪製
static func skinned_character(kind: StringName) -> SkinnedRig:
	if not _templates.has(kind):
		character(kind).free()
	return SkinnedRig.new(kind, _templates[kind])


# ───────── 角色 ─────────

static func _armored_body(rig: Rig, armor: Color, trim: Color, cape: Color, eye: Variant = null, horns := false) -> void:
	var k := rig.kit
	k.add(rig.body, PartKit.cyl(0.3, 0.24, 0.62, 6), k.mat(armor), {"y": 1.28})
	k.add(rig.body, PartKit.cyl(0.25, 0.3, 0.26, 6), k.mat(trim), {"y": 0.9})
	# 披風整片要在軀幹（上緣半徑 0.3）後面，否則會穿進身體、從六角柱的稜角露出碎片：上緣貼著肩背、下襬略往後
	k.add(rig.body, PartKit.box(0.56, 0.95, 0.04), k.mat(cape), {"y": 1.07, "z": -0.35, "rx": 0.05})

	k.add(rig.head, PartKit.cyl(0.19, 0.21, 0.38, 7), k.mat(armor), {"y": 0.2})
	k.add(rig.head, PartKit.box(0.3, 0.035, 0.03), k.mat(eye, true) if eye != null else k.mat(C.socket), {"y": 0.24, "z": 0.19})
	k.add(rig.head, PartKit.box(0.035, 0.12, 0.42), k.mat(trim), {"y": 0.42})
	if horns:
		for s in [-1.0, 1.0]:
			k.add(rig.head, PartKit.cone(0.06, 0.4, 5), k.mat(C.bone_dark), {"x": s * 0.24, "y": 0.42, "rz": -s * 0.9})

	for pair in [[rig.arm_r, rig.hand_r, -1.0], [rig.arm_l, rig.hand_l, 1.0]]:
		var arm: Node3D = pair[0]
		k.add(arm, PartKit.ico(0.17, 0), k.mat(armor), {"x": pair[2] * 0.04, "y": 0.02, "sy": 0.8})
		k.add(arm, PartKit.cyl(0.085, 0.075, 0.4, 6), k.mat(armor), {"y": -0.22})
		k.add(pair[1], PartKit.box(0.14, 0.17, 0.14), k.mat(trim))   # 拳頭掛在手掌掛點上，轉手掌時拳頭和武器一起轉
	for leg in [rig.leg_r, rig.leg_l]:
		k.add(leg, PartKit.cyl(0.1, 0.09, 0.45, 6), k.mat(trim), {"y": -0.22})
		k.add(leg, PartKit.cyl(0.095, 0.11, 0.42, 6), k.mat(armor), {"y": -0.64})
		k.add(leg, PartKit.box(0.16, 0.12, 0.27), k.mat(C.iron), {"y": -0.9, "z": 0.04})


# 武器的掛點（模型座標）：grip = 拳頭握的位置；弓另有 string（弓弦上勾弦的點）、鐵鏟另有 hold（托舉點）。
# 模型掛在手掌掛點（拳頭中心）下、往回移 grip，握的位置就在拳頭裡；要轉武器時轉手掌掛點，不轉模型
static func _hold(model: Node3D, mounts: Dictionary) -> Node3D:
	model.set_meta(&"mounts", mounts)
	model.position = -(model.basis * (mounts.grip as Vector3))
	return model


# 長劍：劍身沿局部 +Y，整組轉 2.8 弧度；握把中央是 grip。回傳的模型由呼叫端掛到手掌掛點
static func _long_sword(k: PartKit, blade: Color, guard: Color, length := 1.0, glow: Variant = null) -> Node3D:
	var g := Node3D.new()
	k.add(g, PartKit.cyl(0.03, 0.03, 0.25, 5), k.mat(C.leather))
	k.add(g, PartKit.ico(0.05), k.mat(guard), {"y": -0.15})
	k.add(g, PartKit.box(0.36, 0.05, 0.07), k.mat(guard), {"y": 0.14})
	k.add(g, PartKit.cyl(0.018, 0.055, length, 4), k.mat(glow, true) if glow != null else k.mat(blade),
		{"y": 0.16 + length / 2.0, "sz": 0.35})
	g.rotation.x = 2.8
	return _hold(g, {"grip": Vector3.ZERO})


# 骷髏弓手的弓：半圓弓身的兩端在局部 ±X，弧的正中間（握把）是 grip，弦連兩端、中點是 string
static func _bow(k: PartKit, color: Color) -> Node3D:
	var r := 0.45
	var g := Node3D.new()
	g.rotation.y = PI / 2.0
	k.add(g, PartKit.torus(r, 0.025, 4, 9, PI), k.mat(color), {"rx": PI})
	k.add(g, PartKit.cyl(0.005, 0.005, r * 2.0, 3), k.mat(Color("cccccc")), {"rz": PI / 2.0})
	return _hold(g, {"grip": Vector3(0.0, -r, 0.0), "string": Vector3.ZERO})


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
	for hand in [rig.hand_r, rig.hand_l]:
		k.add(hand, PartKit.box(0.07, 0.1, 0.04), bone)   # 骨手掛在手掌掛點上
	for leg in [rig.leg_r, rig.leg_l]:
		k.add(leg, PartKit.cyl(0.035, 0.03, 0.42, 4), bone, {"y": -0.22})
		k.add(leg, PartKit.sphere(0.045, 5, 4), bone, {"y": -0.45})
		k.add(leg, PartKit.cyl(0.03, 0.028, 0.4, 4), bone, {"y": -0.67})
		k.add(leg, PartKit.box(0.08, 0.05, 0.18), bone, {"y": -0.9, "z": 0.04})


static func skeleton() -> Rig:
	var rig := Rig.new(SKELETON_JOINTS)
	_skeleton_base(rig)
	rig.hand_r.add_child(_long_sword(rig.kit, C.rust, C.iron, 0.8))
	return rig.optimize()


static func skeleton_archer() -> Rig:
	var rig := Rig.new(SKELETON_JOINTS)
	_skeleton_base(rig, true)
	rig.hand_l.add_child(_bow(rig.kit, C.wood))
	return rig.optimize()


# 腐屍：灰綠的爛肉、破布衣、駝背；沒拿武器（徒手撲抱）
static func zombie() -> Rig:
	var rig := Rig.new(ZOMBIE_JOINTS)
	var k := rig.kit
	var skin := k.mat(C.rot_skin)
	var dark := k.mat(C.rot_dark)
	var cloth := k.mat(C.rag)
	k.add(rig.body, PartKit.cyl(0.24, 0.2, 0.55, 6), cloth, {"y": 1.2, "rx": 0.25, "z": 0.06})
	k.add(rig.body, PartKit.box(0.3, 0.14, 0.04), dark, {"y": 1.08, "z": 0.2, "rx": 0.25})   # 破洞露出的肚子
	k.add(rig.body, PartKit.cyl(0.22, 0.24, 0.28, 6), k.mat(C.rag_dark), {"y": 0.88})
	k.add(rig.head, PartKit.ico(0.17, 1), skin, {"y": 0.16, "sy": 1.05, "z": 0.04})
	k.add(rig.head, PartKit.box(0.15, 0.06, 0.12), dark, {"y": 0.02, "z": 0.08, "rx": 0.3})   # 掉下來的下巴
	for s in [-1.0, 1.0]:
		k.add(rig.head, PartKit.sphere(0.035, 4, 3), k.mat(C.rot_eye, true), {"x": s * 0.065, "y": 0.19, "z": 0.18, "shadow": false})
	for arm in [rig.arm_r, rig.arm_l]:
		k.add(arm, PartKit.cyl(0.07, 0.06, 0.34, 5), cloth, {"y": -0.17})
		k.add(arm, PartKit.cyl(0.05, 0.045, 0.3, 5), skin, {"y": -0.45})
	for hand in [rig.hand_r, rig.hand_l]:
		k.add(hand, PartKit.box(0.09, 0.12, 0.05), skin)
	for leg in [rig.leg_r, rig.leg_l]:
		k.add(leg, PartKit.cyl(0.085, 0.075, 0.45, 5), k.mat(C.rag_dark), {"y": -0.22})
		k.add(leg, PartKit.cyl(0.06, 0.055, 0.4, 5), skin, {"y": -0.64})
		k.add(leg, PartKit.box(0.1, 0.06, 0.2), dark, {"y": -0.88, "z": 0.04})
	return rig.optimize()


# 膨脹屍：同腐屍的骨架，肚子是一顆鼓脹的大肉球（脹大時 body 放大），皮膚上有發光的綠色裂縫
static func bloater() -> Rig:
	var rig := Rig.new(ZOMBIE_JOINTS)
	var k := rig.kit
	var skin := k.mat(C.bloat_skin)
	var dark := k.mat(C.rot_dark)
	k.add(rig.body, PartKit.sphere(0.42, 8, 6), skin, {"y": 1.08, "z": 0.08, "sy": 0.95})
	for v: Vector3 in [Vector3(0.2, 1.2, 0.42), Vector3(-0.18, 0.98, 0.45), Vector3(0.05, 1.32, 0.38)]:
		k.add(rig.body, PartKit.box(0.16, 0.035, 0.02), k.mat(C.bloat_glow, true), {"x": v.x, "y": v.y, "z": v.z, "rz": v.x * 3.0, "shadow": false})
	k.add(rig.body, PartKit.cyl(0.2, 0.22, 0.2, 6), k.mat(C.rag_dark), {"y": 0.86})
	k.add(rig.head, PartKit.ico(0.15, 1), skin, {"y": 0.13, "z": 0.06})
	for s in [-1.0, 1.0]:
		k.add(rig.head, PartKit.sphere(0.03, 4, 3), k.mat(C.rot_eye, true), {"x": s * 0.06, "y": 0.16, "z": 0.19, "shadow": false})
	for arm in [rig.arm_r, rig.arm_l]:
		k.add(arm, PartKit.cyl(0.08, 0.07, 0.34, 5), skin, {"y": -0.17})
		k.add(arm, PartKit.cyl(0.065, 0.055, 0.3, 5), dark, {"y": -0.45})
	for hand in [rig.hand_r, rig.hand_l]:
		k.add(hand, PartKit.box(0.1, 0.12, 0.06), skin)
	for leg in [rig.leg_r, rig.leg_l]:
		k.add(leg, PartKit.cyl(0.1, 0.09, 0.45, 5), k.mat(C.rag_dark), {"y": -0.22})
		k.add(leg, PartKit.cyl(0.075, 0.065, 0.4, 5), skin, {"y": -0.64})
		k.add(leg, PartKit.box(0.12, 0.06, 0.2), dark, {"y": -0.88, "z": 0.04})
	return rig.optimize()


# 屍犬（四足）：用同一套關節，arm = 前腳（往前放）、leg = 後腳（往後放）、body 是橫的軀幹；
# 爛掉的黑毛、露出肋骨、黃眼；手掌掛點不用（沒有拳頭）
static func hound() -> Rig:
	var rig := Rig.new(HOUND_JOINTS)
	var k := rig.kit
	var fur := k.mat(C.hound_fur)
	var bone := k.mat(C.bone_dark)
	k.add(rig.body, PartKit.box(0.32, 0.3, 0.85), fur, {"y": 0.62, "z": 0.0})
	for i in 3:
		k.add(rig.body, PartKit.box(0.34, 0.04, 0.05), bone, {"y": 0.55, "z": 0.12 - i * 0.12})   # 露出的肋骨
	k.add(rig.body, PartKit.cyl(0.05, 0.02, 0.4, 4), fur, {"y": 0.72, "z": -0.55, "rx": -1.0})   # 尾巴
	k.add(rig.head, PartKit.box(0.22, 0.2, 0.26), fur, {"y": 0.0, "z": 0.08})
	k.add(rig.head, PartKit.box(0.14, 0.11, 0.22), k.mat(C.hound_snout), {"y": -0.04, "z": 0.3})
	for s in [-1.0, 1.0]:
		k.add(rig.head, PartKit.cone(0.05, 0.14, 4), fur, {"x": s * 0.07, "y": 0.14, "z": 0.02})
		k.add(rig.head, PartKit.sphere(0.025, 4, 3), k.mat(C.rot_eye, true), {"x": s * 0.07, "y": 0.04, "z": 0.21, "shadow": false})
	for leg in [rig.arm_r, rig.arm_l, rig.leg_r, rig.leg_l]:
		k.add(leg, PartKit.cyl(0.06, 0.045, 0.28, 5), fur, {"y": -0.14})
		k.add(leg, PartKit.cyl(0.035, 0.03, 0.26, 4), bone, {"y": -0.38})
		k.add(leg, PartKit.box(0.07, 0.04, 0.1), bone, {"y": -0.5, "z": 0.03})
	return rig.optimize()


static func death_knight() -> Rig:
	var j := KNIGHT_JOINTS.duplicate()
	j["scale"] = BOSS_SCALE
	var rig := Rig.new(j)
	_armored_body(rig, C.death_armor, C.iron, Color("1c1a22"), C.death_eye, true)
	rig.hand_r.add_child(_long_sword(rig.kit, Color("9aa4b4"), C.iron, 1.35, Color("7fe8ff")))
	return rig.optimize()


# ───────── 玩家武器 ─────────

# → { kit, main（掛右手）, offhand（掛左臂，可為 null）, gem（會自轉，可為 null） }
static func weapon(model: StringName) -> Dictionary:
	match model:
		&"swordShield":
			return _sword_shield()
		&"staff":
			return _staff()
		&"shortbow":
			return _player_bow(0.5, Color("8a5a32"), 0.6)
		&"longbow":
			return _player_bow(0.8, Color("5a3a1e"), 0.68)   # 箭長：拉滿時（沒手肘、側身 70° 約拉 0.57）箭頭剛好露出弓外一點，0.9 太凸（2026-10-27 使用者）
		&"daggers":
			return _daggers()
		&"scepter":
			return _scepter()
		&"torch":
			return _torch()
		&"shovel":
			return _shovel()
	return {}


# 雙匕首（F6）：左右手各一把（left 掛 hand_l）；刀刃沿手臂延伸方向（-Y），手往前刺時刀尖朝前
# 2026-10-27 網頁版實測：原本左手那把掛在左臂、轉 90°，畫面上看不到
static func _daggers() -> Dictionary:
	var k := PartKit.new()
	var parts: Array[Node3D] = []
	for i in 2:
		var g := Node3D.new()
		k.add(g, PartKit.cone(0.045, 0.42, 4), k.mat(Color("c8d0e0")), {"y": 0.3, "sx": 0.35})
		k.add(g, PartKit.box(0.16, 0.03, 0.05), k.mat(C.steel_dark), {"y": 0.09})
		k.add(g, PartKit.cyl(0.025, 0.025, 0.14, 4), k.mat(C.leather), {"y": 0.0})
		k.merge_static(g, [g])
		g.rotation.x = PI   # 刀尖朝 -Y
		parts.append(_hold(g, {"grip": Vector3.ZERO}))
	return {"kit": k, "main": parts[0], "offhand": null, "left": parts[1], "gem": null}


# 驅魔權杖（F7）：木柄 + 金色燈籠形的頭，中間發光（會自轉的 gem）
static func _scepter() -> Dictionary:
	var k := PartKit.new()
	var g := Node3D.new()
	k.add(g, PartKit.cyl(0.03, 0.035, 0.9, 5), k.mat(C.wood), {"y": 0.2})
	k.add(g, PartKit.box(0.2, 0.05, 0.2), k.mat(Color("c9a64a")), {"y": 0.66})
	k.add(g, PartKit.box(0.2, 0.05, 0.2), k.mat(Color("c9a64a")), {"y": 0.94})
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			k.add(g, PartKit.box(0.03, 0.28, 0.03), k.mat(Color("c9a64a")), {"x": sx * 0.085, "y": 0.8, "z": sz * 0.085})
	var gem := k.add(g, PartKit.ico(0.07), k.mat(Color("fff0b0"), true), {"y": 0.8})
	k.merge_static(g, [g], [gem])
	return {"kit": k, "main": _hold(g, {"grip": Vector3.ZERO}), "offhand": null, "gem": gem}


# 火把（F8）：木柄 + 鐵箍 + 發光的火焰（gem 會自轉當作火焰晃動）
static func _torch() -> Dictionary:
	var k := PartKit.new()
	var g := Node3D.new()
	k.add(g, PartKit.cyl(0.035, 0.03, 0.9, 5), k.mat(C.wood), {"y": 0.3})
	k.add(g, PartKit.cyl(0.05, 0.05, 0.08, 6), k.mat(C.iron), {"y": 0.76})
	var flame := k.add(g, PartKit.cone(0.09, 0.3, 5), k.mat(Color("ffb040"), true), {"y": 0.94})
	k.merge_static(g, [g], [flame])
	return {"kit": k, "main": _hold(g, {"grip": Vector3.ZERO}), "offhand": null, "gem": flame}


# 鐵鏟（F9）：手握在柄的尾端（T 形握把 = grip），柄沿 -Y（手臂延伸的方向）伸出，鏟面在遠端，鏟面上有托舉點（hold）
# 鏟面是 U 形槽、凹的一側朝 +Z（手往前伸時朝上，托著鏟起的怪），鏟尖往 +Z 翹
static func _shovel() -> Dictionary:
	var k := PartKit.new()
	var g := Node3D.new()
	var steel := k.mat(Color("a8a8a8"))
	k.add(g, PartKit.box(0.18, 0.04, 0.04), k.mat(C.wood), {"y": 0.05})
	k.add(g, PartKit.cyl(0.03, 0.03, 1.15, 5), k.mat(C.wood), {"y": -0.55})
	k.add(g, PartKit.box(0.26, 0.34, 0.03), steel, {"y": -1.25, "rx": -0.25})
	for sx in [-1.0, 1.0]:
		k.add(g, PartKit.box(0.03, 0.34, 0.08), steel, {"x": sx * 0.13, "y": -1.25, "z": 0.04, "rx": -0.25})
	k.merge_static(g, [g])
	_hold(g, {"grip": Vector3(0.0, 0.05, 0.0), "hold": Vector3(0.0, -1.3, 0.05)})
	# 托舉點：鏟起的怪放在這裡（WorldView._place_on_shovel）；merge_static 之後才加，不會被合併掉
	var hold := Node3D.new()
	hold.name = "HoldPoint"
	hold.position = g.get_meta(&"mounts").hold
	g.add_child(hold)
	return {"kit": k, "main": g, "offhand": null, "gem": null, "hold_point": hold}


# 玩家的弓（F4）：握在左手（Animator 讓它一直保持直立，右手拉弦）；size 是弓身的弧半徑（短弓 0.55、長弓 0.85）
# 座標同身體：+Y 上、+Z 前。弓身沿 YZ 平面的圓弧排 8 段，正中間（握把）就在手上、是最前面的點，
# 兩端往拉弓的人這側（-Z）彎回來，弦接兩端（2026-10-27 使用者：原本圓心偏後，手握的位置不在弓身上）
const BOW_SEGMENTS := 8
const BOW_HALF_ARC := 0.85   # 弓身半邊張開的角度（弧度）
# 箭袋（身體座標，玩家騎士 KNIGHT_JOINTS 的右肩在 (-0.36, 1.55, 0)）：袋口放在右手往後上方伸直時拳頭停的位置
# （Animator.QUIVER_ARM、手臂長 = KNIGHT_JOINTS.grip；改其中一個要重算），箭袋從那裡斜穿背部到左腰下方，
# 夠長夠粗：手伸進袋口、箭在袋裡出現被擋住
const QUIVER_MOUTH := Vector3(-0.451, 1.869, -0.476)
const QUIVER_BOTTOM := Vector3(0.12, 1.05, -0.49)   # 要在披風（這個高度背面 z 約 -0.37）後面
const QUIVER_RADIUS := 0.14


# arrow：箭長（短弓的箭短一點，2026-10-27 使用者）；背上一律有箭袋（back，掛在 Rig.body），
# 袋裡露出短弓箭袋的支數（quiver_arrows；短弓照剩幾發顯示，長弓沒有箭數機制、一直是滿的）
static func _player_bow(size: float, wood: Color, arrow: float) -> Dictionary:
	var k := PartKit.new()
	var g := Node3D.new()
	var step := BOW_HALF_ARC * 2.0 / BOW_SEGMENTS
	for i in BOW_SEGMENTS:
		var phi := -BOW_HALF_ARC + step * (i + 0.5)
		# 弧上的點 = 圓心 (0, 0, -size) + size × (0, sin φ, cos φ)；切線 (0, cos φ, -sin φ) = Y 軸繞 X 轉 -φ
		k.add(g, PartKit.cyl(0.028, 0.028, size * step * 1.05, 4), k.mat(wood),
			{"y": size * sin(phi), "z": -size + size * cos(phi), "rx": -phi})
	var tip_y := size * sin(BOW_HALF_ARC)
	var string_z := -size * (1.0 - cos(BOW_HALF_ARC))
	# 弓弦：上下兩段各從弓梢連到拉弦點（Animator.bow_string 每幀擺，拉弓時拉成 V 字；2026-10-27 使用者），不合併
	var string_mat := k.mat(Color("d8d2bf"))
	var strings: Array[MeshInstance3D] = []
	for i in 2:
		strings.append(k.add(g, PartKit.cyl(0.007, 0.007, 1.0, 3), string_mat))
	g.set_meta(&"strings", strings)
	g.set_meta(&"string_tips", [Vector3(0.0, tip_y, string_z), Vector3(0.0, -tip_y, string_z)])
	k.add(g, PartKit.box(0.06, 0.14, 0.07), k.mat(C.leather))   # 握把（在手上）
	k.merge_static(g, [g], strings)
	_hold(g, {"grip": Vector3.ZERO, "string": Vector3(0.0, 0.0, string_z)})
	# 搭在弦上的箭：掛在右手、沿 -Z 建模（Animator 每幀 look_at 弓的握把，不管右手臂怎麼擺都指著弓）；只在拉弓時顯示
	var nock := Node3D.new()
	k.add(nock, PartKit.cyl(0.022, 0.022, arrow, 4), k.mat(Color("e0c890")), {"z": -arrow / 2.0, "rx": PI / 2.0})
	k.add(nock, PartKit.cone(0.05, 0.16, 4), k.mat(Color("e8eef8"), true), {"z": -arrow - 0.06, "rx": -PI / 2.0})
	for sgn in [-1.0, 1.0]:
		k.add(nock, PartKit.box(0.1, 0.012, 0.16), k.mat(Color("f0f0f0")), {"z": -0.06, "rz": sgn * 0.3})
	k.merge_static(nock, [nock])
	nock.set_meta(&"arrow", arrow)   # Animator 用來限制拉弦距離（箭尾不能拉過箭頭）
	nock.visible = false
	var out := {"kit": k, "main": null, "offhand": null, "left": g, "nock": nock, "gem": null}
	var quiver_count: int = WeaponDefs.WEAPONS[&"shortbow"].attack.quiver
	# 箭袋：從右肩後上方（袋口）斜穿背部到左腰；袋口露出 quiver_count 支箭（各自一個節點，不合併，射一支藏一支）
	var axis := QUIVER_MOUTH - QUIVER_BOTTOM
	var length := axis.length()
	var quiver := Node3D.new()
	k.add(quiver, PartKit.cyl(QUIVER_RADIUS, QUIVER_RADIUS * 0.75, length, 7), k.mat(C.leather), {"y": 0.0})
	k.add(quiver, PartKit.cyl(QUIVER_RADIUS + 0.01, QUIVER_RADIUS + 0.01, 0.06, 7), k.mat(Color("8a6a3a")), {"y": length / 2.0 - 0.03})
	k.merge_static(quiver, [quiver])
	var arrows: Array[Node3D] = []
	for i in quiver_count:
		var a := Node3D.new()
		var ang := TAU * i / quiver_count
		a.position = Vector3(cos(ang) * QUIVER_RADIUS * 0.5, length / 2.0 + 0.07, sin(ang) * QUIVER_RADIUS * 0.5)
		k.add(a, PartKit.cyl(0.014, 0.014, 0.18, 3), k.mat(Color("e0c890")), {"y": -0.06})
		k.add(a, PartKit.box(0.08, 0.13, 0.012), k.mat(Color("f0f0f0")), {"y": 0.05, "ry": ang})
		quiver.add_child(a)
		arrows.append(a)
	quiver.basis = Basis(Quaternion(Vector3.UP, axis.normalized()))
	# 掛在背部掛點：grip 是背部掛點在箭袋座標裡的位置，掛上去後箭袋正好在袋口與袋底中間
	var back: Vector3 = KNIGHT_MOUNTS[&"back"]
	_hold(quiver, {"grip": quiver.basis.inverse() * (back - (QUIVER_MOUTH + QUIVER_BOTTOM) / 2.0)})
	out["back"] = quiver
	out["quiver_arrows"] = arrows
	return out


static func _sword_shield() -> Dictionary:
	var k := PartKit.new()
	var sword := _long_sword(k, Color("b8c0cc"), C.steel_dark, 0.95)

	var shield := Node3D.new()
	k.add(shield, PartKit.box(0.07, 0.42, 0.46), k.mat(C.cape), {"y": 0.1})
	# 盾的下半尖角：四角錐先轉 45°（底面和盾面對齊）再壓扁成盾的厚度。節點是先縮放後旋轉，所以壓扁放在外層節點
	var tip := Node3D.new()
	tip.position.y = -0.31
	tip.scale = Vector3(0.15, 1.0, 0.98)
	shield.add_child(tip)
	k.add(tip, PartKit.cone(0.33, 0.42, 4), k.mat(C.cape), {"rx": PI, "ry": PI / 4.0})
	k.add(shield, PartKit.box(0.09, 0.44, 0.05), k.mat(C.steel), {"y": 0.1})
	k.add(shield, PartKit.ico(0.07), k.mat(C.steel), {"x": 0.05, "y": 0.1})
	_hold(shield, {"grip": Vector3(-0.08, 0.0, 0.0)})   # 內側綁帶，掛在左前臂外側掛點 forearm_l
	k.merge_static(sword, [sword])
	k.merge_static(shield, [shield])
	return {"kit": k, "main": sword, "offhand": shield, "gem": null}


static func _staff() -> Dictionary:
	var k := PartKit.new()
	var g := Node3D.new()
	k.add(g, PartKit.cyl(0.03, 0.045, 1.8, 5), k.mat(C.wood), {"y": 0.3})
	for s in [-1.0, 1.0]:
		k.add(g, PartKit.cone(0.03, 0.3, 4), k.mat(C.wood), {"x": s * 0.08, "y": 1.28, "rz": -s * 0.4})
	var gem := k.add(g, PartKit.ico(0.1), k.mat(Color("b48cff"), true), {"y": 1.3})
	k.merge_static(g, [g], [gem])
	return {"kit": k, "main": _hold(g, {"grip": Vector3.ZERO}), "offhand": null, "gem": gem}


# ───────── 投射物 ─────────

# 敵人箭矢：沿 +Z 建模，箭頭發光（color 為投射物顏色）
static func enemy_projectile(color: Color) -> Node3D:
	# 所有箭共用同一組材質：牆後剪影寫模板值後，每支箭各自的材質會各編一次著色器（遊戲中每射一箭卡一下）
	if _projectile_kit == null:
		_projectile_kit = PartKit.new()
	var k := _projectile_kit
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
