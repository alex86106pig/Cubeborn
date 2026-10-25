# Boss 招式：砸地、衝鋒、召喚與狂暴、直劈、狂暴招式、高台
# 由 tests/check.gd 呼叫；每個 check_* 回傳 "" = 通過，否則是失敗原因
class_name BossChecks
extends CheckKit

# v0.27.0：砸地的紅圈一圈圈往外擴散（3 / 6 / 9，每圈隔 0.25 秒），打到擊飛 + 移速減半 2 秒
static func check_boss_slam() -> String:
	var s: Dictionary = EnemyDefs.ENEMIES.boss.slam
	var w := _new_world(3)
	var p := _player(w)
	var b := _spawn(w, &"boss", Vector2(0, 2.5))
	if w.boss_id != b.id:
		return "world.boss_id 沒有記錄 Boss"
	w.cooldowns.start(b.cd("cleave"), 99.0)   # 只測砸地
	var events: Array[Dictionary] = []
	if _run_until(w, _cmd(Vector2.ZERO), 60 * 4, events, func() -> bool: return b.fsm.is_in(&"slam")) < 0:
		return "4 秒內沒有砸地（狀態 %s）" % b.fsm.current_name
	var start_tick := w.tick
	if _run_until(w, _cmd(Vector2.ZERO), 120, events, func() -> bool: return not _damage_amounts(w.events, p.id).is_empty()) < 0 \
			or _damage_amounts(w.events, p.id) != [float(s.damage)]:
		return "砸地傷害 %s，預期 [%.1f]" % [_damage_amounts(events, p.id), s.damage]
	var windup := (w.tick - start_tick) * DT
	if absf(windup - s.windup) > DT * 1.5:
		return "前搖 %.3f 秒，預期 %.2f" % [windup, s.windup]
	if p.vz <= 0.0 or absf(p.stats.value(&"move_speed") - Config.PLAYER.move_speed * s.slow_mul) > EPS:
		return "被砸到應擊飛並緩速：vz %.2f、移速 %.2f" % [p.vz, p.stats.value(&"move_speed")]
	var cd := w.cooldowns.remaining(b.cd("slam"))
	if absf(cd - (s.cooldown - windup)) > DT * 2:
		return "砸地 CD 剩 %.3f，預期約 %.3f" % [cd, s.cooldown - windup]
	var bd: Dictionary = EnemyDefs.ENEMIES.boss
	var want_kb: float = 100.0 * bd.knockback_mul / bd.mass
	b.take_damage(10.0, Vector2(0, 1), 100.0, p.id)
	if b.fsm.is_in(&"hurt") or absf(b.knockback.length() - want_kb) > EPS:
		return "Boss 不應硬直，擊退應為 100 × %.2f / 質量 %.0f = %.3f，實際 %.3f" % [bd.knockback_mul, bd.mass, want_kb, b.knockback.length()]
	# 外圈：站在 7.5 的玩家在第 3 圈（0.5 秒後）才被打到；站在 1 的玩家只被第 1 圈打一次
	var w2 := World.new(&"test_arena")
	w2.reset(9, [1, 2])
	w2.spawner.finished = true
	_worlds.append(w2)
	var near: Player = w2.players[1]
	var far: Player = w2.players[2]
	near.pos = Vector2(1, 0)
	far.pos = Vector2(7.5, 0)
	var b2: Boss = _spawn(w2, &"boss", Vector2.ZERO)
	_run(w2, _cmd(Vector2.ZERO), roundi(EnemyDefs.ENEMIES.boss.spawn_time / DT) + 2)
	b2.fsm.change(&"slam", {"target": Vector2.INF})
	var times := {}
	for i in 120:
		near.hp = near.max_hp
		far.hp = far.max_hp
		w2.step({1: _cmd(Vector2.ZERO), 2: _cmd(Vector2.ZERO)}, DT)
		for e in _named(w2.events, "entity:damaged"):
			times[e.target_id] = times.get(e.target_id, []) + [i + 1]
	var t_near: Array = times.get(near.id, [])
	var t_far: Array = times.get(far.id, [])
	if t_near.size() != 1 or t_far.size() != 1:
		return "每人應只被打一次：近 %s、遠 %s" % [t_near, t_far]
	var gap: float = (t_far[0] - t_near[0]) * DT
	if absf(gap - 2.0 * s.ring_delay) > DT * 1.5:
		return "第 3 圈應比第 1 圈晚 %.2f 秒，實際 %.3f" % [2.0 * s.ring_delay, gap]
	return ""


