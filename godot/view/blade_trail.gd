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
const REVERSE_MIN := 0.02     # 尖端一幀移動不到這麼多就不記新點（幾乎不動時的小抖動不切斷拖尾、不留尖角）

# 指向鏡頭的方向：遊戲是固定斜角（Config.CAMERA）；動畫檢視器會轉鏡頭，每幀自己設
var to_camera := Vector3(
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
			var at := rig.to_world(model) * tip_of(model)
			var step: Vector3 = at - pts[-1][0] if not pts.is_empty() else Vector3.ONE
			if step.length() >= REVERSE_MIN:   # 尖端幾乎沒動就不記（存下的每段都夠長，折返才判斷得出來）
				if pts.size() >= 2 and ((pts[-1][0] as Vector3) - pts[-2][0]).dot(step) < 0.0:
					pts.assign([pts[-1]])   # 尖端折返（舉劍 → 劈下、刺出 → 收回）：從折返點重新開始，一道拖尾只畫一次連續的揮動
				pts.append([at, 0.0])
		any = any or pts.size() >= 2
	if _imesh.get_surface_count() > 0:
		_imesh.clear_surfaces()
	if not any:
		return
	for pts: Array in _trails:
		if pts.size() >= 2:
			_draw_ribbon(pts, color)


# 沿點畫一條面向鏡頭的帶子：每個點往「前進方向 × 看的方向」兩邊展開，越舊越細越淡
func _draw_ribbon(raw: Array, color: Color) -> void:
	var pts := smooth(raw)
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _mat)
	var n := pts.size()
	for i in n:
		var p: Vector3 = pts[i][0]
		var tangent: Vector3 = (pts[mini(i + 1, n - 1)][0] as Vector3) - (pts[maxi(i - 1, 0)][0] as Vector3)
		var side := tangent.cross(to_camera)
		side = side.normalized() if side.length_squared() > 1e-8 else Vector3.ZERO
		var fresh := 1.0 - clampf(pts[i][1] / LIFE, 0.0, 1.0)   # 1 = 剛記下、0 = 快消失
		var w := WIDTH * 0.5 * fresh
		var c := Color(color, OPACITY * fresh * fresh)
		_imesh.surface_set_color(c)
		_imesh.surface_add_vertex(p + side * w)
		_imesh.surface_set_color(c)
		_imesh.surface_add_vertex(p - side * w)
	_imesh.surface_end()


# 每幀只記一個點、劍尖一幀走 0.5 以上，直接連起來轉彎處是尖角：用 centripetal Catmull-Rom（點的間距不均時不會甩出去）
# 穿過記到的點，每段再切 SUBDIV 小段；經過秒數照著內插
const SUBDIV := 12


static func smooth(pts: Array) -> Array:
	var n := pts.size()
	if n < 3:
		return pts
	var out: Array = []
	for i in n - 1:
		var p0: Vector3 = pts[maxi(i - 1, 0)][0]
		var p1: Vector3 = pts[i][0]
		var p2: Vector3 = pts[i + 1][0]
		var p3: Vector3 = pts[mini(i + 2, n - 1)][0]
		if i == 0:
			p0 = p1 * 2.0 - p2   # 兩端外插一個點，曲線才會走到端點
		if i + 2 > n - 1:
			p3 = p2 * 2.0 - p1
		var t1 := maxf(sqrt(p0.distance_to(p1)), 1e-4)
		var t2 := t1 + maxf(sqrt(p1.distance_to(p2)), 1e-4)
		var t3 := t2 + maxf(sqrt(p2.distance_to(p3)), 1e-4)
		for k in SUBDIV:
			var t := lerpf(t1, t2, float(k) / SUBDIV)
			var a1 := p0.lerp(p1, t / t1)
			var a2 := p1.lerp(p2, (t - t1) / (t2 - t1))
			var a3 := p2.lerp(p3, (t - t2) / (t3 - t2))
			var b1 := a1.lerp(a2, t / t2)
			var b2 := a2.lerp(a3, (t - t1) / (t3 - t1))
			out.append([b1.lerp(b2, (t - t1) / (t2 - t1)), lerpf(pts[i][1], pts[i + 1][1], float(k) / SUBDIV)])
	out.append(pts[n - 1])
	return out


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
