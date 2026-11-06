# 玩家的裝備與背包：手上的武器、倉庫（inventory，不生效）、主袋（core，數值道具生效）、接在主袋四邊的觸發袋（bags）、
# 背包操作（InputCmd.inv_ops）、撿起武器 / 道具 / 袋子 / 屍體、合成、丟棄（規則在 docs/設計方向.md「觸發袋」）
# 規則：一次拿一把武器（許家慶 2026-11-05 拿掉主副手），手上一定有武器；武器只放倉庫或拿在手上
# 左鍵、右鍵的袋子掛在武器上（許家慶 2026-11-05）：接在主袋左右兩邊的袋子屬於手上那把，換武器時跟著舊的那把走（存在武器實例的 bags），
#   新的那把掛著的接上來；上方的按鍵袋、下方的袋子屬於角色，不跟著換
# 放東西的地方用 where 表示：BAG 倉庫、CORE 主袋、0 以上是 bags 的第幾個（接著的觸發袋）
# 袋子的效果怎麼發動在 BagTriggers；這裡只管擺放、生效的數值道具與羈絆（最大同色區塊）
# 不存 Player（Player 持有 Loadout，反過來存會變成循環參照）：要發事件、套屬性、換招式時由呼叫端傳入 p
class_name Loadout
extends RefCounted

const MAIN := 0    # weapon_slots 的手上那把（只有一格；保留陣列給快照與畫面）
const BAG := -1    # 倉庫
const AUTO := -2   # 自動：照分類找主袋或袋子，放不下進倉庫
const CORE := -3   # 主袋
const WEAPON_SIDES: Array[StringName] = [&"left", &"right"]   # 掛在武器上的袋子接在這兩邊

var weapon_slots: Array[Dictionary] = [{}]   # [手上]：武器實例（WeaponDropDefs）或 {}
var branches := {}                     # 武器的分支詞條（觸發袋改版後沒有詞條，留空給 BondEffects.has_branch）
var bond_counts := {}                  # 羈絆 → 最大同色區塊的格數（主袋與袋子一起算，refresh_items 同步）
var items: Array[Dictionary] = []     # 生效的數值道具 { uid, id }（主袋與接著的袋子裡的）；uid 同時是屬性加成的來源名稱
var inventory := Inventory.new()       # 倉庫（只放東西）
var core := Inventory.core()           # 主袋
var bags: Array[Dictionary] = []       # 接著的觸發袋（BagDefs.make 的實例，side 不是空的）
var merged := false                    # 背包合併模式（BagDefs.MODE_MERGED；開局照 World.bag_mode 決定，快照帶給客戶端）
var unlock_picks := 0                  # 背包合併：還能自選開幾格（Boss、鐵砧給）
var _next_item_uid := 1
var _ops: Array = []                   # 本步收到的背包操作（InputCmd.inv_ops），只在權威端執行


func main_weapon() -> Dictionary:
	return weapon_slots[MAIN]


# 實例對應的 WeaponDefs id；空的回傳 &""
static func weapon_of(inst: Dictionary) -> StringName:
	return &"" if inst.is_empty() else ItemDefs.ITEMS[inst.base].weapon


# 手上武器的範圍倍率（揮砍距離、魔彈射程；稀有度與擲出來的數值，WeaponDropDefs.mul）
func weapon_range_mul() -> float:
	var inst := main_weapon()
	return WeaponDropDefs.mul(inst, "range") if not inst.is_empty() else 1.0


func equipped_count() -> int:
	return weapon_slots.filter(func(s: Dictionary) -> bool: return not s.is_empty()).size()


# 換關：袋子裡次數制的技能（插火把）補滿
func refill_slot_charges() -> void:
	for bag in bags:
		for e: Dictionary in bag.entries:
			e.erase("charges")


# 起始武器：灰色、數值固定（WeaponDropDefs.START_RARITY）
func _new_start(p: Player, id: StringName) -> Dictionary:
	assert(WeaponDefs.WEAPONS.has(id), "Unknown weapon: %s" % id)
	return WeaponDropDefs.make(p.world.new_weapon_uid(), id, WeaponDropDefs.START_RARITY)


# 換上一把新的灰色起始武器（開場、--weapon、武器測試場、測試與除錯用；正式取得武器走 add_weapon）
func equip_new(p: Player, id: StringName) -> void:
	weapon_slots[MAIN] = _new_start(p, id)
	p.apply_active_weapon()


# ── 袋子 ──

func new_uid(prefix: String) -> StringName:
	var uid := StringName("%s_%d" % [prefix, _next_item_uid])
	_next_item_uid += 1
	return uid


# 開局的袋子（Player.apply_class / 沒選職業）：清空主袋與袋子，接上按鍵袋 1（裝著起始技能）與職業的小觸發袋
func setup_start_bags(p: Player, class_id: StringName) -> void:
	core.entries.clear()
	core.locked = {}
	bags.clear()
	unlock_picks = 0
	merged = p.world != null and p.world.bag_mode == BagDefs.MODE_MERGED
	var start: Dictionary = BagDefs.START.get(class_id, {})
	if merged:
		_setup_merged(p, start)
		return
	var key := BagDefs.make(new_uid("bag"), &"key")
	_attach(key, &"top", 0)
	if start.has("skill"):
		Inventory.for_bag(key).add(new_uid("item"), start.skill, Vector2i.ZERO, 0)
	if start.has("bag"):
		var b := BagDefs.make(new_uid("bag"), start.bag[0])
		var spot := attach_spot(b, start.bag[1])
		if not spot.is_empty():
			_attach(b, spot.side, spot.offset)
	refresh_items(p)


