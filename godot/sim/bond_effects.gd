# 羈絆的效果（Build 改版第 5 步）：門檻與數字在 defs/bond_defs.gd，件數在 Loadout.bond_counts
# 掛在 Combat（命中前的傷害倍率與必爆擊、命中後疊狀態）、Player（招架、每步）、Enemy（死亡）上；只在權威端結算傷害
#   物理：物理傷害（屬性）、失衡、擊退（屬性）＋撞怪、無視物理抗性、對失衡必爆擊與處決
#   火焰：燃燒疊層（Enemy.add_burn）、疊滿爆炸、死亡時把層數傳出去
#   冰霜：冰冷疊層（Enemy.add_chill）、疊滿凍結、打凍結的怪加傷並碎冰、碎冰噴冰錐、凍結中被殺沒有死亡效果
#   防禦：護甲（屬性）、招架回血、招架後下一擊必爆擊、招架衝擊波、反彈傷害
#   鬼火：繞著玩家轉的鬼火（OrbitWisp，sync_wisps）、定時衝出去、數量加倍與觸發看部位的道具
# hit 帶 no_status 的（燃燒 / 地面持續傷害、爆炸、冰錐、撞怪）不再疊狀態，避免連鎖
class_name BondEffects

static var _pre := {"mul": 1.0, "crit": false, "shatter": false}   # pre_hit 的結果（每一下重複用）


static func tier(p: Player, bond: StringName) -> int:
	return BondDefs.tier(bond, p.loadout.bond_counts.get(bond, 0))


# 手上武器有沒有這條分支詞條（WeaponDropDefs kind branch，第 8c 步）
static func has_branch(p: Player, id: StringName) -> bool:
	return p.loadout.branches.has(id)


static func _p(bond: StringName) -> Dictionary:
	return BondDefs.BONDS[bond].params


# 武器基礎傷害的 pct 倍，乘攻擊力與屬性傷害（燃燒、冰錐、鬼火這類屬性傷害用；Player.pct_damage 看的是武器自己的屬性）
static func elem_damage(p: Player, pct: float) -> float:
	return p.weapon.base_damage * pct * p.damage_mul * p.stats.value(&"elem_damage")


# ── 屬性加成（refresh_items 之後）──

static func refresh(p: Player) -> void:
	var mods := []
	var phys := tier(p, &"phys")
	if phys >= 1:
		mods.append([&"phys_damage", Stats.PCT, _p(&"phys").phys_damage])
	if phys >= 3:
		mods.append([&"knockback", Stats.PCT, _p(&"phys").knockback])
	if tier(p, &"guard") >= 1:
		mods.append([&"armor", Stats.PCT, _p(&"guard").armor])
	if mods.is_empty():
		p.remove_stat_source(&"bond")
	else:
		p.set_stat_source(&"bond", mods)
	p.wisp_plan = wisp_plan(p)


# ── 燃燒、冰冷 ──

# 對 e 加 stacks 層燃燒（算 p 的）：沒有火焰羈絆最多 1 層；第 2 階疊滿就爆炸
static func add_burn(world: World, p: Player, e: Enemy, stacks: int) -> void:
	var c := _p(&"fire")
	var t := tier(p, &"fire")
	if has_branch(p, &"br_burn_rush"):
		_burn_rush(world, p, e)
		return
	var cap := burn_cap(p)
	e.add_burn(p.id, elem_damage(p, c.stack_pct) * p.stats.value(&"burn_damage"), c.duration, stacks, cap if t >= 1 else 1)
	if t >= 2 and e.burn_stacks >= cap:
		_fire_burst(world, p, e)


# 分支・爆燃：燃燒不疊層；打中燃燒中的怪先一次打出剩下的燃燒傷害（火焰、不再疊狀態），再重新點 1 層；不會疊滿爆炸
static func _burn_rush(world: World, p: Player, e: Enemy) -> void:
	var c := _p(&"fire")
	if e.burn_timer > 0.0 and e.burn_tick_damage > 0.0:
		var rest := e.burn_tick_damage * e.burn_timer / Enemy.BURN_TICK
		e.clear_burn()
		var hit := ItemEffects.proc_hit(rest, e, Enemy.BURN_COLOR, 0.0, &"fire")
		hit["no_status"] = true
		Combat.apply_damage(world, p, e, hit)
		if e.is_dead:
			return
	e.add_burn(p.id, elem_damage(p, c.stack_pct) * p.stats.value(&"burn_damage"), c.duration, 1, 1)


