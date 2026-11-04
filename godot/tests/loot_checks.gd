# 背包、靈魂、祭壇 / 石棺（程式裡叫 chest）、局外金幣、道具與武器：撿取、掉落、詞條、合成、道具資料與效果
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
	var bag := BagDefs.MAIN_SIZE
	if not ((size.x <= bag.x and size.y <= bag.y) or (size.y <= bag.x and size.x <= bag.y)):
		return "%d×%d 放不進主袋" % [size.x, size.y]
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
					return "%s 占 %d 格，%s 應占 %d 格" % [id, ItemDefs.cell_count(id),
						ItemDefs.RARITIES[def.rarity].name, ItemDefs.expected_cells(id)]
				counts[def.rarity] = counts.get(def.rarity, 0) + 1
			&"skill":   # 技能：1 格、SkillDefs 有同 id 的資料；weapons 是動作照哪種武器做（不限制能用的武器）
				if ItemDefs.cell_count(id) != 1 or not SkillDefs.SKILLS.has(id) or (SkillDefs.SKILLS[id].get("weapons", []) as Array).is_empty():
					return "技能 %s 應占 1 格、SkillDefs 有資料並寫明動作照哪種武器" % id
			&"bag":   # 觸發袋：BagDefs.BAGS 有對到、沒有效果
				if BagDefs.kind_of_item(id) == &"" or not def.effects.is_empty():
					return "袋子 %s 應對到 BagDefs.BAGS、沒有效果" % id
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


# 觸發袋的分類（BagDefs）：道具與技能都分得出放主袋還是袋子；觸發道具都對到一個效果與一種袋子；
# 致命傷 / 死亡的觸發留在主袋；每個效果都有道具改寫過來；袋子接的邊都存在、每個觸發時機只屬於一種袋子
static func check_bag_roles() -> String:
	for kind: StringName in BagDefs.BAGS:
		var bag: Dictionary = BagDefs.BAGS[kind]
		if (bag.sides as Array).is_empty():
			return "袋子 %s 沒寫能接哪一邊" % kind
		for side: StringName in bag.sides:
			if not BagDefs.SIDES.has(side):
				return "袋子 %s 接的邊不存在：%s" % [kind, side]
		for on: StringName in bag.on:
			if BagDefs.bag_for_trigger(on) != kind:
				return "觸發時機 %s 同時屬於好幾種袋子" % on
	var used := {}
	for id: StringName in ItemDefs.ITEMS:
		var kind: StringName = ItemDefs.ITEMS[id].kind
		var role := ItemDefs.role_of(id)
		if kind in [&"item", &"skill"] and role == &"":
			return "%s 沒有分類" % id
		if kind not in [&"item", &"skill"] and role != &"":
			return "%s（%s）不該放進袋子" % [id, kind]
		for e: Dictionary in ItemDefs.ITEMS[id].effects:
			if not e.has("on"):
				continue
			if BagDefs.MAIN_TRIGGERS.has(e.on):
				if role != ItemDefs.ROLE_STAT:
					return "%s 的觸發 %s 應留在主袋" % [id, e.on]
			elif role != ItemDefs.ROLE_EFFECT or BagDefs.bag_for_trigger(e.on) == &"":
				return "觸發道具 %s（%s）沒有對到效果或袋子" % [id, e.on]
		if role == ItemDefs.ROLE_EFFECT:
			var effect := ItemDefs.effect_of(id)
			if not BagDefs.EFFECTS.has(effect):
				return "%s 改寫成的效果 %s 不在 BagDefs.EFFECTS" % [id, effect]
			if not BagDefs.BAGS.has(ItemDefs.default_bag_of(id)):
				return "%s 沒有預設的袋子" % id
			used[effect] = true
	for effect: StringName in BagDefs.EFFECTS:
		if not used.has(effect):
			return "效果 %s 沒有道具改寫過來" % effect
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
	# 倉庫：大小照 BAG_SIZE，每格放一件，不管形狀與方向
	var store := Inventory.new()
	if store.size != ItemDefs.BAG_SIZE:
		return "倉庫大小 %s，預期 %s" % [store.size, ItemDefs.BAG_SIZE]
	var last := ItemDefs.BAG_SIZE - Vector2i.ONE
	if not store.fits(&"staff", last, 1) or store.fits(&"staff", last + Vector2i(1, 0), 0):
		return "倉庫最後一格應放得下 4 格長的法杖、超出邊界的不行"
	store.add(&"w", &"staff", Vector2i.ZERO, 0)
	if store.occupied().size() != 1 or store.fits(&"loaded_dice", Vector2i.ZERO, 0) or not store.fits(&"staff", Vector2i(1, 0), 0):
		return "倉庫的法杖應只佔一格：佔 %d 格" % store.occupied().size()
	var free_spot := store.find_spot(&"staff")
	if free_spot.cell != Vector2i(1, 0) or free_spot.rot != 0:
		return "倉庫的第一個空位應為 (1, 0) 不轉，實際 %s" % [free_spot]
	# 主袋與袋子：照形狀占格、會轉向
	var i2 := _shaped(&"i2")
	var long_id := _shaped(&"i3")
	# l3：(0,0) (0,1) (1,1)；轉 90° → (-y, x) 再平移：(1,0) (0,0) (0,1)
	var r1 := Inventory.cells_of(_shaped(&"l3"), 1)
	r1.sort()
	var expect: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0)]
	if r1 != expect:
		return "l3 轉 90° 應為 (0,0) (0,1) (1,0)，實際 %s" % [r1]
	var long_box := Inventory.core()
	if ItemDefs.role_of(long_id) != ItemDefs.ROLE_STAT:
		long_box.mode = Inventory.BAG
	var m := BagDefs.MAIN_SIZE
	# 3 格長的橫放貼右邊剛好、再往右超出；直放（轉 90°）貼下面剛好、再往下超出
	if long_box.fits(long_id, Vector2i(m.x - 2, 0), 0) or not long_box.fits(long_id, Vector2i(m.x - 3, 0), 0) \
			or long_box.fits(long_id, Vector2i(0, m.y - 2), 1) or not long_box.fits(long_id, Vector2i(0, m.y - 3), 1):
		return "主袋裡 3 格長的邊界判斷錯誤"
	var inv := Inventory.core()
	inv.add(&"a", i2, Vector2i(0, 0), 0)   # i2：(0,0) (1,0)
	if inv.fits(&"loaded_dice", Vector2i(1, 0), 0) or not inv.fits(&"loaded_dice", Vector2i(2, 0), 0):
		return "重疊判斷錯誤"
	var spot := inv.find_spot(i2)
	if spot.cell != Vector2i(2, 0) or spot.rot != 0:
		return "第一個空位應為 (2, 0) 不轉，實際 %s" % [spot]
	if not inv.move(&"a", Vector2i(m.x - 1, m.y - 2), 1) or inv.find(&"a").cell != Vector2i(m.x - 1, m.y - 2) or inv.move(&"a", Vector2i(m.x - 1, m.y - 1), 1):
		return "搬動：右下角直放應成功、再往下直放應失敗"
	# 只剩直的一行空位時會轉 90° 放進去
	var inv2 := Inventory.core()
	inv2.size = Vector2i(1, 3)
	var s2 := inv2.find_spot(i2)
	if s2.is_empty() or s2.rot % 2 != 1:
		return "1 × 3 的空間應轉 90° 放下 i2，實際 %s" % [s2]
	# 玩家：裝滿背包格數個 1 格道具後撿不起來
	var w := _new_world()
	var p := _player(w)
	for i in ItemDefs.BAG_SIZE.x * ItemDefs.BAG_SIZE.y:
		if p.loadout.add_item(p, &"loaded_dice", {}, 0, Loadout.BAG) == &"":
			return "第 %d 個 1 格道具應放得下" % (i + 1)
	if p.loadout.add_item(p, &"loaded_dice", {}, 0, Loadout.BAG) != &"" or _named(w.events, "inventory:full").is_empty():
		return "背包滿了應放不下並發出 inventory:full"
	return ""


# 放不下時建議拿掉哪一件：4 × 2 的主袋，左上 2 格道具、右下骰子（1 格），2 × 2 的道具哪裡都放不下；
# 拿掉任一件都放得下時挑占格少的骰子；本來就放得下、拿掉一件也不夠時沒有建議
static func check_inventory_suggest() -> String:
	var big := _shaped(&"o4")
	var inv := Inventory.core()
	inv.size = Vector2i(4, 2)
	inv.add(&"a", _shaped(&"i2"), Vector2i(0, 0), 0)
	inv.add(&"b", &"loaded_dice", Vector2i(3, 1), 0)
	if not inv.find_spot(big).is_empty():
		return "左上被磨刀石、右下被骰子占著，2 × 2 不應放得下"
	if inv.find_spot(big, &"a").is_empty() or inv.find_spot(big, &"b").is_empty():
		return "find_spot 當作其中一件不在時應放得下"
	if inv.suggest_removal(big) != &"b":
		return "應建議拿掉占格少的骰子，實際「%s」" % inv.suggest_removal(big)
	if inv.suggest_removal(&"loaded_dice") != &"":
		return "本來就放得下時不應有建議"
	var full_store := Inventory.new()
	for i in ItemDefs.BAG_SIZE.x:
		full_store.add(StringName("s%d" % i), &"loaded_dice", Vector2i(i, 0), 0)
	if full_store.suggest_removal(&"staff") == &"":
		return "倉庫滿了時應建議拿掉一件（拿掉哪件都放得下法杖）"
	var tight := Inventory.core()
	tight.size = Vector2i(2, 2)
	tight.add(&"a", &"loaded_dice", Vector2i(0, 0), 0)
	tight.add(&"b", &"loaded_dice", Vector2i(1, 1), 0)
	if tight.suggest_removal(big) != &"":
		return "拿掉一件也放不下時不應有建議，實際「%s」" % tight.suggest_removal(big)
	return ""


# 互換：放到只被 1 件東西佔住的位置就兩件互換（被換走的回到原位、放不下找空位），換不回去就都不動並發 inventory:denied；
# 拿著的武器放到倉庫的武器上 = 那把換上、換下來的放回那把原本的位置；主手的武器放到倉庫空格不動（主手不能空著）；主袋 ↔ 倉庫的道具互換；
# 背包介面的預覽（Loadout.swap_partner）跟實際結果一致
static func check_inventory_swap() -> String:
	var w := _new_world(3)
	var p := _player(w)
	var lo := p.loadout
	var apply := func(op: Array) -> void:
		lo.queue_ops([op])
		lo.apply_ops(p)
	# 主手武器 ↔ 背包的武器（同種不同稀有度：不是合成）
	var main_uid: StringName = p.weapon_slots[Loadout.MAIN].uid
	lo.add_weapon(p, WeaponDropDefs.make(&"bag_w", p.weapon_slots[Loadout.MAIN].base, &"blue", w.rng))
	var bag_cell: Vector2i = p.inventory.find(&"bag_w").cell
	if lo.swap_partner(main_uid, Loadout.BAG, bag_cell, 0) != &"bag_w":
		return "預覽：主手武器拖到背包的武器上應顯示換上那把"
	apply.call([InputCmd.OP_MOVE, String(main_uid), bag_cell.x, bag_cell.y, 0])
	if p.weapon_slots[Loadout.MAIN].get("uid", &"") != &"bag_w" or p.inventory.find(main_uid).get("cell", Vector2i(-1, -1)) != bag_cell:
		return "主手武器拖到背包的武器上應互換（那把換上、原本的放回 %s）：主手 %s、原本那把 %s" % [bag_cell, p.weapon_slots[Loadout.MAIN].get("uid"), p.inventory.find(main_uid)]
	w.events.clear()
	var main_now: StringName = p.weapon_slots[Loadout.MAIN].uid
	apply.call([InputCmd.OP_MOVE, String(main_now), ItemDefs.BAG_SIZE.x - 1, 0, 0])
	var denied := _named(w.events, "inventory:denied")
	if p.weapon_slots[Loadout.MAIN].get("uid", &"") != main_now or denied.is_empty() or denied[0].reason != "main_empty":
		return "主手武器拖到背包空格應不動並發 inventory:denied（main_empty）：%s" % [denied]
	# 主袋的道具 ↔ 背包的道具（兩個方向），效果跟著換
	var sock := lo.add_item(p, &"whetstone", {}, 0, Loadout.CORE)
	var bag_item := lo.add_item(p, &"worn_boots", {}, 0, Loadout.BAG)
	var s_cell: Vector2i = lo.find_item(sock).entry.cell
	var b_cell: Vector2i = lo.find_item(bag_item).entry.cell
	if lo.swap_partner(bag_item, Loadout.CORE, s_cell, 0) != sock:
		return "預覽：背包的道具拖到主袋的道具上應顯示互換"
	apply.call([InputCmd.OP_MOVE, String(bag_item), s_cell.x, s_cell.y, 0, Loadout.CORE])
	var a := lo.find_item(bag_item)
	var b := lo.find_item(sock)
	if a.get("where", -9) != Loadout.CORE or a.entry.cell != s_cell or b.get("where", -9) != Loadout.BAG or b.entry.cell != b_cell:
		return "背包的道具拖到主袋的道具上應互換位置：%s / %s" % [a, b]
	if not lo.items.any(func(it: Dictionary) -> bool: return it.id == &"worn_boots") or lo.items.any(func(it: Dictionary) -> bool: return it.id == &"whetstone"):
		return "互換後生效的應是換進主袋的那件"
	apply.call([InputCmd.OP_MOVE, String(sock), s_cell.x, s_cell.y, 0, Loadout.CORE])
	if lo.find_item(sock).get("where", -9) != Loadout.CORE or lo.find_item(bag_item).get("where", -9) != Loadout.BAG:
		return "主袋的道具拖回去（背包 → 格子上的那件）應再換回來"
	# 背包裡兩件互換（同一個容器）
	var dice := lo.add_item(p, &"loaded_dice", {}, 0, Loadout.BAG)
	var d_cell: Vector2i = lo.find_item(dice).entry.cell
	b_cell = lo.find_item(bag_item).entry.cell
	apply.call([InputCmd.OP_MOVE, String(dice), b_cell.x, b_cell.y, 0])
	if lo.find_item(dice).entry.cell != b_cell or lo.find_item(bag_item).entry.cell != d_cell:
		return "背包裡兩件應互換位置：骰子 %s、皮靴 %s" % [lo.find_item(dice).entry.cell, lo.find_item(bag_item).entry.cell]
	# 武器不會被換進主袋：主袋的道具拖到背包的武器上不動
	w.events.clear()
	var weapon_cell: Vector2i = p.inventory.find(main_uid).cell
	apply.call([InputCmd.OP_MOVE, String(sock), weapon_cell.x, weapon_cell.y, 0])
	if lo.find_item(sock).get("where", -9) != Loadout.CORE or p.inventory.find(main_uid).cell != weapon_cell or _named(w.events, "inventory:denied").is_empty():
		return "主袋的道具拖到背包的武器上應不動（武器只在倉庫）並發 inventory:denied"
	# 倉庫不管形狀：滿了也換得回去（2 格長的主袋道具換進骰子那一格）
	var w2 := _new_world(4)
	var p2 := _player(w2)
	var lo2 := p2.loadout
	var long := lo2.add_item(p2, _shaped(&"i2"), {"cell": Vector2i(0, 0), "rot": 0}, 0, Loadout.CORE)
	var x := lo2.add_item(p2, &"loaded_dice", {}, 0, Loadout.BAG)
	var x_cell: Vector2i = lo2.find_item(x).entry.cell
	var n := 0
	for xx in p2.inventory.size.x:
		if p2.inventory.fits(&"loaded_dice", Vector2i(xx, 0), 0):
			p2.inventory.add(StringName("fill%d" % n), &"loaded_dice", Vector2i(xx, 0), 0)
			n += 1
	lo2.queue_ops([[InputCmd.OP_MOVE, String(x), 0, 0, 0, Loadout.CORE]])
	lo2.apply_ops(p2)
	var xe := lo2.find_item(x)
	var le := lo2.find_item(long)
	if xe.get("where", -9) != Loadout.CORE or le.get("where", -9) != Loadout.BAG or le.entry.cell != x_cell:
		return "倉庫滿了也應換得回去（倉庫每格一件）：骰子 %s、長的 %s" % [xe, le]
	# 換不過去：倉庫的長道具放到主袋最右邊的骰子上，蓋住 1 件但超出邊界 → 都不動
	var w3 := _new_world(4)
	var p3 := _player(w3)
	var lo3 := p3.loadout
	var edge := Vector2i(BagDefs.MAIN_SIZE.x - 1, 0)
	var dice3 := lo3.add_item(p3, &"loaded_dice", {"cell": edge, "rot": 0}, 0, Loadout.CORE)
	var long3 := lo3.add_item(p3, _shaped(&"i2"), {}, 0, Loadout.BAG)
	if lo3.swap_partner(long3, Loadout.CORE, edge, 0) != &"":
		return "預覽：換不過去時不應顯示互換"
	lo3.queue_ops([[InputCmd.OP_MOVE, String(long3), edge.x, edge.y, 0, Loadout.CORE]])
	lo3.apply_ops(p3)
	if lo3.find_item(long3).get("where", -9) != Loadout.BAG or lo3.find_item(dice3).get("where", -9) != Loadout.CORE or _named(w3.events, "inventory:denied").is_empty():
		return "超出主袋邊界換不過去時應兩件都不動、發 inventory:denied：%s / %s" % [lo3.find_item(long3), lo3.find_item(dice3)]
	return ""

