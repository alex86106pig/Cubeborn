# 技能資料：Q 的治療藥水，與鑲在寶石座、按數字鍵 1~4 放的技能（Build 改版第 7 步）；邏輯在 sim/skill_behaviors.gd
# 寶石座的技能也是 ItemDefs 的條目（kind &"skill"，同一個 id：名稱、說明、形狀在那邊），這裡放動作與數字
# 寶石座的技能耗魔（mana，Player.mana_cost_of；放完同一格 Config.MANA.cast_gap 秒內不能再放）、沒有冷卻；
# 藥水是 mode &"charges"：有使用次數，cooldown 是防連按間隔
# weapons：寶石座時代的「能鑲在哪把武器」，觸發袋改版後技能不限武器；現在有這欄 = 是技能（gem_skill_ids），第一把是平衡表量傷害時拿的武器；tags：修飾看這個（TAGS）
# category（CATEGORIES）：戰技有角色動作、法術被觸發時沒有動作；needs：手上的武器要有這個標籤（WeaponDefs.TAGS）才放得出來，沒寫 = 不限武器；
# scale：傷害吃武器傷害與法術強度各多少（scale_of，沒寫 = DEFAULT_SCALE）。needs 不符的放不出來（fits_weapon，ActiveSlots.can_cast）；scale 還沒接進傷害
# 傷害 damage_pct 是手上武器基礎傷害的倍數（Player.pct_damage，含攻擊力與物理 / 屬性傷害）；等級每升 1 級傷害 +LEVEL.damage、耗魔 −LEVEL.mana
# 耗魔 = 強度：照 docs/設計方向.md「技能強度」，耗魔 ÷ 武器的回魔當作冷卻秒數去算傷害目標（許家慶 2026-11-04：耗魔 ÷ 3、倍率 ÷ 2）
# 數字都是 Claude 暫定（2026-10-30 許家慶照表同意技能清單），試玩後再調；傷害照 docs/設計方向.md「技能強度」的目標，調完跑 `node tools/release.mjs --balance` 看 docs/平衡數字.md
class_name SkillDefs

const TAGS := {&"area": "範圍", &"projectile": "投射", &"move": "移動", &"melee": "近戰", &"guard": "防禦", &"summon": "召喚", &"buff": "增益"}
const CATEGORIES := {&"attack": "戰技", &"spell": "法術"}
const DEFAULT_SCALE := {"weapon": 1.0, "spell": 0.0}   # 傷害 = damage_pct ×（武器傷害 × weapon + 武器的法術強度 × spell）
const LEVEL := {"max": 5, "damage": 0.2, "mana": 0.1}
const PHANTOM_MUL := 0.6    # 幻影放出的技能（手上的武器不符、蓋著幻影修飾）傷害倍率（ActiveSlots.cast_context）
const SUPPORT_MANA := 0.1   # 蓋在技能上的修飾每點強度（ItemDefs power）耗魔 +10%（ActiveSlots.support_mana_mul；節能的 mana_mul 另外算）

