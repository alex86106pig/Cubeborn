# 持武器腐屍的招式（怪物圖鑑備註 1）：EnemyDefs.ARMED_ZOMBIE 的普攻 / 技能，依 type 決定做法
# 追擊（chase）：技能冷卻好、條件符合就用技能，否則普攻；遠程武器（keep）保持距離，近戰直接追
# 出招（Move 狀態）：windup（前 TRACK 比例轉向目標）→ active（依 type）→ recovery；被打進受擊硬直就中斷（舉盾一起放下）
class_name ArmedMoves

const TRACK := 0.6


# 拿武器的腐屍追擊一步
static func chase(e: Zombie, target: Entity, dt: float) -> void:
	var k := e.kit()
	var dist := e.pos.distance_to(target.pos)
	if e.world.cooldowns.is_ready(e.cd("armed_skill")) and _skill_ok(e, target, dist, k.skill):
		e.fsm.change(&"armed_move", {"kind": &"skill", "move": k.skill})
		return
	if e.world.cooldowns.is_ready(e.cd("armed_attack")) and dist <= k.attack.reach and e.has_direct_path():
		e.fsm.change(&"armed_move", {"kind": &"attack", "move": k.attack})
		return
	var goal := target.pos
	if k.has("keep") and e.has_direct_path():
		var keep: Array = k.keep
		if dist >= keep[0] and dist <= keep[1]:
			e.velocity = Vector2.ZERO
			e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * dt)
			return
		if dist < keep[0]:
			goal = e.pos + (e.pos - target.pos).normalized() * 2.0   # 太近：往後退
	var aim := e.steer_point(goal)
	e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, aim), e.def.turn_speed * dt)
	e.velocity = MathUtil.dir_from_angle(e.facing) * e.speed


static func _skill_ok(e: Zombie, target: Entity, dist: float, sk: Dictionary) -> bool:
	match sk.type:
		&"heal":
			return _hurt_ally(e, sk) != null
		&"scoop":
			return dist <= sk.player_range or (dist <= sk.reach and _throwable(e, sk) != null)
		&"blink":
			return dist <= sk.reach and dist > 2.5 and e.has_direct_path()
	return dist <= sk.reach and e.has_direct_path()


# 治療光圈的對象：範圍內血量低於 below 的其他怪（不含 Boss）
static func _hurt_ally(e: Zombie, sk: Dictionary) -> Enemy:
	for o: Entity in e.world.enemies:
		if o != e and o is Enemy and not o.is_dead and not (o as Enemy).is_boss() and o.team == e.team \
				and o.pos.distance_to(e.pos) <= sk.radius and o.hp < o.max_hp * sk.below:
			return o as Enemy
	return null


# 鏟起能拋的怪：grab_range 內、站在地上、不是 Boss，膨脹屍優先
static func _throwable(e: Zombie, sk: Dictionary) -> Enemy:
	var best: Enemy = null
	for o: Entity in e.world.enemies:
		if o == e or not (o is Enemy) or o.is_dead or (o as Enemy).is_boss() or o.team != e.team or not o.is_grounded():
			continue
		var en := o as Enemy
		if en.fsm.is_in(&"launch") or en.pos.distance_to(e.pos) > sk.grab_range:
			continue
		if en is Bloater:
			return en
		if best == null:
			best = en
	return best


static func _hit(e: Zombie, move: Dictionary, pct: float, extra: Dictionary = {}) -> Dictionary:
	var h := {"damage": pct * e.def.armed_damage * e.damage_mul, "knockback": move.get("knockback", 0.0), "blockable": true,
		"damage_type": move.get("damage_type", &"phys"), "tier": move.get("tier", &"medium")}
	h.merge(extra, true)
	return h


