# 畫面層動畫：依模擬層的 player.anim（狀態、階段、進度 k）算出關節角度（PROJECT_GUIDELINES.md 第 11 節）
# 姿勢公式照搬網頁版 playerStates.js（腿、上半身、倒地、硬直）與 weaponBehaviors.js（各武器的 update）
# 每個渲染幀執行；網頁版「每步 lerp 固定比例」換算成與幀率無關的版本（_step_lerp）
class_name Animator
extends RefCounted

# 招式 → 姿勢（2026-10-27 網頁版實測後補專屬動作）；同一個招式依武器模型換姿勢的在 _pose_for
const POSE_OF := {
	&"arrowFan": &"bow",
	&"chargedShot": &"bowCharge",
	&"shadowStep": &"thrust",
	&"holyCircle": &"arcaneBurst",
	&"torchStance": &"torchRaise",
	&"plantTorch": &"plant",
	&"fireBreath": &"arcaneBurst",
	&"shovelGrab": &"scoop",
	&"shovelThrow": &"fling",
	&"shovelBury": &"slam",
}
const BOW_MODELS: Array[StringName] = [&"shortbow", &"longbow"]
const UPRIGHT_MODELS: Array[StringName] = [&"staff", &"torch", &"scepter"]   # 武器跟著 weapon_tilt 保持直立（不隨手臂轉）

const WALK_SHARPNESS := 12.0
const IDLE_SHARPNESS := 18.0
const DEATH_FALL_TIME := 0.45
const BLINK_RATE := 20.0      # 無敵時間每秒閃爍次數
const GEM_SPIN := 3.0         # 法杖寶石自轉（弧度/秒；網頁版每幀 0.05 × 60）
const ROLL_CENTER := 0.4      # 翻滾的旋轉中心（角色高度的比例）
const DIG_RATE := 1.5         # 挖墳每秒挖幾下（D6）

var rig: Rig
var walk_phase := 0.0
var walk_amount := 0.0
var weapon_tilt := 0.0


func _init(p_rig: Rig) -> void:
	rig = p_rig


func update(p: Player, dt: float) -> void:
	rig.set_weapon(p.weapon.model)
	var a := p.anim
	rig.body.position.z = 0.0   # 只有翻滾會移動 body 的前後位置
	_pose_locomotion(p, a, dt)
	var is_down: bool = a.loco == &"dead" or a.loco == &"downed"   # 倒地假死（C4）和死亡同一個躺地姿勢
	if a.airborne and not is_down:
		_pose_airborne(a)
	if not is_down:
		_pose_action(p, a, dt)
		if a.parry > 0.0:
			_pose_parry(1.0 - a.parry)
	if rig.weapon_model in UPRIGHT_MODELS and rig.weapon_main != null:
		rig.weapon_main.rotation.x = weapon_tilt - rig.arm_r.rotation.x
	if rig.weapon_nock != null and not (a.action in [&"attack", &"special"] and _pose_for(a.behavior) in [&"bow", &"bowCharge"]):
		rig.weapon_nock.visible = false
	var shown: int = p.quiver if p.weapon.attack.has("quiver") else rig.weapon_quiver_arrows.size()
	for i in rig.weapon_quiver_arrows.size():   # 短弓箭袋：剩幾發就露出幾支；長弓沒有箭數機制，一直是滿的
		(rig.weapon_quiver_arrows[i] as Node3D).visible = i < shown
	if rig.weapon_model in BOW_MODELS and rig.weapon_left != null:
		rig.weapon_left.rotation.x = -rig.arm_l.rotation.x   # 弓一直直立（左手平舉時也不會躺平）
	if rig.weapon_gem != null:
		rig.weapon_gem.rotation.y += GEM_SPIN * dt

	var flash_time: float = Config.COMBAT.flash_time
	rig.set_flash(0.9 * p.flash_timer / flash_time if p.flash_timer > 0.0 else 0.0)
	rig.visible = p.is_dead or p.invuln_timer <= 0.0 or int(floor(p.invuln_timer * BLINK_RATE)) % 2 == 0


# 網頁版每個邏輯步 lerp(a, b, f)；換成每幀時以經過的步數換算比例
static func _step_lerp(from: float, to: float, f: float, dt: float) -> float:
	return lerpf(from, to, 1.0 - pow(1.0 - f, dt / Config.FIXED_DT))


