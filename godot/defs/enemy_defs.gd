# 敵人資料定義（照搬網頁版 legacy/src/entities/enemyDefs.js，欄位改 snake_case）；行為在 sim/enemies/
# 網頁版寫死在行為程式裡的數字也搬到這裡（例如 Boss 招式的震動與停頓）
# v0.17.0 起和網頁版刻意不同：拿掉接觸傷害（contact_*），骷髏戰士改用 swing 揮砍；blockable 標示能否被格擋（B5）
# behavior：行為類別（Spawner.BEHAVIORS：melee / ranged / boss）；is_boss：Boss（先出場、出生位置、不套波次倍率、Boss 血條）；
# freeze_immune：不會被道具冰凍。流程只看這些欄位，不寫死怪物種類
# resists：屬性 → 抗性（StatDefs.DAMAGE_TYPES；負的是弱點，−0.25 = 多受 25%），數字 Claude 暫定；遊戲裡不顯示，寫在怪物圖鑑
class_name EnemyDefs

const ENEMIES := {
	&"grunt": {
		"resists": {&"holy": -0.25, &"poison": 0.5},
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
		"resists": {&"holy": -0.25, &"poison": 0.5},
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

	# 腐屍（第 1 層主力，數值 Claude 暫定）：慢、血厚、成群；撲抱抓住後持續啃咬（sim/enemies/zombie.gd）
	&"zombie": {
		"resists": {&"fire": -0.25, &"holy": -0.25, &"poison": 0.5, &"shadow": 0.5},
		"visual": &"zombie",
		"behavior": &"zombie",
		"max_hp": 48.0,
		"move_speed": 1.8,
		"speed_variance": 0.12,
		"turn_speed": 5.0,
		"radius": 0.45,
		"mass": 1.2,
		"hurt_time": 0.22,
		"spawn_time": 0.9,
		"corpse_time": 1.4,
		"lunge": {
			"trigger_distance": 1.4,   # 與目標中心距離在這以內、冷卻好時開始舉手
			"windup": 0.6,             # 舉手後仰：前 track 比例的時間轉向目標，之後鎖定方向
			"track": 0.6,
			"distance": 1.2,           # 往前撲多遠（duration 秒內）
			"duration": 0.18,
			"hit_reach": 0.35,         # 撲的判定：身體外擴這麼多的圓，只打一次
			"recovery": 0.6,
			"damage": 6.0,
			"cooldown": 1.6,           # 從舉手開始算
			"blockable": true,
			"blocked_stagger": 0.5,    # 撲抱被盾擋下時踉蹌幾秒
			"grab_time": 0.8,          # 撲中後抓住幾秒（期間玩家同暈眩，按翻滾立刻掙脫）
			"bite_interval": 0.2,
			"bite_damage": 4.0,        # 每口；抓滿 0.8 秒咬 4 口
		},
	},

	# 膨脹屍（第 1 層，數值 Claude 暫定）：走近停下脹大 → 自爆，留下腐氣；被打死也會炸（sim/enemies/bloater.gd）
	&"bloater": {
		"resists": {&"fire": -0.5, &"poison": 0.75},
		"visual": &"bloater",
		"behavior": &"bloater",
		"max_hp": 30.0,
		"move_speed": 1.5,
		"speed_variance": 0.1,
		"turn_speed": 4.0,
		"radius": 0.55,
		"mass": 2.0,
		"hurt_time": 0.22,
		"spawn_time": 0.9,
		"corpse_time": 4.0,          # 要比 death_delay + 腐氣持續時間長：腐氣的傷害來源是屍體
		"burst": {
			"trigger_distance": 2.0,  # 與目標中心距離在這以內就停下脹大
			"swell_time": 1.0,
			"death_delay": 0.5,       # 被打死後幾秒炸
			"radius": 2.5,
			"damage": 22.0,
			"knockback": 10.0,
			"color": Color("8fbf4a"),
		},
		"gas": {"radius": 2.2, "duration": 3.0, "damage_per_sec": 6.0, "color": Color("7aa83a")},
	},

	# 屍犬（第 1 層，數值 Claude 暫定）：快，繞到目標背後的視野外才撲（sim/enemies/hound.gd）
	&"hound": {
		"resists": {&"cold": -0.25, &"poison": 0.25},
		"visual": &"hound",
		"behavior": &"hound",
		"max_hp": 22.0,
		"move_speed": 4.5,
		"speed_variance": 0.1,
		"turn_speed": 10.0,
		"radius": 0.4,
		"mass": 0.8,
		"hurt_time": 0.2,
		"spawn_time": 0.7,
		"corpse_time": 1.4,
		"prowl": {
			"orbit": [5.0, 7.0],               # 繞圈的半徑範圍；被看著時退到外圈
			"step": 0.7,                       # 每次往目標背後轉多少弧度（決定繞圈的目標點）
			"behind_angle": deg_to_rad(110.0), # 相對目標朝向超過這個角度算在背後（視野是前方 ±60°）
			"patience": 6.0,                   # 繞這麼久還到不了背後就從正面撲
		},
		"pounce": {
			"trigger_distance": 4.5,
			"windup": 0.4,      # 伏低（鎖定方向）
			"distance": 4.0,
			"duration": 0.3,
			"leap_vz": 3.5,     # 撲的時候跳起來
			"hit_reach": 0.3,
			"recovery": 0.5,
			"damage": 10.0,
			"knockback": 7.0,
			"cooldown": 2.5,    # 從伏低開始算
			"blockable": true,
		},
	},

	# 守墓人（第 1 層 Boss，數值 Claude 暫定）：開局假裝 NPC，第一型態慢、靠道具（sim/enemies/gravekeeper.gd）
	&"gravekeeper": {
		"resists": {&"holy": -0.25, &"fire": 0.75},
		"name": "守墓人",
		"visual": &"gravekeeper",
		"behavior": &"gravekeeper",
		"is_boss": true,
		"freeze_immune": true,
		"hit_color": Color("ff9a40"),
		"max_hp": 700.0,
		"move_speed": 1.8,
		"speed_variance": 0.0,
		"turn_speed": 3.5,
		"radius": 0.7,
		"mass": 30.0,
		"knockback_mul": 0.12,
		"spawn_time": 1.0,
		"corpse_time": 3.5,
		"decide_delay": 0.35,
		"first_cooldowns": {"lob": 1.5, "lantern": 2.0, "whistle": 4.0},
		"npc": {
			"speed_mul": 0.4, "pause": [2.0, 4.0],   # 掃地：慢慢走、停下來掃
			"talk_range": 1.6,                        # 身體邊緣到身體邊緣多近能按 F 說話
			"reveal_time": 1.5,                       # 說完「又一頭肥羊……」幾秒後開打
		},
		"shovel": {
			"trigger_distance": 2.8, "windup": 0.9, "track": 0.5, "active": 0.1, "recovery": 0.6,
			"range": 3.0, "arc": PI * 120.0 / 180.0, "damage": 18.0, "knockback": 9.0, "cooldown": 2.0,
		},
		"lob": {
			"min_distance": 4.0, "max_distance": 14.0, "windup": 0.6, "flight_time": 0.8, "recovery": 0.4, "cooldown": 5.0,
			"count": 3, "spread": 2.2,      # 第一坨丟目標腳下，其他兩坨在 spread 半徑內
			"radius": 1.2, "damage": 10.0, "knockback": 4.0, "slow_mul": 0.5, "slow_time": 1.5, "color": Color("6b4f2e"),
		},
		"lantern": {
			"trigger_distance": 5.5, "windup": 0.8, "track": 0.6, "duration": 1.0, "tick": 0.25, "recovery": 0.6, "cooldown": 6.0,
			"range": 6.0, "arc": PI * 60.0 / 180.0, "damage": 6.0, "color": Color("ff8a30"),
			"embers": [2.5, 4.5], "ember_radius": 1.0, "ember_time": 2.0, "ember_dps": 5.0,   # 噴完沿噴火方向留下的殘火（擋不住）
		},
		"whistle": {"windup": 0.6, "recovery": 0.4, "cooldown": 12.0, "count": 2, "max_alive": 2, "distance": 2.0},
		# 半血轉型態（取代狂暴）：form 0 老守墓人 → 1 墓園狼人；畫面層照 form_models 換模型、HUD 照 form_names 換名字
		"form_models": [&"gravekeeper", &"werewolf"],
		"form_names": ["守墓人", "墓園狼人"],
		"transform": {
			"hp_threshold": 0.5, "time": 2.0,                       # 變身中無敵
			"roar_radius": 4.0, "roar_damage": 5.0, "roar_knockback": 14.0, "shake": 0.6, "shake_duration": 0.5,
		},
		"wolf": {
			"resists": {&"phys": 0.3, &"holy": -0.5},   # 變身後整組換掉
			"move_speed": 7.5, "turn_speed": 9.0, "decide_delay": 0.2,
			"first_cooldowns": {"leap": 1.5, "howl": 6.0, "stalk": 4.0},
			"claw": {   # 三連爪：前兩下擋得住，第三下往前撲、擋不住
				"trigger_distance": 2.2, "windup": 0.3, "interval": 0.25, "range": 2.4, "arc": PI * 100.0 / 180.0,
				"damage": 10.0, "last_damage": 16.0, "knockback": 5.0, "lunge": 2.0, "lunge_time": 0.15, "recovery": 0.6, "cooldown": 2.0,
			},
			"leap": {   # 飛撲：跳到目標當時的位置，看影子躲
				"min_distance": 4.5, "max_distance": 12.0, "windup": 0.5, "flight": 0.6, "recovery": 0.5, "cooldown": 6.0,
				"radius": 2.5, "damage": 22.0, "knockback": 10.0, "shake": 0.5,
			},
			"stalk": {"max_distance": 10.0, "behind": 6.0, "time": 3.0, "speed_mul": 1.1, "cooldown": 10.0},   # 隱入黑暗：跑到目標背後再撲
			"howl": {"windup": 1.0, "recovery": 0.3, "cooldown": 15.0, "count": 3, "max_alive": 3, "speed_mul": 1.2, "buff_time": 5.0},
		},
	},

	&"boss": {
		"resists": {&"holy": -0.25, &"poison": 0.5, &"shadow": 0.5},
		"name": "亡骸騎士",
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


# 各層的小怪種類與比例（設計方向「各層怪物」）：地圖預放的怪群、挖墳怪潮用這一層的表，挖墳點噴的是下一層的表；
# 超過表的層數用最後一層的表
const FLOOR_MIX := {
	1: {&"zombie": 0.7, &"hound": 0.2, &"bloater": 0.1},
	2: {&"grunt": 0.75, &"archer": 0.25},
}


static func is_boss(type: StringName) -> bool:
	return ENEMIES[type].get("is_boss", false)


static func floor_mix(floor_num: int) -> Dictionary:
	var last: int = FLOOR_MIX.keys().max()
	return FLOOR_MIX[clampi(floor_num, 1, last)]


# 照 floor_mix 的比例抽一種（用傳入的 rng，模擬才有決定性）
static func roll_floor_type(floor_num: int, rng: RandomNumberGenerator) -> StringName:
	var mix := floor_mix(floor_num)
	var r := rng.randf()
	var acc := 0.0
	var pick: StringName = mix.keys()[0]
	for type: StringName in mix:
		pick = type
		acc += mix[type]
		if r < acc:
			break
	return pick