static func check_soul_chests() -> String:
	# 擺放規則換 20 個種子看（台階邊緣的位置約 8% 會抽到，單一種子擋不住）
	for s in range(1, 21):
		var ws := _new_world(s, false, &"graveyard_a")
		var e := _chest_layout(ws, 1)
		if e == "":
			ws.next_floor()   # 第 2 層的地圖（墓窟）照同一套規則
			e = _chest_layout(ws, 1)
		ws.clear()
		if e != "":
			return "種子 %d 第 %d 層：%s" % [s, ws.floor_num, e]
	var w := _new_world(12345, false, &"graveyard_a")
	var err := _chest_layout(w, 1)
	if err != "":
		return err
	var p := _player(w)
	var g := _spawn(w, &"grunt", p.pos + Vector2(3, 0))
	g.die()
	var b := _spawn(w, &"boss", p.pos + Vector2(-6, 0))
	b.die()
	var earned: int = LootDefs.KILL_SOULS[&"grunt"] + LootDefs.KILL_SOULS[&"boss"]
	if w.souls != earned:
		return "殺骷髏 + Boss 應得 %d 靈魂，實際 %d" % [earned, w.souls]
	var chest: Chest = null
	for c: Entity in w.chests:
		if (c as Chest).tier == &"big":
			chest = c
	var price: int = LootDefs.CHESTS[&"big"].price
	p.pos = chest.pos + Vector2(0, 1.5)
	w.souls = price - 1
	w.events.clear()
	if chest.try_open(p) or chest.opened or w.souls != price - 1 or _named(w.events, "chest:denied").is_empty():
		return "靈魂 %d < %d 應開不了並發出 chest:denied" % [price - 1, price]
	w.souls = price + 1
	var before := w.relics.size()   # Boss 也掉一個遺物
	if not chest.try_open(p) or not chest.opened or w.souls != 1 or w.relics.size() != before + 1:
		return "靈魂夠應打開：開了 %s、剩 %d、地上多了 %d 個遺物" % [chest.opened, w.souls, w.relics.size() - before]
	var relic: Relic = w.relics.back()
	if relic.pos.distance_to(chest.pos) > LootDefs.DROP_DISTANCE + 1.0 or relic.tier != &"big":
		return "石棺的遺物應在旁邊、用石棺的機率：距離 %.2f、%s" % [relic.pos.distance_to(chest.pos), relic.tier]
	if p.relic_id != relic.id or not relic.offers.has(p.peer_id):   # 2026-10-31 使用者：開完不用再按一次 F
		return "開石棺的人應直接打開遺物的 N 選 1（relic_id %d，遺物 %d）" % [p.relic_id, relic.id]
	# 道具遺物的選項照石棺的稀有度；技能遺物（第 7 步，skill_chance）的選項都是技能（技能的稀有度固定白色，不看石棺的機率）
	for id: StringName in relic.offers.get(p.peer_id, []):
		if relic.relic_kind == &"skill":
			if not ItemDefs.is_skill(id):
				return "技能遺物的選項應都是技能：%s" % id
		elif LootDefs.CHESTS.big.weights.get(ItemDefs.ITEMS[id].rarity, 0.0) <= 0.0:
			return "石棺的遺物不應有 %s 的選項（%s）" % [ItemDefs.ITEMS[id].rarity, id]
	w.souls = 100
	if chest.try_open(p) or w.souls != 100:
		return "開過的寶箱不能再開"
	return ""


# 寶箱的數量（不跟人數變）與位置規則（可走、走得到出生點、離出生點 / 挖墳點 / 地圖邊緣夠遠、底面是平的）
static func _chest_layout(w: World, players: int) -> String:
	var c: Dictionary = LootDefs.CHEST_PLACEMENT
	var want := {}
	for tier: StringName in w.map.chest_count:
		want[tier] = int(w.map.chest_count[tier])   # 不跟人數變
	var tiers := {}
	var lim: Vector2 = w.half_extents - Vector2(c.edge_margin, c.edge_margin)
	for e: Entity in w.chests:
		tiers[(e as Chest).tier] = tiers.get((e as Chest).tier, 0) + 1
		if not w.nav.is_walkable(e.pos) or not w.nav.same_region(e.pos, w.spawn_point):
			return "寶箱 %s 放在走不到的地方" % e.pos
		if e.pos.distance_to(w.spawn_point) < c.min_spawn_distance or e.pos.distance_to(w.event.point) < c.min_dig_distance:
			return "寶箱 %s 離出生點 %.1f、挖墳點 %.1f，太近" % [e.pos, e.pos.distance_to(w.spawn_point), e.pos.distance_to(w.event.point)]
		if absf(e.pos.x) > lim.x or absf(e.pos.y) > lim.y:
			return "寶箱 %s 太靠近地圖邊緣" % e.pos
	# 底面是平的：半徑內地面都和中心差不到一階（不擺在台階邊緣半邊懸空，使用者回報）
	for e: Entity in w.chests + w.forges:
		var g := w.terrain.ground_at(e.pos)
		for k in 24:
			for rr: float in [0.3, 0.7, 1.0]:
				var gk := w.terrain.ground_at(e.pos + Vector2.from_angle(k * TAU / 24.0) * e.radius * rr)
				if absf(gk - g) > Config.HEIGHT.step:
					return "%s %s 擺在高低差上：中心高 %.2f、底面有 %.2f" % [e.kind, e.pos, g, gk]
	if tiers != want:
		return "%d 人時地圖 A 的寶箱 %s，應為 %s" % [players, tiers, want]
	return ""


# 寶箱隨機放與靈魂平衡（v0.44.0）：不同種子位置不同、同種子相同；2 / 4 人寶箱數量與殺怪靈魂都和單人一樣；
# 召喚出來的怪不給靈魂；開場怪群全清（10 個種子）賺的靈魂都買不完全部寶箱
static func check_chest_balance() -> String:
	var spots := func(w: World) -> Array:
		return w.chests.map(func(e: Entity) -> Vector2: return e.pos)
	var a := _new_world(1, false, &"graveyard_a")
	var a2 := _new_world(1, false, &"graveyard_a")
	var b := _new_world(2, false, &"graveyard_a")
	if spots.call(a) != spots.call(a2):
		return "同一個種子的寶箱位置應相同（連線重播與決定性）"
	if spots.call(a) == spots.call(b):
		return "不同種子的寶箱位置應不同（隨機放）"
	var min_gap := INF
	for i in a.chests.size():
		for j in range(i + 1, a.chests.size()):
			min_gap = minf(min_gap, a.chests[i].pos.distance_to(a.chests[j].pos))
	if min_gap < LootDefs.CHEST_PLACEMENT.min_chest_distance:
		return "單人時寶箱之間最近 %.1f，應至少 %.1f（地圖 A 放得下，不該放寬）" % [min_gap, LootDefs.CHEST_PLACEMENT.min_chest_distance]
	for players in [2, 4]:
		var peers: Array[int] = []
		for i in players:
			peers.append(World.HOST_PEER_ID + i)
		var wm := World.new(&"graveyard_a")
		wm.spawn_packs = false
		wm.reset(3, peers)
		wm.spawner.finished = true
		_worlds.append(wm)
		var err := _chest_layout(wm, players)
		if err != "":
			return err
		var g := _spawn(wm, &"grunt", Vector2(0, 30))
		g.die()
		var want: int = LootDefs.KILL_SOULS[&"grunt"]
		if wm.souls != want:
			return "%d 人時殺一隻骷髏應得 %d 靈魂，實際 %d" % [players, want, wm.souls]
	# 召喚詞條、Boss 召喚出來的怪不給靈魂
	var w := _new_world(4, false, &"graveyard_a")
	var summoner := _spawn(w, &"grunt", Vector2(0, 30))
	summoner.set_rarity(MonsterRarityDefs.MAGIC, [&"summoner"], "")
	summoner._summon_timer = 0.0
	summoner.dormant = false
	var boss := _spawn(w, &"boss", Vector2(10, 30))
	for i in roundi(EnemyDefs.ENEMIES.grunt.get("spawn_time", 1.0) / DT) + 5:
		w.step({World.HOST_PEER_ID: InputCmd.new()}, DT)
	boss.summon_minions()
	var minions := w.enemies.filter(func(e: Entity) -> bool: return e is Enemy and (e as Enemy).no_souls)
	var from_affix := minions.filter(func(e: Entity) -> bool: return (e as Enemy).summoner_id == summoner.id).size()
	if from_affix == 0 or minions.size() <= from_affix:
		return "應有召喚詞條與 Boss 叫出來的怪（詞條 %d、全部 %d）" % [from_affix, minions.size()]
	w.souls = 0
	for e: Entity in minions:
		e.die()
	if w.souls != 0:
		return "召喚出來的 %d 隻怪死了給了 %d 靈魂，應為 0" % [minions.size(), w.souls]
	# 開場怪群全清 + Boss 的靈魂 < 全部寶箱的價錢
	var total_price := 0
	for tier: StringName in a.map.chest_count:
		total_price += a.map.chest_count[tier] * LootDefs.CHESTS[tier].price
	var most := 0
	for seed_value in range(1, 11):
		var wp := World.new(&"graveyard_a")
		wp.reset(seed_value)
		_worlds.append(wp)
		var souls: int = LootDefs.KILL_SOULS.boss
		for e: Entity in wp.enemies:
			souls += LootDefs.KILL_SOULS.get((e as Enemy).type, 0)
		most = maxi(most, souls)
	if most >= total_price:
		return "開場怪群全清最多賺 %d 靈魂，全部寶箱 %d，應買不完" % [most, total_price]
	return ""


# 局外金幣（v0.45）：過關給 floor_clear_per_floor × 剛過的層數（越後面越多）；地上的金幣活著的玩家走近自動撿、倒地的不撿；
# 多人時只記一個數字（全員各拿一份）；Profile 存檔讀得回來、save_path = "" 不寫檔
static func check_run_coins() -> String:
	var w := _new_world(5, false, &"graveyard_a")
	var per: int = LootDefs.RUN_COINS.floor_clear_per_floor
	w.next_floor()
	var got := [w.run_coins]
	w.events.clear()   # 沒有經過 step，事件不會自動清
	w.next_floor()
	got.append(w.run_coins)
	if got != [per, per * 3]:
		return "過第 1、2 層後金幣應為 %d / %d（第 2 層給 %d），實際 %s" % [per, per * 3, per * 2, got]
	var ev := _named(w.events, "coins:gained")
	if ev.size() != 1 or ev[0].amount != per * 2 or ev[0].reason != "floor":
		return "過第 2 層應發出一個 coins:gained（%d、floor）：%s" % [per * 2, ev]
	# 走近自動撿；倒地的玩家不撿
	var peers: Array[int] = [World.HOST_PEER_ID, World.HOST_PEER_ID + 1]
	var wm := World.new(&"graveyard_a")
	wm.spawn_packs = false
	wm.reset(6, peers)
	wm.spawner.finished = true
	_worlds.append(wm)
	var p1: Player = wm.players[peers[0]]
	var p2: Player = wm.players[peers[1]]
	p2.pos = p1.pos + Vector2(-8, 0)
	var coin := wm.drop_coin(p1.pos + Vector2(4, 0))
	var idle := {peers[0]: InputCmd.new(), peers[1]: InputCmd.new()}
	for i in 10:
		wm.step(idle, DT)
	if coin.is_removed or wm.run_coins != 0:
		return "離 4 單位的金幣不該被撿走（撿取距離 %.1f）" % LootDefs.RUN_COINS.collect_range
	p1.is_downed = true
	p1.down_timer = 99.0   # 倒地計時到 0 會直接死亡（World._update_downed）
	p1.pos = coin.pos
	wm.step(idle, DT)
	if coin.is_removed:
		return "倒地的玩家不該撿到金幣"
	p1.is_downed = false
	wm.step(idle, DT)
	if not coin.is_removed or wm.run_coins != 1 or not wm.coins.is_empty() or _named(wm.events, "coins:gained").is_empty():
		return "走到金幣上應撿起：移除 %s、本局金幣 %d（應 1）、地上 %d" % [coin.is_removed, wm.run_coins, wm.coins.size()]
	# 存檔
	var path := "user://check_profile.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var pf := Profile.new()
	pf.save_path = path
	pf.load_file()
	pf.add_coins(7)
	pf.add_coins(3)
	var pf2 := Profile.new()
	pf2.save_path = path
	pf2.load_file()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if pf2.coins != 10:
		return "存檔後重新讀取應有 10 金幣，實際 %d" % pf2.coins
	var mem := Profile.new()
	mem.save_path = ""
	mem.add_coins(5)
	if mem.coins != 5 or FileAccess.file_exists(path):
		return "save_path 為空時只記在記憶體、不寫檔"
	return ""


# 掉金幣的機率（v0.45）：小怪、Boss 大量抽樣符合 RUN_COINS.drop_chance；召喚出來的不掉（用另外的 coin_rng，world.rng 的序列不變）
static func check_coin_drops() -> String:
	var w := _new_world(8, false, &"graveyard_a")
	var cases := {&"grunt": 40000, &"boss": 3000}
	for type: StringName in cases:
		var n: int = cases[type]
		var chance: float = LootDefs.RUN_COINS.drop_chance[type]
		var e := _spawn(w, type, Vector2(0, 30))
		var before := w.coins.size()
		for i in n:
			w.on_enemy_died(e)
		var rate := float(w.coins.size() - before) / n
		# 容許 4 個標準差（二項分布）
		var tol := 4.0 * sqrt(chance * (1.0 - chance) / n)
		_feel("v0.45 掉金幣：%s 死 %d 次掉 %d 枚（%.2f%%，設定 %.2f%%）" % [type, n, w.coins.size() - before, rate * 100.0, chance * 100.0])
		if absf(rate - chance) > tol:
			return "%s 掉金幣率 %.3f%%，應為 %.3f%% ± %.3f%%" % [type, rate * 100.0, chance * 100.0, tol * 100.0]
		e.remove()
	var minion := _spawn(w, &"grunt", Vector2(5, 30))
	minion.no_souls = true
	var before_minion := w.coins.size()
	for i in 20000:
		w.on_enemy_died(minion)
	if w.coins.size() != before_minion:
		return "召喚出來的怪不該掉金幣（掉了 %d 枚）" % (w.coins.size() - before_minion)
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
	if _held_items(p).size() != 1 or not drop.is_removed or absf(p.stats.value(&"damage") - one) > EPS:
		return "按 F 應撿起磨刀石（鑲在武器上）並生效：拿著 %d、攻擊力 %.2f" % [_held_items(p).size(), p.stats.value(&"damage")]
	# 按住不放不會連撿
	w.drop_item(&"whetstone", p.pos + Vector2(1.0, 0))
	_run(w, press, 10)
	if _held_items(p).size() != 1:
		return "按住 F 不放不應再撿，背包 %d" % _held_items(p).size()
	_run(w, _cmd(Vector2.ZERO), 1)
	_run(w, press, 1)
	if _held_items(p).size() != 2:
		return "放開再按應撿起第二個，背包 %d" % _held_items(p).size()
	# 丟掉：回到地上、效果移除
	var uid: StringName = _held_items(p)[0].uid
	var drop_cmd := _cmd(Vector2.ZERO)
	drop_cmd.inv_ops = [[InputCmd.OP_DROP, String(uid)]]
	_run(w, drop_cmd, 1)
	if _held_items(p).size() != 1 or w.pickups.size() != 1 or absf(p.stats.value(&"damage") - one) > EPS:
		return "丟掉一個：背包 %d、地上 %d、攻擊力 %.2f（應為 1 / 1 / %.2f）" % [_held_items(p).size(), w.pickups.size(), p.stats.value(&"damage"), one]
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
	if _held_items(a).size() + _held_items(c).size() != 1:
		return "兩人同時撿：共拿到 %d 個（應為 1）" % (_held_items(a).size() + _held_items(c).size())
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
	if not d.is_downed or _held_items(r).size() != 0:
		return "旁邊有倒地隊友時 F 應先救人：倒地 %s、撿到 %d" % [d.is_downed, _held_items(r).size()]
	return ""


