# 動作表（除錯用，--pose-test=表名，網頁版 ?pose-test=表名）：檢查角色動作有沒有怪的地方。
# 用真的模擬跑一段（玩家照按鍵、怪物照 AI 或強制出招），錄下每一步的 anim，再把同一個動作的 8 個時間點並排：
# 一列 = 一個動作，一格 = 一個時間點（每格各自一隻角色，從頭重播到那一步，動畫器的平滑也算進去）。
# 表名：player-<武器 id>（待機、跑、普攻、右鍵、翻滾、跳、喝藥水、受擊、倒地）、skills-1~3（18 招戰技）、enemy-<種類>（AI 的每個狀態 + Boss 每一招）。
# 表名後面加 @起-迄 只畫那幾列（從 0 數，例：player-shovel@0-2），格子比較大。
# --pose-view=side（預設，從角色右側看，看得到手肘膝蓋）/ front（右前方斜看）。畫好後印 "pose ready rows=N"
class_name PoseGallery
extends Node3D

const COLS := AnimRecorder.COLS
const DT := Config.FIXED_DT

var _sheet := ""
var _range := Vector2i(0, 999)
var _view := "side"
var _recorder := AnimRecorder.new()


func _init(sheet: String, view: String) -> void:
	_sheet = sheet.get_slice("@", 0)
	if sheet.contains("@"):
		var r := sheet.get_slice("@", 1)
		_range = Vector2i(r.get_slice("-", 0).to_int(), r.get_slice("-", 1).to_int() if r.contains("-") else r.to_int())
	_view = view if view in ["side", "front"] else "side"


func _ready() -> void:
	var rows := _recorder.rows(_sheet, false).slice(_range.x, _range.y + 1)
	_layout(rows)
	_recorder.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	print("pose ready rows=%d sheet=%s view=%s" % [rows.size(), _sheet, _view])


# ───────── 排版 ─────────

func _layout(rows: Array) -> void:
	var tallest := 2.2
	var cells := []   # [row, col, rig]
	for r in rows.size():
		var row: Dictionary = rows[r]
		for c in (row.samples as Array).size():
			var made: Dictionary = (row.make as Callable).call()
			var rig: Node3D = made.rig
			add_child(rig)
			AnimRecorder.replay(row, made, row.samples[c])
			if rig is Rig:
				tallest = maxf(tallest, (rig as Rig).height)
			elif rig is SkinnedRig:
				tallest = maxf(tallest, (rig as SkinnedRig).height)
			cells.append([r, c, rig])
	var cell_h := tallest * 1.35
	var cell_w := tallest * 1.05
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var fwd := Vector3(1.0, -0.12, 0.0) if _view == "side" else Vector3(0.55, -0.3, -1.0)   # side：從角色右側（-X）往 +X 看，臉朝畫面右邊
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	for cell: Array in cells:
		var rig: Node3D = cell[2]
		rig.position = right * (cell[1] * cell_w) + Vector3.UP * (-cell[0] * cell_h)
		var slab := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(cell_w * 0.9, 0.04, cell_w * 0.9)
		slab.mesh = box
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.35, 0.36, 0.33) if (cell[0] + cell[1]) % 2 == 0 else Color(0.3, 0.31, 0.29)
		slab.material_override = m
		slab.position = rig.position + Vector3(0.0, -0.02, 0.0)
		add_child(slab)
	for r in rows.size():
		var label := Label3D.new()
		label.text = rows[r].key   # 英文 id：Label3D 的預設字型在網頁版沒有中文
		label.pixel_size = tallest * 0.0045
		label.font_size = 40
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(1.0, 0.92, 0.6)
		label.outline_size = 8
		label.position = right * (-cell_w * 0.9) + Vector3.UP * (-r * cell_h + tallest * 0.5)
		add_child(label)
	var width := cell_w * (COLS + 1.2)
	var height := cell_h * maxf(rows.size(), 1.0)
	var aspect := 16.0 / 9.0
	cam.size = maxf(height, width / aspect) * 1.02
	var center := right * (cell_w * (COLS - 1.6) / 2.0) + Vector3.UP * (-(rows.size() - 1) * cell_h / 2.0 + tallest * 0.45)
	cam.far = 100.0
	add_child(cam)
	cam.look_at_from_position(center - fwd * 30.0, center, Vector3.UP)
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, -0.6 if _view == "side" else 0.4, 0.0)
	sun.light_energy = 1.1
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.13, 0.14, 0.17)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
