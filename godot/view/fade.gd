# 視野的淡入淡出：把一個模型的材質暫時改成半透明，完全顯示時還原
# 用材質的透明度、不用 GeometryInstance3D.transparency：後者網頁版（Compatibility）不支援
# 兩次繪製：先畫一次只寫深度（DEPTH_SHADER），再畫原本的材質（next_pass，半透明）。只有最前面的面畫得到顏色，
# 角色前後重疊的零件不會互相透出來（Godot 的 TRANSPARENCY_ALPHA_DEPTH_PRE_PASS 只在 alpha ≥ 0.99 時寫深度，淡入淡出時沒用）
# 材質就地修改：角色的材質每隻各一份（受擊閃白、狀態染色也改同一份）；標了 SHARED 的共用材質先複製一份給這個模型
# 同一個模型的好幾個網格常共用一個材質（寶箱的木頭、角色的盔甲），原本的設定每個材質只記一次
# 淡入淡出中不投影、不畫牆後剪影（WorldView 處理）
class_name Fade

const SHARED := &"fade_shared"   # 多個模型共用的材質加這個 meta（例如 SkinnedRig 的發光材質）
const DEPTH_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_always, cull_back, blend_mix, shadows_disabled, fog_disabled;
void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
"""
static var _depth_shader: Shader


# 套上顯示程度 a（0 = 看不到、1 = 完全顯示）；a = 1 時還原，回傳 true 代表這次還原了（呼叫端要把剪影接回去）
static func apply(root: Node3D, a: float) -> bool:
	if a >= 1.0:
		if not root.has_meta(&"fade"):
			return false
		_restore(root)
		return true
	if not root.has_meta(&"fade"):
		root.set_meta(&"fade", _collect(root))
	var state: Dictionary = root.get_meta(&"fade")
	for entry: Array in state.lights:
		(entry[0] as Light3D).light_energy = entry[1] * a
	for entry: Array in state.materials:
		(entry[0] as BaseMaterial3D).albedo_color.a = entry[2] * a
	return false


static func is_fading(root: Node) -> bool:
	return root.has_meta(&"fade")


# 記下燈原本的亮度、每個材質原本的透明模式與 alpha、每個網格原本的材質；網格換成「只寫深度 → 原本的材質（半透明）」；
# 剪影（material_overlay）先拿掉
static func _collect(root: Node) -> Dictionary:
	var state := {"lights": [], "materials": [], "meshes": []}
	var depth_of := {}    # 材質 -> 它的只寫深度那一次（同一個模型裡共用）
	var copy_of := {}     # 共用材質 -> 這個模型自己的複本
	for node in _descendants(root):
		if node is Light3D:
			state.lights.append([node, (node as Light3D).light_energy])
		elif node is MeshInstance3D:
			var mi := node as MeshInstance3D
			mi.material_overlay = null
			var m := mi.material_override as BaseMaterial3D
			if m == null:
				continue
			if m.has_meta(SHARED):
				if not copy_of.has(m):
					var own: BaseMaterial3D = m.duplicate()
					own.remove_meta(SHARED)
					copy_of[m] = own
				m = copy_of[m]
			if not depth_of.has(m):
				state.materials.append([m, m.transparency, m.albedo_color.a, m.render_priority])
				if m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.render_priority = 1   # 半透明的顏色排在所有「只寫深度」之後畫
				depth_of[m] = _depth_pass(m)
			state.meshes.append([mi, m])
			mi.material_override = depth_of[m]
	return state


static func _restore(root: Node) -> void:
	var state: Dictionary = root.get_meta(&"fade")
	for entry: Array in state.lights:
		(entry[0] as Light3D).light_energy = entry[1]
	for entry: Array in state.materials:
		var m: BaseMaterial3D = entry[0]
		m.transparency = entry[1]
		m.albedo_color.a = entry[2]
		m.render_priority = entry[3]
	for entry: Array in state.meshes:
		(entry[0] as MeshInstance3D).material_override = entry[1]
	root.remove_meta(&"fade")


# 只寫深度的那一次：每次開始淡入淡出時新建（記在材質上會和 next_pass 互相參照、釋放不掉）；Shader 共用，只編譯一次
static func _depth_pass(m: BaseMaterial3D) -> ShaderMaterial:
	if _depth_shader == null:
		_depth_shader = Shader.new()
		_depth_shader.code = DEPTH_SHADER
	var dm := ShaderMaterial.new()
	dm.shader = _depth_shader
	dm.next_pass = m
	return dm


static func _descendants(node: Node, out: Array[Node] = []) -> Array[Node]:
	for child in node.get_children():
		out.append(child)
		_descendants(child, out)
	return out