# 燃燒 / 冰冷的層數上限：羈絆的上限＋武器詞條（燃燒層數上限、冰冷層數上限）
static func burn_cap(p: Player) -> int:
	return _p(&"fire").max_stacks + roundi(p.stats.value(&"burn_max_stacks"))


static func chill_cap(p: Player) -> int:
	return _p(&"cold").max_stacks + roundi(p.stats.value(&"chill_max_stacks"))


static func _fire_burst(world: World, p: Player, e: Enemy) -> void:
	var c := _p(&"fire")
	e.clear_burn()
	var damage := elem_damage(p, c.burst_pct) * p.stats.value(&"burn_damage")
	world.emit_event("fx:explosion", {"pos": e.pos, "height": e.ground_height, "radius": c.burst_radius, "color": Enemy.BURN_COLOR})
	world.emit_event("sfx:cue", {"cue": "explosion", "pos": e.pos})
	for t in world.enemies.duplicate():
		if t.is_dead or t.team == p.team or t.pos.distance_to(e.pos) > c.burst_radius + t.radius:
			continue
		var hit := ItemEffects.proc_hit(damage, t, Enemy.BURN_COLOR, 4.0, &"fire")
		hit["no_status"] = true
		hit["origin"] = e.pos
		Combat.apply_damage(world, p, t, hit)


# 對 e 加 stacks 層冰冷（算 p 的）：沒有冰霜羈絆最多 1 層；第 2 階疊滿凍結（Boss 不會被凍結，停在滿層）
static func add_chill(_world: World, p: Player, e: Enemy, stacks: int) -> void:
	var c := _p(&"cold")
	var t := tier(p, &"cold")
	var cap := chill_cap(p)
	var n := e.add_chill(stacks, cap if t >= 1 else 1, c.slow_per_stack + p.stats.value(&"chill_slow"), c.duration)
	if t >= 2 and n >= cap and not e.def.get("freeze_immune", false):
		e.clear_chill()
		var coffin := has_branch(p, &"br_ice_coffin")
		e.apply_freeze(WeaponDropDefs.BRANCH.coffin_time if coffin else c.freeze_time * p.stats.value(&"freeze_time"))
		e.ice_coffin = coffin
		e.freeze_source_id = p.id


# ── 命中前後（Combat._apply_damage）──

# 這一下的傷害倍率與要不要必爆擊：失衡的怪受傷變多（誰打都算）；玩家的：打凍結的怪碎冰加傷、無視物理抗性、
# 對失衡必爆擊（物理 5 階）、招架後的下一擊（防禦 2 階，用掉）
static func pre_hit(source: Entity, target: Entity, hit: Dictionary, is_proc: bool) -> Dictionary:
	_pre.mul = 1.0
	_pre.crit = false
	_pre.shatter = false
	if not target is Enemy:
		return _pre
	var e := target as Enemy
	if e.stagger_timer > 0.0:
		_pre.mul *= _p(&"phys").stagger_damage_taken
	if not source is Player:
		return _pre
	var p := source as Player
	if e.frozen_timer > 0.0 and not e.ice_coffin and not hit.get("no_status", false) and tier(p, &"cold") >= 2:
		_pre.mul *= _p(&"cold").shatter_mul
		_pre.shatter = true
	if hit.get("damage_type", &"phys") == &"phys" and tier(p, &"phys") >= 4:
		var r := e.stats.value(&"resist_phys")
		if r > 0.0:
			var before := 1.0 - clampf(r, StatDefs.RESIST_MIN, StatDefs.RESIST_MAX)
			_pre.mul *= (1.0 - clampf(r * (1.0 - _p(&"phys").resist_pierce), StatDefs.RESIST_MIN, StatDefs.RESIST_MAX)) / before
	if not is_proc:
		if e.stagger_timer > 0.0 and tier(p, &"phys") >= 5:
			_pre.crit = true
		if p.riposte_timer > 0.0:
			p.riposte_timer = 0.0
			_pre.mul *= _p(&"guard").riposte_mul
			_pre.crit = true
	return _pre