# ── 背包合併（BagDefs.MERGED_ZONES）──

# 開局：主袋與每一塊觸發區都接好、全部鎖著，再開主袋中間 3 × 3、職業那一區貼著主袋的 2 格（裝著起始技能）、數字區 1 格
func _setup_merged(p: Player, start: Dictionary) -> void:
	for y in BagDefs.MAIN_SIZE.y:
		for x in BagDefs.MAIN_SIZE.x:
			if not BagDefs.MERGED_START_CORE.has_point(Vector2i(x, y)):
				core.locked[Vector2i(x, y)] = true
	var keys_open := 0
	var class_zone: Array = start.get("bag", [])
	for z: Array in BagDefs.MERGED_ZONES:
		var b := BagDefs.make(new_uid("bag"), z[0])
		b.length = z[3]
		b.depth = z[4]
		var locked := {}
		for y in b.depth:
			for x in b.length:
				locked[Vector2i(x, y)] = true
		if z[0] == &"key" and keys_open < BagDefs.MERGED_START_KEYS:
			keys_open += 1
			locked.erase(Vector2i.ZERO)
		elif not class_zone.is_empty() and z[0] == class_zone[0] and z[1] == class_zone[1]:
			for x in mini(BagDefs.MERGED_START_CLASS, b.length):
				locked.erase(Vector2i(x, 0))
			class_zone = []
			if start.has("skill"):
				b.entries.append({"uid": new_uid("item"), "id": start.skill, "cell": Vector2i.ZERO, "rot": 0})
		b["locked"] = locked
		_attach(b, z[1], z[2])
	if start.has("skill") and not class_zone.is_empty():   # 職業的區塊不在表上（不會發生）：技能放數字區
		for b in key_bags():
			if not b.locked.has(Vector2i.ZERO):
				b.entries.append({"uid": new_uid("item"), "id": start.skill, "cell": Vector2i.ZERO, "rot": 0})
				break
	refresh_items(p)


# 還鎖著的格子：[{ where: CORE 或第幾個袋子, cell }]，照主袋、袋子的順序
func locked_spots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Vector2i in core.locked:
		out.append({"where": CORE, "cell": c})
	for i in bags.size():
		for c: Vector2i in bags[i].get("locked", {}):
			out.append({"where": i, "cell": c})
	return out


# 開一格（where 的 cell 要是鎖著的）；回傳有沒有開
func unlock_cell(p: Player, where: int, cell: Vector2i) -> bool:
	var locked: Dictionary = core.locked if where == CORE else (bags[where].get("locked", {}) if where >= 0 and where < bags.size() else {})
	if not locked.has(cell):
		return false
	locked.erase(cell)
	p.world.emit_event("bag:unlocked", {"player_id": p.id, "where": where, "x": cell.x, "y": cell.y})
	return true


# 隨機開 1 格（整個背包裡隨機，許家慶 2026-11-06 選「全隨機」）；全開了回傳 false
func unlock_random(p: Player, rng: RandomNumberGenerator) -> bool:
	var spots := locked_spots()
	if spots.is_empty():
		return false
	var s: Dictionary = spots[rng.randi_range(0, spots.size() - 1)]
	return unlock_cell(p, s.where, s.cell)


# 自選開格（背包操作 OP_UNLOCK）：用掉 1 次機會
func _unlock_pick(p: Player, where: int, cell: Vector2i) -> void:
	if unlock_picks <= 0 or not unlock_cell(p, where, cell):
		_deny(p, &"no_pick")
		return
	unlock_picks -= 1


# 袋子 b 能不能接在 side 的 offset（ignore：當作那個袋子不在，搬自己的位置用）：邊對、在邊長內、不跟同一邊別的袋子重疊、按鍵袋不超過上限
func bag_fits(b: Dictionary, side: StringName, offset: int, ignore := &"") -> bool:
	if not (BagDefs.BAGS[b.kind].sides as Array).has(side) or offset < 0 or offset + b.length > BagDefs.edge_length(side):
		return false
	var same_kind := 0
	for o in bags:
		if o.uid == ignore or o.uid == b.uid:
			continue
		if o.kind == b.kind:
			same_kind += 1
		if o.side == side and offset < o.offset + o.length and o.offset < offset + b.length:
			return false
	return same_kind < BagDefs.BAGS[b.kind].get("max", 1 << 20)


# 第一個接得下的位置（side 空 = 照 BagDefs.SIDE_ORDER 試這種袋子能接的每一邊）：{ side, offset }；接不下回傳 {}
func attach_spot(b: Dictionary, side := &"") -> Dictionary:
	var sides: Array = [side] if side != &"" else BagDefs.SIDE_ORDER.filter(func(s: StringName) -> bool: return (BagDefs.BAGS[b.kind].sides as Array).has(s))
	for s: StringName in sides:
		for off in BagDefs.edge_length(s) - b.length + 1:
			if bag_fits(b, s, off):
				return {"side": s, "offset": off}
	return {}


func _attach(b: Dictionary, side: StringName, offset: int) -> void:
	b.side = side
	b.offset = offset
	if not bags.has(b):
		bags.append(b)


func find_bag(uid: StringName) -> Dictionary:
	for b in bags:
		if b.uid == uid:
			return b
	var e := inventory.find(uid)
	return e.bag if e.has("bag") else {}


