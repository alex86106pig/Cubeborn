# 壓力測試：大量敵人與投射物，量測 GDScript 資料導向寫法的效能
# 寫法：資料放在 Packed 陣列集中處理；碰撞用格子切分；畫面用 MultiMesh 一次繪製
# 指令列參數（放在 -- 之後）：--enemies=N --projectiles=N --seconds=S --autoquit --screenshot=路徑 --vsync
extends Node3D

const ARENA_HALF := 40.0
const CELL := 2.0
const GRID := int(ARENA_HALF * 2.0 / CELL)
const ENEMY_RADIUS := 0.4
const ENEMY_SPEED := 3.0
const ENEMY_HP := 3
const PROJ_SPEED := 18.0
const PROJ_LIFE := 2.2
const PROJ_RADIUS := 0.15
const WARMUP := 2.0

var enemy_n := 2000
var proj_n := 3000
var run_seconds := 10.0
var autoquit := false
var screenshot_path := ""

# 敵人資料
var ex := PackedFloat32Array()
var ez := PackedFloat32Array()
var evx := PackedFloat32Array()
var evz := PackedFloat32Array()
var ehp := PackedInt32Array()
var ecell := PackedInt32Array()
# 投射物資料
var px := PackedFloat32Array()
var pz := PackedFloat32Array()
var pvx := PackedFloat32Array()
var pvz := PackedFloat32Array()
var plife := PackedFloat32Array()
# 格子（counting sort）
var cell_start := PackedInt32Array()
var cell_items := PackedInt32Array()
var cell_cursor := PackedInt32Array()
# 繪製
var enemy_mm: MultiMesh
var proj_mm: MultiMesh
var enemy_buf := PackedFloat32Array()
var proj_buf := PackedFloat32Array()

var player := Vector2.ZERO
var elapsed := 0.0
var kills := 0
var frame_times: Array[float] = []
var logic_us := {"move": 0, "grid": 0, "separate": 0, "projectiles": 0, "upload": 0}
var logic_frames := 0
var label: Label
var label_timer := 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	_parse_args()
	rng.seed = 12345
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if "--vsync" in OS.get_cmdline_user_args() else DisplayServer.VSYNC_DISABLED)
	_build_scene()
	_init_data()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--enemies="):
			enemy_n = int(arg.get_slice("=", 1))
		elif arg.begins_with("--projectiles="):
			proj_n = int(arg.get_slice("=", 1))
		elif arg.begins_with("--seconds="):
			run_seconds = float(arg.get_slice("=", 1))
		elif arg == "--autoquit":
			autoquit = true
		elif arg.begins_with("--screenshot="):
			screenshot_path = arg.get_slice("=", 1)


func _build_scene() -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ARENA_HALF * 2.1
	cam.position = Vector3(45, 60, 45)
	add_child(cam)
	cam.look_at(Vector3.ZERO)

	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-55, 35, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.055, 0.07, 0.125)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.6, 0.75)
	add_child(env)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ARENA_HALF * 2.0, ARENA_HALF * 2.0)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.17, 0.21, 0.16)
	plane.material = ground_mat
	ground.mesh = plane
	add_child(ground)

	var body := CapsuleMesh.new()
	body.radius = 0.35
	body.height = 1.6
	body.radial_segments = 6
	body.rings = 1
	var enemy_mat := StandardMaterial3D.new()
	enemy_mat.albedo_color = Color(0.85, 0.82, 0.75)
	body.material = enemy_mat
	enemy_mm = _make_multimesh(body, enemy_n, true)

	var bolt := SphereMesh.new()
	bolt.radius = PROJ_RADIUS
	bolt.height = PROJ_RADIUS * 2.0
	bolt.radial_segments = 6
	bolt.rings = 3
	var bolt_mat := StandardMaterial3D.new()
	bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bolt_mat.albedo_color = Color(0.7, 0.55, 1.0)
	bolt.material = bolt_mat
	proj_mm = _make_multimesh(bolt, proj_n, false)

	var layer := CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(16, 16)
	label.add_theme_font_size_override("font_size", 20)
	layer.add_child(label)


