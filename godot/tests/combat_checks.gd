# 武器與小怪戰鬥：武器資料、法杖、武器稀有度數值、高度判定、打擊感、骷髏戰士與弓手、投射物撞牆
# 由 tests/check.gd 呼叫；每個 check_* 回傳 "" = 通過，否則是失敗原因
class_name CombatChecks
extends CheckKit

static func check_weapon_defs() -> String:
	var cues := _cue_names()
	for id: StringName in WeaponDefs.WEAPONS:
		var w: Dictionary = WeaponDefs.WEAPONS[id]
		for kind in ["attack", "special", "dual_attack"]:
			if not w.has(kind):   # 盾（只能當副手）沒有左鍵；只有匕首有雙持招式
				continue
			var def: Dictionary = w[kind]
			if not WeaponBehaviors.BEHAVIORS.has(def.behavior):
				return "%s.%s 的 behavior「%s」不存在" % [id, kind, def.behavior]
			for t in ["windup", "active", "recovery"]:
				# 按住類（劍盾格擋，v0.41.0）的 active 是 0：按著就停在 active，放開立刻收招
				if def[t] <= 0.0 and not (t == "active" and def.get("hold", false) and def[t] == 0.0):
					return "%s.%s 的 %s 不是正數" % [id, kind, t]
			for key in ["sfx", "sfx_heavy", "sfx_release"]:
				if def.has(key) and not cues.has(def[key]):
					return "%s.%s 的音效「%s」不在 Sound.CUE_NAMES" % [id, kind, def[key]]
	return _weapon_catalog()


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
	var bolt_dmg := WeaponDefs.move_base_damage(WeaponDefs.WEAPONS[&"staff"], a)
	if _damage_amounts(events, dummy.id) != [bolt_dmg] or not bolt.is_removed:
		return "命中傷害 %s（預期 [%.1f]），投射物 is_removed=%s" % [_damage_amounts(events, dummy.id), bolt_dmg, bolt.is_removed]
	# 射程：沒有目標時飛滿射程後消失
	var w2 := _new_world()
	_player(w2).equip_weapon(&"staff")
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, -5), InputCmd.BTN_ATTACK), 1)
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, -5)), 10)
	var far: Projectile = w2.projectiles[0]
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, -5)), 60)
	if not far.is_removed or far.traveled < a.range or far.traveled > a.range + step_len:
		return "射程：飛行 %.3f 後 is_removed=%s，預期 %.1f" % [far.traveled, far.is_removed, a.range]
	# 每一招都有畫好的圖示與說明（技能欄與選角畫面共用，2026-10-27）
	for wid: StringName in WeaponDefs.WEAPONS:
		var wd: Dictionary = WeaponDefs.WEAPONS[wid]
		var moves: Array = [wd.special]
		for kind: String in ["attack", "dual_attack"]:   # 盾沒有左鍵；匕首多一招雙持
			if wd.has(kind):
				moves.append(wd[kind])
		for alt: Dictionary in [wd.get("stance", {}), wd.get("grab", {})]:
			for kind: String in ["attack", "special"]:   # 火把舉著時只換左鍵
				if alt.has(kind):
					moves.append(alt[kind])
		if wd.special.has("parry"):
			moves.append(wd.special.parry)
		if wd.has("slot_skill"):   # 武器帶的技能欄技能（插火把）也在選角畫面顯示
			var item: Dictionary = ItemDefs.ITEMS[wd.slot_skill]   # 名稱與說明在物品資料（技能是 kind skill 的條目）
			moves.append(SkillDefs.SKILLS[wd.slot_skill].merged({"name": item.name, "desc": item.desc}))
		for m: Dictionary in moves:
			if not SkillIcons.has(m.get("icon", "")) or m.get("desc", "") == "":
				return "%s「%s」要有畫好的圖示（SkillIcons.DRAWN）與說明 desc：%s / %s" % [wd.name, m.name, m.get("icon", ""), m.get("desc", "")]
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
	var burst_dmg := WeaponDefs.move_base_damage(WeaponDefs.WEAPONS[&"staff"], s)
	if _damage_amounts(events, near.id) != [burst_dmg]:
		return "範圍內目標受到 %s，預期 [%.1f]" % [_damage_amounts(events, near.id), burst_dmg]
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
	var a: Dictionary = WeaponDefs.WEAPONS[&"longsword"].attack
	var swing_time: float = a.windup + a.active + a.recovery
	for r: StringName in [&"white", &"green"]:
		var got := WeaponDropDefs.base_stats({"base": &"longsword", "rarity": r})
		var m: Dictionary = WeaponDropDefs.RARITY_BASE[r]
		var want := [WeaponDefs.move_base_damage(WeaponDefs.WEAPONS[&"longsword"], a) * m.damage, m.attack_speed / swing_time, a.range * m.range]
		if absf(got.damage - want[0]) > EPS or absf(got.attack_speed - want[1]) > 0.01 or absf(got.range - want[2]) > EPS:
			return "%s 劍盾應為 %.2f / %.2f / %.2f，實際 %.2f / %.2f / %.2f" % [r, want[0], want[1], want[2], got.damage, got.attack_speed, got.range]
	var green: Dictionary = WeaponDropDefs.RARITY_BASE[&"green"]
	var w := _new_world()
	var p := _player(w)
	p.weapon_slots[0] = {"uid": &"g", "base": &"longsword", "rarity": &"green", "affixes": [] as Array[StringName]}
	p.apply_active_weapon()
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
	var want_stop: float = WeaponDefs.WEAPONS[&"longsword"].attack.hit_stop
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


