# 技能行為：Q 的治療藥水、寶石座的技能（Build 改版第 7 步，數字在 SkillDefs）
# cast 由 ActiveSlots.use 呼叫（本機預測時也會跑）：位移（衝刺、瞬移、後跳）兩邊都做，傷害、投射物、召喚、地面區域只在權威端
# ctx（ActiveSlots.cast_context）：mul 等級的傷害倍率、area 延長的範圍倍率、type 火焰化 / 霜化後的屬性、split 分裂（0.25 秒後再放一次 60%）
#   觸發袋有目標時再加上 at / dir / facing / target_id（aim_at）：範圍與落點改在目標身上、投射物從命中點沿原方向射出、位移朝目標；祝福、召喚、插火把仍在自己身上
# 晚一點才發生的（隕石、箭雨、連珠箭、狙擊、分裂）用 later 排進 World.delayed，只在權威端
class_name SkillBehaviors

const SPLIT_DELAY := 0.25
const SPLIT_MUL := 0.6


class Behavior:
	func can_use(_owner: Player, _def: Dictionary) -> bool:
		return true

	# 觸發袋有目標時能不能放；沒特別條件的照 can_use
	func can_use_on(owner: Player, def: Dictionary, _target: Entity) -> bool:
		return can_use(owner, def)

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
		var at := SkillBehaviors.origin(owner, ctx)
		SkillBehaviors.area_hit(owner, def, ctx, at, {"shape": &"circle", "radius": r})
		owner.world.emit_event("fx:explosion", {"pos": at, "height": SkillBehaviors.origin_ground(owner, ctx), "radius": r, "color": def.color})


# 面前扇形：震地
class Cone extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		if not ctx.has("at"):
			SkillBehaviors.face_aim(owner)
		var shape := {"shape": &"sector", "range": def.range * ctx.area, "arc": def.arc}
		var at := SkillBehaviors.origin(owner, ctx)
		SkillBehaviors.area_hit(owner, def, ctx, at, shape)
		owner.world.emit_event("fx:slash", {"pos": at, "height": SkillBehaviors.origin_ground(owner, ctx) if ctx.has("at") else owner.height, "facing": ctx.get("facing", owner.facing), "range": shape.range, "arc": def.arc, "color": def.color, "swing_dir": 1})


# 往準星衝刺，衝的這段時間打面前（每隻一次）：衝鋒斬、火焰衝刺（沿路留火）、盾衝（暈眩）
class Dash extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var dir := SkillBehaviors.turn_to(owner, ctx)
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
		var e := SkillBehaviors.target_of(owner, ctx)
		if e == null or e.pos.distance_to(owner.pos) > def.range * ctx.area:
			e = SkillBehaviors.nearest_enemy(owner, owner.pos, def.range * ctx.area)
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
		var dir: Vector2 = ctx.dir if ctx.has("dir") else SkillBehaviors.face_aim(owner)
		var delay: float = def.get("windup", 0.0)
		if delay > 0.0:
			SkillBehaviors.later(owner, delay, func() -> void: SkillBehaviors.fire_fan(owner, def, ctx, ctx.dir if ctx.has("dir") else SkillBehaviors.face_aim(owner)))
		elif def.get("interval", 0.0) > 0.0:
			for i in def.count:
				SkillBehaviors.later(owner, def.interval * i, func() -> void: SkillBehaviors.fire_one(owner, def, ctx, ctx.dir if ctx.has("dir") else SkillBehaviors.face_aim(owner)))
		else:
			SkillBehaviors.fire_fan(owner, def, ctx, dir)


# 往後跳開，同時往準星扇形射箭
class LeapShot extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var dir := SkillBehaviors.turn_to(owner, ctx)
		SkillBehaviors.push(owner, -dir * def.distance * ctx.area)
		var from_self := ctx.duplicate()   # 位移技能：箭從自己身上射向目標，不從目標身上出發
		from_self.erase("at")
		SkillBehaviors.fire_fan(owner, def, from_self, dir)


