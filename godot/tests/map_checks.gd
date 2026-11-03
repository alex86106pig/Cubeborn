# 地圖、尋路與生成：波次、地形、地圖 A、怪物繞牆與跳上高台、事件生怪的位置
# 由 tests/check.gd 呼叫；每個 check_* 回傳 "" = 通過，否則是失敗原因
class_name MapChecks
extends CheckKit

static func check_wave_defs() -> String:
	var waves := WaveDefs.WAVES
	if waves.size() < 2:
		return "只有 %d 波" % waves.size()
	var last := waves.size() - 1
	for i in waves.size():
		var w: Dictionary = waves[i]
		if w.get("is_boss", false) != (i == last):
			return "第 %d 波 is_boss 不正確（只有最後一波是 Boss）" % (i + 1)
		var n := 0
		for type: StringName in w.spawns:
			if not EnemyDefs.ENEMIES.has(type):
				return "第 %d 波的敵人類型「%s」不存在" % [i + 1, type]
			if type != &"boss":
				n += w.spawns[type]
		if i < last and n <= 0:
			return "第 %d 波沒有小怪" % (i + 1)
	# 成長倍率線性：第 1 波 ×1，之後每波加 WAVE_SCALING
	var m1 := WaveDefs.wave_multipliers(1)
	var m3 := WaveDefs.wave_multipliers(3)
	for k: String in ["hp", "damage", "speed"]:
		if m1[k] != 1.0 or absf(m3[k] - (1.0 + 2.0 * WaveDefs.WAVE_SCALING[k])) > EPS:
			return "倍率錯誤：第 1 波 %s、第 3 波 %s" % [m1, m3]
	return ""


static func check_spawning() -> String:
	var w := _new_world(4242, true)
	var events: Array[Dictionary] = []
	var sc := Config.SPAWNER
	var steps := _run_until(w, _cmd(Vector2.ZERO), 300, events, func() -> bool: return not _named(events, "wave:started").is_empty())
	var first_steps := roundi(sc.first_delay / DT)
	if absi(steps - first_steps) > 1:
		return "第一波在第 %d 步開始，預期約 %d 步" % [steps, first_steps]
	# 逐步記錄每隻敵人剛出現時離玩家的距離（之後會追過來，不能等全部生完才量）
	var count := 0
	for type: StringName in WaveDefs.WAVES[0].spawns:
		count += WaveDefs.WAVES[0].spawns[type]
	var p := _player(w)
	var seen := {}
	for i in ceili((sc.first_spawn_delay + (count - 1) * sc.spawn_interval) / DT) + 8:   # 計時器以浮點遞減，每段可能多 1 步
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		for e in w.enemies:
			if not seen.has(e.id):
				seen[e.id] = e.pos.distance_to(p.pos)
	if seen.size() != count:
		return "第一波生成 %d 隻，預期 %d" % [seen.size(), count]
	for id: int in seen:
		if seen[id] < sc.min_distance_from_player:
			return "敵人生成在離玩家 %.2f 處，應 ≥ %.1f" % [seen[id], sc.min_distance_from_player]
	w.spawner.wave = 3
	var m3 := WaveDefs.wave_multipliers(3)
	var g := _spawn(w, &"grunt", Vector2(10, 10))
	var want_hp := roundf(EnemyDefs.ENEMIES.grunt.max_hp * m3.hp)
	if g.max_hp != want_hp or absf(g.damage_mul - m3.damage) > EPS:
		return "第 3 波小怪 max_hp=%.1f damage_mul=%.3f，預期 %.0f / %.3f" % [g.max_hp, g.damage_mul, want_hp, m3.damage]
	return ""


static func check_full_run() -> String:
	var w := _new_world(99, true)
	var p := _player(w)
	var events: Array[Dictionary] = []
	var enemy_deaths := 0
	var boss_died_tick := -1
	for i in 60 * 120:
		p.invuln_timer = 1.0   # 這項只測流程，不讓玩家被打死
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		events.append_array(w.events)
		for e in w.enemies:
			if not e.is_dead:
				e.die()
				enemy_deaths += 1
				if (e as Enemy).is_boss():
					boss_died_tick = w.tick
		if not _named(events, "game:victory").is_empty():
			break
	var n := WaveDefs.WAVES.size()
	var started := _named(events, "wave:started")
	if started.size() != n or not started[n - 1].is_boss:
		return "wave:started %d 次（預期 %d，最後一波是 Boss）" % [started.size(), n]
	var victory := _named(events, "game:victory")
	if victory.is_empty() or not w.is_over:
		return "打倒 Boss 後沒有通關"
	var delay := (w.tick - boss_died_tick) * DT
	if absf(delay - Config.WORLD.victory_delay) > DT * 1.5:
		return "Boss 倒下到 game:victory 經過 %.3f 秒，預期 %.2f" % [delay, Config.WORLD.victory_delay]
	if victory[0].stats.kills != enemy_deaths or w.stats.wave != n:
		return "擊殺數 %d（實際打倒 %d）、wave=%d" % [victory[0].stats.kills, enemy_deaths, w.stats.wave]
	return ""


