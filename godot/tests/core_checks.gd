# 核心規範與基礎系統：編譯、模擬層禁用 API、版號、CD、狀態機、InputCmd、碰撞分離、決定性、記憶體釋放、屬性計算
# 由 tests/check.gd 呼叫；每個 check_* 回傳 "" = 通過，否則是失敗原因
class_name CoreChecks
extends CheckKit

# 模擬層禁止使用的東西（見 PROJECT_GUIDELINES.md 第 2 節）
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


# 畫面層與 main.gd 不會被其他檢查載入；編譯錯誤只會出現在匯入紀錄裡，容易漏看
static func check_all_scripts_compile() -> String:
	var broken: Array[String] = []
	for path in _list_gd("res://"):
		if path.begins_with("res://.godot") or path.begins_with("res://tests/"):
			continue
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			broken.append(path)
	return "無法編譯：" + ", ".join(broken) if not broken.is_empty() else ""


static func check_sim_forbidden() -> String:
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


static func check_versions() -> String:
	var root := ProjectSettings.globalize_path("res://").path_join("..")
	var changelog := _read_text(root.path_join("CHANGELOG.md"))
	# 還沒推送的改動記在最上面的 [未發布]（推送時才換成版號，見 PROJECT_GUIDELINES 第 12 節），比對跳過它
	var cl_ver := RegEx.create_from_string("## \\[(\\d+\\.\\d+\\.\\d+)\\]").search(changelog)
	if cl_ver == null:
		return "讀不到 CHANGELOG.md 的版號"
	if cl_ver.get_string(1) != GameVersion.VERSION:
		return "version.gd=%s CHANGELOG=%s" % [GameVersion.VERSION, cl_ver.get_string(1)]
	var unreleased := changelog.find("## [未發布]")
	if unreleased != -1 and unreleased > cl_ver.get_start():
		return "[未發布] 要放在最新版號的上面"
	return ""


static func check_cooldowns() -> String:
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


static func check_state_machine() -> String:
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


static func check_input_cmd() -> String:
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


static func check_separation() -> String:
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
	# 固定不動的（休眠怪群，v0.30.0）不被推，會動的一方退開全部重疊；兩個都固定的不互推
	a.pos = Vector2(0, 0)
	b.pos = Vector2(0.4, 0)
	b.fixed = true
	SimPhysics.separate(list, w.rng)
	if absf(a.pos.x + 0.6) > EPS or absf(b.pos.x - 0.4) > EPS:
		return "b 固定時 a.x=%.4f b.x=%.4f，預期 -0.6 / 0.4" % [a.pos.x, b.pos.x]
	a.pos = Vector2(0, 0)
	a.fixed = true
	SimPhysics.separate(list, w.rng)
	if a.pos != Vector2.ZERO or absf(b.pos.x - 0.4) > EPS:
		return "兩個都固定時不應互推：a=%s b=%s" % [a.pos, b.pos]
	return ""


static func check_hit_stop() -> String:
	var w := _new_world()
	w.hit_stop(0.1)
	var slow_ticks := 0
	for i in 20:
		if w.consume_hit_stop(DT) < 1.0:
			slow_ticks += 1
	if slow_ticks != 6:
		return "0.1 秒停頓持續 %d 個真實步，預期 6" % slow_ticks
	return ""


static func check_events_serializable() -> String:
	var w := _new_world()
	var p := _player(w)
	var events: Array[Dictionary] = w.events.duplicate()   # 開場的 game:restart
	_dummy(w, Vector2(0, 1.5), 30.0, 1.0)
	_dummy(w, Vector2(3, 6))
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 80, events)
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL), 40, events)
	p.equip_weapon(&"staff")
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(3, 6), InputCmd.BTN_ATTACK), 30, events)
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(3, 6), InputCmd.BTN_SPECIAL), 90, events)
	p.die()
	events.append_array(w.events)
	_run_collect(w, _cmd(Vector2(1, 0)), 5, events)
	if _named(events, "entity:damaged").size() < 3 or _named(events, "entity:died").size() < 2 or _named(events, "game:restart").is_empty():
		return "情境沒有產生足夠的事件（damaged %d、died %d、restart %d）" % [_named(events, "entity:damaged").size(), _named(events, "entity:died").size(), _named(events, "game:restart").size()]
	for e in events:
		for k: String in e:
			if typeof(e[k]) == TYPE_OBJECT:
				return "事件 %s 的欄位 %s 是物件" % [e.name, k]
	return ""


