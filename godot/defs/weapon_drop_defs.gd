# 武器掉落與詞條（D4；Build 改版第 8 步詞條改成跟羈絆有關）：殺怪機率掉武器、稀有度機率、詞條清單；武器實例的建立與合成
# 使用者決定（2026-10-23）：小怪 4%、Boss 必掉；小怪 白 60 / 綠 25 / 藍 12 / 紫 3、Boss 藍 60 / 紫 30 / 橘 10；
# 白色沒有詞條、每高一級多 1 條；2026-10-30 許家慶決定詞條都跟羈絆有關（種類照武器格子 artifact，數字 Claude 暫定）
# 主手與副手的詞條都生效；合成要在鍛造祭壇（Forge），兩把各留一條、其他重抽
# 武器實例：{ uid, base（WeaponDefs / ItemDefs 的武器 id）, rarity, affixes: Array[StringName] }
class_name WeaponDropDefs

const DROP_CHANCE := {&"grunt": 0.04, &"archer": 0.04, &"zombie": 0.04, &"bloater": 0.04, &"hound": 0.04, &"boss": 1.0, &"gravekeeper": 1.0}

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

# 詞條（Build 改版第 8 步，數字 Claude 暫定）：kind 決定種類，bond 是相關的羈絆（偏向與介面顏色用）
#   bond 羈絆 +1：這把武器本身算那個羈絆 1 件（Loadout.refresh_items）
#   enh 羈絆強化：那個羈絆專屬的數值（屬性，效果在 BondEffects）
#   cvt 屬性轉換：玩家的非道具物理傷害有 value 比例改成那個屬性（Combat，轉換的部分會疊狀態）
#   imp 印記格（藍以上，第 8b 步）：武器上 IMPRINT.cells 格標記，鑲在上面、屬於那個羈絆的道具效果 × IMPRINT.mul（Loadout.refresh_items）；
#       格子位置在實例的 imprints（make 時擲）
# mods 格式同 ItemDefs 的屬性效果；w 是抽中的權重（每個羈絆的強化合計 1）；min 是最低稀有度（沒寫 = 綠）
const AFFIXES := {
	&"bond_phys": {"kind": &"bond", "bond": &"phys", "desc": "算 1 件物理羈絆", "w": 1.0, "mods": []},
	&"bond_fire": {"kind": &"bond", "bond": &"fire", "desc": "算 1 件火焰羈絆", "w": 1.0, "mods": []},
	&"bond_cold": {"kind": &"bond", "bond": &"cold", "desc": "算 1 件冰霜羈絆", "w": 1.0, "mods": []},
	&"bond_guard": {"kind": &"bond", "bond": &"guard", "desc": "算 1 件防禦羈絆", "w": 1.0, "mods": []},
	&"bond_wisp": {"kind": &"bond", "bond": &"wisp", "desc": "算 1 件鬼火羈絆", "w": 1.0, "mods": []},
	&"enh_poise": {"kind": &"enh", "bond": &"phys", "desc": "失衡值累積 +40%", "w": 0.5, "mods": [[&"poise_gain", Stats.PCT, 0.4]]},
	&"enh_knockback": {"kind": &"enh", "bond": &"phys", "desc": "擊退 +25%", "w": 0.5, "mods": [[&"knockback", Stats.PCT, 0.25]]},
	&"enh_burn_cap": {"kind": &"enh", "bond": &"fire", "desc": "燃燒層數上限 +2", "w": 0.5, "mods": [[&"burn_max_stacks", Stats.ADD, 2.0]]},
	&"enh_burn_damage": {"kind": &"enh", "bond": &"fire", "desc": "燃燒傷害 +25%", "w": 0.5, "mods": [[&"burn_damage", Stats.PCT, 0.25]]},
	&"enh_chill_cap": {"kind": &"enh", "bond": &"cold", "desc": "冰冷層數上限 +2", "w": 0.5, "mods": [[&"chill_max_stacks", Stats.ADD, 2.0]]},
	&"enh_freeze": {"kind": &"enh", "bond": &"cold", "desc": "凍結時間 +50%", "w": 0.5, "mods": [[&"freeze_time", Stats.PCT, 0.5]]},
	&"enh_parry": {"kind": &"enh", "bond": &"guard", "desc": "招架判定時間 +50%", "w": 0.5, "mods": [[&"parry_window", Stats.PCT, 0.5]]},
	&"enh_armor": {"kind": &"enh", "bond": &"guard", "desc": "護甲 +15", "w": 0.5, "mods": [[&"armor", Stats.ADD, 15.0]]},
	&"enh_wisp_count": {"kind": &"enh", "bond": &"wisp", "desc": "鬼火 +1 顆（秘術）", "w": 0.5, "mods": [[&"wisp_count", Stats.ADD, 1.0]]},
	&"enh_wisp_damage": {"kind": &"enh", "bond": &"wisp", "desc": "鬼火傷害 +25%", "w": 0.5, "mods": [[&"wisp_damage", Stats.PCT, 0.25]]},
	&"cvt_fire": {"kind": &"cvt", "bond": &"fire", "desc": "50% 物理傷害轉成火焰", "w": 1.0, "mods": [[&"convert_fire", Stats.ADD, 0.5]]},
	&"cvt_cold": {"kind": &"cvt", "bond": &"cold", "desc": "50% 物理傷害轉成冰霜", "w": 1.0, "mods": [[&"convert_cold", Stats.ADD, 0.5]]},
	&"imp_phys": {"kind": &"imp", "bond": &"phys", "desc": "物理印記格：鑲在上面的物理道具效果 ×1.5", "w": 0.6, "min": &"blue", "mods": []},
	&"imp_fire": {"kind": &"imp", "bond": &"fire", "desc": "火焰印記格：鑲在上面的火焰道具效果 ×1.5", "w": 0.6, "min": &"blue", "mods": []},
	&"imp_cold": {"kind": &"imp", "bond": &"cold", "desc": "冰霜印記格：鑲在上面的冰霜道具效果 ×1.5", "w": 0.6, "min": &"blue", "mods": []},
	&"imp_guard": {"kind": &"imp", "bond": &"guard", "desc": "防禦印記格：鑲在上面的防禦道具效果 ×1.5", "w": 0.6, "min": &"blue", "mods": []},
	&"imp_wisp": {"kind": &"imp", "bond": &"wisp", "desc": "鬼火印記格：鑲在上面的鬼火道具效果 ×1.5", "w": 0.6, "min": &"blue", "mods": []},
}

