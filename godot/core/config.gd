# 全域可調參數：迴圈、世界、相機、玩家、戰鬥（數值照搬網頁版 legacy/src/core/config.js）
class_name Config

const FIXED_DT := 1.0 / 60.0
const MAX_STEPS_PER_FRAME := 5
const HIT_STOP_TIME_SCALE := 0.05

const WORLD := {
	"arena_half_size": 16.0,        # 測試場地（MapDefs 的 test_arena）的一半邊長；正式地圖的大小在 defs/map_defs.gd
	"default_map": &"graveyard_a",  # 遊戲用的地圖（D1）；check.gd 大部分檢查用 test_arena
	"physics_cell": 2.0,          # 碰撞分離的格子邊長（≥ 任兩個實體半徑相加的最大值：Boss 1.0 + 1.0）
	"victory_delay": 2.2,         # 打倒 Boss 後幾秒發出 game:victory
	"victory_hit_stop": 0.25,
	"victory_shake": 0.8,
	"victory_shake_duration": 0.6,
}

const SPAWNER := {
	"first_delay": 1.0,
	"wave_delay": 2.5,
	"spawn_interval": 0.35,
	"first_spawn_delay": 0.6,     # 一波開始到第一隻出現的秒數
	"boss_first_spawn_delay": 1.2,
	"min_distance_from_player": 8.0,
	"edge_margin": 2.0,           # 生成點離場地邊緣至少這麼遠
	"spawn_attempts": 20,
	"boss_distance": 8.0,         # Boss 出現在玩家對面、離中央這麼遠（大地圖：往地圖中央方向、離玩家這麼遠）
	"max_distance_from_player": 18.0,   # 大地圖（spawn_rule = around_player）：生在離玩家 min ~ max 的一圈內、走得到的地方
}

const CAMERA := {
	"view_half_height": 10.0,   # 正交相機可視範圍的一半高度（世界單位）
	"distance": 40.0,
	"azimuth": PI / 4.0,        # 從 +X+Z 方向看向場地
	"elevation": 0.7,           # 約 40°，比標準等距角略高，戰鬥較好讀
	"follow_sharpness": 8.0,
	"aim_plane_height": 0.9,    # 滑鼠瞄準射線投射的平面高度（約胸口）
}

const COMBAT := {
	"knockback_damping": 9.0,
	"flash_time": 0.12,
	"hit_shake_duration": 0.15,         # 命中震動秒數（網頁版 Combat.applyDamage）
	"explosion_shake_duration": 0.3,    # 爆炸震動秒數（網頁版 Projectile.#explode）
	"projectile_height": 1.25,          # 網頁版的投射物飛行高度（保留給網頁版比對；Godot 用 HEIGHT.bolt_altitude）
}

const PLAYER := {
	"max_hp": 100.0,
	"move_speed": 6.5,
	"turn_speed": 25.0,
	"radius": 0.45,
	"mass": 2.0,
	"invuln_time": 0.6,
	"regen_delay": 5.0,                 # 受傷後幾秒內生命回復暫停（職業、道具、詞條的回復都算）
	"stagger_time": 0.15,
	"stagger_move_speed_mul": 0.4,
	"action_buffer_time": 0.25,
	"start_weapon": &"longsword",
	"start_offhand": &"woodShield",   # 沒選職業時的起始副手（測試與自動驗證）
	"run_speed_mul": 1.4,               # Ctrl 切換跑步的移速倍率（2026-10-27 使用者，取代疾跑）
	"use_item_time": 0.18,              # 使用道具的動作秒數
	"hurt_shake": 0.25,                 # 受傷時畫面震動強度與秒數
	"hurt_shake_duration": 0.2,
}

# 暗黑幻想的環境色（照搬 darkFantasy.js 的 environment；里程碑 5 移到 view/styles/）
const ENVIRONMENT := {
	"background": Color("0e1220"),
	"hemi_sky": Color("8a9aba"),
	"hemi_ground": Color("2a2420"),
	"sun_color": Color("b8ceff"),
}

# 音量（0~1，照網頁版 AUDIO）：實際音量 = master × 分類音量
const AUDIO := {
	"master": 0.7,
	"sfx": 0.8,
	"music": 0.5,
	"baked_gain": 1.0,       # tools/bake_*.gd 寫入 WAV 時乘上的倍數（防止峰值超過 1）；播放時再除回來
	"music_fade": 1.0,       # 換曲、死亡、勝利時音樂淡出的秒數
	# 距離衰減（v0.44.0 使用者要求：看不到的隊友打怪不該聽得清楚）：離本機角色 hear_full 內全音量（約畫面範圍），
	# 到 hear_max 之間音量 (1 − t)² 遞減（20 單位約 −5 dB、25 約 −12 dB、30 約 −24 dB），hear_max 以外不播
	"hear_full": 15.0,
	"hear_max": 35.0,
}

