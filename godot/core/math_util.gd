# 共用數學小工具（角度、插值、緩動）；XZ 平面以 Vector2(x, z) 表示
class_name MathUtil


static func ease_out_cubic(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)


static func ease_in_quad(t: float) -> float:
	return t * t


# 與幀率無關的指數趨近
static func damp(current: float, target: float, sharpness: float, dt: float) -> float:
	return lerpf(current, target, 1.0 - exp(-sharpness * dt))


static func wrap_angle(a: float) -> float:
	return wrapf(a, -PI, PI)


static func damp_angle(current: float, target: float, sharpness: float, dt: float) -> float:
	return wrap_angle(current + angle_difference(current, target) * (1.0 - exp(-sharpness * dt)))


static func turn_towards(current: float, target: float, max_step: float) -> float:
	var diff := angle_difference(current, target)
	if absf(diff) <= max_step:
		return wrap_angle(target)
	return wrap_angle(current + signf(diff) * max_step)


# XZ 平面朝向角：方向向量為 (sin a, cos a)，0 = 面向 +Z
static func angle_to(from: Vector2, to: Vector2) -> float:
	return atan2(to.x - from.x, to.y - from.y)


static func dir_from_angle(a: float) -> Vector2:
	return Vector2(sin(a), cos(a))
