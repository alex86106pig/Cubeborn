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
var _errors := _ErrorCounter.new()


# Godot 的執行期錯誤（SCRIPT ERROR）只會印出來、函式照樣往下跑，檢查本身看不出來；
# 掛一個 Logger 計數，檢查期間有任何錯誤就算失敗
class _ErrorCounter extends Logger:
	var count := 0
	var last := ""

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		count += 1
		last = "%s（%s:%d）" % [rationale if rationale != "" else code, file, line]

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _initialize() -> void:
	OS.add_logger(_errors)
	print("Cubeborn Godot 自動檢查\n")
	_check("編譯：專案內所有 .gd（含畫面層、main）都能編譯", _check_all_scripts_compile)
	_check("模擬層：sim/ 沒有使用禁止的 API（Input、節點、全域隨機、時間、讀檔、畫面層）", _check_sim_forbidden)
	_check("版號：version.gd 與 CHANGELOG 最新版一致", _check_versions)
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
	_check("格擋（v0.18.0 取代盾擊衝鋒）：按一下維持 3 秒、移速 ×0.5 可轉向；CD 4 秒、CD 中發 skill:onCooldown；翻滾可提前結束", _check_shield_block)
	_check("格擋判定：正前方 ±37.5° 擋下揮砍與箭（不扣血、箭消失）、背後擋不住；Boss 衝鋒擋得住但推退 100%、只判定一次；Boss 砸地擋不住；0.2 秒內完美格擋觸發盾反 25 傷害並結束格擋", _check_block_hits)
	_check("受擊：扣血後進入 stagger（移速 ×0.4、0.15 秒）、無敵 0.6 秒、畫面震動", _check_stagger)
	_check("輸入緩衝：攻擊中按右鍵會在後搖取消並接特殊技；0.25 秒後過期", _check_buffer)
	_check("法杖魔彈：前方 0.6 產生、20 單位/秒、命中造成 8 傷害、最遠 14 單位", _check_fire_bolt)
	_check("奧術爆裂：落點限制在 2~12、爆炸半徑 3.2 造成 28 傷害、範圍外不受傷", _check_arcane_burst)
	_check("死亡：發出 player:died、移動層進入 dead、不再接受輸入", _check_player_death)
	_check("事件：戰鬥中的事件 payload 也只含可序列化的值", _check_combat_events_serializable)
	_check("音效：模擬層 sfx:cue 的名稱都存在於網頁版 CUES", _check_sim_cues)
	_check("波次資料：共 5 波、只有最後一波是 Boss、第 1~4 波小怪 5 / 7 / 9 / 12、成長倍率線性", _check_wave_defs)
	_check("生成：1 秒後開第一波、離玩家 8 單位以上、第 3 波小怪血量 ×1.3 傷害 ×1.24", _check_spawning)
	_check("一局流程：5 波依序開始、打倒 Boss 後 is_over、2.2 秒後 game:victory、擊殺數正確", _check_full_run)
	_check("近戰小怪：爬出 0.7 秒後追擊、揮砍傷害 12、間隔 ≥ 1.2 秒（v0.17.0 取代接觸傷害 10 / 0.8 秒）；受擊硬直 0.22 秒", _check_melee_enemy)
	_check("遠程小怪：瞄準 0.75 秒後射出 12 傷害的箭、保持 6~10 單位距離", _check_ranged_enemy)
	_check("Boss 重砸：近身時前搖 0.85 秒後造成 26 傷害、CD 3.5 秒；霸體不硬直、擊退 ×0.12", _check_boss_slam)
	_check("Boss 衝鋒：蓄力 0.75 秒、15 單位/秒、命中 22 傷害、撞牆暈眩 1.6 秒", _check_boss_charge)
	_check("Boss 召喚與狂暴：血量 ≤ 75% 召喚 3 隻、≤ 50% 狂暴（移速 ×1.3、CD ×0.65）", _check_boss_summon_enrage)
	_check("碰撞分離：格子切分與兩兩比對結果一致（80 個實體）", _check_grid_matches_brute_force)
	_check("決定性：有敵人與波次時，同種子、同輸入的兩個 World 結果相同", _check_determinism_with_enemies)
	_check("記憶體：敵人移除後 CD 清除、實體會被釋放", _check_enemy_release)
	_check("治療藥水：3 次、回 35 血不超過上限、滿血不能用、間隔 1.5 秒、用完不能再用", _check_heal_slot)
	_check("疾跑：移速 6.5 × 1.6 = 10.4、持續 3 秒、CD 8 秒；使用道具動作 0.18 秒", _check_sprint_slot)
	_check("數字鍵緩衝：攻擊中按 1 會在後搖取消並使用道具；空欄位不提示", _check_slot_buffer)
	_check("HUD：能建立、處理各種事件、顯示波次 / 血量 / 結算文字、暫停畫面有「離開遊戲」", _check_hud)
	_check("屬性計算：同類相加（+8% ×2 = +16%）、暫時效果與冷卻縮減相乘（0.94 × 0.75 = 0.705）、取整、上下限、來源可移除", _check_stats_formula)
	_check("護甲與爆擊：護甲 100 減傷 50%、護甲 8 減傷 7.4%；爆擊率 100% 時 ×1.5，爆擊率 0% 不消耗亂數", _check_stats_armor_crit)
	_check("屬性接上遊戲：攻速 ×2 普攻時間減半、冷卻 ×0.5、最大生命 +20 時目前生命同步增加、每秒回血、除錯移速 +50% = 9.75", _check_stats_hooks)
	_check("物品資料：45 個道具（白 15 / 綠 12 / 藍 9 / 紫 6 / 橘 3）＋武器，名稱不重複、欄位完整、形狀合法（相連、不重複、放得進 8×6）、格數 = ceil(強度 ÷ 稀有度效率)、效果都對應到存在的屬性 / 條件 / 觸發 / 能力", _check_item_defs)
	_check("道具放進身上：磨刀石攻擊力 ×1.08、兩雙皮靴移速 ×1.16、麵包最大生命與目前生命 +20、疾風護符翻滾 2 次、移除與清空後回到原值、武器道具直接換武器、發出 item:added", _check_items_apply)
	_check("翻滾：0.35 秒翻 4 單位；移速 +50% 時同樣 0.35 秒翻 6 單位；冷卻 1.2 秒（−10% 為 1.08）；次數 +1 可連翻兩次", _check_roll_motion)
	_check("翻滾無敵：前 0.2 秒打不到、投射物穿過，之後會被打中", _check_roll_invuln)
	_check("翻滾取消：普攻前搖與後搖可取消；揮下去、特殊技（奧術爆裂）、硬直中先緩衝，結束後才翻", _check_roll_cancel)
	_check("跳躍：第 18 步最高 1.5、第 36 步落地；空中不能再跳；攻擊中可以跳、硬直中不行；空中翻滾照常下墜且一樣翻 4 單位", _check_jump_motion)
	_check("地形：0.5 石台走不上去、跳得上去；從 0.5 跳上 1.0；走出邊緣會掉回地面；2.5 的牆跳不過去", _check_terrain)
	_check("高度判定：最高點時箭從腳下飛過、地面會中箭；跳起來躲過 Boss 砸地；空中揮砍與空中魔彈打得到地上的怪", _check_height_hits)
	_check("沒有碰撞傷害：骷髏戰士（揮砍冷卻中）、弓手（不射箭時）、Boss（不出招時）貼身 2 秒都不扣血", _check_no_contact_damage)
	_check("骷髏揮砍：舉刀 0.5 秒後才命中、傷害 12；扇形 100° / 1.5 的邊界；舉刀後半鎖定方向，繞到側面就躲開；舉刀中被打會中斷", _check_grunt_swing)
	_check("打擊感：玩家打中不震動、模擬時間不放慢（hit_stop 只放進事件）；玩家被打與 Boss 砸地照常震動；沒有命中定格（v0.19.1 拿掉），打中後模型照常移動", _check_hit_feel)
	_check("受擊閃白：只改自發光顏色、不切換 emission_enabled（切換會在第一次命中即時編譯著色器而卡頓）", _check_flash_no_shader_switch)
	_check("字型：介面文字都在打包的 Noto Sans TC 裡（網頁版沒有系統字型），缺字的圖示改用向量圖", _check_font_coverage)
	_check("零件合併：依 anchor + 材質合併、外框不變、keep 的零件留在原位、空群組移除、面法線朝外且為正面", _check_merge_static)
	_check("零件數：騎士 ≤ 20、骷髏戰士 ≤ 16、骷髏弓手 ≤ 16、Boss ≤ 22、場地 ≤ 12（同網頁版上限，避免卡頓）", _check_mesh_counts)
	_check("音效檔：網頁版 CUES 每個名稱都有配方與 audio/sfx/*.wav，檔案不是空的、峰值 ≤ 1", _check_sfx_files)
	_check("背景音樂：一般 / Boss 兩首匯入後為往前循環，長度 15.00 / 10.43 秒（64 / 92 BPM × 4 小節）", _check_music_files)
	_check("音效對應：事件 → 音效同網頁版（受傷 / 爆擊 / Boss 死亡 / 道具…），Boss 波換 Boss 曲、死亡停音樂", _check_sound_mapping)
	_check("網頁版資料逐欄比對：設定、武器、敵人、技能、波次的每個數值都與 tests/web_defs.json 相同", _check_web_defs)
	_check("手感：擊退 7 推動質量 1 的目標，總位移同網頁版公式（阻尼 9、每步先移動再衰減）", _check_feel_knockback)
	_check("手感：轉身 180° 需 8 步（0.133 秒，轉速 25 弧度/秒）", _check_feel_turn)
	_check("手感：劍盾普攻前衝同網頁版公式（3.5、第三段 ×1.25），連段 0.35 秒內接下一段、超過就重來", _check_feel_lunge_combo)
	_check("手感：斬擊扇形範圍與網頁版 querySector 完全一致（距離 2.3、角度 117°、加目標半徑、貼身必中）", _check_feel_sector)
	_check("手感：生成間隔 0.35 秒、開波 0.6 秒後出第一隻、清空 2.5 秒後開下一波，步數與網頁版計時器完全相同", _check_feel_wave_timing)
	_check("手感：小怪移速 = 基礎 × 波次成長 × 隨機 ±變異、Boss 固定 2.2；弓手箭速 10、射程 18", _check_feel_enemy_speed)
	print("\n手感量測（給 docs/手感對照.md）：\n    " + "\n    ".join(_feel_lines))
	for w in _worlds:
		w.clear()
	_worlds.clear()
	print("\n%d / %d 通過" % [_passed, _passed + _failed])
	OS.remove_logger(_errors)
	quit(1 if _failed > 0 else 0)


func _check(title: String, fn: Callable) -> void:
	var errors_before := _errors.count
	var result: Variant = fn.call()
	var err: String = result if result is String else "檢查函式沒有回傳結果"
	if _errors.count > errors_before:
		err = "執行期間發生 %d 個錯誤，最後一個：%s" % [_errors.count - errors_before, _errors.last]
	if err == "":
		_passed += 1
		print("✔ ", title)
	else:
		_failed += 1
		print("✘ ", title, "\n    ", err)


# ---- 工具 ----

# 預設關掉生成器，只測玩家；要測波次時傳 with_spawner = true
func _new_world(seed_value: int = 12345, with_spawner: bool = false) -> World:
	var w := World.new()
	w.reset(seed_value)
	w.spawner.finished = not with_spawner
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
	var text := _read_text(root.path_join("legacy/src/audio/Sound.js"))
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

# 畫面層與 main.gd 不會被其他檢查載入；編譯錯誤只會出現在匯入紀錄裡，容易漏看
func _check_all_scripts_compile() -> String:
	var broken: Array[String] = []
	for path in _list_gd("res://"):
		if path.begins_with("res://.godot") or path.begins_with("res://tests/"):
			continue
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			broken.append(path)
	return "無法編譯：" + ", ".join(broken) if not broken.is_empty() else ""


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
	var changelog := _read_text(root.path_join("CHANGELOG.md"))
	var cl_ver := RegEx.create_from_string("## \\[([^\\]]+)\\]").search(changelog)
	if cl_ver == null:
		return "讀不到 CHANGELOG.md 的版號"
	if cl_ver.get_string(1) != GameVersion.VERSION:
		return "version.gd=%s CHANGELOG=%s" % [GameVersion.VERSION, cl_ver.get_string(1)]
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
	# 重擊（顯示與音效）只有第三段；爆擊率預設 0%，不會有真正的爆擊
	var heavies := _named(events, "entity:damaged").map(func(e: Dictionary) -> bool: return e.is_heavy)
	if heavies != [false, false, true]:
		return "is_heavy 應只有第三段為 true，實際 %s" % [heavies]
	var crits := _named(events, "entity:damaged").map(func(e: Dictionary) -> bool: return e.is_crit)
	if crits != [false, false, false]:
		return "爆擊率 0%% 時 is_crit 應全為 false，實際 %s" % [crits]
	var sfx := _named(events, "sfx:cue").map(func(e: Dictionary) -> String: return e.cue)
	if sfx != ["swing", "swing", "swingHeavy"]:
		return "音效 %s，預期 swing / swing / swingHeavy" % [sfx]
	return ""