static func _ease(k: float) -> float:
	return MathUtil.ease_out_cubic(clampf(k, 0.0, 1.0))


# ───────── 移動層 ─────────

func _pose_locomotion(p: Player, a: Dictionary, dt: float) -> void:
	match a.loco:
		&"idle":
			walk_amount = MathUtil.damp(walk_amount, 0.0, WALK_SHARPNESS, dt)
			_pose_legs()
		&"move":
			walk_amount = MathUtil.damp(walk_amount, 1.0, WALK_SHARPNESS, dt)
			walk_phase += dt * p.velocity.length() * 1.7
			_pose_legs()
		&"dead", &"downed":
			walk_amount = 0.0
			var k := _ease(a.loco_time / DEATH_FALL_TIME)
			rig.body.rotation.x = lerpf(0.0, PI / 2.0, k)
			rig.body.position.y = 0.13 * k
			rig.arm_r.rotation.x = _step_lerp(rig.arm_r.rotation.x, -2.6, 0.2, dt)
			rig.arm_l.rotation.x = _step_lerp(rig.arm_l.rotation.x, -2.6, 0.2, dt)


func _pose_legs() -> void:
	var swing := sin(walk_phase) * 0.9 * walk_amount
	rig.leg_r.rotation.x = swing
	rig.leg_l.rotation.x = -swing
	rig.body.position.y = absf(sin(walk_phase)) * 0.06 * walk_amount


# 空中：前腳抬起、後腳往後，上升時縮得多、下墜時慢慢伸直準備落地（翻滾時由翻滾姿勢覆蓋）
func _pose_airborne(a: Dictionary) -> void:
	var v0 := 4.0 * Config.JUMP.height / Config.JUMP.air_time
	var tuck := clampf(0.5 + 0.5 * a.vz / v0, 0.0, 1.0)
	rig.leg_r.rotation.x = lerpf(-0.35, -1.1, tuck)
	rig.leg_l.rotation.x = lerpf(0.15, 0.45, tuck)
	rig.body.position.y = 0.0


# ───────── 動作層 ─────────

func _pose_action(p: Player, a: Dictionary, dt: float) -> void:
	var idle: Dictionary = p.weapon.idle
	match a.action:
		&"ready":
			_pose_idle_upper_body(idle, dt)
			if a.get("holding", false):
				_pose_holding(dt)        # 鐵鏟舉著怪
			elif a.get("torch_stance", false):
				_pose_torch_raised(dt)   # 火把準備姿態
		&"attack", &"special":
			var e := _ease(a.k)
			match _pose_for(a.behavior):
				&"meleeSwing":
					_pose_melee_swing(idle, a, e, dt)
				&"shieldBlock":
					_pose_shield_block(a, e, dt)
				&"arcaneBurst":
					_pose_arcane_burst(idle, a, e)
				&"thrust":
					_pose_thrust(idle, a, e)
				&"scoop":
					_pose_scoop(idle, a, e)
				&"fling":
					_pose_overhead(idle, a, e, -1.0, 0.1)
				&"slam":
					_pose_overhead(idle, a, e, -0.15, 0.45)
				&"mace":
					_pose_mace(idle, a, e, dt)
				&"bow":
					_pose_bow(idle, a, e, false)
				&"bowCharge":
					_pose_bow(idle, a, e, true)
				&"torchRaise":
					_pose_torch_raise(idle, a, e)
				&"plant":
					_pose_plant(idle, a, e)
				_:
					_pose_fire_bolt(idle, a, e)
		&"useItem":
			var k := clampf(a.action_time / Config.PLAYER.use_item_time, 0.0, 1.0)
			rig.arm_l.rotation.x = lerpf(0.0, -2.4, sin(k * PI))
		&"stagger":
			var k := clampf(a.action_time / Config.PLAYER.stagger_time, 0.0, 1.0)
			rig.body.rotation.x = -0.3 * sin(k * PI)
		&"roll":
			_pose_roll(clampf(a.action_time / Config.ROLL.duration, 0.0, 1.0))
		&"dig":
			# 挖墳（D6）：彎腰、雙手一下一下往下挖（每秒約 1.5 下）
			var swing := 0.5 + 0.5 * sin(a.action_time * TAU * DIG_RATE)
			rig.body.rotation.x = lerpf(0.25, 0.55, swing)
			rig.arm_r.rotation.x = lerpf(-1.9, -0.3, swing)
			rig.arm_l.rotation.x = lerpf(-1.9, -0.3, swing)