# 準星的位置延遲 delay 秒後打一圈：隕石、聖光柱（隊友回血）
class Strike extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var at: Vector2 = ctx.at if ctx.has("at") else SkillBehaviors.aim_point(owner, def.max_range)
		var r: float = def.radius * ctx.area
		owner.world.emit_event("fx:telegraph", {"pos": at, "height": owner.world.terrain.ground_at(at), "radius": r, "color": def.color, "life": def.delay})
		SkillBehaviors.later(owner, def.delay, func() -> void:
			SkillBehaviors.area_hit(owner, def, ctx, at, {"shape": &"circle", "radius": r})
			owner.world.emit_event("fx:explosion", {"pos": at, "height": owner.world.terrain.ground_at(at), "radius": r, "color": def.color})
			if def.has("heal_ratio"):
				for o in owner.friends():
					if not o.is_dead and not o.is_downed and o.pos.distance_to(at) <= r + o.radius:
						var healed := o.heal(o.max_hp * def.heal_ratio)
						if healed > 0.0:
							owner.world.emit_event("entity:healed", {"target_id": o.id, "amount": healed}))


# 準星的位置下一陣箭雨：duration 秒內每 tick 秒打一次
class Rain extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var at: Vector2 = ctx.at if ctx.has("at") else SkillBehaviors.aim_point(owner, def.max_range)
		var r: float = def.radius * ctx.area
		owner.world.emit_event("fx:telegraph", {"pos": at, "height": owner.world.terrain.ground_at(at), "radius": r, "color": def.color, "life": def.duration})
		for i in roundi(def.duration / def.tick):
			SkillBehaviors.later(owner, def.tick * (i + 1), func() -> void:
				SkillBehaviors.area_hit(owner, def, ctx, at, {"shape": &"circle", "radius": r}))


# 閃電鏈：打準星附近最近的怪，再跳到 jump_range 內還沒打過的怪，共 jumps 次
class Chain extends Behavior:
	func can_use(owner: Player, def: Dictionary) -> bool:
		return SkillBehaviors.nearest_enemy(owner, SkillBehaviors.aim_point(owner, def.range), def.range) != null

	# 目標活著就打它；打死了（擊殺袋）打它旁邊最近的
	func can_use_on(owner: Player, def: Dictionary, target: Entity) -> bool:
		return SkillBehaviors.nearest_enemy(owner, target.pos, def.range) != null

	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var first: Entity = null
		if ctx.has("at"):
			first = SkillBehaviors.target_of(owner, ctx)
			if first == null:
				first = SkillBehaviors.nearest_enemy(owner, ctx.at, def.range * ctx.area)
		else:
			SkillBehaviors.face_aim(owner)
			first = SkillBehaviors.nearest_enemy(owner, SkillBehaviors.aim_point(owner, def.range * ctx.area), def.range * ctx.area)
		if first != null:
			SkillBehaviors.chain(owner, first, def.jumps, def.jump_range * ctx.area, SkillBehaviors.hit_of(owner, def, ctx), def.color, SkillBehaviors.origin(owner, ctx))


# 煙霧彈：腳下一團煙（GroundZones 的 smoke）
class Smoke extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		GroundZones.add(owner.world, {"pos": SkillBehaviors.origin(owner, ctx), "radius": def.radius * ctx.area, "duration": def.duration, "owner_id": owner.id,
			"color": def.color, "visual": &"gas", "smoke": def.dodge})


# 嘲諷：周圍的怪（Boss 不會）這段時間改打自己；自己受到的傷害變少
class Taunt extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var at := SkillBehaviors.origin(owner, ctx)
		for e in owner.world.enemies:
			if not e.is_dead and e.team != owner.team and not (e as Enemy).is_boss() and e.pos.distance_to(at) <= def.radius * ctx.area:
				(e as Enemy).taunt_id = owner.id
				(e as Enemy).taunt_timer = def.duration
		owner.add_buff(&"taunt", def.duration, {"stats": [[&"damage_taken", Stats.MUL, def.damage_taken]]})
		owner.world.emit_event("fx:explosion", {"pos": at, "height": SkillBehaviors.origin_ground(owner, ctx), "radius": def.radius * ctx.area, "color": def.color})


# 召喚骷髏僕從（同亡者大軍的僕從），存在 life 秒
class Summon extends Behavior:
	func activate(owner: Player, def: Dictionary, _ctx: Dictionary) -> void:
		if not owner.world.is_authority or owner.is_ghost():   # 僕從是玩家方的：冤魂召不出來
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
		for o in owner.friends():
			if not o.is_dead and o.pos.distance_to(owner.pos) <= def.radius * ctx.area:
				o.add_buff(&"blessing", def.duration, {"stats": [[&"attack_speed", Stats.PCT, def.attack_speed]]})
		owner.world.emit_event("fx:heal", {"pos": owner.pos, "height": owner.height, "color": def.color})


