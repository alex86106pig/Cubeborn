# 死掉時手上的武器掉到地上（畫面層，玩家與怪物共用）：倒下撞到地的時候鬆手，記下那一刻武器在角色座標的位置與方向，
# 往外彈一下、照重力落地，同時轉到平躺（DarkFantasy.LIE），落在手的外側不動。武器還是掛在手持關節（held_*）上，每幀換算成手的座標，
# 所以屍體沉進地面時一起沉；不再倒地（假死被救起來、物件重用）就回到手上
class_name HeldDrop
extends RefCounted

const RELEASE := 0.25    # 倒下後幾秒鬆手（身體撞到地的時候）；怪物的長柄武器倒下途中會戳到地，早一點鬆（EnemyAnimator 一死就鬆）
const OUT := 0.5         # 落點比鬆手時往外多遠（× 身體縮放）
const HOP := 1.2         # 鬆手時往上彈的速度（單位/秒）
const FALL_MIN := 0.15   # 掉落秒數的範圍（照高度算，太低也要看得到在掉）
const FALL_MAX := 0.6

var _state: Array = [{}, {}]   # 右手、左手：{ from, to（角色座標的 Transform3D）, fall（秒）, t }


# down：倒在地上；time：倒下幾秒；lies：右手、左手的 DarkFantasy.LIE（空的 = 沒拿東西）；release：倒下後幾秒鬆手
func update(rig, down: bool, time: float, lies: Array, dt: float, release := RELEASE) -> void:
	for i in 2:
		var right := i == 0
		var held = rig.held_r if right else rig.held_l
		var lie: Array = lies[i]
		if not down or lie.is_empty() or time < release:
			if not (_state[i] as Dictionary).is_empty():
				_state[i] = {}
				_set_local(held, Transform3D.IDENTITY)
			continue
		var hand := _hand_tf(rig, right)
		if (_state[i] as Dictionary).is_empty():
			_state[i] = _release(rig, hand * _local(held), lie, right)
		var s: Dictionary = _state[i]
		s.t += dt
		var k := clampf(s.t / s.fall, 0.0, 1.0)
		var from: Transform3D = s.from
		var to: Transform3D = s.to
		var pos := from.origin.lerp(to.origin, k)
		pos.y = maxf(to.origin.y, from.origin.y + HOP * s.t - 0.5 * BodyPose.G * s.t * s.t) if k < 1.0 else to.origin.y
		var q := from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), k)
		_set_local(held, hand.affine_inverse() * Transform3D(Basis(q).scaled(from.basis.get_scale()), pos))


# 鬆手那一刻：from = 武器現在在角色座標的位置；to = 落在手的外側、平躺、離地 LIE 的半厚
func _release(rig, from: Transform3D, lie: Array, right: bool) -> Dictionary:
	var s: float = from.basis.get_scale().x
	var fore := _arm_dir(rig, right)
	var out := Vector3(fore.x, 0.0, fore.z)
	out = out.normalized() if out.length_squared() > 1e-6 else Vector3.RIGHT * (-1.0 if right else 1.0)
	var dir: Vector3 = {&"out": out, &"feet": Vector3.BACK, &"side": out.cross(Vector3.UP)}[lie[2]]
	var flat := Basis(dir, Vector3.UP, dir.cross(Vector3.UP)) * Basis(lie[0], lie[1], (lie[0] as Vector3).cross(lie[1])).inverse()
	var land := from.origin + out * OUT * s
	land.y = float(lie[3]) * s
	var fall := clampf((HOP + sqrt(HOP * HOP + 2.0 * BodyPose.G * maxf(from.origin.y - land.y, 0.0))) / BodyPose.G, FALL_MIN, FALL_MAX)
	return {"from": from, "to": Transform3D(flat.scaled(Vector3.ONE * s), land), "fall": fall, "t": 0.0}


# 手掌在角色座標（Rig 與 SkinnedRig 的關節都只有 position / rotation / scale）
static func _hand_tf(rig, right: bool) -> Transform3D:
	var t := Transform3D.IDENTITY
	for j in ([rig.body, rig.arm_r, rig.forearm_r, rig.hand_r] if right else [rig.body, rig.arm_l, rig.forearm_l, rig.hand_l]):
		t = t * _local(j)
	return t


# 前臂往拳頭的方向（角色座標）
static func _arm_dir(rig, right: bool) -> Vector3:
	var t := Transform3D.IDENTITY
	for j in ([rig.body, rig.arm_r, rig.forearm_r] if right else [rig.body, rig.arm_l, rig.forearm_l]):
		t = t * _local(j)
	return (t.basis * Vector3.DOWN).normalized()


static func _local(j) -> Transform3D:
	return Transform3D(Basis.from_euler(j.rotation, EULER_ORDER_YXZ).scaled_local(j.scale), j.position)


static func _set_local(j, t: Transform3D) -> void:
	j.position = t.origin
	j.rotation = t.basis.orthonormalized().get_euler(EULER_ORDER_YXZ)
	j.scale = t.basis.get_scale()
