# 畫面層敵人動畫：依模擬層的 enemy.anim（狀態、經過秒數、招式階段）擺姿勢，並畫 Boss 招式的地面預警
# 姿勢公式照搬網頁版 Enemy.js（爬出 / 受擊 / 死亡 / 走路）、MeleeEnemy.js、RangedEnemy.js、Boss.js
class_name EnemyAnimator
extends RefCounted

const TELEGRAPH_COLOR := Color("ff3030")
const HURT_ARM_SHARPNESS := 20.0
const DEATH_FALL_TIME := 0.4
const CORPSE_SINK_START := 0.6   # 屍體停留時間的 60% 後開始沉入地面
const CORPSE_SINK_DEPTH := 0.8
const SLAM_FOLLOW_TIME := 0.12   # 重砸落地後手臂揮下的秒數

var rig: Rig
var walk_phase := 0.0
var _prev_state: StringName = &""
var _slam_ring: MeshInstance3D = null
var _charge_line: MeshInstance3D = null


func _init(p_rig: Rig, e: Enemy) -> void:
	rig = p_rig
	walk_phase = randf() * TAU   # 畫面用隨機，與模擬無關
	if e.is_boss():
		_slam_ring = _make_ring(e.def.slam.radius)
		_charge_line = _make_line(e.def.charge.speed * e.def.charge.duration, e.radius * 2.0)


func update(e: Enemy, dt: float) -> void:
	var a := e.anim
	var state: StringName = a.state
	var t: float = a.time
	if state != _prev_state:
		# 網頁版各狀態 exit 時的還原
		rig.body.rotation.x = 0.0
		rig.head.rotation.y = 0.0
		rig.arm_r.rotation.y = 0.0
		rig.position.y = 0.0
		_prev_state = state
	var moving := e.velocity.length_squared() > 0.01
	var def := e.def

	match state:
		&"spawn":
			var k := MathUtil.ease_out_cubic(clampf(t / def.spawn_time, 0.0, 1.0))
			rig.position.y = lerpf(-rig.height, 0.0, k)
			_pose_walk(0.0, -0.4, -0.2)
		&"hurt":
			var k := clampf(t / def.hurt_time, 0.0, 1.0)
			rig.body.rotation.x = -0.35 * sin(k * PI)
			rig.arm_r.rotation.x = MathUtil.damp(rig.arm_r.rotation.x, -0.6, HURT_ARM_SHARPNESS, dt)
			rig.arm_l.rotation.x = MathUtil.damp(rig.arm_l.rotation.x, -0.6, HURT_ARM_SHARPNESS, dt)
		&"dead":
			var fall := clampf(t / DEATH_FALL_TIME, 0.0, 1.0)
			rig.body.rotation.x = lerpf(0.0, -PI / 2.0, MathUtil.ease_out_cubic(fall))
			rig.body.position.y = 0.13 * fall
			var corpse: float = def.corpse_time
			var sink_start := corpse * CORPSE_SINK_START
			rig.position.y = -CORPSE_SINK_DEPTH * clampf((t - sink_start) / (corpse - sink_start), 0.0, 1.0)
		&"chase":
			if e.is_boss():
				walk_phase += dt * e.velocity.length() * 1.6
				_pose_walk(1.0 if moving else 0.0, -0.5, -0.3)
			else:
				walk_phase += dt * e.velocity.length() * 2.2
				_pose_walk(1.0 if moving else 0.0, -0.6, -0.3)
		&"swing":
			_pose_walk(0.0, -0.6, -0.3)
			_pose_melee_swing(t, def.swing)
		&"kite":
			walk_phase += dt * e.velocity.length() * 2.2
			_pose_walk(1.0 if moving else 0.0, -0.2, -0.5)
		&"aim":
			var draw := MathUtil.ease_out_cubic(minf(1.0, t / def.aim_time * 1.5))
			rig.arm_l.rotation.x = lerpf(-0.5, -1.55, draw)
			rig.arm_r.rotation.x = lerpf(-0.2, -1.45, draw)
			rig.arm_r.rotation.y = lerpf(0.0, 0.5, draw)
			rig.leg_r.rotation.x = 0.0
			rig.leg_l.rotation.x = 0.0
		&"slam":
			_pose_slam(t, def.slam)
		&"charge":
			_pose_charge(a, dt, def.charge)
		&"summon":
			var k := clampf(t / def.summon.windup, 0.0, 1.0)
			_pose_arms(lerpf(-0.4, -2.9, MathUtil.ease_out_cubic(k)), 0.5)

	_update_telegraphs(e, a)
	var flash_time: float = Config.COMBAT.flash_time
	rig.set_flash(0.9 * e.flash_timer / flash_time if e.flash_timer > 0.0 else 0.0)