# 招式傷害 = 基礎傷害 × 招式 % × 攻擊力 × 物理 / 屬性傷害；護甲只擋物理、所有抗性只擋物理以外、各屬性看自己的抗性
# （上下限、秘術只吃一半正抗性）；怪物照 EnemyDefs 的 resists；閃避整下閃掉；尋寶加權
static func check_damage_types() -> String:
	for id: StringName in WeaponDefs.WEAPONS:
		var wd: Dictionary = WeaponDefs.WEAPONS[id]
		if wd.hands == &"off":   # 只能當副手（盾）：招式傷害用主手的基礎傷害
			continue
		if wd.get("base_damage", 0.0) <= 0.0 or not StatDefs.DAMAGE_TYPES.has(wd.get("damage_type", &"")):
			return "%s 要有 base_damage > 0 與 StatDefs.DAMAGE_TYPES 裡的 damage_type" % id
		for kind in ["attack", "special"]:
			if wd[kind].has("damage"):
				return "%s.%s 還留著固定 damage，應改成 damage_pct" % [id, kind]
	for type: StringName in StatDefs.DAMAGE_TYPES:
		if not StatDefs.STATS.has(StatDefs.DAMAGE_TYPES[type].resist):
			return "%s 的抗性屬性 %s 不在 StatDefs.STATS" % [type, StatDefs.DAMAGE_TYPES[type].resist]
	for id: StringName in EnemyDefs.ENEMIES:
		for r: Dictionary in [EnemyDefs.ENEMIES[id].get("resists", {}), EnemyDefs.ENEMIES[id].get("wolf", {}).get("resists", {})]:
			for type: StringName in r:
				if not StatDefs.DAMAGE_TYPES.has(type) or r[type] < StatDefs.RESIST_MIN or r[type] > StatDefs.RESIST_MAX:
					return "%s 的抗性 %s = %.2f 不是合法的屬性或超出範圍" % [id, type, r[type]]
	# 物理 / 屬性傷害只乘對應類型的武器
	var w := _new_world()
	var p := _player(w)
	p.set_stat_source(&"test", [[&"phys_damage", Stats.PCT, 0.5], [&"elem_damage", Stats.PCT, 1.0]])
	var sword: Dictionary = WeaponDefs.WEAPONS[&"longsword"]
	var staff: Dictionary = WeaponDefs.WEAPONS[&"staff"]
	if absf(p.move_damage(sword.attack) - WeaponDefs.move_base_damage(sword, sword.attack) * 1.5) > EPS:
		return "物理傷害 +50%%：劍盾普攻應 ×1.5，實際 %.2f" % p.move_damage(sword.attack)
	p.equip_weapon(&"staff")
	if absf(p.move_damage(staff.attack) - WeaponDefs.move_base_damage(staff, staff.attack) * 2.0) > EPS:
		return "屬性傷害 +100%%：法杖（秘術）普攻應 ×2，實際 %.2f" % p.move_damage(staff.attack)
	# 護甲 100 只擋物理；所有抗性 50% 只擋物理以外
	var t := _dummy(w, Vector2(0, 3))
	var hurt := func(type: StringName) -> float: return t.take_damage(10.0, Vector2.UP, 0.0, p.id, type)
	t.set_stat_source(&"test", [[&"armor", Stats.ADD, 100.0]])
	var phys: float = hurt.call(&"phys")
	var fire: float = hurt.call(&"fire")
	t.set_stat_source(&"test", [[&"resist_all", Stats.ADD, 0.5]])
	var phys2: float = hurt.call(&"phys")
	var cold: float = hurt.call(&"cold")
	if absf(phys - 5.0) > EPS or absf(fire - 10.0) > EPS or absf(phys2 - 10.0) > EPS or absf(cold - 5.0) > EPS:
		return "護甲 100：物理 10 → 5、火焰不擋；所有抗性 50%%：物理不擋、冰霜 10 → 5。實際 %.2f / %.2f / %.2f / %.2f" % [phys, fire, phys2, cold]
	# 抗性上下限 −50% ~ 75%；秘術只吃一半正抗性、弱點照算
	t.set_stat_source(&"test", [[&"resist_fire", Stats.ADD, 0.9], [&"resist_holy", Stats.ADD, -0.8], [&"resist_arcane", Stats.ADD, 0.6]])
	var capped: float = hurt.call(&"fire")
	var weak: float = hurt.call(&"holy")
	var arcane: float = hurt.call(&"arcane")
	t.set_stat_source(&"test", [[&"resist_arcane", Stats.ADD, -0.4]])
	var arcane_weak: float = hurt.call(&"arcane")
	if absf(capped - 2.5) > EPS or absf(weak - 15.0) > EPS or absf(arcane - 7.0) > EPS or absf(arcane_weak - 14.0) > EPS:
		return "火焰抗性 90%% 封頂 75%% → 2.5、神聖 −80%% 封底 −50%% → 15、秘術抗性 60%% 只算一半 → 7、秘術弱點 −40%% → 14。實際 %.2f / %.2f / %.2f / %.2f" % [capped, weak, arcane, arcane_weak]
	t.remove_stat_source(&"test")
	# 怪物照 EnemyDefs 的 resists：腐屍怕火（10 → 12.5）、抗腐毒（10 → 5）
	var z := _spawn(w, &"zombie", Vector2(4, 4))
	var zr: Dictionary = EnemyDefs.ENEMIES.zombie.resists
	var zf := z.stats.value(&"resist_fire")
	var zp := z.stats.value(&"resist_poison")
	if absf(zf - zr.fire) > EPS or absf(zp - zr.poison) > EPS:
		return "腐屍的火焰 / 腐毒抗性 %.2f / %.2f，預期 %.2f / %.2f" % [zf, zp, zr.fire, zr.poison]
	# 閃避率 0 不擲骰（不消耗 world.rng）
	var state := w.rng.state
	Combat.apply_damage(w, p, t, {"damage": 1.0})
	if w.rng.state != state:
		return "閃避率 0 時不應消耗 world.rng"
	# 閃避率上限 75%：閃掉的那幾下不扣血、發 entity:dodged
	t.set_stat_source(&"test", [[&"dodge", Stats.ADD, 2.0]])
	var dodge := t.stats.value(&"dodge")
	var dodged := 0
	var hp0 := t.hp
	var n := 400
	w.events.clear()
	for i in n:
		Combat.apply_damage(w, p, t, {"damage": 1.0})
	dodged = _named(w.events, "entity:dodged").size()
	var hits := _named(w.events, "entity:damaged").size()
	_note("閃避率 %.2f：%d 下閃掉 %d" % [dodge, n, dodged])
	if absf(dodge - 0.75) > EPS or dodged + hits != n or absf((hp0 - t.hp) - hits) > EPS or absf(float(dodged) / n - dodge) > 0.07:
		return "閃避率應封頂 75%%（%.2f）；%d 下閃掉 %d、命中 %d、扣血 %.1f" % [dodge, n, dodged, hits, hp0 - t.hp]
	# 尋寶：最低一級以外的權重 × (1 + 尋寶)；0 時原樣
	var base := {&"white": 70.0, &"green": 25.0, &"blue": 5.0}
	var got := LootDefs.treasure_weights(base, 1.0)
	if got != {&"white": 70.0, &"green": 50.0, &"blue": 10.0} or LootDefs.treasure_weights(base, 0.0) != base:
		return "尋寶 100%% 權重應為白 70 / 綠 50 / 藍 10，實際 %s" % got
	return ""


# 每把武器都有道具資料（才會掉落、進背包）、模型（主手 DarkFantasy.weapon、能當副手的 DarkFantasy.offhand）；
# 職業的起始主手、副手都存在而且拿得動（F4 起，併在 check_weapon_defs）
static func _weapon_catalog() -> String:
	for id: StringName in WeaponDefs.WEAPONS:
		if not ItemDefs.ITEMS.has(id) or ItemDefs.ITEMS[id].weapon != id:
			return "%s 沒有對應的 ItemDefs 武器資料" % id
		var wd: Dictionary = WeaponDefs.WEAPONS[id]
		var models: Array[Dictionary] = []
		if wd.hands != &"off":
			models.append(DarkFantasy.weapon(wd.model))
		if wd.hands == &"off" or wd.get("offhand", false):
			models.append(DarkFantasy.offhand(wd.model))
		for model in models:
			if model.is_empty():
				return "%s 的模型 %s 沒有在 DarkFantasy.weapon / offhand 做" % [id, wd.model]
			for key in ["main", "offhand", "left", "nock", "back"]:
				if model.get(key) != null:
					(model[key] as Node).free()
	for id: StringName in ClassDefs.CLASSES:
		var c: Dictionary = ClassDefs.CLASSES[id]
		if not WeaponDefs.WEAPONS.has(c.weapon) or not WeaponDefs.WEAPONS.has(c.get("offhand", c.weapon)) or not WeaponDefs.can_hold(c.weapon, c.get("offhand", &"")):
			return "職業 %s 的起始武器 %s ＋ %s 不存在或拿不動" % [id, c.weapon, c.get("offhand", "")]
	return ""


