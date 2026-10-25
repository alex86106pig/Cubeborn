# 背包、金錢、寶箱、道具與武器：撿取、掉落、詞條、合成、道具資料與效果
# 由 tests/check.gd 呼叫；每個 check_* 回傳 "" = 通過，否則是失敗原因
class_name LootChecks
extends CheckKit

static func _shape_error(cells: Array) -> String:
	if cells.is_empty():
		return "沒有格子"
	var seen := {}
	var max_cell := Vector2i.ZERO
	var min_cell := Vector2i(999, 999)
	for c: Vector2i in cells:
		if seen.has(c):
			return "格子重複 %s" % c
		seen[c] = true
		min_cell = min_cell.min(c)
		max_cell = max_cell.max(c)
	if min_cell != Vector2i.ZERO:
		return "沒有從 (0, 0) 開始（最小 %s）" % min_cell
	var size := max_cell + Vector2i.ONE
	var bag := ItemDefs.BAG_SIZE
	if not ((size.x <= bag.x and size.y <= bag.y) or (size.y <= bag.x and size.x <= bag.y)):
		return "%d×%d 放不進背包" % [size.x, size.y]
	# 上下左右相連
	var stack: Array = [cells[0]]
	var reached := {cells[0]: true}
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if seen.has(c + d) and not reached.has(c + d):
				reached[c + d] = true
				stack.append(c + d)
	if reached.size() != cells.size():
		return "格子沒有相連"
	return ""


static func _params_error(e: Dictionary, table: Dictionary, key: String) -> String:
	if not table.has(e[key]):
		return "%s 不存在：%s" % [key, e[key]]
	for p: String in table[e[key]].get("params", []):
		if not e.has(p):
			return "%s %s 缺少參數 %s" % [key, e[key], p]
	return ""


static func _effect_error(e: Dictionary) -> String:
	var kinds := 0
	for k in ["when", "on", "ability"]:
		if e.has(k):
			kinds += 1
	if kinds > 1:
		return "一筆效果只能是一種：%s" % e
	if e.has("stat") or e.has("when"):
		if not (e.has("stat") and e.has("op") and e.has("value")):
			return "屬性效果缺 stat / op / value：%s" % e
		if not StatDefs.STATS.has(e.stat):
			return "屬性不存在：%s" % e.stat
		if not e.op in [Stats.ADD, Stats.PCT, Stats.MUL]:
			return "運算不存在：%s" % e.op
		if e.op == Stats.MUL and e.value <= 0.0:
			return "相乘的數值必須大於 0：%s" % e
		return _params_error(e, ItemDefs.CONDITIONS, "when") if e.has("when") else ""
	if e.has("on"):
		if not e.has("do"):
			return "觸發效果缺 do：%s" % e
		if e.has("chance") and not (e.chance > 0.0 and e.chance <= 1.0):
			return "機率要在 (0, 1]：%s" % e
		var err := _params_error(e, ItemDefs.TRIGGERS, "on")
		return err if err != "" else _params_error(e, ItemDefs.ACTIONS, "do")
	if e.has("ability"):
		return _params_error(e, ItemDefs.ABILITIES, "ability")
	return "看不出是哪一種效果：%s" % e


static func check_item_defs() -> String:
	for shape: StringName in ItemDefs.SHAPES:
		var err := _shape_error(ItemDefs.SHAPES[shape])
		if err != "":
			return "形狀 %s：%s" % [shape, err]
	var counts := {}
	var names := {}
	for id: StringName in ItemDefs.ITEMS:
		var def: Dictionary = ItemDefs.ITEMS[id]
		for field in ["kind", "name", "rarity", "shape", "desc", "effects"]:
			if not def.has(field):
				return "%s 缺少欄位 %s" % [id, field]
		if names.has(def.name):
			return "名稱重複：%s（%s 與 %s）" % [def.name, names[def.name], id]
		names[def.name] = id
		if not ItemDefs.RARITIES.has(def.rarity):
			return "%s 的稀有度不存在：%s" % [id, def.rarity]
		if not ItemDefs.SHAPES.has(def.shape):
			return "%s 的形狀不存在：%s" % [id, def.shape]
		match def.kind:
			&"weapon":
				if not WeaponDefs.WEAPONS.has(def.get("weapon", &"")):
					return "%s 對應的武器不存在：%s" % [id, def.get("weapon")]
			&"item":
				if not (def.get("power", 0.0) > 0.0):
					return "%s 缺少強度分數 power" % id
				if def.effects.is_empty():
					return "%s 沒有效果" % id
				if ItemDefs.cell_count(id) != ItemDefs.expected_cells(id):
					return "%s 占 %d 格，強度 %.1f ÷ 效率 %.2f 應占 %d 格" % [id, ItemDefs.cell_count(id), def.power,
						ItemDefs.RARITIES[def.rarity].efficiency, ItemDefs.expected_cells(id)]
				counts[def.rarity] = counts.get(def.rarity, 0) + 1
			&"corpse":   # 隊友的屍體（D6）：2 × 3 格、沒有效果，不算在 45 個道具裡
				if ItemDefs.cell_count(id) != 6 or not def.effects.is_empty():
					return "屍體應占 6 格、沒有效果"
			_:
				return "%s 的 kind 不存在：%s" % [id, def.kind]
		for e: Dictionary in def.effects:
			var err := _effect_error(e)
			if err != "":
				return "%s：%s" % [id, err]
	for id: StringName in WeaponDefs.WEAPONS:
		if not ItemDefs.ITEMS.has(id) or ItemDefs.ITEMS[id].kind != &"weapon":
			return "武器 %s 沒有物品資料" % id
	var total := 0
	for r: StringName in ItemDefs.RARITIES:
		if counts.get(r, 0) == 0:
			return "稀有度 %s 沒有道具：%s" % [r, counts]
		total += counts[r]
	if ItemDefs.item_ids().size() != total:
		return "item_ids() 有 %d 個，資料表裡的道具有 %d 個" % [ItemDefs.item_ids().size(), total]
	return ""


