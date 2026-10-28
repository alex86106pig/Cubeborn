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
const PACKS := {
	"count": [12, 20],
	"size": [6, 15],
	"min_spawn_distance": 15.0,   # 群中心離玩家出生點至少這麼遠
	"min_pack_distance": 10.0,    # 群與群的中心至少這麼遠
	"spread": 3.5,                # 成員散在群中心這個半徑內
	"member_gap": 1.0,            # 成員之間至少這麼遠（找不到就放寬）
	"edge_margin": 4.0,           # 群中心離地圖邊緣至少這麼遠
	"wake_distance": 12.0,        # 任一位玩家離群中心這麼近，整群醒來
	"magic_per_pack": [1, 2],
	"rare_chance": 0.25,
	"attempts": 400,              # 找群中心的嘗試次數
}


static func affix_count(rarity: StringName, rng: RandomNumberGenerator) -> int:
	var r: Array = RARITIES[rarity].affixes
	return rng.randi_range(r[0], r[1])


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


static func roll_rare_name(rng: RandomNumberGenerator) -> String:
	return RARE_NAME_A[rng.randi_range(0, RARE_NAME_A.size() - 1)] + RARE_NAME_B[rng.randi_range(0, RARE_NAME_B.size() - 1)]


# 一群的稀有度清單（長度 size）：魔法 1~2 隻、rare_chance 機率 1 隻稀有，其餘普通；位置由呼叫端打散
static func roll_pack_rarities(size: int, rng: RandomNumberGenerator) -> Array[StringName]:
	var out: Array[StringName] = []
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