const SKILLS := {
	&"heal": {
		"id": &"heal",
		"name": "治療藥水",
		"icon": "✚",
		"mode": &"charges",
		"charges": 3,
		"cooldown": 1.5,
		"behavior": &"heal",
		"amount": 35.0,
		"color": Color("5dff7a"),
	},

	# ---- 劍盾（原本長劍的） ----
	&"whirlwind": {"icon": "旋", "mana": 10, "behavior": &"nova", "category": &"attack", "needs": &"melee", "weapons": [&"swordShield"], "tags": [&"area", &"melee"],
		"radius": 2.6, "damage_pct": 3, "knockback": 6.0, "damage_type": &"phys", "color": Color("d8e4ff"), "sfx": "swingHeavy"},
	&"charge_slash": {"icon": "衝", "mana": 12, "behavior": &"dash", "category": &"attack", "needs": &"melee", "weapons": [&"swordShield"], "tags": [&"move", &"melee"],
		"distance": 5.0, "time": 0.3, "width": 1.4, "damage_pct": 3.5, "knockback": 5.0, "damage_type": &"phys", "color": Color("d8e4ff"), "sfx": "swingHeavy"},
	&"sword_wave": {"icon": "氣", "mana": 8, "behavior": &"shoot", "category": &"spell", "needs": &"melee", "weapons": [&"swordShield"], "tags": [&"projectile"],
		"count": 1, "spread": 0.0, "speed": 16.0, "range": 10.0, "radius": 0.6, "pierce": true, "damage_pct": 2.5, "damage_type": &"phys",
		"color": Color("b8d0ff"), "visual": &"crescent", "sfx": "arcaneCast"},
	# 突刺（原本長劍按住右鍵的蓄力突刺，許家慶 2026-11-05 改成技能；袋子觸發沒辦法按住蓄力，改成一放就衝）：比衝鋒斬短、窄、快、擊退大，傷害同衝鋒斬（4.5 時平衡表偏高 25%，Claude 暫定）
	&"thrust": {"icon": "sword_thrust", "mana": 12, "behavior": &"dash", "category": &"attack", "needs": &"melee", "weapons": [&"swordShield"], "tags": [&"move", &"melee"],
		"distance": 3.0, "time": 0.18, "width": 1.0, "damage_pct": 3.5, "knockback": 8.0, "damage_type": &"phys", "color": Color("ffe27a"), "sfx": "swingHeavy"},
	# ---- 雙匕首 ----
	&"ambush": {"icon": "襲", "mana": 13, "behavior": &"ambush", "category": &"attack", "needs": &"melee", "weapons": [&"dagger"], "tags": [&"move", &"melee"],
		"range": 6.0, "damage_pct": 2.75, "damage_type": &"phys", "color": Color("b36bff"), "sfx": "swing"},
	&"knife_fan": {"icon": "扇", "mana": 8, "behavior": &"shoot", "category": &"spell", "needs": &"dagger", "weapons": [&"dagger"], "tags": [&"projectile"],
		"count": 5, "spread": 0.7, "speed": 18.0, "range": 9.0, "radius": 0.2, "pierce": false, "damage_pct": 0.875, "damage_type": &"phys",
		"color": Color("c8d0dc"), "visual": &"arrow", "sfx": "arrowShot"},
	&"smoke_bomb": {"icon": "煙", "mana": 40, "behavior": &"smoke", "category": &"spell", "weapons": [&"dagger"], "tags": [&"area"],
		"radius": 3.0, "duration": 3.0, "dodge": 0.35, "color": Color("8a8a9a")},   # 閃避 30% × 綠 1.15 ≈ 35%（RARITY_BUDGET）
	# ---- 火把 ----
	&"fire_nova": {"icon": "焰", "mana": 12, "behavior": &"nova", "category": &"spell", "needs": &"torch", "weapons": [&"torch"], "tags": [&"area"],
		"radius": 3.5, "damage_pct": 4, "knockback": 3.0, "damage_type": &"fire", "burn": 1, "color": Color("ff8a3d"), "sfx": "explosion"},
	&"fire_flask": {"icon": "瓶", "mana": 10, "behavior": &"shoot", "category": &"spell", "weapons": [&"torch"], "tags": [&"projectile", &"area"],
		"count": 1, "spread": 0.0, "speed": 12.0, "range": 7.0, "radius": 0.3, "pierce": false, "damage_pct": 1.25, "damage_type": &"fire",
		"color": Color("ff8a3d"), "visual": &"orb", "sfx": "arcaneCast",
		"pool": {"radius": 2.0, "duration": 4.0, "dps_pct": 0.75}},
	&"flame_dash": {"icon": "奔", "mana": 14, "behavior": &"dash", "category": &"attack", "needs": &"melee", "weapons": [&"torch"], "tags": [&"move"],
		"distance": 6.0, "time": 0.35, "width": 1.2, "damage_pct": 1.25, "knockback": 2.0, "damage_type": &"fire", "color": Color("ff8a3d"), "sfx": "swing",
		"trail": {"radius": 1.0, "duration": 3.0, "dps_pct": 0.75, "every": 1.2}},
	# ---- 劍盾（原本木盾的） ----
	&"shield_charge": {"icon": "撞", "mana": 13, "behavior": &"dash", "category": &"attack", "needs": &"shield", "weapons": [&"swordShield"], "tags": [&"move", &"melee"],
		"distance": 5.0, "time": 0.35, "width": 1.6, "damage_pct": 2, "knockback": 10.0, "damage_type": &"phys", "stun": 0.8,
		"color": Color("d8b070"), "sfx": "shieldBash"},
	&"taunt": {"icon": "吼", "mana": 47, "behavior": &"taunt", "category": &"spell", "weapons": [&"swordShield"], "tags": [&"guard"],
		"radius": 6.0, "duration": 3.9, "damage_taken": 0.67, "color": Color("ff6b4a")},   # 受到的傷害 −33%；持續 3 秒 × 藍 1.3（RARITY_BUDGET）
	&"shield_slam": {"icon": "震", "mana": 15, "behavior": &"nova", "category": &"attack", "needs": &"shield", "weapons": [&"swordShield"], "tags": [&"area"],
		"radius": 3.0, "damage_pct": 2.25, "knockback": 9.0, "damage_type": &"phys", "stun": 0.5, "color": Color("d8b070"), "sfx": "shieldBash"},
	# ---- 法杖 ----
	&"frost_nova": {"icon": "霜", "mana": 13, "behavior": &"nova", "category": &"spell", "weapons": [&"staff"], "tags": [&"area"],
		"radius": 4.0, "damage_pct": 2.25, "knockback": 2.0, "damage_type": &"cold", "chill": 2, "color": Color("8fd8ff"), "sfx": "arcaneCast"},
	&"meteor": {"icon": "隕", "mana": 17, "behavior": &"strike", "category": &"spell", "weapons": [&"staff"], "tags": [&"area"],
		"delay": 1.0, "max_range": 12.0, "radius": 3.0, "damage_pct": 2.5, "knockback": 8.0, "damage_type": &"fire", "burn": 1,
		"color": Color("ff6a2a"), "sfx": "explosion"},
	&"chain_bolt": {"icon": "鏈", "mana": 10, "behavior": &"chain", "category": &"spell", "weapons": [&"staff"], "tags": [&"projectile"],
		"range": 10.0, "jumps": 4, "jump_range": 5.0, "damage_pct": 1.75, "damage_type": &"lightning", "color": Color("ffe45c"), "sfx": "arcaneCast"},
	# ---- 驅魔權杖 ----
	&"holy_pillar": {"icon": "柱", "mana": 15, "behavior": &"strike", "category": &"spell", "weapons": [&"scepter"], "tags": [&"area"],
		"delay": 0.4, "max_range": 10.0, "radius": 2.5, "damage_pct": 2.3, "knockback": 3.0, "damage_type": &"holy", "heal_ratio": 0.1,
		"color": Color("fff3b0"), "sfx": "arcaneCast"},
	&"bone_guard": {"icon": "骸", "mana": 33, "behavior": &"summon", "category": &"spell", "weapons": [&"scepter"], "tags": [&"summon"],
		"count": 2, "life": 7.5, "color": Color("d8d0b8")},   # 存在 5 秒 × 紫 1.5（RARITY_BUDGET）
	&"blessing": {"icon": "祝", "mana": 50, "behavior": &"bless", "category": &"spell", "weapons": [&"scepter"], "tags": [&"buff"],
		"radius": 6.0, "duration": 5.0, "attack_speed": 0.375, "color": Color("fff3b0")},   # 攻速 +25% × 紫 1.5（RARITY_BUDGET）
	# ---- 短弓 ----
	&"volley": {"icon": "連", "mana": 9, "behavior": &"shoot", "category": &"attack", "needs": &"bow", "weapons": [&"shortbow"], "tags": [&"projectile"],
		"count": 5, "spread": 0.0, "interval": 0.08, "speed": 22.0, "range": 12.0, "radius": 0.2, "pierce": false, "damage_pct": 0.5,
		"damage_type": &"phys", "color": Color("e8d8b0"), "visual": &"arrow", "sfx": "arrowShot"},
	&"leap_shot": {"icon": "躍", "mana": 12, "behavior": &"leap_shot", "category": &"attack", "needs": &"bow", "weapons": [&"shortbow"], "tags": [&"move", &"projectile"],
		"distance": 4.0, "count": 3, "spread": 0.5, "speed": 20.0, "range": 11.0, "radius": 0.2, "pierce": false, "damage_pct": 3.5,
		"damage_type": &"phys", "color": Color("e8d8b0"), "visual": &"arrow", "sfx": "arrowShot"},
	&"lightning_arrow": {"icon": "雷", "mana": 8, "behavior": &"shoot", "category": &"attack", "needs": &"bow", "weapons": [&"shortbow"], "tags": [&"projectile"],
		"count": 1, "spread": 0.0, "speed": 24.0, "range": 13.0, "radius": 0.25, "pierce": false, "damage_pct": 2.75,
		"damage_type": &"lightning", "color": Color("ffe45c"), "visual": &"arrow", "sfx": "arrowShot", "chain": {"jumps": 3, "jump_range": 4.0, "ratio": 0.6}},
	# ---- 長弓 ----
	&"arrow_rain": {"icon": "雨", "mana": 17, "behavior": &"rain", "category": &"spell", "needs": &"bow", "weapons": [&"longbow"], "tags": [&"area", &"projectile"],
		"max_range": 13.0, "radius": 3.0, "duration": 2.0, "tick": 0.25, "damage_pct": 0.5, "damage_type": &"phys", "color": Color("e8d8b0"), "sfx": "arrowShot"},
	&"snipe": {"icon": "狙", "mana": 15, "behavior": &"shoot", "category": &"attack", "needs": &"bow", "weapons": [&"longbow"], "tags": [&"projectile"],
		"windup": 0.8, "count": 1, "spread": 0.0, "speed": 34.0, "range": 18.0, "radius": 0.3, "pierce": true, "damage_pct": 3,
		"damage_type": &"phys", "color": Color("fff0c0"), "visual": &"arrow", "sfx": "arrowShot"},
	&"frost_arrow": {"icon": "凍", "mana": 10, "behavior": &"shoot", "category": &"attack", "needs": &"bow", "weapons": [&"longbow"], "tags": [&"projectile", &"area"],
		"count": 1, "spread": 0.0, "speed": 24.0, "range": 14.0, "radius": 0.25, "pierce": false, "damage_pct": 2,
		"damage_type": &"cold", "color": Color("8fd8ff"), "visual": &"arrow", "sfx": "arrowShot", "burst": {"radius": 2.5, "chill": 2}},
	# ---- 鐵鏟 ----
	&"ground_slam": {"icon": "砸", "mana": 13, "behavior": &"cone", "category": &"attack", "needs": &"shovel", "weapons": [&"shovel"], "tags": [&"area", &"melee"],
		"range": 5.0, "arc": 1.6, "damage_pct": 2.6, "knockback": 9.0, "damage_type": &"phys", "stun": 0.5, "color": Color("9a7a50"), "sfx": "explosion"},
	&"dirt_toss": {"icon": "土", "mana": 10, "behavior": &"shoot", "category": &"attack", "needs": &"shovel", "weapons": [&"shovel"], "tags": [&"projectile", &"area"],
		"count": 1, "spread": 0.0, "speed": 13.0, "range": 8.0, "radius": 0.4, "pierce": false, "damage_pct": 3.8,
		"damage_type": &"phys", "color": Color("8a6a40"), "visual": &"orb", "sfx": "swingHeavy", "burst": {"radius": 2.2, "stun": 0.6}},
	&"burrow": {"icon": "掘", "mana": 17, "behavior": &"burrow", "category": &"attack", "needs": &"shovel", "weapons": [&"shovel"], "tags": [&"move", &"area"],
		"distance": 6.0, "time": 1.0, "radius": 3.0, "damage_pct": 6.2, "knockback": 8.0, "damage_type": &"phys", "color": Color("8a6a40"), "sfx": "explosion"},
	# 活埋（許家慶 2026-11-06：原本鐵鏟舉著怪時的右鍵「埋入」改成技能；數字 Claude 暫定）：暈 2 秒的控場，傷害照功能型減半
	&"bury": {"icon": "shovel_bury", "mana": 9, "behavior": &"bury", "category": &"attack", "needs": &"shovel", "weapons": [&"shovel"], "tags": [&"melee"],
		"reach": 2.0, "damage_pct": 1.5, "stun": 1.5, "crawl": 0.5, "damage_type": &"phys", "color": Color("6a5236"), "sfx": "bossSlam"},

	# ---- 橘色（傳說；mockups/橘色技能.html 方案 1 大招型、2 改寫袋子型、3 成長型，許家慶 2026-11-06 選；數字 Claude 暫定）----
	# 傷害照「技能強度」：白色每 1 點耗魔 ≈ 0.3 倍武器傷害（旋風斬 10 魔 3），施放時再乘橘色預算 1.75；× 8（劍盾）取整數
	&"hell_gate": {"icon": "冥", "mana": 24, "behavior": &"strike", "category": &"spell", "weapons": [&"swordShield"], "tags": [&"area"],
		"delay": 1.2, "max_range": 12.0, "radius": 4.0, "damage_pct": 7.25, "knockback": 0.0, "damage_type": &"shadow", "color": Color("b48cff"), "sfx": "explosion"},
	&"blade_storm": {"icon": "刃", "mana": 20, "behavior": &"storm", "category": &"attack", "needs": &"melee", "weapons": [&"swordShield"], "tags": [&"area", &"melee"],
		"duration": 3.0, "tick": 0.25, "radius": 2.5, "damage_pct": 0.5, "knockback": 2.0, "damage_type": &"phys", "color": Color("d8e4ff"), "sfx": "swingHeavy"},
	&"fissure": {"icon": "裂", "mana": 18, "behavior": &"line", "category": &"spell", "needs": &"melee", "weapons": [&"swordShield"], "tags": [&"area"],
		"length": 12.0, "width": 1.6, "damage_pct": 5.375, "knockback": 6.0, "knockup": 6.0, "damage_type": &"phys", "color": Color("c8a070"), "sfx": "explosion"},
	&"judgment": {"icon": "譴", "mana": 22, "behavior": &"smite", "category": &"spell", "weapons": [&"swordShield"], "tags": [&"area"],
		"range": 8.0, "targets": 4, "delay": 0.4, "radius": 1.2, "damage_pct": 6.625, "knockback": 3.0, "damage_type": &"lightning", "color": Color("ffe45c"), "sfx": "explosion"},
	# 改寫袋子：bag_rule 的技能不會自己放、不耗魔（回響、共鳴、血契），規則在 BagTriggers.run_bag；共鳴發動時才扣 mana
	&"echo": {"icon": "響", "behavior": &"bag_rule", "category": &"spell", "weapons": [&"swordShield"], "tags": [&"buff"], "rule": &"echo",
		"delay": 0.5, "mul": 0.6, "mana_share": 0.5, "color": Color("ffb060")},
	&"soul_spring": {"icon": "泉", "mana": 20, "behavior": &"mana_buff", "category": &"spell", "weapons": [&"swordShield"], "tags": [&"buff"],
		"duration": 5.0, "mana_cost": 0.5, "color": Color("7fb0ff")},
	&"resonance": {"icon": "鳴", "mana": 8, "behavior": &"bag_rule", "category": &"spell", "weapons": [&"swordShield"], "tags": [&"buff"], "rule": &"resonance", "color": Color("ffb060")},
	&"blood_pact": {"icon": "契", "behavior": &"bag_rule", "category": &"spell", "weapons": [&"swordShield"], "tags": [&"buff"], "rule": &"blood_pact",
		"hp_per_mana": 0.005, "power": 1.25, "color": Color("ff5a5a")},
	# 成長型
	&"soul_reaver": {"icon": "噬", "mana": 14, "behavior": &"reaver", "category": &"attack", "needs": &"melee", "weapons": [&"swordShield"], "tags": [&"melee"],
		"range": 3.0, "arc": 1.6, "damage_pct": 2.75, "knockback": 5.0, "damage_type": &"shadow", "per_kill": 0.03, "max_stacks": 30,
		"color": Color("b48cff"), "sfx": "swingHeavy"},
	&"legion": {"icon": "軍", "mana": 30, "behavior": &"legion", "category": &"spell", "weapons": [&"scepter"], "tags": [&"summon"],
		"radius": 8.0, "max": 6, "life": 8.0, "color": Color("d8d0b8")},
	&"grudge": {"icon": "怨", "mana": 16, "behavior": &"grudge", "category": &"spell", "weapons": [&"swordShield"], "tags": [&"area"],
		"radius": 4.0, "damage_pct": 2.375, "grudge_mul": 1.7, "knockback": 8.0, "damage_type": &"shadow", "color": Color("ff5a5a"), "sfx": "explosion"},
	&"star_sign": {"icon": "星", "mana": 10, "behavior": &"star", "category": &"spell", "weapons": [&"swordShield"], "tags": [&"area"],
		"max": 3, "life": 20.0, "tick": 1.0, "damage_pct": 1.0, "damage_type": &"holy", "color": Color("ffd27a"), "sfx": "arcaneCast"},
}