# 從背包介面的「腳邊」撿（OP_PICKUP）：放到指定的格子與方向並生效、地上的消失；已經被撿走、按不到 F、放不下的不動；
# 武器放進背包指定的格子（不放空的裝備欄）；按 F 撿不下時 inventory:full 帶著地上道具的 id
static func check_pickup_to_cell() -> String:
	var w := _new_world(12345, false, &"test_arena")
	var p := _player(w)
	var pick := func(ip: ItemPickup, cell: Vector2i, rot: int) -> void:
		var cmd := _cmd(Vector2.ZERO)
		cmd.inv_ops = [[InputCmd.OP_PICKUP, ip.id, cell.x, cell.y, rot]]
		_run(w, cmd, 1)
	var stone := w.drop_item(&"whetstone", p.pos + Vector2(1.0, 0))
	pick.call(stone, Vector2i(3, 0), 1)
	var e: Dictionary = p.inventory.entries[0] if p.inventory.entries.size() == 1 else {}
	if e.is_empty() or e.cell != Vector2i(3, 0) or e.rot != 1 or not stone.is_removed:
		return "OP_PICKUP 應把磨刀石放在倉庫 (3, 0) 並從地上移除：背包 %s、地上還在 %s" % [p.inventory.entries, not stone.is_removed]
	if absf(p.stats.value(&"damage") - 1.0) > EPS:
		return "背包裡的道具沒有效果：攻擊力 %.2f（應為 1.00）" % p.stats.value(&"damage")
	# 搬到主袋 (1, 1) 才生效，搬回倉庫就失效
	var one := 1.0 + _effect_value(&"whetstone", &"damage")
	var sock := _cmd(Vector2.ZERO)
	sock.inv_ops = [[InputCmd.OP_MOVE, String(e.uid), 1, 1, 0, Loadout.CORE]]
	_run(w, sock, 1)
	if p.loadout.find_item(e.uid).get("where", -9) != Loadout.CORE or absf(p.stats.value(&"damage") - one) > EPS:
		return "磨刀石搬到主袋 (1, 1) 應生效：%s、攻擊力 %.2f" % [p.loadout.find_item(e.uid), p.stats.value(&"damage")]
	var unsock := _cmd(Vector2.ZERO)
	unsock.inv_ops = [[InputCmd.OP_MOVE, String(e.uid), 3, 0, 1]]
	_run(w, unsock, 1)
	if p.inventory.find(e.uid).is_empty() or absf(p.stats.value(&"damage") - 1.0) > EPS:
		return "磨刀石搬回背包應失效：攻擊力 %.2f" % p.stats.value(&"damage")
	pick.call(stone, Vector2i(0, 0), 0)
	if p.inventory.entries.size() != 1:
		return "已經撿走的不應再撿一次，背包 %d" % p.inventory.entries.size()
	var far := w.drop_item(&"whetstone", p.pos + Vector2(LootDefs.INTERACT_RANGE + 3.0, 0))
	pick.call(far, Vector2i(0, 0), 0)
	if p.inventory.entries.size() != 1 or far.is_removed:
		return "按不到 F 的距離不應撿得到"
	var near := w.drop_item(&"whetstone", p.pos + Vector2(1.0, 0))
	pick.call(near, Vector2i(3, 0), 0)   # (3, 0) 被磨刀石占著
	if p.inventory.entries.size() != 1 or near.is_removed:
		return "放不下的格子不應撿起"
	p.weapon_slots[1] = {}
	var inst := {"uid": w.new_weapon_uid(), "base": &"staff", "rarity": &"white", "affixes": [] as Array[StringName]}
	var staff := w.drop_weapon(inst, p.pos + Vector2(1.0, 0))
	pick.call(staff, Vector2i(5, 0), 0)
	if not p.weapon_slots[1].is_empty() or p.inventory.find(inst.uid).get("cell", Vector2i(-1, -1)) != Vector2i(5, 0):
		return "武器從腳邊拖進倉庫應放在 (5, 0)、不放空的裝備欄：裝備欄 %s、倉庫 %s" % [p.weapon_slots[1], p.inventory.find(inst.uid)]
	# 武器格子與背包都滿了按 F：inventory:full 帶著地上那個的 id
	var w2 := _new_world(12345, false, &"test_arena")
	var q := _player(w2)
	while q.add_item(&"loaded_dice") != &"":
		pass
	var dice := w2.drop_item(&"loaded_dice", q.pos + Vector2(1.0, 0))
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_INTERACT), 1)
	var full := _named(w2.events, "inventory:full")
	if full.is_empty() or full[-1].get("pickup_id", 0) != dice.id or dice.is_removed:
		return "撿不下時 inventory:full 應帶 pickup_id = %d：%s" % [dice.id, full]
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
	var want_pct: float = WeaponDropDefs.drop_chance(&"grunt", w.floor_num) * 100.0
	if absf(pct - want_pct) > 0.9:
		return "第 %d 層小怪掉武器 %.2f%%，應約 %.1f%%" % [w.floor_num, pct, want_pct]
	# 召喚出來的（no_souls）不掉：一般掉率下 2000 隻都沒掉
	var summoned := 0
	for i in 2000:
		var s := _spawn(w, &"grunt", p.pos + Vector2(6, 0))
		s.no_souls = true
		var before := w.events.size()
		s.die()
		for k in range(before, w.events.size()):
			if w.events[k].name == "weapon:dropped":
				summoned += 1
		s.remove()
		if i % 200 == 0:
			w._remove_dead_entities()
			w.events.clear()
	if summoned > 0:
		return "召喚出來的小怪不該掉武器，2000 隻掉了 %d 把" % summoned
	# 超過表的層用最後一層
	var last: int = WeaponDropDefs.MINION_DROP_BY_FLOOR.keys().max()
	if WeaponDropDefs.drop_chance(&"grunt", last + 5) != WeaponDropDefs.MINION_DROP_BY_FLOOR[last] or WeaponDropDefs.drop_chance(&"ghost", 1) != 0.0:
		return "第 %d 層應用最後一層的掉率、冤魂不掉武器" % (last + 5)
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
	_note("小怪死 %d 次掉 %d 把（%.2f%%）" % [n, drops, pct])
	return ""


# 觸發袋改版後武器沒有詞條：每種稀有度做出來都沒有；撿到時在倉庫不生效；主手照稀有度套基礎倍率；副手沒有數值
static func check_weapon_affixes() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for r in WeaponDropDefs.RARITY_ORDER:
		var inst := WeaponDropDefs.make(&"x", &"staff", r, rng)
		if not inst.affixes.is_empty() or inst.has("sockets") or inst.has("imprints"):
			return "%s 法杖不應有詞條、寶石座或印記格：%s" % [r, inst]
	var w := _new_world()
	var p := _player(w)
	p.add_weapon({"uid": &"blue", "base": &"staff", "rarity": &"blue", "affixes": [] as Array[StringName]})
	if p.inventory.find(&"blue").is_empty() or absf(p.stats.value(&"damage") - 1.0) > EPS:
		return "撿到的法杖應放倉庫、不生效：攻擊力 %.2f" % p.stats.value(&"damage")
	var equip := _cmd(Vector2.ZERO)
	equip.inv_ops = [[InputCmd.OP_EQUIP, "blue", Loadout.MAIN]]
	_run(w, equip, 1)
	var want_dmg: float = WeaponDropDefs.RARITY_BASE.blue.damage
	var want_spd: float = WeaponDropDefs.RARITY_BASE.blue.attack_speed
	if p.weapon_id != &"staff" or absf(p.stats.value(&"damage") - want_dmg) > EPS or absf(p.stats.value(&"attack_speed") - want_spd) > EPS:
		return "藍法杖裝上主手後攻擊力 / 攻速應為 %.2f / %.2f：%s、%.2f / %.2f" % [want_dmg, want_spd, p.weapon_id, p.stats.value(&"damage"), p.stats.value(&"attack_speed")]
	var w2 := _new_world()
	var p2 := _player(w2)
	p2.weapon_slots[Loadout.OFF] = {"uid": &"gs", "base": &"woodShield", "rarity": &"orange", "affixes": [] as Array[StringName]}
	p2.apply_active_weapon()
	if absf(p2.stats.value(&"armor")) > EPS or absf(p2.stats.value(&"damage") - 1.0) > EPS:
		return "橘木盾當副手不應加數值：護甲 %.1f、攻擊力 %.2f" % [p2.stats.value(&"armor"), p2.stats.value(&"damage")]
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


# 怪受到 raw 傷害時實際扣多少（套護甲、抗性與受傷倍率，同 Entity.take_damage）
static func _dealt(e: Enemy, raw: float, damage_type := &"phys") -> int:
	return roundi(_dealt_exact(e, raw, damage_type))


static func _dealt_exact(e: Enemy, raw: float, damage_type := &"phys") -> float:
	return raw * StatDefs.damage_factor(e.stats, damage_type) * e.damage_taken_mul


# 道具效果的類別（v0.42.1 重構）：ItemDefs 標成「已接上」的條件 / 觸發，和 ItemEffects 登錄的類別一一對應
static func check_item_effect_registry() -> String:
	var conds: Array = ItemEffects.CONDITIONS.keys()
	for c: StringName in ItemDefs.IMPLEMENTED_CONDITIONS:
		if not conds.has(c):
			return "條件 %s 標成已接上，但 ItemEffects.CONDITIONS 沒有類別" % c
	for c: StringName in conds:
		if not ItemDefs.IMPLEMENTED_CONDITIONS.has(c):
			return "條件 %s 有類別，但 ItemDefs.IMPLEMENTED_CONDITIONS 沒列" % c
	var wired: Array[String] = []
	for do: StringName in ItemEffects.ACTIONS:
		for on: StringName in (ItemEffects.ACTIONS[do] as ItemEffects.Action).triggers():
			wired.append("%s|%s" % [on, do])
	for t: String in ItemDefs.IMPLEMENTED_TRIGGERS:
		if not wired.has(t):
			return "觸發 %s 標成已接上，但沒有動作類別接在這個觸發上" % t
	for t: String in wired:
		if not ItemDefs.IMPLEMENTED_TRIGGERS.has(t):
			return "觸發 %s 有動作類別，但 ItemDefs.IMPLEMENTED_TRIGGERS 沒列" % t
	return ""


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
	# 戰鼓：擊殺後一段時間攻速加成；吸魂鐮：擊殺回復魔力
	var drum := _effect(&"war_drum")
	var want_mana: float = 50.0 + p.max_mana() * _effect(&"soul_scythe").ratio
	p.add_item(&"war_drum")
	_put(p, _bag(p, &"kill", &"left"), &"soul_scythe")   # 吸魂鐮是效果：放左邊的擊殺袋、普攻打死才發動（扣掉自己的耗魔）
	p.mana = 50.0
	want_mana -= BagTriggers.effect_mana(&"soul_scythe")
	var b := _item_dummy(w, Vector2(0, 3), 1.0)
	Combat.apply_damage(w, p, b, {"damage": 10.0, "attack": &"primary"})
	if not b.is_dead or absf(p.mana - want_mana) > EPS:
		return "擊殺後魔力應為 %.1f，實際 %.1f（怪死了 %s）" % [want_mana, p.mana, b.is_dead]
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
	# 火藥包放左邊的擊殺袋：普攻打死怪時爆炸，旁邊的怪受那一下的 damage_ratio；右鍵、技能打死的不發動左邊的袋子
	var ex: Dictionary = ItemDefs.PROCS[&"explode"]
	_put(p, _bag(p, &"kill", &"left"), &"powder_pouch")
	var a := _item_dummy(w, Vector2(0, 4), 1.0)
	var b := _item_dummy(w, Vector2(minf(1.0, ex.radius * 0.5), 4))
	var b_before := b.hp
	Combat.apply_damage(w, p, a, {"damage": 40.0, "attack": &"primary"})
	if _hp_loss(b, b_before) != _dealt(b, 40.0 * ex.damage_ratio):
		return "爆炸應讓旁邊的怪扣 %d，實際 %d" % [_dealt(b, 40.0 * ex.damage_ratio), _hp_loss(b, b_before)]
	for tag: StringName in [&"secondary", &"skill"]:
		b_before = b.hp
		Combat.apply_damage(w, p, _item_dummy(w, Vector2(0, 4), 1.0), {"damage": 40.0, "attack": tag})
		if _hp_loss(b, b_before) != 0:
			return "%s 打死的不應發動左邊的擊殺袋（旁邊的怪扣了 %d）" % [tag, _hp_loss(b, b_before)]
	p.clear_items()
	w.clear()
	# 雷鳴符文（左邊的命中袋，普攻打中就發動）：
	# a → b → c（每跳都在 jump_range 內），d 太遠；每跳 damage_ratio，閃電不會再觸發閃電
	var cl: Dictionary = ItemDefs.PROCS[&"chain_lightning"]
	var jr: float = cl.jump_range
	w = _new_world()
	p = _player(w)
	_put(p, _bag(p, &"hit", &"left"), &"thunder_rune")
	a = _item_dummy(w, Vector2(0, 5))
	b = _item_dummy(w, Vector2(0, 5 + jr * 0.6))
	var c := _item_dummy(w, Vector2(0, 5 + jr * 1.4))
	var d := _item_dummy(w, Vector2(0, 5 + jr * 5.0))
	var hp0 := [a.max_hp, b.max_hp, c.max_hp, d.max_hp]
	for i in 300:
		for e: Enemy in [a, b, c, d]:
			e.hp = e.max_hp
		w.events.clear()
		Combat.apply_damage(w, p, a, {"damage": 10.0, "attack": &"primary"})
		if b.hp < b.max_hp:
			break
	var got := [_hp_loss(a, hp0[0]), _hp_loss(b, hp0[1]), _hp_loss(c, hp0[2]), _hp_loss(d, hp0[3])]
	var want := [_dealt(a, 10.0), _dealt(b, 10.0 * cl.damage_ratio), _dealt(c, 10.0 * cl.damage_ratio), 0]
	if got != want:
		return "連鎖閃電 a / b / c / d 應扣 %s，實際 %s" % [want, got]
	var bolts := w.events.filter(func(ev: Dictionary) -> bool: return ev.name == "fx:lightning")
	if bolts.size() != 1 or bolts[0].points.size() != _effect(&"thunder_rune").targets:
		return "應有 1 道經過 %d 點的閃電：%s" % [_effect(&"thunder_rune").targets, bolts]
	p.clear_items()
	w.clear()
	# 淬毒刀刃（左邊的命中袋）：中毒那一下 10 → duration 秒共 10 × total_ratio，每 tick 秒扣一次
	var po: Dictionary = ItemDefs.PROCS[&"poison"]
	var ticks := roundi(po.duration / po.tick)
	w = _new_world()
	p = _player(w)
	_put(p, _bag(p, &"hit", &"left"), &"venom_blade")
	a = _item_dummy(w, Vector2(0, 5))
	var before := a.max_hp
	for i in 300:
		a.hp = a.max_hp
		Combat.apply_damage(w, p, a, {"damage": 10.0, "attack": &"primary"})
		if a.poison_timer > 0.0:
			break
	if a.poison_timer <= 0.0:
		return "命中後應中毒"
	_run(w, idle, roundi(po.duration / DT) + 20)
	var want_poison := roundi(_dealt_exact(a, 10.0) + ticks * _dealt_exact(a, 10.0 * po.total_ratio / ticks, &"poison"))
	if _hp_loss(a, before) != want_poison:
		return "中毒 %.1f 秒後總共應扣 %d，實際 %d" % [po.duration, want_poison, _hp_loss(a, before)]
	p.clear_items()
	w.clear()
	# 霜之心（左邊的命中袋）：冰凍 duration 秒不能動，之後照常追；Boss 不會被冰凍
	var freeze_time: float = _effect(&"frost_heart").duration
	w = _new_world()
	p = _player(w)
	_put(p, _bag(p, &"hit", &"left"), &"frost_heart")
	a = _item_dummy(w, Vector2(0, 6))
	for i in 300:
		Combat.apply_damage(w, p, a, {"damage": 1.0, "attack": &"primary"})
		if a.frozen_timer > 0.0:
			break
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