# 職業開局的世界（測試用）
static func _class_world(class_id: StringName) -> World:
	var w := World.new(&"test_arena")
	_worlds.append(w)
	w.spawn_packs = false
	w.player_classes[World.HOST_PEER_ID] = class_id
	w.reset(5)
	w.spawner.finished = true
	return w


# F4 短弓與盜墓遊俠：快射是箭、不擊退；散射一次 5 支平均分在 50° 內、每支 80%；遊俠移動中普攻不減速、右鍵照常減速
static func check_shortbow() -> String:
	var w := _class_world(&"ranger")
	var p := _player(w)
	var bow: Dictionary = WeaponDefs.WEAPONS[&"shortbow"]
	_run(w, _cmd(Vector2(0, 1), Vector2(0, 8), InputCmd.BTN_ATTACK), 8)
	var moving_attack := p.velocity.length()
	if w.projectiles.is_empty() or w.projectiles[0].visual != &"arrow" or w.projectiles[0].knockback_force != 0.0:
		return "快射應射出不擊退的箭：%d 支" % w.projectiles.size()
	if absf(w.projectiles[0].damage - p.move_damage(bow.attack)) > EPS or absf(p.move_damage(bow.attack) - 6.0 * 1.15) > EPS:
		return "快射傷害應 = 6 × 100%% × 物理 115%% = 6.9，實際 %.2f" % w.projectiles[0].damage
	if absf(moving_attack - p.stats.value(&"move_speed")) > 0.05:
		return "遊俠移動中普攻不減速：速度 %.2f，移速 %.2f" % [moving_attack, p.stats.value(&"move_speed")]
	var w2 := _class_world(&"ranger")
	var p2 := _player(w2)
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, 8), InputCmd.BTN_SPECIAL), 1)
	_run(w2, _cmd(Vector2(0, 1), Vector2(0, 8)), ceili((bow.special.windup + bow.special.active) / DT) + 1)
	var arrows := w2.projectiles.filter(func(pr: Projectile) -> bool: return pr.owner_id == p2.id)
	var angles: Array[float] = []
	for pr: Projectile in arrows:
		angles.append(atan2(pr.direction.x, pr.direction.y))
	angles.sort()
	if arrows.size() != bow.special.count or absf((angles.back() - angles.front()) - bow.special.fan_arc) > 0.01:
		return "散射應射出 %d 支、扇形 %.0f°：%d 支、%.1f°" % [bow.special.count, rad_to_deg(bow.special.fan_arc), arrows.size(), rad_to_deg(angles.back() - angles.front()) if angles.size() > 1 else 0.0]
	if absf(arrows[0].damage - p2.move_damage(bow.special)) > EPS:
		return "散射每支應 %.2f，實際 %.2f" % [p2.move_damage(bow.special), arrows[0].damage]
	var w3 := _class_world(&"ranger")
	_run(w3, _cmd(Vector2(0, 1), Vector2(0, 8), InputCmd.BTN_SPECIAL), 3)
	var p3 := _player(w3)
	if absf(p3.velocity.length() - p3.stats.value(&"move_speed") * bow.special.move_speed_mul) > 0.05:
		return "右鍵照常減速：速度 %.2f，應 %.2f" % [p3.velocity.length(), p3.stats.value(&"move_speed") * bow.special.move_speed_mul]
	return _quiver()


# F5 長弓：重射可擊退；右鍵按住蓄力、放開射出穿透箭（沒蓄 150%、蓄滿 400%），一直線上的敵人都打到、每隻一次
static func check_longbow() -> String:
	var bow: Dictionary = WeaponDefs.WEAPONS[&"longbow"]
	if bow.attack.knockback <= 0.0 or bow.attack.get("no_stagger", false):
		return "長弓是重型遠程，普攻要可擊退"
	var results := []
	for hold_steps: int in [0, roundi(bow.special.charge_time / DT) + 10]:
		var w := _new_world()
		var p := _player(w)
		p.equip_weapon(&"longbow")
		var dummies: Array[Entity] = []
		for z in [4.0, 6.0, 8.0]:
			dummies.append(_dummy(w, Vector2(0, z)))
		var held := InputCmd.BTN_SPECIAL | InputCmd.BTN_SPECIAL_HELD
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 8), held), 1)
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 8), InputCmd.BTN_SPECIAL_HELD), roundi(bow.special.windup / DT) + hold_steps)
		var events: Array[Dictionary] = []
		_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 8)), 40, events)
		var amounts := []
		for d in dummies:
			amounts.append(_damage_amounts(events, d.id))
		results.append(amounts)
	# 冷卻中再按住右鍵：不射（按住類也要看冷卻）
	var wc := _new_world()
	var pc := _player(wc)
	pc.equip_weapon(&"longbow")
	var hold := InputCmd.BTN_SPECIAL | InputCmd.BTN_SPECIAL_HELD
	var seen := {}   # 射出過的箭（飛完射程就會消失，所以記 id）
	var plan := [[hold, 1], [0, 20]]
	for i in 4:
		plan.append_array([[hold, 10], [0, 10]])
	for step: Array in plan:
		for j in step[1]:
			_run(wc, _cmd(Vector2.ZERO, Vector2(0, 8), step[0]), 1)
			for pr in wc.projectiles:
				seen[pr.id] = true
	if seen.size() != 1:
		return "穿透箭冷卻 %.0f 秒內再按不應再射：共射出 %d 支" % [bow.special.cooldown, seen.size()]
	var base := WeaponDefs.move_base_damage(WeaponDefs.WEAPONS[&"longbow"], bow.special)
	var tap: Array = results[0]
	var full: Array = results[1]
	var want_full: float = base * bow.special.full_damage_pct / bow.special.damage_pct
	for i in 3:
		if tap[i].size() != 1 or absf(tap[i][0] - base) > EPS or full[i].size() != 1 or absf(full[i][0] - want_full) > EPS:
			return "穿透箭：沒蓄力每隻應 [%.1f]、蓄滿 [%.1f]（一直線 3 隻都打到一次）；實際 %s / %s" % [base, want_full, tap, full]
	return ""


