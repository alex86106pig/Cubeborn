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
	"keeper_coat": Color("4a3a2a"), "keeper_skin": Color("b8a088"), "keeper_beard": Color("c8c4b8"), "keeper_hat": Color("2a2622"),
	"keeper_flame": Color("ffb040"), "wolf_fur": Color("4a4642"),
}

# 騎士身上的掛點（Rig.mount_nodes）：back 在披風外、hip_l / hip_r 在腰帶外側（身體座標），head 在頭盔頂（頭的座標），
# forearm_l 在左前臂外側（左前臂座標，原點在手肘）。目前 forearm_l 掛盾、back 掛箭袋，hip_l / hip_r / head 預留
const KNIGHT_MOUNTS := {
	&"back": Vector3(0.0, 1.35, -0.4),
	&"hip_l": Vector3(0.32, 0.9, 0.0),
	&"hip_r": Vector3(-0.32, 0.9, 0.0),
	&"head": Vector3(0.0, 0.5, 0.0),
	&"forearm_l": Vector3(0.1, -0.1, 0.0),
}
const KNIGHT_JOINTS := {
	"neck": 1.6, "shoulder_y": 1.55, "shoulder_x": 0.36, "grip": 0.58, "elbow": 0.3,
	"hip_y": 0.95, "hip_x": 0.14, "knee": 0.47, "height": 2.1, "mounts": KNIGHT_MOUNTS,
}
const SKELETON_JOINTS := {
	"neck": 1.5, "shoulder_y": 1.45, "shoulder_x": 0.3, "grip": 0.65, "elbow": 0.33,
	"hip_y": 0.92, "hip_x": 0.12, "knee": 0.45, "height": 1.95,
}
# 盾槍兵的塔盾在左前臂座標的位置（前臂外側，同騎士的 forearm_l 掛點）。直接掛在前臂上合併：
# 掛點底下的零件不會進 to_template，蒙皮版會少掉
const SPEARMAN_SHIELD_AT := Vector3(0.09, -0.05, 0.0)
# 骨輪：整個輪子掛在 head 關節上（head 在輪軸的高度），滾動 = 轉 head 的 x；手腳沒有零件
const WHEEL_RADIUS := 0.62
const WHEEL_JOINTS := {
	"neck": WHEEL_RADIUS, "shoulder_y": WHEEL_RADIUS, "shoulder_x": 0.0, "grip": 0.1,
	"hip_y": WHEEL_RADIUS, "hip_x": 0.0, "height": WHEEL_RADIUS * 2.0,
}
# 萬骨聚合體：駝背、手長腿短（肩膀到拳頭 1.0、髖關節只有 0.45 高）
const COLOSSUS_JOINTS := {
	"neck": 1.4, "shoulder_y": 1.3, "shoulder_x": 0.5, "grip": 1.0, "elbow": 0.5,
	"hip_y": 0.45, "hip_x": 0.22, "knee": 0.22, "height": 1.7,
}
const ZOMBIE_JOINTS := {
	"neck": 1.42, "shoulder_y": 1.4, "shoulder_x": 0.3, "grip": 0.58, "elbow": 0.32,
	"hip_y": 0.92, "hip_x": 0.13, "knee": 0.46, "height": 1.85,
}
const HOUND_JOINTS := {
	"neck": 0.8, "neck_z": 0.48, "shoulder_y": 0.55, "shoulder_x": 0.12, "shoulder_z": 0.3, "grip": 0.5, "elbow": 0.27,
	"hip_y": 0.55, "hip_x": 0.12, "hip_z": -0.3, "knee": 0.27, "height": 1.0,
}
# 屍甲蟲：貼地的小甲蟲，前腳（arm）往前、後腳（leg）往後；中間那對腳是身體上的固定零件
const BEETLE_JOINTS := {
	"neck": 0.22, "neck_z": 0.28, "shoulder_y": 0.18, "shoulder_x": 0.16, "shoulder_z": 0.15, "grip": 0.2, "elbow": 0.1,
	"hip_y": 0.18, "hip_x": 0.16, "hip_z": -0.15, "knee": 0.1, "height": 0.45,
}
# 墓穴蜘蛛：前腳（arm）往前、後腳（leg）往後，中間兩對腳是身體上的固定零件；腹部在後面
const SPIDER_JOINTS := {
	"neck": 0.42, "neck_z": 0.32, "shoulder_y": 0.38, "shoulder_x": 0.2, "shoulder_z": 0.22, "grip": 0.4, "elbow": 0.22,
	"hip_y": 0.38, "hip_x": 0.2, "hip_z": -0.15, "knee": 0.22, "height": 0.9,
}
# 蟲巢：一團不會動的卵囊，整團在 body；頂端的大卵囊在 head、四邊的小卵囊在手腳關節（噴酸時一起鼓起來）
const HIVE_JOINTS := {
	"neck": 1.0, "shoulder_y": 0.55, "shoulder_x": 0.6, "shoulder_z": 0.35, "grip": 0.2,
	"hip_y": 0.4, "hip_x": 0.55, "hip_z": -0.4, "height": 1.5,
}
# 噬墓巨蟲：從地裡豎起來的一截蟲身（body），頂端是一圈牙的頭（head），大顎在手臂關節；腳關節是洞口的土塊
const WORM_JOINTS := {
	"neck": 2.7, "neck_z": 0.25, "shoulder_y": 2.7, "shoulder_x": 0.4, "shoulder_z": 0.7, "grip": 0.5,
	"hip_y": 0.15, "hip_x": 0.9, "height": 3.4,
}
# 屍蛾女王：毛茸茸的胸腹在 body、頭與觸角在 head、兩片大翅膀在手臂關節（拍翅 = 轉手臂的 z）、腳關節是垂下來的細腳
const MOTH_JOINTS := {
	"neck": 1.75, "neck_z": 0.35, "shoulder_y": 1.5, "shoulder_x": 0.3, "grip": 0.5,
	"hip_y": 0.8, "hip_x": 0.25, "height": 2.2,
}
const KEEPER_SPADE := Color("9a948a")   # 守墓人鏟面：磨亮的舊鐵（要比地面亮，看得出是鏟子）
const SWORD_TILT := 2.8   # 長劍在手掌座標的傾角（繞 X）
# 死掉時手上的東西掉到地上怎麼躺（HeldDrop）：[東西的方向, 平面的法線]（手持座標）、往哪邊放（out = 順著手臂、feet = 朝腳、
# side = 跟手臂垂直）、躺平時中心離地多高（法線方向的半厚，× 身體縮放）
const LIE := {
	&"sword": [Vector3(0.0, -0.942, 0.335), Vector3(0.0, -0.335, -0.942), &"out", 0.04],   # 長劍、長槍（SWORD_TILT）
	&"keeper_shovel": [Vector3.BACK, Vector3.UP, &"feet", 0.05],   # 守墓人鏟子：鏟面在 -Z、鏟面薄的方向是 Y
	&"hanging": [Vector3.DOWN, Vector3.BACK, &"out", 0.09],        # 提燈這種垂在拳頭下的
	&"enemy_bow": [Vector3.UP, Vector3.RIGHT, &"feet", 0.03],      # 骷髏弓手的弓：弓身在 YZ 平面
	&"shovel": [Vector3.DOWN, Vector3.BACK, &"out", 0.05],         # 玩家鐵鏟：鏟面在 -Y
	&"bow": [Vector3.UP, Vector3.RIGHT, &"side", 0.03],            # 玩家的弓：弓臂沿 ±Y、弓身在 YZ 平面
	&"dagger": [Vector3.DOWN, Vector3.RIGHT, &"out", 0.03],        # 匕首：刀尖 -Y、刃很薄的方向是 X
	&"staff": [Vector3.UP, Vector3.BACK, &"out", 0.1],             # 法杖、火把、權杖：頭在 +Y
}
# 玩家武器（腐屍撿到的也一樣）→ 右手、左手掉下去的東西怎麼躺（LIE 的鍵，空的 = 那隻手沒拿東西）
const LIE_OF := {
	&"longsword": [&"sword", &""], &"shovel": [&"shovel", &""], &"shortbow": [&"", &"bow"], &"longbow": [&"", &"bow"],
	&"dagger": [&"dagger", &"dagger"], &"staff": [&"staff", &""], &"torch": [&"staff", &""], &"scepter": [&"staff", &""],
}
const BOSS_SCALE := 1.85
const KEEPER_SCALE := 1.3
const WOLF_SCALE := 1.45
static var _projectile_kit: PartKit   # 箭的材質（enemy_projectile）

