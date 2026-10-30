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
					return "%s 占 %d 格，%s 應占 %d 格" % [id, ItemDefs.cell_count(id),
						ItemDefs.RARITIES[def.rarity].name, ItemDefs.expected_cells(id)]
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
	var i2 := _shaped(&"i2")
	if inv.size != ItemDefs.BAG_SIZE:
		return "背包大小 %s，預期 %s" % [inv.size, ItemDefs.BAG_SIZE]
	# l3：(0,0) (0,1) (1,1)；轉 90° → (-y, x) 再平移：(1,0) (0,0) (0,1)
	var r1 := Inventory.cells_of(_shaped(&"l3"), 1)
	r1.sort()
	var expect: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0)]
	if r1 != expect:
		return "l3 轉 90° 應為 (0,0) (0,1) (1,0)，實際 %s" % [r1]
	# i4 橫放在 (5, 0) 超出邊界，(4, 0) 剛好；直放（轉 90°）在 (0, 3) 超出、(0, 2) 剛好
	if inv.fits(&"staff", Vector2i(5, 0), 0) or not inv.fits(&"staff", Vector2i(4, 0), 0) \
			or inv.fits(&"staff", Vector2i(0, 3), 1) or not inv.fits(&"staff", Vector2i(0, 2), 1):
		return "i4 的邊界判斷錯誤"
	inv.add(&"a", i2, Vector2i(0, 0), 0)   # i2：(0,0) (1,0)
	if inv.fits(&"loaded_dice", Vector2i(1, 0), 0) or not inv.fits(&"loaded_dice", Vector2i(2, 0), 0):
		return "重疊判斷錯誤"
	var spot := inv.find_spot(i2)
	if spot.cell != Vector2i(2, 0) or spot.rot != 0:
		return "第一個空位應為 (2, 0) 不轉，實際 %s" % [spot]
	if not inv.move(&"a", Vector2i(7, 4), 1) or inv.find(&"a").cell != Vector2i(7, 4) or inv.move(&"a", Vector2i(7, 5), 1):
		return "搬動：(7, 4) 直放應成功、(7, 5) 直放應失敗"
	# 只剩直的一行空位時會轉 90° 放進去
	var inv2 := Inventory.new()
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


# 放不下時建議拿掉哪一件：4 × 2 的背包，左上磨刀石（2 格）、右下骰子（1 格），2 × 2 的骨製護盾哪裡都放不下；
# 放不下時建議拿掉哪一件：4 × 2 的背包，左上 2 格道具、右下骰子（1 格），2 × 2 的道具哪裡都放不下；
# 拿掉任一件都放得下時挑占格少的骰子；本來就放得下、拿掉一件也不夠時沒有建議
static func check_inventory_suggest() -> String:
	var big := _shaped(&"o4")
	var inv := Inventory.new()
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
	var tight := Inventory.new()
	tight.size = Vector2i(2, 2)
	tight.add(&"a", &"loaded_dice", Vector2i(0, 0), 0)
	tight.add(&"b", &"loaded_dice", Vector2i(1, 1), 0)
	if tight.suggest_removal(big) != &"":
		return "拿掉一件也放不下時不應有建議，實際「%s」" % tight.suggest_removal(big)
	return ""


static func check_soul_chests() -> String:
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
	var before := w.pickups.size()   # Boss 必掉一把武器，地上原本就有東西
	if not chest.try_open(p) or not chest.opened or w.souls != 1 or w.pickups.size() != before + 1:
		return "靈魂夠應打開：開了 %s、剩 %d、地上多了 %d 個" % [chest.opened, w.souls, w.pickups.size() - before]
	var drop: ItemPickup = w.pickups.back()
	if drop.pos.distance_to(chest.pos) > LootDefs.DROP_DISTANCE + 1.0 or not ItemDefs.ITEMS.has(drop.item_id):
		return "道具應掉在寶箱旁：距離 %.2f" % drop.pos.distance_to(chest.pos)
	if LootDefs.CHESTS.big.weights.get(drop.rarity(), 0.0) <= 0.0:
		return "大寶箱不應開出 %s" % drop.rarity()
	w.souls = 100
	if chest.try_open(p) or w.souls != 100:
		return "開過的寶箱不能再開"
	return ""