class Move:
	func enter(e: Zombie, data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		var cd: float = data.move.cooldown if data.kind == &"attack" else EnemyDefs.armed_skill_cooldown(e.armed_weapon.base)
		e.world.cooldowns.start(e.cd("armed_" + String(data.kind)), e.cd_time(cd))
		data.phase = &"windup"
		data.phase_time = 0.0
		data.fired = 0

	func exit(e: Zombie, _fsm: StateMachine) -> void:
		e.shielding = false

	func update(e: Zombie, dt: float, fsm: StateMachine) -> void:
		var m: Dictionary = fsm.data.move
		var d := fsm.data
		d.phase_time += dt
		e.velocity = Vector2.ZERO
		var target: Entity = e.nearest_target()
		if d.phase == &"windup":
			if d.phase_time < m.windup * TRACK and target != null:
				e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * dt)
			if d.phase_time >= m.windup:
				d.phase = &"active"
				d.phase_time = 0.0
			else:
				return
		if d.phase == &"active":
			if _active(e, m, d, target, dt):
				d.phase = &"recovery"
				d.phase_time = 0.0
			return
		if d.phase_time >= m.recovery:
			fsm.change(&"chase")

	# 出招中的一步；回傳 true = 這招打完了
	func _active(e: Zombie, m: Dictionary, d: Dictionary, target: Entity, dt: float) -> bool:
		match m.type:
			&"melee":
				var interval: float = m.get("interval", 0.0)
				while d.fired < m.hits.size() and d.phase_time + 1e-6 >= d.fired * interval:
					var h: Dictionary = m.hits[d.fired]
					Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"sector", "range": h.range, "arc": h.arc},
						ArmedMoves._hit(e, m, h.damage_pct, {"tier": h.tier}))
					d.fired += 1
				return d.fired >= m.hits.size()
			&"shot":
				var interval: float = m.get("interval", 0.0)
				while d.fired < m.count and (m.has("fan_arc") or d.phase_time + 1e-6 >= d.fired * interval):
					if target != null and d.fired > 0 and not m.has("fan_arc"):
						e.facing = MathUtil.angle_to(e.pos, target.pos)   # 連射：每支重新瞄準
					var spread := 0.0
					if m.has("fan_arc") and m.count > 1:
						spread = -m.fan_arc / 2.0 + m.fan_arc * d.fired / (m.count - 1)
					ArmedMoves._shoot(e, m, e.facing + spread, target)
					d.fired += 1
				return d.fired >= m.count
			&"shield":
				e.shielding = true
				if target != null:
					e.facing = MathUtil.turn_towards(e.facing, MathUtil.angle_to(e.pos, target.pos), e.def.turn_speed * 0.5 * dt)
				if d.phase_time < m.duration:
					return false
				e.shielding = false
				var b: Dictionary = m.bash
				Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"sector", "range": b.range, "arc": b.arc},
					ArmedMoves._hit(e, b, b.damage_pct))
				return true
			&"burst":
				var h := ArmedMoves._hit(e, m, m.damage_pct, {"blockable": false, "origin": e.pos, "is_heavy": true, "color": m.color})
				Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"circle", "radius": m.radius}, h)
				e.world.emit_event("fx:explosion", {"pos": e.pos, "height": e.ground_height, "radius": m.radius, "color": m.color})
				e.world.emit_event("sfx:cue", {"cue": "explosion", "pos": e.pos})
				return true
			&"blink":
				if target != null:
					var from := e.pos
					var at := e.world.nav.nearest_walkable(target.pos - MathUtil.dir_from_angle(target.facing) * m.behind)
					e.pos = at
					e.facing = MathUtil.angle_to(e.pos, target.pos)
					e.world.emit_event("fx:boss_teleport", {"pos": from, "height": e.ground_height, "to": at})   # 黑煙：原地與目的地
				return true
			&"heal":
				for o: Entity in e.world.enemies:
					if o is Enemy and not o.is_dead and not (o as Enemy).is_boss() and o.team == e.team and o.pos.distance_to(e.pos) <= m.radius:
						o.heal(o.max_hp * m.heal_ratio)
				e.world.emit_event("fx:heal", {"pos": e.pos, "height": e.ground_height, "color": m.color})
				return true
			&"breath":
				var ticks := floori((d.phase_time + 1e-6) / m.tick) + 1
				while d.fired < ticks and d.fired * m.tick < m.duration:
					Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"sector", "range": m.range, "arc": m.arc},
						ArmedMoves._hit(e, m, m.damage_pct, {"knockback": 0.0, "pierce_invuln": true, "color": m.color}))
					e.world.emit_event("fx:slash", {"pos": e.pos, "height": e.height + 1.0, "facing": e.facing, "range": m.range, "arc": m.arc, "color": m.color, "swing_dir": 1})
					d.fired += 1
				return d.phase_time >= m.duration
			&"scoop":
				return ArmedMoves._scoop(e, m, d, target)
		return true