# 撿到一個新的袋子：接得上就接（照 SIDE_ORDER 找第一個空位），不然放倉庫；都放不下回傳 &""、發出 inventory:full
# existing：地上撿回來的袋子（別人或自己丟的），大小、倍率、內容照舊，袋子與裡面道具的 uid 換成自己的（不跟身上的撞號）
func add_bag(p: Player, kind: StringName, tier: StringName = &"small", spot: Dictionary = {}, pickup_id := 0, existing: Dictionary = {}) -> StringName:
	var b := BagDefs.make(new_uid("bag"), kind, tier) if existing.is_empty() else _adopt_bag(existing)
	var where := attach_spot(b) if spot.is_empty() else {}
	if not where.is_empty():
		_attach(b, where.side, where.offset)
	else:
		if spot.is_empty():
			spot = inventory.find_spot(BagDefs.BAGS[kind].item)
		if spot.is_empty():
			_emit_full(p, BagDefs.BAGS[kind].item, pickup_id)
			return &""
		b.side = &""
		inventory.add(b.uid, BagDefs.BAGS[kind].item, spot.cell, spot.rot, {"bag": b})
	refresh_items(p)
	p.world.emit_event("item:added", {"player_id": p.id, "item": String(BagDefs.BAGS[kind].item), "uid": String(b.uid)})
	return b.uid


func _adopt_bag(src: Dictionary) -> Dictionary:
	var b := BagDefs.from_array(BagDefs.to_array(src))   # 深拷貝，地上那份不跟著變
	b.uid = new_uid("bag")
	b.side = &""
	b.offset = 0
	for e: Dictionary in b.entries:
		e.uid = new_uid("item")
	return b


# 袋子搬到 side 的 offset（從倉庫接上、或沿著邊滑動 / 換邊）；side 空 = 拿下來放倉庫（cell / rot 是倉庫的位置，沒給就找空位）
func _place_bag(p: Player, uid: StringName, side: StringName, offset: int, cell := Vector2i(-1, -1), rot := 0) -> bool:
	var stored := inventory.find(uid)
	var b: Dictionary = stored.bag if stored.has("bag") else {}
	if merged:
		return false   # 背包合併：觸發區固定，不能接、搬、拿下來
	var attached := b.is_empty()
	if attached:
		for o in bags:
			if o.uid == uid:
				b = o
	if b.is_empty():
		return false
	if side == &"":
		if not attached:
			return cell.x >= 0 and inventory.move(uid, cell, rot)
		var item: StringName = BagDefs.BAGS[b.kind].item
		var spot := {"cell": cell, "rot": rot} if cell.x >= 0 and inventory.fits(item, cell, rot) else inventory.find_spot(item)
		if spot.is_empty():
			return false
		bags.erase(b)
		b.side = &""
		inventory.add(uid, item, spot.cell, spot.rot, {"bag": b})
	else:
		if not bag_fits(b, side, offset, uid):
			return false
		if not attached:
			inventory.remove(uid)
		_attach(b, side, offset)
	refresh_items(p)
	return true


# 接著的按鍵袋，由左到右（數字鍵）
func key_bags() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in bags:
		if b.kind == &"key":
			out.append(b)
	out.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return a.offset < c.offset)
	return out


# 袋子格子 c 在整張盤上的座標（主袋左上角 (0, 0)；同色區塊與畫面用）
static func board_cell(b: Dictionary, c: Vector2i) -> Vector2i:
	match b.side:
		&"top":
			return Vector2i(b.offset + c.x, -1 - c.y)
		&"bottom":
			return Vector2i(b.offset + c.x, BagDefs.MAIN_SIZE.y + c.y)
		&"left":
			return Vector2i(-1 - c.y, b.offset + c.x)
	return Vector2i(BagDefs.MAIN_SIZE.x + c.y, b.offset + c.x)


# ── 撿東西 ──

# 撿起地上的道具 / 武器 / 袋子 / 屍體，放進去就移除地上那個；spot（{ cell, rot }）空 = 自動放，否則放到 where 的 spot（呼叫端先確認放得下）
func take_pickup(p: Player, ip: ItemPickup, spot: Dictionary = {}, where := AUTO) -> bool:
	var taken: bool
	if ip.corpse_of != 0:
		taken = add_corpse(p, ip.corpse_of, spot, ip.id)
	elif ip.is_weapon():
		taken = add_weapon(p, ip.weapon, spot, ip.id)
	elif ItemDefs.ITEMS[ip.item_id].kind == &"bag":
		taken = add_bag(p, BagDefs.kind_of_item(ip.item_id), &"small", spot, ip.id, ip.bag) != &""
	else:
		taken = add_item(p, ip.item_id, spot, ip.id, BAG if where == AUTO and not spot.is_empty() else where) != &""
	if taken:
		ip.remove()
	return taken


# 放不下：inventory:full 帶著地上道具的實體 id（不是從地上撿的為 0），背包介面用來標出是哪一個
func _emit_full(p: Player, item: StringName, pickup_id: int) -> void:
	p.world.emit_event("inventory:full", {"player_id": p.id, "item": String(item), "pickup_id": pickup_id})