func _check_shield_block() -> String:
	var w := _new_world()
	var p := _player(w)
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(5, 0), InputCmd.BTN_SPECIAL), 1, events)
	if not p.action.is_in(&"special") or p.block_time < 0.0 or _named(events, "skill:used").is_empty():
		return "右鍵後應開始格擋並發出 skill:used"
	# 格擋中可以移動（×0.5）、會轉向瞄準點
	_run(w, _cmd(Vector2(0, 1), Vector2(5, 0)), 20)
	var aim_angle := MathUtil.angle_to(p.pos, Vector2(5, 0))   # 邊走邊瞄準固定點，朝向要用目前位置算
	if absf(p.velocity.length() - 6.5 * 0.5) > EPS or absf(angle_difference(p.facing, aim_angle)) > 0.05:
		return "格擋中移速 %.3f（預期 3.25）、朝向 %.2f（預期 %.2f）" % [p.velocity.length(), p.facing, aim_angle]
	var steps := 21
	while p.block_time >= 0.0 and steps < 400:
		_run(w, _cmd(Vector2.ZERO, Vector2(5, 0)), 1)
		steps += 1
	if absi(steps - roundi(3.0 / DT)) > 2:
		return "格擋應維持約 %d 步，實際 %d 步" % [roundi(3.0 / DT), steps]
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(5, 0), InputCmd.BTN_SPECIAL), 2, events)
	if _named(events, "skill:onCooldown").is_empty() or p.block_time >= 0.0:
		return "CD 中按右鍵應發出 skill:onCooldown 且不格擋"
	var remaining := w.cooldowns.remaining("player.special")
	var elapsed := w.tick * DT
	if absf(remaining - (4.0 - elapsed + DT)) > DT * 1.5:
		return "CD 剩餘 %.3f 秒，預期約 %.3f" % [remaining, 4.0 - elapsed + DT]
	# 翻滾可以提前結束格擋
	var w2 := _new_world()
	var p2 := _player(w2)
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL), 10)
	_run(w2, _cmd(Vector2(1, 0), Vector2(0, 5), InputCmd.BTN_ROLL), 1)
	if not p2.action.is_in(&"roll") or p2.block_time >= 0.0:
		return "格擋中按翻滾應結束格擋並翻滾，實際狀態 %s" % p2.action.current_name
	return ""


func _check_block_hits() -> String:
	var front := Vector2(0, -5)   # 骷髏在玩家 -Z 方向（_grunt_swinging 的配置）
	# 一般格擋：骷髏舉刀時就開始格擋，命中時已超過 0.2 秒 → 擋下但不是完美格擋
	var w := _new_world()
	var p := _player(w)
	var g := _grunt_swinging(w, p)
	_run(w, _cmd(Vector2.ZERO, front, InputCmd.BTN_SPECIAL), 1)
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO, front), 40, events)
	var blocked := _named(events, "player:blocked")
	if p.hp != p.max_hp or blocked.size() != 1 or blocked[0].perfect:
		return "正面應擋下揮砍（非完美）：血量 %.0f、blocked 事件 %s" % [p.hp, blocked]
	# 背對：擋不住
	var w2 := _new_world()
	var p2 := _player(w2)
	_grunt_swinging(w2, p2)
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, 10), InputCmd.BTN_SPECIAL), 1)
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, 10)), 40)
	if p2.hp >= p2.max_hp:
		return "背對骷髏格擋應擋不住"
	# 完美格擋：先面向骷髏，在命中前約 0.15 秒才按右鍵 → 擋下、下一步盾反 25 傷害並結束格擋
	var w3 := _new_world()
	var p3 := _player(w3)
	var g3 := _grunt_swinging(w3, p3)
	var s: Dictionary = EnemyDefs.ENEMIES.grunt.swing
	_run(w3, _cmd(Vector2.ZERO, front), roundi((s.windup - 0.15) / DT) - 1)
	var g_hp := g3.hp
	var ev3: Array[Dictionary] = []
	_run_collect(w3, _cmd(Vector2.ZERO, front, InputCmd.BTN_SPECIAL), 1, ev3)
	_run_collect(w3, _cmd(Vector2.ZERO, front), 15, ev3)
	var b3 := _named(ev3, "player:blocked")
	if b3.size() != 1 or not b3[0].perfect or p3.hp != p3.max_hp:
		return "0.2 秒內擋下應為完美格擋：%s、血量 %.0f" % [b3, p3.hp]
	if g_hp - g3.hp != 25.0 or p3.block_time >= 0.0:
		return "盾反應造成 25 傷害並結束格擋：傷害 %.0f、格擋 %s" % [g_hp - g3.hp, p3.block_time >= 0.0]
	# 箭：正面擋下並消失
	var w4 := _new_world()
	var p4 := _player(w4)
	var archer := _spawn(w4, &"archer", Vector2(0, 15))
	_run(w4, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL), 20)
	var arrow := Projectile.new(w4, {"owner": archer, "pos": p4.pos + Vector2(0, 1.5), "direction": Vector2(0, -1),
		"speed": 10.0, "range": 5.0, "damage": 12.0, "altitude": Config.HEIGHT.arrow_altitude, "blockable": true})
	w4.spawn_projectile(arrow)
	_run(w4, _cmd(Vector2.ZERO, Vector2(0, 5)), 20)
	if not arrow.is_removed or p4.hp != p4.max_hp:
		return "正面應擋下箭（箭消失、不扣血）：removed=%s 血量 %.0f" % [arrow.is_removed, p4.hp]
	# Boss 衝鋒（v0.18.2）：正面擋得住、不扣血、只判定一次，但被推退得比一般格擋遠（100% 擊退）
	var w6 := _new_world()
	var p6 := _player(w6)
	var boss6 := _spawn(w6, &"boss", Vector2(0, 8.0))
	_run(w6, _cmd(Vector2.ZERO, Vector2(0, 8)), roundi(EnemyDefs.ENEMIES.boss.spawn_time / DT) + 2)
	boss6.facing = PI
	boss6.fsm.change(&"charge")
	_run(w6, _cmd(Vector2.ZERO, Vector2(0, 8), InputCmd.BTN_SPECIAL), 1)
	var ev6: Array[Dictionary] = []
	var push := 0.0   # 擋下那一步的被動推退速度（Boss 本身的推擠不算在內）
	for i in 90:
		_run_collect(w6, _cmd(Vector2.ZERO, boss6.pos), 1, ev6)
		if push == 0.0 and not _named(w6.events, "player:blocked").is_empty():
			push = p6.knockback.length()
	var b6 := _named(ev6, "player:blocked")
	if p6.hp != p6.max_hp or b6.size() != 1:
		return "正面應擋下 Boss 衝鋒且只判定一次：血量 %.0f、blocked %d 次" % [p6.hp, b6.size()]
	# 衝鋒擊退 18 ÷ 玩家質量 2 = 9，同一步衰減一次後約 7.7；一般格擋 30% 只有約 2.3
	var expected_push: float = EnemyDefs.ENEMIES.boss.charge.knockback / Config.PLAYER.mass * exp(-Config.COMBAT.knockback_damping * DT)
	if absf(push - expected_push) > 0.05:
		return "擋下衝鋒的推退速度應約 %.2f（100%% 擊退），實際 %.2f" % [expected_push, push]
	# Boss 砸地：格擋也擋不住
	var w5 := _new_world()
	var p5 := _player(w5)
	var boss := _spawn(w5, &"boss", Vector2(0, 2.0))
	_run(w5, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL), 20)
	boss.slam_impact()
	if p5.hp >= p5.max_hp:
		return "Boss 砸地不能被格擋"
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
	# 劍盾：前搖中按右鍵 → 後搖第一步取消 → 下一步接格擋（不等攻擊自然結束的第 23 步）
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
		return "格擋在第 %d 步才開始，應在攻擊後搖時取消（第 23 步之前）" % started
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


func _spawn(w: World, type: StringName, at: Vector2) -> Enemy:
	return w.spawner.spawn_at(w, type, at)


# 跑到 pred 成立為止（最多 max_steps 步），回傳跑了幾步；沒成立回傳 -1
func _run_until(w: World, cmd: InputCmd, max_steps: int, events: Array[Dictionary], pred: Callable) -> int:
	for i in max_steps:
		w.step({World.HOST_PEER_ID: cmd}, DT)
		events.append_array(w.events)
		if pred.call():
			return i + 1
	return -1


func _check_sim_cues() -> String:
	var cues := _web_cue_names()
	var re := RegEx.create_from_string("\"cue\": \"(\\w+)\"")
	var count := 0
	for path in _list_gd("res://sim"):
		for m in re.search_all(_read_text(path)):
			count += 1
			if not cues.has(m.get_string(1)):
				return "%s 的音效「%s」不在網頁版 CUES" % [path, m.get_string(1)]
	if count < 8:   # 目前 sim/ 有 9 個字面音效名稱；玩家武器音效走變數，由「武器資料」檢查負責
		return "只比對到 %d 個 sfx:cue，比對規則可能失效" % count
	return ""


func _check_wave_defs() -> String:
	var waves := WaveDefs.WAVES
	if waves.size() != 5:
		return "共 %d 波，預期 5" % waves.size()
	var minions := []
	for i in waves.size():
		var w: Dictionary = waves[i]
		if w.get("is_boss", false) != (i == 4):
			return "第 %d 波 is_boss 不正確" % (i + 1)
		var n := 0
		for type: StringName in w.spawns:
			if not EnemyDefs.ENEMIES.has(type):
				return "第 %d 波的敵人類型「%s」不存在" % [i + 1, type]
			if type != &"boss":
				n += w.spawns[type]
		minions.append(n)
	if minions.slice(0, 4) != [5, 7, 9, 12]:
		return "第 1~4 波小怪數 %s" % [minions.slice(0, 4)]
	var m1 := WaveDefs.wave_multipliers(1)
	var m3 := WaveDefs.wave_multipliers(3)
	if m1.hp != 1.0 or m1.damage != 1.0 or absf(m3.hp - 1.3) > EPS or absf(m3.damage - 1.24) > EPS or absf(m3.speed - 1.06) > EPS:
		return "倍率錯誤：第 1 波 %s、第 3 波 %s" % [m1, m3]
	return ""


func _check_spawning() -> String:
	var w := _new_world(4242, true)
	var events: Array[Dictionary] = []
	var steps := _run_until(w, _cmd(Vector2.ZERO), 300, events, func() -> bool: return not _named(events, "wave:started").is_empty())
	if absi(steps - 60) > 1:
		return "第一波在第 %d 步開始，預期約 60 步（1 秒）" % steps
	# 逐步記錄每隻敵人剛出現時離玩家的距離（之後會追過來，不能等全部生完才量）
	var p := _player(w)
	var seen := {}
	for i in ceili((0.6 + 4 * 0.35) / DT) + 8:   # 計時器以浮點遞減，每段可能多 1 步
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		for e in w.enemies:
			if not seen.has(e.id):
				seen[e.id] = e.pos.distance_to(p.pos)
	if seen.size() != 5:
		return "第一波生成 %d 隻，預期 5" % seen.size()
	for id: int in seen:
		if seen[id] < 8.0:
			return "敵人生成在離玩家 %.2f 處，應 ≥ 8" % seen[id]
	w.spawner.wave = 3
	var g := _spawn(w, &"grunt", Vector2(10, 10))
	if g.max_hp != 47.0 or absf(g.damage_mul - 1.24) > EPS:
		return "第 3 波小怪 max_hp=%.1f damage_mul=%.3f，預期 47 / 1.24" % [g.max_hp, g.damage_mul]
	return ""


func _check_full_run() -> String:
	var w := _new_world(99, true)
	var p := _player(w)
	var events: Array[Dictionary] = []
	var enemy_deaths := 0
	var boss_died_tick := -1
	for i in 60 * 120:
		p.invuln_timer = 1.0   # 這項只測流程，不讓玩家被打死
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		events.append_array(w.events)
		for e in w.enemies:
			if not e.is_dead:
				e.die()
				enemy_deaths += 1
				if (e as Enemy).is_boss():
					boss_died_tick = w.tick
		if not _named(events, "game:victory").is_empty():
			break
	var started := _named(events, "wave:started")
	if started.size() != 5 or not started[4].is_boss:
		return "wave:started %d 次（預期 5，最後一波是 Boss）" % started.size()
	var victory := _named(events, "game:victory")
	if victory.is_empty() or not w.is_over:
		return "打倒 Boss 後沒有通關"
	var delay := (w.tick - boss_died_tick) * DT
	if absf(delay - 2.2) > DT * 1.5:
		return "Boss 倒下到 game:victory 經過 %.3f 秒，預期 2.2" % delay
	if victory[0].stats.kills != enemy_deaths or w.stats.wave != 5:
		return "擊殺數 %d（實際打倒 %d）、wave=%d" % [victory[0].stats.kills, enemy_deaths, w.stats.wave]
	return ""


func _check_melee_enemy() -> String:
	var w := _new_world(7)
	var p := _player(w)
	var g := _spawn(w, &"grunt", Vector2(0, 4))
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO), ceili(0.7 / DT) - 1, events)
	if not g.fsm.is_in(&"spawn") or g.velocity != Vector2.ZERO:
		return "爬出期間應停在 spawn 且不移動"
	_run_collect(w, _cmd(Vector2.ZERO), 2, events)
	if not g.fsm.is_in(&"chase"):
		return "0.7 秒後應進入 chase，實際 %s" % g.fsm.current_name
	var hit_ticks: Array[int] = []
	for i in 60 * 5:
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		for e in _named(w.events, "entity:damaged"):
			if e.target_id == p.id:
				if e.amount != 12:
					return "揮砍傷害 %d，預期 12" % e.amount
				hit_ticks.append(w.tick)
	if hit_ticks.size() < 3:
		return "5 秒內只命中 %d 次" % hit_ticks.size()
	for i in range(1, hit_ticks.size()):
		if (hit_ticks[i] - hit_ticks[i - 1]) * DT < 1.2 - EPS:
			return "揮砍間隔 %.3f 秒，應 ≥ 1.2（冷卻）" % ((hit_ticks[i] - hit_ticks[i - 1]) * DT)
	# 受擊硬直
	var w2 := _new_world(7)
	var g2 := _spawn(w2, &"grunt", Vector2(0, 6))
	_run(w2, _cmd(Vector2.ZERO), ceili(0.7 / DT) + 2)
	g2.take_damage(5.0, Vector2(0, 1), 0.0, 0)
	if not g2.fsm.is_in(&"hurt"):
		return "受擊應進入 hurt，實際 %s" % g2.fsm.current_name
	_run(w2, _cmd(Vector2.ZERO), ceili(0.22 / DT) + 1)
	if not g2.fsm.is_in(&"chase"):
		return "0.22 秒後應回到 chase，實際 %s" % g2.fsm.current_name
	return ""