# 道具資料裡某個屬性效果的數值（第一筆）
static func _effect_value(item_id: StringName, stat: StringName) -> float:
	for e: Dictionary in ItemDefs.ITEMS[item_id].effects:
		if e.get("stat") == stat:
			return e.value
	assert(false, "%s 沒有 %s 效果" % [item_id, stat])
	return 0.0


# 道具資料的第一筆效果
static func _effect(item_id: StringName) -> Dictionary:
	return ItemDefs.ITEMS[item_id].effects[0]


# 機率觸發的道具要放幾個才會 100% 觸發（同種動作機率相加）
static func _stacks_for_sure(item_id: StringName) -> int:
	return ceili(1.0 / _effect(item_id).chance - EPS)


static func check_items_apply() -> String:
	var w := _new_world()
	var p := _player(w)
	var base_speed := p.stats.value(&"move_speed")
	var whet := p.add_item(&"whetstone")
	var want_dmg := 1.0 + _effect_value(&"whetstone", &"damage")
	if absf(p.stats.value(&"damage") - want_dmg) > EPS:
		return "磨刀石後攻擊力應為 %.3f，實際 %.4f" % [want_dmg, p.stats.value(&"damage")]
	var added := w.events.filter(func(e: Dictionary) -> bool: return e.name == "item:added")
	if added.size() != 1 or added[0].item != "whetstone" or added[0].uid != String(whet):
		return "應發出一次 item:added（whetstone），實際 %s" % [added]
	p.add_item(&"worn_boots")
	p.add_item(&"worn_boots")
	var want_speed := base_speed * (1.0 + 2.0 * _effect_value(&"worn_boots", &"move_speed"))   # 百分比同類相加
	if absf(p.stats.value(&"move_speed") - want_speed) > EPS:
		return "兩雙皮靴移速應為 %.3f，實際 %.3f" % [want_speed, p.stats.value(&"move_speed")]
	p.hp = 50.0
	var bread_hp := _effect_value(&"stale_bread", &"max_hp")
	var bread := p.add_item(&"stale_bread")
	if p.max_hp != Config.PLAYER.max_hp + bread_hp or p.hp != 50.0 + bread_hp:
		return "麵包後最大生命應 +%.0f、目前生命跟著加，實際 %.0f / %.0f" % [bread_hp, p.hp, p.max_hp]
	p.add_item(&"gale_charm")
	var want_rolls := 1 + roundi(_effect_value(&"gale_charm", &"roll_charges"))
	if p.roll_max() != want_rolls:
		return "疾風護符後翻滾次數上限應為 %d，實際 %d" % [want_rolls, p.roll_max()]
	if p.items.size() != 5:
		return "身上應有 5 個道具實例，實際 %d" % p.items.size()
	p.remove_item(bread)
	if p.max_hp != Config.PLAYER.max_hp or p.items.size() != 4:
		return "移除麵包後最大生命應回到 %.0f、剩 4 個，實際 %.0f / %d" % [Config.PLAYER.max_hp, p.max_hp, p.items.size()]
	p.clear_items()
	if not p.items.is_empty() or p.stats.value(&"damage") != 1.0 or absf(p.stats.value(&"move_speed") - base_speed) > EPS or p.roll_max() != 1:
		return "清空後屬性應回到原值：攻擊力 %.3f 移速 %.3f 翻滾 %d" % [p.stats.value(&"damage"), p.stats.value(&"move_speed"), p.roll_max()]
	if p.stats.has_source(whet):
		return "清空後不應留下道具的屬性來源"
	if p.add_item(&"staff") != &"" or p.weapon_id != &"staff" or not p.items.is_empty():
		return "武器道具應直接換上法杖、不放進道具列表"
	# 每個道具都能放進身上、拿掉後不殘留
	for id in ItemDefs.item_ids():
		var uid := p.add_item(id)
		p.remove_item(uid)
	if p.stats.value(&"damage") != 1.0 or p.max_hp != Config.PLAYER.max_hp:
		return "所有道具放進再拿掉後屬性應回到原值"
	return ""


