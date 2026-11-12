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

	# 骷髏盾槍兵（第 2 層，數值 Claude 暫定）：正面舉盾擋下所有攻擊、重攻擊破防；直刺時正面打得到（sim/enemies/spearman.gd）
	&"spearman": {
		"name": "骷髏盾槍兵",
		"resists": {&"holy": -0.25, &"poison": 0.5},
		"visual": &"spearman",
		"behavior": &"spearman",
		"max_hp": 55.0,
		"move_speed": 2.0,
		"speed_variance": 0.15,
		"turn_speed": 3.0,          # 舉盾時轉得慢：繞到側面就打得到
		"radius": 0.5,
		"mass": 1.6,
		"hurt_time": 0.22,
		"spawn_time": 0.7,
		"corpse_time": 1.4,
		"shield": {
			"arc": PI * 120.0 / 180.0,   # 正面這個角度內的攻擊全部擋下
			"push_mul": 0.3,             # 擋下時被推退的比例
			"break_time": 1.5,           # 重攻擊（is_heavy：連段最後一下、盾反、爆炸、蓄力）打盾破防
			"sfx_block": "shieldBash", "sfx_break": "hitHeavy",
		},
		"thrust": {
			"trigger_distance": 3.0,
			"windup": 0.5, "track": 0.5,   # 盾往旁邊偏、槍收到腰間；前一半轉向目標
			"active": 0.12,
			"recovery": 0.6,
			"range": 3.5, "width": 0.35,   # 前方 3.5 的細長直線（窄扇形）
			"damage": 14.0,
			"knockback": 8.0,
			"cooldown": 2.2,
			"blockable": true,
		},
	},

	# 骨輪（第 2 層，數值 Claude 暫定）：直線滾向玩家、撞牆散成骨堆暈 2 秒；不會硬直（sim/enemies/bone_wheel.gd）
	&"bone_wheel": {
		"name": "骨輪",
		"resists": {&"holy": -0.25, &"poison": 0.5},
		"visual": &"bone_wheel",
		"behavior": &"bone_wheel",
		"max_hp": 40.0,
		"move_speed": 2.4,          # 沒在滾時慢慢滾近
		"speed_variance": 0.1,
		"turn_speed": 4.0,
		"radius": 0.6,
		"mass": 3.0,                # 不會硬直、很難推動
		"hurt_time": 0.0,
		"spawn_time": 0.7,
		"corpse_time": 1.4,
		"roll": {
			"trigger_distance": 18.0,   # 這麼近、中間沒有牆才滾
			"windup": 0.5,              # 原地喀啦晃、骨頭收緊
			"speed": 13.0,
			"turn_rate": PI / 3.0,      # 滾的時候每秒最多轉 60° 追著目標
			"max_time": 4.0,            # 一直沒撞到東西就停下（不散）
			"hit_reach": 0.25,
			"damage": 16.0,
			"knockback": 12.0,
			"side_push": 0.8,           # 擊退方向往側面的比例（其餘往前）：把人撞到一邊，輪子滾過去
			"blockable": true,          # 被盾擋下算撞牆
			"collapse": 2.0,            # 撞牆散成骨堆暈多久（最後 reform 秒組回去，畫面用）
			"reform": 0.5,
			"cooldown": 2.5,            # 停下 / 組回去之後多久才再滾
			"shake": 0.12,
			"sfx_windup": "enemySpawn", "sfx_crash": "hitHeavy",
		},
	},

	# 屍甲蟲（第 3 層的怪，第 2 層的石棺噴出來，數值 Claude 暫定）：鑽地偷襲（sim/enemies/beetle.gd）
	&"beetle": {
		"name": "屍甲蟲",
		"resists": {&"fire": -0.25, &"poison": 0.5},
		"visual": &"beetle",
		"behavior": &"beetle",
		"max_hp": 10.0,
		"move_speed": 4.0,
		"speed_variance": 0.15,
		"turn_speed": 8.0,
		"radius": 0.3,
		"mass": 0.5,
		"hurt_time": 0.0,          # 不硬直（beetle.gd 沒有 hurt 狀態）
		"spawn_time": 0.5,
		"corpse_time": 1.0,
		"swarm": 3,                # 挖墳點（石棺）抽到牠一次噴這麼多隻
		"burrow": {
			"min_time": 0.6,           # 鑽下去至少這麼久才冒出來
			"strike_reach": 0.15,      # 爬到跟目標碰在一起（兩個半徑）再近這麼多就停下：碰撞分離會把兩個推開，不能只看中心距離
			"emerge": 0.4,             # 停在腳下、土塊跳動（預兆）
			"bite_radius": 0.85, "damage": 8.0, "knockback": 3.0, "knockup": 4.0,   # 冒出來咬，擋不住、小擊飛
			"surface": 2.0,            # 咬完在地面停多久（打得到）
		},
	},

	# 蟲巢（第 3 層，數值 Claude 暫定）：不會動，一直孵屍甲蟲、靠近會噴酸、打破再孵一窩（sim/enemies/hive.gd）
	&"hive": {
		"name": "蟲巢",
		"resists": {&"fire": -0.5, &"poison": 0.75},
		"visual": &"hive",
		"behavior": &"hive",
		"max_hp": 110.0,
		"move_speed": 0.0,
		"speed_variance": 0.0,
		"turn_speed": 0.0,
		"radius": 0.9,
		"mass": 50.0,
		"knockback_mul": 0.0,      # 推不動
		"hurt_time": 0.0,          # 不硬直（hive.gd 沒有 hurt 狀態）
		"spawn_time": 0.6,
		"corpse_time": 1.2,
		"pack_max": 1,             # 只出現在預先放好的怪群裡、每群最多這麼多個；超過的、怪潮與噴怪抽到的換成 pack_fallback（roll_floor_type）
		"pack_fallback": &"beetle",
		"no_affixes": [&"summoner"],   # 自己就會孵蟲，不抽召喚（會叫出更多蟲巢）
		"hatch": {
			"type": &"beetle",
			"first": 2.0,              # 醒來後多久孵第一窩
			"interval": 6.0, "count": 3,
			"max_alive": 8,            # 自己孵的同時最多活這麼多隻
			"on_death": 3,             # 被打破時再孵一窩（不看上限）
			"spread": 1.6,             # 孵在身邊這個半徑的一圈上
		},
		"acid": {
			"trigger_distance": 3.0,   # 目標中心進到這以內、冷卻好就開始鼓酸泡
			"windup": 0.5,
			"radius": 3.0,
			"damage": 12.0,
			"knockback": 6.0,
			"cooldown": 4.0,           # 從噴出來開始算
			"color": Color("a8e04a"),
			"sfx_windup": "enemySpawn", "sfx_burst": "explosion",
		},
	},

	# 墓穴蜘蛛（第 3 層的怪，第 2 層的石棺噴出來，數值 Claude 暫定）：同弓手保持距離，吐蛛絲彈纏住玩家、沒中結成蛛網（sim/enemies/spider.gd）
	&"spider": {
		"name": "墓穴蜘蛛",
		"resists": {&"fire": -0.5, &"poison": 0.5},
		"visual": &"spider",
		"behavior": &"spider",
		"max_hp": 28.0,
		"move_speed": 3.2,
		"speed_variance": 0.15,
		"turn_speed": 7.0,
		"radius": 0.5,
		"mass": 1.0,
		"hurt_time": 0.22,
		"spawn_time": 0.6,
		"corpse_time": 1.2,
		"preferred_range": [5.0, 8.0],
		"fire_reach": 2.0,
		"strafe_time": [1.0, 2.2],
		"strafe_speed_mul": 0.7,
		"aim_time": 0.6,                  # 前腳抬起、腹部翹起
		"aim_track": 0.7,
		"aim_turn_mul": 1.5,
		"first_fire_delay": [0.8, 1.6],
		"fire_interval": 3.0,
		"fire_interval_jitter": [0.8, 1.25],
		"projectile_speed": 8.0,
		"projectile_damage": 4.0,
		"projectile_radius": 0.3,
		"projectile_range": 12.0,
		"projectile_knockback": 0.0,
		"projectile_offset": 0.6,
		"projectile_color": Color("e8e4dc"),
		"projectile_blockable": true,
		# 蛛絲彈：打中纏住 root 秒；沒中在落點結成半徑 radius 的蛛網 time 秒，站在上面移速 × slow，火燒得掉
		"web": {"root": 1.2, "radius": 1.5, "time": 8.0, "slow": 0.5, "overshoot": 1.5},
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
		"move_speed": 5.6,           # 使用者 2026-11-02：要比攻擊中的玩家快（法杖、短弓邊打邊走 6.5 × 0.8 = 5.2），比純跑 6.5 慢
		"speed_variance": 0.05,
		"turn_speed": 5.0,
		"radius": 0.45,
		"mass": 1.2,
		"hurt_time": 0.22,
		"spawn_time": 0.9,
		"corpse_time": 1.4,
		"lunge": {
			"trigger_distance": 2.6,   # 與目標中心距離在這以內、冷卻好時開始舉手（怪物圖鑑）
			"windup": 0.4,             # 舉手後仰：前 track 比例的時間轉向目標，之後鎖定方向
			"track": 0.6,
			"distance": 2.2,           # 往前撲多遠（duration 秒內）
			"duration": 0.15,
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
		# 撿武器（怪物圖鑑）：每 scan_interval 秒找 radius 內地上的武器，走到 reach 內彎腰 bend 秒撿起（被打中斷）；走 give_up 秒還沒到就放棄
		"pickup": {"radius": 4.0, "scan_interval": 0.5, "reach": 0.6, "bend": 0.8, "give_up": 4.0},
		"armed_damage": 6.0,       # 持武器的招式傷害 = damage_pct × 這個（ARMED_ZOMBIE）
	},

	# 膨脹屍（第 1 層，數值 Claude 暫定）：走近停下脹大 → 自爆，留下腐氣；被打死也會炸（sim/enemies/bloater.gd）
	&"bloater": {
		"resists": {&"fire": -0.5, &"poison": 0.75},
		"visual": &"bloater",
		"behavior": &"bloater",
		"max_hp": 30.0,
		"move_speed": 5.4,           # 使用者 2026-11-02：同腐屍，要比攻擊中的玩家快
		"speed_variance": 0.03,
		"turn_speed": 4.0,
		"radius": 0.55,
		"mass": 2.0,
		"hurt_time": 0.22,
		"spawn_time": 0.9,
		"corpse_time": 4.0,          # 要比 death_delay + 腐氣持續時間長：腐氣的傷害來源是屍體
		"no_affixes": [&"volatile"],  # 自己就會死後爆炸，不抽死亡爆炸（會炸兩次）
		# 撲抱（只用一次）：挺肚子張手 windup → 往前撲 distance；撲中抱住並開始脹（burst.hold_swell_time），被盾擋下倒地 blocked_fall
		"hug": {"trigger_distance": 3.5, "windup": 0.5, "track": 0.6, "distance": 2.5, "duration": 0.25, "hit_reach": 0.3, "recovery": 0.4, "blocked_fall": 0.5},
		"burst": {
			"trigger_distance": 2.0,  # 與目標中心距離在這以內就停下脹大
			"swell_time": 1.0,
			"hold_swell_time": 0.7,   # 抱住時脹這麼久就炸
			"death_delay": 0.5,       # 被打死後幾秒炸
			"radius": 2.5,
			"damage": 35.0,           # 怪物圖鑑：35、抱住的那位 +10、擊倒並彈起
			"hold_bonus": 10.0,
			"knockup": 6.0,
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
		"move_speed": 7.0,           # 使用者 2026-11-02：腐屍加速到 5.6 後，狗要明顯更快
		"speed_variance": 0.1,
		"turn_speed": 10.0,
		"radius": 0.4,
		"mass": 0.8,
		"hurt_time": 0.35,
		"spawn_time": 0.7,
		"corpse_time": 1.4,
		"prowl": {
			"orbit": [5.0, 7.0],               # 繞圈的半徑範圍；被看著時退到外圈
			"step": 0.7,                       # 每次往目標背後轉多少弧度（決定繞圈的目標點）
			"behind_angle": deg_to_rad(110.0), # 相對目標朝向超過這個角度算在背後（視野是前方 ±60°）
			"patience": 2.5,                   # 繞 / 牽制這麼久還沒出招就從正面撲（怪物圖鑑）
			"reverse_margin": deg_to_rad(45.0),# 照目前方向要繞超過 180° + 這個角度才換邊（玩家小幅轉身不會讓狗來回）
			"radius_speed": 2.0,               # 要繞的半徑每秒最多變多少（被看著 / 沒被看著切換時不跳）
			"retreat_slack": 0.3,              # 撲完退到 orbit[0] - 這個距離就算退開了，可以再撲（要大於離目標點 0.2 就停下的距離，否則停在半路退不完）
		},
		# 正面牽制（被目標看著的最近那隻）：逼近到 range、每 hop_interval 秒左右側跳 hop_distance
		"pin": {"range": [2.5, 4.0], "hop_interval": [0.5, 0.8], "hop_distance": 1.8, "hop_time": 0.22, "hop_vz": 2.5},
		"pack": {"max_attackers": 2},   # 同時最多幾隻在出招（快咬、飛撲）
		# 快咬（輕）：低頭齜牙 windup → 往前竄 distance → 往後跳 back_hop；擋下自己暈 blocked_daze
		"snap": {
			"trigger_distance": 1.8, "windup": 0.2, "track": 0.5, "distance": 1.2, "duration": 0.12, "hit_reach": 0.3,
			"damage": 6.0, "cooldown": 1.2, "blockable": true, "blocked_daze": 0.6, "back_hop": 2.5, "back_hop_time": 0.25,
		},
		# 飛撲（擊倒）：在目標視野外（含側面）、trigger_distance 內才撲；低吼前腳壓低 windup（鎖定方向）→ 直線 distance
		"pounce": {
			"trigger_distance": 6.0,
			"windup": 0.3,
			"distance": 4.0,
			"duration": 0.3,
			"leap_vz": 3.5,     # 撲的時候跳起來
			"hit_reach": 0.3,
			"recovery": 0.5,
			"damage": 10.0,
			"knockback": 7.0,
			"cooldown": 2.5,    # 從伏低開始算
			"blockable": true,
			"blocked_daze": 0.6,
		},
		# 抓翻滾：目標在 radius 內翻滾 → 飛撲到翻滾終點（跟飛撲共用冷卻與傷害）
		"roll_punish": {"radius": 3.0, "windup": 0.15, "max_distance": 5.0},
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
		"max_hp": 1000.0,            # 使用者 2026-11-02：700 → 1000（招式全面加快加痛，就是要變難）
		"move_speed": 3.0,
		"speed_variance": 0.0,
		"turn_speed": 3.5,
		"radius": 0.7,               # NPC 時的大小；開打後照 grow.size 放大（半徑、身高、模型一起）
		"mass": 30.0,
		"knockback_mul": 0.12,
		"spawn_time": 1.0,
		"corpse_time": 3.5,
		"decide_delay": 0.15,
		"first_cooldowns": {"dig": 2.0, "lantern": 1.5, "whistle": 3.0, "scoop": 1.0},
		"npc": {
			"speed_mul": 0.27, "pause": [2.0, 4.0],  # 掃地：慢慢走（約 0.8 單位/秒）、停下來掃
			"talk_range": 1.6,                        # 身體邊緣到身體邊緣多近能按 F 說話
			"reveal_time": 1.5,                       # 說完「又一頭肥羊……」幾秒後開打
		},
		"grow": {"time": 1.0, "size": 2.0},          # 開打時 time 秒內慢慢變大到 size 倍（不出招）；狼人維持這個大小
		# 以下距離都是從中心算（開打後半徑 1.4）
		"shovel": {
			"trigger_distance": 4.2, "windup": 0.45, "track": 0.5, "active": 0.1, "recovery": 0.45,
			"range": 4.8, "arc": PI * 150.0 / 180.0, "damage": 27.0, "knockback": 10.0, "cooldown": 1.2, "tier": &"heavy",
		},
		# 瘋狂鏟土：彎腰 windup → 狂鏟 duration 秒，每 interval 秒在競技場（map.boss_room；Boss 不在裡面就是身邊 fallback_radius）隨機落一顆石頭，
		# 每位玩家每 player_interval 秒必定有一顆落在腳邊 aim_jitter 內；每顆 fall_time 秒落地（地上影子越來越大），擋不住
		"dig": {
			"max_distance": 20.0, "windup": 0.4, "duration": 2.5, "interval": 0.08, "player_interval": 0.5, "aim_jitter": 0.8,
			"fall_time": 1.0, "recovery": 0.5, "cooldown": 8.0, "fallback_radius": 12.0,
			"radius": 1.5, "damage": 15.0, "knockback": 4.0, "slow_mul": 0.5, "slow_time": 1.5, "tier": &"medium", "color": Color("6b4f2e"),
		},
		# 提燈噴火：吸氣 windup → 邊噴邊追目標 duration 秒（移速 ×chase_mul、轉向 ×turn_mul）→ 預備 spin_windup 秒（只有動作，不畫圈）→ 原地轉一圈噴 spin_time 秒（每 spin_tick 一下，範圍 spin_range）→ recovery
		# 追著噴時每 ember_every 秒在火焰中段留一團殘火，轉圈時在身邊留 spin_embers 團（殘火擋不住、不硬直）
		"lantern": {
			"trigger_distance": 7.0, "windup": 0.55, "track": 0.6, "duration": 2.0, "tick": 0.25, "recovery": 0.5, "cooldown": 4.5,
			"chase_mul": 0.6, "turn_mul": 0.5, "spin_windup": 0.4, "spin_range": 4.0, "spin_time": 0.5, "spin_tick": 0.1, "spin_embers": 3,
			"range": 7.5, "arc": PI * 80.0 / 180.0, "damage": 9.0, "tier": &"light", "color": Color("ff8a30"),
			"ember_every": 0.5, "ember_at": 4.0, "ember_radius": 1.0, "ember_time": 2.0, "ember_dps": 5.0,
		},
		"whistle": {"windup": 0.3, "recovery": 0.3, "cooldown": 12.0, "count": 2, "max_alive": 2, "distance": 3.0},
		# 鏟起（怪物圖鑑備註 2）：鏟面貼地往前滑 windup → 前方 range、arc 抓第一位玩家（擋不住）→ 隨機 A / B 連段；連段中的傷害不吃受傷無敵；
		# 連段中被抓的那位以外的人打守墓人累積 break_damage 就中斷（放開玩家）
		"scoop": {
			"trigger_distance": 3.2, "windup": 0.3, "track": 0.5, "slide": 0.6, "range": 3.0, "arc": PI * 60.0 / 180.0,
			"damage": 9.0, "miss_recovery": 0.6, "cooldown": 8.0, "break_damage": 60.0, "color": Color("6b4f2e"),
			# A 拋飛 → 鏟土：往守墓人背後拋 distance（flight 秒，落地 land_damage、擊倒）；落地 rock_delay 秒後 rocks 顆土落在落點周圍 rock_spread 內
			"throw": {"distance": 6.0, "flight": 0.7, "land_damage": 15.0, "rock_delay": 0.4, "rocks": 3, "rock_spread": 1.5, "recovery": 0.6},
			# B 埋地 → 噴火：埋 bury 秒（連按翻滾每下少 mash_step、最多少 mash_max）；退 step_back（step_time 秒）→ 開燈罩 open → 直噴 flame 秒
			"bury": {"bury": 1.0, "mash_step": 0.1, "mash_max": 0.3, "step_back": 1.2, "step_time": 0.3, "open": 0.4, "flame": 0.8,
				"tick": 0.25, "range": 7.0, "arc": PI * 30.0 / 180.0, "damage": 9.0, "recovery": 0.5},
		},
		# 半血轉型態（取代狂暴）：form 0 老守墓人 → 1 墓園狼人；畫面層照 form_models 換模型、HUD 照 form_names 換名字
		"form_models": [&"gravekeeper", &"werewolf"],
		"form_names": ["守墓人", "墓園狼人"],
		"transform": {
			"hp_threshold": 0.5, "time": 2.0,                       # 變身中無敵
			"roar_radius": 5.0, "roar_damage": 8.0, "roar_knockback": 14.0, "roar_tier": &"heavy", "shake": 0.6, "shake_duration": 0.5,
		},
		"wolf": {
			"resists": {&"phys": 0.3, &"holy": -0.5},   # 變身後整組換掉
			"move_speed": 7.5, "turn_speed": 9.0, "decide_delay": 0.15,
			"first_cooldowns": {"leap": 1.5, "howl": 6.0, "stalk": 4.0},
			"claw": {   # 三連爪：前兩下擋得住，第三下往前撲、擋不住；每一下發 fx:claw（3 條紅色爪痕）
				"trigger_distance": 3.4, "windup": 0.25, "interval": 0.25, "range": 4.0, "arc": PI * 140.0 / 180.0,
				"damage": 15.0, "last_damage": 24.0, "knockback": 5.0, "lunge": 3.0, "lunge_time": 0.15, "recovery": 0.5, "cooldown": 2.0,
				"tiers": [&"medium", &"medium", &"heavy"], "color": Color("ff2a2a"),
			},
			"leap": {   # 飛撲：跳到目標當時的位置；蹲低到落地只有 windup + flight 秒，要靠反應翻滾
				"min_distance": 4.5, "max_distance": 12.0, "windup": 0.35, "flight": 0.3, "recovery": 0.5, "cooldown": 6.0,
				"radius": 3.0, "damage": 33.0, "knockback": 10.0, "shake": 0.5, "tier": &"knockdown",
			},
			"stalk": {"max_distance": 10.0, "behind": 6.0, "time": 3.0, "speed_mul": 1.1, "cooldown": 10.0},   # 隱入黑暗：跑到目標背後再撲
			"howl": {"windup": 0.8, "recovery": 0.3, "cooldown": 15.0, "count": 3, "max_alive": 3, "speed_mul": 1.2, "buff_time": 5.0},
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

	# 骸骨將軍（第 2 層 Boss，sim/enemies/bone_general.gd）：第一型態 = 亡骸騎士（inherits：沒寫的欄位照 boss，EnemyDefs.def_of 合併）；
	# 半血轉型態（取代狂暴）：脫甲 → 萬骨聚合體（colossus，數值 Claude 暫定）。測試場地的波次照舊用 boss（亡骸騎士，會狂暴）
	&"bone_general": {
		"inherits": &"boss",
		"name": "骸骨將軍",
		"visual": &"boss",
		"behavior": &"bone_general",
		"is_boss": true,
		"freeze_immune": true,
		"radius": 1.0,
		"max_hp": 900.0,
		"form_models": [&"boss", &"bone_colossus"],
		"form_names": ["骸骨將軍", "萬骨聚合體"],
		# 脫甲：跪地 time 秒無敵，盔甲碎片往外飛（有傷害、擋得住），場上的骷髏屍體全部被吸過來
		"transform": {
			"hp_threshold": 0.5, "time": 1.5,
			"shards": 8, "shard_speed": 9.0, "shard_range": 6.0, "shard_damage": 10.0, "shard_knockback": 6.0, "shard_color": Color("8a93a3"),
			"shake": 0.6, "shake_duration": 0.5,
		},
		"colossus": {
			"scale": 1.5,               # 模型放大的倍數
			"radius": 1.15,             # 碰撞半徑 1.0 → 1.15：跟著模型大一點，但不超過大隻怪的尋路格子（Config.NAV.margin_large），過得了 6 寬的走道與墓室的門
			"damage_taken": 1.3,        # 受到的傷害 +30%
			"move_speed": 2.4, "turn_speed": 3.0, "decide_delay": 0.35,
			"first_cooldowns": {"spikes": 1.0, "sweep": 2.0, "wheel": 4.0, "devour": 6.0},
			# 骨刺陣：骨臂插地（windup，地面沿 lines 個方向隆起）→ 從身邊往外一根根竄出骨刺（每 step 一根、每根晚 delay_per 秒），擋不住
			"spikes": {
				"windup": 0.6, "lines": 6, "start": 1.5, "length": 10.0, "step": 1.5, "delay_per": 0.07,
				"radius": 0.8, "damage": 18.0, "knockback": 4.0, "knockup": 6.0, "recovery": 0.7, "cooldown": 5.0,
			},
			# 多臂橫掃：身體扭到底（windup）→ 低掃一圈（跳起來躲，擋不住）→ gap 秒後高掃一圈（翻滾或格擋）
			"sweep": {
				"trigger_distance": 4.0, "windup": 0.7, "gap": 0.5, "range": 4.2, "low_damage": 16.0, "low_max_air": 0.3,
				"high_damage": 18.0, "knockback": 10.0, "recovery": 0.7, "cooldown": 4.0,
			},
			# 巨骨輪：蜷成球（windup）→ 同骨輪追著目標滾，撞牆 / 被盾擋下暈 stun 秒
			"wheel": {
				"min_distance": 5.0, "windup": 0.8, "speed": 11.0, "turn_rate": PI / 4.0, "max_time": 4.0, "hit_reach": 0.4,
				"damage": 24.0, "knockback": 14.0, "side_push": 0.8, "blockable": true, "stun": 3.0, "cooldown": 9.0, "shake": 0.5,
			},
			# 吞屍：胸腔打開（windup），radius 內的骷髏屍體與活著的骷髏都被吸進去，每具回 heal_per 最大生命
			"devour": {"radius": 8.0, "windup": 0.8, "recovery": 0.5, "heal_per": 0.02, "cooldown": 10.0, "min_bodies": 1},
		},
	},

	# 噬墓巨蟲（第 3 層 Boss，sim/enemies/grave_worm.gd，數值 Claude 暫定）：大部分時間在地底，冒出 surface.time 秒才打得到
	&"grave_worm": {
		"name": "噬墓巨蟲",
		"resists": {&"fire": -0.25, &"poison": 0.5},
		"visual": &"grave_worm",
		"behavior": &"grave_worm",
		"is_boss": true,
		"freeze_immune": true,
		"hit_color": Color("a8e04a"),
		"max_hp": 1100.0,
		"move_speed": 3.0,              # 巡邏時在地面上爬的速度；地底的速度在 tunnel.speed
		"speed_variance": 0.0,
		"turn_speed": 4.0,
		"radius": 1.1,
		"mass": 40.0,
		"knockback_mul": 0.0,           # 紮在地裡，推不動
		"spawn_time": 1.6,
		"spawn_shake": 0.4,
		"corpse_time": 3.5,
		"decide_delay": 0.4,            # 冒出來、每招之後至少這麼久才出下一招
		"first_cooldowns": {"acid": 0.5, "devour": 1.5, "eggs": 3.0},
		"patrol": {"speed_mul": 0.45, "pause": [1.0, 2.5], "sight_radius": 12.0, "sight_arc": deg_to_rad(120.0), "notice_radius": 4.0},
		"surface": {"time": 3.5},       # 每次冒出來在地面上停多久（出招中到時間，出完才鑽）
		"form_models": [&"grave_worm", &"moth_queen"],
		"form_names": ["噬墓巨蟲", "屍蛾女王"],
		# 結蛹：半血時原地縮成蛹 time 秒（打得到，受到的傷害 × damage_taken），破蛹變成屍蛾女王
		"transform": {"hp_threshold": 0.5, "time": 4.0, "damage_taken": 2.0, "shake": 0.5, "shake_duration": 0.5},
		# 屍蛾女王：會飛（只有投射物、跳起來腳離地 jump_reach 以上的攻擊打得到），每 land.interval 秒落地一次
		"moth": {
			"move_speed": 4.5, "turn_speed": 5.0, "decide_delay": 0.5,
			"knockback_mul": 0.12,
			"hover": [4.0, 7.0],          # 盤旋時跟目標保持的距離
			"altitude": 2.6,              # 畫面上飛多高（模擬的高度不變，夠不夠得到看 out_of_reach）
			"jump_reach": 0.5,
			"first_cooldowns": {"dust": 1.0, "gust": 2.0, "swoop": 3.0},
			# 鱗粉雲：空中停住、翅膀抖動掉粉（windup）→ 目標身邊 offset 的一圈上撒 clouds 團，每團 radius、time 秒；站在裡面視野縮成 vision
			"dust": {"windup": 0.6, "clouds": 3, "offset": 2.2, "radius": 2.5, "time": 6.0, "vision": 5.0, "recovery": 0.5, "cooldown": 10.0, "color": Color("c8b890")},
			# 俯衝：飛高、收翅、尖鳴（windup，前 track 比例跟著目標轉）→ 直線衝 length，路上 width 內擊倒
			"swoop": {
				"min_distance": 5.0, "windup": 0.7, "track": 0.7, "speed": 16.0, "length": 12.0, "width": 1.4,
				"damage": 26.0, "knockback": 12.0, "tier": &"knockdown", "recovery": 0.6, "cooldown": 6.0,
			},
			# 拍翅狂風：翅膀後張、身體後仰（windup）→ 前方扇形把人吹退 push_distance（擊退屬性照樣算）、吹散蛛網
			"gust": {"trigger_distance": 6.0, "windup": 0.6, "range": 7.0, "arc": deg_to_rad(90.0), "push_distance": 6.0, "damage": 6.0, "recovery": 0.5, "cooldown": 7.0},
			# 落地產卵：descend 秒降下來 → 落地 time 秒（近戰打得到），留 eggs 顆卵（孵化照 eggs 那一段）
			"land": {"interval": 12.0, "descend": 0.5, "time": 4.0, "eggs": 3, "egg_distance": 2.0},
		},
		# 地底追蹤：dive 秒鑽下去（還打得到）→ 在地底追 track_time 秒（到腳下 stop_distance 內就停）→ 停下、地面鼓起 warn 秒 → 衝出地面
		"tunnel": {
			"dive": 0.5, "speed": 7.5, "turn_rate": PI, "track_time": 2.0, "stop_distance": 0.5, "warn": 0.6,
			"radius": 3.0, "damage": 28.0, "knockback": 8.0, "knockup": 7.5, "shake": 0.6,
		},
		# 噴酸：頭後仰、喉嚨發綠光（windup）→ 3 個方向各吐一團，flight 秒後落在離自己 distance（照目標的距離、夾在這個範圍）的地方，留酸池
		"acid": {
			"min_distance": 3.0, "windup": 0.7, "lobs": 3, "spread": deg_to_rad(40.0), "distance": [3.0, 8.0], "flight": 0.7,
			"radius": 1.8, "damage": 14.0, "pool_time": 4.0, "pool_dps": 8.0, "recovery": 0.5, "cooldown": 5.0, "color": Color("a8e04a"),
		},
		# 吞噬：嘴巴張開（windup）→ 吸 pull_time 秒，前方 arc、radius 內的人被拉過來（翻滾中不被拉），拉到嘴邊咬一口
		"devour": {
			"trigger_distance": 7.0, "windup": 0.5, "pull_time": 1.2, "radius": 7.0, "arc": deg_to_rad(90.0), "pull_speed": 5.0,
			"bite_reach": 0.8, "damage": 40.0, "knockback": 14.0, "recovery": 0.6, "cooldown": 7.0,
		},
		# 產卵：尾巴翹起（windup）→ 身後留 count 顆卵，hatch_time 秒後每顆孵 per_egg 隻（自己孵的同時最多 max_alive 隻）
		"eggs": {
			"windup": 0.6, "count": 2, "spread": deg_to_rad(50.0), "distance": 2.5, "hatch_time": 4.0, "hatch": &"beetle", "per_egg": 2,
			"max_alive": 8, "recovery": 0.4, "cooldown": 9.0,
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


# 各層自己的小怪種類與比例（設計方向「各層怪物」）：地圖預放的怪群、挖墳怪潮用這一層的表，挖墳點噴的是下一層的表；
# 超過表的層數用最後一層的表。第 2 層起怪群與怪潮另有 UPPER_SHARE 的機率改抽上一層的表（挖墳點噴的不混）
# 持武器的腐屍（怪物圖鑑備註 1，數值 Claude 暫定）：武器種類 → 招式。技能冷卻好就用（冷卻 = 玩家耗魔 ÷ 5 的 2 倍，armed_skill_cooldown），
# 冷卻中用普攻；預兆（windup）至少 0.4 秒；傷害 = damage_pct × zombie.armed_damage（6）。招式的 type 決定做法（sim/enemies/armed_moves.gd）：
#   melee 揮擊：hits 每下 {range, arc, damage_pct, tier}，間隔 interval；shot 射擊：count 支、間隔 interval 或扇形 fan_arc；
#   shield 舉盾（正面 arc 擋下、結束時盾擊 bash）；burst 原地爆開；blink 黑煙後閃到背後；heal 治療周圍腐屍；breath 前方噴火；scoop 鏟起
# reach：目標在這以內才出這招；keep：遠程武器保持的距離 [近, 遠]；move_mul：移速倍率
const ARMED_ZOMBIE := {
	&"swordShield": {
		"name": "劍盾", "model": &"longsword", "offhand_model": &"woodShield",
		"attack": {"type": &"melee", "reach": 1.9, "windup": 0.45, "recovery": 0.5, "cooldown": 1.3,
			"hits": [{"range": 2.1, "arc": PI * 100.0 / 180.0, "damage_pct": 1.0, "tier": &"light"}]},
		"skill": {"type": &"shield", "reach": 7.0, "windup": 0.4, "duration": 2.5, "recovery": 0.3, "arc": PI * 100.0 / 180.0, "block_push": 0.3,
			"bash": {"range": 2.0, "arc": PI * 120.0 / 180.0, "damage_pct": 1.0, "knockback": 9.0, "tier": &"medium"}},
	},
	&"staff": {
		"name": "法杖", "model": &"staff", "keep": [5.0, 9.0],
		"attack": {"type": &"shot", "reach": 10.0, "windup": 0.5, "recovery": 0.5, "cooldown": 1.8, "count": 1, "speed": 7.0, "range": 12.0,
			"damage_pct": 1.2, "visual": &"orb", "damage_type": &"arcane", "color": Color("b98cff")},
		"skill": {"type": &"burst", "reach": 2.5, "windup": 0.8, "recovery": 0.6, "radius": 2.5, "damage_pct": 2.5, "damage_type": &"arcane",
			"tier": &"heavy", "knockback": 8.0, "color": Color("b98cff")},
	},
	&"shortbow": {
		"name": "短弓", "model": &"shortbow", "keep": [5.0, 9.0],
		"attack": {"type": &"shot", "reach": 10.0, "windup": 0.4, "recovery": 0.4, "cooldown": 1.6, "count": 3, "interval": 0.4, "speed": 14.0,
			"range": 14.0, "damage_pct": 0.6, "visual": &"arrow", "tier": &"light", "color": Color("e8d9a8")},
		"skill": {"type": &"shot", "reach": 9.0, "windup": 0.5, "recovery": 0.4, "count": 5, "fan_arc": PI * 50.0 / 180.0, "speed": 14.0,
			"range": 12.0, "damage_pct": 0.8, "visual": &"arrow", "tier": &"light", "color": Color("e8d9a8")},
	},
	&"longbow": {
		"name": "長弓", "model": &"longbow", "keep": [6.0, 11.0],
		"attack": {"type": &"shot", "reach": 12.0, "windup": 1.2, "recovery": 0.5, "cooldown": 2.5, "count": 1, "speed": 18.0, "range": 18.0,
			"damage_pct": 2.5, "knockback": 6.0, "visual": &"arrow", "tier": &"heavy", "color": Color("e8d9a8")},
		"skill": {"type": &"shot", "reach": 12.0, "windup": 0.8, "recovery": 0.5, "count": 1, "speed": 22.0, "range": 20.0, "pierce": true,
			"damage_pct": 2.5, "visual": &"arrow", "tier": &"heavy", "color": Color("ffd36b")},
	},
	&"dagger": {
		"name": "雙匕首", "model": &"dagger", "move_mul": 1.4,
		"attack": {"type": &"melee", "reach": 1.5, "windup": 0.4, "recovery": 0.4, "cooldown": 1.4, "interval": 0.15,
			"hits": [{"range": 1.7, "arc": PI * 70.0 / 180.0, "damage_pct": 0.4, "tier": &"light"}, {"range": 1.7, "arc": PI * 70.0 / 180.0, "damage_pct": 0.4, "tier": &"light"},
				{"range": 1.7, "arc": PI * 70.0 / 180.0, "damage_pct": 0.4, "tier": &"light"}, {"range": 1.7, "arc": PI * 70.0 / 180.0, "damage_pct": 0.4, "tier": &"light"},
				{"range": 1.7, "arc": PI * 70.0 / 180.0, "damage_pct": 0.4, "tier": &"light"}]},
		"skill": {"type": &"blink", "reach": 8.0, "windup": 0.5, "recovery": 0.2, "behind": 1.2},
	},
	&"scepter": {
		"name": "驅魔權杖", "model": &"scepter",
		"attack": {"type": &"melee", "reach": 1.9, "windup": 0.5, "recovery": 0.5, "cooldown": 1.6, "interval": 0.35, "damage_type": &"holy",
			"hits": [{"range": 2.1, "arc": PI * 110.0 / 180.0, "damage_pct": 1.0, "tier": &"medium"}, {"range": 2.1, "arc": PI * 110.0 / 180.0, "damage_pct": 1.0, "tier": &"medium"}]},
		"skill": {"type": &"heal", "reach": 99.0, "windup": 0.6, "recovery": 0.4, "radius": 5.0, "heal_ratio": 0.25, "below": 0.7, "color": Color("9be07a")},
	},
	&"torch": {
		"name": "火把", "model": &"torch",
		"attack": {"type": &"melee", "reach": 1.9, "windup": 0.4, "recovery": 0.5, "cooldown": 1.3, "damage_type": &"fire",
			"hits": [{"range": 2.1, "arc": PI * 100.0 / 180.0, "damage_pct": 1.0, "tier": &"light"}]},
		"skill": {"type": &"breath", "reach": 4.0, "windup": 0.5, "recovery": 0.5, "duration": 1.0, "tick": 0.25, "range": 4.0, "arc": PI * 60.0 / 180.0,
			"damage_pct": 0.6, "damage_type": &"fire", "tier": &"light", "color": Color("ff8a30")},
	},
	&"shovel": {
		"name": "鐵鏟", "model": &"shovel",
		"attack": {"type": &"melee", "reach": 3.2, "windup": 0.5, "recovery": 0.6, "cooldown": 1.6,
			"hits": [{"range": 3.6, "arc": PI * 25.0 / 180.0, "damage_pct": 1.2, "tier": &"medium"}]},
		# 鏟起：grab_range 內有別的怪 → 拋向玩家（膨脹屍優先、落地 bloater_fuse 秒就炸；其他怪落地 land_radius 內擊倒）；
		# 玩家在 player_range 內 → 鏟玩家，隨機拋飛（擊倒）或埋進地底 bury 秒
		"skill": {"type": &"scoop", "reach": 6.0, "windup": 0.4, "recovery": 0.5, "grab_range": 4.0, "player_range": 2.0, "flight": 0.6,
			"land_radius": 1.2, "land_pct": 1.5, "bloater_fuse": 0.3, "damage_pct": 1.0, "launch": 7.0, "bury": 1.0},
	},
}


const FLOOR_MIX := {
	1: {&"zombie": 0.7, &"hound": 0.2, &"bloater": 0.1},
	2: {&"grunt": 0.5, &"archer": 0.25, &"spearman": 0.125, &"bone_wheel": 0.125},
	3: {&"beetle": 0.625, &"spider": 0.25, &"hive": 0.125},   # 圖鑑 50 : 20 : 10；蟲巢只在怪群裡、每群最多 1 個（pack_max）
}
const UPPER_SHARE := 0.2

# 骷髏類（萬骨聚合體吞得掉的屍體）
const SKELETONS: Array[StringName] = [&"grunt", &"archer", &"spearman", &"bone_wheel", &"minion"]

static var _merged := {}   # def_of 合併過的資料（inherits）


# 這種怪的完整資料：有 inherits 的先拿被繼承的那種，再蓋上自己寫的欄位（同一層字典整個換掉）
static func def_of(type: StringName) -> Dictionary:
	var d: Dictionary = ENEMIES[type]
	if not d.has("inherits"):
		return d
	if not _merged.has(type):
		_merged[type] = def_of(d.inherits).merged(d, true)
	return _merged[type]


# 持武器腐屍的招式（ARMED_ZOMBIE 的 key 就是武器 id）
static func armed_kit(base: StringName) -> Dictionary:
	return ARMED_ZOMBIE[base]


static func has_armed_kit(base: StringName) -> bool:
	return ARMED_ZOMBIE.has(base)


# 持武器腐屍的技能冷卻：玩家用這把武器右鍵的「耗魔 ÷ 5」秒的 2 倍（怪物圖鑑備註 1）
static func armed_skill_cooldown(base: StringName) -> float:
	var special: Dictionary = WeaponDefs.WEAPONS.get(base, {}).get("special", {})
	return 2.0 * special.get("mana", 25) / 5.0


static func is_boss(type: StringName) -> bool:
	return def_of(type).get("is_boss", false)


static func floor_mix(floor_num: int) -> Dictionary:
	var last: int = FLOOR_MIX.keys().max()
	return FLOOR_MIX[clampi(floor_num, 1, last)]


# 照 floor_mix 的比例抽一種（用傳入的 rng，模擬才有決定性）；with_upper：第 2 層起 UPPER_SHARE 改抽上一層（第 1 層不多耗亂數）
# in_pack：是不是預先放好的怪群在抽。有 pack_max 的種類（蟲巢：不會動）只出現在怪群裡，怪潮與出口噴怪抽到就換成它的 pack_fallback；
# 怪群每群的上限由 Spawner._spawn_pack 另外數
static func roll_floor_type(floor_num: int, rng: RandomNumberGenerator, with_upper := true, in_pack := false) -> StringName:
	if with_upper and floor_num > 1 and rng.randf() < UPPER_SHARE:
		floor_num -= 1
	var mix := floor_mix(floor_num)
	var r := rng.randf()
	var acc := 0.0
	var pick: StringName = mix.keys()[0]
	for type: StringName in mix:
		pick = type
		acc += mix[type]
		if r < acc:
			break
	if not in_pack and ENEMIES[pick].has("pack_max"):
		pick = ENEMIES[pick].pack_fallback
	return pick