func _check_ranged_enemy() -> String:
	var w := _new_world(11)
	var p := _player(w)
	var a := _spawn(w, &"archer", Vector2(0, 8))
	var events: Array[Dictionary] = []
	var aim_tick := -1
	var shot_tick := -1
	for i in 60 * 6:
		p.hp = p.max_hp   # 只測弓手行為，不讓玩家死
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		events.append_array(w.events)
		if aim_tick < 0 and a.fsm.is_in(&"aim"):
			aim_tick = w.tick
		if aim_tick >= 0 and shot_tick < 0 and not _named(w.events, "sfx:cue").filter(func(e: Dictionary) -> bool: return e.cue == "arrowShot").is_empty():
			shot_tick = w.tick
	if aim_tick < 0 or shot_tick < 0:
		return "6 秒內沒有瞄準 / 射擊"
	var aim_len := (shot_tick - aim_tick) * DT
	if absf(aim_len - 0.75) > DT * 1.5:
		return "瞄準到射擊 %.3f 秒，預期 0.75" % aim_len
	var arrows := _named(events, "entity:damaged").filter(func(e: Dictionary) -> bool: return e.target_id == p.id and e.amount == 12)
	if arrows.is_empty():
		return "箭沒有造成 12 傷害（玩家受到 %s）" % [_damage_amounts(events, p.id)]
	var dist := a.pos.distance_to(p.pos)
	if dist < 5.5 or dist > 10.5:
		return "6 秒後與玩家距離 %.2f，應保持在 6~10 附近" % dist
	return ""


func _check_boss_slam() -> String:
	var w := _new_world(3)
	var p := _player(w)
	var b := _spawn(w, &"boss", Vector2(0, 3))
	if w.boss_id != b.id:
		return "world.boss_id 沒有記錄 Boss"
	var events: Array[Dictionary] = []
	var slam_start := _run_until(w, _cmd(Vector2.ZERO), 60 * 4, events, func() -> bool: return b.fsm.is_in(&"slam"))
	if slam_start < 0:
		return "4 秒內沒有重砸（狀態 %s）" % b.fsm.current_name
	var start_tick := w.tick
	var hit := _run_until(w, _cmd(Vector2.ZERO), 120, events, func() -> bool: return not _damage_amounts(w.events, p.id).is_empty())
	if hit < 0 or _damage_amounts(w.events, p.id) != [26]:
		return "重砸傷害 %s，預期 [26]" % [_damage_amounts(events, p.id)]
	var windup := (w.tick - start_tick) * DT
	if absf(windup - 0.85) > DT * 1.5:
		return "前搖 %.3f 秒，預期 0.85" % windup
	var cd := w.cooldowns.remaining(b.cd("slam"))
	if absf(cd - (3.5 - windup)) > DT * 2:
		return "重砸 CD 剩 %.3f，預期約 %.3f" % [cd, 3.5 - windup]
	b.take_damage(10.0, Vector2(0, 1), 100.0, p.id)
	if b.fsm.is_in(&"hurt") or absf(b.knockback.length() - 100.0 * 0.12 / 30.0) > EPS:
		return "Boss 不應硬直，擊退應為 100 × 0.12 / 質量 30 = 0.4，實際 %.3f" % b.knockback.length()
	return ""


func _check_boss_charge() -> String:
	var w := _new_world(5)
	var p := _player(w)
	p.pos = Vector2(0, 11)
	var b := _spawn(w, &"boss", Vector2(0, 2))
	var events: Array[Dictionary] = []
	if _run_until(w, _cmd(Vector2.ZERO), 60 * 5, events, func() -> bool: return b.fsm.is_in(&"charge")) < 0:
		return "5 秒內沒有衝鋒（狀態 %s）" % b.fsm.current_name
	var windup_steps := _run_until(w, _cmd(Vector2.ZERO), 120, events, func() -> bool: return b.fsm.data.phase == &"dash")
	if absf(windup_steps * DT - 0.75) > DT * 1.5:
		return "蓄力 %.3f 秒，預期 0.75" % (windup_steps * DT)
	_run_collect(w, _cmd(Vector2.ZERO), 1, events)
	if absf(b.velocity.length() - 15.0) > EPS:
		return "衝刺速度 %.3f，預期 15" % b.velocity.length()
	# 命中後把玩家移出路線，否則玩家被擊退到牆邊會擋住 Boss，測不到撞牆
	if _run_until(w, _cmd(Vector2.ZERO), 60, events, func() -> bool: return not _damage_amounts(w.events, p.id).is_empty()) < 0:
		return "衝刺沒有撞到玩家"
	p.pos = Vector2(-12, -12)
	if _run_until(w, _cmd(Vector2.ZERO), 120, events, func() -> bool: return b.fsm.data.get("phase") == &"stunned") < 0:
		return "沒有撞牆暈眩（階段 %s）" % b.fsm.data.get("phase")
	if not _damage_amounts(events, p.id).has(22):
		return "衝鋒命中傷害 %s，應含 22" % [_damage_amounts(events, p.id)]
	if _named(events, "sfx:cue").filter(func(e: Dictionary) -> bool: return e.cue == "bossWallHit").is_empty():
		return "撞牆應發出 bossWallHit"
	var stun := _run_until(w, _cmd(Vector2.ZERO), 200, events, func() -> bool: return not b.fsm.is_in(&"charge"))
	if absf(stun * DT - 1.6) > DT * 1.5:
		return "暈眩 %.3f 秒，預期 1.6" % (stun * DT)
	return ""


func _check_boss_summon_enrage() -> String:
	var w := _new_world(8)
	var p := _player(w)
	var b: Boss = _spawn(w, &"boss", Vector2(0, -10))
	b.hp = 600.0   # ≤ 75%
	var events: Array[Dictionary] = []
	if _run_until(w, _cmd(Vector2.ZERO), 60 * 4, events, func() -> bool: return b.fsm.is_in(&"summon")) < 0:
		return "血量 600/900 時 4 秒內沒有召喚（狀態 %s）" % b.fsm.current_name
	_run_collect(w, _cmd(Vector2.ZERO), ceili(1.0 / DT) + 1, events)
	var minions := w.enemies.filter(func(e: Entity) -> bool: return e.kind == &"grunt")
	if minions.size() != 3:
		return "召喚 %d 隻，預期 3" % minions.size()
	for m in minions:
		if absf(m.pos.distance_to(b.pos) - 2.5) > 0.3:
			return "召喚的小怪離 Boss %.2f，預期 2.5" % m.pos.distance_to(b.pos)
	Combat.apply_damage(w, p, b, {"damage": 160.0})
	if not b.is_enraged or _named(w.events, "boss:enraged").is_empty():
		return "血量 %.0f/900 應進入狂暴" % b.hp
	if absf(b.enrage_mul("speed_mul") - 1.3) > EPS or absf(b.enrage_mul("cooldown_mul") - 0.65) > EPS:
		return "狂暴倍率錯誤"
	for m in minions:
		m.die()
	if _run_until(w, _cmd(Vector2.ZERO), 60 * 3, events, func() -> bool: return b.fsm.is_in(&"chase") and b.velocity != Vector2.ZERO) < 0:
		return "狂暴後沒有回到追擊"
	if absf(b.velocity.length() - 2.2 * 1.3) > EPS:
		return "狂暴移速 %.3f，預期 %.3f" % [b.velocity.length(), 2.2 * 1.3]
	return ""


func _check_grid_matches_brute_force() -> String:
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


func _check_determinism_with_enemies() -> String:
	var w1 := _new_world(31337, true)
	var w2 := _new_world(31337, true)
	var cmd := _cmd(Vector2(0.3, -0.2), Vector2(4, 3), InputCmd.BTN_ATTACK)
	for i in 60 * 12:
		for w in [w1, w2]:
			w.step({World.HOST_PEER_ID: cmd}, DT)
	if w1.entities.size() != w2.entities.size() or w1.rng.state != w2.rng.state:
		return "實體數或隨機數狀態不同（%d / %d）" % [w1.entities.size(), w2.entities.size()]
	for id: int in w1.entities:
		if not w2.entities.has(id) or w1.entities[id].pos != w2.entities[id].pos:
			return "實體 %d 位置不同" % id
	if w1.enemies.is_empty() and w1.stats.kills == 0:
		return "12 秒內沒有任何敵人，情境無效"
	return ""


func _check_enemy_release() -> String:
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


func _press_slot(w: World, index: int, events: Array[Dictionary], move: Vector2 = Vector2.ZERO) -> void:
	_run_collect(w, _cmd(move, Vector2(0, 5), InputCmd.slot_bit(index)), 1, events)


func _check_heal_slot() -> String:
	var w := _new_world()
	var p := _player(w)
	var events: Array[Dictionary] = []
	_press_slot(w, 0, events)
	if _named(events, "skill:onCooldown").is_empty() or p.slots.slots[0].charges != 3:
		return "滿血時使用應被擋下（skill:onCooldown）且不扣次數"
	p.hp = 50.0
	events.clear()
	_press_slot(w, 0, events)
	if p.hp != 85.0 or p.slots.slots[0].charges != 2 or not p.action.is_in(&"useItem"):
		return "50 血喝藥後 hp=%.0f charges=%d 狀態=%s，預期 85 / 2 / useItem" % [p.hp, p.slots.slots[0].charges, p.action.current_name]
	var healed := _named(events, "entity:healed")
	if healed.is_empty() or healed[0].amount != 35:
		return "entity:healed 應為 35"
	_run(w, _cmd(Vector2.ZERO), 20)
	events.clear()
	_press_slot(w, 0, events)
	if p.slots.slots[0].charges != 2 or _named(events, "skill:onCooldown").is_empty():
		return "1.5 秒內再喝應被擋下"
	_run(w, _cmd(Vector2.ZERO), ceili(1.5 / DT))
	p.hp = 90.0
	events.clear()
	_press_slot(w, 0, events)
	if p.hp != 100.0 or _named(events, "entity:healed")[0].amount != 10:
		return "90 血喝藥應補到 100（回 10），實際 hp=%.0f" % p.hp
	_run(w, _cmd(Vector2.ZERO), ceili(1.5 / DT) + 1)
	p.hp = 10.0
	_press_slot(w, 0, events)
	_run(w, _cmd(Vector2.ZERO), ceili(1.5 / DT) + 1)
	events.clear()
	_press_slot(w, 0, events)
	if p.slots.slots[0].charges != 0 or p.hp != 45.0 or _named(events, "skill:onCooldown").is_empty():
		return "3 次用完後不能再喝：charges=%d hp=%.0f" % [p.slots.slots[0].charges, p.hp]
	return ""


func _check_sprint_slot() -> String:
	var w := _new_world()
	var p := _player(w)
	var events: Array[Dictionary] = []
	_press_slot(w, 1, events, Vector2(1, 0))
	if not p.action.is_in(&"useItem"):
		return "按 2 應進入 useItem，實際 %s" % p.action.current_name
	var item_steps := 1
	while p.action.is_in(&"useItem") and item_steps < 60:
		_run(w, _cmd(Vector2(1, 0)), 1)
		item_steps += 1
	if item_steps - 1 != ceili(0.18 / DT):
		return "使用道具動作 %d 步，預期 %d" % [item_steps - 1, ceili(0.18 / DT)]
	if absf(p.velocity.length() - 6.5 * 1.6) > EPS:
		return "疾跑移速 %.3f，預期 10.4" % p.velocity.length()
	if p.anim.trail_color == null:
		return "疾跑中 anim.trail_color 應有顏色（給畫面畫殘影）"
	_run(w, _cmd(Vector2(1, 0)), ceili(3.0 / DT) - item_steps + 2)
	if absf(p.velocity.length() - 6.5) > EPS:
		return "3 秒後移速 %.3f，應回到 6.5" % p.velocity.length()
	var cd := w.cooldowns.remaining(ActiveSlots.cd_key(1))
	var elapsed := (w.tick - 1) * DT
	if absf(cd - (8.0 - elapsed)) > DT * 1.5:
		return "疾跑 CD 剩 %.3f，預期約 %.3f" % [cd, 8.0 - elapsed]
	return ""


func _check_slot_buffer() -> String:
	var w := _new_world()
	var p := _player(w)
	p.hp = 40.0
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1)
	_run(w, _cmd(Vector2.ZERO), 1)
	var events: Array[Dictionary] = []
	_press_slot(w, 0, events)
	var started := -1
	for i in 30:
		_run(w, _cmd(Vector2.ZERO), 1)
		if p.action.is_in(&"useItem"):
			started = w.tick
			break
	if started < 0 or started >= 23 or p.hp != 75.0:
		return "攻擊中按 1：第 %d 步才使用、hp=%.0f（應在後搖取消並回到 75）" % [started, p.hp]
	events.clear()
	_press_slot(w, 3, events)
	_run_collect(w, _cmd(Vector2.ZERO), 30, events)
	if not _named(events, "skill:onCooldown").is_empty():
		return "空欄位不應發出 skill:onCooldown"
	return ""


