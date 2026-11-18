# 分波生成（照搬網頁版 Spawner.js）：依 wave_defs 逐隻從遠離玩家的位置生成；場上清空後倒數進入下一波
# 不持有 World（避免循環參照），每次呼叫時傳入；隨機用 world.rng，地圖預放的怪群用這一層的配置亂數（World.floor_rng）
class_name Spawner
extends RefCounted

var wave := 0
var queue: Array[StringName] = []
var wave_timer := 0.0
var spawn_timer := 0.0
var finished := false


func _init() -> void:
	reset()


func total_waves() -> int:
	return WaveDefs.WAVES.size()


func reset() -> void:
	wave = 0
	queue.clear()
	wave_timer = Config.SPAWNER.first_delay
	spawn_timer = 0.0
	finished = false


func update(world: World, dt: float) -> void:
	if not world.is_any_player_alive() or world.is_over or finished or world.has_floors():   # 挖墳地圖與小關沒有波次（D6，改由 DigEvent 生怪）
		return

	if not queue.is_empty():
		spawn_timer -= dt
		if spawn_timer <= 0.0:
			_spawn_from_queue(world, queue.pop_front())
			spawn_timer = Config.SPAWNER.spawn_interval
		return

	for e in world.enemies:
		if not e.is_dead and (not e is Enemy or (e as Enemy).wave_member):   # 地圖預放的怪群不擋下一波（D5）
			return
	if wave >= total_waves():
		finished = true
		return
	wave_timer -= dt
	if wave_timer > 0.0:
		return
	_start_wave(world, wave + 1)


func _start_wave(world: World, p_wave: int) -> void:
	var def: Dictionary = WaveDefs.WAVES[p_wave - 1]
	var is_boss: bool = def.get("is_boss", false)
	wave = p_wave
	wave_timer = Config.SPAWNER.wave_delay
	spawn_timer = Config.SPAWNER.boss_first_spawn_delay if is_boss else Config.SPAWNER.first_spawn_delay

	var bosses: Array[StringName] = []
	var others: Array[StringName] = []
	for type: StringName in def.spawns:
		for i in def.spawns[type]:
			(bosses if EnemyDefs.is_boss(type) else others).append(type)
	# Boss 先出場，其餘隨機排序（Fisher-Yates，用 world.rng 才有決定性）
	for i in range(others.size() - 1, 0, -1):
		var j := world.rng.randi_range(0, i)
		var tmp := others[i]
		others[i] = others[j]
		others[j] = tmp
	queue = bosses + others

	world.stats.wave = wave
	world.emit_event("wave:started", {"wave": wave, "total": total_waves(), "is_boss": is_boss})


func _spawn_from_queue(world: World, type: StringName) -> void:
	var player := world.first_alive_player()
	var p := player.pos if player != null else Vector2.ZERO
	if world.map.spawn_rule == &"around_player":
		spawn_at(world, type, _around_player(world, type, p)).wave_member = true
		return
	var limit: float = world.half_extents.x - Config.SPAWNER.edge_margin
	var at := Vector2.ZERO
	if EnemyDefs.is_boss(type):
		# 出現在玩家對面、靠近場地中央
		var from_center := p.length()
		var dist := minf(Config.SPAWNER.boss_distance, limit)
		at = -p / from_center * dist if from_center > 1.0 else Vector2(0.0, -dist)
	else:
		for attempt in Config.SPAWNER.spawn_attempts:
			at = Vector2(world.rng.randf_range(-limit, limit), world.rng.randf_range(-limit, limit))
			if at.distance_to(p) >= Config.SPAWNER.min_distance_from_player:
				break
	spawn_at(world, type, at).wave_member = true


