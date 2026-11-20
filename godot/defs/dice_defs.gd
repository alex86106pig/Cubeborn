# 骰子模式的資料（規則在 docs/改版構想.md「骰子模式」、做法在 docs/系統說明.md §55）：骰面、效果、威力、獎勵、時間；數字 Claude 暫定
# 骰面是 StringName：技能 id（SkillDefs.SKILLS）、效果 id（EFFECTS，fx_ 開頭）、&"" = 空白
class_name DiceDefs
extends RefCounted

const DICE_COUNT := 6
const FACES := 6
const BLANK := &""
const ROLL_TIME := 10.0         # 每人限時：沒擲就自動擲、擲過了沒按完成就自動完成
const SETTLE_TIME := 1.0        # 擲出去之後骰子轉的時間：這段不收操作、不倒數（畫面播動畫）
const PHYSICS_WAIT := 9.0       # 物理擲骰（DiceRun.physics）：丟出去之後最多等桌子回報幾秒（從放開算；DiceTable 自己 6 秒一定停好，多留 3 秒），超過就由模擬層抽
const REROLLS := 1              # 每場可以重擲沒鎖的幾次
const COUNTDOWN := 2.4          # 全部擲完 → 3、2、1 → 開打
# 每一場都擲（YangHsu 2026-11-19 改回構想的流程；中間一版是「擲骰次數、R 隨時擲」）。沒中技能面就只有普攻（不保底）
const CHARGES_STAGE := 2        # 重擲券：每一關開頭 +幾張（第一關開局也是）；擲骰時免費重擲用完，再丟沒留的花 1 張
const CHARGES_PER_FIGHT := 1    # 打完一場 +幾張
const CHARGES_MAX := 3          # 最多存幾張
const CLEAR_TIME := 1.5         # 這一場的怪全倒之後停多久才選獎勵（清場：世界照常動，怪倒完、掉的武器出來；Claude 暫定）
const MERGE_RANGE := 22.0       # 碰到一群怪時，中心這麼近（直線與走過去的路都要在這麼近內）的怪群一起醒、併成一場；隔著牆要繞路的不併，不然繞的路出了霧牆會卡在圈邊
const NOTICE_DETOUR := 1.5      # 怪靠近（notice_close）或聽到打鬥（noise_radius）發現玩家時，走過去的路不能超過那個距離的這麼多倍（隔著牆的不算）
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
# 組合（YangHsu 2026-11-19：「順子那些組合也做上去」；條件與效果 Claude 暫定）：看 6 個朝上的面，可以同時成立好幾個
#   順子：6 面都不一樣、沒有空白（別的武器的技能面算空白）→ 技能威力 +1 級、全部效果 ×2
#   葫蘆：同一招 3 面以上 + 同一種效果 2 面以上 → 技能威力 +1 級
#   三條：同一種效果 3 面以上 → 那種效果 ×1.5
#   兩對：兩種以上的效果各 2 面以上 → 那幾種效果各多算 1 面（先算，再算三條）
# 「威力 +1 級」只換威力倍率（TIERS 往上一格），換大招（BIG_FROM）還是看真的骰到幾個
const COMBOS := {
	&"straight": {"name": "順子", "text": "技能威力 +1 級、全部效果 ×2", "power": 1, "effects_mul": 2.0},
	&"full_house": {"name": "葫蘆", "text": "技能威力 +1 級", "power": 1},
	&"three": {"name": "三條", "text": "那種效果 ×1.5", "three_mul": 1.5},
	&"two_pair": {"name": "兩對", "text": "那兩種效果各多算 1 面", "pair_add": 1.0},
}
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
static func effect_text(id: StringName, n: float) -> String:
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
	# 組合（COMBOS）：效果面數改成小數（三條 ×1.5），威力看 tier_count
	var combos: Array[StringName] = []
	var power := 0
	var distinct := {}
	var real := faces.size() == FACES
	for f: StringName in faces:
		if f == BLANK or (is_skill(f) and not skill_fits(f, weapon_id)):
			real = false
		distinct[f] = true
	var pairs: Array[StringName] = []
	var threes: Array[StringName] = []
	for id: StringName in effects:
		if effects[id] >= 2:
			pairs.append(id)
		if effects[id] >= 3:
			threes.append(id)
	if real and distinct.size() == FACES:
		combos.append(&"straight")
	if count >= 3 and not pairs.is_empty():
		combos.append(&"full_house")
	if not threes.is_empty():
		combos.append(&"three")
	if pairs.size() >= 2:
		combos.append(&"two_pair")
	var eff := {}
	for id: StringName in effects:
		eff[id] = float(effects[id])
	for c: StringName in combos:
		power += int(COMBOS[c].get("power", 0))
	if combos.has(&"two_pair"):
		for id in pairs:
			eff[id] += COMBOS[&"two_pair"].pair_add
	if combos.has(&"three"):
		for id in threes:
			eff[id] *= COMBOS[&"three"].three_mul
	if combos.has(&"straight"):
		for id: StringName in eff:
			eff[id] *= COMBOS[&"straight"].effects_mul
	var tier_count := mini(TIERS.size() - 1, count + power) if count > 0 else 0
	return {"skill": skill, "base": base, "count": count, "tier_count": tier_count, "cands": cands, "effects": eff, "combos": combos}


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


