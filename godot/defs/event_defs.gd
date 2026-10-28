# 去下一層的事件（第 1 層是挖墳，規格見 docs/系統說明.md §15）
# Boss 開局就在挖墳點巡邏；碰到墳墓開始事件：怪潮與挖墳點噴怪同時開始，挖完停怪，再到墳墓互動前往下一層
# 難度 = 該層基礎難度 + 事件開始後的秒數 × per_second；怪物的生命與攻擊力、事件生怪的間隔與數量、魔法 / 稀有機率都跟著難度
class_name EventDefs

const DIG := {
	"time": 60.0,              # 每位玩家要挖幾秒：總量 = time × 活著的人數，多人一起挖速度相加（全員一起挖都是 60 秒）
	"decay": 0.0,              # 沒人挖時進度每秒掉多少（0 = 不掉）
	"range": 2.2,              # 離挖墳點這麼近才能挖、挖完後按 F 前往下一層（中心距離）
	"exit_radius": 1.4,        # 挖完後墓穴洞口的大小（畫面用）
	"boss_type": &"gravekeeper",   # 開局就在挖墳點的 Boss（EnemyDefs 的種類；之後每層可以換；第 1 層是守墓人，舊的亡骸騎士等第 2 層）
	"last_floor": 1,           # 這一層挖完再互動就通關（測試版只有一層）；之後的層照舊 World.next_floor
}

# 挖墳點噴怪：事件進行中每 interval 秒，挖墳點的墳土先隆起、裂開、冒出白骨手（warning 秒，不畫圈），接著噴出下一層的怪，同時進度 +progress
# 數量 = count_base + 事件開始後漲的難度 × count_per_point（無條件捨去），多人照 SPAWN.per_extra_player 放大
# 強度：目前難度 + DIFFICULTY.per_floor（下一層的基礎難度起算）
const ERUPT := {
	"interval": 10.0,
	"warning": 1.0,                # 墳土隆起幾秒後噴出（第一次在事件開始後 interval 秒）
	"radius": 2.5,                 # 隆起的墳土範圍
	"progress": 0.1,               # 每次噴發進度 +10%（全隊共用的進度條，不隨人數變）
	"count_base": 3,
	"count_per_point": 0.05,       # 難度每漲 20 點多 1 隻
	"land_distance": [3.0, 6.0],   # 落點離挖墳點多遠
	"flight_time": 1.0,            # 噴出後在空中幾秒（最高點 = 重力 × flight_time² ÷ 8）
	"shake": 0.25, "shake_duration": 0.3,
}

# 挖完後的「前往下一層」投票（多人）：一人在墳墓按 F 發起，其他人 Enter 同意 / Esc 反對；全員同意或時間到就走，有人反對就取消
const VOTE := {
	"time": 15.0,
}

const DIFFICULTY := {
	"per_second": 1.0,         # 挖墳事件開始後每秒 +1（挖完就停）
	"per_floor": 10.0,         # 每層基礎難度（第 1 層 0、第 2 層 10…）
	"stat_per_point": 0.005,   # 怪物生命與攻擊力每點 +0.5%（30 點 +15%）
}

# 選角畫面選的難度（2026-10-27 使用者決定）：只改怪潮開始後難度上升的速度（per_second 的倍率），其他都不動
const MODE_ORDER: Array[StringName] = [&"easy", &"normal", &"hard"]
const MODES := {
	&"easy": {"name": "簡單", "rate": 0.75},
	&"normal": {"name": "普通", "rate": 1.0},
	&"hard": {"name": "困難", "rate": 1.5},
}
const DEFAULT_MODE := &"normal"

# 事件中不斷冒怪：每 interval 秒冒一批，數量 = base + 難度 × per_point（無條件捨去），多人每多 1 人 ×1.5
# v0.44.0 使用者試玩：清怪比不上生怪、完全挖不了 → 方案 B（單人第 60 秒累計 68 → 26 隻、120 秒 238 → 76 隻）
const SPAWN := {
	"interval_start": 5.0,          # 原本 3.0
	"interval_min": 1.0,            # 原本 0.8
	"interval_per_point": 0.01,     # 難度每點間隔 −0.01 秒
	"group_base": 2,
	"group_per_point": 0.02,        # 難度每 50 點多 1 隻（原本每 20 點）
	"per_extra_player": 0.5,
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


# 一次噴幾隻：rise = 事件開始後漲了多少難度
static func erupt_count(rise: float, players: int) -> int:
	var n: float = (ERUPT.count_base + floorf(ERUPT.count_per_point * rise)) * (1.0 + SPAWN.per_extra_player * maxi(0, players - 1))
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
