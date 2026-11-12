# 動作表（除錯用，--pose-test=表名，網頁版 ?pose-test=表名）：檢查角色動作有沒有怪的地方。
# 用真的模擬跑一段（玩家照按鍵、怪物照 AI 或強制出招），錄下每一步的 anim，再把同一個動作的 8 個時間點並排：
# 一列 = 一個動作，一格 = 一個時間點（每格各自一隻角色，從頭重播到那一步，動畫器的平滑也算進去）。
# 表名：player-<武器 id>（待機、跑、普攻、右鍵、翻滾、跳、喝藥水、受擊、倒地）、skills-1~3（18 招戰技）、enemy-<種類>（AI 的每個狀態 + Boss 每一招）。
# 表名後面加 @起-迄 只畫那幾列（從 0 數，例：player-shovel@0-2），格子比較大。
# --pose-view=side（預設，從角色右側看，看得到手肘膝蓋）/ front（右前方斜看）。畫好後印 "pose ready rows=N"
class_name PoseGallery
extends Node3D

const COLS := 8
const DT := Config.FIXED_DT
const PLAYER_WEAPONS: Array[StringName] = [&"swordShield", &"staff", &"shortbow", &"longbow", &"dagger", &"scepter", &"torch", &"shovel"]
const ENEMY_KINDS: Array[StringName] = [&"grunt", &"archer", &"spearman", &"zombie", &"bloater", &"hound", &"spider", &"beetle", &"bone_wheel", &"boss", &"gravekeeper", &"werewolf", &"bone_general", &"bone_colossus"]
const BOSS_MOVES := {
	&"boss": [0, [&"slam", &"charge", &"summon", &"cleave"]],
	&"gravekeeper": [0, [&"shovel", &"dig", &"lantern", &"whistle", &"scoop"]],
	&"werewolf": [1, [&"claw", &"leap", &"howl"]],
	&"bone_general": [0, [&"slam", &"charge", &"cleave"]],
	&"bone_colossus": [1, [&"spikes", &"sweep", &"wheel", &"devour"]],
}
const BOSS_KIND := {&"werewolf": &"gravekeeper", &"bone_colossus": &"bone_general"}
const SKILLS_PER_SHEET := 6

var _sheet := ""
var _range := Vector2i(0, 999)
var _view := "side"
var _worlds: Array[World] = []


func _init(sheet: String, view: String) -> void:
	_sheet = sheet.get_slice("@", 0)
	if sheet.contains("@"):
		var r := sheet.get_slice("@", 1)
		_range = Vector2i(r.get_slice("-", 0).to_int(), r.get_slice("-", 1).to_int() if r.contains("-") else r.to_int())
	_view = view if view in ["side", "front"] else "side"


func _ready() -> void:
	var rows := _rows().slice(_range.x, _range.y + 1)
	_layout(rows)
	for w in _worlds:
		w.clear()
	_worlds.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	print("pose ready rows=%d sheet=%s view=%s" % [rows.size(), _sheet, _view])


# 每列：{ name, make（Callable → 一隻新的角色 {rig, anim}）, subject（Player / Enemy）, frames（[{anim, vel}]）, samples（取哪幾步） }
func _rows() -> Array:
	if _sheet.begins_with("player-"):
		return _player_rows(StringName(_sheet.trim_prefix("player-")))
	if _sheet.begins_with("skills-"):
		return _skill_rows(_sheet.trim_prefix("skills-").to_int())
	if _sheet.begins_with("enemy-"):
		return _enemy_rows(StringName(_sheet.trim_prefix("enemy-")))
	push_warning("pose-test：沒有這張表 %s" % _sheet)
	return []


func _new_world() -> World:
	var w := World.new(&"test_arena")
	w.spawn_packs = false
	w.reset(7)
	w.spawner.finished = true
	_worlds.append(w)
	return w


static func _cmd(move: Vector2, buttons: int = 0) -> InputCmd:
	var c := InputCmd.new()
	c.move = move
	c.aim = Vector2(0, 5)
	c.buttons = buttons
	return c


func _player(w: World, weapon: StringName) -> Player:
	var p: Player = w.players[World.HOST_PEER_ID]
	p.equip_weapon(weapon)
	p.stats.set_base(&"max_hp", 1e6)
	p.hp = 1e6
	return p


