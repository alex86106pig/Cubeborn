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
		"name": "測試場地",
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
	# A 環形墓園（使用者 2026-10-23 選定）：中央是圍牆圍住的王族墓（出口、Boss）；外圈 7 格照種子抽區塊（2026-11-02），南邊是出生點
	&"graveyard_a": {
		"name": "墓園 A",
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
			# 王族墓圍牆的南邊（出生點那側，不開門）與裡面四角的石座
			[33.0, 61.5, 30.0, 1.5, WALL_TOP, WALL],
			[36.0, 37.0, 5.0, 5.0, 1.0, PLATFORM], [55.0, 37.0, 5.0, 5.0, 1.0, PLATFORM],
			[36.0, 55.0, 5.0, 5.0, 1.0, PLATFORM], [55.0, 55.0, 5.0, 5.0, 1.0, PLATFORM],
		],
		"tomb_rows": [],
		# 外圈 7 格（方框左上角，地圖座標）：西北、北、東北、西、東、西南、東南
		"zone_slots": [[6.0, 6.0], [37.0, 6.0], [68.0, 6.0], [6.0, 37.0], [68.0, 37.0], [6.0, 68.0], [68.0, 68.0]],
		# 王族墓的門：北 / 東 / 西抽 count 個開（中間 45~51 留 6 寬），其餘整面牆；at = 門口中心（檢查用）
		"exit_doors": {"count": 1, "sides": {
			&"N": {"at": Vector2(48.0, 33.75), "closed": [[33.0, 33.0, 30.0, 1.5, WALL_TOP, WALL]],
				"open": [[33.0, 33.0, 12.0, 1.5, WALL_TOP, WALL], [51.0, 33.0, 12.0, 1.5, WALL_TOP, WALL]]},
			&"W": {"at": Vector2(33.75, 48.0), "closed": [[33.0, 33.0, 1.5, 30.0, WALL_TOP, WALL]],
				"open": [[33.0, 33.0, 1.5, 12.0, WALL_TOP, WALL], [33.0, 51.0, 1.5, 12.0, WALL_TOP, WALL]]},
			&"E": {"at": Vector2(62.25, 48.0), "closed": [[61.5, 33.0, 1.5, 30.0, WALL_TOP, WALL]],
				"open": [[61.5, 33.0, 1.5, 12.0, WALL_TOP, WALL], [61.5, 51.0, 1.5, 12.0, WALL_TOP, WALL]]},
		}},
		# 寶箱（D3）：每種幾個，開場隨機放（v0.44.0 使用者要求，原本照草圖固定 4 小 1 大；規則在 LootDefs.CHEST_PLACEMENT）
		"chest_count": {&"small": 12, &"big": 4},
		"forge_count": 1,   # 鍛造祭壇（Build 改版第 8 步）
		"packs": true,   # 開場散放怪群（D5，defs/monster_rarity_defs.gd 的 PACKS）
		"dig_event": true,   # 挖墳事件取代波次（D6，sim/dig_event.gd）
		"theme": &"graveyard",
	},
	# 墓園（地圖改版）：每一小關照種子產生（sim/map_gen.gd、defs/map_gen_defs.gd），這裡只寫不會變的部分；
	# size、origin、spawn、dig、boss_room、blocks 與寶箱 / 怪群的位置由 MapGen.build_map 填上
	&"graveyard": {
		"name": "墓園",
		"generator": &"stage",
		"spawn_rule": &"around_player",
		"forge_count": 0,
		"packs": true,
		"theme": &"graveyard",
	},
	# 第 2 層 骸骨墓窟：3 × 3 個墓室，用 6 寬的走道連成一圈；中央主墓室（石棺 = 出口、Boss）、南邊出生室固定，其餘 7 間照種子抽區塊（2026-11-02）
	# 墓室內側：西 / 中 / 東欄 x 2~27、37~59、69~94，北 / 中 / 南列 y 同；中間 10 寬的岩壁只在走道處開口
	&"catacomb_a": {
		"name": "墓窟",
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
			# 岩壁（主墓室旁邊那幾段在 exit_doors）：西欄與中欄之間開口 y 13~19、77~83；中欄與東欄之間同
			[27.0, 2.0, 10.0, 11.0, WALL_TOP, WALL], [27.0, 83.0, 10.0, 11.0, WALL_TOP, WALL],
			[59.0, 2.0, 10.0, 11.0, WALL_TOP, WALL], [59.0, 83.0, 10.0, 11.0, WALL_TOP, WALL],
			# 北列與中列之間開口 x 12~18、78~84；中列與南列之間同（主墓室南邊整面，不開）
			[2.0, 27.0, 10.0, 10.0, WALL_TOP, WALL], [18.0, 27.0, 9.0, 10.0, WALL_TOP, WALL],
			[69.0, 27.0, 9.0, 10.0, WALL_TOP, WALL], [84.0, 27.0, 10.0, 10.0, WALL_TOP, WALL],
			[2.0, 59.0, 10.0, 10.0, WALL_TOP, WALL], [18.0, 59.0, 9.0, 10.0, WALL_TOP, WALL],
			[37.0, 59.0, 22.0, 10.0, WALL_TOP, WALL],
			[69.0, 59.0, 9.0, 10.0, WALL_TOP, WALL], [84.0, 59.0, 10.0, 10.0, WALL_TOP, WALL],
			# 主墓室四角的矮座（石棺在正中央，周圍留空）、出生室兩根石柱
			[38.0, 38.0, 4.0, 4.0, 0.5, PLATFORM], [54.0, 38.0, 4.0, 4.0, 0.5, PLATFORM],
			[38.0, 54.0, 4.0, 4.0, 0.5, PLATFORM], [54.0, 54.0, 4.0, 4.0, 0.5, PLATFORM],
			[41.0, 73.0, 2.0, 2.0, WALL_TOP, WALL], [55.0, 73.0, 2.0, 2.0, WALL_TOP, WALL],
		],
		"tomb_rows": [],
		# 7 間墓室的方框（墓室正中）：西北、北、東北、西、東、西南、東南
		"zone_slots": [[3.5, 3.5], [37.0, 3.5], [70.5, 3.5], [3.5, 37.0], [70.5, 37.0], [3.5, 70.5], [70.5, 70.5]],
		# 主墓室的門：北 / 東 / 西抽 count 個開（岩壁中間開 6 寬的走道）
		"exit_doors": {"count": 2, "sides": {
			&"N": {"at": Vector2(48.0, 32.0), "closed": [[37.0, 27.0, 22.0, 10.0, WALL_TOP, WALL]],
				"open": [[37.0, 27.0, 8.0, 10.0, WALL_TOP, WALL], [51.0, 27.0, 8.0, 10.0, WALL_TOP, WALL]]},
			&"W": {"at": Vector2(32.0, 48.0), "closed": [[27.0, 19.0, 10.0, 58.0, WALL_TOP, WALL]],
				"open": [[27.0, 19.0, 10.0, 26.0, WALL_TOP, WALL], [27.0, 51.0, 10.0, 26.0, WALL_TOP, WALL]]},
			&"E": {"at": Vector2(64.0, 48.0), "closed": [[59.0, 19.0, 10.0, 58.0, WALL_TOP, WALL]],
				"open": [[59.0, 19.0, 10.0, 26.0, WALL_TOP, WALL], [59.0, 51.0, 10.0, 26.0, WALL_TOP, WALL]]},
		}},
		"chest_count": {&"small": 12, &"big": 4},
		"forge_count": 1,
		"packs": true,
		"dig_event": true,
		"theme": &"catacomb",
	},
}

