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
				if e.is_dead or hit_ids.has(e.id):
					continue
				var d := e.pos.distance_squared_to(from.pos)
				if d <= best_d:
					best_d = d
					best = e
			if best == null:
				break
			hit_ids[best.id] = true
			points.append(best.pos)
			Combat.apply_damage(world, p, best, ItemEffects.proc_hit(damage * cfg.damage_ratio, best, cfg.color))
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


# 以目標的位置為中心的小爆炸（擊殺那一下的 damage_ratio）
class Explode extends Action:
	func triggers() -> Array[StringName]:
		return [&"kill"]

	func run(world: World, p: Player, target: Entity, damage: float, _proc: Dictionary) -> void:
		var cfg: Dictionary = ItemDefs.PROCS.explode
		var at := target.pos
		world.emit_event("sfx:cue", {"cue": "explosion", "pos": at})
		world.emit_event("fx:explosion", {"pos": at, "height": target.ground_height, "radius": cfg.radius, "color": cfg.color})
		for e in Combat.query_circle(at, cfg.radius, Combat.hostiles_of(world, p.team, p.id)):
			var hit := ItemEffects.proc_hit(damage * cfg.damage_ratio, e, cfg.color, cfg.knockback)
			hit["origin"] = at
			hit["is_heavy"] = true
			Combat.apply_damage(world, p, e, hit)


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
			by_do[eff.do] = {"do": eff.do, "effect": eff, "chance": 0.0, "count": 0}
			order.append(by_do[eff.do])
		by_do[eff.do].chance += eff.get("chance", 1.0)
		by_do[eff.do].count += 1
	return order


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


# 命中時（Combat 在一般攻擊命中後呼叫）：damage 是這一下的傷害（扣護甲前）
static func on_hit(world: World, p: Player, target: Entity, damage: float) -> void:
	if not target is Enemy:
		return
	_run_procs(world, p, &"hit", target, damage)


# 擊殺時（Combat 在玩家方的傷害打死怪之後呼叫，含道具效果打死的）
static func on_kill(world: World, p: Player, target: Entity, damage: float) -> void:
	p.floor_kills += 1
	for x in conditions_of(p):
		(x.condition as Condition).on_kill(p, x.uid, x.effect)
	_run_procs(world, p, &"kill", target, damage)


static func proc_hit(damage: float, target: Entity, color: Color, knockback := 0.0) -> Dictionary:
	return {"damage": damage, "knockback": knockback, "proc": true, "no_stagger": true, "blockable": false,
		"band": Combat.body_band(target), "color": color}
