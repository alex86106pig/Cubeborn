# 玩家的裝備與背包（2026-10-25 從 Player 拆出來）：主手與副手（Build 改版）、背包擺放（D3，Inventory）、生效的道具、
# 背包操作（InputCmd.inv_ops）、撿起武器 / 道具 / 屍體、合成、丟棄
# 規則：主手一定有武器；單手武器可以再拿副手，雙手武器不行（WeaponDefs.can_hold）；主手與副手的詞條都生效；
# 道具鑲在主手 / 副手的格子上才生效（Build 改版第 3 步），鑲的道具跟著武器實例走（inst.sockets）；背包只放東西，沒有效果
# 不存 Player（Player 持有 Loadout，反過來存會變成循環參照）：要發事件、套屬性、換招式時由呼叫端傳入 p
class_name Loadout
extends RefCounted

const MAIN := 0
const OFF := 1
const BAG := -1    # 道具放哪裡：BAG 背包、MAIN / OFF 主手 / 副手的武器格子
const AUTO := -2   # 自動：主手格子 → 副手格子 → 背包，第一個放得下的

var weapon_slots: Array[Dictionary] = [{}, {}]   # [主手, 副手]：武器實例（WeaponDropDefs）或 {}
var bond_counts := {}                  # 羈絆 → 件數（BondDefs；鑲在兩隻手上、同一種只算 1 件，refresh_items 同步）
var items: Array[Dictionary] = []     # 生效的道具實例 { uid, id, parts }（鑲在主手 / 副手上的，refresh_items 同步）；uid 同時是屬性加成的來源名稱，parts 是碰到的部位字元（發動時機）
var inventory := Inventory.new()       # 背包的擺放（只放東西）
var _next_item_uid := 1
var _ops: Array = []                   # 本步收到的背包操作（InputCmd.inv_ops），只在權威端執行


func main_weapon() -> Dictionary:
	return weapon_slots[MAIN]


# 實例對應的 WeaponDefs id；空的回傳 &""
static func weapon_of(inst: Dictionary) -> StringName:
	return &"" if inst.is_empty() else ItemDefs.ITEMS[inst.base].weapon


# 主手稀有度的範圍倍率（揮砍距離、魔彈射程）
func weapon_range_mul() -> float:
	var inst := main_weapon()
	return WeaponDropDefs.RARITY_BASE[inst.rarity].range if not inst.is_empty() else 1.0


func equipped_count() -> int:
	return weapon_slots.filter(func(s: Dictionary) -> bool: return not s.is_empty()).size()


# 換層：裝備欄與背包裡武器的技能次數補滿（火把的插火把；掉在地上的不補）
func refill_slot_charges() -> void:
	for inst in weapon_slots:
		inst.erase("slot_charges")
	for e in inventory.entries:
		if e.has("weapon"):
			e.weapon.erase("slot_charges")


func _new_white(p: Player, id: StringName) -> Dictionary:
	assert(WeaponDefs.WEAPONS.has(id), "Unknown weapon: %s" % id)
	return {"uid": p.world.new_weapon_uid(), "base": id, "rarity": &"white", "affixes": [] as Array[StringName]}


# 換上一把新的白色武器（開場、--weapon、武器測試場、測試與除錯用；正式取得武器走 add_weapon）：
# 一般武器放主手、副手清空（武器測試場按一把就只拿那一把，才看得到它自己的右鍵）；只能當副手的（盾）放副手，主手是雙手武器時主手換成起始武器
func equip_new(p: Player, id: StringName) -> void:
	if WeaponDefs.WEAPONS[id].hands == &"off":
		if not WeaponDefs.can_hold(weapon_of(main_weapon()), id):
			weapon_slots[MAIN] = _new_white(p, Config.PLAYER.start_weapon)
		weapon_slots[OFF] = _new_white(p, id)
	else:
		weapon_slots[MAIN] = _new_white(p, id)
		weapon_slots[OFF] = {}
	p.apply_active_weapon()


# 副手換成一把新的白色武器（開場的職業起始副手）；id 空 = 空手。拿不動（主手是雙手）就清空
func equip_offhand_new(p: Player, id: StringName) -> void:
	weapon_slots[OFF] = _new_white(p, id) if id != &"" and WeaponDefs.can_hold(weapon_of(main_weapon()), id) else {}
	p.apply_active_weapon()


