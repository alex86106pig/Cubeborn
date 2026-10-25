# 武器與小怪戰鬥：武器資料、法杖、武器稀有度數值、高度判定、打擊感、骷髏戰士與弓手、投射物撞牆
# 由 tests/check.gd 呼叫；每個 check_* 回傳 "" = 通過，否則是失敗原因
class_name CombatChecks
extends CheckKit

static func check_weapon_defs() -> String:
	var cues := _cue_names()
	for id: StringName in WeaponDefs.WEAPONS:
		var w: Dictionary = WeaponDefs.WEAPONS[id]
		for kind in ["attack", "special"]:
			var def: Dictionary = w[kind]
			if not WeaponBehaviors.BEHAVIORS.has(def.behavior):
				return "%s.%s 的 behavior「%s」不存在" % [id, kind, def.behavior]
			for t in ["windup", "active", "recovery"]:
				# 按住類（劍盾格擋，v0.41.0）的 active 是 0：按著就停在 active，放開立刻收招
				if def[t] <= 0.0 and not (t == "active" and def.get("hold", false) and def[t] == 0.0):
					return "%s.%s 的 %s 不是正數" % [id, kind, t]
			for key in ["sfx", "sfx_heavy"]:
				if def.has(key) and not cues.has(def[key]):
					return "%s.%s 的音效「%s」不在 Sound.CUE_NAMES" % [id, kind, def[key]]
	return ""


static func check_fire_bolt() -> String:
	var w := _new_world()
	var p := _player(w)
	p.equip_weapon(&"staff")
	var dummy := _dummy(w, Vector2(0, 5))
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1, events)
	var bolt: Projectile = null
	for i in 20:
		_run_collect(w, _cmd(Vector2.ZERO), 1, events)
		if not w.projectiles.is_empty():
			bolt = w.projectiles[0]
			break
	if bolt == null:
		return "沒有產生投射物"
	var a: Dictionary = WeaponDefs.WEAPONS[&"staff"].attack
	var step_len: float = a.projectile_speed * DT
	if absf(bolt.pos.y - bolt.traveled - a.spawn_offset) > EPS or absf(bolt.traveled - step_len) > EPS:
		return "產生位置 %.3f（預期 %.2f）、第一步飛行 %.4f（預期 %.4f）" % [bolt.pos.y - bolt.traveled, a.spawn_offset, bolt.traveled, step_len]
	_run_collect(w, _cmd(Vector2.ZERO), 30, events)
	if _damage_amounts(events, dummy.id) != [float(a.damage)] or not bolt.is_removed:
		return "命中傷害 %s（預期 [%.1f]），投射物 is_removed=%s" % [_damage_amounts(events, dummy.id), a.damage, bolt.is_removed]
	# 射程：沒有目標時飛滿射程後消失
	var w2 := _new_world()
	_player(w2).equip_weapon(&"staff")
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, -5), InputCmd.BTN_ATTACK), 1)
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, -5)), 10)
	var far: Projectile = w2.projectiles[0]
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, -5)), 60)
	if not far.is_removed or far.traveled < a.range or far.traveled > a.range + step_len:
		return "射程：飛行 %.3f 後 is_removed=%s，預期 %.1f" % [far.traveled, far.is_removed, a.range]
	return ""