# 屬性（第二批）：接到各系統的屬性（命中回復、吸血、投射物減傷、靈魂、祭壇價格、撿取範圍、視野）
static func check_item_stats() -> String:
	var w := _new_world()
	var p := _player(w)
	var idle := _cmd(Vector2.ZERO)
	# 蝙蝠牙（左邊命中袋的回血效果）：普攻同一步打兩下只回一次（命中袋的內部冷卻），冷卻過了再回
	var loh := _effect_value(&"bat_fang", &"life_on_hit")
	_put(p, _bag(p, &"hit", &"left"), &"bat_fang")
	p.hp = 50.0
	var a := _item_dummy(w, Vector2(0, 3))
	Combat.apply_damage(w, p, a, {"damage": 10.0, "attack": &"primary"})
	Combat.apply_damage(w, p, a, {"damage": 10.0, "attack": &"primary"})
	if absf(p.hp - (50.0 + loh)) > EPS:
		return "蝙蝠牙同一步打兩下應只回 %.0f：生命 %.1f" % [loh, p.hp]
	_run(w, idle, ceili(BagDefs.BAGS.hit.icd / DT) + 1)
	Combat.apply_damage(w, p, a, {"damage": 10.0, "attack": &"primary"})
	if absf(p.hp - (50.0 + loh * 2.0)) > EPS:
		return "蝙蝠牙冷卻過後應再回 %.0f：生命 %.1f" % [loh, p.hp]
	p.clear_items()
	# 血族王冠：實際扣血的比例；道具效果（proc）的傷害不算
	var ls := _effect_value(&"blood_crown", &"lifesteal")
	p.add_item(&"blood_crown")
	p.hp = 50.0
	var before := a.hp
	Combat.apply_damage(w, p, a, {"damage": 40.0})
	var want_hp := 50.0 + (before - a.hp) * ls
	if absf(p.hp - want_hp) > EPS:
		return "血族王冠應回到 %.2f：%.2f" % [want_hp, p.hp]
	Combat.apply_damage(w, p, a, ItemEffects.proc_hit(40.0, a, Color.WHITE))
	if absf(p.hp - want_hp) > EPS:
		return "道具效果的傷害不該吸血：%.2f → %.2f" % [want_hp, p.hp]
	p.clear_items()
	# 鐵皮斗篷：投射物的傷害 × projectile_damage_taken，近戰照常
	var archer := _item_dummy(w, Vector2(5, 0))
	p.hp = p.max_hp
	Combat.apply_damage(w, archer, p, {"damage": 20.0, "projectile": true})
	var plain := p.max_hp - p.hp
	p.add_item(&"iron_cloak")
	p.hp = p.max_hp
	p.invuln_timer = 0.0   # 受傷後的無敵時間
	Combat.apply_damage(w, archer, p, {"damage": 20.0, "projectile": true})
	var cloaked := p.max_hp - p.hp
	var mul := _effect_value(&"iron_cloak", &"projectile_damage_taken")
	if absf(cloaked - plain * mul) > 0.01:
		return "鐵皮斗篷：投射物 %.2f × %.2f 應為 %.2f，實際 %.2f" % [plain, mul, plain * mul, cloaked]
	p.hp = p.max_hp
	p.invuln_timer = 0.0
	Combat.apply_damage(w, archer, p, {"damage": 20.0})
	if absf((p.max_hp - p.hp) - plain) > 0.01:
		return "鐵皮斗篷不該減近戰傷害：%.2f / %.2f" % [p.max_hp - p.hp, plain]
	p.clear_items()
	# 盜墓者錢袋：擊殺者的靈魂獲得，小數累積；貪婪之手：精英怪（魔法 / 稀有）再 ×2，普通怪不變
	var base: int = LootDefs.KILL_SOULS[&"grunt"]
	var gain := _effect_value(&"grave_purse", &"soul_gain")
	p.add_item(&"grave_purse")
	w.souls = 0
	var kills := 20
	for i in kills:
		Combat.apply_damage(w, p, _item_dummy(w, Vector2(0, 3), 1.0), {"damage": 10.0})
	var want_souls := kills * base * (1.0 + gain)
	if absf(w.souls - want_souls) > 1.0:
		return "盜墓者錢袋殺 %d 隻應得約 %.1f 靈魂，實際 %d" % [kills, want_souls, w.souls]
	p.clear_items()
	p.add_item(&"greedy_hand")
	w.souls = 0
	w.soul_carry = 0.0
	Combat.apply_damage(w, p, _item_dummy(w, Vector2(0, 3), 1.0), {"damage": 10.0})
	var elite := _item_dummy(w, Vector2(0, 3), 1.0)
	elite.set_rarity(MonsterRarityDefs.MAGIC, [])
	Combat.apply_damage(w, p, elite, {"damage": 10.0})
	var greed: float = _effect(&"greedy_hand").value
	if w.souls != base + roundi(base * greed):
		return "貪婪之手：普通 %d + 精英 %d 應為 %d，實際 %d" % [base, roundi(base * greed), base + roundi(base * greed), w.souls]
	p.clear_items()
	# 撬鎖工具：開的人的價格 × chest_price；靈魂剛好夠打折價就開得了
	var chest := Chest.new(w, &"small", Vector2(0, 2))
	w.add_entity(chest)
	p.add_item(&"lockpick")
	var cost := chest.price_for(p)
	if cost != roundi(chest.price() * _effect_value(&"lockpick", &"chest_price")) or cost >= chest.price():
		return "撬鎖工具：原價 %d 應打折，實際 %d" % [chest.price(), cost]
	w.souls = cost
	if not chest.try_open(p) or w.souls != 0:
		return "靈魂剛好 %d 應開得了並扣光：剩 %d" % [cost, w.souls]
	p.clear_items()
	# 磁石：F 的距離與自動撿金幣的距離都乘 pickup_radius
	p.pos = Vector2(12, -12)   # 離開剛剛祭壇掉的道具
	var reach := _effect_value(&"lodestone", &"pickup_radius")
	var far := LootDefs.INTERACT_RANGE * (1.0 + reach * 0.5)
	var drop := w.drop_item(&"whetstone", p.pos + Vector2(0, p.radius + far))
	drop.pos = p.pos + Vector2(0, p.radius + drop.radius + far)
	if w.nearest_interactable(p, w.pickups) != null:
		return "沒有磁石時 %.2f 外的道具不該按得到" % far
	p.add_item(&"lodestone")
	if w.nearest_interactable(p, w.pickups) != drop:
		return "有磁石時 %.2f 外的道具應按得到" % far
	var coin := w.drop_coin(p.pos)
	coin.pos = p.pos + Vector2(p.radius + LootDefs.RUN_COINS.collect_range * (1.0 + reach * 0.5), 0)
	var coins_before := w.run_coins
	_run(w, idle, 1)
	if w.run_coins != coins_before + 1:
		return "有磁石時稍遠的金幣應自動撿起"
	p.clear_items()
	# 守夜蠟燭：視野距離與扇形角度 × vision
	var v := _effect_value(&"vigil_candle", &"vision")
	var r0 := Vision.view_range(p)
	var a0 := Vision.view_angle(p)
	p.add_item(&"vigil_candle")
	if absf(Vision.view_range(p) - r0 * (1.0 + v)) > EPS or absf(Vision.view_angle(p) - a0 * (1.0 + v)) > EPS:
		return "守夜蠟燭：視野 %.2f / %.3f 應 ×%.2f：%.2f / %.3f" % [r0, a0, 1.0 + v, Vision.view_range(p), Vision.view_angle(p)]
	return ""


# 條件（第二批）：翻滾後一段時間、本層每擊殺疊一層
static func check_item_conditions_roll_kills() -> String:
	var w := _new_world()
	var p := _player(w)
	var idle := _cmd(Vector2.ZERO)
	# 獵人斗篷：翻滾結束後 duration 秒內爆擊率 +value，之後回來
	var hc := _effect(&"hunter_cloak")
	p.add_item(&"hunter_cloak")
	var crit0 := p.stats.value(&"crit_chance")
	_run(w, _cmd(Vector2(1, 0), Vector2(0, 5), InputCmd.BTN_ROLL), 1)
	_run(w, idle, ceili(Config.ROLL.duration / DT) + 1)
	if absf(p.stats.value(&"crit_chance") - (crit0 + hc.value)) > EPS:
		return "翻滾後爆擊率應為 %.2f，實際 %.2f" % [crit0 + hc.value, p.stats.value(&"crit_chance")]
	_run(w, idle, ceili(hc.duration / DT) + 1)
	if absf(p.stats.value(&"crit_chance") - crit0) > EPS:
		return "翻滾 %.1f 秒後爆擊率應回到 %.2f，實際 %.2f" % [hc.duration, crit0, p.stats.value(&"crit_chance")]
	p.clear_items()
	# 亡者之契：本層每擊殺 +value、最多 max 層；換層歸零
	var pact := _effect(&"pact_of_dead")
	p.add_item(&"pact_of_dead")
	for i in 5:
		Combat.apply_damage(w, p, _item_dummy(w, Vector2(0, 3), 1.0), {"damage": 10.0})
	_run(w, idle, 1)
	if absf(p.stats.value(&"damage") - (1.0 + pact.value * 5)) > EPS:
		return "亡者之契殺 5 隻攻擊力應為 %.2f，實際 %.3f" % [1.0 + pact.value * 5, p.stats.value(&"damage")]
	p.floor_kills = pact.max + 20
	_run(w, idle, 1)
	if absf(p.stats.value(&"damage") - (1.0 + pact.value * pact.max)) > EPS:
		return "亡者之契最多 %d 層：攻擊力 %.3f" % [pact.max, p.stats.value(&"damage")]
	p.arrive_floor(p.pos, p.height)
	_run(w, idle, 1)
	if absf(p.stats.value(&"damage") - 1.0) > EPS:
		return "換層後亡者之契應歸零：攻擊力 %.3f" % p.stats.value(&"damage")
	return ""


# 受傷袋（下方）：反彈、自身爆炸（同一袋的內部冷卻）；命中袋：投射物命中爆炸、點燃並擴散
static func check_item_procs_hurt_ignite() -> String:
	var w := _new_world()
	var p := _player(w)
	var idle := _cmd(Vector2.ZERO)
	p.stats.set_base(&"max_hp", 100000.0)
	p.hp = p.max_hp
	# 荊棘鎖甲（受傷袋）：扣的血 × ratio 打回攻擊者；投射物打到也算受傷（內部冷卻過了再打）
	var thorn := _effect(&"thorn_mail")
	var hurt_bag := _bag(p, &"hurt", &"bottom")
	_put(p, hurt_bag, &"thorn_mail")
	var a := _item_dummy(w, Vector2(0, 2))
	var hp_p := p.hp
	var hp_a := a.hp
	Combat.apply_damage(w, a, p, {"damage": 40.0})
	var taken := hp_p - p.hp
	if _hp_loss(a, hp_a) != _dealt(a, taken * thorn.ratio):
		return "荊棘鎖甲：受到 %.1f 應反彈讓攻擊者扣 %d，實際 %d" % [taken, _dealt(a, taken * thorn.ratio), _hp_loss(a, hp_a)]
	hp_a = a.hp
	_run(w, idle, ceili(BagDefs.BAGS.hurt.icd / DT) + 1)
	p.invuln_timer = 0.0
	Combat.apply_damage(w, a, p, {"damage": 40.0, "projectile": true})
	if _hp_loss(a, hp_a) == 0:
		return "受傷袋：投射物打到也應反彈"
	p.clear_items()
	_run(w, idle, ceili(BagDefs.BAGS.hurt.icd / DT) + 1)
	# 王墓之心（受傷袋）：在打到自己的怪那裡炸、實際扣的血 × damage_ratio；同一袋內部冷卻內再被打不炸
	var heart := _effect(&"tomb_heart")
	var hx := {"icd": BagDefs.BAGS.hurt.icd, "radius": ItemDefs.PROCS.hurt_explode.radius}
	_put(p, hurt_bag, &"tomb_heart")
	var b := _item_dummy(w, Vector2(minf(1.5, hx.radius * 0.5), 0))
	var hp_b := b.hp
	p.invuln_timer = 0.0
	Combat.apply_damage(w, a, p, {"damage": 20.0})
	if _hp_loss(b, hp_b) != _dealt(b, 20.0 * heart.damage_ratio):
		return "王墓之心：旁邊的怪應扣 %d，實際 %d" % [_dealt(b, 20.0 * heart.damage_ratio), _hp_loss(b, hp_b)]
	hp_b = b.hp
	p.invuln_timer = 0.0
	Combat.apply_damage(w, a, p, {"damage": 20.0})
	if _hp_loss(b, hp_b) != 0:
		return "王墓之心內部冷卻 %.1f 秒內不該再炸：扣 %d" % [hx.icd, _hp_loss(b, hp_b)]
	_run(w, idle, ceili(hx.icd / DT) + 1)
	hp_b = b.hp
	p.invuln_timer = 0.0
	Combat.apply_damage(w, a, p, {"damage": 20.0})
	if _hp_loss(b, hp_b) == 0:
		return "王墓之心冷卻過後應再炸"
	p.clear_items()
	w.clear()
	# 爆裂箭袋（左邊的命中袋）：普攻打中時以被打中的怪為中心爆炸（該下 × explode.damage_ratio）；右鍵打中不發動左邊的袋子
	w = _new_world()
	p = _player(w)
	var ex: Dictionary = ItemDefs.PROCS.explode
	_put(p, _bag(p, &"hit", &"left"), &"blast_quiver")
	a = _item_dummy(w, Vector2(0, 5))
	b = _item_dummy(w, Vector2(minf(1.0, ex.radius * 0.5), 5))
	hp_b = b.hp
	Combat.apply_damage(w, p, a, {"damage": 20.0, "projectile": true, "attack": &"primary"})
	if _hp_loss(b, hp_b) != _dealt(b, 20.0 * ex.damage_ratio):
		return "爆裂箭袋：旁邊的怪應扣 %d，實際 %d" % [_dealt(b, 20.0 * ex.damage_ratio), _hp_loss(b, hp_b)]
	_run(w, _cmd(Vector2.ZERO), ceili(BagDefs.BAGS.hit.icd / DT) + 1)
	hp_b = b.hp
	Combat.apply_damage(w, p, a, {"damage": 20.0, "projectile": true, "attack": &"secondary"})
	if _hp_loss(b, hp_b) != 0:
		return "爆裂箭袋：右鍵打中不該發動左邊的命中袋"
	p.clear_items()
	w.clear()
	# 永恆之焰：命中就點燃；燒著的怪 spread_interval 秒後傳給 spread_range 內一隻，太遠的不會
	w = _new_world()
	p = _player(w)
	var ig: Dictionary = ItemDefs.PROCS.ignite
	_put(p, _bag(p, &"hit", &"left"), &"eternal_flame")
	a = _item_dummy(w, Vector2(0, 5))
	b = _item_dummy(w, Vector2(a.radius * 2.0 + ig.spread_range * 0.5, 5))
	var c := _item_dummy(w, Vector2(-8, 5))
	Combat.apply_damage(w, p, a, {"damage": 20.0, "attack": &"primary"})
	if a.burn_timer <= 0.0 or not a.burn_spread:
		return "永恆之焰：命中應點燃（會擴散）"
	_run(w, idle, ceili(ig.spread_interval / DT) + 2)
	if b.burn_timer <= 0.0 or c.burn_timer > 0.0:
		return "燃燒 %.1f 秒後應傳給旁邊的怪、不傳給遠的：旁邊 %.2f、遠的 %.2f" % [ig.spread_interval, b.burn_timer, c.burn_timer]
	return ""


