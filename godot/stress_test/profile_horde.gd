# 成群怪物的模擬層耗時（D5）：地圖 A、玩家在出生點、周圍 N 隻醒著的小怪，量 World.step 各段平均耗時（毫秒 / 步）
# 用法（在 godot/ 內，headless）：<Godot> --headless --path . -s res://stress_test/profile_horde.gd -- --horde=200
extends SceneTree

const DT := 1.0 / 60.0
const WARMUP := 120
const STEPS := 300


func _initialize() -> void:
	var n := 200
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--horde="):
			n = arg.get_slice("=", 1).to_int()
	var w := World.new(&"graveyard_a")
	w.spawn_packs = false
	w.reset(1)
	w.spawner.finished = true
	var p: Player = w.players[World.HOST_PEER_ID]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in n:
		var type := &"archer" if rng.randf() < 0.2 else &"grunt"
		var a := rng.randf() * TAU
		w.spawner.spawn_at(w, type, w.nav.nearest_walkable(p.pos + Vector2(sin(a), cos(a)) * rng.randf_range(4.0, 16.0)))
	var cmd := InputCmd.new()
	for i in WARMUP:
		p.hp = p.max_hp
		w.step({World.HOST_PEER_ID: cmd}, DT)

	var total := 0
	for i in STEPS:
		p.hp = p.max_hp
		var t0 := Time.get_ticks_usec()
		w.step({World.HOST_PEER_ID: cmd}, DT)
		total += Time.get_ticks_usec() - t0
	print("horde=%d alive=%d step_ms=%.3f" % [n, w.enemies.size(), total / 1000.0 / STEPS])

	# 照 World.step 的順序手動跑，逐段計時（模擬層不能讀時間，只能在這裡量）
	var parts := {"players": 0, "enemies": 0, "projectiles": 0, "integrate": 0, "separate": 0, "terrain": 0, "rest": 0}
	for i in STEPS:
		p.hp = p.max_hp
		w.events.clear()
		w.hitboxes.clear()
		w.tick += 1
		for e: Entity in w.entities.values():
			e.prev_pos = e.pos
			e.prev_facing = e.facing
			e.prev_height = e.height
		w.cooldowns.tick(DT)
		var t := Time.get_ticks_usec()
		p.apply_cmd(cmd)
		p.update(DT)
		t = _lap(parts, "players", t)
		w._update_packs()
		for e in w.enemies:
			e.update(DT)
		t = _lap(parts, "enemies", t)
		for e in w.projectiles:
			e.update(DT)
		t = _lap(parts, "projectiles", t)
		var bs: Array[Entity] = [p]
		bs.append_array(w.enemies)
		for b in bs:
			b.integrate(DT)
		t = _lap(parts, "integrate", t)
		SimPhysics.separate(bs, w.rng)
		t = _lap(parts, "separate", t)
		for b in bs:
			w.terrain.push_out(b)
			SimPhysics.clamp_to_arena(b, w.half_extents)
			b.integrate_vertical(DT, w.terrain)
		t = _lap(parts, "terrain", t)
		w._update_downed(DT)
		w.spawner.update(w, DT)
		w._remove_dead_entities()
		t = _lap(parts, "rest", t)
	var pl := ""
	for k: String in parts:
		pl += " %s=%.3f" % [k, parts[k] / 1000.0 / STEPS]
	print("step_parts_ms:" + pl)

	# 各段分開量（同一個狀態重複做 STEPS 次）
	var bodies: Array[Entity] = []
	bodies.append(p)
	bodies.append_array(w.enemies)
	var seg := {}
	seg["enemy_update"] = _time(func() -> void:
		for e in w.enemies:
			e.update(DT))
	seg["integrate"] = _time(func() -> void:
		for b in bodies:
			b.integrate(DT))
	seg["separate"] = _time(func() -> void: SimPhysics.separate(bodies, w.rng))
	seg["push_out"] = _time(func() -> void:
		for b in bodies:
			w.terrain.push_out(b))
	seg["clamp"] = _time(func() -> void:
		for b in bodies:
			SimPhysics.clamp_to_arena(b, w.half_extents))
	seg["vertical"] = _time(func() -> void:
		for b in bodies:
			b.integrate_vertical(DT, w.terrain))
	seg["nearest_player"] = _time(func() -> void:
		for e in w.enemies:
			(e as Enemy).nearest_player())
	seg["has_los"] = _time(func() -> void:
		for e in w.enemies:
			w.nav.has_los(e.pos, p.pos))
	seg["find_path"] = _time(func() -> void:
		for e in w.enemies:
			w.nav.find_path(e.pos, p.pos))
	seg["remove_dead"] = _time(func() -> void: w._remove_dead_entities())
	seg["fsm"] = _time(func() -> void:
		for e in w.enemies:
			(e as Enemy).fsm.update(DT))
	seg["jump"] = _time(func() -> void:
		for e in w.enemies:
			(e as Enemy)._update_jump(DT))
	seg["anim"] = _time(func() -> void:
		for e in w.enemies:
			(e as Enemy)._update_anim())
	seg["cd_key"] = _time(func() -> void:
		for e in w.enemies:
			w.cooldowns.is_ready((e as Enemy).cd("swing")))
	seg["stats_value"] = _time(func() -> void:
		for e in w.enemies:
			e.stats.value(&"hp_regen"))
	var line := ""
	for k: String in seg:
		line += " %s=%.3f" % [k, seg[k]]
	print("segments_ms_per_call:" + line)
	print("  (has_los / find_path 是每隻都做一次的耗時；實際每 0.25 秒才重新判斷一次 = 每步約 1/15 隻)")
	w.clear()
	quit(0)


func _lap(parts: Dictionary, key: String, t: int) -> int:
	var now := Time.get_ticks_usec()
	parts[key] += now - t
	return now


func _time(fn: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	for i in 20:
		fn.call()
	return (Time.get_ticks_usec() - t0) / 1000.0 / 20