static func check_arcane_burst() -> String:
	var w := _new_world()
	var p := _player(w)
	p.equip_weapon(&"staff")
	var s: Dictionary = WeaponDefs.WEAPONS[&"staff"].special
	var max_r: float = s.range
	var near := _dummy(w, Vector2(s.explosion_radius - 0.7, max_r))   # 落點旁：在爆炸半徑 + 假敵人半徑 0.5 內
	var far := _dummy(w, Vector2(s.explosion_radius + 1.3, max_r))    # 範圍外
	var far_aim := Vector2(0, max_r * 2.5)
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO, far_aim, InputCmd.BTN_SPECIAL), 1, events)
	if absf(p.action.data.get("dist", 0.0) - max_r) > EPS:
		return "瞄準射程外，落點距離 %.3f，預期限制為 %.1f" % [p.action.data.get("dist", 0.0), max_r]
	_run_collect(w, _cmd(Vector2.ZERO, far_aim), 90, events)
	if _damage_amounts(events, near.id) != [float(s.damage)]:
		return "範圍內目標受到 %s，預期 [%.1f]" % [_damage_amounts(events, near.id), s.damage]
	if not _damage_amounts(events, far.id).is_empty():
		return "範圍外目標不應受傷，實際 %s" % [_damage_amounts(events, far.id)]
	var names := _named(events, "sfx:cue").map(func(e: Dictionary) -> String: return e.cue)
	if names != ["arcaneCast", "explosion"]:
		return "音效 %s，預期 arcaneCast / explosion" % [names]
	# 最短距離：瞄準比最短距離更近的地方，落點限制為最短距離
	var w2 := _new_world()
	var p2 := _player(w2)
	p2.equip_weapon(&"staff")
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, s.min_range * 0.4), InputCmd.BTN_SPECIAL), 1)
	if absf(p2.action.data.get("dist", 0.0) - s.min_range) > EPS:
		return "瞄準 %.2f 單位處，落點距離 %.3f，預期 %.1f" % [s.min_range * 0.4, p2.action.data.get("dist", 0.0), s.min_range]
	return ""


static func check_melee_enemy() -> String:
	var w := _new_world(7)
	var p := _player(w)
	var gd: Dictionary = EnemyDefs.ENEMIES.grunt
	var g := _spawn(w, &"grunt", Vector2(0, 4))
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO), ceili(gd.spawn_time / DT) - 1, events)
	if not g.fsm.is_in(&"spawn") or g.velocity != Vector2.ZERO:
		return "爬出期間應停在 spawn 且不移動"
	_run_collect(w, _cmd(Vector2.ZERO), 2, events)
	if not g.fsm.is_in(&"chase"):
		return "爬出後應進入 chase，實際 %s" % g.fsm.current_name
	var hit_ticks: Array[int] = []
	for i in 60 * 5:
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		for e in _named(w.events, "entity:damaged"):
			if e.target_id == p.id:
				if absf(e.amount - gd.swing.damage) > 1e-4:
					return "揮砍傷害 %.2f，預期 %.2f" % [e.amount, gd.swing.damage]
				hit_ticks.append(w.tick)
	if hit_ticks.size() < 3:
		return "5 秒內只命中 %d 次" % hit_ticks.size()
	for i in range(1, hit_ticks.size()):
		if (hit_ticks[i] - hit_ticks[i - 1]) * DT < gd.swing.cooldown - EPS:
			return "揮砍間隔 %.3f 秒，應 ≥ %.2f（冷卻）" % [(hit_ticks[i] - hit_ticks[i - 1]) * DT, gd.swing.cooldown]
	# 受擊硬直
	var w2 := _new_world(7)
	var g2 := _spawn(w2, &"grunt", Vector2(0, 6))
	_run(w2, _cmd(Vector2.ZERO), ceili(gd.spawn_time / DT) + 2)
	g2.take_damage(5.0, Vector2(0, 1), 0.0, 0)
	if not g2.fsm.is_in(&"hurt"):
		return "受擊應進入 hurt，實際 %s" % g2.fsm.current_name
	_run(w2, _cmd(Vector2.ZERO), ceili(gd.hurt_time / DT) + 1)
	if not g2.fsm.is_in(&"chase"):
		return "硬直 %.2f 秒後應回到 chase，實際 %s" % [gd.hurt_time, g2.fsm.current_name]
	return ""