const BLOOD := Color("d8d2bf")        # 骷髏死亡碎骨（網頁版 colors.blood）
const BOSS_BLOOD := Color("55e0ff")   # 亡骸騎士的死亡、狂暴、召喚（網頁版 colors.bossBlood）

const GROUND_COLORS: Array[Color] = [Color("2b3528"), Color("3a4431"), Color("4a4a3a")]
const CATACOMB_GROUND: Array[Color] = [Color("2a2724"), Color("35302a"), Color("423a31")]   # 地下墓窟的石地
const CATACOMB_ROCK: Array[Color] = [Color("2e2925"), Color("3a332c"), Color("252220")]     # 場外的岩塊
const BURROW_GROUND: Array[Color] = [Color("26281c"), Color("323423"), Color("3f3d2a")]     # 蟲蝕墓道的濕土
const BURROW_ROCK: Array[Color] = [Color("2c2b20"), Color("38372a"), Color("23231b")]
const BURROW_EGG := Color("b9c08a")     # 蟲卵（淡黃綠）
const BURROW_SILK := Color("c9cdbd")    # 地上的蟲絲
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
		&"spider":
			rig = spider()
		&"beetle":
			rig = beetle()
		&"hive":
			rig = hive()
		&"lich":
			rig = lich()
		&"wraith":
			rig = wraith()
		&"bone_wheel":
			rig = bone_wheel()
		&"spearman":
			rig = spearman()
		&"gravekeeper":
			rig = gravekeeper()
		&"werewolf":
			rig = werewolf()
		&"boss":
			rig = death_knight()
		&"bone_colossus":
			rig = bone_colossus()
		&"grave_worm":
			rig = grave_worm()
		&"moth_queen":
			rig = moth_queen()
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

	# 上臂：肩甲 + 上臂甲 + 肘甲（手肘彎起來時蓋住接縫）；前臂：前臂甲；拳頭掛在手掌掛點上，轉手掌時拳頭和武器一起轉
	for limb in [[rig.arm_r, rig.forearm_r, rig.hand_r, -1.0], [rig.arm_l, rig.forearm_l, rig.hand_l, 1.0]]:
		k.add(limb[0], PartKit.ico(0.17, 0), k.mat(armor), {"x": limb[3] * 0.04, "y": 0.02, "sy": 0.8})
		k.add(limb[0], PartKit.cyl(0.085, 0.08, 0.3, 6), k.mat(armor), {"y": -0.15})
		k.add(limb[0], PartKit.ico(0.085, 0), k.mat(armor), {"y": -0.3})
		k.add(limb[1], PartKit.cyl(0.08, 0.075, 0.2, 6), k.mat(armor), {"y": -0.1})
		k.add(limb[2], PartKit.box(0.14, 0.17, 0.14), k.mat(trim))
	# 大腿：腿甲；小腿：膝甲 + 脛甲 + 鐵靴（腳底在髖關節下 hip_y）
	for limb in [[rig.leg_r, rig.shin_r], [rig.leg_l, rig.shin_l]]:
		k.add(limb[0], PartKit.cyl(0.1, 0.09, 0.45, 6), k.mat(trim), {"y": -0.22})
		k.add(limb[1], PartKit.ico(0.1, 0), k.mat(armor), {"z": 0.02})
		k.add(limb[1], PartKit.cyl(0.095, 0.11, 0.42, 6), k.mat(armor), {"y": -0.17})
		k.add(limb[1], PartKit.box(0.16, 0.12, 0.27), k.mat(C.iron), {"y": -0.43, "z": 0.04})


# 武器的掛點（模型座標）：grip = 拳頭握的位置；弓另有 string（弓弦上勾弦的點）、鐵鏟另有 hold（托舉點）。
# 模型掛在手掌掛點（拳頭中心）下、往回移 grip，握的位置就在拳頭裡；要轉武器時轉手掌掛點，不轉模型
static func _hold(model: Node3D, mounts: Dictionary) -> Node3D:
	model.set_meta(&"mounts", mounts)
	model.position = -(model.basis * (mounts.grip as Vector3))
	return model


# 長劍：劍身沿局部 +Y，整組繞 X 轉 SWORD_TILT，刃寬在 X；握把中央是 grip
static func _long_sword(k: PartKit, blade: Color, guard: Color, length := 1.0, glow: Variant = null) -> Node3D:
	var g := Node3D.new()
	k.add(g, PartKit.cyl(0.03, 0.03, 0.25, 5), k.mat(C.leather))
	k.add(g, PartKit.ico(0.05), k.mat(guard), {"y": -0.15})
	k.add(g, PartKit.box(0.36, 0.05, 0.07), k.mat(guard), {"y": 0.14})
	k.add(g, PartKit.cyl(0.018, 0.055, length, 4), k.mat(glow, true) if glow != null else k.mat(blade),
		{"y": 0.16 + length / 2.0, "sz": 0.35})
	g.rotation.x = SWORD_TILT
	return _hold(g, {"grip": Vector3.ZERO})


# 劍身方向（手掌座標）
static func sword_axis() -> Vector3:
	return Basis(Vector3.RIGHT, SWORD_TILT) * Vector3.UP


# 手掌方向：手腕上翹 wrist 後再繞劍身轉 roll（PI/2 = 刃朝上下）
static func sword_grip(wrist: float, roll: float) -> Basis:
	return Basis(Vector3.RIGHT, wrist) * Basis(sword_axis(), roll)


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

	for limb in [[rig.arm_r, rig.forearm_r], [rig.arm_l, rig.forearm_l]]:
		k.add(limb[0], PartKit.cyl(0.03, 0.03, 0.3, 4), bone, {"y": -0.17})
		k.add(limb[0], PartKit.sphere(0.04, 5, 4), bone, {"y": -0.33})
		k.add(limb[1], PartKit.cyl(0.028, 0.025, 0.28, 4), bone, {"y": -0.15})
	for hand in [rig.hand_r, rig.hand_l]:
		k.add(hand, PartKit.box(0.07, 0.1, 0.04), bone)   # 骨手掛在手掌掛點上
	for limb in [[rig.leg_r, rig.shin_r], [rig.leg_l, rig.shin_l]]:
		k.add(limb[0], PartKit.cyl(0.035, 0.03, 0.42, 4), bone, {"y": -0.22})
		k.add(limb[0], PartKit.sphere(0.045, 5, 4), bone, {"y": -0.45})
		k.add(limb[1], PartKit.cyl(0.03, 0.028, 0.4, 4), bone, {"y": -0.22})
		k.add(limb[1], PartKit.box(0.08, 0.05, 0.18), bone, {"y": -0.45, "z": 0.04})


