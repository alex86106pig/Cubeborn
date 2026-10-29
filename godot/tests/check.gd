# 自動檢查的執行器：依序跑各主題檔的 check_*，畫面只印沒過的項目與總數，有失敗就以 1 結束
# 每一項的結果、單項量到的數字（CheckKit._note）、手感量測都寫進 tests/check_last.log（不進版控）
# 平常用 `node tools/release.mjs --check` 跑（含匯入與逾時）；直接跑：在 godot/ 內 <Godot console 執行檔> --headless --path . -s res://tests/check.gd
# 檢查本體在 core / player / combat / boss / map / loot / view / monster / event / net_checks.gd，共用工具在 check_kit.gd
# 數值都從資料表（Config、defs/）讀：調數值不用改檢查，只有機制改了才要改
# 清單依種類分組（PROJECT_GUIDELINES.md 第 17 節）：同一種機制的子檢查用 CheckKit.all_of 合成一項，子檢查各自獨立
# 打亂順序跑（驗證項目之間不互相依賴）：… -s res://tests/check.gd -- --shuffle=種子
# 只跑標題開頭相符的項目（逐項找洩漏、單獨重跑）：… -- --only=標題開頭
extends SceneTree

const LOG_PATH := "res://tests/check_last.log"

var _passed := 0
var _failed := 0
var _errors := _ErrorCounter.new()
var _log: FileAccess
var _items: Array = []   # [標題, 函式]：先登錄，全部登錄完才跑（--shuffle 時打亂）


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
	_log = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	_log.store_line("Cubeborn Godot 自動檢查　%s\n" % Time.get_datetime_string_from_system(false, true))
	var all := CheckKit.all_of
	var feel := CheckKit._feel_lines

	# ───────── 核心規範與基礎系統 ─────────
	_check("編譯：專案內所有 .gd（含畫面層、main）都能編譯", CoreChecks.check_all_scripts_compile)
	_check("模擬層：sim/ 沒有使用禁止的 API（Input、節點、全域隨機、時間、讀檔、畫面層）", CoreChecks.check_sim_forbidden)
	_check("版號：version.gd 與 CHANGELOG 最新的已發布版本一致；[未發布] 只能在最上面", CoreChecks.check_versions)
	_check("CD：計時、進度、到期、長度 0 視為立即可用", CoreChecks.check_cooldowns)
	_check("狀態機：enter/exit 順序、can_exit 否決、time 累計、data 複製", CoreChecks.check_state_machine)
	_check("InputCmd：按鈕位元不重疊、陣列序列化來回一致", CoreChecks.check_input_cmd)
	_check("碰撞分離：重疊實體依質量比例推開到剛好接觸、固定不動的不被推；格子切分與兩兩比對結果一致（80 個實體）",
		all.bind([CoreChecks.check_separation, CoreChecks.check_grid_matches_brute_force]))
	_check("命中停頓：期間時間縮放變慢，到期恢復 1", CoreChecks.check_hit_stop)
	_check("事件：開場、戰鬥、死亡的事件 payload 只含可序列化的值（沒有物件參照）", CoreChecks.check_events_serializable)
	_check("決定性：有敵人與波次時，同種子、同輸入的兩個 World 結果相同（實體位置、朝向、亂數狀態）", CoreChecks.check_determinism_with_enemies)
	_check("記憶體：reset 與移除實體後舊實體會被釋放（切斷與 World 的循環參照）；敵人移除後 CD 清除",
		all.bind([CoreChecks.check_entity_release, CoreChecks.check_enemy_release]))
	_check("屬性系統：同類百分比相加、暫時效果與冷卻縮減相乘、取整、上下限、來源可移除、顯示格式；接上遊戲：攻速 ×2 普攻時間減半、冷卻 ×0.5、最大生命增加時目前生命同步增加、每秒回血、受傷後暫停回血、除錯移速加成",
		all.bind([CoreChecks.check_stats_formula, CoreChecks.check_stats_hooks]))
	_check("傷害公式：護甲 100 減傷 50%、護甲 8 減傷 7.4%；爆擊率 100% 時乘爆擊傷害、0% 不消耗亂數；傷害保留小數（12.5 實際扣 12.5），數字四捨五入、血量無條件進位",
		all.bind([CoreChecks.check_stats_armor_crit, CoreChecks.check_fractional_damage]))

	# ───────── 玩家操作 ─────────
	_check("移動與轉向：1 秒移動 move_speed 單位、斜向輸入長度被限制為 1；面朝瞄準點；停在場地邊界 arena_half_size - radius",
		all.bind([PlayerChecks.check_player_move, PlayerChecks.check_facing, PlayerChecks.check_arena_clamp]))
	_check("劍盾普攻與連段：三段時間合計 windup + active + recovery、期間移速照 move_speed_mul；前兩段照基礎傷害、第三段乘 finisher_mul 且後搖乘 finisher_recovery_mul、重擊與音效只有第三段、同一目標每次出手只中一次",
		all.bind([PlayerChecks.check_attack_timing, PlayerChecks.check_combo]))
	_check("格擋與招架（v0.41.0）：按住右鍵才格擋、放開就放下、沒有冷卻與時間上限、可移動轉向、翻滾提前放下；格擋中按左鍵招架（冷卻、按住不連發），判定內擋下 = 全額盾反，沒擋到 = 盾擊；正面擋得下揮砍與箭、背後擋不住；Boss 衝鋒擋得住但全額推退；Boss 砸地擋不住", PlayerChecks.check_block)
	_check("受擊：扣血後進入 stagger（移速照 stagger_move_speed_mul、持續 stagger_time）、無敵 invuln_time、畫面震動", PlayerChecks.check_stagger)
	_check("輸入緩衝：攻擊中按右鍵會在後搖取消並接特殊技；緩衝過期後不會被消化", PlayerChecks.check_buffer)
	_check("死亡：發出 player:died、移動層進入 dead、不再接受輸入", PlayerChecks.check_player_death)
	_check("數字鍵欄位：治療藥水（次數、不超過上限、滿血不能用、冷卻、用完不能用）；攻擊中按 1 會在後搖取消並使用、空欄位不提示；Ctrl 切換跑步（×1.4，跳躍翻滾不取消，攻擊、技能欄、硬直取消）",
		all.bind([PlayerChecks.check_heal_slot, PlayerChecks.check_run, PlayerChecks.check_slot_buffer]))
	_check("翻滾：duration 秒翻 distance 單位、移速 +50% 翻 1.5 倍遠、冷卻吃 roll_cooldown、次數 +1 可連翻兩次；開始後 invuln_time 內打不到、投射物穿過；普攻前後搖可取消，揮下去、特殊技、硬直中先緩衝",
		all.bind([PlayerChecks.check_roll_motion, PlayerChecks.check_roll_invuln, PlayerChecks.check_roll_cancel]))
	_check("跳躍：空中時間一半時到最高 JUMP.height、air_time 落地；空中不能再跳；攻擊中可以跳、硬直中不行；空中翻滾照常下墜且一樣遠", PlayerChecks.check_jump_motion)
	_check("動作手感：擊退總位移符合阻尼公式、轉身 180° 的步數符合 turn_speed、普攻與第三段前衝距離、連段窗口內接下一段、超過就重來", PlayerChecks.check_motion_feel)

	# ───────── 職業與武器 ─────────
	_check("職業（F2）：開局套用基礎數值、起始武器、被動；沒選職業照舊、重新開始保留；守墓騎士被隊友從背後打到減半", PlayerChecks.check_classes)
	_check("武器資料：behavior 存在、三段時間為正數、音效名稱都在 Sound.CUE_NAMES；每把武器都有道具資料與模型，職業的起始武器都存在；每一招都有畫好的圖示與說明", CombatChecks.check_weapon_defs)
	_check("武器基礎數值：面板攻擊力 / 攻速 / 範圍 = 武器資料 × 稀有度倍率；裝上綠劍盾後攻擊力與揮砍距離跟著倍率", CombatChecks.check_weapon_base_stats)
	_check("傷害類型（F1）：基礎傷害 × 招式 % × 物理 / 魔法傷害；護甲只擋物理、魔抗只擋魔法；閃避率封頂 75% 且 0 時不擲骰；尋寶加權", CombatChecks.check_damage_types)
	_check("法杖：魔彈從前方 spawn_offset 產生、照速度飛、命中造成武器傷害、飛滿射程消失；奧術爆裂落點限制在 min_range ~ range、半徑內才受傷；普攻按住照三段時間連發、打中骷髏不擊退不硬直",
		all.bind([CombatChecks.check_fire_bolt, CombatChecks.check_arcane_burst, CombatChecks.check_staff_changes]))
	_check("短弓（F4）：快射是不擊退的箭、傷害照物理加成；散射 5 支平均分在 50° 內；盜墓遊俠移動中普攻不減速、右鍵照常減速；箭袋 6 支、最後一支重箭、射空裝填 1.2 秒、翻滾瞬間補滿", CombatChecks.check_shortbow)
	_check("長弓（F5）：重射可擊退；按住右鍵蓄力、放開射出穿透箭（沒蓄 150%、蓄滿 400%），一直線上每隻打一次", CombatChecks.check_longbow)
	_check("雙匕首（F6）：五連刺第 5 下 150% 必爆擊且只有它擊退、讓怪硬直；影步瞬移到怪背後背刺必爆擊、沒有怪不瞬移冷卻 1 秒；竊影者翻滾 2 次、翻滾後攻速 +30% 持續 1.5 秒", CombatChecks.check_daggers)
	_check("驅魔權杖（F7）：敲擊是魔法、可擊退；聖光圈 4 秒每 0.5 秒對範圍內敵人持續傷害（不爆擊）、隊友回血；神官救人快 50%、救起回 50% 生命", CombatChecks.check_scepter)
	_check("火把（F8）：按住右鍵舉火把（移速 ×0.6）、放開放下；舉著左鍵噴火 120%（冷卻 6 秒、不占右鍵）；插火把在技能欄第一個空格（冷卻 1 秒、3 次記在武器上、換層補滿）；翻滾放下；火把旁不管視野都看得到；揮擊點燃；傭兵視野 +3、身邊 6", CombatChecks.check_torch)
	_check("鐵鏟（F9）：鏟起面前的怪舉 2 秒（移速 ×0.7、不能跳），左鍵拋出（落地 200%、路上 150%）、右鍵埋入（80%、2 秒）、沒按就掙脫；Boss 抓不起來、沒抓到冷卻 2 秒；掘墓人挖墳中受傷 −25%；埋著打得到、不被擊退", CombatChecks.check_shovel)
	_check("武器測試木樁（--weapon-test）：爬出後站著不動、不打人；鐵鏟抓得起、埋得下，埋完回到站著", CombatChecks.check_training_dummies)

	# ───────── 小怪與戰鬥判定 ─────────
	_check("高度判定：最高點時箭從腳下飛過、地面會中箭；跳起來躲過 Boss 砸地；空中揮砍與空中魔彈打得到地上的怪", CombatChecks.check_height_hits)
	_check("打擊感：玩家打中不震動、模擬時間不放慢（hit_stop 只放進事件）；玩家被打與 Boss 砸地照常震動；沒有命中定格", CombatChecks.check_hit_feel)
	_check("沒有碰撞傷害：骷髏戰士（揮砍冷卻中）、弓手（不射箭時）、Boss（不出招時）貼身 2 秒都不扣血", CombatChecks.check_no_contact_damage)
	_check("骷髏戰士：爬出 spawn_time 後追擊、揮砍傷害照資料、間隔 ≥ 冷卻、受擊硬直 hurt_time；舉刀 windup 秒後才命中、扇形邊界（加目標半徑）、後半鎖定方向繞到側面就躲開、舉刀中被打會中斷",
		all.bind([CombatChecks.check_melee_enemy, CombatChecks.check_grunt_swing]))
	_check("骷髏弓手：瞄準 aim_time 後射箭、箭傷害照資料、保持在 preferred_range 附近", CombatChecks.check_ranged_enemy)
	_check("敵人移速與箭：小怪移速 = 基礎 × 波次成長 × 隨機 ±變異、Boss 固定；弓手的箭速與射程照資料", CombatChecks.check_enemy_speed)
	_check("投射物不穿牆：魔彈對牆射會在牆前消失；從高台往下射照樣打得到地上的怪", CombatChecks.check_projectile_walls)

	# ───────── Boss ─────────
	_check("瞬移砸地躲得掉（v0.42.0，每圈間隔 0.5 秒）：站著不動被第 1 圈打一次；看到預兆反應 0.3 秒往外直跑三圈都打不到；地板裂紋比每圈爆開早 ring_delay 爬滿、變亮到爆開後淡掉", BossChecks.check_teleport_slam_dodge.bind(feel))
	_check("Boss 砸地：近身時前搖後打中、擊飛 + 緩速、CD；一圈圈往外（外圈晚 ring_delay）、每人只被打一次；霸體不硬直、擊退乘 knockback_mul", BossChecks.check_boss_slam)
	_check("Boss 衝鋒：蓄力 windup、照 speed 衝刺、命中傷害並讓玩家暈眩 stun、撞牆自己暈眩 wall_stun", BossChecks.check_boss_charge)
	_check("Boss 直劈：沒有地面預警；舉劍 windup 秒後劈下；追蹤只做一半，繞圈走位躲得開", BossChecks.check_boss_cleave)
	_check("Boss 狂暴招式：衝鋒連 charge_count 次；召喚的骷髏戰士衝撞一次；砸地不管多遠都放（玩家腳下冒紫煙、不畫圈 → 瞬移 → 砸）", BossChecks.check_boss_enraged_moves)
	_check("怪物攻擊不畫預警圈：sim/ 只有玩家方的道具與聖光圈發 fx:telegraph；Boss 砸地、衝鋒、召喚、直劈的預備動作兩兩不同",
		all.bind([ViewChecks.check_no_monster_telegraph, ViewChecks.check_boss_windup_poses]))
	_check("Boss 召喚與狂暴：血量低於召喚門檻召喚 count 隻、低於狂暴門檻狂暴（移速、CD、前搖倍率）", BossChecks.check_boss_summon_enrage)
	_check("Boss 跳上高台：從地面跳上 1.0 石座；衝鋒遇到 1.0 石台直接跳上去不暈眩、遇到牆照樣暈眩；砸地打得到旁邊 1.0 石台上的玩家，跳起來躲得過", BossChecks.check_boss_high_ground)

	# ───────── 地圖、尋路與生成 ─────────
	_check("波次資料：只有最後一波是 Boss、其他波都有小怪、敵人類型存在、成長倍率線性", MapChecks.check_wave_defs)
	_check("生成：first_delay 後開第一波、第一波數量照資料、離玩家 min_distance 以上、第 3 波小怪套成長倍率", MapChecks.check_spawning)
	_check("一局流程：每波依序開始、打倒 Boss 後 is_over、victory_delay 秒後 game:victory、擊殺數正確", MapChecks.check_full_run)
	_check("地形：0.5 石台走不上去、跳得上去；從 0.5 跳上 1.0；走出邊緣會掉回地面；2.5 的牆跳不過去；起跳偵測的快速排除（Terrain.may_rise）不漏掉會起跳的地方",
		all.bind([MapChecks.check_terrain, MapChecks.check_may_rise]))
	_check("地圖 A（環形墓園）：大小與邊界一致、石台都在場地內、出生點與挖墳點可走且相連、可走的格子連成一片、相鄰可走格高低差 ≤ climb_height、牆比最高的地面高出跳躍高度以上；挖墳事件生的小怪都在離玩家 min ~ max_distance、走得到玩家的地方",
		all.bind([MapChecks.check_map_a, MapChecks.check_map_spawns]))
	_check("怪物尋路：直線離牆小於 margin 不算看得到、繞北門變慢的步數 < 30；玩家在圍牆內，骷髏戰士從牆外繞到北門打到、弓手繞進來射中；離目標超過 far_distance 時降低重新判斷頻率、走進來立刻判斷",
		all.bind([MapChecks.check_nav_clearance, MapChecks.check_enemy_pathing, MapChecks.check_far_repath]))
	_check("高台：骷髏戰士先蹲 jump_windup 再跳，經 0.5 跳上 1.0 打到玩家、Boss 也跳得上去；弓手射得到高台上的玩家、被牆擋住先移動不對牆射",
		all.bind([MapChecks.check_enemy_climb, MapChecks.check_archer_high_ground]))

	# ───────── 怪物稀有度與挖墳事件 ─────────
	_check("怪物種類只看資料表：每種怪的 behavior 都對應得到行為類別、建出來的類別一致；is_boss、freeze_immune 照資料；挖墳事件的 boss_type 是 Boss；各層怪群與挖墳怪潮只有 FLOOR_MIX 這一層的怪、挖墳點噴下一層的；召喚詞條叫出同種的怪",
		all.bind([MonsterChecks.check_enemy_defs, MonsterChecks.check_floor_mix]))
	_check("腐屍：撲中抓住 grab_time 秒、撲 1 下 + 每 bite_interval 咬一口；被抓時按翻滾立刻掙脫；隊友打它就鬆手；舉盾擋下不被抓、腐屍踉蹌", MonsterChecks.check_zombie)
	_check("膨脹屍：走近停下脹大 swell_time 秒（被打不硬直）→ 自爆炸到玩家與旁邊的怪、不給靈魂；留下腐氣持續傷害玩家與怪、不畫圈只冒煙；被打死 death_delay 秒後照樣炸、給靈魂", MonsterChecks.check_bloater)
	_check("屍犬：玩家站著不轉身時繞到背後（≥ behind_angle）才撲、patience 內做到；玩家一直轉身看著它 patience 內不撲、之後從正面撲；撲中有傷害", MonsterChecks.check_hound)
	_check("守墓人（第 1 層 Boss）：假裝 NPC（旁邊 3 秒不開打；按 F 說話先冒台詞、不開挖、reveal_time 後開打；被打或有人開挖直接開打）；" \
		+ "四招（鐵鏟 windup 後打中；鏟土 windup + flight_time 落地、發 fx:dirt_lob；噴火每 tick 一下再被殘火燒；口哨叫不給靈魂的屍犬；不畫預警圈）；" \
		+ "半血轉型態（無敵 transform.time 秒 → 狼人移速、嚎叫、提燈火堆；三連爪吃滿 3 下、飛撲落地打中、狼嚎叫魔法屍犬並加速）",
		all.bind([MonsterChecks.check_gravekeeper_npc, MonsterChecks.check_gravekeeper_moves, MonsterChecks.check_gravekeeper_transform]))
	_check("怪物稀有度（D5）：魔法 / 稀有骷髏的生命、攻擊力、體型照倍率；詞條數照 RARITIES.affixes 不重複、稀有怪有名字；每群魔法 magic_per_pack 隻、稀有 rare_chance（±1.5%）", MonsterChecks.check_rarity)
	_check("怪物詞條（D5）：迅捷 / 強壯 / 厚皮照 mods 倍率、再生、吸血、狂暴、死亡爆炸、召喚照資料", MonsterChecks.check_affixes)
	_check("怪群（D5）：地圖 A 散放 PACKS.count 群、每群 size 隻、距離限制、都走得到；開場休眠不播音效、不動；走近或被打整群醒來；同種子結果相同", MonsterChecks.check_packs)
	_check("蒙皮小怪（D5 效能）：骷髏戰士 / 弓手 / 腐屍合成一個蒙皮網格（≤ 2 個網格、頂點數與原本零件相同），關節姿勢寫進骨架", MonsterChecks.check_skinned_rig)
	_check("挖墳（D6）：DIG.range 內按住 F 開始事件並挖墳；挖墳中不能移動、跳，照樣轉向，被打不中斷不被擊退；總量 DIG.time × 活著的人數、一起挖速度相加、放手不掉（DIG.decay）、噴怪 +ERUPT.progress；挖完出口打開", EventChecks.check_dig)
	_check("事件難度（D6）：怪物生命 × difficulty_mul；生怪間隔遞減夾在 interval_min；每批隻數隨難度與人數增加；魔法 / 稀有機率隨難度；挖墳前不冒怪、開挖就開始怪潮、難度每秒 +per_second；選的難度（簡單 / 普通 / 困難）讓上升 ×0.75 / ×1 / ×1.5、重新開始保留；挖墳點噴怪（墳土隆起預警、不畫圈、數量、下一層難度、拋物線落地）；挖完停怪、難度不漲、場上的怪留著", EventChecks.check_difficulty)
	_check("出口與換層（D6）：挖完不會自動走；墳墓旁按 F，單人最後一層直接通關；多人投票（Esc 反對取消、全員同意或 VOTE.time 秒到就走、陣亡的不用投）；換層回出生點、基礎難度 +per_floor、保留靈魂與背包、地上與怪物清空、寶箱重放、事件歸零", EventChecks.check_next_floor)
	_check("Boss（D6）：挖墳地圖開局在 boss_room 裡巡邏、沒看到玩家不追、不出範圍；前方視野或貼近看到玩家、被打就開始追、不限範圍；打倒不通關，掉 1 把武器、1 個大寶箱機率的道具、Boss 靈魂", EventChecks.check_boss_reward)
	_check("屍體與冤魂（D6）：多人時死亡留下屍體、撿進背包；背著換層出現冤魂，打倒後死者在那裡復活、屍體消失；沒人帶屍體就沒有冤魂", EventChecks.check_corpse_ghost)

	# ───────── 背包、祭壇與武器 ─────────
	_check("背包：大小照 BAG_SIZE；形狀旋轉後格子正確；超出邊界、重疊放不下；自動找第一個空位（不夠時會轉向）；搬動成功 / 失敗；裝滿後撿不起來並發出 inventory:full；放不下時建議拿掉哪一件（占格最少），拿掉一件也不夠就不建議",
		all.bind([LootChecks.check_inventory, LootChecks.check_inventory_suggest]))
	_check("祭壇與石棺：數量照地圖資料、位置可走且夠遠、殺怪靈魂照 KILL_SOULS（共用）、靈魂不夠開不了、夠了扣靈魂並掉一個道具、開過不能再開；隨機放（同種子相同）與人數倍率、全清買不完；稀有度各抽 20000 次符合權重、不會開出武器",
		all.bind([LootChecks.check_soul_chests, LootChecks.check_chest_balance, LootChecks.check_chest_rarity]))
	_check("局外金幣（v0.45）：過第 1 / 2 層給 5 / 10；地上的金幣走近自動撿、倒地不撿、多人只記一個數字；Profile 存檔讀得回來；掉落率符合 RUN_COINS.drop_chance（±4 個標準差）、召喚出來的不掉",
		all.bind([LootChecks.check_run_coins, LootChecks.check_coin_drops]))
	_check("撿道具：按 F 撿起最近的道具放進背包並生效；剛按下那一步才算；兩人同一步按 F 只有一人拿到；丟掉後道具回到地上、效果移除；附近有倒地隊友時 F 先救人；從腳邊拖進背包放到指定格子（太遠、放不下、已被撿走不動，武器不放裝備欄）；撿不下的事件帶地上道具的 id",
		all.bind([LootChecks.check_pickups, LootChecks.check_pickup_to_cell]))
	_check("武器掉落與詞條：小怪掉落率符合 DROP_CHANCE、Boss 必掉、稀有度符合權重；詞條數 = 稀有度順位、不重複；只有手上那把生效，X 切換後屬性跟著換",
		all.bind([LootChecks.check_weapon_drops, LootChecks.check_weapon_affixes]))
	_check("武器的背包操作：撿武器先放裝備欄、滿了放背包、都滿撿不起來，裝備欄 ↔ 背包搬動、手上至少留一把；兩把同種同稀有度合成 → 高一級、詞條重抽，不同種 / 不同稀有度 / 橘色不能合成",
		all.bind([LootChecks.check_weapon_pickup, LootChecks.check_weapon_merge]))

	# ───────── 道具（依效果種類：屬性 / 條件 / 觸發 / 能力）─────────
	_check("物品資料：每個稀有度都有道具，名稱不重複、欄位完整、形狀合法、格數 = ceil(強度 ÷ 稀有度效率)、效果都對應到存在的屬性 / 條件 / 觸發 / 能力", LootChecks.check_item_defs)
	_check("道具效果的類別：ItemDefs 標成已接上的條件與觸發，和 ItemEffects 的條件 / 動作類別一一對應", LootChecks.check_item_effect_registry)
	_check("道具屬性：放進身上照資料生效（百分比同類相加、最大生命與目前生命一起加、移除後回到原值、武器道具直接換武器）；命中回復有內部冷卻、吸血看實際扣血、投射物減傷、靈魂看擊殺者（小數累積）與精英倍率、祭壇價格看開的人、撿取範圍、視野距離與角度",
		all.bind([LootChecks.check_items_apply, LootChecks.check_item_stats]))
	_check("道具條件：對滿血敵人、低於門檻生命、擊殺後一段時間、翻滾後一段時間、本層每擊殺疊一層（有上限、換層歸零）；拿掉道具就沒了",
		all.bind([LootChecks.check_item_conditions, LootChecks.check_item_conditions_roll_kills]))
	_check("道具觸發：擊殺（爆炸、回血、鬼火、召喚骷髏僕從）、命中（連鎖閃電、中毒、冰凍、點燃擴散）、受傷（近戰反彈、自身爆炸）、投射物命中（爆炸）、普攻出手（飛刀、斬波）、定時（落雷）、翻滾（減速）、致命傷（守護亡靈、復活十字）；機率相加、內部冷卻、上限",
		all.bind([LootChecks.check_item_procs, LootChecks.check_item_procs_hurt_ignite, LootChecks.check_item_procs_attack_timed,
			LootChecks.check_item_procs_lethal, LootChecks.check_item_procs_summon]))
	_check("道具能力：二段跳（沒有道具空中跳不了、有雙躍之靴可再跳一次、落地重置）；自動回充的護盾（先扣盾、recharge_delay 秒沒受傷才補滿）",
		all.bind([PlayerChecks.check_double_jump, LootChecks.check_item_shield]))
	_check("道具掉落：全部道具的效果都已接上；寶箱只開出效果都接上的道具；沒有的稀有度往下一級找", LootChecks.check_item_drop_pool)

	# ───────── 畫面 ─────────
	_check("角色視野：前方扇形與 range 內看得到、身邊 near_radius 背後也看得到；牆擋視線、高台不擋；自己的投射物在背後也看得到、怪物的看不到；寶箱看中心、怪物看身體邊緣", ViewChecks.check_vision_rules)
	_check("視野畫面：背後的模型隱藏、前方的顯示；背後的特效不畫；轉身時 fade_out / fade_in 淡出淡入；本機角色陣亡後全部看得到；變暗遮罩最先畫；挖墳中朝向與遮罩跟著滑鼠",
		all.bind([ViewChecks.check_vision_view, ViewChecks.check_dig_vision]))
	_check("觀戰：多人時本機陣亡看第一位站著的隊友、左右切換、看的人死了或走進出口就換、沒人可看就不觀戰；視野改用隊友的；房主依 InputCmd.spectate 挑快照；復活後回到自己", ViewChecks.check_spectate)
	_check("頭頂血條：滿血不畫、受傷畫；自己與隊友綠、怪物紅；視野外、Boss、倒地、隱藏的不畫；比例 = hp / max_hp；不疊到詞條與名牌", ViewChecks.check_health_bars)
	_check("開場預熱：每一種怪、魔法 / 稀有怪、玩家、寶箱、金幣、道具、武器、投射物、每種稀有度的武器（含淡入淡出中的版本）都在鏡頭附近畫幾幀後移除；點光源前一半關後一半開；預熱文字含所有會用到的字", ViewChecks.check_warm_up)
	_check("牆後剪影：角色材質寫模板值；玩家一直有、怪物只有被牆擋住時才有；箭與魔彈被牆擋住時畫剪影（怪物紅、自己藍），同顏色的投射物共用材質",
		all.bind([ViewChecks.check_xray, ViewChecks.check_projectile_xray]))
	_check("寶箱模型：已開過的寶箱重新建立模型時箱蓋直接打開、不重播開蓋；沒開過的關著", ViewChecks.check_chest_lid)
	_check("模型零件：依 anchor + 材質合併、外框不變、keep 的零件留在原位、法線朝外；零件數上限（騎士 ≤ 20、骷髏 ≤ 16、Boss ≤ 22、場地 ≤ 12）；"
		+ "披風整片在軀幹後面、身體前方沒有披風色的零件；盾的尖角和盾面同一平面；騎士骨架有 back / forearm_l / head / hip_l / hip_r 掛點，盾掛 forearm_l、箭袋掛 back",
		all.bind([ViewChecks.check_merge_static, ViewChecks.check_mesh_counts, ViewChecks.check_body_parts]))
	_check("握武器與持弓：每把玩家武器的 grip 掛點在拳頭中心（手掌掛點）、手掌掛點上有拳頭；法杖類直立靠轉手掌（武器不另外轉）；骷髏與 Boss 的拳頭也在手掌掛點上；"
		+ "弓不拉弓時平放（弓梢連線水平、弓背朝下、弦在上）；骷髏弓手瞄準時舉平、射完右手平滑放下、目標在射擊距離內左手停在預備高度、離開射擊距離才平滑放回垂直",
		all.bind([ViewChecks.check_weapon_grip, ViewChecks.check_bow_rest, ViewChecks.check_archer_bow_arm]))
	_check("受擊閃白：只改自發光顏色、不切換 emission_enabled（切換會在第一次命中即時編譯著色器而卡頓）", ViewChecks.check_flash_no_shader_switch)
	_check("特效：模擬層發出的每個 fx:* 都有畫面處理、也列在 PROJECT_GUIDELINES 第 9 節，餵給 Effects 會產生粒子；粒子與弧光環有上限、拖尾 30 / 144 FPS 每秒粒子數相同、暫停時不產生",
		all.bind([ViewChecks.check_effects_events, ViewChecks.check_effects_limits]))

	# ───────── 介面 ─────────
	_check("HUD：能建立、處理各種事件、顯示波次 / 血量 / 結算文字、暫停畫面有「離開遊戲」；別人撿到道具不跳橫幅；武器欄的另一把標示切換鍵 X", ViewChecks.check_hud)
	_check("背包介面：和屬性面板並排塞得進介面最大檔的畫面；腳邊欄只列按得到 F 的地上道具、滑鼠停著顯示說明，拖進背包撿起放在那一格、背包的拖到腳邊丟掉；撿不下時 HUD 通知打開背包、提示拿掉哪一件就放得下，關掉就清除", ViewChecks.check_inventory_panel)
	_check("技能欄：劍盾格擋中左鍵換成「招架」與冷卻、法杖沒有招架格；火把準備姿態換成插火把 / 噴火、鐵鏟舉著怪換成拋出 / 埋入；CD 遮罩疊放順序 文字圖示 < 壓黑 < 秒數",
		all.bind([ViewChecks.check_skill_bar_parry, ViewChecks.check_skill_bar_cd_mask]))
	_check("新手提示：換武器鍵是 X；開場跳操作與挖墳；撿到東西、開背包、可合成、出口打開、隊友倒地各跳一次；看過不再跳；重設後再跳", ViewChecks.check_hints)
	_check("挖墳進度條：事件進行中所有人上方中央都看得到進度與說明，出口打開後收起；Boss 血條排在它下面、寬度塞得進 1920", ViewChecks.check_dig_bar)
	_check("主選單：首頁有單人 / 多人 / 離開遊戲（網頁版不顯示離開）、桌面版先選房號 / IP、多人頁放連線面板與返回、塞得進 1920×1080；暫停畫面有「回主選單」；選角畫面（點職業只是選、按開始才開局帶難度、佔位選不到、數值條照職業、塞得進）；武器測試場入口與按鈕列", ViewChecks.check_main_menu)
	_check("設定頁：主選單與暫停畫面的「設定」打開、塞得進 1920×1080、選單關掉一起關；改值存檔讀得回來（啟動參數蓋的不存）；音量套到 Music / SFX 匯流排、0% = −80 dB；陰影與光源開關套到太陽和精英怪的光（之後新建的也照設定）；--shadows / --lights", ViewChecks.check_settings)
	_check("按鈕：ui/ 裡都用 UiKit.button（選單 / 面板 / 一排很多顆三種尺寸），不自己 Button.new()", ViewChecks.check_buttons)
	_check("網頁版網址參數：?horde=200&perf&seconds=20 轉成 --horde=200 --perf --seconds=20；連線參數 host / join / room / net-autostart 也轉；不在開放清單的參數不轉", ViewChecks.check_url_query_args)
	_check("遊玩紀錄：自己的擊殺依種類、受到的傷害依攻擊者、被看不見的攻擊、倒下被誰打倒；結算畫面塞得進 1920×1080；「複製遊玩紀錄」內容完整；重新開始清空", ViewChecks.check_run_log)
	_check("字型：介面文字都在打包的 Noto Sans TC 裡（網頁版沒有系統字型），缺字的圖示改用向量圖", ViewChecks.check_font_coverage)

	# ───────── 音效 ─────────
	_check("音效素材：模擬層 sfx:cue 的名稱都在 Sound.CUE_NAMES；每個名稱都有配方與 wav（不是空的、峰值 ≤ 1）；背景音樂一般 / Boss 往前循環、長度 15.00 / 10.43 秒",
		all.bind([ViewChecks.check_sim_cues, ViewChecks.check_sfx_files, ViewChecks.check_music_files]))
	_check("音效播放：事件 → 音效、Boss 波換 Boss 曲、死亡停音樂；距離衰減（15 內全音量、35 外不播、中間 (1 − t)²）、sfx:cue 都帶位置、法杖普攻 −8 dB",
		all.bind([ViewChecks.check_sound_mapping, ViewChecks.check_sound_distance]))
	_check("結束程式不洩漏：主場景跑 3 秒（有怪、一直攻擊，音效還在播）後結束兩次，沒有 ObjectDB 洩漏、資源還在用", ViewChecks.check_quit_no_leak)

	# ───────── 連線 ─────────
	_check("快照：房主的實體序列化後客戶端建立同樣類別、位置、血量、武器的鏡像、動畫狀態相同時數值補間；地圖 A 怪群 + 4 人、P2 被 30 隻圍住時每份快照 ≤ 4.5 KB",
		all.bind([NetChecks.check_codec, NetChecks.check_snapshot_size.bind(feel)]))
	_check("網頁連線配對（v0.36.0）：PeerJS 網址、房主 ID、房號（4 碼、不含易混字）、訊息格式、伺服器訊息對應的訊號；桌面版 IP 與房號兩種都能用", NetChecks.check_web_signaling)
	_check("桌面版 WebRTC（v0.40.0）：同一程序兩條連線交換 SDP，照 NetSession 的設定建房主 / 客戶端，5 秒內連上且封包收得到；網頁版接收緩衝區至少 1024 KB", NetChecks.check_desktop_webrtc.bind(feel))
	_check("誤傷（C2）：玩家揮劍打得到前方的隊友、打不到自己；魔彈打得到隊友、不打發射者；單機目標不含自己", NetChecks.check_friendly_fire)
	_check("人數調整（C3）：敵人數量不變、血量每多 1 人 +50%（Boss 也是）", NetChecks.check_player_count_scaling)
	_check("倒下與救援（C4）：多人時生命歸零先倒地假死、down_time 秒沒人救才死亡、最後一人倒下 game:defeat、單機直接死亡；範圍內按住 F 累積 revive_time 秒救起、期間不能動但會轉向、放開進度衰退、救起 revive_hp_ratio 的血",
		all.bind([NetChecks.check_downed, NetChecks.check_revive]))
	_check("大廳選職業（F3）：預設第一個職業、全員準備好才能開始；選角畫面的名單、舞台站位、客戶端準備鈕與難度鎖住、預選即時更新；房主改難度重設準備、佔位選不到；開局後房主與客戶端的角色職業、移速、武器一致", NetChecks.check_lobby_classes)
	_check("戰鬥同步（C2）：延遲 3 步、30 秒對打，客戶端套用的每筆快照擊殺 / 波次 / 敵人血量都和房主當時一致，事件順序一致", NetChecks.check_sync.bind(feel))
	_check("遊玩紀錄的連線數據：延遲 100 ms 時回應時間在「來回 + 快照間隔」內、快照最長間隔約 snapshot_interval 步、房主收輸入最長間隔約 1 步", NetChecks.check_net_stats.bind(feel))
	_check("延遲下的手感（C3）：延遲 100 ms + 掉包 10%，按下就在本機移動、修正誤差 < 0.25、停下後與房主差 < 0.01；別人的角色每步位移平順", NetChecks.check_prediction.bind(feel))
	_check("打中回饋與延遲補償（v0.38.0）：延遲 100 ms 時客戶端的火花 / 音效 / 閃白在出招當下出現一次，房主的同一下標 predicted；側移的怪兩邊都判定打中", NetChecks.check_hit_prediction.bind(feel))
	_check("連線武器（D4）：客戶端按 X 切換、拖曳合成，兩邊的裝備欄、手上武器、詞條一致；殺怪掉的武器兩邊都看得到", NetChecks.check_net_weapons)
	_check("連線稀有度（D5）：客戶端的稀有度、詞條、名字、半徑、最大生命與房主相同；普通怪的快照不帶稀有度欄位", MonsterChecks.check_net_rarity)
	_check("連線寶箱與背包（D3）：客戶端按 F 開箱、再按 F 撿起、拖曳搬動與丟掉、從腳邊拖回背包指定的格子；兩邊的寶箱、靈魂、背包、生效道具一致", NetChecks.check_net_loot)
	_check("連線金幣（v0.45）：房主掉的金幣客戶端看得到；客戶端走過去撿起，兩邊本局金幣都是 1、地上都沒了", NetChecks.check_net_coins)
	_check("連線道具（G）：客戶端看到玩家方的骷髏僕從與鬼火；自己的護盾量跟房主一致（被打後也是）；守護亡靈救下後不倒地並收到 player:saved；碎骨爆裂特效收得到", NetChecks.check_net_items)
	_check("連線倒下與救援（C4）：客戶端跟著房主倒地、不能預測移動，被救起後站起來；客戶端按住 F 也能救起房主", NetChecks.check_net_downed)
	_check("連線挖墳（D6）：層數、事件狀態、進度、難度、怪潮、走進出口、屍體的主人與挖墳點在客戶端相同", EventChecks.check_net_event)
	_check("兩個程序連線（C1）：headless 照玩家順序（主選單多人頁開房 / 加入）連線（ENet），兩邊都沒停在暫停、收得到輸入、特效在走、自己的角色各移動約 13 單位，停下後兩邊的玩家位置一致（< 0.01）", NetChecks.check_two_processes.bind(feel))
	_check("兩個程序連線道具（G）：房主帶亡者大軍、骨製護盾、鬼火燈籠打一群怪，兩邊這一局都看過玩家方的骷髏僕從，兩份 log 沒有執行期錯誤", NetChecks.check_two_processes_items.bind(feel))

	await _run_all()
	_log.store_line("\n手感量測（給 docs/手感對照.md）：\n    " + "\n    ".join(CheckKit._feel_lines))
	for w in CheckKit._worlds:
		w.clear()
	CheckKit._worlds.clear()
	NetChecks.cleanup()
	MonsterChecks.cleanup()
	EventChecks.cleanup()
	var summary := "%d / %d 通過" % [_passed, _passed + _failed]
	_log.store_line("\n" + summary)
	_log.close()
	print(("\n" if _failed > 0 else "") + summary + "（完整結果：godot/tests/check_last.log）")
	OS.remove_logger(_errors)
	quit(1 if _failed > 0 else 0)