static func check_grid_matches_brute_force() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var w := _new_world()
	var a: Array[Entity] = []
	var b: Array[Entity] = []
	for i in 80:
		var r := rng.randf_range(0.4, 1.0)
		var m := rng.randf_range(1.0, 5.0)
		var at := Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
		for list in [a, b]:
			var e := Entity.new(w, &"test", &"enemy", r, 10.0, m)
			e.pos = at
			e.fixed = i % 4 == 0   # 每 4 個有 1 個固定不動（休眠怪群，v0.30.0）
			list.append(e)
	var r1 := RandomNumberGenerator.new()
	var r2 := RandomNumberGenerator.new()
	r1.seed = 1
	r2.seed = 1
	SimPhysics.separate(a, r1)
	SimPhysics.separate_brute_force(b, r2)
	var max_diff := 0.0
	for i in a.size():
		max_diff = maxf(max_diff, a[i].pos.distance_to(b[i].pos))
	for list in [a, b]:
		for e in list:
			e.world = null
	if max_diff > 1e-5:
		return "格子版與兩兩比對最大差異 %.6f" % max_diff
	return ""


static func check_determinism_with_enemies() -> String:
	var w1 := _new_world(31337, true)
	var w2 := _new_world(31337, true)
	var cmd := _cmd(Vector2(0.3, -0.2), Vector2(4, 3), InputCmd.BTN_ATTACK)
	for i in 60 * 12:
		for w in [w1, w2]:
			w.step({World.HOST_PEER_ID: cmd}, DT)
	if w1.entities.size() != w2.entities.size() or w1.rng.state != w2.rng.state:
		return "實體數或隨機數狀態不同（%d / %d）" % [w1.entities.size(), w2.entities.size()]
	for id: int in w1.entities:
		if not w2.entities.has(id) or w1.entities[id].pos != w2.entities[id].pos or w1.entities[id].facing != w2.entities[id].facing:
			return "實體 %d 位置或朝向不同" % id
	if w1.enemies.is_empty() and w1.stats.kills == 0:
		return "12 秒內沒有任何敵人，情境無效"
	return ""


static func check_enemy_release() -> String:
	var w := _new_world()
	var a := _spawn(w, &"archer", Vector2(8, 8))
	var key := a.cd("fire")
	if w.cooldowns.is_ready(key):
		return "弓手出生時應有第一次射擊的延遲"
	var ref: WeakRef = weakref(a)
	a.remove()
	a = null
	_run(w, _cmd(Vector2.ZERO), 1)
	if not w.cooldowns.is_ready(key):
		return "移除後 CD %s 應被清除" % key
	if ref.get_ref() != null or not w.enemies.is_empty():
		return "移除後弓手仍存在"
	return ""


static func check_stats_formula() -> String:
	var s := Stats.new({&"move_speed": 6.5})
	if s.value(&"move_speed") != 6.5 or s.value(&"damage") != StatDefs.STATS[&"damage"].base or s.value(&"crit_damage") != StatDefs.STATS[&"crit_damage"].base:
		return "預設值錯誤：移速 %.3f 攻擊力 %.3f 爆擊傷害 %.3f" % [s.value(&"move_speed"), s.value(&"damage"), s.value(&"crit_damage")]
	s.set_source(&"boots_a", [[&"move_speed", Stats.PCT, 0.08]])
	s.set_source(&"boots_b", [[&"move_speed", Stats.PCT, 0.08]])
	if absf(s.value(&"move_speed") - 6.5 * 1.16) > EPS:
		return "兩個 +8%% 應為 ×1.16 = %.3f，實際 %.3f" % [6.5 * 1.16, s.value(&"move_speed")]
	s.set_source(&"sprint", [[&"move_speed", Stats.MUL, 1.6]])
	if absf(s.value(&"move_speed") - 6.5 * 1.16 * 1.6) > EPS:
		return "疾跑 ×1.6 應與百分比加成相乘，實際 %.3f" % s.value(&"move_speed")
	s.remove_source(&"sprint")
	s.remove_source(&"boots_a")
	if absf(s.value(&"move_speed") - 6.5 * 1.08) > EPS:
		return "移除來源後應剩 ×1.08，實際 %.3f" % s.value(&"move_speed")
	s.set_source(&"wormwood", [[&"cooldown", Stats.MUL, 0.94]])
	s.set_source(&"hourglass", [[&"cooldown", Stats.MUL, 0.75]])
	if absf(s.value(&"cooldown") - 0.705) > EPS:
		return "冷卻縮減應相乘為 0.705，實際 %.4f" % s.value(&"cooldown")
	s.set_source(&"dice", [[&"crit_chance", Stats.ADD, 1.5]])
	if s.value(&"crit_chance") != 1.0:
		return "爆擊率上限應為 100%%，實際 %.3f" % s.value(&"crit_chance")
	var hp := Stats.new({&"max_hp": 36.0})
	hp.set_source(&"wave", [[&"max_hp", Stats.MUL, 1.3]])
	if hp.value(&"max_hp") != 47.0:
		return "最大生命 36 × 1.3 應取整為 47，實際 %.2f" % hp.value(&"max_hp")
	if StatDefs.format_value(&"armor", 8.0) != "8（減傷 7.4%）" or StatDefs.format_value(&"cooldown", 0.705) != "70.5%":
		return "顯示格式錯誤：%s / %s" % [StatDefs.format_value(&"armor", 8.0), StatDefs.format_value(&"cooldown", 0.705)]
	return ""


