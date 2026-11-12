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
	var warn := _named(events, "fx:boss_teleport_warn")
	if warn.is_empty() or (warn.back().pos as Vector2).distance_to(p3.pos) > 1.0:
		return "瞬移前應在玩家腳下冒紫煙（fx:boss_teleport_warn）"
	if not _named(events, "fx:telegraph").is_empty():
		return "瞬移砸地不應畫預警圈"
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


# 瞬移砸地躲不躲得掉（v0.42.0：ring_delay 0.25 → 0.5）：站著不動被第 1 圈打一次；
# 看到預警後反應 0.3 秒往外直跑就躲得掉（三圈打到時都在那一圈外面）；
# 畫面的地板裂紋：每一圈比爆開早 ring_delay 秒爬滿（舉手時間短時縮短）、之後變亮到爆開、爆開後淡掉
static func check_teleport_slam_dodge(feel: Array[String]) -> String:
	var s: Dictionary = EnemyDefs.ENEMIES.boss.slam
	var results := []
	for run in [false, true]:
		var w := _new_world(8)
		var p := _player(w)
		p.pos = Vector2(0, 12)
		var b: Boss = _spawn(w, &"boss", Vector2(0, -8))
		_run(w, _cmd(Vector2.ZERO), roundi(EnemyDefs.ENEMIES.boss.spawn_time / DT) + 2)
		b.is_enraged = true
		w.cooldowns.start(b.cd("charge"), 99.0)
		w.cooldowns.start(b.cd("summon"), 99.0)
		w.cooldowns.start(b.cd("cleave"), 99.0)
		w.cooldowns.reset(b.cd("slam"))
		var events: Array[Dictionary] = []
		if _run_until(w, _cmd(Vector2.ZERO), 60, events, func() -> bool: return b.fsm.is_in(&"slam")) < 0:
			return "狂暴時應瞬移砸地"
		var start := w.tick
		var center: Vector2 = b.fsm.data.target
		var dists: Array[float] = []   # 每一圈打出去那一步，玩家離砸地中心的距離
		var hits := 0
		for i in 240:
			var move := Vector2.ZERO
			if run and (w.tick - start) * DT >= 0.3:
				move = (Vector2.ZERO - center).normalized()   # 往場地中央跑（玩家在 (0, 12)，往外跑會撞到場地邊緣）
			w.step({World.HOST_PEER_ID: _cmd(move, p.pos + move * 5.0)}, DT)
			for e in w.events:
				if e.name == "fx:boss_slam":
					dists.append(p.pos.distance_to(center))
				elif e.name == "entity:damaged" and e.target_id == p.id:
					hits += 1
			if not b.fsm.is_in(&"slam"):
				break
		results.append([hits, dists])
	if results[0][0] != 1:
		return "站著不動應被第 1 圈打一次，實際 %d 次" % results[0][0]
	var d: Array = results[1][1]
	var rings: Array = s.rings
	if results[1][0] != 0 or d.size() != rings.size():
		return "反應 0.3 秒往外跑應躲得掉：被打 %d 次、每圈打出時的距離 %s（圈半徑 %s）" % [results[1][0], d, rings]
	feel.append("瞬移砸地往外跑（反應 0.3 秒、移速 %.1f）：三圈打出時離中心 %.2f / %.2f / %.2f，圈外緣 %s（加角色半徑 %.2f）" % [Config.PLAYER.move_speed, d[0], d[1], d[2], rings, Config.PLAYER.radius])
	var C := EnemyAnimator.slam_crack
	var dl: float = s.ring_delay
	var wu: float = s.windup
	var fails: Array[String] = []
	if C.call(&"windup", 0.1, wu, 0, dl).x <= 0.0 or C.call(&"windup", 0.1, wu, 2, dl).y != 0.0:
		fails.append("舉手 0.1 秒：第 1 圈裂紋應開始長、第 3 圈還沒有")
	# 第 3 圈在 2 × ring_delay 爆開，ring_delay 前剛好爬滿
	if C.call(&"impact", dl - 0.01, wu, 2, dl).x >= 1.0 or C.call(&"impact", dl, wu, 2, dl).x < 1.0:
		fails.append("第 3 圈應在落地後 %.2f 秒爬滿（提前 %.2f 秒）" % [dl, dl])
	var before: Vector2 = C.call(&"impact", 2.0 * dl - 0.01, wu, 2, dl)
	if before.y < 0.95 or before.y > 1.0 or C.call(&"impact", 2.0 * dl - 0.2, wu, 2, dl).y >= before.y:
		fails.append("爬滿後到爆開應越來越亮（爆開前 %.2f）" % before.y)
	if C.call(&"impact", dl + EnemyAnimator.CRACK_FADE + 0.01, wu, 1, dl).y != 0.0:
		fails.append("爆開 %.1f 秒後應淡掉" % EnemyAnimator.CRACK_FADE)
	if C.call(&"warn", 0.1, wu, 0, dl).y != 0.0:
		fails.append("瞬移前（warn）不應有裂紋")
	var tw: float = EnemyDefs.ENEMIES.boss.enrage.teleport_windup
	if C.call(&"windup", 0.02, tw, 0, dl).x <= 0.0 or C.call(&"windup", tw - 0.01, tw, 0, dl).x < 1.0:
		fails.append("瞬移後舉手只有 %.2f 秒：第 1 圈裂紋也要在落地前爬滿" % tw)
	var B := EnemyAnimator.slam_band_charging
	if not B.call(&"impact", dl + 0.1, wu, 2, dl) or B.call(&"impact", dl + 0.1, wu, 1, dl) or B.call(&"impact", dl - 0.1, wu, 2, dl):
		fails.append("碎石只在爬滿、還沒爆開的那一圈跳")
	if not fails.is_empty():
		return "砸地裂紋：" + "；".join(fails)
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
	_note("Boss：%.1f 秒跳上石座、%.1f 秒打到石座上的玩家" % [up * DT, hit * DT])
	return ""