# 地圖分區的區塊（使用者 2026-11-02 選定 10 種，照 mockups/map_zones.html）：方框 ZONE_BOX × ZONE_BOX 的座標，
# 外圈 2 與中間十字 4 寬留空（門、走道一定連得通），東西只放在四角 7 × 7 的口袋；[x, y, 寬, 深, 頂面, 種類]
const ZONE_TEMPLATES := [
	{"id": &"tombs", "name": "墓碑林", "blocks": [
		[2.5, 3.0, 1.2, 0.5, TOMB_TOP, TOMB], [2.5, 6.5, 1.2, 0.5, TOMB_TOP, TOMB], [5.0, 3.0, 1.2, 0.5, TOMB_TOP, TOMB],
		[5.0, 6.5, 1.2, 0.5, TOMB_TOP, TOMB], [7.5, 3.0, 1.2, 0.5, TOMB_TOP, TOMB], [7.5, 6.5, 1.2, 0.5, TOMB_TOP, TOMB],
		[13.5, 3.0, 1.2, 0.5, TOMB_TOP, TOMB], [13.5, 6.5, 1.2, 0.5, TOMB_TOP, TOMB], [16.0, 3.0, 1.2, 0.5, TOMB_TOP, TOMB],
		[16.0, 6.5, 1.2, 0.5, TOMB_TOP, TOMB], [18.5, 3.0, 1.2, 0.5, TOMB_TOP, TOMB], [18.5, 6.5, 1.2, 0.5, TOMB_TOP, TOMB],
		[2.5, 14.0, 1.2, 0.5, TOMB_TOP, TOMB], [2.5, 17.5, 1.2, 0.5, TOMB_TOP, TOMB], [5.0, 14.0, 1.2, 0.5, TOMB_TOP, TOMB],
		[5.0, 17.5, 1.2, 0.5, TOMB_TOP, TOMB], [7.5, 14.0, 1.2, 0.5, TOMB_TOP, TOMB], [7.5, 17.5, 1.2, 0.5, TOMB_TOP, TOMB],
		[13.5, 14.0, 1.2, 0.5, TOMB_TOP, TOMB], [13.5, 17.5, 1.2, 0.5, TOMB_TOP, TOMB], [16.0, 14.0, 1.2, 0.5, TOMB_TOP, TOMB],
		[16.0, 17.5, 1.2, 0.5, TOMB_TOP, TOMB], [18.5, 14.0, 1.2, 0.5, TOMB_TOP, TOMB], [18.5, 17.5, 1.2, 0.5, TOMB_TOP, TOMB],
	]},
	{"id": &"terrace", "name": "對角高台", "blocks": [
		[2.0, 2.0, 7.0, 7.0, 0.5, PLATFORM], [3.5, 3.5, 4.0, 4.0, 1.0, PLATFORM], [14.0, 5.0, 1.2, 0.5, TOMB_TOP, TOMB],
		[17.5, 5.0, 1.2, 0.5, TOMB_TOP, TOMB], [3.0, 16.0, 1.2, 0.5, TOMB_TOP, TOMB], [6.5, 16.0, 1.2, 0.5, TOMB_TOP, TOMB],
		[13.0, 13.0, 7.0, 7.0, 0.5, PLATFORM], [14.5, 14.5, 4.0, 4.0, 1.0, PLATFORM],
	]},
	{"id": &"coffins", "name": "棺木台", "blocks": [
		[2.0, 2.5, 6.5, 2.0, 0.5, PLATFORM], [2.0, 6.5, 6.5, 2.0, 0.5, PLATFORM], [13.0, 2.5, 6.5, 2.0, 0.5, PLATFORM],
		[13.0, 6.5, 6.5, 2.0, 0.5, PLATFORM], [2.0, 13.5, 6.5, 2.0, 0.5, PLATFORM], [2.0, 17.5, 6.5, 2.0, 0.5, PLATFORM],
		[13.0, 13.5, 6.5, 2.0, 0.5, PLATFORM], [13.0, 17.5, 6.5, 2.0, 0.5, PLATFORM],
	]},
	{"id": &"pillars", "name": "石柱廳", "blocks": [
		[4.25, 4.25, 2.5, 2.5, WALL_TOP, WALL], [15.25, 4.25, 2.5, 2.5, WALL_TOP, WALL], [4.25, 15.25, 2.5, 2.5, WALL_TOP, WALL],
		[15.25, 15.25, 2.5, 2.5, WALL_TOP, WALL],
	]},
	{"id": &"crypts", "name": "小墓穴", "blocks": [
		[3.0, 3.5, 5.0, 4.0, WALL_TOP, WALL], [14.0, 3.5, 5.0, 4.0, WALL_TOP, WALL], [3.0, 14.5, 5.0, 4.0, WALL_TOP, WALL],
		[14.0, 14.5, 5.0, 4.0, WALL_TOP, WALL],
	]},
	{"id": &"ruins", "name": "廢墟牆", "blocks": [
		[2.0, 2.0, 6.0, 1.0, WALL_TOP, WALL], [2.0, 2.0, 1.0, 6.0, WALL_TOP, WALL], [14.0, 2.0, 6.0, 1.0, WALL_TOP, WALL],
		[19.0, 2.0, 1.0, 6.0, WALL_TOP, WALL], [2.0, 19.0, 6.0, 1.0, WALL_TOP, WALL], [2.0, 14.0, 1.0, 6.0, WALL_TOP, WALL],
		[14.0, 19.0, 6.0, 1.0, WALL_TOP, WALL], [19.0, 14.0, 1.0, 6.0, WALL_TOP, WALL],
	]},
	{"id": &"pit", "name": "亂葬坑", "blocks": [
		[2.0, 2.0, 2.5, 2.5, 0.5, PLATFORM], [6.0, 2.5, 3.0, 2.0, 0.5, PLATFORM], [3.0, 6.5, 2.0, 2.5, 0.5, PLATFORM], [6.5, 6.0, 2.5, 3.0, 0.5, PLATFORM],
		[13.0, 2.0, 2.5, 2.5, 0.5, PLATFORM], [17.0, 2.5, 3.0, 2.0, 0.5, PLATFORM], [14.0, 6.5, 2.0, 2.5, 0.5, PLATFORM],
		[17.5, 6.0, 2.5, 3.0, 0.5, PLATFORM], [2.0, 13.0, 2.5, 2.5, 0.5, PLATFORM], [6.0, 13.5, 3.0, 2.0, 0.5, PLATFORM],
		[3.0, 17.5, 2.0, 2.5, 0.5, PLATFORM], [6.5, 17.0, 2.5, 3.0, 0.5, PLATFORM], [13.0, 13.0, 2.5, 2.5, 0.5, PLATFORM],
		[17.0, 13.5, 3.0, 2.0, 0.5, PLATFORM], [14.0, 17.5, 2.0, 2.5, 0.5, PLATFORM], [17.5, 17.0, 2.5, 3.0, 0.5, PLATFORM],
	]},
	{"id": &"open", "name": "空地", "blocks": [
		[4.9, 5.25, 1.2, 0.5, TOMB_TOP, TOMB], [15.9, 5.25, 1.2, 0.5, TOMB_TOP, TOMB], [4.9, 16.25, 1.2, 0.5, TOMB_TOP, TOMB],
		[15.9, 16.25, 1.2, 0.5, TOMB_TOP, TOMB],
	]},
	{"id": &"mound", "name": "骨堆丘", "blocks": [
		[2.0, 2.0, 7.0, 7.0, 0.5, PLATFORM], [2.0, 2.0, 3.0, 3.0, 1.0, PLATFORM], [13.0, 2.0, 7.0, 7.0, 0.5, PLATFORM],
		[17.0, 2.0, 3.0, 3.0, 1.0, PLATFORM], [2.0, 13.0, 7.0, 7.0, 0.5, PLATFORM], [2.0, 17.0, 3.0, 3.0, 1.0, PLATFORM],
		[13.0, 13.0, 7.0, 7.0, 0.5, PLATFORM], [17.0, 17.0, 3.0, 3.0, 1.0, PLATFORM],
	]},
	{"id": &"tomb_terrace", "name": "墓碑高台", "blocks": [
		[2.5, 3.0, 1.2, 0.5, TOMB_TOP, TOMB], [5.0, 3.0, 1.2, 0.5, TOMB_TOP, TOMB], [7.5, 3.0, 1.2, 0.5, TOMB_TOP, TOMB],
		[2.5, 6.5, 1.2, 0.5, TOMB_TOP, TOMB], [5.0, 6.5, 1.2, 0.5, TOMB_TOP, TOMB], [7.5, 6.5, 1.2, 0.5, TOMB_TOP, TOMB],
		[13.0, 2.0, 7.0, 7.0, 0.5, PLATFORM], [2.0, 13.0, 7.0, 7.0, 0.5, PLATFORM], [13.5, 14.0, 1.2, 0.5, TOMB_TOP, TOMB],
		[16.0, 14.0, 1.2, 0.5, TOMB_TOP, TOMB], [18.5, 14.0, 1.2, 0.5, TOMB_TOP, TOMB], [13.5, 17.5, 1.2, 0.5, TOMB_TOP, TOMB],
		[16.0, 17.5, 1.2, 0.5, TOMB_TOP, TOMB], [18.5, 17.5, 1.2, 0.5, TOMB_TOP, TOMB],
	]},
]
const ZONE_BOX := 22.0
const DOOR_SIDES: Array[StringName] = [&"N", &"E", &"W"]   # 抽門的順序（洗牌前），exit_doors.sides 的鍵