# 往 move 方向走 steps 步，可選擇第一步起跳
static func _walk(w: World, move: Vector2, steps: int, jump := false) -> void:
	if jump:
		_run(w, _jump_cmd(move), 1)
		steps -= 1
	_run(w, _cmd(move), steps)


static func check_terrain() -> String:
	var w := _new_world()
	var p := _player(w)
	# 0.5 石台：x 7.75~10.25、z 10.75~13.25
	p.pos = Vector2(9.0, 9.5)
	_walk(w, Vector2(0, 1), 60)
	if p.pos.y > 10.75 - p.radius + 0.01 or p.height != 0.0:
		return "0.5 石台應走不上去：z %.2f、高度 %.2f" % [p.pos.y, p.height]
	# 走 20 步（約 2.2 單位）再原地等落地：停在石台上，不會走過整塊掉下去
	_walk(w, Vector2(0, 1), 20, true)
	_run(w, _cmd(Vector2.ZERO), 30)
	if absf(p.height - 0.5) > 1e-3 or p.pos.y < 10.75:
		return "應跳上 0.5 石台：z %.2f、高度 %.3f" % [p.pos.y, p.height]
	# 往 +X 走到 1.0 石台（x 10.25 起）：走不上去，跳得上去
	p.pos = Vector2(9.0, 12.0)
	_walk(w, Vector2(1, 0), 40)
	if p.height > 0.5 + 1e-3 or p.pos.x > 10.25 - p.radius + 0.01:
		return "從 0.5 應走不上 1.0：x %.2f、高度 %.2f" % [p.pos.x, p.height]
	_walk(w, Vector2(1, 0), 20, true)
	_run(w, _cmd(Vector2.ZERO), 30)
	if absf(p.height - 1.0) > 1e-3:
		return "應從 0.5 跳上 1.0 石台，實際高度 %.3f（x %.2f）" % [p.height, p.pos.x]
	# 走出 1.0 石台的 +X 邊緣（13.75）會掉回地面
	_walk(w, Vector2(1, 0), 60)
	if p.height != 0.0 or p.pos.x < 13.75:
		return "走出邊緣應掉回地面：x %.2f、高度 %.2f" % [p.pos.x, p.height]
	# 2.5 的牆（z 7.5~8.5）：從南邊一直跳也過不去
	p.pos = Vector2(11.0, 5.0)
	for i in 4:
		_walk(w, Vector2(0, 1), 40, true)
	if p.pos.y > 7.5 - p.radius + 0.01:
		return "2.5 的牆不應跳得過：z %.2f、高度 %.2f" % [p.pos.y, p.height]
	return ""


# Terrain.may_rise 排除的點，ground_at 一定不會落在起跳範圍（怪物起跳偵測先用它排除，不能漏掉任何一次起跳）
# 兩張地圖：網格取點 + 每個石台的角與邊緣內外；腳下高度含 0、各頂面，以及剛好差 step / climb_height 的邊界值
static func check_may_rise() -> String:
	var lo: float = Config.HEIGHT.step
	var hi: float = Config.NAV.climb_height
	var tested := 0
	for map_id: StringName in [&"test_arena", &"graveyard_a", &"catacomb_a"]:
		var w := _new_world(12345, false, map_id)
		if MapDefs.FLOOR_MAPS.values().has(map_id):
			w.sync_floor(MapDefs.FLOOR_MAPS.find_key(map_id))   # reset 會回到第 1 層的地圖
		var t := w.terrain
		var froms: Array[float] = [0.0]
		for b in t.blocks:
			for f: float in [b.top, b.top - lo, b.top - hi]:
				if f >= 0.0 and not froms.has(f):
					froms.append(f)
		var points := PackedVector2Array()
		var x := -w.half_extents.x
		while x <= w.half_extents.x:
			var z := -w.half_extents.y
			while z <= w.half_extents.y:
				points.append(Vector2(x, z))
				z += 0.25
			x += 0.25
		for b in t.blocks:
			for d: float in [-1e-6, 0.0, 1e-6]:
				for corner: Vector2 in [b.min, b.max, Vector2(b.min.x, b.max.y), Vector2(b.max.x, b.min.y)]:
					points.append(corner + Vector2(d, d))
					points.append(corner - Vector2(d, -d))
		for p in points:
			var ground := t.ground_at(p)
			for f in froms:
				var rise := ground - f
				if rise > lo and rise <= hi and not t.may_rise(p, f, lo, hi):
					return "%s：%s 腳下 %.3f 會起跳（高低差 %.3f），may_rise 卻排除" % [map_id, p, f, rise]
				tested += 1
	_note("may_rise 比對 %d 組（點 × 腳下高度），沒有漏掉起跳" % tested)
	return ""


