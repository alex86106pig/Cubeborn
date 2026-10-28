# 敵人資料定義（照搬網頁版 legacy/src/entities/enemyDefs.js，欄位改 snake_case）；行為在 sim/enemies/
# 網頁版寫死在行為程式裡的數字也搬到這裡（例如 Boss 招式的震動與停頓）
# v0.17.0 起和網頁版刻意不同：拿掉接觸傷害（contact_*），骷髏戰士改用 swing 揮砍；blockable 標示能否被格擋（B5）
# behavior：行為類別（Spawner.BEHAVIORS：melee / ranged / boss）；is_boss：Boss（先出場、出生位置、不套波次倍率、Boss 血條）；
# freeze_immune：不會被道具冰凍。流程只看這些欄位，不寫死怪物種類
class_name EnemyDefs

const ENEMIES := {
	&"grunt": {
		"visual": &"melee",
		"behavior": &"melee",
		"max_hp": 36.0,
		"move_speed": 2.6,
		"speed_variance": 0.2,
		"turn_speed": 6.0,
		"radius": 0.45,
		"mass": 1.0,
		"hurt_time": 0.22,
		"spawn_time": 0.7,
		"corpse_time": 1.4,
		# 揮砍（v0.17.0，使用者選「中等」）：取代網頁版的接觸傷害
		"swing": {
			"trigger_distance": 1.3,    # 與玩家中心距離在這以內、冷卻好時開始舉刀
			"windup": 0.5,              # 舉刀：站定，前 track 比例的時間轉向玩家，之後鎖定方向
			"track": 0.5,
			"active": 0.1,              # 揮下：判定出現的時間，每揮一次每個目標只打一次
			"recovery": 0.5,
			"range": 1.5,
			"arc": PI * 100.0 / 180.0,  # 100°
			"damage": 12.0,
			"knockback": 9.0,
			"cooldown": 1.2,            # 從舉刀開始算
			"blockable": true,
		},
		# 衝撞（v0.27.0）：狂暴的 Boss 召喚出來的骷髏戰士爬出來後衝一次（同 Boss 衝鋒的模式、規模小）
		"rush": {
			"windup": 0.5, "speed": 11.0, "duration": 0.5, "recovery": 0.5, "hit_reach": 0.3,
			"damage": 12.0, "knockback": 10.0, "blockable": true,
		},
	},

	&"archer": {
		"visual": &"ranged",
		"behavior": &"ranged",
		"max_hp": 26.0,
		"move_speed": 2.3,
		"speed_variance": 0.15,
		"turn_speed": 8.0,
		"radius": 0.42,
		"mass": 1.0,
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
		"projectile_blockable": true,
	},

	&"boss": {
		"visual": &"boss",
		"behavior": &"boss",
		"is_boss": true,
		"freeze_immune": true,   # v0.33.0：Boss 不會被冰凍
		"hit_color": Color("ff4040"),   # 砸地、衝鋒打中時的命中粒子（網頁版 0xff4040）
		"max_hp": 900.0,
		# v0.27.0 使用者決定 Boss 加強：跑速 2.2 → 3.0、出招間隔縮短 30%、招式範圍變大、新招直劈、狂暴進化（數值 Claude 訂）
		"move_speed": 3.0,
		"speed_variance": 0.0,
		"turn_speed": 4.0,
		"radius": 1.0,
		"mass": 30.0,
		"knockback_mul": 0.12,
		"spawn_time": 1.6,
		"spawn_shake": 0.4,
		"corpse_time": 3.5,
		"decide_delay": 0.28,             # 回到追擊後至少這麼久才出下一招（0.4 × 0.7）
		"first_cooldowns": {"charge": 2.1, "summon": 1.4},   # 開場給玩家一點時間（巡邏中發現玩家時重新計算）
		# 挖墳地圖開局在 map.boss_room 裡巡邏：走到隨機點、停一下再走；前方 sight_arc 扇形 sight_radius 內、
		# 或任何方向 notice_radius 內看到玩家（沒被牆擋）、或被打，就開始追（之後不再回去巡邏、不限範圍）
		"patrol": {"speed_mul": 0.45, "pause": [1.0, 2.5], "sight_radius": 12.0, "sight_arc": deg_to_rad(120.0), "notice_radius": 4.0},
		# 砸地：以 Boss 為中心，紅圈一圈一圈往外擴散；每圈只打到「那一圈範圍內」的目標（同一次砸地每人最多被打一次）
		# 打到：擊飛（往上 knockup 速度）＋ 移速 ×slow_mul 持續 slow_time 秒；跳起來躲得過（同 v0.23.0 的 max_air）
		"slam": {
			# ring_delay 0.25 → 0.5（v0.42.0 使用者決定）：波往外每秒 6 單位，比玩家移速 6.5 慢，往外跑躲得掉
			"trigger_distance": 4.0, "rings": [3.0, 6.0, 9.0], "ring_delay": 0.5, "windup": 0.7, "recovery": 0.8,
			"damage": 26.0, "knockback": 8.0, "knockup": 7.0, "slow_mul": 0.5, "slow_time": 2.0, "cooldown": 2.45,
			"hit_stop": 0.06, "shake": 0.7, "shake_duration": 0.35, "blockable": false,
		},
		# 衝鋒：準備時間縮短、判定加大，撞到（沒擋下）的玩家暈眩 stun 秒
		"charge": {
			"min_distance": 5.0, "windup": 0.45, "speed": 15.0, "duration": 0.85, "recovery": 0.8,
			"wall_stun": 1.6, "damage": 22.0, "knockback": 18.0, "cooldown": 4.2, "stun": 0.8,
			"hit_reach": 0.8, "hit_stop": 0.06, "shake": 0.4, "wall_margin": 0.05,
			"wall_shake": 0.6, "wall_shake_duration": 0.35,
			"blockable": true, "block_knockback_mul": 1.0,   # v0.18.2 使用者決定：擋得住，但擋下時照樣被全額擊退
		},
		# 召喚：4 隻，每隻隨機是骷髏戰士或弓手
		"summon": {
			"hp_threshold": 0.75, "count": 4, "archer_chance": 0.5, "windup": 0.8, "recovery": 0.4, "cooldown": 9.8,
			"spread": 0.9, "distance": 2.5, "edge_margin": 1.5,
		},
		# 直劈（v0.27.0 新招）：沒有紅圈，舉劍 windup 秒（看動作就知道要來）→ 往前劈下前方細長的扇形
		# 舉劍的前 track 比例用一半的轉身速度跟著玩家（追得不好），之後鎖定方向：繞圈走位就躲得開
		"cleave": {
			"trigger_distance": 4.0, "windup": 0.6, "track": 0.5, "track_turn_mul": 0.5, "active": 0.1, "recovery": 0.6,
			"range": 4.5, "arc": PI * 40.0 / 180.0, "damage": 30.0, "knockback": 12.0, "cooldown": 2.5,
			"hit_stop": 0.06, "shake": 0.35, "blockable": true,
		},
		# 狂暴（血量一半以下）：全部更快；衝鋒連續 3 次；召喚完的骷髏戰士各衝撞一次；砸地不管多遠都放（先在玩家腳下預警，再瞬移過去砸）
		"enrage": {
			"hp_threshold": 0.5, "speed_mul": 1.3, "cooldown_mul": 0.6, "windup_mul": 0.75,
			"charge_count": 3, "charge_rewindup": 0.3,   # 連衝之間重新瞄準的秒數
			"teleport_warn": 0.6, "teleport_windup": 0.3,   # 玩家腳下預警幾秒後瞬移過去、再過幾秒砸下
			"shake": 0.5, "shake_duration": 0.4,
		},
	},

	# 冤魂（D6，Godot 版新增，數值 Claude 暫定）：死去的隊友在下一層的樣子，打倒就復活；行為同骷髏戰士（MeleeEnemy）
	# 不掉金幣、不掉武器（LootDefs / WeaponDropDefs 沒有它）；畫面是半透明的騎士
	&"ghost": {
		"visual": &"ghost",
		"behavior": &"melee",
		"max_hp": 150.0,
		"move_speed": 3.0,
		"speed_variance": 0.0,
		"turn_speed": 6.0,
		"radius": 0.45,
		"mass": 1.5,
		"hurt_time": 0.22,
		"spawn_time": 0.7,
		"corpse_time": 1.0,
		"swing": {
			"trigger_distance": 1.4, "windup": 0.45, "track": 0.5, "active": 0.1, "recovery": 0.45,
			"range": 1.6, "arc": PI * 100.0 / 180.0, "damage": 14.0, "knockback": 9.0, "cooldown": 1.1, "blockable": true,
		},
		"rush": {
			"windup": 0.5, "speed": 11.0, "duration": 0.5, "recovery": 0.5, "hit_reach": 0.3,
			"damage": 14.0, "knockback": 10.0, "blockable": true,
		},
	},

	# 骷髏僕從（G6 亡者大軍，數值 Claude 暫定）：玩家方的骷髏戰士（sim/enemies/minion.gd），打怪、不打玩家，life 秒後消失
	# 不給靈魂、不掉金幣與武器（LootDefs / WeaponDropDefs 沒有它）；畫面是染綠的骷髏戰士
	&"minion": {
		"visual": &"melee",
		"behavior": &"melee",
		"max_hp": 60.0,
		"move_speed": 4.5,
		"speed_variance": 0.0,
		"turn_speed": 8.0,
		"radius": 0.4,
		"mass": 1.0,
		"hurt_time": 0.15,
		"spawn_time": 0.5,
		"corpse_time": 0.8,
		"life": 20.0,            # 存在秒數
		"seek_range": 12.0,      # 找多遠內的怪；沒有就跟著召喚者
		"follow_distance": 2.5,  # 跟著召喚者時離多遠就停
		# 專屬特性「碎骨爆裂」：倒下時（被打死或時間到）炸開，半徑內的怪受傷並被擊退
		"burst": {"radius": 2.2, "damage": 20.0, "knockback": 8.0, "color": Color("d8e8c0")},
		"swing": {
			"trigger_distance": 1.3, "windup": 0.35, "track": 0.5, "active": 0.1, "recovery": 0.35,
			"range": 1.5, "arc": PI * 100.0 / 180.0, "damage": 8.0, "knockback": 6.0, "cooldown": 0.9, "blockable": false,
		},
		"rush": {
			"windup": 0.5, "speed": 11.0, "duration": 0.5, "recovery": 0.5, "hit_reach": 0.3,
			"damage": 8.0, "knockback": 6.0, "blockable": false,
		},
	},
}


static func is_boss(type: StringName) -> bool:
	return ENEMIES[type].get("is_boss", false)