static func skeleton() -> Rig:
	var rig := Rig.new(SKELETON_JOINTS)
	_skeleton_base(rig)
	rig.held_r.add_child(_long_sword(rig.kit, C.rust, C.iron, 0.8))
	return rig.optimize()


# 骷髏盾槍兵：右手長槍（槍身沿手臂往前）、左前臂鏽鐵塔盾
static func spearman() -> Rig:
	var rig := Rig.new(SKELETON_JOINTS)
	_skeleton_base(rig)
	var k := rig.kit
	var spear := Node3D.new()
	k.add(spear, PartKit.cyl(0.025, 0.025, 2.0, 5), k.mat(C.wood), {"y": 0.45})
	k.add(spear, PartKit.cone(0.06, 0.28, 4), k.mat(C.steel_dark), {"y": 1.59})
	k.add(spear, PartKit.box(0.16, 0.04, 0.04), k.mat(C.iron), {"y": 1.43})
	spear.rotation.x = 2.8
	rig.held_r.add_child(_hold(spear, {"grip": Vector3.ZERO}))
	var shield := Node3D.new()
	k.add(shield, PartKit.box(0.06, 0.78, 0.5), k.mat(C.rust), {"y": 0.05})
	k.add(shield, PartKit.box(0.08, 0.8, 0.06), k.mat(C.iron), {"y": 0.05})
	k.add(shield, PartKit.box(0.08, 0.06, 0.52), k.mat(C.iron), {"y": 0.3})
	k.add(shield, PartKit.ico(0.06), k.mat(C.bone_dark), {"x": 0.05, "y": 0.1})
	_hold(shield, {"grip": Vector3(-0.07, 0.0, 0.0)})
	shield.position += SPEARMAN_SHIELD_AT
	rig.forearm_l.add_child(shield)
	return rig.optimize()


# 骨輪：骨頭圈（輪面在 YZ 平面、軸沿 X）+ 3 根肋骨輻條 + 輪軸上的頭骨（紅眼朝前）
static func bone_wheel() -> Rig:
	var rig := Rig.new(WHEEL_JOINTS)
	var k := rig.kit
	var bone := k.mat(C.bone)
	var dark := k.mat(C.bone_dark)
	k.add(rig.head, PartKit.torus(WHEEL_RADIUS - 0.06, 0.07, 5, 14), bone, {"rz": PI / 2.0})
	for i in 3:
		k.add(rig.head, PartKit.cyl(0.035, 0.035, WHEEL_RADIUS * 2.0 - 0.1, 4), dark, {"rx": PI * i / 3.0})
	for i in 8:   # 輪圈上一節一節的脊椎骨
		var a := TAU * i / 8.0
		k.add(rig.head, PartKit.box(0.2, 0.09, 0.09), bone, {"y": cos(a) * WHEEL_RADIUS, "z": sin(a) * WHEEL_RADIUS, "rx": -a})
	k.add(rig.head, PartKit.ico(0.17, 1), bone, {"sy": 1.1})
	for s in [-1.0, 1.0]:
		k.add(rig.head, PartKit.sphere(0.045, 5, 4), k.mat(C.socket), {"x": s * 0.065, "y": 0.03, "z": 0.13})
		k.add(rig.head, PartKit.sphere(0.022, 4, 3), k.mat(C.eye_red, true), {"x": s * 0.065, "y": 0.03, "z": 0.16, "shadow": false})
	return rig.optimize()


# 屍甲蟲：深色有光澤的甲殼（中間一道縫）、小頭、一對大顎、6 隻腳
static func beetle() -> Rig:
	var rig := Rig.new(BEETLE_JOINTS)
	var k := rig.kit
	var shell := k.mat(Color("2a2f26"))
	var under := k.mat(Color("4a3a2a"))
	k.add(rig.body, PartKit.sphere(0.24, 8, 5), shell, {"y": 0.22, "sx": 1.0, "sy": 0.55, "sz": 1.35})
	k.add(rig.body, PartKit.box(0.015, 0.02, 0.6), k.mat(Color("15180f")), {"y": 0.35})
	k.add(rig.body, PartKit.sphere(0.2, 6, 4), under, {"y": 0.16, "sy": 0.4, "sz": 1.2})
	for s in [-1.0, 1.0]:   # 中間那對腳
		k.add(rig.body, PartKit.cyl(0.018, 0.012, 0.3, 4), under, {"x": s * 0.26, "y": 0.1, "rz": s * 1.0})
	k.add(rig.head, PartKit.sphere(0.1, 6, 4), shell, {"sy": 0.7})
	for s in [-1.0, 1.0]:
		k.add(rig.head, PartKit.cone(0.025, 0.16, 4), k.mat(C.bone_dark), {"x": s * 0.05, "y": -0.02, "z": 0.12, "rx": PI / 2.0, "ry": -s * 0.4})
		k.add(rig.head, PartKit.sphere(0.018, 4, 3), k.mat(C.rot_eye, true), {"x": s * 0.05, "y": 0.04, "z": 0.08, "shadow": false})
	for limb in [[rig.arm_r, rig.forearm_r], [rig.arm_l, rig.forearm_l], [rig.leg_r, rig.shin_r], [rig.leg_l, rig.shin_l]]:
		k.add(limb[0], PartKit.cyl(0.018, 0.015, 0.11, 4), under, {"y": -0.05})
		k.add(limb[1], PartKit.cyl(0.015, 0.01, 0.11, 4), under, {"y": -0.05})
	return rig.optimize()


# 尖嘯幽影：灰藍的破斗篷往下收成一縷（沒有腳）、兜帽裡一張骷髏臉與發白光的眼、兩隻細長的手
static func wraith() -> Rig:
	var rig := Rig.new(SKELETON_JOINTS)
	var k := rig.kit
	var shroud := k.mat(Color("4a5568"))
	var dark := k.mat(Color("2a3140"))
	var bone := k.mat(C.bone)
	k.add(rig.body, PartKit.cyl(0.3, 0.06, 1.25, 7), shroud, {"y": 0.85})
	k.add(rig.body, PartKit.cyl(0.26, 0.3, 0.35, 7), dark, {"y": 1.35})
	k.add(rig.head, PartKit.sphere(0.24, 7, 5), dark, {"y": 0.18})
	k.add(rig.head, PartKit.ico(0.15, 1), bone, {"y": 0.16, "z": 0.1})
	for s in [-1.0, 1.0]:
		k.add(rig.head, PartKit.sphere(0.035, 4, 3), k.mat(Color("dfefff"), true), {"x": s * 0.06, "y": 0.19, "z": 0.23, "shadow": false})
	for arm in [rig.arm_r, rig.arm_l]:
		k.add(arm, PartKit.cyl(0.05, 0.025, 0.7, 5), shroud, {"y": -0.32})
		for c in 3:
			k.add(arm, PartKit.cone(0.015, 0.16, 4), bone, {"x": (c - 1) * 0.035, "y": -0.72, "rx": PI})
	for leg in [rig.leg_r, rig.leg_l]:
		k.add(leg, PartKit.cyl(0.06, 0.01, 0.5, 4), dark, {"y": -0.3})
	return rig.optimize()


