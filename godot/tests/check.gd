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
	_check("武器資料：behavior 存在、三段時間為正數、音效名稱存在於網頁版 CUES", _check_weapon_defs)
	_check("劍盾普攻：三段時間合計 0.36 秒，期間移速 ×0.35、收招後回到 ready", _check_attack_timing)
	_check("劍盾連段：傷害 12 / 12 / 22（第三段 ×1.8）、第三段後搖 ×1.6、同一目標每次出手只中一次", _check_combo)
	_check("盾擊衝鋒：CD 4 秒、衝刺 17 單位/秒 × 0.22 秒、受傷 ×0.2 且不被打斷、CD 中發 skill:onCooldown", _check_shield_bash)
	_check("受擊：扣血後進入 stagger（移速 ×0.4、0.15 秒）、無敵 0.6 秒、畫面震動", _check_stagger)
	_check("輸入緩衝：攻擊中按右鍵會在後搖取消並接特殊技；0.25 秒後過期", _check_buffer)
	_check("法杖魔彈：前方 0.6 產生、20 單位/秒、命中造成 8 傷害、最遠 14 單位", _check_fire_bolt)
	_check("奧術爆裂：落點限制在 2~12、爆炸半徑 3.2 造成 28 傷害、範圍外不受傷", _check_arcane_burst)
	_check("死亡：發出 player:died、移動層進入 dead、不再接受輸入", _check_player_death)
	_check("事件：戰鬥中的事件 payload 也只含可序列化的值", _check_combat_events_serializable)
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


# 不會動的假敵人：血多、質量大（擊退位移小），放在 world.enemies 讓玩家的攻擊打得到
func _dummy(w: World, at: Vector2, hp: float = 1000.0, mass: float = 1000.0) -> Entity:
	var e := Entity.new(w, &"test", &"enemy", 0.5, hp, mass)
	e.pos = at
	w.add_entity(e)
	w.enemies.append(e)
	return e


# 跑 steps 步並收集事件
func _run_collect(w: World, cmd: InputCmd, steps: int, out: Array[Dictionary]) -> void:
	for i in steps:
		w.step({World.HOST_PEER_ID: cmd}, DT)
		out.append_array(w.events)


static func _named(events: Array[Dictionary], name: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.name == name)


func _damage_amounts(events: Array[Dictionary], target_id: int) -> Array:
	var out := []
	for e in _named(events, "entity:damaged"):
		if e.target_id == target_id:
			out.append(e.amount)
	return out


# 網頁版 Sound.js 的 CUES 名稱（以「名稱: (a) =>」比對）
func _web_cue_names() -> Dictionary:
	var root := ProjectSettings.globalize_path("res://").path_join("..")
	var text := _read_text(root.path_join("src/audio/Sound.js"))
	var names := {}
	for m in RegEx.create_from_string("(?m)^\\s+(\\w+): \\(a\\) =>").search_all(text):
		names[m.get_string(1)] = true
	return names


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


func _check_weapon_defs() -> String:
	var cues := _web_cue_names()
	if cues.size() < 5:
		return "只從 Sound.js 比對到 %d 個 CUES，比對規則可能失效" % cues.size()
	for id: StringName in WeaponDefs.WEAPONS:
		var w: Dictionary = WeaponDefs.WEAPONS[id]
		for kind in ["attack", "special"]:
			var def: Dictionary = w[kind]
			if not WeaponBehaviors.BEHAVIORS.has(def.behavior):
				return "%s.%s 的 behavior「%s」不存在" % [id, kind, def.behavior]
			for t in ["windup", "active", "recovery"]:
				if def[t] <= 0.0:
					return "%s.%s 的 %s 不是正數" % [id, kind, t]
			for key in ["sfx", "sfx_heavy"]:
				if def.has(key) and not cues.has(def[key]):
					return "%s.%s 的音效「%s」不在網頁版 CUES" % [id, kind, def[key]]
	return ""