# -s 執行的檢查腳本在 autoload 註冊前就編譯，不能直接寫 HUD / GameEvents 型別（hud.gd 引用了 GameEvents），
# 所以 HUD 用 load() 在執行時載入、變數不寫型別，事件直接交給 HUD
func _feed_hud(hud: Node, events: Array[Dictionary]) -> void:
	for e in events:
		hud._on_event(e.name, e)


func _check_hud() -> String:
	var w := _new_world(5, true)
	var cam := Camera3D.new()
	root.add_child(cam)
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w, cam)
	root.add_child(hud)
	var p := _player(w)
	hud._process(DT)
	if hud._wave.text != "準備中" or hud._hp.text.text != "100 / 100":
		return "開場文字錯誤：%s / %s" % [hud._wave.text, hud._hp.text.text]
	_run(w, _cmd(Vector2.ZERO), 70)
	_feed_hud(hud, w.events)
	hud._process(DT)
	if hud._wave.text != "第 1 / 5 波":
		return "波次文字 %s" % hud._wave.text
	var b := _spawn(w, &"boss", Vector2(5, 5))
	_run(w, _cmd(Vector2.ZERO), 30)
	Combat.apply_damage(w, p, b, {"damage": 500.0, "is_heavy": true})
	p.hp = 50.0
	Combat.apply_damage(w, b, p, {"damage": 10.0})
	_feed_hud(hud, w.events)
	hud._process(DT)
	if not hud._boss_box.visible or not hud._boss_name.text.contains("狂暴"):
		return "Boss 血條應顯示且標示狂暴：visible=%s name=%s" % [hud._boss_box.visible, hud._boss_name.text]
	if hud._floaters.get_child_count() < 2:
		return "應產生浮動數字，實際 %d 個" % hud._floaters.get_child_count()
	w.events.clear()
	p.add_item(&"loaded_dice")
	_feed_hud(hud, w.events)
	if hud._banner.text != "獲得 灌鉛骰子\n爆擊率 +6%":
		return "item:added 橫幅文字錯誤：%s" % hud._banner.text
	for name in ["game:paused", "player:died", "game:victory", "game:restart"]:
		var payload := {"paused": true, "stats": w.stats.duplicate()}
		hud._on_event(name, payload)
	if hud._game_over.visible or hud._pause.visible:
		return "game:restart 後結算與暫停畫面應隱藏"
	if hud._quit_button.get_parent() == null or not hud._pause.is_ancestor_of(hud._quit_button) or not hud._quit_button.visible:
		return "暫停畫面應有可見的「離開遊戲」按鈕"
	var quit_count := [0]
	hud.quit_requested.connect(func() -> void: quit_count[0] += 1)
	hud._quit_button.pressed.emit()
	if quit_count[0] != 1:
		return "按下「離開遊戲」應發出 quit_requested 一次，實際 %d 次" % quit_count[0]
	hud._on_event("game:victory", {"stats": w.stats.duplicate()})
	if not hud._game_over.visible or hud._game_over_title.text != "勝利！":
		return "game:victory 應顯示勝利畫面"
	hud.queue_free()
	cam.queue_free()
	return ""


func _check_stats_formula() -> String:
	var s := Stats.new({&"move_speed": 6.5})
	if s.value(&"move_speed") != 6.5 or s.value(&"damage") != 1.0 or s.value(&"crit_damage") != 1.5:
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


func _shape_error(cells: Array) -> String:
	if cells.is_empty():
		return "沒有格子"
	var seen := {}
	var max_cell := Vector2i.ZERO
	var min_cell := Vector2i(999, 999)
	for c: Vector2i in cells:
		if seen.has(c):
			return "格子重複 %s" % c
		seen[c] = true
		min_cell = min_cell.min(c)
		max_cell = max_cell.max(c)
	if min_cell != Vector2i.ZERO:
		return "沒有從 (0, 0) 開始（最小 %s）" % min_cell
	var size := max_cell + Vector2i.ONE
	var bag := ItemDefs.BAG_SIZE
	if not ((size.x <= bag.x and size.y <= bag.y) or (size.y <= bag.x and size.x <= bag.y)):
		return "%d×%d 放不進背包" % [size.x, size.y]
	# 上下左右相連
	var stack: Array = [cells[0]]
	var reached := {cells[0]: true}
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if seen.has(c + d) and not reached.has(c + d):
				reached[c + d] = true
				stack.append(c + d)
	if reached.size() != cells.size():
		return "格子沒有相連"
	return ""


func _params_error(e: Dictionary, table: Dictionary, key: String) -> String:
	if not table.has(e[key]):
		return "%s 不存在：%s" % [key, e[key]]
	for p: String in table[e[key]].get("params", []):
		if not e.has(p):
			return "%s %s 缺少參數 %s" % [key, e[key], p]
	return ""


func _effect_error(e: Dictionary) -> String:
	var kinds := 0
	for k in ["when", "on", "ability"]:
		if e.has(k):
			kinds += 1
	if kinds > 1:
		return "一筆效果只能是一種：%s" % e
	if e.has("stat") or e.has("when"):
		if not (e.has("stat") and e.has("op") and e.has("value")):
			return "屬性效果缺 stat / op / value：%s" % e
		if not StatDefs.STATS.has(e.stat):
			return "屬性不存在：%s" % e.stat
		if not e.op in [Stats.ADD, Stats.PCT, Stats.MUL]:
			return "運算不存在：%s" % e.op
		if e.op == Stats.MUL and e.value <= 0.0:
			return "相乘的數值必須大於 0：%s" % e
		return _params_error(e, ItemDefs.CONDITIONS, "when") if e.has("when") else ""
	if e.has("on"):
		if not e.has("do"):
			return "觸發效果缺 do：%s" % e
		if e.has("chance") and not (e.chance > 0.0 and e.chance <= 1.0):
			return "機率要在 (0, 1]：%s" % e
		var err := _params_error(e, ItemDefs.TRIGGERS, "on")
		return err if err != "" else _params_error(e, ItemDefs.ACTIONS, "do")
	if e.has("ability"):
		return _params_error(e, ItemDefs.ABILITIES, "ability")
	return "看不出是哪一種效果：%s" % e


func _check_item_defs() -> String:
	for shape: StringName in ItemDefs.SHAPES:
		var err := _shape_error(ItemDefs.SHAPES[shape])
		if err != "":
			return "形狀 %s：%s" % [shape, err]
	var counts := {}
	var names := {}
	for id: StringName in ItemDefs.ITEMS:
		var def: Dictionary = ItemDefs.ITEMS[id]
		for field in ["kind", "name", "rarity", "shape", "desc", "effects"]:
			if not def.has(field):
				return "%s 缺少欄位 %s" % [id, field]
		if names.has(def.name):
			return "名稱重複：%s（%s 與 %s）" % [def.name, names[def.name], id]
		names[def.name] = id
		if not ItemDefs.RARITIES.has(def.rarity):
			return "%s 的稀有度不存在：%s" % [id, def.rarity]
		if not ItemDefs.SHAPES.has(def.shape):
			return "%s 的形狀不存在：%s" % [id, def.shape]
		match def.kind:
			&"weapon":
				if not WeaponDefs.WEAPONS.has(def.get("weapon", &"")):
					return "%s 對應的武器不存在：%s" % [id, def.get("weapon")]
			&"item":
				if not (def.get("power", 0.0) > 0.0):
					return "%s 缺少強度分數 power" % id
				if def.effects.is_empty():
					return "%s 沒有效果" % id
				if ItemDefs.cell_count(id) != ItemDefs.expected_cells(id):
					return "%s 占 %d 格，強度 %.1f ÷ 效率 %.2f 應占 %d 格" % [id, ItemDefs.cell_count(id), def.power,
						ItemDefs.RARITIES[def.rarity].efficiency, ItemDefs.expected_cells(id)]
				counts[def.rarity] = counts.get(def.rarity, 0) + 1
			_:
				return "%s 的 kind 不存在：%s" % [id, def.kind]
		for e: Dictionary in def.effects:
			var err := _effect_error(e)
			if err != "":
				return "%s：%s" % [id, err]
	for id: StringName in WeaponDefs.WEAPONS:
		if not ItemDefs.ITEMS.has(id) or ItemDefs.ITEMS[id].kind != &"weapon":
			return "武器 %s 沒有物品資料" % id
	var want := {&"white": 15, &"green": 12, &"blue": 9, &"purple": 6, &"orange": 3}
	if counts != want:
		return "各稀有度道具數 %s，應為 %s" % [counts, want]
	if ItemDefs.item_ids().size() != 45:
		return "道具共 %d 個，應為 45" % ItemDefs.item_ids().size()
	return ""


func _check_items_apply() -> String:
	var w := _new_world()
	var p := _player(w)
	var base_speed := p.stats.value(&"move_speed")
	var whet := p.add_item(&"whetstone")
	if absf(p.stats.value(&"damage") - 1.08) > EPS:
		return "磨刀石後攻擊力應為 1.08，實際 %.4f" % p.stats.value(&"damage")
	var added := w.events.filter(func(e: Dictionary) -> bool: return e.name == "item:added")
	if added.size() != 1 or added[0].item != "whetstone" or added[0].uid != String(whet):
		return "應發出一次 item:added（whetstone），實際 %s" % [added]
	p.add_item(&"worn_boots")
	p.add_item(&"worn_boots")
	if absf(p.stats.value(&"move_speed") - base_speed * 1.16) > EPS:
		return "兩雙皮靴移速應為 %.3f，實際 %.3f" % [base_speed * 1.16, p.stats.value(&"move_speed")]
	p.hp = 50.0
	var bread := p.add_item(&"stale_bread")
	if p.max_hp != Config.PLAYER.max_hp + 20.0 or p.hp != 70.0:
		return "麵包後最大生命應 +20、目前生命 50 → 70，實際 %.0f / %.0f" % [p.hp, p.max_hp]
	p.add_item(&"gale_charm")
	if p.roll_max() != 2:
		return "疾風護符後翻滾次數上限應為 2，實際 %d" % p.roll_max()
	if p.items.size() != 5:
		return "身上應有 5 個道具實例，實際 %d" % p.items.size()
	p.remove_item(bread)
	if p.max_hp != Config.PLAYER.max_hp or p.items.size() != 4:
		return "移除麵包後最大生命應回到 %.0f、剩 4 個，實際 %.0f / %d" % [Config.PLAYER.max_hp, p.max_hp, p.items.size()]
	p.clear_items()
	if not p.items.is_empty() or p.stats.value(&"damage") != 1.0 or absf(p.stats.value(&"move_speed") - base_speed) > EPS or p.roll_max() != 1:
		return "清空後屬性應回到原值：攻擊力 %.3f 移速 %.3f 翻滾 %d" % [p.stats.value(&"damage"), p.stats.value(&"move_speed"), p.roll_max()]
	if p.stats.has_source(whet):
		return "清空後不應留下道具的屬性來源"
	if p.add_item(&"staff") != &"" or p.weapon_id != &"staff" or not p.items.is_empty():
		return "武器道具應直接換上法杖、不放進道具列表"
	# 每個道具都能放進身上、拿掉後不殘留
	for id in ItemDefs.item_ids():
		var uid := p.add_item(id)
		p.remove_item(uid)
	if p.stats.value(&"damage") != 1.0 or p.max_hp != Config.PLAYER.max_hp:
		return "所有道具放進再拿掉後屬性應回到原值"
	return ""


func _check_stats_armor_crit() -> String:
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
	if dealt != [10.0, 19.0]:
		return "20 傷害打護甲 100 / 8 應為 10 / 19（20 × 100 ÷ 108 = 18.5），實際 %s" % [dealt]
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
func _attack_steps(w: World, p: Player) -> int:
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1)
	var steps := 1
	while not p.action.is_in(&"ready") and steps < 600:
		_run(w, _cmd(Vector2.ZERO), 1)
		steps += 1
	return steps