# ---------- 連線（快照，docs/系統說明.md §55「連線」）----------
# 骰面編碼成 1 個位元組：0 = 空白、接著是 SkillDefs.SKILLS、再來是 EFFECTS（兩邊程式一樣，表的順序就一樣）
static var _codes: Array[StringName] = []
static var _code_of: Dictionary = {}


static func _face_codes() -> void:
	if not _codes.is_empty():
		return
	_codes.append(BLANK)
	for id: StringName in SkillDefs.SKILLS:
		_codes.append(id)
	for id: StringName in EFFECTS:
		_codes.append(id)
	assert(_codes.size() < 256)
	for i in _codes.size():
		_code_of[_codes[i]] = i


# 好幾顆骰子（每顆 FACES 面）接成一串位元組
static func dice_to_bytes(dice: Array) -> PackedByteArray:
	_face_codes()
	var out := PackedByteArray()
	for die: Array in dice:
		for f: StringName in die:
			out.append(_code_of.get(f, 0))
	return out


static func dice_from_bytes(b: PackedByteArray) -> Array:
	_face_codes()
	var out := []
	for i in range(0, b.size() - FACES + 1, FACES):
		var die: Array[StringName] = []
		for j in FACES:
			die.append(_codes[b[i + j]] if b[i + j] < _codes.size() else BLANK)
		out.append(die)
	return out


# ---------- 戰場霧牆、隊長帶隊、擲骰演出（§55，數字 Claude 暫定）----------
# 霧牆：開一場時以這一場的怪為中心圍一圈（要圈住這一場的怪與活著的玩家，再留 ARENA_MARGIN），夾在 MIN~MAX；Boss 直接用 MAX
# 圈裡的玩家與這一場的怪出不去；圈外的怪群打完之前不會發現玩家
const DOWNED_REVIVE_HP := 0.3    # 倒地：不倒數，這一場打完自動站起、剩這麼多生命（構想）
const ARENA_MARGIN := 3.0
const ARENA_MIN := 9.0
const ARENA_MAX := 16.0
# 隊長帶隊：逛地圖時第一位能動的玩家（房主）帶隊，其他人跟在他身後的位置（隊長的座標：x 往右、y 往後）；第 4 位以後往後排
const FOLLOW_SLOTS: Array[Vector2] = [Vector2(-1.6, 1.4), Vector2(1.6, 1.4), Vector2(0.0, 2.6)]
const FOLLOW_DEADZONE := 0.45     # 離位置這麼近就站著
const FOLLOW_TELEPORT := 14.0     # 離隊長的位置這麼遠（卡住、剛換場地）直接搬過去
# 擲骰演出：只剩最後一顆在滾、而它停在某一面就能湊到 3 個以上同一招時，桌子放慢、鏡頭推近、音樂收小
const SUSPENSE_SLOW := 0.3        # 放慢到幾倍速
const SUSPENSE_MAX := 1.6         # 最多放慢這麼多秒（實際時間）
const SHOW_TICK_GAP := 0.11       # 揭曉時每個中的技能面「叮」一聲的間隔，一聲比一聲高
const SHOW_TICK_PITCH := 0.12     # 每一聲高多少（音高倍率）
const TRAY_VIEW := 16.0           # 擲骰時鏡頭看多大（可視高度；平常 20）：骰盤 12 寬要放得下
const TRAY_VIEW_FOCUS := 11.0     # 放慢時推近
const TRAY_ELEVATION := 1.134      # 擲骰時鏡頭的俯角（65°）（平常 Config.CAMERA.elevation 約 40°：骰盤看起來太斜、骰面不好讀）；不要到 90°（look_at 朝上會轉不出方向）
const TRAY_SCREEN_UP := 2.5      # 骰盤在畫面上往上挪多少（世界單位）
const TRAY_LIFT := 1.0            # 骰盤比底下最高的地面高多少（底下有木座，看起來是一個擺著的骰盒）
const SHOW_SHAKE := 0.18          # 中了強化 / 組合的畫面震動（受傷是 0.25）
const SHOW_SHAKE_BIG := 0.35      # 中了大招以上