func _check_attack_timing() -> String:
	var w := _new_world()
	var p := _player(w)
	_run(w, _cmd(Vector2(1, 0), Vector2(0, 5), InputCmd.BTN_ATTACK), 1)
	if not p.action.is_in(&"attack"):
		return "按住左鍵後應進入 attack，實際 %s" % p.action.current_name
	_run(w, _cmd(Vector2(1, 0)), 1)
	var expected_speed := 6.5 * 0.35
	if absf(p.velocity.length() - expected_speed) > EPS:
		return "攻擊中移速 %.4f，預期 %.4f" % [p.velocity.length(), expected_speed]
	var steps := 2
	while p.action.is_in(&"attack") and steps < 120:
		_run(w, _cmd(Vector2(1, 0)), 1)
		steps += 1
	var expected := ceili(0.36 / DT)   # 22 步
	if steps - 1 != expected or not p.action.is_in(&"ready"):
		return "攻擊持續 %d 步（%.3f 秒），預期 %d 步；結束後狀態 %s" % [steps - 1, (steps - 1) * DT, expected, p.action.current_name]
	return ""


func _check_combo() -> String:
	var w := _new_world()
	var p := _player(w)
	var dummy := _dummy(w, Vector2(0, 1.5))
	var events: Array[Dictionary] = []
	var hold := _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK)
	var finisher_recovery := 0.0
	var reached_finisher := false
	for i in 200:
		w.step({World.HOST_PEER_ID: hold}, DT)
		events.append_array(w.events)
		if p.action.is_in(&"attack") and p.action.data.get("is_finisher", false):
			reached_finisher = true
			finisher_recovery = p.action.data.durations[2]
		elif reached_finisher and p.action.is_in(&"attack"):
			break   # 第四刀開始（回到第一段）
	var amounts := _damage_amounts(events, dummy.id)
	if amounts != [12, 12, 22]:
		return "三段傷害 %s，預期 [12, 12, 22]" % [amounts]
	if absf(finisher_recovery - 0.32) > EPS:
		return "第三段後搖 %.3f 秒，預期 0.32" % finisher_recovery
	var crits := _named(events, "entity:damaged").map(func(e: Dictionary) -> bool: return e.is_crit)
	if crits != [false, false, true]:
		return "is_crit 應只有第三段為 true，實際 %s" % [crits]
	var sfx := _named(events, "sfx:cue").map(func(e: Dictionary) -> String: return e.cue)
	if sfx != ["swing", "swing", "swingHeavy"]:
		return "音效 %s，預期 swing / swing / swingHeavy" % [sfx]
	return ""


func _check_shield_bash() -> String:
	var w := _new_world()
	var p := _player(w)
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(5, 0), InputCmd.BTN_SPECIAL), 1, events)
	if not p.action.is_in(&"special") or _named(events, "skill:used").is_empty():
		return "右鍵後應進入 special 並發出 skill:used"
	var idle := _cmd(Vector2.ZERO, Vector2(5, 0))
	var hurt_checked := false
	for i in 60:
		_run_collect(w, idle, 1, events)
		if not hurt_checked and p.action.data.get("phase_index", 0) == 1:
			hurt_checked = true
			var dealt := p.take_damage(10.0, Vector2(-1, 0), 20.0, 0)
			if dealt != 2 or not p.action.is_in(&"special"):
				return "衝鋒中受到 10 傷害實際扣 %d（預期 2），狀態 %s（應維持 special）" % [dealt, p.action.current_name]
		if p.action.is_in(&"ready"):
			break
	if not hurt_checked:
		return "沒有進入 active 階段"
	var dist := p.pos.x
	if absf(dist - 17.0 * 0.22) > 17.0 * DT * 1.5:
		return "衝刺距離 %.3f，預期約 %.3f" % [dist, 17.0 * 0.22]
	if p.mass != Config.PLAYER.mass or p.damage_taken_mul != 1.0 or p.knockback_mul != 1.0:
		return "結束後質量 / 受傷倍率 / 擊退倍率沒有還原"
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(5, 0), InputCmd.BTN_SPECIAL), 2, events)
	if _named(events, "skill:onCooldown").is_empty() or p.action.is_in(&"special"):
		return "CD 中按右鍵應發出 skill:onCooldown 且不出招"
	var remaining := w.cooldowns.remaining("player.special")
	var elapsed := w.tick * DT
	if absf(remaining - (4.0 - elapsed + DT)) > DT * 1.5:
		return "CD 剩餘 %.3f 秒，預期約 %.3f" % [remaining, 4.0 - elapsed + DT]
	_run(w, idle, ceili(remaining / DT) + 1)
	if not w.cooldowns.is_ready("player.special"):
		return "4 秒後 CD 應已結束"
	return ""