# 寶箱的數量（× 人數倍率）與位置規則（可走、走得到出生點、離出生點 / 挖墳點 / 地圖邊緣夠遠）
static func _chest_layout(w: World, players: int) -> String:
	var c: Dictionary = LootDefs.CHEST_PLACEMENT
	var want := {}
	for tier: StringName in w.map.chest_count:
		want[tier] = roundi(w.map.chest_count[tier] * LootDefs.player_mul(players))
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
	if tiers != want:
		return "%d 人時地圖 A 的寶箱 %s，應為 %s" % [players, tiers, want]
	return ""


# 寶箱隨機放與靈魂平衡（v0.44.0）：不同種子位置不同、同種子相同；2 / 4 人寶箱 ×1.5 / ×2.5、殺怪靈魂也一樣；
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
		var want := roundi(LootDefs.KILL_SOULS[&"grunt"] * LootDefs.player_mul(players))
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
	pick.call(stone, Vector2i(3, 2), 1)
	var e: Dictionary = p.inventory.entries[0] if p.inventory.entries.size() == 1 else {}
	if e.is_empty() or e.cell != Vector2i(3, 2) or e.rot != 1 or not stone.is_removed:
		return "OP_PICKUP 應把磨刀石直放在 (3, 2) 並從地上移除：背包 %s、地上還在 %s" % [p.inventory.entries, not stone.is_removed]
	if absf(p.stats.value(&"damage") - 1.0) > EPS:
		return "背包裡的道具沒有效果：攻擊力 %.2f（應為 1.00）" % p.stats.value(&"damage")
	# 搬到主手長劍的格子 (1, 1) 才生效，搬回背包就失效
	var one := 1.0 + _effect_value(&"whetstone", &"damage")
	var sock := _cmd(Vector2.ZERO)
	sock.inv_ops = [[InputCmd.OP_MOVE, String(e.uid), 1, 1, 0, Loadout.MAIN]]
	_run(w, sock, 1)
	if p.loadout.find_item(e.uid).get("where", -9) != Loadout.MAIN or absf(p.stats.value(&"damage") - one) > EPS:
		return "磨刀石搬到長劍格子 (1, 1) 應鑲上並生效：%s、攻擊力 %.2f" % [p.loadout.find_item(e.uid), p.stats.value(&"damage")]
	var unsock := _cmd(Vector2.ZERO)
	unsock.inv_ops = [[InputCmd.OP_MOVE, String(e.uid), 3, 2, 1]]
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
	pick.call(near, Vector2i(3, 2), 0)   # (3, 2) 被磨刀石占著
	if p.inventory.entries.size() != 1 or near.is_removed:
		return "放不下的格子不應撿起"
	p.weapon_slots[1] = {}
	var inst := {"uid": w.new_weapon_uid(), "base": &"staff", "rarity": &"white", "affixes": [] as Array[StringName]}
	var staff := w.drop_weapon(inst, p.pos + Vector2(1.0, 0))
	pick.call(staff, Vector2i(0, 4), 0)
	if not p.weapon_slots[1].is_empty() or p.inventory.find(inst.uid).get("cell", Vector2i(-1, -1)) != Vector2i(0, 4):
		return "武器從腳邊拖進背包應放在 (0, 4)、不放空的裝備欄：裝備欄 %s、背包 %s" % [p.weapon_slots[1], p.inventory.find(inst.uid)]
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
	_note("小怪死 %d 次掉 %d 把（%.2f%%）" % [n, drops, pct])
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
	# 主手：稀有度倍率 + 詞條都生效；撿到的時候在背包、不生效
	var w := _new_world()
	var p := _player(w)
	var aff: Array[StringName] = [&"aff_damage", &"aff_attack_speed"]
	p.add_weapon({"uid": &"blue", "base": &"staff", "rarity": &"blue", "affixes": aff})
	if p.inventory.find(&"blue").is_empty() or absf(p.stats.value(&"damage") - 1.0) > EPS:
		return "撿到的法杖應放背包、詞條不生效：攻擊力 %.2f" % p.stats.value(&"damage")
	var equip := _cmd(Vector2.ZERO)
	equip.inv_ops = [[InputCmd.OP_EQUIP, "blue", Loadout.MAIN]]
	_run(w, equip, 1)
	# v0.27.0 起稀有度有基礎倍率：藍色攻擊力 ×1.4、攻速 ×1.10，再乘詞條的 +10%
	var want_dmg: float = WeaponDropDefs.RARITY_BASE.blue.damage * 1.1
	var want_spd: float = WeaponDropDefs.RARITY_BASE.blue.attack_speed * 1.1
	if p.weapon_id != &"staff" or absf(p.stats.value(&"damage") - want_dmg) > EPS or absf(p.stats.value(&"attack_speed") - want_spd) > EPS:
		return "藍法杖裝上主手後攻擊力 / 攻速應為 %.2f / %.2f：%s、%.2f / %.2f" % [want_dmg, want_spd, p.weapon_id, p.stats.value(&"damage"), p.stats.value(&"attack_speed")]
	# 副手只有詞條生效（稀有度倍率只算主手）
	var w2 := _new_world()
	var p2 := _player(w2)
	var aff2: Array[StringName] = [&"aff_damage"]
	p2.weapon_slots[Loadout.OFF] = {"uid": &"gs", "base": &"woodShield", "rarity": &"green", "affixes": aff2}
	p2.apply_active_weapon()
	if absf(p2.stats.value(&"damage") - 1.1) > EPS:
		return "綠木盾（攻擊力 +10%%）當副手：攻擊力應 1.10（稀有度倍率不算副手），實際 %.2f" % p2.stats.value(&"damage")
	p2.weapon_slots[Loadout.OFF] = {}
	p2.apply_active_weapon()
	if absf(p2.stats.value(&"damage") - 1.0) > EPS:
		return "拿掉副手後詞條應移除：攻擊力 %.2f" % p2.stats.value(&"damage")
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
	# 雷鳴符文：一直打到觸發（命中類只算碰到攻擊部位的，武器格子放不下疊到 100% 的件數）：
	# a → b → c（每跳都在 jump_range 內），d 太遠；每跳 damage_ratio，閃電不會再觸發閃電
	var cl: Dictionary = ItemDefs.PROCS[&"chain_lightning"]
	var jr: float = cl.jump_range
	w = _new_world()
	p = _player(w)
	p.add_item(&"thunder_rune")
	a = _item_dummy(w, Vector2(0, 5))
	b = _item_dummy(w, Vector2(0, 5 + jr * 0.6))
	var c := _item_dummy(w, Vector2(0, 5 + jr * 1.4))
	var d := _item_dummy(w, Vector2(0, 5 + jr * 5.0))
	var hp0 := [a.max_hp, b.max_hp, c.max_hp, d.max_hp]
	for i in 300:
		for e: Enemy in [a, b, c, d]:
			e.hp = e.max_hp
		w.events.clear()
		Combat.apply_damage(w, p, a, {"damage": 10.0})
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
	# 淬毒刀刃：一直打到中毒（同上）；中毒那一下 10 → duration 秒共 10 × total_ratio，每 tick 秒扣一次
	var po: Dictionary = ItemDefs.PROCS[&"poison"]
	var ticks := roundi(po.duration / po.tick)
	w = _new_world()
	p = _player(w)
	p.add_item(&"venom_blade")
	a = _item_dummy(w, Vector2(0, 5))
	var before := a.max_hp
	for i in 300:
		a.hp = a.max_hp
		Combat.apply_damage(w, p, a, {"damage": 10.0})
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
	# 霜之心：一直打到觸發冰凍（武器格子放不下 10 個疊到 100%），冰凍 duration 秒不能動，之後照常追；Boss 不會被冰凍
	var freeze_time: float = _effect(&"frost_heart").duration
	w = _new_world()
	p = _player(w)
	p.add_item(&"frost_heart")
	a = _item_dummy(w, Vector2(0, 6))
	for i in 300:
		Combat.apply_damage(w, p, a, {"damage": 1.0})
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
	# 蝙蝠牙：同一步打兩下只回一次（內部冷卻），冷卻過了再回
	var loh := _effect_value(&"bat_fang", &"life_on_hit")
	p.add_item(&"bat_fang")
	p.hp = 50.0
	var a := _item_dummy(w, Vector2(0, 3))
	Combat.apply_damage(w, p, a, {"damage": 10.0})
	Combat.apply_damage(w, p, a, {"damage": 10.0})
	if absf(p.hp - (50.0 + loh)) > EPS:
		return "蝙蝠牙同一步打兩下應只回 %.0f：生命 %.1f" % [loh, p.hp]
	_run(w, idle, ceili(ItemDefs.PROCS.life_on_hit.icd / DT) + 1)
	Combat.apply_damage(w, p, a, {"damage": 10.0})
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
	var base := roundi(LootDefs.KILL_SOULS[&"grunt"] * LootDefs.player_mul(1))
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


