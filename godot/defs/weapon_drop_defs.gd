# 武器掉落與詞條（D4；Build 改版第 8 步詞條改成跟羈絆有關）：殺怪機率掉武器、稀有度機率、詞條清單；武器實例的建立與合成
# 【詞條目前沒使用】觸發袋改版後 make 做出來的武器都沒有詞條；AFFIXES / BRANCH / IMPRINT / CONVERSIONS / BIAS、roll_affixes、roll_imprints、
# affix_count、allowed 先留著（許家慶 2026-11-05：之後可能再用），只有武器測試場的詞條按鈕還做得出帶詞條的武器。下面 2~4 行是當時的規則
# 使用者決定（2026-10-23）：小怪 4%（2026-11-01 改成照層數 1.5% / 2.5% / 4%）、Boss 必掉；小怪 白 60 / 綠 25 / 藍 12 / 紫 3、Boss 藍 60 / 紫 30 / 橘 10；
# 白色沒有詞條、每高一級多 1 條；2026-10-30 許家慶決定詞條都跟羈絆有關（種類照武器格子 artifact，數字 Claude 暫定）
# 主手與副手的詞條都生效；合成要在鍛造祭壇（Forge），兩把各留一條、其他重抽
# 武器實例：{ uid, base（WeaponDefs / ItemDefs 的武器 id）, rarity, affixes: Array[StringName] }
class_name WeaponDropDefs

# 小怪掉武器的機率照層數（使用者 2026-11-01 決定：原本每層都 4%，自動試玩量到第 1 層全清就掉 8~19 把、背包 48 格被武器占 28~46 格；
# 要第 2~3 層才滿）；超過表的層用最後一層。召喚出來的怪（no_souls）不掉，同靈魂與金幣
const MINION_DROP_BY_FLOOR := {1: 0.015, 2: 0.025, 3: 0.04}
const MINION_TYPES := [&"grunt", &"archer", &"zombie", &"bloater", &"hound", &"spearman", &"bone_wheel", &"beetle", &"spider"]
const BOSS_TYPES := [&"boss", &"gravekeeper", &"bone_general"]   # 必掉


# 這種怪在第 floor_num 層死掉時掉武器的機率（不在兩張表的怪不掉：冤魂、骷髏僕從）
static func drop_chance(type: StringName, floor_num: int) -> float:
	if type in BOSS_TYPES:
		return 1.0
	if not type in MINION_TYPES:
		return 0.0
	var last: int = MINION_DROP_BY_FLOOR.keys().max()
	return MINION_DROP_BY_FLOOR[clampi(floor_num, 1, last)]

const RARITY_WEIGHTS := {
	&"minion": {&"white": 60.0, &"green": 25.0, &"blue": 12.0, &"purple": 3.0},
	&"boss": {&"blue": 60.0, &"purple": 30.0, &"orange": 10.0},
}

const RARITY_ORDER: Array[StringName] = [&"white", &"green", &"blue", &"purple", &"orange"]   # 掉落的稀有度（低 → 高）

# 起始武器的稀有度（許家慶 2026-11-05 決定）：灰色，數值固定 = 武器資料本身（--balance 量的就是這個），比白色低；
# 不在 RARITY_ORDER 裡（find 是 -1，比所有掉落的都低）、不掉落、不能合成
const START_RARITY := &"gray"