static func check_inventory() -> String:
	var inv := Inventory.new()
	if inv.size != ItemDefs.BAG_SIZE:
		return "背包大小 %s，預期 %s" % [inv.size, ItemDefs.BAG_SIZE]
	# l3：(0,0) (0,1) (1,1)；轉 90° → (-y, x) 再平移：(1,0) (0,0) (0,1)
	var r1 := Inventory.cells_of(&"thunder_rune", 1)
	r1.sort()
	var expect: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0)]
	if r1 != expect:
		return "l3 轉 90° 應為 (0,0) (0,1) (1,0)，實際 %s" % [r1]
	# i4 橫放在 (5, 0) 超出邊界，(4, 0) 剛好；直放（轉 90°）在 (0, 3) 超出、(0, 2) 剛好
	if inv.fits(&"staff", Vector2i(5, 0), 0) or not inv.fits(&"staff", Vector2i(4, 0), 0) \
			or inv.fits(&"staff", Vector2i(0, 3), 1) or not inv.fits(&"staff", Vector2i(0, 2), 1):
		return "i4 的邊界判斷錯誤"
	inv.add(&"a", &"whetstone", Vector2i(0, 0), 0)   # i2：(0,0) (1,0)
	if inv.fits(&"loaded_dice", Vector2i(1, 0), 0) or not inv.fits(&"loaded_dice", Vector2i(2, 0), 0):
		return "重疊判斷錯誤"
	var spot := inv.find_spot(&"whetstone")
	if spot.cell != Vector2i(2, 0) or spot.rot != 0:
		return "第一個空位應為 (2, 0) 不轉，實際 %s" % [spot]
	if not inv.move(&"a", Vector2i(7, 4), 1) or inv.find(&"a").cell != Vector2i(7, 4) or inv.move(&"a", Vector2i(7, 5), 1):
		return "搬動：(7, 4) 直放應成功、(7, 5) 直放應失敗"
	# 只剩直的一行空位時會轉 90° 放進去
	var inv2 := Inventory.new()
	inv2.size = Vector2i(1, 3)
	var s2 := inv2.find_spot(&"whetstone")
	if s2.is_empty() or s2.rot % 2 != 1:
		return "1 × 3 的空間應轉 90° 放下 i2，實際 %s" % [s2]
	# 玩家：裝滿背包格數個 1 格道具後撿不起來
	var w := _new_world()
	var p := _player(w)
	for i in ItemDefs.BAG_SIZE.x * ItemDefs.BAG_SIZE.y:
		if p.add_item(&"loaded_dice") == &"":
			return "第 %d 個 1 格道具應放得下" % (i + 1)
	if p.add_item(&"loaded_dice") != &"" or _named(w.events, "inventory:full").is_empty():
		return "背包滿了應放不下並發出 inventory:full"
	return ""


static func check_gold_chests() -> String:
	var w := _new_world(12345, false, &"graveyard_a")
	var want_tiers := {}
	for c: Array in w.map.chests:
		want_tiers[c[2]] = want_tiers.get(c[2], 0) + 1
	var tiers := {}
	for c: Entity in w.chests:
		tiers[(c as Chest).tier] = tiers.get((c as Chest).tier, 0) + 1
		if not w.nav.is_walkable(c.pos) and absf(c.height) < EPS:
			return "寶箱 %s 放在不能走的地方" % c.pos
	if tiers != want_tiers or not tiers.has(&"big"):
		return "地圖 A 的寶箱 %s，地圖資料是 %s（要有大寶箱）" % [tiers, want_tiers]
	var p := _player(w)
	var g := _spawn(w, &"grunt", p.pos + Vector2(3, 0))
	g.die()
	var b := _spawn(w, &"boss", p.pos + Vector2(-6, 0))
	b.die()
	var earned: int = LootDefs.KILL_GOLD[&"grunt"] + LootDefs.KILL_GOLD[&"boss"]
	if w.gold != earned:
		return "殺骷髏 + Boss 應得 %d 金幣，實際 %d" % [earned, w.gold]
	var chest: Chest = null
	for c: Entity in w.chests:
		if (c as Chest).tier == &"big":
			chest = c
	var price: int = LootDefs.CHESTS[&"big"].price
	p.pos = chest.pos + Vector2(0, 1.5)
	w.gold = price - 1
	w.events.clear()
	if chest.try_open(p) or chest.opened or w.gold != price - 1 or _named(w.events, "chest:denied").is_empty():
		return "錢 %d < %d 應開不了並發出 chest:denied" % [price - 1, price]
	w.gold = price + 1
	var before := w.pickups.size()   # Boss 必掉一把武器，地上原本就有東西
	if not chest.try_open(p) or not chest.opened or w.gold != 1 or w.pickups.size() != before + 1:
		return "錢夠應打開：開了 %s、剩 %d、地上多了 %d 個" % [chest.opened, w.gold, w.pickups.size() - before]
	var drop: ItemPickup = w.pickups.back()
	if drop.pos.distance_to(chest.pos) > LootDefs.DROP_DISTANCE + 1.0 or not ItemDefs.ITEMS.has(drop.item_id):
		return "道具應掉在寶箱旁：距離 %.2f" % drop.pos.distance_to(chest.pos)
	if LootDefs.CHESTS.big.weights.get(drop.rarity(), 0.0) <= 0.0:
		return "大寶箱不應開出 %s" % drop.rarity()
	w.gold = 100
	if chest.try_open(p) or w.gold != 100:
		return "開過的寶箱不能再開"
	return ""