# 跑 steps 步、每步錄下 anim 與速度；cmd(i) 給第 i 步的輸入
static func _record(w: World, e: Entity, steps: int, cmd: Callable) -> Array:
	var out := []
	for i in steps:
		var c: InputCmd = cmd.call(i)
		w.step({World.HOST_PEER_ID: c}, DT)
		out.append({"anim": e.anim.duplicate(true), "vel": e.velocity})
	return out


static func _even(from: int, to: int) -> Array[int]:
	var out: Array[int] = []
	for c in COLS:
		out.append(from + roundi((to - from) * float(c) / (COLS - 1)))
	return out


# ───────── 玩家 ─────────

func _player_rows(weapon: StringName) -> Array:
	var rows := []
	var specs := [
		["idle", 40, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO)],
		["run", 60, func(_i: int) -> InputCmd: return _cmd(Vector2(0, 1))],
		["sprint", 60, func(i: int) -> InputCmd: return _cmd(Vector2(0, 1), InputCmd.BTN_RUN if i == 0 else 0)],
		["attack", 100, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO, InputCmd.BTN_ATTACK)],
		["attack+move", 80, func(_i: int) -> InputCmd: return _cmd(Vector2(1, 0), InputCmd.BTN_ATTACK)],
		["special", 70, func(i: int) -> InputCmd: return _cmd(Vector2.ZERO, (InputCmd.BTN_SPECIAL | InputCmd.BTN_SPECIAL_HELD) if i < 2 else 0)],
		["roll", 40, func(i: int) -> InputCmd: return _cmd(Vector2(0, 1), InputCmd.BTN_ROLL if i == 2 else 0)],
		["jump", 50, func(i: int) -> InputCmd: return _cmd(Vector2.ZERO, InputCmd.BTN_JUMP if i == 2 else 0)],
		["potion", 45, func(i: int) -> InputCmd: return _cmd(Vector2.ZERO, InputCmd.slot_bit(ActiveSlots.HEAL_INDEX) if i == 2 else 0)],
	]
	for spec: Array in specs:
		var w := _new_world()
		var p := _player(w, weapon)
		if spec[0] == "potion":
			p.hp = p.max_hp * 0.5
		_record(w, p, 20, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))   # 先站穩
		var frames := _record(w, p, spec[1], spec[2])
		rows.append(_player_row(spec[0], p, frames, _even(0, frames.size() - 1)))
	for extra: String in ["stagger", "knocked", "dead"]:
		var w := _new_world()
		var p := _player(w, weapon)
		_record(w, p, 20, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))
		match extra:
			"stagger":
				p.action.change(&"stagger")
			"knocked":
				p.knock_down(1.0)
			"dead":
				p.hp = 0.0
				p.die(0)
		var frames := _record(w, p, 45, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))
		rows.append(_player_row(extra, p, frames, _even(0, frames.size() - 1)))
	return rows


func _player_row(name: String, p: Player, frames: Array, samples: Array[int]) -> Dictionary:
	return {"name": name, "subject": p, "frames": frames, "samples": samples,
		"make": func() -> Dictionary:
			var rig := DarkFantasy.player_character(p.class_id)
			return {"rig": rig, "anim": Animator.new(rig)}}


# 戰技：先站穩錄好 anim，再每一步把 skill / skill_time 塞進去（衝刺類給往前的速度，腳才會跑）
func _skill_rows(page: int) -> Array:
	var ids: Array[StringName] = []
	for id: StringName in SkillDefs.SKILLS:
		if SkillDefs.SKILLS[id].get("category", &"") == &"attack":
			ids.append(id)
	var rows := []
	for i in range((page - 1) * SKILLS_PER_SHEET, mini(page * SKILLS_PER_SHEET, ids.size())):
		var id := ids[i]
		var def: Dictionary = SkillDefs.SKILLS[id]
		var w := _new_world()
		var p := _player(w, def.weapons[0])
		var base := _record(w, p, 20, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))
		var idle: Dictionary = base[-1].anim
		var total := SkillDefs.pose_time(id)
		var steps := roundi(total / DT) + 6
		var frames := []
		for s in steps:
			var t := s * DT
			var a := idle.duplicate(true)
			var vel := Vector2.ZERO
			if t < total:
				a["skill"] = id
				a["skill_time"] = t
				if def.behavior in [&"dash", &"burrow"] and t < def.time:
					vel = Vector2(0, def.distance / def.time)
					a["loco"] = &"move"
			frames.append({"anim": a, "vel": vel})
		rows.append(_player_row(String(id), p, frames, _even(0, roundi(total / DT))))
	return rows