# 這張圖這一局的地形：固定的 blocks + 出口的門（exit_doors，北 / 東 / 西洗牌取 count 個開）+ 每格抽一種區塊、轉 0~3 個 90°
# rng：World.floor_rng(&"layout")；只用整數亂數、方框座標的加減（二進位剛好表示得出來的值），客戶端照種子算出同一張
# 回傳 { blocks（地圖座標）, doors: [開的那幾邊], zones: [[區塊 id, 轉幾次], ...] }；沒有分區與門的地圖（測試場地）就是 blocks
static func layout(m: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var blocks: Array = (m.blocks as Array).duplicate()
	var doors: Array[StringName] = []
	if m.has("exit_doors"):
		var sides: Array[StringName] = DOOR_SIDES.duplicate()
		for i in range(sides.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t := sides[i]
			sides[i] = sides[j]
			sides[j] = t
		var count: int = m.exit_doors.count
		for i in sides.size():
			var side := sides[i]
			var def: Dictionary = m.exit_doors.sides[side]
			if i < count:
				doors.append(side)
				blocks.append_array(def.open)
			else:
				blocks.append_array(def.closed)
	var zones := []
	for slot: Array in m.get("zone_slots", []):
		var k := rng.randi_range(0, ZONE_TEMPLATES.size() - 1)
		var turns := rng.randi_range(0, 3)
		zones.append([ZONE_TEMPLATES[k].id, turns])
		for b: Array in ZONE_TEMPLATES[k].blocks:
			var r := _rotate(b, turns)
			blocks.append([slot[0] + r[0], slot[1] + r[1], r[2], r[3], r[4], r[5]])
	return {"blocks": blocks, "doors": doors, "zones": zones}


# 方框裡順時針轉 90° × turns：(x, y, 寬, 深) → (BOX − y − 深, x, 深, 寬)
static func _rotate(b: Array, turns: int) -> Array:
	var x: float = b[0]
	var y: float = b[1]
	var w: float = b[2]
	var d: float = b[3]
	for i in turns:
		var nx := ZONE_BOX - y - d
		y = x
		x = nx
		var t := w
		w = d
		d = t
	return [x, y, w, d, b[4], b[5]]


const DOOR_NAMES := {&"N": "北", &"E": "東", &"W": "西"}


# 這一層地形的一句話（遊玩紀錄用）：開哪幾邊的門、7 格各是哪種區塊
static func layout_text(layout: Dictionary) -> String:
	var parts: Array[String] = []
	if layout.has("stage"):
		var names: Array[String] = []
		for themes: Array in layout.themes:
			names.append("＋".join(PackedStringArray(themes.map(func(t: StringName) -> String: return MapGenDefs.THEME_NAMES.get(t, String(t))))))
		parts.append("第 %d 小關 %s" % [layout.stage, "、".join(PackedStringArray(names))])
	var doors: Array = layout.get("doors", [])
	if not doors.is_empty():
		parts.append("門 " + "、".join(PackedStringArray(doors.map(func(d: StringName) -> String: return DOOR_NAMES[d]))))
	var zones: Array = layout.get("zones", [])
	if not zones.is_empty():
		var names: Array[String] = []
		for z: Array in zones:
			for t: Dictionary in ZONE_TEMPLATES:
				if t.id == z[0]:
					names.append(t.name)
		parts.append("區塊 " + "、".join(PackedStringArray(names)))
	return "；".join(PackedStringArray(parts))


# 地圖有沒有照種子變的部分（分區、門）：沒有的地圖換種子不用重建地形
static func has_layout(m: Dictionary) -> bool:
	return m.has("generator") or m.has("exit_doors") or not (m.get("zone_slots", []) as Array).is_empty()


# 每層的地圖：從這張表裡的地圖開局，換層就換成該層的；超過表的層數用最後一層的。不在表裡的地圖（測試場地）換層也不換
const FLOOR_MAPS := {1: &"graveyard", 2: &"catacomb_a"}


static func floor_map(map_id: StringName, floor_num: int) -> StringName:
	if not FLOOR_MAPS.values().has(map_id):
		return map_id
	var last: int = FLOOR_MAPS.keys().max()
	return FLOOR_MAPS[clampi(floor_num, 1, last)]


static func get_map(id: StringName) -> Dictionary:
	assert(MAPS.has(id), "Unknown map: %s" % id)
	return MAPS[id]


# 展開成 Terrain 用的石台：{ min, max, top, kind }（世界座標）
# blocks：這一局的石台（layout().blocks，地圖座標）；沒給就用地圖資料的固定 blocks
static func world_blocks(m: Dictionary, blocks: Array = []) -> Array[Dictionary]:
	var origin: Vector2 = m.origin
	var out: Array[Dictionary] = []
	for b: Array in (blocks if not blocks.is_empty() else m.blocks):
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