# 撿到武器：手上空著就拿起來，其他放倉庫；都放不下回傳 false、發出 inventory:full。指定 spot 時直接放到倉庫的那一格（背包介面從「腳邊」拖進來）
func add_weapon(p: Player, inst: Dictionary, spot: Dictionary = {}, pickup_id := 0) -> bool:
	if inst.has("bags"):
		var own: Array = []
		for b: Dictionary in inst.bags:
			var nb := _adopt_bag(b)
			nb.side = b.side
			nb.offset = b.offset
			own.append(nb)
		inst.bags = own
	if spot.is_empty():
		if main_weapon().is_empty():
			_set_hand(p, inst)
			p.world.emit_event("weapon:added", {"player_id": p.id, "uid": String(inst.uid), "slot": MAIN})
			return true
		spot = inventory.find_spot(inst.base)
	if spot.is_empty():
		_emit_full(p, inst.base, pickup_id)
		return false
	inventory.add(inst.uid, inst.base, spot.cell, spot.rot, {"weapon": inst})
	p.world.emit_event("weapon:added", {"player_id": p.id, "uid": String(inst.uid), "slot": -1})
	return true


# 依 uid 找武器在哪：{ slot: MAIN } 或 { bag: 倉庫條目 }；找不到回傳 {}
func _find_weapon(uid: StringName) -> Dictionary:
	for i in weapon_slots.size():
		if not weapon_slots[i].is_empty() and weapon_slots[i].uid == uid:
			return {"slot": i, "inst": weapon_slots[i]}
	var e := inventory.find(uid)
	if not e.is_empty() and e.has("weapon"):
		return {"bag": e, "inst": e.weapon}
	return {}


func _take_weapon(where: Dictionary) -> void:
	if where.has("slot"):
		weapon_slots[where.slot] = {}
	else:
		inventory.remove(where.bag.uid)


# 倉庫的武器換上手（slot 只有 MAIN）：換下來的那把放回倉庫（先試換上那把原本的位置，看起來是兩把互換，放不下再找空位）；倉庫放不下就不換
func _equip_from(p: Player, uid: StringName, slot: int) -> bool:
	var src := _find_weapon(uid)
	if src.is_empty() or slot != MAIN or not src.has("bag"):
		return false
	var old := main_weapon()
	inventory.remove(uid)
	if not old.is_empty():
		var spot := {"cell": src.bag.cell, "rot": src.bag.rot} if inventory.fits(old.base, src.bag.cell, src.bag.rot) else inventory.find_spot(old.base)
		if spot.is_empty():
			inventory.add(uid, src.bag.id, src.bag.cell, src.bag.rot, {"weapon": src.inst})
			return false
		inventory.add(old.uid, old.base, spot.cell, spot.rot, {"weapon": old})
	_set_hand(p, src.inst)
	return true


# 換上手：原本那把帶走接在左右邊的袋子（存進它的 bags），新的那把掛著的袋子接上來（接不下的進倉庫、倉庫滿了掉在腳邊）
func _set_hand(p: Player, inst: Dictionary) -> void:
	var old := main_weapon()
	if merged:   # 背包合併：袋子屬於背包，換武器不搬
		weapon_slots[MAIN] = inst
		refresh_items(p)
		p.apply_active_weapon()
		return
	if not old.is_empty() and (inst.is_empty() or old.uid != inst.uid):
		var carried: Array = []
		for b in bags.duplicate():
			if WEAPON_SIDES.has(b.side):
				bags.erase(b)
				carried.append(b)
		if carried.is_empty():
			old.erase("bags")
		else:
			old["bags"] = carried
	weapon_slots[MAIN] = inst
	if not inst.is_empty():
		var extra: Array = []
		for b: Dictionary in inst.get("bags", []):
			if bag_fits(b, b.side, b.offset):
				bags.append(b)
			else:
				extra.append(b)
		inst.erase("bags")
		_stash_bags(p, extra)
	refresh_items(p)
	p.apply_active_weapon()


# 放不回武器上的袋子：連同內容放進倉庫，倉庫滿了掉在腳邊（合成時被吃掉那把掛著的、接不下的）
func _stash_bags(p: Player, list: Array) -> void:
	for b: Dictionary in list:
		b.side = &""
		var item: StringName = BagDefs.BAGS[b.kind].item
		var spot := inventory.find_spot(item)
		if not spot.is_empty():
			inventory.add(b.uid, item, spot.cell, spot.rot, {"bag": b})
		else:
			p.world.drop_item(item, p.pos + MathUtil.dir_from_angle(p.facing) * LootDefs.DROP_DISTANCE).bag = b


# 武器掛著的袋子（倉庫或地上的武器；手上那把的就是接在左右邊的）
static func weapon_bags(inst: Dictionary) -> Array:
	return inst.get("bags", [])


# ── 道具 ──

# 放東西的容器：BAG 倉庫、CORE 主袋、0 以上是第幾個接著的袋子（不存在回傳 null）
func container(where: int) -> Inventory:
	if where == BAG:
		return inventory
	if where == CORE:
		return core
	return Inventory.for_bag(bags[where]) if where >= 0 and where < bags.size() else null


# 有效果的容器：主袋 + 每個接著的袋子
func active_wheres() -> Array[int]:
	var out: Array[int] = [CORE]
	for i in bags.size():
		out.append(i)
	return out


# 道具在哪：{ where, inv, entry }；找不到（或是倉庫裡的武器 / 袋子 / 屍體）回傳 {}
func find_item(uid: StringName) -> Dictionary:
	for where: int in active_wheres() + [BAG]:
		var inv := container(where)
		var e := inv.find(uid)
		if not e.is_empty() and not e.has("weapon") and not e.has("bag") and e.id != &"corpse":
			return {"where": where, "inv": inv, "entry": e}
	return {}


