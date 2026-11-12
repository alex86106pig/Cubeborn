# 畫面層動畫：依模擬層的 player.anim（狀態、階段、進度 k）算出關節角度（PROJECT_GUIDELINES.md 第 11 節）
# 每個渲染幀執行，分四層：移動層（步態、倒地、空中）→ 動作層（普攻、右鍵、道具、翻滾…）→ 戰技層（SkillPoses，蓋過動作層）
# → 收尾（上身從髖部彎、雙腳踩地的 IK，見 BodyPose.plant；弓的箭與弦照最後的姿勢擺）。
# 動作照真實的發力順序：揮砍 = 轉腰 → 肩 → 手肘伸直；刺 = 手肘收到腰側再打直、前腳踏出去；拉弓 = 弓手幾乎打直、拉弦手肘抬到箭的直線後面。
# 參考數字見 docs/動作參考.md
class_name Animator
extends RefCounted

# 招式 → 姿勢；同一個招式依武器模型換姿勢的在 _pose_for
const POSE_OF := {
	&"arrowFan": &"bow",
	&"chargedShot": &"bowCharge",
	&"shadowStep": &"thrust",
	&"holyCircle": &"arcaneBurst",
	&"fireBreath": &"breath",
	&"shovelFling": &"heave",
}
const BOW_MODELS: Array[StringName] = [&"shortbow", &"longbow"]
const UPRIGHT_MODELS: Array[StringName] = [&"staff", &"torch", &"scepter"]   # 右手掌跟著 weapon_tilt 轉、武器保持直立（不隨手臂轉）
# 各武器待機時手肘彎多少 [右, 左]（弧度）：持劍、匕首、權杖是護身的架式（前臂往前），弓手放鬆、鐵鏟扛著
const IDLE_ELBOW := {
	&"longsword": [0.95, 0.5], &"dagger": [1.1, 1.1], &"scepter": [0.8, 0.35], &"staff": [0.55, 0.3], &"torch": [0.7, 0.3],
	&"shortbow": [0.35, 0.3], &"longbow": [0.35, 0.3], &"shovel": [0.6, 0.35],
}

const WALK_SHARPNESS := 12.0
const IDLE_SHARPNESS := 18.0
const DEATH_FALL_TIME := 0.45
const KNOCK_FALL_TIME := 0.25   # 被擊倒往後倒的秒數
const BLINK_RATE := 20.0      # 無敵時間每秒閃爍次數
const GEM_SPIN := 3.0         # 法杖寶石自轉（弧度/秒）
const ROLL_CENTER := 0.56     # 翻滾的旋轉中心（角色高度的比例）：要比頭到中心的距離高，翻到頭下腳上時頭才不會插進地裡
const LIE_FRONT := 0.32       # 趴著時身體離地多高：胸甲的厚度（不然胸口穿進地板）
const LIE_BACK := 0.4         # 仰躺時身體離地多高：背後的披風
const DIG_RATE := 1.5         # 挖墳每秒挖幾下（D6）
const LAND_TIME := 0.18       # 落地緩衝的秒數
const WRIST_SHARPNESS := 25.0 # 手腕轉到目標角度的速度（出招時約 0.1 秒轉回來）
# 各武器待機時手腕往上翹多少（負的 = 往上）：持劍的架式劍尖朝斜上方約 45°（劍順著前臂會是水平往前）
const IDLE_WRIST := {&"longsword": -0.75}
# 待機時繞劍身轉多少：PI/2 = 刃朝上下
const IDLE_ROLL := {&"longsword": PI / 2.0}
# 長劍三連砍：右上斜劈 → 左下反撩 → 舉過頭直劈；每招收尾 = 下一招起手。權杖第 1 下、火把用第 1 招
# keys = [起手, 打中, 收尾] 的 [拳頭位置, 劍身方向]（身體座標）；twist / lean = [起手, 收尾]；stance = [蹲低, 右腳, 左腳]
const SWORD_CUTS := [
	{"keys": [[Vector3(-0.5, 1.95, -0.05), Vector3(-0.35, 0.55, -0.75)], [Vector3(-0.15, 1.35, 0.45), Vector3(0.35, -0.2, 0.9)],
		[Vector3(0.0, 1.05, 0.3), Vector3(0.75, -0.45, 0.3)]],
		"pole": Vector3(-0.6, -0.4, -0.7), "twist": [-0.35, 0.4], "lean": [0.05, 0.15], "stance": [0.06, -0.12, 0.32]},
	{"keys": [[Vector3(0.0, 1.05, 0.3), Vector3(0.7, -0.5, 0.35)], [Vector3(-0.2, 1.3, 0.5), Vector3(-0.1, 0.15, 1.0)],
		[Vector3(-0.5, 1.75, 0.3), Vector3(-0.6, 0.65, 0.35)]],
		"pole": Vector3(-0.6, -0.5, -0.6), "twist": [0.4, -0.35], "lean": [0.15, 0.05], "stance": [0.06, -0.12, 0.32]},
	{"keys": [[Vector3(-0.25, 2.05, -0.05), Vector3(0.0, 0.45, -0.9)], [Vector3(-0.15, 1.4, 0.5), Vector3(0.05, 0.0, 1.0)],
		[Vector3(-0.18, 1.22, 0.4), Vector3(0.05, -0.3, 0.95)]],
		"pole": Vector3(-0.9, -0.1, -0.3), "twist": [-0.15, 0.1], "lean": [-0.1, 0.3], "stance": [0.2, -0.3, 0.55]},
]
const SWORD_LEN := 1.0          # 算劍尖軌跡用的劍長
# 匕首在手掌上：刀尖 -Y、刃寬 Z（DarkFantasy._dagger）；刀尖方向用角色座標（腰怎麼轉都一樣），x 是往身體中線
const DAGGER_FRAME := Basis(Vector3.BACK, Vector3.DOWN, Vector3.RIGHT)
const DAGGER_IDLE := Vector3(0.15, 0.6, 0.8)
const DAGGER_CHAMBER := Vector3(0.05, 0.1, 1.0)   # 收在腰側：刀尖朝前
const DAGGER_STAB := Vector3(0.1, -0.05, 1.0)     # 刺到底：刀尖朝正前方
const CUT_EDGE_STICKY := 0.5    # 刃換面的遲滯，避免揮到一半翻面
const LAND_DROP := 0.16       # 落地時髖部往下沉多少（× 腿長；膝蓋約彎 45°，真人落地膝蓋彎曲至少 45°）
const BOW_REST := Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)   # 不拉弓時弓平放（相對角色）：弓梢朝前後、弓背朝下、弦在上

var rig: Rig
var walk_phase := 0.0
var walk_amount := 0.0
var weapon_tilt := 0.0
var bow_rest := 1.0   # 弓平放的比例：1 = 平放（BOW_REST）、0 = 直立
var bow_raise := 0.0  # 開始拉弓時弓手舉起的進度（0 = 還在出手前的姿勢、1 = 舉到位）；連射時一直是 1
var bow_hand_from := Vector3.ZERO   # 開始拉弓那一刻弓手拳頭的位置（身體座標），舉弓從這裡平滑移過去