func _check_stats_hooks() -> String:
	var w := _new_world()
	var p := _player(w)
	var normal := _attack_steps(w, p)
	_run(w, _cmd(Vector2.ZERO), 120)   # 等連段視窗結束，下一刀回到第一段
	p.set_stat_source(&"test", [[&"attack_speed", Stats.MUL, 2.0]])
	var fast := _attack_steps(w, p)
	if absi(fast * 2 - normal) > 2:
		return "攻速 ×2 普攻應從 %d 步變約 %d 步，實際 %d 步" % [normal, normal / 2, fast]
	p.remove_stat_source(&"test")

	p.set_stat_source(&"test", [[&"cooldown", Stats.MUL, 0.5]])
	_run(w, _cmd(Vector2.ZERO), 120)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL), 1)
	var expected: float = p.weapon.special.cooldown * 0.5
	var remaining := w.cooldowns.remaining("player.special")
	if absf(remaining - expected) > DT * 2.0:
		return "冷卻 ×0.5：特殊技冷卻應約 %.2f 秒，實際 %.2f" % [expected, remaining]
	p.remove_stat_source(&"test")

	var w2 := _new_world()
	var p2 := _player(w2)
	p2.hp = 50.0
	p2.set_stat_source(&"bread", [[&"max_hp", Stats.ADD, 20.0]])
	if p2.max_hp != 120.0 or p2.hp != 70.0:
		return "最大生命 +20：應為 70 / 120，實際 %.0f / %.0f" % [p2.hp, p2.max_hp]
	p2.remove_stat_source(&"bread")
	if p2.max_hp != 100.0 or p2.hp != 70.0:
		return "移除後應為 70 / 100，實際 %.0f / %.0f" % [p2.hp, p2.max_hp]
	p2.set_stat_source(&"bandage", [[&"hp_regen", Stats.ADD, 6.0]])
	_run(w2, _cmd(Vector2.ZERO), 60)
	if absf(p2.hp - 76.0) > 0.05:
		return "每秒回 6 血，1 秒後應為 76，實際 %.2f" % p2.hp
	p2.remove_stat_source(&"bandage")

	p2.set_stat_source(&"debug", [[&"move_speed", Stats.PCT, Config.DEBUG.speed_bonus]])
	if absf(p2.stats.value(&"move_speed") - 9.75) > EPS:
		return "除錯移速 +50%% 應為 9.75，實際 %.3f" % p2.stats.value(&"move_speed")
	var start := p2.pos
	_run(w2, _cmd(Vector2(1, 0)), 60)
	var moved := p2.pos.distance_to(start)
	if absf(moved - 9.75) > 9.75 * DT * 2.0:
		return "移速 9.75 跑 1 秒應約 9.75 單位，實際 %.3f" % moved
	return ""


# 按一次翻滾（往 +X）直到回到 ready；回傳 [位移, 步數]
func _do_roll(w: World, p: Player) -> Array:
	var start := p.pos
	_run(w, _cmd(Vector2(1, 0), Vector2(0, 5), InputCmd.BTN_ROLL), 1)
	var steps := 1
	while p.action.is_in(&"roll") and steps < 300:
		_run(w, _cmd(Vector2.ZERO), 1)
		steps += 1
	# 最後一步已回到 ready（沒有位移），不算在翻滾步數內
	return [p.pos.distance_to(start), steps - 1]


func _check_roll_motion() -> String:
	var duration_steps := roundi(Config.ROLL.duration / DT)
	var w := _new_world()
	var p := _player(w)
	var r := _do_roll(w, p)
	if absf(r[0] - 4.0) > 0.02 or r[1] != duration_steps:
		return "翻滾應 %d 步翻 4 單位，實際 %d 步 %.3f 單位" % [duration_steps, r[1], r[0]]
	if p.roll_charges != 0:
		return "翻滾後次數應為 0，實際 %d" % p.roll_charges
	# 冷卻中再按：不會翻，提示冷卻
	w.events.clear()
	_run(w, _cmd(Vector2(1, 0), Vector2(0, 5), InputCmd.BTN_ROLL), 1)
	if p.action.is_in(&"roll") or _named(w.events, "skill:onCooldown").is_empty():
		return "沒有次數時按翻滾應提示冷卻、不翻"
	# 從開始翻滾算起 1.2 秒回滿（已過 22 步）
	_run(w, _cmd(Vector2.ZERO), roundi(Config.ROLL.cooldown / DT) - duration_steps - 3)
	if p.roll_charges != 0:
		return "1.2 秒前不應回充"
	_run(w, _cmd(Vector2.ZERO), 3)
	if p.roll_charges != 1:
		return "1.2 秒後應回充 1 次，實際 %d" % p.roll_charges

	var w2 := _new_world()
	var p2 := _player(w2)
	p2.set_stat_source(&"test", [[&"move_speed", Stats.PCT, 0.5]])
	var fast := _do_roll(w2, p2)
	if absf(fast[0] - 6.0) > 0.03 or fast[1] != duration_steps:
		return "移速 +50%% 應 %d 步翻 6 單位，實際 %d 步 %.3f 單位" % [duration_steps, fast[1], fast[0]]

	var w3 := _new_world()
	var p3 := _player(w3)
	p3.set_stat_source(&"test", [[&"roll_charges", Stats.ADD, 1.0], [&"roll_cooldown", Stats.MUL, 0.9]])
	p3.roll_charges = p3.roll_max()
	_run(w3, _cmd(Vector2(1, 0), Vector2(0, 5), InputCmd.BTN_ROLL), 1)
	var cd := w3.cooldowns.remaining(Player.ROLL_CD)
	if absf(cd - 1.08) > DT * 1.5:
		return "翻滾冷卻 −10%% 應為 1.08 秒，實際 %.3f" % cd
	while p3.action.is_in(&"roll"):
		_run(w3, _cmd(Vector2.ZERO), 1)
	var second := _do_roll(w3, p3)
	if second[1] != duration_steps or p3.roll_charges != 0:
		return "次數 +1 應能連翻第二次，實際 %d 步、剩 %d 次" % [second[1], p3.roll_charges]
	return ""


func _check_roll_invuln() -> String:
	var invuln_steps := roundi(Config.ROLL.invuln_time / DT)
	var w := _new_world()
	var p := _player(w)
	var archer := _spawn(w, &"archer", Vector2(0, 15))
	# 開始翻滾的那一步算第 1 步，無敵涵蓋第 1 ~ 12 步（0.2 秒）
	_run(w, _cmd(Vector2(1, 0), Vector2(0, 5), InputCmd.BTN_ROLL), 1)
	for i in invuln_steps - 2:
		_run(w, _cmd(Vector2.ZERO), 1)
	if p.can_be_hit():
		return "翻滾開始後第 %d 步（0.2 秒內）應無敵" % (invuln_steps - 1)
	# 第 12 步：投射物放在玩家身上，無敵中直接穿過，不會消失
	var arrow := Projectile.new(w, {"owner": archer, "pos": p.pos, "direction": Vector2(0, -1), "speed": 0.01, "range": 5.0, "damage": 10.0})
	w.spawn_projectile(arrow)
	var hp := p.hp
	_run(w, _cmd(Vector2.ZERO), 1)
	if arrow.is_removed or p.hp != hp:
		return "無敵中投射物應穿過：removed=%s 血量 %.0f → %.0f" % [arrow.is_removed, hp, p.hp]
	# 第 13 步：無敵結束，投射物命中
	var arrow2 := Projectile.new(w, {"owner": archer, "pos": p.pos, "direction": Vector2(0, -1), "speed": 0.01, "range": 5.0, "damage": 10.0})
	w.spawn_projectile(arrow2)
	_run(w, _cmd(Vector2.ZERO), 1)
	if not arrow2.is_removed or p.hp >= hp:
		return "0.2 秒後投射物應命中：removed=%s 血量 %.0f → %.0f" % [arrow2.is_removed, hp, p.hp]
	return ""


func _check_roll_cancel() -> String:
	var roll := _cmd(Vector2(1, 0), Vector2(0, 5), InputCmd.BTN_ROLL)
	# 前搖
	var w := _new_world()
	var p := _player(w)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1)
	if not (p.action.is_in(&"attack") and p.action.data.phase_index == 0):
		return "按攻擊後應在前搖"
	_run(w, roll, 1)
	if not p.action.is_in(&"roll"):
		return "前搖應能用翻滾取消，實際狀態 %s" % p.action.current_name
	# 揮下去（active）：先緩衝，active 結束後進入後搖就翻
	var w2 := _new_world()
	var p2 := _player(w2)
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1)
	while p2.action.is_in(&"attack") and p2.action.data.phase_index == 0:
		_run(w2, _cmd(Vector2.ZERO), 1)
	_run(w2, roll, 1)
	if not (p2.action.is_in(&"attack") and p2.action.data.phase_index == 1):
		return "揮下去時不應被翻滾取消，實際狀態 %s" % p2.action.current_name
	var waited := 0
	while not p2.action.is_in(&"roll") and waited < 30:
		_run(w2, _cmd(Vector2.ZERO), 1)
		waited += 1
	if not p2.action.is_in(&"roll") or waited > roundi(0.09 / DT) + 1:
		return "揮下去結束後應接著翻滾（%d 步）" % waited
	# 特殊技與硬直：不取消，結束後在緩衝時間內翻
	for state in [&"special", &"stagger"]:
		var w3 := _new_world()
		var p3 := _player(w3)
		if state == &"special":
			# 用法杖的奧術爆裂（劍盾格擋 v0.18.0 起可以用翻滾結束，見 _check_shield_block）
			p3.equip_weapon(&"staff")
			_run(w3, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL), 1)
		else:
			p3.action.change(&"stagger")
		_run(w3, roll, 1)
		if p3.action.is_in(&"roll"):
			return "%s 中不應被翻滾取消" % state
	var w4 := _new_world()
	var p4 := _player(w4)
	p4.action.change(&"stagger")
	_run(w4, roll, 1)
	_run(w4, _cmd(Vector2.ZERO), roundi(Config.PLAYER.stagger_time / DT) + 1)
	if not p4.action.is_in(&"roll"):
		return "硬直結束後應執行緩衝的翻滾，實際狀態 %s" % p4.action.current_name
	return ""


func _jump_cmd(move: Vector2 = Vector2.ZERO, extra: int = 0) -> InputCmd:
	return _cmd(move, Vector2(0, 5), InputCmd.BTN_JUMP | extra)


func _check_jump_motion() -> String:
	var w := _new_world()
	var p := _player(w)
	_run(w, _jump_cmd(), 1)
	var peak := p.height
	var peak_step := 1
	var steps := 1
	while not p.is_grounded() and steps < 200:
		_run(w, _cmd(Vector2.ZERO), 1)
		steps += 1
		if p.height > peak:
			peak = p.height
			peak_step = steps
	if absf(peak - 1.5) > 0.005 or peak_step != 18 or steps != 36:
		return "最高 %.3f（第 %d 步）、第 %d 步落地；預期 1.5、第 18 步、第 36 步" % [peak, peak_step, steps]
	# 空中再按跳躍不會再往上
	_run(w, _jump_cmd(), 10)
	var vz_before := p.vz
	_run(w, _jump_cmd(), 1)
	if p.vz > vz_before:
		return "空中再按跳躍不應再往上（二段跳）"
	while not p.is_grounded():
		_run(w, _cmd(Vector2.ZERO), 1)
	# 攻擊中可以跳
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1)
	_run(w, _jump_cmd(Vector2.ZERO, InputCmd.BTN_ATTACK), 1)
	if not p.action.is_in(&"attack") or p.height <= 0.0:
		return "攻擊中應能起跳（狀態 %s、高度 %.2f）" % [p.action.current_name, p.height]
	while not p.is_grounded():
		_run(w, _cmd(Vector2.ZERO), 1)
	_run(w, _cmd(Vector2.ZERO), 30)
	# 硬直中不能跳
	p.action.change(&"stagger")
	_run(w, _jump_cmd(), 1)
	if p.height > 0.0:
		return "硬直中不應能跳"
	_run(w, _cmd(Vector2.ZERO), 30)
	# 空中翻滾：高度持續下降、水平一樣 4 單位
	var w2 := _new_world()
	var p2 := _player(w2)
	_run(w2, _jump_cmd(), 18)
	var h0 := p2.height
	var r := _do_roll(w2, p2)
	if absf(r[0] - 4.0) > 0.02:
		return "空中翻滾水平應為 4 單位，實際 %.3f" % r[0]
	if p2.height >= h0:
		return "空中翻滾應照常下墜（%.2f → %.2f）" % [h0, p2.height]
	return ""


# 往 move 方向走 steps 步，可選擇第一步起跳
func _walk(w: World, move: Vector2, steps: int, jump := false) -> void:
	if jump:
		_run(w, _jump_cmd(move), 1)
		steps -= 1
	_run(w, _cmd(move), steps)


func _check_terrain() -> String:
	var w := _new_world()
	var p := _player(w)
	# 0.5 石台：x 7.75~10.25、z 10.75~13.25
	p.pos = Vector2(9.0, 9.5)
	_walk(w, Vector2(0, 1), 60)
	if p.pos.y > 10.75 - p.radius + 0.01 or p.height != 0.0:
		return "0.5 石台應走不上去：z %.2f、高度 %.2f" % [p.pos.y, p.height]
	# 走 20 步（約 2.2 單位）再原地等落地：停在石台上，不會走過整塊掉下去
	_walk(w, Vector2(0, 1), 20, true)
	_run(w, _cmd(Vector2.ZERO), 30)
	if absf(p.height - 0.5) > 1e-3 or p.pos.y < 10.75:
		return "應跳上 0.5 石台：z %.2f、高度 %.3f" % [p.pos.y, p.height]
	# 往 +X 走到 1.0 石台（x 10.25 起）：走不上去，跳得上去
	p.pos = Vector2(9.0, 12.0)
	_walk(w, Vector2(1, 0), 40)
	if p.height > 0.5 + 1e-3 or p.pos.x > 10.25 - p.radius + 0.01:
		return "從 0.5 應走不上 1.0：x %.2f、高度 %.2f" % [p.pos.x, p.height]
	_walk(w, Vector2(1, 0), 20, true)
	_run(w, _cmd(Vector2.ZERO), 30)
	if absf(p.height - 1.0) > 1e-3:
		return "應從 0.5 跳上 1.0 石台，實際高度 %.3f（x %.2f）" % [p.height, p.pos.x]
	# 走出 1.0 石台的 +X 邊緣（13.75）會掉回地面
	_walk(w, Vector2(1, 0), 60)
	if p.height != 0.0 or p.pos.x < 13.75:
		return "走出邊緣應掉回地面：x %.2f、高度 %.2f" % [p.pos.x, p.height]
	# 2.5 的牆（z 7.5~8.5）：從南邊一直跳也過不去
	p.pos = Vector2(11.0, 5.0)
	for i in 4:
		_walk(w, Vector2(0, 1), 40, true)
	if p.pos.y > 7.5 - p.radius + 0.01:
		return "2.5 的牆不應跳得過：z %.2f、高度 %.2f" % [p.pos.y, p.height]
	return ""


