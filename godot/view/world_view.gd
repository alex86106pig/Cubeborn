# 畫面層：依實體 id 建立 / 移除模型並補間位置；燈光與背景（模型暫用方塊，里程碑 5 換成 Rig）
class_name WorldView
extends Node3D

const HITBOX_COLOR := Color(1.0, 0.93, 0.0, 0.8)

var show_hitboxes := false
var _nodes: Dictionary = {}   # entity id -> Node3D


func _ready() -> void:
	_setup_environment()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Config.ENVIRONMENT.background
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Config.ENVIRONMENT.hemi_sky.lerp(Config.ENVIRONMENT.hemi_ground, 0.35)
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_color = Config.ENVIRONMENT.sun_color
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	sun.look_at_from_position(Vector3(-10.0, 22.0, 8.0), Vector3.ZERO)


# alpha：上一步到這一步之間的補間比例（0~1）
func sync(world: World, alpha: float) -> void:
	for id: int in _nodes.keys():
		if not world.entities.has(id):
			_nodes[id].queue_free()
			_nodes.erase(id)
	for id: int in world.entities:
		var e: Entity = world.entities[id]
		if not _nodes.has(id):
			_nodes[id] = _create_placeholder(e)
		var node: Node3D = _nodes[id]
		var p := e.prev_pos.lerp(e.pos, alpha)
		node.position = Vector3(p.x, 0.0, p.y)
		node.rotation.y = lerp_angle(e.prev_facing, e.facing, alpha)
		node.get_node(^"Hitbox").visible = show_hitboxes


func _create_placeholder(e: Entity) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(e.radius * 2.0, 1.8, e.radius * 1.4)
	body.mesh = box
	body.position.y = 0.9
	body.material_override = _mat(Color("6f86b8"))
	root.add_child(body)

	var nose := MeshInstance3D.new()   # 標示面向（+Z）
	var nose_box := BoxMesh.new()
	nose_box.size = Vector3(0.2, 0.2, 0.4)
	nose.mesh = nose_box
	nose.position = Vector3(0.0, 1.4, e.radius * 0.7 + 0.2)
	nose.material_override = _mat(Color("dfe8ff"))
	root.add_child(nose)

	var ring := MeshInstance3D.new()
	ring.name = &"Hitbox"
	var torus := TorusMesh.new()
	torus.inner_radius = e.radius * 0.92
	torus.outer_radius = e.radius
	torus.rings = 32
	ring.mesh = torus
	ring.scale.y = 0.05
	ring.position.y = 0.03
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = HITBOX_COLOR
	ring.material_override = ring_mat
	root.add_child(ring)

	add_child(root)
	return root


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m
