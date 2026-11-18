# 骰子模式的資料（規則在 docs/改版構想.md「骰子模式」、做法在 docs/系統說明.md §55）：骰面、效果、威力、獎勵、時間；數字 Claude 暫定
# 骰面是 StringName：技能 id（SkillDefs.SKILLS）、效果 id（EFFECTS，fx_ 開頭）、&"" = 空白
class_name DiceDefs
extends RefCounted

const DICE_COUNT := 6
const FACES := 6
const BLANK := &""
const ROLL_TIME := 10.0         # 每人限時：沒擲就自動擲、擲過了沒按完成就自動完成
const SETTLE_TIME := 1.0        # 擲出去之後骰子轉的時間：這段不收操作、不倒數（畫面播動畫）
const REROLLS := 1              # 每場可以重擲沒鎖的幾次
const COUNTDOWN := 2.4          # 全部擲完 → 3、2、1 → 開打
# 擲骰次數（YangHsu 2026-11-19，取代「碰到怪群就擲」）：一般的怪群碰到直接開打、用手上的結果；逛地圖或戰鬥中按 R 花 1 次自己擲；
# 菁英群（有魔法 / 稀有怪）與 Boss 開打前免費擲一次。沒中技能面就只有普攻（不保底）
const CHARGES_STAGE := 2        # 每一關開頭 +幾次（第一關開局也是）
const CHARGES_PER_FIGHT := 1    # 打完一場 +幾次
const CHARGES_MAX := 3          # 最多存幾次
const BASIC_ATTACK_MUL := 0.5   # 左鍵普攻的傷害倍率（右鍵骰到的技能才是主力）
const COOLDOWN_PER_MANA := 0.3  # 右鍵技能的冷卻 = 技能原本的耗魔 × 這麼多秒（旋風斬 10 魔 → 3 秒）
const COOLDOWN_MIN := 1.5
const CDR_FLOOR := 0.4          # 冷卻縮減最多縮到原本的幾倍

# 同一招出現幾次 → 威力（index = 次數）；BIG_FROM 次以上換成 BIG 的大招版本（動作、範圍跟著換），沒列的照原本的招、只乘威力
const TIERS := [
	{"name": "沒中", "mul": 0.0},
	{"name": "一般", "mul": 1.0},
	{"name": "一般", "mul": 1.8},
	{"name": "強化", "mul": 2.6},
	{"name": "大招", "mul": 4.0},
	{"name": "超大招", "mul": 6.0},
	{"name": "傳說", "mul": 10.0},
]
const BIG_FROM := 4
const BIG := {&"whirlwind": &"blade_storm"}

# 效果面：每一面疊一次。kind：stat 掛在屬性來源上（stat = [屬性, op, 每面的值]）；basic 普攻倍率、shield 開場護盾、heal 開場回血、cdr 右鍵冷卻縮減由 DiceRun 另外算
# team：全隊都吃（每位擲的人各掛一個來源）；text 的 %s 填「每面的值 × 面數」（pct 的 × 100）
const EFFECTS := {
	&"fx_dmg": {"icon": "傷", "kind": &"stat", "stat": [&"damage", &"pct", 0.10], "text": "傷害 +%s%%", "pct": true},
	&"fx_basic": {"icon": "普", "kind": &"basic", "value": 0.20, "text": "普攻 +%s%%", "pct": true},
	&"fx_shield": {"icon": "盾", "kind": &"shield", "value": 15.0, "text": "開場護盾 +%s"},
	&"fx_heal": {"icon": "血", "kind": &"heal", "value": 0.10, "text": "開場回 %s%% 生命", "pct": true},
	&"fx_haste": {"icon": "速", "kind": &"stat", "stat": [&"attack_speed", &"pct", 0.10], "text": "攻速 +%s%%", "pct": true},
	&"fx_cdr": {"icon": "冷", "kind": &"cdr", "value": 0.10, "text": "右鍵冷卻 −%s%%", "pct": true},
	&"fx_speed": {"icon": "移", "kind": &"stat", "stat": [&"move_speed", &"pct", 0.08], "text": "移速 +%s%%", "pct": true},
	&"fx_guard": {"icon": "減", "kind": &"stat", "stat": [&"damage_taken", &"pct", -0.08], "text": "受傷 −%s%%", "pct": true},
	&"fx_crit": {"icon": "暴", "kind": &"stat", "stat": [&"crit_chance", &"add", 0.08], "text": "暴擊 +%s%%", "pct": true},
	&"fx_knock": {"icon": "退", "kind": &"stat", "stat": [&"knockback", &"pct", 0.30], "text": "擊退 +%s%%", "pct": true},
	&"fx_team_dmg": {"icon": "隊", "kind": &"stat", "stat": [&"damage", &"pct", 0.05], "team": true, "text": "全隊傷害 +%s%%", "pct": true},
	&"fx_team_shield": {"icon": "護", "kind": &"shield", "value": 8.0, "team": true, "text": "全隊開場護盾 +%s"},
}