# 長劍與主手 / 副手（Build 改版）：拿得動的組合（WeaponDefs.can_hold）；長劍沒有副手時右鍵蓄力突刺，
# 沒蓄 / 蓄滿各往前衝 dash / full_dash、打到的怪各一次 damage_pct / full_damage_pct；守墓騎士開局長劍＋木盾（右鍵格擋）
static func check_longsword() -> String:
	for c: Array in [[&"longsword", &"woodShield", true], [&"longsword", &"dagger", true], [&"dagger", &"dagger", true], [&"torch", &"woodShield", true],
			[&"staff", &"woodShield", false], [&"woodShield", &"", false], [&"longsword", &"staff", false], [&"longsword", &"longsword", false]]:
		if WeaponDefs.can_hold(c[0], c[1]) != c[2]:
			return "can_hold(%s, %s) 應為 %s" % c
	var sd: Dictionary = WeaponDefs.WEAPONS.longsword.special
	var base := WeaponDefs.move_base_damage(WeaponDefs.WEAPONS.longsword, sd)
	var held := InputCmd.BTN_SPECIAL | InputCmd.BTN_SPECIAL_HELD
	for full: bool in [false, true]:
		var hold_steps := roundi(sd.windup / DT) + (roundi(sd.charge_time / DT) + 5 if full else 0)
		# 衝刺距離（前面沒有東西擋）
		var w := _new_world()
		var p := _player(w)
		p.loadout.equip_offhand_new(p, &"")
		if p.weapon.special != sd:
			return "長劍沒有副手時右鍵應是蓄力突刺：%s" % p.weapon_id
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 20), held), 1)
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 20), InputCmd.BTN_SPECIAL_HELD), hold_steps)
		var start := p.pos
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 20)), 60)
		var moved := p.pos.distance_to(start)
		var want_dist: float = sd.full_dash if full else sd.dash
		_note("蓄力突刺（%s）衝 %.2f 單位" % ["蓄滿" if full else "沒蓄", moved])
		if absf(moved - want_dist) > 0.3 or p.pos.x > 0.05 or p.pos.y < start.y:
			return "蓄力突刺%s應往準星方向衝 %.1f，實際 %.2f（%s → %s）" % ["蓄滿" if full else "沒蓄", want_dist, moved, start, p.pos]
		# 傷害：面前的怪打一次
		var w2 := _new_world()
		var p2 := _player(w2)
		p2.loadout.equip_offhand_new(p2, &"")
		var target := _dummy(w2, Vector2(0, 1.4))
		_run(w2, _cmd(Vector2.ZERO, Vector2(0, 20), held), 1)
		_run(w2, _cmd(Vector2.ZERO, Vector2(0, 20), InputCmd.BTN_SPECIAL_HELD), hold_steps)
		var events: Array[Dictionary] = []
		_run_collect(w2, _cmd(Vector2.ZERO, Vector2(0, 20)), 40, events)
		var got := _damage_amounts(events, target.id)
		var want: float = base * (sd.full_damage_pct / sd.damage_pct if full else 1.0)
		# 沒蓄：前搖結束到放開之間可能多蓄 1 步，容許 1 步的蓄力量
		var tol: float = EPS if full else base * (sd.full_damage_pct / sd.damage_pct - 1.0) * DT / sd.charge_time + EPS
		if got.size() != 1 or got[0] < want - EPS or got[0] > want + tol:
			return "蓄力突刺%s應打面前的怪一次 %.1f，實際 %s" % ["蓄滿" if full else "沒蓄", want, got]
	# 守墓騎士開局長劍＋木盾：左鍵斬擊、右鍵格擋
	var pk := _player(_class_world(&"guardian"))
	if pk.weapon_id != &"longsword+woodShield" or pk.weapon.special.behavior != &"shieldBlock":
		return "守墓騎士開局應是長劍＋木盾（右鍵格擋），實際 %s" % pk.weapon_id
	return ""


# 主手、副手都拿匕首（雙持）
static func _equip_dual(p: Player) -> void:
	p.equip_weapon(&"dagger")
	p.loadout.equip_offhand_new(p, &"dagger")