# 噬墓巨蟲的檢查共用：玩家血很多、站在 at；巨蟲在原點冒在地面上，only 以外的招式都鎖住（only 空的 = 全鎖）
static func _worm_setup(at: Vector2, only: String, surface_left: float) -> Array:
	var w := _new_world(3)
	var p := _player(w)
	p.stats.set_base(&"max_hp", 99999.0)
	p.hp = p.max_hp
	p.pos = at
	var b := _spawn(w, &"grave_worm", Vector2.ZERO) as GraveWorm
	b.fsm.change(&"chase")
	b._surface_left = surface_left
	for move: String in ["acid", "devour", "eggs"]:
		if move == only:
			w.cooldowns.reset(b.cd(move))
		else:
			w.cooldowns.start(b.cd(move), 999.0)
	return [w, p, b]


# 跑 steps 步，收集事件；on_step（每步之後呼叫，回傳 true 就停）
static func _worm_run(w: World, steps: int, events: Array[Dictionary], on_step: Callable = Callable()) -> void:
	for i in steps:
		w.step({World.HOST_PEER_ID: InputCmd.new()}, DT)
		events.append_array(w.events)
		if on_step.is_valid() and on_step.call():
			return


static func _worm_hits(events: Array[Dictionary], p: Player, b: Enemy) -> int:
	return events.filter(func(ev: Dictionary) -> bool: return ev.name == "entity:damaged" and ev.target_id == p.id and ev.source_id == b.id).size()


