# 武器資料定義（照搬網頁版 legacy/src/weapons/weaponDefs.js，欄位改 snake_case）；邏輯在 sim/weapon_behaviors.gd
# 每把武器一個 base_damage 與 damage_type（&"phys" / &"magic"），招式用 damage_pct（基礎傷害的倍率，F1）；實際傷害見 Player.move_damage
class_name WeaponDefs

const WEAPONS := {
	&"swordShield": {
		"id": &"swordShield",
		"name": "劍盾",
		"type": &"melee",
		"base_damage": 12.0,
		"damage_type": &"phys",
		"model": &"swordShield",
		"idle": {"arm_r": -0.35, "arm_l": -0.1, "tilt": 0.0},
		"attack": {
			"behavior": &"meleeSwing",
			"sfx": "swing", "sfx_heavy": "swingHeavy",
			"name": "斬擊",
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
		# 格擋與招架（v0.41.0 使用者決定，取代 v0.18.0 的「按一下維持 3 秒、剛舉盾擋下 = 完美格擋」）：
		# 按住右鍵格擋、放開就放下，沒有冷卻；格擋中按左鍵招架（有冷卻），判定時間內擋到攻擊 = 全額盾反，沒擋到 = 盾擊傷害減半
		"special": {
			"behavior": &"shieldBlock",
			"name": "格擋",
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
				"name": "招架",               # 格擋中技能欄左鍵那格顯示這兩個字
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
		"name": "法杖",
		"type": &"ranged",
		"base_damage": 8.0,
		"damage_type": &"magic",
		"model": &"staff",
		"idle": {"arm_r": -0.5, "arm_l": 0.0, "tilt": 0.0},
		"attack": {
			"behavior": &"fireBolt",
			"sfx": "fireBolt",
			"name": "魔彈",
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
}


# 招式的基礎傷害（不含屬性）= 武器基礎傷害 × 招式 %（F1）；weapon 是 WEAPONS 的一筆，move 是它的 attack / special / parry
static func move_base_damage(weapon: Dictionary, move: Dictionary) -> float:
	return weapon.base_damage * move.damage_pct