func _check_stagger() -> String:
	var w := _new_world()
	var p := _player(w)
	_run(w, _cmd(Vector2.ZERO), 1)
	var dealt := p.take_damage(10.0, Vector2(1, 0), 0.0, 0)
	if dealt != 10 or p.hp != 90.0:
		return "受到 10 傷害後 hp=%.1f" % p.hp
	if not p.action.is_in(&"stagger") or absf(p.invuln_timer - 0.6) > EPS:
		return "應進入 stagger 且無敵 0.6 秒，實際 %s / %.3f" % [p.action.current_name, p.invuln_timer]
	if _named(w.events, "camera:shake").is_empty():
		return "受傷應發出 camera:shake"
	if p.take_damage(10.0, Vector2(1, 0), 0.0, 0) != -1:
		return "無敵中不應受傷"
	_run(w, _cmd(Vector2(1, 0)), 1)
	if absf(p.velocity.length() - 6.5 * 0.4) > EPS:
		return "硬直中移速 %.4f，預期 %.4f" % [p.velocity.length(), 6.5 * 0.4]
	_run(w, _cmd(Vector2(1, 0)), ceili(0.15 / DT))
	if not p.action.is_in(&"ready"):
		return "0.15 秒後應回到 ready，實際 %s" % p.action.current_name
	return ""


func _check_buffer() -> String:
	# 劍盾：前搖中按右鍵 → 後搖第一步取消 → 下一步接盾擊（不等攻擊自然結束的第 23 步）
	var w := _new_world()
	var p := _player(w)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1)
	_run(w, _cmd(Vector2.ZERO), 1)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL), 1)
	var started := -1
	for i in 30:
		_run(w, _cmd(Vector2.ZERO), 1)
		if p.action.is_in(&"special"):
			started = w.tick
			break
	if started < 0 or started >= 23:
		return "盾擊在第 %d 步才開始，應在攻擊後搖時取消（第 23 步之前）" % started
	# 法杖：奧術爆裂前搖 0.35 秒，期間再按右鍵的緩衝 0.25 秒後過期 → 不會在後搖時被消化（不發 skill:onCooldown）
	var w2 := _new_world()
	var p2 := _player(w2)
	p2.equip_weapon(&"staff")
	var events: Array[Dictionary] = []
	_run_collect(w2, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL), 1, events)
	_run_collect(w2, _cmd(Vector2.ZERO), 1, events)
	_run_collect(w2, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL), 1, events)
	_run_collect(w2, _cmd(Vector2.ZERO), 60, events)
	if not _named(events, "skill:onCooldown").is_empty():
		return "緩衝應在 0.25 秒後過期，但後搖時仍被消化"
	return ""


func _check_fire_bolt() -> String:
	var w := _new_world()
	var p := _player(w)
	p.equip_weapon(&"staff")
	var dummy := _dummy(w, Vector2(0, 5))
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1, events)
	var bolt: Projectile = null
	for i in 20:
		_run_collect(w, _cmd(Vector2.ZERO), 1, events)
		if not w.projectiles.is_empty():
			bolt = w.projectiles[0]
			break
	if bolt == null:
		return "沒有產生投射物"
	var step_len := 20.0 * DT
	if absf(bolt.pos.y - bolt.traveled - 0.6) > EPS or absf(bolt.traveled - step_len) > EPS:
		return "產生位置 %.3f（預期 0.6）、第一步飛行 %.4f（預期 %.4f）" % [bolt.pos.y - bolt.traveled, bolt.traveled, step_len]
	_run_collect(w, _cmd(Vector2.ZERO), 30, events)
	if _damage_amounts(events, dummy.id) != [8] or not bolt.is_removed:
		return "命中傷害 %s（預期 [8]），投射物 is_removed=%s" % [_damage_amounts(events, dummy.id), bolt.is_removed]
	# 射程：沒有目標時飛 14 單位後消失
	var w2 := _new_world()
	_player(w2).equip_weapon(&"staff")
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, -5), InputCmd.BTN_ATTACK), 1)
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, -5)), 10)
	var far: Projectile = w2.projectiles[0]
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, -5)), 60)
	if not far.is_removed or far.traveled < 14.0 or far.traveled > 14.0 + step_len:
		return "射程：飛行 %.3f 後 is_removed=%s，預期 14" % [far.traveled, far.is_removed]
	return ""


