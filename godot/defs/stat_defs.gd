# 屬性表：玩家與敵人共用的屬性名稱、基礎值、上下限、顯示方式（計算見 sim/stats.gd）
# base 為沒有指定時的預設基礎值；max_hp、move_speed 由實體建立時給定
# format：&"int" 整數、&"float" 小數兩位、&"regen" 每秒、&"pct" 百分比（1.0 = 100%）、&"armor" 護甲與減傷
# in_use = false 的屬性已定名但對應系統還沒做（翻滾、背包、視野…），屬性面板不顯示
class_name StatDefs

const ARMOR_SCALE := 100.0   # 受到傷害 × ARMOR_SCALE ÷ (ARMOR_SCALE + 護甲)：護甲 100 減傷 50%
const RESIST_MIN := -0.5     # 抗性下限：弱點最多多受 50%
const RESIST_MAX := 0.75     # 抗性上限
const ARCANE_PIERCE := 0.5   # 秘術無視目標正抗性的比例（弱點照算）

# 傷害屬性：名稱、傷害數字的顏色、對應的抗性屬性。物理先看護甲再看物理抗性；所有抗性（resist_all）只擋物理以外
const DAMAGE_TYPES := {
	&"phys": {"name": "物理", "color": Color.WHITE, "resist": &"resist_phys"},
	&"fire": {"name": "火焰", "color": Color("ff8a3d"), "resist": &"resist_fire"},
	&"cold": {"name": "冰霜", "color": Color("8fd8ff"), "resist": &"resist_cold"},
	&"lightning": {"name": "閃電", "color": Color("ffe45c"), "resist": &"resist_lightning"},
	&"poison": {"name": "腐毒", "color": Color("9be36b"), "resist": &"resist_poison"},
	&"holy": {"name": "神聖", "color": Color("fff3b0"), "resist": &"resist_holy"},
	&"shadow": {"name": "暗影", "color": Color("b48cff"), "resist": &"resist_shadow"},
	&"arcane": {"name": "秘術", "color": Color("e47bff"), "resist": &"resist_arcane"},
}

