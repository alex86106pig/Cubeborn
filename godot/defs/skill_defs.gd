# 技能資料：Q 的治療藥水，與鑲在寶石座、按數字鍵 1~4 放的技能（Build 改版第 7 步）；邏輯在 sim/skill_behaviors.gd
# 寶石座的技能也是 ItemDefs 的條目（kind &"skill"，同一個 id：名稱、說明、形狀在那邊），這裡放動作與數字
# mode：&"cooldown" 只受 CD 限制；&"charges" 另有使用次數（CD 作為防連按間隔）
# weapons：能鑲在哪幾種武器上（寶石座在那把武器的格子裡）；tags：輔助道具看這個（TAGS）
# 傷害 damage_pct 是手上武器基礎傷害的倍數（Player.pct_damage，含攻擊力與物理 / 屬性傷害）；等級每升 1 級傷害 +LEVEL.damage、冷卻 −LEVEL.cooldown
# 數字都是 Claude 暫定（2026-10-30 許家慶照表同意技能清單），試玩後再調；傷害照 docs/設計方向.md「技能強度」的目標，調完跑 `node tools/release.mjs --balance` 看 docs/平衡數字.md
class_name SkillDefs

const TAGS := {&"area": "範圍", &"projectile": "投射", &"move": "移動", &"melee": "近戰", &"guard": "防禦", &"summon": "召喚", &"buff": "增益"}
const LEVEL := {"max": 5, "damage": 0.2, "cooldown": 0.1}

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
	# 插火把（F8）：火把出廠就鑲在寶石座上（WeaponDefs 的 slot_skill）；次數記在那把火把上（WeaponDropDefs.slot_charges），換層補滿
	&"plantTorch": {"icon": "torch_plant", "mode": &"charges", "charges": 3, "weapon_charges": true, "cooldown": 1.0,
		"behavior": &"plantTorch", "weapons": [&"torch"], "tags": [], "no_relic": true},

	# ---- 長劍 ----
	&"whirlwind": {"icon": "旋", "cooldown": 6.0, "behavior": &"nova", "weapons": [&"longsword"], "tags": [&"area", &"melee"],
		"radius": 2.6, "damage_pct": 6.0, "knockback": 6.0, "damage_type": &"phys", "color": Color("d8e4ff"), "sfx": "swingHeavy"},
	&"charge_slash": {"icon": "衝", "cooldown": 7.0, "behavior": &"dash", "weapons": [&"longsword"], "tags": [&"move", &"melee"],
		"distance": 5.0, "time": 0.3, "width": 1.4, "damage_pct": 7.0, "knockback": 5.0, "damage_type": &"phys", "color": Color("d8e4ff"), "sfx": "swingHeavy"},
	&"sword_wave": {"icon": "氣", "cooldown": 5.0, "behavior": &"shoot", "weapons": [&"longsword"], "tags": [&"projectile"],
		"count": 1, "spread": 0.0, "speed": 16.0, "range": 10.0, "radius": 0.6, "pierce": true, "damage_pct": 5.0, "damage_type": &"phys",
		"color": Color("b8d0ff"), "visual": &"orb", "sfx": "arcaneCast"},
	# ---- 匕首 ----
	&"ambush": {"icon": "襲", "cooldown": 8.0, "behavior": &"ambush", "weapons": [&"dagger"], "tags": [&"move", &"melee"],
		"range": 6.0, "damage_pct": 5.5, "damage_type": &"phys", "color": Color("b36bff"), "sfx": "swing"},
	&"knife_fan": {"icon": "扇", "cooldown": 5.0, "behavior": &"shoot", "weapons": [&"dagger"], "tags": [&"projectile"],
		"count": 5, "spread": 0.7, "speed": 18.0, "range": 9.0, "radius": 0.2, "pierce": false, "damage_pct": 1.75, "damage_type": &"phys",
		"color": Color("c8d0dc"), "visual": &"arrow", "sfx": "arrowShot"},
	&"smoke_bomb": {"icon": "煙", "cooldown": 12.0, "behavior": &"smoke", "weapons": [&"dagger"], "tags": [&"area"],
		"radius": 3.0, "duration": 3.0, "dodge": 0.3, "color": Color("8a8a9a")},
	# ---- 火把 ----
	&"fire_nova": {"icon": "焰", "cooldown": 7.0, "behavior": &"nova", "weapons": [&"torch"], "tags": [&"area"],
		"radius": 3.5, "damage_pct": 5.25, "knockback": 3.0, "damage_type": &"fire", "burn": 1, "color": Color("ff8a3d"), "sfx": "explosion"},
	&"fire_flask": {"icon": "瓶", "cooldown": 6.0, "behavior": &"shoot", "weapons": [&"torch"], "tags": [&"projectile", &"area"],
		"count": 1, "spread": 0.0, "speed": 12.0, "range": 7.0, "radius": 0.3, "pierce": false, "damage_pct": 1.5, "damage_type": &"fire",
		"color": Color("ff8a3d"), "visual": &"orb", "sfx": "arcaneCast",
		"pool": {"radius": 2.0, "duration": 4.0, "dps_pct": 1.0}},
	&"flame_dash": {"icon": "奔", "cooldown": 8.0, "behavior": &"dash", "weapons": [&"torch"], "tags": [&"move"],
		"distance": 6.0, "time": 0.35, "width": 1.2, "damage_pct": 1.75, "knockback": 2.0, "damage_type": &"fire", "color": Color("ff8a3d"), "sfx": "swing",
		"trail": {"radius": 1.0, "duration": 3.0, "dps_pct": 1.0, "every": 1.2}},
	# ---- 木盾 ----
	&"shield_charge": {"icon": "撞", "cooldown": 8.0, "behavior": &"dash", "weapons": [&"woodShield"], "tags": [&"move", &"melee"],
		"distance": 5.0, "time": 0.35, "width": 1.6, "damage_pct": 4.0, "knockback": 10.0, "damage_type": &"phys", "stun": 0.8,
		"color": Color("d8b070"), "sfx": "shieldBash"},
	&"taunt": {"icon": "吼", "cooldown": 14.0, "behavior": &"taunt", "weapons": [&"woodShield"], "tags": [&"guard"],
		"radius": 6.0, "duration": 3.0, "damage_taken": 0.67, "color": Color("ff6b4a")},   # 受到的傷害 −33%
	&"shield_slam": {"icon": "震", "cooldown": 9.0, "behavior": &"nova", "weapons": [&"woodShield"], "tags": [&"area"],
		"radius": 3.0, "damage_pct": 4.5, "knockback": 9.0, "damage_type": &"phys", "stun": 0.5, "color": Color("d8b070"), "sfx": "shieldBash"},
	# ---- 法杖 ----
	&"frost_nova": {"icon": "霜", "cooldown": 8.0, "behavior": &"nova", "weapons": [&"staff"], "tags": [&"area"],
		"radius": 4.0, "damage_pct": 4.5, "knockback": 2.0, "damage_type": &"cold", "chill": 2, "color": Color("8fd8ff"), "sfx": "arcaneCast"},
	&"meteor": {"icon": "隕", "cooldown": 10.0, "behavior": &"strike", "weapons": [&"staff"], "tags": [&"area"],
		"delay": 1.0, "max_range": 12.0, "radius": 3.0, "damage_pct": 5.0, "knockback": 8.0, "damage_type": &"fire", "burn": 1,
		"color": Color("ff6a2a"), "sfx": "explosion"},
	&"chain_bolt": {"icon": "鏈", "cooldown": 6.0, "behavior": &"chain", "weapons": [&"staff"], "tags": [&"projectile"],
		"range": 10.0, "jumps": 4, "jump_range": 5.0, "damage_pct": 3.375, "damage_type": &"lightning", "color": Color("ffe45c"), "sfx": "arcaneCast"},
	# ---- 驅魔權杖 ----
	&"holy_pillar": {"icon": "柱", "cooldown": 9.0, "behavior": &"strike", "weapons": [&"scepter"], "tags": [&"area"],
		"delay": 0.4, "max_range": 10.0, "radius": 2.5, "damage_pct": 3.6, "knockback": 3.0, "damage_type": &"holy", "heal_ratio": 0.1,
		"color": Color("fff3b0"), "sfx": "arcaneCast"},
	&"bone_guard": {"icon": "骸", "cooldown": 20.0, "behavior": &"summon", "weapons": [&"scepter"], "tags": [&"summon"],
		"count": 2, "life": 10.0, "color": Color("d8d0b8")},
	&"blessing": {"icon": "祝", "cooldown": 15.0, "behavior": &"bless", "weapons": [&"scepter"], "tags": [&"buff"],
		"radius": 6.0, "duration": 5.0, "attack_speed": 0.25, "color": Color("fff3b0")},
	# ---- 短弓 ----
	&"volley": {"icon": "連", "cooldown": 6.0, "behavior": &"shoot", "weapons": [&"shortbow"], "tags": [&"projectile"],
		"count": 5, "spread": 0.0, "interval": 0.08, "speed": 22.0, "range": 12.0, "radius": 0.2, "pierce": false, "damage_pct": 0.75,
		"damage_type": &"phys", "color": Color("e8d8b0"), "visual": &"arrow", "sfx": "arrowShot"},
	&"leap_shot": {"icon": "躍", "cooldown": 7.0, "behavior": &"leap_shot", "weapons": [&"shortbow"], "tags": [&"move", &"projectile"],
		"distance": 4.0, "count": 3, "spread": 0.5, "speed": 20.0, "range": 11.0, "radius": 0.2, "pierce": false, "damage_pct": 4.75,
		"damage_type": &"phys", "color": Color("e8d8b0"), "visual": &"arrow", "sfx": "arrowShot"},
	&"lightning_arrow": {"icon": "雷", "cooldown": 5.0, "behavior": &"shoot", "weapons": [&"shortbow"], "tags": [&"projectile"],
		"count": 1, "spread": 0.0, "speed": 24.0, "range": 13.0, "radius": 0.25, "pierce": false, "damage_pct": 3.5,
		"damage_type": &"lightning", "color": Color("ffe45c"), "visual": &"arrow", "sfx": "arrowShot", "chain": {"jumps": 3, "jump_range": 4.0, "ratio": 0.6}},
	# ---- 長弓 ----
	&"arrow_rain": {"icon": "雨", "cooldown": 10.0, "behavior": &"rain", "weapons": [&"longbow"], "tags": [&"area", &"projectile"],
		"max_range": 13.0, "radius": 3.0, "duration": 2.0, "tick": 0.25, "damage_pct": 0.5, "damage_type": &"phys", "color": Color("e8d8b0"), "sfx": "arrowShot"},
	&"snipe": {"icon": "狙", "cooldown": 9.0, "behavior": &"shoot", "weapons": [&"longbow"], "tags": [&"projectile"],
		"windup": 0.8, "count": 1, "spread": 0.0, "speed": 34.0, "range": 18.0, "radius": 0.3, "pierce": true, "damage_pct": 4.0,
		"damage_type": &"phys", "color": Color("fff0c0"), "visual": &"arrow", "sfx": "arrowShot"},
	&"frost_arrow": {"icon": "凍", "cooldown": 6.0, "behavior": &"shoot", "weapons": [&"longbow"], "tags": [&"projectile", &"area"],
		"count": 1, "spread": 0.0, "speed": 24.0, "range": 14.0, "radius": 0.25, "pierce": false, "damage_pct": 2.75,
		"damage_type": &"cold", "color": Color("8fd8ff"), "visual": &"arrow", "sfx": "arrowShot", "burst": {"radius": 2.5, "chill": 2}},
	# ---- 鐵鏟 ----
	&"ground_slam": {"icon": "砸", "cooldown": 8.0, "behavior": &"cone", "weapons": [&"shovel"], "tags": [&"area", &"melee"],
		"range": 5.0, "arc": 1.6, "damage_pct": 1.4, "knockback": 9.0, "damage_type": &"phys", "stun": 0.5, "color": Color("9a7a50"), "sfx": "explosion"},
	&"dirt_toss": {"icon": "土", "cooldown": 6.0, "behavior": &"shoot", "weapons": [&"shovel"], "tags": [&"projectile", &"area"],
		"count": 1, "spread": 0.0, "speed": 13.0, "range": 8.0, "radius": 0.4, "pierce": false, "damage_pct": 2.0,
		"damage_type": &"phys", "color": Color("8a6a40"), "visual": &"orb", "sfx": "swingHeavy", "burst": {"radius": 2.2, "stun": 0.6}},
	&"burrow": {"icon": "掘", "cooldown": 10.0, "behavior": &"burrow", "weapons": [&"shovel"], "tags": [&"move", &"area"],
		"distance": 6.0, "time": 1.0, "radius": 3.0, "damage_pct": 3.3, "knockback": 8.0, "damage_type": &"phys", "color": Color("8a6a40"), "sfx": "explosion"},
}


# 寶石座技能（鑲得進武器的，不含治療藥水）
static func gem_skill_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in SKILLS:
		if SKILLS[id].has("weapons"):
			out.append(id)
	return out


# 技能遺物抽得到的
static func relic_pool() -> Array[StringName]:
	return gem_skill_ids().filter(func(id: StringName) -> bool: return not SKILLS[id].get("no_relic", false))


static func can_socket(skill: StringName, weapon: StringName) -> bool:
	return SKILLS.has(skill) and (SKILLS[skill].get("weapons", []) as Array).has(weapon)
