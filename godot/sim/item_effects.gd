# 道具的條件加成與觸發效果（v0.33.0 第一批）：只在權威端結算傷害（Combat 已檢查），數值在 ItemDefs.PROCS
#   條件（"when"）：CONDITIONS 的類別。每步判斷的（自己低血、擊殺後幾秒，Player 每步呼叫 update_player）成立時套上屬性；
#     每一下攻擊判斷的（對滿血敵人，Combat 呼叫 target_damage_pct）回傳這一下額外的百分比
#   觸發（"on" + "do"）：ACTIONS 的類別。命中時（連鎖閃電、中毒、冰凍）、擊殺時（小爆炸、回血）
#   新增一種條件 / 動作：在這裡加一個類別並登錄，再把名稱加進 ItemDefs.IMPLEMENTED_*（檢查會比對兩邊一致）
# 道具效果造成的傷害標記 proc：不爆擊、不再觸發命中效果（避免閃電觸發閃電），但打死怪照樣算擊殺
class_name ItemEffects


class Condition:
	# 每步判斷：成立時以「cond:道具 uid」為來源套上這條效果的屬性
	func per_step() -> bool:
		return true

	func active(_p: Player, _uid: StringName, _eff: Dictionary) -> bool:
		return false

	# 每一下攻擊判斷：對這個目標額外的攻擊力百分比（per_step() 為 false 的條件用）
	func attack_pct(_p: Player, _target: Entity, _eff: Dictionary) -> float:
		return 0.0

	# 玩家打死怪時（例如重新計時）
	func on_kill(_p: Player, _uid: StringName, _eff: Dictionary) -> void:
		pass

	# 成立時套上的數值（會隨狀況變的條件覆寫，例如每擊殺疊一層）
	func value(_p: Player, _uid: StringName, eff: Dictionary) -> float:
		return eff.value


class TargetFullHp extends Condition:
	func per_step() -> bool:
		return false

	func attack_pct(_p: Player, target: Entity, eff: Dictionary) -> float:
		if eff.stat == &"damage" and target.hp >= target.max_hp - 1e-4:
			return eff.value
		return 0.0


class HpBelow extends Condition:
	func active(p: Player, _uid: StringName, eff: Dictionary) -> bool:
		return not p.is_dead and p.hp < p.max_hp * eff.threshold


class AfterKill extends Condition:
	func active(p: Player, uid: StringName, _eff: Dictionary) -> bool:
		return p.kill_timers.has(uid)

	func on_kill(p: Player, uid: StringName, eff: Dictionary) -> void:
		p.kill_timers[uid] = maxf(p.kill_timers.get(uid, 0.0), eff.duration)


# 翻滾結束後一段時間（G2 獵人斗篷）：Roll.exit 呼叫 on_roll_end 開始計時；翻滾本機也會預測，客戶端自己就知道
class AfterRoll extends Condition:
	func active(p: Player, uid: StringName, _eff: Dictionary) -> bool:
		return p.roll_timers.has(uid)


# 本層每擊殺 1 隻疊一層、最多 max 層（G2 亡者之契）：Player.floor_kills 換層歸零
class PerKillStack extends Condition:
	func active(p: Player, _uid: StringName, _eff: Dictionary) -> bool:
		return p.floor_kills > 0

	func value(p: Player, _uid: StringName, eff: Dictionary) -> float:
		return eff.value * mini(p.floor_kills, eff.max)


# 來自精英怪（G2 貪婪之手）：不是每步或每一下的加成，由 soul_mul 在擊殺時讀
class FromElite extends Condition:
	func per_step() -> bool:
		return false


# 觸發的動作：proc = procs_of 合併後的 { do, effect, chance, count }；damage 是觸發那一下的傷害（扣護甲前）
class Action:
	# 這個動作接在哪些觸發上（對應 ItemDefs.IMPLEMENTED_TRIGGERS 的「on|do」）
	func triggers() -> Array[StringName]:
		return []

	func run(_world: World, _p: Player, _target: Entity, _damage: float, _proc: Dictionary) -> void:
		pass