static func _item_projectiles(w: World) -> Array[Projectile]:
	var out: Array[Projectile] = []
	for e in w.projectiles:
		if not e.is_removed and (e as Projectile).proc:
			out.append(e as Projectile)
	return out


# 出手袋（左邊）：普攻追加飛刀 / 斬波（效果自己的內部冷卻）；計時袋：每隔幾秒落雷；翻滾袋：減速周圍的怪
static func check_item_procs_attack_timed() -> String:
	var w := _new_world()
	var p := _player(w)
	var idle := _cmd(Vector2.ZERO)
	# 袖中飛刀（左邊的出手袋）：普攻出手射 1 把（proc、武器基礎傷害 × damage_pct）；內部冷卻內再出手不射
	var kn: Dictionary = ItemDefs.PROCS.throw_knife
	_put(p, _bag(p, &"cast", &"left"), &"sleeve_knife")
	p.aim_point = p.pos + Vector2(0, 5)
	for i in 300:
		ItemEffects.on_attack(w, p, &"primary")
		if not _item_projectiles(w).is_empty():
			break
	var knives := _item_projectiles(w)
	if knives.size() != 1 or absf(knives[0].damage - p.pct_damage(kn.damage_pct)) > EPS or knives[0].pierce:
		return "普攻出手應射 1 把飛刀（傷害 %.2f）：%d 把 %s" % [p.pct_damage(kn.damage_pct), knives.size(), knives.map(func(k: Projectile) -> float: return k.damage)]
	ItemEffects.on_attack(w, p, &"primary")
	if _item_projectiles(w).size() != 1:
		return "飛刀內部冷卻 %.1f 秒內不該再射" % kn.icd
	p.clear_items()
	w.clear()
	# 裂空之刃：左右對稱 count 道穿透斬波，各 damage_ratio
	w = _new_world()
	p = _player(w)
	var rb := _effect(&"rift_blade")
	_put(p, _bag(p, &"cast", &"left"), &"rift_blade")
	p.aim_point = p.pos + Vector2(0, 5)
	ItemEffects.on_attack(w, p, &"primary")
	var waves := _item_projectiles(w)
	if waves.size() != rb.count:
		return "裂空之刃應射出 %d 道斬波，實際 %d" % [rb.count, waves.size()]
	var sw: Dictionary = ItemDefs.PROCS.slash_wave
	for wv in waves:
		var off := absf(MathUtil.wrap_angle(wv.facing - 0.0))
		if not wv.pierce or absf(wv.damage - p.pct_damage(rb.damage_ratio)) > EPS or absf(off - sw.spread) > 0.01:
			return "斬波應穿透、傷害 %.2f、偏 ±%.2f：穿透 %s、%.2f、偏 %.2f" % [p.pct_damage(rb.damage_ratio), sw.spread, wv.pierce, wv.damage, off]
	w.clear()
	# 雷霆鈴（計時袋）：每 period 秒（計時袋的間隔）打 range 內最近的 targets 隻，再遠的、第 targets + 1 近的不打
	w = _new_world()
	p = _player(w)
	var bell := {"period": BagDefs.BAGS.timer.period}
	var ls: Dictionary = ItemDefs.PROCS.lightning_strike
	_put(p, _bag(p, &"timer", &"bottom"), &"thunder_bell")
	var foes: Array[Enemy] = []
	for i in ls.targets + 1:
		foes.append(_item_dummy(w, Vector2(0, 2.0 + i)))
	var far := _item_dummy(w, Vector2(0, ls.range + 4.0))
	for e in foes:
		e.dormant = true   # 不要走過來
	far.dormant = true
	_run(w, idle, roundi(bell.period / DT) - 5)
	if foes.any(func(e: Enemy) -> bool: return e.hp < e.max_hp):
		return "雷霆鈴 %.0f 秒前不該打" % bell.period
	_run(w, idle, 10)
	var struck := foes.map(func(e: Enemy) -> bool: return e.hp < e.max_hp)
	var want_struck := []
	for i in foes.size():
		want_struck.append(i < ls.targets)
	if struck != want_struck or far.hp < far.max_hp:
		return "雷霆鈴應打最近的 %d 隻：%s、遠的 %s" % [ls.targets, struck, far.hp < far.max_hp]
	w.clear()
	# 停滯懷錶：翻滾時 radius 內的怪移速 × (1 − slow)、duration 秒後恢復；範圍外的不變
	w = _new_world()
	p = _player(w)
	var watch := _effect(&"stasis_watch")
	var st: Dictionary = ItemDefs.PROCS.slow_time
	_put(p, _bag(p, &"roll", &"bottom"), &"stasis_watch")
	var near := _item_dummy(w, Vector2(0, st.radius * 0.5))
	var away := _item_dummy(w, Vector2(0, -(st.radius + 4.0)))
	var spd_near := near.speed
	var spd_away := away.speed
	_run(w, _cmd(Vector2(1, 0), Vector2(0, 5), InputCmd.BTN_ROLL), 1)
	if absf(near.speed - spd_near * (1.0 - watch.slow)) > EPS or absf(away.speed - spd_away) > EPS:
		return "停滯懷錶：近的移速應 %.2f、遠的 %.2f：%.2f / %.2f" % [spd_near * (1.0 - watch.slow), spd_away, near.speed, away.speed]
	_run(w, idle, roundi(watch.duration / DT) + 2)
	if absf(near.speed - spd_near) > EPS:
		return "停滯懷錶 %.0f 秒後移速應恢復：%.2f / %.2f" % [watch.duration, near.speed, spd_near]
	return ""


# 打 p 一下致命傷（先清掉受傷無敵）
static func _lethal_hit(w: World, foe: Entity, p: Player) -> void:
	p.invuln_timer = 0.0
	Combat.apply_damage(w, foe, p, {"damage": p.max_hp * 10.0})


# 觸發（第二批）：致命傷 / 死亡時——守護亡靈（每層一次、先用）、復活十字（用完碎掉）都在倒地 / 死亡之前攔下
static func check_item_procs_lethal() -> String:
	var w := _new_world()
	var p := _player(w)
	var foe := _item_dummy(w, Vector2(0, 3))
	foe.dormant = true
	var guard := _effect(&"guardian_spirit")
	var rev: Dictionary = ItemDefs.PROCS.revive
	p.add_item(&"guardian_spirit")
	var cross_uid := p.add_item(&"resurrection_cross")
	# 第一次：守護亡靈先用，留 1 血、無敵 invuln 秒，十字還在
	_lethal_hit(w, foe, p)
	if p.is_dead or p.is_downed or absf(p.hp - 1.0) > EPS or absf(p.invuln_timer - guard.invuln) > EPS or p.loadout.find_item(cross_uid).is_empty():
		return "守護亡靈應先用：死 %s、生命 %.1f、無敵 %.2f、十字還在 %s" % [p.is_dead, p.hp, p.invuln_timer, not p.loadout.find_item(cross_uid).is_empty()]
	# 第二次（同一層）：換復活十字，回 hp_ratio、十字碎掉空出格子
	_lethal_hit(w, foe, p)
	var want := roundf(p.max_hp * rev.hp_ratio)
	if p.is_dead or absf(p.hp - want) > EPS or not p.loadout.find_item(cross_uid).is_empty() or p.items.any(func(it: Dictionary) -> bool: return it.uid == cross_uid):
		return "同一層第二次應用復活十字並碎掉：死 %s、生命 %.1f（應 %.0f）" % [p.is_dead, p.hp, want]
	# 第三次：都用完了，單機就死
	_lethal_hit(w, foe, p)
	if not p.is_dead:
		return "守護亡靈本層用過、十字碎了，應該死亡"
	w.clear()
	# 換層後守護亡靈又能用一次
	w = _new_world()
	p = _player(w)
	foe = _item_dummy(w, Vector2(0, 3))
	foe.dormant = true
	p.add_item(&"guardian_spirit")
	_lethal_hit(w, foe, p)
	p.arrive_floor(p.pos, p.height)
	_lethal_hit(w, foe, p)
	if p.is_dead or absf(p.hp - 1.0) > EPS:
		return "換層後守護亡靈應再救一次：死 %s、生命 %.1f" % [p.is_dead, p.hp]
	w.clear()
	# 多人：攔在倒地之前（不會倒地）
	w = World.new(&"test_arena")
	w.spawn_packs = false
	w.reset(12345, [World.HOST_PEER_ID, 2])
	w.spawner.finished = true
	p = _player(w)
	foe = _item_dummy(w, Vector2(0, 3))
	foe.dormant = true
	p.add_item(&"guardian_spirit")
	_lethal_hit(w, foe, p)
	if p.is_downed or p.is_dead:
		return "多人時守護亡靈應在倒地之前救下：倒地 %s" % p.is_downed
	_lethal_hit(w, foe, p)
	if not p.is_downed:
		return "多人時用完守護亡靈應照常倒地"
	w.clear()
	return ""


# 擊殺袋（左邊）：普攻打死放追蹤鬼火、召喚玩家方的骷髏僕從
static func check_item_procs_summon() -> String:
	var w := _new_world()
	var p := _player(w)
	var idle := _cmd(Vector2.ZERO)
	# 鬼火燈籠：擊殺時從屍體飛出 1 顆（擊殺那一下 × damage_ratio），會轉彎打到旁邊的怪；同時最多 max 顆
	var wp: Dictionary = ItemDefs.PROCS.wisp
	_put(p, _bag(p, &"kill", &"left"), &"wisp_lantern")
	var b := _item_dummy(w, Vector2(4, 6))
	b.dormant = true
	Combat.apply_damage(w, p, _item_dummy(w, Vector2(0, 6), 1.0), {"damage": 20.0, "attack": &"primary"})
	var wisps := _item_projectiles(w).filter(func(x: Projectile) -> bool: return x.homing > 0.0)
	if wisps.size() != 1 or absf(wisps[0].damage - 20.0 * wp.damage_ratio) > EPS:
		return "擊殺應放出 1 顆鬼火（傷害 %.1f）：%s" % [20.0 * wp.damage_ratio, wisps.map(func(x: Projectile) -> float: return x.damage)]
	_run(w, idle, roundi(wp.life / DT))
	if b.hp >= b.max_hp:
		return "鬼火應追到旁邊的怪"
	for i in wp.max + 4:
		Combat.apply_damage(w, p, _item_dummy(w, Vector2(-8, -8), 1.0), {"damage": 20.0, "attack": &"primary"})
	var alive := _item_projectiles(w).filter(func(x: Projectile) -> bool: return x.homing > 0.0).size()
	if alive != wp.max:
		return "鬼火同時最多 %d 顆，實際 %d" % [wp.max, alive]
	w.clear()
	# 亡者大軍：普攻打死召喚 1 隻玩家方的僕從；玩家打不到它、它打不到玩家、怪打得到它；會去打怪；最多 max 隻；life 秒後倒下、不給靈魂
	w = _new_world()
	p = _player(w)
	var army := _effect(&"army_of_dead")
	var md: Dictionary = EnemyDefs.ENEMIES.minion
	_put(p, _bag(p, &"kill", &"left"), &"army_of_dead")
	Combat.apply_damage(w, p, _item_dummy(w, Vector2(0, 3), 1.0), {"damage": 20.0, "attack": &"primary"})
	if w.allies.size() != 1 or not w.allies[0] is Minion or w.allies[0].team != &"player":
		return "擊殺應召喚 1 隻玩家方的骷髏僕從：%d" % w.allies.size()
	var m := w.allies[0] as Minion
	if Combat.hostiles_of(w, &"player", p.id).has(m) or Combat.hostiles_of(w, m.team, m.id).has(p) or not Combat.hostiles_of(w, &"enemy").has(m):
		return "僕從的敵我判斷不對：玩家打得到 %s、它打得到玩家 %s、怪打得到 %s" % [
			Combat.hostiles_of(w, &"player", p.id).has(m), Combat.hostiles_of(w, m.team, m.id).has(p), Combat.hostiles_of(w, &"enemy").has(m)]
	# 一般怪會把比較近的僕從當目標；Boss 只追玩家
	var lure := _item_dummy(w, m.pos + Vector2(1.5, 0))
	var boss := _spawn(w, &"boss", m.pos + Vector2(-1.5, 0))
	if lure.nearest_target() != m or boss.nearest_target() != p:
		return "一般怪應追比較近的僕從、Boss 只追玩家：%s / %s" % [lure.nearest_target() == m, boss.nearest_target() == p]
	lure.remove()
	boss.remove()
	_run(w, idle, 1)
	var foe := _item_dummy(w, Vector2(6, 3))
	foe.dormant = false
	foe.fsm.change(&"chase")
	_run(w, idle, roundi(5.0 / DT))
	if foe.hp >= foe.max_hp:
		return "僕從 5 秒內應去打旁邊的怪（離 %.1f）" % m.pos.distance_to(foe.pos)
	for i in army.max + 3:
		Combat.apply_damage(w, p, _item_dummy(w, Vector2(-6, -6), 1.0), {"damage": 20.0, "attack": &"primary"})
	var minions := w.allies.filter(func(e: Entity) -> bool: return not e.is_dead).size()
	if minions != army.max:
		return "僕從同時最多 %d 隻，實際 %d" % [army.max, minions]
	# 快照鏡像：客戶端建出來的也是玩家方
	var mirror := World.new(&"test_arena")
	var copy := NetCodec.create_entity(mirror, NetCodec.entity_fields(m))
	if copy.team != &"player" or not mirror.allies.has(copy):
		return "客戶端的僕從鏡像應是玩家方：%s" % copy.team
	mirror.clear()
	var souls := w.souls
	var kills: int = w.stats.kills
	_run(w, idle, roundi(md.life / DT) + 10)
	if w.allies.any(func(e: Entity) -> bool: return not e.is_dead and not e.is_removed):
		return "僕從 %.0f 秒後應倒下" % md.life
	if w.souls != souls or w.stats.kills != kills:
		return "僕從倒下不該給靈魂、不算擊殺：靈魂 %d → %d、擊殺 %d → %d" % [souls, w.souls, kills, w.stats.kills]
	# 碎骨爆裂：倒下時半徑內的怪受 burst.damage；玩家不會被炸
	var bu: Dictionary = md.burst
	var m2 := Minion.new(w, Vector2(10, 10), p)
	w.add_enemy(m2)
	var near := _item_dummy(w, Vector2(10 + bu.radius * 0.5, 10))
	near.dormant = true
	p.pos = Vector2(10, 10 - bu.radius * 0.5)
	var hp_near := near.hp
	var hp_p := p.hp
	m2.die(0)
	if _hp_loss(near, hp_near) != _dealt(near, bu.damage) or p.hp < hp_p:
		return "碎骨爆裂：旁邊的怪應扣 %d、玩家不扣：%d、玩家 %.1f → %.1f" % [_dealt(near, bu.damage), _hp_loss(near, hp_near), hp_p, p.hp]
	return ""


# 能力（第二批）：自動回充的護盾（二段跳在 PlayerChecks.check_double_jump）
static func check_item_shield() -> String:
	# 骨製護盾：盾量 = 最大生命 × ratio、先扣盾；recharge_delay 秒沒受傷才補滿
	var w := _new_world()
	var p := _player(w)
	var idle := _cmd(Vector2.ZERO)
	var bs := _effect(&"bone_buckler")
	p.add_item(&"bone_buckler")
	_run(w, idle, 1)
	var cap: float = p.max_hp * bs.ratio
	if absf(p.shield - cap) > EPS:
		return "骨製護盾應有 %.1f，實際 %.1f" % [cap, p.shield]
	var foe := _item_dummy(w, Vector2(0, 3))
	foe.dormant = true   # 不要走過來打（會一直重設回充時間）
	var hp0 := p.hp
	Combat.apply_damage(w, foe, p, {"damage": 1.0})
	if absf(p.hp - hp0) > EPS or p.shield >= cap - EPS:
		return "小傷害應全部扣在盾上：生命 %.1f → %.1f、盾 %.1f" % [hp0, p.hp, p.shield]
	_run(w, idle, roundi(bs.recharge_delay / DT) - 10)
	if p.shield >= cap - EPS:
		return "%.0f 秒內不該回充：盾 %.1f" % [bs.recharge_delay, p.shield]
	_run(w, idle, 20)
	if absf(p.shield - cap) > EPS:
		return "%.0f 秒沒受傷應補滿 %.1f：%.1f" % [bs.recharge_delay, cap, p.shield]
	return ""