# 噬墓巨蟲（第 3 層）：冒在地面 surface.time 秒後鑽下去；地底打不到、不能當目標、不擋路；追到腳下停 warn 秒再衝出來，
# 站著被打中並擊飛、先跑開就打不到；噴酸 lobs 團落地各留一個酸池、站在落點被打中；吞噬把前方的人拉過來咬一口；
# 產卵 count 顆、hatch_time 秒後各孵 per_egg 隻不給靈魂的屍甲蟲
static func check_grave_worm() -> String:
	var d: Dictionary = EnemyDefs.ENEMIES.grave_worm
	var t: Dictionary = d.tunnel
	for mode: StringName in [&"stand", &"dodge"]:
		var s := _worm_setup(Vector2(0, -10), "", d.surface.time)
		var w: World = s[0]
		var p: Player = s[1]
		var b: GraveWorm = s[2]
		var ev: Array[Dictionary] = []
		_worm_run(w, roundi((d.surface.time - 0.2) / DT), ev)
		if b.is_burrowed() or not b.is_targetable():
			return "噬墓巨蟲冒出來 %.1f 秒內應在地面上（狀態 %s）" % [d.surface.time, b.fsm.current_name]
		_worm_run(w, roundi((0.4 + t.dive) / DT) + 2, ev)
		if not b.is_burrowed() or b.is_targetable() or not b.passes_through():
			return "噬墓巨蟲 %.1f 秒後應鑽進地底（狀態 %s）" % [d.surface.time + t.dive, b.fsm.current_name]
		var hp0 := b.hp
		if Combat.apply_damage(w, p, b, {"damage": 50.0, "knockback": 0.0}) or b.hp < hp0:
			return "噬墓巨蟲在地底應打不到"
		ev.clear()
		var lurk_at := [Vector2.INF]
		_worm_run(w, roundi((t.track_time + t.warn + 1.0) / DT), ev, func() -> bool:
			if lurk_at[0] == Vector2.INF and b.fsm.is_in(&"lurk"):
				lurk_at[0] = b.pos
				if mode == &"dodge":
					p.pos = b.pos + Vector2(t.radius + 2.5, 0.0)
			return lurk_at[0] != Vector2.INF and not b.is_burrowed())
		if lurk_at[0] == Vector2.INF or b.is_burrowed():
			return "噬墓巨蟲應在 %.1f 秒內追到目標附近衝出來（狀態 %s、離目標 %.1f）" % [t.track_time + t.warn, b.fsm.current_name, b.pos.distance_to(p.pos)]
		if mode == &"stand" and (lurk_at[0] as Vector2).distance_to(Vector2(0, -10)) > t.radius:
			return "噬墓巨蟲應追到目標腳下才停（停在 %s）" % [lurk_at[0]]
		var hits := _worm_hits(ev, p, b)
		if mode == &"stand" and (hits != 1 or p.vz <= 0.0 and p.height <= p.ground_height + 0.01):
			return "站著不動應被衝出來的巨蟲打中一次並擊飛（%d 次、vz %.1f）" % [hits, p.vz]
		if mode == &"dodge" and hits != 0:
			return "地面鼓起時跑開 %.1f 應打不到（打中 %d 次）" % [t.radius + 2.5, hits]
		if absf(b._surface_left - d.surface.time) > 0.1 or not b.is_targetable():
			return "衝出來後應在地面上停 %.1f 秒（剩 %.2f）" % [d.surface.time, b._surface_left]
	# 噴酸：目標在 6（夾在 distance 範圍內）→ 中間那團落在目標腳下
	var a: Dictionary = d.acid
	var s2 := _worm_setup(Vector2(0, -6), "acid", 99.0)
	var w2: World = s2[0]
	var ev2: Array[Dictionary] = []
	_worm_run(w2, roundi((d.decide_delay + a.windup + a.flight + 0.3) / DT), ev2)
	var lobs := _named(ev2, "fx:dirt_lob")
	if lobs.size() != 1 or (lobs[0].targets as Array).size() != int(a.lobs):
		return "噴酸應吐 %d 團（fx:dirt_lob %d 個）" % [a.lobs, lobs.size()]
	if _worm_hits(ev2, s2[1], s2[2]) != 1:
		return "站在酸液落點應被打中一次（%d 次）" % _worm_hits(ev2, s2[1], s2[2])
	if w2.zones.size() != int(a.lobs):
		return "酸液落地應留 %d 個酸池（%d 個）" % [a.lobs, w2.zones.size()]
	# 吞噬：目標在前方 6 → 被拉過來、拉到嘴邊咬一口
	var v: Dictionary = d.devour
	var s3 := _worm_setup(Vector2(0, -6), "devour", 99.0)
	var w3: World = s3[0]
	var p3: Player = s3[1]
	var b3: GraveWorm = s3[2]
	var ev3: Array[Dictionary] = []
	_worm_run(w3, roundi((d.decide_delay + v.windup) / DT) + 2, ev3)
	if not b3.fsm.is_in(&"devour") or _worm_hits(ev3, p3, b3) != 0:
		return "目標在 %.0f 內噬墓巨蟲應張嘴吞噬（狀態 %s）" % [v.trigger_distance, b3.fsm.current_name]
	var dist0 := b3.pos.distance_to(p3.pos)
	_worm_run(w3, roundi(0.4 / DT), ev3)
	if b3.pos.distance_to(p3.pos) > dist0 - 0.4 * v.pull_speed * 0.5:
		return "吞噬應把前方的人拉過來（0.4 秒從 %.2f 到 %.2f）" % [dist0, b3.pos.distance_to(p3.pos)]
	_worm_run(w3, roundi((v.pull_time + v.recovery) / DT), ev3)
	if _worm_hits(ev3, p3, b3) != 1:
		return "被拉到嘴邊應被咬一口（%d 次）" % _worm_hits(ev3, p3, b3)
	# 產卵
	var g: Dictionary = d.eggs
	var s4 := _worm_setup(Vector2(0, -14), "eggs", 99.0)
	var w4: World = s4[0]
	var b4: GraveWorm = s4[2]
	var ev4: Array[Dictionary] = []
	_worm_run(w4, roundi((d.decide_delay + g.windup) / DT) + 3, ev4)
	if _named(ev4, "fx:worm_egg").size() != int(g.count) or b4.hatched_alive() != 0:
		return "產卵應留 %d 顆卵（%d 顆）、還沒孵" % [g.count, _named(ev4, "fx:worm_egg").size()]
	_worm_run(w4, roundi(g.hatch_time / DT) + 2, ev4)
	if b4.hatched_alive() != int(g.count) * int(g.per_egg):
		return "卵 %.0f 秒後應孵出 %d 隻（%d 隻）" % [g.hatch_time, int(g.count) * int(g.per_egg), b4.hatched_alive()]
	for e in w4.enemies:
		if e is Enemy and (e as Enemy).summoner_id == b4.id and not (e as Enemy).no_souls:
			return "卵孵出來的不給靈魂"
	if EventDefs.boss_type(3) != &"grave_worm":
		return "第 3 層的 Boss 應是噬墓巨蟲"
	return ""