# 大地圖（D1）：小怪生在離玩家 min ~ max 的一圈內、可走而且走得到玩家的格子；Boss 往地圖中央方向、離玩家 boss_distance
# 找不到合適的點時退回玩家旁邊最近的空地
static func _around_player(world: World, type: StringName, p: Vector2) -> Vector2:
	var s: Dictionary = Config.SPAWNER
	var nav := world.nav_for(EnemyDefs.ENEMIES[type].radius)   # Boss 用大隻的格子圖，不會生在窄縫裡
	if EnemyDefs.is_boss(type):
		var to_center := -p
		var dir := to_center.normalized() if to_center.length() > 1.0 else Vector2(0.0, -1.0)
		var at := nav.nearest_walkable(p + dir * s.boss_distance)
		if nav.same_region(at, p):
			return at
	for attempt in s.spawn_attempts:
		var a := world.rng.randf() * TAU
		var r := world.rng.randf_range(s.min_distance_from_player, s.max_distance_from_player)
		var at := p + Vector2(sin(a), cos(a)) * r
		var lim: Vector2 = world.half_extents - Vector2(s.edge_margin, s.edge_margin)
		if absf(at.x) > lim.x or absf(at.y) > lim.y:
			continue
		if nav.is_walkable(at) and nav.same_region(at, p):
			return at
	return nav.nearest_walkable(p)


# extra 併進 mul（例如 dormant = true、initial_state，見 Enemy._init）；difficulty 指定挖墳地圖用的難度（挖墳點噴出的下一層怪）
# p_id：指定實體 id（怪群用 World.pack_entity_id，房主與客戶端各自生出來 id 才對得上）；0 = 照順序給
func spawn_at(world: World, type: StringName, at: Vector2, extra: Dictionary = {}, p_id: int = 0) -> Enemy:
	var enemy := create(world, type, at, spawn_mul(world, type, extra))
	world.add_enemy(enemy, p_id)
	return enemy


# 生成倍率：挖墳地圖依目前難度、波次依第幾波；血量再乘人數；extra 蓋上去
func spawn_mul(world: World, type: StringName, extra: Dictionary) -> Dictionary:
	var mul: Dictionary
	if world.has_floors():   # 挖墳地圖（D6）與小關：所有怪（含 Boss、怪群、冤魂）依目前難度與過了幾個小關
		mul = EventDefs.difficulty_mul(extra.get("difficulty", world.difficulty()), world.stages_cleared())
	else:
		mul = (WaveDefs.NO_SCALING if EnemyDefs.is_boss(type) else WaveDefs.wave_multipliers(wave)).duplicate()
	mul.hp *= player_count_hp_mul(world.players.size())
	mul.merge(extra)
	return mul


# ───────── 武器測試場景（--weapon-test，2026-10-27）──────────
# 木樁位置（center 為原點，等距相機的畫面方向）：右邊貼身 1 隻（近戰、鏟起）、往右一排 3 隻（穿透、散射、拋出）、上方 1 隻（影步）
const TRAINING_RIGHT := Vector2(1.0, -1.0)   # 畫面右方（世界座標，未正規化）
const TRAINING_UP := Vector2(-1.0, -1.0)     # 畫面上方
const TRAINING_SPOTS := [[&"right", 1.6], [&"right", 5.0], [&"right", 7.0], [&"right", 9.0], [&"up", 4.0]]
const TRAINING_HP := 100000.0
# 木樁的擺法（測試面板的怪物分頁選）：一般 = TRAINING_SPOTS；護甲 = 同樣位置、護甲 TRAINING_ARMOR；
# 會動 = 在右邊 TRAINING_WALK_NEAR ~ TRAINING_WALK_FAR 之間來回走的幾隻（每隻往上錯開）；一群 = 右邊 TRAINING_CROWD_AT 為中心的方陣（範圍、穿透、連鎖）
const TRAINING_KINDS := {&"normal": "一般", &"armored": "護甲", &"moving": "會動", &"crowd": "一群"}
const TRAINING_DEFAULT := &"normal"
const TRAINING_ARMOR := StatDefs.ARMOR_SCALE   # 物理傷害剛好減半，數字好對
const TRAINING_WALK_NEAR := 3.0
const TRAINING_WALK_FAR := 9.0
const TRAINING_WALK_ROWS := [0.0, 2.5, -2.5]   # 每隻離中線多遠（畫面上下）；第幾隻就從路線的哪一頭出發，錯開來
const TRAINING_CROWD_AT := 6.0
const TRAINING_CROWD_SIDE := 3                 # 方陣每邊幾隻
const TRAINING_CROWD_GAP := 1.3


