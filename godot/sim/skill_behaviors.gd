# 技能行為：Q 的治療藥水、寶石座的技能（Build 改版第 7 步，數字在 SkillDefs）
# cast 由 ActiveSlots.use 呼叫（本機預測時也會跑）：位移（衝刺、瞬移、後跳）兩邊都做，傷害、投射物、召喚、地面區域只在權威端
# ctx（ActiveSlots.cast_context）：mul 等級的傷害倍率、area 延長的範圍倍率、type 火焰化 / 霜化後的屬性、split 分裂（0.25 秒後再放一次 60%）
# 晚一點才發生的（隕石、箭雨、連珠箭、狙擊、分裂）用 later 排進 World.delayed，只在權威端
class_name SkillBehaviors

const SPLIT_DELAY := 0.25
const SPLIT_MUL := 0.6


class Behavior:
	func can_use(_owner: Player, _def: Dictionary) -> bool:
		return true

	func activate(_owner: Player, _def: Dictionary, _ctx: Dictionary) -> void:
		pass


class Heal extends Behavior:
	func can_use(owner: Player, _def: Dictionary) -> bool:
		return owner.hp < owner.max_hp

	func activate(owner: Player, def: Dictionary, _ctx: Dictionary) -> void:
		var healed := owner.heal(def.amount)
		owner.world.emit_event("entity:healed", {"target_id": owner.id, "amount": healed})
		owner.world.emit_event("fx:heal", {"pos": owner.pos, "height": owner.height, "color": def.color})


# 插火把（F8）：插在面前，整關不熄；只有房主產生火把實體
class PlantTorch extends Behavior:
	func activate(owner: Player, _def: Dictionary, _ctx: Dictionary) -> void:
		if owner.world.is_authority:
			var t := Torch.new(owner.world, owner.pos + WeaponBehaviors.forward(owner) * 0.6, owner.id)
			owner.world.add_entity(t)
			owner.world.torches.append(t)


# 以自己為中心一圈：旋風斬、火焰新星、震盾、冰霜新星
class Nova extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var r: float = def.radius * ctx.area
		SkillBehaviors.area_hit(owner, def, ctx, owner.pos, {"shape": &"circle", "radius": r})
		owner.world.emit_event("fx:explosion", {"pos": owner.pos, "height": owner.ground_height, "radius": r, "color": def.color})


# 面前扇形：震地
class Cone extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		SkillBehaviors.face_aim(owner)
		var shape := {"shape": &"sector", "range": def.range * ctx.area, "arc": def.arc}
		SkillBehaviors.area_hit(owner, def, ctx, owner.pos, shape)
		owner.world.emit_event("fx:slash", {"pos": owner.pos, "height": owner.height, "facing": owner.facing, "range": shape.range, "arc": def.arc, "color": def.color, "swing_dir": 1})


# 往準星衝刺，衝的這段時間打面前（每隻一次）：衝鋒斬、火焰衝刺（沿路留火）、盾衝（暈眩）
class Dash extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var dir := SkillBehaviors.face_aim(owner)
		var dist: float = def.distance * ctx.area
		SkillBehaviors.push(owner, dir * dist)
		owner.skill_dash = {"left": def.time, "def": def, "ctx": ctx, "hit": {}}
		if def.has("trail") and owner.world.is_authority:
			var t: Dictionary = def.trail
			var d := 0.0
			while d <= dist:
				SkillBehaviors.fire_zone(owner, owner.pos + dir * d, t.radius, t.duration, owner.pct_damage(t.dps_pct) * ctx.mul, ctx.type)
				d += t.every


# 瞬移到範圍內最近的怪背後刺一刀（必爆擊）；附近沒有怪就不能放
class Ambush extends Behavior:
	func can_use(owner: Player, def: Dictionary) -> bool:
		return SkillBehaviors.nearest_enemy(owner, owner.pos, def.range) != null

	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var e := SkillBehaviors.nearest_enemy(owner, owner.pos, def.range * ctx.area)
		if e == null:
			return
		var back := MathUtil.dir_from_angle(e.facing)
		var from := owner.pos
		owner.pos = owner.world.nav.nearest_walkable(e.pos - back * (e.radius + owner.radius + 0.3))
		owner.facing = MathUtil.angle_to(owner.pos, e.pos)
		owner.world.emit_event("fx:boss_teleport", {"pos": from, "height": owner.ground_height, "to": owner.pos})
		var hit := SkillBehaviors.hit_of(owner, def, ctx)
		hit["force_crit"] = true
		Combat.apply_damage(owner.world, owner, e, hit)