# 道具自動放哪：數值 → 只放主袋（放袋子由玩家手動決定）；效果 → 原本時機的那種袋子優先、再來其他袋子（技能先找按鍵袋）；
# 修飾 → 先找透明格蓋得到有作用的技能的位置、沒有就照順序找空位；都放不下回傳 { }，呼叫端改放倉庫
func auto_place(id: StringName) -> Dictionary:
	var role := ItemDefs.role_of(id)
	var order: Array[int] = []
	if role == ItemDefs.ROLE_STAT:
		order.append(CORE)
	else:
		var prefer: StringName = &"key" if role == ItemDefs.ROLE_SKILL else ItemDefs.default_bag_of(id)
		for i in bags.size():
			if bags[i].kind == prefer:
				order.append(i)
		for i in bags.size():
			if not order.has(i):
				order.append(i)
	if role == ItemDefs.ROLE_MOD:   # 修飾先找蓋得到、而且有作用的技能（第 8 步 f）
		for where in order:
			var cover := container(where).find_cover_spot(id, func(skill: StringName) -> bool: return ItemDefs.mod_applies(id, skill))
			if not cover.is_empty():
				return {"where": where, "spot": cover}
	for where in order:
		var spot := container(where).find_spot(id)
		if not spot.is_empty():
			return {"where": where, "spot": spot}
	return {}


# 道具放進去：where = AUTO 時照分類找主袋或袋子、放不下進倉庫；指定 where 與 spot 時直接放那裡（呼叫端先確認放得下）
# 同一個道具拿兩個就是兩個實例。都放不下回傳 &""、發出 inventory:full；武器道具（kind = weapon）直接換上、袋子接上
func add_item(p: Player, item_id: StringName, spot: Dictionary = {}, pickup_id := 0, where := AUTO) -> StringName:
	assert(ItemDefs.ITEMS.has(item_id), "Unknown item: %s" % item_id)
	var def: Dictionary = ItemDefs.ITEMS[item_id]
	if def.kind == &"bag":
		return add_bag(p, BagDefs.kind_of_item(item_id), &"small", spot if where == BAG else {}, pickup_id)
	var uid := &""
	if def.kind == &"weapon":
		equip_new(p, def.weapon)
	else:
		if where == AUTO:
			var auto := auto_place(item_id)
			if not auto.is_empty():
				where = auto.where
				spot = auto.spot
			else:
				where = BAG
				spot = inventory.find_spot(item_id)
		var inv := container(where)
		if inv != null and spot.is_empty():
			spot = inv.find_spot(item_id)
		if inv == null or spot.is_empty():
			_emit_full(p, item_id, pickup_id)
			return &""
		uid = new_uid("item")
		inv.add(uid, item_id, spot.cell, spot.rot)
		refresh_items(p)
	p.world.emit_event("item:added", {"player_id": p.id, "item": String(item_id), "uid": String(uid)})
	return uid


# 拿掉道具（主袋、袋子或倉庫裡的）；倉庫裡的屍體也走這裡
func remove_item(p: Player, uid: StringName) -> void:
	var found := find_item(uid)
	if found.is_empty():
		inventory.remove(uid)
		return
	(found.inv as Inventory).remove(uid)
	refresh_items(p)


# 拿掉所有道具（主袋、袋子、倉庫裡的；武器、袋子本身、屍體不動）：測試與除錯 F5
func clear_items(p: Player) -> void:
	for where: int in active_wheres() + [BAG]:
		var inv := container(where)
		for e: Dictionary in inv.entries.duplicate():
			if not e.has("weapon") and not e.has("bag") and e.id != &"corpse":
				inv.remove(e.uid)
	refresh_items(p)


# 生效的數值道具 = 主袋與接著的袋子裡的；和 items 比對，新放進來的套屬性、拿出去的移除屬性與條件。詛咒袋接著時套它的缺點。羈絆重算
# 數值道具在主袋與接著的袋子裡都生效（第 8 步 a，YangHsu 2026-11-04）；袋子裡的效果、技能、修飾不算屬性
func refresh_items(p: Player) -> void:
	var want := {}
	for e: Dictionary in core.entries:
		want[e.uid] = e.id
	for b in bags:
		for e: Dictionary in b.entries:
			if ItemDefs.role_of(e.id) == ItemDefs.ROLE_STAT:
				want[e.uid] = e.id
	for it: Dictionary in items.duplicate():
		if not want.has(it.uid):
			items.erase(it)
			p.remove_stat_source(it.uid)
			ItemEffects.forget_item(p, it.uid)
	for uid: StringName in want:
		if not items.any(func(it: Dictionary) -> bool: return it.uid == uid):
			items.append({"uid": uid, "id": want[uid]})
			p.set_stat_source(uid, ItemDefs.stat_mods(want[uid]))
	_refresh_curses(p)
	bond_counts = bond_blocks()
	BondEffects.refresh(p)   # 羈絆的屬性加成、該有的鬼火


# 詛咒袋（BagDefs.TIERS.cursed）：接著時以「curse:<uid>」為來源套上缺點；拿下來就移除
func _refresh_curses(p: Player) -> void:
	var want := {}
	for b in bags:
		var curse: Array = BagDefs.TIERS[b.tier].get("curse", [])
		if not curse.is_empty():
			want[StringName("curse:%s" % b.uid)] = curse
	for source: StringName in p.cursed_sources.duplicate():
		if not want.has(source):
			p.remove_stat_source(source)
			p.cursed_sources.erase(source)
	for source: StringName in want:
		if not p.cursed_sources.has(source):
			p.set_stat_source(source, want[source])
			p.cursed_sources.append(source)