static func check_item_drop_pool() -> String:
	# 道具第二批（G）做完後全部接上：之後新增的道具也要接好才進資料表（只有資料的不會掉，等於沒有）
	for id in ItemDefs.item_ids():
		if not ItemDefs.item_implemented(id):
			return "%s 還有效果沒接上" % id
	var order: Array = ItemDefs.RARITIES.keys()
	for r: StringName in ItemDefs.RARITIES:
		var pool := LootDefs.drop_pool(r)
		if pool.is_empty():
			return "%s 沒有可以掉的道具" % r
		for id in pool:
			if not ItemDefs.item_implemented(id):
				return "%s 的掉落裡有還沒實作的 %s" % [r, id]
		# 這個稀有度有實作好的道具就全部都在掉落裡；一個都沒有就往下一級找
		var done := LootDefs.items_of(r).filter(func(id: StringName) -> bool:
			return ItemDefs.item_implemented(id))
		if not done.is_empty():
			if pool != done:
				return "%s 的掉落應為實作好的 %s（沒有羈絆的也掉），實際 %s" % [r, done, pool]
		elif order.find(ItemDefs.ITEMS[pool[0]].rarity) >= order.find(r):
			return "%s 都還沒實作，應改掉較低的稀有度，實際掉 %s" % [r, ItemDefs.ITEMS[pool[0]].rarity]
	return ""


static func check_weapon_pickup() -> String:
	var w := _new_world()
	var p := _player(w)
	var mk := func(uid: String, base: StringName) -> Dictionary:
		return {"uid": StringName(uid), "base": base, "rarity": &"white", "affixes": [] as Array[StringName]}
	var op := func(ops: Array) -> void:
		var c := _cmd(Vector2.ZERO)
		c.inv_ops = ops
		_run(w, c, 1)
	var sword: StringName = p.weapon_slots[Loadout.MAIN].uid
	var shield: StringName = p.weapon_slots[Loadout.OFF].uid
	if p.weapon_id != &"longsword+woodShield" or p.weapon.special.behavior != &"shieldBlock" or p.weapon.attack.name != WeaponDefs.WEAPONS.longsword.attack.name:
		return "開局應是長劍＋木盾：左鍵斬擊、右鍵格擋，實際 %s" % p.weapon_id
	# 地上的武器按 F 撿起：手上有武器時放背包、不換手上的
	w.drop_weapon(mk.call("a", &"staff"), p.pos + Vector2(1, 0))
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_INTERACT), 1)
	if p.inventory.find(&"a").is_empty() or p.weapon_id != &"longsword+woodShield":
		return "撿起的法杖應放背包、不換手上：%s" % p.weapon_id
	# 副手空著時撿到盾：直接拿上副手
	op.call([[InputCmd.OP_MOVE, String(shield), 5, 0, 0]])
	if not p.weapon_slots[Loadout.OFF].is_empty() or p.weapon_id != &"longsword" or p.weapon.special.behavior != &"chargedThrust":
		return "副手的盾搬進背包後應只拿長劍、右鍵蓄力突刺：%s" % p.weapon_id
	p.add_weapon(mk.call("sh", &"woodShield"))
	if p.weapon_slots[Loadout.OFF].get("uid", &"") != &"sh":
		return "副手空著時撿到的盾應放副手"
	# 背包塞滿 → 撿不起來
	for i in ItemDefs.BAG_SIZE.x * ItemDefs.BAG_SIZE.y:
		p.loadout.add_item(p, &"loaded_dice", {}, 0, Loadout.BAG)
	w.events.clear()
	if p.add_weapon(mk.call("c", &"staff")) or _named(w.events, "inventory:full").is_empty():
		return "背包滿了應撿不起來並發出 inventory:full"
	p.clear_items()
	# 雙手武器裝上主手：原本的長劍和副手的盾都回背包
	op.call([[InputCmd.OP_EQUIP, "a", Loadout.MAIN]])
	if p.weapon_slots[Loadout.MAIN].get("uid", &"") != &"a" or not p.weapon_slots[Loadout.OFF].is_empty() 			or p.inventory.find(sword).is_empty() or p.inventory.find(&"sh").is_empty() or p.weapon_id != &"staff":
		return "法杖（雙手）裝上主手後長劍與盾應回背包：手上 %s、副手 %s" % [p.weapon_id, p.weapon_slots[Loadout.OFF]]
	# 盾不能放主手；主手是雙手武器時不能拿副手
	op.call([[InputCmd.OP_EQUIP, "sh", Loadout.MAIN], [InputCmd.OP_EQUIP, "sh", Loadout.OFF]])
	if p.weapon_slots[Loadout.MAIN].get("uid", &"") != &"a" or not p.weapon_slots[Loadout.OFF].is_empty():
		return "盾不能放主手、拿雙手武器時不能放副手"
	# 主手不能搬進背包、不能丟
	op.call([[InputCmd.OP_MOVE, "a", 4, 5, 0], [InputCmd.OP_DROP, "a"]])
	if p.weapon_slots[Loadout.MAIN].get("uid", &"") != &"a":
		return "主手的武器不能搬走或丟掉"
	# 換回長劍、盾放副手 → 長劍＋木盾
	op.call([[InputCmd.OP_EQUIP, String(sword), Loadout.MAIN], [InputCmd.OP_EQUIP, "sh", Loadout.OFF]])
	if p.weapon_id != &"longsword+woodShield" or p.inventory.find(&"a").is_empty():
		return "長劍裝回主手、盾放副手後應是長劍＋木盾、法杖回背包：%s" % p.weapon_id
	# 主手與副手互換：盾不能當主手，互換被拒絕
	op.call([[InputCmd.OP_EQUIP, "sh", Loadout.MAIN]])
	if p.weapon_id != &"longsword+woodShield":
		return "盾拖到主手應被拒絕：%s" % p.weapon_id
	# 主袋的道具不跟著武器：主袋的磨刀石生效；換上倉庫的法杖後照樣在主袋、照樣生效；武器快照沒有鑲的東西
	var stone := p.loadout.add_item(p, &"whetstone", {}, 0, Loadout.CORE)
	var dmg := p.stats.value(&"damage")
	if stone == &"" or p.loadout.find_item(stone).get("where", -9) != Loadout.CORE or dmg <= 1.0:
		return "磨刀石應在主袋並生效：攻擊力 %.2f" % dmg
	op.call([[InputCmd.OP_EQUIP, "a", Loadout.MAIN]])
	if p.weapon_id != &"staff" or p.loadout.find_item(stone).get("where", -9) != Loadout.CORE or absf(p.stats.value(&"damage") - dmg) > EPS:
		return "換上法杖後磨刀石應還在主袋、照樣生效：%s、%s、攻擊力 %.2f" % [p.weapon_id, p.loadout.find_item(stone), p.stats.value(&"damage")]
	var back := WeaponDropDefs.from_array(WeaponDropDefs.to_array(p.weapon_slots[Loadout.MAIN]))
	if back.has("sockets") or back.base != &"staff":
		return "武器快照來回應只有種類與稀有度：%s" % [back]
	return ""


static func check_weapon_merge() -> String:
	var w := _new_world()
	var p := _player(w)
	var mk := func(uid: String, base: StringName, rarity: StringName) -> Dictionary:
		return {"uid": StringName(uid), "base": base, "rarity": rarity, "affixes": [] as Array[StringName]}
	var start_uid: StringName = p.weapon_slots[0].uid
	p.add_weapon(mk.call("s2", &"longsword", &"white"))   # 背包（手上有武器時都放背包）
	p.add_weapon(mk.call("s3", &"longsword", &"white"))   # 背包
	p.add_weapon(mk.call("st", &"staff", &"white"))       # 背包
	p.add_weapon(mk.call("g1", &"longsword", &"green"))   # 背包
	var merge := func(a: String, b: String, keep_a := "", keep_b := "") -> void:
		var c := _cmd(Vector2.ZERO)
		c.inv_ops = [[InputCmd.OP_MERGE, a, b, keep_a, keep_b]]
		w.events.clear()
		_run(w, c, 1)
	# 不在鍛造祭壇旁不能合成（Build 改版第 8 步），拒絕的原因是 forge
	merge.call("s3", String(start_uid))
	var denied := _named(w.events, "weapon:merge_denied")
	if denied.is_empty() or denied[0].get("reason", "") != "forge" or p.inventory.find(&"s3").is_empty():
		return "不在鍛造祭壇旁應不能合成（reason = forge）：%s" % [denied]
	var forge := _forge_near(w, p)
	# 倉庫的白長劍拖到主手的白長劍 → 綠色（沒有詞條）、留在主手、立刻生效
	merge.call("s3", String(start_uid))
	var m: Dictionary = p.weapon_slots[0]
	if m.rarity != &"green" or not m.affixes.is_empty() or not p.inventory.find(&"s3").is_empty() or _named(w.events, "weapon:merged").is_empty():
		return "合成應得到綠色、沒有詞條、在主手：%s" % [m]
	if absf(p.stats.value(&"damage") - WeaponDropDefs.RARITY_BASE.green.damage) > EPS:
		return "合成後手上綠長劍的攻擊力倍率應立刻生效：%.2f" % p.stats.value(&"damage")
	# 不同種、不同稀有度不能合成
	merge.call("st", "s2")
	if _named(w.events, "weapon:merge_denied").is_empty() or p.inventory.find(&"st").is_empty():
		return "法杖拖到長劍上不應合成"
	merge.call("s2", "g1")
	if _named(w.events, "weapon:merge_denied").is_empty() or p.inventory.find(&"s2").is_empty():
		return "白色拖到綠色上不應合成"
	# 主手的綠長劍拖到倉庫的綠長劍 → 藍色留在主手（主手不能沒有武器），倉庫那把消失
	merge.call(String(start_uid), "g1")
	var g: Dictionary = p.weapon_slots[Loadout.MAIN]
	if g.get("rarity", &"") != &"blue" or not p.inventory.find(&"g1").is_empty() or p.weapon_id != &"longsword+woodShield":
		return "主手的綠 + 倉庫的綠應在主手得到藍色：%s" % [g]
	# 走遠就不能合成
	forge.pos += Vector2(LootDefs.FORGE.range + 5.0, 0.0)
	if w.near_forge(p):
		return "離鍛造祭壇 %.1f 以外不應算在旁邊" % LootDefs.FORGE.range
	# 雙持的兩把匕首合成 → 結果在主手、副手空出來
	var wd := _new_world()
	var pd := _player(wd)
	pd.equip_weapon(&"dagger")
	pd.loadout.equip_offhand_new(pd, &"dagger")
	_forge_near(wd, pd)
	var c2 := _cmd(Vector2.ZERO)
	c2.inv_ops = [[InputCmd.OP_MERGE, String(pd.weapon_slots[Loadout.OFF].uid), String(pd.weapon_slots[Loadout.MAIN].uid)]]
	_run(wd, c2, 1)
	if pd.weapon_slots[Loadout.MAIN].get("rarity", &"") != &"green" or not pd.weapon_slots[Loadout.OFF].is_empty() or pd.weapon_id != &"dagger":
		return "主副手兩把白匕首合成應在主手得到綠匕首、副手空：%s %s" % [pd.weapon_id, pd.weapon_slots]
	# 橘色不能再合成
	var o1: Dictionary = mk.call("o1", &"staff", &"orange")
	var o2: Dictionary = mk.call("o2", &"staff", &"orange")
	if WeaponDropDefs.can_merge(o1, o2):
		return "橘色不能再合成"
	return ""


# 羈絆：道具標的羈絆都存在、掉落池只有屬於羈絆的（修飾、魔力道具例外）；格數 = 最大同色區塊（主袋與袋子一起、跨袋子也連、
# 斜的不算、倉庫裡的不算、同一種拿兩個照格數算、跨羈絆的道具兩種都算）；拿掉就扣；階數照門檻
static func check_bonds() -> String:
	for id: StringName in ItemDefs.ITEMS:
		for bond: StringName in ItemDefs.ITEMS[id].get("bonds", []):
			if not BondDefs.BONDS.has(bond):
				return "%s 的羈絆不存在：%s" % [id, bond]
	for bond: StringName in BondDefs.BONDS:
		var th: Array = BondDefs.BONDS[bond].thresholds
		if BondDefs.BONDS[bond].tiers.size() != th.size():
			return "%s 的階數和門檻數不一樣" % bond
		if BondDefs.tier(bond, th[0] - 1) != 0 or BondDefs.tier(bond, th[0]) != 1 or BondDefs.tier(bond, th[-1]) != th.size() \
				or BondDefs.next_threshold(bond, th[-1]) != -1:
			return "%s 的階數計算不對" % bond
	var w := _new_world()
	var p := _player(w)
	var lo := p.loadout
	var put := func(id: StringName, cell: Vector2i) -> StringName: return lo.add_item(p, id, {"cell": cell, "rot": 0}, 0, Loadout.CORE)
	put.call(&"whetstone", Vector2i(0, 0))
	put.call(&"whetstone", Vector2i(1, 0))   # 同一種拿兩個照格數算
	var diag: StringName = put.call(&"loaded_dice", Vector2i(2, 1))   # 只碰到斜角：不連
	lo.add_item(p, &"loaded_dice", {}, 0, Loadout.BAG)   # 倉庫裡的不算
	if lo.bond_counts.get(&"phys", 0) != 2:
		return "兩顆磨刀石相連、斜角的骰子不連、倉庫不算：物理應 2 格，實際 %s" % lo.bond_counts
	lo.queue_ops([[InputCmd.OP_MOVE, String(diag), 2, 0, 0, Loadout.CORE]])
	lo.apply_ops(p)
	if lo.bond_counts.get(&"phys", 0) != 3:
		return "骰子搬到貼著的 (2, 0) 後物理應 3 格，實際 %s" % lo.bond_counts
	var heart: StringName = put.call(&"tomb_heart", Vector2i(4, 0))   # 防禦 + 火焰，2 × 2：沒貼著物理那塊
	if lo.bond_counts.get(&"guard", 0) != 4 or lo.bond_counts.get(&"fire", 0) != 4 or lo.bond_counts.get(&"phys", 0) != 3:
		return "王墓之心（防禦 + 火焰 4 格）兩種都算、不連到物理：%s" % lo.bond_counts
	if BondDefs.tier(&"guard", lo.bond_counts[&"guard"]) != 1:
		return "防禦 4 格應啟動第 1 階"
	# 跨袋子：上方按鍵袋貼著主袋 (0, 0)、(1, 0) 的那兩格放冰霜效果，主袋下面放霜晶 → 冰霜只算相連的那塊
	var key: Dictionary = lo.key_bags()[0]
	lo.add_item(p, &"ice_coffin_nail", {"cell": Vector2i(0, 0), "rot": 0}, 0, lo.bags.find(key))
	put.call(&"frost_crystal", Vector2i(0, 1))
	if lo.bond_counts.get(&"cold", 0) != 2:
		return "冰棺釘（2 格）在按鍵袋、霜晶在主袋 (0, 1) 中間隔著磨刀石：冰霜最大一塊應 2 格，實際 %s" % lo.bond_counts
	lo.remove_item(p, heart)
	if lo.bond_counts.get(&"guard", 0) != 0 or lo.bond_counts.get(&"fire", 0) != 0:
		return "拿掉王墓之心後防禦、火焰應歸零：%s" % lo.bond_counts
	var w2 := _new_world()
	var p2 := _player(w2)
	p2.loadout.add_item(p2, &"frost_crystal", {"cell": Vector2i(0, 0), "rot": 0}, 0, Loadout.CORE)
	p2.loadout.add_item(p2, &"ice_coffin_nail", {"cell": Vector2i(0, 0), "rot": 0}, 0, 0)   # 按鍵袋貼著主袋 (0, 0) 的那一格
	if p2.loadout.bond_counts.get(&"cold", 0) != 3:
		return "主袋 (0, 0) 的霜晶和上方按鍵袋貼著的冰棺釘（2 格）應連成 3 格，實際 %s" % p2.loadout.bond_counts
	return ""