# 屍巫：戴兜帽的骷髏、深紫長袍拖到地上、兩手掌心各一團紫火（掛在手臂末端：手的掛點底下的零件不進蒙皮版）
static func lich() -> Rig:
	var rig := Rig.new(SKELETON_JOINTS)
	_skeleton_base(rig, true)
	var k := rig.kit
	var robe := k.mat(Color("3a2a4a"))
	k.add(rig.body, PartKit.cyl(0.2, 0.36, 0.95, 7), robe, {"y": 0.5})
	k.add(rig.body, PartKit.cyl(0.25, 0.21, 0.5, 7), robe, {"y": 1.22})
	for arm in [rig.arm_r, rig.arm_l]:
		k.add(arm, PartKit.sphere(0.07, 6, 4), k.mat(Color("b070ff"), true), {"y": -float(SKELETON_JOINTS.grip), "shadow": false})
	return rig.optimize()


# 蟲巢：土黃色的肉瘤堆、表面嵌著發淡光的卵、幾條把它黏在地上的蟲絲
static func hive() -> Rig:
	var rig := Rig.new(HIVE_JOINTS)
	var k := rig.kit
	var flesh := k.mat(Color("6b6a3e"))
	var dark := k.mat(Color("3a3a24"))
	var egg := k.mat(BURROW_EGG, true)
	k.add(rig.body, PartKit.sphere(0.85, 9, 6), flesh, {"y": 0.45, "sy": 0.75})
	k.add(rig.body, PartKit.sphere(0.6, 8, 5), dark, {"y": 0.2, "sx": 1.5, "sy": 0.35, "sz": 1.5})   # 攤在地上的底
	for i in 6:   # 嵌在表面的卵
		var a := TAU * i / 6.0 + 0.3
		k.add(rig.body, PartKit.sphere(0.13, 6, 4), egg, {"x": sin(a) * 0.7, "y": 0.45 + 0.2 * sin(i * 2.1), "z": cos(a) * 0.7, "sy": 1.3, "shadow": false})
	for i in 4:   # 黏在地上的蟲絲
		var a := TAU * i / 4.0 + 0.8
		k.add(rig.body, PartKit.cyl(0.02, 0.02, 1.1, 4), k.mat(BURROW_SILK), {"x": sin(a) * 1.1, "y": 0.25, "z": cos(a) * 1.1, "rz": PI / 2.0 - 0.45, "ry": a - PI / 2.0})
	k.add(rig.head, PartKit.sphere(0.42, 8, 5), flesh, {"sy": 1.1})
	k.add(rig.head, PartKit.sphere(0.16, 6, 4), egg, {"y": 0.38, "shadow": false})
	for limb in [rig.arm_r, rig.arm_l, rig.leg_r, rig.leg_l]:
		k.add(limb, PartKit.sphere(0.3, 7, 4), flesh, {"sy": 0.9})
		k.add(limb, PartKit.sphere(0.1, 5, 3), egg, {"y": 0.22, "shadow": false})
	return rig.optimize()


# 墓穴蜘蛛：灰黑的大腹部（背上骨白的花紋）、小頭胸部、一排 6 顆紅眼、8 隻細長的腳
static func spider() -> Rig:
	var rig := Rig.new(SPIDER_JOINTS)
	var k := rig.kit
	var hide := k.mat(Color("2c2830"))
	var leg := k.mat(Color("3a3440"))
	k.add(rig.body, PartKit.sphere(0.34, 8, 6), hide, {"y": 0.48, "z": -0.38, "sy": 0.85, "sz": 1.15})   # 腹部
	k.add(rig.body, PartKit.box(0.14, 0.04, 0.3), k.mat(C.bone_dark), {"y": 0.77, "z": -0.38})
	k.add(rig.body, PartKit.sphere(0.2, 7, 5), hide, {"y": 0.4, "z": 0.08, "sy": 0.7})                      # 頭胸部
	for s in [-1.0, 1.0]:
		for z in [0.12, -0.05]:   # 中間兩對腳：往外伸再往下
			k.add(rig.body, PartKit.cyl(0.022, 0.016, 0.55, 4), leg, {"x": s * 0.32, "y": 0.42, "z": z, "rz": s * 1.15})
			k.add(rig.body, PartKit.cyl(0.016, 0.01, 0.45, 4), leg, {"x": s * 0.58, "y": 0.2, "z": z, "rz": -s * 0.35})
	k.add(rig.head, PartKit.sphere(0.11, 6, 4), hide, {"sy": 0.8})
	for i in 6:
		var x := (i % 3 - 1) * 0.045
		k.add(rig.head, PartKit.sphere(0.02, 4, 3), k.mat(C.eye_red, true), {"x": x, "y": 0.04 + (i / 3) * 0.035, "z": 0.1, "shadow": false})
	for s in [-1.0, 1.0]:
		k.add(rig.head, PartKit.cone(0.025, 0.12, 4), k.mat(C.bone_dark), {"x": s * 0.04, "y": -0.06, "z": 0.08, "rx": PI * 0.8})
	for limb in [[rig.arm_r, rig.forearm_r], [rig.arm_l, rig.forearm_l], [rig.leg_r, rig.shin_r], [rig.leg_l, rig.shin_l]]:
		k.add(limb[0], PartKit.cyl(0.024, 0.018, 0.23, 4), leg, {"y": -0.11})
		k.add(limb[0], PartKit.sphere(0.024, 4, 3), leg, {"y": -0.22})
		k.add(limb[1], PartKit.cyl(0.018, 0.01, 0.2, 4), leg, {"y": -0.1})
	return rig.optimize()


static func skeleton_archer() -> Rig:
	var rig := Rig.new(SKELETON_JOINTS)
	_skeleton_base(rig, true)
	rig.held_l.add_child(_bow(rig.kit, C.wood))
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
	for limb in [[rig.arm_r, rig.forearm_r], [rig.arm_l, rig.forearm_l]]:
		k.add(limb[0], PartKit.cyl(0.07, 0.06, 0.34, 5), cloth, {"y": -0.17})
		k.add(limb[1], PartKit.cyl(0.05, 0.045, 0.3, 5), skin, {"y": -0.13})
	for hand in [rig.hand_r, rig.hand_l]:
		k.add(hand, PartKit.box(0.09, 0.12, 0.05), skin)
	for limb in [[rig.leg_r, rig.shin_r], [rig.leg_l, rig.shin_l]]:
		k.add(limb[0], PartKit.cyl(0.085, 0.075, 0.45, 5), k.mat(C.rag_dark), {"y": -0.22})
		k.add(limb[1], PartKit.cyl(0.06, 0.055, 0.4, 5), skin, {"y": -0.18})
		k.add(limb[1], PartKit.box(0.1, 0.06, 0.2), dark, {"y": -0.42, "z": 0.04})
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
	for limb in [[rig.arm_r, rig.forearm_r], [rig.arm_l, rig.forearm_l]]:
		k.add(limb[0], PartKit.cyl(0.08, 0.07, 0.34, 5), skin, {"y": -0.17})
		k.add(limb[1], PartKit.cyl(0.065, 0.055, 0.3, 5), dark, {"y": -0.13})
	for hand in [rig.hand_r, rig.hand_l]:
		k.add(hand, PartKit.box(0.1, 0.12, 0.06), skin)
	for limb in [[rig.leg_r, rig.shin_r], [rig.leg_l, rig.shin_l]]:
		k.add(limb[0], PartKit.cyl(0.1, 0.09, 0.45, 5), k.mat(C.rag_dark), {"y": -0.22})
		k.add(limb[1], PartKit.cyl(0.075, 0.065, 0.4, 5), skin, {"y": -0.18})
		k.add(limb[1], PartKit.box(0.12, 0.06, 0.2), dark, {"y": -0.42, "z": 0.04})
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
	for limb in [[rig.arm_r, rig.forearm_r], [rig.arm_l, rig.forearm_l], [rig.leg_r, rig.shin_r], [rig.leg_l, rig.shin_l]]:
		k.add(limb[0], PartKit.cyl(0.06, 0.045, 0.28, 5), fur, {"y": -0.14})
		k.add(limb[1], PartKit.cyl(0.035, 0.03, 0.26, 4), bone, {"y": -0.11})
		k.add(limb[1], PartKit.box(0.07, 0.04, 0.1), bone, {"y": -0.25, "z": 0.03})
	return rig.optimize()


