# 敵人資料定義（照搬網頁版 src/entities/enemyDefs.js，欄位改 snake_case）；行為在 sim/enemies/
# 網頁版寫死在行為程式裡的數字也搬到這裡（例如接觸判定的寬容距離、Boss 招式的震動與停頓）
class_name EnemyDefs

const ENEMIES := {
	&"grunt": {
		"visual": &"melee",
		"max_hp": 36.0,
		"move_speed": 2.6,
		"speed_variance": 0.2,
		"turn_speed": 6.0,
		"radius": 0.45,
		"mass": 1.0,
		"contact_damage": 10.0,
		"contact_interval": 0.8,
		"contact_knockback": 9.0,
		"contact_reach": 0.15,       # 兩者半徑相加再多這麼遠就算貼到
		"hurt_time": 0.22,
		"spawn_time": 0.7,
		"corpse_time": 1.4,
		"swing_time": 0.3,           # 接觸命中時的揮擊動畫秒數（畫面用）
	},

	&"archer": {
		"visual": &"ranged",
		"max_hp": 26.0,
		"move_speed": 2.3,
		"speed_variance": 0.15,
		"turn_speed": 8.0,
		"radius": 0.42,
		"mass": 1.0,
		"contact_damage": 6.0,
		"contact_interval": 1.0,
		"contact_knockback": 6.0,
		"contact_reach": 0.15,
		"hurt_time": 0.22,
		"spawn_time": 0.7,
		"corpse_time": 1.4,
		"preferred_range": [6.0, 10.0],   # 保持與玩家的距離
		"fire_reach": 3.0,                # 距離在 preferred_range 上限 + 這個值以內才射擊
		"strafe_time": [1.2, 2.6],        # 每次橫移方向維持的秒數
		"strafe_speed_mul": 0.6,
		"aim_time": 0.75,                 # 出手前的預備動作（玩家的閃避提示）
		"aim_track": 0.75,                # 預備動作前 75% 追蹤玩家，之後鎖定方向
		"aim_turn_mul": 1.5,
		"first_fire_delay": [0.8, 2.0],   # 剛出生時第一次射擊前的延遲
		"fire_interval": 2.4,
		"fire_interval_jitter": [0.8, 1.25],
		"projectile_speed": 10.0,
		"projectile_damage": 12.0,
		"projectile_radius": 0.25,
		"projectile_range": 18.0,
		"projectile_knockback": 6.0,
		"projectile_offset": 0.7,
		"projectile_color": Color("b48cff"),
	},

	&"boss": {
		"visual": &"boss",
		"max_hp": 900.0,
		"move_speed": 2.2,
		"speed_variance": 0.0,
		"turn_speed": 3.5,
		"radius": 1.0,
		"mass": 30.0,
		"knockback_mul": 0.12,
		"contact_damage": 12.0,
		"contact_interval": 1.0,
		"contact_knockback": 12.0,
		"contact_reach": 0.15,
		"spawn_time": 1.6,
		"spawn_shake": 0.4,
		"corpse_time": 3.5,
		"decide_delay": 0.4,              # 回到追擊後至少這麼久才出下一招
		"first_cooldowns": {"charge": 3.0, "summon": 2.0},   # 開場給玩家一點時間
		"slam": {
			"trigger_distance": 3.2, "radius": 3.4, "windup": 0.85, "recovery": 0.8,
			"damage": 26.0, "knockback": 16.0, "cooldown": 3.5,
			"hit_stop": 0.06, "shake": 0.7, "shake_duration": 0.35,
		},
		"charge": {
			"min_distance": 5.0, "windup": 0.75, "speed": 15.0, "duration": 0.85, "recovery": 1.0,
			"wall_stun": 1.6, "damage": 22.0, "knockback": 18.0, "cooldown": 6.0,
			"hit_reach": 0.3, "hit_stop": 0.06, "shake": 0.4, "wall_margin": 0.05,
			"wall_shake": 0.6, "wall_shake_duration": 0.35,
		},
		"summon": {
			"hp_threshold": 0.75, "count": 3, "windup": 1.0, "recovery": 0.4, "cooldown": 14.0,
			"spread": 0.9, "distance": 2.5, "edge_margin": 1.5,
		},
		"enrage": {
			"hp_threshold": 0.5, "speed_mul": 1.3, "cooldown_mul": 0.65,
			"shake": 0.5, "shake_duration": 0.4,
		},
	},
}
