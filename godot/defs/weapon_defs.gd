# 武器資料定義（照搬網頁版 legacy/src/weapons/weaponDefs.js，欄位改 snake_case）；邏輯在 sim/weapon_behaviors.gd
# 每把武器一個 base_damage 與 damage_type（StatDefs.DAMAGE_TYPES），招式用 damage_pct（基礎傷害的倍率，F1）；實際傷害見 Player.move_damage
# tags（TAGS）：技能的武器需求看這個（SkillDefs 的 needs）；spell_power：法術強度，跟 base_damage 同一個尺度的數字（還沒接進傷害，數字暫定）
# trigger_every：左鍵的命中袋、出手袋每幾下發動一次（BagTriggers._ready）
# 一次拿一把武器（沒有主手 / 副手）；offhand_model：左手也拿東西的武器（劍盾的盾、雙匕首的另一把），只給畫面
# grid：武器格子（Build 改版第 3 步，形狀 Claude 暫定），每列一個字串、每字一格：A 攻擊部位、E 末端、D 防禦部位、H 握柄、G 寶石座、. 沒有格子；
# （觸發袋改版後格子已經不用，留著給 grid_cells）
class_name WeaponDefs

const TAGS := {&"melee": "近戰", &"ranged": "遠程", &"shield": "盾", &"dagger": "匕首", &"shovel": "鏟", &"torch": "火把", &"bow": "弓", &"caster": "施法"}

