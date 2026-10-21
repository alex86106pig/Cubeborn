# 全域可調參數：迴圈、世界、相機、玩家、戰鬥（數值照搬網頁版 src/core/config.js）
class_name Config

const FIXED_DT := 1.0 / 60.0
const MAX_STEPS_PER_FRAME := 5
const HIT_STOP_TIME_SCALE := 0.05

const WORLD := {
	"arena_half_size": 16.0,
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
}

const PLAYER := {
	"max_hp": 100.0,
	"move_speed": 6.5,
	"turn_speed": 25.0,
	"radius": 0.45,
	"mass": 2.0,
	"invuln_time": 0.6,
	"stagger_time": 0.15,
	"action_buffer_time": 0.25,
	"start_weapon": &"swordShield",
}

# 暗黑幻想的環境色（照搬 darkFantasy.js 的 environment；里程碑 5 移到 view/styles/）
const ENVIRONMENT := {
	"background": Color("0e1220"),
	"hemi_sky": Color("8a9aba"),
	"hemi_ground": Color("2a2420"),
	"sun_color": Color("b8ceff"),
}