# 屍蛾女王的檢查共用：玩家血很多、站在 at；Boss 在原點、已經是屍蛾女王，only 以外的招式都鎖住（only 空的 = 全鎖），不會落地
static func _moth_setup(at: Vector2, only: String) -> Array:
	var w := _new_world(3)
	var p := _player(w)
	p.stats.set_base(&"max_hp", 99999.0)
	p.hp = p.max_hp
	p.pos = at
	var b := _spawn(w, &"grave_worm", Vector2.ZERO) as GraveWorm
	b._become_moth()
	b._land_timer = 999.0
	for move: String in ["dust", "swoop", "gust"]:
		if move == only:
			w.cooldowns.reset(b.cd(move))
		else:
			w.cooldowns.start(b.cd(move), 999.0)
	return [w, p, b]


# 屍蛾女王（噬墓巨蟲半血）：結蛹 transform.time 秒打得到、受傷 × damage_taken → form 1；飛著時地面的近戰打不到、投射物與跳起來的打得到、
# 不擋路；land.interval 秒後落地 land.time 秒（近戰打得到）並留 eggs 顆卵；鱗粉雲 clouds 團、站在裡面視野最多 dust.vision、拿火把不受影響；
# 俯衝打中路上的人、站在旁邊打不到；拍翅狂風把前方的人吹退、背後的不受影響、吹散蛛網
static func check_moth_queen() -> String:
	var d: Dictionary = EnemyDefs.ENEMIES.grave_worm
	var tr: Dictionary = d.transform
	var m: Dictionary = d.moth
	var s := _worm_setup(Vector2(0, -12), "", 99.0)
	var w: World = s[0]
	var p: Player = s[1]
	var b: GraveWorm = s[2]
	b.hp = b.max_hp * 0.55
	Combat.apply_damage(w, p, b, {"damage": b.max_hp * 0.1, "knockback": 0.0})
	if not b.fsm.is_in(&"pupate"):
		return "噬墓巨蟲：血量 %.0f%% 應開始結蛹（狀態 %s）" % [b.hp / b.max_hp * 100.0, b.fsm.current_name]
	_step_n(w, 3)
	b.invuln_timer = 0.0
	var dealt := b.take_damage(10.0, Vector2.UP, 0.0, p.id)
	if absf(dealt - 10.0 * tr.damage_taken * StatDefs.damage_factor(b.stats, &"phys")) > 0.05:
		return "打蛹的傷害應 × %.1f（10 → %.2f）" % [tr.damage_taken, dealt]
	var ev: Array[Dictionary] = []
	_worm_run(w, roundi(tr.time / DT) + 2, ev)
	if b.form != 1 or not b.is_flying() or _named(ev, "boss:transformed").size() != 1:
		return "結蛹 %.1f 秒後應變成屍蛾女王並飛起來（form %d、狀態 %s）" % [tr.time, b.form, b.fsm.current_name]
	b.invuln_timer = 0.0
	dealt = b.take_damage(10.0, Vector2.UP, 0.0, p.id)
	if absf(dealt - 10.0 * StatDefs.damage_factor(b.stats, &"phys")) > 0.05:
		return "破蛹後受到的傷害應回到原本（10 → %.2f）" % dealt
	# 飛著：地面的近戰打不到、投射物打得到、跳起來打得到；不擋路
	var s2 := _moth_setup(Vector2(0, -5), "")
	var w2: World = s2[0]
	var p2: Player = s2[1]
	var b2: GraveWorm = s2[2]
	_step_n(w2, 2)
	b2.invuln_timer = 0.0
	if not b2.is_flying() or not b2.passes_through():
		return "屍蛾女王盤旋時應在飛、不擋路（狀態 %s）" % b2.fsm.current_name
	if Combat.apply_damage(w2, p2, b2, {"damage": 5.0, "knockback": 0.0}):
		return "屍蛾女王飛著時站在地上的近戰應打不到"
	if not Combat.apply_damage(w2, p2, b2, {"damage": 5.0, "knockback": 0.0, "projectile": true}):
		return "屍蛾女王飛著時投射物應打得到"
	b2.invuln_timer = 0.0
	p2.height = p2.ground_height + m.jump_reach + 0.1
	if not Combat.apply_damage(w2, p2, b2, {"damage": 5.0, "knockback": 0.0, "band": Vector2(-10.0, 10.0)}):
		return "跳起來（腳離地 %.1f 以上）的攻擊應打得到飛著的屍蛾女王" % m.jump_reach
	# 落地：land.interval 秒後降下來，落地期間近戰打得到、留 eggs 顆卵，之後再飛起來
	var l: Dictionary = m.land
	var s3 := _moth_setup(Vector2(0, -5), "")
	var w3: World = s3[0]
	var p3: Player = s3[1]
	var b3: GraveWorm = s3[2]
	b3._land_timer = 0.3
	var ev3: Array[Dictionary] = []
	_worm_run(w3, roundi((0.3 + m.decide_delay + l.descend) / DT) + 4, ev3)
	b3.invuln_timer = 0.0
	if not b3.fsm.is_in(&"land") or b3.is_flying() or not Combat.apply_damage(w3, p3, b3, {"damage": 5.0, "knockback": 0.0}):
		return "屍蛾女王該落地時應降下來、近戰打得到（狀態 %s）" % b3.fsm.current_name
	if _named(ev3, "fx:worm_egg").size() != int(l.eggs):
		return "落地應留 %d 顆卵（%d 顆）" % [l.eggs, _named(ev3, "fx:worm_egg").size()]
	# 跑到飛起來的那一步就停：計時器在起飛時重設成 interval，起飛後才往下數
	_worm_run(w3, roundi(l.time / DT) + 2, ev3, func() -> bool: return b3.is_flying())
	if not b3.is_flying() or absf(b3._land_timer - l.interval) > 0.05:
		return "落地 %.1f 秒後應再飛起來、%.0f 秒後才再落地（狀態 %s、剩 %.1f）" % [l.time, l.interval, b3.fsm.current_name, b3._land_timer]
	# 鱗粉雲：clouds 團；站在裡面視野最多 vision，拿火把的不受影響
	var u: Dictionary = m.dust
	for torch: bool in [false, true]:
		var s4 := _moth_setup(Vector2(0, -5), "dust")
		var w4: World = s4[0]
		var p4: Player = s4[1]
		if torch:
			p4.equip_weapon(&"torch")
		var before := Vision.view_range(p4)
		var ev4: Array[Dictionary] = []
		_worm_run(w4, roundi((m.decide_delay + u.windup) / DT) + 3, ev4)
		var clouds := w4.zones.filter(func(z: Dictionary) -> bool: return z.has("vision_cap"))
		if clouds.size() != int(u.clouds):
			return "鱗粉雲應撒 %d 團（%d 團）" % [u.clouds, clouds.size()]
		p4.pos = clouds[0].pos
		_worm_run(w4, roundi(0.6 / DT), ev4)
		var inside := Vision.view_range(p4)
		if torch and absf(inside - before) > EPS:
			return "拿火把站在鱗粉雲裡視野不應變（%.1f → %.1f）" % [before, inside]
		if not torch and absf(inside - u.vision) > EPS:
			return "站在鱗粉雲裡視野應縮成 %.1f（%.1f）" % [u.vision, inside]
		if not torch:
			p4.pos = Vector2(14, 14)
			_worm_run(w4, roundi(1.0 / DT), ev4)
			if absf(Vision.view_range(p4) - before) > EPS:
				return "走出鱗粉雲視野應恢復（%.1f，原本 %.1f）" % [Vision.view_range(p4), before]
	# 俯衝：站在路上被打中；鎖定方向後站到旁邊（離路線 width + 2）打不到
	var sw: Dictionary = m.swoop
	for mode: StringName in [&"stand", &"side"]:
		var s5 := _moth_setup(Vector2(0, -8), "swoop")
		var w5: World = s5[0]
		var p5: Player = s5[1]
		var b5: GraveWorm = s5[2]
		var ev5: Array[Dictionary] = []
		_worm_run(w5, roundi((m.decide_delay + sw.windup + sw.length / sw.speed + 0.3) / DT), ev5, func() -> bool:
			if mode == &"side" and b5.fsm.is_in(&"swoop") and b5.fsm.time >= sw.windup * sw.track and p5.pos.x == 0.0:
				p5.pos = Vector2(sw.width + p5.radius + 2.0, -8)
			return false)
		var hits := _worm_hits(ev5, p5, b5)
		if mode == &"stand" and hits != 1:
			return "站在俯衝的路上應被打中一次（%d 次，Boss 在 %s）" % [hits, b5.pos]
		if mode == &"side" and hits != 0:
			return "方向鎖定後站到路線旁邊應打不到（%d 次）" % hits
		if b5.pos.distance_to(Vector2.ZERO) < sw.length * 0.5:
			return "俯衝應直線衝出去（只到 %s）" % b5.pos
	# 拍翅狂風：前方的人被吹退、蛛網被吹散；背後的人不受影響
	var g: Dictionary = m.gust
	var s6 := _moth_setup(Vector2(0, -4), "gust")
	var w6: World = s6[0]
	var p6: Player = s6[1]
	var b6: GraveWorm = s6[2]
	GroundZones.add_web(w6, Vector2(0, -3), EnemyDefs.ENEMIES.spider.web, b6.id)
	GroundZones.add_web(w6, Vector2(0, 5), EnemyDefs.ENEMIES.spider.web, b6.id)
	var ev6: Array[Dictionary] = []
	_worm_run(w6, roundi((m.decide_delay + g.windup + 0.5) / DT), ev6)
	var pushed := p6.pos.distance_to(Vector2(0, -4))
	if _worm_hits(ev6, p6, b6) != 1 or absf(pushed - g.push_distance * p6.knockback_mul) > g.push_distance * 0.1:
		return "拍翅狂風應把前方的人吹退 %.1f（打中 %d 次、吹退 %.2f）" % [g.push_distance * p6.knockback_mul, _worm_hits(ev6, p6, b6), pushed]
	CheckKit._note("屍蛾女王拍翅狂風：吹退 %.2f（目標 %.1f）" % [pushed, g.push_distance])
	var webs := w6.zones.filter(func(z: Dictionary) -> bool: return z.has("web_id"))
	if webs.size() != 1 or (webs[0].pos as Vector2).y < 0.0:
		return "拍翅狂風應吹散前方的蛛網、留下背後的（剩 %d 張）" % webs.size()
	return ""