# 羈絆 = 最大同色區塊（C）：主袋與接著的袋子裡每一格的顏色是那個道具的羈絆（跨羈絆的道具兩種都算），
# 同色上下左右連成一塊、跨袋子也算（袋子的格子照 board_cell 換成盤上座標）；回傳 羈絆 → 最大那塊的格數
func bond_blocks() -> Dictionary:
	var colors := {}   # 盤上座標 → 這格的羈絆
	for e: Dictionary in core.entries:
		for c in Inventory.cells_of(e.id, e.rot):
			colors[e.cell + c] = ItemDefs.ITEMS[e.id].get("bonds", [])
	for b in bags:
		var inv := Inventory.for_bag(b)
		for e: Dictionary in b.entries:
			for c in inv.solid_cells(e.id, e.rot):   # 修飾的透明格不算羈絆（第 8 步 f）
				colors[board_cell(b, e.cell + c)] = ItemDefs.ITEMS[e.id].get("bonds", [])
	var out := {}
	for bond: StringName in BondDefs.BONDS:
		var seen := {}
		for start: Vector2i in colors:
			if seen.has(start) or not (colors[start] as Array).has(bond):
				continue
			var size := 0
			var stack: Array[Vector2i] = [start]
			seen[start] = true
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				size += 1
				for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var n := c + d
					if not seen.has(n) and colors.has(n) and (colors[n] as Array).has(bond):
						seen[n] = true
						stack.append(n)
			if size > out.get(bond, 0):
				out[bond] = size
	return out


# 撿起隊友的屍體放進倉庫（佔一格、沒有效果）；放不下回傳 false 並發出 inventory:full
func add_corpse(p: Player, owner_peer: int, spot: Dictionary = {}, pickup_id := 0) -> bool:
	if spot.is_empty():
		spot = inventory.find_spot(&"corpse")
	if spot.is_empty():
		_emit_full(p, &"corpse", pickup_id)
		return false
	inventory.add(Player.corpse_uid(owner_peer), &"corpse", spot.cell, spot.rot)
	p.world.emit_event("item:added", {"player_id": p.id, "item": "corpse", "uid": String(Player.corpse_uid(owner_peer))})
	return true


# 快照：[倉庫, 主袋, [袋子…], [背包合併?, 主袋鎖著的格子, 自選開格的次數]]（Inventory.to_array / BagDefs.to_array）
func bags_to_array() -> Array:
	return [inventory.to_array(), core.to_array(), bags.map(BagDefs.to_array), [merged, BagDefs.cells_to_array(core.locked), unlock_picks]]


# 客戶端：倉庫、主袋、袋子以房主的快照為準（bags_to_array），同步完重算生效的道具與羈絆
func sync_inventory(p: Player, arr: Array) -> void:
	inventory.sync_from(arr[0])
	core.sync_from(arr[1])
	bags.clear()
	for a: Array in arr[2]:
		bags.append(BagDefs.from_array(a))
	var m: Array = arr[3] if arr.size() > 3 else [false, [], 0]
	merged = m[0]
	core.locked = BagDefs.cells_from_array(m[1])
	unlock_picks = int(m[2])
	refresh_items(p)


# 客戶端：手上的武器以房主的快照為準（[手上]，見 WeaponDropDefs.to_array）
func sync_weapon_slots(p: Player, arr: Array) -> void:
	for i in weapon_slots.size():
		weapon_slots[i] = WeaponDropDefs.from_array(arr[i])
	p.apply_active_weapon()


func queue_ops(ops: Array) -> void:
	_ops.append_array(ops)


func clear_ops() -> void:
	_ops.clear()


# 背包操作（InputCmd.inv_ops）：
#   [OP_MOVE, uid, x, y, rot, where?] 搬到 where（BAG 倉庫、CORE 主袋、0 以上第幾個袋子；沒寫 = 倉庫）的 (x, y)；
#     武器、袋子、屍體只在倉庫裡搬；那裡被 1 件東西佔住就互換（_swap_into），拿著的武器放到倉庫的武器上 = 那把換上；沒做成發 inventory:denied
#   [OP_BAG, uid, side, offset, x?, y?, rot?] 袋子接到 side 的 offset（從倉庫接上、或沿著邊滑動 / 換邊）；side 空字串 = 拿下來放倉庫的 (x, y)
#   [OP_DROP, uid] 丟到面前的地上（袋子連同內容）；[OP_EQUIP, uid, slot] 倉庫的武器換上手（slot 只有 MAIN）；[OP_MERGE, uid_a, uid_b] 把 a 拖到 b 上合成（鍛造祭壇旁）
#   [OP_PICKUP, 地上道具 id, x, y, rot, where?] 撿起按得到 F 的地上道具放到 where 的 (x, y)（已被撿走、太遠、放不下就不動；武器、袋子、屍體只能進倉庫）
func apply_ops(p: Player) -> void:
	for op: Array in _ops:
		var where: int = int(op[5]) if op.size() > 5 else BAG
		if int(op[0]) == InputCmd.OP_PICKUP:
			var ip := p.world.entities.get(int(op[1])) as ItemPickup
			var spot := {"cell": Vector2i(op[2], op[3]), "rot": posmod(int(op[4]), 4)}
			if ip == null or ip.is_removed or not p.world.can_reach(p, ip):
				continue
			var stored_only: bool = ip.is_weapon() or ip.corpse_of != 0 or ItemDefs.ITEMS[ip.item_id].kind == &"bag"
			if stored_only and where != BAG:
				continue
			var inv := container(where)
			if inv != null and inv.fits(ip.item_id, spot.cell, spot.rot):
				take_pickup(p, ip, spot, where)
			continue
		if int(op[0]) in [InputCmd.OP_RELIC_PICK, InputCmd.OP_RELIC_REROLL, InputCmd.OP_RELIC_CLOSE]:
			_relic_op(p, op)
			continue
		if int(op[0]) == InputCmd.OP_UNLOCK:
			if op.size() > 3:
				_unlock_pick(p, int(op[1]), Vector2i(int(op[2]), int(op[3])))
			continue
		var uid := StringName(op[1])
		match int(op[0]):
			InputCmd.OP_MOVE:
				var w := _find_weapon(uid)
				var cell := Vector2i(op[2], op[3])
				if w.has("slot"):
					_move_hand_weapon(p, w, cell, int(op[4]))
				elif not w.is_empty() or find_item(uid).is_empty():
					# 倉庫裡的武器、袋子、屍體：只在倉庫裡搬，放到別的東西上就互換
					if where != BAG or (not inventory.move(uid, cell, op[4]) and not _swap_into(inventory.find(uid), inventory, inventory, cell, posmod(int(op[4]), 4))):
						_deny(p, &"no_room")
				else:
					_move_item(p, uid, cell, posmod(int(op[4]), 4), where)
			InputCmd.OP_BAG:
				var cell := Vector2i(int(op[4]), int(op[5])) if op.size() > 5 else Vector2i(-1, -1)
				if not _place_bag(p, uid, StringName(op[2]), int(op[3]), cell, int(op[6]) if op.size() > 6 else 0):
					_deny(p, &"no_room")
			InputCmd.OP_DROP:
				_drop(p, uid)
			InputCmd.OP_EQUIP:
				_equip_from(p, uid, int(op[2]))
			InputCmd.OP_MERGE:
				merge(p, uid, StringName(op[2]))
	_ops.clear()