# F6 匕首與竊影者：雙持五連刺第 5 下 150% 必爆擊、只有第 5 下擊退；單拿三連刺第 3 下 120% 且只有它擊退；
# 影步瞬移到怪背後背刺 300% 必爆擊，沒有怪不瞬移、冷卻 1 秒；竊影者開局雙持、翻滾次數 2、翻滾後攻速 +30%
static func check_daggers() -> String:
	var dg: Dictionary = WeaponDefs.def_of(&"dagger+dagger")
	if dg.attack != WeaponDefs.WEAPONS.dagger.dual_attack or dg.special != WeaponDefs.WEAPONS.dagger.special:
		return "雙持匕首應是左鍵五連刺、右鍵影步"
	var w := _new_world()
	var p := _player(w)
	_equip_dual(p)
	var dummy := _dummy(w, Vector2(0, 1.2))
	var events: Array[Dictionary] = []
	var hit_steps: Array[int] = []
	for step in 200:
		_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1, events)
		for e in w.events:
			if e.name == "entity:damaged" and e.target_id == dummy.id:
				hit_steps.append(step)
	var hits := _named(events, "entity:damaged").filter(func(e: Dictionary) -> bool: return e.target_id == dummy.id)
	var base := WeaponDefs.move_base_damage(dg, dg.attack)
	if hits.size() < 6:
		return "五連刺 200 步內應打完一輪再接下一刺，實際 %d 下" % hits.size()
	# 節奏：刺刺─停─刺刺─停─重擊（間隔：一刺、一刺 + 停頓、一刺、一刺 + 停頓 + 重擊的前搖差）
	var a: Dictionary = dg.attack
	var one: float = a.windup + a.active + a.recovery
	var want_gaps := [one, one + a.beat_pause, one, one + a.beat_pause - a.windup + a.finisher_windup]
	var gaps: Array = []
	for i in 4:
		gaps.append((hit_steps[i + 1] - hit_steps[i]) * DT)
	for i in 4:   # 每下多 2 步：收招 → 待機 → 出下一刺的狀態切換（每拍一樣，不影響節奏）
		if gaps[i] - want_gaps[i] < -DT * 0.5 or gaps[i] - want_gaps[i] > DT * 2.5:
			return "五連刺的間隔應約 %s 秒（+2 步切換），實際 %s" % [want_gaps, gaps]
	var cycle: float = (hit_steps[5] - hit_steps[0]) * DT
	var dmg_cycle: float = base * 4.0 + base * a.finisher_mul * p.stats.value(&"crit_damage")
	_note("雙匕首一輪 %.2f 秒、%.2f 傷害、每秒約 %.1f（不算職業加成）" % [cycle, dmg_cycle, dmg_cycle / cycle])
	for i in 5:
		var fin := i == 4
		var want: float = base * (dg.attack.finisher_mul * p.stats.value(&"crit_damage") if fin else 1.0)
		if absf(hits[i].amount - want) > EPS or hits[i].is_crit != fin or (hits[i].knockback > 0.0) != fin:
			return "第 %d 下應 %.2f、爆擊 %s、擊退 %s：%s" % [i + 1, want, fin, fin, hits[i]]
	# 前 4 下也不讓怪受擊硬直（2026-10-27 使用者：停下後仰看起來像被擊退），只有第 5 下
	var wg := _new_world()
	var pg := _player(wg)
	_equip_dual(pg)
	var g := _spawn(wg, &"grunt", Vector2(0, 1.4))
	_run(wg, _cmd(Vector2.ZERO), roundi(EnemyDefs.ENEMIES.grunt.spawn_time / DT) + 2)
	g.stats.set_base(&"max_hp", 99999.0)
	g.hp = 99999.0
	var staggered := []
	for step in 130:
		pg.hp = pg.max_hp
		_run(wg, _cmd(Vector2.ZERO, g.pos, InputCmd.BTN_ATTACK), 1)
		for e in wg.events:
			if e.name == "entity:damaged" and e.target_id == g.id:
				staggered.append(g.fsm.current_name == &"hurt")
	if staggered.size() < 5 or staggered.slice(0, 5) != [false, false, false, false, true]:
		return "雙匕首只有第 5 下讓怪硬直：%s" % [staggered]
	# 單拿一把：三連刺，第 3 下 finisher_mul 倍且只有它擊退
	var ws := _new_world()
	var ps := _player(ws)
	ps.equip_weapon(&"dagger")
	ps.loadout.equip_offhand_new(ps, &"")
	var single: Dictionary = WeaponDefs.WEAPONS.dagger
	if ps.weapon_id != &"dagger" or ps.weapon.attack != single.attack or ps.weapon.special != single.special:
		return "單拿匕首應是左鍵三連刺、右鍵影步：%s" % ps.weapon_id
	var dummy_s := _dummy(ws, Vector2(0, 1.2))
	var ev_s: Array[Dictionary] = []
	_run_collect(ws, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 90, ev_s)
	var hits_s := _named(ev_s, "entity:damaged").filter(func(e: Dictionary) -> bool: return e.target_id == dummy_s.id)
	var base_s := WeaponDefs.move_base_damage(single, single.attack)
	if hits_s.size() < 4:
		return "三連刺 90 步內應打完一輪再接下一刺，實際 %d 下" % hits_s.size()
	for i in 3:
		var fin_s := i == 2
		var want_s: float = base_s * (single.attack.finisher_mul if fin_s else 1.0)
		if absf(hits_s[i].amount - want_s) > EPS or (hits_s[i].knockback > 0.0) != fin_s:
			return "三連刺第 %d 下應 %.2f、擊退 %s：%s" % [i + 1, want_s, fin_s, hits_s[i]]
	# 影步
	var w2 := _new_world()
	var p2 := _player(w2)
	_equip_dual(p2)
	var target := _dummy(w2, Vector2(0, 4.0))
	target.facing = 0.0   # 面向 +Z：背後在 z 較小的一側
	var ev2: Array[Dictionary] = []
	_run_collect(w2, _cmd(Vector2.ZERO, Vector2(0, 4), InputCmd.BTN_SPECIAL), 20, ev2)
	var stab := _damage_amounts(ev2, target.id)
	var want_stab := WeaponDefs.move_base_damage(dg, dg.special) * p2.stats.value(&"crit_damage")
	if p2.pos.y > target.pos.y - target.radius or p2.pos.distance_to(target.pos) > target.radius + p2.radius + 0.3 or stab != [want_stab]:
		return "影步應到怪背後貼身、背刺 [%.2f]：位置 %s、傷害 %s" % [want_stab, p2.pos, stab]
	var w3 := _new_world()
	var p3 := _player(w3)
	_equip_dual(p3)
	_run(w3, _cmd(Vector2.ZERO, Vector2(0, 4), InputCmd.BTN_SPECIAL), 2)
	if p3.pos.length() > 0.01 or absf(w3.cooldowns.remaining(p3.cd("player.special")) - dg.special.miss_cooldown) > 3 * DT:
		return "沒有怪不瞬移、冷卻 %.1f 秒：位置 %s、冷卻 %.2f" % [dg.special.miss_cooldown, p3.pos, w3.cooldowns.remaining(p3.cd("player.special"))]
	# 竊影者：翻滾 2 次、翻滾後攻速 +30%
	var w4 := _class_world(&"shadow")
	var p4 := _player(w4)
	var aspd0 := p4.stats.value(&"attack_speed")
	if p4.weapon_id != &"dagger+dagger":
		return "竊影者開局應雙持匕首，實際 %s" % p4.weapon_id
	if p4.roll_charges != 2:
		return "竊影者翻滾次數應 2，實際 %d" % p4.roll_charges
	_run(w4, _cmd(Vector2(1, 0), Vector2(0, 5), InputCmd.BTN_ROLL), 1)
	_run(w4, _cmd(Vector2.ZERO), ceili(Config.ROLL.duration / DT) + 2)
	if absf(p4.stats.value(&"attack_speed") - aspd0 * 1.3 / 1.0) > 0.02 and absf(p4.stats.value(&"attack_speed") - (aspd0 + 0.3)) > 0.02:
		return "翻滾後攻速應 +30%%：%.2f → %.2f" % [aspd0, p4.stats.value(&"attack_speed")]
	_run(w4, _cmd(Vector2.ZERO), ceili(1.5 / DT) + 2)
	if absf(p4.stats.value(&"attack_speed") - aspd0) > EPS:
		return "1.5 秒後攻速應回到 %.2f，實際 %.2f" % [aspd0, p4.stats.value(&"attack_speed")]
	return ""