# 武器基礎數值的倍率依稀有度提高（v0.27.0 使用者決定：要看得到實際數字）；這裡是每個稀有度的平均（I-5，許家慶 2026-11-05：
# 灰色 = 原本的白色、掉落的往上推）：攻擊力 白 1.1、每級 +0.2，攻速、範圍、最大魔力、回魔每級 +5%
const RARITY_BASE := {
	&"gray": {"damage": 1.0, "attack_speed": 1.0, "range": 1.0, "max_mana": 1.0, "mana_regen": 1.0},
	&"white": {"damage": 1.1, "attack_speed": 1.05, "range": 1.05, "max_mana": 1.05, "mana_regen": 1.05},
	&"green": {"damage": 1.3, "attack_speed": 1.10, "range": 1.10, "max_mana": 1.10, "mana_regen": 1.10},
	&"blue": {"damage": 1.5, "attack_speed": 1.15, "range": 1.15, "max_mana": 1.15, "mana_regen": 1.15},
	&"purple": {"damage": 1.7, "attack_speed": 1.20, "range": 1.20, "max_mana": 1.20, "mana_regen": 1.20},
	&"orange": {"damage": 1.9, "attack_speed": 1.25, "range": 1.25, "max_mana": 1.25, "mana_regen": 1.25},
}
# 掉落的武器每項倍率 = 平均 × (1 ± 寬度)，均勻分布、每項各擲一次（I-5，許家慶 2026-11-05 選「寬」：同稀有度差很多，爛的綠會輸好的白）；
# 攻擊力擲完取整數（武器資料的 base_damage × 倍率四捨五入，至少 1），最大魔力也取整數，其他取到 0.01
const ROLL_KEYS: Array[String] = ["damage", "attack_speed", "range", "max_mana", "mana_regen"]
const ROLL_SPREAD := {"damage": 0.2, "attack_speed": 0.1, "range": 0.1, "max_mana": 0.25, "mana_regen": 0.25}

# 【目前沒使用，見檔案開頭】詞條（Build 改版第 8 步，數字 Claude 暫定）：kind 決定種類，bond 是相關的羈絆（偏向與介面顏色用）
#   bond 羈絆 +1：這把武器本身算那個羈絆 1 件（Loadout.refresh_items）
#   enh 羈絆強化：那個羈絆專屬的數值（屬性，效果在 BondEffects）
#   cvt 屬性轉換：玩家的非道具物理傷害有 value 比例改成那個屬性（Combat，轉換的部分會疊狀態）
#   imp 印記格（藍以上，第 8b 步）：武器上 IMPRINT.cells 格標記，鑲在上面、屬於那個羈絆的道具效果 × IMPRINT.mul（Loadout.refresh_items）；
#       格子位置在實例的 imprints（make 時擲）
#   branch 分支（紫橘，第 8c 步）：改寫一個羈絆的規則，一把最多 1 條（roll_affixes）；有沒有在 Loadout.branches，效果在 BondEffects / Player
#   mana 魔力：唯一不屬於羈絆的種類（bond 空的，不受武器偏向影響），合計權重 MANA_AFFIX_W
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
	&"mana_max": {"kind": &"mana", "bond": &"", "desc": "最大魔力 +30", "w": 0.5, "mods": [[&"max_mana", Stats.ADD, 30.0]]},
	&"mana_regen": {"kind": &"mana", "bond": &"", "desc": "每秒回魔 +2", "w": 0.5, "mods": [[&"mana_regen", Stats.ADD, 2.0]]},
	&"mana_cost": {"kind": &"mana", "bond": &"", "desc": "耗魔 −10%", "w": 0.5, "mods": [[&"mana_cost", Stats.MUL, 0.9]]},
	&"mana_hit": {"kind": &"mana", "bond": &"", "desc": "命中回復 1 魔力（每 0.3 秒最多一次）", "w": 0.5, "mods": [[&"mana_on_hit", Stats.ADD, 1.0]]},
	&"cvt_fire": {"kind": &"cvt", "bond": &"fire", "desc": "50% 物理傷害轉成火焰", "w": 1.0, "mods": [[&"convert_fire", Stats.ADD, 0.5]]},
	&"cvt_cold": {"kind": &"cvt", "bond": &"cold", "desc": "50% 物理傷害轉成冰霜", "w": 1.0, "mods": [[&"convert_cold", Stats.ADD, 0.5]]},
	&"imp_phys": {"kind": &"imp", "bond": &"phys", "desc": "物理印記格：鑲在上面的物理道具效果 ×1.5", "w": 0.6, "min": &"blue", "mods": []},
	&"imp_fire": {"kind": &"imp", "bond": &"fire", "desc": "火焰印記格：鑲在上面的火焰道具效果 ×1.5", "w": 0.6, "min": &"blue", "mods": []},
	&"imp_cold": {"kind": &"imp", "bond": &"cold", "desc": "冰霜印記格：鑲在上面的冰霜道具效果 ×1.5", "w": 0.6, "min": &"blue", "mods": []},
	&"imp_guard": {"kind": &"imp", "bond": &"guard", "desc": "防禦印記格：鑲在上面的防禦道具效果 ×1.5", "w": 0.6, "min": &"blue", "mods": []},
	&"imp_wisp": {"kind": &"imp", "bond": &"wisp", "desc": "鬼火印記格：鑲在上面的鬼火道具效果 ×1.5", "w": 0.6, "min": &"blue", "mods": []},
	&"br_heavy": {"kind": &"branch", "bond": &"phys", "desc": "分支・沉重：攻速 −30%、失衡值累積 ×2.5", "w": 0.5, "min": &"purple",
		"mods": [[&"attack_speed", Stats.MUL, 0.7], [&"poise_gain", Stats.MUL, 2.5]]},
	&"br_burn_rush": {"kind": &"branch", "bond": &"fire", "desc": "分支・爆燃：燃燒不疊層，再打中就一次打完剩下的燃燒", "w": 0.5, "min": &"purple", "mods": []},
	&"br_ice_coffin": {"kind": &"branch", "bond": &"cold", "desc": "分支・冰棺：凍結改成 3 秒冰棺、不碎冰，受傷的 50% 分給旁邊 4 隻", "w": 0.5, "min": &"purple", "mods": []},
	&"br_counter": {"kind": &"branch", "bond": &"guard", "desc": "分支・反擊架勢：不拿盾也能招架（普攻剛出手時），判定時間減半", "w": 0.5, "min": &"purple", "mods": []},
	&"br_star": {"kind": &"branch", "bond": &"wisp", "desc": "分支・星位：鬼火停在上次翻滾的地方當砲台", "w": 0.5, "min": &"purple", "mods": []},
}