# 翻滾（Godot 版新增，使用者 2026-10-22 決定）：速度與距離隨移速屬性等比放大（÷ PLAYER.move_speed），時間與無敵不變
const ROLL := {
	"duration": 0.35,        # 翻滾秒數
	"distance": 4.0,         # 基礎移速 6.5 時的翻滾距離
	"invuln_time": 0.2,      # 開始後的無敵秒數（投射物穿過）
	"cooldown": 1.2,         # 每次充能的回充秒數（乘上 roll_cooldown 屬性）
	"sfx": "sprint",         # 先借用疾跑音效
}

# 跳躍與高度（Godot 版新增，使用者 2026-10-22 決定）：最高 1.5、起跳到落地 0.6 秒、只有一段跳
# 重力 = 8 × 高度 ÷ 時間² ≈ 33.3，起跳速度 = 4 × 高度 ÷ 時間 = 10（所有站在地上的實體共用重力）
const JUMP := {
	"height": 1.5,
	"air_time": 0.6,
}

# 怪物尋路與跳躍（D1，使用者決定：玩家去得了的地方怪物都去得了、沒有安全區，怪物只是比玩家多花一點時間上去）
const NAV := {
	"cell": 1.0,                # 尋路格子邊長
	"margin": 0.6,              # 小怪（半徑 ≤ large_radius）：牆與墓碑往外擴多少算障礙，直線離牆至少這麼遠才直走（半徑 0.45 + 0.15）
	"margin_large": 1.15,       # 大隻（Boss 半徑 1.0）用的另一張格子圖
	"large_radius": 0.6,        # 半徑超過這個就用 margin_large 的格子圖
	"jump_air_speed": 4.0,      # 怪物跳上高台時空中往前的最低速度（Boss 2.2 太慢，落地時身體還在邊緣外會掉回去）
	"repath_interval": 0.25,    # 每隔幾秒重新判斷「直接走過去」或「重找路徑」
	"far_distance": 18.0,       # 離目標超過這麼遠（= 視野範圍 VISION.range，玩家看不到）的小怪降低重新判斷的頻率（效能）
	"repath_interval_far": 1.0, # 遠的小怪每隔幾秒重新判斷；走進 far_distance 內的那一步立刻判斷
	"far_stagger_steps": 8,     # 遠的小怪依 id 錯開 0~7 步，同一步醒來的怪群不會每次都擠在同一步找路
	"waypoint_reach": 0.6,      # 離路徑點這麼近就換下一點
	"smooth_lookahead": 8,      # 拉直路徑時往後看幾個點
	"nearest_search": 6,        # 目標在障礙格上時，往外找幾圈可走格
	"climb_height": 1.1,        # 怪物會跳上去的最大高低差（1.0 高台；1.3 的墓碑太高，站在下面揮砍 / 射擊）
	"jump_windup": 0.25,        # 怪物起跳前蹲的秒數（比玩家多花的那一點時間）
	"jump_lookahead": 0.3,      # 移動方向前方多遠（從身體邊緣算）有高台就起跳
}

# 角色視野（D2，使用者 2026-10-23 決定；sim/vision.gd）：只影響畫面
const VISION := {
	"angle": PI * 120.0 / 180.0,   # 前方合計 120°（朝向 = 角色面對的方向，跟著滑鼠）
	"range": 18.0,                 # 約到畫面邊緣
	"near_radius": 4.0,            # 身邊這麼近不管方向都看得到（背後的箭約提早 0.3 秒、骷髏約 1.5 秒出現）
	"darkness": 0.3,               # 視野外的畫面蓋上多黑（0~1）
	"inner_darkness": 0.1,         # 視野內也稍微壓暗，內外只差 0.2
	"edge": 0.3,                   # 扇形側邊的漸層寬度（世界單位）
	"range_edge": 0.8,             # 扇形遠端弧形的漸層寬度
	"near_edge": 1.0,              # 身邊一圈（背後）的漸層寬度
	"fade_in": 0.2,                # 模型進入視野幾秒淡入、離開幾秒淡出（view/fade.gd）
	"fade_out": 0.2,
}

# 命中的高度判定：每個實體佔 [腳底高度, 腳底 + 身高]，攻擊有自己的高度範圍，兩者重疊才命中
const HEIGHT := {
	"body": {&"player": 2.1, &"grunt": 1.95, &"archer": 1.95, &"boss": 3.885},   # 身高（view/rig.gd 的關節高度 × 縮放）
	"default_body": 2.0,
	"reach_below": 0.3,              # 近戰與碰撞的判定往腳底下延伸多少（空中揮砍打得到地上的怪）
	"projectile_half": 0.15,         # 投射物的上下厚度一半
	"arrow_altitude": 1.17,          # 敵人箭矢離地高度（弓手身高 1.95 × 0.6，同網頁版畫面）
	"bolt_altitude": 1.25,           # 玩家投射物離地高度（同 COMBAT.projectile_height）
	"bolt_settle_distance": 3.0,     # 玩家在空中發射時，飛出幾單位內降到 bolt_altitude
	"explosion_height": 2.5,         # 爆炸範圍從地面往上的高度
	"slam_height": 0.5,              # Boss 砸地只打得到腳底在這個高度以下的目標
	"step": 0.05,                    # 走路可以直接跨上的高度差（超過就是牆）
}