static func check_chest_rarity() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for tier: StringName in LootDefs.CHESTS:
		var weights: Dictionary = LootDefs.CHESTS[tier].weights
		var counts := {}
		var n := 20000
		for i in n:
			var r := LootDefs.roll_rarity(tier, rng)
			counts[r] = counts.get(r, 0) + 1
		for r: StringName in counts:
			if not weights.has(r):
				return "%s 開出了不該有的 %s" % [tier, r]
		for r: StringName in weights:
			var pct: float = counts.get(r, 0) * 100.0 / n
			if absf(pct - weights[r]) > 1.5:
				return "%s 的 %s 應約 %.0f%%，實際 %.2f%%" % [tier, r, weights[r], pct]
		for r: StringName in weights:
			for id in LootDefs.items_of(r):
				if ItemDefs.ITEMS[id].kind != &"item":
					return "寶箱會開出武器 %s" % id
			if LootDefs.drop_pool(r).is_empty():
				return "%s 稀有度沒有道具可開" % r
	return ""


static func check_pickups() -> String:
	var w := _new_world(12345, false, &"test_arena")
	var p := _player(w)
	var drop := w.drop_item(&"whetstone", p.pos + Vector2(1.0, 0))
	var press := _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_INTERACT)
	_run(w, press, 1)
	var one := 1.0 + _effect_value(&"whetstone", &"damage")
	if p.inventory.entries.size() != 1 or not drop.is_removed or absf(p.stats.value(&"damage") - one) > EPS:
		return "按 F 應撿起磨刀石並生效：背包 %d、攻擊力 %.2f" % [p.inventory.entries.size(), p.stats.value(&"damage")]
	# 按住不放不會連撿
	w.drop_item(&"whetstone", p.pos + Vector2(1.0, 0))
	_run(w, press, 10)
	if p.inventory.entries.size() != 1:
		return "按住 F 不放不應再撿，背包 %d" % p.inventory.entries.size()
	_run(w, _cmd(Vector2.ZERO), 1)
	_run(w, press, 1)
	if p.inventory.entries.size() != 2:
		return "放開再按應撿起第二個，背包 %d" % p.inventory.entries.size()
	# 丟掉：回到地上、效果移除
	var uid: StringName = p.inventory.entries[0].uid
	var drop_cmd := _cmd(Vector2.ZERO)
	drop_cmd.inv_ops = [[InputCmd.OP_DROP, String(uid)]]
	_run(w, drop_cmd, 1)
	if p.inventory.entries.size() != 1 or w.pickups.size() != 1 or absf(p.stats.value(&"damage") - one) > EPS:
		return "丟掉一個：背包 %d、地上 %d、攻擊力 %.2f（應為 1 / 1 / %.2f）" % [p.inventory.entries.size(), w.pickups.size(), p.stats.value(&"damage"), one]
	# 兩人同一步按 F：只有一人拿到
	var w2 := World.new(&"test_arena")
	w2.reset(5, [1, 2])
	w2.spawner.finished = true
	_worlds.append(w2)
	var a: Player = w2.players[1]
	var c: Player = w2.players[2]
	a.pos = Vector2(-1, 0)
	c.pos = Vector2(1, 0)
	w2.drop_item(&"whetstone", Vector2(0, 0))
	w2.step({1: press, 2: press}, DT)
	if a.inventory.entries.size() + c.inventory.entries.size() != 1:
		return "兩人同時撿：共拿到 %d 個（應為 1）" % (a.inventory.entries.size() + c.inventory.entries.size())
	# 倒地隊友在旁邊：F 先救人，不撿道具
	var w3 := World.new(&"test_arena")
	w3.reset(5, [1, 2])
	w3.spawner.finished = true
	_worlds.append(w3)
	var r: Player = w3.players[1]
	var d: Player = w3.players[2]
	r.pos = Vector2(0, 0)
	d.pos = Vector2(1.2, 0)
	d.hp = 1.0
	d.take_damage(10.0, Vector2.RIGHT, 0.0, 0)
	w3.drop_item(&"whetstone", Vector2(0.8, 0.5))
	w3.step({1: press, 2: _cmd(Vector2.ZERO)}, DT)
	if not d.is_downed or r.inventory.entries.size() != 0:
		return "旁邊有倒地隊友時 F 應先救人：倒地 %s、撿到 %d" % [d.is_downed, r.inventory.entries.size()]
	return ""