# 分支的數字（第 8c 步，Claude 暫定；描述在 AFFIXES 的 desc）
const BRANCH := {
	"coffin_time": 3.0, "coffin_share": 0.5, "coffin_radius": 3.0, "coffin_targets": 4,   # 冰棺
	"counter_window_mul": 0.5, "counter_arc": PI * 0.67,   # 反擊架勢：盾的判定時間 × 0.5、正面 120°
	"star_leash": 20.0,                                      # 星位：離錨點超過這麼遠（換層、跑遠）鬼火回到身邊
}

# 印記格（第 8b 步，Claude 暫定）：每條印記詞條標 cells 格（不標寶石座）；道具的屬性數值（加 / 百分比 × mul，相乘的取 mul 次方）
# 與觸發機率 × mul（ItemDefs.stat_mods、ItemEffects.procs_of）；條件加成、能力（鬼火燈顆數這類）不變
const IMPRINT := {"cells": 2, "mul": 1.5}

# 屬性轉換：轉換屬性 → 傷害屬性（Combat 依序處理，合計最多 100%）
const CONVERSIONS := [[&"convert_fire", &"fire"], [&"convert_cold", &"cold"]]

# 武器偏向（artifact 的表，Claude 暫定）：這些羈絆的詞條權重 × BIAS_MUL；第一版只有 5 個羈絆，表上其他的（暗影、神聖…）之後再加
const BIAS_MUL := 3.0
const BIAS := {
	&"swordShield": [&"phys", &"guard"], &"dagger": [&"phys"],
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


# 【目前沒使用】不重複地抽 count 條詞條：依 AFFIXES 的權重（武器偏向的羈絆 × BIAS_MUL）一條一條抽，用 world.rng 才有決定性；
# keep 是一定要留的（合成時兩把各挑的那條），先放進去、不重複；rarity 低於詞條的 min 就不抽（keep 也一樣）
static func roll_affixes(count: int, rng: RandomNumberGenerator, base := &"", keep: Array[StringName] = [], rarity := &"orange") -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in keep:
		if AFFIXES.has(id) and allowed(id, rarity) and not out.has(id) and out.size() < count:
			if AFFIXES[id].kind == &"branch" and out.any(func(o: StringName) -> bool: return AFFIXES[o].kind == &"branch"):
				continue   # 兩把各留一條分支：只留第一條
			out.append(id)
	var favored: Array = BIAS.get(base, [])
	var pool: Array[StringName] = []
	var weights: Array[float] = []
	for id: StringName in AFFIXES:
		if out.has(id) or not allowed(id, rarity):
			continue
		pool.append(id)
		weights.append(AFFIXES[id].w * (BIAS_MUL if favored.has(AFFIXES[id].bond) else 1.0))
	var has_branch := out.any(func(id: StringName) -> bool: return AFFIXES[id].kind == &"branch")
	if has_branch:
		_drop_branches(pool, weights)
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
		var picked_branch: bool = AFFIXES[pool[i]].kind == &"branch"
		pool.remove_at(i)
		weights.remove_at(i)
		if picked_branch:
			_drop_branches(pool, weights)   # 分支一把最多 1 條
	return out


static func _drop_branches(pool: Array[StringName], weights: Array[float]) -> void:
	for j in range(pool.size() - 1, -1, -1):
		if AFFIXES[pool[j]].kind == &"branch":
			pool.remove_at(j)
			weights.remove_at(j)


# 這種稀有度能不能出這條詞條（AFFIXES 的 min）
static func allowed(id: StringName, rarity: StringName) -> bool:
	return RARITY_ORDER.find(rarity) >= RARITY_ORDER.find(AFFIXES[id].get("min", &"green"))


# 觸發袋改版後武器沒有詞條、印記格與寶石座：只有種類、稀有度與數值；給 rng 時照稀有度擲隨機數值（inst.roll，灰色不擲），
# 沒給（武器測試場、檢查手做的）就用平均
static func make(uid: StringName, base: StringName, rarity: StringName, rng: RandomNumberGenerator = null, _keep: Array[StringName] = []) -> Dictionary:
	var inst := {"uid": uid, "base": base, "rarity": rarity, "affixes": [] as Array[StringName]}
	if rng != null and rarity != START_RARITY:
		inst["roll"] = roll_stats(base, rarity, rng)
	return inst


# 擲一把武器的各項倍率（ROLL_KEYS → 倍率）
static func roll_stats(base: StringName, rarity: StringName, rng: RandomNumberGenerator) -> Dictionary:
	var wd: Dictionary = WeaponDefs.WEAPONS[ItemDefs.ITEMS[base].weapon]
	var out := {}
	for key in ROLL_KEYS:
		var spread: float = ROLL_SPREAD[key]
		var m: float = RARITY_BASE[rarity][key] * (1.0 + rng.randf_range(-spread, spread))
		match key:
			"damage":
				var bd: float = wd.base_damage
				m = maxf(1.0, roundf(bd * m)) / bd
			"max_mana":
				var mx: float = wd.get("max_mana", Config.MANA.max)
				m = maxf(1.0, roundf(mx * m)) / mx
			_:
				m = snappedf(m, 0.01)
		out[key] = m
	return out


# 這把武器某一項（ROLL_KEYS）的倍率：擲過的照擲出來的，沒擲過的用稀有度平均
static func mul(inst: Dictionary, key: String) -> float:
	var roll: Dictionary = inst.get("roll", {})
	return roll[key] if roll.has(key) else RARITY_BASE[inst.rarity][key]


# 這把武器的最大魔力與回魔（魔力照武器：WeaponDefs 的 max_mana / mana_regen，沒寫的用 Config.MANA；乘稀有度倍率）
static func mana_base(inst: Dictionary) -> Dictionary:
	var wd: Dictionary = WeaponDefs.WEAPONS[ItemDefs.ITEMS[inst.base].weapon]
	return {"max_mana": wd.get("max_mana", Config.MANA.max) * mul(inst, "max_mana"),
		"mana_regen": wd.get("mana_regen", Config.MANA.regen) * mul(inst, "mana_regen")}


# 【目前沒使用】印記詞條的格子：每條從武器格子裡（不含寶石座、不和別條重疊）隨機挑 IMPRINT.cells 格，寫進 inst.imprints [{ bond, cell }]
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


# 武器的基礎數值（介面顯示用的實際數字）：攻擊力 = 普攻傷害、攻速 = 每秒普攻次數、範圍 = 揮砍距離或魔彈射程、最大魔力、回魔，
# 都乘上這把的倍率（mul）；只能當副手的（盾）沒有普攻，回傳 {}
static func base_stats(inst: Dictionary) -> Dictionary:
	var wd: Dictionary = WeaponDefs.WEAPONS[ItemDefs.ITEMS[inst.base].weapon]
	if not wd.has("attack"):
		return {}
	var atk: Dictionary = wd.attack
	var out := {
		"damage": WeaponDefs.move_base_damage(wd, atk) * mul(inst, "damage"),
		"attack_speed": mul(inst, "attack_speed") / (atk.windup + atk.active + atk.recovery),
		"range": atk.range * mul(inst, "range"),
	}
	out.merge(mana_base(inst))
	return out


# 手上這把生效的屬性：這把的倍率（攻擊力、攻速）＋詞條；範圍由 Player.weapon_range_mul 直接乘、魔力由 Player.apply_active_weapon 設基礎值
static func stat_mods(inst: Dictionary) -> Array:
	var mods := []
	var dmg := mul(inst, "damage")
	var spd := mul(inst, "attack_speed")
	if dmg != 1.0:
		mods.append([&"damage", Stats.MUL, dmg])
	if spd != 1.0:
		mods.append([&"attack_speed", Stats.MUL, spd])
	for id: StringName in inst.affixes:   # 詞條目前沒使用：只有武器測試場做的武器會有
		mods.append_array(AFFIXES[id].mods)
	return mods


# 這把武器的「羈絆 +1」詞條算哪些羈絆（Loadout.refresh_items）
static func bonds_of(inst: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in inst.get("affixes", []):
		if AFFIXES[id].kind == &"bond":
			out.append(AFFIXES[id].bond)
	return out


# 能不能合成：同種、同稀有度、不是同一把、還沒到最高（橘色）；灰色不在 RARITY_ORDER，next_rarity 是空的 → 不能合
static func can_merge(a: Dictionary, b: Dictionary) -> bool:
	return not a.is_empty() and not b.is_empty() and a.uid != b.uid and a.base == b.base \
		and a.rarity == b.rarity and next_rarity(a.rarity) != &""


# 快照用：[uid, base, rarity, [詞條…], 武器技能剩幾次?, 鑲的道具?, 印記格?, 掛著的袋子?, 擲出來的倍率?]；空的是 []；
# 後面幾欄有才送：最後一個有內容的之前補空的（次數沒用過送 -1、其他送 []）。鑲的道具：[[uid, id, x, y, rot], …]；
# 印記格：[[羈絆, x, y], …]；掛著的袋子（倉庫 / 地上的武器帶著的左右鍵袋子，Loadout.WEAPON_SIDES）是 BagDefs.to_array 的陣列；
# 倍率照 ROLL_KEYS 的順序
static func to_array(inst: Dictionary) -> Array:
	if inst.is_empty():
		return []
	var affixes := []
	for id: StringName in inst.affixes:
		affixes.append(String(id))
	var a := [String(inst.uid), String(inst.base), String(inst.rarity), affixes]
	var sockets := []
	for e: Dictionary in inst.get("sockets", []):
		sockets.append([String(e.uid), String(e.id), e.cell.x, e.cell.y, e.rot])
	var roll: Dictionary = inst.get("roll", {})
	var tail := [inst.get("slot_charges", -1), sockets,
		inst.get("imprints", []).map(func(im: Dictionary) -> Array: return [String(im.bond), im.cell.x, im.cell.y]),
		inst.get("bags", []).map(BagDefs.to_array),
		[] if roll.is_empty() else ROLL_KEYS.map(func(k: String) -> float: return roll[k])]
	var last := tail.size() - 1
	while last >= 0 and (tail[last] is int and tail[last] == -1 or tail[last] is Array and (tail[last] as Array).is_empty()):
		last -= 1
	a.append_array(tail.slice(0, last + 1))
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
	if a.size() > 5 and not (a[5] as Array).is_empty():
		var sockets: Array[Dictionary] = []
		for e: Array in a[5]:
			sockets.append({"uid": StringName(e[0]), "id": StringName(e[1]), "cell": Vector2i(e[2], e[3]), "rot": int(e[4])})
		inst["sockets"] = sockets
	if a.size() > 6 and not (a[6] as Array).is_empty():
		var imprints: Array[Dictionary] = []
		for im: Array in a[6]:
			imprints.append({"bond": StringName(im[0]), "cell": Vector2i(im[1], im[2])})
		inst["imprints"] = imprints
	if a.size() > 7 and not (a[7] as Array).is_empty():
		inst["bags"] = (a[7] as Array).map(BagDefs.from_array)
	if a.size() > 8 and not (a[8] as Array).is_empty():
		var roll := {}
		for i in ROLL_KEYS.size():
			roll[ROLL_KEYS[i]] = float(a[8][i])
		inst["roll"] = roll
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
