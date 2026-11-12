# 觸發袋的發動（規則在 docs/設計方向.md「觸發袋」）：時機到了，接在對應那一邊的那種袋子把裡面的效果與技能一招接一招放出來
#   左邊的袋子只被普攻觸發、右邊的只被右鍵招式觸發（Combat 的 hit.attack / Player.attack_tag）；下方的不分按鍵；上方的按鍵袋由 ActiveSlots 按數字鍵發動
#   左邊的命中袋、出手袋每打 / 出手 N 下才發動一次（N = 武器的 trigger_every，許家慶 2026-11-05：取代機率，打得快的武器 N 大）；
#   同一袋由左到右、由上到下一招接一招放（技能銜接，CHAIN_GAP）；每個效果耗魔（道具強度 × BagDefs.EFFECT_MANA_PER_POWER）、技能照自己的耗魔，放不出來或打空就停
#   效果的數字照道具資料（ItemDefs 的 on / do 那筆），時機與機率不看；修飾作用在透明格蓋住的技能與效果（ActiveSlots.cast_context、run_effect 的 mods）
#   有目標的時機（命中、擊殺、受傷、招架）效果與技能都在目標身上發動（技能怎麼算在 SkillBehaviors.aim_at）；沒有目標的照舊
#   袋子放出來的效果是道具效果（proc，不觸發命中）、技能的傷害沒有 attack 標記：都不會再觸發袋子，不會連鎖
# 只在權威端執行
class_name BagTriggers

# 一定要有一隻怪當目標的效果（沒有就跳過）；其他的效果沒有目標時以自己為中心
const ENEMY_TARGET: Array[StringName] = [&"poison", &"freeze", &"ignite", &"chill", &"chain_lightning", &"reflect"]


# 袋子裡的東西，依放的順序：照畫面上的位置左上 → 右下（一列一列，同一列由左到右；許家慶 2026-11-06）
# 左右兩邊的袋子在畫面上是轉過的，所以用盤上座標（Loadout.board_cell）排，不用袋子自己的格子座標；多格的用它最左上那一格
static func contents(b: Dictionary) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.assign(b.entries)
	var key := {}
	for e: Dictionary in list:
		var best := Vector2i(1 << 20, 1 << 20)
		for c in Inventory.cells_of(e.id, e.rot):
			var bc := Loadout.board_cell(b, e.cell + c)
			if bc.y < best.y or (bc.y == best.y and bc.x < best.x):
				best = bc
		key[e] = best
	list.sort_custom(func(a: Dictionary, c: Dictionary) -> bool:
		var ka: Vector2i = key[a]
		var kc: Vector2i = key[c]
		return ka.y < kc.y or (ka.y == kc.y and ka.x < kc.x))
	return list


# 時機到了：kind 是袋子種類；source 是哪個動作（&"primary" 普攻、&"secondary" 右鍵、&"" 不分按鍵）；
# target 是命中 / 擊殺的那隻怪或打到自己的怪（沒有就 null）、damage 是那一下的傷害
static func fire(world: World, p: Player, kind: StringName, source: StringName, target: Entity, damage: float) -> void:
	if not world.is_authority or p.is_dead or p.is_downed:
		return
	_count_moment(world, p, StringName("%s:%s" % [kind, source]))
	for b in p.loadout.bags:
		if b.kind == kind and BagDefs.SIDES[b.side].source == source and _ready(world, p, b, source):
			run_bag(world, p, b, target, damage)


# 時機發生幾次（不管有沒有袋子；同一步打到好幾隻算一次）：自動試玩與平衡表量各種袋子的觸發頻率
static func _count_moment(world: World, p: Player, key: StringName) -> void:
	var tick_key := StringName("tick:" + String(key))
	if p.trigger_moments.get(tick_key, -1) == world.tick:
		return
	p.trigger_moments[tick_key] = world.tick
	p.trigger_moments[key] = p.trigger_moments.get(key, 0) + 1