# 這一幀的站姿（動作層、戰技層填，收尾時踩地）：weight = 0 → 照步態；> 0 → 往 stance 的腳位與高度靠
var stance := {"weight": 0.0, "drop": 0.0, "r": 0.0, "l": 0.0, "shift": 0.0}
var free_legs := false   # 倒地、翻滾、空中：腿照姿勢給的角度，不踩地
var wrist := 0.0         # 右手腕轉多少（不是直立武器時轉手掌掛點；負的往上翹）：每幀往 wrist_target 平滑轉過去
var wrist_target := 0.0  # 這一幀要的手腕角度：待機持劍往上翹（劍尖朝斜上方）、翻滾往後轉（劍貼著身體），其他 0
var roll := 0.0          # 繞劍身轉多少，往 roll_target 平滑轉
var roll_target := 0.0
var _cut_hand: Variant = null   # 連砍這一幀的右手掌方向；null = 照 wrist / roll
var _cut_from := {}             # 連砍起手前的右手姿勢
var _cut_phase: StringName = &""
var _cut_edge := 1.0            # 刃朝哪一面（±1）
var _last_arm := {}             # 上一幀的右手姿勢
var _hand_carry := 0.0          # 連砍結束後手掌還留在連砍方向的比例
var _hand_last := Basis.IDENTITY
var _blade_aim: Array = [null, null]   # 這一幀右手、左手的刀尖方向（角色座標，x 照右手；null = 照預設握法）
var _blade_q: Array = [Quaternion.IDENTITY, Quaternion.IDENTITY]
var _gait: Dictionary = {}
var _was_airborne := false
var _land_t := 1.0
var _arrow := &"none"    # 弓：none / hand（從箭袋抽出、拿在手上）/ bow（搭在弦上）；收尾時照這個擺箭
var _bring := 0.0        # 弓：手從箭袋帶到弓前的進度
var _drawing := false    # 這一幀在拉弓（普攻、右鍵、弓的戰技）：弓直立、顯示搭弦的箭


func _init(p_rig: Rig) -> void:
	rig = p_rig


func update(p: Player, dt: float) -> void:
	rig.set_weapon(p.weapon.model, p.weapon.get("offhand_model", &""))
	var a := p.anim
	BodyPose.straighten(rig)
	rig.head.rotation = Vector3.ZERO
	wrist_target = 0.0
	roll_target = 0.0
	_cut_hand = null
	_blade_aim = [null, null]
	stance.weight = 0.0
	free_legs = false
	_arrow = &"none"
	_drawing = false
	_bring = 0.0
	rig.body.position = Vector3.ZERO
	_pose_locomotion(p, a, dt)
	var is_down: bool = a.loco == &"dead" or a.loco == &"downed"   # 倒地假死（C4）和死亡同一個躺地姿勢
	if a.get("knocked", 0.0) > 0.0 and not is_down:
		_pose_knocked(a.knocked, dt)
		is_down = true
	if a.airborne and not is_down:
		_pose_airborne(a)
	elif _was_airborne:
		_land_t = 0.0
	_was_airborne = a.airborne and not is_down
	_land_t += dt
	if not is_down:
		_pose_action(p, a, dt)
		if a.parry > 0.0:
			_pose_parry(1.0 - a.parry)
		if a.get("skill", &"") != &"" and a.action != &"roll":
			SkillPoses.apply(self, p, a, dt)
	_finish(a)
	# 轉手掌掛點而不是武器：拳頭和武器一起轉，握的位置不會滑出拳頭
	var upright := rig.weapon_model in UPRIGHT_MODELS and rig.weapon_main != null
	var fore := rig.forearm_r.rotation.x
	wrist = MathUtil.damp(wrist, wrist_target, WRIST_SHARPNESS, dt)
	roll = MathUtil.damp(roll, roll_target, WRIST_SHARPNESS, dt)
	if _cut_hand != null:
		rig.hand_r.basis = _cut_hand
		_hand_last = _cut_hand
		_hand_carry = 1.0
	elif upright:
		rig.hand_r.rotation = Vector3(weapon_tilt - rig.arm_r.rotation.x - fore, 0.0, 0.0)
		_hand_carry = 0.0
	else:
		var grip := DarkFantasy.sword_grip(wrist, roll)
		_hand_carry = MathUtil.damp(_hand_carry, 0.0, WRIST_SHARPNESS, dt) if _hand_carry > 0.001 else 0.0
		rig.hand_r.basis = Basis(grip.get_rotation_quaternion().slerp(_hand_last.get_rotation_quaternion(), _hand_carry)) if _hand_carry > 0.0 else grip
	if _cut_hand == null:
		_cut_phase = &""
	_last_arm = _arm_state()
	var drawing := _drawing
	if rig.weapon_nock != null and not drawing:
		rig.weapon_nock.visible = false
		_bow_string(null)
	var shown: int = p.quiver if p.weapon.attack.has("quiver") else rig.weapon_quiver_arrows.size()
	for i in rig.weapon_quiver_arrows.size():   # 短弓箭袋：剩幾發就露出幾支；長弓沒有箭數機制，一直是滿的
		(rig.weapon_quiver_arrows[i] as Node3D).visible = i < shown
	if rig.weapon_model in BOW_MODELS and rig.weapon_left != null:
		# 拉弓時弓直立、弓背朝前（相對角色 = 單位矩陣），其他時候平放；兩者之間平滑轉換。
		# 轉左手掌掛點（拳頭跟著弓），抵銷身體、上臂、前臂的轉向
		if drawing:
			bow_rest = 1.0 - bow_raise
		else:
			bow_raise = 0.0
			bow_rest = MathUtil.damp(bow_rest, 1.0, IDLE_SHARPNESS, dt)
		var target := Basis(Quaternion.IDENTITY.slerp(BOW_REST.get_rotation_quaternion(), bow_rest))
		rig.hand_l.basis = (rig.body.basis * rig.arm_l.basis * rig.forearm_l.basis).orthonormalized().inverse() * target
		_bow_visuals()
	else:
		rig.hand_l.rotation = Vector3.ZERO
		bow_raise = 0.0
	if rig.weapon_model == &"dagger":
		_aim_blades(a.action in [&"attack", &"special"], dt)
	if rig.weapon_gem != null:
		rig.weapon_gem.rotation.y += GEM_SPIN * dt

	var flash_time: float = Config.COMBAT.flash_time
	rig.set_flash(0.9 * p.flash_timer / flash_time if p.flash_timer > 0.0 else 0.0)
	rig.visible = p.is_dead or p.invuln_timer <= 0.0 or int(floor(p.invuln_timer * BLINK_RATE)) % 2 == 0


# 動作層、戰技層要求的站姿：drop = 髖部往下（× 腿長）、r / l = 右 / 左腳往前（× 腿長，負的往後）、shift = 髖部往前（× 腿長）
func set_stance(drop: float, r: float, l: float, weight := 1.0, shift := 0.0) -> void:
	stance.weight = clampf(weight, 0.0, 1.0)
	stance.drop = drop
	stance.r = r
	stance.l = l
	stance.shift = shift


