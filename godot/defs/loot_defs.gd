# 靈魂與祭壇 / 石棺（D3）：殺怪給的靈魂（多人共用）、祭壇 / 石棺價格、開出各稀有度的機率；局外金幣（RUN_COINS）
# 數值是 Claude 暫定（2026-10-23，使用者說都先用建議值，試玩後再調）
# v0.45 使用者決定（盜墓主題）：局內貨幣「錢」改成「靈魂」、小寶箱 / 大寶箱改成祭壇 / 石棺（程式裡沿用 chest 與 small / big），
# 金幣改成帶出去的局外貨幣。舊註解的「金」「錢」就是現在的靈魂
class_name LootDefs

# 殺一隻給多少靈魂（召喚出來的不給，Enemy.no_souls）；多人時不變（2026-10-30 許家慶：一個遺物大家都能拿，寶箱與靈魂都不跟人數變）
# v0.44.0 使用者試玩：錢太多（地圖 A 開場平均 155 隻怪 ×5 ≈ 775 金，寶箱總價才 160）→ 5 → 2、Boss 50 → 30，清完也開不完全部寶箱
const KILL_SOULS := {&"grunt": 2, &"archer": 2, &"zombie": 2, &"bloater": 2, &"hound": 2, &"boss": 30, &"gravekeeper": 30}

# 寶箱（v0.44.0）：開場隨機放在地圖上（有 "chest_count" 的地圖），數量不跟人數變
# 開場怪群 109~207 隻（40 個種子量測，平均 155），清完 + Boss ≈ 248~444 金（平均 340）< 寶箱總價 12×25 + 4×60 = 540
const CHEST_PLACEMENT := {
	"min_spawn_distance": 15.0,   # 離玩家出生點至少這麼遠
	"min_dig_distance": 6.0,      # 離挖墳點至少這麼遠
	"min_chest_distance": 8.0,    # 寶箱之間至少這麼遠（找不到就放寬）
	"edge_margin": 4.0,
	"attempts": 400,
}

# 寶箱：價格、開出的稀有度權重（加總 100）、碰撞半徑（只給互動距離與畫面用，不擋路）
const CHESTS := {
	&"small": {"name": "祭壇", "price": 25, "radius": 0.6,
		"weights": {&"white": 70.0, &"green": 25.0, &"blue": 5.0}},
	&"big": {"name": "石棺", "price": 60, "radius": 0.85,
		"weights": {&"green": 50.0, &"blue": 35.0, &"purple": 13.0, &"orange": 2.0}},
}

# 局外金幣（v0.45，Claude 暫定，獲得量與方式使用者還在構思）：本局拿到的存進 Profile；多人時全員各拿一份（不用搶）
# - 過關：全員走進出口時給 floor_clear_per_floor × 剛過的層數（第 1 層最少）；之後要做「開寶箱噴錢」的過場
# - 掉落：殺怪極低機率掉 1 枚在地上，活著的玩家走到 collect_range 內自動撿（參考雨中冒險 2 的月幣）；召喚出來的怪不掉
const RUN_COINS := {
	"floor_clear_per_floor": 5,
	"drop_chance": {&"grunt": 0.003, &"archer": 0.003, &"zombie": 0.003, &"bloater": 0.003, &"hound": 0.003, &"boss": 0.03, &"gravekeeper": 0.03},
	"collect_range": 1.2,   # 身體邊緣到金幣中心多近就撿起
}

# 遺物（Build 改版第 6 步）：開局每人幾顆骰子（重擲 N 選 1 用掉 1 顆，2026-10-30 許家慶參考 Sephiria；之後的道具與局外成長會加）
const RELIC := {"start_dice": 3, "radius": 0.55}

const INTERACT_RANGE := 1.6     # 身體邊緣到寶箱 / 道具邊緣多近才按得到 F
const DROP_DISTANCE := 1.4      # 開箱時道具掉在寶箱往玩家方向這麼遠；從背包丟出時掉在面前這麼遠


# 依權重抽一個稀有度（用 world.rng 才有決定性）；treasure = 開箱者的尋寶（F1）
static func roll_rarity(tier: StringName, rng: RandomNumberGenerator, treasure := 0.0) -> StringName:
	return pick_rarity(treasure_weights(CHESTS[tier].weights, treasure), rng)


# 尋寶（F1）：表裡最低一級（第一個）以外的權重 × (1 + 尋寶)；武器掉落（WeaponDropDefs）共用
static func treasure_weights(weights: Dictionary, treasure: float) -> Dictionary:
	if treasure <= 0.0:
		return weights
	var out := {}
	var first := true
	for r: StringName in weights:
		out[r] = weights[r] if first else weights[r] * (1.0 + treasure)
		first = false
	return out


# 依權重抽一個（只擲一次 rng）
static func pick_rarity(weights: Dictionary, rng: RandomNumberGenerator) -> StringName:
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
			if ItemDefs.item_implemented(id) and not ItemDefs.ITEMS[id].get("bonds", []).is_empty():   # 不屬於任何羈絆的先不掉
				out.append(id)
		if not out.is_empty():
			return out
	return items_of(rarity)
