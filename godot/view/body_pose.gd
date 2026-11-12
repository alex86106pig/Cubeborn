# 姿勢的共用工具（畫面層，玩家與敵人共用）：兩節 IK（手臂 / 腿）、照真實步態算的走路與跑步、腳踩地的站姿
# rig 可以是 Rig（Node3D 關節）或 SkinnedRig（Joint），兩者都有 position / rotation / scale，這裡只讀寫這三個欄位。
# 座標：「身體座標」= body 的區域座標（+Y 上、+Z 前、右側 -X，腳伸直時腳底 y = 0）；「角色座標」= rig 的區域座標（地面 y = 0）。
# 真實動作的參考數字整理在 docs/動作參考.md；改常數時對照那裡的範圍
class_name BodyPose
extends RefCounted

const G := 9.8                       # 算 Froude 數用（1 單位當 1 公尺；角色比真人高大一點，誤差不影響走跑的分界）
const RUN_FROUDE := Vector2(0.4, 3.0)   # Froude 數 v²/(g·腿長) 0.4 以下全走、3 以上全跑（真人約 0.5 換成跑）
const STRIDE_K := 2.3                # 相對步幅 = 一個循環（左右各一步）的距離 ÷ 腿長 = 2.3 × Fr^0.3（Alexander 的動態相似）
const STRIDE_EXP := 0.3
const STRIDE_MIN := 1.0              # 很慢時步幅的下限（× 腿長）：不然小碎步看起來在原地抖
const STRIDE_MAX := 4.2              # 步幅上限（× 腿長）：再大腳就搆不到地
const DUTY_WALK := 0.62              # 一隻腳踩在地上的時間比例：走路約 0.6、跑步約 0.3~0.4
const DUTY_RUN := 0.33
const LIFT_WALK := 0.15              # 擺盪期腳抬多高（× 腿長）：讓膝蓋在擺盪初期彎到約 60°
const LIFT_RUN := 0.42               # 跑步後腳往上踢（× 腿長）：膝蓋在擺盪中期彎到約 100~120°
const FOOT_ROLL := 0.8               # 踩地期間髖部帶動的距離比例：真人腳掌從腳跟滾到腳尖分掉一部分，沒有腳掌這裡直接縮短
const STANCE_FRONT := 0.6            # 踩地範圍在髖部前面的比例（髖部屈 30° 落地、伸 10° 離地，前多後少）
const HIP_STAND := 0.995             # 站著時髖部高度（× 腿長）：膝蓋微鬆、不鎖死
const HIP_WALK := 0.965              # 走路踩地中段的髖部高度：倒單擺，踩地中段最高
const HIP_WALK_BOB := 0.025
const HIP_RUN := 0.93                # 跑步踩地中段最低（膝蓋彎約 40° 吸收衝擊）、騰空時最高
const HIP_RUN_BOB := 0.05
const ARM_SWING_WALK := 0.3          # 手臂前後擺（弧度，跟對側的腳同方向）：走路 ±17°
const ARM_SWING_RUN := 0.75          # 跑步 ±43°
const ELBOW_WALK := 0.3              # 走路手肘微彎 ~17°
const ELBOW_RUN := 1.5               # 跑步手肘彎 ~86°（約直角）
const RUN_LEAN := 0.12               # 跑步上身前傾（弧度）


# 走跑的比例 0~1：照 Froude 數
static func run_amount(speed: float, leg: float) -> float:
	if leg <= 0.0:
		return 0.0
	return smoothstep(RUN_FROUDE.x, RUN_FROUDE.y, speed * speed / (G * leg))


# 一個步態循環（2π）走多遠
static func stride(speed: float, leg: float) -> float:
	var fr := speed * speed / (G * maxf(leg, 0.01))
	return leg * clampf(STRIDE_K * pow(fr, STRIDE_EXP), STRIDE_MIN, STRIDE_MAX)


# 步態相位往前推：踩在地上的腳往後滑的速度 = 移動速度，腳不會在地上滑
static func advance(phase: float, speed: float, leg: float, dt: float) -> float:
	if speed <= 0.001:
		return phase
	return fmod(phase + TAU * speed * dt / stride(speed, leg), TAU)


# 腿長（角色座標）：髖關節高度 × 身體縮放
static func leg_length(rig) -> float:
	return rig.leg_r.position.y * rig.body.scale.y


# 一隻腳在循環位置 u（0~1，0 = 腳跟著地）時，腳底相對髖部正下方的 (前後 z, 離地高 y)
# run：跑步的腳先往後上方踢（腳跟靠近臀部），擺盪後半才往前帶；走路的腳貼著地往前
static func foot_path(u: float, duty: float, reach: float, lift: float, run: float) -> Vector2:
	u = fposmod(u, 1.0)
	var front := reach * STANCE_FRONT
	var back := reach - front
	if u < duty:
		return Vector2(front - reach * u / duty, 0.0)
	var v := (u - duty) / (1.0 - duty)
	var fwd := smoothstep(0.0, 1.0, pow(v, lerpf(1.0, 1.7, run)))
	return Vector2(lerpf(-back, front, fwd), lift * sin(PI * pow(v, lerpf(0.75, 0.6, run))))


