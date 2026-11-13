# 劍尖拖尾：玩家揮砍（meleeSwing）時沿武器尖端真正走過的路畫一條帶子，帶子的寬度永遠面向鏡頭（斜視角下哪個方向揮都不會變成一條線，
# 斜劈就是斜的、直劈就是直的）。打得到的範圍另外由 Effects 在地上畫一片淡扇形（fx:slash 帶 tilt 的那種）。
# 掛在玩家骨架底下、top_level（點是世界座標，不跟著骨架動），每幀 WorldView 更新完動畫後呼叫 update
class_name BladeTrail
extends MeshInstance3D

const LIFE := 0.15            # 一個點留多久（秒）
const WIDTH := 0.16           # 帶子最寬（最新的點）多寬，往舊的點變細
const OPACITY := 0.9
const WINDUP_FROM := 0.7      # 前搖走到這個比例就開始畫（劍已經往下揮）
const MAX_POINTS := 24

# 鏡頭固定斜角（Config.CAMERA）：指向鏡頭的方向
static var _to_camera := Vector3(
	cos(Config.CAMERA.elevation) * sin(Config.CAMERA.azimuth), sin(Config.CAMERA.elevation), cos(Config.CAMERA.elevation) * cos(Config.CAMERA.azimuth))

var _trails: Array = [[], []]   # 右手、左手武器各一串：[[位置, 經過秒數], …]，新的在後
var _imesh := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()
var _model_ids: Array = [0, 0]   # 換武器就清掉


func _init() -> void:
	name = "BladeTrail"
	top_level = true
	mesh = _imesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = _mat


func update(rig: Rig, p: Player, dt: float) -> void:
	var a := p.anim
	var swinging: bool = a.get("action", &"") == &"attack" and a.get("behavior", &"") == &"meleeSwing" \
		and (a.get("phase", &"") == &"active" or (a.get("phase", &"") == &"windup" and a.get("k", 0.0) >= WINDUP_FROM))
	var attack: Dictionary = p.weapon.get("attack", {})
	var color: Color = attack.get("slash_finisher_color" if a.get("is_finisher", false) else "slash_color", Color.WHITE)
	var models: Array = [rig.weapon_main, rig.weapon_left]
	var any := false
	for i in 2:
		var pts: Array = _trails[i]
		var model: Node3D = models[i]
		var mid := model.get_instance_id() if model != null else 0
		if mid != _model_ids[i]:
			pts.clear()
			_model_ids[i] = mid
		for pt: Array in pts:
			pt[1] += dt
		while not pts.is_empty() and (pts[0][1] > LIFE or pts.size() > MAX_POINTS):
			pts.pop_front()
		if swinging and model != null:
			pts.append([_world_of(rig, model) * tip_of(model), 0.0])
		any = any or pts.size() >= 2
	if _imesh.get_surface_count() > 0:
		_imesh.clear_surfaces()
	if not any:
		return
	for pts: Array in _trails:
		if pts.size() >= 2:
			_draw_ribbon(pts, color)


# 沿點畫一條面向鏡頭的帶子：每個點往「前進方向 × 看的方向」兩邊展開，越舊越細越淡
func _draw_ribbon(pts: Array, color: Color) -> void:
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _mat)
	var n := pts.size()
	for i in n:
		var p: Vector3 = pts[i][0]
		var tangent: Vector3 = (pts[mini(i + 1, n - 1)][0] as Vector3) - (pts[maxi(i - 1, 0)][0] as Vector3)
		var side := tangent.cross(_to_camera)
		side = side.normalized() if side.length_squared() > 1e-8 else Vector3.ZERO
		var fresh := 1.0 - clampf(pts[i][1] / LIFE, 0.0, 1.0)   # 1 = 剛記下、0 = 快消失
		var w := WIDTH * 0.5 * fresh
		var c := Color(color, OPACITY * fresh * fresh)
		_imesh.surface_set_color(c)
		_imesh.surface_add_vertex(p + side * w)
		_imesh.surface_set_color(c)
		_imesh.surface_add_vertex(p - side * w)
	_imesh.surface_end()


# 模型在世界座標的 transform：沿父節點乘到骨架根節點（不靠場景樹的 global_transform，不在樹裡也能算）
static func _world_of(rig: Rig, model: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = model
	while n != rig and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return (rig.global_transform if rig.is_inside_tree() else rig.transform) * t


# 武器的尖端（模型座標）：離握把最遠的頂點（劍尖、匕首尖、權杖頭、火焰頂、鏟面末端），每個模型算一次記在 meta
static func tip_of(model: Node3D) -> Vector3:
	if model.has_meta(&"tip"):
		return model.get_meta(&"tip")
	var grip: Vector3 = model.get_meta(&"mounts", {}).get("grip", Vector3.ZERO)
	var best := grip
	for mi in PartKit.mesh_instances(model):
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != model and n is Node3D:
			t = (n as Node3D).transform * t
			n = n.get_parent()
		for v: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var w := t * v
			if w.distance_squared_to(grip) > best.distance_squared_to(grip):
				best = w
	model.set_meta(&"tip", best)
	return best