# 技能的傷害吃武器傷害與法術強度各多少：{ weapon, spell }
static func scale_of(id: StringName) -> Dictionary:
	return SKILLS[id].get("scale", DEFAULT_SCALE)


# 這把武器（WeaponDefs 的一筆）放不放得出這個技能：沒有武器需求，或武器有那個標籤
static func fits_weapon(def: Dictionary, weapon: Dictionary) -> bool:
	return not def.has("needs") or (weapon.tags as Array).has(def.needs)


# 寶石座技能（鑲得進武器的，不含治療藥水）
static func gem_skill_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in SKILLS:
		if SKILLS[id].has("weapons"):
			out.append(id)
	return out


# 技能遺物每個技能被抽到的權重：越稀有越少（10 白 / 7 綠 / 7 藍 / 3 紫時約 50% / 28% / 17.5% / 4.5%）
const RELIC_WEIGHTS := {&"white": 10, &"green": 8, &"blue": 5, &"purple": 3, &"orange": 1}


# 技能遺物抽得到的
static func relic_pool() -> Array[StringName]:
	return gem_skill_ids().filter(func(id: StringName) -> bool: return not SKILLS[id].get("no_relic", false))


# 從 pool 照稀有度權重抽一個技能（權重是每個技能各自的，RELIC_WEIGHTS）
static func pick_relic(pool: Array, rng: RandomNumberGenerator) -> StringName:
	var total := 0
	for id: StringName in pool:
		total += RELIC_WEIGHTS[ItemDefs.ITEMS[id].rarity]
	var roll := rng.randi_range(1, total)
	for id: StringName in pool:
		roll -= RELIC_WEIGHTS[ItemDefs.ITEMS[id].rarity]
		if roll <= 0:
			return id
	return pool[-1]


# 稀有度的強度預算（製作計畫 I「技能稀有度」，使用者 2026-11-04 定）：同耗魔換到的傷害 / 功能。傷害照 damage_mul 在施放時乘；
# 沒有傷害的功能型（煙霧彈、嘲諷、祝福、骸骨衛士）把係數直接乘進資料的效果數值（許家慶 2026-11-05 同意），說明文字跟著寫
const RARITY_BUDGET := {&"white": 1.0, &"green": 1.15, &"blue": 1.3, &"purple": 1.5, &"orange": 1.75}


static func budget(id: StringName) -> float:
	return RARITY_BUDGET[ItemDefs.ITEMS[id].rarity]


# 技能這一級的傷害倍率 = 等級 × 稀有度的強度預算（施放、說明框、遺物卡共用；袋子的倍率另外乘）
static func damage_mul(id: StringName, level: int) -> float:
	return level_damage_mul(level) * budget(id)


# 等級的傷害倍率與耗魔倍率（施放、技能欄、說明框共用）
static func level_damage_mul(level: int) -> float:
	return 1.0 + LEVEL.damage * (level - 1)


static func level_mana_mul(level: int) -> float:
	return 1.0 - LEVEL.mana * (level - 1)