static func check_ranged_enemy() -> String:
	var w := _new_world(11)
	var p := _player(w)
	var a := _spawn(w, &"archer", Vector2(0, 8))
	var events: Array[Dictionary] = []
	var aim_tick := -1
	var shot_tick := -1
	for i in 60 * 6:
		p.hp = p.max_hp   # 只測弓手行為，不讓玩家死
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		events.append_array(w.events)
		if aim_tick < 0 and a.fsm.is_in(&"aim"):
			aim_tick = w.tick
		if aim_tick >= 0 and shot_tick < 0 and not _named(w.events, "sfx:cue").filter(func(e: Dictionary) -> bool: return e.cue == "arrowShot").is_empty():
			shot_tick = w.tick
	if aim_tick < 0 or shot_tick < 0:
		return "6 秒內沒有瞄準 / 射擊"
	var ad: Dictionary = EnemyDefs.ENEMIES.archer
	var aim_len := (shot_tick - aim_tick) * DT
	if absf(aim_len - ad.aim_time) > DT * 1.5:
		return "瞄準到射擊 %.3f 秒，預期 %.2f" % [aim_len, ad.aim_time]
	var dmg := roundi(ad.projectile_damage)
	var arrows := _named(events, "entity:damaged").filter(func(e: Dictionary) -> bool: return e.target_id == p.id and e.amount == dmg)
	if arrows.is_empty():
		return "箭沒有造成 %d 傷害（玩家受到 %s）" % [dmg, _damage_amounts(events, p.id)]
	var dist := a.pos.distance_to(p.pos)
	var pr: Array = ad.preferred_range
	if dist < pr[0] - 0.5 or dist > pr[1] + 0.5:
		return "6 秒後與玩家距離 %.2f，應保持在 %.0f~%.0f 附近" % [dist, pr[0], pr[1]]
	return ""


static func check_projectile_walls() -> String:
	var w := _new_world()
	var p := _player(w)
	p.pos = Vector2(11, 5)   # 牆在 z 7.5~8.5
	var d := _dummy(w, Vector2(11, 11))
	var bolt := Projectile.new(w, {"owner": p, "pos": p.pos, "direction": Vector2(0, 1), "speed": 10.0, "range": 10.0,
		"damage": 10.0, "settle_altitude": Config.HEIGHT.bolt_altitude, "settle_distance": Config.HEIGHT.bolt_settle_distance})
	w.spawn_projectile(bolt)
	_run(w, _cmd(Vector2.ZERO), 60)
	if not bolt.is_removed or bolt.pos.y > 7.5 + 0.2 or d.hp < 1000.0:
		return "魔彈應在牆前消失：z %.2f、已移除 %s、牆後的假人血 %.0f" % [bolt.pos.y, bolt.is_removed, d.hp]
	var w2 := _new_world()
	var p2 := _player(w2)
	p2.pos = Vector2(12, 12)
	p2.height = 1.0
	_run(w2, _cmd(Vector2.ZERO), 1)
	var d2 := _dummy(w2, Vector2(18, 12))
	w2.spawn_projectile(Projectile.new(w2, {"owner": p2, "pos": p2.pos, "direction": Vector2(1, 0), "speed": 10.0, "range": 10.0,
		"damage": 10.0, "settle_altitude": Config.HEIGHT.bolt_altitude, "settle_distance": Config.HEIGHT.bolt_settle_distance}))
	_run(w2, _cmd(Vector2.ZERO), 60)
	if d2.hp >= 1000.0:
		return "從 1.0 石台往下射，應打到地上的假人"
	return ""


static func check_staff_changes() -> String:
	var w := _new_world()
	var p := _player(w)
	p.equip_weapon(&"staff")
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 120, events)
	var shots := _named(events, "fx:muzzle").size()
	# 按住 2 秒：每 (windup + active + recovery) 秒一發，前搖結束時射出
	var a: Dictionary = WeaponDefs.WEAPONS[&"staff"].attack
	var period := ceili((a.windup + a.active + a.recovery) / DT)
	var want := (120 - ceili(a.windup / DT)) / period + 1
	if shots != want:
		return "法杖 2 秒普攻 %d 發，預期 %d（%.2f 秒一發）" % [shots, want, a.windup + a.active + a.recovery]
	var w2 := _new_world()
	var p2 := _player(w2)
	p2.equip_weapon(&"staff")
	var g := _spawn(w2, &"grunt", Vector2(0, 5))
	_run(w2, _cmd(Vector2.ZERO), roundi(EnemyDefs.ENEMIES.grunt.spawn_time / DT) + 2)
	var hp := g.hp
	var hurt := false
	for i in 40:
		_run(w2, _cmd(Vector2.ZERO, g.pos, InputCmd.BTN_ATTACK), 1)
		hurt = hurt or g.fsm.is_in(&"hurt")
		if g.hp < hp:
			break
	if g.hp >= hp:
		return "魔彈應打中骷髏"
	if hurt or g.fsm.is_in(&"hurt") or g.knockback.length() > EPS:
		return "遠程普攻不應讓骷髏硬直或擊退：硬直 %s、擊退 %.3f" % [hurt or g.fsm.is_in(&"hurt"), g.knockback.length()]
	return ""


