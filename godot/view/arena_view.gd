# 場地外觀（暫時版）：平面地面＋邊界石條；里程碑 5 換成 darkFantasy 的墓地場景。碰撞邊界由 World 決定
class_name ArenaView
extends Node3D

const GROUND_COLOR := Color("2b3528")
const BORDER_COLOR := Color("55585e")
const BORDER_WIDTH := 0.3
const BORDER_HEIGHT := 0.4


func build(half_size: float) -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (half_size + 14.0) * 2.0
	ground.mesh = plane
	ground.material_override = _mat(GROUND_COLOR)
	add_child(ground)

	var length := half_size * 2.0 + BORDER_WIDTH
	for side in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var border := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(BORDER_WIDTH, BORDER_HEIGHT, length) if side.x != 0 else Vector3(length, BORDER_HEIGHT, BORDER_WIDTH)
		border.mesh = box
		border.material_override = _mat(BORDER_COLOR)
		border.position = Vector3(side.x * (half_size + BORDER_WIDTH * 0.5), BORDER_HEIGHT * 0.5, side.y * (half_size + BORDER_WIDTH * 0.5))
		add_child(border)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m