# 每一層的地圖（MapDefs.FLOOR_MAPS）都照同一套規則：用 next_floor 走到那一層，跟遊戲裡一樣
# 每層的地形照種子抽門與區塊：換 LAYOUT_SEEDS 個種子都要符合同一套規則、怪群放得下；所有區塊與門的方向都抽得到
const LAYOUT_SEEDS := 16

static func check_map_a() -> String:
	var used := {}
	for s in range(0, LAYOUT_SEEDS + 1):
		var seed_value := 12345 if s == 0 else s
		for f: int in MapDefs.FLOOR_MAPS:
			var err := _check_floor_map(f, seed_value, s == 0, used)
			if err != "":
				return "%s 種子 %d：%s" % [MapDefs.FLOOR_MAPS[f], seed_value, err]
	for t: Dictionary in MapDefs.ZONE_TEMPLATES:
		if not used.has(t.id):
			return "%d 個種子都沒抽到區塊 %s" % [LAYOUT_SEEDS + 1, t.name]
	for side: StringName in MapDefs.DOOR_SIDES:
		if not used.has(side):
			return "%d 個種子都沒開過 %s 邊的門" % [LAYOUT_SEEDS + 1, side]
	_note("地形：%d 個種子 × %d 層都符合規則，%d 種區塊、%d 個方向的門都抽到" % [LAYOUT_SEEDS + 1, MapDefs.FLOOR_MAPS.size(), MapDefs.ZONE_TEMPLATES.size(), MapDefs.DOOR_SIDES.size()])
	return ""


# 種子：每層的怪群與寶箱只看種子（World.floor_rng），第 1 層打法不同（world.rng 用掉的量不同）第 2 層照樣一樣；換種子就不一樣
static func check_floor_seed() -> String:
	var layouts := []
	for case: Array in [[77, 0], [77, 500], [78, 0]]:
		var w := World.new(&"graveyard_a")
		w.reset(case[0])
		w.spawner.finished = true
		_worlds.append(w)
		var first := _layout(w)
		for i in int(case[1]):
			w.rng.randf()   # 當成第 1 層打了一場（爆擊、閃避、AI 都用 world.rng）
		w.next_floor()
		layouts.append([first, _layout(w)])
	if layouts[0][0] != layouts[1][0] or layouts[0][1] != layouts[1][1]:
		return "同一個種子，第 1 層打法不同，第 2 層的怪群 / 寶箱配置應相同"
	if layouts[0][0] == layouts[2][0] or layouts[0][1] == layouts[2][1]:
		return "不同種子的配置應不同"
	CheckKit._note("種子：第 2 層怪群 %d 隻、寶箱 %d 個，同種子兩局一致" % [(layouts[0][1][0] as Array).size(), (layouts[0][1][1] as Array).size()])
	return ""


# 這一層的配置：怪群成員（種類、位置、稀有度、詞條）、寶箱與鍛造祭壇（種類、位置），位置取到 0.001
static func _layout(w: World) -> Array:
	var packs := []
	for e in w.enemies:
		var en := e as Enemy
		if en != null and en.pack_id >= 0:
			packs.append([en.type, snappedf(en.pos.x, 0.001), snappedf(en.pos.y, 0.001), en.rarity, en.affixes.duplicate()])
	var chests := []
	for c in w.chests:
		chests.append([(c as Chest).tier, snappedf(c.pos.x, 0.001), snappedf(c.pos.y, 0.001)])
	for f in w.forges:
		chests.append([&"forge", snappedf(f.pos.x, 0.001), snappedf(f.pos.y, 0.001)])
	return [packs, chests, w.layout.doors.duplicate(), w.layout.zones.duplicate(true)]


# note：記可走格數（只記一個種子）；used：記抽到的區塊 id 與門的方向
static func _check_floor_map(floor_num: int, seed_value: int, note: bool, used: Dictionary) -> String:
	var w := World.new(MapDefs.FLOOR_MAPS[1])
	w.reset(seed_value)
	w.spawner.finished = true
	_worlds.append(w)
	for i in floor_num - 1:
		w.next_floor()
	if w.map_id != MapDefs.FLOOR_MAPS[floor_num]:
		return "第 %d 層應是這張地圖，實際 %s" % [floor_num, w.map_id]
	for z: Array in w.layout.zones:
		used[z[0]] = true
	for side: StringName in w.layout.doors:
		used[side] = true
	if w.map.has("exit_doors") and w.layout.doors.size() != int(w.map.exit_doors.count):
		return "出口應開 %d 個門，實際 %s" % [w.map.exit_doors.count, w.layout.doors]
	var pc: Dictionary = MonsterRarityDefs.PACKS
	if w.map.has("pack_spots"):
		if w.packs.size() != (w.map.pack_spots as Array).size() or w.packs.is_empty():
			return "產生的地圖挑了 %d 群的位置，放下 %d 群" % [(w.map.pack_spots as Array).size(), w.packs.size()]
	elif w.packs.size() < pc.count[0]:
		return "怪群只放得下 %d 群（至少 %d）" % [w.packs.size(), pc.count[0]]
	for e in w.enemies:
		if (e as Enemy).pack_id >= 0 and (not w.nav.is_walkable(e.pos) or not w.nav.same_region(e.pos, w.spawn_point)):
			return "怪群成員放在走不到的地方 %s" % e.pos
	return _map_rules(w, note)