const WEAPONS := {
	# 劍盾（守墓騎士的起始武器；許家慶 2026-11-05 拿掉主副手與長劍）：左鍵三段斬擊、右鍵格擋（格擋中左鍵招架）；模型右手劍、左手盾
	&"swordShield": {
		"id": &"swordShield",
		"name": "劍盾",
		"type": &"melee",
		"tags": [&"melee", &"shield"],
		"spell_power": 3.0,
		"base_damage": 8.0,         # 原本長劍的（普攻 + 蓄力突刺打一隻每秒照近戰目標，12 → 8）；蓄力突刺改成技能「突刺」
		"trigger_every": 2,          # 左鍵的命中袋 / 出手袋每 2 下發動一次（每秒打中約 2.4 下 → 約每秒 1 次，docs/平衡數字.md；許家慶 2026-11-05 取代機率，Claude 暫定）
		"max_mana": 120.0, "mana_regen": 5,   # 魔力照武器（許家慶 2026-11-04）：最大魔力與回魔 = 基準（基礎傷害 8：120、每秒 5）× 8 ÷ 白裝基礎傷害，技能的長時間輸出與爆發跟武器無關
		"damage_type": &"phys",
		"model": &"longsword",
		"offhand_model": &"woodShield",   # 左手拿的模型（只給畫面）
		"grid": ["..E..", ".AAA.", ".AAA.", ".AGA.", ".AAA.", "HHHHH", "..H..", "..G.."],
		"idle": {"arm_r": -0.35, "arm_l": -0.1, "tilt": 0.0},
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
			"finisher_mul": 1.75,      # 第三段傷害倍率（8 × 175% = 14：白裝每一下都是整數）
			"finisher_impact_mul": 1.8,   # 第三段擊退與命中停頓倍率
			"finisher_shake_mul": 2.5,
			"finisher_scale": 1.25,    # 第三段範圍與角度倍率
			"finisher_recovery_mul": 1.6,
			"hit_stop": 0.04,
			"shake": 0.08,
			"slash_color": Color.WHITE,                  # 揮砍弧光（網頁版 effects.slash）
			"slash_finisher_color": Color("ffe27a"),     # 第三段弧光
			"slash_shape": [[-0.7, 0.0, 1.0], [-0.45, 0.0, 1.0], [-PI / 2.0, -0.6, 0.75]],   # 每段弧光的 [傾斜, 上仰, 角度倍率]（只有畫面）
		},
		# 盾擊（許家慶 2026-11-06，取代按住格擋 + 左鍵招架：右鍵統一成「按一下放一招、耗魔、有傷害」）：
		# 往前推盾打 damage_pct；推盾的 active 期間（block_window 秒，× 招架判定時間）正面 block_arc 內的攻擊擋下 = 盾反（parry）
		"special": {
			"behavior": &"shieldBash",
			"name": "盾擊",
			"desc": "往前推盾 150%；推盾的 0.4 秒內擋下正面的攻擊就盾反 300% 並大幅擊退；耗魔 13。",
			"icon": "🛡",
			"mana": 13,                # 平衡表照功能型（格擋 + 盾反）算目標 × 0.5：12 時比 1.25、13 約 1.1（Claude 暫定；原本招架 20）
			"damage_pct": 1.5,         # 劍盾 8 × 150% = 12（原本招架沒擋到的盾擊）
			"range": 2.6,
			"arc": PI * 120.0 / 180.0,
			"knockback": 6.0,
			"windup": 0.05,
			"active": 0.4,             # = 格擋判定時間（block_window）；擋下一次盾反後照樣舉到結束（之後擋下的不再盾反）
			"block_window": 0.4,
			"recovery": 0.25,
			"move_speed_mul": 0.5,     # 推盾時移速減半
			"roll_cancel": true,       # 可以用翻滾提前結束
			"hit_stop": 0.05,
			"shake": 0.1,
			"block_arc": PI * 120.0 / 180.0,  # 正前方合計 120°（左右各 60°；v0.23.0 使用者決定，原本 75°）
			"block_knockback_mul": 0.3,   # 擋下時自己被推退的比例（不扣血）
			"sfx_block": "shieldBash",
			"sfx_parry": "hitHeavy",
			"parry": {
				"window": 0.2,                # 反擊架勢分支（Player._try_counter）用的判定時間
				"damage_pct": 3.0,             # 劍盾 8 × 300% = 24（原本固定 25，F1 使用者同意 24；基礎傷害調低時跟著拉高）
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
		"name": "法杖",
		"type": &"ranged",
		"tags": [&"ranged", &"caster"],
		"spell_power": 8.0,
		"base_damage": 8.0,
		"trigger_every": 2,          # 左鍵的命中袋 / 出手袋每 2 下發動一次（每秒打中約 1.7 下 → 約每秒 1 次，docs/平衡數字.md；許家慶 2026-11-05 取代機率，Claude 暫定）
		"max_mana": 120.0, "mana_regen": 5,   # 魔力照武器（許家慶 2026-11-04）：最大魔力與回魔 = 基準（基礎傷害 8：120、每秒 5）× 8 ÷ 白裝基礎傷害，技能的長時間輸出與爆發跟武器無關
		"damage_type": &"arcane",
		"model": &"staff",
		# 杖頭連成一塊（攻擊部位 16 格、放得下 2×2）、寶石座移到握柄兩側（使用者 2026-11-02：原本攻擊部位 12 格被寶石座切碎，2×2 放不進去）
		"grid": [".AAA.", "AAAAA", "AAAAA", ".AAA.", ".GHG.", ".HHH.", ".GHG.", ".HHH.", "..H..", "..H.."],
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
			"desc": "往準星丟出法球，落地爆炸（半徑 3.2）造成 350% 並擊退；耗魔 25。",
			"icon": "✺",
			"mana": 25,
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
		"name": "短弓",
		"type": &"ranged",
		"tags": [&"ranged", &"bow"],
		"spell_power": 5.0,
		"model": &"shortbow",
		"grid": [".AAAA", "AAA..", "AAG..", "HHHH.", "AAG..", "AAA..", ".AAAA"],
		"base_damage": 12.0,        # 使用者 2026-11-02 決定：短弓打一隻每秒是全武器最高、箭不穿透（打一群靠散射）；8 → 12（14 時連珠箭 × 0.75 不是整數）
		"trigger_every": 2,          # 左鍵的命中袋 / 出手袋每 2 下發動一次（每秒打中約 1.8 下 → 約每秒 1 次，docs/平衡數字.md；許家慶 2026-11-05 取代機率，Claude 暫定）
		"max_mana": 80.0, "mana_regen": 3.33,   # 魔力照武器（許家慶 2026-11-04）：最大魔力與回魔 = 基準（基礎傷害 8：120、每秒 5）× 8 ÷ 白裝基礎傷害，技能的長時間輸出與爆發跟武器無關
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
			"desc": "一次 5 支箭散開 50°，每支 350%；耗魔 25。",
			"icon": "bow_fan",
			"mana": 17,   # 照魔力倍率 × 8 ÷ 基礎傷害（原本 25）
			"damage_pct": 3.5,         # 6 單位外打一隻、打一群每隻都只中 1 支：一支就是目標；貼近時多中幾支
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
		"name": "長弓",
		"type": &"ranged",
		"tags": [&"ranged", &"bow"],
		"spell_power": 5.0,
		"model": &"longbow",
		"grid": [".AAAA", "AAA..", "AAA..", "AAG..", "HHHH.", "HHG..", "HHHH.", "AAG..", "AAA..", "AAA..", ".AAAA"],
		"base_damage": 12.0,        # 11 → 12（白裝每一下都是整數）
		"trigger_every": 2,          # 左鍵的命中袋 / 出手袋每 2 下發動一次（每秒打中約 1.4 下 → 約每秒 1 次，docs/平衡數字.md；許家慶 2026-11-05 取代機率，Claude 暫定）
		"max_mana": 80.0, "mana_regen": 3.33,   # 魔力照武器（許家慶 2026-11-04）：最大魔力與回魔 = 基準（基礎傷害 8：120、每秒 5）× 8 ÷ 白裝基礎傷害，技能的長時間輸出與爆發跟武器無關
		"damage_type": &"phys",
		"idle": {"arm_r": -0.4, "arm_l": 0.0, "tilt": 0.0},
		"attack": {
			"pierce_count": 2,         # 穿過 2 隻（第 3 隻打中才消失）：打一群照「武器強度」3~6 倍（設計方向）
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
			"desc": "按住蓄力、放開射出：150% → 400%（蓄滿 1 秒），穿過路上所有敵人；耗魔 30。",
			"icon": "bow_pierce",
			"mana": 20,   # 照魔力倍率 × 8 ÷ 基礎傷害（原本 30）
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


	# 雙匕首（竊影者的起始武器；許家慶 2026-11-05 拿掉主副手：匕首一律雙持，原本單拿的三連刺拿掉）：左鍵五連刺、右鍵影步；模型兩手各一把
	&"dagger": {
		"id": &"dagger",
		"name": "雙匕首",
		"type": &"melee",
		"tags": [&"melee", &"dagger"],
		"spell_power": 3.0,
		"model": &"dagger",
		"offhand_model": &"dagger",   # 左手也拿一把（只給畫面）
		"grid": [".E.", ".A.", "AAA", "AGA", "HHH", ".H."],
		"base_damage": 8.0,            # 2026-10-27 放慢後 5 → 9（雙持每秒傷害約 31.6 → 27.8）；2026-10-31 9 → 8（白裝每一下都是整數、打一隻照近戰目標）
		"trigger_every": 3,          # 左鍵的命中袋 / 出手袋每 3 下發動一次（每秒打中約 2.7 下 → 約每秒 1 次，docs/平衡數字.md；許家慶 2026-11-05 取代機率，Claude 暫定）
		"max_mana": 120.0, "mana_regen": 5,   # 魔力照武器（許家慶 2026-11-04）：最大魔力與回魔 = 基準（基礎傷害 8：120、每秒 5）× 8 ÷ 白裝基礎傷害，技能的長時間輸出與爆發跟武器無關
		"damage_type": &"phys",
		"idle": {"arm_r": -0.6, "arm_l": -0.6, "tilt": 0.0},
		# 五連刺：很快，第 5 下必爆擊、可擊退
		"attack": {
			"behavior": &"meleeSwing",
			"sfx": "swing", "sfx_heavy": "swingHeavy",
			"name": "五連刺",
			"desc": "刺刺、停、刺刺、停、重擊：每刺 125%，第 5 下 187.5% 必爆擊並擊退。",
			"icon": "dagger_combo",
			"damage_pct": 1.25,        # 許家慶 2026-11-05：高風險高傷害、打一隻可以比短弓高；100% → 125%（白裝 8 → 10，技能照基礎傷害 8 算不受影響）
			"combo_count": 5,          # 第 combo_count 下是終結技
			"range": 1.6,
			"arc": PI * 0.5,           # 90°
			# 節奏「刺刺─停─刺刺─停─重擊」（使用者 2026-10-27：原本 0.18 秒一下太快、沒節奏）；許家慶 2026-11-05 嫌慢，保留節奏、整體加快：
			# 一刺 0.3 → 0.22 秒，第 2、4 刺後多停 beat_pause 0.12 → 0.08；第 5 下前搖 finisher_windup 0.18 → 0.13、收招 finisher_recovery 0.35 → 0.25
			"windup": 0.07,
			"active": 0.04,
			"recovery": 0.11,
			"beat_pause": 0.08,
			"beat_steps": [1, 3],      # combo_step（0 起算）：第 2、4 刺
			"finisher_windup": 0.13,
			"finisher_recovery": 0.25,
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
			"desc": "瞬移到準星附近敵人的背後（6 單位內），背刺 300% 必爆擊；耗魔 25。",
			"icon": "shadow_step",
			"mana": 25,
			"miss_mana": 5,      # 沒有發動（沒怪 / 沒抓到）：只扣這麼多魔力，其他退回
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
		"name": "驅魔權杖",
		"type": &"melee",
		"tags": [&"melee", &"caster"],
		"spell_power": 10.0,
		"model": &"scepter",
		"grid": ["AAAAA", "AGAGA", "AAAAA", ".HHH.", "..H..", ".HHH.", "..H..", "..H.."],
		"base_damage": 10.0,
		"trigger_every": 2,          # 左鍵的命中袋 / 出手袋每 2 下發動一次（每秒打中約 1.7 下 → 約每秒 1 次，docs/平衡數字.md；許家慶 2026-11-05 取代機率，Claude 暫定）
		"max_mana": 96.0, "mana_regen": 4,   # 魔力照武器（許家慶 2026-11-04）：最大魔力與回魔 = 基準（基礎傷害 8：120、每秒 5）× 8 ÷ 白裝基礎傷害，技能的長時間輸出與爆發跟武器無關
		"damage_type": &"holy",
		"idle": {"arm_r": -0.4, "arm_l": -0.1, "tilt": 0.0},
		"attack": {
			"behavior": &"meleeSwing",
			"sfx": "swing", "sfx_heavy": "swingHeavy",
			"name": "聖光敲擊",
			"desc": "兩段：先斜揮 100%，再往前砸出一圈聖光（130%，圈內再 60%）。",
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
			"slash_shape": [[-0.7, 0.0, 1.0]],
		},
		"special": {
			"behavior": &"holyCircle",
			"sfx": "arcaneCast",
			"name": "聖光圈",
			"desc": "腳下放 4 秒的聖光圈（半徑 4）：隊友每秒回 4、亡靈每秒受到 120% 神聖傷害；耗魔 60。",
			"icon": "holy_circle",
			"mana": 48,   # 照魔力倍率 × 8 ÷ 基礎傷害（原本 60）
			"damage_pct": 1.2,         # 亡靈每秒受到 120%
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


	# 火把（F8，火把傭兵的起始武器）：功能型，普攻刻意偏低、打中點燃；右鍵直接往前噴火（許家慶 2026-11-06：拿掉準備姿態與插火把）
	&"torch": {
		"id": &"torch",
		"name": "火把",
		"type": &"melee",
		"tags": [&"melee", &"torch"],
		"spell_power": 8.0,
		"model": &"torch",
		"grid": ["AAA", "AAA", "AGA", "HHH", ".H.", ".H."],
		"base_damage": 12.0,        # 打一隻每秒照近戰目標，6 → 12
		"trigger_every": 2,          # 左鍵的命中袋 / 出手袋每 2 下發動一次（每秒打中約 2.3 下 → 約每秒 1 次，docs/平衡數字.md；許家慶 2026-11-05 取代機率，Claude 暫定）
		"max_mana": 80.0, "mana_regen": 3.33,   # 魔力照武器（許家慶 2026-11-04）：最大魔力與回魔 = 基準（基礎傷害 8：120、每秒 5）× 8 ÷ 白裝基礎傷害，技能的長時間輸出與爆發跟武器無關
		"damage_type": &"fire",
		"idle": {"arm_r": -0.5, "arm_l": -0.1, "tilt": 0.0},
		"light_radius": 6.0,           # 地上的火把（守墓人的提燈）照亮的半徑（Vision.lights）
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
			"slash_shape": [[-0.7, 0.0, 1.0]],
		},
		"special": {
			"behavior": &"fireBreath",
			"sfx": "explosion",
			"name": "噴火",
			"desc": "向前噴火（90°、長 5）125% 並點燃；耗魔 10。",
			"icon": "fire_breath",
			"mana": 10,   # 原本舉著時左鍵 125%、耗魔 20；改成右鍵後耗魔減半，傷害不加（火把普攻已到近戰目標，噴火再痛打一隻會超過雙匕首，平衡表的 KEEP）
			"damage_pct": 1.25,
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


	# 鐵鏟（F9，掘墓人的起始武器）：技能型，普攻慢又窄；右鍵鏟拋（許家慶 2026-11-06，取代「鏟起舉 2 秒、再選左鍵拋出 / 右鍵埋入」）：
	# 鏟起面前一隻非 Boss 敵人直接往準星拋出，被丟的怪與路上撞到的怪受傷、可擊退；埋入改成技能「活埋」（SkillDefs bury）
	&"shovel": {
		"id": &"shovel",
		"name": "鐵鏟",
		"type": &"melee",
		"tags": [&"melee", &"shovel"],
		"spell_power": 12.0,
		"model": &"shovel",
		"grid": ["AAAAA", "AAGAA", "AAAAA", ".AAA.", "..H..", "..H..", ".HHH.", "..H..", "..G.."],
		"base_damage": 30.0,        # 打一隻每秒照近戰目標，12 → 30（攻速慢）
		"trigger_every": 1,          # 左鍵的命中袋 / 出手袋每 1 下發動一次（每秒打中約 0.9 下 → 約每秒 1 次，docs/平衡數字.md；許家慶 2026-11-05 取代機率，Claude 暫定）
		"max_mana": 32.0, "mana_regen": 1.33,   # 魔力照武器（許家慶 2026-11-04）：最大魔力與回魔 = 基準（基礎傷害 8：120、每秒 5）× 8 ÷ 白裝基礎傷害，技能的長時間輸出與爆發跟武器無關
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
			"behavior": &"shovelFling",
			"sfx": "swingHeavy",
			"name": "鏟拋",
			"desc": "把面前一隻怪（Boss 除外）鏟起來往準星丟出 7 單位：路上的怪 150%、被丟的怪落地 200%；耗魔 9。",
			"icon": "shovel_throw",
			"mana": 9,   # 鏟起 + 拋出合成一招後照平衡表的右鍵目標調（13 時比 0.68）
			"miss_mana": 5,      # 沒有發動（沒怪 / 沒抓到）：只扣這麼多魔力，其他退回
			"reach": 2.0,              # 抓取距離（自己身體邊緣到怪身體邊緣）；屍犬牽制時停在中心距離 2.5 外，要搆得到
			"damage_pct": 2.0,     # 被丟的怪落地
			"path_damage_pct": 1.5,   # 路上撞到的怪
			"distance": 7.0,
			"flight_time": 0.6,    # 被丟的怪飛到落點的秒數（拋物線）；路上的怪在飛過時才被撞到
			"path_width": 0.8,
			"knockback": 10.0,
			"windup": 0.15,
			"active": 0.05,
			"recovery": 0.3,
			"move_speed_mul": 0.3,
			"color": Color("b89a6a"),
			"hit_stop": 0.06,
			"shake": 0.3,
		},
	},

}


# 招式的基礎傷害（不含屬性）= 武器基礎傷害 × 招式 %（F1）；weapon 是 WEAPONS 的一筆，move 是它的 attack / special / parry
static func move_base_damage(weapon: Dictionary, move: Dictionary) -> float:
	return weapon.base_damage * move.damage_pct


# 武器的招式資料（一次拿一把，許家慶 2026-11-05 拿掉主副手）；Player.weapon_id、快照的 P_WEAPON 就是 WEAPONS 的 id
static func def_of(id: StringName) -> Dictionary:
	return WEAPONS[id]


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