# 這一袋這次發不發動：左邊的命中袋、出手袋數到武器的 trigger_every 下才發動（同一步打到好幾隻只算一下）；其他照內部冷卻
static func _ready(world: World, p: Player, b: Dictionary, source: StringName) -> bool:
	if source != &"primary" or not BagDefs.COUNTED.has(b.kind):
		return _icd_ready(p, b)
	if p.bag_count_tick.get(b.uid, -1) == world.tick:
		return false
	p.bag_count_tick[b.uid] = world.tick
	var n: int = maxi(1, p.weapon.get("trigger_every", 1))
	var c: int = p.bag_counts.get(b.uid, 0) + 1
	p.bag_counts[b.uid] = 0 if c >= n else c
	return c >= n


# 同一袋的內部冷卻（BagDefs.BAGS 的 icd）：好了回傳 true 並開始計時
static func _icd_ready(p: Player, b: Dictionary) -> bool:
	var t: float = BagDefs.BAGS[b.kind].get("icd", 0.0)
	if t <= 0.0:
		return true
	var key := StringName("bag:%s" % b.uid)
	if p.proc_timers.has(key):
		return false
	p.proc_timers[key] = t
	return true


# 技能銜接（許家慶 2026-11-06，mockups/技能銜接.html 方案 1 + 2 + 3）：同一袋由左到右一招一招放，間隔 CHAIN_GAP 秒；
#   每一招從前一招最後打到的地方放（打到的目標裡離這一招中心最遠的那隻）；前一招放不出來（魔力不夠、條件不符）或打空就停，後面的不放、不扣魔
#   手上的武器放不出來、也沒蓋幻影的技能（ActiveSlots.slot_of 的 fits）不算斷：跳過、不扣魔，同一步接下一招，目標沿用
#   「打空」只看當下就知道結果的招式（INSTANT_HIT 的技能、有打出傷害的效果）；投射物、晚一點落下的、增益、召喚、衝刺放出來就算成功，下一招沿用原本的目標
const CHAIN_GAP := 0.15
const INSTANT_HIT: Array[StringName] = [&"nova", &"cone", &"chain", &"ambush", &"line", &"reaver", &"grudge", &"bury"]


# 發動一個袋子：第一招這一步放，後面的照技能銜接排進 World.delayed；回傳這一步放出了幾個（含共鳴帶動的）
# 橘色的袋子規則（SkillDefs 的 bag_rule）：血契 = 這一袋扣生命、傷害 ×power（在 BagDefs.power_of）；回響 = 整串放完 delay 秒後技能再放一次；
# 共鳴 = 同一邊緊鄰的袋子也發動一次（resonating = 被帶動的，不再帶動別的）
static func run_bag(world: World, p: Player, b: Dictionary, target: Entity, damage: float, resonating := false) -> int:
	var fired := StringName("fired:" + String(b.kind))
	p.trigger_moments[fired] = p.trigger_moments.get(fired, 0) + 1   # 發動了幾次（檢查與自動試玩用）
	var steps: Array[Dictionary] = []
	for e in contents(b):
		var role := ItemDefs.role_of(e.id)
		if role == ItemDefs.ROLE_EFFECT or (role == ItemDefs.ROLE_SKILL and SkillDefs.SKILLS[e.id].behavior != &"bag_rule"):
			steps.append(e)
	var chain := {"b": b, "steps": steps, "i": 0, "target_id": target.id if target != null else 0, "damage": damage, "fired": [] as Array[Dictionary]}
	var count := _chain_step(world, p, chain)
	if BagDefs.has_rule(b, &"resonance") and not resonating:
		count += _resonate(world, p, b, target, damage)
	return count