# 收尾：踩地（或照空中 / 倒地的腿），落地緩衝
func _finish(a: Dictionary) -> void:
	if free_legs:
		return
	var leg := BodyPose.leg_length(rig)
	var s: float = rig.body.scale.x
	var g := _gait
	var fr: Vector3 = g.r
	var fl: Vector3 = g.l
	var drop: float = g.drop
	var shift := 0.0
	rig.body.rotation.x += g.lean
	var w: float = stance.weight * (1.0 - 0.6 * walk_amount)   # 邊走邊出手時腳步照走，只借一部分站姿
	if w > 0.0:
		fr = fr.lerp(Vector3(rig.leg_r.position.x * s, 0.0, stance.r * leg), w)
		fl = fl.lerp(Vector3(rig.leg_l.position.x * s, 0.0, stance.l * leg), w)
		drop = lerpf(drop, stance.drop * leg, w)
		shift = stance.shift * leg * w
	if _land_t < LAND_TIME and not a.airborne:
		drop += LAND_DROP * leg * sin(PI * _land_t / LAND_TIME)
	BodyPose.plant(rig, fr, fl, drop, shift)


static func _ease(k: float) -> float:
	return MathUtil.ease_out_cubic(clampf(k, 0.0, 1.0))


# ───────── 移動層 ─────────

func _pose_locomotion(p: Player, a: Dictionary, dt: float) -> void:
	var speed := p.velocity.length()
	var moving: bool = a.loco == &"move"
	walk_amount = MathUtil.damp(walk_amount, 1.0 if moving else 0.0, WALK_SHARPNESS, dt)
	if moving:
		walk_phase = BodyPose.advance(walk_phase, speed, BodyPose.leg_length(rig), dt)
	_gait = BodyPose.gait(rig, walk_phase, walk_amount, maxf(speed, 1.0))
	rig.body.rotation = Vector3.ZERO
	match a.loco:
		&"dead", &"downed":
			walk_amount = 0.0
			free_legs = true
			var k := _ease(a.loco_time / DEATH_FALL_TIME)
			rig.body.rotation.x = lerpf(0.0, PI / 2.0, k)   # 往前撲倒、臉朝下
			rig.body.position.y = LIE_FRONT * k
			BodyPose.arm(rig, true, lerpf(0.0, -2.6, k), 0.25 * k, 0.4 * k)
			BodyPose.arm(rig, false, lerpf(0.0, -2.6, k), -0.25 * k, 0.4 * k)
			BodyPose.leg(rig, true, -0.15 * k, 0.35 * k)
			BodyPose.leg(rig, false, 0.1 * k, 0.15 * k)


# 被擊倒：往後倒成仰躺，膝蓋屈起、雙手往兩側攤在地上（起身交給移動層回正）
func _pose_knocked(t: float, _dt: float) -> void:
	free_legs = true
	var k := _ease(t / KNOCK_FALL_TIME)
	rig.body.rotation = Vector3(lerpf(0.0, -PI / 2.0, k), 0.0, 0.0)
	rig.body.position.y = LIE_BACK * k
	rig.arm_r.rotation = Vector3(-0.3 * k, 0.0, -1.2 * k)   # 往外張開（rotation.z）：仰躺時手臂平貼地面
	rig.arm_l.rotation = Vector3(-0.3 * k, 0.0, 1.2 * k)
	rig.forearm_r.rotation.x = -0.5 * k
	rig.forearm_l.rotation.x = -0.5 * k
	BodyPose.leg(rig, true, -0.9 * k, 1.4 * k)
	BodyPose.leg(rig, false, -0.3 * k, 0.5 * k)


# 空中：上升時雙腿收起（前腳髖屈膝屈、後腳膝蓋往後彎），下墜時慢慢伸直準備落地（翻滾時由翻滾姿勢覆蓋）
func _pose_airborne(a: Dictionary) -> void:
	free_legs = true
	var v0 := 4.0 * Config.JUMP.height / Config.JUMP.air_time
	var tuck := clampf(0.5 + 0.5 * a.vz / v0, 0.0, 1.0)
	BodyPose.leg(rig, true, lerpf(-0.45, -1.15, tuck), lerpf(0.35, 1.5, tuck))
	BodyPose.leg(rig, false, lerpf(0.05, 0.25, tuck), lerpf(0.3, 1.2, tuck))
	rig.body.position.y = 0.0


# ───────── 動作層 ─────────

func _pose_action(p: Player, a: Dictionary, dt: float) -> void:
	var idle: Dictionary = p.weapon.idle
	match a.action:
		&"ready":
			_pose_idle_upper_body(idle, dt)
		&"attack", &"special":
			var e := _ease(a.k)
			match _pose_for(a.behavior):
				&"swordCut":
					_pose_cut(idle, a, e, SWORD_CUTS[2 if a.get("is_finisher", false) else (1 if a.get("swing_dir", 1) < 0 else 0)])
				&"cut":
					_pose_cut(idle, a, e, SWORD_CUTS[0])
				&"shieldBash":
					_pose_shield_block(a, e, dt)
				&"arcaneBurst":
					_pose_arcane_burst(idle, a, e)
				&"thrust":
					_pose_thrust(idle, a, e)
				&"scoop":
					_pose_scoop(idle, a, e)
				&"fling":
					_pose_overhead(idle, a, e, -1.0, 0.1)
				&"breath":
					_pose_breath(idle, a, e)
				&"heave":
					_pose_heave(idle, a, e)
				&"mace":
					_pose_mace(idle, a, e, dt)
				&"bow":
					pose_bow(a, e, false)
				&"bowCharge":
					pose_bow(a, e, true)
				_:
					_pose_fire_bolt(idle, a, e)
		&"useItem":
			# 喝藥水：左手把瓶子舉到嘴邊（手肘彎、上臂往前），頭往後仰
			_pose_idle_upper_body(idle, dt)
			var k := sin(clampf(a.action_time / Config.PLAYER.use_item_time, 0.0, 1.0) * PI)
			var mouth := rig.head.position + Vector3(0.08, 0.15, 0.25)
			BodyPose.arm_ik(rig, false, BodyPose.hand_pos(rig, false).lerp(mouth, k), Vector3(0.6, -0.3, 0.2))
			rig.head.rotation.x = -0.3 * k
		&"stagger":
			# 受擊硬直：上身往後仰、退半步、膝蓋一沉
			_pose_idle_upper_body(idle, dt)
			var k := sin(clampf(a.action_time / Config.PLAYER.stagger_time, 0.0, 1.0) * PI)
			rig.body.rotation.x = -0.3 * k
			BodyPose.arm(rig, true, rig.arm_r.rotation.x + 0.4 * k, 0.0, 0.5 + 0.3 * k)
			BodyPose.arm(rig, false, rig.arm_l.rotation.x + 0.5 * k, 0.0, 0.5 + 0.3 * k)
			set_stance(0.08, 0.1, -0.3, k)
		&"roll":
			_pose_roll(clampf(a.action_time / Config.ROLL.duration, 0.0, 1.0))
		&"dig":
			# 挖墳（D6）：深蹲（彎膝蓋、背打直前傾），雙手握在身前一下一下往下挖（每秒約 1.5 下）
			var swing := 0.5 + 0.5 * sin(a.action_time * TAU * DIG_RATE)
			rig.body.rotation.x = lerpf(0.3, 0.5, swing)
			var low := Vector3(-0.1, lerpf(0.55, 0.2, swing), lerpf(0.55, 0.65, swing))
			BodyPose.arm_ik(rig, true, low + Vector3(0.0, 0.25, -0.05), BodyPose.elbow_pole(true))
			BodyPose.arm_ik(rig, false, low, BodyPose.elbow_pole(false))
			set_stance(lerpf(0.22, 0.3, swing), 0.25, -0.2)
	if a.get("is_finisher", false) and a.action in [&"attack", &"special"] and a.phase == &"active":
		stance.drop += 0.03   # 終結技壓得更低