func _make_multimesh(mesh: Mesh, count: int, shadows: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 實例分布在整個場地，關閉逐實例剔除的外框計算
	inst.custom_aabb = AABB(Vector3(-ARENA_HALF, -1, -ARENA_HALF), Vector3(ARENA_HALF * 2, 4, ARENA_HALF * 2))
	add_child(inst)
	return mm


func _init_data() -> void:
	# Packed 陣列是值型別，必須逐一對成員呼叫 resize
	ex.resize(enemy_n)
	ez.resize(enemy_n)
	evx.resize(enemy_n)
	evz.resize(enemy_n)
	ehp.resize(enemy_n)
	ecell.resize(enemy_n)
	for i in enemy_n:
		_respawn_enemy(i)
		ex[i] = rng.randf_range(-ARENA_HALF, ARENA_HALF)
		ez[i] = rng.randf_range(-ARENA_HALF, ARENA_HALF)
	px.resize(proj_n)
	pz.resize(proj_n)
	pvx.resize(proj_n)
	pvz.resize(proj_n)
	plife.resize(proj_n)
	for i in proj_n:
		_respawn_projectile(i)
		plife[i] = rng.randf() * PROJ_LIFE
	cell_start.resize(GRID * GRID + 1)
	cell_cursor.resize(GRID * GRID)
	cell_items.resize(enemy_n)
	enemy_buf.resize(enemy_n * 12)
	proj_buf.resize(proj_n * 12)


func _respawn_enemy(i: int) -> void:
	var side := rng.randi_range(0, 3)
	var t := rng.randf_range(-ARENA_HALF, ARENA_HALF)
	var edge := ARENA_HALF - 0.5
	match side:
		0: ex[i] = t; ez[i] = -edge
		1: ex[i] = t; ez[i] = edge
		2: ex[i] = -edge; ez[i] = t
		_: ex[i] = edge; ez[i] = t
	ehp[i] = ENEMY_HP


func _respawn_projectile(i: int) -> void:
	var a := rng.randf() * TAU
	px[i] = player.x
	pz[i] = player.y
	pvx[i] = sin(a) * PROJ_SPEED
	pvz[i] = cos(a) * PROJ_SPEED
	plife[i] = PROJ_LIFE


func _process(delta: float) -> void:
	elapsed += delta
	player = Vector2(cos(elapsed * 0.5), sin(elapsed * 0.5)) * 10.0
	var measuring := elapsed > WARMUP

	var t0 := Time.get_ticks_usec()
	_move_enemies(delta)
	var t1 := Time.get_ticks_usec()
	_build_grid()
	var t2 := Time.get_ticks_usec()
	_separate_enemies()
	var t3 := Time.get_ticks_usec()
	_update_projectiles(delta)
	var t4 := Time.get_ticks_usec()
	_upload()
	var t5 := Time.get_ticks_usec()

	if measuring:
		frame_times.append(delta)
		logic_us.move += t1 - t0
		logic_us.grid += t2 - t1
		logic_us.separate += t3 - t2
		logic_us.projectiles += t4 - t3
		logic_us.upload += t5 - t4
		logic_frames += 1

	label_timer += delta
	if label_timer >= 0.5:
		label_timer = 0.0
		label.text = "FPS %d  |  敵人 %d  投射物 %d  |  邏輯 %.2f ms/幀  |  擊殺 %d" % [
			Engine.get_frames_per_second(), enemy_n, proj_n, (t5 - t0) / 1000.0, kills]

	if screenshot_path != "" and elapsed > WARMUP + 1.0:
		get_viewport().get_texture().get_image().save_png(screenshot_path)
		screenshot_path = ""
	if elapsed > WARMUP + run_seconds and logic_frames > 0:
		_report()
		if autoquit:
			get_tree().quit()
		else:
			set_process(false)


func _move_enemies(delta: float) -> void:
	var tx := player.x
	var tz := player.y
	for i in enemy_n:
		var dx := tx - ex[i]
		var dz := tz - ez[i]
		var d := sqrt(dx * dx + dz * dz) + 0.0001
		evx[i] = dx / d * ENEMY_SPEED
		evz[i] = dz / d * ENEMY_SPEED
		ex[i] = clampf(ex[i] + evx[i] * delta, -ARENA_HALF + 0.1, ARENA_HALF - 0.1)
		ez[i] = clampf(ez[i] + evz[i] * delta, -ARENA_HALF + 0.1, ARENA_HALF - 0.1)


func _cell_of(x: float, z: float) -> int:
	var cx := clampi(int((x + ARENA_HALF) / CELL), 0, GRID - 1)
	var cz := clampi(int((z + ARENA_HALF) / CELL), 0, GRID - 1)
	return cz * GRID + cx


# counting sort：cell_items 依格子排列，cell_start[c]..cell_start[c+1] 是第 c 格的敵人
func _build_grid() -> void:
	cell_start.fill(0)
	for i in enemy_n:
		var c := _cell_of(ex[i], ez[i])
		ecell[i] = c
		cell_start[c + 1] += 1
	for c in GRID * GRID:
		cell_start[c + 1] += cell_start[c]
	for c in GRID * GRID:
		cell_cursor[c] = cell_start[c]
	for i in enemy_n:
		var c := ecell[i]
		cell_items[cell_cursor[c]] = i
		cell_cursor[c] += 1


func _separate_enemies() -> void:
	var min_d := ENEMY_RADIUS * 2.0
	var min_d2 := min_d * min_d
	for i in enemy_n:
		var c := ecell[i]
		var cx := c % GRID
		var cz := c / GRID
		var push_x := 0.0
		var push_z := 0.0
		for gz in range(maxi(cz - 1, 0), mini(cz + 2, GRID)):
			for gx in range(maxi(cx - 1, 0), mini(cx + 2, GRID)):
				var g := gz * GRID + gx
				for k in range(cell_start[g], cell_start[g + 1]):
					var j := cell_items[k]
					if j == i:
						continue
					var dx := ex[i] - ex[j]
					var dz := ez[i] - ez[j]
					var d2 := dx * dx + dz * dz
					if d2 < min_d2 and d2 > 0.000001:
						var d := sqrt(d2)
						var push := (min_d - d) * 0.5 / d
						push_x += dx * push
						push_z += dz * push
		ex[i] += push_x
		ez[i] += push_z


func _update_projectiles(delta: float) -> void:
	var hit_d := ENEMY_RADIUS + PROJ_RADIUS
	var hit_d2 := hit_d * hit_d
	for i in proj_n:
		plife[i] -= delta
		if plife[i] <= 0.0:
			_respawn_projectile(i)
			continue
		px[i] += pvx[i] * delta
		pz[i] += pvz[i] * delta
		if absf(px[i]) > ARENA_HALF or absf(pz[i]) > ARENA_HALF:
			_respawn_projectile(i)
			continue
		var c := _cell_of(px[i], pz[i])
		var cx := c % GRID
		var cz := c / GRID
		var hit := false
		for gz in range(maxi(cz - 1, 0), mini(cz + 2, GRID)):
			for gx in range(maxi(cx - 1, 0), mini(cx + 2, GRID)):
				var g := gz * GRID + gx
				for k in range(cell_start[g], cell_start[g + 1]):
					var j := cell_items[k]
					var dx := px[i] - ex[j]
					var dz := pz[i] - ez[j]
					if dx * dx + dz * dz < hit_d2:
						ehp[j] -= 1
						if ehp[j] <= 0:
							kills += 1
							_respawn_enemy(j)
						hit = true
						break
				if hit:
					break
			if hit:
				break
		if hit:
			_respawn_projectile(i)


# 直接寫入 MultiMesh 緩衝區（每個實例 12 個 float：3x4 矩陣，逐列）
func _upload() -> void:
	var b := enemy_buf
	for i in enemy_n:
		var a := atan2(evx[i], evz[i])
		var s := sin(a)
		var co := cos(a)
		var o := i * 12
		b[o] = co; b[o + 1] = 0.0; b[o + 2] = s; b[o + 3] = ex[i]
		b[o + 4] = 0.0; b[o + 5] = 1.0; b[o + 6] = 0.0; b[o + 7] = 0.8
		b[o + 8] = -s; b[o + 9] = 0.0; b[o + 10] = co; b[o + 11] = ez[i]
	RenderingServer.multimesh_set_buffer(enemy_mm.get_rid(), b)
	var p := proj_buf
	for i in proj_n:
		var o := i * 12
		p[o] = 1.0; p[o + 1] = 0.0; p[o + 2] = 0.0; p[o + 3] = px[i]
		p[o + 4] = 0.0; p[o + 5] = 1.0; p[o + 6] = 0.0; p[o + 7] = 1.0
		p[o + 8] = 0.0; p[o + 9] = 0.0; p[o + 10] = 1.0; p[o + 11] = pz[i]
	RenderingServer.multimesh_set_buffer(proj_mm.get_rid(), p)


func _report() -> void:
	var sorted := frame_times.duplicate()
	sorted.sort()
	var total := 0.0
	for t in frame_times:
		total += t
	var n := frame_times.size()
	var avg_ms := total / n * 1000.0
	var p95_ms: float = sorted[int(n * 0.95)] * 1000.0
	var p99_ms: float = sorted[mini(int(n * 0.99), n - 1)] * 1000.0
	print("RESULT enemies=%d projectiles=%d frames=%d" % [enemy_n, proj_n, n])
	print("RESULT avg_fps=%.1f avg_frame_ms=%.2f p95_frame_ms=%.2f p99_frame_ms=%.2f" % [1000.0 / avg_ms, avg_ms, p95_ms, p99_ms])
	var parts := []
	var logic_total := 0.0
	for key in logic_us:
		var ms: float = logic_us[key] / 1000.0 / logic_frames
		logic_total += ms
		parts.append("%s=%.2f" % [key, ms])
	print("RESULT logic_ms_per_frame total=%.2f %s" % [logic_total, " ".join(parts)])
	print("RESULT draw_calls=%d kills=%d" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), kills])
	label.text += "\n測試完成：平均 FPS %.1f，最差 5%% 幀 %.2f ms，邏輯 %.2f ms/幀" % [1000.0 / avg_ms, p95_ms, logic_total]