# 主袋、袋子或倉庫裡有沒有這個道具 / 技能
func has_item(item_id: StringName) -> bool:
	for where: int in active_wheres() + [BAG]:
		if container(where).entries.any(func(e: Dictionary) -> bool: return e.id == item_id):
			return true
	return false


# 遺物的操作：只對自己打開著的那個遺物有效
func _relic_op(p: Player, op: Array) -> void:
	var relic := p.world.entities.get(p.relic_id) as Relic
	if int(op[0]) == InputCmd.OP_RELIC_CLOSE or relic == null:
		p.relic_id = 0
		return
	if op.size() < 2 or int(op[1]) != relic.id:
		return
	if int(op[0]) == InputCmd.OP_RELIC_PICK and op.size() > 2:
		relic.pick(p, int(op[2]))
	elif int(op[0]) == InputCmd.OP_RELIC_REROLL:
		relic.reroll(p)


# 道具搬到 where 的 cell：同一個容器就是搬位置，不同容器放得下（而且收這種東西）才搬；放不下就不動
func _move_item(p: Player, uid: StringName, cell: Vector2i, rot: int, where: int) -> void:
	var found := find_item(uid)
	var dst := container(where)
	if found.is_empty() or dst == null:
		return
	if found.where == where:
		if not (dst.move(uid, cell, rot) or _swap_into(found.entry, dst, dst, cell, rot)):
			_deny(p, &"no_room")
		elif where != BAG:
			refresh_items(p)   # 位置變了，同色區塊跟著變
		return
	var e: Dictionary = found.entry
	if dst.fits(e.id, cell, rot):
		(found.inv as Inventory).remove(uid)
		dst.add(uid, e.id, cell, rot)
		refresh_items(p)
	elif _swap_into(e, found.inv, dst, cell, rot):
		refresh_items(p)
	else:
		_deny(p, &"no_room" if dst.accepts(e.id) else &"wrong_bag")


# 拿著的武器拖進倉庫：拖到倉庫的武器上 = 那把換上手（_equip_from）；放到空位不行（手上一定要有武器）
func _move_hand_weapon(p: Player, w: Dictionary, cell: Vector2i, _rot: int) -> void:
	var under: StringName = inventory.occupied().get(cell, &"")
	if under != &"" and inventory.find(under).has("weapon"):
		if not _equip_from(p, under, w.slot):
			_deny(p, &"no_room")
	else:
		_deny(p, &"main_empty")


# 放到只被 1 件東西佔住的位置：兩件互換（e 放上去，被換走的那件先試 e 原本的位置、放不下找空位）；任何一件放不下就都不動
func _swap_into(e: Dictionary, src: Inventory, dst: Inventory, cell: Vector2i, rot: int) -> bool:
	var plan := swap_plan(e, src, dst, cell, rot)
	if plan.is_empty():
		return false
	var other: Dictionary = plan.other
	src.entries.erase(e)
	dst.entries.erase(other)
	e.cell = cell
	e.rot = rot
	dst.entries.append(e)
	other.cell = plan.spot.cell
	other.rot = plan.spot.rot
	src.entries.append(other)
	return true