# 招式的姿勢：普攻依武器模型分（長劍三連砍、匕首刺、鐵鏟鏟、權杖敲砸、火把斜揮、弓拉弓），其餘查 POSE_OF
func _pose_for(behavior: StringName) -> StringName:
	match behavior:
		&"meleeSwing":
			match rig.weapon_model:
				&"dagger":
					return &"thrust"
				&"shovel":
					return &"scoop"
				&"scepter":
					return &"mace"
				&"longsword":
					return &"swordCut"
			return &"cut"
		&"fireBolt":
			return &"bow" if rig.weapon_model in BOW_MODELS else &"fireBolt"
		&"shieldBash", &"arcaneBurst":
			return behavior
	return POSE_OF.get(behavior, &"fireBolt")


func idle_elbow(right: bool) -> float:
	var e: Array = IDLE_ELBOW.get(rig.weapon_model, [0.4, 0.3])
	return e[0] if right else e[1]


# 上半身平滑回到武器待機姿勢（手肘照 IDLE_ELBOW 彎）；手臂隨步態擺動
func _pose_idle_upper_body(idle: Dictionary, dt: float) -> void:
	var s := IDLE_SHARPNESS
	var run: float = _gait.run * walk_amount
	var sw := cos(TAU * _gait.u) * lerpf(BodyPose.ARM_SWING_WALK, BodyPose.ARM_SWING_RUN, run) * walk_amount
	var elbow_add := lerpf(0.0, BodyPose.ELBOW_RUN * 0.6, run)
	rig.arm_r.rotation.x = MathUtil.damp(rig.arm_r.rotation.x, idle.arm_r + sw * 0.5, s, dt)
	rig.arm_r.rotation.y = MathUtil.damp(rig.arm_r.rotation.y, 0.0, s, dt)
	rig.arm_l.rotation.x = MathUtil.damp(rig.arm_l.rotation.x, idle.arm_l - sw, s, dt)
	rig.arm_l.rotation.y = MathUtil.damp(rig.arm_l.rotation.y, 0.0, s, dt)
	rig.arm_r.rotation.z = 0.0
	rig.arm_l.rotation.z = 0.0
	rig.forearm_r.rotation.x = -(idle_elbow(true) + elbow_add * 0.5)
	rig.forearm_l.rotation.x = -(idle_elbow(false) + elbow_add + maxf(0.0, sw) * 0.4)
	rig.body.rotation.y = 0.0
	weapon_tilt = MathUtil.damp(weapon_tilt, idle.tilt, s, dt)
	_blade_aim = [DAGGER_IDLE, DAGGER_IDLE]
	wrist_target = IDLE_WRIST.get(rig.weapon_model, 0.0)
	roll_target = IDLE_ROLL.get(rig.weapon_model, 0.0)


# 揮砍（SWORD_CUTS 的一招）：出手用 IK 走關鍵格，起手與收招用關節角度內插（不重解 IK，不會跳）
func _pose_cut(idle: Dictionary, a: Dictionary, e: float, cut: Dictionary) -> void:
	var k := clampf(a.k, 0.0, 1.0)
	var fresh: bool = a.phase == &"windup" and _cut_phase != &"windup"
	_cut_phase = a.phase
	wrist = IDLE_WRIST.get(rig.weapon_model, 0.0)   # 收招後直接接待機，不再轉一次
	roll = IDLE_ROLL.get(rig.weapon_model, 0.0)
	weapon_tilt = idle.tilt
	var tw: Array = cut.twist
	var ln: Array = cut.lean
	var st: Array = cut.stance
	match a.phase:
		&"windup":
			if fresh or _cut_from.is_empty():
				_cut_from = _last_arm if not _last_arm.is_empty() else _idle_arm(idle)
				_cut_edge = 1.0
				_cut_edge = _cut_pick_edge(cut, 0.0, 0.0)
			_apply_arm(_blend_arm(_cut_from, _cut_solve(cut, 0.0), e))
			rig.body.rotation.y = lerpf(0.0, tw[0], e)
			rig.body.rotation.x = lerpf(0.0, ln[0], e)
			set_stance(st[0] * 0.5 * e, st[1] * 0.5, st[2] * 0.5, e)
		&"active":
			var u := smoothstep(0.0, 1.0, k)
			_apply_arm(_cut_solve(cut, u))
			rig.body.rotation.y = lerpf(tw[0], tw[1], smoothstep(0.0, 0.7, k))   # 腰先轉
			rig.body.rotation.x = lerpf(ln[0], ln[1], u)
			set_stance(st[0] * lerpf(0.5, 1.0, u), lerpf(st[1] * 0.5, st[1], u), lerpf(st[2] * 0.5, st[2], u))
		_:
			var back := smoothstep(0.25, 1.0, k)   # 先停一下再回待機
			var end := _cut_solve(cut, 1.0)
			_apply_arm(_blend_arm(end, _idle_arm(idle), back))
			rig.body.rotation.y = lerpf(tw[1], 0.0, back)
			rig.body.rotation.x = lerpf(ln[1], 0.0, back)
			set_stance(st[0], st[1], st[2], 1.0 - back)
	BodyPose.arm(rig, false, -0.65, 0.3, 1.4)   # 左手（盾）收在胸前


# 拳頭位置：通過三格的二次曲線
static func _cut_pos(keys: Array, u: float) -> Vector3:
	var p0: Vector3 = keys[0][0]
	var p2: Vector3 = keys[2][0]
	var c: Vector3 = 2.0 * (keys[1][0] as Vector3) - (p0 + p2) / 2.0
	return p0 * (1.0 - u) * (1.0 - u) + c * 2.0 * u * (1.0 - u) + p2 * u * u


# 劍身方向：依序轉過三格
static func _cut_dir(keys: Array, u: float) -> Vector3:
	var d0: Vector3 = (keys[0][1] as Vector3).normalized()
	var d1: Vector3 = (keys[1][1] as Vector3).normalized()
	var d2: Vector3 = (keys[2][1] as Vector3).normalized()
	return d0.slerp(d1, u * 2.0) if u < 0.5 else d1.slerp(d2, u * 2.0 - 1.0)


# 刃朝劍尖移動的方向
static func _cut_edge_dir(keys: Array, u: float) -> Vector3:
	var u0 := clampf(u - 0.03, 0.0, 0.94)
	var u1 := u0 + 0.06
	var dir := _cut_dir(keys, u)
	var w := (_cut_pos(keys, u1) + _cut_dir(keys, u1) * SWORD_LEN) - (_cut_pos(keys, u0) + _cut_dir(keys, u0) * SWORD_LEN)
	w -= dir * w.dot(dir)
	if w.length_squared() < 1e-8:
		w = Vector3.UP - dir * dir.y
	return w.normalized()


# 武器朝 dir、刃朝 w 時的手掌方向（身體座標）；長劍在手掌上斜 SWORD_TILT，其他武器沿手掌 +Y
func _cut_hand_basis(dir: Vector3, w: Vector3) -> Basis:
	var tilt := DarkFantasy.SWORD_TILT if rig.weapon_model == &"longsword" else 0.0
	return Basis(w, dir, w.cross(dir)) * Basis(Vector3.RIGHT, tilt).inverse()


