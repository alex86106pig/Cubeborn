# 視野的淡入淡出：模型的網格暫時換成半透明的材質，完全顯示時換回原本的
# 用材質的透明度、不用 GeometryInstance3D.transparency：後者網頁版（Compatibility）不支援
# 兩次繪製：先畫一次只寫深度（DEPTH_SHADER），再畫半透明的顏色（next_pass）。只有最前面的面畫得到顏色，
# 角色前後重疊的零件不會互相透出來（Godot 的 TRANSPARENCY_ALPHA_DEPTH_PRE_PASS 只在 alpha ≥ 0.99 時寫深度，淡入淡出時沒用）
# 半透明的材質全部共用一份快取：依原本材質的外觀（指紋）與透明程度（分 LEVELS 階）各建一個，開場預熱時建好；
# 淡入淡出時只換網格指向的材質，不改原本的材質、不新建材質（網頁版每次轉身新建 / 切換材質會卡）
# 淡入淡出中受擊閃白、狀態染色不更新（停在開始那一刻），不畫牆後剪影（WorldView 處理）
# 影子跟著淡（2026-10-27 使用者要求）：半透明的材質不會投影、影子圖也沒有「半透明」，第三次繪製（SHADOW_SHADER）只在畫影子時畫，
# 依透明度用 4×4 Bayer 抖動丟掉一部分像素（業界淡出物件影子的通用做法）；一般畫面全部丟掉。只跟階數有關，全部共用 LEVELS - 1 份
class_name Fade

const LEVELS := 8
const DEPTH_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_always, cull_back, blend_mix, shadows_disabled, fog_disabled;
void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
"""
const SHADOW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
uniform float coverage = 0.5;
void fragment() {
	if (!IN_SHADOW_PASS) {
		discard;
	}
	float bayer[16] = {0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0};
	ivec2 p = ivec2(FRAGCOORD.xy) % 4;
	if ((bayer[p.y * 4 + p.x] + 0.5) / 16.0 >= coverage) {
		discard;
	}
	ALBEDO = vec3(0.0);
}
"""
static var _depth_shader: Shader
static var _shadow_shader: Shader
static var _cache: Dictionary = {}   # "指紋|階" -> 只寫深度的 ShaderMaterial（next_pass = 半透明的材質，再 next_pass = 抖動影子）
static var _shadow_cache: Dictionary = {}   # 階 -> 抖動影子的 ShaderMaterial


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
	var level := level_of(a)
	if level == state.level:
		return false
	state.level = level
	for entry: Array in state.meshes:
		(entry[0] as MeshInstance3D).material_override = faded(entry[1], level)
	for entry: Array in state.lights:
		(entry[0] as Light3D).light_energy = entry[1] * level / LEVELS
	return false


static func is_fading(root: Node) -> bool:
	return root.has_meta(&"fade")


# 顯示程度 → 透明的階（1 ~ LEVELS - 1）；alpha = 階 / LEVELS
static func level_of(a: float) -> int:
	return clampi(roundi(a * LEVELS), 1, LEVELS - 1)


# 開場預熱：把這個模型每個材質的每一階都先建好
static func prepare(root: Node) -> void:
	for mi in PartKit.mesh_instances(root):
		var m := mi.material_override as BaseMaterial3D
		if m != null:
			for level in range(1, LEVELS):
				faded(m, level)


static func cache_size() -> int:
	return _cache.size()


# 記下每個網格原本的材質、每盞燈原本的亮度；剪影（material_overlay）先拿掉
static func _collect(root: Node) -> Dictionary:
	var state := {"level": 0, "meshes": [], "lights": []}
	for node in _descendants(root):
		if node is Light3D:
			state.lights.append([node, (node as Light3D).light_energy])
		elif node is MeshInstance3D:
			var mi := node as MeshInstance3D
			mi.material_overlay = null
			if mi.material_override is BaseMaterial3D:
				state.meshes.append([mi, mi.material_override])
	return state


static func _restore(root: Node) -> void:
	var state: Dictionary = root.get_meta(&"fade")
	for entry: Array in state.meshes:
		(entry[0] as MeshInstance3D).material_override = entry[1]
	for entry: Array in state.lights:
		(entry[0] as Light3D).light_energy = entry[1]
	root.remove_meta(&"fade")


# 原本的材質 m 在第 level 階的半透明版本（只寫深度 → 半透明的顏色）；沒有就建一個放進快取
static func faded(m: BaseMaterial3D, level: int) -> ShaderMaterial:
	var key := "%s|%d" % [_fingerprint(m), level]
	if not _cache.has(key):
		var f: BaseMaterial3D = m.duplicate()
		if f.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			f.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		f.albedo_color.a = m.albedo_color.a * level / LEVELS
		f.emission = _flash_free(m.emission)
		f.render_priority = 1   # 半透明的顏色排在所有「只寫深度」之後畫
		if _depth_shader == null:
			_depth_shader = Shader.new()
			_depth_shader.code = DEPTH_SHADER
		f.next_pass = _shadow(level)
		var dm := ShaderMaterial.new()
		dm.shader = _depth_shader
		dm.next_pass = f
		_cache[key] = dm
	return _cache[key]


# 第 level 階的抖動影子：影子圖裡畫 level / LEVELS 的像素
static func _shadow(level: int) -> ShaderMaterial:
	if not _shadow_cache.has(level):
		if _shadow_shader == null:
			_shadow_shader = Shader.new()
			_shadow_shader.code = SHADOW_SHADER
		var sm := ShaderMaterial.new()
		sm.shader = _shadow_shader
		sm.set_shader_parameter(&"coverage", float(level) / LEVELS)
		_shadow_cache[level] = sm
	return _shadow_cache[level]


# 外觀相同的材質（同種怪每隻各一份的材質）共用同一組半透明版本
static func _fingerprint(m: BaseMaterial3D) -> String:
	return "%s|%d|%d|%d|%d|%d|%.2f|%d|%s|%.2f|%d|%d" % [
		m.albedo_color.to_html(), m.shading_mode, int(m.vertex_color_use_as_albedo), int(m.vertex_color_is_srgb),
		m.diffuse_mode, m.specular_mode, m.roughness, int(m.emission_enabled), _flash_free(m.emission).to_html(false),
		m.emission_energy_multiplier, m.transparency, m.cull_mode]


# 自發光量化成 0.1 一階：受擊閃白是把自發光連續調成灰白（PartKit.set_flash），不量化的話快取會越來越多
static func _flash_free(c: Color) -> Color:
	return Color(snappedf(c.r, 0.1), snappedf(c.g, 0.1), snappedf(c.b, 0.1))


static func _descendants(node: Node, out: Array[Node] = []) -> Array[Node]:
	for child in node.get_children():
		out.append(child)
		_descendants(child, out)
	return out
