# 武器資料定義（照搬網頁版 legacy/src/weapons/weaponDefs.js，欄位改 snake_case）；邏輯在 sim/weapon_behaviors.gd
# 每把武器一個 base_damage 與 damage_type（StatDefs.DAMAGE_TYPES），招式用 damage_pct（基礎傷害的倍率，F1）；實際傷害見 Player.move_damage
# hands：&"one" 單手（可以再拿副手）、&"two" 雙手（不能拿副手）、&"off" 只能當副手；offhand = true 的單手武器也能當副手
# 玩家手上的招式資料是主手＋副手組合出來的（def_of）：左鍵看主手，右鍵有副手時看副手
# grid：武器格子（Build 改版第 3 步，形狀 Claude 暫定），每列一個字串、每字一格：A 攻擊部位、E 末端、D 防禦部位、H 握柄、G 寶石座、. 沒有格子；
# 道具鑲在主手 / 副手的格子上才生效（Loadout）；部位決定發動時機在第 4 步
class_name WeaponDefs

const WEAPONS := {
	# 長劍（單手，守墓騎士的主手）：三段斬擊；沒有副手時右鍵蓄力突刺，拿木盾當副手時右鍵換成格擋（def_of）
	&"longsword": {
		"id": &"longsword",
		"name": "長劍",
		"type": &"melee",
		"hands": &"one",
		"base_damage": 12.0,
		"damage_type": &"phys",
		"model": &"longsword",
		"grid": ["..E..", ".AAA.", ".AAA.", ".AGA.", ".AAA.", "HHHHH", "..H..", "..G.."],
		"idle": {"arm_r": -0.35, "arm_l": 0.0, "tilt": 0.0},
		"attack": {
			"behavior": &"meleeSwing",
			"sfx": "swing", "sfx_heavy": "swingHeavy",
			"name": "斬擊",
			"desc": "三段連斬，第三下是終結技、收招比較久。",
			"icon": "⚔",
			"damage_pct": 1.0,
			"range": 2.3,
			"arc": PI * 0.65,
			"windup": 0.07,
			"active": 0.09,
			"recovery": 0.2,
			"knockback": 7.0,
			"lunge": 3.5,
			"move_speed_mul": 0.35,
			"combo_window": 0.35,      # 收招後多久內再出手可接下一段
			"finisher_mul": 1.8,       # 第三段傷害倍率
			"finisher_impact_mul": 1.8,   # 第三段擊退與命中停頓倍率
			"finisher_shake_mul": 2.5,
			"finisher_scale": 1.25,    # 第三段範圍與角度倍率
			"finisher_recovery_mul": 1.6,
			"hit_stop": 0.04,
			"shake": 0.08,
			"slash_color": Color.WHITE,                  # 揮砍弧光（網頁版 effects.slash）
			"slash_finisher_color": Color("ffe27a"),     # 第三段弧光
		},
		# 蓄力突刺（Claude 暫定）：按住蓄力（同長弓穿透箭的按住機制），放開往前衝刺，衝刺途中每步判定前方
		"special": {
			"behavior": &"chargedThrust",
			"sfx": "swing",
			"sfx_release": "swingHeavy",
			"name": "蓄力突刺",
			"desc": "按住蓄力（最多 0.8 秒）、放開往前衝 2 → 5 單位刺出 150% → 300%；冷卻 5 秒。",
			"icon": "sword_thrust",
			"cooldown": 5.0,
			"hold": true,
			"roll_cancel": true,
			"damage_pct": 1.5,         # 沒蓄力
			"full_damage_pct": 3.0,    # 蓄滿
			"charge_time": 0.8,
			"dash": 2.0,               # 衝刺距離：沒蓄力 → 蓄滿
			"full_dash": 5.0,
			"dash_time": 0.25,         # 放開後這麼久內每步判定前方（同一隻只打一次）
			"range": 1.6,
			"arc": PI * 0.5,
			"knockback": 8.0,
			"windup": 0.08,
			"active": 0.0,             # 放開右鍵就衝出去
			"recovery": 0.35,
			"move_speed_mul": 0.5,     # 蓄力中移速 ×0.5
			"hit_stop": 0.06,
			"shake": 0.15,
			"color": Color("ffe27a"),
		},
	},

	# 木盾（副手）：右鍵格擋、格擋中左鍵招架；招架的傷害用主手的基礎傷害（def_of 把 special 換進主手的招式）
	# 格擋與招架（v0.41.0 使用者決定）：按住右鍵格擋、放開就放下，沒有冷卻；格擋中按左鍵招架（有冷卻），判定時間內擋到攻擊 = 全額盾反，沒擋到 = 盾擊傷害減半
	&"woodShield": {
		"id": &"woodShield",
		"name": "木盾",
		"type": &"melee",
		"hands": &"off",
		"model": &"woodShield",
		"grid": [".DDD.", "DDGDD", "DDDDD", ".DDD."],
		"offhand_arm_l": -0.1,         # 拿在副手時左手的待機角度
		"special": {
			"behavior": &"shieldBlock",
			"name": "格擋",
			"desc": "按住舉盾，擋下正前方 120° 的攻擊；格擋中移速減半。",
			"icon": "🛡",
			"hold": true,              # 按住右鍵維持（InputCmd.BTN_SPECIAL_HELD）：active 期間右鍵按著或招架中就停在 active
			"windup": 0.05,            # 舉盾；按下就開始格擋
			"active": 0.0,             # 放開右鍵就進入收招
			"recovery": 0.15,
			"move_speed_mul": 0.5,     # 格擋時移速減半
			"roll_cancel": true,       # 可以用翻滾提前結束
			"block_arc": PI * 120.0 / 180.0,  # 正前方合計 120°（左右各 60°；v0.23.0 使用者決定，原本 75°）
			"block_knockback_mul": 0.3,   # 擋下時自己被推退的比例（不扣血）
			"sfx_block": "shieldBash",
			"sfx_parry": "hitHeavy",
			"parry": {
				"name": "招架",
				"icon": "parry",              # 格擋中技能欄左鍵那格換成這個圖示
				"desc": "格擋中按左鍵：0.2 秒內擋到攻擊就招架成功，盾擊 200% 並大幅擊退；冷卻 4 秒。",
				"window": 0.2,                # 按下左鍵後這麼久內擋到攻擊 = 招架成功（沿用原本完美格擋的 0.2 秒）
				"cooldown": 4.0,              # 從按下左鍵開始算（沿用原本格擋的 4 秒）
				"fail_damage_mul": 0.5,       # 判定時間結束都沒擋到：盾擊照樣打出，傷害與擊退 × 0.5（24 → 12）
				"damage_pct": 2.0,             # 200% = 24（原本固定 25，F1 使用者同意）
				"range": 3.5,                 # v0.23.0 使用者決定（原本 2.5 / 120°）
				"arc": PI * 180.0 / 180.0,
				"knockback": 14.0,
				"hit_stop": 0.08,
				"shake": 0.3,
				"color": Color("ffd36b"),   # 衝擊環與命中粒子（沿用網頁版盾擊的金色）
			},
		},
	},

	&"staff": {
		"id": &"staff",
		"hands": &"two",
		"name": "法杖",
		"type": &"ranged",
		"base_damage": 8.0,
		"damage_type": &"arcane",
		"model": &"staff",
		"grid": ["A.A.A", "AAGAA", "AGAGA", ".AGA.", "..H..", ".HHH.", ".HHH.", "..H..", ".HHH.", "..H..", "..H.."],
		"idle": {"arm_r": -0.5, "arm_l": 0.0, "tilt": 0.0},
		"attack": {
			"behavior": &"fireBolt",
			"sfx": "fireBolt",
			"name": "魔彈",
			"desc": "射出秘術魔彈，射程 14、不擊退。",
			"icon": "✦",
			"damage_pct": 1.0,
			"projectile_speed": 20.0,
			"projectile_radius": 0.22,
			"spawn_offset": 0.6,       # 投射物出生點在玩家前方的距離
			"range": 14.0,
			# v0.27.0 使用者決定：法杖像法師，普攻不是重點 → 攻速減半（0.28 → 0.56 秒一發）；遠程武器的普攻不擊退、不讓怪物受擊硬直
			"knockback": 0.0,
			"no_stagger": true,
			"windup": 0.12,
			"active": 0.04,
			"recovery": 0.4,
			"move_speed_mul": 0.8,
			"color": Color("7fd8ff"),
			"hit_stop": 0.02,
			"shake": 0.04,
		},
		"special": {
			"behavior": &"arcaneBurst",
			"sfx": "arcaneCast",
			"name": "奧術爆裂",
			"desc": "往準星丟出法球，落地爆炸（半徑 3.2）造成 350% 並擊退；冷卻 5 秒。",
			"icon": "✺",
			"cooldown": 5.0,
			"projectile_speed": 16.0,
			"projectile_radius": 0.45,
			"spawn_offset": 0.6,
			"min_range": 2.0,
			"range": 12.0,
			"explosion_radius": 3.2,
			"damage_pct": 3.5,
			"knockback": 13.0,
			"windup": 0.35,
			"active": 0.02,
			"recovery": 0.25,
			"move_speed_mul": 0.4,
			"color": Color("c77dff"),
			"hit_stop": 0.08,
			"shake": 0.4,
		},
	},

	# 短弓（F4，盜墓遊俠的起始武器）：輕型遠程，普攻不擊退、不讓怪硬直；右鍵扇形散射 5 支（不擊退）
	&"shortbow": {
		"id": &"shortbow",
		"hands": &"two",
		"name": "短弓",
		"type": &"ranged",
		"model": &"shortbow",
		"grid": [".AAAA", "AAA..", "AAG..", "HHHH.", "AAG..", "AAA..", ".AAAA"],
		"base_damage": 6.0,
		"damage_type": &"phys",
		"idle": {"arm_r": -0.4, "arm_l": 0.0, "tilt": 0.0},
		"attack": {
			"behavior": &"fireBolt",
			"sfx": "arrowShot",
			"name": "快射",
			"desc": "0.35 秒一箭、不擊退；箭袋 6 支，最後一支是 200% 的重箭，射空要裝填 1.2 秒（翻滾瞬間補滿）。",
			"icon": "bow_shot",
			"damage_pct": 1.0,
			# 箭袋（使用者 2026-10-27：原本按住就一直射太無腦）：6 支射完自動裝填 1.2 秒（移速 ×0.5、不能射），翻滾瞬間補滿；
			# 最後一支是重箭：多拉弓 0.15 秒、200%、小擊退。節奏「射射射射射─碰─翻滾或裝填」
			"quiver": 6,
			"reload_time": 1.2,
			"reload_move_mul": 0.5,
			"heavy_last": {"damage_pct": 2.0, "extra_windup": 0.15, "knockback": 4.0, "color": Color("ffd36b")},
			"visual": &"arrow",
			"projectile_speed": 24.0,
			"projectile_radius": 0.2,
			"spawn_offset": 0.6,
			"range": 16.0,
			"knockback": 0.0,
			"no_stagger": true,
			"windup": 0.08,            # 三段合計 0.35 秒一發
			"active": 0.03,
			"recovery": 0.24,
			"move_speed_mul": 0.8,
			"color": Color("e8d9a8"),
			"hit_stop": 0.02,
			"shake": 0.03,
		},
		"special": {
			"behavior": &"arrowFan",
			"sfx": "arrowShot",
			"name": "散射",
			"desc": "一次 5 支箭散開 50°，每支 80%；冷卻 5 秒。",
			"icon": "bow_fan",
			"cooldown": 5.0,
			"damage_pct": 0.8,
			"count": 5,
			"fan_arc": PI * 50.0 / 180.0,
			"visual": &"arrow",
			"projectile_speed": 24.0,
			"projectile_radius": 0.2,
			"spawn_offset": 0.6,
			"range": 12.0,
			"knockback": 0.0,
			"no_stagger": true,
			"windup": 0.15,
			"active": 0.03,
			"recovery": 0.2,
			"move_speed_mul": 0.5,
			"color": Color("e8d9a8"),
			"hit_stop": 0.02,
			"shake": 0.08,
		},
	},


	# 長弓（F5，只從怪物身上掉）：重型遠程，攻速慢、普攻可擊退；右鍵按住蓄力、放開射出穿透一直線的箭
	&"longbow": {
		"id": &"longbow",
		"hands": &"two",
		"name": "長弓",
		"type": &"ranged",
		"model": &"longbow",
		"grid": [".AAAA", "AAA..", "AAA..", "AAG..", "HHHH.", "HHG..", "HHHH.", "AAG..", "AAA..", "AAA..", ".AAAA"],
		"base_damage": 11.0,
		"damage_type": &"phys",
		"idle": {"arm_r": -0.4, "arm_l": 0.0, "tilt": 0.0},
		"attack": {
			"behavior": &"fireBolt",
			"sfx": "arrowShot",
			"name": "重射",
			"desc": "0.7 秒一發的重箭，射程 18、會擊退。",
			"icon": "bow_heavy",
			"damage_pct": 1.0,
			"visual": &"arrow",
			"projectile_speed": 26.0,
			"projectile_radius": 0.22,
			"spawn_offset": 0.6,
			"range": 18.0,
			"knockback": 8.0,          # 重型遠程：普攻可擊退（設計方向「職業與武器手感」）
			"windup": 0.22,            # 三段合計 0.7 秒一發
			"active": 0.04,
			"recovery": 0.44,
			"move_speed_mul": 0.7,
			"color": Color("f0e0b0"),
			"hit_stop": 0.04,
			"shake": 0.06,
		},
		"special": {
			"behavior": &"chargedShot",
			"sfx": "bowDraw",
			"sfx_release": "arrowShot",
			"name": "穿透箭",
			"desc": "按住蓄力、放開射出：150% → 400%（蓄滿 1 秒），穿過路上所有敵人；冷卻 6 秒。",
			"icon": "bow_pierce",
			"cooldown": 6.0,
			"hold": true,              # 按住右鍵蓄力（同格擋的按住機制），放開射出
			"roll_cancel": true,
			"damage_pct": 1.5,         # 沒蓄力
			"full_damage_pct": 4.0,    # 蓄滿
			"charge_time": 1.0,
			"pierce": true,
			"visual": &"arrow",
			"projectile_speed": 30.0,
			"projectile_radius": 0.3,
			"spawn_offset": 0.6,
			"range": 20.0,
			"knockback": 10.0,
			"windup": 0.1,
			"active": 0.0,             # 放開右鍵就射出
			"recovery": 0.2,
			"move_speed_mul": 0.5,     # 蓄力中移速 ×0.5
			"color": Color("ffe9a0"),
			"hit_stop": 0.05,
			"shake": 0.15,
		},
	},


	# 匕首（單手，也能當副手；竊影者主手、副手各一把）：單拿是三連刺；主副手都是匕首（雙持）時左鍵換成 dual_attack 五連刺（def_of）
	# 右鍵影步：單拿時是主手自己的右鍵，當副手時副手的右鍵也是影步
	&"dagger": {
		"id": &"dagger",
		"name": "匕首",
		"type": &"melee",
		"hands": &"one",
		"offhand": true,               # 也能拿在副手
		"model": &"dagger",
		"grid": [".E.", ".A.", "AAA", "AGA", "HHH", ".H."],
		"base_damage": 9.0,            # 2026-10-27 放慢後 5 → 9（雙持每秒傷害約 31.6 → 27.8）
		"damage_type": &"phys",
		"idle": {"arm_r": -0.6, "arm_l": 0.0, "tilt": 0.0},
		"offhand_arm_l": -0.6,
		# 單拿（Claude 暫定）：刺、刺、重刺，一刺 0.3 秒，第 3 下 120% 並擊退
		"attack": {
			"behavior": &"meleeSwing",
			"sfx": "swing", "sfx_heavy": "swingHeavy",
			"name": "三連刺",
			"desc": "刺、刺、重刺：第 3 下 120% 並擊退。",
			"icon": "dagger_stab",
			"damage_pct": 1.0,
			"combo_count": 3,
			"range": 1.6,
			"arc": PI * 0.5,
			"windup": 0.1,
			"active": 0.05,
			"recovery": 0.15,
			"knockback": 0.0,
			"finisher_knockback": 6.0,
			"finisher_only_stagger": true,   # 前兩下不讓怪受擊硬直
			"lunge": 1.5,
			"move_speed_mul": 0.6,
			"combo_window": 0.35,
			"finisher_mul": 1.2,
			"finisher_impact_mul": 1.2,
			"finisher_shake_mul": 1.5,
			"finisher_scale": 1.2,
			"finisher_recovery_mul": 1.3,
			"hit_stop": 0.03,
			"shake": 0.05,
			"slash_color": Color("c8d0e0"),
			"slash_finisher_color": Color("9aa3ff"),
		},
		# 雙持：很快的五連刺，第 5 下必爆擊、可擊退
		"dual_attack": {
			"behavior": &"meleeSwing",
			"sfx": "swing", "sfx_heavy": "swingHeavy",
			"name": "五連刺",
			"desc": "刺刺、停、刺刺、停、重擊：第 5 下 150% 必爆擊並擊退。",
			"icon": "dagger_combo",
			"damage_pct": 1.0,
			"combo_count": 5,          # 第 combo_count 下是終結技
			"range": 1.6,
			"arc": PI * 0.5,           # 90°
			# 節奏「刺刺─停─刺刺─停─重擊」（使用者 2026-10-27：原本 0.18 秒一下太快、沒節奏）：一刺 0.3 秒，
			# 第 2、4 刺後多停 beat_pause；第 5 下前搖 finisher_windup（蓄一下）、收招 finisher_recovery，一輪約 2.0 秒
			"windup": 0.1,
			"active": 0.05,
			"recovery": 0.15,
			"beat_pause": 0.12,
			"beat_steps": [1, 3],      # combo_step（0 起算）：第 2、4 刺
			"finisher_windup": 0.18,
			"finisher_recovery": 0.35,
			"knockback": 0.0,          # 前 4 下不擊退
			"finisher_knockback": 9.0, # 第 5 下可擊退
			"finisher_only_stagger": true,   # 前 4 下也不讓怪受擊硬直（2026-10-27 使用者：停下後仰看起來像被擊退）
			"finisher_crit": true,     # 第 5 下必爆擊
			"lunge": 1.5,
			"move_speed_mul": 0.6,
			"combo_window": 0.35,
			"finisher_mul": 1.5,
			"finisher_impact_mul": 1.5,
			"finisher_shake_mul": 2.0,
			"finisher_scale": 1.4,     # 重擊往前衝得更遠、範圍更大
			"finisher_recovery_mul": 1.0,   # 用 finisher_recovery
			"hit_stop": 0.03,
			"shake": 0.05,
			"slash_color": Color("c8d0e0"),
			"slash_finisher_color": Color("9aa3ff"),
		},
		"special": {
			"behavior": &"shadowStep",
			"sfx": "swingHeavy",
			"name": "影步",
			"desc": "瞬移到準星附近敵人的背後（6 單位內），背刺 300% 必爆擊；冷卻 5 秒。",
			"icon": "shadow_step",
			"cooldown": 5.0,
			"miss_cooldown": 1.0,      # 6 單位內沒有怪：不瞬移，冷卻只算這麼久
			"damage_pct": 3.0,         # 背刺必爆擊
			"range": 6.0,
			"knockback": 0.0,
			"windup": 0.06,
			"active": 0.04,
			"recovery": 0.18,
			"move_speed_mul": 0.0,
			"color": Color("9aa3ff"),
			"hit_stop": 0.06,
			"shake": 0.2,
		},
	},


	# 驅魔權杖（F7，驅魔神官的起始武器）：神聖近戰敲擊（可擊退）；右鍵腳下聖光圈 4 秒，隊友回血、亡靈（所有怪物）受傷
	&"scepter": {
		"id": &"scepter",
		"hands": &"two",
		"name": "驅魔權杖",
		"type": &"melee",
		"model": &"scepter",
		"grid": ["AAAAA", "AGAGA", "AAAAA", ".HHH.", "..H..", ".HHH.", "..H..", "..H.."],
		"base_damage": 10.0,
		"damage_type": &"holy",
		"idle": {"arm_r": -0.4, "arm_l": -0.1, "tilt": 0.0},
		"attack": {
			"behavior": &"meleeSwing",
			"sfx": "swing", "sfx_heavy": "swingHeavy",
			"name": "聖光敲擊",
			"desc": "兩段：先橫掃 100%，再往前砸出一圈聖光（130%，圈內再 60%）。",
			"icon": "mace_smash",
			"damage_pct": 1.0,
			# 兩段「敲─砸」（使用者 2026-10-27：每一下都一樣太無腦）：第 2 下蓄一下再砸，扇形 130%，
			# 並在前方 finisher_burst.offset 處砸出半徑 radius 的聖光圈（再 60%、擊退）
			"combo_count": 2,
			"finisher_windup": 0.22,
			"finisher_recovery": 0.35,
			"finisher_burst": {"offset": 1.6, "radius": 2.0, "damage_pct": 0.6, "knockback": 10.0, "color": Color("fff0b0")},
			"range": 2.6,
			"arc": PI * 150.0 / 180.0,
			"windup": 0.12,            # 三段合計 0.45 秒一下
			"active": 0.08,
			"recovery": 0.25,
			"knockback": 8.0,
			"lunge": 2.0,
			"move_speed_mul": 0.4,
			"combo_window": 0.35,
			"finisher_mul": 1.3,
			"finisher_impact_mul": 1.25,
			"finisher_shake_mul": 2.0,
			"finisher_scale": 1.0,
			"finisher_recovery_mul": 1.0,   # 用 finisher_recovery
			"hit_stop": 0.05,
			"shake": 0.08,
			"slash_color": Color("fff0b0"),
			"slash_finisher_color": Color("ffe27a"),
		},
		"special": {
			"behavior": &"holyCircle",
			"sfx": "arcaneCast",
			"name": "聖光圈",
			"desc": "腳下放 4 秒的聖光圈（半徑 4）：隊友每秒回 4、亡靈每秒受到 60% 神聖傷害；冷卻 12 秒。",
			"icon": "holy_circle",
			"cooldown": 12.0,
			"damage_pct": 0.6,         # 亡靈每秒受到 60%
			"heal_per_sec": 4.0,       # 隊友（含自己）每秒回血
			"radius": 4.0,
			"duration": 4.0,
			"windup": 0.25,
			"active": 0.05,
			"recovery": 0.25,
			"move_speed_mul": 0.3,
			"color": Color("fff0b0"),
		},
	},


	# 火把（F8，火把傭兵的起始武器）：功能型，普攻刻意偏低、打中點燃；按住右鍵舉起火把（放開、翻滾、跳躍就放下），
	# 舉著時左鍵換成 stance 的噴火；插火把是技能欄的技能（slot_skill，放第一個空格，次數記在武器上）。
	# 舉著的與插著的火把都照亮周圍、全隊看得到（Vision.lights）。2026-10-27 使用者改：原本右鍵按一下進入姿態、姿態中左鍵插火把、右鍵噴火
	&"torch": {
		"id": &"torch",
		"hands": &"one",
		"name": "火把",
		"type": &"melee",
		"model": &"torch",
		"grid": ["AAA", "AAA", "AGA", "HHH", ".H.", ".H."],
		"base_damage": 6.0,
		"damage_type": &"fire",
		"idle": {"arm_r": -0.5, "arm_l": -0.1, "tilt": 0.0},
		"light_radius": 6.0,           # 舉著 / 插著的火把照亮的半徑
		"slot_skill": &"plantTorch",   # 自帶的技能：出廠就鑲在第一個寶石座（WeaponDropDefs.add_builtin_skill）
		"attack": {
			"behavior": &"meleeSwing",
			"sfx": "swing", "sfx_heavy": "swing",
			"name": "火把揮擊",
			"desc": "揮動火把 100% 並點燃：3 秒內每秒 15%。",
			"icon": "torch_swing",
			"damage_pct": 1.0,
			"combo_count": 1,
			"burn": {"pct_per_sec": 0.15, "duration": 3.0},   # 點燃：每秒 15% × 3 秒（持續傷害不觸發道具）
			"range": 2.0,
			"arc": PI * 0.6,
			"windup": 0.1,             # 三段合計 0.4 秒一下
			"active": 0.07,
			"recovery": 0.23,
			"knockback": 6.0,
			"lunge": 1.5,
			"move_speed_mul": 0.5,
			"combo_window": 0.3,
			"finisher_mul": 1.0,
			"finisher_impact_mul": 1.0,
			"finisher_shake_mul": 1.0,
			"finisher_scale": 1.0,
			"finisher_recovery_mul": 1.0,
			"hit_stop": 0.04,
			"shake": 0.06,
			"slash_color": Color("ffb040"),
			"slash_finisher_color": Color("ffb040"),
		},
		"special": {
			"behavior": &"torchStance",
			"sfx": "arcaneCast",
			"name": "準備姿態",
			"desc": "按住舉起火把（移速 ×0.6），放開放下；舉著時左鍵噴火。",
			"icon": "torch_raise",
			"windup": 0.1,
			"active": 0.02,
			"recovery": 0.1,
			"move_speed_mul": 0.6,
		},
		"stance": {
			"move_speed_mul": 0.6,     # 舉著火把時的移速
			"attack": {
				"behavior": &"fireBreath",
				"sfx": "explosion",
				"name": "噴火",
				"desc": "舉著火把時向前噴火（90°、長 5）120% 並點燃；冷卻 6 秒。",
				"icon": "fire_breath",
				"cooldown": 6.0,
				"cd_key": "player.breath",   # 左鍵的招式但有冷卻：自己一個冷卻，不占右鍵的 player.special
				"damage_pct": 1.2,
				"burn": {"pct_per_sec": 0.15, "duration": 3.0},
				"range": 5.0,
				"arc": PI * 0.5,       # 90°
				"knockback": 0.0,
				"windup": 0.2,
				"active": 0.1,
				"recovery": 0.25,
				"move_speed_mul": 0.3,
				"color": Color("ff8a30"),
				"hit_stop": 0.04,
				"shake": 0.2,
			},
		},
	},


	# 鐵鏟（F9，掘墓人的起始武器）：技能型，普攻慢又窄；右鍵鏟起貼在面前的一隻非 Boss 敵人舉著 2 秒（不用一直按），
	# 舉著時左右鍵換成 grab 的招式：左鍵拋出（被丟的怪與路上撞到的怪受傷、可擊退）、右鍵埋進土裡（暈 1.5 秒 + 0.5 秒爬出）；2 秒內都沒按就掙脫
	&"shovel": {
		"id": &"shovel",
		"hands": &"two",
		"name": "鐵鏟",
		"type": &"melee",
		"model": &"shovel",
		"grid": ["AAAAA", "AAGAA", "AAAAA", ".AAA.", "..H..", "..H..", ".HHH.", "..H..", "..G.."],
		"base_damage": 12.0,
		"damage_type": &"phys",
		"idle": {"arm_r": -0.4, "arm_l": -0.5, "tilt": 0.0},
		"attack": {
			"behavior": &"meleeSwing",
			"sfx": "swingHeavy", "sfx_heavy": "swingHeavy",
			"name": "鏟地",
			"desc": "往前鏟一下，範圍窄、長 3.6，會擊退。",
			"icon": "shovel_dig",
			"damage_pct": 1.0,
			"combo_count": 1,
			"range": 3.6,              # 打得比較遠（像把一排土鏟出去）
			"arc": PI * 40.0 / 180.0,  # 只打前方窄角度
			"windup": 0.38,            # 三段合計 1.0 秒一下（2026-10-27 使用者：0.8 秒還太快）
			"active": 0.1,
			"recovery": 0.52,
			"knockback": 9.0,
			"lunge": 1.0,
			"move_speed_mul": 0.4,
			"combo_window": 0.3,
			"finisher_mul": 1.0,
			"finisher_impact_mul": 1.0,
			"finisher_shake_mul": 1.0,
			"finisher_scale": 1.0,
			"finisher_recovery_mul": 1.0,
			"hit_stop": 0.06,
			"shake": 0.1,
			"slash_color": Color("b89a6a"),
			"slash_finisher_color": Color("b89a6a"),
		},
		"special": {
			"behavior": &"shovelGrab",
			"sfx": "shieldBash",
			"name": "鏟起",
			"desc": "把面前一隻怪（Boss 除外）鏟起來舉 2 秒，之後左鍵拋出、右鍵埋入；冷卻 10 秒。",
			"icon": "shovel_grab",
			"cooldown": 10.0,
			"miss_cooldown": 2.0,      # 沒抓到：冷卻只算這麼久
			"reach": 1.4,              # 抓取距離（自己身體邊緣到怪身體邊緣）
			"hold_time": 2.0,          # 舉著這麼久沒按就掙脫
			"windup": 0.12,
			"active": 0.05,
			"recovery": 0.15,
			"move_speed_mul": 0.3,
		},
		"grab": {
			"move_speed_mul": 0.7,     # 舉著怪時的移速
			"attack": {
				"behavior": &"shovelThrow",
				"sfx": "swingHeavy",
				"name": "拋出",
				"desc": "把舉著的怪往準星丟出 7 單位：路上的怪 150%、被丟的怪落地 200%。",
				"icon": "shovel_throw",
				"damage_pct": 2.0,     # 被丟的怪落地
				"path_damage_pct": 1.5,   # 路上撞到的怪
				"distance": 7.0,
				"flight_time": 0.6,    # 被丟的怪飛到落點的秒數（拋物線）；路上的怪在飛過時才被撞到
				"path_width": 0.8,
				"knockback": 10.0,
				"windup": 0.12,
				"active": 0.05,
				"recovery": 0.25,
				"move_speed_mul": 0.3,
				"color": Color("b89a6a"),
				"hit_stop": 0.06,
				"shake": 0.3,
			},
			"special": {
				"behavior": &"shovelBury",
				"sfx": "bossSlam",
				"name": "埋入",
				"desc": "把舉著的怪埋進土裡 80%，2 秒不能動也不能出招。",
				"icon": "shovel_bury",
				"damage_pct": 0.8,
				"stun": 1.5,
				"crawl": 0.5,
				"windup": 0.15,
				"active": 0.05,
				"recovery": 0.25,
				"move_speed_mul": 0.0,
				"color": Color("6a5236"),
				"hit_stop": 0.06,
				"shake": 0.25,
			},
		},
	},

}


