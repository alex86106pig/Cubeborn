# 怪物稀有度、詞條與怪群（D5，使用者 2026-10-23 選定 POE 式、8 種基本詞條、地圖預放 + 波次）
# 稀有度：普通 / 魔法 / 稀有；倍率作用在 Stats 的 &"rarity" 來源（乘在波次倍率之上），詞條在 &"affixes" 來源或由 Enemy 處理
# 怪群：開場在地圖上散放（map_defs 的 "packs": true 才有），休眠到玩家靠近 wake_distance 或被打才整群醒來
class_name MonsterRarityDefs

const NORMAL := &"normal"
const MAGIC := &"magic"
const RARE := &"rare"

# hp / damage：倍率；scale：體型（半徑、身高、模型）；affixes：[最少, 最多] 條；color：光與名字的顏色
const RARITIES := {
	NORMAL: {"name": "普通", "hp": 1.0, "damage": 1.0, "scale": 1.0, "affixes": [0, 0], "color": Color.WHITE},
	MAGIC: {"name": "魔法", "hp": 2.0, "damage": 1.2, "scale": 1.0, "affixes": [1, 2], "color": Color("4a8cff")},
	RARE: {"name": "稀有", "hp": 5.0, "damage": 1.5, "scale": 1.2, "affixes": [3, 3], "color": Color("ffc83a")},
}

# mods：直接加在 Stats 的加成；其他欄位由 Enemy（sim/enemy.gd）處理
const AFFIXES := {
	&"swift": {"name": "迅捷", "desc": "移速 +30%", "mods": [[&"move_speed", Stats.MUL, 1.3]]},
	&"mighty": {"name": "強壯", "desc": "傷害 +30%", "mods": [[&"damage", Stats.MUL, 1.3]]},
	&"armored": {"name": "厚皮", "desc": "受到傷害 −25%", "mods": [[&"damage_taken", Stats.MUL, 0.75]]},
	&"regen": {"name": "再生", "desc": "每秒回復 2% 最大生命", "regen_ratio": 0.02},
	&"vampiric": {"name": "吸血", "desc": "造成傷害的 20% 回血", "lifesteal": 0.2},
	&"frenzy": {"name": "狂暴", "desc": "生命低於 30% 時攻速與移速 +40%", "threshold": 0.3, "speed": 1.4},
	&"volatile": {"name": "死亡爆炸", "desc": "死後 0.8 秒在原地爆炸", "delay": 0.8, "radius": 2.2, "damage": 20.0, "knockback": 10.0,
		"color": Color("ff7a3a")},
	&"summoner": {"name": "召喚", "desc": "每 8 秒叫出 2 隻同種的怪", "interval": 8.0, "count": 2, "max_alive": 6, "spread": 2.0},
}

# 稀有怪的名字：前半 + 後半（POE 式隨機名字）
const RARE_NAME_A: Array[String] = ["腐朽的", "低語的", "破碎的", "無眠的", "染血的", "空洞的", "灰燼的", "哀號的", "鏽蝕的", "褪色的"]
const RARE_NAME_B: Array[String] = ["掘墓者", "守陵人", "亡誓者", "骨王", "送葬者", "墓衛", "斷劍", "哀悼者", "夜巡者", "殘魂"]

# 怪群（使用者選定：每群 6~15 隻、12~20 群、離出生點 15 以上、玩家靠近 12 才醒；每群 1~2 隻魔法、每 4 群約 1 隻稀有）
# 怪群模板（製作計畫 L 第 3、4 步，Claude 暫定）：每層照 weight 抽一種（Spawner._spawn_pack）。
# size：隻數（沒寫 = 地圖給的或 PACKS.size）；members：[[種類, 比例]…]（沒寫 = 這一層的怪物表；第 2 層起照樣約 UPPER_SHARE 換成上一層的）；
# layout：scatter 散開、ring_in 圍一圈面向中間、high 弓手站高處其他散開面朝外、line 第一種排前面面朝出生點其他的排後面、buried 埋在地底圍一圈（伏擊）；
# idle：種類 → 休眠的樣子（沒寫照 def.idle）；loot：全清掉在中心掉一把武器；lone：只有一隻、一定是稀有
const PACK_TEMPLATES := {
	1: [
		{"id": &"horde", "weight": 30},
		{"id": &"feast", "weight": 25, "size": [4, 6], "members": [[&"zombie", 0.85], [&"bloater", 0.15]], "layout": &"ring_in", "idle": {&"zombie": &"feed"}, "loot": true},
		{"id": &"hounds", "weight": 20, "size": [4, 6], "members": [[&"hound", 0.6], [&"zombie", 0.4]], "layout": &"scatter"},
		{"id": &"ambush", "weight": 15, "size": [5, 7], "members": [[&"zombie", 0.8], [&"hound", 0.2]], "layout": &"buried"},
		{"id": &"lone", "weight": 10, "size": [1, 1], "lone": true, "idle": {&"zombie": &"sway", &"hound": &"sniff", &"bloater": &"sway"}},
	],
	2: [
		{"id": &"horde", "weight": 30},
		{"id": &"watch", "weight": 25, "size": [5, 7], "members": [[&"archer", 0.4], [&"grunt", 0.6]], "layout": &"high", "idle": {&"grunt": &"guard", &"archer": &"guard"}},
		{"id": &"shieldwall", "weight": 20, "size": [4, 6], "members": [[&"spearman", 0.5], [&"archer", 0.5]], "layout": &"line", "idle": {&"archer": &"guard"}},
		{"id": &"ambush", "weight": 15, "size": [5, 7], "members": [[&"grunt", 1.0]], "layout": &"buried"},
		{"id": &"lone", "weight": 10, "size": [1, 1], "lone": true, "idle": {&"grunt": &"guard", &"archer": &"guard", &"spearman": &"guard"}},
	],
	3: [
		{"id": &"horde", "weight": 50},
		{"id": &"webnest", "weight": 35, "size": [6, 10], "members": [[&"spider", 0.3], [&"beetle", 0.7]], "layout": &"scatter"},
		{"id": &"lone", "weight": 15, "size": [1, 1], "lone": true},
	],
}
# 遊蕩群（L 第 4 步）：每張有怪群的地圖 count 群，size 隻沿兩點來回走（醒著、進快照）；route 兩點相距；speed 走路速度 × 移速
const WANDER := {"count": 1, "size": [3, 4], "route": [16.0, 30.0], "speed": 0.35, "gap": 1.3, "attempts": 40}