# 招式的姿勢：普攻依武器模型分（匕首刺、鐵鏟鏟、權杖敲砸、弓拉弓），其餘查 POSE_OF
func _pose_for(behavior: StringName) -> StringName:
	match behavior:
		&"meleeSwing":
			match rig.weapon_model:
				&"daggers":
					return &"thrust"
				&"shovel":
					return &"scoop"
				&"scepter":
					return &"mace"
			return &"meleeSwing"
		&"fireBolt":
			return &"bow" if rig.weapon_model in BOW_MODELS else &"fireBolt"
		&"shieldBlock", &"arcaneBurst":
			return behavior
	return POSE_OF.get(behavior, &"fireBolt")


# ───────── 2026-10-27 補的專屬動作（網頁版實測：原本都借劍的橫掃或法杖的舉手） ─────────
# 手臂 rotation.x：0 = 自然下垂，負的往前抬（-1.5 約平舉、-2.7 舉過頭），正的往後擺

# 刺（雙匕首、影步）：swing_dir 1 右手、-1 左手輪流往前刺；終結技雙手一起刺、身體前傾
func _pose_thrust(idle: Dictionary, a: Dictionary, e: float) -> void:
	var fin: bool = a.get("is_finisher", false)
	var right: bool = fin or a.get("swing_dir", 1) >= 0
	var left: bool = fin or a.get("swing_dir", 1) < 0
	var back := 0.5 if fin else 0.35
	var x := 0.0
	match a.phase:
		&"windup":
			x = lerpf(idle.arm_r, back, e)
		&"active":
			x = lerpf(back, -1.65, e)
		_:
			x = lerpf(-1.65, idle.arm_r, e)
	if right:
		rig.arm_r.rotation = Vector3(x, 0.15 if fin else 0.0, 0.0)
	if left:
		rig.arm_l.rotation = Vector3(x, -0.15 if fin else 0.0, 0.0)
	var twist := 0.0 if fin else (0.3 if right else -0.3)   # 出手那一側的肩膀往前
	rig.body.rotation.y = twist * (1.0 if a.phase == &"active" else 0.5)
	rig.body.rotation.x = (0.25 if fin else 0.1) * (e if a.phase == &"active" else (1.0 - e if a.phase == &"recovery" else 0.0))


# 鏟（鐵鏟鏟地、鏟起）：雙手握柄，先往後拉、彎腰，再由下往前上鏟出去
func _pose_scoop(idle: Dictionary, a: Dictionary, e: float) -> void:
	var x := 0.0
	var bend := 0.0
	match a.phase:
		&"windup":
			x = lerpf(idle.arm_r, 0.55, e)
			bend = lerpf(0.0, 0.35, e)
		&"active":
			x = lerpf(0.55, -1.25, e)
			bend = lerpf(0.35, 0.05, e)
		_:
			x = lerpf(-1.25, idle.arm_r, e)
			bend = lerpf(0.05, 0.0, e)
	rig.arm_r.rotation = Vector3(x, 0.0, 0.0)
	rig.arm_l.rotation = Vector3(x + 0.15, 0.35, 0.0)   # 左手在右手前面一點握柄
	rig.body.rotation.x = bend


# 舉過頭再往前甩（拋出）/ 往下砸（埋入）：雙手；to = active 結束時手臂的角度，lean = 身體前傾
func _pose_overhead(idle: Dictionary, a: Dictionary, e: float, to: float, lean: float) -> void:
	var x := 0.0
	var body := 0.0
	match a.phase:
		&"windup":
			x = lerpf(-1.1, -2.6, e)
			body = lerpf(0.0, -0.15, e)
		&"active":
			x = lerpf(-2.6, to, e)
			body = lerpf(-0.15, lean, e)
		_:
			x = lerpf(to, idle.arm_r, e)
			body = lerpf(lean, 0.0, e)
	rig.arm_r.rotation = Vector3(x, 0.0, 0.0)
	rig.arm_l.rotation = Vector3(x, 0.3, 0.0)
	rig.body.rotation.x = body