# 刃朝哪一面：選手腕扭得少的那面
func _cut_pick_edge(cut: Dictionary, u: float, sticky: float) -> float:
	BodyPose.arm_ik(rig, true, _cut_pos(cut.keys, u), cut.pole)
	var f := BodyPose.forearm_basis(rig, true).inverse()
	var dir := _cut_dir(cut.keys, u)
	var w := _cut_edge_dir(cut.keys, u)
	var best := _cut_edge
	var score := -INF
	for sgn: float in [1.0, -1.0]:
		var l := f * _cut_hand_basis(dir, w * sgn)
		var sc := l.x.x + l.y.y + l.z.z + (sticky if sgn == _cut_edge else 0.0)
		if sc > score:
			score = sc
			best = sgn
	return best


# 連砍第 u 點的右手姿勢
func _cut_solve(cut: Dictionary, u: float) -> Dictionary:
	_cut_edge = _cut_pick_edge(cut, u, CUT_EDGE_STICKY)
	var hand := _cut_hand_basis(_cut_dir(cut.keys, u), _cut_edge_dir(cut.keys, u) * _cut_edge)
	return {"arm": Quaternion(rig.arm_r.basis.orthonormalized()), "elbow": rig.forearm_r.rotation.x, "hand": hand}


# 待機的右手姿勢（不含走路擺手）
func _idle_arm(idle: Dictionary) -> Dictionary:
	BodyPose.arm(rig, true, idle.arm_r, 0.0, idle_elbow(true))
	var grip := DarkFantasy.sword_grip(IDLE_WRIST.get(rig.weapon_model, 0.0), IDLE_ROLL.get(rig.weapon_model, 0.0))
	var hand := Basis(Vector3.RIGHT, idle.tilt) if rig.weapon_model in UPRIGHT_MODELS else BodyPose.forearm_basis(rig, true) * grip
	return {"arm": Quaternion(rig.arm_r.basis.orthonormalized()), "elbow": rig.forearm_r.rotation.x, "hand": hand}


# 現在的右手姿勢
func _arm_state() -> Dictionary:
	return {"arm": Quaternion(rig.arm_r.basis.orthonormalized()), "elbow": rig.forearm_r.rotation.x,
		"hand": (BodyPose.forearm_basis(rig, true) * rig.hand_r.basis).orthonormalized()}


static func _blend_arm(from: Dictionary, to: Dictionary, t: float) -> Dictionary:
	return {"arm": (from.arm as Quaternion).slerp(to.arm, t), "elbow": lerpf(from.elbow, to.elbow, t),
		"hand": Basis((from.hand as Basis).get_rotation_quaternion().slerp((to.hand as Basis).get_rotation_quaternion(), t))}


# 擺上右手姿勢；手掌方向在 update 收尾時套上
func _apply_arm(s: Dictionary) -> void:
	rig.arm_r.basis = Basis(s.arm as Quaternion)
	rig.forearm_r.rotation = Vector3(s.elbow, 0.0, 0.0)
	_cut_hand = (BodyPose.forearm_basis(rig, true).inverse() * (s.hand as Basis)).orthonormalized()


# 刺（雙匕首、影步）：前搖手肘往後收到腰側（拳頭貼著肋骨）→ 出手肩膀往前、手肘打直、同側的腳往前踏（弓步）→ 收回；
# 左右手輪流（swing_dir），終結技雙手一起刺、身體前傾、踏得更深
func _pose_thrust(idle: Dictionary, a: Dictionary, e: float) -> void:
	var fin: bool = a.get("is_finisher", false)
	var has_left := rig.weapon_left != null
	var right: bool = fin or a.get("swing_dir", 1) >= 0 or not has_left
	var left: bool = has_left and (fin or a.get("swing_dir", 1) < 0)
	var x := 0.0
	var elbow := 0.0
	var reach := 0.0   # 0 = 收在腰側、1 = 刺到底
	match a.phase:
		&"windup":
			x = lerpf(idle.arm_r, 0.45, e)
			elbow = lerpf(idle_elbow(true), 1.9, e)
		&"active":
			x = lerpf(0.45, -1.55, e)
			elbow = lerpf(1.9, 0.05, e)
			reach = e
		_:
			x = lerpf(-1.55, idle.arm_r, e)
			elbow = lerpf(0.05, idle_elbow(true), e)
			reach = 1.0 - e
	var inward := 0.15 if fin else 0.08
	if right:
		BodyPose.arm(rig, true, x, inward, elbow)
	if left:
		BodyPose.arm(rig, false, x, -inward, elbow)
	if not (right and left):   # 另一隻手收回護在胸前
		BodyPose.arm(rig, not right, -0.6 + 0.3 * reach, 0.25 * (-1.0 if right else 1.0), 1.6)
	var aim: Vector3 = {&"windup": DAGGER_IDLE.lerp(DAGGER_CHAMBER, e), &"active": DAGGER_CHAMBER.lerp(DAGGER_STAB, e)}.get(a.phase, DAGGER_STAB.lerp(DAGGER_IDLE, e))
	_blade_aim = [aim if right else DAGGER_IDLE, aim if left else DAGGER_IDLE]
	var twist := 0.0 if fin else (0.35 if right else -0.35)   # 出手那一側的肩膀往前
	rig.body.rotation.y = twist * reach
	rig.body.rotation.x = (0.3 if fin else 0.12) * reach
	var step := (0.55 if fin else 0.4) * reach
	if fin:
		set_stance(0.18 * reach, step, -0.45 * reach)
	elif right:
		set_stance(0.12 * reach, step, -0.35 * reach)
	else:
		set_stance(0.12 * reach, -0.35 * reach, step)


# 匕首：手掌轉到刀尖朝 _blade_aim、刃朝上下（虎口朝上）；出招時直接轉到，其他時候在角色座標裡平滑轉（前臂動刀尖不會跟著甩）
func _aim_blades(snap: bool, dt: float) -> void:
	var body := Basis.from_euler(rig.body.rotation, EULER_ORDER_YXZ)
	for i in 2:
		var right := i == 0
		var hand: Node3D = rig.hand_r if right else rig.hand_l
		var fore := body * BodyPose.forearm_basis(rig, right)
		var want := fore * hand.basis
		if _blade_aim[i] != null:
			var aim: Vector3 = _blade_aim[i]
			var d := Vector3(aim.x * (1.0 if right else -1.0), aim.y, aim.z).normalized()
			var w := (Vector3.UP - d * d.y).normalized()
			want = Basis(w, d, w.cross(d)) * DAGGER_FRAME.inverse()
		var q := want.get_rotation_quaternion()
		if not snap:
			q = (_blade_q[i] as Quaternion).slerp(q, 1.0 - exp(-WRIST_SHARPNESS * dt))
		_blade_q[i] = q
		hand.basis = fore.inverse() * Basis(q)