# 木樁：骷髏戰士、main_state 固定 train（不動不打）、血很多、不給靈魂；被抓、被埋、燃燒、擊退照常。kind 見 TRAINING_KINDS
static func spawn_training_dummies(world: World, center: Vector2, kind: StringName = TRAINING_DEFAULT) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var right := TRAINING_RIGHT.normalized()
	var up := TRAINING_UP.normalized()
	match kind:
		&"moving":
			for i in TRAINING_WALK_ROWS.size():
				var row: Vector2 = center + up * TRAINING_WALK_ROWS[i]
				var path: Array[Vector2] = [row + right * TRAINING_WALK_NEAR, row + right * TRAINING_WALK_FAR]
				var e := _training_dummy(world, path[i % 2])
				e.train_path = path
				e.train_leg = (i + 1) % 2
				out.append(e)
		&"crowd":
			var half := (TRAINING_CROWD_SIDE - 1) * 0.5
			for ix in TRAINING_CROWD_SIDE:
				for iy in TRAINING_CROWD_SIDE:
					out.append(_training_dummy(world, center + right * (TRAINING_CROWD_AT + (ix - half) * TRAINING_CROWD_GAP) + up * (iy - half) * TRAINING_CROWD_GAP))
		_:
			for spot: Array in TRAINING_SPOTS:
				var e := _training_dummy(world, center + (right if spot[0] == &"right" else up) * spot[1])
				if kind == &"armored":
					e.stats.set_base(&"armor", TRAINING_ARMOR)
				out.append(e)
	return out


static func _training_dummy(world: World, at: Vector2) -> Enemy:
	var e := world.spawner.spawn_at(world, &"grunt", at)
	e.main_state = &"train"
	e.no_souls = true
	e.stats.set_base(&"max_hp", TRAINING_HP)
	e.hp = e.max_hp
	return e


# ───────── 怪群（D5）：開場在地圖上散放，休眠到玩家靠近（World._update_packs）──────────

# 群中心：離出生點 min_spawn_distance 以上、可走而且走得到出生點、群與群之間 min_pack_distance 以上
# rng：這一層的配置亂數（World.floor_rng）：群的位置、成員的種類、位置、朝向、稀有度、詞條都用它，同一個種子每層都一樣
# 客戶端用同一個種子在本機算出同一份怪群（休眠的怪不進快照，見 NetHost）：不同平台（Windows / Mac / 網頁）要算出一模一樣的結果，
# 所以位置只用整數亂數取 1 / PACK_GRID 的格點（二進位剛好表示得出來，加減乘都沒有捨入誤差），距離一律比平方，不用三角函數、開根號、
# randf_range（引擎內部的乘加在不同編譯器可能合併成一次運算，最後一位不同）
const PACK_GRID := 8


func spawn_packs(world: World, rng: RandomNumberGenerator) -> void:
	var c: Dictionary = MonsterRarityDefs.PACKS
	var layout := []
	if world.map.has("pack_spots"):
		# 產生的地圖（MapGen）已經挑好群的位置與隻數
		for spot: Array in world.map.pack_spots:
			_spawn_pack(world, Vector2(spot[0], spot[1]) - world.map.origin, rng, layout, spot[2])
		world.pack_digest = hash(layout) & 0x7fffffff
		return
	var lim: Vector2 = world.half_extents - Vector2(c.edge_margin, c.edge_margin)
	var want := rng.randi_range(c.count[0], c.count[1])
	var centers: Array[Vector2] = []
	var spawn_gap2: float = c.min_spawn_distance * c.min_spawn_distance
	var pack_gap2: float = c.min_pack_distance * c.min_pack_distance
	for attempt in c.attempts:
		if centers.size() >= want:
			break
		var at := Vector2(_grid(rng, lim.x), _grid(rng, lim.y))
		if at.distance_squared_to(world.spawn_point) < spawn_gap2:
			continue
		if not world.nav.is_walkable(at) or not world.nav.same_region(at, world.spawn_point):
			continue
		var apart := true
		for o in centers:
			if o.distance_squared_to(at) < pack_gap2:
				apart = false
				break
		if apart:
			centers.append(at)
	for center in centers:
		_spawn_pack(world, center, rng, layout)
	world.pack_digest = hash(layout) & 0x7fffffff