# 從目標跳到最近的、還沒被打過的怪（jump_range 內），最多 targets 隻
class ChainLightning extends Action:
	func triggers() -> Array[StringName]:
		return [&"hit"]

	func run(world: World, p: Player, first: Entity, damage: float, proc: Dictionary) -> void:
		var cfg: Dictionary = ItemDefs.PROCS.chain_lightning
		var hit_ids := {first.id: true}
		var points: Array[Vector2] = [first.pos]
		var from := first
		for i in proc.effect.targets:
			var best: Entity = null
			var best_d: float = cfg.jump_range * cfg.jump_range
			for e in world.enemies:
				if e.is_dead or e.team == p.team or hit_ids.has(e.id):
					continue
				var d := e.pos.distance_squared_to(from.pos)
				if d <= best_d:
					best_d = d
					best = e
			if best == null:
				break
			hit_ids[best.id] = true
			points.append(best.pos)
			Combat.apply_damage(world, p, best, ItemEffects.proc_hit(damage * cfg.damage_ratio, best, cfg.color, 0.0, &"lightning"))
			from = best
		if points.size() > 1:
			world.emit_event("fx:lightning", {"pos": first.pos, "height": first.ground_height, "points": points, "color": cfg.color})


class Poison extends Action:
	func triggers() -> Array[StringName]:
		return [&"hit"]

	func run(_world: World, p: Player, target: Entity, damage: float, _proc: Dictionary) -> void:
		(target as Enemy).apply_poison(p.id, damage * ItemDefs.PROCS.poison.total_ratio)


class Freeze extends Action:
	func triggers() -> Array[StringName]:
		return [&"hit"]

	func run(_world: World, _p: Player, target: Entity, _damage: float, proc: Dictionary) -> void:
		(target as Enemy).apply_freeze(proc.effect.duration)


# 以目標的位置為中心的爆炸：擊殺（火藥包，擊殺那一下的 damage_ratio）、投射物命中（G3 爆裂箭袋，以被打中的怪為中心）、
# 受傷（G3 王墓之心：以自己為中心、受傷量 × 道具的 damage_ratio、半徑 hurt_explode）；道具資料有 damage_ratio 時蓋過預設
class Explode extends Action:
	func triggers() -> Array[StringName]:
		return [&"kill", &"projectile_hit", &"hurt"]

	func run(world: World, p: Player, target: Entity, damage: float, proc: Dictionary) -> void:
		var cfg: Dictionary = ItemDefs.PROCS.explode
		var radius: float = ItemDefs.PROCS.hurt_explode.radius if proc.on == &"hurt" else cfg.radius
		var color: Color = ItemDefs.PROCS.hurt_explode.color if proc.on == &"hurt" else cfg.color
		var ratio: float = proc.effect.get("damage_ratio", cfg.damage_ratio) * ItemEffects.stacks(proc)
		var at := target.pos
		world.emit_event("sfx:cue", {"cue": "explosion", "pos": at})
		world.emit_event("fx:explosion", {"pos": at, "height": target.ground_height, "radius": radius, "color": color})
		for e in Combat.query_circle(at, radius, Combat.hostiles_of(world, p.team, p.id)):
			var hit := ItemEffects.proc_hit(damage * ratio, e, color, cfg.knockback, &"fire")
			hit["origin"] = at
			hit["is_heavy"] = true
			Combat.apply_damage(world, p, e, hit)


# 反彈（G3 荊棘鎖甲）：受到近戰傷害時，把實際扣的血 × ratio 打回攻擊者
class Reflect extends Action:
	func triggers() -> Array[StringName]:
		return [&"hurt_melee"]

	func run(world: World, p: Player, attacker: Entity, dealt: float, proc: Dictionary) -> void:
		if not attacker is Enemy or attacker.is_dead:
			return
		var hit := ItemEffects.proc_hit(dealt * proc.effect.ratio * ItemEffects.stacks(proc), attacker, ItemDefs.PROCS.reflect.color)
		hit["origin"] = p.pos
		Combat.apply_damage(world, p, attacker, hit)


# 點燃（G3 永恆之焰）：命中那一下 × pct_per_sec 每秒、duration 秒；spread 的燃燒會傳給旁邊的怪（Enemy._update_burn）
class Ignite extends Action:
	func triggers() -> Array[StringName]:
		return [&"hit"]

	func run(_world: World, p: Player, target: Entity, damage: float, proc: Dictionary) -> void:
		var cfg: Dictionary = ItemDefs.PROCS.ignite
		(target as Enemy).apply_burn(p.id, damage * cfg.pct_per_sec * ItemEffects.stacks(proc), cfg.duration, proc.effect.get("spread", false))


