# 畫面層動畫：依模擬層的 player.anim（狀態、階段、進度 k）算出關節角度（15.5）
# 姿勢公式照搬網頁版 playerStates.js（腿、上半身、倒地、硬直）與 weaponBehaviors.js（各武器的 update）
# 每個渲染幀執行；網頁版「每步 lerp 固定比例」換算成與幀率無關的版本（_step_lerp）
class_name Animator
extends RefCounted

const WALK_SHARPNESS := 12.0
const IDLE_SHARPNESS := 18.0
const DEATH_FALL_TIME := 0.45
const BLINK_RATE := 20.0      # 無敵時間每秒閃爍次數
const GEM_SPIN := 3.0         # 法杖寶石自轉（弧度/秒；網頁版每幀 0.05 × 60）
const ROLL_CENTER := 0.4      # 翻滾的旋轉中心（角色高度的比例）

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
	if a.loco != &"dead":
		_pose_action(p, a, dt)
	if rig.weapon_model == &"staff" and rig.weapon_main != null:
		rig.weapon_main.rotation.x = weapon_tilt - rig.arm_r.rotation.x
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
		&"dead":
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


# ───────── 動作層 ─────────

func _pose_action(p: Player, a: Dictionary, dt: float) -> void:
	var idle: Dictionary = p.weapon.idle
	match a.action:
		&"ready":
			_pose_idle_upper_body(idle, dt)
		&"attack", &"special":
			var e := _ease(a.k)
			match a.behavior:
				&"meleeSwing":
					_pose_melee_swing(idle, a, e, dt)
				&"shieldBash":
					_pose_shield_bash(a, e)
				&"fireBolt":
					_pose_fire_bolt(idle, a, e)
				&"arcaneBurst":
					_pose_arcane_burst(idle, a, e)
		&"useItem":
			var k := clampf(a.action_time / Config.PLAYER.use_item_time, 0.0, 1.0)
			rig.arm_l.rotation.x = lerpf(0.0, -2.4, sin(k * PI))
		&"stagger":
			var k := clampf(a.action_time / Config.PLAYER.stagger_time, 0.0, 1.0)
			rig.body.rotation.x = -0.3 * sin(k * PI)
		&"roll":
			_pose_roll(clampf(a.action_time / Config.ROLL.duration, 0.0, 1.0))


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


func _pose_shield_bash(a: Dictionary, e: float) -> void:
	match a.phase:
		&"windup":
			rig.arm_l.rotation.x = lerpf(-0.1, -1.5, e)
			rig.arm_l.rotation.y = lerpf(0.0, -0.6, e)
			rig.arm_r.rotation.x = lerpf(-0.35, 0.5, e)
			rig.body.rotation.x = lerpf(0.0, 0.25, e)
		&"active":
			rig.arm_l.rotation = Vector3(-1.5, -0.6, 0.0)
			rig.arm_r.rotation.x = 0.5
			rig.body.rotation.x = 0.25
		_:
			rig.body.rotation.x = lerpf(0.25, 0.0, e)


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