static func check_weapon_drops() -> String:
	var w := _new_world()
	var p := _player(w)
	var drops := 0
	var n := 5000
	for i in n:
		var g := _spawn(w, &"grunt", p.pos + Vector2(6, 0))
		var before := w.events.size()
		g.die()
		for k in range(before, w.events.size()):
			if w.events[k].name == "weapon:dropped":
				drops += 1
		g.remove()
		if i % 200 == 0:
			for d in w.pickups:
				d.remove()
			w._remove_dead_entities()
			w.events.clear()
	var pct := drops * 100.0 / n
	var want_pct: float = WeaponDropDefs.DROP_CHANCE[&"grunt"] * 100.0
	if absf(pct - want_pct) > 0.9:
		return "小怪掉武器 %.2f%%，應約 %.1f%%" % [pct, want_pct]
	var w2 := _new_world()
	var before2 := w2.pickups.size()
	_spawn(w2, &"boss", Vector2(6, 0)).die()
	if w2.pickups.size() != before2 + 1 or not (w2.pickups.back() as ItemPickup).is_weapon():
		return "Boss 應必掉一把武器"
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for source: StringName in WeaponDropDefs.RARITY_WEIGHTS:
		var weights: Dictionary = WeaponDropDefs.RARITY_WEIGHTS[source]
		var counts := {}
		for i in 20000:
			var r := WeaponDropDefs.roll_rarity(source, rng)
			counts[r] = counts.get(r, 0) + 1
		for r: StringName in counts:
			if not weights.has(r):
				return "%s 掉出了不該有的 %s" % [source, r]
		for r: StringName in weights:
			var got: float = counts.get(r, 0) * 100.0 / 20000.0
			if absf(got - weights[r]) > 1.5:
				return "%s 的 %s 應約 %.0f%%，實際 %.2f%%" % [source, r, weights[r], got]
	print("    小怪死 %d 次掉 %d 把（%.2f%%）" % [n, drops, pct])
	return ""


static func check_weapon_affixes() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for r in WeaponDropDefs.RARITY_ORDER:
		for i in 50:
			var inst := WeaponDropDefs.make(&"x", &"staff", r, rng)
			var uniq := {}
			for a in inst.affixes:
				uniq[a] = true
			if inst.affixes.size() != WeaponDropDefs.RARITY_ORDER.find(r) or uniq.size() != inst.affixes.size():
				return "%s 應有 %d 條不重複詞條，實際 %s" % [r, WeaponDropDefs.RARITY_ORDER.find(r), inst.affixes]
	var w := _new_world()
	var p := _player(w)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SWAP_WEAPON), 1)
	if p.active_slot != 0:
		return "另一格是空的時不應切換"
	var aff: Array[StringName] = [&"aff_damage", &"aff_attack_speed"]
	p.add_weapon({"uid": &"blue", "base": &"staff", "rarity": &"blue", "affixes": aff})
	if p.weapon_slots[1].is_empty() or p.active_slot != 0 or absf(p.stats.value(&"damage") - 1.0) > EPS:
		return "撿到的武器應放第 2 格、不換手上、詞條不生效：攻擊力 %.2f" % p.stats.value(&"damage")
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SWAP_WEAPON), 1)
	# v0.27.0 起稀有度有基礎倍率：藍色攻擊力 ×1.4、攻速 ×1.10，再乘詞條的 +10%
	var want_dmg: float = WeaponDropDefs.RARITY_BASE.blue.damage * 1.1
	var want_spd: float = WeaponDropDefs.RARITY_BASE.blue.attack_speed * 1.1
	if p.active_slot != 1 or p.weapon_id != &"staff" or absf(p.stats.value(&"damage") - want_dmg) > EPS or absf(p.stats.value(&"attack_speed") - want_spd) > EPS:
		return "按 X 換成藍法杖後攻擊力 / 攻速應為 %.2f / %.2f：%s、%.2f / %.2f" % [want_dmg, want_spd, p.weapon_id, p.stats.value(&"damage"), p.stats.value(&"attack_speed")]
	_run(w, _cmd(Vector2.ZERO), 1)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SWAP_WEAPON), 1)
	if p.active_slot != 0 or p.weapon_id != &"swordShield" or absf(p.stats.value(&"damage") - 1.0) > EPS:
		return "再按 X 換回劍盾，詞條應移除：攻擊力 %.2f" % p.stats.value(&"damage")
	return ""


# 生一隻血很多、站在 at 的骷髏（道具檢查用）
static func _item_dummy(w: World, at: Vector2, hp: float = 1000.0) -> Enemy:
	var e := _spawn(w, &"grunt", at)
	e.fsm.change(e.main_state)   # 不等爬出來
	e.stats.set_base(&"max_hp", hp)
	e.hp = e.max_hp
	return e


static func _hp_loss(e: Enemy, before: float) -> int:
	return roundi(before - e.hp)


# 怪受到 raw 傷害時實際扣多少（套護甲與受傷倍率，同 Entity.take_damage）
static func _dealt(e: Enemy, raw: float) -> int:
	return roundi(raw * StatDefs.armor_damage_factor(e.stats.value(&"armor")) * e.damage_taken_mul)


