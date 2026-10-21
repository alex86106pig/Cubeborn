# 自動檢查（作用等同網頁版 check.js）：模擬層規範、版號、核心機制
# 在 godot/ 內執行：<Godot console 執行檔> --headless --path . -s res://tests/check.gd
extends SceneTree

const DT := 1.0 / 60.0
const EPS := 1e-3

# 模擬層禁止使用的東西（見 PROJECT_GUIDELINES.md 15.2）
const SIM_FORBIDDEN := {
	"Input 單例": "\\bInput\\.",
	"get_node / $": "get_node|get_tree|\\$[A-Za-z_\"]",
	"繼承 Node": "extends\\s+Node",
	"Engine.time_scale": "Engine\\.time_scale",
	"全域隨機": "(?<![\\w.])(randf|randi|randf_range|randi_range|randomize)\\(",
	"讀系統時間": "Time\\.get_",
	"讀檔": "FileAccess|DirAccess|ResourceLoader|load\\(",
	"引用畫面/輸入/連線層": "\\b(CameraRig|WorldView|ArenaView|InputCollector|HUD|GameEvents)\\b",
}

var _passed := 0
var _failed := 0
var _worlds: Array[World] = []   # 結束前全部 clear()，避免循環參照造成洩漏警告


func _initialize() -> void:
	print("Cubeborn Godot 自動檢查\n")
	_check("模擬層：sim/ 沒有使用禁止的 API（Input、節點、全域隨機、時間、讀檔、畫面層）", _check_sim_forbidden)
	_check("版號：version.gd、version.js、CHANGELOG 最新版一致", _check_versions)
	_check("CD：計時、進度、到期、長度 0 視為立即可用", _check_cooldowns)
	_check("狀態機：enter/exit 順序、can_exit 否決、time 累計、data 複製", _check_state_machine)
	_check("InputCmd：按鈕位元不重疊、陣列序列化來回一致", _check_input_cmd)
	_check("玩家移動：1 秒移動 6.5 單位（同網頁版 PLAYER.moveSpeed）", _check_player_move)
	_check("玩家移動：斜向輸入長度被限制為 1（權威端不信任輸入）", _check_diagonal)
	_check("玩家轉向：面朝瞄準點（facing = atan2(dx, dz)）", _check_facing)
	_check("場地邊界：玩家停在 arenaHalfSize - radius", _check_arena_clamp)
	_check("碰撞分離：重疊實體依質量比例推開到剛好接觸", _check_separation)
	_check("命中停頓：期間時間縮放 5%，到期恢復 1", _check_hit_stop)
	_check("事件：payload 只含可序列化的值（沒有物件參照）", _check_events_serializable)
	_check("決定性：同種子、同輸入的兩個 World 結果相同", _check_determinism)
	_check("記憶體：reset 與移除實體後，舊實體會被釋放（切斷與 World 的循環參照）", _check_entity_release)
	for w in _worlds:
		w.clear()
	_worlds.clear()
	print("\n%d / %d 通過" % [_passed, _passed + _failed])
	quit(1 if _failed > 0 else 0)


func _check(title: String, fn: Callable) -> void:
	var err: String = fn.call()
	if err == "":
		_passed += 1
		print("✔ ", title)
	else:
		_failed += 1
		print("✘ ", title, "\n    ", err)


# ---- 工具 ----

func _new_world(seed_value: int = 12345) -> World:
	var w := World.new()
	w.reset(seed_value)
	_worlds.append(w)
	return w


func _cmd(move: Vector2, aim: Vector2 = Vector2(0, 5), buttons: int = 0) -> InputCmd:
	var c := InputCmd.new()
	c.move = move
	c.aim = aim
	c.buttons = buttons
	return c


func _run(w: World, cmd: InputCmd, steps: int) -> void:
	for i in steps:
		w.step({World.HOST_PEER_ID: cmd}, DT)


func _player(w: World) -> Player:
	return w.players[World.HOST_PEER_ID]


func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f else ""