static func check_weapon_base_stats() -> String:
	# 武器面板數值 = 武器資料 × 稀有度倍率（攻速 = 倍率 ÷ 一刀的秒數）
	var a: Dictionary = WeaponDefs.WEAPONS[&"swordShield"].attack
	var swing_time: float = a.windup + a.active + a.recovery
	for r: StringName in [&"white", &"green"]:
		var got := WeaponDropDefs.base_stats({"base": &"swordShield", "rarity": r})
		var m: Dictionary = WeaponDropDefs.RARITY_BASE[r]
		var want := [a.damage * m.damage, m.attack_speed / swing_time, a.range * m.range]
		if absf(got.damage - want[0]) > EPS or absf(got.attack_speed - want[1]) > 0.01 or absf(got.range - want[2]) > EPS:
			return "%s 劍盾應為 %.2f / %.2f / %.2f，實際 %.2f / %.2f / %.2f" % [r, want[0], want[1], want[2], got.damage, got.attack_speed, got.range]
	var green: Dictionary = WeaponDropDefs.RARITY_BASE[&"green"]
	var w := _new_world()
	var p := _player(w)
	p.weapon_slots[0] = {"uid": &"g", "base": &"swordShield", "rarity": &"green", "affixes": [] as Array[StringName]}
	p._apply_active_weapon()
	if absf(p.stats.value(&"damage") - green.damage) > EPS or absf(p.weapon_range_mul() - green.range) > EPS:
		return "裝上綠劍盾：攻擊力 %.2f（應 %.2f）、範圍倍率 %.2f（應 %.2f）" % [p.stats.value(&"damage"), green.damage, p.weapon_range_mul(), green.range]
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 15, events)
	var slash := _named(events, "fx:slash")
	if slash.is_empty() or absf(slash[0].range - a.range * green.range) > EPS:
		return "綠劍盾揮砍距離應為 %.3f" % (a.range * green.range)
	return ""


static func check_height_hits() -> String:
	var w := _new_world()
	var p := _player(w)
	var archer := _spawn(w, &"archer", Vector2(0, 15))
	var arrow_at := func() -> Projectile:
		var a := Projectile.new(w, {"owner": archer, "pos": p.pos, "direction": Vector2(0, -1), "speed": 0.01,
			"range": 5.0, "damage": 10.0, "altitude": Config.HEIGHT.arrow_altitude})
		w.spawn_projectile(a)
		return a
	_run(w, _jump_cmd(), roundi(Config.JUMP.air_time / 2.0 / DT))
	var hp := p.hp
	var high: Projectile = arrow_at.call()
	_run(w, _cmd(Vector2.ZERO), 1)
	if high.is_removed or p.hp != hp:
		return "最高點（%.2f）時箭應從腳下飛過" % p.height
	high.remove()
	while not p.is_grounded():
		_run(w, _cmd(Vector2.ZERO), 1)
	var low: Projectile = arrow_at.call()
	_run(w, _cmd(Vector2.ZERO), 1)
	if not low.is_removed or p.hp >= hp:
		return "站在地面應中箭"

	# Boss 砸地：腳底高於 slam_height 打不到
	var w2 := _new_world()
	var p2 := _player(w2)
	var boss := _spawn(w2, &"boss", Vector2(0, 2.0))
	p2.height = Config.HEIGHT.slam_height + 0.3
	var hp2 := p2.hp
	boss.slam_ring(0, {})
	if p2.hp != hp2:
		return "腳底 %.2f 時不應被砸地打到" % p2.height
	p2.height = 0.0
	boss.slam_ring(0, {})
	if p2.hp >= hp2:
		return "站在地面應被砸地打到"

	# 空中揮砍打得到地上的骷髏
	var w3 := _new_world()
	var p3 := _player(w3)
	var g := _spawn(w3, &"grunt", Vector2(0, 1.3))
	_run(w3, _jump_cmd(), 17)
	var g_hp := g.hp
	_run(w3, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 12)
	if g.hp >= g_hp:
		return "空中揮砍（高度 %.2f）應打得到地上的骷髏" % p3.height

	# 空中魔彈：從 2.75 發射，3 單位內降到 1.25，打得到 4.5 單位外的骷髏
	var w4 := _new_world()
	var p4 := _player(w4)
	p4.equip_weapon(&"staff")
	var g4 := _spawn(w4, &"grunt", Vector2(0, 4.5))
	_run(w4, _jump_cmd(Vector2.ZERO), 16)
	var g4_hp := g4.hp
	_run(w4, _cmd(Vector2.ZERO, Vector2(0, 4.5), InputCmd.BTN_ATTACK), 1)
	_run(w4, _cmd(Vector2.ZERO, Vector2(0, 4.5)), 40)
	if g4.hp >= g4_hp:
		return "空中魔彈應降回胸口高度、打得到地上的骷髏"
	return ""