# −limit ~ limit 之間的格點（1 / PACK_GRID 單位）
static func _grid(rng: RandomNumberGenerator, limit: float) -> float:
	var n := floori(limit * PACK_GRID)
	return float(rng.randi_range(-n, n)) / PACK_GRID


# layout：每隻生出來的 [id, 種類, x, y, 稀有度, 詞條]（檢查碼用生成的值算，不看場上實體現在的位置：醒了的會走動）
# 客戶端：這個 id 已經有快照建的鏡像（那群已經醒了）就不再生一隻蓋掉它，但亂數照樣抽（後面的成員才對得上）
# count：幾隻（0 = 照 PACKS.size 抽；模板有 size 的照模板）。先抽模板（MonsterRarityDefs.PACK_TEMPLATES），照模板的 layout 擺
func _spawn_pack(world: World, center: Vector2, rng: RandomNumberGenerator, layout: Array, count: int = 0) -> void:
	var c: Dictionary = MonsterRarityDefs.PACKS
	var tpl := MonsterRarityDefs.roll_pack_template(world.floor_num, rng)
	var kind: StringName = tpl.get("layout", &"scatter")
	var lone: bool = tpl.get("lone", false)
	var pack_id := world.packs.size()
	var ids: Array[int] = []
	var placed: Array[Vector2] = []
	if tpl.has("size"):
		count = rng.randi_range(tpl.size[0], tpl.size[1])
	elif count <= 0:
		count = rng.randi_range(c.size[0], c.size[1])
	var front := _toward(center, world.spawn_point)
	var highs := _high_spots(world, center, rng) if kind == &"high" else ([] as Array[Vector2])
	var lead: StringName = tpl.members[0][0] if tpl.has("members") else &""
	var rows := {"front": 0, "back": 0}
	var capped := {}   # 有 pack_max 的種類這一群已經放了幾個
	for r in MonsterRarityDefs.roll_pack_rarities(count, rng, lone):
		var type := _roll_member(world, tpl, rng)
		var cap: int = EnemyDefs.ENEMIES[type].get("pack_max", 0)
		if cap > 0:
			if lone or capped.get(type, 0) >= cap:
				type = EnemyDefs.ENEMIES[type].pack_fallback
			else:
				capped[type] = capped.get(type, 0) + 1
		var radius: float = EnemyDefs.ENEMIES[type].radius
		var spot := _layout_spot(world, center, placed, rng, radius, kind, type == lead, front, highs, rows)
		var at: Vector2 = spot.at
		placed.append(at)
		var id := World.pack_entity_id(world.floor_num, world.stage_num, world.pack_member_count() + ids.size())
		var mirrored := world.entities.has(id)
		var e := create(world, type, at, spawn_mul(world, type, {"dormant": true})) if mirrored else spawn_at(world, type, at, {"dormant": true}, id)
		e.pack_id = pack_id
		e.facing = spot.facing if spot.has("facing") else float(rng.randi_range(0, 4095)) * TAU / 4096.0
		e.lurking = kind == &"buried"
		var idles: Array = e.def.get("idle", [])
		e.idle = (tpl.get("idle", {}) as Dictionary).get(type, idles[id % idles.size()] if not idles.is_empty() else &"")   # 不抽亂數
		roll_rarity(world, e, r, rng)
		layout.append([id, type, at.x, at.y, e.rarity, e.affixes.duplicate()])
		if mirrored:
			e.detach()   # 只是用來抽亂數的暫時實體，沒有加進 World
		ids.append(id)
	world.packs.append({"center": center, "ids": ids, "awake": false, "template": tpl.id, "loot": tpl.get("loot", false), "ambush": kind == &"buried"})