const STATS := {
	# 生存
	&"max_hp": {"name": "最大生命", "base": 1.0, "min": 1.0, "max": INF, "round": true, "format": &"int", "in_use": true},
	&"hp_regen": {"name": "生命回復", "base": 0.0, "min": 0.0, "max": INF, "format": &"regen", "in_use": true},
	&"armor": {"name": "護甲", "base": 0.0, "min": 0.0, "max": INF, "format": &"armor", "in_use": true},
	&"resist_all": {"name": "所有抗性", "base": 0.0, "min": -1.0, "max": 1.0, "format": &"pct", "in_use": true},
	# 各屬性的抗性：怪物照 EnemyDefs 的 resists 設基礎值；玩家還沒有來源，面板先不顯示
	&"resist_phys": {"name": "物理抗性", "base": 0.0, "min": -1.0, "max": 1.0, "format": &"pct", "in_use": false},
	&"resist_fire": {"name": "火焰抗性", "base": 0.0, "min": -1.0, "max": 1.0, "format": &"pct", "in_use": false},
	&"resist_cold": {"name": "冰霜抗性", "base": 0.0, "min": -1.0, "max": 1.0, "format": &"pct", "in_use": false},
	&"resist_lightning": {"name": "閃電抗性", "base": 0.0, "min": -1.0, "max": 1.0, "format": &"pct", "in_use": false},
	&"resist_poison": {"name": "腐毒抗性", "base": 0.0, "min": -1.0, "max": 1.0, "format": &"pct", "in_use": false},
	&"resist_holy": {"name": "神聖抗性", "base": 0.0, "min": -1.0, "max": 1.0, "format": &"pct", "in_use": false},
	&"resist_shadow": {"name": "暗影抗性", "base": 0.0, "min": -1.0, "max": 1.0, "format": &"pct", "in_use": false},
	&"resist_arcane": {"name": "秘術抗性", "base": 0.0, "min": -1.0, "max": 1.0, "format": &"pct", "in_use": false},
	&"dodge": {"name": "閃避率", "base": 0.0, "min": 0.0, "max": 0.75, "format": &"pct", "in_use": true},   # 完全閃掉一次攻擊（F1；上限 75% Claude 暫定）
	&"damage_taken": {"name": "受到傷害", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	&"knockback_taken": {"name": "受到擊退", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	# 攻擊
	# 招式傷害 = 武器基礎傷害 × 招式 % × 攻擊力 × 物理 / 屬性傷害：攻擊力是全部傷害的倍率（道具、詞條、怪物難度），物理 / 屬性只乘對應的攻擊
	&"damage": {"name": "攻擊力", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	&"phys_damage": {"name": "物理傷害", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	&"elem_damage": {"name": "屬性傷害", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},   # 物理以外的屬性都吃
	&"attack_speed": {"name": "攻速", "base": 1.0, "min": 0.1, "max": INF, "format": &"pct", "in_use": true},
	&"crit_chance": {"name": "爆擊率", "base": 0.0, "min": 0.0, "max": 1.0, "format": &"pct", "in_use": true},
	&"crit_damage": {"name": "爆擊傷害", "base": 1.5, "min": 1.0, "max": INF, "format": &"pct", "in_use": true},
	&"knockback": {"name": "擊退", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	# 移動與冷卻（冷卻縮減的道具用 mul，疊再多也不會到 0）
	&"move_speed": {"name": "移速", "base": 1.0, "min": 0.0, "max": INF, "format": &"float", "in_use": true},
	&"cooldown": {"name": "技能冷卻", "base": 1.0, "min": 0.05, "max": INF, "format": &"pct", "in_use": true},
	&"roll_cooldown": {"name": "翻滾冷卻", "base": 1.0, "min": 0.05, "max": INF, "format": &"pct", "in_use": true},
	&"roll_charges": {"name": "翻滾次數", "base": 1.0, "min": 1.0, "max": INF, "round": true, "format": &"int", "in_use": true},
	&"treasure": {"name": "尋寶", "base": 0.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},   # 開祭壇 / 石棺、掉武器時，比最低一級稀有的權重 × (1 + 尋寶)（F1）
	# 道具第二批（G1）接上：命中回復、吸血、受到投射物傷害在 Combat；靈魂、價格、撿取範圍在 World / Chest；視野在 Vision
	&"projectile_damage_taken": {"name": "受到投射物傷害", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	&"life_on_hit": {"name": "命中回復", "base": 0.0, "min": 0.0, "max": INF, "format": &"float", "in_use": true},
	&"lifesteal": {"name": "吸血", "base": 0.0, "min": 0.0, "max": 1.0, "format": &"pct", "in_use": true},
	&"soul_gain": {"name": "靈魂獲得", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	&"pickup_radius": {"name": "撿取範圍", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	&"chest_price": {"name": "祭壇 / 石棺價格", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	&"vision": {"name": "視野", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	# 羈絆道具（Build 改版第 5 步）：附加傷害在 Combat（普攻命中時多打一下該屬性，是這一下傷害的比例）；燃燒 / 冰冷在 Enemy；鬼火在 OrbitWisp
	&"added_fire": {"name": "附加火焰傷害", "base": 0.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	&"added_cold": {"name": "附加冰霜傷害", "base": 0.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	&"burn_damage": {"name": "燃燒傷害", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	&"chill_slow": {"name": "冰冷每層減速", "base": 0.0, "min": 0.0, "max": 1.0, "format": &"pct", "in_use": true},   # 加在羈絆的每層減速上
	&"chilled_damage_taken": {"name": "受到冰冷敵人的傷害", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	&"wisp_damage": {"name": "鬼火傷害", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	&"wisp_life_on_hit": {"name": "鬼火命中回復", "base": 0.0, "min": 0.0, "max": INF, "format": &"float", "in_use": true},
	# 武器詞條的羈絆強化與屬性轉換（Build 改版第 8 步）：效果在 BondEffects、Combat、WeaponBehaviors 的招架
	# optional：屬性面板只在不是基礎值時顯示（一般沒有，全部列出來面板會超出畫面）
	&"poise_gain": {"name": "失衡值累積", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true, "optional": true},
	&"burn_max_stacks": {"name": "燃燒層數上限", "base": 0.0, "min": 0.0, "max": INF, "round": true, "format": &"bonus_int", "in_use": true, "optional": true},   # 加在羈絆的上限上
	&"chill_max_stacks": {"name": "冰冷層數上限", "base": 0.0, "min": 0.0, "max": INF, "round": true, "format": &"bonus_int", "in_use": true, "optional": true},
	&"freeze_time": {"name": "凍結時間", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true, "optional": true},
	&"parry_window": {"name": "招架判定時間", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true, "optional": true},
	&"wisp_count": {"name": "額外鬼火", "base": 0.0, "min": 0.0, "max": INF, "round": true, "format": &"int", "in_use": true, "optional": true},
	&"convert_fire": {"name": "物理轉火焰", "base": 0.0, "min": 0.0, "max": 1.0, "format": &"pct", "in_use": true, "optional": true},
	&"convert_cold": {"name": "物理轉冰霜", "base": 0.0, "min": 0.0, "max": 1.0, "format": &"pct", "in_use": true, "optional": true},
	&"relic_choices": {"name": "遺物選項數", "base": 3.0, "min": 1.0, "max": 6.0, "round": true, "format": &"int", "in_use": true},   # N 選 1（Relic）
}


static func armor_damage_factor(armor: float) -> float:
	return ARMOR_SCALE / (ARMOR_SCALE + maxf(armor, 0.0))


# 受到這種屬性的傷害時乘的倍率：物理 = 護甲 × (1 − 物理抗性)；其他 = 1 − (該屬性抗性 + 所有抗性)
# 抗性限制在 RESIST_MIN ~ RESIST_MAX；秘術只吃一半的正抗性
static func damage_factor(stats: Stats, damage_type: StringName) -> float:
	var r := stats.value(DAMAGE_TYPES[damage_type].resist)
	var f := 1.0
	if damage_type == &"phys":
		f = armor_damage_factor(stats.value(&"armor"))
	else:
		r += stats.value(&"resist_all")
	if damage_type == &"arcane" and r > 0.0:
		r *= 1.0 - ARCANE_PIERCE
	return f * (1.0 - clampf(r, RESIST_MIN, RESIST_MAX))


# 攻擊類型對應的傷害屬性
static func type_damage_stat(damage_type: StringName) -> StringName:
	return &"phys_damage" if damage_type == &"phys" else &"elem_damage"


# 屬性面板用的顯示文字
static func format_value(stat: StringName, value: float) -> String:
	match STATS[stat].format:
		&"int":
			return "%d" % roundi(value)
		&"bonus_int":
			return "+%d" % roundi(value)
		&"regen":
			return "%.1f / 秒" % value
		&"pct":
			return "%s%%" % _trim(value * 100.0)
		&"armor":
			return "%s（減傷 %s%%）" % [_trim(value), _trim((1.0 - armor_damage_factor(value)) * 100.0)]
		_:
			return "%.2f" % value


# 去掉多餘的小數：100 → "100"、70.5 → "70.5"、7.4074 → "7.4"
static func _trim(v: float) -> String:
	var s := "%.1f" % v
	return s.trim_suffix(".0")