# 觸發（第二批）：受到近戰傷害反彈、受傷爆炸（內部冷卻）、投射物命中爆炸、點燃並擴散
static func check_item_procs_hurt_ignite() -> String:
	var w := _new_world()
	var p := _player(w)
	var idle := _cmd(Vector2.ZERO)
	p.stats.set_base(&"max_hp", 100000.0)
	p.hp = p.max_hp
	# 荊棘鎖甲：近戰扣的血 × ratio 打回攻擊者；投射物不反彈
	var thorn := _effect(&"thorn_mail")
	p.add_item(&"thorn_mail")
	var a := _item_dummy(w, Vector2(0, 2))
	var hp_p := p.hp
	var hp_a := a.hp
	Combat.apply_damage(w, a, p, {"damage": 40.0})
	var taken := hp_p - p.hp
	if _hp_loss(a, hp_a) != _dealt(a, taken * thorn.ratio):
		return "荊棘鎖甲：受到 %.1f 應反彈讓攻擊者扣 %d，實際 %d" % [taken, _dealt(a, taken * thorn.ratio), _hp_loss(a, hp_a)]
	hp_a = a.hp
	p.invuln_timer = 0.0
	Combat.apply_damage(w, a, p, {"damage": 40.0, "projectile": true})
	if _hp_loss(a, hp_a) != 0:
		return "荊棘鎖甲不該反彈投射物：攻擊者扣 %d" % _hp_loss(a, hp_a)
	p.clear_items()
	# 王墓之心：以自己為中心、扣護甲前的受傷量 × damage_ratio；內部冷卻內再被打不炸
	var heart := _effect(&"tomb_heart")
	var hx: Dictionary = ItemDefs.PROCS.hurt_explode
	p.add_item(&"tomb_heart")
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
	# 爆裂箭袋：投射物直接命中時以被打中的怪為中心爆炸（該下 × explode.damage_ratio）；近戰不炸
	w = _new_world()
	p = _player(w)
	var ex: Dictionary = ItemDefs.PROCS.explode
	p.add_item(&"blast_quiver")
	a = _item_dummy(w, Vector2(0, 5))
	b = _item_dummy(w, Vector2(minf(1.0, ex.radius * 0.5), 5))
	hp_b = b.hp
	Combat.apply_damage(w, p, a, {"damage": 20.0, "projectile": true})
	if _hp_loss(b, hp_b) != _dealt(b, 20.0 * ex.damage_ratio):
		return "爆裂箭袋：旁邊的怪應扣 %d，實際 %d" % [_dealt(b, 20.0 * ex.damage_ratio), _hp_loss(b, hp_b)]
	hp_b = b.hp
	Combat.apply_damage(w, p, a, {"damage": 20.0})
	if _hp_loss(b, hp_b) != 0:
		return "爆裂箭袋：近戰命中不該爆炸"
	p.clear_items()
	w.clear()
	# 永恆之焰：命中就點燃；燒著的怪 spread_interval 秒後傳給 spread_range 內一隻，太遠的不會
	w = _new_world()
	p = _player(w)
	var ig: Dictionary = ItemDefs.PROCS.ignite
	p.add_item(&"eternal_flame")
	a = _item_dummy(w, Vector2(0, 5))
	b = _item_dummy(w, Vector2(a.radius * 2.0 + ig.spread_range * 0.5, 5))
	var c := _item_dummy(w, Vector2(-8, 5))
	Combat.apply_damage(w, p, a, {"damage": 20.0})
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


