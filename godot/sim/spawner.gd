# 分波生成（照搬網頁版 Spawner.js）：依 wave_defs 逐隻從遠離玩家的位置生成；場上清空後倒數進入下一波
# 不持有 World（避免循環參照），每次呼叫時傳入；隨機一律用 world.rng
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
	if not world.is_any_player_alive() or world.is_over or finished or DigEvent.enabled(world):   # 挖墳地圖沒有波次（D6，改由 DigEvent 生怪）
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
func spawn_at(world: World, type: StringName, at: Vector2, extra: Dictionary = {}) -> Enemy:
	var mul: Dictionary
	if DigEvent.enabled(world):   # 挖墳地圖（D6）：所有怪（含 Boss、怪群、冤魂）依目前難度
		mul = EventDefs.difficulty_mul(extra.get("difficulty", world.difficulty()))
	else:
		mul = (WaveDefs.NO_SCALING if EnemyDefs.is_boss(type) else WaveDefs.wave_multipliers(wave)).duplicate()
	mul.hp *= player_count_hp_mul(world.players.size())
	mul.merge(extra)
	var enemy := create(world, type, at, mul)
	world.add_enemy(enemy)
	return enemy


# ───────── 武器測試場景（--weapon-test，2026-10-27）──────────
# 木樁位置（center 為原點，等距相機的畫面方向）：右邊貼身 1 隻（近戰、鏟起）、往右一排 3 隻（穿透、散射、拋出）、上方 1 隻（影步）
const TRAINING_RIGHT := Vector2(1.0, -1.0)   # 畫面右方（世界座標，未正規化）
const TRAINING_UP := Vector2(-1.0, -1.0)     # 畫面上方
const TRAINING_SPOTS := [[&"right", 1.6], [&"right", 5.0], [&"right", 7.0], [&"right", 9.0], [&"up", 4.0]]
const TRAINING_HP := 100000.0


# 木樁：骷髏戰士、main_state 固定 train（不動不打）、血很多、不給靈魂；被抓、被埋、燃燒、擊退照常
static func spawn_training_dummies(world: World, center: Vector2) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for spot: Array in TRAINING_SPOTS:
		var dir: Vector2 = (TRAINING_RIGHT if spot[0] == &"right" else TRAINING_UP).normalized()
		var e := world.spawner.spawn_at(world, &"grunt", center + dir * spot[1])
		e.main_state = &"train"
		e.no_souls = true
		e.stats.set_base(&"max_hp", TRAINING_HP)
		e.hp = e.max_hp
		out.append(e)
	return out


# ───────── 怪群（D5）：開場在地圖上散放，休眠到玩家靠近（World._update_packs）──────────

# 群中心：離出生點 min_spawn_distance 以上、可走而且走得到出生點、群與群之間 min_pack_distance 以上
func spawn_packs(world: World) -> void:
	var c: Dictionary = MonsterRarityDefs.PACKS
	var rng := world.rng
	var lim: Vector2 = world.half_extents - Vector2(c.edge_margin, c.edge_margin)
	var want := rng.randi_range(c.count[0], c.count[1])
	var centers: Array[Vector2] = []
	for attempt in c.attempts:
		if centers.size() >= want:
			break
		var at := Vector2(rng.randf_range(-lim.x, lim.x), rng.randf_range(-lim.y, lim.y))
		if at.distance_to(world.spawn_point) < c.min_spawn_distance:
			continue
		if not world.nav.is_walkable(at) or not world.nav.same_region(at, world.spawn_point):
			continue
		var apart := true
		for o in centers:
			if o.distance_to(at) < c.min_pack_distance:
				apart = false
				break
		if apart:
			centers.append(at)
	for center in centers:
		_spawn_pack(world, center)


func _spawn_pack(world: World, center: Vector2) -> void:
	var c: Dictionary = MonsterRarityDefs.PACKS
	var rng := world.rng
	var pack_id := world.packs.size()
	var ids: Array[int] = []
	var placed: Array[Vector2] = []
	for r in MonsterRarityDefs.roll_pack_rarities(rng.randi_range(c.size[0], c.size[1]), rng):
		var type := EnemyDefs.roll_floor_type(world.floor_num, rng)
		var at := _pack_member_spot(world, center, placed)
		placed.append(at)
		var e := spawn_at(world, type, at, {"dormant": true})
		e.pack_id = pack_id
		e.facing = rng.randf() * TAU
		roll_rarity(world, e, r)
		ids.append(e.id)
	world.packs.append({"center": center, "ids": ids, "awake": false})


# 群中心 spread 內、可走、和已放的成員至少 member_gap；找不到就放在群中心附近最近的空地（碰撞分離會推開）
static func _pack_member_spot(world: World, center: Vector2, placed: Array[Vector2]) -> Vector2:
	var c: Dictionary = MonsterRarityDefs.PACKS
	var rng := world.rng
	var gap2: float = c.member_gap * c.member_gap
	for attempt in 12:
		var a := rng.randf() * TAU
		var r: float = sqrt(rng.randf()) * c.spread
		var at := center + Vector2(sin(a), cos(a)) * r
		if not world.nav.is_walkable(at) or not world.nav.same_region(at, center):
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
static func roll_rarity(world: World, e: Enemy, rarity: StringName) -> void:
	if rarity == MonsterRarityDefs.NORMAL:
		return
	var affixes := MonsterRarityDefs.roll_affixes(MonsterRarityDefs.affix_count(rarity, world.rng), world.rng)
	var name := MonsterRarityDefs.roll_rare_name(world.rng) if rarity == MonsterRarityDefs.RARE else ""
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
	return null


# 客戶端建立鏡像實體也用這個
static func create(world: World, type: StringName, at: Vector2, mul: Dictionary) -> Enemy:
	assert(EnemyDefs.ENEMIES.has(type), "Unknown enemy type: %s" % type)
	return behavior_class(EnemyDefs.ENEMIES[type].behavior).new(world, type, at, mul)