# 普攻時追加的投射物（G4 袖中飛刀、裂空之刃）：傷害是手上武器基礎傷害的百分比、proc（不爆擊、不觸發命中效果）；內部冷卻 icd
static func _spawn_extra(world: World, p: Player, cfg: Dictionary, damage_pct: float, angles: Array[float], pierce: bool) -> void:
	var dir := WeaponBehaviors.aim_direction(p)
	var base := atan2(dir.x, dir.y)
	for off in angles:
		var d := MathUtil.dir_from_angle(base + off)
		WeaponBehaviors.spawn_projectile(p, {
			"pos": p.pos + d * 0.6, "direction": d, "speed": cfg.speed, "range": cfg.range, "radius": cfg.radius,
			"damage": p.pct_damage(damage_pct), "damage_type": p.weapon.damage_type, "color": cfg.color,
			"visual": cfg.visual, "no_stagger": true, "blockable": false, "pierce": pierce, "proc": true,
		})
	world.emit_event("sfx:cue", {"cue": cfg.sfx, "pos": p.pos})


class ThrowKnife extends Action:
	func triggers() -> Array[StringName]:
		return [&"attack"]

	func run(world: World, p: Player, _target: Entity, _damage: float, _proc: Dictionary) -> void:
		if ItemEffects.icd_ready(p, &"throw_knife"):
			var cfg: Dictionary = ItemDefs.PROCS.throw_knife
			ItemEffects._spawn_extra(world, p, cfg, cfg.damage_pct, [0.0], false)


class SlashWave extends Action:
	func triggers() -> Array[StringName]:
		return [&"attack"]

	func run(world: World, p: Player, _target: Entity, _damage: float, proc: Dictionary) -> void:
		if not ItemEffects.icd_ready(p, &"slash_wave"):
			return
		var cfg: Dictionary = ItemDefs.PROCS.slash_wave
		var n: int = proc.effect.count * proc.count
		var angles: Array[float] = []
		for i in n:   # 左右對稱：2 道 = ±spread，4 道 = ±spread、±2 spread
			angles.append(cfg.spread * (floori(i / 2.0) + 1) * (1 if i % 2 == 0 else -1))
		ItemEffects._spawn_extra(world, p, cfg, proc.effect.damage_ratio, angles, true)


# 每隔固定秒數（G4 雷霆鈴）：打 range 內最近的 targets 隻
class LightningStrike extends Action:
	func triggers() -> Array[StringName]:
		return [&"interval"]

	func run(world: World, p: Player, _target: Entity, _damage: float, _proc: Dictionary) -> void:
		var cfg: Dictionary = ItemDefs.PROCS.lightning_strike
		var near: Array[Entity] = []
		for e in Combat.query_circle(p.pos, cfg.range, Combat.hostiles_of(world, p.team, p.id)):
			if e is Enemy:   # 不打隊友
				near.append(e)
		near.sort_custom(func(a: Entity, b: Entity) -> bool: return a.pos.distance_squared_to(p.pos) < b.pos.distance_squared_to(p.pos))
		if near.is_empty():
			return
		world.emit_event("sfx:cue", {"cue": "explosion", "pos": p.pos})
		for e in near.slice(0, cfg.targets):
			world.emit_event("fx:explosion", {"pos": e.pos, "height": e.ground_height, "radius": cfg.radius, "color": cfg.color})
			var hit := ItemEffects.proc_hit(p.pct_damage(cfg.damage_pct), e, cfg.color)
			hit["damage_type"] = &"lightning"
			hit["band"] = Vector2(e.height - 1.0, e.height + e.body_height + 1.0)   # 從天上打下來：不管高低差
			Combat.apply_damage(world, p, e, hit)