# 觸發（第二批）：普攻追加飛刀 / 斬波（內部冷卻）、每隔幾秒落雷、翻滾減速周圍的怪
static func check_item_procs_attack_timed() -> String:
	var w := _new_world()
	var p := _player(w)
	var idle := _cmd(Vector2.ZERO)
	# 袖中飛刀：普攻出手一直到射出 1 把（proc、武器基礎傷害 × damage_pct；武器格子放不下疊到 100% 的件數）；
	# 內部冷卻內再出手不射。真的走狀態機出手的路徑在 check_item_part_timing
	var kn: Dictionary = ItemDefs.PROCS.throw_knife
	p.add_item(&"sleeve_knife")
	p.aim_point = p.pos + Vector2(0, 5)
	for i in 300:
		ItemEffects.on_attack(w, p, false)
		if not _item_projectiles(w).is_empty():
			break
	var knives := _item_projectiles(w)
	if knives.size() != 1 or absf(knives[0].damage - p.pct_damage(kn.damage_pct)) > EPS or knives[0].pierce:
		return "普攻出手應射 1 把飛刀（傷害 %.2f）：%d 把 %s" % [p.pct_damage(kn.damage_pct), knives.size(), knives.map(func(k: Projectile) -> float: return k.damage)]
	ItemEffects.on_attack(w, p, false)
	if _item_projectiles(w).size() != 1:
		return "飛刀內部冷卻 %.1f 秒內不該再射" % kn.icd
	p.clear_items()
	w.clear()
	# 裂空之刃：左右對稱 count 道穿透斬波，各 damage_ratio
	w = _new_world()
	p = _player(w)
	var rb := _effect(&"rift_blade")
	p.add_item(&"rift_blade")
	p.aim_point = p.pos + Vector2(0, 5)
	ItemEffects.on_attack(w, p, false)
	var waves := _item_projectiles(w)
	if waves.size() != rb.count:
		return "裂空之刃應射出 %d 道斬波，實際 %d" % [rb.count, waves.size()]
	var sw: Dictionary = ItemDefs.PROCS.slash_wave
	for wv in waves:
		var off := absf(MathUtil.wrap_angle(wv.facing - 0.0))
		if not wv.pierce or absf(wv.damage - p.pct_damage(rb.damage_ratio)) > EPS or absf(off - sw.spread) > 0.01:
			return "斬波應穿透、傷害 %.2f、偏 ±%.2f：穿透 %s、%.2f、偏 %.2f" % [p.pct_damage(rb.damage_ratio), sw.spread, wv.pierce, wv.damage, off]
	w.clear()
	# 雷霆鈴：每 period 秒打 range 內最近的 targets 隻，再遠的、第 targets + 1 近的不打
	w = _new_world()
	p = _player(w)
	var bell := _effect(&"thunder_bell")
	var ls: Dictionary = ItemDefs.PROCS.lightning_strike
	p.add_item(&"thunder_bell")
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
	p.add_item(&"stasis_watch")
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


