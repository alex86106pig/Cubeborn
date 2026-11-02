# 地圖資料（D1）：大小、出生點、挖墳點、地形石台。座標是「地圖座標」：左上角 (0, 0)，x 往右、y 往下（= 世界 X、Z）
# 世界座標 = 地圖座標 − origin（地圖中央在世界原點）。畫面是等距視角，所以地圖在畫面上轉了 45°（菱形）
# blocks：[x, y, 寬, 深, 頂面高度, 種類]（x, y 是左上角）；tomb_rows：[x, y, 欄數, 列數, 欄距, 列距]，每個墓碑 TOMB_SIZE、高 TOMB_TOP
# 種類：&"wall" 牆 / 陵墓（跳不上去，怪物繞路）、&"tomb" 墓碑（擋箭、玩家跳得上去，怪物繞路）、&"platform" 可以站的高台（怪物會跳上去）
# 草圖與還沒做的 B、C、D 三張在 mockups/graveyard_map.html；theme 決定畫面的外觀（ArenaView、Config.ENVIRONMENTS）
class_name MapDefs

const WALL := &"wall"
const TOMB := &"tomb"
const PLATFORM := &"platform"

const WALL_TOP := 3.0      # 牆比旁邊最高的地面（1.0）高 2.0，跳躍最高 1.5 上不去
const TOMB_TOP := 1.3      # 高過箭（1.17）與魔彈（1.25）的飛行高度，所以擋得住；玩家跳得上去
const TOMB_SIZE := Vector2(1.2, 0.5)