# 傷害保留小數、只在顯示時取整（v0.41.0 使用者決定）：12.5 實際扣 12.5、兩下是 25；
# 傷害數字四捨五入（12.5 → 13、0.4 → 至少 1）、血量無條件進位（87.5 → 88、剩 0.4 → 1）
static func check_fractional_damage() -> String:
	var w := _new_world()
	var g := _dummy(w, Vector2(0, 3))
	var before := g.hp
	var dealt := g.take_damage(12.5, Vector2(0, 1), 0.0, 0)
	g.invuln_timer = 0.0
	g.take_damage(12.5, Vector2(0, 1), 0.0, 0)
	if absf(dealt - 12.5) > 1e-6 or absf((before - g.hp) - 25.0) > 1e-6:
		return "12.5 傷害應實際扣 12.5、兩下 25：回傳 %.4f、合計 %.4f" % [dealt, before - g.hp]
	var cases := [[UiKit.dmg_text(12.5), "13"], [UiKit.dmg_text(12.4), "12"], [UiKit.dmg_text(0.4), "1"], [UiKit.dmg_text(0.0), "0"],
		[UiKit.hp_text(87.5), "88"], [UiKit.hp_text(0.4), "1"], [UiKit.hp_text(100.0), "100"], [UiKit.hp_text(0.0), "0"]]
	for c: Array in cases:
		if c[0] != c[1]:
			return "顯示取整錯誤：%s" % [cases]
	return ""


static func check_stats_armor_crit() -> String:
	var w := _new_world()
	var p := _player(w)
	var g := _spawn(w, &"grunt", Vector2(0, 3))
	g.stats.set_base(&"max_hp", 1000.0)
	g.hp = 1000.0
	var dealt := []
	for armor in [100.0, 8.0]:
		g.stats.set_base(&"armor", armor)
		var before := g.hp
		Combat.apply_damage(w, p, g, {"damage": 20.0})
		dealt.append(before - g.hp)
	# v0.41.0 起傷害保留小數（使用者決定），原本扣血前四捨五入成 19
	var want_8 := 20.0 * 100.0 / 108.0
	if absf(dealt[0] - 10.0) > 1e-4 or absf(dealt[1] - want_8) > 1e-4:
		return "20 傷害打護甲 100 / 8 應為 10 / %.4f（20 × 100 ÷ 108，保留小數），實際 %s" % [want_8, dealt]
	g.stats.set_base(&"armor", 0.0)
	var state := w.rng.state
	w.events.clear()
	Combat.apply_damage(w, p, g, {"damage": 10.0})
	if w.rng.state != state:
		return "爆擊率 0% 時不應消耗亂數"
	if _named(w.events, "entity:damaged")[0].is_crit:
		return "爆擊率 0% 時不應爆擊"
	p.set_stat_source(&"test", [[&"crit_chance", Stats.ADD, 1.0]])
	w.events.clear()
	var hp_before := g.hp
	Combat.apply_damage(w, p, g, {"damage": 10.0})
	var ev: Dictionary = _named(w.events, "entity:damaged")[0]
	if not ev.is_crit or hp_before - g.hp != 15.0:
		return "爆擊率 100%% 應爆擊且 10 × 1.5 = 15，實際 is_crit=%s 傷害 %.1f" % [ev.is_crit, hp_before - g.hp]
	return ""