# 觸發（第二批）：擊殺放追蹤鬼火、擊殺召喚玩家方的骷髏僕從
static func check_item_procs_summon() -> String:
	var w := _new_world()
	var p := _player(w)
	var idle := _cmd(Vector2.ZERO)
	# 鬼火燈籠：擊殺時從屍體飛出 1 顆（擊殺那一下 × damage_ratio），會轉彎打到旁邊的怪；同時最多 max 顆
	var wp: Dictionary = ItemDefs.PROCS.wisp
	p.add_item(&"wisp_lantern")
	var b := _item_dummy(w, Vector2(4, 6))
	b.dormant = true
	Combat.apply_damage(w, p, _item_dummy(w, Vector2(0, 6), 1.0), {"damage": 20.0})
	var wisps := _item_projectiles(w).filter(func(x: Projectile) -> bool: return x.homing > 0.0)
	if wisps.size() != 1 or absf(wisps[0].damage - 20.0 * wp.damage_ratio) > EPS:
		return "擊殺應放出 1 顆鬼火（傷害 %.1f）：%s" % [20.0 * wp.damage_ratio, wisps.map(func(x: Projectile) -> float: return x.damage)]
	_run(w, idle, roundi(wp.life / DT))
	if b.hp >= b.max_hp:
		return "鬼火應追到旁邊的怪"
	for i in wp.max + 4:
		Combat.apply_damage(w, p, _item_dummy(w, Vector2(-8, -8), 1.0), {"damage": 20.0})
	var alive := _item_projectiles(w).filter(func(x: Projectile) -> bool: return x.homing > 0.0).size()
	if alive != wp.max:
		return "鬼火同時最多 %d 顆，實際 %d" % [wp.max, alive]
	w.clear()
	# 亡者大軍疊到 100%：擊殺召喚 1 隻玩家方的僕從；玩家打不到它、它打不到玩家、怪打得到它；會去打怪；最多 max 隻；life 秒後倒下、不給靈魂
	w = _new_world()
	p = _player(w)
	var army := _effect(&"army_of_dead")
	var md: Dictionary = EnemyDefs.ENEMIES.minion
	for i in _stacks_for_sure(&"army_of_dead"):
		p.add_item(&"army_of_dead")
	Combat.apply_damage(w, p, _item_dummy(w, Vector2(0, 3), 1.0), {"damage": 20.0})
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
		Combat.apply_damage(w, p, _item_dummy(w, Vector2(-6, -6), 1.0), {"damage": 20.0})
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
			return ItemDefs.item_implemented(id) and not ItemDefs.ITEMS[id].get("bonds", []).is_empty())
		if not done.is_empty():
			if pool != done:
				return "%s 的掉落應為實作好、屬於羈絆的 %s，實際 %s" % [r, done, pool]
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
	op.call([[InputCmd.OP_MOVE, String(shield), 6, 0, 0]])
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
	# 鑲嵌（Build 改版第 3 步）：鑲在長劍上的磨刀石生效；換上背包的法杖時跟著搬到法杖格子、照樣生效
	var stone := p.loadout.add_item(p, &"whetstone", {}, 0, Loadout.MAIN)
	var dmg := p.stats.value(&"damage")
	if stone == &"" or p.loadout.find_item(stone).get("where", -9) != Loadout.MAIN or dmg <= 1.0:
		return "磨刀石應鑲在長劍上並生效：攻擊力 %.2f" % dmg
	op.call([[InputCmd.OP_EQUIP, "a", Loadout.MAIN]])
	if p.weapon_id != &"staff" or p.loadout.find_item(stone).get("where", -9) != Loadout.MAIN or absf(p.stats.value(&"damage") - dmg) > EPS:
		return "換上法杖後磨刀石應搬到法杖格子、照樣生效：%s、%s、攻擊力 %.2f" % [p.weapon_id, p.loadout.find_item(stone), p.stats.value(&"damage")]
	# 武器格子只能放 mask 裡的格子；快照來回鑲的道具不變
	var staff_inv := p.loadout.container(Loadout.MAIN)
	if staff_inv.fits(&"loaded_dice", Vector2i(1, 0), 0):
		return "法杖格子 (1, 0) 是空的（不是格子），不應放得下"
	var back := WeaponDropDefs.from_array(WeaponDropDefs.to_array(p.weapon_slots[Loadout.MAIN]))
	if back.get("sockets", []).size() != 1 or back.sockets[0].uid != stone or back.sockets[0].cell != staff_inv.find(stone).cell:
		return "快照來回後法杖上鑲的東西應一樣：%s" % [back.get("sockets", [])]
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
	var merge := func(a: String, b: String) -> void:
		var c := _cmd(Vector2.ZERO)
		c.inv_ops = [[InputCmd.OP_MERGE, a, b]]
		w.events.clear()
		_run(w, c, 1)
	# 背包的白長劍拖到主手的白長劍 → 綠色、1 條詞條、留在主手、立刻生效
	merge.call("s3", String(start_uid))
	var m: Dictionary = p.weapon_slots[0]
	if m.rarity != &"green" or m.affixes.size() != 1 or not p.inventory.find(&"s3").is_empty() or _named(w.events, "weapon:merged").is_empty():
		return "合成應得到綠色 1 條詞條、在主手：%s" % [m]
	var mods := WeaponDropDefs.stat_mods(m)
	var stat: StringName = mods[0][0]
	if is_equal_approx(p.stats.value(stat), p.stats.base(stat)):
		return "合成後手上的詞條（%s）應立刻生效" % stat
	# 不同種、不同稀有度不能合成
	merge.call("st", "s2")
	if _named(w.events, "weapon:merge_denied").is_empty() or p.inventory.find(&"st").is_empty():
		return "法杖拖到長劍上不應合成"
	merge.call("s2", "g1")
	if _named(w.events, "weapon:merge_denied").is_empty() or p.inventory.find(&"s2").is_empty():
		return "白色拖到綠色上不應合成"
	# 主手的綠長劍拖到背包的綠長劍 → 藍色留在主手（主手不能沒有武器），背包那把消失
	merge.call(String(start_uid), "g1")
	var g: Dictionary = p.weapon_slots[Loadout.MAIN]
	if g.get("rarity", &"") != &"blue" or not p.inventory.find(&"g1").is_empty() or p.weapon_id != &"longsword+woodShield":
		return "主手的綠 + 背包的綠應在主手得到藍色：%s" % [g]
	# 雙持的兩把匕首合成 → 結果在主手、副手空出來
	var wd := _new_world()
	var pd := _player(wd)
	pd.equip_weapon(&"dagger")
	pd.loadout.equip_offhand_new(pd, &"dagger")
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