# F7 驅魔權杖與驅魔神官：敲擊是魔法、可擊退；聖光圈每 0.5 秒對範圍內敵人造成持續傷害（不爆擊、不算命中）、隊友回血，4 秒後消失；
# 神官救人快 50%、救起回 50% 生命
static func check_scepter() -> String:
	var sc: Dictionary = WeaponDefs.WEAPONS[&"scepter"]
	var w := _new_world()
	var p := _player(w)
	p.equip_weapon(&"scepter")
	var near := _dummy(w, Vector2(0, 2.0))
	var far := _dummy(w, Vector2(0, sc.special.radius + 2.0))
	p.take_damage(30.0, Vector2.UP, 0.0, 0)
	var hp0 := p.hp
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, -5), InputCmd.BTN_SPECIAL), 1, events)
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, -5)), roundi((sc.special.windup + sc.special.active + sc.special.duration) / DT) + 30, events)
	var ticks := roundi(sc.special.duration / GroundZones.TICK_INTERVAL)
	var per_tick := WeaponDefs.move_base_damage(sc, sc.special) * GroundZones.TICK_INTERVAL
	var got := _damage_amounts(events, near.id)
	var crit := _named(events, "entity:damaged").any(func(e: Dictionary) -> bool: return e.is_crit)
	if got.size() != ticks or absf(got[0] - per_tick) > EPS or crit or not _damage_amounts(events, far.id).is_empty() or not w.zones.is_empty():
		return "聖光圈應對範圍內打 %d 次、每次 %.1f、不爆擊、範圍外不受傷、結束後消失：%s / 範圍外 %s / 剩 %d 個" % [ticks, per_tick, got, _damage_amounts(events, far.id), w.zones.size()]
	var healed := p.hp - hp0
	if absf(healed - minf(30.0, sc.special.heal_per_sec * sc.special.duration)) > EPS:
		return "聖光圈隊友每秒回 %.0f，4 秒應回 %.0f，實際 %.1f" % [sc.special.heal_per_sec, sc.special.heal_per_sec * sc.special.duration, healed]
	# 敲擊：魔法、可擊退；兩段「敲─砸」：第 2 下扇形 130% + 前方一圈 60%（同一隻兩邊都打到）
	var w2 := _new_world()
	var p2 := _player(w2)
	p2.equip_weapon(&"scepter")
	var t2 := _dummy(w2, Vector2(0, 1.5))
	t2.set_stat_source(&"test", [[&"armor", Stats.ADD, 1000.0]])   # 護甲不擋魔法
	var side := _dummy(w2, Vector2(2.0, 2.6))   # 第 2 下往前衝後也在扇形內，但會被砸出的圈多打一次
	var ev2: Array[Dictionary] = []
	_run_collect(w2, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 75, ev2)
	var h2 := _named(ev2, "entity:damaged").filter(func(e: Dictionary) -> bool: return e.target_id == t2.id)
	var b := WeaponDefs.move_base_damage(sc, sc.attack)
	var want2 := [b, b * sc.attack.finisher_mul, sc.base_damage * sc.attack.finisher_burst.damage_pct]
	var got2 := h2.map(func(e: Dictionary) -> float: return e.amount)
	if got2.size() < 3 or absf(got2[0] - want2[0]) > EPS or absf(got2[1] - want2[1]) > EPS or absf(got2[2] - want2[2]) > EPS or h2[0].knockback <= 0.0:
		return "聖光敲擊（魔法，護甲不擋）應依序 %s、可擊退：%s" % [want2, got2]
	if not _damage_amounts(ev2, side.id).has(want2[2]):
		return "第 2 下砸出的圈應打到旁邊的怪（%.1f）：%s" % [want2[2], _damage_amounts(ev2, side.id)]
	# 神官救人
	var w3 := World.new(&"test_arena")
	_worlds.append(w3)
	w3.player_classes = {1: &"priest"}
	w3.reset(9, [1, 2] as Array[int])
	w3.spawner.finished = true
	var priest: Player = w3.players[1]
	var down: Player = w3.players[2]
	priest.pos = Vector2.ZERO
	down.pos = Vector2(0, 1.0)
	down.take_damage(1000.0, Vector2(1, 0), 0.0, 0)
	var steps := 0
	while down.is_downed and steps < 600:
		w3.step({1: _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_INTERACT), 2: _cmd(Vector2.ZERO)}, DT)
		steps += 1
	var want_steps: float = Config.REVIVE.revive_time / 1.5 / DT
	if down.is_downed or absf(steps - want_steps) > 3 or absf(down.hp - roundf(down.max_hp * 0.5)) > EPS:
		return "神官救人約 %.0f 步、救起 50%% 生命：%d 步、倒地 %s、血 %.0f / %.0f" % [want_steps, steps, down.is_downed, down.hp, down.max_hp]
	return ""


# F8 火把與火把傭兵（2026-10-27 改）：按住右鍵舉火把（移速 ×0.6）、放開放下；舉著時左鍵噴火（120% + 點燃、冷卻 6 秒，冷卻中不出招）；
# 插火把出廠鑲在火把的寶石座、是數字鍵 1（冷卻 1 秒、次數 3 記在武器上、換層補滿）；翻滾取消；插著與舉著的火把照亮的範圍不管視野扇形都看得到；
# 揮擊點燃；傭兵視野 +3、身邊 6
static func check_torch() -> String:
	var tw: Dictionary = WeaponDefs.WEAPONS[&"torch"]
	var plant: Dictionary = SkillDefs.SKILLS[tw.slot_skill]
	var held := InputCmd.BTN_SPECIAL_HELD
	var w := _new_world()
	var p := _player(w)
	p.equip_weapon(&"torch")
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL | held), 1)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), held), 20)
	if not p.torch_stance or not p.anim.get("torch_stance", false):
		return "按住右鍵應舉起火把"
	_run(w, _cmd(Vector2(1, 0), Vector2(0, 5), held), 3)
	if absf(p.velocity.length() - p.stats.value(&"move_speed") * tw.stance.move_speed_mul) > 0.05:
		return "舉著火把移速應 ×%.1f：%.2f" % [tw.stance.move_speed_mul, p.velocity.length()]
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5)), 1)
	if p.torch_stance:
		return "放開右鍵應放下火把"
	# 噴火：舉著時左鍵，前方的怪受到 120% 魔法；冷卻中再按不出招
	var front := _dummy(w, Vector2(0, 3))
	var events: Array[Dictionary] = []
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL | held), 1)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), held), 20)
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), held | InputCmd.BTN_ATTACK), 30, events)
	var got := _damage_amounts(events, front.id)
	if got.size() != 1 or absf(got[0] - WeaponDefs.move_base_damage(tw, tw.stance.attack)) > EPS:
		return "舉著火把左鍵噴火應打中前方一次 %.1f（按住 0.5 秒、冷卻 6 秒）：%s" % [WeaponDefs.move_base_damage(tw, tw.stance.attack), got]
	if not p.torch_stance or w.cooldowns.is_ready(p.cd(tw.stance.attack.cd_key)) or not w.cooldowns.is_ready(p.cd("player.special")):
		return "噴火後應還舉著火把、冷卻算在 %s（不占右鍵）" % tw.stance.attack.cd_key
	events.clear()
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), held), 20)   # 等噴火收招
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), held | InputCmd.BTN_ATTACK), 1, events)
	if _named(events, "skill:onCooldown").is_empty() or not p.action.is_in(&"ready"):
		return "噴火冷卻中按左鍵應提示、不出招：%s" % p.action.current_name
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5)), 1)
	# 插火把：火把出廠就鑲在寶石座、是數字鍵 1；背後 10 單位的怪本來看不到，火把插在它旁邊後看得到
	var idx := 0
	var first: Variant = p.slots.get_slot(p, idx)
	if first == null or first.id != tw.slot_skill:
		return "插火把應鑲在火把的寶石座、是數字鍵 1：%s" % [first]
	var behind := _dummy(w, Vector2(0, -10))
	if Vision.point_visible(w, p, behind.pos):
		return "背後的怪本來應看不到"
	p.pos = Vector2(0, -6)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.slot_bit(idx)), 1)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5)), 20)
	if w.torches.size() != 1 or WeaponDropDefs.slot_charges(p.active_weapon()) != plant.charges - 1:
		return "按技能欄應插 1 支火把：%d 支、武器上剩 %d" % [w.torches.size(), WeaponDropDefs.slot_charges(p.active_weapon())]
	p.pos = Vector2.ZERO
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5)), 1)
	if not Vision.point_visible(w, p, behind.pos):
		return "火把旁邊的怪不管視野都應看得到"
	for i in 6:   # 再按 6 次：冷卻 1 秒、最多 3 次
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.slot_bit(idx)), 1)
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 5)), 70)
	if w.torches.size() != plant.charges or WeaponDropDefs.slot_charges(p.active_weapon()) != 0:
		return "插火把最多 %d 次：%d 支、剩 %d" % [plant.charges, w.torches.size(), WeaponDropDefs.slot_charges(p.active_weapon())]
	# 次數跟著武器：快照來回後還在；換一把新的火把是滿的；換層補滿
	var used := p.active_weapon()
	if WeaponDropDefs.slot_charges(WeaponDropDefs.from_array(WeaponDropDefs.to_array(used))) != 0:
		return "插火把次數應跟著武器實例同步"
	p.loadout.refill_slot_charges()
	if WeaponDropDefs.slot_charges(used) != plant.charges:
		return "換層應補滿插火把次數：%d" % WeaponDropDefs.slot_charges(used)
	# 翻滾取消舉火把（就算右鍵還按著）
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL | held), 1)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), held), 20)
	_run(w, _cmd(Vector2(1, 0), Vector2(0, 5), held | InputCmd.BTN_ROLL), 2)
	if p.torch_stance:
		return "翻滾應放下火把"
	# 揮擊點燃（燃燒是 Enemy 的狀態：用真的骷髏）
	var w2 := _new_world()
	var p2 := _player(w2)
	p2.equip_weapon(&"torch")
	var g := _spawn(w2, &"grunt", Vector2(0, 1.5))
	g.stats.set_base(&"max_hp", 1000.0)
	g.hp = 1000.0
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 15)
	if g.burn_timer <= 0.0:
		return "火把揮擊應點燃打中的怪"
	# 傭兵視野
	var w3 := _class_world(&"mercenary")
	var m := _player(w3)
	if absf(Vision.view_range(m) - (Config.VISION.range + 3.0)) > EPS or absf(Vision.near_radius(m) - 6.0) > EPS:
		return "火把傭兵視野應 %.0f、身邊 6：%.1f / %.1f" % [Config.VISION.range + 3.0, Vision.view_range(m), Vision.near_radius(m)]
	return ""