static func check_boss_charge() -> String:
	var w := _new_world(5)
	var p := _player(w)
	p.pos = Vector2(0, 11)
	var b := _spawn(w, &"boss", Vector2(0, 2))
	var events: Array[Dictionary] = []
	if _run_until(w, _cmd(Vector2.ZERO), 60 * 5, events, func() -> bool: return b.fsm.is_in(&"charge")) < 0:
		return "5 秒內沒有衝鋒（狀態 %s）" % b.fsm.current_name
	var c: Dictionary = EnemyDefs.ENEMIES.boss.charge
	var windup_steps := _run_until(w, _cmd(Vector2.ZERO), 120, events, func() -> bool: return b.fsm.data.phase == &"dash")
	if absf(windup_steps * DT - c.windup) > DT * 1.5:
		return "蓄力 %.3f 秒，預期 %.2f" % [windup_steps * DT, c.windup]
	_run_collect(w, _cmd(Vector2.ZERO), 1, events)
	if absf(b.velocity.length() - c.speed) > EPS:
		return "衝刺速度 %.3f，預期 %.1f" % [b.velocity.length(), c.speed]
	# 命中後把玩家移出路線，否則玩家被擊退到牆邊會擋住 Boss，測不到撞牆
	if _run_until(w, _cmd(Vector2.ZERO), 60, events, func() -> bool: return not _damage_amounts(w.events, p.id).is_empty()) < 0:
		return "衝刺沒有撞到玩家"
	if absf(p.stun_timer - c.stun) > DT * 1.5 or not p.anim.get("stunned", false) and p.stun_timer <= 0.0:
		return "被衝鋒撞到應暈眩 %.1f 秒，實際 %.3f" % [c.stun, p.stun_timer]
	p.pos = Vector2(-12, -12)
	if _run_until(w, _cmd(Vector2.ZERO), 120, events, func() -> bool: return b.fsm.data.get("phase") == &"stunned") < 0:
		return "沒有撞牆暈眩（階段 %s）" % b.fsm.data.get("phase")
	if not _damage_amounts(events, p.id).has(float(c.damage)):
		return "衝鋒命中傷害 %s，應含 %.1f" % [_damage_amounts(events, p.id), c.damage]
	if _named(events, "sfx:cue").filter(func(e: Dictionary) -> bool: return e.cue == "bossWallHit").is_empty():
		return "撞牆應發出 bossWallHit"
	var stun := _run_until(w, _cmd(Vector2.ZERO), 200, events, func() -> bool: return not b.fsm.is_in(&"charge"))
	if absf(stun * DT - c.wall_stun) > DT * 1.5:
		return "暈眩 %.3f 秒，預期 %.2f" % [stun * DT, c.wall_stun]
	return ""


