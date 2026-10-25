# 去下一層的事件（D6，第 1 層是挖墳；使用者 2026-10-23 選定：60 秒、難度線性無上限、
# Boss 必掉武器 + 大寶箱道具、全員進出口後重新載入地圖且基礎難度 +10、屍體裝背包 / 冤魂復活）
# 使用者 2026-10-25 試玩後改：事件開始先只有 Boss，Boss 倒下才開始怪潮；沒人挖時進度掉得慢很多（1% → 0.2%）
# 難度 = 該層基礎難度 + 怪潮開始後的秒數 × per_second；怪物的生命與攻擊力、事件生怪的間隔與數量、魔法 / 稀有機率都跟著難度
class_name EventDefs

const DIG := {
	"time": 60.0,              # 一個人不停挖幾秒挖完（多人一起挖速度相加）
	"decay": 0.002,            # 沒人挖時進度每秒掉多少（0.2%：離開 30 秒掉 6%）
	"range": 2.2,              # 離挖墳點這麼近才能挖（中心距離）
	"exit_radius": 1.4,        # 挖完後墓穴就是出口：走進這個範圍就「下去」
	"boss_distance": 8.0,      # 事件開始時 Boss 出現在挖墳點旁邊這麼遠
}

const DIFFICULTY := {
	"per_second": 1.0,         # 怪潮開始後（Boss 倒下後）每秒 +1
	"per_floor": 10.0,         # 每層基礎難度（第 1 層 0、第 2 層 10…）
	"stat_per_point": 0.005,   # 怪物生命與攻擊力每點 +0.5%（30 點 +15%）
}

# 事件中不斷冒怪：每 interval 秒冒一批，數量 = base + 難度 × per_point（無條件捨去），多人每多 1 人 ×1.5
const SPAWN := {
	"interval_start": 3.0,
	"interval_min": 0.8,
	"interval_per_point": 0.01,     # 難度每點間隔 −0.01 秒
	"group_base": 2,
	"group_per_point": 0.05,        # 難度每 20 點多 1 隻
	"per_extra_player": 0.5,
	"archer_ratio": 0.25,
	"magic_base": 0.05, "magic_per_point": 0.002, "magic_max": 0.5,
	"rare_base": 0.0, "rare_per_point": 0.0008, "rare_max": 0.25,
	"max_alive": 120,               # 事件怪同時最多這麼多隻（效能上限）
}

# 冤魂（屍體帶到下一層）：出現在出生點附近，打倒就在那裡復活
const GHOST := {
	"distance": [10.0, 14.0],
	"revive_hp_ratio": 0.3,
}


static func difficulty_mul(difficulty: float) -> Dictionary:
	var k := 1.0 + DIFFICULTY.stat_per_point * difficulty
	return {"hp": k, "damage": k, "speed": 1.0}


static func spawn_interval(difficulty: float) -> float:
	return maxf(SPAWN.interval_min, SPAWN.interval_start - SPAWN.interval_per_point * difficulty)


static func group_size(difficulty: float, players: int) -> int:
	var n: float = (SPAWN.group_base + floorf(SPAWN.group_per_point * difficulty)) * (1.0 + SPAWN.per_extra_player * maxi(0, players - 1))
	return int(n)


# 事件怪的稀有度：先擲稀有、再擲魔法
static func roll_rarity(difficulty: float, rng: RandomNumberGenerator) -> StringName:
	var rare := minf(SPAWN.rare_max, SPAWN.rare_base + SPAWN.rare_per_point * difficulty)
	var magic := minf(SPAWN.magic_max, SPAWN.magic_base + SPAWN.magic_per_point * difficulty)
	var r := rng.randf()
	if r < rare:
		return MonsterRarityDefs.RARE
	if r < rare + magic:
		return MonsterRarityDefs.MAGIC
	return MonsterRarityDefs.NORMAL
