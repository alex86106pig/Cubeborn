# 武器掉落與詞條（D4）：殺怪機率掉武器、稀有度機率、詞條清單；武器實例的建立與合成
# 使用者決定（2026-10-23）：小怪 4%、Boss 必掉；小怪 白 60 / 綠 25 / 藍 12 / 紫 3、Boss 藍 60 / 紫 30 / 橘 10；
# 白色沒有詞條、每高一級多 1 條；詞條清單與數值由 Claude 擬（暫定），只有手上正在用的那把生效
# 武器實例：{ uid, base（WeaponDefs / ItemDefs 的武器 id）, rarity, affixes: Array[StringName] }
class_name WeaponDropDefs

const DROP_CHANCE := {&"grunt": 0.04, &"archer": 0.04, &"boss": 1.0}

const RARITY_WEIGHTS := {
	&"minion": {&"white": 60.0, &"green": 25.0, &"blue": 12.0, &"purple": 3.0},
	&"boss": {&"blue": 60.0, &"purple": 30.0, &"orange": 10.0},
}

const RARITY_ORDER: Array[StringName] = [&"white", &"green", &"blue", &"purple", &"orange"]

# 武器基礎數值依稀有度提高（v0.27.0 使用者決定：要看得到「白色攻擊力 10、綠色 12」這種實際數字）
# 倍率是 Claude 暫定：攻擊力每級 +20%（白 10 → 綠 12），攻速與範圍每級 +5%
const RARITY_BASE := {
	&"white": {"damage": 1.0, "attack_speed": 1.0, "range": 1.0},
	&"green": {"damage": 1.2, "attack_speed": 1.05, "range": 1.05},
	&"blue": {"damage": 1.4, "attack_speed": 1.10, "range": 1.10},
	&"purple": {"damage": 1.6, "attack_speed": 1.15, "range": 1.15},
	&"orange": {"damage": 1.8, "attack_speed": 1.20, "range": 1.20},
}

# 詞條：屬性加成（格式同 ItemDefs 的屬性效果）；desc 給介面顯示
const AFFIXES := {
	&"aff_damage": {"desc": "攻擊力 +10%", "stat": &"damage", "op": Stats.PCT, "value": 0.10},
	&"aff_attack_speed": {"desc": "攻速 +10%", "stat": &"attack_speed", "op": Stats.PCT, "value": 0.10},
	&"aff_crit_chance": {"desc": "爆擊率 +6%", "stat": &"crit_chance", "op": Stats.ADD, "value": 0.06},
	&"aff_crit_damage": {"desc": "爆擊傷害 +25%", "stat": &"crit_damage", "op": Stats.ADD, "value": 0.25},
	&"aff_cooldown": {"desc": "技能冷卻 −10%", "stat": &"cooldown", "op": Stats.MUL, "value": 0.9},
	&"aff_move_speed": {"desc": "移速 +6%", "stat": &"move_speed", "op": Stats.PCT, "value": 0.06},
	&"aff_max_hp": {"desc": "最大生命 +15", "stat": &"max_hp", "op": Stats.ADD, "value": 15.0},
	&"aff_armor": {"desc": "護甲 +10", "stat": &"armor", "op": Stats.ADD, "value": 10.0},
	&"aff_regen": {"desc": "生命回復 +1 / 秒", "stat": &"hp_regen", "op": Stats.ADD, "value": 1.0},
	&"aff_knockback": {"desc": "擊退 +25%", "stat": &"knockback", "op": Stats.PCT, "value": 0.25},
}


# 武器的種類（ItemDefs 裡 kind = weapon 的 id）
static func bases() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in ItemDefs.ITEMS:
		if ItemDefs.ITEMS[id].kind == &"weapon":
			out.append(id)
	return out


static func affix_count(rarity: StringName) -> int:
	return RARITY_ORDER.find(rarity)


static func next_rarity(rarity: StringName) -> StringName:
	var i := RARITY_ORDER.find(rarity)
	return RARITY_ORDER[i + 1] if i >= 0 and i + 1 < RARITY_ORDER.size() else &""


static func roll_rarity(source: StringName, rng: RandomNumberGenerator) -> StringName:
	var weights: Dictionary = RARITY_WEIGHTS[source]
	var total := 0.0
	for r: StringName in weights:
		total += weights[r]
	var x := rng.randf() * total
	for r: StringName in weights:
		x -= weights[r]
		if x < 0.0:
			return r
	return weights.keys().back()


# 不重複地抽 count 條詞條（依 AFFIXES 順序做部分洗牌，用 world.rng 才有決定性）
static func roll_affixes(count: int, rng: RandomNumberGenerator) -> Array[StringName]:
	var pool: Array[StringName] = []
	for id: StringName in AFFIXES:
		pool.append(id)
	var out: Array[StringName] = []
	for i in mini(count, pool.size()):
		var j := rng.randi_range(i, pool.size() - 1)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
		out.append(pool[i])
	return out


static func make(uid: StringName, base: StringName, rarity: StringName, rng: RandomNumberGenerator) -> Dictionary:
	return {"uid": uid, "base": base, "rarity": rarity, "affixes": roll_affixes(affix_count(rarity), rng)}


# 武器的基礎數值（介面顯示用的實際數字）：攻擊力 = 普攻傷害、攻速 = 每秒普攻次數、範圍 = 揮砍距離或魔彈射程，都乘上稀有度倍率
static func base_stats(inst: Dictionary) -> Dictionary:
	var atk: Dictionary = WeaponDefs.WEAPONS[ItemDefs.ITEMS[inst.base].weapon].attack
	var m: Dictionary = RARITY_BASE[inst.rarity]
	return {
		"damage": atk.damage * m.damage,
		"attack_speed": m.attack_speed / (atk.windup + atk.active + atk.recovery),
		"range": atk.range * m.range,
	}


# 手上這把生效的屬性：稀有度的基礎倍率（攻擊力、攻速）＋詞條；範圍由 Player.weapon_range_mul 直接乘
static func stat_mods(inst: Dictionary) -> Array:
	var m: Dictionary = RARITY_BASE[inst.rarity]
	var mods := []
	if m.damage != 1.0:
		mods.append([&"damage", Stats.MUL, m.damage])
	if m.attack_speed != 1.0:
		mods.append([&"attack_speed", Stats.MUL, m.attack_speed])
	for id: StringName in inst.affixes:
		var a: Dictionary = AFFIXES[id]
		mods.append([a.stat, a.op, a.value])
	return mods


# 能不能合成：同種、同稀有度、不是同一把、還沒到最高（橘色）
static func can_merge(a: Dictionary, b: Dictionary) -> bool:
	return not a.is_empty() and not b.is_empty() and a.uid != b.uid and a.base == b.base \
		and a.rarity == b.rarity and next_rarity(a.rarity) != &""


# 快照用：[uid, base, rarity, [詞條…]]；空的裝備欄是 []
static func to_array(inst: Dictionary) -> Array:
	if inst.is_empty():
		return []
	var affixes := []
	for id: StringName in inst.affixes:
		affixes.append(String(id))
	return [String(inst.uid), String(inst.base), String(inst.rarity), affixes]


static func from_array(a: Array) -> Dictionary:
	if a.is_empty():
		return {}
	var affixes: Array[StringName] = []
	for s: String in a[3]:
		affixes.append(StringName(s))
	return {"uid": StringName(a[0]), "base": StringName(a[1]), "rarity": StringName(a[2]), "affixes": affixes}


static func display_name(inst: Dictionary) -> String:
	return "%s %s" % [ItemDefs.RARITIES[inst.rarity].name, ItemDefs.ITEMS[inst.base].name]