static func check_boss_summon_enrage() -> String:
	var w := _new_world(8)
	var p := _player(w)
	var b: Boss = _spawn(w, &"boss", Vector2(0, -10))
	var su: Dictionary = EnemyDefs.ENEMIES.boss.summon
	var en: Dictionary = EnemyDefs.ENEMIES.boss.enrage
	b.hp = b.max_hp * (su.hp_threshold + en.hp_threshold) / 2.0   # 低於召喚門檻、高於狂暴門檻
	var events: Array[Dictionary] = []
	if _run_until(w, _cmd(Vector2.ZERO), 60 * 4, events, func() -> bool: return b.fsm.is_in(&"summon")) < 0:
		return "血量 %.0f/%.0f 時 4 秒內沒有召喚（狀態 %s）" % [b.hp, b.max_hp, b.fsm.current_name]
	_run_collect(w, _cmd(Vector2.ZERO), ceili(su.windup / DT) + 1, events)
	var minions := w.enemies.filter(func(e: Entity) -> bool: return e.kind == &"grunt" or e.kind == &"archer")
	if minions.size() != su.count:
		return "召喚 %d 隻，預期 %d" % [minions.size(), su.count]
	for m in minions:
		if absf(m.pos.distance_to(b.pos) - su.distance) > 0.3:
			return "召喚的小怪離 Boss %.2f，預期 %.1f" % [m.pos.distance_to(b.pos), su.distance]
	# 召喚的種類是隨機的：多召喚幾次，骷髏戰士與弓手都要出現
	var kinds := {}
	for i in 10:
		b.summon_minions()
	for e: Entity in w.enemies:
		kinds[e.kind] = true
	if not kinds.has(&"grunt") or not kinds.has(&"archer"):
		return "召喚應隨機出現骷髏戰士與弓手，實際 %s" % kinds.keys()
	for e: Entity in w.enemies.duplicate():
		if e != b and not minions.has(e):
			e.remove()
	w._remove_dead_entities()
	Combat.apply_damage(w, p, b, {"damage": b.hp - b.max_hp * en.hp_threshold + 10.0})
	if not b.is_enraged or _named(w.events, "boss:enraged").is_empty():
		return "血量 %.0f/%.0f 應進入狂暴" % [b.hp, b.max_hp]
	for k: String in ["speed_mul", "cooldown_mul", "windup_mul"]:
		if absf(b.enrage_mul(k) - en[k]) > EPS:
			return "狂暴後 %s = %.2f，預期 %.2f" % [k, b.enrage_mul(k), en[k]]
	for m in minions:
		m.die()
	if _run_until(w, _cmd(Vector2.ZERO), 60 * 3, events, func() -> bool: return b.fsm.is_in(&"chase") and b.velocity != Vector2.ZERO) < 0:
		return "狂暴後沒有回到追擊"
	var enraged_speed: float = EnemyDefs.ENEMIES.boss.move_speed * en.speed_mul
	if absf(b.velocity.length() - enraged_speed) > EPS:
		return "狂暴移速 %.3f，預期 %.3f" % [b.velocity.length(), enraged_speed]
	return ""


# v0.27.0 新招直劈：沒有地面預警事件；舉劍 0.6 秒後劈下；前半段只用一半轉速跟著玩家 → 繞圈就躲得開
static func check_boss_cleave() -> String:
	var c: Dictionary = EnemyDefs.ENEMIES.boss.cleave
	for case in [["站著不動", false], ["繞圈走位", true]]:
		var w := _new_world(4)
		var p := _player(w)
		p.pos = Vector2(0, 3)
		var b: Boss = _spawn(w, &"boss", Vector2.ZERO)
		_run(w, _cmd(Vector2.ZERO), roundi(EnemyDefs.ENEMIES.boss.spawn_time / DT) + 2)
		b.facing = 0.0
		b.fsm.change(&"cleave")
		var events: Array[Dictionary] = []
		var hit_at := -1
		for i in roundi((c.windup + c.active + 0.1) / DT):
			var move := Vector2.ZERO
			if case[1]:
				move = Vector2(1, 0).rotated(-float(i) * 0.03)   # 繞著 Boss 往側面跑
			p.hp = p.max_hp
			_run_collect(w, _cmd(move), 1, events)
			if p.hp < p.max_hp and hit_at < 0:
				hit_at = i + 1
		if not _named(events, "fx:telegraph").is_empty():
			return "直劈不應有地面預警"
		if case[1] and hit_at >= 0:
			return "繞圈走位應躲得開直劈（第 %d 步被打到，玩家在 %s）" % [hit_at, p.pos]
		if not case[1] and absf(hit_at * DT - c.windup) > DT * 2.5:
			return "站著不動應在舉劍 %.2f 秒後被劈到，實際 %.3f" % [c.windup, hit_at * DT]
	return ""