func _check_height_hits() -> String:
	var w := _new_world()
	var p := _player(w)
	var archer := _spawn(w, &"archer", Vector2(0, 15))
	var arrow_at := func() -> Projectile:
		var a := Projectile.new(w, {"owner": archer, "pos": p.pos, "direction": Vector2(0, -1), "speed": 0.01,
			"range": 5.0, "damage": 10.0, "altitude": Config.HEIGHT.arrow_altitude})
		w.spawn_projectile(a)
		return a
	_run(w, _jump_cmd(), 18)
	var hp := p.hp
	var high: Projectile = arrow_at.call()
	_run(w, _cmd(Vector2.ZERO), 1)
	if high.is_removed or p.hp != hp:
		return "最高點（%.2f）時箭應從腳下飛過" % p.height
	high.remove()
	while not p.is_grounded():
		_run(w, _cmd(Vector2.ZERO), 1)
	var low: Projectile = arrow_at.call()
	_run(w, _cmd(Vector2.ZERO), 1)
	if not low.is_removed or p.hp >= hp:
		return "站在地面應中箭"

	# Boss 砸地：腳底高於 0.5 打不到
	var w2 := _new_world()
	var p2 := _player(w2)
	var boss := _spawn(w2, &"boss", Vector2(0, 2.0))
	p2.height = 0.8
	var hp2 := p2.hp
	boss.slam_impact()
	if p2.hp != hp2:
		return "腳底 0.8 時不應被砸地打到"
	p2.height = 0.0
	boss.slam_impact()
	if p2.hp >= hp2:
		return "站在地面應被砸地打到"

	# 空中揮砍打得到地上的骷髏
	var w3 := _new_world()
	var p3 := _player(w3)
	var g := _spawn(w3, &"grunt", Vector2(0, 1.3))
	_run(w3, _jump_cmd(), 17)
	var g_hp := g.hp
	_run(w3, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 12)
	if g.hp >= g_hp:
		return "空中揮砍（高度 %.2f）應打得到地上的骷髏" % p3.height

	# 空中魔彈：從 2.75 發射，3 單位內降到 1.25，打得到 4.5 單位外的骷髏
	var w4 := _new_world()
	var p4 := _player(w4)
	p4.equip_weapon(&"staff")
	var g4 := _spawn(w4, &"grunt", Vector2(0, 4.5))
	_run(w4, _jump_cmd(Vector2.ZERO), 16)
	var g4_hp := g4.hp
	_run(w4, _cmd(Vector2.ZERO, Vector2(0, 4.5), InputCmd.BTN_ATTACK), 1)
	_run(w4, _cmd(Vector2.ZERO, Vector2(0, 4.5)), 40)
	if g4.hp >= g4_hp:
		return "空中魔彈應降回胸口高度、打得到地上的骷髏"
	return ""


func _check_no_contact_damage() -> String:
	var w := _new_world()
	var p := _player(w)
	var g := _spawn(w, &"grunt", Vector2(0, 1.0))
	var a := _spawn(w, &"archer", Vector2(1.0, 0))
	var b := _spawn(w, &"boss", Vector2(-1.6, 0))
	for name in ["swing", "fire", "slam", "charge", "summon"]:
		for e: Enemy in [g, a, b]:
			w.cooldowns.start(e.cd(name), 100.0)
	_run(w, _cmd(Vector2.ZERO), 120)
	if p.hp != p.max_hp:
		return "貼身 2 秒不應扣血，實際血量 %.0f" % p.hp
	return ""


# 骷髏戰士爬出後馬上在玩家前方：回傳 grunt（已進入 swing 狀態）
func _grunt_swinging(w: World, p: Player) -> MeleeEnemy:
	var g: MeleeEnemy = _spawn(w, &"grunt", Vector2(0, 0))
	p.pos = Vector2(0, 1.2)
	g.facing = 0.0
	var steps := 0
	while not g.fsm.is_in(&"swing") and steps < 120:
		p.pos = Vector2(0, 1.2)
		_run(w, _cmd(Vector2.ZERO), 1)
		steps += 1
	return g


func _check_grunt_swing() -> String:
	var s: Dictionary = EnemyDefs.ENEMIES.grunt.swing
	# 命中時機與傷害
	var w := _new_world()
	var p := _player(w)
	var g := _grunt_swinging(w, p)
	if not g.fsm.is_in(&"swing"):
		return "玩家在 1.2 內時骷髏應開始舉刀"
	var steps := 0
	var dealt := 0
	while steps < 60 and dealt == 0:
		_run(w, _cmd(Vector2.ZERO), 1)
		steps += 1
		for e in _named(w.events, "entity:damaged"):
			if e.target_id == p.id:
				dealt = e.amount
	var expected_steps := roundi(s.windup / DT)
	if dealt != 12 or absi(steps - expected_steps) > 1:
		return "舉刀約 %d 步後應命中 12，實際第 %d 步、傷害 %d" % [expected_steps, steps, dealt]
	if w.hitboxes.is_empty() or w.hitboxes[0].shape.shape != &"sector":
		return "命中當步應記錄扇形判定（F2 顯示用）"

	# 扇形邊界：半角 50° + 目標半徑換算的角度（距離 1.4 時 +18.7°），距離 1.5 + 目標半徑
	var w2 := _new_world()
	var p2 := _player(w2)
	var shape := {"shape": &"sector", "range": s.range, "arc": s.arc}
	var inside := func(at: Vector2) -> bool:
		p2.pos = at
		return not Hitbox.query(w2, &"enemy", Vector2.ZERO, 0.0, shape).is_empty()
	var allow: float = s.arc / 2.0 + asin(p2.radius / 1.4)
	if not inside.call(MathUtil.dir_from_angle(allow - 0.05) * 1.4) or inside.call(MathUtil.dir_from_angle(allow + 0.05) * 1.4):
		return "扇形角度邊界應在 %.1f°" % rad_to_deg(allow)
	var reach: float = s.range + p2.radius
	if not inside.call(Vector2(0, reach - 0.02)) or inside.call(Vector2(0, reach + 0.05)):
		return "扇形距離邊界應在 %.2f" % reach

	# 舉刀後半鎖定方向：鎖定後玩家繞到側面就躲開
	var w3 := _new_world()
	var p3 := _player(w3)
	var g3 := _grunt_swinging(w3, p3)
	_run(w3, _cmd(Vector2.ZERO), roundi(s.windup * s.track / DT) + 2)
	var locked := g3.facing
	p3.pos = Vector2(1.5, -0.3)
	var hp := p3.hp
	_run(w3, _cmd(Vector2.ZERO), roundi((s.windup + s.active) / DT))
	if p3.hp != hp:
		return "鎖定方向後繞到側面應躲開，實際扣 %.0f" % (hp - p3.hp)
	if absf(angle_difference(locked, g3.facing)) > 1e-4:
		return "舉刀後半不應再轉向"

	# 舉刀中被打會中斷，不會揮下
	var w4 := _new_world()
	var p4 := _player(w4)
	var g4 := _grunt_swinging(w4, p4)
	_run(w4, _cmd(Vector2.ZERO), 10)
	g4.take_damage(5.0, Vector2(0, -1), 0.0, p4.id)
	var hp4 := p4.hp
	_run(w4, _cmd(Vector2.ZERO), roundi(s.windup / DT))
	if p4.hp != hp4 or g4.fsm.is_in(&"swing"):
		return "舉刀中被打應中斷：血量 %.0f → %.0f、狀態 %s" % [hp4, p4.hp, g4.fsm.current_name]
	return ""


func _check_hit_feel() -> String:
	# 玩家揮砍打中：不震動、不放慢，事件帶 hit_stop 0.04
	var w := _new_world()
	var p := _player(w)
	var g := _spawn(w, &"grunt", Vector2(0, 1.5))
	w.cooldowns.start(g.cd("swing"), 100.0)
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1, events)
	_run_collect(w, _cmd(Vector2.ZERO), 15, events)
	var hits := _named(events, "entity:damaged").filter(func(e: Dictionary) -> bool: return e.target_id == g.id)
	if hits.is_empty() or absf(hits[0].hit_stop - 0.04) > EPS:
		return "玩家打中應發出帶 hit_stop 0.04 的 entity:damaged：%s" % [hits]
	if not _named(events, "camera:shake").is_empty():
		return "玩家攻擊打中不應震動"
	if w.hit_stop_timer > 0.0:
		return "一般命中不應放慢模擬時間（hit_stop_timer %.3f）" % w.hit_stop_timer
	# 法杖奧術爆裂：爆炸不震動
	var w2 := _new_world()
	var p2 := _player(w2)
	p2.equip_weapon(&"staff")
	var ev2: Array[Dictionary] = []
	_run_collect(w2, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL), 1, ev2)
	_run_collect(w2, _cmd(Vector2.ZERO), 90, ev2)
	if _named(ev2, "sfx:cue").filter(func(e: Dictionary) -> bool: return e.cue == "explosion").is_empty():
		return "奧術爆裂應該爆炸（檢查前提）"
	if not _named(ev2, "camera:shake").is_empty():
		return "玩家的奧術爆炸不應震動"
	# 玩家被打、Boss 砸地：照常震動
	var w3 := _new_world()
	var p3 := _player(w3)
	w3.events.clear()
	Combat.apply_damage(w3, _spawn(w3, &"grunt", Vector2(0, 1.0)), p3, {"damage": 5.0})
	if _named(w3.events, "camera:shake").is_empty():
		return "玩家被打應震動"
	var boss := _spawn(w3, &"boss", Vector2(0, 8))
	w3.events.clear()
	boss.slam_impact()
	if _named(w3.events, "camera:shake").is_empty():
		return "Boss 砸地應震動"
	# 命中定格 v0.19.1 起關閉：打中後模型照常跟著實際位置
	if Config.FEEL.hit_freeze:
		return "Config.FEEL.hit_freeze 應為 false（v0.19.1 使用者決定拿掉命中定格）"
	var w4 := _new_world()
	var p4 := _player(w4)
	var g4 := _spawn(w4, &"grunt", Vector2(0, 3))
	var view := WorldView.new()
	view.sync(w4, 1.0, DT)
	var node: Node3D = view._nodes[g4.id]
	view.on_event("entity:damaged", {"source_id": p4.id, "target_id": g4.id, "hit_stop": 0.1})
	g4.pos += Vector2(1, 0)
	g4.prev_pos = g4.pos
	view.sync(w4, 1.0, 0.05)
	if absf(node.position.x - g4.pos.x) > EPS:
		return "打中後模型不應定格，應立刻跟上實際位置（%.2f vs %.2f）" % [node.position.x, g4.pos.x]
	view.free()
	return ""


func _check_flash_no_shader_switch() -> String:
	var kit := PartKit.new()
	var m := kit.mat(Color("8899aa"))
	for k in [0.0, 0.9, 0.0]:
		kit.set_flash(k)
		if not m.emission_enabled:
			return "set_flash(%.1f) 後 emission_enabled 應保持 true" % k
		if not m.emission.is_equal_approx(Color(k, k, k)):
			return "set_flash(%.1f) 後自發光應為 (%.1f, %.1f, %.1f)，實際 %s" % [k, k, k, k, m.emission]
	return ""


func _check_font_coverage() -> String:
	if ProjectSettings.get_setting("gui/theme/custom_font", "") != "res://assets/fonts/hud_font.tres":
		return "project.godot 的 gui/theme/custom_font 沒有設成打包字型"
	var font := load("res://assets/fonts/NotoSansTC-VF.ttf") as FontFile
	if font == null:
		return "讀不到 assets/fonts/NotoSansTC-VF.ttf"
	var drawn: Array = load("res://ui/skill_bar.gd").get_script_constant_map().DRAWN_ICONS
	var texts: Array[String] = []
	for w: Dictionary in WeaponDefs.WEAPONS.values():
		texts.append_array([w.name, w.attack.name, w.attack.icon, w.special.name, w.special.icon])
	for s: Dictionary in SkillDefs.SKILLS.values():
		texts.append_array([s.name, s.icon])
	var hud_consts: Dictionary = load("res://ui/hud.gd").get_script_constant_map()
	texts.append_array([hud_consts.CONTROLS_TEXT, hud_consts.BOSS_NAME])
	for s: Dictionary in StatDefs.STATS.values():
		texts.append(s.name)
	for item: Dictionary in ItemDefs.ITEMS.values():
		texts.append_array([item.name, item.desc, "獲得 "])
	texts.append(StatDefs.format_value(&"armor", 8.0) + StatDefs.format_value(&"hp_regen", 1.0))
	# HUD 程式裡的字串常值（標題、橫幅、結算、按鍵名稱）
	var re := RegEx.create_from_string("\"([^\"\\\\]*)\"")
	for path in ["res://ui/hud.gd", "res://ui/skill_bar.gd", "res://ui/stats_panel.gd"]:
		for m in re.search_all(_read_text(path)):
			texts.append(m.get_string(1))
	var missing := {}
	for t in texts:
		if t in drawn:
			continue
		for i in t.length():
			var code := t.unicode_at(i)
			if code > 32 and not font.has_char(code):
				missing[t[i]] = true
	if not missing.is_empty():
		return "打包字型缺字：%s" % " ".join(missing.keys())
	return ""


