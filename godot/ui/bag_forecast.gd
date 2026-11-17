# 觸發袋說明框的換算：放一次對一隻怪約打多少、照現在的武器每分鐘約發動幾次（倍率照樣寫在說明框，這裡給玩家乘好的結果）
class_name BagForecast
extends RefCounted


# 說明框的一行：「放一次約 120 傷害（打一隻）· 每分鐘約發動 72 次（照你現在的武器一直打）」；沒有能說的回空字串
static func line(p: Player, b: Dictionary) -> String:
	var parts: Array[String] = []
	var dmg := damage_per_fire(p, b)
	if dmg >= 0.5:
		parts.append("放一次約 %d 傷害（打一隻）" % roundi(dmg))
	var rate := per_minute(p, b)
	if rate > 0.0:
		var how := "照你現在的武器一直打" if BagDefs.COUNTED.has(b.kind) and b.side == &"left" else ("每 %s 秒一次" % String.num(BagDefs.BAGS.timer.period) if b.kind == &"timer" else "自動試玩的平均")
		parts.append("每分鐘約發動 %d 次（%s）" % [roundi(rate), how])
	return " · ".join(parts)


# 每分鐘約發動幾次；按鍵袋（自己按）與沒有資料的回 0
static func per_minute(p: Player, b: Dictionary) -> float:
	if b.kind == &"timer":
		return 60.0 / BagDefs.BAGS.timer.period
	if BagDefs.COUNTED.has(b.kind) and b.side == &"left":
		return p.weapon.get("hits_per_sec", 0.0) * p.stats.value(&"attack_speed") * 60.0 / maxi(1, p.weapon.get("trigger_every", 1))
	return BagDefs.TYPICAL_PER_MIN.get(b.kind, {}).get(b.side, 0.0)


# 放一次全部的效果與技能打在一隻怪身上的傷害（套袋子倍率、修飾換的屬性；還沒算怪的護甲與抗性）：
# 技能照招式的主段（多發的照發數、扇形只算中間那支、持續的照次數；火堆、火痕不算），效果照道具資料；
# 手上武器放不出來的技能、受傷袋看受到多少傷害的效果、連鎖閃電（從那隻往外跳、不打牠）不算
static func damage_per_fire(p: Player, b: Dictionary) -> float:
	var total := 0.0
	var trigger := _trigger_damage(p, b)
	for e: Dictionary in BagTriggers.contents(b):
		match ItemDefs.role_of(e.id):
			ItemDefs.ROLE_SKILL:
				total += _skill_damage(p, b, e)
			ItemDefs.ROLE_EFFECT:
				total += _effect_damage(p, b, e.id, trigger)
	return total


# 觸發那一下的傷害（效果的「觸發那一下的 X%」）：左鍵是普攻一下、右鍵是右鍵招式一下、沒有那一下的袋子用武器傷害 100%（同 BagTriggers.run_effect）；受傷袋看不出來回 -1
static func _trigger_damage(p: Player, b: Dictionary) -> float:
	if b.kind == &"hurt":
		return -1.0
	if b.kind in [&"hit", &"kill"]:
		var move: Dictionary = p.weapon.get("attack" if b.side == &"left" else "special", {})
		if move.has("damage_pct"):
			return p.pct_damage(move.damage_pct)
	return p.pct_damage(1.0)


static func _skill_damage(p: Player, b: Dictionary, e: Dictionary) -> float:
	var slot := ActiveSlots.slot_of(p, b, e)
	var def: Dictionary = slot.def
	if not slot.fits or not def.has("damage_pct"):
		return 0.0
	var ctx := ActiveSlots.cast_context(p, slot)
	var hits := 1
	if def.behavior in [&"rain", &"storm"]:
		hits = roundi(def.duration / def.tick)
	elif def.get("spread", 0.0) == 0.0:
		hits = def.get("count", 1)
	return p.pct_damage(def.damage_pct, ctx.type) * ctx.mul * hits


# 效果（觸發道具改寫的）：觸發那一下的幾 %、或武器傷害的幾 %，再乘袋子倍率（BagTriggers._run_entry：前者乘在 damage、後者靠攻擊力屬性）
static func _effect_damage(p: Player, b: Dictionary, id: StringName, trigger: float) -> float:
	var mul := BagDefs.power_of(b)
	for eff: Dictionary in ItemDefs.ITEMS[id].effects:
		var proc: Dictionary = ItemDefs.PROCS.get(eff.get("do", &""), {})
		var of_hit := -1.0
		var of_weapon := -1.0
		match eff.get("do", &""):
			&"explode":
				of_hit = eff.get("damage_ratio", proc.damage_ratio)
			&"wisp":
				of_hit = proc.damage_ratio
			&"poison":
				of_hit = proc.total_ratio
			&"ignite":
				of_hit = proc.pct_per_sec * proc.duration
			&"throw_knife", &"lightning_strike":
				of_weapon = proc.damage_pct
			&"slash_wave":
				of_weapon = eff.damage_ratio * eff.count
			_:
				continue
		if of_weapon >= 0.0:
			return p.pct_damage(of_weapon) * mul
		return of_hit * trigger * mul if trigger > 0.0 else 0.0
	return 0.0