# 從按下攻擊到回到 ready 經過幾步
static func _attack_steps(w: World, p: Player) -> int:
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1)
	var steps := 1
	while not p.action.is_in(&"ready") and steps < 600:
		_run(w, _cmd(Vector2.ZERO), 1)
		steps += 1
	return steps


static func check_stats_hooks() -> String:
	var w := _new_world()
	var p := _player(w)
	var normal := _attack_steps(w, p)
	_run(w, _cmd(Vector2.ZERO), 120)   # 等連段視窗結束，下一刀回到第一段
	p.set_stat_source(&"test", [[&"attack_speed", Stats.MUL, 2.0]])
	var fast := _attack_steps(w, p)
	if absi(fast * 2 - normal) > 2:
		return "攻速 ×2 普攻應從 %d 步變約 %d 步，實際 %d 步" % [normal, normal / 2, fast]
	p.remove_stat_source(&"test")

	# 劍盾格擋 v0.41.0 起沒有冷卻，改用法杖的奧術爆裂
	p.equip_weapon(&"staff")
	p.set_stat_source(&"test", [[&"cooldown", Stats.MUL, 0.5]])
	_run(w, _cmd(Vector2.ZERO), 120)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL), 1)
	var expected: float = p.weapon.special.cooldown * 0.5
	var remaining := w.cooldowns.remaining(_player(w).cd("player.special"))
	if absf(remaining - expected) > DT * 2.0:
		return "冷卻 ×0.5：特殊技冷卻應約 %.2f 秒，實際 %.2f" % [expected, remaining]
	p.remove_stat_source(&"test")

	var w2 := _new_world()
	var p2 := _player(w2)
	var base_hp: float = Config.PLAYER.max_hp
	p2.hp = 50.0
	p2.set_stat_source(&"bread", [[&"max_hp", Stats.ADD, 20.0]])
	if p2.max_hp != base_hp + 20.0 or p2.hp != 70.0:
		return "最大生命 +20：應為 70 / %.0f，實際 %.0f / %.0f" % [base_hp + 20.0, p2.hp, p2.max_hp]
	p2.remove_stat_source(&"bread")
	if p2.max_hp != base_hp or p2.hp != 70.0:
		return "移除後應為 70 / %.0f，實際 %.0f / %.0f" % [base_hp, p2.hp, p2.max_hp]
	p2.set_stat_source(&"bandage", [[&"hp_regen", Stats.ADD, 6.0]])
	_run(w2, _cmd(Vector2.ZERO), 60)
	if absf(p2.hp - 76.0) > 0.05:
		return "每秒回 6 血，1 秒後應為 76，實際 %.2f" % p2.hp
	# 受傷後 regen_delay 秒內不回血，過了照常回
	var delay: float = Config.PLAYER.regen_delay
	p2.invuln_timer = 0.0
	p2.take_damage(10.0, Vector2.ZERO, 0.0, 0)
	var hurt_hp := p2.hp
	_run(w2, _cmd(Vector2.ZERO), roundi((delay - 0.5) / DT))
	if p2.hp != hurt_hp:
		return "受傷後 %.1f 秒內不該回血：應維持 %.2f，%.1f 秒後是 %.2f" % [delay, hurt_hp, delay - 0.5, p2.hp]
	_run(w2, _cmd(Vector2.ZERO), roundi(1.5 / DT))
	if absf(p2.hp - (hurt_hp + 6.0)) > 0.15:
		return "受傷 %.1f 秒後恢復回血：應約 %.2f，實際 %.2f" % [delay + 1.0, hurt_hp + 6.0, p2.hp]
	p2.remove_stat_source(&"bandage")

	p2.set_stat_source(&"debug", [[&"move_speed", Stats.PCT, Config.DEBUG.speed_bonus]])
	var fast_speed: float = Config.PLAYER.move_speed * (1.0 + Config.DEBUG.speed_bonus)
	if absf(p2.stats.value(&"move_speed") - fast_speed) > EPS:
		return "除錯移速應為 %.3f，實際 %.3f" % [fast_speed, p2.stats.value(&"move_speed")]
	var start := p2.pos
	_run(w2, _cmd(Vector2(1, 0)), 60)
	var moved := p2.pos.distance_to(start)
	if absf(moved - fast_speed) > fast_speed * DT * 2.0:
		return "移速 %.2f 跑 1 秒應約 %.2f 單位，實際 %.3f" % [fast_speed, fast_speed, moved]
	return ""


static func check_entity_release() -> String:
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