# 放這一串的下一招；成功而且還有下一招就 CHAIN_GAP 秒後再來；回傳這一次放出了幾個（0 或 1）
static func _chain_step(world: World, p: Player, chain: Dictionary) -> int:
	var b: Dictionary = chain.b
	var steps: Array[Dictionary] = chain.steps
	if chain.i >= steps.size():
		_chain_end(p, chain)
		return 0
	var e: Dictionary = steps[chain.i]
	chain.i += 1
	if not b.entries.has(e):   # 中間被拿出袋子了：跳過、照樣往下
		return _chain_step(world, p, chain)
	if ItemDefs.is_skill(e.id) and not ActiveSlots.slot_of(p, b, e).fits:   # 手上的武器放不出來（也沒蓋幻影）：跳過、不扣魔，馬上接下一招
		return _chain_step(world, p, chain)
	var target := world.entities.get(chain.target_id) as Entity
	if target != null and target.is_removed:
		target = null
	var was_paying := p.pay_with_hp
	p.pay_with_hp = BagDefs.has_rule(b, &"blood_pact")
	Combat.begin_record()
	var result := _run_entry(world, p, b, e, target, chain.damage)
	var hits := Combat.end_record()
	p.pay_with_hp = was_paying
	if not result.ok or (result.instant and hits.is_empty()):
		_chain_end(p, chain)   # 斷了：後面的不放
		return 1 if result.ok else 0
	if result.skill:
		chain.fired.append(e)
	if not hits.is_empty():   # 接力：下一招從這一招打到的、離中心最遠的那隻放
		var center: Vector2 = target.pos if target != null else p.pos
		var far: Entity = hits[0]
		for h in hits:
			if h.pos.distance_squared_to(center) > far.pos.distance_squared_to(center):
				far = h
		chain.target_id = far.id
	if chain.i >= steps.size():
		_chain_end(p, chain)
	else:
		SkillBehaviors.later(p, CHAIN_GAP, func() -> void: _chain_step(world, p, chain))
	return 1


# 一串放完（或斷了）：有回響就把放出的技能再放一次
static func _chain_end(p: Player, chain: Dictionary) -> void:
	var fired: Array[Dictionary] = chain.fired
	if BagDefs.has_rule(chain.b, &"echo") and not fired.is_empty():
		_echo(p, chain.b, fired, p.world.entities.get(chain.target_id) as Entity)
	chain.fired = [] as Array[Dictionary]


# 放袋子裡的一個東西（效果或技能）：{ ok 放出來了, instant 當下就知道有沒有打到（打空算斷）, skill 是技能 }
static func _run_entry(world: World, p: Player, b: Dictionary, e: Dictionary, target: Entity, damage: float) -> Dictionary:
	var mul := BagDefs.power_of(b)   # 大小倍率 × 種類與邊的倍率（× 血契）
	if ItemDefs.role_of(e.id) == ItemDefs.ROLE_EFFECT:
		var short := not p.has_mana(effect_cost(b, e))
		# 效果用武器基礎傷害算的部分（飛刀、落雷…）靠攻擊力屬性乘上倍率；技能的倍率在 ActiveSlots.cast_context（原本兩邊都乘，技能吃到兩次）
		if mul != 1.0:
			p.set_stat_source(&"bag_mul", [[&"damage", Stats.MUL, mul]])
		var ok := run_effect(world, p, e.id, target, damage * mul, ActiveSlots.mod_ids_on(b, e), mul)
		if mul != 1.0:
			p.remove_stat_source(&"bag_mul")
		_log_cast(p, e.id, ok, short)
		return {"ok": ok, "instant": false, "skill": false}
	var slot := ActiveSlots.slot_of(p, b, e)
	var short: bool = slot.def.has("mana") and not p.has_mana(ActiveSlots.mana_cost(p, slot))
	var ok := cast_skill(p, b, e, target)
	_log_cast(p, e.id, ok, short)
	return {"ok": ok, "instant": slot.def.has("damage_pct") and INSTANT_HIT.has(slot.def.behavior), "skill": true}


