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
	if not world.is_any_player_alive() or world.is_over or finished:
		return

	if not queue.is_empty():
		spawn_timer -= dt
		if spawn_timer <= 0.0:
			_spawn_from_queue(world, queue.pop_front())
			spawn_timer = Config.SPAWNER.spawn_interval
		return

	for e in world.enemies:
		if not e.is_dead:
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
			(bosses if type == &"boss" else others).append(type)
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
		spawn_at(world, type, _around_player(world, type, p))
		return
	var limit: float = world.half_extents.x - Config.SPAWNER.edge_margin
	var at := Vector2.ZERO
	if type == &"boss":
		# 出現在玩家對面、靠近場地中央
		var from_center := p.length()
		var dist := minf(Config.SPAWNER.boss_distance, limit)
		at = -p / from_center * dist if from_center > 1.0 else Vector2(0.0, -dist)
	else:
		for attempt in Config.SPAWNER.spawn_attempts:
			at = Vector2(world.rng.randf_range(-limit, limit), world.rng.randf_range(-limit, limit))
			if at.distance_to(p) >= Config.SPAWNER.min_distance_from_player:
				break
	spawn_at(world, type, at)


# 大地圖（D1）：小怪生在離玩家 min ~ max 的一圈內、可走而且走得到玩家的格子；Boss 往地圖中央方向、離玩家 boss_distance
# 找不到合適的點時退回玩家旁邊最近的空地
static func _around_player(world: World, type: StringName, p: Vector2) -> Vector2:
	var s: Dictionary = Config.SPAWNER
	var nav := world.nav_for(EnemyDefs.ENEMIES[type].radius)   # Boss 用大隻的格子圖，不會生在窄縫裡
	if type == &"boss":
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


func spawn_at(world: World, type: StringName, at: Vector2) -> Enemy:
	var mul: Dictionary = (WaveDefs.NO_SCALING if type == &"boss" else WaveDefs.wave_multipliers(wave)).duplicate()
	mul.hp *= player_count_hp_mul(world.players.size())
	var enemy := create(world, type, at, mul)
	world.add_enemy(enemy)
	return enemy


# 依人數調整（C3，使用者決定）：數量不變，血量每多 1 位玩家 +50%；單機 ×1
static func player_count_hp_mul(count: int) -> float:
	return 1.0 + Config.NET.enemy_hp_per_extra_player * maxi(0, count - 1)


# 敵人類型 → 行為類別（網頁版 Spawner 的 ENEMY_CLASSES）；客戶端建立鏡像實體也用這個
static func create(world: World, type: StringName, at: Vector2, mul: Dictionary) -> Enemy:
	match type:
		&"grunt":
			return MeleeEnemy.new(world, type, at, mul)
		&"archer":
			return RangedEnemy.new(world, type, at, mul)
		&"boss":
			return Boss.new(world, type, at, mul)
	assert(false, "Unknown enemy type: %s" % type)
	return null