# 掘地：鑽進土裡無敵 time 秒、往準星移動，出土時震開周圍
class Burrow extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var dir := SkillBehaviors.turn_to(owner, ctx)
		owner.invuln_timer = maxf(owner.invuln_timer, def.time)
		SkillBehaviors.push(owner, dir * def.distance * ctx.area)
		owner.world.emit_event("fx:explosion", {"pos": owner.pos, "height": owner.ground_height, "radius": 1.2, "color": def.color})
		SkillBehaviors.later(owner, def.time, func() -> void:
			var r: float = def.radius * ctx.area
			SkillBehaviors.area_hit(owner, def, ctx, owner.pos, {"shape": &"circle", "radius": r})
			owner.world.emit_event("fx:explosion", {"pos": owner.pos, "height": owner.ground_height, "radius": r, "color": def.color}))


# ── 橘色技能（mockups/橘色技能.html 方案 1~3）──

# 千刃風暴：duration 秒內每 tick 秒砍一次身邊（跟著自己走）
class Storm extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var r: float = def.radius * ctx.area
		for i in roundi(def.duration / def.tick):
			SkillBehaviors.later(owner, def.tick * i, func() -> void:
				SkillBehaviors.area_hit(owner, def, ctx, owner.pos, {"shape": &"circle", "radius": r})
				owner.world.emit_event("fx:sweep", {"pos": owner.pos, "height": owner.ground_height, "radius": r, "low": i % 2 == 0}))


# 裂地斬：往準星劈一道 length 長、width 寬的直線，路上的怪各打一次並擊飛
class Line extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var dir := SkillBehaviors.turn_to(owner, ctx)
		var from := owner.pos if not ctx.has("at") else (ctx.at as Vector2) - dir * 1.0
		var length: float = def.length * ctx.area
		if not owner.world.is_authority:
			return
		var hit := SkillBehaviors.hit_of(owner, def, ctx)
		hit["origin"] = from
		var hits: Array[Entity] = []
		for e in Combat.hostiles_of(owner.world, owner.team, owner.id):
			if not e.can_be_hit():
				continue
			var along := (e.pos - from).dot(dir)
			if along < 0.0 or along > length:
				continue
			if absf((e.pos - from).cross(dir)) <= def.width * 0.5 + e.radius and Combat.apply_damage(owner.world, owner, e, hit):
				hits.append(e)
				if e is Enemy and not (e as Enemy).is_boss():
					e.vz = maxf(e.vz, def.get("knockup", 0.0))   # 擊飛（Boss 不會）
		SkillBehaviors._after_hits(owner, def, ctx, hits)
		var points := []
		for k in 7:
			points.append(from + dir * length * k / 6.0)
		owner.world.emit_event("fx:lightning", {"pos": from, "height": owner.ground_height, "points": points, "color": def.color})


# 天譴：range 內最近的 targets 隻各落一道雷（delay 秒後；每隻一次）
class Smite extends Behavior:
	func can_use(owner: Player, def: Dictionary) -> bool:
		return SkillBehaviors.nearest_enemy(owner, owner.pos, def.range) != null

	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var center := SkillBehaviors.origin(owner, ctx)
		var picked := {}
		var targets: Array[Entity] = []
		for i in def.targets:
			var e := SkillBehaviors.nearest_enemy(owner, center, def.range * ctx.area, picked)
			if e == null:
				break
			picked[e.id] = true
			targets.append(e)
		for e in targets:
			var at := e.pos
			owner.world.emit_event("fx:telegraph", {"pos": at, "height": owner.world.terrain.ground_at(at), "radius": def.radius, "color": def.color, "life": def.delay})
			var id := e.id
			SkillBehaviors.later(owner, def.delay, func() -> void:
				var t := owner.world.entities.get(id) as Entity
				if t == null or t.is_dead:
					return
				var hit := SkillBehaviors.hit_of(owner, def, ctx)
				hit["origin"] = t.pos
				if Combat.apply_damage(owner.world, owner, t, hit):
					SkillBehaviors._after_hits(owner, def, ctx, [t] as Array[Entity])
				owner.world.emit_event("fx:explosion", {"pos": t.pos, "height": t.ground_height, "radius": def.radius, "color": def.color}))


