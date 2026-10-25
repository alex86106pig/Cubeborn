# 視野的淡入淡出（2026-10-26 使用者決定，像 Project Zomboid）：把一個模型的材質暫時改成半透明，完全顯示時還原
# 用材質的透明度、不用 GeometryInstance3D.transparency：後者網頁版（Compatibility）不支援
# 材質就地修改：角色的材質每隻各一份（受擊閃白、狀態染色也改同一份）；標了 SHARED 的共用材質先複製一份給這個模型
# 模式用「先畫深度再混色」：角色前後重疊的零件不會互相透出來；淡入淡出中不投影、不畫牆後剪影（WorldView 處理）
class_name Fade

const SHARED := &"fade_shared"   # 多個模型共用的材質加這個 meta（例如 SkinnedRig 的發光材質）
const MODE := BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS


# 套上顯示程度 a（0 = 看不到、1 = 完全顯示）；a = 1 時還原，回傳 true 代表這次還原了（呼叫端要把剪影接回去）
static func apply(root: Node3D, a: float) -> bool:
	if a >= 1.0:
		if not root.has_meta(&"fade"):
			return false
		_restore(root)
		return true
	if not root.has_meta(&"fade"):
		root.set_meta(&"fade", _collect(root))
	for entry: Array in root.get_meta(&"fade"):
		if entry[0] is Light3D:
			(entry[0] as Light3D).light_energy = entry[1] * a
		else:
			var m: BaseMaterial3D = entry[1]
			m.albedo_color.a = entry[3] * a
	return false


static func is_fading(root: Node) -> bool:
	return root.has_meta(&"fade")


# 記下每個材質原本的透明模式與 alpha、每盞燈原本的亮度，並把材質切成半透明；剪影（material_overlay）先拿掉
static func _collect(root: Node) -> Array:
	var out: Array = []
	for node in _descendants(root):
		if node is Light3D:
			out.append([node, (node as Light3D).light_energy])
		elif node is MeshInstance3D:
			var mi := node as MeshInstance3D
			mi.material_overlay = null
			var m := mi.material_override as BaseMaterial3D
			if m == null:
				continue
			if m.has_meta(SHARED):
				m = m.duplicate()
				m.remove_meta(SHARED)
				mi.material_override = m
			out.append([mi, m, m.transparency, m.albedo_color.a])
			if m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				m.transparency = MODE
	return out


static func _restore(root: Node) -> void:
	for entry: Array in root.get_meta(&"fade"):
		if entry[0] is Light3D:
			(entry[0] as Light3D).light_energy = entry[1]
		else:
			var m: BaseMaterial3D = entry[1]
			m.transparency = entry[2]
			m.albedo_color.a = entry[3]
	root.remove_meta(&"fade")


static func _descendants(node: Node, out: Array[Node] = []) -> Array[Node]:
	for child in node.get_children():
		out.append(child)
		_descendants(child, out)
	return out