# 互換的計畫（不改任何東西，背包介面拖曳時也用來畫預覽）：{ other: 被換走的那件, spot: 它換到 src 的哪裡 }；換不了回傳 {}
# src / dst 可以是同一個容器；兩邊都要收對方的東西（主袋只收數值、袋子只收效果技能修飾，Inventory.accepts）
func swap_plan(e: Dictionary, src: Inventory, dst: Inventory, cell: Vector2i, rot: int) -> Dictionary:
	if e.is_empty() or src == null or dst == null:
		return {}
	var taken := dst.occupied(e.uid)
	var under := {}
	for c in dst.cells(e.id, rot):
		if taken.has(cell + c):
			under[taken[cell + c]] = true
	if under.size() != 1:
		return {}
	var other := dst.find(under.keys()[0])
	if src != dst and (other.has("weapon") or other.has("bag") or other.id == &"corpse"):
		return {}
	# 暫時拿掉兩件、e 的替身放到新位置算得下算不下，算完原地還原（袋子的 entries 就是袋子實例的 entries）
	var src_before := src.entries.duplicate()
	var dst_before := dst.entries.duplicate()
	src.entries.erase(e)
	dst.entries.erase(other)
	var spot := {}
	if dst.fits(e.id, cell, rot):
		var moved := e.duplicate()
		moved.cell = cell
		moved.rot = rot
		dst.entries.append(moved)
		spot = {"cell": e.cell, "rot": other.rot}
		if not src.fits(other.id, spot.cell, spot.rot):
			spot = src.find_spot(other.id)
	src.entries.assign(src_before)
	dst.entries.assign(dst_before)
	return {"other": other, "spot": spot} if not spot.is_empty() else {}


# 背包介面拖曳的預覽：uid 放到 where 的 cell 會跟誰互換（拿著的武器放到倉庫的武器上 = 那把換上）；不會互換回傳 &""
func swap_partner(uid: StringName, where: int, cell: Vector2i, rot: int) -> StringName:
	var w := _find_weapon(uid)
	if w.has("slot"):
		var under: StringName = inventory.occupied().get(cell, &"") if where == BAG else &""
		return under if inventory.find(under).has("weapon") else &""
	var found := find_item(uid)
	if found.is_empty():
		var e := inventory.find(uid)
		return swap_plan(e, inventory, inventory, cell, rot).get("other", {}).get("uid", &"") if where == BAG else &""
	var dst := container(where)
	return swap_plan(found.entry, found.inv, dst, cell, rot).get("other", {}).get("uid", &"") if dst != null else &""


# 背包操作沒做成：讓本機玩家看得到原因（HUD 跳字）
func _deny(p: Player, reason: StringName) -> void:
	p.world.emit_event("inventory:denied", {"player_id": p.id, "reason": String(reason)})


# 把武器 a 拖到 b 上面合成：同種、同稀有度才行，要站在鍛造祭壇旁；b 的位置換成高一級的新武器，a 消失
func merge(p: Player, uid_a: StringName, uid_b: StringName) -> bool:
	var a := _find_weapon(uid_a)
	var b := _find_weapon(uid_b)
	if a.is_empty() or b.is_empty() or not WeaponDropDefs.can_merge(a.inst, b.inst):
		p.world.emit_event("weapon:merge_denied", {"player_id": p.id})
		return false
	if not p.world.near_forge(p):
		p.world.emit_event("weapon:merge_denied", {"player_id": p.id, "reason": "forge"})
		return false
	var merged := WeaponDropDefs.make(b.inst.uid, b.inst.base, WeaponDropDefs.next_rarity(b.inst.rarity), p.world.rng)
	# 掛著的袋子：結果留在手上時手上的照舊接著；兩把都在倉庫時留 b 的；被吃掉那把的進倉庫（滿了掉腳邊）
	if a.has("slot"):
		inventory.remove(b.bag.uid)   # 手上的拖到倉庫的武器上：結果留在手上（手上不能沒有武器）
		weapon_slots[a.slot] = merged
		_stash_bags(p, weapon_bags(b.inst))
	elif b.has("slot"):
		_take_weapon(a)
		weapon_slots[b.slot] = merged
		_stash_bags(p, weapon_bags(a.inst))
	else:
		_take_weapon(a)
		if not weapon_bags(b.inst).is_empty():
			merged["bags"] = weapon_bags(b.inst)
		b.bag.weapon = merged
		_stash_bags(p, weapon_bags(a.inst))
	refresh_items(p)
	p.apply_active_weapon()
	p.world.emit_event("weapon:merged", {"player_id": p.id, "uid": String(merged.uid), "base": String(merged.base), "rarity": String(merged.rarity)})
	return true


# 丟到面前的地上：道具移除效果；手上的武器不能丟（手上一定要有武器）；袋子連同裡面的東西一起丟（大小、倍率、內容都記在地上的袋子，撿回來照原樣）
func _drop(p: Player, uid: StringName) -> void:
	var at := p.pos + MathUtil.dir_from_angle(p.facing) * LootDefs.DROP_DISTANCE
	var w := _find_weapon(uid)
	if not w.is_empty():
		if w.get("slot", -1) == MAIN:
			return
		_take_weapon(w)
		p.apply_active_weapon()
		p.world.drop_weapon(w.inst, at)
		return
	var b := find_bag(uid)
	if not b.is_empty():
		if merged and bags.has(b):
			return   # 背包合併：觸發區固定在背包上，不能丟
		if bags.has(b):
			bags.erase(b)
		else:
			inventory.remove(uid)
		b.side = &""
		b.offset = 0
		refresh_items(p)
		p.world.drop_item(BagDefs.BAGS[b.kind].item, at).bag = b
		return
	var found := find_item(uid)
	var entry: Dictionary = found.get("entry", inventory.find(uid))
	if entry.is_empty():
		return
	if found.is_empty():
		inventory.remove(uid)   # 屍體
	else:
		remove_item(p, uid)
	if entry.id == &"corpse":
		p.world.drop_corpse(String(uid).get_slice("_", 1).to_int(), at)
	else:
		p.world.drop_item(entry.id, at)
