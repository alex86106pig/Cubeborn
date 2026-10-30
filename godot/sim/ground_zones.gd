# 地上的持續區域（F7 驅魔權杖的聖光圈、膨脹屍的腐氣）：每 tick_interval 秒對範圍內的隊友回血、敵人造成持續傷害
# 存在 world.zones（Dictionary，不是實體：畫面只靠建立時的事件，連線不用進快照）
# 玩家方的畫圈（fx:telegraph）；怪物的不畫圈（visual = &"gas" → fx:gas_cloud 一團煙，設計方向「怪物攻擊不畫紅圈」）
# 持續傷害不算「命中」（hit.proc）：不爆擊、不觸發道具效果、不讓怪硬直（武器構想「持續傷害不觸發道具」）
class_name GroundZones

const TICK_INTERVAL := 0.5


# zone：pos、radius、duration、owner_id、heal_per_sec（隊友每秒回血）、damage_per_sec（敵人每秒傷害）、damage_type、color
# 選填 hits_all：玩家與怪都受傷（不分隊伍，不含自己）；visual：&"gas" = 畫成一團煙（不畫圈）、&"fire" = 一團火
# 選填 smoke：煙霧彈（第 7 步），站在裡面的玩家閃避 + smoke、裡面的怪打人一半打偏（Enemy.blind_timer）
# 選填 burn_per_sec：站在上面的怪每秒加幾層燃燒（火油罐的殘火，算放的玩家、照他的火焰羈絆，BondEffects.add_burn）
static func add(world: World, zone: Dictionary) -> void:
	var z := zone.duplicate()
	z.remaining = zone.duration
	z.tick_timer = TICK_INTERVAL
	z.burn_carry = 0.0
	if world.is_authority:   # 客戶端預測自己的出招時只畫圈，回血與傷害以房主為準
		world.zones.append(z)
	var at := {"pos": z.pos, "height": world.terrain.ground_at(z.pos), "radius": z.radius, "color": z.color, "life": z.duration}
	var visual: StringName = z.get("visual", &"")
	if visual == &"gas" or visual == &"fire":
		at["fire"] = visual == &"fire"
		world.emit_event("fx:gas_cloud", at)
	else:
		at["fill"] = true
		world.emit_event("fx:telegraph", at)


static func update(world: World, dt: float) -> void:
	for i in range(world.zones.size() - 1, -1, -1):
		var z: Dictionary = world.zones[i]
		z.remaining -= dt
		z.tick_timer -= dt
		if z.tick_timer <= 1e-6:
			z.tick_timer += TICK_INTERVAL
			_tick(world, z)
		if z.remaining <= 1e-6:
			world.zones.remove_at(i)


static func _tick(world: World, z: Dictionary) -> void:
	var owner: Entity = world.entities.get(z.owner_id)
	if z.get("smoke", 0.0) > 0.0:
		for p in world.player_list:
			if not p.is_dead and p.pos.distance_to(z.pos) <= z.radius + p.radius:
				p.add_buff(&"smoke", TICK_INTERVAL * 2.0, {"stats": [[&"dodge", Stats.ADD, z.smoke]]})
		for e in world.enemies:
			if not e.is_dead and e.team != &"player" and e.pos.distance_to(z.pos) <= z.radius + e.radius:
				(e as Enemy).blind_timer = TICK_INTERVAL * 2.0
	if z.get("burn_per_sec", 0.0) > 0.0 and owner is Player:
		z.burn_carry += z.burn_per_sec * TICK_INTERVAL
		var stacks := floori(z.burn_carry + 1e-6)
		if stacks > 0:
			z.burn_carry -= stacks
			for e in world.enemies.duplicate():
				if not e.is_dead and e.team != owner.team and e.pos.distance_to(z.pos) <= z.radius + e.radius:
					BondEffects.add_burn(world, owner as Player, e as Enemy, stacks)
	if z.get("heal_per_sec", 0.0) > 0.0:
		for p in world.player_list:
			if p.is_dead or p.is_downed or p.pos.distance_to(z.pos) > z.radius + p.radius:
				continue
			var healed := p.heal(z.heal_per_sec * TICK_INTERVAL)
			if healed > 0.0:
				world.emit_event("entity:healed", {"target_id": p.id, "amount": healed})
	if z.get("damage_per_sec", 0.0) > 0.0 and owner != null:
		var hits_all: bool = z.get("hits_all", false)
		var targets: Array[Entity] = []
		if hits_all:
			targets.append_array(world.player_list)
			targets.append_array(world.enemies)
		elif owner.team == &"player":
			targets.append_array(world.enemies)   # 玩家放的只打怪（不誤傷隊友）
		else:
			targets.append_array(world.player_list)   # 怪放的（守墓人的殘火）只打玩家
		for e in targets:
			if e == owner or e.is_dead or (not hits_all and e.team == owner.team) or e.pos.distance_to(z.pos) > z.radius + e.radius:
				continue
			if e is Player and not (e as Player).is_targetable():
				continue
			Combat.apply_damage(world, owner, e, {
				"damage": z.damage_per_sec * TICK_INTERVAL, "damage_type": z.damage_type, "proc": true, "no_stagger": true,
				"knockback": 0.0, "origin": z.pos, "band": Vector2(-INF, INF), "color": z.color, "no_status": true,
			})