# 印記格（第 8b 步，Claude 暫定）：每條印記詞條標 cells 格（不標寶石座）；道具的屬性數值（加 / 百分比 × mul，相乘的取 mul 次方）
# 與觸發機率 × mul（ItemDefs.stat_mods、ItemEffects.procs_of）；條件加成、能力（鬼火燈顆數這類）不變
const IMPRINT := {"cells": 2, "mul": 1.5}

# 屬性轉換：轉換屬性 → 傷害屬性（Combat 依序處理，合計最多 100%）
const CONVERSIONS := [[&"convert_fire", &"fire"], [&"convert_cold", &"cold"]]

# 武器偏向（artifact 的表，Claude 暫定）：這些羈絆的詞條權重 × BIAS_MUL；第一版只有 5 個羈絆，表上其他的（暗影、神聖…）之後再加
const BIAS_MUL := 3.0
const BIAS := {
	&"longsword": [&"phys", &"guard"], &"woodShield": [&"guard", &"phys"], &"dagger": [&"phys"],
	&"torch": [&"fire"], &"staff": [&"wisp", &"fire", &"cold"], &"scepter": [&"wisp", &"guard"],
	&"shortbow": [&"phys"], &"longbow": [&"phys", &"cold"], &"shovel": [&"phys", &"guard"],
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


# treasure = 全隊最高的尋寶（F1，見 World.team_treasure）
static func roll_rarity(source: StringName, rng: RandomNumberGenerator, treasure := 0.0) -> StringName:
	return LootDefs.pick_rarity(LootDefs.treasure_weights(RARITY_WEIGHTS[source], treasure), rng)


# 不重複地抽 count 條詞條：依 AFFIXES 的權重（武器偏向的羈絆 × BIAS_MUL）一條一條抽，用 world.rng 才有決定性；
# keep 是一定要留的（合成時兩把各挑的那條），先放進去、不重複；rarity 低於詞條的 min 就不抽（keep 也一樣）
static func roll_affixes(count: int, rng: RandomNumberGenerator, base := &"", keep: Array[StringName] = [], rarity := &"orange") -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in keep:
		if AFFIXES.has(id) and allowed(id, rarity) and not out.has(id) and out.size() < count:
			out.append(id)
	var favored: Array = BIAS.get(base, [])
	var pool: Array[StringName] = []
	var weights: Array[float] = []
	for id: StringName in AFFIXES:
		if out.has(id) or not allowed(id, rarity):
			continue
		pool.append(id)
		weights.append(AFFIXES[id].w * (BIAS_MUL if favored.has(AFFIXES[id].bond) else 1.0))
	while out.size() < count and not pool.is_empty():
		var total := 0.0
		for w in weights:
			total += w
		var r := rng.randf() * total
		var i := 0
		while i < pool.size() - 1 and r >= weights[i]:
			r -= weights[i]
			i += 1
		out.append(pool[i])
		pool.remove_at(i)
		weights.remove_at(i)
	return out


# 這種稀有度能不能出這條詞條（AFFIXES 的 min）
static func allowed(id: StringName, rarity: StringName) -> bool:
	return RARITY_ORDER.find(rarity) >= RARITY_ORDER.find(AFFIXES[id].get("min", &"green"))


static func make(uid: StringName, base: StringName, rarity: StringName, rng: RandomNumberGenerator, keep: Array[StringName] = []) -> Dictionary:
	var inst := {"uid": uid, "base": base, "rarity": rarity, "affixes": roll_affixes(affix_count(rarity), rng, base, keep, rarity)}
	roll_imprints(inst, rng)
	return add_builtin_skill(inst)


# 印記詞條的格子：每條從武器格子裡（不含寶石座、不和別條重疊）隨機挑 IMPRINT.cells 格，寫進 inst.imprints [{ bond, cell }]
static func roll_imprints(inst: Dictionary, rng: RandomNumberGenerator) -> void:
	inst.erase("imprints")
	var cells := WeaponDefs.grid_cells(ItemDefs.ITEMS[inst.base].weapon)
	var free: Array[Vector2i] = []
	for c: Vector2i in cells:
		if cells[c] != "G":
			free.append(c)
	free.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var out: Array[Dictionary] = []
	for id: StringName in inst.affixes:
		if AFFIXES[id].kind != &"imp":
			continue
		for i in IMPRINT.cells:
			if free.is_empty():
				break
			out.append({"bond": AFFIXES[id].bond, "cell": free.pop_at(rng.randi_range(0, free.size() - 1))})
	if not out.is_empty():
		inst["imprints"] = out


# 道具 e（武器格子裡的條目 { id, cell, rot }）的效果倍率：碰到同羈絆的印記格就是 IMPRINT.mul
static func imprint_mul(inst: Dictionary, e: Dictionary) -> float:
	var bonds: Array = ItemDefs.ITEMS[e.id].get("bonds", [])
	for im: Dictionary in inst.get("imprints", []):
		if bonds.has(im.bond) and Inventory.cells_of(e.id, e.rot).any(func(c: Vector2i) -> bool: return e.cell + c == im.cell):
			return IMPRINT.mul
	return 1.0


# 武器自帶的技能（WeaponDefs 的 slot_skill，火把的插火把）：出廠就鑲在第一個寶石座；之後可以拿下來
static func add_builtin_skill(inst: Dictionary) -> Dictionary:
	var w: Dictionary = WeaponDefs.WEAPONS[ItemDefs.ITEMS[inst.base].weapon]
	if not w.has("slot_skill"):
		return inst
	var cells := WeaponDefs.grid_cells(ItemDefs.ITEMS[inst.base].weapon)
	var gems: Array = cells.keys().filter(func(c: Vector2i) -> bool: return cells[c] == "G")
	gems.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	if not gems.is_empty():
		var sockets: Array[Dictionary] = [{"uid": StringName("%s_skill" % inst.uid), "id": w.slot_skill, "cell": gems[0], "rot": 0}]
		inst["sockets"] = sockets
	return inst


# 武器的基礎數值（介面顯示用的實際數字）：攻擊力 = 普攻傷害、攻速 = 每秒普攻次數、範圍 = 揮砍距離或魔彈射程，都乘上稀有度倍率；
# 只能當副手的（盾）沒有普攻，回傳 {}
static func base_stats(inst: Dictionary) -> Dictionary:
	var wd: Dictionary = WeaponDefs.WEAPONS[ItemDefs.ITEMS[inst.base].weapon]
	if not wd.has("attack"):
		return {}
	var atk: Dictionary = wd.attack
	var m: Dictionary = RARITY_BASE[inst.rarity]
	return {
		"damage": WeaponDefs.move_base_damage(wd, atk) * m.damage,
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
	mods.append_array(offhand_mods(inst))
	return mods


# 副手生效的屬性：只有詞條（稀有度的攻擊力、攻速倍率只算主手，Claude 暫定）
static func offhand_mods(inst: Dictionary) -> Array:
	var mods := []
	for id: StringName in inst.affixes:
		mods.append_array(AFFIXES[id].mods)
	return mods


# 這把武器的「羈絆 +1」詞條算哪些羈絆（Loadout.refresh_items）
static func bonds_of(inst: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in inst.get("affixes", []):
		if AFFIXES[id].kind == &"bond":
			out.append(AFFIXES[id].bond)
	return out


# 能不能合成：同種、同稀有度、不是同一把、還沒到最高（橘色）
static func can_merge(a: Dictionary, b: Dictionary) -> bool:
	return not a.is_empty() and not b.is_empty() and a.uid != b.uid and a.base == b.base \
		and a.rarity == b.rarity and next_rarity(a.rarity) != &""


# 快照用：[uid, base, rarity, [詞條…], 武器技能剩幾次?, 鑲的道具?, 印記格?]；空的主手 / 副手是 []；
# 次數沒用過（滿的）送 -1、沒鑲東西也沒印記格就不送後面幾欄。鑲的道具：[[uid, id, x, y, rot], …]；印記格：[[羈絆, x, y], …]
static func to_array(inst: Dictionary) -> Array:
	if inst.is_empty():
		return []
	var affixes := []
	for id: StringName in inst.affixes:
		affixes.append(String(id))
	var a := [String(inst.uid), String(inst.base), String(inst.rarity), affixes]
	var sockets: Array = inst.get("sockets", [])
	var imprints: Array = inst.get("imprints", [])
	if inst.has("slot_charges") or not sockets.is_empty() or not imprints.is_empty():
		a.append(inst.get("slot_charges", -1))
	if not sockets.is_empty() or not imprints.is_empty():
		var arr := []
		for e: Dictionary in sockets:
			arr.append([String(e.uid), String(e.id), e.cell.x, e.cell.y, e.rot])
		a.append(arr)
	if not imprints.is_empty():
		a.append(imprints.map(func(im: Dictionary) -> Array: return [String(im.bond), im.cell.x, im.cell.y]))
	return a


static func from_array(a: Array) -> Dictionary:
	if a.is_empty():
		return {}
	var affixes: Array[StringName] = []
	for s: String in a[3]:
		affixes.append(StringName(s))
	var inst := {"uid": StringName(a[0]), "base": StringName(a[1]), "rarity": StringName(a[2]), "affixes": affixes}
	if a.size() > 4 and int(a[4]) >= 0:
		inst["slot_charges"] = int(a[4])
	if a.size() > 5:
		var sockets: Array[Dictionary] = []
		for e: Array in a[5]:
			sockets.append({"uid": StringName(e[0]), "id": StringName(e[1]), "cell": Vector2i(e[2], e[3]), "rot": int(e[4])})
		inst["sockets"] = sockets
	if a.size() > 6:
		var imprints: Array[Dictionary] = []
		for im: Array in a[6]:
			imprints.append({"bond": StringName(im[0]), "cell": Vector2i(im[1], im[2])})
		inst["imprints"] = imprints
	return inst


# 次數記在武器上的技能（插火把，weapon_charges）還剩幾次：記在鑲著它的武器實例的 slot_charges，沒有就是滿的；沒鑲這種技能回傳 -1
static func slot_charges(inst: Dictionary) -> int:
	if inst.is_empty():
		return -1
	for e: Dictionary in inst.get("sockets", []):
		var def: Dictionary = SkillDefs.SKILLS.get(e.id, {})
		if def.get("weapon_charges", false):
			return inst.get("slot_charges", def.charges)
	return -1


# 名稱；有武器技能次數的接在後面括號（「白色 火把（2）」）
static func display_name(inst: Dictionary) -> String:
	var text := "%s %s" % [ItemDefs.RARITIES[inst.rarity].name, ItemDefs.ITEMS[inst.base].name]
	var n := slot_charges(inst)
	return text + ("（%d）" % n if n >= 0 else "")