static func check_no_contact_damage() -> String:
	var w := _new_world()
	var p := _player(w)
	var g := _spawn(w, &"grunt", Vector2(0, 1.0))
	var a := _spawn(w, &"archer", Vector2(1.0, 0))
	var b := _spawn(w, &"boss", Vector2(-1.6, 0))
	for name in ["swing", "fire", "slam", "charge", "summon"]:
		for e: Enemy in [g, a, b]:
			w.cooldowns.start(e.cd(name), 100.0)
	_run(w, _cmd(Vector2.ZERO), 120)
	if p.hp != p.max_hp:
		return "貼身 2 秒不應扣血，實際血量 %.0f" % p.hp
	return ""


static func check_grunt_swing() -> String:
	var s: Dictionary = EnemyDefs.ENEMIES.grunt.swing
	# 命中時機與傷害
	var w := _new_world()
	var p := _player(w)
	var g := _grunt_swinging(w, p)
	if not g.fsm.is_in(&"swing"):
		return "玩家在 1.2 內時骷髏應開始舉刀"
	var steps := 0
	var dealt := 0.0
	while steps < 60 and dealt == 0.0:
		_run(w, _cmd(Vector2.ZERO), 1)
		steps += 1
		for e in _named(w.events, "entity:damaged"):
			if e.target_id == p.id:
				dealt = e.amount
	var expected_steps := roundi(s.windup / DT)
	if absf(dealt - s.damage) > 1e-4 or absi(steps - expected_steps) > 1:
		return "舉刀約 %d 步後應命中 %.1f，實際第 %d 步、傷害 %.2f" % [expected_steps, s.damage, steps, dealt]
	if w.hitboxes.is_empty() or w.hitboxes[0].shape.shape != &"sector":
		return "命中當步應記錄扇形判定（F2 顯示用）"

	# 扇形邊界：半角 50° + 目標半徑換算的角度（距離 1.4 時 +18.7°），距離 1.5 + 目標半徑
	var w2 := _new_world()
	var p2 := _player(w2)
	var shape := {"shape": &"sector", "range": s.range, "arc": s.arc}
	var inside := func(at: Vector2) -> bool:
		p2.pos = at
		return not Hitbox.query(w2, &"enemy", Vector2.ZERO, 0.0, shape).is_empty()
	var allow: float = s.arc / 2.0 + asin(p2.radius / 1.4)
	if not inside.call(MathUtil.dir_from_angle(allow - 0.05) * 1.4) or inside.call(MathUtil.dir_from_angle(allow + 0.05) * 1.4):
		return "扇形角度邊界應在 %.1f°" % rad_to_deg(allow)
	var reach: float = s.range + p2.radius
	if not inside.call(Vector2(0, reach - 0.02)) or inside.call(Vector2(0, reach + 0.05)):
		return "扇形距離邊界應在 %.2f" % reach

	# 舉刀後半鎖定方向：鎖定後玩家繞到側面就躲開
	var w3 := _new_world()
	var p3 := _player(w3)
	var g3 := _grunt_swinging(w3, p3)
	_run(w3, _cmd(Vector2.ZERO), roundi(s.windup * s.track / DT) + 2)
	var locked := g3.facing
	p3.pos = Vector2(1.5, -0.3)
	var hp := p3.hp
	_run(w3, _cmd(Vector2.ZERO), roundi((s.windup + s.active) / DT))
	if p3.hp != hp:
		return "鎖定方向後繞到側面應躲開，實際扣 %.0f" % (hp - p3.hp)
	if absf(angle_difference(locked, g3.facing)) > 1e-4:
		return "舉刀後半不應再轉向"

	# 舉刀中被打會中斷，不會揮下
	var w4 := _new_world()
	var p4 := _player(w4)
	var g4 := _grunt_swinging(w4, p4)
	_run(w4, _cmd(Vector2.ZERO), 10)
	g4.take_damage(5.0, Vector2(0, -1), 0.0, p4.id)
	var hp4 := p4.hp
	_run(w4, _cmd(Vector2.ZERO), roundi(s.windup / DT))
	if p4.hp != hp4 or g4.fsm.is_in(&"swing"):
		return "舉刀中被打應中斷：血量 %.0f → %.0f、狀態 %s" % [hp4, p4.hp, g4.fsm.current_name]
	return ""