# 射出投射物：count 支、扇形 spread；interval > 0 是一支一支連射；windup > 0 先蓄力
# 投射物結束時的效果（chain 跳電、burst 炸開疊冰冷 / 暈眩、pool 落地一攤火）在 Projectile.skill_fx
class Shoot extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var dir := SkillBehaviors.face_aim(owner)
		var delay: float = def.get("windup", 0.0)
		if delay > 0.0:
			SkillBehaviors.later(owner, delay, func() -> void: SkillBehaviors.fire_fan(owner, def, ctx, SkillBehaviors.face_aim(owner)))
		elif def.get("interval", 0.0) > 0.0:
			for i in def.count:
				SkillBehaviors.later(owner, def.interval * i, func() -> void: SkillBehaviors.fire_one(owner, def, ctx, SkillBehaviors.face_aim(owner)))
		else:
			SkillBehaviors.fire_fan(owner, def, ctx, dir)


# 往後跳開，同時往準星扇形射箭
class LeapShot extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var dir := SkillBehaviors.face_aim(owner)
		SkillBehaviors.push(owner, -dir * def.distance * ctx.area)
		SkillBehaviors.fire_fan(owner, def, ctx, dir)


# 準星的位置延遲 delay 秒後打一圈：隕石、聖光柱（隊友回血）
class Strike extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var at := SkillBehaviors.aim_point(owner, def.max_range)
		var r: float = def.radius * ctx.area
		owner.world.emit_event("fx:telegraph", {"pos": at, "height": owner.world.terrain.ground_at(at), "radius": r, "color": def.color, "life": def.delay})
		SkillBehaviors.later(owner, def.delay, func() -> void:
			SkillBehaviors.area_hit(owner, def, ctx, at, {"shape": &"circle", "radius": r})
			owner.world.emit_event("fx:explosion", {"pos": at, "height": owner.world.terrain.ground_at(at), "radius": r, "color": def.color})
			if def.has("heal_ratio"):
				for o in owner.world.player_list:
					if not o.is_dead and not o.is_downed and o.pos.distance_to(at) <= r + o.radius:
						var healed := o.heal(o.max_hp * def.heal_ratio)
						if healed > 0.0:
							owner.world.emit_event("entity:healed", {"target_id": o.id, "amount": healed}))


# 準星的位置下一陣箭雨：duration 秒內每 tick 秒打一次
class Rain extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var at := SkillBehaviors.aim_point(owner, def.max_range)
		var r: float = def.radius * ctx.area
		owner.world.emit_event("fx:telegraph", {"pos": at, "height": owner.world.terrain.ground_at(at), "radius": r, "color": def.color, "life": def.duration})
		for i in roundi(def.duration / def.tick):
			SkillBehaviors.later(owner, def.tick * (i + 1), func() -> void:
				SkillBehaviors.area_hit(owner, def, ctx, at, {"shape": &"circle", "radius": r}))


# 閃電鏈：打準星附近最近的怪，再跳到 jump_range 內還沒打過的怪，共 jumps 次
class Chain extends Behavior:
	func can_use(owner: Player, def: Dictionary) -> bool:
		return SkillBehaviors.nearest_enemy(owner, SkillBehaviors.aim_point(owner, def.range), def.range) != null

	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		SkillBehaviors.face_aim(owner)
		var first := SkillBehaviors.nearest_enemy(owner, SkillBehaviors.aim_point(owner, def.range * ctx.area), def.range * ctx.area)
		if first != null:
			SkillBehaviors.chain(owner, first, def.jumps, def.jump_range * ctx.area, SkillBehaviors.hit_of(owner, def, ctx), def.color, owner.pos)