# 守墓人：駝背的老人，寬簷帽、灰白鬍子、長外套；右手鐵鏟、左手提燈（燈火發光）
static func gravekeeper() -> Rig:
	var j := KNIGHT_JOINTS.duplicate()
	j["scale"] = KEEPER_SCALE
	var rig := Rig.new(j)
	var k := rig.kit
	var coat := k.mat(C.keeper_coat)
	var skin := k.mat(C.keeper_skin)
	k.add(rig.body, PartKit.cyl(0.28, 0.34, 0.75, 7), coat, {"y": 1.15})
	k.add(rig.body, PartKit.cyl(0.34, 0.38, 0.4, 7), coat, {"y": 0.72})   # 外套下擺
	k.add(rig.body, PartKit.box(0.5, 0.06, 0.32), k.mat(C.leather), {"y": 0.98})   # 腰帶
	k.add(rig.head, PartKit.ico(0.17, 1), skin, {"y": 0.16})
	k.add(rig.head, PartKit.cone(0.15, 0.3, 6), k.mat(C.keeper_beard), {"y": 0.0, "z": 0.12, "rx": PI})
	k.add(rig.head, PartKit.cyl(0.36, 0.36, 0.03, 10), k.mat(C.keeper_hat), {"y": 0.3})
	k.add(rig.head, PartKit.cyl(0.17, 0.2, 0.22, 8), k.mat(C.keeper_hat), {"y": 0.42})
	for s in [-1.0, 1.0]:
		k.add(rig.head, PartKit.sphere(0.025, 4, 3), k.mat(C.socket), {"x": s * 0.06, "y": 0.2, "z": 0.15})
	for limb in [[rig.arm_r, rig.forearm_r, rig.hand_r], [rig.arm_l, rig.forearm_l, rig.hand_l]]:
		k.add(limb[0], PartKit.cyl(0.085, 0.078, 0.31, 6), coat, {"y": -0.15})
		k.add(limb[1], PartKit.cyl(0.078, 0.07, 0.17, 6), coat, {"y": -0.08})
		k.add(limb[2], PartKit.box(0.1, 0.12, 0.09), skin)
	for limb in [[rig.leg_r, rig.shin_r], [rig.leg_l, rig.shin_l]]:
		k.add(limb[0], PartKit.cyl(0.09, 0.085, 0.48, 6), k.mat(C.keeper_hat), {"y": -0.24})
		k.add(limb[1], PartKit.cyl(0.085, 0.075, 0.38, 6), k.mat(C.keeper_hat), {"y": -0.18})
		k.add(limb[1], PartKit.box(0.14, 0.1, 0.26), k.mat(C.leather), {"y": -0.41, "z": 0.05})
	# 鐵鏟：手握在柄的上段（grip），上端 T 型握把、下端鐵套環接鏟面，鏟面是磨亮的舊鐵、底下尖（暗色的鐵在墓地裡看不出是鏟子）
	var shovel := Node3D.new()
	var blade := k.mat(KEEPER_SPADE)
	k.add(shovel, PartKit.box(0.2, 0.045, 0.045), k.mat(C.wood), {"y": 0.48})
	k.add(shovel, PartKit.cyl(0.028, 0.028, 1.06, 5), k.mat(C.wood), {"y": -0.05})
	k.add(shovel, PartKit.cyl(0.045, 0.04, 0.1, 6), k.mat(C.iron), {"y": -0.6})
	# 鏟面寬大於長、上緣有一道踩腳的捲邊、底下只微尖（太長太尖會像矛頭）
	k.add(shovel, PartKit.box(0.36, 0.3, 0.025), blade, {"y": -0.79, "rx": -0.15})
	k.add(shovel, PartKit.box(0.38, 0.035, 0.06), k.mat(C.iron), {"y": -0.645, "z": 0.01, "rx": -0.15})
	k.add(shovel, PartKit.box(0.16, 0.16, 0.025), blade, {"y": -0.9, "z": 0.017, "rx": -0.15, "rz": PI / 4.0})   # 尖端：轉 45° 的小方塊下半露出 6 公分
	shovel.rotation.x = PI / 2.0
	rig.held_r.add_child(_hold(shovel, {"grip": Vector3(0.0, 0.2, 0.0)}))
	# 提燈：提把在 grip，燈火發光（噴火的特效從這裡出來）
	var lantern := Node3D.new()
	k.add(lantern, PartKit.box(0.18, 0.24, 0.18), k.mat(C.iron), {"y": -0.2})
	k.add(lantern, PartKit.box(0.12, 0.16, 0.12), k.mat(C.keeper_flame, true), {"y": -0.2, "shadow": false})
	rig.held_l.add_child(_hold(lantern, {"grip": Vector3.ZERO}))
	return rig.optimize()


# 墓園狼人（守墓人半血變身）：比老人高大，黑灰毛、狼頭（口鼻、尖耳、黃眼）、爪子，身上還掛著破外套
static func werewolf() -> Rig:
	var j := KNIGHT_JOINTS.duplicate()
	j["scale"] = WOLF_SCALE
	var rig := Rig.new(j)
	var k := rig.kit
	var fur := k.mat(C.wolf_fur)
	var dark := k.mat(C.hound_fur)
	k.add(rig.body, PartKit.cyl(0.36, 0.26, 0.8, 7), fur, {"y": 1.2})
	k.add(rig.body, PartKit.box(0.6, 0.35, 0.05), k.mat(C.keeper_coat), {"y": 0.95, "z": -0.26, "rx": 0.15})   # 撐破的外套
	k.add(rig.body, PartKit.cyl(0.24, 0.26, 0.3, 7), dark, {"y": 0.82})
	k.add(rig.head, PartKit.box(0.32, 0.3, 0.32), fur, {"y": 0.16, "z": 0.02})
	k.add(rig.head, PartKit.box(0.18, 0.15, 0.3), dark, {"y": 0.1, "z": 0.28})
	for s in [-1.0, 1.0]:
		k.add(rig.head, PartKit.cone(0.07, 0.22, 4), fur, {"x": s * 0.11, "y": 0.38, "z": 0.0})
		k.add(rig.head, PartKit.sphere(0.03, 4, 3), k.mat(C.rot_eye, true), {"x": s * 0.08, "y": 0.2, "z": 0.18, "shadow": false})
	for limb in [[rig.arm_r, rig.forearm_r, rig.hand_r], [rig.arm_l, rig.forearm_l, rig.hand_l]]:
		k.add(limb[0], PartKit.cyl(0.11, 0.095, 0.32, 6), fur, {"y": -0.15})
		k.add(limb[1], PartKit.cyl(0.095, 0.08, 0.2, 6), fur, {"y": -0.1})
		k.add(limb[2], PartKit.box(0.14, 0.14, 0.12), dark)
		for c in 3:
			k.add(limb[2], PartKit.cone(0.025, 0.16, 4), k.mat(C.bone), {"x": (c - 1) * 0.045, "y": -0.13, "z": 0.04, "rx": PI})
	for limb in [[rig.leg_r, rig.shin_r], [rig.leg_l, rig.shin_l]]:
		k.add(limb[0], PartKit.cyl(0.12, 0.1, 0.48, 6), fur, {"y": -0.24})
		k.add(limb[1], PartKit.cyl(0.1, 0.07, 0.38, 6), fur, {"y": -0.18})
		k.add(limb[1], PartKit.box(0.16, 0.1, 0.28), dark, {"y": -0.41, "z": 0.06})
	return rig.optimize()


