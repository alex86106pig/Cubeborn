# 道具的條件加成與觸發效果（v0.33.0 第一批）：只在權威端結算傷害（Combat 已檢查），數值在 ItemDefs.PROCS
#   條件：對滿血敵人（每一下攻擊算，Combat 呼叫 target_damage_pct）、自己低血、擊殺後幾秒（每步由 Player 呼叫 update_player）
#   觸發：命中時（連鎖閃電、中毒、冰凍）、擊殺時（小爆炸、回血、擊殺後計時）
# 道具效果造成的傷害標記 proc：不爆擊、不再觸發命中效果（避免閃電觸發閃電），但打死怪照樣算擊殺
class_name ItemEffects


# 身上（items）所有道具的某種效果：key = "when" / "on"，value = 條件或觸發名稱；回傳 [{ uid, effect }]
static func effects_of(p: Player, key: String, value: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it: Dictionary in p.items:
		for eff: Dictionary in ItemDefs.ITEMS[it.id].effects:
			if eff.get(key, &"") == value:
				out.append({"uid": it.uid, "effect": eff})
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


# 這一下攻擊額外的攻擊力百分比（對滿血敵人）
static func target_damage_pct(p: Player, target: Entity) -> float:
	var pct := 0.0
	if target.hp >= target.max_hp - 1e-4:
		for x in effects_of(p, "when", &"target_full_hp"):
			if x.effect.stat == &"damage":
				pct += x.effect.value
	return pct


# 每步：低血、擊殺後計時的條件加成，成立時以「cond:道具 uid」為來源套上屬性，不成立就拿掉（有變才改，免得每步清屬性快取）
static func update_player(p: Player, dt: float) -> void:
	for uid: StringName in p.kill_timers.keys():
		p.kill_timers[uid] -= dt
		if p.kill_timers[uid] <= 0.0:
			p.kill_timers.erase(uid)
	for it: Dictionary in p.items:
		for eff: Dictionary in ItemDefs.ITEMS[it.id].effects:
			var active: bool
			match eff.get("when", &""):
				&"hp_below":
					active = not p.is_dead and p.hp < p.max_hp * eff.threshold
				&"after_kill":
					active = p.kill_timers.has(it.uid)
				_:
					continue
			var source := StringName("cond:%s" % it.uid)
			if active != p.stats.has_source(source):
				if active:
					p.set_stat_source(source, [[eff.stat, eff.op, eff.value]])
				else:
					p.remove_stat_source(source)


# 道具拿掉時（Player.remove_item / sync_inventory）連同它的條件加成與計時一起拿掉
static func forget_item(p: Player, uid: StringName) -> void:
	p.remove_stat_source(StringName("cond:%s" % uid))
	p.kill_timers.erase(uid)


# 命中時（Combat 在一般攻擊命中後呼叫）：damage 是這一下的傷害（扣護甲前）
static func on_hit(world: World, p: Player, target: Entity, damage: float) -> void:
	if not target is Enemy:
		return
	for proc in procs_of(p, &"hit"):
		if not _rolled(world, proc):
			continue
		match proc.do:
			&"chain_lightning":
				chain_lightning(world, p, target, damage, proc.effect.targets)
			&"poison":
				(target as Enemy).apply_poison(p.id, damage * ItemDefs.PROCS.poison.total_ratio)
			&"freeze":
				(target as Enemy).apply_freeze(proc.effect.duration)


# 擊殺時（Combat 在玩家方的傷害打死怪之後呼叫，含道具效果打死的）
static func on_kill(world: World, p: Player, target: Entity, damage: float) -> void:
	for x in effects_of(p, "when", &"after_kill"):
		p.kill_timers[x.uid] = maxf(p.kill_timers.get(x.uid, 0.0), x.effect.duration)
	for proc in procs_of(p, &"kill"):
		if not _rolled(world, proc):
			continue
		match proc.do:
			&"explode":
				explode(world, p, target.pos, target.ground_height, damage * ItemDefs.PROCS.explode.damage_ratio)
			&"heal_max_hp":
				var healed := p.heal(p.max_hp * proc.effect.ratio * proc.count)
				if healed > 0.0:
					world.emit_event("entity:healed", {"target_id": p.id, "amount": healed})


static func proc_hit(damage: float, target: Entity, color: Color, knockback := 0.0) -> Dictionary:
	return {"damage": damage, "knockback": knockback, "proc": true, "no_stagger": true, "blockable": false,
		"band": Combat.body_band(target), "color": color}


# 從 first 跳到最近的、還沒被打過的怪（jump_range 內），最多 targets 隻
static func chain_lightning(world: World, p: Player, first: Entity, damage: float, targets: int) -> void:
	var cfg: Dictionary = ItemDefs.PROCS.chain_lightning
	var hit_ids := {first.id: true}
	var points: Array[Vector2] = [first.pos]
	var from := first
	for i in targets:
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
		Combat.apply_damage(world, p, best, proc_hit(damage * cfg.damage_ratio, best, cfg.color))
		from = best
	if points.size() > 1:
		world.emit_event("fx:lightning", {"pos": first.pos, "height": first.ground_height, "points": points, "color": cfg.color})


static func explode(world: World, p: Player, at: Vector2, ground: float, damage: float) -> void:
	var cfg: Dictionary = ItemDefs.PROCS.explode
	world.emit_event("sfx:cue", {"cue": "explosion"})
	world.emit_event("fx:explosion", {"pos": at, "height": ground, "radius": cfg.radius, "color": cfg.color})
	for e in Combat.query_circle(at, cfg.radius, Combat.hostiles_of(world, p.team, p.id)):
		var hit := proc_hit(damage, e, cfg.color, cfg.knockback)
		hit["origin"] = at
		hit["is_heavy"] = true
		Combat.apply_damage(world, p, e, hit)