static func _shoot(e: Zombie, m: Dictionary, angle: float, target: Entity) -> void:
	var dir := MathUtil.dir_from_angle(angle)
	var a: float = Config.HEIGHT.arrow_altitude
	var aim := {}
	if target != null:
		aim = {"aim_altitude": e.world.terrain.ground_at(target.pos) + a, "aim_distance": e.pos.distance_to(target.pos)}
	e.world.emit_event("sfx:cue", {"cue": "arrowShot" if m.visual == &"arrow" else "fireBolt", "pos": e.pos})
	e.world.spawn_projectile(Projectile.new(e.world, aim.merged({
		"owner": e, "pos": e.pos + dir * 0.6, "direction": dir, "speed": m.speed, "range": m.range, "radius": 0.2,
		"damage": m.damage_pct * e.def.armed_damage * e.damage_mul, "knockback": m.get("knockback", 0.0), "color": m.color,
		"visual": m.visual, "altitude": e.height + a, "blockable": true, "damage_type": m.get("damage_type", &"phys"),
		"pierce": m.get("pierce", false),
	})))


# 鏟起：第一步決定拋怪還是鏟玩家；拋怪要等 flight 秒落地才結算
static func _scoop(e: Zombie, m: Dictionary, d: Dictionary, target: Entity) -> bool:
	if not d.has("plan"):
		d.plan = &"none"
		var thrown := _throwable(e, m)
		var dist := e.pos.distance_to(target.pos) if target != null else INF
		if thrown != null and target != null and dist > m.player_range:
			d.plan = &"throw"
			d.thrown_id = thrown.id
			d.land_at = target.pos
			thrown.launch_to(target.pos, m.flight)
			e.world.emit_event("fx:dirt_lob", {"pos": thrown.pos, "height": thrown.height, "targets": [target.pos], "flight": m.flight, "radius": m.land_radius, "shadow_only": true})
		elif target != null and dist <= m.player_range + target.radius:
			var bury := e.world.rng.randf() < 0.5
			var h := ArmedMoves._hit(e, m, m.damage_pct, {"blockable": false, "tier": &"none" if bury else &"knockdown"})
			for t in Hitbox.strike(e.world, e, e.pos, e.facing, {"shape": &"sector", "range": m.player_range + 0.3, "arc": PI / 3.0}, h):
				if t is Player:
					if bury:
						(t as Player).stun(m.bury)
						e.world.emit_event("player:buried", {"player_id": t.id, "duration": m.bury})
					else:
						(t as Player).knock_up(m.launch)
		return d.plan == &"none"
	if d.phase_time < m.flight:
		return false
	var o := e.world.entities.get(d.thrown_id) as Enemy
	if o is Bloater and not o.is_dead:
		o.fsm.change(&"swell", {"time": m.bloater_fuse})   # 落地很快就炸
	else:
		var at: Vector2 = o.pos if o != null else d.land_at
		var h := ArmedMoves._hit(e, m, m.land_pct, {"blockable": false, "tier": &"knockdown", "origin": at, "knockback": 6.0})
		for p: Player in e.world.player_list:
			if p.is_targetable() and p.pos.distance_to(at) <= m.land_radius + p.radius:
				Combat.apply_damage(e.world, e, p, h)
		e.world.emit_event("fx:explosion", {"pos": at, "height": e.world.terrain.ground_at(at), "radius": m.land_radius, "color": Color("6b4f2e")})
	return true