# v0.27.0 狂暴：衝鋒連 3 次；召喚的骷髏戰士衝撞一次；砸地不管多遠都放（玩家腳下預警 → 瞬移 → 砸）
static func check_boss_enraged_moves() -> String:
	var en: Dictionary = EnemyDefs.ENEMIES.boss.enrage
	var w := _new_world(6)
	var p := _player(w)
	p.pos = Vector2(0, 12)
	var b: Boss = _spawn(w, &"boss", Vector2(0, -12))
	_run(w, _cmd(Vector2.ZERO), roundi(EnemyDefs.ENEMIES.boss.spawn_time / DT) + 2)
	b.is_enraged = true
	b.fsm.change(&"charge")
	var dashes := 0
	var prev := &""
	for i in 60 * 6:
		p.hp = p.max_hp
		p.pos = Vector2(0, 12) if i % 120 < 60 else Vector2(0, -12)
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		if not b.fsm.is_in(&"charge"):
			break
		var ph: StringName = b.fsm.data.phase
		if ph == &"dash" and prev != &"dash":
			dashes += 1
		prev = ph
	if dashes != en.charge_count:
		return "狂暴衝鋒應連衝 %d 次，實際 %d" % [en.charge_count, dashes]
	# 召喚的骷髏戰士爬出來後衝撞一次
	var w2 := _new_world(7)
	var p2 := _player(w2)
	var b2: Boss = _spawn(w2, &"boss", Vector2(0, -8))
	b2.is_enraged = true
	b2.summon_minions()
	var rushed := {}
	for i in 60 * 3:
		p2.hp = p2.max_hp
		w2.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		for e: Entity in w2.enemies:
			if e is MeleeEnemy and (e as MeleeEnemy).fsm.is_in(&"rush"):
				rushed[e.id] = true
	var grunts := w2.enemies.filter(func(e: Entity) -> bool: return e is MeleeEnemy)
	if grunts.is_empty() or rushed.size() != grunts.size():
		return "狂暴召喚的骷髏戰士都應衝撞一次：%d 隻裡 %d 隻衝了" % [grunts.size(), rushed.size()]
	# 瞬移砸地：玩家在 20 單位外也會放；先在玩家腳下預警 teleport_warn 秒，瞬移後 teleport_windup 秒砸下
	var w3 := _new_world(8)
	var p3 := _player(w3)
	p3.pos = Vector2(0, 12)
	var b3: Boss = _spawn(w3, &"boss", Vector2(0, -8))
	_run(w3, _cmd(Vector2.ZERO), roundi(EnemyDefs.ENEMIES.boss.spawn_time / DT) + 2)
	b3.is_enraged = true
	w3.cooldowns.start(b3.cd("charge"), 99.0)
	w3.cooldowns.start(b3.cd("summon"), 99.0)
	w3.cooldowns.reset(b3.cd("slam"))
	var events: Array[Dictionary] = []
	if _run_until(w3, _cmd(Vector2.ZERO), 60, events, func() -> bool: return b3.fsm.is_in(&"slam")) < 0:
		return "狂暴時離玩家 20 單位也應砸地"
	var warn := _named(events, "fx:telegraph")
	if warn.is_empty() or (warn.back().pos as Vector2).distance_to(p3.pos) > 1.0:
		return "瞬移前應在玩家腳下預警"
	var start := w3.tick
	if _run_until(w3, _cmd(Vector2.ZERO), 120, events, func() -> bool: return b3.pos.distance_to(p3.pos) < 3.0) < 0:
		return "Boss 應瞬移到玩家旁邊"
	if absf((w3.tick - start) * DT - en.teleport_warn) > DT * 2:
		return "預警 %.3f 秒後才瞬移，預期 %.2f" % [(w3.tick - start) * DT, en.teleport_warn]
	var tp := w3.tick
	if _run_until(w3, _cmd(Vector2.ZERO), 120, events, func() -> bool: return b3.fsm.data.get("phase") == &"impact") < 0 \
			or absf((w3.tick - tp) * DT - en.teleport_windup) > DT * 2:
		return "瞬移後應 %.2f 秒砸下，實際 %.3f" % [en.teleport_windup, (w3.tick - tp) * DT]
	return ""