# 一張地圖的規則（每層的地圖、每種小關都照這套）：大小與邊界、石台在場地內、出生點與挖墳點可走且相連、可走格連成一片、
# 相鄰可走格高低差、牆夠高、石台網格的三角形都是正面；note：記可走格數
static func _map_rules(w: World, note: bool) -> String:
	var m := w.map
	var half := w.half_extents
	if m.size != half * 2.0:
		return "地圖大小 %s 與場地邊界 ±%s 不一致" % [m.size, half]
	for b in w.terrain.blocks:
		if b.min.x < -half.x - EPS or b.min.y < -half.y - EPS or b.max.x > half.x + EPS or b.max.y > half.y + EPS:
			return "石台超出場地：%s ~ %s" % [b.min, b.max]
	var nav := w.nav
	var spawn := w.spawn_point
	var dig := MapDefs.to_world(m, m.dig)
	if not nav.is_walkable(spawn) or not nav.is_walkable(dig) or not nav.same_region(spawn, dig):
		return "出生點 %s 與挖墳點 %s 應可走且相連" % [spawn, dig]
	if not w.players.is_empty() and _player(w).pos != spawn:
		return "玩家應出生在 %s，實際 %s" % [spawn, _player(w).pos]
	var regions := {}
	var walkable := 0
	for r in nav.region:
		if r >= 0:
			regions[r] = true
			walkable += 1
	if regions.size() != 1:
		return "可走的格子分成 %d 塊（有怪物到不了的地方）" % regions.size()
	var climb: float = Config.NAV.climb_height
	for x in nav.size.x:
		for y in nav.size.y:
			var c := Vector2i(x, y)
			if not nav.is_walkable_cell(c):
				continue
			var g := w.terrain.ground_at(nav.cell_center(c))
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var q := c + d
				if nav.is_walkable_cell(q) and absf(w.terrain.ground_at(nav.cell_center(q)) - g) > climb + EPS:
					return "相鄰可走格 %s → %s 高低差 %.2f > %.2f（怪物跳不上去）" % [c, q, absf(w.terrain.ground_at(nav.cell_center(q)) - g), climb]
	var highest := 0.0
	var counts := {}
	for b in w.terrain.blocks:
		counts[b.kind] = counts.get(b.kind, 0) + 1
		if b.kind == MapDefs.PLATFORM:
			highest = maxf(highest, b.top)
	for b in w.terrain.blocks:
		if b.kind == MapDefs.WALL and b.top - highest < Config.JUMP.height + 0.3:
			return "牆 %.1f 只比最高的地面 %.1f 高 %.1f，跳得上去" % [b.top, highest, b.top - highest]
	# 畫面：所有石台合併成一個網格，每個三角形都是正面（Godot：cross(b - a, c - a) 與法線反向）
	var mi := ArenaView.create_blocks(w.terrain.blocks, m.get("theme", &"graveyard"))
	var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	mi.free()
	if verts.size() != w.terrain.blocks.size() * 30:
		return "石台網格應有 %d 個頂點（每個石台 5 面），實際 %d" % [w.terrain.blocks.size() * 30, verts.size()]
	for i in range(0, verts.size(), 3):
		if (verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i]).dot(normals[i]) >= 0.0:
			return "石台網格第 %d 個三角形是背面" % (i / 3)
	if note:
		_note("%s：可走格 %d / %d、牆 %d、墓碑 %d、高台 %d" % [w.map_id, walkable, nav.size.x * nav.size.y, counts.get(MapDefs.WALL, 0), counts.get(MapDefs.TOMB, 0), counts.get(MapDefs.PLATFORM, 0)])
	return ""


# 玩家站著不動、每步補滿血；回傳第一次被打中的步數（-1 = 沒被打中）；on_step 每步之後呼叫
static func _run_until_hurt(w: World, max_steps: int, on_step: Callable = Callable()) -> int:
	var p := _player(w)
	for i in max_steps:
		p.hp = p.max_hp
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		if on_step.is_valid():
			on_step.call()
		if p.hp < p.max_hp:
			return i + 1
	return -1