func _check(title: String, fn: Callable) -> void:
	_items.append([title, fn])


# --shuffle=種子：打亂順序跑，項目之間有依賴（共用的狀態、靜態快取、存檔）就會失敗；--only=標題開頭：只跑相符的項目
func _run_all() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.get_slice("=", 1)
		if arg.begins_with("--shuffle="):
			var rng := RandomNumberGenerator.new()
			rng.seed = arg.get_slice("=", 1).to_int()
			for i in range(_items.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var t: Variant = _items[i]
				_items[i] = _items[j]
				_items[j] = t
			_log.store_line("（打亂順序，種子 %s）\n" % arg.get_slice("=", 1))
	for it: Array in _items:
		if only == "" or (it[0] as String).begins_with(only):
			await _run_one(it[0], it[1])


# 檢查函式可以 await（要等畫面更新一幀才量得準的，例如換過文字的介面尺寸）；沒 await 的照舊同步跑完、不會多跑幀
func _run_one(title: String, fn: Callable) -> void:
	var errors_before := _errors.count
	var result: Variant = await fn.call()
	var err: String = result if result is String else "檢查函式沒有回傳結果"
	if _errors.count > errors_before:
		err = "執行期間發生 %d 個錯誤，最後一個：%s" % [_errors.count - errors_before, _errors.last]
	if err == "":
		_passed += 1
		_log.store_line("✔ " + title)
	else:
		_failed += 1
		var line := "✘ %s\n    %s" % [title, err]
		_log.store_line(line)
		print(line)
	for note in CheckKit._notes:
		_log.store_line("    " + note)
	CheckKit._notes.clear()