# 部位決定發動時機（Build 改版第 4 步）：命中 / 普攻類只算碰到那個部位的道具——攻擊部位每次、末端只有連段最後一下（跨兩個部位各算一次）、
# 防禦部位格擋成功時、握柄不發動；同一隻手的格子裡搬位置會跟著改；自動擺放時觸發道具碰攻擊部位、數值道具不佔觸發部位
static func check_item_part_timing() -> String:
	var w := _new_world()
	var p := _player(w)
	p.loadout.equip_new(p, &"longsword")
	p.loadout.equip_offhand_new(p, &"woodShield")
	# 長劍格子：(2, 0) 末端、第 1~4 列中間攻擊部位、第 5 列握柄（WeaponDefs.WEAPONS.longsword.grid）
	var rune := p.loadout.add_item(p, &"thunder_rune", {"cell": Vector2i(2, 0), "rot": 1}, 0, Loadout.MAIN)
	var it := ItemEffects._item_of(p, rune)
	if it.get("parts", "") != "EA":
		return "雷鳴符文鑲在劍尖 + 刃，部位應為 EA：%s" % it.get("parts", "")
	var chance: float = _effect(&"thunder_rune").chance
	for part in ["A", "E"]:
		var procs := ItemEffects.procs_of(p, &"hit", part)
		if procs.size() != 1 or absf(procs[0].chance - chance) > EPS:
			return "鑲在 EA 的雷鳴符文在 %s 應發動（機率 %.2f）：%s" % [part, chance, procs]
	if not ItemEffects.procs_of(p, &"hit", "D").is_empty():
		return "劍上的雷鳴符文格擋時不該發動"
	# 命中時擲骰次數：一般命中 1 次（攻擊部位）、連段最後一下 2 次（攻擊部位 + 末端各一次）
	var a := _item_dummy(w, Vector2(0, 5))
	var draws := func(finisher: bool) -> int:
		var before: int = w.rng.state
		ItemEffects.on_hit(w, p, a, 10.0, false, finisher)
		var after: int = w.rng.state
		w.rng.state = before
		for n in 8:
			if w.rng.state == after:
				return n
			w.rng.randf()
		return -1
	if draws.call(false) != 1 or draws.call(true) != 2:
		return "EA 的符文：一般命中應擲 1 次、連段最後一下 2 次，實際 %d / %d" % [draws.call(false), draws.call(true)]
	# 搬到握柄（同一隻手）：不發動
	p.loadout._move_item(p, rune, Vector2i(2, 5), 1, Loadout.MAIN)
	if ItemEffects._item_of(p, rune).get("parts", "") != "H" or draws.call(true) != 0:
		return "搬到握柄後部位應為 H、命中不擲骰：%s / %d" % [ItemEffects._item_of(p, rune).get("parts", ""), draws.call(true)]
	if ItemDefs.timing_line(&"thunder_rune", "H").find("不發動") < 0 or ItemDefs.timing_line(&"whetstone", "A") != "":
		return "說明：握柄應寫不發動、數值道具不寫發動：%s / %s" % [ItemDefs.timing_line(&"thunder_rune", "H"), ItemDefs.timing_line(&"whetstone", "A")]
	# 攻擊部位的裂空之刃：真的普攻出手（狀態機）就射出斬波
	var rb := _effect(&"rift_blade")
	var blade := p.loadout.add_item(p, &"rift_blade", {"cell": Vector2i(1, 2), "rot": 0}, 0, Loadout.MAIN)
	if ItemEffects._item_of(p, blade).get("parts", "") != "A":
		return "裂空之刃應只在攻擊部位：%s" % ItemEffects._item_of(p, blade).get("parts", "")
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), roundi(p.weapon.attack.windup / DT) + 2)
	if _item_projectiles(w).size() != rb.count:
		return "攻擊部位的裂空之刃普攻出手應射 %d 道，實際 %d" % [rb.count, _item_projectiles(w).size()]
	# 搬到盾面（防禦部位）：普攻不射、格擋成功才射
	p.loadout.remove_item(p, blade)
	blade = p.loadout.add_item(p, &"rift_blade", {"cell": Vector2i(1, 0), "rot": 0}, 0, Loadout.OFF)
	p.proc_timers.clear()
	for e in _item_projectiles(w):
		e.remove()
	ItemEffects.on_attack(w, p, true)
	if not _item_projectiles(w).is_empty():
		return "盾面的裂空之刃普攻不該射"
	var foe := _item_dummy(w, p.pos + Vector2(0, 2))
	p.facing = 0.0
	p.block_time = 0.0
	Combat.apply_damage(w, foe, p, {"damage": 5.0, "blockable": true})
	if _item_projectiles(w).size() != rb.count:
		return "盾面的裂空之刃格擋成功應射 %d 道，實際 %d" % [rb.count, _item_projectiles(w).size()]
	# 盾面的永恆之焰（命中類）：格擋成功時點燃攻擊者
	p.loadout.remove_item(p, blade)
	p.loadout.add_item(p, &"eternal_flame", {"cell": Vector2i(1, 0), "rot": 0}, 0, Loadout.OFF)
	Combat.apply_damage(w, foe, p, {"damage": 5.0, "blockable": true})
	if foe.burn_timer <= 0.0:
		return "盾面的永恆之焰格擋成功應點燃攻擊者"
	# 自動擺放：觸發道具碰到攻擊部位、數值道具不佔攻擊部位 / 末端 / 防禦部位
	var w2 := _new_world()
	var p2 := _player(w2)
	p2.loadout.equip_new(p2, &"longsword")
	var auto_rune := ItemEffects._item_of(p2, p2.add_item(&"venom_blade"))
	var auto_stone := ItemEffects._item_of(p2, p2.add_item(&"whetstone"))
	if not String(auto_rune.get("parts", "")).contains("A"):
		return "自動擺放的淬毒刀刃應碰到攻擊部位：%s" % auto_rune.get("parts", "")
	for part in ["A", "E", "D"]:
		if String(auto_stone.get("parts", "")).contains(part):
			return "自動擺放的磨刀石不該佔 %s：%s" % [part, auto_stone.get("parts", "")]
	return ""