# 翻滾時（G4 停滯懷錶）：周圍 radius 內的怪移速與出招速度變慢
class SlowTime extends Action:
	func triggers() -> Array[StringName]:
		return [&"roll"]

	func run(world: World, p: Player, _target: Entity, _damage: float, proc: Dictionary) -> void:
		var cfg: Dictionary = ItemDefs.PROCS.slow_time
		world.emit_event("fx:telegraph", {"pos": p.pos, "height": p.ground_height, "radius": cfg.radius, "color": cfg.color,
			"life": proc.effect.duration, "fill": true})
		for e in world.enemies:
			if not e.is_dead and e.team != p.team and e.pos.distance_to(p.pos) <= cfg.radius + e.radius:
				(e as Enemy).apply_slow(proc.effect.duration, proc.effect.slow)


# 擊殺時放出追蹤鬼火（G6 鬼火燈籠）：從屍體飛出、轉向最近的怪，打擊殺那一下的 damage_ratio；每人同時最多 max 顆
class Wisp extends Action:
	func triggers() -> Array[StringName]:
		return [&"kill"]

	func run(world: World, p: Player, target: Entity, damage: float, proc: Dictionary) -> void:
		var cfg: Dictionary = ItemDefs.PROCS.wisp
		var alive := 0
		for e in world.projectiles:
			if not e.is_removed and (e as Projectile).homing > 0.0 and (e as Projectile).owner_id == p.id:
				alive += 1
		for i in mini(ItemEffects.stacks(proc), cfg.max - alive):
			var a := world.rng.randf() * TAU
			var params := {
				"pos": target.pos, "direction": MathUtil.dir_from_angle(a), "speed": cfg.speed, "range": cfg.speed * cfg.life,
				"radius": cfg.radius, "damage": damage * cfg.damage_ratio, "damage_type": &"arcane", "color": cfg.color,
				"no_stagger": true, "blockable": false, "proc": true, "homing": cfg.turn_rate,
			}
			WeaponBehaviors.spawn_projectile(p, params)


# 擊殺時召喚骷髏僕從（G6 亡者大軍）：在屍體的位置爬出來；每人同時最多 max 隻
class SummonSkeleton extends Action:
	func triggers() -> Array[StringName]:
		return [&"kill"]

	func run(world: World, p: Player, target: Entity, _damage: float, proc: Dictionary) -> void:
		var alive := 0
		for e in world.allies:
			if not e.is_dead and e is Minion and (e as Minion).owner_id == p.id:
				alive += 1
		if alive >= proc.effect.max:
			return
		var m := Minion.new(world, world.nav.nearest_walkable(target.pos), p)
		world.add_enemy(m)
		world.emit_event("sfx:cue", {"cue": "enemySpawn", "pos": m.pos})


# 受到致命傷害時留 1 血並無敵（G5 守護亡靈）；次數由 on_lethal 管
class CheatDeath extends Action:
	func triggers() -> Array[StringName]:
		return [&"lethal"]

	func run(world: World, p: Player, _target: Entity, _damage: float, proc: Dictionary) -> void:
		p.hp = 1.0
		p.invuln_timer = proc.effect.invuln
		ItemEffects._saved(world, p, proc.item)


# 死亡時復活一次（G5 復活十字）：回 hp_ratio 的血、短暫無敵，道具碎掉空出格子
class Revive extends Action:
	func triggers() -> Array[StringName]:
		return [&"death"]

	func run(world: World, p: Player, _target: Entity, _damage: float, proc: Dictionary) -> void:
		var cfg: Dictionary = ItemDefs.PROCS.revive
		p.hp = maxf(1.0, roundf(p.max_hp * cfg.hp_ratio))
		p.invuln_timer = cfg.invuln
		if proc.effect.get("consume", false):
			p.remove_item(proc.uid)
		ItemEffects._saved(world, p, proc.item)


# 回血：沒有機率，多個道具的比例相加（proc.count）
class HealMaxHp extends Action:
	func triggers() -> Array[StringName]:
		return [&"kill"]

	func run(world: World, p: Player, _target: Entity, _damage: float, proc: Dictionary) -> void:
		var healed := p.heal(p.max_hp * proc.effect.ratio * proc.count)
		if healed > 0.0:
			world.emit_event("entity:healed", {"target_id": p.id, "amount": healed})


static var CONDITIONS := {
	&"target_full_hp": TargetFullHp.new(),
	&"hp_below": HpBelow.new(),
	&"after_kill": AfterKill.new(),
	&"after_roll": AfterRoll.new(),
	&"per_kill_stack": PerKillStack.new(),
	&"from_elite": FromElite.new(),
}