static func check_enemy_pathing() -> String:
	var w := _new_world(12345, false, &"graveyard_a")
	var p := _player(w)
	p.pos = MapDefs.to_world(w.map, w.map.dig)
	var g := _spawn(w, &"grunt", Vector2(0, 22))   # 圍牆南邊外面（南邊不開門）
	var side: StringName = w.layout.doors[0]   # 門照種子開在北 / 東 / 西其中一邊
	var door := MapDefs.to_world(w.map, w.map.exit_doors.sides[side].at)
	var closest := [INF]
	var t := _run_until_hurt(w, 90 * 60, func() -> void: closest[0] = minf(closest[0], g.pos.distance_to(door)))
	if t < 0:
		return "骷髏戰士 90 秒內沒打到玩家（停在 %s）" % g.pos
	if closest[0] > 2.5:
		return "骷髏戰士應繞到門口（%s 門 %s）進來，最近只到 %.1f" % [side, door, closest[0]]
	var w2 := _new_world(12345, false, &"graveyard_a")
	var p2 := _player(w2)
	p2.pos = p.pos
	var a := _spawn(w2, &"archer", Vector2(0, 22))
	var t2 := _run_until_hurt(w2, 90 * 60)
	if t2 < 0:
		return "弓手 90 秒內沒射中玩家（停在 %s）" % a.pos
	_note("繞到 %s 門：骷髏戰士 %.1f 秒打到玩家（離門口最近 %.1f）、弓手 %.1f 秒射中" % [side, t * DT, closest[0], t2 * DT])
	return ""


static func check_enemy_climb() -> String:
	var w := _new_world()
	var p := _player(w)
	p.pos = Vector2(12, 12)   # 1.0 石台中央；西邊 x 7.75~10.25 是 0.5 石台
	p.height = 1.0
	var g := _spawn(w, &"grunt", Vector2(2, 12))
	var heights := {"half": -1, "top": -1, "windup": 0, "windup_done": false}
	var watch := func() -> void:
		if g._jump_windup > 0.0 and not heights.windup_done:
			heights.windup += 1
		elif heights.windup > 0:
			heights.windup_done = true
		if g.is_grounded() and heights.half < 0 and absf(g.height - 0.5) < EPS:
			heights.half = w.tick
		if g.is_grounded() and heights.top < 0 and absf(g.height - 1.0) < EPS:
			heights.top = w.tick
	var t := _run_until_hurt(w, 20 * 60, watch)
	if heights.half < 0 or heights.top < 0:
		return "骷髏戰士應先跳上 0.5 再跳上 1.0：0.5 第 %d 步、1.0 第 %d 步、高度 %.2f" % [heights.half, heights.top, g.height]
	if absi(heights.windup - roundi(Config.NAV.jump_windup / DT)) > 1:
		return "起跳前應蹲 %.2f 秒，實際 %d 步" % [Config.NAV.jump_windup, heights.windup]
	if t < 0:
		return "骷髏戰士上了石台卻沒打到玩家"
	var w2 := _new_world()
	var p2 := _player(w2)
	p2.pos = Vector2(12, 12)
	p2.height = 1.0
	var boss := _spawn(w2, &"boss", Vector2(2, 12))
	var top := -1
	for i in 30 * 60:
		p2.hp = p2.max_hp
		w2.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		if boss.is_grounded() and absf(boss.height - 1.0) < EPS:
			top = i + 1
			break
	if top < 0:
		return "Boss 30 秒內沒跳上 1.0 石台（停在 %s、高度 %.2f）" % [boss.pos, boss.height]
	_note("骷髏戰士：第 %.2f 秒上 0.5、%.2f 秒上 1.0、%.2f 秒打到玩家（起跳前蹲 %d 步）；Boss %.1f 秒上 1.0" % [heights.half * DT, heights.top * DT, t * DT, heights.windup, top * DT])
	return ""


static func check_archer_high_ground() -> String:
	var w := _new_world()
	var p := _player(w)
	p.pos = Vector2(12, 12)
	p.height = 1.0
	_spawn(w, &"archer", Vector2(0, 12))
	var t := _run_until_hurt(w, 10 * 60)
	if t < 0:
		return "玩家在 1.0 石台上，弓手 10 秒內沒射中"
	# 2.5 的牆（x 8~14、z 7.5~8.5）擋在中間：弓手先移動到射得到的地方，不對牆射
	var w2 := _new_world()
	var p2 := _player(w2)
	p2.pos = Vector2(12, 12)
	p2.height = 1.0
	var a := _spawn(w2, &"archer", Vector2(11, 3))
	var fizzles := [0]
	var t2 := _run_until_hurt(w2, 20 * 60, func() -> void: fizzles[0] += _named(w2.events, "fx:fizzle").size())
	if t2 < 0:
		return "牆後的弓手 20 秒內沒射中玩家（停在 %s）" % a.pos
	if fizzles[0] > 0:
		return "弓手射中前有 %d 支箭撞牆或落空" % fizzles[0]
	_note("弓手射中 1.0 石台上的玩家：開闊 %.1f 秒、隔著牆 %.1f 秒（繞到 %s）" % [t * DT, t2 * DT, a.pos])
	return ""