static func death_knight() -> Rig:
	var j := KNIGHT_JOINTS.duplicate()
	j["scale"] = BOSS_SCALE
	var rig := Rig.new(j)
	_armored_body(rig, C.death_armor, C.iron, Color("1c1a22"), C.death_eye, true)
	rig.held_r.add_child(_long_sword(rig.kit, Color("9aa4b4"), C.iron, 1.35, Color("7fe8ff")))
	return rig.optimize()


# 萬骨聚合體（骸骨將軍的第二型態）：矮壯的骨堆巨人。骨盆是一堆骨球、胸口一圈圈肋骨嵌著小頭骨、背上多兩對骨臂；
# 大頭骨的眼睛是將軍的青光。比例照 COLOSSUS_JOINTS（駝背、手長腿短），整隻 × BOSS_SCALE × colossus.scale
static func bone_colossus() -> Rig:
	var j := COLOSSUS_JOINTS.duplicate()
	j["scale"] = BOSS_SCALE * float(EnemyDefs.ENEMIES.bone_general.colossus.scale) * 0.8
	var rig := Rig.new(j)
	var k := rig.kit
	var bone := k.mat(C.bone)
	var dark := k.mat(C.bone_dark)
	var eye := k.mat(C.death_eye, true)
	for i in 7:   # 骨盆：一堆骨球
		var a := TAU * i / 7.0
		k.add(rig.body, PartKit.ico(0.2 + 0.05 * (i % 3), 0), bone if i % 2 == 0 else dark, {"x": cos(a) * 0.28, "y": 0.62 + 0.06 * (i % 2), "z": sin(a) * 0.22})
	k.add(rig.body, PartKit.cyl(0.07, 0.07, 0.7, 5), dark, {"y": 1.0})   # 脊椎
	for i in 4:
		k.add(rig.body, PartKit.torus(0.42 - i * 0.04, 0.04, 4, 10), bone, {"y": 0.92 + i * 0.12, "rx": PI / 2.0, "sy": 0.75})
	for p in [[-0.18, 1.02], [0.2, 1.1], [0.0, 1.22]]:   # 胸口嵌著的小頭骨
		k.add(rig.body, PartKit.ico(0.1, 1), bone, {"x": p[0], "y": p[1], "z": 0.3})
		k.add(rig.body, PartKit.sphere(0.02, 4, 3), eye, {"x": p[0], "y": p[1] + 0.02, "z": 0.39, "shadow": false})
	for s in [-1.0, 1.0]:   # 背上多出來的兩對骨臂（固定的，往外張開）
		for h in [0.95, 1.15]:
			k.add(rig.body, PartKit.cyl(0.04, 0.03, 0.75, 4), dark, {"x": s * 0.55, "y": h, "z": -0.2, "rz": s * 1.1, "rx": 0.4})
	k.add(rig.head, PartKit.ico(0.26, 1), bone, {"y": 0.16, "sy": 1.05})
	k.add(rig.head, PartKit.box(0.26, 0.09, 0.2), dark, {"y": -0.04, "z": 0.06})
	for s in [-1.0, 1.0]:
		k.add(rig.head, PartKit.sphere(0.07, 5, 4), k.mat(C.socket), {"x": s * 0.1, "y": 0.2, "z": 0.2})
		k.add(rig.head, PartKit.sphere(0.04, 4, 3), eye, {"x": s * 0.1, "y": 0.2, "z": 0.25, "shadow": false})
	for limb in [[rig.arm_r, rig.forearm_r], [rig.arm_l, rig.forearm_l]]:
		k.add(limb[0], PartKit.cyl(0.07, 0.06, 0.45, 5), bone, {"y": -0.24})
		k.add(limb[0], PartKit.ico(0.08, 0), dark, {"y": -0.5})
		k.add(limb[1], PartKit.cyl(0.06, 0.05, 0.45, 5), bone, {"y": -0.25})
	for hand in [rig.hand_r, rig.hand_l]:
		for c in 3:   # 爪子
			k.add(hand, PartKit.cone(0.03, 0.22, 4), bone, {"x": (c - 1) * 0.06, "y": -0.12, "rx": PI})
	for limb in [[rig.leg_r, rig.shin_r], [rig.leg_l, rig.shin_l]]:
		k.add(limb[0], PartKit.cyl(0.08, 0.075, 0.22, 5), bone, {"y": -0.11})
		k.add(limb[1], PartKit.cyl(0.075, 0.07, 0.16, 5), bone, {"y": -0.08})
		k.add(limb[1], PartKit.box(0.16, 0.08, 0.26), dark, {"y": -0.18, "z": 0.05})
	return rig.optimize()


# 噬墓巨蟲：一節一節的灰褐蟲身、節與節之間的深色環、頂端的頭有一圈往內的牙與一對大顎
static func grave_worm() -> Rig:
	var rig := Rig.new(WORM_JOINTS)
	var k := rig.kit
	var flesh := k.mat(Color("8d7f5f"))
	var ring := k.mat(Color("4d4433"))
	var tooth := k.mat(C.bone)
	for i in 5:
		var r := 0.85 - i * 0.05
		k.add(rig.body, PartKit.cyl(r - 0.04, r, 0.5, 9), flesh, {"y": 0.3 + i * 0.52})
		k.add(rig.body, PartKit.cyl(r - 0.1, r - 0.1, 0.06, 9), ring, {"y": 0.56 + i * 0.52})
	k.add(rig.head, PartKit.sphere(0.68, 9, 6), flesh, {"sz": 1.15})
	k.add(rig.head, PartKit.cyl(0.42, 0.5, 0.12, 9), k.mat(Color("1a0f12")), {"z": 0.72, "rx": PI / 2.0})   # 嘴裡
	for i in 8:
		var a := TAU * i / 8.0
		k.add(rig.head, PartKit.cone(0.06, 0.3, 4), tooth, {"x": cos(a) * 0.4, "y": sin(a) * 0.4, "z": 0.8, "rx": PI / 2.0})
	for s in [-1.0, 1.0]:
		k.add(rig.head, PartKit.sphere(0.05, 4, 3), k.mat(C.rot_eye, true), {"x": s * 0.35, "y": 0.4, "z": 0.45, "shadow": false})
	for arm in [rig.arm_r, rig.arm_l]:
		k.add(arm, PartKit.cone(0.1, 0.75, 5), tooth, {"z": 0.3, "rx": PI / 2.0})
	for leg in [rig.leg_r, rig.leg_l]:
		k.add(leg, PartKit.ico(0.45, 0), ring, {"sy": 0.5})
	return rig.optimize()