# 以 root 為座標系統計零件：{ meshes, min, max, bad_faces（法線與正面方向不符的三角形數） }
func _mesh_stats(root: Node3D) -> Dictionary:
	var lo := Vector3.INF
	var hi := -Vector3.INF
	var bad := 0
	var meshes := PartKit.mesh_instances(root)
	for mi in meshes:
		var xf := mi.transform
		var n: Node = mi.get_parent()
		while n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var arrays := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for v in verts:
			lo = lo.min(xf * v)
			hi = hi.max(xf * v)
		if mi.mesh is ArrayMesh and arrays[Mesh.ARRAY_INDEX] == null:
			for i in range(0, verts.size(), 3):
				var face := (verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i])
				# Godot 正面為順時針：(b-a)×(c-a) 朝內，與法線相反（頂點是 float32，用 dot 容許誤差）
				if face.normalized().dot(-normals[i]) < 0.999:
					bad += 1
	return {"meshes": meshes.size(), "min": lo, "max": hi, "bad_faces": bad}


func _check_merge_static() -> String:
	var kit := PartKit.new()
	var root := Node3D.new()
	var arm := Node3D.new()
	arm.position = Vector3(0.5, 1, 0)
	arm.rotation.z = 0.4
	root.add_child(arm)
	var sub := Node3D.new()   # 非 anchor 的子群組：應被併入 arm
	sub.position = Vector3(0, -0.3, 0.1)
	sub.rotation.x = 0.7
	arm.add_child(sub)
	var red := kit.mat(Color.RED)
	var blue := kit.mat(Color.BLUE)
	kit.add(root, PartKit.box(0.4, 0.6, 0.3), red, {"y": 1.0})
	kit.add(root, PartKit.cyl(0.1, 0.1, 0.5, 6), red, {"x": 0.3, "rz": 0.5})
	kit.add(arm, PartKit.ico(0.1, 0), red, {"y": -0.2})
	kit.add(sub, PartKit.box(0.1, 0.1, 0.1), red, {"s": 2.0})
	kit.add(sub, PartKit.cone(0.1, 0.2, 4), blue)
	kit.add(sub, PartKit.torus(0.2, 0.03, 4, 8, PI), blue, {"rx": 0.3, "ry": 1.1})
	var gem := kit.add(arm, PartKit.ico(0.05, 1), blue, {"y": -0.5})

	var before := _mesh_stats(root)
	kit.merge_static(root, [root, arm], [gem])
	var after := _mesh_stats(root)
	var err := ""
	if not (after.min as Vector3).is_equal_approx(before.min) or not (after.max as Vector3).is_equal_approx(before.max):
		err = "外框改變：%s~%s → %s~%s" % [before.min, before.max, after.min, after.max]
	elif after.meshes != 4:
		err = "應剩 root 紅、arm 紅、arm 藍、gem 共 4 個，實際 %d 個" % after.meshes
	elif gem.get_parent() != arm or arm.get_parent() != root:
		err = "keep 的零件與 anchor 應留在原位"
	elif is_instance_valid(sub):
		err = "空的子群組應移除"
	elif after.bad_faces > 0:
		err = "%d 個三角形的法線不是朝外的面法線" % after.bad_faces
	root.free()
	return err


# ---- 手感量測：期望值都用網頁版的公式與更新順序算，再和 Godot 模擬的實測值比 ----

var _feel_lines: Array[String] = []


func _feel(line: String) -> void:
	_feel_lines.append(line)


# 網頁版 Entity.js：每步 position += knockback × dt，之後 knockback ×= exp(-阻尼 × dt)；k0 起速跑 n 步的總位移
static func _web_knockback_distance(k0: float, n: int) -> float:
	var r := exp(-Config.COMBAT.knockback_damping * DT)
	return k0 * DT * (1.0 - pow(r, n)) / (1.0 - r)


func _check_feel_knockback() -> String:
	var w := _new_world()
	var p := _player(w)
	var d := _dummy(w, Vector2(0, 4), 1000.0, 1.0)
	Combat.apply_damage(w, p, d, {"damage": 1.0, "knockback": 7.0})
	_run(w, _cmd(Vector2.ZERO, Vector2(0, -5)), 120)
	var moved := d.pos.y - 4.0
	var expect := _web_knockback_distance(7.0, 120)
	_feel("擊退 7、質量 1：網頁版公式 %.4f，Godot 實測 %.4f 單位" % [expect, moved])
	return "" if absf(moved - expect) < 1e-4 else "位移 %.4f，網頁版公式 %.4f" % [moved, expect]


func _check_feel_turn() -> String:
	var w := _new_world()
	var p := _player(w)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5)), 10)
	var steps := 0
	while steps < 60 and absf(angle_difference(p.facing, PI)) > 1e-4:
		_run(w, _cmd(Vector2.ZERO, Vector2(0, -5)), 1)
		steps += 1
	var expect := ceili(PI / (Config.PLAYER.turn_speed * DT))
	_feel("轉身 180°：網頁版 %d 步，Godot 實測 %d 步（%.3f 秒）" % [expect, steps, steps * DT])
	return "" if steps == expect else "轉身 %d 步，預期 %d" % [steps, expect]


# 按一下攻擊（只按一步），之後放開跑 rest 步
func _tap_attack(w: World, rest: int) -> void:
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5)), rest)


func _check_feel_lunge_combo() -> String:
	var def: Dictionary = WeaponDefs.WEAPONS.swordShield.attack
	var w := _new_world()
	var p := _player(w)
	var start := p.pos
	_tap_attack(w, 120)
	var lunge := p.pos.distance_to(start)
	# 前衝在 active 開始時加上，到量測時跑了 120 + 1 - windup 步
	var steps_after := 121 - roundi(def.windup / DT)
	var expect := _web_knockback_distance(def.lunge, steps_after)
	_feel("普攻前衝：網頁版公式 %.4f，Godot 實測 %.4f 單位" % [expect, lunge])
	if absf(lunge - expect) > 0.005:
		return "前衝 %.4f，網頁版公式 %.4f" % [lunge, expect]

	# 連段：收招後 0.30 秒內出手接下一段，0.40 秒後出手回到第一段
	var total := roundi((def.windup + def.active + def.recovery) / DT)
	var w2 := _new_world()
	var p2 := _player(w2)
	_tap_attack(w2, total + roundi(0.30 / DT))
	_tap_attack(w2, 0)
	var within := p2.combo_step
	var w3 := _new_world()
	var p3 := _player(w3)
	_tap_attack(w3, total + roundi(0.40 / DT))
	_tap_attack(w3, 0)
	var after := p3.combo_step
	_feel("連段：收招後 0.30 秒出手 → 第 %d 段；0.40 秒出手 → 第 %d 段（窗口 %.2f 秒）" % [within + 1, after + 1, def.combo_window])
	if within != 1 or after != 0:
		return "0.30 秒後應接第 2 段（實際第 %d 段），0.40 秒後應回第 1 段（實際第 %d 段）" % [within + 1, after + 1]

	# 第三段前衝 ×1.25
	var w4 := _new_world()
	var p4 := _player(w4)
	for i in 2:
		_tap_attack(w4, total + 3)
	var before := p4.pos
	var residual := p4.knockback.length()   # 第二段前衝還沒衰減完（收招後只隔 3 步），同方向，要一起算
	_tap_attack(w4, 120)
	var fin := p4.pos.distance_to(before)
	var fin_expect := _web_knockback_distance(def.lunge * 1.25, steps_after) + _web_knockback_distance(residual, 121)
	_feel("第三段前衝：網頁版公式 %.4f，Godot 實測 %.4f 單位" % [fin_expect, fin])
	return "" if absf(fin - fin_expect) < 0.005 else "第三段前衝 %.4f，網頁版公式 %.4f" % [fin, fin_expect]


# 網頁版 Combat.querySector 原樣照抄，用來和 Godot 的 Combat.query_sector 比對
static func _web_in_sector(dx: float, dz: float, radius: float, facing: float, range_: float, arc: float) -> bool:
	var dist := sqrt(dx * dx + dz * dz)
	if dist > range_ + radius:
		return false
	if dist <= radius + 0.3:
		return true
	var diff := absf(wrapf(atan2(dx, dz) - facing, -PI, PI))
	return diff <= arc / 2.0 + asin(minf(1.0, radius / dist))


func _check_feel_sector() -> String:
	var def: Dictionary = WeaponDefs.WEAPONS.swordShield.attack
	var w := _new_world()
	var mismatch := 0
	var ties := 0      # 剛好落在邊界上（差距 < 1e-4）：Godot 的 Vector2 是 float32，和這裡的 double 計算捨入不同
	var total := 0
	var max_hit_angle := 0.0
	for scale: float in [1.0, 1.25]:
		for ri in 70:
			var dist := 0.05 + ri * 0.05
			for ai in 120:
				var angle := ai * TAU / 120.0
				var e := Entity.new(w, &"test", &"enemy", 0.45, 10.0, 1.0)
				e.pos = Vector2(sin(angle), cos(angle)) * dist
				var hit := not Combat.query_sector(Vector2.ZERO, 0.0, def.range * scale, def.arc * scale, [e] as Array[Entity]).is_empty()
				var web := _web_in_sector(e.pos.x, e.pos.y, 0.45, 0.0, def.range * scale, def.arc * scale)
				total += 1
				if hit != web:
					var d := e.pos.length()
					var diff := absf(wrapf(atan2(e.pos.x, e.pos.y), -PI, PI))
					var margin := minf(absf(d - (def.range * scale + 0.45)), absf(d - 0.75))
					margin = minf(margin, absf(diff - (def.arc * scale / 2.0 + asin(minf(1.0, 0.45 / d)))))
					if margin < 1e-4:
						ties += 1
					else:
						mismatch += 1
				if hit and scale == 1.0 and absf(dist - 2.0) < 1e-6:
					max_hit_angle = maxf(max_hit_angle, absf(wrapf(angle, -PI, PI)))
	_feel("斬擊範圍：%d 個位置（距離 0.05~3.5、每 3°、一般與第三段）與網頁版不同 %d 個（另有 %d 個剛好壓在邊界上，差距 < 0.0001，屬浮點捨入）；距離 2.0 的小怪最多偏 %.0f° 仍打得到" % [total, mismatch, ties, rad_to_deg(max_hit_angle)])
	return "" if mismatch == 0 else "%d / %d 個位置命中結果與網頁版不同" % [mismatch, total]


func _check_feel_wave_timing() -> String:
	var w := _new_world(31, true)
	var p := _player(w)
	var start_tick := -1
	var spawn_ticks: Array[int] = []
	var seen := {}
	var cleared_tick := -1
	var next_wave_tick := -1
	for i in 60 * 30:
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		for e in w.events:
			if e.name == "wave:started":
				if start_tick < 0:
					start_tick = w.tick
				else:
					next_wave_tick = w.tick
		if next_wave_tick > 0:
			break
		for e in w.enemies:   # 一出現就記錄並打死（只量第一波）
			if not seen.has(e.id) and start_tick > 0:
				seen[e.id] = true
				spawn_ticks.append(w.tick)
			if not e.is_dead:
				Combat.apply_damage(w, p, e, {"damage": 9999.0})
		if spawn_ticks.size() == WaveDefs.WAVES[0].spawns.grunt and cleared_tick < 0:
			cleared_tick = w.tick
	var first := spawn_ticks[0] - start_tick
	var gaps: Array[int] = []
	for i in range(1, spawn_ticks.size()):
		gaps.append(spawn_ticks[i] - spawn_ticks[i - 1])
	var wave_gap := next_wave_tick - cleared_tick
	var e_first := _web_countdown(Config.SPAWNER.first_spawn_delay)
	var e_gap := _web_countdown(Config.SPAWNER.spawn_interval)
	var e_wave := _web_countdown(Config.SPAWNER.wave_delay)
	_feel("生成節奏：開波後第 %d 步出第一隻（網頁版 %d 步），間隔 %s 步（網頁版 %d 步），清空後第 %d 步開下一波（網頁版 %d 步）。網頁版計時器每步減 1/60、≤ 0 才觸發，浮點誤差讓 0.35 秒變 22 步、2.5 秒變 151 步，兩版一致" % [first, e_first, gaps, e_gap, wave_gap, e_wave])
	if first != e_first:
		return "第一隻在開波後 %d 步出現，網頁版 %d 步" % [first, e_first]
	for g in gaps:
		if g != e_gap:
			return "生成間隔 %s 步，網頁版 %d 步" % [gaps, e_gap]
	if wave_gap != e_wave:
		return "清空到下一波 %d 步，網頁版 %d 步" % [wave_gap, e_wave]
	return ""


# 網頁版 Spawner 的計時：t 每步減 dt，減到 ≤ 0 的那一步觸發（JS 與 GDScript 都是 64 位元浮點，結果相同）
static func _web_countdown(seconds: float) -> int:
	var t := seconds
	var n := 0
	while t > 0.0:
		t -= DT
		n += 1
	return n


