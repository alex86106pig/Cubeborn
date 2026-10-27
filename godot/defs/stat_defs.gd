# 屬性表：玩家與敵人共用的屬性名稱、基礎值、上下限、顯示方式（計算見 sim/stats.gd）
# base 為沒有指定時的預設基礎值；max_hp、move_speed 由實體建立時給定
# format：&"int" 整數、&"float" 小數兩位、&"regen" 每秒、&"pct" 百分比（1.0 = 100%）、&"armor" 護甲與減傷
# in_use = false 的屬性已定名但對應系統還沒做（翻滾、背包、視野…），屬性面板不顯示
class_name StatDefs

const ARMOR_SCALE := 100.0   # 受到傷害 × ARMOR_SCALE ÷ (ARMOR_SCALE + 護甲)：護甲 100 減傷 50%

const STATS := {
	# 生存
	&"max_hp": {"name": "最大生命", "base": 1.0, "min": 1.0, "max": INF, "round": true, "format": &"int", "in_use": true},
	&"hp_regen": {"name": "生命回復", "base": 0.0, "min": 0.0, "max": INF, "format": &"regen", "in_use": true},
	&"armor": {"name": "護甲", "base": 0.0, "min": 0.0, "max": INF, "format": &"armor", "in_use": true},
	&"magic_resist": {"name": "魔抗", "base": 0.0, "min": 0.0, "max": INF, "format": &"armor", "in_use": true},   # 擋魔法傷害，公式同護甲（F1）
	&"dodge": {"name": "閃避率", "base": 0.0, "min": 0.0, "max": 0.75, "format": &"pct", "in_use": true},   # 完全閃掉一次攻擊（F1；上限 75% Claude 暫定）
	&"damage_taken": {"name": "受到傷害", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	&"knockback_taken": {"name": "受到擊退", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	# 攻擊
	# 招式傷害 = 武器基礎傷害 × 招式 % × 攻擊力 × 物理 / 魔法傷害（F1）：攻擊力是全部傷害的倍率（道具、詞條、怪物難度），物理 / 魔法只乘對應的攻擊
	&"damage": {"name": "攻擊力", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	&"phys_damage": {"name": "物理傷害", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
	&"magic_damage": {"name": "魔法傷害", "base": 1.0, "min": 0.0, "max": INF, "format": &"pct", "in_use": true},
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
}


static func armor_damage_factor(armor: float) -> float:
	return ARMOR_SCALE / (ARMOR_SCALE + maxf(armor, 0.0))


# 攻擊類型對應的防禦屬性：魔法傷害看魔抗，其餘（物理）看護甲
static func resist_stat(damage_type: StringName) -> StringName:
	return &"magic_resist" if damage_type == &"magic" else &"armor"


# 攻擊類型對應的傷害屬性
static func type_damage_stat(damage_type: StringName) -> StringName:
	return &"magic_damage" if damage_type == &"magic" else &"phys_damage"


# 屬性面板用的顯示文字
static func format_value(stat: StringName, value: float) -> String:
	match STATS[stat].format:
		&"int":
			return "%d" % roundi(value)
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