# F9 鐵鏟與掘墓人：鏟地窄而遠、可擊退；鏟起面前的怪舉 2 秒（不能跳、翻滾，移速 ×0.7），左鍵拋出（落地 200%、路上 150%）、
# 右鍵埋入（80%、2 秒不能動）、沒按就掙脫；Boss 抓不起來、沒抓到冷卻 2 秒；掘墓人挖墳 +40%、挖墳中受傷 −25%
static func check_shovel() -> String:
	var sv: Dictionary = WeaponDefs.WEAPONS[&"shovel"]
	var results := {}
	for mode: StringName in [&"throw", &"bury", &"free"]:
		var w := _new_world()
		var p := _player(w)
		p.equip_weapon(&"shovel")
		var g := _spawn(w, &"grunt", Vector2(0, 1.4))
		g.stats.set_base(&"max_hp", 1000.0)
		g.hp = 1000.0
		var other := _dummy(w, Vector2(0, 5.0))
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 8), InputCmd.BTN_SPECIAL), 1)
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 8)), 20)
		if p.held_enemy_id != g.id or g.grabbed_by != p.id:
			return "鏟起應抓住面前的骷髏：舉著 %d、骷髏 %d" % [p.held_enemy_id, g.id]
		if mode == &"throw":
			_run(w, _cmd(Vector2(1, 0), Vector2(0, 8)), 3)
			if absf(p.velocity.length() - p.stats.value(&"move_speed") * sv.grab.move_speed_mul) > 0.05 or p.try_jump():
				return "舉著怪移速 ×0.7、不能跳：%.2f" % p.velocity.length()
			var hp_g := g.hp
			var hp_o := other.hp
			var ta: Dictionary = sv.grab.attack
			_run(w, _cmd(Vector2.ZERO, Vector2(0, 8), InputCmd.BTN_ATTACK), 1)
			# 飛行一半：還在空中、離地、還沒到落點、沒受落地傷害（拋出有飛行過程，不是瞬移）
			_run(w, _cmd(Vector2.ZERO, Vector2(0, 8)), roundi((ta.windup + ta.active + ta.flight_time * 0.5) / DT))
			if not g.is_launching() or g.height - g.ground_height < 0.3 or g.pos.y > 7.0 or absf(hp_g - g.hp) > EPS:
				return "拋出飛到一半應還在空中（%.1f 秒飛完）：飛行中 %s、離地 %.2f、z %.2f、扣血 %.1f" % [ta.flight_time, g.is_launching(), g.height - g.ground_height, g.pos.y, hp_g - g.hp]
			_run(w, _cmd(Vector2.ZERO, Vector2(0, 8)), roundi(ta.flight_time * 0.5 / DT) + 20)
			results[mode] = [hp_g - g.hp, hp_o - other.hp, g.pos.y, p.held_enemy_id]
		elif mode == &"bury":
			var hp_g := g.hp
			_run(w, _cmd(Vector2.ZERO, Vector2(0, 8), InputCmd.BTN_SPECIAL), 1)
			_run(w, _cmd(Vector2.ZERO, Vector2(0, 8)), 20)
			results[mode] = [hp_g - g.hp, g.buried_timer, p.held_enemy_id]
			# 埋著打得到、但不會被擊退（2026-10-27 使用者）
			var hp_b := g.hp
			var at := g.pos
			Combat.apply_damage(w, p, g, {"damage": 5.0, "knockback": 20.0})
			_run(w, _cmd(Vector2.ZERO, Vector2(0, 8)), 5)
			if absf((hp_b - g.hp) - 5.0) > EPS or g.pos.distance_to(at) > 0.05:
				return "埋著的怪應打得到（扣 5）、不被擊退：扣 %.2f、移動 %.2f" % [hp_b - g.hp, g.pos.distance_to(at)]
		else:
			_run(w, _cmd(Vector2.ZERO, Vector2(0, 8)), roundi(sv.special.hold_time / DT) + 2)
			results[mode] = [p.held_enemy_id, g.grabbed_by]
	var base := 12.0
	var th: Array = results[&"throw"]
	if absf(th[0] - base * sv.grab.attack.damage_pct) > EPS or absf(th[1] - base * sv.grab.attack.path_damage_pct) > EPS or th[2] < 5.0 or th[3] != 0:
		return "拋出：被丟的 %.0f、路上的 %.0f、飛到 z ≥ 5、手上放開：%s" % [base * sv.grab.attack.damage_pct, base * sv.grab.attack.path_damage_pct, th]
	var bu: Array = results[&"bury"]
	var bury_time: float = sv.grab.special.stun + sv.grab.special.crawl
	if absf(bu[0] - base * sv.grab.special.damage_pct) > EPS or bu[1] <= 0.0 or bu[1] > bury_time or bu[2] != 0:
		return "埋入：%.1f 傷害、埋 %.1f 秒、手上放開：%s" % [base * sv.grab.special.damage_pct, bury_time, bu]
	if results[&"free"] != [0, 0]:
		return "2 秒沒按應掙脫：%s" % [results[&"free"]]
	# Boss 抓不起來、沒抓到冷卻 2 秒
	var w2 := _new_world()
	var p2 := _player(w2)
	p2.equip_weapon(&"shovel")
	_spawn(w2, &"boss", Vector2(0, 2.5))
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, 8), InputCmd.BTN_SPECIAL), 1)
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, 8)), 12)
	if p2.held_enemy_id != 0 or w2.cooldowns.remaining(p2.cd("player.special")) > sv.special.miss_cooldown:
		return "Boss 抓不起來、沒抓到冷卻 %.0f 秒：舉著 %d、冷卻 %.2f" % [sv.special.miss_cooldown, p2.held_enemy_id, w2.cooldowns.remaining(p2.cd("player.special"))]
	# 掘墓人：挖墳中受傷 −25%
	var w3 := _class_world(&"gravedigger")
	var gd := _player(w3)
	var dummy := _dummy(w3, Vector2(0, 3))
	gd.action.change(&"dig")
	var before := gd.hp
	Combat.apply_damage(w3, dummy, gd, {"damage": 20.0})
	var want: float = 20.0 * 0.75 * StatDefs.armor_damage_factor(gd.stats.value(&"armor"))
	if absf((before - gd.hp) - want) > EPS:
		return "掘墓人挖墳中受到 20 應扣 %.2f（−25%% 再算護甲），實際 %.2f" % [want, before - gd.hp]
	return ""