# 魂泉：duration 秒內技能耗魔 × mana_cost（同一個增益，重放只刷新時間）
class ManaBuff extends Behavior:
	func activate(owner: Player, def: Dictionary, _ctx: Dictionary) -> void:
		owner.add_buff(&"soul_spring", def.duration, {"stats": [[&"mana_cost", Stats.MUL, def.mana_cost]]})
		owner.world.emit_event("fx:heal", {"pos": owner.pos, "height": owner.height, "color": def.color})


# 回響、共鳴、血契：改寫放它的那個袋子（BagTriggers.run_bag），自己不會放
class BagRule extends Behavior:
	func can_use(_owner: Player, _def: Dictionary) -> bool:
		return false


# 噬魂刃：面前扇形一刀；用它打死的怪讓這一層的傷害 +per_kill（最多 max_stacks 層，Player.reaver_stacks，換層歸零）
class Reaver extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		if not ctx.has("at"):
			SkillBehaviors.face_aim(owner)
		var grown := ctx.duplicate()
		grown.mul = ctx.mul * (1.0 + def.per_kill * owner.reaver_stacks)
		var at := SkillBehaviors.origin(owner, ctx)
		var shape := {"shape": &"sector", "range": def.range * ctx.area, "arc": def.arc}
		var hit := SkillBehaviors.hit_of(owner, def, grown)
		hit["origin"] = at
		var hits := Hitbox.strike(owner.world, owner, at, ctx.get("facing", owner.facing), shape, hit)
		for e in hits:
			if e.is_dead and e is Enemy:
				owner.reaver_stacks = mini(def.max_stacks, owner.reaver_stacks + 1)
		owner.world.emit_event("fx:slash", {"pos": at, "height": owner.height, "facing": ctx.get("facing", owner.facing), "range": shape.range, "arc": def.arc, "color": def.color, "swing_dir": 1})


# 亡者軍勢：radius 內每具怪物屍體（死了還沒移除的）起來一隻骷髏僕從，最多 max 隻；屍體用掉（不再有死亡效果）
class Legion extends Behavior:
	func can_use(owner: Player, def: Dictionary) -> bool:
		return not SkillBehaviors.corpses_near(owner, owner.pos, def.radius).is_empty()

	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		if not owner.world.is_authority or owner.is_ghost():   # 僕從是玩家方的：冤魂召不出來
			return
		var at := SkillBehaviors.origin(owner, ctx)
		var bodies := SkillBehaviors.corpses_near(owner, at, def.radius * ctx.area)
		for i in mini(def.max, bodies.size()):
			var c: Enemy = bodies[i]
			var m := Minion.new(owner.world, owner.world.nav.nearest_walkable(c.pos), owner)
			m.life = def.life
			owner.world.add_enemy(m)
			c.no_death_effect = true
			c.remove()
		owner.world.emit_event("sfx:cue", {"cue": "enemySpawn", "pos": at})


# 積怨：把上次放出之後受到的傷害（Player.grudge_taken）× grudge_mul 炸向身邊，至少 damage_pct；放完歸零
class Grudge extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		var r: float = def.radius * ctx.area
		var hit := SkillBehaviors.hit_of(owner, def, ctx)
		hit.damage = maxf(hit.damage, owner.grudge_taken * def.grudge_mul * ctx.mul)
		hit["origin"] = owner.pos
		owner.grudge_taken = 0.0
		SkillBehaviors._after_hits(owner, def, ctx, Hitbox.strike(owner.world, owner, owner.pos, owner.facing, {"shape": &"circle", "radius": r}, hit))
		owner.world.emit_event("fx:explosion", {"pos": owner.pos, "height": owner.ground_height, "radius": r, "color": def.color})