static func check_item_conditions() -> String:
	var w := _new_world()
	var p := _player(w)
	var idle := _cmd(Vector2.ZERO)
	# 獵犬項圈：滿血那一下有加成，之後照常
	p.add_item(&"hound_collar")
	var a := _item_dummy(w, Vector2(0, 3))
	var before := a.hp
	var full_hit: float = 10.0 * (1.0 + _effect(&"hound_collar").value)
	Combat.apply_damage(w, p, a, {"damage": 10.0})
	if _hp_loss(a, before) != _dealt(a, full_hit):
		return "對滿血敵人應扣 %d，實際 %d" % [_dealt(a, full_hit), _hp_loss(a, before)]
	before = a.hp
	Combat.apply_damage(w, p, a, {"damage": 10.0})
	if _hp_loss(a, before) != _dealt(a, 10.0):
		return "不是滿血時應扣 %d，實際 %d" % [_dealt(a, 10.0), _hp_loss(a, before)]
	p.clear_items()
	# 狂戰士護符：生命低於門檻才有加成；拿掉道具就沒了
	var bz := _effect(&"berserker_charm")
	var uid := p.add_item(&"berserker_charm")
	p.hp = p.max_hp * (bz.threshold - 0.05)
	_run(w, idle, 1)
	if absf(p.stats.value(&"damage") - (1.0 + bz.value)) > EPS:
		return "生命低於 %.0f%% 時攻擊力應為 %.2f，實際 %.3f" % [bz.threshold * 100.0, 1.0 + bz.value, p.stats.value(&"damage")]
	p.remove_item(uid)
	if absf(p.stats.value(&"damage") - 1.0) > EPS:
		return "拿掉狂戰士護符後攻擊力應回到 1.0，實際 %.3f" % p.stats.value(&"damage")
	p.add_item(&"berserker_charm")
	p.hp = p.max_hp
	_run(w, idle, 1)
	if absf(p.stats.value(&"damage") - 1.0) > EPS:
		return "滿血時不應有狂戰士加成：%.3f" % p.stats.value(&"damage")
	p.clear_items()
	# 戰鼓：擊殺後一段時間攻速加成；吸魂鐮：擊殺回復最大生命的比例
	var drum := _effect(&"war_drum")
	var heal_hp: float = 50.0 + p.max_hp * _effect(&"soul_scythe").ratio
	p.add_item(&"war_drum")
	p.add_item(&"soul_scythe")
	p.hp = 50.0
	var b := _item_dummy(w, Vector2(0, 3), 1.0)
	Combat.apply_damage(w, p, b, {"damage": 10.0})
	if not b.is_dead or absf(p.hp - heal_hp) > EPS:
		return "擊殺後生命應為 %.1f，實際 %.1f（怪死了 %s）" % [heal_hp, p.hp, b.is_dead]
	_run(w, idle, 1)
	if absf(p.stats.value(&"attack_speed") - (1.0 + drum.value)) > EPS:
		return "擊殺後攻速應為 %.2f，實際 %.3f" % [1.0 + drum.value, p.stats.value(&"attack_speed")]
	_run(w, idle, roundi(drum.duration / DT))
	if absf(p.stats.value(&"attack_speed") - 1.0) > EPS:
		return "擊殺 %.1f 秒後攻速應回到 1.0，實際 %.3f" % [drum.duration, p.stats.value(&"attack_speed")]
	return ""