# 短弓箭袋：6 支，最後一支是重箭（多拉弓、200%、擊退）；射空自動裝填 1.2 秒（不能射、移速 ×0.5）；翻滾瞬間補滿（併在 check_shortbow）
static func _quiver() -> String:
	var atk: Dictionary = WeaponDefs.WEAPONS[&"shortbow"].attack
	var w := _new_world()
	var p := _player(w)
	p.equip_weapon(&"shortbow")
	var dummy := _dummy(w, Vector2(0, 4))
	var events: Array[Dictionary] = []
	var steps := 0
	while p.quiver > 0 and steps < 300:
		_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 8), InputCmd.BTN_ATTACK), 1, events)
		steps += 1
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 8)), 15, events)
	var dmg := _damage_amounts(events, dummy.id)
	var base := WeaponDefs.move_base_damage(WeaponDefs.WEAPONS[&"shortbow"], atk)
	var heavy: float = base * atk.heavy_last.damage_pct
	if dmg.size() != atk.quiver or absf(dmg.back() - heavy) > EPS or absf(dmg[0] - base) > EPS:
		return "箭袋 %d 支、最後一支 %.1f：%s" % [atk.quiver, heavy, dmg]
	var kb := _named(events, "entity:damaged").filter(func(e: Dictionary) -> bool: return e.target_id == dummy.id)
	if kb.back().knockback <= 0.0 or kb[0].knockback != 0.0:
		return "只有重箭擊退：%s / %s" % [kb[0].knockback, kb.back().knockback]
	# 裝填中：按住也不射、移速 ×0.5
	var before := w.projectiles.size()
	_run(w, _cmd(Vector2(1, 0), Vector2(0, 8), InputCmd.BTN_ATTACK), 10)
	if p.reload_timer <= 0.0 or w.projectiles.size() > before or absf(p.velocity.length() - p.stats.value(&"move_speed") * atk.reload_move_mul) > 0.05:
		return "裝填中不能射、移速 ×%.1f：裝填 %.2f、速度 %.2f" % [atk.reload_move_mul, p.reload_timer, p.velocity.length()]
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 8)), ceili(atk.reload_time / DT) + 1)
	if p.quiver != atk.quiver or p.reload_timer > 0.0:
		return "裝填 %.1f 秒後應補滿：剩 %d、裝填 %.2f" % [atk.reload_time, p.quiver, p.reload_timer]
	# 翻滾瞬間補滿
	p.quiver = 1
	p.reload_timer = 0.0
	_run(w, _cmd(Vector2(1, 0), Vector2(0, 8), InputCmd.BTN_ROLL), 2)
	if p.quiver != atk.quiver:
		return "翻滾應瞬間補滿箭袋：剩 %d" % p.quiver
	return ""



# 武器測試場景（--weapon-test）的木樁：爬出後站著不動、不打人；鐵鏟抓得起來、埋得下去，埋完回到站著
static func check_training_dummies() -> String:
	var w := _new_world()
	var p := _player(w)
	var dummies := Spawner.spawn_training_dummies(w, p.pos)
	var start := dummies.map(func(e: Enemy) -> Vector2: return e.pos)
	var hp0 := p.hp
	_run(w, _cmd(Vector2.ZERO), 240)
	for i in dummies.size():
		var e: Enemy = dummies[i]
		if e.pos.distance_to(start[i]) > 0.05 or not e.fsm.is_in(&"train"):
			return "木樁 %d 應站著不動（狀態 train）：移動 %.2f、狀態 %s" % [i, e.pos.distance_to(start[i]), e.fsm.current_name]
	if p.hp != hp0:
		return "木樁不應打人：玩家血 %.0f → %.0f" % [hp0, p.hp]
	# 鐵鏟：朝貼身那隻抓起、埋入，埋完回到 train
	p.equip_weapon(&"shovel")
	var near: Enemy = dummies[0]
	var aim := p.pos + (near.pos - p.pos) * 3.0
	_run(w, _cmd(Vector2.ZERO, aim, InputCmd.BTN_SPECIAL), 1)
	_run(w, _cmd(Vector2.ZERO, aim), 20)
	if p.held_enemy_id != near.id:
		return "鐵鏟應抓起貼身的木樁：舉著 %d、木樁 %d" % [p.held_enemy_id, near.id]
	_run(w, _cmd(Vector2.ZERO, aim, InputCmd.BTN_SPECIAL), 1)
	_run(w, _cmd(Vector2.ZERO, aim), 20)
	if near.buried_timer <= 0.0 or near.grabbed_by != 0:
		return "右鍵應把木樁埋下去：埋 %.2f 秒、被舉 %d" % [near.buried_timer, near.grabbed_by]
	_run(w, _cmd(Vector2.ZERO, aim), 180)
	if near.buried_timer > 0.0 or not near.fsm.is_in(&"train"):
		return "埋完應回到站著：埋 %.2f、狀態 %s" % [near.buried_timer, near.fsm.current_name]
	return ""