# 舉著怪（鐵鏟）：雙手把鏟子往前上抬到鏟面約肩膀高，身體後仰撐住（怪放在鏟上的托舉點，2026-10-27 原本 -1.15 鏟面貼地、怪像被推著）
func _pose_holding(dt: float) -> void:
	rig.arm_r.rotation.x = _step_lerp(rig.arm_r.rotation.x, -1.8, 0.3, dt)
	rig.arm_l.rotation.x = _step_lerp(rig.arm_l.rotation.x, -1.65, 0.3, dt)
	rig.arm_l.rotation.y = _step_lerp(rig.arm_l.rotation.y, 0.35, 0.3, dt)
	rig.body.rotation.x = _step_lerp(rig.body.rotation.x, -0.2, 0.3, dt)


# 權杖：第 1 下橫掃（頭朝前），第 2 下（終結技）舉過頭往下砸
func _pose_mace(idle: Dictionary, a: Dictionary, e: float, dt: float) -> void:
	if a.get("is_finisher", false):
		_pose_overhead(idle, a, e, -0.6, 0.35)
		match a.phase:
			&"windup":
				weapon_tilt = lerpf(0.0, -0.4, e)
			&"active":
				weapon_tilt = lerpf(-0.4, 1.7, e)
			_:
				weapon_tilt = lerpf(1.7, idle.tilt, e)
		return
	_pose_melee_swing(idle, a, e, dt)
	weapon_tilt = 1.4 if a.phase == &"active" else lerpf(0.0, 1.4, e) if a.phase == &"windup" else lerpf(1.4, idle.tilt, e)


# 拉弓（2026-10-27 使用者：箭要從右手拿出、搭上弓弦）：一發的循環 = 收招時右手往上繞到背後箭袋把下一支箭往上抽出（箭沿手臂拿著）
# → 前搖前段經過頭頂往上繞到弓前搭弦（搭上後箭和瞄準方向平行）→ 前搖後段拉到胸前 → active 放箭、手往外彈、箭消失；
# 蓄力（charge）時 active 一直拉滿。左手持弓平舉、一直保持直立。右臂 rotation.y 正 = 往身體中線（內側）
const QUIVER_ARM := Vector2(-4.4, 0.2)   # 右手碰到背後的箭袋口（手臂往正後方、稍微往上）；和 NOCK_ARM 之間內插 = 往上抽、經過頭頂繞到前方
# （2026-10-27 使用者：箭袋維持在背上，從箭袋取出、向上繞再搭到弓上；水平往後擺的版本弧度太大）
const NOCK_ARM := Vector2(-1.5, 0.45)    # 右手在弓前搭弦
const DRAW_OUT := -0.35                  # 拉弦時右手往外後方收的角度
const NOCK_BACK := 0.25                  # 剛搭上弦時箭尾在握把後方多遠
const DRAWN_BACK := 0.6                  # 拉滿時箭尾在握把後方多遠（箭往後縮）
const BRING_PART := 0.45                 # 前搖的前段（帶到弓前）佔多少
const QUIVER_TOUCH := 0.95               # 收招走到這個比例時手碰到箭袋，箭才出現