# 玩家打到怪之後（扣完血、事件之後，道具的命中效果之前）：疊燃燒 / 冰冷 / 失衡、撞怪、碎冰、處決
static func on_hit(world: World, p: Player, e: Enemy, hit: Dictionary, dealt: float, knockback: float, is_proc: bool, shatter: bool) -> void:
	var type: StringName = hit.get("damage_type", &"phys")
	if shatter:
		e.frozen_timer = 0.0
		world.emit_event("fx:explosion", {"pos": e.pos, "height": e.ground_height, "radius": 1.2, "color": Enemy.CHILL_COLOR})
		if tier(p, &"cold") >= 3:
			_shards(world, p, e)
	if e.ice_coffin and e.frozen_timer > 0.0 and dealt > 0.0 and not hit.get("coffin_share", false):
		_coffin_share(world, p, e, dealt)
	if hit.get("no_status", false) or e.is_dead:
		return
	match type:
		&"fire":
			if tier(p, &"fire") >= 1:
				add_burn(world, p, e, 1)
		&"cold":
			if tier(p, &"cold") >= 1:
				add_chill(world, p, e, 1)
		&"phys":
			if not is_proc:
				var c := _p(&"phys")
				var t := tier(p, &"phys")
				if t >= 2:
					e.add_poise(dealt * (c.poise_finisher_mul if hit.get("finisher", false) else 1.0) * p.stats.value(&"poise_gain"), c.poise_ratio, c.poise_decay, c.stagger_time)
				if t >= 3 and knockback > 0.0:
					e.ram_timer = c.ram_window
					e.ram_damage = dealt * c.ram_ratio
					e.ram_source_id = p.id
				if t >= 5 and e.stagger_timer > 0.0 and not e.is_boss() and e.hp < e.max_hp * c.execute_hp:
					e.hp = 0.0
					e.die(p.id)


# 分支・冰棺：冰棺受到的傷害 coffin_share 倍分給 coffin_radius 內最近的 coffin_targets 隻（冰霜、不再疊狀態、不再分）
static func _coffin_share(world: World, p: Player, e: Enemy, dealt: float) -> void:
	var b: Dictionary = WeaponDropDefs.BRANCH
	var near: Array[Enemy] = []
	for o in world.enemies:
		if o != e and not o.is_dead and o.team == e.team and o.pos.distance_to(e.pos) <= b.coffin_radius + o.radius:
			near.append(o as Enemy)
	near.sort_custom(func(a: Enemy, c: Enemy) -> bool: return a.pos.distance_squared_to(e.pos) < c.pos.distance_squared_to(e.pos))
	for i in mini(b.coffin_targets, near.size()):
		var hit := ItemEffects.proc_hit(dealt * b.coffin_share, near[i], Enemy.CHILL_COLOR, 0.0, &"cold")
		hit["no_status"] = true
		hit["coffin_share"] = true
		hit["origin"] = e.pos
		Combat.apply_damage(world, p, near[i], hit)


# 碎冰噴出的冰錐：從怪的位置往四周平均射出（冰霜傷害、不再疊冰冷）
static func _shards(world: World, p: Player, e: Enemy) -> void:
	var c := _p(&"cold")
	for i in c.shards:
		var a: float = TAU * i / c.shards
		world.spawn_projectile(Projectile.new(world, {
			"owner": p, "pos": e.pos, "direction": MathUtil.dir_from_angle(a), "speed": c.shard_speed, "range": c.shard_range,
			"radius": 0.25, "damage": elem_damage(p, c.shard_pct), "damage_type": &"cold", "color": Enemy.CHILL_COLOR,
			"visual": &"arrow", "proc": true, "no_stagger": true, "blockable": false, "no_status": true,
			"altitude": e.ground_height + Config.HEIGHT.bolt_altitude,
		}))


# 怪死掉時（Enemy._on_died）：燃燒傳出去（火焰 3 階）；冰霜 3 階凍住的不發動死亡效果
static func on_enemy_died(world: World, e: Enemy) -> void:
	if e.frozen_timer > 0.0 and e.freeze_source_id != 0:
		var fp := world.entities.get(e.freeze_source_id) as Player
		if fp != null and tier(fp, &"cold") >= 3:
			e.no_death_effect = true
	if e.burn_timer <= 0.0 or e.burn_stacks <= 0:
		return
	var p := world.entities.get(e.burn_source_id) as Player
	if p == null or tier(p, &"fire") < 3:
		return
	var c := _p(&"fire")
	var near: Array[Enemy] = []
	for o in world.enemies:
		if o == e or o.is_dead or o.team != e.team or o.pos.distance_to(e.pos) > c.spread_range:
			continue
		near.append(o as Enemy)
	near.sort_custom(func(a: Enemy, b: Enemy) -> bool: return a.pos.distance_squared_to(e.pos) < b.pos.distance_squared_to(e.pos))
	for i in mini(c.spread_count, near.size()):
		near[i].add_burn(p.id, e.burn_stack_dps, c.duration, e.burn_stacks, burn_cap(p))