# 觸發袋的擺放：接哪幾邊看種類、在邊長內、同一邊不重疊、按鍵袋最多 4 個；撿到的袋子自動接、接不下進倉庫；
# OP_BAG 換邊 / 滑動 / 拿下來放倉庫（內容跟著、拿下來就不生效）、接不下拒絕；袋子連同內容丟在地上、撿回來照原樣（詛咒袋還是詛咒袋）；詛咒袋接著時套缺點；快照來回一樣
static func check_bag_layout() -> String:
	var w := _new_world()
	var p := _player(w)
	var lo := p.loadout
	var hit := BagDefs.make(&"t1", &"hit")
	if lo.bag_fits(hit, &"top", 0) or lo.bag_fits(hit, &"bottom", 0) or not lo.bag_fits(hit, &"left", 0) or lo.bag_fits(hit, &"left", BagDefs.edge_length(&"left") - 1):
		return "命中袋只能接左右、不能超出邊長"
	var uid := lo.add_bag(p, &"hit")
	var b := lo.find_bag(uid)
	if b.get("side", &"") != &"left" or b.offset != 0:
		return "撿到的命中袋應自動接在左邊 0：%s" % [b]
	if lo.bag_fits(BagDefs.make(&"t2", &"kill"), &"left", 1):
		return "同一邊重疊的位置不能接"
	var rune := _put(p, b, &"thunder_rune")
	# 數值道具放袋子也生效（第 8 步 a）；自動擺放只放主袋
	var dmg_before := p.stats.value(&"damage")
	var stone := _put(p, b, &"whetstone")
	if stone == &"" or p.stats.value(&"damage") <= dmg_before:
		return "磨刀石放進接著的命中袋應生效：攻擊力 %s → %s" % [dmg_before, p.stats.value(&"damage")]
	if lo.auto_place(&"whetstone").get("where", -9) != Loadout.CORE:
		return "數值道具自動擺放應只放主袋：%s" % [lo.auto_place(&"whetstone")]
	var op := func(o: Array) -> void:
		lo.queue_ops([o])
		lo.apply_ops(p)
	op.call([InputCmd.OP_BAG, String(uid), "right", 1])
	if b.side != &"right" or b.offset != 1 or lo.find_item(rune).get("where", -9) != lo.bags.find(b):
		return "OP_BAG 應把命中袋換到右邊 1、裡面的東西跟著：%s、%s" % [b, lo.find_item(rune)]
	w.events.clear()
	op.call([InputCmd.OP_BAG, String(uid), "bottom", 0])
	if b.side != &"right" or _named(w.events, "inventory:denied").is_empty():
		return "命中袋不能接下方，應拒絕"
	op.call([InputCmd.OP_BAG, String(uid), "", 0, 0, 0, 0])
	var stored := p.inventory.find(uid)
	if stored.is_empty() or lo.bags.has(b) or not lo.find_item(rune).is_empty() and lo.find_item(rune).where != Loadout.BAG:
		return "拿下來應放進倉庫 (0, 0)、不再接著：倉庫 %s" % [stored]
	if not is_equal_approx(p.stats.value(&"damage"), dmg_before):
		return "袋子拿下來，裡面的磨刀石應失效：攻擊力 %s，應為 %s" % [p.stats.value(&"damage"), dmg_before]
	op.call([InputCmd.OP_BAG, String(uid), "left", 2])
	if b.side != &"left" or b.offset != 2 or not p.inventory.find(uid).is_empty():
		return "倉庫的袋子 OP_BAG 應接回左邊 2：%s" % [b]
	# 丟袋子：連同內容一起丟、裡面的數值失效；撿回來照原樣接上、再生效（uid 換新的）
	var dmg_on := p.stats.value(&"damage")
	op.call([InputCmd.OP_DROP, String(uid)])
	var ground: Array = w.pickups.filter(func(e: Entity) -> bool: return not (e as ItemPickup).bag.is_empty())
	if lo.bags.has(b) or ground.size() != 1 or (ground[0] as ItemPickup).bag.entries.size() != 2 or not is_equal_approx(p.stats.value(&"damage"), dmg_before):
		return "丟袋子：應離開背包、地上 1 個帶 2 件內容的袋子、磨刀石失效：接著 %s、地上 %d、攻擊力 %s（應為 %s）" % [lo.bags.has(b), ground.size(), p.stats.value(&"damage"), dmg_before]
	lo.take_pickup(p, ground[0])
	var back := lo.bags.filter(func(o: Dictionary) -> bool: return o.kind == &"hit")
	if back.size() != 1 or (back[0] as Dictionary).entries.size() != 2 or (back[0] as Dictionary).uid == uid or not is_equal_approx(p.stats.value(&"damage"), dmg_on):
		return "撿回丟掉的袋子應照原樣接上（內容 2 件、新 uid）、磨刀石再生效：%s、攻擊力 %s（應為 %s）" % [back, p.stats.value(&"damage"), dmg_on]
	for i in 3:
		lo.add_bag(p, &"key")
	if lo.key_bags().size() != BagDefs.BAGS.key.max:
		return "按鍵袋應接滿 %d 個，實際 %d" % [BagDefs.BAGS.key.max, lo.key_bags().size()]
	var extra := lo.add_bag(p, &"key")
	if p.inventory.find(extra).is_empty():
		return "第 %d 個按鍵袋應放進倉庫" % (BagDefs.BAGS.key.max + 1)
	var taken0 := p.stats.value(&"damage_taken")
	var cursed := lo.add_bag(p, &"timer", &"cursed")
	if lo.find_bag(cursed).get("side", &"") != &"bottom" or absf(p.stats.value(&"damage_taken") - taken0 * 1.2) > EPS:
		return "詛咒計時袋接著時受到傷害應 ×1.2：%.2f" % p.stats.value(&"damage_taken")
	op.call([InputCmd.OP_BAG, String(cursed), "", 0])
	if absf(p.stats.value(&"damage_taken") - taken0) > EPS:
		return "詛咒袋拿下來後缺點應移除：%.2f" % p.stats.value(&"damage_taken")
	# 詛咒袋丟掉再撿回來還是詛咒袋（大小不會變回小袋）
	op.call([InputCmd.OP_DROP, String(cursed)])
	var cursed_ground: Array = w.pickups.filter(func(e: Entity) -> bool: return (e as ItemPickup).bag.get("tier", &"") == &"cursed")
	if cursed_ground.size() != 1 or not p.inventory.find(cursed).is_empty() or (cursed_ground[0] as ItemPickup).display_name() != "詛咒計時袋":
		return "倉庫的詛咒袋應丟在地上、名稱「詛咒計時袋」：地上 %d" % cursed_ground.size()
	var cursed2 := lo.add_bag(p, &"timer", &"small", {}, 0, (cursed_ground[0] as ItemPickup).bag)
	if lo.find_bag(cursed2).get("tier", &"") != &"cursed" or lo.find_bag(cursed2).get("length", 0) != BagDefs.TIERS.cursed.length:
		return "撿回的詛咒袋應保留大小：%s" % [lo.find_bag(cursed2)]
	op.call([InputCmd.OP_BAG, String(cursed2), "", 0])
	var arr := lo.bags_to_array()
	var copy := Loadout.new()
	copy.sync_inventory(p, arr)
	if copy.bags_to_array() != arr:
		return "倉庫、主袋、袋子的快照來回應一樣"
	lo.sync_inventory(p, arr)
	return ""


# 觸發袋的發動：左邊只被普攻觸發、右邊只被右鍵；效果各自耗魔（強度 × EFFECT_MANA_PER_POWER），不夠的跳過、由左到右先放；
# 按鍵袋按數字鍵一起放；觸發袋裡的技能自動放；袋子放出來的傷害不再觸發袋子；計時袋照間隔；強化袋的倍率
# 觸發袋的技能放在哪：有目標（命中、擊殺、受傷）在目標身上，沒有目標的照舊（計時袋從自己身上、隕石落在準星）
static func check_bag_skill_target() -> String:
	var fx_at := func(w: World, name: String, at: Vector2) -> bool:
		return _named(w.events, name).any(func(ev: Dictionary) -> bool: return (ev.pos as Vector2).distance_to(at) < 0.01)
	var setup := func(item: StringName, kind: StringName, side: StringName) -> Array:
		var w := _new_world()
		var p := _player(w)
		p.mana = p.max_mana()
		_put(p, _bag(p, kind, side), item)
		return [w, p]
	# 範圍：冰霜新星以目標為中心，目標旁邊的怪中、自己旁邊的怪不中
	var nova: Array = setup.call(&"frost_nova", &"hit", &"right")
	var w1: World = nova[0]
	var p1: Player = nova[1]
	var far := _item_dummy(w1, p1.pos + Vector2(0, 8), 100000.0)
	var by_target := _item_dummy(w1, far.pos + Vector2(1.5, 0), 100000.0)
	var by_self := _item_dummy(w1, p1.pos + Vector2(-1.5, 0), 100000.0)
	var hp_t := by_target.hp
	var hp_s := by_self.hp
	w1.events.clear()
	Combat.apply_damage(w1, p1, far, {"damage": 1.0, "attack": &"secondary"})
	if not fx_at.call(w1, "fx:explosion", far.pos) or by_target.hp >= hp_t or by_self.hp < hp_s:
		return "右鍵打中時冰霜新星應在目標身上爆：爆炸在目標 %s、目標旁扣 %.1f、自己旁扣 %.1f" % [fx_at.call(w1, "fx:explosion", far.pos), hp_t - by_target.hp, hp_s - by_self.hp]
	# 落點：隕石落在目標身上，不看準星
	var met: Array = setup.call(&"meteor", &"hit", &"right")
	var w2: World = met[0]
	var p2: Player = met[1]
	p2.aim_point = p2.pos + Vector2(-6, 0)
	var t2 := _item_dummy(w2, p2.pos + Vector2(0, 8), 100000.0)
	w2.events.clear()
	Combat.apply_damage(w2, p2, t2, {"damage": 1.0, "attack": &"secondary"})
	if not fx_at.call(w2, "fx:telegraph", t2.pos):
		return "命中袋的隕石應落在目標身上（準星在別處）：%s" % [_named(w2.events, "fx:telegraph")]
	# 連鎖：第一跳就是目標，準星附近沒有怪也放得出來
	var ch: Array = setup.call(&"chain_bolt", &"hit", &"right")
	var w3: World = ch[0]
	var p3: Player = ch[1]
	p3.aim_point = p3.pos + Vector2(-20, 0)
	var t3 := _item_dummy(w3, p3.pos + Vector2(0, 9), 100000.0)
	var hp3 := t3.hp
	Combat.apply_damage(w3, p3, t3, {"damage": 1.0, "attack": &"secondary"})
	if hp3 - t3.hp <= 1.0 + EPS:
		return "命中袋的閃電鏈應打到目標：只扣 %.1f" % (hp3 - t3.hp)
	# 投射物：從命中點沿原方向射出，先打目標，穿透的再打後面的怪
	var sh: Array = setup.call(&"sword_wave", &"hit", &"right")
	var w4: World = sh[0]
	var p4: Player = sh[1]
	var t4 := _item_dummy(w4, p4.pos + Vector2(0, 8), 100000.0)
	Combat.apply_damage(w4, p4, t4, {"damage": 1.0, "attack": &"secondary"})
	var shots: Array = w4.projectiles.filter(func(x: Projectile) -> bool: return x.attack == &"skill")
	if shots.size() != 1 or shots[0].pos.distance_to(t4.pos) > 0.01 or shots[0].direction.distance_to(Vector2(0, 1)) > 0.01:
		return "命中袋的投射物應從命中點沿原方向射出（離目標 %s、方向 %s）" % [shots[0].pos.distance_to(t4.pos) if not shots.is_empty() else -1.0, shots[0].direction if not shots.is_empty() else Vector2.ZERO]
	var behind := _item_dummy(w4, t4.pos + Vector2(0, 3), 100000.0)
	var hp_t4 := t4.hp
	var hp_b4 := behind.hp
	_run(w4, _cmd(Vector2.ZERO), 30)
	if _hp_loss(t4, hp_t4) <= 0 or _hp_loss(behind, hp_b4) <= 0:
		return "穿透的投射物應先打目標、再打後面的怪：目標扣 %d、後面扣 %d" % [_hp_loss(t4, hp_t4), _hp_loss(behind, hp_b4)]
	# 扇形：同時射出的只有中間那支打得到目標
	var fan: Array = setup.call(&"knife_fan", &"hit", &"right")
	var w_f: World = fan[0]
	var p_f: Player = fan[1]
	var t_f := _item_dummy(w_f, p_f.pos + Vector2(0, 8), 100000.0)
	Combat.apply_damage(w_f, p_f, t_f, {"damage": 1.0, "attack": &"secondary"})
	var hp_f := t_f.hp
	_run(w_f, _cmd(Vector2.ZERO), 30)
	var one_knife := _dealt(t_f, p_f.pct_damage(SkillDefs.SKILLS.knife_fan.damage_pct))
	if _hp_loss(t_f, hp_f) != one_knife:
		return "扇形技能只有中間那支打得到目標：應扣 %d（一支），實際 %d" % [one_knife, _hp_loss(t_f, hp_f)]
	# 位移：自己朝目標移動，不會瞬移到目標身上
	var da: Array = setup.call(&"charge_slash", &"hit", &"right")
	var w5: World = da[0]
	var p5: Player = da[1]
	p5.aim_point = p5.pos + Vector2(-6, 0)
	var t5 := _item_dummy(w5, p5.pos + Vector2(0, 12), 100000.0)
	var y0 := p5.pos.y
	var x0 := p5.pos.x
	Combat.apply_damage(w5, p5, t5, {"damage": 1.0, "attack": &"secondary"})
	_run(w5, _cmd(Vector2.ZERO), 20)
	if p5.pos.y - y0 < 1.0 or absf(p5.pos.x - x0) > 0.5:
		return "命中袋的衝鋒應朝目標移動（準星在別處）：位移 %s" % [p5.pos - Vector2(x0, y0)]
	# 擊殺袋：在怪死的位置放；受傷袋：在打你的怪身上放
	var ki: Array = setup.call(&"frost_nova", &"kill", &"right")
	var w6: World = ki[0]
	var p6: Player = ki[1]
	var t6 := _item_dummy(w6, p6.pos + Vector2(0, 8), 1.0)
	w6.events.clear()
	Combat.apply_damage(w6, p6, t6, {"damage": 100.0, "attack": &"secondary"})
	if not t6.is_dead or not fx_at.call(w6, "fx:explosion", t6.pos):
		return "擊殺袋的冰霜新星應在怪死的位置爆"
	var hu: Array = setup.call(&"frost_nova", &"hurt", &"bottom")
	var w7: World = hu[0]
	var p7: Player = hu[1]
	var t7 := _item_dummy(w7, p7.pos + Vector2(0, 6), 100000.0)
	w7.events.clear()
	ItemEffects.on_hurt(w7, p7, t7, 1.0, 1.0, false)
	if not fx_at.call(w7, "fx:explosion", t7.pos):
		return "受傷袋的冰霜新星應在打你的怪身上爆"
	# 祝福、召喚留在自己身上；計時袋沒有目標，新星在自己身上
	var bl: Array = setup.call(&"blessing", &"hit", &"right")
	var w8: World = bl[0]
	var p8: Player = bl[1]
	var t8 := _item_dummy(w8, p8.pos + Vector2(0, 8), 100000.0)
	w8.events.clear()
	Combat.apply_damage(w8, p8, t8, {"damage": 1.0, "attack": &"secondary"})
	if not fx_at.call(w8, "fx:heal", p8.pos):
		return "命中袋的祝福應留在自己身上：%s" % [_named(w8.events, "fx:heal")]
	var ti: Array = setup.call(&"frost_nova", &"timer", &"bottom")
	var w9: World = ti[0]
	var p9: Player = ti[1]
	var at_self := false
	for i in roundi(BagDefs.BAGS.timer.period / DT) + 2:
		w9.step({World.HOST_PEER_ID: _cmd(Vector2.ZERO)}, DT)
		at_self = at_self or fx_at.call(w9, "fx:explosion", p9.pos)
	if not at_self:
		return "計時袋沒有目標，冰霜新星應在自己身上爆"
	return ""