# 步態的站姿：{ r, l = 兩腳腳底（角色座標）, drop = 髖部比站直低多少, lean = 上身前傾, run }
# amount：0 = 站著、1 = 走 / 跑；speed 決定步幅與走跑；phase 用 advance 推
static func gait(rig, phase: float, amount: float, speed: float) -> Dictionary:
	var leg := leg_length(rig)
	var run := run_amount(speed, leg)
	var duty := lerpf(DUTY_WALK, DUTY_RUN, run)
	var reach := stride(maxf(speed, 0.5), leg) * duty * FOOT_ROLL * amount   # 踩地期間腳底相對髖部往後移的距離
	var lift := leg * lerpf(LIFT_WALK, LIFT_RUN, run) * amount
	var u := phase / TAU
	var fr := foot_path(u, duty, reach, lift, run)
	var fl := foot_path(u + 0.5, duty, reach, lift, run)
	var bob := cos(4.0 * PI * (u - duty / 2.0))   # 兩腳的踩地中段各一次
	var walk_h := HIP_WALK + HIP_WALK_BOB * bob
	var run_h := HIP_RUN - HIP_RUN_BOB * bob
	var h := lerpf(HIP_STAND, lerpf(walk_h, run_h, run), amount)
	var s: float = rig.body.scale.x
	return {
		"r": Vector3(rig.leg_r.position.x * s, fr.y, fr.x + rig.leg_r.position.z * s),
		"l": Vector3(rig.leg_l.position.x * s, fl.y, fl.x + rig.leg_l.position.z * s),
		"drop": leg * (1.0 - h), "lean": RUN_LEAN * run * amount, "run": run, "u": u,
	}


# 雙腳站在 feet_r / feet_l（角色座標的腳底位置）：上身照 body.rotation 從髖部彎（不是從腳底整個人斜過去），
# 髖部在站直的位置往下 drop、往前 shift，腿用 IK 搆到腳底（搆不到就伸直指過去）
static func plant(rig, feet_r: Vector3, feet_l: Vector3, drop: float, shift := 0.0) -> void:
	var body = rig.body
	var s: float = body.scale.x
	var basis := Basis.from_euler(body.rotation, EULER_ORDER_YXZ)
	var hip := Vector3(0.0, rig.leg_r.position.y, rig.leg_r.position.z)
	body.position = Vector3(0.0, s * hip.y - drop, s * hip.z + shift) - basis * (hip * s)
	var to_body := Transform3D(basis.scaled_local(Vector3.ONE * s), body.position).affine_inverse()
	leg_ik(rig, rig.leg_r, rig.shin_r, to_body * feet_r)
	leg_ik(rig, rig.leg_l, rig.shin_l, to_body * feet_l)


# 站在原地（腳在髖部正下方，可前後錯開）：stance_r / stance_l = 腳底往前多少（角色座標）
static func stand(rig, drop: float, stance_r := 0.0, stance_l := 0.0, shift := 0.0) -> void:
	var s: float = rig.body.scale.x
	plant(rig, Vector3(rig.leg_r.position.x * s, 0.0, stance_r), Vector3(rig.leg_l.position.x * s, 0.0, stance_l), drop, shift)


# 腿（或四足的前腳）的 IK：target = 腳底的身體座標；膝蓋往前（小腿往後彎，正的 rotation.x）
static func leg_ik(rig, root, mid, target: Vector3, knee_forward := true) -> void:
	var upper: float = -mid.position.y
	var lower: float = root.position.y - upper   # 伸直時腳底剛好在 y = 0
	two_bone(root, mid, target, upper, lower, Vector3.BACK if knee_forward else Vector3.FORWARD, 1.0 if knee_forward else -1.0)


# 手臂的 IK：target = 拳頭中心的身體座標；pole = 手肘大概朝哪（身體座標，例如往後下方）
static func arm_ik(rig, right: bool, target: Vector3, pole: Vector3) -> void:
	var arm = rig.arm_r if right else rig.arm_l
	var fore = rig.forearm_r if right else rig.forearm_l
	var hand = rig.hand_r if right else rig.hand_l
	two_bone(arm, fore, target, -fore.position.y, -hand.position.y, pole, -1.0)


# 手肘預設往後下方、稍微往外
static func elbow_pole(right: bool) -> Vector3:
	return Vector3(-0.35 if right else 0.35, -0.4, -1.0)