# 羈絆（Build 改版第 5 步）：道具標的羈絆都存在、掉落池只有屬於羈絆的；件數只算鑲在兩隻手上的、同一種只算 1 件、
# 跨羈絆的兩邊各算；拿下來就扣；階數照門檻
static func check_bonds() -> String:
	for id: StringName in ItemDefs.ITEMS:
		for bond: StringName in ItemDefs.ITEMS[id].get("bonds", []):
			if not BondDefs.BONDS.has(bond):
				return "%s 的羈絆不存在：%s" % [id, bond]
	for r: StringName in ItemDefs.RARITIES:
		for id in LootDefs.drop_pool(r):
			if ItemDefs.ITEMS[id].get("bonds", []).is_empty():
				return "%s 不屬於任何羈絆，不該在掉落池" % id
	for bond: StringName in BondDefs.BONDS:
		var th: Array = BondDefs.BONDS[bond].thresholds
		if BondDefs.BONDS[bond].tiers.size() != th.size():
			return "%s 的階數和門檻數不一樣" % bond
		if BondDefs.tier(bond, th[0] - 1) != 0 or BondDefs.tier(bond, th[0]) != 1 or BondDefs.tier(bond, th[-1]) != th.size() \
				or BondDefs.next_threshold(bond, th[-1]) != -1:
			return "%s 的階數計算不對" % bond
	var w := _new_world()
	var p := _player(w)
	p.loadout.equip_new(p, &"longsword")
	p.loadout.equip_offhand_new(p, &"woodShield")
	p.add_item(&"whetstone")
	p.add_item(&"whetstone")   # 同一種只算 1 件
	p.add_item(&"light_gloves")
	var dice := p.loadout.add_item(p, &"loaded_dice", {}, 0, Loadout.BAG)   # 背包裡的不算
	p.add_item(&"tomb_heart")   # 防禦 + 火焰
	var want := {&"phys": 2, &"guard": 1, &"fire": 1}
	if p.loadout.bond_counts != want:
		return "件數應為 %s，實際 %s" % [want, p.loadout.bond_counts]
	if BondDefs.tier(&"phys", p.loadout.bond_counts[&"phys"]) != 1:
		return "物理 2 件應啟動第 1 階"
	p.loadout._move_item(p, dice, Vector2i(2, 0), 0, Loadout.MAIN)
	if p.loadout.bond_counts.get(&"phys", 0) != 3:
		return "灌鉛骰子鑲上後物理應 3 件，實際 %s" % p.loadout.bond_counts
	p.loadout.remove_item(p, dice)
	if p.loadout.bond_counts.get(&"phys", 0) != 2:
		return "拿掉灌鉛骰子後物理應回到 2 件，實際 %s" % p.loadout.bond_counts
	return ""