func _pose_bow(idle: Dictionary, a: Dictionary, e: float, charge: bool) -> void:
	var arm := NOCK_ARM
	var arrow := &"none"   # none / hand（從箭袋抽出、拿在手上）/ bow（搭在弦上）
	var bring := 0.0       # 手從箭袋帶到弓前的進度（箭頭從朝上轉成朝前）
	var draw := 0.0        # 拉弦的進度（搭在弦上的箭往後滑）
	match a.phase:
		&"windup":
			bring = minf(1.0, e / BRING_PART)
			draw = maxf(0.0, (e - BRING_PART) / (1.0 - BRING_PART))
			arm = QUIVER_ARM.lerp(NOCK_ARM, bring) + Vector2(0.0, DRAW_OUT * draw)
			arrow = &"bow" if bring >= 1.0 else &"hand"
		&"active":
			if charge:
				arm = NOCK_ARM + Vector2(0.0, DRAW_OUT)
				arrow = &"bow"
				draw = 1.0
			else:
				arm = NOCK_ARM + Vector2(0.0, DRAW_OUT - 0.8 * e)   # 放箭：手往外彈開
		_:
			var from := NOCK_ARM + Vector2(0.0, DRAW_OUT - 0.8)
			arm = from.lerp(QUIVER_ARM, e)   # 收招：伸到肩後拿下一支箭
			arrow = &"hand" if e >= QUIVER_TOUCH else &"none"   # 手碰到箭袋才拿出箭（2026-10-27 使用者）
	const BODY_YAW := 0.35   # 身體側過來、左肩朝前
	rig.body.rotation.y = BODY_YAW
	rig.body.rotation.x = 0.0
	rig.arm_l.rotation = Vector3(-1.55, -BODY_YAW, 0.0)   # 弓手抵銷身體轉向，指向前方
	rig.arm_r.rotation = Vector3(arm.x, arm.y, 0.0)
	if rig.weapon_nock == null:
		return
	rig.weapon_nock.visible = arrow != &"none"
	if arrow == &"none" or not rig.weapon_nock.is_inside_tree():
		return
	var fwd := rig.global_transform.basis.z
	if arrow == &"hand":
		# 從箭袋抽出：箭頭朝上（袋口方向），手往上繞到前方的過程中轉成朝前（2026-10-27 使用者：原本沿手臂往後橫著戳出去）
		var dir := Vector3.UP.slerp(fwd, bring)
		rig.weapon_nock.position = Vector3.ZERO
		rig.weapon_nock.look_at(rig.weapon_nock.global_position + dir, Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP)
	elif rig.weapon_left != null:
		# 搭在弦上：箭尾在弦上（握把後方）、和瞄準方向平行，拉弦時往後滑（2026-10-27 使用者：準備射出前要往後縮）
		var tail := rig.weapon_left.global_position - fwd * lerpf(NOCK_BACK, DRAWN_BACK, draw)
		rig.weapon_nock.look_at_from_position(tail, tail + fwd, Vector3.UP)


# 舉起火把（進入準備姿態）
func _pose_torch_raise(idle: Dictionary, a: Dictionary, e: float) -> void:
	var k := e if a.phase == &"windup" else 1.0
	rig.arm_r.rotation = Vector3(lerpf(idle.arm_r, -2.7, k), 0.0, 0.0)
	weapon_tilt = 0.0


# 準備姿態中：火把舉過頭（全隊看得到的火光）
func _pose_torch_raised(dt: float) -> void:
	rig.arm_r.rotation.x = _step_lerp(rig.arm_r.rotation.x, -2.7, 0.3, dt)
	rig.arm_r.rotation.y = 0.0
	weapon_tilt = 0.0


# 插火把：蹲下、手往下把火把插進地裡
func _pose_plant(idle: Dictionary, a: Dictionary, e: float) -> void:
	var k := e if a.phase == &"windup" else (1.0 if a.phase == &"active" else 1.0 - e)
	rig.arm_r.rotation = Vector3(lerpf(-2.7, -0.6, k), 0.0, 0.0)
	rig.body.rotation.x = 0.45 * k


# 翻滾：繞身體中心往前翻一圈（body 樞紐在腳底，所以同時位移讓中心不動），四肢縮起
func _pose_roll(k: float) -> void:
	var angle := TAU * smoothstep(0.0, 1.0, k)
	var center := rig.height * ROLL_CENTER
	rig.body.rotation.x = wrapf(angle, -PI, PI)   # 結束時接近 0，回到待機姿勢不會倒轉一圈
	rig.body.rotation.y = 0.0
	rig.body.position.y = center - center * cos(angle)
	rig.body.position.z = -center * sin(angle)
	var tuck := sin(k * PI)
	rig.leg_r.rotation.x = -1.4 * tuck
	rig.leg_l.rotation.x = -1.4 * tuck
	rig.arm_r.rotation.x = -1.0 * tuck
	rig.arm_l.rotation.x = -1.0 * tuck