# 鏟（鐵鏟鏟地、鏟起）：右手握柄尾、左手握在柄中段（IK 跟著鏟柄）；前搖蹲低、鏟面貼著身前的地 →
# 出手腿蹬直、鏟面沿地往前再往上鏟出去（彎膝蓋不彎腰，往鏟的方向踏一步）
func _pose_scoop(idle: Dictionary, a: Dictionary, e: float) -> void:
	var x := 0.0
	var elbow := 0.0
	var bend := 0.0
	var drop := 0.0
	match a.phase:
		&"windup":   # 鏟柄沿著手臂往前下方。手臂的角度是相對身體：上身前彎 0.3 時手臂要多往前 0.3（實際往前 0.7），蹲低 0.2 時鏟面剛好在身前的地上
			x = lerpf(idle.arm_r, -1.0, e)
			elbow = lerpf(idle_elbow(true), 0.1, e)
			bend = lerpf(0.0, 0.3, e)
			drop = lerpf(0.0, 0.2, e)
		&"active":
			x = lerpf(-1.0, -1.3, e)
			elbow = lerpf(0.1, 0.35, e)
			bend = lerpf(0.3, 0.05, e)
			drop = lerpf(0.2, 0.03, e)
		_:
			x = lerpf(-1.3, idle.arm_r, e)
			elbow = lerpf(0.35, idle_elbow(true), e)
			bend = lerpf(0.05, 0.0, e)
			drop = lerpf(0.03, 0.0, e)
	BodyPose.arm(rig, true, x, 0.1, elbow)
	rig.body.rotation.x = bend
	grip_shaft(0.45)
	set_stance(drop, -0.1, 0.4)


# 噴火（火把右鍵）：火把收到右腰、腰往右扭 → 往前推到胸口高度、火把頭朝前、左腳踏出 → 停一下再收回
# 姿勢 = 待機 + 收腰的量 × (收腰 - 待機) + 推出的量 × (推出 - 待機)
func _pose_breath(idle: Dictionary, a: Dictionary, e: float) -> void:
	var pull := 0.0
	var push := 0.0
	match a.phase:
		&"windup":
			pull = e
		&"active":
			pull = 1.0 - e
			push = e
		_:
			push = 1.0 - smoothstep(0.4, 1.0, clampf(a.k, 0.0, 1.0))
	var ax: float = idle.arm_r
	var el := idle_elbow(true)
	BodyPose.arm(rig, true, ax + (0.1 - ax) * pull + (-1.45 - ax) * push, 0.2 * pull + 0.05 * push, el + (1.7 - el) * pull + (0.15 - el) * push)
	BodyPose.arm(rig, false, -0.1 - 0.9 * pull - 0.4 * push, -0.2 * pull + 0.25 * push, 0.3 + 0.6 * pull + 1.1 * push)
	weapon_tilt = idle.tilt + (0.4 - idle.tilt) * pull + (1.4 - idle.tilt) * push
	rig.body.rotation.y = -0.3 * pull   # 推出時腰轉正：火把是直立武器、跟著身體朝向，腰一轉火就噴歪
	rig.body.rotation.x = 0.15 * push
	set_stance(0.06 * pull + 0.1 * push, -0.2, 0.45, maxf(pull, push))


# 鏟拋（鐵鏟右鍵）：蹲低、鏟面插到怪的腳下 → 膝蓋蹬直、雙手把鏟子往前上方掀過頭、上身微後仰 → 收回
func _pose_heave(idle: Dictionary, a: Dictionary, e: float) -> void:
	var k := clampf(a.k, 0.0, 1.0)
	var x := 0.0
	var elbow := 0.0
	var bend := 0.0
	var drop := 0.0
	match a.phase:
		&"windup":
			x = lerpf(idle.arm_r, -1.1, e)
			elbow = lerpf(idle_elbow(true), 0.3, e)
			bend = 0.45 * e
			drop = 0.3 * e
		&"active":
			x = lerpf(-1.1, -1.8, e)
			elbow = lerpf(0.3, 0.4, e)
			bend = lerpf(0.45, 0.2, e)
			drop = lerpf(0.3, 0.15, e)
		_:
			if k < 0.45:
				var u := MathUtil.ease_out_cubic(k / 0.45)
				x = lerpf(-1.8, -2.5, u)
				elbow = lerpf(0.4, 0.5, u)
				bend = lerpf(0.2, -0.12, u)
				drop = lerpf(0.15, 0.02, u)
			else:
				var u := MathUtil.ease_out_cubic((k - 0.45) / 0.55)
				x = lerpf(-2.5, idle.arm_r, u)
				elbow = lerpf(0.5, idle_elbow(true), u)
				bend = lerpf(-0.12, 0.0, u)
				drop = lerpf(0.02, 0.0, u)
	BodyPose.arm(rig, true, x, 0.1, elbow)
	rig.body.rotation.x = bend
	grip_shaft(0.45)
	set_stance(drop, -0.2, 0.4)


# 左手握在鏟柄 / 長柄上離右手 along 遠的地方（沿右前臂的方向往外，鏟柄沿右手的 -Y），手肘往外下
func grip_shaft(along: float) -> void:
	var hand := BodyPose.hand_pos(rig, true)
	var dir := BodyPose.forearm_basis(rig, true) * Vector3.DOWN
	BodyPose.arm_ik(rig, false, hand + dir * along, Vector3(0.6, -0.6, -0.3))


# 舉過頭再往前甩（拋出）/ 往下砸：雙手、上臂舉高時手肘彎（前臂在頭後蓄力），出手手肘打直、踏前腳；
# to = active 結束時手臂的角度、lean = 身體前傾
func _pose_overhead(idle: Dictionary, a: Dictionary, e: float, to: float, lean: float) -> void:
	var x := 0.0
	var elbow := 0.0
	var body := 0.0
	var reach := 0.0
	match a.phase:
		&"windup":
			x = lerpf(-1.1, -2.7, e)
			elbow = lerpf(0.5, 1.3, e)
			body = lerpf(0.0, -0.18, e)
		&"active":
			x = lerpf(-2.7, to, e)
			elbow = lerpf(1.3, 0.1, e)
			body = lerpf(-0.18, lean, e)
			reach = e
		_:
			x = lerpf(to, idle.arm_r, e)
			elbow = lerpf(0.1, idle_elbow(true), e)
			body = lerpf(lean, 0.0, e)
			reach = 1.0 - e
	BodyPose.arm(rig, true, x, 0.15, elbow)
	BodyPose.arm(rig, false, x, -0.15, elbow)
	rig.body.rotation.x = body
	set_stance(0.04 + 0.12 * reach, -0.3 * reach, 0.4 * reach)


# 權杖：第 1 下右上往左下斜揮（同長劍第 1 招），第 2 下（終結技）舉過頭往下砸、蹲低
func _pose_mace(idle: Dictionary, a: Dictionary, e: float, _dt: float) -> void:
	if a.get("is_finisher", false):
		_pose_overhead(idle, a, e, -0.6, 0.35)
		match a.phase:
			&"windup":
				weapon_tilt = lerpf(0.0, -0.4, e)
			&"active":
				weapon_tilt = lerpf(-0.4, 1.7, e)
				stance.drop += 0.08 * e
			_:
				weapon_tilt = lerpf(1.7, idle.tilt, e)
		return
	_pose_cut(idle, a, e, SWORD_CUTS[0])