# 撿起地上的道具 / 武器 / 屍體，放進去就移除地上那個；spot（{ cell, rot }）空 = 自動放，否則放到背包的 spot（呼叫端先確認放得下）
# where：道具放哪（AUTO / BAG / MAIN / OFF，見 add_item）；武器與屍體只會進背包
func take_pickup(p: Player, ip: ItemPickup, spot: Dictionary = {}, where := AUTO) -> bool:
	var taken: bool
	if ip.corpse_of != 0:
		taken = add_corpse(p, ip.corpse_of, spot, ip.id)
	elif ip.is_weapon():
		taken = add_weapon(p, ip.weapon, spot, ip.id)
	else:
		taken = add_item(p, ip.item_id, spot, ip.id, BAG if where == AUTO and not spot.is_empty() else where) != &""
	if taken:
		ip.remove()
	return taken


# 放不下：inventory:full 帶著地上道具的實體 id（不是從地上撿的為 0），背包介面用來標出是哪一個
func _emit_full(p: Player, item: StringName, pickup_id: int) -> void:
	p.world.emit_event("inventory:full", {"player_id": p.id, "item": String(item), "pickup_id": pickup_id})


# 撿到武器（D4）：主手空著放主手；副手空著、撿到的是盾而且拿得動放副手（單手武器不自動放副手，免得右鍵突然變了）；
# 其他放背包；都放不下回傳 false、發出 inventory:full。指定 spot 時直接放到背包的那一格（背包介面從「腳邊」拖進來）
func add_weapon(p: Player, inst: Dictionary, spot: Dictionary = {}, pickup_id := 0) -> bool:
	if spot.is_empty():
		var id := weapon_of(inst)
		var slot := -1
		if main_weapon().is_empty() and WeaponDefs.WEAPONS[id].hands != &"off":
			slot = MAIN
		elif weapon_slots[OFF].is_empty() and WeaponDefs.WEAPONS[id].hands == &"off" and WeaponDefs.can_hold(weapon_of(main_weapon()), id):
			slot = OFF
		if slot >= 0:
			weapon_slots[slot] = inst
			p.apply_active_weapon()
			p.world.emit_event("weapon:added", {"player_id": p.id, "uid": String(inst.uid), "slot": slot})
			return true
		spot = inventory.find_spot(inst.base)
	if spot.is_empty():
		_emit_full(p, inst.base, pickup_id)
		return false
	inventory.add(inst.uid, inst.base, spot.cell, spot.rot, inst)
	p.world.emit_event("weapon:added", {"player_id": p.id, "uid": String(inst.uid), "slot": -1})
	return true


# 依 uid 找武器在哪：{ slot: MAIN / OFF } 或 { bag: 背包條目 }；找不到回傳 {}
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


# 武器放進主手 / 副手（slot）：主手與副手互換；從背包來時換下來的那把放回背包。
# 換完拿不動的（雙手武器配副手、副手放了不能當副手的）也放回背包；主手不能變空、背包放不下就整個不換
func _equip_from(p: Player, uid: StringName, slot: int) -> bool:
	var src := _find_weapon(uid)
	if src.is_empty() or slot < MAIN or slot > OFF or src.get("slot", -1) == slot:
		return false
	var hands: Array[Dictionary] = [weapon_slots[MAIN], weapon_slots[OFF]]
	var displaced: Array[Dictionary] = []
	var other := OFF if slot == MAIN else MAIN
	if src.has("slot"):
		hands[other] = hands[slot]   # 主副手互換
	elif not hands[slot].is_empty():
		displaced.append(hands[slot])
	hands[slot] = src.inst
	if not hands[OFF].is_empty() and not WeaponDefs.can_hold(weapon_of(hands[MAIN]), weapon_of(hands[OFF])):
		displaced.append(hands[OFF])
		hands[OFF] = {}
	if hands[MAIN].is_empty() or not WeaponDefs.can_hold(weapon_of(hands[MAIN]), weapon_of(hands[OFF])):
		return false
	if src.has("bag"):
		inventory.remove(uid)
	var placed: Array[StringName] = []
	for w in displaced:
		var spot := inventory.find_spot(w.base)
		if spot.is_empty():
			for u in placed:
				inventory.remove(u)
			if src.has("bag"):
				inventory.add(uid, src.bag.id, src.bag.cell, src.bag.rot, src.inst)
			return false
		inventory.add(w.uid, w.base, spot.cell, spot.rot, w)
		placed.append(w.uid)
	weapon_slots[MAIN] = hands[MAIN]
	weapon_slots[OFF] = hands[OFF]
	for w in displaced:   # 換下來的武器上鑲的道具：搬到現在手上的武器，放不下進背包，再放不下留在原本的武器上
		_move_sockets(w, [weapon_slots[MAIN], weapon_slots[OFF]])
	p.apply_active_weapon()
	return true