# 開局的武器骰（6 顆一樣）：1 技能面 + 2 效果面 + 3 空白；沒列的武器用 FALLBACK_EFFECTS 配它第一個能用的技能
const WEAPON_DICE := {
	&"swordShield": [&"whirlwind", &"fx_shield", &"fx_dmg"],
	&"dagger": [&"knife_fan", &"fx_haste", &"fx_crit"],
	&"staff": [&"frost_nova", &"fx_cdr", &"fx_heal"],
	&"scepter": [&"holy_pillar", &"fx_cdr", &"fx_heal"],
	&"shortbow": [&"volley", &"fx_haste", &"fx_speed"],
	&"longbow": [&"arrow_rain", &"fx_dmg", &"fx_crit"],
	&"torch": [&"fire_nova", &"fx_dmg", &"fx_haste"],
	&"shovel": [&"ground_slam", &"fx_basic", &"fx_knock"],
}
const FALLBACK_EFFECTS := [&"fx_dmg", &"fx_shield"]

# 打完一場的獎勵：4 選 1，種類不重複（構想：單人 4 選 1）；新武器、新骰子的稀有度看這一場的難度（FIGHT_TIERS）
const REWARD_CHOICES := 4
const REWARD_KINDS := [&"die", &"weapon", &"carve_skill", &"carve_effect", &"item"]
const CARVE_SKILL_CHOICES := 3   # 刻技能面：選到才打開，從自己武器能用的技能裡幾選 1
# 骰子的稀有度（獎勵骰與掉落 / 獎勵武器的武器骰共用；跟武器稀有度同一套 id）：空白幾面、技能面幾面，其餘是效果
# 構想的表：灰 / 白 空白 2~3、技能 0~2；綠 / 藍 空白 1~2、技能 1~3；紫 / 橘 空白 0~1、技能 2~4
const RARITIES := {
	&"white": {"name": "白", "blanks": [2, 3], "skills": [0, 2]},
	&"green": {"name": "綠", "blanks": [1, 2], "skills": [1, 3]},
	&"blue": {"name": "藍", "blanks": [1, 2], "skills": [1, 3]},
	&"purple": {"name": "紫", "blanks": [0, 1], "skills": [2, 4]},
	&"orange": {"name": "橘", "blanks": [0, 1], "skills": [2, 4]},
}
# 一場的難度：一般群 / 有菁英（魔法、稀有）/ 有 Boss → 獎勵的稀有度權重（Claude 暫定）
const FIGHT_TIERS := {
	&"normal": {"name": "一般", "weights": {&"white": 50.0, &"green": 30.0, &"blue": 15.0, &"purple": 5.0}},
	&"elite": {"name": "菁英", "weights": {&"green": 35.0, &"blue": 40.0, &"purple": 20.0, &"orange": 5.0}},
	&"boss": {"name": "Boss", "weights": {&"blue": 40.0, &"purple": 40.0, &"orange": 20.0}},
}
const SPARE_WEAPONS := 2         # 備用武器最多幾把（沒有背包；滿了撿的那把直接跟手上的換，舊的掉在原地）
# 門的獎勵（MapGenDefs.DOOR_REWARDS 照地圖抽到的種類對應，地圖不變）：遺物 / 技能 → 下一關開頭多一次 4 選 1；袋子 / 靈魂 / 骰子 → 下一關每次擲骰的重擲 +1
const DOOR_REWARDS := {
	&"relic": {"kind": &"reward", "name": "獎勵 4 選 1"},
	&"skill": {"kind": &"reward", "name": "獎勵 4 選 1"},
	&"bag": {"kind": &"reroll", "name": "重擲 +1"},
	&"souls": {"kind": &"reroll", "name": "重擲 +1"},
	&"dice": {"kind": &"reroll", "name": "重擲 +1"},
}
const DOOR_REROLLS := 1
# 數值道具：拿了就一直有（掛屬性來源 dice_item:N）
const ITEMS := [
	{"name": "攻擊力 +8%", "stat": [&"damage", &"pct", 0.08]},
	{"name": "最大生命 +20", "stat": [&"max_hp", &"add", 20.0]},
	{"name": "攻速 +6%", "stat": [&"attack_speed", &"pct", 0.06]},
	{"name": "移速 +5%", "stat": [&"move_speed", &"pct", 0.05]},
	{"name": "受到傷害 −5%", "stat": [&"damage_taken", &"pct", -0.05]},
]


static func is_effect(face: StringName) -> bool:
	return EFFECTS.has(face)


static func is_skill(face: StringName) -> bool:
	return face != BLANK and SkillDefs.SKILLS.has(face)


# 畫面分顏色用：&"blank" / &"skill" / &"grey"（不是這把武器能放的技能，當空白）/ &"effect" / &"team"
static func kind_of(face: StringName, weapon_id: StringName) -> StringName:
	if face == BLANK:
		return &"blank"
	if is_effect(face):
		return &"team" if EFFECTS[face].get("team", false) else &"effect"
	return &"skill" if skill_fits(face, weapon_id) else &"grey"


static func skill_fits(id: StringName, weapon_id: StringName) -> bool:
	return is_skill(id) and SkillDefs.SKILLS[id].get("weapons", []).has(weapon_id)