func _check_feel_enemy_speed() -> String:
	var w := _new_world(77, true)
	w.spawner.finished = true
	for type: StringName in [&"grunt", &"archer"]:
		var def: Dictionary = EnemyDefs.ENEMIES[type]
		for wave in [1, 3, 4]:
			w.spawner.wave = wave
			var mul: float = WaveDefs.wave_multipliers(wave).speed
			var lo: float = def.move_speed * mul * (1.0 - def.speed_variance)
			var hi: float = def.move_speed * mul * (1.0 + def.speed_variance)
			var s_min := INF
			var s_max := -INF
			for i in 40:
				var e := _spawn(w, type, Vector2(10, 10))
				s_min = minf(s_min, e.speed)
				s_max = maxf(s_max, e.speed)
				e.remove()
			if s_min < lo - EPS or s_max > hi + EPS:
				return "%s 第 %d 波移速 %.3f~%.3f，網頁版範圍 %.3f~%.3f" % [type, wave, s_min, s_max, lo, hi]
			if wave == 3:
				_feel("%s 第 3 波移速：網頁版範圍 %.3f~%.3f，Godot 40 隻實測 %.3f~%.3f" % [type, lo, hi, s_min, s_max])
	w.spawner.wave = 5
	var boss := _spawn(w, &"boss", Vector2(-10, -10))
	if boss.speed != 2.2:
		return "Boss 移速 %.3f，預期固定 2.2" % boss.speed
	boss.remove()

	# 弓手箭：射出後把玩家移開讓箭落空，量速度與最遠距離
	var p := _player(w)
	var archer := _spawn(w, &"archer", Vector2(0, 8))
	var proj: Projectile = null
	for i in 600:
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		if not w.projectiles.is_empty():
			proj = w.projectiles[0]
			break
	if proj == null:
		return "弓手 10 秒內沒有射箭"
	p.pos = Vector2(12, -12)
	var origin := proj.pos
	var last := proj.pos
	var speed := 0.0
	var farthest := 0.0
	var ref: WeakRef = weakref(proj)
	proj = null
	for i in 240:
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		var pr: Projectile = ref.get_ref()
		if pr == null or not w.projectiles.has(pr):
			break
		speed = pr.pos.distance_to(last) / DT
		last = pr.pos
		farthest = pr.pos.distance_to(origin)
	_feel("弓手箭：網頁版 10 單位/秒、射程 18；Godot 實測 %.2f 單位/秒、最遠 %.2f" % [speed, farthest])
	archer.remove()
	if absf(speed - 10.0) > 0.01:
		return "箭速 %.2f，預期 10" % speed
	if farthest < 18.0 - 10.0 * DT - EPS or farthest > 18.0 + EPS:
		return "箭最遠 %.2f，預期約 18" % farthest
	return ""


# ---- 網頁版資料比對（tests/web_defs.json 由 tools/dump_web_defs.mjs 匯出） ----

var _web_compared := 0   # 比對過的欄位數（回報用）


func _check_web_defs() -> String:
	var web: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/web_defs.json"))
	if web == null or web.is_empty():
		return "讀不到 tests/web_defs.json（在專案根目錄執行 node tools/dump_web_defs.mjs）"
	var godot := {
		"FIXED_DT": Config.FIXED_DT, "MAX_STEPS_PER_FRAME": Config.MAX_STEPS_PER_FRAME,
		"WORLD": Config.WORLD, "CAMERA": Config.CAMERA, "COMBAT": Config.COMBAT, "PLAYER": Config.PLAYER,
		"SPAWNER": Config.SPAWNER, "AUDIO": Config.AUDIO,
		"WEAPONS": WeaponDefs.WEAPONS, "ENEMIES": EnemyDefs.ENEMIES, "SKILLS": SkillDefs.SKILLS,
		"WAVES": WaveDefs.WAVES, "WAVE_SCALING": WaveDefs.WAVE_SCALING,
	}
	var diffs: Array[String] = []
	_web_compared = 0
	for key: String in web:
		if not godot.has(key):
			diffs.append("%s：Godot 沒有對應的資料表" % key)
			continue
		_compare_web(key, web[key], godot[key], diffs)
	if not diffs.is_empty():
		return "%d 處不同：\n      %s" % [diffs.size(), "\n      ".join(diffs)]
	print("    （比對 %d 個欄位）" % _web_compared)
	return ""


static func _snake(key: String) -> String:
	return RegEx.create_from_string("([a-z0-9])([A-Z])").sub(key, "$1_$2", true).to_lower()


# 網頁版欄位名稱 camelCase → Godot snake_case；Godot 的鍵可能是 String 或 StringName
static func _godot_key(d: Dictionary, web_key: String) -> Variant:
	for k: Variant in [_snake(web_key), StringName(_snake(web_key)), web_key, StringName(web_key)]:
		if d.has(k):
			return k
	return null


# 照使用者的設計刻意和網頁版不同的欄位（路徑用網頁版欄位名稱）：不比對，但要寫明原因
const WEB_DIVERGENCE := {
	"contactDamage": "v0.17.0 B4：設計方向「怪物沒有碰撞傷害」，改用各自的招式（骷髏戰士揮砍）",
	"contactInterval": "同上",
	"contactKnockback": "同上",
}
# 整段不比對的路徑
const WEB_DIVERGENCE_PATHS := {
	"WEAPONS.swordShield.special": "v0.18.0 B5：使用者決定劍盾右鍵從盾擊衝鋒改成格擋與盾反",
}


func _compare_web(path: String, w: Variant, g: Variant, diffs: Array[String]) -> void:
	if WEB_DIVERGENCE_PATHS.has(path):
		return
	if w is Dictionary:
		if not g is Dictionary:
			diffs.append("%s：Godot 不是 Dictionary（%s）" % [path, type_string(typeof(g))])
			return
		for k: String in w:
			if path.begins_with("ENEMIES.") and WEB_DIVERGENCE.has(k):
				continue
			var gk: Variant = _godot_key(g, k)
			if gk == null:
				diffs.append("%s.%s：Godot 缺少欄位 %s" % [path, k, _snake(k)])
			else:
				_compare_web("%s.%s" % [path, k], w[k], g[gk], diffs)
		return
	if w is Array:
		if not (g is Array) or g.size() != w.size():
			diffs.append("%s：陣列不同（網頁版 %s，Godot %s）" % [path, w, g])
			return
		for i in w.size():
			_compare_web("%s[%d]" % [path, i], w[i], g[i], diffs)
		return
	_web_compared += 1
	var same := false
	if w == null:
		same = g == null
	elif w is float or w is int:
		if g is Color:   # 網頁版顏色是 0xRRGGBB 整數
			same = int(w) == (g as Color).to_rgba32() >> 8
		elif g is float or g is int:
			same = absf(float(w) - float(g)) <= 1e-9 * maxf(1.0, absf(float(w)))
	elif w is bool:
		same = g is bool and w == g
	else:
		same = (g is String or g is StringName) and String(g) == String(w)
	if not same:
		diffs.append("%s：網頁版 %s，Godot %s" % [path, w, g])


# audio/sound.gd 用到 GameEvents（autoload），在檢查腳本編譯時還不存在，所以執行時才載入（同 HUD）
func _sound_script() -> GDScript:
	return load("res://audio/sound.gd")


# 讀 tools/synth.gd 寫出的 16-bit WAV（資料從第 44 位元組開始），回傳 { samples, peak }
func _wav_stats(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return {"samples": 0, "peak": 0.0}
	var n := bytes.decode_u32(40) / 2
	var peak := 0
	for i in n:
		peak = maxi(peak, absi(bytes.decode_s16(44 + i * 2)))
	return {"samples": n, "peak": peak / 32767.0}


func _check_sfx_files() -> String:
	var sound_script := _sound_script()
	var web := _web_cue_names().keys()
	var recipes: Array = load("res://tools/bake_sfx.gd").cues().keys()
	web.sort()
	recipes.sort()
	var names: Array = sound_script.CUE_NAMES.duplicate()
	names.sort()
	if web.size() != 30 or web != recipes or web != names:
		return "名稱不一致：網頁版 %d 個、配方 %d 個、Sound.CUE_NAMES %d 個" % [web.size(), recipes.size(), names.size()]
	for cue_name: String in web:
		var stats := _wav_stats(sound_script.SFX_DIR + cue_name + ".wav")
		if stats.samples == 0:
			return "%s.wav 不存在或是空的（執行 tools/bake_sfx.gd）" % cue_name
		if stats.peak >= 1.0:
			return "%s.wav 峰值 %.3f，會失真" % [cue_name, stats.peak]
		if not ResourceLoader.exists(sound_script.SFX_DIR + cue_name + ".wav"):
			return "%s.wav 還沒匯入（執行 --import）" % cue_name
	return ""


func _check_music_files() -> String:
	var sound_script := _sound_script()
	var expected := {&"normal": 60.0 / 64.0 * 16.0, &"boss": 60.0 / 92.0 * 16.0}
	for track: StringName in expected:
		var stream: AudioStreamWAV = sound_script.MUSIC[track]
		if stream.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			return "%s 沒有設定循環（loop_mode = %d）" % [track, stream.loop_mode]
		if absf(stream.get_length() - expected[track]) > 0.01:
			return "%s 長度 %.3f 秒，應為 %.3f" % [track, stream.get_length(), expected[track]]
		var stats := _wav_stats("res://audio/music/%s.wav" % track)
		if stats.peak >= 1.0:
			return "%s 峰值 %.3f，會失真" % [track, stats.peak]
	return ""


func _check_sound_mapping() -> String:
	var sound_script := _sound_script()
	var w := _new_world(7, true)
	var p := _player(w)
	var grunt := _spawn(w, &"grunt", Vector2(6, 0))
	var boss := _spawn(w, &"boss", Vector2(-6, 0))
	var cue := func(event_name: String, payload: Dictionary) -> String:
		return sound_script.cue_for_event(w, event_name, payload)
	var cases := [
		[cue.call("entity:damaged", {"target_id": p.id, "is_crit": false}), "playerHurt"],
		[cue.call("entity:damaged", {"target_id": grunt.id, "is_crit": false}), "hit"],
		[cue.call("entity:damaged", {"target_id": grunt.id, "is_crit": true}), "hitHeavy"],
		[cue.call("entity:damaged", {"target_id": grunt.id, "is_heavy": true}), "hitHeavy"],
		[cue.call("entity:died", {"entity_id": grunt.id}), "enemyDeath"],
		[cue.call("entity:died", {"entity_id": boss.id}), "bossDeath"],
		[cue.call("entity:died", {"entity_id": p.id}), ""],
		[cue.call("skill:used", {"key": "player.special", "player_id": p.id}), ""],
		[cue.call("skill:onCooldown", {"key": "player.slot1", "player_id": p.id}), "denied"],
		[cue.call("wave:started", {"is_boss": false}), "waveStart"],
		[cue.call("wave:started", {"is_boss": true}), "bossAppear"],
		[cue.call("boss:enraged", {}), "enrage"],
		[cue.call("player:died", {}), "defeat"],
		[cue.call("game:victory", {}), "victory"],
		[cue.call("game:paused", {"paused": true}), "pause"],
		[cue.call("game:paused", {"paused": false}), "resume"],
		[cue.call("sfx:cue", {"cue": "arrowShot"}), "arrowShot"],
	]
	for i in ActiveSlots.SLOT_COUNT:   # 道具欄依裝備的技能決定音效
		var slot: Variant = p.slots.slots[i]
		var expect: String = sound_script.SKILL_CUES.get(slot.def.id, "") if slot != null else ""
		cases.append([cue.call("skill:used", {"key": ActiveSlots.cd_key(i), "player_id": p.id}), expect])
	for c in cases:
		if c[0] != c[1]:
			return "預期 %s，實際 %s（第 %d 組）" % [c[1], c[0], cases.find(c) + 1]
		if c[1] != "" and not c[1] in sound_script.CUE_NAMES:
			return "%s 不在 CUE_NAMES" % c[1]
	if not "potion" in cases.map(func(c: Array) -> String: return c[0]):
		return "道具欄沒有治療藥水，無法驗證 potion"

	var m := func(current: StringName, event_name: String, payload: Dictionary) -> StringName:
		return sound_script.music_for_event(current, event_name, payload)
	var music_cases := [
		[m.call(&"", "game:restart", {}), &"normal"],
		[m.call(&"boss", "game:restart", {}), &"normal"],
		[m.call(&"normal", "wave:started", {"is_boss": false}), &"normal"],
		[m.call(&"normal", "wave:started", {"is_boss": true}), &"boss"],
		[m.call(&"boss", "player:died", {}), &""],
		[m.call(&"normal", "game:victory", {}), &""],
		[m.call(&"boss", "game:paused", {"paused": true}), &"boss"],
	]
	for c in music_cases:
		if c[0] != c[1]:
			return "音樂：預期 %s，實際 %s（第 %d 組）" % [c[1], c[0], music_cases.find(c) + 1]
	return ""


func _check_mesh_counts() -> String:
	var limits := {&"player": 20, &"grunt": 16, &"archer": 16, &"boss": 22}
	var err := ""
	for kind: StringName in limits:
		var rig := DarkFantasy.character(kind)
		var stats := _mesh_stats(rig)
		if stats.meshes > limits[kind]:
			err = "%s 有 %d 個零件，上限 %d" % [kind, stats.meshes, limits[kind]]
		elif stats.bad_faces > 0:
			err = "%s 有 %d 個三角形法線方向錯誤" % [kind, stats.bad_faces]
		rig.free()
		if err != "":
			return err
	var rng := RandomNumberGenerator.new()
	var arena := DarkFantasy.build_arena(Config.WORLD.arena_half_size, rng)
	var n := PartKit.mesh_instances(arena).size()
	arena.free()
	if n > 12:
		return "場地有 %d 個零件，上限 12" % n
	for model: StringName in [&"swordShield", &"staff"]:
		var w := DarkFantasy.weapon(model)
		if w.is_empty() or w.main == null:
			return "武器 %s 沒有建立外觀" % model
		for node: Variant in [w.main, w.offhand]:
			if node != null:
				(node as Node3D).free()
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