static func check_hit_feel() -> String:
	# 玩家揮砍打中：不震動、不放慢，事件帶武器資料的 hit_stop
	var want_stop: float = WeaponDefs.WEAPONS[&"swordShield"].attack.hit_stop
	var w := _new_world()
	var p := _player(w)
	var g := _spawn(w, &"grunt", Vector2(0, 1.5))
	w.cooldowns.start(g.cd("swing"), 100.0)
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1, events)
	_run_collect(w, _cmd(Vector2.ZERO), 15, events)
	var hits := _named(events, "entity:damaged").filter(func(e: Dictionary) -> bool: return e.target_id == g.id)
	if hits.is_empty() or absf(hits[0].hit_stop - want_stop) > EPS:
		return "玩家打中應發出帶 hit_stop %.2f 的 entity:damaged：%s" % [want_stop, hits]
	if not _named(events, "camera:shake").is_empty():
		return "玩家攻擊打中不應震動"
	if w.hit_stop_timer > 0.0:
		return "一般命中不應放慢模擬時間（hit_stop_timer %.3f）" % w.hit_stop_timer
	# 法杖奧術爆裂：爆炸不震動
	var w2 := _new_world()
	var p2 := _player(w2)
	p2.equip_weapon(&"staff")
	var ev2: Array[Dictionary] = []
	_run_collect(w2, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL), 1, ev2)
	_run_collect(w2, _cmd(Vector2.ZERO), 90, ev2)
	if _named(ev2, "sfx:cue").filter(func(e: Dictionary) -> bool: return e.cue == "explosion").is_empty():
		return "奧術爆裂應該爆炸（檢查前提）"
	if not _named(ev2, "camera:shake").is_empty():
		return "玩家的奧術爆炸不應震動"
	# 玩家被打、Boss 砸地：照常震動
	var w3 := _new_world()
	var p3 := _player(w3)
	w3.events.clear()
	Combat.apply_damage(w3, _spawn(w3, &"grunt", Vector2(0, 1.0)), p3, {"damage": 5.0})
	if _named(w3.events, "camera:shake").is_empty():
		return "玩家被打應震動"
	var boss := _spawn(w3, &"boss", Vector2(0, 8))
	w3.events.clear()
	boss.slam_ring(0, {})
	if _named(w3.events, "camera:shake").is_empty():
		return "Boss 砸地應震動"
	# 命中定格 v0.19.1 起關閉：打中後模型照常跟著實際位置
	if Config.FEEL.hit_freeze:
		return "Config.FEEL.hit_freeze 應為 false（v0.19.1 使用者決定拿掉命中定格）"
	var w4 := _new_world()
	var p4 := _player(w4)
	var g4 := _spawn(w4, &"grunt", Vector2(0, 3))
	var view := WorldView.new()
	view.sync(w4, 1.0, DT)
	var node: Node3D = view._nodes[g4.id]
	view.on_event("entity:damaged", {"source_id": p4.id, "target_id": g4.id, "hit_stop": 0.1})
	g4.pos += Vector2(1, 0)
	g4.prev_pos = g4.pos
	view.sync(w4, 1.0, 0.05)
	if absf(node.position.x - g4.pos.x) > EPS:
		return "打中後模型不應定格，應立刻跟上實際位置（%.2f vs %.2f）" % [node.position.x, g4.pos.x]
	view.free()
	return ""