# 屍蛾女王：灰白帶毛的胸、一節節往後垂的腹部、兩片有眼斑的大翅膀、羽毛狀的觸角、發綠光的複眼
static func moth_queen() -> Rig:
	var rig := Rig.new(MOTH_JOINTS)
	var k := rig.kit
	var fur := k.mat(Color("b9b2a0"))
	var dark := k.mat(Color("4a4338"))
	var wing := k.mat(Color("8f8672"))
	var spot := k.mat(Color("2a2420"))
	k.add(rig.body, PartKit.sphere(0.45, 8, 6), fur, {"y": 1.45, "sz": 1.2})
	for i in 4:   # 腹部：越往後越小、往下垂
		k.add(rig.body, PartKit.sphere(0.36 - i * 0.05, 7, 5), dark if i % 2 == 1 else fur, {"y": 1.25 - i * 0.2, "z": -0.45 - i * 0.3})
	k.add(rig.head, PartKit.sphere(0.28, 7, 5), fur, {})
	for s in [-1.0, 1.0]:
		k.add(rig.head, PartKit.sphere(0.11, 6, 4), k.mat(Color("a8e04a"), true), {"x": s * 0.18, "y": 0.05, "z": 0.2, "shadow": false})
		k.add(rig.head, PartKit.box(0.04, 0.5, 0.12), dark, {"x": s * 0.14, "y": 0.42, "z": 0.1, "rz": -s * 0.5, "rx": -0.4})
	for side: Array in [[rig.arm_r, -1.0], [rig.arm_l, 1.0]]:
		var arm: Node3D = side[0]
		var s: float = side[1]
		k.add(arm, PartKit.box(1.7, 0.04, 1.2), wing, {"x": s * 0.95, "z": 0.15})      # 前翅
		k.add(arm, PartKit.box(1.2, 0.04, 0.9), wing, {"x": s * 0.7, "z": -0.75})      # 後翅
		k.add(arm, PartKit.cyl(0.22, 0.22, 0.05, 8), spot, {"x": s * 1.2, "y": 0.01, "z": 0.2})   # 眼斑
	for leg in [rig.leg_r, rig.leg_l]:
		k.add(leg, PartKit.cyl(0.03, 0.02, 0.7, 4), dark, {"y": -0.35})
	return rig.optimize()


# ───────── 玩家武器 ─────────

# 主手武器 → { kit, main（掛右手）, left（掛左手，弓），gem（會自轉，可為 null）… }；副手另外由 offhand 建
static func weapon(model: StringName) -> Dictionary:
	match model:
		&"longsword":
			var k := PartKit.new()
			var sword := _long_sword(k, Color("b8c0cc"), C.steel_dark, 0.95)
			k.merge_static(sword, [sword])
			return {"kit": k, "main": sword, "gem": null}
		&"dagger":
			var k := PartKit.new()
			return {"kit": k, "main": _dagger(k), "gem": null}
		&"staff":
			return _staff()
		&"shortbow":
			return _player_bow(0.5, Color("8a5a32"), BOW_ARROW)
		&"longbow":
			return _player_bow(0.8, Color("5a3a1e"), BOW_ARROW)
		&"scepter":
			return _scepter()
		&"torch":
			return _torch()
		&"shovel":
			return _shovel()
	return {}


# 副手 → { kit, offhand（盾，掛左前臂外側掛點 forearm_l）或 left（匕首，掛 hand_l） }
static func offhand(model: StringName) -> Dictionary:
	var k := PartKit.new()
	match model:
		&"woodShield":
			return {"kit": k, "offhand": _shield(k)}
		&"dagger":
			return {"kit": k, "left": _dagger(k)}
	return {}


# 匕首（F6）：刀尖朝手掌 -Y、刃寬與護手在 Z；左手那把直接掛 hand_l。刀尖朝哪由 Animator.aim_blade 轉手掌
# 2026-10-27 網頁版實測：原本左手那把掛在左臂、轉 90°，畫面上看不到
static func _dagger(k: PartKit) -> Node3D:
	var g := Node3D.new()
	k.add(g, PartKit.cone(0.045, 0.42, 4), k.mat(Color("c8d0e0")), {"y": 0.3, "sx": 0.35})
	k.add(g, PartKit.box(0.05, 0.03, 0.16), k.mat(C.steel_dark), {"y": 0.09})
	k.add(g, PartKit.cyl(0.025, 0.025, 0.14, 4), k.mat(C.leather), {"y": 0.0})
	k.merge_static(g, [g])
	g.rotation.x = PI   # 刀尖朝 -Y
	return _hold(g, {"grip": Vector3.ZERO})


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
# 箭袋（身體座標，玩家騎士 KNIGHT_JOINTS 的右肩在 (-0.36, 1.55, 0)、手臂長 0.58）：照真人的背後箭袋，背在上背、袋口在右肩胛後面跟肩膀
# 差不多高，斜到左腰後；箭只露出袋口 QUIVER_OUT（真人約 4~6 吋、箭長的 15%），箭尾在肩膀頂端的高度。拉弓時右手往後伸過肩抓箭尾
# （QUIVER_GRAB，離右肩 0.51），沿箭袋往上拉到搆得到的最遠處（QUIVER_PULL），之後翻過肩（Animator.pose_bow）。
# 改肩膀、手臂長或箭長要重算。箭袋在披風（背面 z 約 -0.37）外面
# 玩家的箭長（兩把弓一樣，拉弦長由身體決定）：Animator.pose_bow 拉滿時拳頭在右臉頰旁、弓手打直，兩者距離約 0.84，
# 箭長 = 那段 + 0.1（拉滿時箭頭剛好露出弓外 0.1）；改骨架的肩寬、手臂長或 Animator.ANCHOR_* 要一起改
const BOW_ARROW := 0.95
const QUIVER_AXIS := Vector3(-0.4512, 0.8924, 0.0)   # 袋底 → 袋口（往右上斜約 27°）
const QUIVER_MOUTH := Vector3(-0.3, 1.5, -0.48)      # 右肩胛後面
const QUIVER_OUT := 0.15                             # 箭露出袋口多長
const QUIVER_GRAB := QUIVER_MOUTH + QUIVER_AXIS * QUIVER_OUT   # 露出袋口的箭尾、手抓的地方
const QUIVER_PULL := 0.19                            # 沿箭袋往上拉多遠（手臂伸到底；拉不出整支，剩下的翻過肩時順著袋口出來）
const QUIVER_BOTTOM := QUIVER_MOUTH - QUIVER_AXIS * (BOW_ARROW - QUIVER_OUT + 0.02)
const QUIVER_RADIUS := 0.11


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
	var head := k.add(nock, PartKit.cone(0.05, 0.16, 4), k.mat(Color("e8eef8"), true), {"z": -arrow - 0.06, "rx": -PI / 2.0})
	for sgn in [-1.0, 1.0]:
		k.add(nock, PartKit.box(0.1, 0.012, 0.16), k.mat(Color("f0f0f0")), {"z": -0.06, "rz": sgn * 0.3})
	k.merge_static(nock, [nock], [head])   # 箭頭不合併：從箭袋抽出來、箭頭還在袋裡時要藏起來（Animator._bow_visuals）
	nock.set_meta(&"head", head)
	nock.set_meta(&"arrow", arrow)   # Animator 用來限制拉弦距離（箭尾不能拉過箭頭）
	nock.visible = false
	var out := {"kit": k, "main": null, "offhand": null, "left": g, "nock": nock, "gem": null}
	var quiver_count: int = WeaponDefs.WEAPONS[&"shortbow"].attack.quiver
	# 箭袋：從右肩胛後（袋口）斜到左腰後；袋口露出 quiver_count 支箭尾（各自一個節點，不合併，射一支藏一支）
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
		var out_len := QUIVER_OUT
		a.position = Vector3(cos(ang) * QUIVER_RADIUS * 0.5, length / 2.0, sin(ang) * QUIVER_RADIUS * 0.5)
		k.add(a, PartKit.cyl(0.014, 0.014, out_len, 3), k.mat(Color("e0c890")), {"y": out_len / 2.0})
		k.add(a, PartKit.box(0.08, 0.13, 0.012), k.mat(Color("f0f0f0")), {"y": out_len - 0.06, "ry": ang})
		quiver.add_child(a)
		arrows.append(a)
	quiver.basis = Basis(Quaternion(Vector3.UP, axis.normalized()))
	# 掛在背部掛點：grip 是背部掛點在箭袋座標裡的位置，掛上去後箭袋正好在袋口與袋底中間
	var back: Vector3 = KNIGHT_MOUNTS[&"back"]
	_hold(quiver, {"grip": quiver.basis.inverse() * (back - (QUIVER_MOUTH + QUIVER_BOTTOM) / 2.0)})
	out["back"] = quiver
	out["quiver_arrows"] = arrows
	return out


