# 觸發袋的發動（規則在 docs/設計方向.md「觸發袋」）：時機到了，接在對應那一邊的那種袋子把裡面的效果與技能一起放出來
#   左邊的袋子只被普攻觸發、右邊的只被右鍵招式觸發（Combat 的 hit.attack / Player.attack_tag）；下方的不分按鍵；上方的按鍵袋由 ActiveSlots 按數字鍵發動
#   左邊的命中袋、出手袋每打 / 出手 N 下才發動一次（N = 武器的 trigger_every，許家慶 2026-11-05：取代機率，打得快的武器 N 大）；
#   同一袋裡沒有順序，由左到右、由上到下依序放；每個效果耗魔（道具強度 × BagDefs.EFFECT_MANA_PER_POWER）、技能照自己的耗魔，魔力不夠的跳過
#   效果的數字照道具資料（ItemDefs 的 on / do 那筆），時機與機率不看；修飾作用在透明格蓋住的技能與效果（ActiveSlots.cast_context、run_effect 的 mods）
#   有目標的時機（命中、擊殺、受傷、招架）效果與技能都在目標身上發動（技能怎麼算在 SkillBehaviors.aim_at）；沒有目標的照舊
#   袋子放出來的效果是道具效果（proc，不觸發命中）、技能的傷害沒有 attack 標記：都不會再觸發袋子，不會連鎖
# 只在權威端執行
class_name BagTriggers

# 一定要有一隻怪當目標的效果（沒有就跳過）；其他的效果沒有目標時以自己為中心
const ENEMY_TARGET: Array[StringName] = [&"poison", &"freeze", &"ignite", &"chill", &"chain_lightning", &"reflect"]


# 袋子裡的東西，依放的順序（由左到右、由上到下）
static func contents(b: Dictionary) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.assign(b.entries)
	list.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return a.cell.x < c.cell.x or (a.cell.x == c.cell.x and a.cell.y < c.cell.y))
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


# 發動一個袋子：裡面的效果與技能依序放；回傳放出了幾個
static func run_bag(world: World, p: Player, b: Dictionary, target: Entity, damage: float) -> int:
	var count := 0
	var mul := BagDefs.power_of(b)   # 大小倍率 × 種類與邊的倍率
	var fired := StringName("fired:" + String(b.kind))
	p.trigger_moments[fired] = p.trigger_moments.get(fired, 0) + 1   # 發動了幾次（檢查與自動試玩用）
	var scaled: bool = mul != 1.0
	for e in contents(b):
		match ItemDefs.role_of(e.id):
			ItemDefs.ROLE_EFFECT:
				# 效果用武器基礎傷害算的部分（飛刀、落雷…）靠攻擊力屬性乘上倍率；技能的倍率在 ActiveSlots.cast_context（原本兩邊都乘，技能吃到兩次）
				if scaled:
					p.set_stat_source(&"bag_mul", [[&"damage", Stats.MUL, mul]])
				if run_effect(world, p, e.id, target, damage * mul, ActiveSlots.mod_ids_on(b, e), mul):
					count += 1
				if scaled:
					p.remove_stat_source(&"bag_mul")
			ItemDefs.ROLE_SKILL:
				if cast_skill(p, b, e, target):
					count += 1
	return count


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