static func check_item_procs() -> String:
	var w := _new_world()
	var p := _player(w)
	var idle := _cmd(Vector2.ZERO)
	# 火藥包疊到 100%：擊殺時爆炸，旁邊的怪受那一下的 damage_ratio
	var ex: Dictionary = ItemDefs.PROCS[&"explode"]
	for i in _stacks_for_sure(&"powder_pouch"):
		p.add_item(&"powder_pouch")
	var a := _item_dummy(w, Vector2(0, 4), 1.0)
	var b := _item_dummy(w, Vector2(minf(1.0, ex.radius * 0.5), 4))
	var b_before := b.hp
	Combat.apply_damage(w, p, a, {"damage": 40.0})
	if _hp_loss(b, b_before) != _dealt(b, 40.0 * ex.damage_ratio):
		return "爆炸應讓旁邊的怪扣 %d，實際 %d" % [_dealt(b, 40.0 * ex.damage_ratio), _hp_loss(b, b_before)]
	p.clear_items()
	w.clear()
	# 雷鳴符文疊到 100%：a → b → c（每跳都在 jump_range 內），d 太遠；每跳 damage_ratio，閃電不會再觸發閃電
	var cl: Dictionary = ItemDefs.PROCS[&"chain_lightning"]
	var jr: float = cl.jump_range
	w = _new_world()
	p = _player(w)
	for i in _stacks_for_sure(&"thunder_rune"):
		p.add_item(&"thunder_rune")
	a = _item_dummy(w, Vector2(0, 5))
	b = _item_dummy(w, Vector2(0, 5 + jr * 0.6))
	var c := _item_dummy(w, Vector2(0, 5 + jr * 1.4))
	var d := _item_dummy(w, Vector2(0, 5 + jr * 5.0))
	var hp0 := [a.hp, b.hp, c.hp, d.hp]
	w.events.clear()
	Combat.apply_damage(w, p, a, {"damage": 10.0})
	var got := [_hp_loss(a, hp0[0]), _hp_loss(b, hp0[1]), _hp_loss(c, hp0[2]), _hp_loss(d, hp0[3])]
	var want := [_dealt(a, 10.0), _dealt(b, 10.0 * cl.damage_ratio), _dealt(c, 10.0 * cl.damage_ratio), 0]
	if got != want:
		return "連鎖閃電 a / b / c / d 應扣 %s，實際 %s" % [want, got]
	var bolts := w.events.filter(func(ev: Dictionary) -> bool: return ev.name == "fx:lightning")
	if bolts.size() != 1 or bolts[0].points.size() != _effect(&"thunder_rune").targets:
		return "應有 1 道經過 %d 點的閃電：%s" % [_effect(&"thunder_rune").targets, bolts]
	p.clear_items()
	w.clear()
	# 淬毒刀刃疊到 100%：命中 10 → duration 秒共 10 × total_ratio，每 tick 秒扣一次
	var po: Dictionary = ItemDefs.PROCS[&"poison"]
	var ticks := roundi(po.duration / po.tick)
	w = _new_world()
	p = _player(w)
	for i in _stacks_for_sure(&"venom_blade"):
		p.add_item(&"venom_blade")
	a = _item_dummy(w, Vector2(0, 5))
	var before := a.hp
	Combat.apply_damage(w, p, a, {"damage": 10.0})
	if not a.anim.is_empty() and a.poison_timer <= 0.0:
		return "命中後應中毒"
	_run(w, idle, roundi(po.duration / DT) + 20)
	var want_poison := _dealt(a, 10.0) + ticks * _dealt(a, 10.0 * po.total_ratio / ticks)
	if _hp_loss(a, before) != want_poison:
		return "中毒 %.1f 秒後總共應扣 %d，實際 %d" % [po.duration, want_poison, _hp_loss(a, before)]
	p.clear_items()
	w.clear()
	# 霜之心疊到 100%：冰凍 duration 秒不能動，之後照常追；Boss 不會被冰凍
	var freeze_time: float = _effect(&"frost_heart").duration
	w = _new_world()
	p = _player(w)
	for i in _stacks_for_sure(&"frost_heart"):
		p.add_item(&"frost_heart")
	a = _item_dummy(w, Vector2(0, 6))
	Combat.apply_damage(w, p, a, {"damage": 1.0})
	var at := a.pos
	var frozen_steps := roundi(freeze_time / DT) - 30
	_run(w, idle, frozen_steps)
	if a.pos.distance_to(at) > EPS or not a.anim.get("frozen", false):
		return "冰凍中不應移動：移動 %.3f、frozen %s" % [a.pos.distance_to(at), a.anim.get("frozen", false)]
	# 解凍後先把被打中的受擊硬直做完（凍住時狀態機停住），之後才開始追
	_run(w, idle, 30 + roundi(1.0 / DT))
	if a.pos.distance_to(at) < 0.1 or a.anim.get("frozen", false):
		return "冰凍結束 1 秒後應解凍並開始追：移動 %.3f" % a.pos.distance_to(at)
	var boss := _spawn(w, &"boss", Vector2(10, 10))
	boss.apply_freeze(1.5)
	if boss.frozen_timer > 0.0:
		return "Boss 不應被冰凍"
	return ""


static func check_item_drop_pool() -> String:
	var order: Array = ItemDefs.RARITIES.keys()
	for r: StringName in ItemDefs.RARITIES:
		var pool := LootDefs.drop_pool(r)
		if pool.is_empty():
			return "%s 沒有可以掉的道具" % r
		for id in pool:
			if not ItemDefs.item_implemented(id):
				return "%s 的掉落裡有還沒實作的 %s" % [r, id]
		# 這個稀有度有實作好的道具就全部都在掉落裡；一個都沒有就往下一級找
		var done := LootDefs.items_of(r).filter(func(id: StringName) -> bool: return ItemDefs.item_implemented(id))
		if not done.is_empty():
			if pool != done:
				return "%s 的掉落應為實作好的 %s，實際 %s" % [r, done, pool]
		elif order.find(ItemDefs.ITEMS[pool[0]].rarity) >= order.find(r):
			return "%s 都還沒實作，應改掉較低的稀有度，實際掉 %s" % [r, ItemDefs.ITEMS[pool[0]].rarity]
	return ""