# 星位：腳下留一顆星（Player.stars，最多 max 顆、各 life 秒，多的頂掉最舊的）；3 顆圍成的三角形每 tick 秒打一次（update_player）
class Star extends Behavior:
	func activate(owner: Player, def: Dictionary, ctx: Dictionary) -> void:
		if not owner.world.is_authority:
			return
		owner.stars.append({"pos": owner.pos, "t": def.life, "ctx": ctx})
		while owner.stars.size() > def.max:
			owner.stars.pop_front()
		owner.world.emit_event("fx:telegraph", {"pos": owner.pos, "height": owner.ground_height, "radius": 0.6, "color": def.color, "life": def.life})


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
	&"storm": Storm.new(),
	&"line": Line.new(),
	&"smite": Smite.new(),
	&"mana_buff": ManaBuff.new(),
	&"bag_rule": BagRule.new(),
	&"reaver": Reaver.new(),
	&"legion": Legion.new(),
	&"grudge": Grudge.new(),
	&"star": Star.new(),
}


# 星位的三角形（每步，權威端）：星倒數、過期移除；有 3 顆時每 tick 秒打三角形裡的怪一次，畫三條連線
static func update_stars(p: Player, dt: float) -> void:
	if p.stars.is_empty():
		return
	var def: Dictionary = SkillDefs.SKILLS.star_sign
	for s: Dictionary in p.stars:
		s.t -= dt
	p.stars = p.stars.filter(func(s: Dictionary) -> bool: return s.t > 0.0)
	if p.stars.size() < 3:
		p.star_timer = 0.0
		return
	p.star_timer -= dt
	if p.star_timer > 0.0:
		return
	p.star_timer = def.tick
	var a: Vector2 = p.stars[0].pos
	var b: Vector2 = p.stars[1].pos
	var c: Vector2 = p.stars[2].pos
	var ctx: Dictionary = p.stars[-1].ctx
	var hit := hit_of(p, def, ctx)
	hit["origin"] = (a + b + c) / 3.0
	Combat.scoped("k:star_sign", func() -> void:
		for e in Combat.hostiles_of(p.world, p.team, p.id):
			if e.can_be_hit() and Geometry2D.point_is_inside_triangle(e.pos, a, b, c):
				Combat.apply_damage(p.world, p, e, hit))
	p.world.emit_event("fx:lightning", {"pos": a, "height": p.ground_height, "points": [a, b, c, a], "color": def.color})


