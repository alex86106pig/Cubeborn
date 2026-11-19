# 骰子模式的戰場霧牆（畫面層；docs/系統說明.md §55「霧牆」）：照 World.dice 的 arena_center / arena_radius 畫一圈半透明的霧
# 下面濃、往上淡、繞著圈慢慢流動；開打時淡入、打完淡出。碰撞（出不去、圈外的怪不會發現）在模擬層 DiceRun
class_name DiceArenaView
extends Node3D

const HEIGHT := 3.2
const FADE_TIME := 0.5
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.84, 0.87, 0.92, 1.0);
uniform float strength = 0.0;
void fragment() {
	float low = pow(clamp(UV.y, 0.0, 1.0), 1.4);
	float a = sin(UV.x * 50.0 + TIME * 0.7 + UV.y * 4.0) * 0.5 + 0.5;
	float b = sin(UV.x * 21.0 - TIME * 0.45 - UV.y * 7.0) * 0.5 + 0.5;
	ALBEDO = tint.rgb;
	ALPHA = strength * low * (0.55 + 0.4 * a * b);
}
"""

var strength := 0.0   # 現在的濃度（0~1，檢查讀）
var _mesh := MeshInstance3D.new()
var _mat := ShaderMaterial.new()


func _init() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = HEIGHT
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 96
	cyl.rings = 1
	var shader := Shader.new()
	shader.code = SHADER
	_mat.shader = shader
	cyl.material = _mat
	_mesh.mesh = cyl
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.position.y = HEIGHT / 2.0 - 0.2
	add_child(_mesh)
	visible = false


# 每幀（WorldView.sync）：有霧牆就移到圈上、淡入；沒有就淡出（停在原地）
func sync(world: World, dt: float) -> void:
	var dice := world.dice if world != null else null
	var on := dice != null and dice.arena_radius > 0.0
	if on:
		position = Vector3(dice.arena_center.x, 0.0, dice.arena_center.y)
		scale = Vector3(dice.arena_radius, 1.0, dice.arena_radius)
	strength = move_toward(strength, 1.0 if on else 0.0, dt / FADE_TIME)
	visible = strength > 0.0
	_mat.set_shader_parameter(&"strength", strength)


func clear() -> void:
	strength = 0.0
	visible = false
