# 全域可調參數：迴圈、世界、相機、玩家、戰鬥（數值照搬網頁版 legacy/src/core/config.js）
class_name Config

const FIXED_DT := 1.0 / 60.0
const MAX_STEPS_PER_FRAME := 5
const HIT_STOP_TIME_SCALE := 0.05

const WORLD := {
	"arena_half_size": 16.0,
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
	"boss_distance": 8.0,         # Boss 出現在玩家對面、離中央這麼遠
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
	"stagger_time": 0.15,
	"stagger_move_speed_mul": 0.4,
	"action_buffer_time": 0.25,
	"start_weapon": &"swordShield",
	"slots": [&"heal", &"sprint", null, null, null],
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

# 除錯鍵（Godot 版才有，網頁版沒有）
const DEBUG := {
	"speed_bonus": 0.5,      # F3：玩家移速 +50%（驗證屬性系統用）
}