# ── 防禦 ──

# 招架成功（Player.try_block，權威端）：回血、下一擊必爆擊、衝擊波消掉附近怪的投射物
static func on_parry(world: World, p: Player) -> void:
	var t := tier(p, &"guard")
	if t < 1:
		return
	var c := _p(&"guard")
	var healed := p.heal(p.max_hp * c.parry_heal)
	if healed > 0.0:
		world.emit_event("entity:healed", {"target_id": p.id, "amount": healed})
	if t >= 2:
		p.riposte_timer = c.riposte_time
	if t >= 3:
		for pr in world.projectiles:
			if not pr.is_removed and pr.team != p.team and pr.pos.distance_to(p.pos) <= c.wave_radius:
				pr.remove()
		world.emit_event("fx:explosion", {"pos": p.pos, "height": p.ground_height, "radius": c.wave_radius, "color": BondDefs.BONDS.guard.color})


# 玩家被怪打到（Combat，扣血之後）：防禦 3 階把實際扣的血 reflect 倍反彈給攻擊者
static func on_hurt(world: World, p: Player, attacker: Entity, dealt: float) -> void:
	if dealt <= 0.0 or not attacker is Enemy or attacker.is_dead or tier(p, &"guard") < 3:
		return
	var hit := ItemEffects.proc_hit(dealt * _p(&"guard").reflect, attacker, Color("d0d0d0"))
	hit["no_status"] = true
	Combat.apply_damage(world, p, attacker, hit)


# ── 鬼火 ──

# 這位玩家該有的鬼火：每顆一個屬性。鬼火燈（wisp_orb 能力）自帶；第 1 階起其他鬼火道具也各帶 1 顆秘術；
# 武器詞條的額外鬼火（wisp_count）各 1 顆秘術；第 3 階數量加倍
static func wisp_plan(p: Player) -> Array[StringName]:
	var out: Array[StringName] = []
	var t := tier(p, &"wisp")
	var seen := {}
	for it: Dictionary in p.items:
		if seen.has(it.id):
			continue
		seen[it.id] = true
		var def: Dictionary = ItemDefs.ITEMS[it.id]
		var own := false
		for eff: Dictionary in def.effects:
			if eff.get("ability", &"") == &"wisp_orb":
				own = true
				for i in eff.count:
					out.append(eff.damage_type)
		if not own and t >= 1 and def.get("bonds", []).has(&"wisp"):
			out.append(&"arcane")
	for i in roundi(p.stats.value(&"wisp_count")):
		out.append(&"arcane")
	if t >= 3:
		out.append_array(out.duplicate())
	return out


# 每步（Player._tick_timers）：招架後的計時、噬魂燈的計時；權威端讓場上的鬼火跟 wisp_plan 一致（換層清掉投射物後也會補回來）
static func update_player(p: Player, dt: float) -> void:
	p.riposte_timer = maxf(0.0, p.riposte_timer - dt)
	p.wisp_frenzy_timer = maxf(0.0, p.wisp_frenzy_timer - dt)
	if p.world.is_authority:
		sync_wisps(p)


static func sync_wisps(p: Player) -> void:
	var alive := 0
	for w in p.wisps:
		if not w.is_removed:
			alive += 1
	var same := alive == p.wisps.size() and p.wisps.size() == p.wisp_plan.size()
	if same:
		for i in p.wisps.size():
			if p.wisps[i].damage_type != p.wisp_plan[i]:
				same = false
				break
	if same:
		return
	for w in p.wisps:
		if not w.is_removed:
			w.remove()
	p.wisps.clear()
	if p.is_dead:
		return
	for i in p.wisp_plan.size():
		var w := OrbitWisp.new(p.world, p, p.wisp_plan[i], i, p.wisp_plan.size())
		p.world.spawn_projectile(w)
		p.wisps.append(w)


# 招魂幡：所有鬼火馬上衝向最近的怪
static func rally_wisps(p: Player) -> void:
	for w in p.wisps:
		if not w.is_removed:
			w.dash_timer = 0.0
			w.forced_dash = true