# 照模板抽一隻的種類：沒有 members 照這一層的怪物表（含上一層）；有的話第 2 層起照樣約 UPPER_SHARE 換成上一層的
static func _roll_member(world: World, tpl: Dictionary, rng: RandomNumberGenerator) -> StringName:
	if not tpl.has("members"):
		return EnemyDefs.roll_floor_type(world.floor_num, rng, true, true)
	if world.floor_num > 1 and rng.randf() < EnemyDefs.UPPER_SHARE:
		return EnemyDefs.roll_floor_type(world.floor_num - 1, rng, false, true)
	var x := rng.randf()
	var acc := 0.0
	var pick: StringName = tpl.members[0][0]
	for m: Array in tpl.members:
		pick = m[0]
		acc += float(m[1])
		if x < acc:
			break
	return pick


# 從 a 往 b 最接近的四個方向之一（單位向量的分量只有 0、±1：算得出一樣的位置，不用開根號）
static func _toward(a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	if absf(d.x) > absf(d.y):
		return Vector2(signf(d.x), 0.0)
	return Vector2(0.0, signf(d.y) if d.y != 0.0 else 1.0)


# 朝向 from → to（Enemy.facing 的角度，量化到 1 / 4096 圈）；只影響休眠時看哪邊（房主照這個發現玩家，客戶端只拿來畫）
static func _face(from: Vector2, to: Vector2) -> float:
	var d := to - from
	if d.length_squared() < 1e-8:
		return 0.0
	return float(roundi(atan2(d.x, d.y) / TAU * 4096.0)) * TAU / 4096.0


# 照模板擺一隻：回傳 { at, facing? }（沒有 facing = 隨機）
func _layout_spot(world: World, center: Vector2, placed: Array[Vector2], rng: RandomNumberGenerator, radius: float, kind: StringName,
		is_lead: bool, front: Vector2, highs: Array[Vector2], rows: Dictionary) -> Dictionary:
	var c: Dictionary = MonsterRarityDefs.PACKS
	match kind:
		&"ring_in", &"buried":   # 圍一圈面向中間（啃食群圍著屍體、伏擊埋在玩家走進來的四周）
			var ring: Array = c.feast_ring if kind == &"ring_in" else c.ambush_ring
			var at := _ring_spot(world, center, placed, rng, radius, ring[0], ring[1])
			return {"at": at, "facing": _face(at, center)}
		&"high":   # 弓手站高處、其他散開，都面朝外
			if is_lead:
				for h in highs:
					if not placed.any(func(q: Vector2) -> bool: return q.distance_squared_to(h) < c.member_gap * c.member_gap):
						return {"at": h, "facing": _face(center, h)}
			var at := _pack_member_spot(world, center, placed, rng, radius)
			return {"at": at, "facing": _face(center, at)}
		&"line":   # 第一種排在前面（往出生點那邊 1.5）面朝出生點，其他排在後面；每排從中間往兩邊 1.5 一個。
			# 被擋住就試同一排的下一個位置、再往中間縮一半，都放不下才照一般散開
			var row := "front" if is_lead else "back"
			var depth := 1.5 if is_lead else -1.0
			var facing := atan2(front.x, front.y)
			for d: float in [depth, depth * 0.5]:
				for tries in 4:
					var k: int = rows[row]
					rows[row] = k + 1
					var side := float((k + 1) / 2) * 1.5 * (1.0 if k % 2 == 1 else -1.0)
					var at := center + front * d + Vector2(-front.y, front.x) * side
					if _spot_ok(world, center, placed, at, radius):
						return {"at": at, "facing": facing}
				rows[row] = 0
			return {"at": _pack_member_spot(world, center, placed, rng, radius), "facing": facing}
	return {"at": _pack_member_spot(world, center, placed, rng, radius)}


# 離 center r0~r1 的一圈裡（正方形裡抽、不在圈裡重抽）；找不到放寬到 r0 的一半再找，還是沒有才照一般散開
func _ring_spot(world: World, center: Vector2, placed: Array[Vector2], rng: RandomNumberGenerator, radius: float, r0: float, r1: float) -> Vector2:
	for inner: float in [r0, r0 * 0.5]:
		for attempt in 24:
			var off := Vector2(_grid(rng, r1), _grid(rng, r1))
			var d2 := off.length_squared()
			if d2 < inner * inner or d2 > r1 * r1:
				continue
			if _spot_ok(world, center, placed, center + off, radius):
				return center + off
	return _pack_member_spot(world, center, placed, rng, radius)


static func _spot_ok(world: World, center: Vector2, placed: Array[Vector2], at: Vector2, radius: float) -> bool:
	var gap2: float = MonsterRarityDefs.PACKS.member_gap * MonsterRarityDefs.PACKS.member_gap
	if not world.nav.is_walkable(at) or not world.nav.same_region(at, center) or not world.terrain.clear_at(at, radius):
		return false
	return not placed.any(func(q: Vector2) -> bool: return q.distance_squared_to(at) < gap2)


# 高台弓手：群中心 high_search 內不比中心低、走得到的格點，高的排前面（同高照抽到的順序）：有石台先站石台，
# 沒有就站跟中心一樣高的地方（不會站到下面去）
func _high_spots(world: World, center: Vector2, rng: RandomNumberGenerator) -> Array[Vector2]:
	var c: Dictionary = MonsterRarityDefs.PACKS
	var base := world.terrain.ground_at(center)
	var out: Array[Vector2] = []
	for attempt in 24:
		var at := center + Vector2(_grid(rng, c.high_search), _grid(rng, c.high_search))
		if world.terrain.ground_at(at) >= base and _spot_ok(world, center, out, at, 0.5):
			out.append(at)
	out.sort_custom(func(a: Vector2, b: Vector2) -> bool: return world.terrain.ground_at(a) > world.terrain.ground_at(b))
	return out


# 遊蕩群（L 第 4 步，只在房主）：WANDER.count 群，每群 size 隻沿兩點來回走（醒著、照快照同步，不在客戶端本機生）。
# 加在 world.packs 最後面（客戶端的 packs 只有本機生的那幾群，快照的醒來位元多出來的不看）；亂數用這一層自己的 floor_rng(&"wander")
func spawn_wanderers(world: World, rng: RandomNumberGenerator) -> void:
	var w: Dictionary = MonsterRarityDefs.WANDER
	for g in w.count:
		var route := _wander_route(world, rng)
		if route.is_empty():
			continue
		var pack_id := world.packs.size()
		var ids: Array[int] = []
		var lead_id := 0
		for i in rng.randi_range(w.size[0], w.size[1]):
			var type := EnemyDefs.roll_floor_type(world.floor_num, rng, false, false)
			if type == &"beetle":   # 屍甲蟲平常鑽在地底，不會在地上排隊走
				type = &"spider"
			var at := world.nav.nearest_walkable(route[0] - _toward(route[0], route[1]) * (w.gap * i))
			var e := spawn_at(world, type, at, {"initial_state": &"wander"})
			e.pack_id = pack_id
			e.wander_route = route
			e.wander_lead = lead_id
			e.wander_slot = i
			e.facing = _face(route[0], route[1])
			if i == 0:
				lead_id = e.id
			ids.append(e.id)
		world.packs.append({"center": route[0], "ids": ids, "awake": false, "template": &"wander", "loot": false, "ambush": false, "wander": true})


# 遊蕩的兩點：都走得到出生點、離出生點至少 PACKS.min_spawn_distance、離每個怪群中心至少 spread + 3、兩點相距 route
static func _wander_route(world: World, rng: RandomNumberGenerator) -> PackedVector2Array:
	var w: Dictionary = MonsterRarityDefs.WANDER
	var lim: Vector2 = world.half_extents - Vector2(4, 4)
	var gap2: float = MonsterRarityDefs.PACKS.min_spawn_distance * MonsterRarityDefs.PACKS.min_spawn_distance
	var pack_gap: float = MonsterRarityDefs.PACKS.spread + 3.0
	var pack2 := pack_gap * pack_gap
	for attempt in w.attempts:
		var a := Vector2(_grid(rng, lim.x), _grid(rng, lim.y))
		var b := Vector2(_grid(rng, lim.x), _grid(rng, lim.y))
		var d2 := a.distance_squared_to(b)
		if d2 < w.route[0] * w.route[0] or d2 > w.route[1] * w.route[1]:
			continue
		if a.distance_squared_to(world.spawn_point) < gap2 or b.distance_squared_to(world.spawn_point) < gap2:
			continue
		if world.packs.any(func(pk: Dictionary) -> bool: return pk.center.distance_squared_to(a) < pack2 or pk.center.distance_squared_to(b) < pack2):
			continue   # 兩端離休眠的怪群遠一點：休眠的怪固定不動，起點貼著會被卡住
		if world.nav.is_walkable(a) and world.nav.is_walkable(b) and world.nav.same_region(a, world.spawn_point) and world.nav.same_region(b, world.spawn_point):
			return PackedVector2Array([a, b])
	return PackedVector2Array()


# 群中心 spread 內（正方形裡抽、超出圓就重抽）、可走、身體不碰到牆（不然房主每步會把它推出牆、跟客戶端本機的位置不同）、
# 和已放的成員至少 member_gap；找不到就放在群中心附近最近的空地（休眠中固定不動，醒了碰撞分離才推開）
static func _pack_member_spot(world: World, center: Vector2, placed: Array[Vector2], rng: RandomNumberGenerator, radius: float) -> Vector2:
	var c: Dictionary = MonsterRarityDefs.PACKS
	var gap2: float = c.member_gap * c.member_gap
	var spread2: float = c.spread * c.spread
	for attempt in 12:
		var off := Vector2(_grid(rng, c.spread), _grid(rng, c.spread))
		if off.length_squared() > spread2:
			continue
		var at := center + off
		if not world.nav.is_walkable(at) or not world.nav.same_region(at, center) or not world.terrain.clear_at(at, radius):
			continue
		var free := true
		for p in placed:
			if p.distance_squared_to(at) < gap2:
				free = false
				break
		if free:
			return at
	return world.nav.nearest_walkable(center)


# 抽詞條與名字並套上稀有度（普通不抽、不耗亂數）
# rng：怪群用這一層的配置亂數；沒給（挖墳事件、波次）用 world.rng
static func roll_rarity(world: World, e: Enemy, rarity: StringName, rng: RandomNumberGenerator = null) -> void:
	if rarity == MonsterRarityDefs.NORMAL:
		return
	var r := rng if rng != null else world.rng
	var affixes := MonsterRarityDefs.roll_affixes(MonsterRarityDefs.affix_count(rarity, r), r, e.def.get("no_affixes", []))
	var name := MonsterRarityDefs.roll_rare_name(r) if rarity == MonsterRarityDefs.RARE else ""
	e.set_rarity(rarity, affixes, name)
	e.apply_rarity_stats()


# 依人數調整（C3，使用者決定）：數量不變，血量每多 1 位玩家 +50%；單機 ×1
static func player_count_hp_mul(count: int) -> float:
	return 1.0 + Config.NET.enemy_hp_per_extra_player * maxi(0, count - 1)


# EnemyDefs 的 behavior → 行為類別（網頁版 Spawner 的 ENEMY_CLASSES）：新增怪物種類只改資料表，新增一種行為才改這裡
# （不能寫成 const Dictionary：類別互相參照時不算常數運算式）
static func behavior_class(behavior: StringName) -> GDScript:
	match behavior:
		&"melee":
			return MeleeEnemy
		&"ranged":
			return RangedEnemy
		&"boss":
			return Boss
		&"zombie":
			return Zombie
		&"bloater":
			return Bloater
		&"hound":
			return Hound
		&"spearman":
			return Spearman
		&"bone_wheel":
			return BoneWheel
		&"bone_general":
			return BoneGeneral
		&"beetle":
			return Beetle
		&"spider":
			return Spider
		&"hive":
			return Hive
		&"grave_worm":
			return GraveWorm
		&"lich":
			return Lich
		&"wraith":
			return Wraith
		&"gravekeeper":
			return Gravekeeper
	return null


# 客戶端建立鏡像實體也用這個
static func create(world: World, type: StringName, at: Vector2, mul: Dictionary) -> Enemy:
	assert(EnemyDefs.ENEMIES.has(type), "Unknown enemy type: %s" % type)
	return behavior_class(EnemyDefs.ENEMIES[type].behavior).new(world, type, at, mul)
