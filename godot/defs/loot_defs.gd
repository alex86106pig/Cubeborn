# 金錢與寶箱（D3）：殺怪給的錢（多人共用）、寶箱價格、開出各稀有度的機率
# 數值是 Claude 暫定（2026-10-23，使用者說都先用建議值，試玩後再調）
class_name LootDefs

# 殺一隻給多少錢（Boss 召喚的小怪照樣給）
const KILL_GOLD := {&"grunt": 5, &"archer": 5, &"boss": 50}

# 寶箱：價格、開出的稀有度權重（加總 100）、碰撞半徑（只給互動距離與畫面用，不擋路）
const CHESTS := {
	&"small": {"name": "小寶箱", "price": 25, "radius": 0.6,
		"weights": {&"white": 70.0, &"green": 25.0, &"blue": 5.0}},
	&"big": {"name": "大寶箱", "price": 60, "radius": 0.85,
		"weights": {&"green": 50.0, &"blue": 35.0, &"purple": 13.0, &"orange": 2.0}},
}

const INTERACT_RANGE := 1.6     # 身體邊緣到寶箱 / 道具邊緣多近才按得到 F
const DROP_DISTANCE := 1.4      # 開箱時道具掉在寶箱往玩家方向這麼遠；從背包丟出時掉在面前這麼遠


# 依權重抽一個稀有度（用 world.rng 才有決定性）
static func roll_rarity(tier: StringName, rng: RandomNumberGenerator) -> StringName:
	var weights: Dictionary = CHESTS[tier].weights
	var total := 0.0
	for r: StringName in weights:
		total += weights[r]
	var x := rng.randf() * total
	for r: StringName in weights:
		x -= weights[r]
		if x < 0.0:
			return r
	return weights.keys().back()


# 某個稀有度的道具 id（不含武器），依清單順序
static func items_of(rarity: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in ItemDefs.ITEMS:
		var def: Dictionary = ItemDefs.ITEMS[id]
		if def.kind == &"item" and def.rarity == rarity:
			out.append(id)
	return out