# 骸骨將軍（第 2 層）：半血脫甲（無敵 transform.time 秒、碎片往外飛、吸掉場上的骷髏屍體）→ 萬骨聚合體（受傷 × damage_taken）；
# 骨刺陣打得到線上的、打不到兩條線中間的；低掃跳起來躲得過、高掃打得到跳起來的；巨骨輪撞牆暈 stun 秒；吞屍吃掉附近的骷髏回血
static func check_bone_general() -> String:
	var d: Dictionary = EnemyDefs.def_of(&"bone_general")
	var c: Dictionary = d.colossus
	var w := _new_world(3)
	var p := _player(w)
	p.stats.set_base(&"max_hp", 99999.0)
	p.hp = p.max_hp
	p.pos = Vector2(0, -6)
	var b := _spawn(w, &"bone_general", Vector2.ZERO) as BoneGeneral
	b.fsm.change(&"chase")
	var corpse := _spawn(w, &"grunt", Vector2(8, 8))
	corpse.die()
	w.events.clear()
	b.hp = b.max_hp * 0.55
	Combat.apply_damage(w, p, b, {"damage": b.max_hp * 0.1, "knockback": 0.0})
	if not b.fsm.is_in(&"transform"):
		return "骸骨將軍：血量 %.0f%% 應開始脫甲（狀態 %s）" % [b.hp / b.max_hp * 100.0, b.fsm.current_name]
	var shards := w.projectiles.filter(func(e: Entity) -> bool: return (e as Projectile).owner_id == b.id).size()
	if shards != int(d.transform.shards) or not corpse.is_removed:
		return "脫甲應射出 %d 片碎片（%d）、吸掉骷髏屍體（移除了 %s）" % [d.transform.shards, shards, corpse.is_removed]
	var hp0 := b.hp
	_step_n(w, 3)
	Combat.apply_damage(w, p, b, {"damage": 50.0, "knockback": 0.0})
	if b.hp < hp0 - EPS:
		return "脫甲中應無敵（扣了 %.1f）" % (hp0 - b.hp)
	_step_n(w, roundi(d.transform.time / DT) + 2)
	if b.form != 1 or not b.fsm.is_in(&"colossus_chase"):
		return "脫甲 %.1f 秒後應變成萬骨聚合體（form %d、狀態 %s）" % [d.transform.time, b.form, b.fsm.current_name]
	if b.radius != c.radius or c.radius > Config.NAV.margin_large + 1e-6:
		return "萬骨聚合體的碰撞半徑應是 %.2f、不超過大隻怪的尋路格子 %.2f：%.2f" % [c.radius, Config.NAV.margin_large, b.radius]
	b.invuln_timer = 0.0
	var hp1 := b.hp
	var dealt := b.take_damage(10.0, Vector2.UP, 0.0, p.id)
	if absf(dealt - 10.0 * c.damage_taken * StatDefs.damage_factor(b.stats, &"phys")) > 0.05:
		return "萬骨聚合體受到的傷害應 × %.1f（10 → %.2f）" % [c.damage_taken, dealt]
	b.hp = hp1
	# 骨刺陣：出招時對準目標（玩家在 +y）定下 6 條線；線上 4.5 打得到；之後走到兩條線中間（30°）3.0 打不到
	for case: Array in [[Vector2(0, 4.5), true], [MathUtil.dir_from_angle(PI / 6.0) * 3.0, false]]:
		var w2 := _new_world(3)
		var p2 := _player(w2)
		p2.stats.set_base(&"max_hp", 99999.0)
		p2.hp = p2.max_hp
		p2.pos = Vector2(0, 4.5)
		var b2 := _spawn(w2, &"bone_general", Vector2.ZERO) as BoneGeneral
		b2.form = 1
		b2.fsm.change(&"spikes")
		var hit := false
		for i in roundi((c.spikes.windup + 1.0) / DT):
			p2.pos = case[0]
			w2.step({World.HOST_PEER_ID: InputCmd.new()}, DT)
			for ev in w2.events:
				if ev.name == "entity:damaged" and ev.target_id == p2.id and ev.source_id == b2.id:
					hit = true
		if hit != case[1]:
			return "骨刺陣：玩家在 %s %s（應%s）" % [case[0], "被刺中" if hit else "沒被刺中", "刺中" if case[1] else "刺不到"]
	# 多臂橫掃：跳起來（離地 1.0）躲得過低掃、被高掃打到；站著被低掃打到
	for jump: bool in [false, true]:
		var w3 := _new_world(3)
		var p3 := _player(w3)
		p3.stats.set_base(&"max_hp", 99999.0)
		p3.hp = p3.max_hp
		p3.pos = Vector2(0, 2.5)
		var b3 := _spawn(w3, &"bone_general", Vector2.ZERO) as BoneGeneral
		b3.form = 1
		b3.fsm.change(&"sweep")
		var low_hit := false
		var high_hit := false
		for i in roundi((c.sweep.windup + c.sweep.gap + 0.1) / DT):
			if jump:
				p3.height = 1.0
				p3.vz = 0.0
			p3.pos = Vector2(0, 2.5)
			w3.step({World.HOST_PEER_ID: InputCmd.new()}, DT)
			for ev in w3.events:
				if ev.name == "entity:damaged" and ev.target_id == p3.id and ev.source_id == b3.id:
					if b3.fsm.data.get("phase", &"") == &"low":
						low_hit = true
					else:
						high_hit = true
		if jump and (low_hit or not high_hit):
			return "多臂橫掃：跳起來應躲過低掃、被高掃打到（低 %s、高 %s）" % [low_hit, high_hit]
		if not jump and not low_hit:
			return "多臂橫掃：站著應被低掃打到"
	# 巨骨輪：滾到場地邊緣撞牆，暈 stun 秒再回來追
	var w4 := _new_world(3)
	var p4 := _player(w4)
	p4.stats.set_base(&"max_hp", 99999.0)
	p4.hp = p4.max_hp
	p4.pos = Vector2(0, 12)
	var b4 := _spawn(w4, &"bone_general", Vector2(0, 0)) as BoneGeneral
	b4.form = 1
	b4.fsm.change(&"wheel")
	var stunned_at := -1
	for i in roundi((c.wheel.windup + c.wheel.max_time + 0.5) / DT):
		p4.hp = p4.max_hp
		w4.step({World.HOST_PEER_ID: InputCmd.new()}, DT)
		if b4.fsm.is_in(&"wheel_stun"):
			stunned_at = i
			break
	if stunned_at < 0:
		return "巨骨輪應滾到撞牆暈眩（狀態 %s、位置 %s）" % [b4.fsm.current_name, b4.pos]
	_step_n(w4, roundi(c.wheel.stun / DT) + 2)
	if not b4.fsm.is_in(&"colossus_chase"):
		return "巨骨輪撞牆暈 %.1f 秒後應回來追（狀態 %s）" % [c.wheel.stun, b4.fsm.current_name]
	# 吞屍：radius 內 3 隻活的骷髏 + 1 具屍體被吃掉，每具回 heal_per
	var w5 := _new_world(3)
	_player(w5).pos = Vector2(0, -15)
	var b5 := _spawn(w5, &"bone_general", Vector2.ZERO) as BoneGeneral
	b5.form = 1
	b5.hp = b5.max_hp * 0.5
	var eaten: Array[Entity] = []
	for at: Vector2 in [Vector2(3, 0), Vector2(-3, 2), Vector2(0, 5)]:
		eaten.append(_spawn(w5, &"grunt", at))
	var dead := _spawn(w5, &"archer", Vector2(2, -2))
	dead.die()
	eaten.append(dead)
	var far := _spawn(w5, &"grunt", Vector2(0, c.devour.radius + 4.0))
	b5.fsm.change(&"devour")
	_step_n(w5, roundi((c.devour.windup + 0.05) / DT))
	var gone := eaten.filter(func(e: Entity) -> bool: return not w5.entities.has(e.id)).size()
	var want: float = 0.5 + c.devour.heal_per * 4.0
	if gone != 4 or not w5.entities.has(far.id) or absf(b5.hp / b5.max_hp - want) > 0.005:
		return "吞屍：應吃掉 radius 內 4 具（%d）、不吃遠的（還在 %s）、血量 %.0f%% → %.0f%%（%.1f%%）" % [gone, w5.entities.has(far.id), 50.0, want * 100.0, b5.hp / b5.max_hp * 100.0]
	return ""


static func _step_n(w: World, n: int) -> void:
	var p := _player(w)
	for i in n:
		p.hp = p.max_hp
		w.step({World.HOST_PEER_ID: InputCmd.new()}, DT)