# spawn_rule：&"arena" = 舊的方形場地（整個場地隨機、Boss 在玩家對面）；&"around_player" = 大地圖（生在玩家周圍一圈內）
const MAPS := {
	# 測試場地：32 × 32 的空場地，角落 3 個測試石台（v0.16.0）；check.gd 的大部分檢查用這張
	&"test_arena": {
		"size": Vector2(32.0, 32.0),
		"origin": Vector2(16.0, 16.0),
		"spawn": Vector2(16.0, 16.0),
		"dig": Vector2(16.0, 16.0),
		"spawn_rule": &"arena",
		"blocks": [
			[23.75, 26.75, 2.5, 2.5, 0.5, PLATFORM],   # 走不上去、跳得上去
			[26.25, 26.25, 3.5, 3.5, 1.0, PLATFORM],   # 緊鄰上一塊；跳得上去，可以站著走
			[24.0, 23.5, 6.0, 1.0, 2.5, WALL],         # 跳不上去，當牆
		],
		"tomb_rows": [],
	},
	# A 環形墓園（使用者 2026-10-23 選定）：中央是圍牆圍住的王族墓，北門進；外圈四區
	&"graveyard_a": {
		"size": Vector2(96.0, 96.0),
		"origin": Vector2(48.0, 48.0),
		"spawn": Vector2(48.0, 88.0),
		"dig": Vector2(48.0, 50.0),
		"boss_room": [36.5, 36.5, 23.0, 23.0],   # Boss 巡邏範圍 [x, y, 寬, 深]：王族墓圍牆內側留 2 格（Boss 半徑大，貼牆會卡）
		"spawn_rule": &"around_player",
		"blocks": [
			# 外圍
			[0.0, 0.0, 96.0, 2.0, WALL_TOP, WALL], [0.0, 94.0, 96.0, 2.0, WALL_TOP, WALL],
			[0.0, 0.0, 2.0, 96.0, WALL_TOP, WALL], [94.0, 0.0, 2.0, 96.0, WALL_TOP, WALL],
			# 王族墓圍牆（北門 45~51）與裡面四角的石座
			[33.0, 33.0, 12.0, 1.5, WALL_TOP, WALL], [51.0, 33.0, 12.0, 1.5, WALL_TOP, WALL],
			[33.0, 61.5, 30.0, 1.5, WALL_TOP, WALL], [33.0, 33.0, 1.5, 30.0, WALL_TOP, WALL], [61.5, 33.0, 1.5, 30.0, WALL_TOP, WALL],
			[36.0, 37.0, 5.0, 5.0, 1.0, PLATFORM], [55.0, 37.0, 5.0, 5.0, 1.0, PLATFORM],
			[36.0, 55.0, 5.0, 5.0, 1.0, PLATFORM], [55.0, 55.0, 5.0, 5.0, 1.0, PLATFORM],
			# 西：教堂廢墟
			[6.0, 36.0, 20.0, 1.5, WALL_TOP, WALL], [6.0, 36.0, 1.5, 18.0, WALL_TOP, WALL],
			[24.5, 36.0, 1.5, 8.0, WALL_TOP, WALL], [6.0, 52.5, 10.0, 1.5, WALL_TOP, WALL],
			# 北：小山丘（0.5 外圈、1.0 山頂）
			[40.0, 6.0, 30.0, 22.0, 0.5, PLATFORM], [46.0, 10.0, 18.0, 14.0, 1.0, PLATFORM],
			# 東：亂葬坑的矮棺木
			[68.0, 38.0, 10.0, 3.0, 0.5, PLATFORM], [80.0, 38.0, 10.0, 3.0, 0.5, PLATFORM],
			[68.0, 48.0, 10.0, 3.0, 0.5, PLATFORM], [80.0, 48.0, 10.0, 3.0, 0.5, PLATFORM],
			# 東南：陵墓列
			[67.0, 67.0, 6.0, 5.0, WALL_TOP, WALL], [77.0, 67.0, 6.0, 5.0, WALL_TOP, WALL], [86.0, 67.0, 6.0, 5.0, WALL_TOP, WALL],
			[67.0, 79.0, 6.0, 5.0, WALL_TOP, WALL], [77.0, 79.0, 6.0, 5.0, WALL_TOP, WALL], [86.0, 79.0, 6.0, 5.0, WALL_TOP, WALL],
		],
		# 西南、西北的墓碑林
		"tomb_rows": [[6.0, 66.0, 8, 5, 3.0, 4.0], [6.0, 6.0, 7, 4, 3.5, 5.0]],
		# 寶箱（D3）：每種幾個，開場隨機放（v0.44.0 使用者要求，原本照草圖固定 4 小 1 大；規則在 LootDefs.CHEST_PLACEMENT）
		"chest_count": {&"small": 12, &"big": 4},
		"forge_count": 1,   # 鍛造祭壇（Build 改版第 8 步）
		"packs": true,   # 開場散放怪群（D5，defs/monster_rarity_defs.gd 的 PACKS）
		"dig_event": true,   # 挖墳事件取代波次（D6，sim/dig_event.gd）
		"theme": &"graveyard",
	},
	# 第 2 層 骸骨墓窟：3 × 3 個墓室，用 6 寬的走道連成一圈；中央主墓室（石棺 = 出口、Boss）只開北門與西門，出生室在南
	# 墓室內側：西 / 中 / 東欄 x 2~27、37~59、69~94，北 / 中 / 南列 y 同；中間 10 寬的岩壁只在走道處開口
	&"catacomb_a": {
		"size": Vector2(96.0, 96.0),
		"origin": Vector2(48.0, 48.0),
		"spawn": Vector2(48.0, 88.0),
		"dig": Vector2(48.0, 48.0),
		"boss_room": [39.5, 39.5, 17.0, 17.0],   # 主墓室內側留 2.5 格
		"spawn_rule": &"around_player",
		"blocks": [
			# 外圍
			[0.0, 0.0, 96.0, 2.0, WALL_TOP, WALL], [0.0, 94.0, 96.0, 2.0, WALL_TOP, WALL],
			[0.0, 0.0, 2.0, 96.0, WALL_TOP, WALL], [94.0, 0.0, 2.0, 96.0, WALL_TOP, WALL],
			# 西欄與中欄之間的岩壁（開口 y 13~19、45~51 主墓室西門、77~83）
			[27.0, 2.0, 10.0, 11.0, WALL_TOP, WALL], [27.0, 19.0, 10.0, 26.0, WALL_TOP, WALL],
			[27.0, 51.0, 10.0, 26.0, WALL_TOP, WALL], [27.0, 83.0, 10.0, 11.0, WALL_TOP, WALL],
			# 中欄與東欄之間（開口 y 13~19、77~83；主墓室沒有東門）
			[59.0, 2.0, 10.0, 11.0, WALL_TOP, WALL], [59.0, 19.0, 10.0, 58.0, WALL_TOP, WALL], [59.0, 83.0, 10.0, 11.0, WALL_TOP, WALL],
			# 北列與中列之間（開口 x 12~18、45~51 主墓室北門、78~84）
			[2.0, 27.0, 10.0, 10.0, WALL_TOP, WALL], [18.0, 27.0, 9.0, 10.0, WALL_TOP, WALL],
			[37.0, 27.0, 8.0, 10.0, WALL_TOP, WALL], [51.0, 27.0, 8.0, 10.0, WALL_TOP, WALL],
			[69.0, 27.0, 9.0, 10.0, WALL_TOP, WALL], [84.0, 27.0, 10.0, 10.0, WALL_TOP, WALL],
			# 中列與南列之間（開口 x 12~18、78~84；主墓室沒有南門）
			[2.0, 59.0, 10.0, 10.0, WALL_TOP, WALL], [18.0, 59.0, 9.0, 10.0, WALL_TOP, WALL],
			[37.0, 59.0, 22.0, 10.0, WALL_TOP, WALL],
			[69.0, 59.0, 9.0, 10.0, WALL_TOP, WALL], [84.0, 59.0, 10.0, 10.0, WALL_TOP, WALL],
			# 西北：骨堆高台（0.5 外圈、1.0 頂）
			[7.0, 7.0, 14.0, 14.0, 0.5, PLATFORM], [10.0, 10.0, 8.0, 8.0, 1.0, PLATFORM],
			# 北廳：祭壇台階
			[42.0, 5.0, 12.0, 8.0, 0.5, PLATFORM], [45.0, 6.0, 6.0, 5.0, 1.0, PLATFORM],
			# 東北：石柱廳
			[75.0, 7.0, 2.0, 2.0, WALL_TOP, WALL], [87.0, 7.0, 2.0, 2.0, WALL_TOP, WALL], [81.0, 13.0, 2.0, 2.0, WALL_TOP, WALL],
			[75.0, 20.0, 2.0, 2.0, WALL_TOP, WALL], [87.0, 20.0, 2.0, 2.0, WALL_TOP, WALL],
			# 西：棺木台
			[6.0, 41.0, 7.0, 3.0, 0.5, PLATFORM], [16.0, 41.0, 7.0, 3.0, 0.5, PLATFORM],
			[6.0, 53.0, 7.0, 3.0, 0.5, PLATFORM], [16.0, 53.0, 7.0, 3.0, 0.5, PLATFORM],
			# 主墓室四角的矮座（石棺在正中央，周圍留空）
			[38.0, 38.0, 4.0, 4.0, 0.5, PLATFORM], [54.0, 38.0, 4.0, 4.0, 0.5, PLATFORM],
			[38.0, 54.0, 4.0, 4.0, 0.5, PLATFORM], [54.0, 54.0, 4.0, 4.0, 0.5, PLATFORM],
			# 出生室兩根石柱
			[41.0, 73.0, 2.0, 2.0, WALL_TOP, WALL], [55.0, 73.0, 2.0, 2.0, WALL_TOP, WALL],
			# 東南：小墓穴
			[73.0, 74.0, 5.0, 4.0, WALL_TOP, WALL], [84.0, 74.0, 5.0, 4.0, WALL_TOP, WALL],
			[73.0, 85.0, 5.0, 4.0, WALL_TOP, WALL], [84.0, 85.0, 5.0, 4.0, WALL_TOP, WALL],
		],
		# 東：壁龕列；西南：棺材列（用墓碑的尺寸，擋箭）
		"tomb_rows": [[73.0, 41.0, 7, 4, 3.0, 4.5], [6.0, 73.0, 7, 5, 3.0, 4.0]],
		"chest_count": {&"small": 12, &"big": 4},
		"forge_count": 1,
		"packs": true,
		"dig_event": true,
		"theme": &"catacomb",
	},
}