# 把武器 a 拖到 b 上面合成（D4）：同種、同稀有度才行；b 的位置換成高一級、詞條重新抽的新武器，a 消失
func merge(p: Player, uid_a: StringName, uid_b: StringName) -> bool:
	var a := _find_weapon(uid_a)
	var b := _find_weapon(uid_b)
	if a.is_empty() or b.is_empty() or not WeaponDropDefs.can_merge(a.inst, b.inst):
		p.world.emit_event("weapon:merge_denied", {"player_id": p.id})
		return false
	var merged := WeaponDropDefs.make(b.inst.uid, b.inst.base, WeaponDropDefs.next_rarity(b.inst.rarity), p.world.rng)
	if b.inst.has("sockets"):
		merged["sockets"] = b.inst.sockets   # 鑲的道具：b 的留著，a 的搬到合成結果、放不下進背包、再不下掉在地上
	_move_sockets(a.inst, [merged], p)
	if a.has("slot") and b.has("slot"):
		# 主副手兩把（雙持匕首）合成：結果拿在主手、副手空出來
		weapon_slots[MAIN] = merged
		weapon_slots[OFF] = {}
	elif a.has("slot"):
		# 手上的拖到背包的武器上：結果留在手上（主手不能沒有武器），背包那把消失
		inventory.remove(b.bag.uid)
		weapon_slots[a.slot] = merged
	elif b.has("slot"):
		_take_weapon(a)
		weapon_slots[b.slot] = merged
	else:
		_take_weapon(a)
		b.bag.weapon = merged
	p.apply_active_weapon()
	p.world.emit_event("weapon:merged", {"player_id": p.id, "uid": String(merged.uid), "base": String(merged.base), "rarity": String(merged.rarity)})
	return true


# 放道具的容器：BAG 背包、MAIN / OFF 那隻手武器的格子（手上沒武器回傳 null）
func container(where: int) -> Inventory:
	if where == BAG:
		return inventory
	return null if weapon_slots[where].is_empty() else Inventory.for_weapon(weapon_slots[where])


# 道具在哪：{ where, inv, entry }；找不到（或是背包裡的武器 / 屍體）回傳 {}
func find_item(uid: StringName) -> Dictionary:
	for where: int in [MAIN, OFF, BAG]:
		var inv := container(where)
		if inv == null:
			continue
		var e := inv.find(uid)
		if not e.is_empty() and not e.has("weapon") and e.id != &"corpse":
			return {"where": where, "inv": inv, "entry": e}
	return {}


# 道具放進去：where = AUTO 時依序試主手格子、副手格子、背包；指定 where 與 spot 時直接放那裡（呼叫端先確認放得下）
# 同一個道具拿兩個就是兩個實例。都放不下回傳 &""、發出 inventory:full；武器道具（kind = weapon）直接換上
func add_item(p: Player, item_id: StringName, spot: Dictionary = {}, pickup_id := 0, where := AUTO) -> StringName:
	assert(ItemDefs.ITEMS.has(item_id), "Unknown item: %s" % item_id)
	var def: Dictionary = ItemDefs.ITEMS[item_id]
	var uid := &""
	if def.kind == &"weapon":
		equip_new(p, def.weapon)
	else:
		var inv: Inventory = null
		if where == AUTO:
			for w: int in [MAIN, OFF, BAG]:
				inv = container(w)
				spot = inv.find_spot(item_id) if inv != null else {}
				if not spot.is_empty():
					break
		else:
			inv = container(where)
			if inv != null and spot.is_empty():
				spot = inv.find_spot(item_id)
		if inv == null or spot.is_empty():
			_emit_full(p, item_id, pickup_id)
			return &""
		uid = StringName("item_%d" % _next_item_uid)
		_next_item_uid += 1
		inv.add(uid, item_id, spot.cell, spot.rot)
		refresh_items(p)
	p.world.emit_event("item:added", {"player_id": p.id, "item": String(item_id), "uid": String(uid)})
	return uid