# ───────── 拉弓 ─────────
# 一發的循環 = 收招時右手往上繞到背後箭袋抽箭（箭頭朝前帶出來）→ 前搖前段經過肩膀上方帶到弓前搭弦 → 前搖後段拉到下巴（拉弦手肘抬到
# 箭的直線後面、和肩膀同高，靠背部出力）→ active 放箭、拉弦手順著往後彈；蓄力（charge）時 active 一直拉滿。
# 弓手往前推、手肘微彎不鎖死；身體側轉讓左肩對著目標。全部用身體座標算（不用 global），收尾踩地後位置不會錯開
const BRING_PART := 0.45                 # 前搖的前段（帶到弓前）佔多少
const BOW_TWIST := 1.22                  # 拉滿時身體順時針轉多少（弧度，約 70°）
const SHORTBOW_TWIST := 0.7              # 短弓拉滿只轉約 40°
const BOW_IN := 0.6                      # 搭箭時弓手往身體內側收多少，讓右手搆得到弦
const BOW_LOW := 0.5                     # 搭箭時弓手放低多少
const BOW_FRONT := 1.0                   # 弓手往胸前偏多少：箭的直線走在胸口前方
const BOW_UP := 0.3                      # 弓手往上抬多少：箭的直線在下巴高度
const BOW_ARM_REACH := 0.96              # 弓手伸出去的長度（× 手臂全長）：手肘微彎不鎖死
const PULL_OUT := 0.25                   # 帶箭到弓前的前段佔多少：箭頭從朝袋底轉成朝前（之後一直朝前）
const QUIVER_TOUCH := 0.95               # 收招走到這個比例時手碰到箭袋，箭才出現
const OVER_SHOULDER := Vector3(-0.12, 0.5, 0.05)   # 從箭袋帶到弓前途中經過的點（右肩上方，相對右肩）
const RELEASE_BACK := 0.18               # 放箭後拉弦手往後彈多遠


func pose_bow(a: Dictionary, e: float, charge: bool) -> void:
	var max_back: float = rig.weapon_nock.get_meta(&"arrow", 0.9) - 0.1 if rig.weapon_nock != null else 0.5   # 箭尾不能拉過箭頭
	var bring := 0.0
	var draw := 0.0
	if a.phase == &"windup":
		bring = minf(1.0, e / BRING_PART)
		draw = maxf(0.0, (e - BRING_PART) / (1.0 - BRING_PART))
	elif a.phase == &"active" and charge:
		draw = 1.0
	var twist := 0.0
	match a.phase:
		&"windup":
			twist = 0.4 * bring + 0.6 * draw
		&"active":
			twist = 1.0 if charge else 1.0 - 0.5 * e
		_:
			twist = 0.5 * (1.0 - e)
	rig.body.rotation.y = -(SHORTBOW_TWIST if rig.weapon_model == &"shortbow" else BOW_TWIST) * twist
	rig.body.rotation.x = 0.0
	set_stance(0.04, 0.15, -0.2, 0.6 + 0.4 * twist)   # 側身站開、膝蓋微彎
	var slack := bring * (1.0 - draw) if a.phase == &"windup" else 0.0
	var inv := Basis.from_euler(rig.body.rotation, EULER_ORDER_YXZ).inverse()
	var fwd := inv * Vector3.BACK          # 瞄準方向（角色的正前方）在身體座標
	var up := inv * Vector3.UP
	var bow_dir := (fwd + Vector3.BACK * BOW_FRONT + up * BOW_UP + (-up * BOW_LOW + Vector3.LEFT * BOW_IN) * slack).normalized()
	var arm_len := BodyPose.arm_length(rig)
	var grip := rig.arm_l.position + bow_dir * arm_len * BOW_ARM_REACH
	# 從待機開始拉弓：弓手在整段前搖從原本的位置平滑舉起，不在第一幀直接跳到舉弓的位置（用沒緩動的 a.k）
	if bow_raise <= 0.0:
		bow_hand_from = BodyPose.hand_pos(rig, false)
	bow_raise = maxf(bow_raise, smoothstep(0.0, 1.0, a.k)) if a.phase == &"windup" else 1.0
	BodyPose.arm_ik(rig, false, bow_hand_from.lerp(grip, bow_raise), Vector3(0.8, -0.6, -0.4))
	# 拉弦手：沿箭的直線（握把往後）拉，最多拉到箭長、右手臂搆得到的地方；手肘抬到箭線後面
	var full := minf(max_back, _reach_on_line(grip, fwd, arm_len * 0.98))
	var nock := grip - fwd * 0.08
	var drawn := grip - fwd * lerpf(0.08, full, draw)
	var shoulder := rig.arm_r.position
	var over := shoulder + OVER_SHOULDER
	var quiver := DarkFantasy.QUIVER_MOUTH
	var draw_pole := -fwd + Vector3.RIGHT * 0.6 + up * 0.25   # 右邊是 -X
	var reach_pole := Vector3(-0.8, 0.6, 0.3)                # 伸到背後時手肘往外上
	var hand := drawn
	var pole := draw_pole
	match a.phase:
		&"windup":
			if bring < 1.0:
				var k := smoothstep(0.0, 1.0, bring)
				hand = _bezier(quiver, over, nock, k)
				pole = reach_pole.lerp(draw_pole, k)
				_arrow = &"hand"
			else:
				_arrow = &"bow"
		&"active":
			if charge:
				_arrow = &"bow"
			else:
				hand = (grip - fwd * full).lerp(grip - fwd * (full + RELEASE_BACK) + Vector3.RIGHT * 0.15, e)   # 放箭：手順著往後彈
		_:
			var from := grip - fwd * (full + RELEASE_BACK) + Vector3.RIGHT * 0.15
			hand = _bezier(from, over, quiver, smoothstep(0.0, 1.0, e))
			pole = draw_pole.lerp(reach_pole, e)
			_arrow = &"hand" if e >= QUIVER_TOUCH else &"none"
	BodyPose.arm_ik(rig, true, hand, pole)
	_drawing = true
	_bring = bring if a.phase == &"windup" else 0.0


static func _bezier(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)


# 直線 grip - fwd * s 上，右手（全長 arm_len）搆得到的最遠的 s（搆不到就是最近點）
func _reach_on_line(grip: Vector3, fwd: Vector3, arm_len: float) -> float:
	var w := grip - rig.arm_r.position
	var along := w.dot(fwd)
	var disc := along * along - w.length_squared() + arm_len * arm_len
	return along + sqrt(disc) if disc >= 0.0 else along


# 收尾後擺箭與弦（要世界座標，在場景樹裡才做）
func _bow_visuals() -> void:
	if rig.weapon_nock == null:
		return
	rig.weapon_nock.visible = _arrow != &"none"
	var ok := rig.weapon_nock.is_inside_tree()
	_bow_string(rig.hand_r.global_position if _arrow == &"bow" and ok else null)
	if _arrow == &"none" or not ok:
		return
	var fwd := rig.global_transform.basis.z.normalized()
	if _arrow == &"hand":
		# 從箭袋抽出：一開始和箭袋平行、箭頭朝袋底，帶到弓前的途中轉成朝前（箭頭朝靶）
		var start := -rig.weapon_back.global_transform.basis.y.normalized() if rig.weapon_back != null else Vector3.DOWN
		var outward := -rig.body.global_transform.basis.x.normalized()
		var carry := (fwd + Vector3.DOWN * 0.3 + outward * 0.4).normalized()
		var dir := carry.slerp(fwd, clampf((_bring - PULL_OUT) / (1.0 - PULL_OUT), 0.0, 1.0))
		if _bring < PULL_OUT:
			var k := _bring / PULL_OUT
			dir = (start.slerp(carry, k) + outward * sin(PI * k)).normalized()
		rig.weapon_nock.position = Vector3.ZERO
		rig.weapon_nock.look_at(rig.weapon_nock.global_position + dir, Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP)
	elif rig.weapon_left != null:
		# 搭在弦上：箭尾在右手（勾弦處）、箭身穿過握把；拉弦時手往後、箭跟著往後縮
		var grip := Rig.mount_point(rig.weapon_left, &"grip")
		var tail := rig.hand_r.global_position
		var dir := grip - tail
		if dir.length() < 0.05:
			dir = fwd
		rig.weapon_nock.look_at_from_position(tail, tail + dir, Vector3.UP)