static func check_bag_triggers() -> String:
	var w := _new_world()
	var p := _player(w)
	p.set_stat_source(&"test", [[&"mana_regen", Stats.MUL, 0.0]])
	var left := _bag(p, &"hit", &"left")
	var right := _bag(p, &"hit", &"right")
	_put(p, left, &"ice_coffin_nail")   # 寒氣：目標疊冰冷
	var a := _item_dummy(w, Vector2(0, 3))
	Combat.apply_damage(w, p, a, {"damage": 5.0, "attack": &"secondary"})
	if a.chill_stacks > 0:
		return "右鍵打中不應發動左邊的命中袋"
	var mana0 := p.mana
	Combat.apply_damage(w, p, a, {"damage": 5.0, "attack": &"primary"})
	if a.chill_stacks <= 0 or absf(mana0 - p.mana - BagTriggers.effect_mana(&"ice_coffin_nail")) > EPS:
		return "普攻打中應發動左邊的命中袋並耗魔 %.1f：冰冷 %d、耗魔 %.2f" % [BagTriggers.effect_mana(&"ice_coffin_nail"), a.chill_stacks, mana0 - p.mana]
	# 魔力不夠：由左到右先放，放不起的跳過
	_put(p, right, &"venom_blade")
	_put(p, right, &"frost_heart")
	var b := _item_dummy(w, Vector2(0, -3))
	_run(w, _cmd(Vector2.ZERO), ceili(BagDefs.BAGS.hit.icd / DT) + 1)   # 上面右鍵打中時右邊的袋子開始了內部冷卻（空的也算）
	p.mana = BagTriggers.effect_mana(&"venom_blade") + 0.01
	Combat.apply_damage(w, p, b, {"damage": 5.0, "attack": &"secondary"})
	var first_left: bool = BagTriggers.contents(right)[0].id == &"venom_blade"
	if (b.poison_timer > 0.0) != first_left or (b.frozen_timer > 0.0) == first_left:
		return "魔力只夠一個時應放左邊那個（%s）：中毒 %.2f、冰凍 %.2f" % [BagTriggers.contents(right)[0].id, b.poison_timer, b.frozen_timer]
	p.mana = p.max_mana()
	# 不連鎖：袋子放出來的傷害（proc）、技能的傷害不觸發命中袋
	var c := _item_dummy(w, Vector2(3, 0))
	var chill0 := c.chill_stacks
	Combat.apply_damage(w, p, c, ItemEffects.proc_hit(5.0, c, Color.WHITE))
	Combat.apply_damage(w, p, c, {"damage": 5.0, "attack": &"skill"})
	if c.chill_stacks != chill0:
		return "道具效果、技能的傷害不應觸發命中袋"
	# 按鍵袋：數字鍵把裡面的效果與技能一起放
	var w2 := _new_world()
	var p2 := _player(w2)
	var key: Dictionary = p2.loadout.key_bags()[0]
	_put(p2, key, &"whirlwind")
	_put(p2, key, &"frost_bell")   # 寒氣：周圍疊冰冷
	var d := _item_dummy(w2, Vector2(0, 1.5), 100000.0)
	var hp0 := d.hp
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.slot_bit(0)), 1)
	if d.hp >= hp0 or d.chill_stacks <= 0:
		return "按 1 應同時放旋風斬與寒氣：扣血 %.1f、冰冷 %d" % [hp0 - d.hp, d.chill_stacks]
	# 觸發袋裡的技能：左邊的命中袋放旋風斬，普攻打中時自動放
	var w3 := _new_world()
	var p3 := _player(w3)
	_put(p3, _bag(p3, &"hit", &"left"), &"whirlwind")
	var e3 := _item_dummy(w3, Vector2(0, 1.5), 100000.0)
	var m3 := p3.mana
	Combat.apply_damage(w3, p3, e3, {"damage": 1.0, "attack": &"primary"})
	if absf(m3 - p3.mana - ActiveSlots.mana_cost(p3, ActiveSlots.slot_of(p3, p3.loadout.bags[1], p3.loadout.bags[1].entries[0]))) > EPS:
		return "命中袋裡的旋風斬應在普攻打中時自動放（扣魔）：%.1f → %.1f" % [m3, p3.mana]
	# 計時袋：間隔到了自己發動；強化袋（×1.5）裡的效果傷害跟著變
	var w4 := _new_world()
	var p4 := _player(w4)
	_put(p4, _bag(p4, &"timer", &"bottom", &"strong"), &"thunder_bell")
	var f := _item_dummy(w4, Vector2(0, 2))
	f.dormant = true
	var hp_f := f.hp
	_run(w4, _cmd(Vector2.ZERO), roundi(BagDefs.BAGS.timer.period / DT) + 2)
	var want := _dealt(f, p4.pct_damage(ItemDefs.PROCS.lightning_strike.damage_pct) * BagDefs.TIERS.strong.mul)
	if _hp_loss(f, hp_f) != want:
		return "強化計時袋的落雷 %.0f 秒後應打 %d（×%.1f），實際 %d" % [BagDefs.BAGS.timer.period, want, BagDefs.TIERS.strong.mul, _hp_loss(f, hp_f)]
	return ""


# 遺物（Build 改版第 6 步）：兩個玩家各自擲 N 選 1；關掉再打開還是同一組；骰子重擲；選一次；全員選過才消失；放不下掉腳邊；走遠就關掉
static func check_relic() -> String:
	var w := World.new(&"test_arena")
	w.spawn_packs = false
	w.reset(7, [World.HOST_PEER_ID, World.HOST_PEER_ID + 1] as Array[int])
	w.spawner.finished = true
	_worlds.append(w)
	var a: Player = w.players[World.HOST_PEER_ID]
	var b: Player = w.players[World.HOST_PEER_ID + 1]
	var relic := w.drop_relic(&"big", Vector2(0, 3))
	a.pos = relic.pos + Vector2(1.0, 0)
	b.pos = relic.pos + Vector2(-1.0, 0)
	relic.open_for(a)
	relic.open_for(b)
	var n := roundi(a.stats.value(&"relic_choices"))
	var oa: Array = relic.offers.get(a.peer_id, [])
	var ob: Array = relic.offers.get(b.peer_id, [])
	if oa.size() != n or ob.size() != n or a.relic_id != relic.id:
		return "每人應有 %d 個選項並打開：%s / %s、打開 %d" % [n, oa, ob, a.relic_id]
	for o: Array in [oa, ob]:
		for id: StringName in o:
			if not Relic.bag_choice(id).is_empty():
				continue   # 石棺偶爾把一個換成詛咒袋（BagDefs.CURSED_CHANCE）
			if o.count(id) != 1 or not LootDefs.drop_pool(ItemDefs.ITEMS[id].rarity).has(id):   # 掉落池含魔力、修飾道具（不屬於羈絆）
				return "選項不該重複、要是掉落池裡的道具：%s" % [o]
	# 關掉再開：同一組；重骰：骰子 −1、換一組；沒有骰子不能骰
	a.relic_id = 0
	relic.open_for(a)
	if relic.offers[a.peer_id] != oa:
		return "關掉再打開應是同一組選項"
	var dice := a.dice
	var tries := 0
	while relic.offers[a.peer_id] == oa and tries < 5 and a.dice > 0:
		relic.reroll(a)
		tries += 1
	if a.dice != dice - tries or relic.offers[a.peer_id] == oa:
		return "重骰應用掉骰子並換一組：骰子 %d → %d（骰了 %d 次）" % [dice, a.dice, tries]
	a.dice = 0
	var before: Array = relic.offers[a.peer_id].duplicate()
	if relic.reroll(a) or relic.offers[a.peer_id] != before:
		return "沒有骰子不能重骰"
	# a 選第 0 個：拿到、只能選一次、遺物還在（b 還沒選）
	var pick_i: int = (relic.offers[a.peer_id] as Array).find_custom(func(id: StringName) -> bool: return Relic.bag_choice(id).is_empty())
	var want: StringName = relic.offers[a.peer_id][pick_i]
	if not relic.pick(a, pick_i) or relic.pick(a, 1) or relic.is_removed or a.relic_id != 0:
		return "a 選了應只能選一次、遺物留給 b"
	if not _held_items(a).any(func(e: Dictionary) -> bool: return e.id == want):
		return "a 應拿到 %s" % want
	if w.nearest_interactable(a, w.relics) != null:
		return "選過的人按 F 不該再打開"
	# b 主袋、袋子、倉庫都塞滿：選的道具掉在腳邊；全員選過遺物消失
	for where: int in b.loadout.active_wheres() + [Loadout.BAG]:
		while b.loadout.add_item(b, &"loaded_dice", {}, 0, where) != &"":
			pass
	var drops := w.pickups.size()
	relic.pick(b, (relic.offers[b.peer_id] as Array).find_custom(func(id: StringName) -> bool: return Relic.bag_choice(id).is_empty()))
	if w.pickups.size() != drops + 1 or not relic.is_removed:
		return "b 放不下應掉在腳邊、全員選過遺物消失：地上多 %d、移除 %s" % [w.pickups.size() - drops, relic.is_removed]
	# 走遠就關掉
	var r2 := w.drop_relic(&"small", Vector2(0, -6))
	a.pos = r2.pos + Vector2(1.0, 0)
	r2.open_for(a)
	a.pos = r2.pos + Vector2(LootDefs.INTERACT_RANGE + 3.0, 0)
	Relic.update_player(a)
	if a.relic_id != 0:
		return "走遠後應關掉遺物"
	return ""


# 遺物的「有人看過」（小地圖用）：兩人都面向 +Z，前方的遺物幾步內算看過、背後遠處的沒人看到；快照帶過去
static func check_relic_spotted() -> String:
	var w := World.new(&"test_arena")
	w.spawn_packs = false
	w.reset(7, [1, 2])
	w.spawner.finished = true
	_worlds.append(w)
	for p: Player in w.player_list:
		p.pos = Vector2(p.peer_id * 1.5, 0)
	var front := w.drop_relic(&"small", Vector2(1.5, 5), &"item")
	var behind := w.drop_relic(&"small", Vector2(1.5, -18), &"item")
	for i in World.RELIC_SPOT_TICKS * 2 + 1:
		var cmds := {}
		for p: Player in w.player_list:
			var c := InputCmd.new()
			c.aim = Vector2(0, 5)
			cmds[p.peer_id] = c
		w.step(cmds, Config.FIXED_DT)
	if not front.spotted or behind.spotted:
		return "前方的遺物應算看過、背後 18 的沒人看到：前 %s、後 %s" % [front.spotted, behind.spotted]
	var mirror := World.new(&"test_arena")
	var copy := NetCodec.create_entity(mirror, NetCodec.entity_fields(front)) as Relic
	var spotted := copy != null and copy.spotted
	mirror.clear()
	if not spotted:
		return "客戶端的遺物鏡像應帶「有人看過」"
	return ""


# 鐵砧（遺物的一種）：選項是改造自己接著的袋子（加大一格要接得下、強化倍率 +0.25 到上限、換成同一邊能接的別種），不重複；
# 選了套在那個袋子上、每人一次、用完不消失；身上沒有能改的袋子時改給新袋子；門的「袋子」獎勵是小袋 N 選 1、Boss 的是大袋或強化袋
static func check_anvil() -> String:
	var w := World.new(&"test_arena")
	w.spawn_packs = false
	w.reset(7)
	w.spawner.finished = true
	_worlds.append(w)
	var p: Player = w.players[World.HOST_PEER_ID]
	var hit := _bag(p, &"hit", &"left")
	var anvil := w.drop_relic(&"small", p.pos + Vector2(1.0, 0.0), &"anvil")
	anvil.open_for(p)
	var n := roundi(p.stats.value(&"relic_choices"))
	var offers: Array = anvil.offers.get(p.peer_id, [])
	if offers.size() != n or p.relic_id != anvil.id:
		return "鐵砧應打開 %d 個改造選項：%s" % [n, offers]
	for id: StringName in offers:
		var c := Relic.anvil_choice(id)
		if c.is_empty() or offers.count(id) != 1 or p.loadout.find_bag(c.uid).is_empty():
			return "鐵砧的選項要是改自己接著的袋子、不重複：%s" % [offers]
	var grow_i := offers.find_custom(func(id: StringName) -> bool: return Relic.anvil_choice(id).action == &"grow" and Relic.anvil_choice(id).uid == hit.uid)
	if grow_i < 0:
		return "左邊 0 的命中袋接得下加大，應有加大的選項：%s" % [offers]
	var length0: int = hit.length
	anvil.pick(p, grow_i)
	if hit.length != length0 + 1 or not anvil.taken.has(p.peer_id) or anvil.is_removed:
		return "選加大後命中袋應長 %d、算用過、鐵砧不消失：長 %d" % [length0 + 1, hit.length]
	anvil.open_for(p)
	if p.relic_id != 0:
		return "用過的鐵砧不能再打開"
	# 強化與換種類直接套用
	var r2 := w.drop_relic(&"small", p.pos + Vector2(-1.0, 0.0), &"anvil")
	r2._anvil_apply(p, Relic.anvil_choice(StringName("anvil:mul:%s" % hit.uid)))
	r2._anvil_apply(p, Relic.anvil_choice(StringName("anvil:kind:%s:kill" % hit.uid)))
	if absf(hit.mul - (1.0 + BagDefs.ANVIL.mul_step)) > EPS or hit.kind != &"kill":
		return "強化後倍率應 ×%.2f、換種類後是擊殺袋：×%.2f、%s" % [1.0 + BagDefs.ANVIL.mul_step, hit.mul, hit.kind]
	# 沒有能改的袋子（只有接滿的按鍵袋也算能改）：開一個全新的玩家，拿掉所有袋子
	var w3 := _new_world()
	var p3 := _player(w3)
	p3.loadout.bags.clear()
	var r3 := w3.drop_relic(&"small", p3.pos + Vector2(1.0, 0.0), &"anvil")
	r3.open_for(p3)
	var fresh: Array = r3.offers.get(p3.peer_id, [])
	if fresh.is_empty() or fresh.any(func(id: StringName) -> bool: return Relic.bag_choice(id).is_empty()):
		return "沒有袋子時鐵砧應改給新袋子的選項：%s" % [fresh]
	# 門的「袋子」獎勵：小袋、種類不重複；Boss 的是大袋或強化袋；選了就接上
	var door := w3.drop_relic(&"big", p3.pos + Vector2(-1.0, 0.0), &"bag")
	door.open_for(p3)
	var bag_offers: Array = door.offers[p3.peer_id]
	var kinds := {}
	for id: StringName in bag_offers:
		var bc := Relic.bag_choice(id)
		if bc.is_empty() or bc.tier != &"small":
			return "門的袋子獎勵應都是小袋：%s" % [bag_offers]
		kinds[bc.kind] = true
	if kinds.size() != bag_offers.size():
		return "袋子的種類不該重複：%s" % [bag_offers]
	var boss := w3.drop_relic(&"big", p3.pos + Vector2(0.0, 1.0), &"bag_big")
	boss.open_for(p3)
	if (boss.offers[p3.peer_id] as Array).any(func(id: StringName) -> bool: return not (Relic.bag_choice(id).get("tier", &"") in [&"big", &"strong"])):
		return "Boss 的袋子應是大袋或強化袋：%s" % [boss.offers[p3.peer_id]]
	var bc0 := Relic.bag_choice(boss.offers[p3.peer_id][0])
	boss.pick(p3, 0)
	if not p3.loadout.bags.any(func(b: Dictionary) -> bool: return b.kind == bc0.kind and b.tier == bc0.tier) and not p3.inventory.entries.any(func(e: Dictionary) -> bool: return e.has("bag")):
		return "選了 Boss 的袋子應接上或放進倉庫：%s" % [bc0]
	return ""