# 上半身平滑回到武器待機姿勢；手臂隨走路擺動
func _pose_idle_upper_body(idle: Dictionary, dt: float) -> void:
	var swing := sin(walk_phase) * 0.6 * walk_amount
	var s := IDLE_SHARPNESS
	rig.arm_r.rotation.x = MathUtil.damp(rig.arm_r.rotation.x, idle.arm_r - swing * 0.5, s, dt)
	rig.arm_r.rotation.y = MathUtil.damp(rig.arm_r.rotation.y, 0.0, s, dt)
	rig.arm_l.rotation.x = MathUtil.damp(rig.arm_l.rotation.x, idle.arm_l + swing, s, dt)
	rig.arm_l.rotation.y = MathUtil.damp(rig.arm_l.rotation.y, 0.0, s, dt)
	rig.body.rotation.x = MathUtil.damp(rig.body.rotation.x, 0.0, s, dt)
	rig.body.rotation.y = MathUtil.damp(rig.body.rotation.y, 0.0, s, dt)
	weapon_tilt = MathUtil.damp(weapon_tilt, idle.tilt, s, dt)


func _pose_melee_swing(idle: Dictionary, a: Dictionary, e: float, dt: float) -> void:
	var s: float = a.swing_dir
	var arm := rig.arm_r
	var body := rig.body
	rig.arm_l.rotation.x = _step_lerp(rig.arm_l.rotation.x, -0.6, 0.3, dt)
	match a.phase:
		&"windup":
			arm.rotation.x = lerpf(idle.arm_r, -1.35, e)
			arm.rotation.y = lerpf(0.0, -1.3 * s, e)
			body.rotation.y = lerpf(0.0, -0.25 * s, e)
		&"active":
			arm.rotation.x = -1.45
			arm.rotation.y = lerpf(-1.3 * s, 1.2 * s, e)
			body.rotation.y = lerpf(-0.25 * s, 0.35 * s, e)
		_:
			arm.rotation.x = lerpf(-1.45, idle.arm_r, e)
			arm.rotation.y = lerpf(1.2 * s, 0.0, e)
			body.rotation.y = lerpf(0.35 * s, 0.0, e)


# 格擋：盾舉到身前、劍收在身側、身體微蹲前傾；收招時放下（腿照常隨移動擺動）
func _pose_shield_block(a: Dictionary, e: float, dt: float) -> void:
	match a.phase:
		&"windup":
			rig.arm_l.rotation.x = lerpf(-0.1, -1.45, e)
			rig.arm_l.rotation.y = lerpf(0.0, -0.75, e)
			rig.arm_r.rotation.x = lerpf(-0.35, 0.3, e)
			rig.body.rotation.x = lerpf(0.0, 0.12, e)
		&"active":
			rig.arm_l.rotation = Vector3(-1.45, -0.75, 0.0)
			rig.arm_r.rotation.x = 0.3
			rig.body.rotation.x = 0.12
		_:
			rig.arm_l.rotation.x = _step_lerp(rig.arm_l.rotation.x, -0.1, 0.3, dt)
			rig.arm_l.rotation.y = lerpf(-0.75, 0.0, e)
			rig.body.rotation.x = lerpf(0.12, 0.0, e)


# 盾反：盾往前猛推、身體前衝（parry 從 1 降到 0）
func _pose_parry(k: float) -> void:
	var push := sin(k * PI)
	rig.arm_l.rotation = Vector3(-1.5 - 0.2 * push, -0.4, 0.0)
	rig.body.rotation.x = 0.35 * push


func _pose_fire_bolt(idle: Dictionary, a: Dictionary, e: float) -> void:
	if a.phase == &"windup":
		rig.arm_r.rotation.x = lerpf(idle.arm_r, -1.5, e)
		weapon_tilt = lerpf(0.0, 1.3, e)
		return
	var r := 0.0 if a.phase == &"active" else e
	rig.arm_r.rotation.x = lerpf(-1.5, idle.arm_r, r)
	weapon_tilt = lerpf(1.3, 0.0, r)


func _pose_arcane_burst(idle: Dictionary, a: Dictionary, e: float) -> void:
	if a.phase == &"windup":
		rig.arm_r.rotation.x = lerpf(idle.arm_r, -2.7, e)
		rig.arm_l.rotation.x = lerpf(0.0, -1.2, e)
		weapon_tilt = lerpf(0.0, -0.3, e)
		return
	var r := 0.0 if a.phase == &"active" else e
	rig.arm_r.rotation.x = lerpf(-1.6, idle.arm_r, r)
	rig.arm_l.rotation.x = lerpf(-0.6, 0.0, r)
	weapon_tilt = lerpf(1.2, 0.0, r)
