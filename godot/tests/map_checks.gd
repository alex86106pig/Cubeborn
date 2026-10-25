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


static func check_map_a() -> String:
	var w := _new_world(12345, false, &"graveyard_a")
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
	if _player(w).pos != spawn:
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
	var mi := ArenaView.create_blocks(w.terrain.blocks)
	var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	mi.free()
	if verts.size() != w.terrain.blocks.size() * 30:
		return "石台網格應有 %d 個頂點（每個石台 5 面），實際 %d" % [w.terrain.blocks.size() * 30, verts.size()]
	for i in range(0, verts.size(), 3):
		if (verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i]).dot(normals[i]) >= 0.0:
			return "石台網格第 %d 個三角形是背面" % (i / 3)
	print("    地圖 A：可走格 %d / %d、牆 %d、墓碑 %d、高台 %d" % [walkable, nav.size.x * nav.size.y, counts.get(MapDefs.WALL, 0), counts.get(MapDefs.TOMB, 0), counts.get(MapDefs.PLATFORM, 0)])
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
	var g := _spawn(w, &"grunt", Vector2(0, 22))   # 圍牆南邊外面
	var north := [INF]
	var t := _run_until_hurt(w, 90 * 60, func() -> void: north[0] = minf(north[0], g.pos.y))
	if t < 0:
		return "骷髏戰士 90 秒內沒打到玩家（停在 %s）" % g.pos
	if north[0] > -15.0:
		return "骷髏戰士應繞到北門（z < -15）進來，最北只到 z %.1f" % north[0]
	var w2 := _new_world(12345, false, &"graveyard_a")
	var p2 := _player(w2)
	p2.pos = p.pos
	var a := _spawn(w2, &"archer", Vector2(0, 22))
	var t2 := _run_until_hurt(w2, 90 * 60)
	if t2 < 0:
		return "弓手 90 秒內沒射中玩家（停在 %s）" % a.pos
	print("    繞北門：骷髏戰士 %.1f 秒打到玩家（最北 z %.1f）、弓手 %.1f 秒射中" % [t * DT, north[0], t2 * DT])
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
	print("    骷髏戰士：第 %.2f 秒上 0.5、%.2f 秒上 1.0、%.2f 秒打到玩家（起跳前蹲 %d 步）；Boss %.1f 秒上 1.0" % [heights.half * DT, heights.top * DT, t * DT, heights.windup, top * DT])
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
	print("    弓手射中 1.0 石台上的玩家：開闊 %.1f 秒、隔著牆 %.1f 秒（繞到 %s）" % [t * DT, t2 * DT, a.pos])
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
		return "繞北門時被牆擋住變慢 %d 步（應 < 30）" % slowed
	print("    繞北門被牆擋住變慢 %d 步（v0.22.0 為 154 步）" % slowed)
	return ""


# D6 起地圖 A 沒有波次，小怪由挖墳事件生（同樣用 Spawner._around_player 的距離）；Boss 在挖墳點旁邊，不算
static func check_map_spawns() -> String:
	var w := _new_world(12345, true, &"graveyard_a")
	var p := _player(w)
	var s: Dictionary = Config.SPAWNER
	var seen := {}
	var count := 0
	w.event._start(w)
	(w.entities.get(w.boss_id) as Enemy).die()   # 怪潮在 Boss 倒下後才開始（v0.38.0）
	for e: Entity in w.enemies:
		seen[e.id] = true
	for i in 60 * 60:
		p.hp = p.max_hp
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		for e: Entity in w.enemies:
			# Boss、Boss 召喚的、召喚詞條叫出來的（生在召喚者旁邊）不算
			if seen.has(e.id) or not (e is Enemy and (e as Enemy).wave_member and (e as Enemy).summoner_id == 0):
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