# ───────── 怪物 ─────────

func _enemy_rows(model: StringName) -> Array:
	var kind: StringName = BOSS_KIND.get(model, model)
	var rows := []
	var spec: Array = BOSS_MOVES.get(model, [0, []])
	var form: int = spec[0]
	# AI 自己打：玩家站在前面不動（打不死），錄 12 秒，每個狀態取第一次出現的那段
	var w := _new_world()
	var p := _player(w, &"swordShield")
	var e := _spawn(w, kind, p.pos + Vector2(0, 5), form)
	var frames := _record(w, e, roundi(12.0 / DT), func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))
	var seen := {}
	var start := 0
	for i in frames.size() + 1:
		var st: StringName = frames[i].anim.state if i < frames.size() else &""
		if i == frames.size() or st != frames[start].anim.state:
			var name: StringName = frames[start].anim.state
			if not seen.has(name) and i - start >= 3 and rows.size() < 8:
				seen[name] = true
				rows.append(_enemy_row(String(name), e, model, frames, _even(start, mini(i - 1, start + roundi(2.5 / DT)))))
			start = i
	# Boss 每一招（強制出招）
	for move: StringName in spec[1]:
		if seen.has(move):
			continue
		var w2 := _new_world()
		var p2 := _player(w2, &"swordShield")
		var b := _spawn(w2, kind, p2.pos + Vector2(0, 6), form)
		_record(w2, b, roundi(b.def.spawn_time / DT) + 2, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))
		b.fsm.change(move)
		var mf := _record(w2, b, roundi(3.0 / DT), func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))
		var end := mf.size() - 1
		for i in mf.size():
			if mf[i].anim.state != move:
				end = maxi(i - 1, 1)
				break
		rows.append(_enemy_row(String(move), b, model, mf, _even(0, end)))
	# 死掉
	var w3 := _new_world()
	_player(w3, &"swordShield")
	var d := _spawn(w3, kind, Vector2(0, 6) + (w3.players[World.HOST_PEER_ID] as Player).pos, form)
	_record(w3, d, roundi(d.def.spawn_time / DT) + 2, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))
	d.hp = 0.0
	d.die(0)
	var df := _record(w3, d, 50, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))
	rows.append(_enemy_row("dead", d, model, df, _even(0, df.size() - 1)))
	return rows


func _spawn(w: World, kind: StringName, at: Vector2, form: int) -> Enemy:
	var e: Enemy = w.spawner.spawn_at(w, kind, at)
	if form > 0:
		e.set(&"form", form)
	return e


func _enemy_row(name: String, e: Enemy, model: StringName, frames: Array, samples: Array[int]) -> Dictionary:
	return {"name": name, "subject": e, "frames": frames, "samples": samples,
		"make": func() -> Dictionary:
			var rig: Node3D = DarkFantasy.character(model) if e.is_boss() else DarkFantasy.skinned_character(e.kind)
			return {"rig": rig, "anim": EnemyAnimator.new(rig, e)}}


# ───────── 排版 ─────────

func _layout(rows: Array) -> void:
	var tallest := 2.2
	var cells := []   # [row, col, rig]
	for r in rows.size():
		var row: Dictionary = rows[r]
		var subject: Entity = row.subject
		for c in (row.samples as Array).size():
			var made: Dictionary = (row.make as Callable).call()
			var rig: Node3D = made.rig
			add_child(rig)
			var upto: int = row.samples[c]
			for i in upto + 1:
				subject.anim = row.frames[i].anim
				subject.velocity = row.frames[i].vel
				made.anim.update(subject, DT)
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
		label.text = rows[r].name
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