const PACKS := {
	"count": [12, 20],
	"size": [6, 15],
	"min_spawn_distance": 15.0,   # 群中心離玩家出生點至少這麼遠
	"min_pack_distance": 10.0,    # 群與群的中心至少這麼遠
	"spread": 3.5,                # 成員散在群中心這個半徑內
	"member_gap": 1.0,            # 成員之間至少這麼遠（找不到就放寬）
	"edge_margin": 4.0,           # 群中心離地圖邊緣至少這麼遠
	# 發現玩家（World._update_packs，製作計畫 L 第 1 步）：休眠的怪各自看，一隻發現就整群依序醒
	"notice_sight": 10.0,         # 正面 notice_arc 內這麼遠、視線沒被牆擋住就發現
	"notice_arc": PI * 140.0 / 180.0,   # 正面的角度（全寬）
	"notice_close": 3.0,          # 身邊這麼近不管方向都發現
	"noise_radius": 8.0,          # 這麼近有打鬥（有東西受傷、死掉）就發現
	"notice_every": 6,            # 每幾步看一次（照 id 錯開；打鬥聲記這麼多步）
	"alert_time": 0.6,            # 發現的那隻停下、轉向、吼的時間
	"alert_follow": 0.25,         # 同群其他的醒來後停下轉頭的時間
	"alert_spread": 0.08,         # 同群其他的每離發現的那隻 1 單位晚這麼多秒醒（從 alert_time 一半開始算）
	"ambush_trigger": 2.5,        # 伏擊：玩家走到群中心這麼近，地底的一圈爬出來
	"ambush_ring": [3.0, 4.5],    # 伏擊的成員埋在離中心這麼遠的一圈
	"feast_ring": [1.3, 2.2],     # 啃食群圍著中間的屍體，離中心這麼遠
	"high_search": 6.0,           # 高台弓手：離中心這麼遠內找高處
	"magic_per_pack": [1, 2],
	"rare_chance": 0.25,
	"attempts": 400,              # 找群中心的嘗試次數
}


static func affix_count(rarity: StringName, rng: RandomNumberGenerator) -> int:
	var r: Array = RARITIES[rarity].affixes
	return rng.randi_range(r[0], r[1])


# 不重複地抽 count 條詞條（依 AFFIXES 順序做部分洗牌，用 world.rng 才有決定性）；exclude 裡的不抽（膨脹屍不抽死亡爆炸，見 EnemyDefs no_affixes）
static func roll_affixes(count: int, rng: RandomNumberGenerator, exclude: Array = []) -> Array[StringName]:
	var pool: Array[StringName] = []
	for id: StringName in AFFIXES:
		if not exclude.has(id):
			pool.append(id)
	var out: Array[StringName] = []
	for i in mini(count, pool.size()):
		var j := rng.randi_range(i, pool.size() - 1)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
		out.append(pool[i])
	return out


static func roll_rare_name(rng: RandomNumberGenerator) -> String:
	return RARE_NAME_A[rng.randi_range(0, RARE_NAME_A.size() - 1)] + RARE_NAME_B[rng.randi_range(0, RARE_NAME_B.size() - 1)]


# 一群的稀有度清單（長度 size）：魔法 1~2 隻、rare_chance 機率 1 隻稀有，其餘普通；位置由呼叫端打散。
# 獨行的（lone）只有一隻稀有、不抽亂數
static func roll_pack_rarities(size: int, rng: RandomNumberGenerator, lone := false) -> Array[StringName]:
	var out: Array[StringName] = []
	if lone:
		out.append(RARE)
		return out
	var m: Array = PACKS.magic_per_pack
	var magic := rng.randi_range(m[0], m[1])
	var rare := 1 if rng.randf() < PACKS.rare_chance else 0
	for i in size:
		if i < rare:
			out.append(RARE)
		elif i < rare + magic:
			out.append(MAGIC)
		else:
			out.append(NORMAL)
	return out


static func affix_names(affixes: Array) -> String:
	var names: PackedStringArray = []
	for id: StringName in affixes:
		names.append(AFFIXES[id].name)
	return "、".join(names)


# 這一層照權重抽一種怪群模板（只用一次 randi_range：客戶端本機算的怪群照樣一致）；沒有表的層用最後一層
static func roll_pack_template(floor_num: int, rng: RandomNumberGenerator) -> Dictionary:
	var keys := PACK_TEMPLATES.keys()
	var list: Array = PACK_TEMPLATES.get(floor_num, PACK_TEMPLATES[keys.max()])
	var total := 0
	for t: Dictionary in list:
		total += int(t.weight)
	var r := rng.randi_range(0, total - 1)
	for t: Dictionary in list:
		r -= int(t.weight)
		if r < 0:
			return t
	return list[0]


static func template_by_id(id: StringName) -> Dictionary:
	for list: Array in PACK_TEMPLATES.values():
		for t: Dictionary in list:
			if t.id == id:
				return t
	return {}