# 遠的小怪降低重新判斷路線的頻率（效能）：離目標超過 far_distance 時至少間隔 repath_interval_far 秒，
# 走進 far_distance 的那一步立刻重新判斷，弓手進射程後照常瞄準（不沿用遠處「看不到」的判斷）
static func check_far_repath() -> String:
	var w := _new_world()
	var p := _player(w)
	p.pos = Vector2(-13, -13)
	var a := _spawn(w, &"archer", Vector2(13, 13)) as RangedEnemy
	var n: Dictionary = Config.NAV
	var far_gap := INF        # 遠處兩次重新判斷之間最短的間隔（步）
	var last_far := -1
	var entered := -1         # 走進 far_distance 的那一步
	var refreshed_on_enter := false
	var in_range := -1        # 走進射擊距離的那一步
	var aimed := -1
	for i in 30 * 60:
		p.hp = p.max_hp
		var before := a._nav_timer
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		var refreshed := absf(a._nav_timer - (before - DT)) > EPS   # 計時器不是只扣一步 = 這一步重新判斷
		var dist := a.pos.distance_to(p.pos)
		if refreshed and a._nav_far:
			if last_far >= 0:
				far_gap = minf(far_gap, i - last_far)
			last_far = i
		if entered < 0 and last_far >= 0 and not a._nav_far:
			entered = i
			refreshed_on_enter = refreshed
		if in_range < 0 and dist <= a.def.preferred_range[1] + a.def.fire_reach:
			in_range = i
		if a.fsm.current_name == &"aim":
			aimed = i
			break
	if entered < 0:
		return "弓手 30 秒內沒走進 far_distance（停在 %s）" % a.pos
	if far_gap < roundi(n.repath_interval_far / DT):
		return "遠處重新判斷的間隔應至少 %.2f 秒，最短 %d 步" % [n.repath_interval_far, far_gap]
	if not refreshed_on_enter:
		return "弓手走進 far_distance 的那一步應立刻重新判斷路線"
	if aimed < 0:
		return "弓手走進射擊距離後沒有瞄準（停在 %s）" % a.pos
	_note("遠的弓手：遠處重新判斷間隔最短 %.2f 秒，第 %.2f 秒走進 %.0f 並立刻重新判斷，第 %.2f 秒進射程、%.2f 秒開始瞄準" % [
		far_gap * DT, entered * DT, n.far_distance, in_range * DT, aimed * DT])
	return ""


static func check_nav_clearance() -> String:
	var w := _new_world()
	# 2.5 的牆 x 8~14、z 7.5~8.5：貼著北緣 0.5 的直線算擋住，0.7 的不算
	if w.nav.has_los(Vector2(5, 7.0), Vector2(17, 7.0)):
		return "離牆 0.5 的直線不應算看得到"
	if not w.nav.has_los(Vector2(5, 6.8), Vector2(17, 6.8)):
		return "離牆 0.7 的直線應算看得到"
	# 貼在牆邊往外走不算擋住
	if not w.nav.has_los(Vector2(11, 7.05), Vector2(11, 3.0)):
		return "貼牆往外走應算看得到"
	var w2 := _new_world(12345, false, &"graveyard_a")
	var p := _player(w2)
	p.pos = MapDefs.to_world(w2.map, w2.map.dig)
	var g := _spawn(w2, &"grunt", Vector2(0, 22))
	var slowed := 0
	for i in 90 * 60:
		p.hp = p.max_hp
		var before := g.pos
		w2.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		var want := g.velocity.length() * DT
		if want > 0.0 and g.pos.distance_to(before) < want * 0.95:
			slowed += 1
		if g.pos.distance_to(p.pos) < 1.6:
			break
	if slowed >= 30:
		return "繞到門口時被牆擋住變慢 %d 步（應 < 30）" % slowed
	_note("繞到門口被牆擋住變慢 %d 步（v0.22.0 為 154 步）" % slowed)
	return ""