# 弓弦：pull（世界座標的拉弦點，箭尾）在弦的後方時，上下兩段從弓梢拉到 pull 成 V 字；null 或在弦前方就是直的
func _bow_string(pull: Variant) -> void:
	var bow := rig.weapon_left
	if bow == null or not bow.has_meta(&"strings"):
		return
	var tips: Array = bow.get_meta(&"string_tips")
	var rest: Vector3 = bow.get_meta(&"mounts").string
	var p := rest
	if pull != null and bow.is_inside_tree():
		var local := bow.to_local(pull)
		if local.z < rest.z:
			p = local
	var strings: Array = bow.get_meta(&"strings")
	for i in 2:
		var span: Vector3 = p - tips[i]
		var seg: MeshInstance3D = strings[i]
		seg.transform = Transform3D(Basis(Quaternion(Vector3.UP, span.normalized())).scaled_local(Vector3(1.0, span.length(), 1.0)), (tips[i] + p) / 2.0)


# 翻滾：繞身體中心往前翻一圈（body 樞紐在腳底，所以同時位移讓中心不動），抱膝、手肘收緊
func _pose_roll(k: float) -> void:
	free_legs = true
	var angle := TAU * smoothstep(0.0, 1.0, k)
	var center := rig.height * ROLL_CENTER
	rig.body.rotation = Vector3(wrapf(angle, -PI, PI), 0.0, 0.0)   # 結束時接近 0，回到待機姿勢不會倒轉一圈
	rig.body.position.y = center - center * cos(angle)
	rig.body.position.z = -center * sin(angle)
	var tuck := sin(k * PI)
	rig.head.rotation.x = 0.5 * tuck   # 低頭、下巴收進胸口
	BodyPose.leg(rig, true, -1.6 * tuck, 2.2 * tuck)
	BodyPose.leg(rig, false, -1.5 * tuck, 2.1 * tuck)
	BodyPose.arm(rig, true, -0.5 * tuck, 0.3 * tuck, 2.1 * tuck)   # 拳頭收到胸前，手腕轉到劍尖朝腳（翻到頭下腳上時劍不插進地裡）
	wrist_target = 2.9 * tuck
	BodyPose.arm(rig, false, -0.5 * tuck, -0.3 * tuck, 2.1 * tuck)


# 盾擊：盾舉到身前（左上臂往前外、前臂橫在胸前）→ active 往前推（手肘伸開、肩膀頂進去），劍收在身側；左腳在前、膝蓋微蹲
func _pose_shield_block(a: Dictionary, e: float, dt: float) -> void:
	match a.phase:
		&"windup":
			BodyPose.arm(rig, false, lerpf(-0.1, -1.25, e), lerpf(0.0, -0.55, e), lerpf(0.3, 1.25, e))
			BodyPose.arm(rig, true, lerpf(-0.35, 0.25, e), 0.0, lerpf(idle_elbow(true), 1.2, e))
			rig.body.rotation.x = lerpf(0.0, 0.12, e)
			set_stance(0.1 * e, -0.15, 0.3, e)
		&"active":
			BodyPose.arm(rig, false, -1.4, -0.6, lerpf(1.25, 0.65, minf(1.0, e * 2.0)))
			BodyPose.arm(rig, true, 0.25, 0.0, 1.2)
			rig.body.rotation.x = 0.16
			set_stance(0.12, -0.2, 0.4)
		_:
			rig.arm_l.rotation.x = MathUtil.damp(rig.arm_l.rotation.x, -0.1, 18.0, dt)
			rig.arm_l.rotation.y = lerpf(-0.6, 0.0, e)
			rig.forearm_l.rotation.x = -lerpf(0.65, 0.3, e)
			BodyPose.arm(rig, true, lerpf(0.25, -0.35, e), 0.0, lerpf(1.2, idle_elbow(true), e))
			rig.body.rotation.x = lerpf(0.16, 0.0, e)
			set_stance(0.12, -0.2, 0.4, 1.0 - e)


# 盾反：盾往前猛推（手肘一下打直）、身體前衝、前腳踏出（parry 從 1 降到 0）
func _pose_parry(k: float) -> void:
	var push := sin(k * PI)
	BodyPose.arm(rig, false, -1.5 - 0.15 * push, -0.4, lerpf(1.1, 0.2, push))
	rig.body.rotation.x = 0.35 * push
	set_stance(0.12 * push, -0.3 * push, 0.5 * push, push)


# 施法（法杖、火把往前一指）：前搖手臂抬起、手肘收、杖頭往後倒 → 出手肩膀往前、手肘伸直把杖頭往前推
func _pose_fire_bolt(idle: Dictionary, a: Dictionary, e: float) -> void:
	if a.phase == &"windup":
		BodyPose.arm(rig, true, lerpf(idle.arm_r, -1.2, e), 0.1, lerpf(idle_elbow(true), 1.3, e))
		weapon_tilt = lerpf(0.0, 1.3, e)
		set_stance(0.04 * e, -0.1, 0.25, e)
		return
	var r := 0.0 if a.phase == &"active" else e
	BodyPose.arm(rig, true, lerpf(-1.55, idle.arm_r, r), 0.1, lerpf(0.15, idle_elbow(true), r))
	BodyPose.arm(rig, false, -0.3, 0.2, 0.9)
	weapon_tilt = lerpf(1.3, 0.0, r)
	set_stance(0.06, -0.15, 0.35, 1.0 - r)


# 爆裂（法杖舉高再往下壓）：前搖杖舉過頭（手肘微彎）、另一手往前張、身體後仰 → 出手杖往前下壓、膝蓋一沉
func _pose_arcane_burst(idle: Dictionary, a: Dictionary, e: float) -> void:
	if a.phase == &"windup":
		BodyPose.arm(rig, true, lerpf(idle.arm_r, -2.75, e), 0.1, lerpf(idle_elbow(true), 0.35, e))
		BodyPose.arm(rig, false, lerpf(0.0, -1.2, e), -0.3, lerpf(0.3, 0.6, e))
		weapon_tilt = lerpf(0.0, -0.3, e)
		rig.body.rotation.x = -0.12 * e
		return
	var r := 0.0 if a.phase == &"active" else e
	BodyPose.arm(rig, true, lerpf(-1.6, idle.arm_r, r), 0.1, lerpf(0.3, idle_elbow(true), r))
	BodyPose.arm(rig, false, lerpf(-0.6, 0.0, r), -0.3, 0.5)
	weapon_tilt = lerpf(1.2, 0.0, r)
	rig.body.rotation.x = 0.15 * (1.0 - r)
	set_stance(0.14, 0.2, -0.2, 1.0 - r)