# 招式的基礎傷害（不含屬性）= 武器基礎傷害 × 招式 %（F1）；weapon 是 WEAPONS 的一筆，move 是它的 attack / special / parry
static func move_base_damage(weapon: Dictionary, move: Dictionary) -> float:
	return weapon.base_damage * move.damage_pct


const COMBO_SEP := "+"
static var _combos := {}   # 組合 id → 組合後的招式資料（def_of 的快取）


# 主手＋副手的組合 id：沒有副手就是主手的 id，有就是「主手+副手」（Player.weapon_id、快照的 P_WEAPON）
static func combo_id(main: StringName, off: StringName) -> StringName:
	return main if off == &"" else StringName(String(main) + COMBO_SEP + String(off))


# 拿得動嗎：主手不能放只能當副手的（盾），副手只能放 hands = off 或 offhand = true 的，主手是雙手時不能有副手
static func can_hold(main: StringName, off: StringName) -> bool:
	if main == &"" or WEAPONS[main].hands == &"off":
		return false
	if off == &"":
		return true
	var o: Dictionary = WEAPONS[off]
	return WEAPONS[main].hands != &"two" and (o.hands == &"off" or o.get("offhand", false))


# 玩家手上的招式資料（組合 id 或單一武器 id）：主手的資料為底，有副手時右鍵換成副手的右鍵、左手待機角度換成副手的；
# 主副手都是同一種、而且有 dual_attack（匕首）時左鍵換成雙持招式。結果快取，同一個組合每次拿到同一個 Dictionary
static func def_of(id: StringName) -> Dictionary:
	if WEAPONS.has(id):
		return WEAPONS[id]
	if _combos.has(id):
		return _combos[id]
	var parts := String(id).split(COMBO_SEP)
	var main: Dictionary = WEAPONS[StringName(parts[0])]
	var off: Dictionary = WEAPONS[StringName(parts[1])]
	var d := main.duplicate()
	d.id = id
	d.name = "%s＋%s" % [main.name, off.name]
	d.offhand_model = off.model
	d.special = off.special
	d.idle = {"arm_r": main.idle.arm_r, "arm_l": off.offhand_arm_l, "tilt": main.idle.tilt}
	if main.id == off.id and main.has("dual_attack"):
		d.attack = main.dual_attack
	_combos[id] = d
	return d


const PARTS := {"A": "攻擊部位", "E": "末端", "D": "防禦部位", "H": "握柄", "G": "寶石座"}
static var _grids := {}   # 武器 id → { 格子 Vector2i: 部位字元 }（grid_cells 的快取）


# 武器格子有哪些格、各是什麼部位：{ Vector2i(x, y): "A" / "E" / "D" / "H" / "G" }
static func grid_cells(id: StringName) -> Dictionary:
	if _grids.has(id):
		return _grids[id]
	var out := {}
	var rows: Array = WEAPONS[id].grid
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] != ".":
				out[Vector2i(x, y)] = row[x]
	_grids[id] = out
	return out


# 武器格子的外框大小（最寬那列 × 列數）
static func grid_size(id: StringName) -> Vector2i:
	var rows: Array = WEAPONS[id].grid
	var w := 0
	for row: String in rows:
		w = maxi(w, row.length())
	return Vector2i(w, rows.size())