# D6 起地圖 A 沒有波次，小怪由挖墳事件生（怪潮同樣用 Spawner._around_player 的距離）；Boss、挖墳點噴出來的不算
static func check_map_spawns() -> String:
	var w := _new_world(12345, true, &"graveyard_a")
	var p := _player(w)
	var s: Dictionary = Config.SPAWNER
	var seen := {}
	var count := 0
	w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)   # 第一步放 Boss
	(w.entities.get(w.boss_id) as Enemy).die()   # Boss 巡邏到玩家附近會打人，這裡只看生怪位置
	w.event._start(w)
	for e: Entity in w.enemies:
		seen[e.id] = true
	for i in 60 * 60:
		p.hp = p.max_hp
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		for e: Entity in w.enemies:
			# Boss、Boss 召喚的、召喚詞條叫出來的（生在召喚者旁邊）、挖墳點噴出來的（出生就在 launch）不算
			if seen.has(e.id) or not (e is Enemy and (e as Enemy).wave_member and (e as Enemy).summoner_id == 0):
				continue
			if (e as Enemy).is_launching():
				seen[e.id] = true
				continue
			seen[e.id] = true
			var dist := e.pos.distance_to(p.pos)
			if dist < s.min_distance_from_player - EPS or dist > s.max_distance_from_player + EPS:
				return "第 %d 隻生在離玩家 %.1f 的地方" % [count + 1, dist]
			if not w.nav.is_walkable(e.pos) or not w.nav.same_region(e.pos, p.pos):
				return "第 %d 隻生在 %s：不可走或走不到玩家" % [count + 1, e.pos]
			count += 1
	if count < 5:
		return "60 秒只生了 %d 隻" % count
	return ""


# ───────── 小關隨機地圖（MapGen，docs/系統說明.md §35）─────────

const STAGE_SEEDS := 4   # 每種小關掃幾個種子（1-5 另外在 check_map_a 跟著第 1 層掃 LAYOUT_SEEDS 個）


# 第 stage 小關、這個種子的地圖（不放玩家）：怪群照產生的位置生
static func _stage_world(stage: int, seed_value: int) -> World:
	var w := World.new(&"test_arena")
	_worlds.append(w)
	w.run_seed = seed_value
	w.floor_num = 1
	w.stage_num = stage
	w.load_map(&"graveyard")
	return w


# 每種小關 × STAGE_SEEDS 個種子：產生成功、地圖規則都過；出口的門 / 挖墳點 / 鐵砧 / 寶箱 / 怪群都走得到出生點；
# 寶箱放在平的地方；兩扇門的獎勵不重複；相鄰兩塊主題不重複；王族墓的關有 Boss 巡邏範圍、沒有門，其他關有 STAGES 的門數、沒有挖墳事件
static func check_stage_maps() -> String:
	var lines: Array[String] = []
	for stage: int in MapGenDefs.STAGES:
		var cfg: Dictionary = MapGenDefs.STAGES[stage]
		var routes: Array[float] = []
		var block_counts: Array[int] = []
		for s in STAGE_SEEDS:
			var seed_value := 101 + s
			var w := _stage_world(stage, seed_value)
			var tag := "第 %d 小關種子 %d" % [stage, seed_value]
			if int(w.map.get("stage", 0)) != stage:
				return "%s：產生失敗（改用了 %s）" % [tag, w.map.get("name", "")]
			var err := _map_rules(w, false)
			if err != "":
				return "%s：%s" % [tag, err]
			err = _stage_reach(w, cfg)
			if err != "":
				return "%s：%s" % [tag, err]
			err = _stage_themes(w.map.regions)
			if err != "":
				return "%s：%s" % [tag, err]
			var goal: Vector2 = MapDefs.to_world(w.map, w.map.dig)
			var path := w.nav.find_path(w.spawn_point, goal)
			var length := 0.0
			for i in range(1, path.size()):
				length += path[i - 1].distance_to(path[i])
			routes.append(length)
			block_counts.append(w.terrain.blocks.size())
		lines.append("1-%d 最短路線 %.0f ~ %.0f、石台 %d ~ %d" % [stage, routes.min(), routes.max(), block_counts.min(), block_counts.max()])
	_note("小關地圖：%d 種 × %d 個種子都過；%s" % [MapGenDefs.STAGES.size(), STAGE_SEEDS, "；".join(PackedStringArray(lines))])
	return ""


# 相鄰兩塊主題不重複：主線比主主題；支線跟它接著的那塊的主、副主題都不重複（王族墓固定，不比）
static func _stage_themes(regions: Array) -> String:
	for reg: Dictionary in regions:
		if reg.from < 0 or reg.role == &"boss":
			continue
		var beside: Array = regions[reg.from].themes
		var same: bool = reg.themes.any(func(t: StringName) -> bool: return beside.has(t)) if reg.role == &"branch" else beside[0] == reg.themes[0]
		if same:
			return "%s %s 接在 %s 旁邊，主題重複" % [reg.role, reg.themes, beside]
	return ""