func _check_arcane_burst() -> String:
	var w := _new_world()
	var p := _player(w)
	p.equip_weapon(&"staff")
	var near := _dummy(w, Vector2(2.5, 12))   # 落點 (0, 12) 旁 2.5：在 3.2 + 0.5 內
	var far := _dummy(w, Vector2(4.5, 12))    # 4.5：在範圍外
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 30), InputCmd.BTN_SPECIAL), 1, events)
	if absf(p.action.data.get("dist", 0.0) - 12.0) > EPS:
		return "瞄準 30 單位外，落點距離 %.3f，預期限制為 12" % p.action.data.get("dist", 0.0)
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 30)), 90, events)
	if _damage_amounts(events, near.id) != [28]:
		return "範圍內目標受到 %s，預期 [28]" % [_damage_amounts(events, near.id)]
	if not _damage_amounts(events, far.id).is_empty():
		return "範圍外目標不應受傷，實際 %s" % [_damage_amounts(events, far.id)]
	var names := _named(events, "sfx:cue").map(func(e: Dictionary) -> String: return e.cue)
	if names != ["arcaneCast", "explosion"]:
		return "音效 %s，預期 arcaneCast / explosion" % [names]
	# 最短距離：瞄準 0.8 單位處，落點限制為 2
	var w2 := _new_world()
	var p2 := _player(w2)
	p2.equip_weapon(&"staff")
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, 0.8), InputCmd.BTN_SPECIAL), 1)
	if absf(p2.action.data.get("dist", 0.0) - 2.0) > EPS:
		return "瞄準 0.8 單位處，落點距離 %.3f，預期 2" % p2.action.data.get("dist", 0.0)
	return ""


func _check_player_death() -> String:
	var w := _new_world()
	var p := _player(w)
	_run(w, _cmd(Vector2.ZERO), 1)
	p.take_damage(1000.0, Vector2(1, 0), 0.0, 0)
	if not p.is_dead or _named(w.events, "player:died").is_empty() or _named(w.events, "entity:died").is_empty():
		return "應死亡並發出 entity:died 與 player:died"
	if not p.locomotion.is_in(&"dead"):
		return "移動層應為 dead，實際 %s" % p.locomotion.current_name
	var before := p.pos
	_run(w, _cmd(Vector2(1, 0), Vector2(0, 5), InputCmd.BTN_ATTACK | InputCmd.BTN_SPECIAL), 30)
	if p.pos != before or not p.action.is_in(&"ready"):
		return "死亡後仍在移動或出招：pos=%s action=%s" % [p.pos, p.action.current_name]
	return ""


func _check_combat_events_serializable() -> String:
	var w := _new_world()
	var p := _player(w)
	_dummy(w, Vector2(0, 1.5), 30.0, 1.0)
	_dummy(w, Vector2(3, 6))
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 80, events)
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL), 40, events)
	p.equip_weapon(&"staff")
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(3, 6), InputCmd.BTN_ATTACK), 30, events)
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(3, 6), InputCmd.BTN_SPECIAL), 90, events)
	if _named(events, "entity:damaged").size() < 3 or _named(events, "entity:died").is_empty():
		return "情境沒有產生足夠的戰鬥事件（damaged %d、died %d）" % [_named(events, "entity:damaged").size(), _named(events, "entity:died").size()]
	for e in events:
		for k: String in e:
			if typeof(e[k]) == TYPE_OBJECT:
				return "事件 %s 的欄位 %s 是物件" % [e.name, k]
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