# 打擊感（v0.18.3 使用者決定）
const FEEL := {
	"player_attack_shake": false,   # 玩家方攻擊打中時的畫面震動（網頁版有；被打、Boss 招式的震動不受影響）
	"hit_freeze": false,            # 命中定格：打中時攻擊者與目標的模型停住 hit_stop 秒（v0.18.3 加入，v0.19.1 使用者試玩覺得怪而關掉）
}

# 多人連線（C1~C3，見 docs/系統說明.md §8）
const NET := {
	"port": 24680,
	"max_players": 4,
	"snapshot_interval": 3,          # 房主每幾步送一次快照（3 = 每秒 20 次）
	"interest_radius": 24.0,         # 每位客戶端只收這個距離內的實體（視野 18 + 緩衝 6；玩家與 Boss 一律送，v0.35.0）
	"interp_delay_ticks": 6,         # 其他實體的畫面比最新快照晚幾步（6 = 100 ms），在兩次快照之間補間
	"max_extrapolate_ticks": 6,      # 快照連續掉包、畫面時間追上最新快照時，最多沿速度往前推幾步（不然會停住再跳）
	"rewind_max_ticks": 30,          # 延遲補償最多往回幾步（30 = 0.5 秒：單程延遲約 200 ms 以內完全補償，v0.38.0）
	"predicted_hit_window": 90,      # 客戶端預測打中後，多少步內收到房主的同一下就當成已播過（不再播火花與音效）
	"input_redundancy": 4,           # 客戶端每步送出最近幾筆輸入（防掉包）
	"input_queue_max": 3,            # 房主端某玩家累積的輸入超過這麼多筆就合併兩筆（避免延遲越積越多）
	"snap_distance": 2.5,            # 本機預測與房主位置差超過這麼多就直接跳過去（不平滑）
	"correction_epsilon": 0.001,     # 差距小於這個就不修正
	"friendly_fire": true,           # 誤傷（使用者 2026-10-23 決定）：玩家的攻擊也會打到其他玩家（不會打到自己）
	"enemy_hp_per_extra_player": 0.5,   # 每多 1 位玩家，敵人血量 +50%（2 人 ×1.5、4 人 ×2.5）
	"debug_latency_ms": 0,           # 模擬延遲（單程，毫秒），--net-latency=100 設定
	"debug_loss": 0.0,               # 模擬掉包比例（只對 unreliable），--net-loss=0.1 設定
	# 網頁版連線（v0.36.0）：WebRTC 直連，配對借 PeerJS 的免費公開伺服器（沒有保證，偶爾會掛；掛的時候不能開新房，已連上的不受影響）
	"web_signal_url": "wss://0.peerjs.com:443/peerjs",
	"web_signal_key": "peerjs",
	"web_id_prefix": "cubeborn-mp-",         # 房主在配對伺服器上的 ID = 前綴 + 房號
	"web_room_chars": "ABCDEFGHJKLMNPQRSTUVWXYZ23456789",   # 不含容易看錯的 0 / O、1 / I
	"web_room_length": 4,
	"web_room_retries": 5,                   # 房號撞到別人時重抽幾次
	"web_heartbeat": 5.0,                    # 每幾秒對配對伺服器送一次 HEARTBEAT（不然 ID 會被收回）
	"web_join_timeout": 20.0,                # 加入時幾秒內沒連上就放棄
	# STUN 找自己的公開位址；TURN 是直連打不通時的中繼（PeerJS 預設的公開 TURN，免費共用、沒有保證）
	"ice_servers": [
		{"urls": ["stun:stun.l.google.com:19302"]},
		{"urls": ["turn:eu-0.turn.peerjs.com:3478", "turn:us-0.turn.peerjs.com:3478"], "username": "peerjs", "credential": "peerjsp"},
	],
}

# 倒下與救援（C4，使用者 2026-10-23 決定；decay_rate 是 Claude 暫定）
const REVIVE := {
	"down_time": 10.0,         # 假死秒數：倒數完沒被救起就真的死亡
	"revive_time": 5.0,        # 隊友按住互動鍵累積幾秒救起
	"decay_rate": 1.0,         # 放開後已累積的救援時間每秒減少幾秒（Claude 暫定：和累積同速）
	"range": 1.6,              # 救援者與倒地者中心距離（超過就中斷）
	"revive_hp_ratio": 0.3,    # 救起後的血量（最大生命的比例）
	"revive_invuln": 1.0,      # 救起後的無敵秒數（Claude 暫定，避免一起來就被打倒）
}

# 除錯鍵（Godot 版才有，網頁版沒有）
const DEBUG := {
	"speed_bonus": 0.5,      # F3：玩家移速 +50%（驗證屬性系統用）
}