# 拿掉道具（背包或武器格子裡的）；背包裡的屍體也走這裡
func remove_item(p: Player, uid: StringName) -> void:
	var found := find_item(uid)
	if found.is_empty():
		inventory.remove(uid)
		return
	(found.inv as Inventory).remove(uid)
	refresh_items(p)


# 拿掉所有道具（背包與武器格子裡的；武器、屍體不動）：測試與除錯 F5
func clear_items(p: Player) -> void:
	for where: int in [MAIN, OFF, BAG]:
		var inv := container(where)
		if inv == null:
			continue
		for e: Dictionary in inv.entries.duplicate():
			if not e.has("weapon") and e.id != &"corpse":
				inv.remove(e.uid)
	refresh_items(p)


# 生效的道具 = 鑲在主手與副手格子上的；和 items 比對，新鑲上的套屬性、拿下來的移除屬性與道具效果的狀態
func refresh_items(p: Player) -> void:
	var want := {}
	var parts := {}
	for where: int in [MAIN, OFF]:
		var inv := container(where)
		if inv != null:
			for e: Dictionary in inv.entries:
				want[e.uid] = e.id
				parts[e.uid] = inv.parts_of(e)
	for it: Dictionary in items.duplicate():
		if not want.has(it.uid):
			items.erase(it)
			p.remove_stat_source(it.uid)
			ItemEffects.forget_item(p, it.uid)
		else:
			it.parts = parts[it.uid]   # 同一隻手的格子裡搬位置、換手都會變
	for uid: StringName in want:
		if not items.any(func(it: Dictionary) -> bool: return it.uid == uid):
			items.append({"uid": uid, "id": want[uid], "parts": parts[uid]})
			p.set_stat_source(uid, ItemDefs.stat_mods(want[uid]))
	bond_counts.clear()
	var seen := {}
	for it: Dictionary in items:
		if seen.has(it.id):
			continue
		seen[it.id] = true
		for bond: StringName in ItemDefs.ITEMS[it.id].get("bonds", []):
			bond_counts[bond] = bond_counts.get(bond, 0) + 1


# 把 from 武器上鑲的道具搬走（換下來的武器）：依序試 targets 裡武器的格子、背包；都放不下的留在原本的武器上
# p 不是 null 時，哪裡都放不下的掉在腳下（合成時被吃掉的那把）
func _move_sockets(from: Dictionary, targets: Array[Dictionary], p: Player = null) -> void:
	if from.get("sockets", []).is_empty():
		return
	var src := Inventory.for_weapon(from)
	for e: Dictionary in src.entries.duplicate():
		for inv: Inventory in targets.filter(func(t: Dictionary) -> bool: return not t.is_empty()).map(Inventory.for_weapon) + [inventory]:
			var spot := inv.find_spot(e.id)
			if not spot.is_empty():
				src.remove(e.uid)
				inv.add(e.uid, e.id, spot.cell, spot.rot)
				break
		if p != null and not src.find(e.uid).is_empty():
			src.remove(e.uid)
			p.world.drop_item(e.id, p.pos)


# 撿起隊友的屍體放進背包（占 corpse 形狀的格子、沒有效果）；放不下回傳 false 並發出 inventory:full
func add_corpse(p: Player, owner_peer: int, spot: Dictionary = {}, pickup_id := 0) -> bool:
	if spot.is_empty():
		spot = inventory.find_spot(&"corpse")
	if spot.is_empty():
		_emit_full(p, &"corpse", pickup_id)
		return false
	inventory.add(Player.corpse_uid(owner_peer), &"corpse", spot.cell, spot.rot)
	p.world.emit_event("item:added", {"player_id": p.id, "item": "corpse", "uid": String(Player.corpse_uid(owner_peer))})
	return true


