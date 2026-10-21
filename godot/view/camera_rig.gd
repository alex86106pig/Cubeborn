# 正交等距相機：平滑跟隨、畫面震動、滑鼠投射到地面；提供螢幕方向在地面上的投影
class_name CameraRig
extends Node3D

var camera := Camera3D.new()
var screen_forward := Vector2.ZERO   # 螢幕上方在地面上的方向（世界 XZ）
var screen_right := Vector2.ZERO

var _offset := Vector3.ZERO
var _screen_up := Vector3.ZERO
var _right3 := Vector3.ZERO
var _target := Vector3.ZERO
var _aim_plane := Plane(Vector3.UP, Config.CAMERA.aim_plane_height)
var _shake_strength := 0.0
var _shake_time := 0.0
var _shake_duration := 0.0


func _ready() -> void:
	var el: float = Config.CAMERA.elevation
	var az: float = Config.CAMERA.azimuth
	_offset = Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az)) * Config.CAMERA.distance
	var forward3 := Vector3(-_offset.x, 0.0, -_offset.z).normalized()
	_right3 = forward3.cross(Vector3.UP).normalized()
	_screen_up = _right3.cross(_offset).normalized()
	screen_forward = Vector2(forward3.x, forward3.z)
	screen_right = Vector2(_right3.x, _right3.z)

	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = Config.CAMERA.view_half_height * 2.0   # 預設 KEEP_HEIGHT：size 為可視高度
	camera.near = 0.1
	camera.far = 200.0
	add_child(camera)
	camera.make_current()
	follow(Vector3.ZERO, 0.0, true)


func shake(strength: float, duration: float = 0.2) -> void:
	var current := _shake_strength * (_shake_time / _shake_duration) if _shake_duration > 0.0 else 0.0
	if strength < current:
		return
	_shake_strength = strength
	_shake_time = duration
	_shake_duration = duration


# 畫面效果用一般 randf()：與模擬無關，各台不必一致
func follow(target: Vector3, dt: float, snap: bool = false) -> void:
	if snap:
		_target = target
	else:
		_target = _target.lerp(target, 1.0 - exp(-Config.CAMERA.follow_sharpness * dt))

	var shake_offset := Vector3.ZERO
	if _shake_time > 0.0:
		_shake_time = maxf(0.0, _shake_time - dt)
		var k := _shake_strength * (_shake_time / _shake_duration)
		shake_offset = _right3 * randf_range(-k, k) + _screen_up * randf_range(-k, k)

	var look := _target + shake_offset
	camera.look_at_from_position(look + _offset, look)


# 螢幕座標投射到瞄準平面；未命中回傳 null
func screen_to_ground(screen_pos: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	return _aim_plane.intersects_ray(origin, dir)