# 每層的地圖：從這張表裡的地圖開局，換層就換成該層的；超過表的層數用最後一層的。不在表裡的地圖（測試場地）換層也不換
const FLOOR_MAPS := {1: &"graveyard_a", 2: &"catacomb_a"}


static func floor_map(map_id: StringName, floor_num: int) -> StringName:
	if not FLOOR_MAPS.values().has(map_id):
		return map_id
	var last: int = FLOOR_MAPS.keys().max()
	return FLOOR_MAPS[clampi(floor_num, 1, last)]


static func get_map(id: StringName) -> Dictionary:
	assert(MAPS.has(id), "Unknown map: %s" % id)
	return MAPS[id]


# 展開成 Terrain 用的石台：{ min, max, top, kind }（世界座標）
static func world_blocks(m: Dictionary) -> Array[Dictionary]:
	var origin: Vector2 = m.origin
	var out: Array[Dictionary] = []
	for b: Array in m.blocks:
		var lo := Vector2(b[0], b[1]) - origin
		out.append({"min": lo, "max": lo + Vector2(b[2], b[3]), "top": b[4], "kind": b[5]})
	for r: Array in m.tomb_rows:
		for row in r[3]:
			for col in r[2]:
				var lo := Vector2(r[0] + col * r[4], r[1] + row * r[5]) - origin
				out.append({"min": lo, "max": lo + TOMB_SIZE, "top": TOMB_TOP, "kind": TOMB})
	return out


static func to_world(m: Dictionary, p: Vector2) -> Vector2:
	return p - (m.origin as Vector2)
