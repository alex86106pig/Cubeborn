# 金錢與寶箱（D3）：殺怪給的錢（多人共用）、寶箱價格、開出各稀有度的機率
# 數值是 Claude 暫定（2026-10-23，使用者說都先用建議值，試玩後再調）
class_name LootDefs

# 殺一隻給多少錢（召喚出來的不給，Enemy.no_gold）；多人時乘 player_mul
# v0.44.0 使用者試玩：錢太多（地圖 A 開場平均 155 隻怪 ×5 ≈ 775 金，寶箱總價才 160）→ 5 → 2、Boss 50 → 30，清完也開不完全部寶箱
const KILL_GOLD := {&"grunt": 2, &"archer": 2, &"boss": 30}

# 寶箱（v0.44.0）：開場隨機放在地圖上（有 "chest_count" 的地圖），數量乘 player_mul（四捨五入）
# 開場怪群 109~207 隻（40 個種子量測，平均 155），清完 + Boss ≈ 248~444 金（平均 340）< 寶箱總價 12×25 + 4×60 = 540
const CHEST_PLACEMENT := {
	"min_spawn_distance": 15.0,   # 離玩家出生點至少這麼遠
	"min_dig_distance": 6.0,      # 離挖墳點至少這麼遠
	"min_chest_distance": 8.0,    # 寶箱之間至少這麼遠（找不到就放寬）
	"edge_margin": 4.0,
	"attempts": 400,
}
const PER_EXTRA_PLAYER := 0.5   # 多人每多 1 人，寶箱數量與殺怪金錢 +50%（使用者 2026-10-25 選定；2 人 ×1.5、4 人 ×2.5）

# 寶箱：價格、開出的稀有度權重（加總 100）、碰撞半徑（只給互動距離與畫面用，不擋路）
const CHESTS := {
	&"small": {"name": "小寶箱", "price": 25, "radius": 0.6,
		"weights": {&"white": 70.0, &"green": 25.0, &"blue": 5.0}},
	&"big": {"name": "大寶箱", "price": 60, "radius": 0.85,
		"weights": {&"green": 50.0, &"blue": 35.0, &"purple": 13.0, &"orange": 2.0}},
}

const INTERACT_RANGE := 1.6     # 身體邊緣到寶箱 / 道具邊緣多近才按得到 F
const DROP_DISTANCE := 1.4      # 開箱時道具掉在寶箱往玩家方向這麼遠；從背包丟出時掉在面前這麼遠


static func player_mul(players: int) -> float:
	return 1.0 + PER_EXTRA_PLAYER * maxi(0, players - 1)


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


# 寶箱 / Boss 獎勵實際抽的道具：只抽效果都接上的（v0.33.0 使用者決定，還沒做的先不開出來）；
# 那個稀有度一個都沒有（目前的橘色）就往下一級找
static func drop_pool(rarity: StringName) -> Array[StringName]:
	var order: Array = ItemDefs.RARITIES.keys()
	for i in range(order.find(rarity), -1, -1):
		var out: Array[StringName] = []
		for id in items_of(order[i]):
			if ItemDefs.item_implemented(id):
				out.append(id)
		if not out.is_empty():
			return out
	return items_of(rarity)
