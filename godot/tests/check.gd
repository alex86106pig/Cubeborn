# 自動檢查的執行器：依序跑各主題檔的 check_*，畫面只印沒過的項目與總數，有失敗就以 1 結束
# 每一項的結果、單項量到的數字（CheckKit._note）、手感量測都寫進 tests/check_last.log（不進版控）
# 平常用 `node tools/release.mjs --check` 跑（含匯入與逾時）；直接跑：在 godot/ 內 <Godot console 執行檔> --headless --path . -s res://tests/check.gd
# 檢查本體在 core / player / combat / boss / map / loot / view / monster / event / net_checks.gd，共用工具在 check_kit.gd
# 數值都從資料表（Config、defs/）讀：調數值不用改檢查，只有機制改了才要改
extends SceneTree

const LOG_PATH := "res://tests/check_last.log"

var _passed := 0
var _failed := 0
var _errors := _ErrorCounter.new()
var _log: FileAccess


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
	# 核心規範與基礎系統
	_check("編譯：專案內所有 .gd（含畫面層、main）都能編譯", CoreChecks.check_all_scripts_compile)
	_check("模擬層：sim/ 沒有使用禁止的 API（Input、節點、全域隨機、時間、讀檔、畫面層）", CoreChecks.check_sim_forbidden)
	_check("版號：version.gd 與 CHANGELOG 最新的已發布版本一致；[未發布] 只能在最上面", CoreChecks.check_versions)
	_check("CD：計時、進度、到期、長度 0 視為立即可用", CoreChecks.check_cooldowns)
	_check("狀態機：enter/exit 順序、can_exit 否決、time 累計、data 複製", CoreChecks.check_state_machine)
	_check("InputCmd：按鈕位元不重疊、陣列序列化來回一致", CoreChecks.check_input_cmd)
	_check("碰撞分離：重疊實體依質量比例推開到剛好接觸；固定不動的不被推", CoreChecks.check_separation)
	_check("碰撞分離：格子切分與兩兩比對結果一致（80 個實體）", CoreChecks.check_grid_matches_brute_force)
	_check("命中停頓：期間時間縮放變慢，到期恢復 1", CoreChecks.check_hit_stop)
	_check("事件：開場、戰鬥、死亡的事件 payload 只含可序列化的值（沒有物件參照）", CoreChecks.check_events_serializable)
	_check("決定性：有敵人與波次時，同種子、同輸入的兩個 World 結果相同（實體位置、朝向、亂數狀態）", CoreChecks.check_determinism_with_enemies)
	_check("記憶體：reset 與移除實體後，舊實體會被釋放（切斷與 World 的循環參照）", CoreChecks.check_entity_release)
	_check("記憶體：敵人移除後 CD 清除、實體會被釋放", CoreChecks.check_enemy_release)
	_check("屬性計算：同類百分比相加、暫時效果與冷卻縮減相乘、取整、上下限、來源可移除、顯示格式", CoreChecks.check_stats_formula)
	_check("護甲與爆擊：護甲 100 減傷 50%、護甲 8 減傷 7.4%；爆擊率 100% 時乘爆擊傷害，爆擊率 0% 不消耗亂數", CoreChecks.check_stats_armor_crit)
	_check("傷害保留小數（v0.41.0）：12.5 實際扣 12.5、兩下 25；傷害數字四捨五入（12.5 → 13、0.4 至少顯示 1）、血量無條件進位（87.5 → 88、剩 0.4 顯示 1）", CoreChecks.check_fractional_damage)
	_check("屬性接上遊戲：攻速 ×2 普攻時間減半、冷卻 ×0.5、最大生命增加時目前生命同步增加、每秒回血、除錯移速加成", CoreChecks.check_stats_hooks)
	# 玩家操作
	_check("玩家移動：1 秒移動 move_speed 單位；斜向輸入長度被限制為 1（權威端不信任輸入）", PlayerChecks.check_player_move)
	_check("玩家轉向：面朝瞄準點（facing = atan2(dx, dz)）", PlayerChecks.check_facing)
	_check("場地邊界：玩家停在 arena_half_size - radius", PlayerChecks.check_arena_clamp)
	_check("劍盾普攻：三段時間合計 windup + active + recovery，期間移速照 move_speed_mul、收招後回到 ready", PlayerChecks.check_attack_timing)
	_check("劍盾連段：前兩段照基礎傷害、第三段乘 finisher_mul 且後搖乘 finisher_recovery_mul、重擊與音效只有第三段、同一目標每次出手只中一次", PlayerChecks.check_combo)
	_check("格擋與招架（v0.41.0）：按住右鍵才格擋、放開就放下、沒有冷卻與時間上限、可移動轉向、翻滾提前放下；格擋中按左鍵招架（冷卻、冷卻中發 skill:onCooldown、按住不連發），判定內擋下 = 全額盾反且繼續格擋，沒擋到 = 盾擊 12.5；正面擋得下揮砍與箭（block_arc 邊界內外）、背後擋不住；盾反範圍 parry.range / arc；Boss 衝鋒擋得住但全額推退、只判定一次；Boss 砸地擋不住", PlayerChecks.check_block)
	_check("受擊：扣血後進入 stagger（移速照 stagger_move_speed_mul、持續 stagger_time）、無敵 invuln_time、畫面震動", PlayerChecks.check_stagger)
	_check("輸入緩衝：攻擊中按右鍵會在後搖取消並接特殊技；緩衝過期後不會被消化", PlayerChecks.check_buffer)
	_check("死亡：發出 player:died、移動層進入 dead、不再接受輸入", PlayerChecks.check_player_death)
	_check("治療藥水：次數、回血量不超過上限、滿血不能用、冷卻間隔、用完不能再用", PlayerChecks.check_heal_slot)
	_check("疾跑：移速乘 speed_mul、持續 duration 後恢復、冷卻 cooldown；使用道具動作 use_item_time", PlayerChecks.check_sprint_slot)
	_check("數字鍵緩衝：攻擊中按 1 會在後搖取消並使用道具；空欄位不提示", PlayerChecks.check_slot_buffer)
	_check("翻滾：duration 秒翻 distance 單位；移速 +50% 時同樣時間翻 1.5 倍遠；冷卻吃 roll_cooldown 屬性；次數 +1 可連翻兩次", PlayerChecks.check_roll_motion)
	_check("翻滾無敵：開始後 invuln_time 內打不到、投射物穿過，之後會被打中", PlayerChecks.check_roll_invuln)
	_check("翻滾取消：普攻前搖與後搖可取消；揮下去、特殊技（奧術爆裂）、硬直中先緩衝，結束後才翻", PlayerChecks.check_roll_cancel)
	_check("跳躍：空中時間一半時到最高 JUMP.height、air_time 落地；空中不能再跳；攻擊中可以跳、硬直中不行；空中翻滾照常下墜且一樣遠", PlayerChecks.check_jump_motion)
	_check("二段跳：沒有道具時空中跳不了；放進雙躍之靴後空中可再跳一次、第三次跳不了；落地後重置", PlayerChecks.check_double_jump)
	_check("動作手感：擊退總位移符合阻尼公式（每步先移動再衰減）、轉身 180° 的步數符合 turn_speed、普攻與第三段前衝距離、連段窗口內接下一段、超過就重來", PlayerChecks.check_motion_feel)
	# 武器與小怪戰鬥
	_check("武器資料：behavior 存在、三段時間為正數、音效名稱都在 Sound.CUE_NAMES", CombatChecks.check_weapon_defs)
	_check("法杖魔彈：前方 spawn_offset 產生、照 projectile_speed 飛、命中造成武器傷害、飛滿射程後消失", CombatChecks.check_fire_bolt)
	_check("奧術爆裂：落點限制在 min_range ~ range、爆炸半徑內造成傷害、範圍外不受傷", CombatChecks.check_arcane_burst)
	_check("法杖普攻：按住時照三段時間連發、打中骷髏不擊退也不硬直", CombatChecks.check_staff_changes)
	_check("武器基礎數值：面板攻擊力 / 攻速 / 範圍 = 武器資料 × 稀有度倍率；裝上綠劍盾後攻擊力與揮砍距離跟著倍率", CombatChecks.check_weapon_base_stats)
	_check("高度判定：最高點時箭從腳下飛過、地面會中箭；跳起來躲過 Boss 砸地；空中揮砍與空中魔彈打得到地上的怪", CombatChecks.check_height_hits)
	_check("打擊感：玩家打中不震動、模擬時間不放慢（hit_stop 只放進事件）；玩家被打與 Boss 砸地照常震動；沒有命中定格，打中後模型照常移動", CombatChecks.check_hit_feel)
	_check("沒有碰撞傷害：骷髏戰士（揮砍冷卻中）、弓手（不射箭時）、Boss（不出招時）貼身 2 秒都不扣血", CombatChecks.check_no_contact_damage)
	_check("骷髏揮砍：舉刀 windup 秒後才命中；扇形角度與距離的邊界（加目標半徑）；舉刀後半鎖定方向，繞到側面就躲開；舉刀中被打會中斷", CombatChecks.check_grunt_swing)
	_check("近戰小怪：爬出 spawn_time 後追擊、揮砍傷害照資料、間隔 ≥ 冷卻；受擊硬直 hurt_time", CombatChecks.check_melee_enemy)
	_check("遠程小怪：瞄準 aim_time 後射箭、箭傷害照資料、保持在 preferred_range 附近", CombatChecks.check_ranged_enemy)
	_check("敵人移速與箭：小怪移速 = 基礎 × 波次成長 × 隨機 ±變異、Boss 固定；弓手的箭速與射程照資料", CombatChecks.check_enemy_speed)
	_check("投射物不穿牆：魔彈對牆射會在牆前消失；從高台往下射照樣打得到地上的怪", CombatChecks.check_projectile_walls)
	# Boss 招式
	_check("瞬移砸地躲得掉（v0.42.0，每圈間隔 0.5 秒）：站著不動被第 1 圈打一次；看到預警反應 0.3 秒往外直跑三圈都打不到；砸地圈依序閃亮（等待 0.3、打到 0.85 後淡掉）", BossChecks.check_teleport_slam_dodge.bind(CheckKit._feel_lines))
	_check("Boss 砸地：近身時前搖後打中、擊飛 + 緩速、CD；紅圈一圈圈往外（外圈晚 ring_delay）、每人只被打一次；霸體不硬直、擊退乘 knockback_mul", BossChecks.check_boss_slam)
	_check("Boss 衝鋒：蓄力 windup、照 speed 衝刺、命中傷害並讓玩家暈眩 stun、撞牆自己暈眩 wall_stun", BossChecks.check_boss_charge)
	_check("Boss 直劈：沒有地面預警；舉劍 windup 秒後劈下；追蹤只做一半，繞圈走位躲得開", BossChecks.check_boss_cleave)
	_check("Boss 狂暴招式：衝鋒連 charge_count 次；召喚的骷髏戰士衝撞一次；砸地不管多遠都放（玩家腳下預警 → 瞬移 → 砸）", BossChecks.check_boss_enraged_moves)
	_check("Boss 召喚與狂暴：血量低於召喚門檻召喚 count 隻（骷髏戰士 / 弓手隨機）、低於狂暴門檻狂暴（移速、CD、前搖倍率）", BossChecks.check_boss_summon_enrage)
	_check("Boss 跳上高台、衝鋒跳上去、砸地打得到高台：Boss 從地面跳上 1.0 石座；衝鋒途中遇到 1.0 石台直接跳上去不暈眩、遇到牆照樣暈眩；砸地打得到站在旁邊 1.0 石台上的玩家，跳起來躲得過", BossChecks.check_boss_high_ground)
	# 地圖、尋路與生成
	_check("波次資料：只有最後一波是 Boss、其他波都有小怪、敵人類型存在、成長倍率線性", MapChecks.check_wave_defs)
	_check("生成：first_delay 後開第一波、第一波數量照資料、離玩家 min_distance 以上、第 3 波小怪套成長倍率", MapChecks.check_spawning)
	_check("一局流程：每波依序開始、打倒 Boss 後 is_over、victory_delay 秒後 game:victory、擊殺數正確", MapChecks.check_full_run)
	_check("地形：0.5 石台走不上去、跳得上去；從 0.5 跳上 1.0；走出邊緣會掉回地面；2.5 的牆跳不過去", MapChecks.check_terrain)
	_check("地圖 A（環形墓園）：大小與邊界一致、石台都在場地內、出生點與挖墳點可走且相連、所有可走的格子連成一片（沒有怪物到不了的地方）、相鄰可走格高低差 ≤ climb_height、牆比最高的地面高出跳躍高度以上", MapChecks.check_map_a)
	_check("尋路不擦牆：直線離牆小於 margin 就不算看得到；繞北門時被牆擋住而變慢的步數 < 30", MapChecks.check_nav_clearance)
	_check("怪物繞牆：玩家在王族墓圍牆內，骷髏戰士從南邊牆外繞到北門進來打到玩家；弓手繞進來射中玩家", MapChecks.check_enemy_pathing)
	_check("起跳偵測的快速排除（Terrain.may_rise）：兩張地圖密集取點、各種腳下高度，ground_at 會起跳的地方都沒被排除", MapChecks.check_may_rise)
	_check("怪物跳上高台：玩家站在 1.0 石台上，骷髏戰士先蹲 jump_windup 再跳，經 0.5 跳上 1.0 並打到玩家；Boss 也跳得上去", MapChecks.check_enemy_climb)
	_check("弓手打得到高台：玩家站在 1.0 石台上會中箭；被牆擋住時弓手先移動、不對牆射", MapChecks.check_archer_high_ground)
	_check("遠的小怪降低重新判斷路線的頻率：離目標超過 far_distance 時至少間隔 repath_interval_far 秒，走進來的那一步立刻判斷，弓手進射程後照常瞄準", MapChecks.check_far_repath)
	_check("地圖 A 生成（由挖墳事件生）：小怪都生在離玩家 min ~ max_distance、可走而且走得到玩家的地方", MapChecks.check_map_spawns)
	# 背包、寶箱、道具與武器
	_check("背包：大小照 BAG_SIZE；形狀旋轉 90° 後格子正確；超出邊界、重疊放不下；自動找第一個空位（不夠時會轉向）；搬動成功 / 失敗；裝滿後撿不起來並發出 inventory:full", LootChecks.check_inventory)
	_check("靈魂與祭壇 / 石棺：寶箱數量照地圖資料、位置可走且離出生點 / 挖墳點 / 邊緣夠遠；殺怪靈魂照 KILL_SOULS（共用）；靈魂不夠開不了（chest:denied）、夠了扣靈魂並在寶箱旁掉一個道具；開過不能再開", LootChecks.check_soul_chests)
	_check("寶箱隨機放與靈魂平衡（v0.44.0）：同種子位置相同、不同種子不同、寶箱間距；2 / 4 人寶箱與殺怪靈魂 ×1.5 / ×2.5；召喚詞條與 Boss 召喚的怪不給靈魂；開場怪群全清（10 個種子）買不完全部寶箱", LootChecks.check_chest_balance)
	_check("局外金幣（v0.45）：過第 1 / 2 層給 5 / 10（floor_clear_per_floor × 層數）；地上的金幣走近自動撿、倒地不撿、多人只記一個數字；Profile 存檔讀得回來、save_path 空的不寫檔", LootChecks.check_run_coins)
	_check("掉金幣（v0.45）：小怪死 40000 次、Boss 3000 次的掉落率符合 RUN_COINS.drop_chance（±4 個標準差）；召喚出來的不掉", LootChecks.check_coin_drops)
	_check("寶箱稀有度：各抽 20000 次，比例符合權重（誤差 ±1.5%），不會開出武器", LootChecks.check_chest_rarity)
	_check("撿道具：按 F 撿起最近的道具放進背包並生效；剛按下那一步才算（按住不會連撿）；兩人同一步按 F 只有一人拿到；丟掉後道具回到地上、效果移除；附近有倒地隊友時 F 先救人", LootChecks.check_pickups)
	_check("武器掉落：小怪死 5000 次的掉落率符合 DROP_CHANCE（±0.9%）、Boss 必掉；稀有度各抽 20000 次符合權重（±1.5%）", LootChecks.check_weapon_drops)
	_check("武器詞條：詞條數 = 稀有度順位、不重複；只有手上那把生效，X 切換後屬性跟著換；另一格空的不能切", LootChecks.check_weapon_affixes)
	_check("撿武器：裝備欄有空先放裝備欄（不換手上的），滿了放背包（背包裡沒效果），都滿了撿不起來；裝備欄 ↔ 背包搬動、手上至少留一把", LootChecks.check_weapon_pickup)
	_check("武器合成：兩把同種同稀有度拖在一起 → 高一級、詞條重抽、放在被拖上去的位置；不同種 / 不同稀有度 / 橘色不能合成；合成手上那把屬性立刻更新", LootChecks.check_weapon_merge)
	_check("物品資料：每個稀有度都有道具，名稱不重複、欄位完整、形狀合法（相連、不重複、放得進背包）、格數 = ceil(強度 ÷ 稀有度效率)、效果都對應到存在的屬性 / 條件 / 觸發 / 能力", LootChecks.check_item_defs)
	_check("道具放進身上：屬性效果照道具資料生效（百分比同類相加）、最大生命與目前生命一起加、翻滾次數 +1、移除與清空後回到原值、武器道具直接換武器、發出 item:added", LootChecks.check_items_apply)
	_check("道具效果的類別：ItemDefs 標成已接上的條件與觸發，和 ItemEffects 的條件 / 動作類別一一對應", LootChecks.check_item_effect_registry)
	_check("道具條件：對滿血敵人加傷、低於門檻生命加傷（拿掉道具就沒了）、擊殺後一段時間加攻速、擊殺回復最大生命的比例", LootChecks.check_item_conditions)
	_check("道具觸發：疊到 100% 時擊殺爆炸、連鎖閃電（每跳在 jump_range 內、不重複、不連鎖觸發）、中毒（duration 內共 total_ratio）、冰凍不能動（Boss 不會）；機率相加", LootChecks.check_item_procs)
	_check("道具掉落：寶箱只開出效果都接上的道具；沒有的稀有度往下一級找", LootChecks.check_item_drop_pool)
	# 畫面、介面與音效
	_check("角色視野：前方扇形（angle 邊界內外）與 range 內看得到、身邊 near_radius 背後也看得到；牆擋視線（身邊也擋）、高台不擋；自己的投射物在背後也看得到、怪物的看不到；寶箱看中心、怪物看身體邊緣", ViewChecks.check_vision_rules)
	_check("視野畫面：背後的骷髏模型隱藏、前方的顯示；背後的特效事件不畫、前方的照畫；轉身時離開視野的 fade_out 秒淡出、進入的 fade_in 秒淡入（材質半透明，完成後還原）；本機角色陣亡後立刻全部看得到；變暗遮罩最先畫", ViewChecks.check_vision_view)
	_check("頭頂血條：滿血不畫、受傷畫；自己與隊友綠、怪物紅；背後視野外、Boss、倒地、WorldView 隱藏的不畫；比例 = hp / max_hp；不疊到詞條與名牌", ViewChecks.check_health_bars)
	_check("開場預熱：每一種怪、魔法 / 稀有怪、玩家、兩種寶箱（祭壇 / 石棺）、金幣、道具、武器、兩種投射物、每種稀有度的武器（各再一個淡入淡出中的半透明版本，每一階的材質都先建好）都在鏡頭附近畫幾幀後移除；前一半的幀點光源全關、後一半全開，視野遮罩也畫；預熱文字含道具名稱、怪物詞條、稀有怪名字與介面字串的每個字", ViewChecks.check_warm_up)
	_check("牆後剪影：角色材質寫模板值；玩家一直有剪影；怪物只有和相機之間有牆擋住時才有，離開牆邊就拿掉", ViewChecks.check_xray)
	_check("新手提示：換武器鍵是 X；開場跳操作與挖墳；撿到東西、開背包、可合成、出口打開、隊友倒地各跳一次；看過不再跳、排隊中條件不成立就跳過；重設後再跳", ViewChecks.check_hints)
	_check("挖墳進度條：事件進行中所有人上方中央都看得到進度與說明（Boss 活著 / 怪潮中），出口打開後收起；Boss 血條排在它下面、寬度塞得進 1920", ViewChecks.check_dig_bar)
	_check("寶箱模型：已開過的寶箱重新建立模型時（連線離開視野再回來）箱蓋直接打開、不重播開蓋；沒開過的關著", ViewChecks.check_chest_lid)
	_check("HUD：能建立、處理各種事件、顯示波次 / 血量 / 結算文字、暫停畫面有「離開遊戲」；別人撿到道具不跳橫幅；武器欄的另一把標示切換鍵 X", ViewChecks.check_hud)
	_check("技能欄招架（v0.41.0）：劍盾格擋中左鍵那格換成「招架」並顯示招架冷卻、放下盾換回普攻；法杖沒有招架格", ViewChecks.check_skill_bar_parry)
	_check("主選單：首頁有單人 / 多人 / 離開遊戲（網頁版不顯示離開）、桌面版先選房號 / IP 連線（v0.40.0）、多人頁放連線面板與返回、按鈕發訊號、塞得進 1920×1080；關掉後單機暫停不顯示連線面板、連線中才顯示；暫停畫面有「回主選單」", ViewChecks.check_main_menu)
	_check("網頁版網址參數：?horde=200&perf&seconds=20 轉成 --horde=200 --perf --seconds=20；不在開放清單的參數（例如 host、join）不轉", ViewChecks.check_url_query_args)
	_check("遊玩紀錄：自己的擊殺依種類、受到的傷害依攻擊者、被看不見的攻擊（背後）、倒下被誰打倒；結算畫面顯示且塞得進 1920×1080；「複製遊玩紀錄」拿到版本、結果、配裝、擊殺、效能（單機沒有連線那行）；重新開始清空", ViewChecks.check_run_log)
	_check("特效事件：模擬層發出的每個 fx:* 都有畫面處理、也列在 PROJECT_GUIDELINES 第 9 節；揮砍 / 魔彈 / 奧術 / Boss 砸地的事件餵給 Effects 會產生粒子與弧光環", ViewChecks.check_effects_events)
	_check("特效上限與幀率：粒子與弧光環有上限；投射物拖尾 30 FPS 與 144 FPS 下每秒產生的粒子數相同（每步 1 顆）；暫停時不產生", ViewChecks.check_effects_limits)
	_check("受擊閃白：只改自發光顏色、不切換 emission_enabled（切換會在第一次命中即時編譯著色器而卡頓）", ViewChecks.check_flash_no_shader_switch)
	_check("字型：介面文字都在打包的 Noto Sans TC 裡（網頁版沒有系統字型），缺字的圖示改用向量圖", ViewChecks.check_font_coverage)
	_check("零件合併：依 anchor + 材質合併、外框不變、keep 的零件留在原位、空群組移除、面法線朝外且為正面", ViewChecks.check_merge_static)
	_check("零件數：騎士 ≤ 20、骷髏戰士 ≤ 16、骷髏弓手 ≤ 16、Boss ≤ 22、場地 ≤ 12（避免卡頓）", ViewChecks.check_mesh_counts)
	_check("音效名稱：模擬層 sfx:cue 的名稱都在 Sound.CUE_NAMES", ViewChecks.check_sim_cues)
	_check("音效檔：Sound.CUE_NAMES 每個名稱都有配方與 audio/sfx/*.wav，檔案不是空的、峰值 ≤ 1", ViewChecks.check_sfx_files)
	_check("背景音樂：一般 / Boss 兩首匯入後為往前循環，長度 15.00 / 10.43 秒（64 / 92 BPM × 4 小節）", ViewChecks.check_music_files)
	_check("音效對應：事件 → 音效（受傷 / 爆擊 / Boss 死亡 / 道具…），Boss 波換 Boss 曲、死亡停音樂", ViewChecks.check_sound_mapping)
	_check("音效距離衰減（v0.44.0）：15 內全音量、35 外不播、中間 (1 − t)²；模擬層 sfx:cue 都帶位置；遠處隊友揮劍聽不到、身邊聽得到；法杖普攻 −8 dB", ViewChecks.check_sound_distance)
	# 怪物稀有度與挖墳事件
	_check("怪物種類只看資料表：每種怪的 behavior 都對應得到行為類別、建出來的類別一致；is_boss、freeze_immune 照資料；挖墳事件的 boss_type 是 Boss", MonsterChecks.check_enemy_defs)
	_check("怪物稀有度（D5）：稀有骷髏生命 180、攻擊力 ×1.5、體型 ×1.2；魔法 72、×1.2；詞條魔法 1~2 / 稀有 3 條不重複、稀有怪有名字；每群魔法 1~2 隻、稀有 25%（±1.5%）", MonsterChecks.check_rarity)
	_check("怪物詞條（D5）：迅捷移速 ×1.3、強壯 ×1.3、厚皮 20 → 15、再生每秒 0.72、吸血揮砍 12 回 2.4、狂暴 <30% 移速與狀態機 ×1.4、死亡爆炸 0.8 秒後 2.2 內 20 傷害、召喚 8 秒 2 隻最多 6 隻", MonsterChecks.check_affixes)
	_check("怪群（D5）：地圖 A 散放 12~20 群、每群 6~15 隻、離出生點 15 以上、群距 10 以上、都走得到；開場休眠不播音效、不動；玩家走到 12 以內整群醒來、被打一隻整群醒來；同種子結果相同", MonsterChecks.check_packs)
	_check("蒙皮小怪（D5 效能）：骷髏戰士 / 弓手合成一個蒙皮網格（≤ 2 個網格、頂點數與原本零件相同），關節姿勢寫進骨架", MonsterChecks.check_skinned_rig)
	_check("挖墳（D6）：挖墳點 2.2 內按住 F 開始事件並挖墳；挖墳中不能移動、跳，照樣跟著滑鼠轉向，被打不中斷也不會被擊退；60 秒挖完（30 秒 50%）、放手每秒掉 DIG.decay、兩人一起挖速度相加；挖完出口打開、不能再挖", EventChecks.check_dig)
	_check("事件難度（D6）：難度 60 怪物生命 ×1.3；生怪間隔 5 → 1 秒、每批 2 隻起（難度 100 單人 4、雙人 6）；魔法 / 稀有機率隨難度（±1.5%）；Boss 在挖墳點旁邊；Boss 活著時不冒怪、難度不漲，倒下後發 event:horde、interval_start 秒後冒第一批、難度每秒 +1；休眠的怪群不擋事件生怪", EventChecks.check_difficulty)
	_check("出口與換層（D6）：活著的人都走進出口才換層（有人倒地不換）；先到的消失、不能被打；新的一層回出生點、基礎難度 +10、保留靈魂與背包、地上與怪物清空、寶箱重放、事件歸零；第 2 層怪物生命 ×1.05", EventChecks.check_next_floor)
	_check("Boss 獎勵（D6）：挖墳地圖打倒 Boss 不通關，掉 1 把武器、1 個大寶箱機率的道具、KILL_SOULS 的 Boss 靈魂（30）", EventChecks.check_boss_reward)
	_check("屍體與冤魂（D6）：多人時死亡留下屍體，撿進背包占 6 格；背著換層出現冤魂（離出生點 10~14），打倒後死者在那裡復活 30% 血、屍體消失；沒人帶屍體就沒有冤魂", EventChecks.check_corpse_ghost)
	# 連線
	_check("連線武器（D4）：客戶端按 X 切換、拖曳合成，房主與客戶端的裝備欄、手上武器、詞條一致；殺怪掉的武器兩邊都看得到", NetChecks.check_net_weapons)
	_check("連線稀有度（D5）：客戶端的稀有度、詞條、名字、半徑、最大生命與房主相同；普通怪的快照不帶稀有度欄位", MonsterChecks.check_net_rarity)
	_check("連線挖墳（D6）：層數、事件狀態、進度、難度、怪潮開始了沒、走進出口、屍體的主人與挖墳點在客戶端相同", EventChecks.check_net_event)
	_check("誤傷（C2）：玩家揮劍打得到前方的隊友（12 傷害）、打不到自己；魔彈打得到隊友、不打發射者；單機目標不含自己", NetChecks.check_friendly_fire)
	_check("人數調整（C3 決定）：敵人數量不變、血量每多 1 人 +50%（1 / 2 / 4 人 ×1 / ×1.5 / ×2.5，Boss 也是）", NetChecks.check_player_count_scaling)
	_check("倒下（C4）：多人時生命歸零先倒地假死（不能動、不被打、不被追），10 秒沒人救才死亡；最後一人倒下全員死亡並 game:defeat；單機倒下直接死亡", NetChecks.check_downed)
	_check("救援（C4）：範圍內按住 F 累積 5 秒救起、期間不能移動 / 攻擊 / 跳但照樣跟著滑鼠轉向、倒數暫停；放開時進度每秒 −1、倒數照走；救起後 30% 血；範圍外不能救", NetChecks.check_revive)
	_check("快照（C1）：房主的實體經過序列化後，客戶端建立同樣類別、位置、血量、武器的鏡像；動畫狀態相同時數值補間", NetChecks.check_codec)
	_check("網頁連線配對（v0.36.0）：PeerJS 配對伺服器網址、房主 ID、房號（4 碼、不含 0 / O / 1 / I）、OFFER / ANSWER / CANDIDATE 訊息格式、伺服器訊息對應的訊號；桌面版 IP 與房號兩種都能用", NetChecks.check_web_signaling)
	_check("桌面版 WebRTC（v0.40.0，webrtc-native）：同一程序兩條連線直接交換 SDP，照 NetSession 的設定建房主 / 客戶端，5 秒內連上且封包收得到", NetChecks.check_desktop_webrtc.bind(CheckKit._feel_lines))
	_check("快照大小（v0.35.0）：地圖 A 怪群 + 4 人分散、P2 被 30 隻圍住，每份快照 ≤ 4 KB（網頁 WebRTC 單則約 16 KB）", NetChecks.check_snapshot_size.bind(CheckKit._feel_lines))
	_check("戰鬥同步（C2）：延遲 3 步、30 秒對打，客戶端套用的每筆快照擊殺 / 波次 / 敵人血量都和房主當時一致，事件順序一致", NetChecks.check_sync.bind(CheckKit._feel_lines))
	_check("遊玩紀錄的連線數據：延遲 100 ms 時客戶端回應時間在「來回 + 快照間隔」內、快照最長間隔約 snapshot_interval 步、房主收隊友輸入最長間隔約 1 步", NetChecks.check_net_stats.bind(CheckKit._feel_lines))
	_check("延遲下的手感（C3）：延遲 100 ms + 掉包 10%，按下就在本機移動、修正誤差 < 0.25、停下後與房主差 < 0.01；別人的角色每步位移平順（±0.02）", NetChecks.check_prediction.bind(CheckKit._feel_lines))
	_check("打中回饋與延遲補償（v0.38.0）：延遲 100 ms 時客戶端的火花 / 音效 / 閃白和單機一樣在出招當下出現一次，房主的同一下標 predicted；側移的怪客戶端看到打中，房主也判定打中", NetChecks.check_hit_prediction.bind(CheckKit._feel_lines))
	_check("連線寶箱與背包（D3）：客戶端按 F 開箱（房主扣靈魂 30 → 5、道具掉地上）、再按 F 撿起，拖曳搬動與丟掉；兩邊的寶箱、靈魂、背包、生效道具一致", NetChecks.check_net_loot)
	_check("連線金幣（v0.45）：房主掉的金幣客戶端看得到；客戶端走過去撿起，兩邊本局金幣都是 1、地上都沒了，客戶端收到 coins:gained", NetChecks.check_net_coins)
	_check("連線倒下與救援（C4）：客戶端跟著房主倒地、不能預測移動，被救起後站起來 30 血；客戶端按住 F 也能救起房主", NetChecks.check_net_downed)
	_check("兩個程序連線（C1）：headless 照玩家順序（主選單多人頁開房 / 加入，v0.39.0）連線（ENet），兩邊都沒停在暫停、收得到輸入、特效在走、自己的角色各移動約 13 單位，停下後兩邊的玩家位置一致（< 0.01）", NetChecks.check_two_processes.bind(CheckKit._feel_lines))
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
	var errors_before := _errors.count
	var result: Variant = fn.call()
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