static func _stage_reach(w: World, cfg: Dictionary) -> String:
	var spawn := w.spawn_point
	var nav := w.nav
	var at := func(p: Vector2) -> Vector2: return MapDefs.to_world(w.map, p)
	var reachable := func(p: Vector2) -> bool: return nav.is_walkable(p) and nav.same_region(p, spawn)
	var doors: Array = w.map.stage_doors
	if cfg.get("boss", false):
		if not doors.is_empty() or not w.map.dig_event or (w.map.boss_room as Array).size() != 4:
			return "王族墓的關應有挖墳事件、Boss 範圍、沒有門（門 %d、挖墳 %s）" % [doors.size(), w.map.dig_event]
		if not reachable.call(at.call(w.map.dig)):
			return "挖墳點走不到"
	else:
		if doors.size() != int(cfg.doors) or w.map.dig_event:
			return "應有 %d 扇門、沒有挖墳事件（%d 扇、挖墳 %s）" % [cfg.doors, doors.size(), w.map.dig_event]
		var rewards := {}
		for d: Dictionary in doors:
			if not reachable.call(at.call(d.reach)):
				return "門前 %s 走不到" % d.reach
			rewards[d.reward] = true
		if doors.size() == 2 and rewards.size() != 2:
			return "兩扇門的獎勵應不同：%s" % rewards.keys()
		# 畫面：每扇門一座拱門（兩根柱子、橫樑、門洞）
		var list := []
		for d: Dictionary in doors:
			list.append({"pos": at.call(d.at), "side": d.side})
		var gates := ArenaView.create_doors(list)
		var parts := gates.get_child(0).get_child_count() if gates.get_child_count() > 0 else 0
		var count := gates.get_child_count()
		gates.free()
		if count != doors.size() or parts != 4:
			return "每扇門應畫一座拱門（%d 扇、畫了 %d 座、每座 %d 個零件）" % [doors.size(), count, parts]
	if cfg.get("anvil", false) != w.map.has("anvil"):
		return "鐵砧應%s出現" % ("" if cfg.get("anvil", false) else "不")
	if w.map.has("anvil") and not reachable.call(at.call(w.map.anvil)):
		return "鐵砧走不到"
	for spot: Array in w.map.chest_spots:
		var p: Vector2 = at.call(Vector2(spot[0], spot[1]))
		if not reachable.call(p):
			return "寶箱 %s 走不到" % p
		var g := w.terrain.ground_at(p)
		var r: float = LootDefs.CHESTS[spot[2]].radius
		for k in 8:
			if absf(w.terrain.ground_at(p + Vector2.from_angle(k * TAU / 8.0) * r) - g) > Config.HEIGHT.step:
				return "寶箱 %s 擺在台階邊緣" % p
	w.spawner.spawn_packs(w, w.floor_rng(&"packs"))
	if w.packs.size() != (w.map.pack_spots as Array).size() or w.packs.is_empty():
		return "怪群應照 %d 個位置生，實際 %d 群" % [(w.map.pack_spots as Array).size(), w.packs.size()]
	for e in w.enemies:
		if not reachable.call(e.pos):
			return "怪群成員放在走不到的地方 %s" % e.pos
	return ""


# 同一個種子、同一關產生的地圖每次都一樣（客戶端照種子自己算）；換種子、換小關就不一樣
static func check_stage_map_seed() -> String:
	var key := func(w: World) -> Array:
		return [w.map.size, w.map.spawn, w.map.blocks, w.map.stage_doors, w.map.chest_spots, w.map.pack_spots, w.map.get("anvil")]
	var a: Array = key.call(_stage_world(3, 55))
	var b: Array = key.call(_stage_world(3, 55))
	if a != b:
		return "同一個種子、同一關兩次產生的地圖不同"
	if a == key.call(_stage_world(3, 56)) or a == key.call(_stage_world(4, 55)):
		return "換種子或換小關，地圖應不同"
	return ""


# 產生器要讓每個平台算得一樣：原始碼（去掉註解）不能用三角函數、開根號、randf、Vector2 的長度 / 距離 / 角度
const MAP_GEN_FORBIDDEN: Array[String] = ["sin(", "cos(", "tan(", "atan", "sqrt(", "pow(", "exp(", "log(", "randf", ".length(", "length_squared(",
	"distance_to(", "distance_squared_to(", "angle", "normalized(", "from_angle("]


static func check_map_gen_source() -> String:
	var text := FileAccess.get_file_as_string("res://sim/map_gen.gd")
	if text.is_empty():
		return "讀不到 sim/map_gen.gd"
	var n := 0
	for line in text.split("\n"):
		n += 1
		var code := line.split("#")[0]
		for word in MAP_GEN_FORBIDDEN:
			if code.contains(word):
				return "sim/map_gen.gd 第 %d 行用了 %s（客戶端照種子算地圖，不同平台會算出不同結果）" % [n, word]
	return ""