# 客戶端：背包以房主的快照為準（[[uid, id, x, y, rot, 武器], …]）；生效的道具看武器格子，在 sync_weapon_slots 之後同步
func sync_inventory(_p: Player, arr: Array) -> void:
	inventory.entries.clear()
	for a: Array in arr:
		inventory.add(StringName(a[0]), StringName(a[1]), Vector2i(a[2], a[3]), a[4], WeaponDropDefs.from_array(a[5]))


# 客戶端：主手與副手以房主的快照為準（[主手, 副手]，見 WeaponDropDefs.to_array）
func sync_weapon_slots(p: Player, arr: Array) -> void:
	for i in weapon_slots.size():
		weapon_slots[i] = WeaponDropDefs.from_array(arr[i])
	p.apply_active_weapon()


func queue_ops(ops: Array) -> void:
	_ops.append_array(ops)


func clear_ops() -> void:
	_ops.clear()


# 背包操作（InputCmd.inv_ops）：
#   [OP_MOVE, uid, x, y, rot, where?] 搬到 where（BAG 背包、MAIN / OFF 武器格子；沒寫 = 背包）的 (x, y)；武器只能進背包（副手的可以，主手不行）
#   [OP_DROP, uid] 丟到面前的地上；[OP_EQUIP, uid, slot] 武器放進主手 / 副手（_equip_from）；[OP_MERGE, uid_a, uid_b] 把 a 拖到 b 上合成
#   [OP_PICKUP, 地上道具 id, x, y, rot, where?] 撿起按得到 F 的地上道具放到 where 的 (x, y)（已被撿走、太遠、放不下就不動；武器與屍體只能進背包）
func apply_ops(p: Player) -> void:
	for op: Array in _ops:
		var where: int = int(op[5]) if op.size() > 5 else BAG
		if int(op[0]) == InputCmd.OP_PICKUP:
			var ip := p.world.entities.get(int(op[1])) as ItemPickup
			var spot := {"cell": Vector2i(op[2], op[3]), "rot": posmod(int(op[4]), 4)}
			if ip == null or ip.is_removed or not p.world.can_reach(p, ip) or (where != BAG and (ip.is_weapon() or ip.corpse_of != 0)):
				continue
			var inv := container(where)
			if inv != null and inv.fits(ip.item_id, spot.cell, spot.rot):
				take_pickup(p, ip, spot, where)
			continue
		var uid := StringName(op[1])
		match int(op[0]):
			InputCmd.OP_MOVE:
				var w := _find_weapon(uid)
				if w.has("slot"):
					if w.slot == OFF and inventory.fits(w.inst.base, Vector2i(op[2], op[3]), op[4]):
						weapon_slots[w.slot] = {}
						inventory.add(uid, w.inst.base, Vector2i(op[2], op[3]), op[4], w.inst)
						p.apply_active_weapon()
				elif not w.is_empty() or find_item(uid).is_empty():
					inventory.move(uid, Vector2i(op[2], op[3]), op[4])   # 背包裡的武器、屍體
				else:
					_move_item(p, uid, Vector2i(op[2], op[3]), posmod(int(op[4]), 4), where)
			InputCmd.OP_DROP:
				_drop(p, uid)
			InputCmd.OP_EQUIP:
				_equip_from(p, uid, int(op[2]))
			InputCmd.OP_MERGE:
				merge(p, uid, StringName(op[2]))
	_ops.clear()


# 道具搬到 where（背包或某隻手的武器格子）的 cell：同一個容器就是搬位置，不同容器放得下才搬；放不下就不動
func _move_item(p: Player, uid: StringName, cell: Vector2i, rot: int, where: int) -> void:
	var found := find_item(uid)
	var dst := container(where)
	if found.is_empty() or dst == null:
		return
	if found.where == where:
		if dst.move(uid, cell, rot) and where != BAG:
			refresh_items(p)   # 換了部位，發動時機跟著變
		return
	var e: Dictionary = found.entry
	if dst.fits(e.id, cell, rot):
		(found.inv as Inventory).remove(uid)
		dst.add(uid, e.id, cell, rot)
		refresh_items(p)


# 丟到面前的地上：道具移除效果；主手的武器不能丟（主手一定要有武器）
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