static var ACTIONS := {
	&"chain_lightning": ChainLightning.new(),
	&"poison": Poison.new(),
	&"freeze": Freeze.new(),
	&"explode": Explode.new(),
	&"heal_max_hp": HealMaxHp.new(),
	&"reflect": Reflect.new(),
	&"ignite": Ignite.new(),
	&"throw_knife": ThrowKnife.new(),
	&"slash_wave": SlashWave.new(),
	&"lightning_strike": LightningStrike.new(),
	&"slow_time": SlowTime.new(),
	&"cheat_death": CheatDeath.new(),
	&"revive": Revive.new(),
	&"wisp": Wisp.new(),
	&"summon_skeleton": SummonSkeleton.new(),
}


# 身上（items）所有道具的某種效果：key = "when" / "on"，value = 條件或觸發名稱；回傳 [{ uid, effect }]
static func effects_of(p: Player, key: String, value: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it: Dictionary in p.items:
		for eff: Dictionary in ItemDefs.ITEMS[it.id].effects:
			if eff.get(key, &"") == value:
				out.append({"uid": it.uid, "effect": eff})
	return out


# 身上所有已接上的條件效果：[{ uid, effect, condition }]
static func conditions_of(p: Player) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it: Dictionary in p.items:
		for eff: Dictionary in ItemDefs.ITEMS[it.id].effects:
			var cond: Condition = CONDITIONS.get(eff.get("when", &""))
			if cond != null:
				out.append({"uid": it.uid, "effect": eff, "condition": cond})
	return out


# 觸發的動作依 do 合併：機率相加（最多 1）、沒有機率的次數相加；依道具順序（決定性）
static func procs_of(p: Player, on: StringName) -> Array[Dictionary]:
	var by_do := {}
	var order: Array[Dictionary] = []
	for x in effects_of(p, "on", on):
		var eff: Dictionary = x.effect
		if not ItemDefs.is_implemented(eff):
			continue
		if not by_do.has(eff.do):
			by_do[eff.do] = {"do": eff.do, "on": on, "effect": eff, "chance": 0.0, "count": 0}
			order.append(by_do[eff.do])
		by_do[eff.do].chance += eff.get("chance", 1.0)
		by_do[eff.do].count += 1
	return order


# 沒有機率的觸發（荊棘、王墓之心、爆裂箭袋、永恆之焰）拿兩個效果相加；有機率的疊的是機率，效果只算一份
static func stacks(proc: Dictionary) -> int:
	return 1 if proc.effect.has("chance") else proc.count


static func _rolled(world: World, proc: Dictionary) -> bool:
	return proc.chance >= 1.0 or world.rng.randf() < proc.chance


static func _run_procs(world: World, p: Player, on: StringName, target: Entity, damage: float) -> void:
	for proc in procs_of(p, on):
		if _rolled(world, proc):
			(ACTIONS[proc.do] as Action).run(world, p, target, damage, proc)


# 這一下攻擊額外的攻擊力百分比（對滿血敵人）
static func target_damage_pct(p: Player, target: Entity) -> float:
	var pct := 0.0
	for x in conditions_of(p):
		var cond: Condition = x.condition
		if not cond.per_step():
			pct += cond.attack_pct(p, target, x.effect)
	return pct


# 每步：每步判斷的條件加成，成立時以「cond:道具 uid」為來源套上屬性，不成立就拿掉（有變才改，免得每步清屬性快取）
static func update_player(p: Player, dt: float) -> void:
	_tick(p.kill_timers, dt)
	_tick(p.roll_timers, dt)
	_tick(p.proc_timers, dt)
	if p.world.is_authority and not p.is_dead and not p.is_downed:
		_update_intervals(p, dt)
		_update_shield(p, dt)
	for x in conditions_of(p):
		var cond: Condition = x.condition
		if not cond.per_step():
			continue
		var eff: Dictionary = x.effect
		var source := StringName("cond:%s" % x.uid)
		if cond.active(p, x.uid, eff):
			var v := cond.value(p, x.uid, eff)
			if not p.stats.has_source(source) or p.cond_values.get(source) != v:
				p.set_stat_source(source, [[eff.stat, eff.op, v]])
				p.cond_values[source] = v
		elif p.stats.has_source(source):
			p.remove_stat_source(source)
			p.cond_values.erase(source)


# 每隔固定秒數的觸發（G4 雷霆鈴）：每個道具自己一個計時（拿兩個 = 兩個各自打）；只在權威端
static func _update_intervals(p: Player, dt: float) -> void:
	for x in effects_of(p, "on", &"interval"):
		var eff: Dictionary = x.effect
		if not ItemDefs.is_implemented(eff):
			continue
		var t: float = p.interval_timers.get(x.uid, eff.period) - dt
		if t <= 0.0:
			t += eff.period
			(ACTIONS[eff.do] as Action).run(p.world, p, null, 0.0, {"do": eff.do, "on": &"interval", "effect": eff, "chance": 1.0, "count": 1})
		p.interval_timers[x.uid] = t


# 自動回充的護盾（G4 骨製護盾）：盾量 = 最大生命 × 比例（拿兩個相加）；recharge_delay 秒沒受傷就一次補滿。只在權威端
static func shield_info(p: Player) -> Vector2:
	var ratio := 0.0
	var delay := 0.0
	for it: Dictionary in p.items:
		for eff: Dictionary in ItemDefs.ITEMS[it.id].effects:
			if eff.get("ability", &"") == &"bone_shield":
				ratio += eff.ratio
				delay = maxf(delay, eff.recharge_delay)
	return Vector2(p.max_hp * ratio, delay)


static func _update_shield(p: Player, dt: float) -> void:
	var cap := shield_info(p).x
	if cap <= 0.0:
		p.shield = 0.0
	elif p.shield_delay > 0.0:
		p.shield_delay -= dt
		p.shield = minf(p.shield, cap)
	else:
		p.shield = cap


# 受到傷害時先扣盾（Player._absorb），回傳要扣血的部分；有護盾道具就重新計算回充時間
static func absorb(p: Player, amount: float) -> float:
	var info := shield_info(p)
	if info.x <= 0.0:
		return amount
	p.shield_delay = info.y
	var used := minf(p.shield, amount)
	p.shield -= used
	return amount - used


# 普攻出手時（G4，TimedAction 進入 active、只在權威端）：袖中飛刀、裂空之刃
static func on_attack(world: World, p: Player) -> void:
	_run_procs(world, p, &"attack", null, 0.0)


# 生命歸零、還沒倒地時（G5，Player.die、只在權威端）：守護亡靈先用（每個道具每層一次），沒有才用復活十字；救下來回傳 true
static func on_lethal(world: World, p: Player) -> bool:
	var guards := effects_of(p, "on", &"lethal")
	if p.guardian_uses < guards.size():
		p.guardian_uses += 1
		var g: Dictionary = guards[0]
		(ACTIONS[g.effect.do] as Action).run(world, p, p, 0.0, _single(g, p))
		return true
	var crosses := effects_of(p, "on", &"death")
	if not crosses.is_empty():
		var c: Dictionary = crosses[0]
		(ACTIONS[c.effect.do] as Action).run(world, p, p, 0.0, _single(c, p))
		return true
	return false


static func _single(x: Dictionary, p: Player) -> Dictionary:
	var item: StringName = &""
	for it: Dictionary in p.items:
		if it.uid == x.uid:
			item = it.id
	return {"do": x.effect.do, "on": x.effect.on, "effect": x.effect, "chance": 1.0, "count": 1, "uid": x.uid, "item": item}


static func _saved(world: World, p: Player, item: StringName) -> void:
	world.emit_event("player:saved", {"player_id": p.id, "item": String(item)})
	world.emit_event("fx:heal", {"pos": p.pos, "height": p.height, "color": ItemDefs.PROCS.revive.color})
	world.emit_event("sfx:cue", {"cue": "potion", "pos": p.pos})


# 翻滾開始時（G4，Roll.enter、只在權威端）：停滯懷錶
static func on_roll(world: World, p: Player) -> void:
	_run_procs(world, p, &"roll", p, 0.0)


# 計時表：每個 key 剩下的秒數，到 0 就移除
static func _tick(timers: Dictionary, dt: float) -> void:
	for k in timers.keys():
		timers[k] -= dt
		if timers[k] <= 0.0:
			timers.erase(k)


# 道具拿掉時（Player.remove_item / sync_inventory）連同它的條件加成與計時一起拿掉
static func forget_item(p: Player, uid: StringName) -> void:
	var source := StringName("cond:%s" % uid)
	p.remove_stat_source(source)
	p.cond_values.erase(source)
	p.kill_timers.erase(uid)
	p.roll_timers.erase(uid)
	p.interval_timers.erase(uid)


# 翻滾結束時（Roll.exit）：「翻滾後幾秒」的條件開始計時
static func on_roll_end(p: Player) -> void:
	for x in effects_of(p, "when", &"after_roll"):
		p.roll_timers[x.uid] = maxf(p.roll_timers.get(x.uid, 0.0), x.effect.duration)


# 內部冷卻（ItemDefs.PROCS 的 icd）：key 是動作或屬性名稱，冷卻好了回傳 true 並開始計時
static func icd_ready(p: Player, key: StringName) -> bool:
	if p.proc_timers.has(key):
		return false
	var t: float = ItemDefs.PROCS.get(key, {}).get("icd", 0.0)
	if t > 0.0:
		p.proc_timers[key] = t
	return true


# 玩家方的一般攻擊實際扣了 dealt 血之後（G1）：命中回復（有內部冷卻）+ 吸血；打隊友不算
static func on_dealt(world: World, p: Player, dealt: float) -> void:
	var amount := dealt * p.stats.value(&"lifesteal")
	var per_hit := p.stats.value(&"life_on_hit")
	if per_hit > 0.0 and icd_ready(p, &"life_on_hit"):
		amount += per_hit
	if amount <= 0.0:
		return
	var healed := p.heal(amount)
	if healed >= 0.5:   # 吸血一下常常不到 1：照樣回，只是不飄字
		world.emit_event("entity:healed", {"target_id": p.id, "amount": healed})


# 殺這隻怪得到的靈魂倍率（G1 / G2）：擊殺者的靈魂獲得 × 精英怪（魔法 / 稀有）的道具倍率
static func soul_mul(p: Player, e: Enemy) -> float:
	var mul := p.stats.value(&"soul_gain")
	if e.rarity != MonsterRarityDefs.NORMAL:
		for x in effects_of(p, "when", &"from_elite"):
			mul *= x.effect.value
	return mul


# 命中時（Combat 在一般攻擊命中後呼叫）：damage 是這一下的傷害（扣護甲前）；projectile = 投射物直接命中（G3 爆裂箭袋）
static func on_hit(world: World, p: Player, target: Entity, damage: float, projectile := false) -> void:
	if not target is Enemy:
		return
	_run_procs(world, p, &"hit", target, damage)
	if projectile:
		_run_procs(world, p, &"projectile_hit", target, damage)


# 玩家被怪打到時（G3，Combat 在扣血之後呼叫）：damage 是扣護甲前、dealt 是實際扣的
# 近戰（不是投射物）→ 荊棘鎖甲反彈給攻擊者；任何傷害 → 王墓之心以自己為中心爆炸（內部冷卻 hurt_explode.icd）
static func on_hurt(world: World, p: Player, attacker: Entity, damage: float, dealt: float, projectile: bool) -> void:
	if not projectile:
		_run_procs(world, p, &"hurt_melee", attacker, dealt)
	var procs := procs_of(p, &"hurt")
	if not procs.is_empty() and icd_ready(p, &"hurt_explode"):
		for proc in procs:
			(ACTIONS[proc.do] as Action).run(world, p, p, damage, proc)


# 擊殺時（Combat 在玩家方的傷害打死怪之後呼叫，含道具效果打死的）
static func on_kill(world: World, p: Player, target: Entity, damage: float) -> void:
	p.floor_kills += 1
	for x in conditions_of(p):
		(x.condition as Condition).on_kill(p, x.uid, x.effect)
	_run_procs(world, p, &"kill", target, damage)


static func proc_hit(damage: float, target: Entity, color: Color, knockback := 0.0, damage_type := &"phys") -> Dictionary:
	return {"damage": damage, "knockback": knockback, "proc": true, "no_stagger": true, "blockable": false,
		"band": Combat.body_band(target), "color": color, "damage_type": damage_type}