# 煙霧彈：腳下一團煙（GroundZones 的 smoke）
class Smoke extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		GroundZones.add(owner.world, {"pos": owner.pos, "radius": def.radius * ctx.area, "duration": def.duration, "owner_id": owner.id,
			"color": def.color, "visual": &"gas", "smoke": def.dodge})


# 嘲諷：周圍的怪（Boss 不會）這段時間改打自己；自己受到的傷害變少
class Taunt extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		for e in owner.world.enemies:
			if not e.is_dead and e.team != owner.team and not (e as Enemy).is_boss() and e.pos.distance_to(owner.pos) <= def.radius * ctx.area:
				(e as Enemy).taunt_id = owner.id
				(e as Enemy).taunt_timer = def.duration
		owner.add_buff(&"taunt", def.duration, {"stats": [[&"damage_taken", Stats.MUL, def.damage_taken]]})
		owner.world.emit_event("fx:explosion", {"pos": owner.pos, "height": owner.ground_height, "radius": def.radius * ctx.area, "color": def.color})


# 召喚骷髏僕從（同亡者大軍的僕從），存在 life 秒
class Summon extends Behavior:
	func activate(owner: Player, def: Dictionary, _ctx: Dictionary) -> void:
		if not owner.world.is_authority:
			return
		for i in def.count:
			var at := owner.world.nav.nearest_walkable(owner.pos + MathUtil.dir_from_angle(owner.facing + TAU * i / def.count) * 1.5)
			var m := Minion.new(owner.world, at, owner)
			m.life = def.life
			owner.world.add_enemy(m)
		owner.world.emit_event("sfx:cue", {"cue": "enemySpawn", "pos": owner.pos})


# 祝福：自己與附近隊友攻速變快一段時間
class Bless extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		for o in owner.world.player_list:
			if not o.is_dead and o.pos.distance_to(owner.pos) <= def.radius * ctx.area:
				o.add_buff(&"blessing", def.duration, {"stats": [[&"attack_speed", Stats.PCT, def.attack_speed]]})
		owner.world.emit_event("fx:heal", {"pos": owner.pos, "height": owner.height, "color": def.color})


# 掘地：鑽進土裡無敵 time 秒、往準星移動，出土時震開周圍
class Burrow extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var dir := SkillBehaviors.face_aim(owner)
		owner.invuln_timer = maxf(owner.invuln_timer, def.time)
		SkillBehaviors.push(owner, dir * def.distance * ctx.area)
		owner.world.emit_event("fx:explosion", {"pos": owner.pos, "height": owner.ground_height, "radius": 1.2, "color": def.color})
		SkillBehaviors.later(owner, def.time, func() -> void:
			var r: float = def.radius * ctx.area
			SkillBehaviors.area_hit(owner, def, ctx, owner.pos, {"shape": &"circle", "radius": r})
			owner.world.emit_event("fx:explosion", {"pos": owner.pos, "height": owner.ground_height, "radius": r, "color": def.color}))


static var BEHAVIORS := {
	&"heal": Heal.new(),
	&"plantTorch": PlantTorch.new(),
	&"nova": Nova.new(),
	&"cone": Cone.new(),
	&"dash": Dash.new(),
	&"ambush": Ambush.new(),
	&"shoot": Shoot.new(),
	&"leap_shot": LeapShot.new(),
	&"strike": Strike.new(),
	&"rain": Rain.new(),
	&"chain": Chain.new(),
	&"smoke": Smoke.new(),
	&"taunt": Taunt.new(),
	&"summon": Summon.new(),
	&"bless": Bless.new(),
	&"burrow": Burrow.new(),
}