func _pose_walk(amount: float, arm_r: float, arm_l: float) -> void:
	var swing := sin(walk_phase) * 0.8 * amount
	rig.leg_r.rotation.x = swing
	rig.leg_l.rotation.x = -swing
	rig.arm_r.rotation.x = arm_r - swing * 0.4
	rig.arm_l.rotation.x = arm_l + swing * 0.5
	rig.arm_r.rotation.y = 0.0
	rig.arm_l.rotation.y = 0.0
	rig.body.position.y = absf(sin(walk_phase)) * 0.04 * amount


func _pose_arms(rx: float, ry: float = 0.0) -> void:
	rig.arm_r.rotation = Vector3(rx, -ry, 0.0)
	rig.arm_l.rotation = Vector3(rx, ry, 0.0)


# 骷髏戰士揮砍：舉刀（手臂高舉、身體後仰，看得出要出手）→ 揮下（由上往下砸、身體前傾）→ 收招回到持刀姿勢
func _pose_melee_swing(t: float, s: Dictionary) -> void:
	var arm := rig.arm_r
	var windup: float = s.windup
	var active: float = s.active
	if t < windup:
		var k := MathUtil.ease_out_cubic(t / windup)
		arm.rotation.x = lerpf(-0.6, -2.9, k)
		rig.body.rotation.x = lerpf(0.0, -0.18, k)
	elif t < windup + active:
		var k := (t - windup) / active
		arm.rotation.x = lerpf(-2.9, -0.3, k)
		rig.body.rotation.x = lerpf(-0.18, 0.25, k)
	else:
		var k := clampf((t - windup - active) / s.recovery, 0.0, 1.0)
		arm.rotation.x = lerpf(-0.3, -0.6, k)
		rig.body.rotation.x = lerpf(0.25, 0.0, k)


func _pose_slam(t: float, s: Dictionary) -> void:
	if t < s.windup:
		var k := MathUtil.ease_out_cubic(t / s.windup)
		_pose_arms(lerpf(-0.4, -3.0, k), 0.3)
		rig.body.rotation.x = lerpf(0.0, -0.2, k)
		return
	var k := clampf((t - s.windup) / SLAM_FOLLOW_TIME, 0.0, 1.0)
	_pose_arms(lerpf(-3.0, -0.9, k), 0.3)
	rig.body.rotation.x = lerpf(-0.2, 0.3, k)


func _pose_charge(a: Dictionary, dt: float, c: Dictionary) -> void:
	var pt: float = a.get("phase_time", 0.0)
	match a.get("phase", &"windup"):
		&"windup":
			var k := MathUtil.ease_out_cubic(clampf(pt / c.windup, 0.0, 1.0))
			_pose_arms(lerpf(-0.4, 0.6, k))
			rig.body.rotation.x = lerpf(0.0, 0.35, k)
		&"dash":
			walk_phase += dt * c.speed * 1.2
			_pose_walk(1.0, 0.6, 0.6)
			rig.body.rotation.x = 0.35
		&"stunned":
			rig.body.rotation.x = -0.25 + sin(pt * 18.0) * 0.05
			rig.head.rotation.y = sin(pt * 6.0) * 0.4
			_pose_arms(-0.3)
		_:
			rig.body.rotation.x = lerpf(0.35, 0.0, clampf(pt / c.recovery, 0.0, 1.0))
			_pose_arms(-0.3)


# ───────── Boss 地面預警（網頁版 Effects.telegraph / telegraphLine） ─────────

func _update_telegraphs(e: Enemy, a: Dictionary) -> void:
	if _slam_ring == null:
		return
	var t: float = a.time
	var slam: Dictionary = e.def.slam
	var show_slam: bool = a.state == &"slam" and t < slam.windup
	_slam_ring.visible = show_slam
	if show_slam:
		var k: float = t / slam.windup
		_set_alpha(_slam_ring, 0.35 + 0.35 * pow(sin(k * PI * 6.0), 2.0))

	var charge: Dictionary = e.def.charge
	var pt: float = a.get("phase_time", 0.0)
	var show_line: bool = a.state == &"charge" and a.get("phase", &"") == &"windup"
	_charge_line.visible = show_line
	if show_line:
		var k: float = pt / charge.windup
		_set_alpha(_charge_line, 0.2 + 0.3 * pow(sin(k * PI * 5.0), 2.0))


func _make_ring(radius: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.85
	torus.outer_radius = radius
	torus.rings = 48
	ring.mesh = torus
	ring.scale.y = 0.02
	ring.position.y = 0.05
	ring.material_override = _telegraph_material()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	rig.add_child(ring)
	return ring


# 沿面向（+Z）延伸的長方形；Boss 蓄力時面向已鎖定，掛在 rig 下即可
func _make_line(length: float, width: float) -> MeshInstance3D:
	var line := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, length)
	line.mesh = plane
	line.position = Vector3(0.0, 0.04, length / 2.0)
	line.material_override = _telegraph_material()
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.visible = false
	rig.add_child(line)
	return line


func _telegraph_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	m.albedo_color = TELEGRAPH_COLOR
	return m


static func _set_alpha(mesh: MeshInstance3D, alpha: float) -> void:
	var m: StandardMaterial3D = mesh.material_override
	m.albedo_color.a = alpha