static func _shield(k: PartKit) -> Node3D:
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
	k.merge_static(shield, [shield])
	return shield


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
# theme：MapDefs 的 theme（graveyard 墓園 / catacomb 地下墓窟 / burrow 蟲蝕墓道）
static func build_arena(half: Vector2, rng: RandomNumberGenerator, theme: StringName = &"graveyard") -> Node3D:
	if theme == &"catacomb":
		return _build_catacomb(half, rng)
	if theme == &"burrow":
		return _build_burrow(half, rng)
	var k := PartKit.new()
	var group := Node3D.new()

	var rocks: Array[StandardMaterial3D] = []
	for c in ROCK_COLORS:
		rocks.append(k.mat(c))
	_perimeter_rocks(group, half, rng, rocks, 0.45, 0.45)

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
	group.add_child(ArenaView.create_ground((half + Vector2(14.0, 14.0)) * 2.0, GROUND_COLORS, 1.8, 0.1, rng))
	return group


# 沿著場地邊界一圈石頭（半徑 size_min ~ size_min + size_range、壓扁 / 拉高 0.8~1.4 倍、隨機轉向）：
# 一種顏色一個 MultiMesh（同一份平面法線的單位二十面體），邊界上上千顆也不用逐顆建節點再合併
static var _rock_mesh: ArrayMesh


static func _perimeter_rocks(group: Node3D, half: Vector2, rng: RandomNumberGenerator, mats: Array[StandardMaterial3D], size_min: float, size_range: float) -> void:
	if _rock_mesh == null:
		_rock_mesh = PartKit.flat_mesh(PartKit.ico(1.0, 0), Transform3D.IDENTITY)
	var per_mat: Array[Array] = []
	for m in mats:
		per_mat.append([])
	for p in ArenaView.perimeter_points(half, 1.1, 0.6):
		var s := size_min + rng.randf() * size_range
		var which := rng.randi_range(0, mats.size() - 1)
		var pos := Vector3(p.x + (rng.randf() - 0.5) * 0.4, s * 0.5, p.z + (rng.randf() - 0.5) * 0.4)
		var rot := Vector3(rng.randf() * 3.0, rng.randf() * 3.0, 0.0)
		var basis := Basis.from_euler(rot, EULER_ORDER_XYZ) * Basis.from_scale(Vector3(s, s * (0.8 + rng.randf() * 0.6), s))
		per_mat[which].append(Transform3D(basis, pos))
	for i in mats.size():
		var list: Array = per_mat[i]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _rock_mesh
		mm.instance_count = list.size()
		for j in list.size():
			mm.set_instance_transform(j, list[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mats[i]
		group.add_child(mmi)


# 地下墓窟：場外是一塊塊岩石（沒有墓碑與樹），場內散落碎骨與頭骨堆
static func _build_catacomb(half: Vector2, rng: RandomNumberGenerator) -> Node3D:
	var k := PartKit.new()
	var group := Node3D.new()
	var rocks: Array[StandardMaterial3D] = []
	for c in CATACOMB_ROCK:
		rocks.append(k.mat(c))
	_perimeter_rocks(group, half, rng, rocks, 0.5, 0.5)
	for p in ArenaView.scatter_outside(rng, half, 40, 1.8, 11.0):
		var s: float = (1.0 + rng.randf() * 1.4) * p.s
		k.add(group, PartKit.ico(s, 0), rocks[rng.randi_range(0, 2)], {
			"x": p.x, "y": s * 0.35, "z": p.z, "rx": rng.randf() * 3.0, "ry": p.ry, "sy": 0.6 + rng.randf() * 0.8,
		})
	var bone := k.mat(C.bone_dark)
	var skull := k.mat(C.bone)
	for p in ArenaView.scatter_inside(rng, half, 28):
		k.add(group, PartKit.cyl(0.03, 0.03, 0.35, 4), bone, {"x": p.x, "y": 0.03, "z": p.z, "rz": PI / 2.0, "ry": p.ry, "shadow": false})
	for p in ArenaView.scatter_inside(rng, half, 10):
		for i in 3 + rng.randi_range(0, 2):   # 頭骨堆：幾顆小球疊在一起
			var a := rng.randf() * TAU
			var r := rng.randf() * 0.25
			k.add(group, PartKit.sphere(0.13, 6, 4), skull, {
				"x": p.x + cos(a) * r, "y": 0.1 + (0.12 if i >= 3 else 0.0), "z": p.z + sin(a) * r, "shadow": false,
			})
	k.merge_static(group, [group])
	group.add_child(ArenaView.create_ground((half + Vector2(14.0, 14.0)) * 2.0, CATACOMB_GROUND, 1.8, 0.1, rng))
	return group


# 蟲蝕墓道：場外是土色岩塊，場內散落一窩窩蟲卵、貼地的蟲絲與碎骨
static func _build_burrow(half: Vector2, rng: RandomNumberGenerator) -> Node3D:
	var k := PartKit.new()
	var group := Node3D.new()
	var rocks: Array[StandardMaterial3D] = []
	for c in BURROW_ROCK:
		rocks.append(k.mat(c))
	_perimeter_rocks(group, half, rng, rocks, 0.5, 0.5)
	for p in ArenaView.scatter_outside(rng, half, 40, 1.8, 11.0):
		var s: float = (1.0 + rng.randf() * 1.4) * p.s
		k.add(group, PartKit.ico(s, 0), rocks[rng.randi_range(0, 2)], {
			"x": p.x, "y": s * 0.35, "z": p.z, "rx": rng.randf() * 3.0, "ry": p.ry, "sy": 0.6 + rng.randf() * 0.8,
		})
	var egg := k.mat(BURROW_EGG)
	for p in ArenaView.scatter_inside(rng, half, 14):
		for i in 4 + rng.randi_range(0, 3):   # 一窩卵：幾顆拉長的小球擠在一起
			var a := rng.randf() * TAU
			var r := rng.randf() * 0.3
			k.add(group, PartKit.sphere(0.1, 6, 4), egg, {
				"x": p.x + cos(a) * r, "y": 0.1, "z": p.z + sin(a) * r, "sy": 1.4, "shadow": false,
			})
	var silk := k.mat(BURROW_SILK)
	for p in ArenaView.scatter_inside(rng, half, 24):
		k.add(group, PartKit.cyl(0.015, 0.015, 1.2 + rng.randf() * 1.2, 4), silk, {"x": p.x, "y": 0.02, "z": p.z, "rz": PI / 2.0, "ry": p.ry, "shadow": false})
	var bone := k.mat(C.bone_dark)
	for p in ArenaView.scatter_inside(rng, half, 16):
		k.add(group, PartKit.cyl(0.03, 0.03, 0.35, 4), bone, {"x": p.x, "y": 0.03, "z": p.z, "rz": PI / 2.0, "ry": p.ry, "shadow": false})
	k.merge_static(group, [group])
	group.add_child(ArenaView.create_ground((half + Vector2(14.0, 14.0)) * 2.0, BURROW_GROUND, 1.8, 0.1, rng))
	return group