func _list_gd(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		out.append_array(_list_gd(dir_path.path_join(d)))
	return out


# ---- 檢查 ----

func _check_sim_forbidden() -> String:
	var files := _list_gd("res://sim")
	if files.is_empty():
		return "找不到 sim/ 的檔案"
	var problems: Array[String] = []
	for path in files:
		var lines := _read_text(path).split("\n")
		for i in lines.size():
			var code := lines[i].get_slice("#", 0)   # 去掉註解
			for label: String in SIM_FORBIDDEN:
				var re := RegEx.create_from_string(SIM_FORBIDDEN[label])
				if re.search(code):
					problems.append("%s:%d %s → %s" % [path, i + 1, label, lines[i].strip_edges()])
	return "\n    ".join(problems)


func _check_versions() -> String:
	var root := ProjectSettings.globalize_path("res://").path_join("..")
	var js := _read_text(root.path_join("src/core/version.js"))
	var changelog := _read_text(root.path_join("CHANGELOG.md"))
	var js_ver := RegEx.create_from_string("VERSION = '([^']+)'").search(js)
	var cl_ver := RegEx.create_from_string("## \\[([^\\]]+)\\]").search(changelog)
	if js_ver == null or cl_ver == null:
		return "讀不到 version.js 或 CHANGELOG.md 的版號"
	var v := GameVersion.VERSION
	if js_ver.get_string(1) != v or cl_ver.get_string(1) != v:
		return "version.gd=%s version.js=%s CHANGELOG=%s" % [v, js_ver.get_string(1), cl_ver.get_string(1)]
	return ""


func _check_cooldowns() -> String:
	var cd := CooldownManager.new()
	cd.start("player.special", 1.0)
	if cd.is_ready("player.special"):
		return "開始後不應立即可用"
	cd.tick(0.5)
	if absf(cd.remaining("player.special") - 0.5) > EPS or absf(cd.progress("player.special") - 0.5) > EPS:
		return "0.5 秒後 remaining=%.3f progress=%.3f" % [cd.remaining("player.special"), cd.progress("player.special")]
	cd.tick(0.6)
	if not cd.is_ready("player.special") or cd.progress("player.special") != 1.0:
		return "1.1 秒後應已可用"
	cd.start("player.slot1", 0.0)
	if not cd.is_ready("player.slot1"):
		return "長度 0 應立即可用"
	cd.start("a.b", 3.0)
	cd.reset_all()
	if not cd.is_ready("a.b"):
		return "reset_all 後應可用"
	return ""


class _LogState:
	var log: Array
	var tag: String
	var allow_exit := true

	func _init(p_log: Array, p_tag: String) -> void:
		log = p_log
		tag = p_tag

	func enter(_ctx: Object, data: Dictionary, _fsm: StateMachine) -> void:
		data["entered"] = true
		log.append("enter:" + tag)

	func exit(_ctx: Object, _fsm: StateMachine) -> void:
		log.append("exit:" + tag)

	func can_exit(_ctx: Object, _next: StringName, _fsm: StateMachine) -> bool:
		return allow_exit


func _check_state_machine() -> String:
	var log := []
	var a := _LogState.new(log, "a")
	var b := _LogState.new(log, "b")
	var src := {"x": 1}
	var fsm := StateMachine.new(null, {&"a": a, &"b": b}, &"a")
	fsm.update(0.25)
	if absf(fsm.time - 0.25) > EPS:
		return "time 應累計為 0.25，實際 %.3f" % fsm.time
	fsm.change(&"b", src)
	if log != ["enter:a", "exit:a", "enter:b"]:
		return "呼叫順序錯誤：%s" % [log]
	if fsm.time != 0.0 or fsm.previous_name != &"a" or not fsm.is_in(&"b"):
		return "切換後 time / previous_name / is_in 不正確"
	if src.has("entered") or not fsm.data.has("entered"):
		return "data 應為複本，狀態寫入不應影響傳入的 Dictionary"
	b.allow_exit = false
	if fsm.change(&"a") or not fsm.is_in(&"b"):
		return "can_exit 回傳 false 時不應切換"
	return ""


func _check_input_cmd() -> String:
	var bits := [InputCmd.BTN_ATTACK, InputCmd.BTN_SPECIAL]
	for i in InputCmd.SLOT_COUNT:
		bits.append(InputCmd.slot_bit(i))
	var seen := 0
	for bit: int in bits:
		if seen & bit != 0:
			return "位元重疊：%d" % bit
		seen |= bit
	var c := _cmd(Vector2(0.5, -1), Vector2(3, 4), InputCmd.BTN_SPECIAL | InputCmd.slot_bit(2))
	c.tick = 42
	var back := InputCmd.from_array(c.to_array())
	if back.tick != 42 or back.move != c.move or back.aim != c.aim or back.buttons != c.buttons:
		return "序列化來回不一致"
	if not back.has(InputCmd.slot_bit(2)) or back.has(InputCmd.slot_bit(1)):
		return "has() 結果錯誤"
	return ""


func _check_player_move() -> String:
	var w := _new_world()
	_run(w, _cmd(Vector2(1, 0), Vector2(100, 0)), 60)
	var p := _player(w)
	if absf(p.pos.x - 6.5) > EPS or absf(p.pos.y) > EPS:
		return "60 步後位置 (%.4f, %.4f)，預期 (6.5, 0)" % [p.pos.x, p.pos.y]
	return ""


func _check_diagonal() -> String:
	var w := _new_world()
	_run(w, _cmd(Vector2(1, 1)), 60)
	var dist := _player(w).pos.length()
	if absf(dist - 6.5) > EPS:
		return "斜向 1 秒移動 %.4f，預期 6.5" % dist
	return ""


func _check_facing() -> String:
	var w := _new_world()
	_run(w, _cmd(Vector2.ZERO, Vector2(5, 0)), 10)
	var f := _player(w).facing
	if absf(f - PI / 2.0) > EPS:
		return "瞄準 +X 時 facing=%.4f，預期 %.4f" % [f, PI / 2.0]
	_run(w, _cmd(Vector2.ZERO, Vector2(0, -5)), 10)
	f = absf(_player(w).facing)
	if absf(f - PI) > EPS:
		return "瞄準 -Z 時 |facing|=%.4f，預期 π" % f
	return ""


func _check_arena_clamp() -> String:
	var w := _new_world()
	_run(w, _cmd(Vector2(1, 0)), 600)
	var p := _player(w)
	var limit: float = Config.WORLD.arena_half_size - Config.PLAYER.radius
	if absf(p.pos.x - limit) > EPS:
		return "x=%.4f，預期 %.4f" % [p.pos.x, limit]
	return ""


func _check_separation() -> String:
	var w := _new_world()
	var a := Entity.new(w, &"test", &"enemy", 0.5, 10.0, 1.0)
	var b := Entity.new(w, &"test", &"enemy", 0.5, 10.0, 3.0)
	a.pos = Vector2(0, 0)
	b.pos = Vector2(0.4, 0)
	var list: Array[Entity] = [a, b]
	SimPhysics.separate(list, w.rng)
	var dist := a.pos.distance_to(b.pos)
	if absf(dist - 1.0) > EPS:
		return "推開後距離 %.4f，預期 1.0" % dist
	# 重疊 0.6：輕的（質量 1）推 0.45、重的（質量 3）推 0.15
	if absf(a.pos.x + 0.45) > EPS or absf(b.pos.x - 0.55) > EPS:
		return "a.x=%.4f b.x=%.4f，預期 -0.45 / 0.55" % [a.pos.x, b.pos.x]
	return ""


func _check_hit_stop() -> String:
	var w := _new_world()
	w.hit_stop(0.1)
	var slow_ticks := 0
	for i in 20:
		if w.consume_hit_stop(DT) < 1.0:
			slow_ticks += 1
	if slow_ticks != 6:
		return "0.1 秒停頓持續 %d 個真實步，預期 6" % slow_ticks
	return ""


func _check_events_serializable() -> String:
	var w := _new_world(1)
	var all: Array[Dictionary] = w.events.duplicate()
	_player(w).die()
	all.append_array(w.events)
	_run(w, _cmd(Vector2(1, 0)), 5)
	all.append_array(w.events)
	if all.size() < 2:
		return "應至少有 game:restart 與 entity:died 事件"
	for e in all:
		for k: String in e:
			if typeof(e[k]) == TYPE_OBJECT:
				return "事件 %s 的欄位 %s 是物件" % [e.name, k]
	return ""


func _check_determinism() -> String:
	var w1 := _new_world(777)
	var w2 := _new_world(777)
	for w in [w1, w2]:
		_run(w, _cmd(Vector2(0.3, 0.8), Vector2(-4, 2)), 90)
	var p1 := _player(w1)
	var p2 := _player(w2)
	if p1.pos != p2.pos or p1.facing != p2.facing or w1.rng.state != w2.rng.state:
		return "兩個 World 結果不同"
	return ""


func _check_entity_release() -> String:
	var w := _new_world()
	var old: WeakRef = weakref(_player(w))
	w.reset(1)
	if old.get_ref() != null:
		return "reset 後舊玩家仍存在"
	var p := _player(w)
	var ref: WeakRef = weakref(p)
	p.remove()
	p = null
	_run(w, _cmd(Vector2.ZERO), 1)
	if ref.get_ref() != null or w.players.has(World.HOST_PEER_ID):
		return "remove() 後玩家仍存在"
	return ""