static func check_boss_high_ground() -> String:
	# 地圖 A：玩家站在西北角 1.0 石座上，Boss 從地面跳上去（v0.22.0 會在下面一直砸地）
	var w := _new_world(12345, false, &"graveyard_a")
	var p := _player(w)
	p.pos = MapDefs.to_world(w.map, Vector2(38.5, 39.5))
	p.height = 1.0
	var b := _spawn(w, &"boss", MapDefs.to_world(w.map, w.map.dig))
	var up := -1
	var hit := -1
	for i in 30 * 60:
		var before := p.max_hp
		p.hp = before
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		if up < 0 and b.is_grounded() and absf(b.height - 1.0) < EPS:
			up = i + 1
		if hit < 0 and p.hp < before:
			hit = i + 1
		if up > 0 and hit > 0:
			break
	if up < 0 or hit < 0:
		return "Boss 30 秒內應跳上石座並打到玩家：上去第 %d 步、打到第 %d 步（停在 %s 高 %.2f）" % [up, hit, b.pos, b.height]
	# 衝鋒：往 +X 衝向 1.0 石台上的玩家，途中經過 0.5、1.0 石台都直接跳上去、不暈眩
	# 衝鋒 15 × 0.85 = 12.75：從 x -2 停在 x 約 10.75（1.0 石台 x 10.25~13.75），不會碰到場地邊緣（±16）
	var w2 := _new_world()
	var p2 := _player(w2)
	p2.pos = Vector2(12.5, 12)
	p2.height = 1.0
	var b2 := _spawn(w2, &"boss", Vector2(-2, 12))
	_run(w2, _cmd(Vector2.ZERO), roundi(EnemyDefs.ENEMIES.boss.spawn_time / DT) + 2)
	b2.fsm.change(&"charge")
	var ev: Array[Dictionary] = []
	var top := 0.0
	for i in 120:
		p2.hp = p2.max_hp
		_run_collect(w2, _cmd(Vector2.ZERO), 1, ev)
		top = maxf(top, b2.height)
		if not b2.fsm.is_in(&"charge"):
			break
	if not _named(ev, "fx:boss_wall").is_empty() or top < 1.0:
		return "衝鋒遇到 1.0 石台應跳上去、不暈眩：撞牆事件 %d、最高 %.2f" % [_named(ev, "fx:boss_wall").size(), top]
	# 衝鋒撞到 2.5 的牆（z 7.5~8.5）照樣暈眩
	var w3 := _new_world()
	var p3 := _player(w3)
	p3.pos = Vector2(11, 9.6)
	var b3 := _spawn(w3, &"boss", Vector2(11, 0))
	_run(w3, _cmd(Vector2.ZERO), roundi(EnemyDefs.ENEMIES.boss.spawn_time / DT) + 2)
	b3.fsm.change(&"charge")
	var ev3: Array[Dictionary] = []
	_run_collect(w3, _cmd(Vector2.ZERO), 120, ev3)
	if _named(ev3, "fx:boss_wall").is_empty():
		return "衝鋒撞到 2.5 的牆應暈眩"
	# 砸地：玩家站在旁邊 1.0 石台上打得到；跳起來躲得過
	for jump in [false, true]:
		var w4 := _new_world()
		var p4 := _player(w4)
		p4.pos = Vector2(12, 12)
		p4.height = 1.0
		var b4 := _spawn(w4, &"boss", Vector2(12, 15.2))
		_run(w4, _cmd(Vector2.ZERO), roundi(EnemyDefs.ENEMIES.boss.spawn_time / DT) + 2)
		b4.fsm.change(&"slam")
		var impact := roundi(EnemyDefs.ENEMIES.boss.slam.windup / DT)
		_run(w4, _cmd(Vector2.ZERO), impact - 12)
		if jump:
			_run(w4, _jump_cmd(), 1)
		_run(w4, _cmd(Vector2.ZERO), 20)
		var hurt := p4.hp < p4.max_hp
		if hurt == jump:
			return "Boss 砸地，玩家在 1.0 石台上%s：%s" % ["跳起來" if jump else "站著", "被打到" if hurt else "沒被打到"]
	print("    Boss：%.1f 秒跳上石座、%.1f 秒打到石座上的玩家" % [up * DT, hit * DT])
	return ""
