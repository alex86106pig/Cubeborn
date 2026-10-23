# 武器資料定義（照搬網頁版 legacy/src/weapons/weaponDefs.js，欄位改 snake_case）；邏輯在 sim/weapon_behaviors.gd
class_name WeaponDefs

const WEAPONS := {
	&"swordShield": {
		"id": &"swordShield",
		"name": "劍盾",
		"type": &"melee",
		"model": &"swordShield",
		"idle": {"arm_r": -0.35, "arm_l": -0.1, "tilt": 0.0},
		"attack": {
			"behavior": &"meleeSwing",
			"sfx": "swing", "sfx_heavy": "swingHeavy",
			"name": "斬擊",
			"icon": "⚔",
			"damage": 12.0,
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
		# 格擋與盾反（v0.18.0，取代網頁版的盾擊衝鋒；使用者決定：按一下自動維持、可以移動、拿掉衝鋒，其餘數值 Claude 訂）
		"special": {
			"behavior": &"shieldBlock",
			"name": "格擋",
			"icon": "🛡",
			"cooldown": 4.0,           # 從按下右鍵開始算
			"windup": 0.05,            # 舉盾；按下就開始格擋（完美格擋從按下算）
			"active": 2.95,            # 舉盾 + 維持合計 3 秒
			"recovery": 0.15,
			"move_speed_mul": 0.5,     # 格擋時移速減半
			"roll_cancel": true,       # 可以用翻滾提前結束
			"press_cancel": true,      # 格擋中再按一次右鍵放下盾（v0.23.0 使用者決定；冷卻照舊從舉盾算）
			"block_arc": PI * 120.0 / 180.0,  # 正前方合計 120°（左右各 60°；v0.23.0 使用者決定，原本 75°）
			"perfect_window": 0.2,     # 按下後這麼久內擋下 = 完美格擋，觸發盾反
			"block_knockback_mul": 0.3,   # 擋下時自己被推退的比例（不扣血）
			"sfx_block": "shieldBash",
			"sfx_parry": "hitHeavy",
			"parry": {
				"damage": 25.0,
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
		"model": &"staff",
		"idle": {"arm_r": -0.5, "arm_l": 0.0, "tilt": 0.0},
		"attack": {
			"behavior": &"fireBolt",
			"sfx": "fireBolt",
			"name": "魔彈",
			"icon": "✦",
			"damage": 8.0,
			"projectile_speed": 20.0,
			"projectile_radius": 0.22,
			"spawn_offset": 0.6,       # 投射物出生點在玩家前方的距離
			"range": 14.0,
			"knockback": 3.5,
			"windup": 0.06,
			"active": 0.02,
			"recovery": 0.2,
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
			"damage": 28.0,
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