# 回響：delay 秒後把這一袋剛放出的技能再放一次（傷害 × mul、耗魔 × mana_share；那時放不出來的跳過）
static func _echo(p: Player, b: Dictionary, entries: Array[Dictionary], target: Entity) -> void:
	var rule: Dictionary = SkillDefs.SKILLS.echo
	var target_id := target.id if target != null else 0
	SkillBehaviors.later(p, rule.delay, func() -> void:
		var was_paying := p.pay_with_hp
		p.pay_with_hp = BagDefs.has_rule(b, &"blood_pact")
		var t := p.world.entities.get(target_id) as Entity
		for e in entries:
			if not b.entries.has(e):
				continue
			var slot := ActiveSlots.slot_of(p, b, e)
			var cost: float = ActiveSlots.mana_cost(p, slot) * rule.mana_share
			var behavior: SkillBehaviors.Behavior = SkillBehaviors.BEHAVIORS[slot.def.behavior]
			var alive: Entity = t if t != null and not t.is_removed else null
			if slot.charges == 0 or not slot.fits or not p.has_mana(cost) or not (behavior.can_use(p, slot.def) if alive == null else behavior.can_use_on(p, slot.def, alive)):
				continue
			var ctx := ActiveSlots.cast_context(p, slot)
			ctx.mul *= rule.mul
			if alive != null:
				SkillBehaviors.aim_at(p, ctx, alive)
			Combat.scoped(ctx.credit, func() -> void: SkillBehaviors.cast(p, slot.def, ctx))
			p.spend_mana(cost)
			_log_cast(p, e.id, true, false)
		p.pay_with_hp = was_paying)


# 共鳴：扣共鳴的耗魔，帶動同一邊緊鄰（offset 剛好接著）的袋子各發動一次；回傳帶動的袋子放出了幾個
static func _resonate(world: World, p: Player, b: Dictionary, target: Entity, damage: float) -> int:
	var cost := p.mana_cost_of(SkillDefs.SKILLS.resonance)
	if not p.has_mana(cost):
		_log_cast(p, &"resonance", false, true)
		return 0
	p.spend_mana(cost)
	_log_cast(p, &"resonance", true, false)
	var n := 0
	for o in p.loadout.bags.duplicate():
		if o != b and o.side == b.side and (o.offset == b.offset + b.length or o.offset + o.length == b.offset):
			n += run_bag(world, p, o, target, damage, true)
	return n


# 遊玩紀錄：放出幾次、魔力不夠跳過幾次（其他原因沒放的，例如沒有目標、次數用完，不記）
static func _log_cast(p: Player, id: StringName, ok: bool, short: bool) -> void:
	if not ok and not short:
		return
	var rec: Array = p.cast_log.get_or_add(id, [0, 0])
	rec[0 if ok else 1] += 1


# 效果的道具資料那一筆（時機與機率不看）：觸發道具是 on / do 那筆；數值改成的效果（蝙蝠牙）是那筆屬性
static func effect_data(id: StringName) -> Dictionary:
	for eff: Dictionary in ItemDefs.ITEMS[id].effects:
		if eff.has("do") or (BagDefs.EFFECT_ITEMS.has(id) and eff.has("stat")):
			return eff
	return {}


static func effect_mana(id: StringName) -> float:
	return ItemDefs.ITEMS[id].power * BagDefs.EFFECT_MANA_PER_POWER


# 袋子 b 裡的效果 e 放一次要多少魔力（含蓋在上面的修飾）
static func effect_cost(b: Dictionary, e: Dictionary) -> float:
	return effect_mana(e.id) * ActiveSlots.mods_mana_mul(ActiveSlots.mod_ids_on(b, e))