static func icon_of(face: StringName) -> String:
	if face == BLANK:
		return ""
	return EFFECTS[face].icon if is_effect(face) else String(SkillDefs.SKILLS[face].icon)


static func name_of(face: StringName) -> String:
	if face == BLANK:
		return "空白"
	if is_effect(face):
		return effect_text(face, 1)
	return ItemDefs.ITEMS[face].name if ItemDefs.ITEMS.has(face) else String(face)


# n 面同一種效果疊起來的說明（「傷害 +20%」）
static func effect_text(id: StringName, n: int) -> String:
	var e: Dictionary = EFFECTS[id]
	var per: float = e.stat[2] if e.kind == &"stat" else e.value
	var v := absf(per) * n * (100.0 if e.get("pct", false) else 1.0)
	return e.text % (str(roundi(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v)


# 這把武器的開局骰子（一顆的 6 面）
static func weapon_die(weapon_id: StringName) -> Array[StringName]:
	var faces: Array[StringName] = []
	if WEAPON_DICE.has(weapon_id):
		faces.assign(WEAPON_DICE[weapon_id])
	else:
		var pool := skills_for(weapon_id)
		if not pool.is_empty():
			faces.append(pool[0])
		faces.append_array(FALLBACK_EFFECTS)
	while faces.size() < FACES:
		faces.append(BLANK)
	return faces


# 刻得上骰子的技能：這把武器能放、要耗魔的戰技與法術（輔助、袋子規則不算）
static func skills_for(weapon_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in SkillDefs.SKILLS:
		var def: Dictionary = SkillDefs.SKILLS[id]
		if def.has("mana") and def.get("category", &"") in [&"attack", &"spell"] and def.get("weapons", []).has(weapon_id) and not BIG.values().has(id):
			out.append(id)
	return out


# 結算 6 個朝上的面：同一招（這把武器能放的）數幾次、效果面各幾面
# choice：骰到好幾種技能時自己選的那招（沒選或不在裡面就選次數最多的，同樣多照先出現的）
# 回傳 { skill（實際放的 id，大招已換好）, base（骰面上的那招）, count, cands: [[id, 次數], ...], effects: { id: 面數 } }
static func evaluate(faces: Array, weapon_id: StringName, choice: StringName = &"") -> Dictionary:
	var counts := {}
	var order: Array[StringName] = []
	var effects := {}
	for f: StringName in faces:
		if is_effect(f):
			effects[f] = effects.get(f, 0) + 1
		elif skill_fits(f, weapon_id):
			if not counts.has(f):
				order.append(f)
			counts[f] = counts.get(f, 0) + 1
	var cands := []
	for i in order.size():
		cands.append([order[i], counts[order[i]], i])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1] or (a[1] == b[1] and a[2] < b[2]))
	var base: StringName = choice if counts.has(choice) else (cands[0][0] if not cands.is_empty() else &"")
	var count: int = counts.get(base, 0)
	var skill := base
	if count >= BIG_FROM and BIG.has(base):
		skill = BIG[base]
	return {"skill": skill, "base": base, "count": count, "cands": cands, "effects": effects}


static func tier_of(count: int) -> Dictionary:
	return TIERS[clampi(count, 0, TIERS.size() - 1)]


# 右鍵技能的冷卻（秒）：照原本的耗魔，再乘冷卻縮減（右鍵冷卻面每面 −10%，最多縮到 CDR_FLOOR 倍）
static func cooldown_of(skill: StringName, cdr: float) -> float:
	var base := maxf(COOLDOWN_MIN, float(SkillDefs.SKILLS[skill].get("mana", 0.0)) * COOLDOWN_PER_MANA)
	return base * maxf(CDR_FLOOR, 1.0 - cdr)


# 照稀有度產生一顆骰子（6 面）：空白、技能面（skills 裡抽，可以好幾種）、其餘效果面，最後打亂
static func make_die(rarity: StringName, skills: Array[StringName], rng: RandomNumberGenerator) -> Array[StringName]:
	var r: Dictionary = RARITIES.get(rarity, RARITIES[&"white"])
	var effects: Array = EFFECTS.keys()
	var faces: Array[StringName] = []
	for i in rng.randi_range(r.blanks[0], r.blanks[1]):
		faces.append(BLANK)
	if not skills.is_empty():
		for i in mini(FACES - faces.size(), rng.randi_range(r.skills[0], r.skills[1])):
			faces.append(skills[rng.randi_range(0, mini(2, skills.size() - 1))])
	while faces.size() < FACES:
		faces.append(effects[rng.randi_range(0, effects.size() - 1)])
	for i in range(faces.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := faces[i]
		faces[i] = faces[j]
		faces[j] = t
	return faces


# 這一場難度的稀有度（FIGHT_TIERS 的權重）
static func roll_rarity(tier: StringName, rng: RandomNumberGenerator) -> StringName:
	var w: Dictionary = FIGHT_TIERS.get(tier, FIGHT_TIERS[&"normal"]).weights
	var total := 0.0
	for k: StringName in w:
		total += float(w[k])
	var x := rng.randf() * total
	for k: StringName in w:
		x -= float(w[k])
		if x < 0.0:
			return k
	return w.keys()[0]