static func check_weapon_pickup() -> String:
	var w := _new_world()
	var p := _player(w)
	var mk := func(uid: String, base: StringName) -> Dictionary:
		return {"uid": StringName(uid), "base": base, "rarity": &"white", "affixes": [] as Array[StringName]}
	# 地上的武器按 F 撿起 → 第 2 格
	w.drop_weapon(mk.call("a", &"staff"), p.pos + Vector2(1, 0))
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_INTERACT), 1)
	if p.weapon_slots[1].get("uid", &"") != &"a" or p.active_slot != 0:
		return "撿起的武器應放進空的第 2 格、不換手上"
	# 裝備欄滿了 → 背包（不生效）
	if not p.add_weapon(mk.call("b", &"staff")) or p.inventory.find(&"b").is_empty() or not p.items.is_empty():
		return "裝備欄滿了應放進背包、而且不算生效的道具"
	# 背包塞滿 → 撿不起來
	for i in ItemDefs.BAG_SIZE.x * ItemDefs.BAG_SIZE.y:
		p.add_item(&"loaded_dice")
	w.events.clear()
	if p.add_weapon(mk.call("c", &"staff")) or _named(w.events, "inventory:full").is_empty():
		return "背包滿了應撿不起來並發出 inventory:full"
	p.clear_items()
	# 背包的武器拖到第 1 格：原本那把（劍盾）回背包
	var equip := _cmd(Vector2.ZERO)
	equip.inv_ops = [[InputCmd.OP_EQUIP, "b", 0]]
	_run(w, equip, 1)
	var sword_uid: StringName = &""
	for e in p.inventory.entries:
		if e.has("weapon"):
			sword_uid = e.uid
	if p.weapon_slots[0].get("uid", &"") != &"b" or p.weapon_id != &"staff" or sword_uid == &"":
		return "背包武器裝上第 1 格後，原本的劍盾應回背包：第 1 格 %s、手上 %s" % [p.weapon_slots[0].get("uid", &""), p.weapon_id]
	# 裝備欄 → 背包：還有另一把時可以；只剩一把時不行，也不能丟
	var to_bag := _cmd(Vector2.ZERO)
	to_bag.inv_ops = [[InputCmd.OP_MOVE, "a", 0, 5, 0]]
	_run(w, to_bag, 1)
	if not p.weapon_slots[1].is_empty() or p.inventory.find(&"a").is_empty():
		return "第 2 格的武器應能搬進背包"
	var last := _cmd(Vector2.ZERO)
	last.inv_ops = [[InputCmd.OP_MOVE, "b", 4, 5, 0], [InputCmd.OP_DROP, "b"]]
	_run(w, last, 1)
	if p.weapon_slots[0].get("uid", &"") != &"b":
		return "手上只剩一把時不能搬走或丟掉"
	return ""


static func check_weapon_merge() -> String:
	var w := _new_world()
	var p := _player(w)
	var mk := func(uid: String, base: StringName, rarity: StringName) -> Dictionary:
		return {"uid": StringName(uid), "base": base, "rarity": rarity, "affixes": [] as Array[StringName]}
	var start_uid: StringName = p.weapon_slots[0].uid
	p.add_weapon(mk.call("s2", &"swordShield", &"white"))   # 第 2 格
	p.add_weapon(mk.call("s3", &"swordShield", &"white"))   # 背包
	p.add_weapon(mk.call("st", &"staff", &"white"))         # 背包
	p.add_weapon(mk.call("g1", &"swordShield", &"green"))   # 背包
	var merge := func(a: String, b: String) -> void:
		var c := _cmd(Vector2.ZERO)
		c.inv_ops = [[InputCmd.OP_MERGE, a, b]]
		w.events.clear()
		_run(w, c, 1)
	# 背包的白劍盾拖到手上的白劍盾 → 綠色、1 條詞條、留在第 1 格、手上立刻生效
	merge.call("s3", String(start_uid))
	var m: Dictionary = p.weapon_slots[0]
	if m.rarity != &"green" or m.affixes.size() != 1 or not p.inventory.find(&"s3").is_empty() or _named(w.events, "weapon:merged").is_empty():
		return "合成應得到綠色 1 條詞條、在第 1 格：%s" % [m]
	var mods := WeaponDropDefs.stat_mods(m)
	var stat: StringName = mods[0][0]
	if is_equal_approx(p.stats.value(stat), p.stats.base(stat)):
		return "合成後手上的詞條（%s）應立刻生效" % stat
	# 不同種、不同稀有度不能合成
	merge.call("st", "s2")
	if _named(w.events, "weapon:merge_denied").is_empty() or p.inventory.find(&"st").is_empty():
		return "法杖拖到劍盾上不應合成"
	merge.call("s2", "g1")
	if _named(w.events, "weapon:merge_denied").is_empty() or p.weapon_slots[1].is_empty():
		return "白色拖到綠色上不應合成"
	# 綠 + 綠 → 藍，放在背包那把的位置
	var cell: Vector2i = p.inventory.find(&"g1").cell
	merge.call(String(start_uid), "g1")
	var g := p.inventory.find(&"g1")
	if g.is_empty() or g.weapon.rarity != &"blue" or g.cell != cell or not p.weapon_slots[0].is_empty() and p.weapon_slots[0].uid == start_uid:
		return "綠 + 綠應在背包原位得到藍色"
	if p.active_slot != 1:
		return "手上那把被合成走之後應換成第 2 格"
	# 橘色不能再合成
	var o1: Dictionary = mk.call("o1", &"staff", &"orange")
	var o2: Dictionary = mk.call("o2", &"staff", &"orange")
	if WeaponDropDefs.can_merge(o1, o2):
		return "橘色不能再合成"
	return ""