# 放一個效果：魔力不夠、需要怪當目標卻找不到就不放（回傳 false）
# mods：蓋在上面、有作用的修飾（第 8 步 f）：耗魔相乘；延長 → proc.area、火焰化 / 霜化 → proc.type、分裂 → SPLIT_DELAY 秒後用 SPLIT_MUL 再放一次
static func run_effect(world: World, p: Player, id: StringName, target: Entity, damage: float, mods: Array[StringName] = [], bag_mul := 1.0) -> bool:
	var eff := effect_data(id)
	var cost := effect_mana(id) * ActiveSlots.mods_mana_mul(mods)
	if eff.is_empty() or not p.has_mana(cost):
		return false
	target = _effect_target(world, p, id, target)
	if target == null:
		return false
	if damage <= 0.0:
		damage = p.pct_damage(1.0)
	p.spend_mana(cost)
	var proc := {"do": eff.get("do", &""), "on": eff.get("on", &""), "effect": eff, "chance": 1.0, "count": 1, "item": id, "area": 1.0}
	var split := false
	for m in mods:
		var sup := ItemDefs.support_of(m)
		match sup.mode:
			&"extend":
				proc.area = 1.5
			&"fire", &"cold":
				proc.type = sup.mode
			&"split":
				split = true
	_do_effect(world, p, id, eff, target, damage, proc)
	if split:
		var first := target
		var again := proc.duplicate()
		again["again"] = true   # 飛刀、斬波的內部冷卻不擋分裂的第二次
		SkillBehaviors.later(p, SkillBehaviors.SPLIT_DELAY, func() -> void:
			var t := _effect_target(world, p, id, first)
			if t == null or p.is_dead:
				return
			# 用武器基礎傷害算的效果（飛刀、斬波、落雷）靠攻擊力屬性：暫時乘上分裂與袋子倍率
			p.set_stat_source(&"split_mul", [[&"damage", Stats.MUL, SkillBehaviors.SPLIT_MUL * bag_mul]])
			_do_effect(world, p, id, eff, t, damage * SkillBehaviors.SPLIT_MUL, again)
			p.remove_stat_source(&"split_mul"))
	return true


# 效果的目標：沒有目標（計時、翻滾、出手、按鍵）找最近的怪；打死的怪照樣是位置（爆炸、召喚在那裡），只有一定要活怪的效果才換一隻；
# 一定要怪卻找不到回傳 null，其他找不到就以自己為中心
static func _effect_target(world: World, p: Player, id: StringName, target: Entity) -> Entity:
	var effect := ItemDefs.effect_of(id)
	if target == null or target.is_removed or (ENEMY_TARGET.has(effect) and target.team != p.team and target.is_dead):
		target = _nearest_enemy(world, p)
	if target == null and not ENEMY_TARGET.has(effect):
		target = p
	return target


static func _do_effect(world: World, p: Player, id: StringName, eff: Dictionary, target: Entity, damage: float, proc: Dictionary) -> void:
	if ItemDefs.effect_of(id) == &"heal":
		var healed := p.heal(eff.value)
		if healed >= 0.5:
			world.emit_event("entity:healed", {"target_id": p.id, "amount": healed})
		return
	Combat.scoped("i:" + String(id), func() -> void: (ItemEffects.ACTIONS[eff.do] as ItemEffects.Action).run(world, p, target, damage, proc))


# 放袋子裡的一個技能：有目標就在目標身上放，沒有就照按鍵的放法；照技能自己的條件與耗魔，加上蓋在上面的修飾與袋子倍率
static func cast_skill(p: Player, b: Dictionary, e: Dictionary, target: Entity = null) -> bool:
	var at: Entity = null if target == null or target.is_removed else target
	var slot := ActiveSlots.slot_of(p, b, e)
	if not ActiveSlots.can_cast(p, slot, at):
		return false
	ActiveSlots.cast(p, slot, at)
	return true


# 敵對陣營裡最近的（玩家找怪與冤魂、冤魂找玩家）
static func _nearest_enemy(world: World, p: Player) -> Entity:
	var best: Entity = null
	var best_d := BagDefs.AUTO_TARGET_RANGE * BagDefs.AUTO_TARGET_RANGE
	for e in Combat.hostiles_of(world, p.team):
		if e.is_removed:
			continue
		var d := e.pos.distance_squared_to(p.pos)
		if d < best_d:
			best_d = d
			best = e
	return best


# 計時袋：每個袋子自己一個計時（BagDefs.BAGS.timer.period）；每步呼叫，只在權威端
static func update_timers(p: Player, dt: float) -> void:
	for b in p.loadout.bags:
		if b.kind != &"timer":
			continue
		var period: float = BagDefs.BAGS.timer.period
		var t: float = p.interval_timers.get(b.uid, period) - dt
		if t <= 0.0:
			t += period
			run_bag(p.world, p, b, null, 0.0)
		p.interval_timers[b.uid] = t
