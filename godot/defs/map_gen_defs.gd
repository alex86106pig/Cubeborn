# 小關隨機地圖的規則（地圖改版，照 mockups/map_layouts.html 的「拼形＋不規則邊緣」）：產生器在 sim/map_gen.gd
# 一關 = 一條主線（起點 → 打怪 → 出口 / 王族墓）＋ 機率長出的一條死路支線；每塊（區域）由 SHAPES 的 3~4 個 SUB × SUB 小格拼成
# 數字都是 Claude 暫定；客戶端照種子自己算同一張地圖，改規則時只用整數亂數（見 MapGen 的開頭）
class_name MapGenDefs

const SUB := 16              # 小格邊長（單位）：一塊 3~4 格 = 768~1024，約 32 × 32
const CORRIDOR := 3.5        # 走道半寬：走道上不放牆、墓碑（高台可以），邊緣也不吃進來
const OPENING_MARGIN := 5    # 塊與塊之間的開口離小格角落至少多遠（走道要整條在格子裡）
const EDGE_PAD := 3          # 地圖外框比區域多留的格數（外面一圈實心）
const EAT_MAX := 3           # 不規則邊緣：每塊從邊界往內吃 1 ~ EAT_MAX 格（雜訊決定）；王族墓那塊只吃 1 格；長條只有 SUB 寬，吃太多會變走道
const NOISE_SCALE := 6       # 吃邊雜訊的格點間距
const ATTEMPTS := 30         # 產生失敗（拼不下、走不到）重來幾次
const FALLBACK_MAP := &"graveyard_a"   # ATTEMPTS 次都失敗時改用的固定地圖
const START_STAGE := 1       # 一層從第幾小關開始

# 每個小關：main 主線塊數範圍（不含王族墓）、branch 長出支線的機率（%）、doors 出口幾扇門、anvil 起點旁有鐵砧、boss 最後是王族墓
const STAGES := {
	1: {"main": [3, 3], "branch": 50, "doors": 2},
	2: {"main": [3, 4], "branch": 60, "doors": 1},
	3: {"main": [3, 4], "branch": 60, "doors": 2, "anvil": true},
	4: {"main": [3, 4], "branch": 70, "doors": 1},
	5: {"main": [2, 2], "branch": 50, "anvil": true, "boss": true},
}

# 拼形（小格座標）：會旋轉、翻面；POOL 是抽的權重（重複 = 比較常出現）
const SHAPES := {
	&"O4": [[0, 0], [1, 0], [0, 1], [1, 1]], &"I3": [[0, 0], [1, 0], [2, 0]], &"L3": [[0, 0], [1, 0], [0, 1]],
	&"I4": [[0, 0], [1, 0], [2, 0], [3, 0]], &"L4": [[0, 0], [0, 1], [0, 2], [1, 2]], &"T4": [[0, 0], [1, 0], [2, 0], [1, 1]],
	&"S4": [[0, 0], [1, 0], [1, 1], [2, 1]],
	&"O9": [[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [2, 1], [0, 2], [1, 2], [2, 2]],   # 王族墓專用（BOSS.cells）
}
const SHAPE_POOL: Array[StringName] = [&"O4", &"O4", &"I3", &"L3", &"L3", &"L4", &"L4", &"T4", &"S4", &"I4"]

# 主題：每塊抽一個（相鄰兩塊不重複），SECOND_THEME % 再混一個副主題；起點固定空地、支線從 BRANCH_THEMES 抽（避開它接著的那塊）
const THEMES: Array[StringName] = [&"tombs", &"ruins", &"pits", &"mausoleums", &"hill", &"open"]
const THEME_NAMES := {&"tombs": "墓碑林", &"ruins": "教堂廢墟", &"pits": "亂葬坑", &"mausoleums": "陵墓列", &"hill": "山丘", &"open": "空地", &"boss": "王族墓"}
const BRANCH_THEMES: Array[StringName] = [&"tombs", &"mausoleums", &"ruins"]
const SECOND_THEME := 40

# 障礙物的種類 → 地形：頂面高度（plat 的高度由主題給）
const OBSTACLE_TOP := {&"tomb": MapDefs.TOMB_TOP, &"wall": MapDefs.WALL_TOP}
const RUIN_WALL := 1.5       # 教堂廢墟、王族墓圍牆的厚度

# 王族墓（1-5 最後一塊，固定）：cells × cells 小格的方形（48 × 48，守墓人開打會變 2 倍大），中間 RING × RING 的圍牆、門 GATE 寬對著來的方向；四角石座；中央挖墳點
const BOSS := {"cells": 3, "shape": &"O9", "ring": 30.0, "gate": 6.0, "corner": 5.0, "corner_inset": 3.0, "corner_top": 1.0, "patrol_margin": 2.0}

# 固定要素：鐵砧在起點左或右 ANVIL_OFFSET；出口的門在最後一塊離入口最遠的外緣（前 3 名抽一個）
const ANVIL_OFFSET := 5
const DOOR_OFFSETS_TWO: Array[int] = [4, 12]   # 兩扇門在那一格外緣上的位置（0 ~ SUB；門寬 ArenaView.DOOR_WIDTH 4.4）
const DOOR_REACH := 3.0      # 門前站的位置往內縮多少（走道接到這裡，檢查走不走得到也看這點）
# 兩扇門時各抽一種下一關的獎勵（不重複）；一扇門的關卡下一關固定有鐵砧，門上不抽獎勵
const DOOR_REWARDS: Array[StringName] = [&"relic", &"skill", &"bag", &"souls", &"dice"]
# 門上的獎勵（走進門、下一關開始時給）：relic 遺物（石棺的稀有度機率）、skill 技能遺物（同石棺）、bag 觸發袋 N 選 1 放在出生點旁 REWARD_DROP，
# souls 全隊共用的靈魂、dice 每人的骰子；數字 Claude 暫定
const REWARDS := {
	&"relic": {"name": "遺物"},
	&"skill": {"name": "技能"},
	&"bag": {"name": "袋子"},
	&"souls": {"name": "靈魂", "amount": 60},
	&"dice": {"name": "骰子", "amount": 2},
}
const REWARD_DROP := Vector2(0.0, -3.0)

# 祭壇與石棺：先定這一層的總數，開局照種子分給各小關（MapGen.chest_plan），各小關再找位置擺
# Boss 那關打怪的塊比較少，固定分 boss_altars 個，其他平均；石棺抽不同的小關各一個（第 1 層的經濟目標見 docs/設計方向.md）
const FLOOR_CHESTS := {"altars": 16, "coffins": 3, "boss_altars": 2}

# 擺放：怪群（每塊 1~3 群、支線 1 群，一群 6~10 隻）、祭壇與石棺的位置（min_gap：彼此至少多遠，才不會全擠在同一塊）
const PACKS := {"per_region": [1, 3], "per_branch": [1, 1], "size": [6, 10], "min_start": 14, "min_gap": 8, "margin": 4, "attempts": 60}
const CHESTS := {"min_start": 8, "min_pack": 4, "min_gap": 5, "margin": 3, "attempts": 40}

# 保留空間：這些點周圍不放障礙物（半徑），也不吃邊
const KEEP := {"start": 6.0, "opening": 4.5, "anvil": 3.0, "big_chest": 4.0, "door_reach": 3.0, "door": 2.5}
