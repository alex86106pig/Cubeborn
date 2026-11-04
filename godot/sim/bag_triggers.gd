# 觸發袋的發動（規則在 docs/設計方向.md「觸發袋」）：時機到了，接在對應那一邊的那種袋子把裡面的效果與技能一起放出來
#   左邊的袋子只被普攻觸發、右邊的只被右鍵招式觸發（Combat 的 hit.attack / Player.attack_tag）；下方的不分按鍵；上方的按鍵袋由 ActiveSlots 按數字鍵發動
#   同一袋裡沒有順序，由左到右、由上到下依序放；每個效果耗魔（道具強度 × BagDefs.EFFECT_MANA_PER_POWER）、技能照自己的耗魔，魔力不夠的跳過
#   效果的數字照道具資料（ItemDefs 的 on / do 那筆），時機與機率不看；修飾作用在同一袋的技能（ActiveSlots.cast_context）
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
	for b in p.loadout.bags:
		if b.kind == kind and BagDefs.SIDES[b.side].source == source and _icd_ready(p, b):
			run_bag(world, p, b, target, damage)


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
	var scaled: bool = b.mul != 1.0
	if scaled:
		p.set_stat_source(&"bag_mul", [[&"damage", Stats.MUL, b.mul]])   # 效果用武器基礎傷害算的部分（飛刀、落雷…）
	for e in contents(b):
		match ItemDefs.role_of(e.id):
			ItemDefs.ROLE_EFFECT:
				if run_effect(world, p, e.id, target, damage * b.mul):
					count += 1
			ItemDefs.ROLE_SKILL:
				if cast_skill(p, b, e, target):
					count += 1
	if scaled:
		p.remove_stat_source(&"bag_mul")
	return count


# 效果的道具資料那一筆（時機與機率不看）：觸發道具是 on / do 那筆；數值改成的效果（蝙蝠牙）是那筆屬性
static func effect_data(id: StringName) -> Dictionary:
	for eff: Dictionary in ItemDefs.ITEMS[id].effects:
		if eff.has("do") or (BagDefs.EFFECT_ITEMS.has(id) and eff.has("stat")):
			return eff
	return {}


static func effect_mana(id: StringName) -> float:
	return ItemDefs.ITEMS[id].power * BagDefs.EFFECT_MANA_PER_POWER


# 放一個效果：魔力不夠、需要怪當目標卻找不到就不放（回傳 false）
static func run_effect(world: World, p: Player, id: StringName, target: Entity, damage: float) -> bool:
	var eff := effect_data(id)
	var cost := effect_mana(id)
	if eff.is_empty() or not p.has_mana(cost):
		return false
	var effect := ItemDefs.effect_of(id)
	# 沒有目標（計時、翻滾、出手、按鍵）找最近的怪；打死的怪照樣是位置（爆炸、召喚在那裡），只有一定要活怪的效果才換一隻
	if target == null or target.is_removed or (ENEMY_TARGET.has(effect) and target is Enemy and target.is_dead):
		target = _nearest_enemy(world, p)
	if target == null and ENEMY_TARGET.has(effect):
		return false
	if target == null:
		target = p
	if damage <= 0.0:
		damage = p.pct_damage(1.0)
	p.spend_mana(cost)
	if effect == &"heal":
		var healed := p.heal(eff.value)
		if healed >= 0.5:
			world.emit_event("entity:healed", {"target_id": p.id, "amount": healed})
		return true
	var proc := {"do": eff.do, "on": eff.get("on", &""), "effect": eff, "chance": 1.0, "count": 1, "item": id}
	(ItemEffects.ACTIONS[eff.do] as ItemEffects.Action).run(world, p, target, damage, proc)
	return true


# 放袋子裡的一個技能：有目標就在目標身上放，沒有就照按鍵的放法；照技能自己的條件與耗魔，加上同一袋的修飾與袋子倍率
static func cast_skill(p: Player, b: Dictionary, e: Dictionary, target: Entity = null) -> bool:
	var at: Entity = null if target == null or target.is_removed else target
	var slot := ActiveSlots.slot_of(p, b, e)
	if not ActiveSlots.can_cast(p, slot, at):
		return false
	ActiveSlots.cast(p, slot, at)
	return true


static func _nearest_enemy(world: World, p: Player) -> Enemy:
	var best: Enemy = null
	var best_d := BagDefs.AUTO_TARGET_RANGE * BagDefs.AUTO_TARGET_RANGE
	for x in world.enemies:
		var e := x as Enemy
		if e == null or e.is_dead or e.is_removed or e.team == p.team:
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