# 兩節 IK：root（上臂 / 大腿）從 root.position 搆到 target（同一個父座標系），mid（前臂 / 小腿）只彎 rotation.x。
# bend_sign = -1：前臂往 +Z 彎（手肘，rotation.x 負）；+1：小腿往 -Z 彎（膝蓋，rotation.x 正）。
# 中間關節的位置照 pole 的方向放（pole 垂直於「root → target」的分量決定彎的平面）
static func two_bone(root, mid, target: Vector3, l1: float, l2: float, pole: Vector3, bend_sign: float) -> void:
	var d: Vector3 = target - root.position
	var dist := clampf(d.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.0001)
	var dir := d.normalized() if d.length_squared() > 1e-8 else Vector3.DOWN
	var perp := pole - dir * pole.dot(dir)
	if perp.length_squared() < 1e-6:
		perp = Vector3.FORWARD - dir * dir.z
		if perp.length_squared() < 1e-6:
			perp = Vector3.UP - dir * dir.y
	perp = perp.normalized()
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var a := acos(cos_a)
	var upper_dir := dir * cos_a + perp * sin(a)
	var lower_dir := (dir * dist - upper_dir * l1).normalized()
	var bend := acos(clampf(upper_dir.dot(lower_dir), -1.0, 1.0))
	var side := lower_dir - upper_dir * lower_dir.dot(upper_dir)   # 下一節往哪邊彎
	if side.length_squared() < 1e-6:
		side = -perp
	side = side.normalized()
	var y := -upper_dir
	var z := side * -bend_sign
	root.rotation = Basis(y.cross(z), y, z).get_euler(EULER_ORDER_YXZ)
	mid.rotation = Vector3(bend * bend_sign, 0.0, 0.0)


# 手臂直接給角度（FK）：x 前後抬（負的往前）、y 往內外擺、elbow 手肘彎多少（正的 = 彎，換成 rotation.x 的負值）
static func arm(rig, right: bool, x: float, y: float, elbow: float) -> void:
	var a = rig.arm_r if right else rig.arm_l
	a.rotation = Vector3(x, y, 0.0)
	(rig.forearm_r if right else rig.forearm_l).rotation = Vector3(-maxf(elbow, 0.0), 0.0, 0.0)


# 腿直接給角度（FK，空中、倒地用）：hip 前後（負的往前抬），knee 膝蓋彎多少（正的）
static func leg(rig, right: bool, hip: float, knee: float) -> void:
	(rig.leg_r if right else rig.leg_l).rotation = Vector3(hip, 0.0, 0.0)
	(rig.shin_r if right else rig.shin_l).rotation = Vector3(maxf(knee, 0.0), 0.0, 0.0)


# 前臂、小腿全部伸直（每幀開頭呼叫，姿勢沒寫到的關節不會留著上一個狀態的角度）
static func straighten(rig) -> void:
	for j in [rig.forearm_r, rig.forearm_l, rig.shin_r, rig.shin_l]:
		j.rotation = Vector3.ZERO


# 走路 / 跑步的手臂：跟對側的腳一起往前（u = 右腳的循環位置），手肘照走跑彎；base_r / base_l = 手臂的基本角度
static func swing_arms(rig, g: Dictionary, amount: float, base_r: float, base_l: float, elbow_add := 0.0) -> void:
	var run: float = g.run
	var sw := cos(TAU * g.u) * lerpf(ARM_SWING_WALK, ARM_SWING_RUN, run) * amount   # 右腳在前（u = 0）時右手在後
	var elbow := lerpf(0.12, lerpf(ELBOW_WALK, ELBOW_RUN, run), amount) + elbow_add
	arm(rig, true, base_r + sw, 0.0, elbow + maxf(0.0, -sw) * 0.4)    # 往前擺時手肘多彎一點
	arm(rig, false, base_l - sw, 0.0, elbow + maxf(0.0, sw) * 0.4)


# 拳頭中心的身體座標（照目前的關節角度算）
static func hand_pos(rig, right: bool) -> Vector3:
	var a = rig.arm_r if right else rig.arm_l
	var f = rig.forearm_r if right else rig.forearm_l
	var h = rig.hand_r if right else rig.hand_l
	return a.position + Basis.from_euler(a.rotation, EULER_ORDER_YXZ) * (f.position + Basis.from_euler(f.rotation, EULER_ORDER_YXZ) * h.position)


# 前臂的方向（身體座標）：前臂的 -Y 是往拳頭的方向
static func forearm_basis(rig, right: bool) -> Basis:
	var a = rig.arm_r if right else rig.arm_l
	var f = rig.forearm_r if right else rig.forearm_l
	return Basis.from_euler(a.rotation, EULER_ORDER_YXZ) * Basis.from_euler(f.rotation, EULER_ORDER_YXZ)


# 手臂全長（肩膀到拳頭中心，身體座標）
static func arm_length(rig) -> float:
	return -rig.forearm_r.position.y - rig.hand_r.position.y


# 身體座標的點 → 角色座標（不在場景樹裡也能算）
static func body_to_root(rig, p: Vector3) -> Vector3:
	var body = rig.body
	return Basis.from_euler(body.rotation, EULER_ORDER_YXZ).scaled_local(body.scale) * p + body.position
