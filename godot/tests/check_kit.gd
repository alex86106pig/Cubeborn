# 自動檢查的共用工具（各 *_checks.gd 繼承這個類別，直接呼叫 _new_world、_run…）
# 建立的 World 都記在 _worlds，check.gd 結束前全部 clear()，避免循環參照造成洩漏警告
class_name CheckKit
extends RefCounted

const DT := 1.0 / 60.0


const EPS := 1e-3


static var _worlds: Array[World] = []   # 結束前全部 clear()，避免循環參照造成洩漏警告


# 預設關掉生成器，只測玩家；要測波次時傳 with_spawner = true
static func _new_world(seed_value: int = 12345, with_spawner: bool = false, map_id: StringName = &"test_arena") -> World:
	var w := World.new(map_id)
	w.spawn_packs = false   # 怪群（D5）另外檢查
	w.reset(seed_value)
	w.spawner.finished = not with_spawner
	_worlds.append(w)
	return w


static func _cmd(move: Vector2, aim: Vector2 = Vector2(0, 5), buttons: int = 0) -> InputCmd:
	var c := InputCmd.new()
	c.move = move
	c.aim = aim
	c.buttons = buttons
	return c


static func _run(w: World, cmd: InputCmd, steps: int) -> void:
	for i in steps:
		w.step({World.HOST_PEER_ID: cmd}, DT)


static func _player(w: World) -> Player:
	return w.players[World.HOST_PEER_ID]


# 不會動的假敵人：血多、質量大（擊退位移小），放在 world.enemies 讓玩家的攻擊打得到
static func _dummy(w: World, at: Vector2, hp: float = 1000.0, mass: float = 1000.0) -> Entity:
	var e := Entity.new(w, &"test", &"enemy", 0.5, hp, mass)
	e.pos = at
	w.add_entity(e)
	w.enemies.append(e)
	return e


# 跑 steps 步並收集事件
static func _run_collect(w: World, cmd: InputCmd, steps: int, out: Array[Dictionary]) -> void:
	for i in steps:
		w.step({World.HOST_PEER_ID: cmd}, DT)
		out.append_array(w.events)


static func _named(events: Array[Dictionary], name: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.name == name)


static func _damage_amounts(events: Array[Dictionary], target_id: int) -> Array:
	var out := []
	for e in _named(events, "entity:damaged"):
		if e.target_id == target_id:
			out.append(e.amount)
	return out


# 音效名稱表（audio/sound.gd 的 CUE_NAMES）
static func _cue_names() -> Dictionary:
	var names := {}
	for n: String in _sound_script().CUE_NAMES:
		names[n] = true
	return names


static func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f else ""


static func _list_gd(dir_path: String) -> Array[String]:
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


static func _spawn(w: World, type: StringName, at: Vector2) -> Enemy:
	return w.spawner.spawn_at(w, type, at)


# 跑到 pred 成立為止（最多 max_steps 步），回傳跑了幾步；沒成立回傳 -1
static func _run_until(w: World, cmd: InputCmd, max_steps: int, events: Array[Dictionary], pred: Callable) -> int:
	for i in max_steps:
		w.step({World.HOST_PEER_ID: cmd}, DT)
		events.append_array(w.events)
		if pred.call():
			return i + 1
	return -1


static func _jump_cmd(move: Vector2 = Vector2.ZERO, extra: int = 0) -> InputCmd:
	return _cmd(move, Vector2(0, 5), InputCmd.BTN_JUMP | extra)


# 骷髏戰士爬出後馬上在玩家前方：回傳 grunt（已進入 swing 狀態）
static func _grunt_swinging(w: World, p: Player) -> MeleeEnemy:
	var g: MeleeEnemy = _spawn(w, &"grunt", Vector2(0, 0))
	p.pos = Vector2(0, 1.2)
	g.facing = 0.0
	var steps := 0
	while not g.fsm.is_in(&"swing") and steps < 120:
		p.pos = Vector2(0, 1.2)
		_run(w, _cmd(Vector2.ZERO), 1)
		steps += 1
	return g


static var _feel_lines: Array[String] = []


static func _feel(line: String) -> void:
	_feel_lines.append(line)


# 單項檢查順便量到的數字：不印在畫面上，由 check.gd 寫進 check_last.log 那一項的下面
static var _notes: Array[String] = []


static func _note(line: String) -> void:
	_notes.append(line)


# audio/sound.gd 用到 GameEvents（autoload），在檢查腳本編譯時還不存在，所以執行時才載入（同 HUD）
static func _sound_script() -> GDScript:
	return load("res://audio/sound.gd")

# 場景樹的根節點（HUD、畫面層的檢查要把節點掛上去才會 _ready）
static func _scene_root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root