# 放技能：照行為做，有分裂（標籤相符才會在 ctx 裡）就 SPLIT_DELAY 秒後用 SPLIT_MUL 的傷害再放一次
static func cast(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
	(BEHAVIORS[def.behavior] as Behavior).activate(owner, def, ctx)
	if def.has("sfx"):
		owner.world.emit_event("sfx:cue", {"cue": def.sfx, "pos": owner.pos})
	if ctx.get("split", false):
		var again := ctx.duplicate()
		again.split = false
		again.mul = ctx.mul * SPLIT_MUL
		later(owner, SPLIT_DELAY, func() -> void: (BEHAVIORS[def.behavior] as Behavior).activate(owner, def, again))


# 權威端：seconds 秒後執行 fn（World.delayed；換層、重新開始時清掉）；放的人不見了就不執行
static func later(owner: Player, seconds: float, fn: Callable) -> void:
	if owner.world.is_authority:
		owner.world.delayed.append({"t": seconds, "owner_id": owner.id, "fn": fn})


static func update_world(world: World, dt: float) -> void:
	var i := 0
	while i < world.delayed.size():
		var d: Dictionary = world.delayed[i]
		d.t -= dt
		if d.t > 1e-6:
			i += 1
			continue
		world.delayed.remove_at(i)
		var owner := world.entities.get(d.owner_id) as Player
		if owner != null and not owner.is_dead:
			(d.fn as Callable).call()


# 每步（Player._tick_timers）：衝刺中打面前，每隻怪一次
static func update_player(p: Player, dt: float) -> void:
	if p.skill_dash.is_empty():
		return
	var d: Dictionary = p.skill_dash
	d.left -= dt
	var def: Dictionary = d.def
	var hits := Hitbox.strike(p.world, p, p.pos, p.facing, {"shape": &"circle", "radius": def.width * 0.5 + p.radius}, hit_of(p, def, d.ctx), d.hit)
	_after_hits(p, def, d.ctx, hits)
	if d.left <= 0.0:
		p.skill_dash = {}


# ── 共用 ──

static func hit_of(owner: Player, def: Dictionary, ctx: Dictionary) -> Dictionary:
	return {"damage": owner.pct_damage(def.get("damage_pct", 0.0)) * ctx.mul, "damage_type": ctx.type, "knockback": def.get("knockback", 0.0),
		"is_heavy": true, "blockable": false, "color": def.color, "band": Vector2(-INF, INF)}


static func area_hit(owner: Player, def: Dictionary, ctx: Dictionary, at: Vector2, shape: Dictionary) -> void:
	var hit := hit_of(owner, def, ctx)
	hit["origin"] = at
	_after_hits(owner, def, ctx, Hitbox.strike(owner.world, owner, at, owner.facing, shape, hit))


# 打中之後：暈眩、燃燒、冰冷（層數照羈絆，BondEffects）
static func _after_hits(owner: Player, def: Dictionary, _ctx: Dictionary, hits: Array[Entity]) -> void:
	if not owner.world.is_authority:
		return
	for e in hits:
		if not e is Enemy or e.is_dead:
			continue
		if def.has("stun"):
			(e as Enemy).stun(def.stun)
		if def.has("burn"):
			BondEffects.add_burn(owner.world, owner, e as Enemy, def.burn)
		if def.has("chill"):
			BondEffects.add_chill(owner.world, owner, e as Enemy, def.chill)


static func face_aim(owner: Player) -> Vector2:
	var dir := WeaponBehaviors.aim_direction(owner)
	owner.facing = atan2(dir.x, dir.y)
	return dir


# 準星的位置，離自己最遠 max_range
static func aim_point(owner: Player, max_range: float) -> Vector2:
	var d := owner.aim_point - owner.pos
	return owner.pos + d.limit_length(max_range)


# 用擊退的衝量做位移：總共滑 offset 這麼遠（同蓄力突刺的算法）
static func push(owner: Player, offset: Vector2) -> void:
	var per_unit := (1.0 - exp(-Config.COMBAT.knockback_damping * Config.FIXED_DT)) / Config.FIXED_DT
	owner.knockback += offset * per_unit


static func nearest_enemy(owner: Player, at: Vector2, r: float, skip: Dictionary = {}) -> Enemy:
	var best: Enemy = null
	var best_d := r * r
	for e in owner.world.enemies:
		if e.is_dead or e.team == owner.team or skip.has(e.id) or not e.can_be_hit():
			continue
		var d := e.pos.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = e as Enemy
	return best


# 從 first 開始打，再跳 jumps 次（不打同一隻兩次）；畫一道閃電
static func chain(owner: Player, first: Enemy, jumps: int, jump_range: float, hit: Dictionary, color: Color, from: Vector2) -> void:
	var points := [from]
	var hitted := {}
	var e := first
	for i in jumps + 1:
		if e == null:
			break
		hitted[e.id] = true
		points.append(e.pos)
		Combat.apply_damage(owner.world, owner, e, hit)
		e = nearest_enemy(owner, e.pos, jump_range, hitted)
	owner.world.emit_event("fx:lightning", {"pos": from, "height": owner.ground_height, "points": points, "color": color})


static func fire_fan(owner: Player, def: Dictionary, ctx: Dictionary, dir: Vector2) -> void:
	var base := atan2(dir.x, dir.y)
	for i in def.count:
		var a := base
		if def.count > 1:
			a += lerpf(-def.spread / 2.0, def.spread / 2.0, float(i) / (def.count - 1))
		fire_one(owner, def, ctx, MathUtil.dir_from_angle(a))


static func fire_one(owner: Player, def: Dictionary, ctx: Dictionary, dir: Vector2) -> void:
	if not owner.world.is_authority:
		return
	var pr := Projectile.new(owner.world, {
		"owner": owner, "pos": owner.pos + dir * 0.4, "direction": dir, "speed": def.speed, "range": def.range * ctx.area,
		"radius": def.radius, "damage": owner.pct_damage(def.damage_pct) * ctx.mul, "damage_type": ctx.type,
		"color": StatDefs.DAMAGE_TYPES[ctx.type].color if ctx.type != def.get("damage_type", &"phys") else def.color,
		"visual": def.visual, "pierce": def.pierce, "blockable": false, "no_stagger": false,
		"altitude": owner.height + Config.HEIGHT.bolt_altitude, "settle_altitude": Config.HEIGHT.bolt_altitude,
		"settle_distance": Config.HEIGHT.bolt_settle_distance,
	})
	pr.skill_fx = {"def": def, "ctx": ctx}
	owner.world.spawn_projectile(pr)


# 技能的投射物結束（打中或飛到盡頭；穿透的只在盡頭）：跳電、炸開（暈眩 / 冰冷）、落地一攤火
static func projectile_end(pr: Projectile, target: Entity) -> void:
	var owner := pr.world.entities.get(pr.owner_id) as Player
	if owner == null or not pr.world.is_authority:
		return
	var def: Dictionary = pr.skill_fx.def
	var ctx: Dictionary = pr.skill_fx.ctx
	if def.has("chain") and target is Enemy:
		var c: Dictionary = def.chain
		var hit := hit_of(owner, def, ctx)
		hit.damage *= c.ratio
		var next := nearest_enemy(owner, target.pos, c.jump_range * ctx.area, {target.id: true})
		if next != null:
			chain(owner, next, c.jumps - 1, c.jump_range * ctx.area, hit, def.color, target.pos)
	if def.has("burst"):
		var b: Dictionary = def.burst
		var r: float = b.radius * ctx.area
		pr.world.emit_event("fx:explosion", {"pos": pr.pos, "height": pr.world.terrain.ground_at(pr.pos), "radius": r, "color": def.color})
		for e in pr.world.enemies:
			if e.is_dead or e.team == owner.team or e.pos.distance_to(pr.pos) > r + e.radius:
				continue
			if b.has("stun"):
				(e as Enemy).stun(b.stun)
			if b.has("chill"):
				BondEffects.add_chill(pr.world, owner, e as Enemy, b.chill)
	if def.has("pool"):
		var pl: Dictionary = def.pool
		fire_zone(owner, pr.pos, pl.radius * ctx.area, pl.duration, owner.pct_damage(pl.dps_pct) * ctx.mul, ctx.type)


static func fire_zone(owner: Player, at: Vector2, radius: float, duration: float, dps: float, type: StringName) -> void:
	GroundZones.add(owner.world, {"pos": at, "radius": radius, "duration": duration, "owner_id": owner.id,
		"color": StatDefs.DAMAGE_TYPES[type].color, "visual": &"fire" if type == &"fire" else &"", "damage_per_sec": dps, "damage_type": type})