# 怪物屍體（死了還沒移除、不是 Boss）：離 at 近的排前面
static func corpses_near(owner: Player, at: Vector2, r: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in owner.world.enemies:
		if e.is_dead and not e.is_removed and e is Enemy and not (e as Enemy).is_boss() and e.team != owner.team and e.pos.distance_to(at) <= r:
			out.append(e as Enemy)
	out.sort_custom(func(x: Enemy, y: Enemy) -> bool: return x.pos.distance_squared_to(at) < y.pos.distance_squared_to(at))
	return out


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
		owner.world.delayed.append({"t": seconds, "owner_id": owner.id, "fn": fn, "credit": Combat.credit_scope})


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
			Combat.scoped(d.get("credit", ""), d.fn)   # 排程當下的傷害來源（分裂、晚一點落下的招式）


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
	return {"damage": owner.pct_damage(def.get("damage_pct", 0.0)) * ctx.mul, "damage_type": ctx.type, "knockback": def.get("knockback", 0.0), "attack": &"skill", "credit": ctx.get("credit", ""),
		"is_heavy": true, "blockable": false, "color": def.color, "band": Vector2(-INF, INF)}


# 會幫隊友回血的招式（heal_ratio）不打隊友：誤傷開著時其他招式照打
static func area_hit(owner: Player, def: Dictionary, ctx: Dictionary, at: Vector2, shape: Dictionary) -> void:
	var hit := hit_of(owner, def, ctx)
	hit["origin"] = at
	var skip := {}
	if def.has("heal_ratio"):
		for p in owner.friends():
			skip[p.id] = true
	_after_hits(owner, def, ctx, Hitbox.strike(owner.world, owner, at, ctx.get("facing", owner.facing), shape, hit, skip))


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


# 觸發袋有目標（命中、擊殺、受傷、招架）：技能改在目標身上放。方向 = 自己 → 目標；目標跟自己疊在一起時用準星的方向
static func aim_at(owner: Player, ctx: Dictionary, target: Entity) -> void:
	var d := target.pos - owner.pos
	var dir := d.normalized() if d.length_squared() > 1e-6 else WeaponBehaviors.aim_direction(owner)
	ctx["at"] = target.pos
	ctx["dir"] = dir
	ctx["facing"] = atan2(dir.x, dir.y)
	ctx["target_id"] = target.id


# 技能以哪裡為中心：有目標在目標身上，沒有在自己身上
static func origin(owner: Player, ctx: Dictionary) -> Vector2:
	return ctx.at if ctx.has("at") else owner.pos


static func origin_ground(owner: Player, ctx: Dictionary) -> float:
	return owner.world.terrain.ground_at(ctx.at) if ctx.has("at") else owner.ground_height


# 觸發袋的目標（還活著、打得到才算）；沒有回傳 null
static func target_of(owner: Player, ctx: Dictionary) -> Entity:
	var e := owner.world.entities.get(ctx.get("target_id", -1)) as Entity
	return e if e != null and not e.is_dead and e.team != owner.team and e.can_be_hit() else null


# 位移技能的方向：有目標朝目標（自己也轉過去），沒有朝準星
static func turn_to(owner: Player, ctx: Dictionary) -> Vector2:
	if not ctx.has("dir"):
		return face_aim(owner)
	owner.facing = ctx.facing
	return ctx.dir


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


# 敵對陣營裡離 at 最近的（玩家的技能找怪與冤魂、冤魂的技能找玩家；Combat.hostiles_of，不含誤傷的隊友）
static func nearest_enemy(owner: Player, at: Vector2, r: float, skip: Dictionary = {}) -> Entity:
	var best: Entity = null
	var best_d := r * r
	for e in Combat.hostiles_of(owner.world, owner.team):
		if skip.has(e.id) or not e.can_be_hit():
			continue
		var d := e.pos.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = e
	return best


# 從 first 開始打，再跳 jumps 次（不打同一隻兩次）；畫一道閃電
static func chain(owner: Player, first: Entity, jumps: int, jump_range: float, hit: Dictionary, color: Color, from: Vector2) -> void:
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
		# 同時射出的扇形：從命中點出發時只有中間那支打得到目標（一群時每隻只中一支）
		var side_arrow: bool = ctx.has("at") and def.count > 1 and def.spread > 0.0 and i != def.count / 2
		fire_one(owner, def, ctx, MathUtil.dir_from_angle(a), side_arrow)


static func fire_one(owner: Player, def: Dictionary, ctx: Dictionary, dir: Vector2, skip_target := false) -> void:
	if not owner.world.is_authority:
		return
	# 有目標時從命中點出發：先打目標，能穿透的再打後面的怪
	var from: Vector2 = ctx.at if ctx.has("at") else owner.pos + dir * 0.4
	var pr := Projectile.new(owner.world, {
		"owner": owner, "pos": from, "direction": dir, "speed": def.speed, "range": def.range * ctx.area,
		"radius": def.radius, "damage": owner.pct_damage(def.damage_pct) * ctx.mul, "damage_type": ctx.type,
		"color": StatDefs.DAMAGE_TYPES[ctx.type].color if ctx.type != def.get("damage_type", &"phys") else def.color,
		"visual": def.visual, "pierce": def.pierce, "blockable": false, "no_stagger": false,
		"altitude": owner.height + Config.HEIGHT.bolt_altitude, "settle_altitude": Config.HEIGHT.bolt_altitude,
		"settle_distance": Config.HEIGHT.bolt_settle_distance, "attack": &"skill",
	})
	pr.skill_fx = {"def": def, "ctx": ctx}
	if skip_target:
		pr.ignore_target(ctx.target_id)
	owner.world.spawn_projectile(pr)


# 技能的投射物結束（打中或飛到盡頭；穿透的只在盡頭）：跳電、炸開（暈眩 / 冰冷）、落地一攤火
static func projectile_end(pr: Projectile, target: Entity) -> void:
	var owner := pr.world.entities.get(pr.owner_id) as Player
	if owner == null or not pr.world.is_authority:
		return
	var def: Dictionary = pr.skill_fx.def
	var ctx: Dictionary = pr.skill_fx.ctx
	if def.has("chain") and target != null and target.team != owner.team:
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
		for e in pr.world.enemies:   # 暈眩、冰冷只有怪物有（冤魂、玩家不吃）
			if e.is_dead or e.team == owner.team or not e is Enemy or e.pos.distance_to(pr.pos) > r + e.radius:
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