static func check_enemy_speed() -> String:
	var w := _new_world(77, true)
	w.spawner.finished = true
	for type: StringName in [&"grunt", &"archer"]:
		var def: Dictionary = EnemyDefs.ENEMIES[type]
		for wave in [1, 3, 4]:
			w.spawner.wave = wave
			var mul: float = WaveDefs.wave_multipliers(wave).speed
			var lo: float = def.move_speed * mul * (1.0 - def.speed_variance)
			var hi: float = def.move_speed * mul * (1.0 + def.speed_variance)
			var s_min := INF
			var s_max := -INF
			for i in 40:
				var e := _spawn(w, type, Vector2(10, 10))
				s_min = minf(s_min, e.speed)
				s_max = maxf(s_max, e.speed)
				e.remove()
			if s_min < lo - EPS or s_max > hi + EPS:
				return "%s 第 %d 波移速 %.3f~%.3f，應在 %.3f~%.3f" % [type, wave, s_min, s_max, lo, hi]
			if wave == 3:
				_feel("%s 第 3 波移速：範圍 %.3f~%.3f，40 隻實測 %.3f~%.3f" % [type, lo, hi, s_min, s_max])
	w.spawner.wave = WaveDefs.WAVES.size()
	var boss := _spawn(w, &"boss", Vector2(-10, -10))
	if boss.speed != EnemyDefs.ENEMIES.boss.move_speed:   # Boss 不吃波次成長、沒有隨機變異
		return "Boss 移速 %.3f，預期固定 %.2f" % [boss.speed, EnemyDefs.ENEMIES.boss.move_speed]
	boss.remove()

	# 弓手箭：射出後把玩家移開讓箭落空，量速度與最遠距離
	var p := _player(w)
	var archer := _spawn(w, &"archer", Vector2(0, 8))
	var proj: Projectile = null
	for i in 600:
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		if not w.projectiles.is_empty():
			proj = w.projectiles[0]
			break
	if proj == null:
		return "弓手 10 秒內沒有射箭"
	p.pos = Vector2(12, -12)
	var origin := proj.pos
	var last := proj.pos
	var speed := 0.0
	var farthest := 0.0
	var ref: WeakRef = weakref(proj)
	proj = null
	for i in 240:
		w.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		var pr: Projectile = ref.get_ref()
		if pr == null or not w.projectiles.has(pr):
			break
		speed = pr.pos.distance_to(last) / DT
		last = pr.pos
		farthest = pr.pos.distance_to(origin)
	var ad: Dictionary = EnemyDefs.ENEMIES.archer
	_feel("弓手箭：資料 %.1f 單位/秒、射程 %.1f；實測 %.2f 單位/秒、最遠 %.2f" % [ad.projectile_speed, ad.projectile_range, speed, farthest])
	archer.remove()
	if absf(speed - ad.projectile_speed) > 0.01:
		return "箭速 %.2f，預期 %.1f" % [speed, ad.projectile_speed]
	if farthest < ad.projectile_range - ad.projectile_speed * DT - EPS or farthest > ad.projectile_range + EPS:
		return "箭最遠 %.2f，預期約 %.1f" % [farthest, ad.projectile_range]
	return ""
