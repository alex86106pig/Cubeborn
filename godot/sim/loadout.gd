# 玩家的裝備與背包（2026-10-25 從 Player 拆出來）：裝備欄 2 格（D4）、背包擺放（D3，Inventory）、生效的道具、
# 背包操作（InputCmd.inv_ops）、撿起武器 / 道具 / 屍體、合成、丟棄
# 規則：只有手上那把武器的詞條生效；道具放進背包就生效；手上至少留一把武器；背包裡的武器、屍體沒有效果
# 不存 Player（Player 持有 Loadout，反過來存會變成循環參照）：要發事件、套屬性、換招式時由呼叫端傳入 p
class_name Loadout
extends RefCounted

var weapon_slots: Array[Dictionary] = [{}, {}]   # 裝備欄：武器實例（WeaponDropDefs）或 {}
var active_slot := 0
var items: Array[Dictionary] = []     # 背包裡生效的道具實例 { uid, id }；uid 同時是屬性加成的來源名稱
var inventory := Inventory.new()       # 背包的擺放；items 與它同步
var _next_item_uid := 1
var _ops: Array = []                   # 本步收到的背包操作（InputCmd.inv_ops），只在權威端執行


func active_weapon() -> Dictionary:
	return weapon_slots[active_slot]


# 手上武器稀有度的範圍倍率（揮砍距離、魔彈射程）
func weapon_range_mul() -> float:
	var inst := active_weapon()
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


# Q / 滑鼠滾輪（D4）：換到另一格裝備欄的武器；另一格是空的就不換
func swap(p: Player) -> void:
	var other := 1 - active_slot
	if not weapon_slots[other].is_empty():
		active_slot = other
		p.apply_active_weapon()


# 把手上這格換成一把新的白色武器（開場、--weapon、測試與除錯用；正式取得武器走 add_weapon）
func equip_new(p: Player, id: StringName) -> void:
	assert(WeaponDefs.WEAPONS.has(id), "Unknown weapon: %s" % id)
	weapon_slots[active_slot] = {"uid": p.world.new_weapon_uid(), "base": id, "rarity": &"white", "affixes": [] as Array[StringName]}
	p.apply_active_weapon()


# 撿到武器（D4）：裝備欄有空先放裝備欄（不換手上的），滿了放背包；都放不下回傳 false、發出 inventory:full
func add_weapon(p: Player, inst: Dictionary) -> bool:
	for i in weapon_slots.size():
		if weapon_slots[i].is_empty():
			weapon_slots[i] = inst
			p.world.emit_event("weapon:added", {"player_id": p.id, "uid": String(inst.uid), "slot": i})
			return true
	var spot := inventory.find_spot(inst.base)
	if spot.is_empty():
		p.world.emit_event("inventory:full", {"player_id": p.id, "item": String(inst.base)})
		return false
	inventory.add(inst.uid, inst.base, spot.cell, spot.rot, inst)
	p.world.emit_event("weapon:added", {"player_id": p.id, "uid": String(inst.uid), "slot": -1})
	return true


# 依 uid 找武器在哪：{ slot: 0 / 1 } 或 { bag: 背包條目 }；找不到回傳 {}
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


# 武器放進裝備欄 slot：從另一格來就互換；從背包來時原本那把放回背包（放不下就不換）
func _equip_from(p: Player, uid: StringName, slot: int) -> bool:
	var src := _find_weapon(uid)
	if src.is_empty() or slot < 0 or slot >= weapon_slots.size():
		return false
	if src.has("slot"):
		var tmp: Dictionary = weapon_slots[slot]
		weapon_slots[slot] = weapon_slots[src.slot]
		weapon_slots[src.slot] = tmp
	else:
		var old: Dictionary = weapon_slots[slot]
		inventory.remove(uid)
		if not old.is_empty():
			var spot := inventory.find_spot(old.base)
			if spot.is_empty():
				inventory.add(uid, src.bag.id, src.bag.cell, src.bag.rot, src.inst)
				return false
			inventory.add(old.uid, old.base, spot.cell, spot.rot, old)
		weapon_slots[slot] = src.inst
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
	if a.has("slot") and b.has("bag") and equipped_count() <= 1:
		# 手上唯一的一把拖到背包的武器上：合成結果留在裝備欄（手上不能沒有武器），背包那把消失
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


# 道具放進背包（D3）：自動放到第一個放得下的位置，放進去就生效（屬性效果以實例 uid 為來源套上）；武器則直接換上
# 同一個道具拿兩個就是兩個實例、加成相加。背包放不下時回傳 &""、發出 inventory:full
func add_item(p: Player, item_id: StringName) -> StringName:
	assert(ItemDefs.ITEMS.has(item_id), "Unknown item: %s" % item_id)
	var def: Dictionary = ItemDefs.ITEMS[item_id]
	var uid := &""
	if def.kind == &"weapon":
		equip_new(p, def.weapon)
	else:
		var spot := inventory.find_spot(item_id)
		if spot.is_empty():
			p.world.emit_event("inventory:full", {"player_id": p.id, "item": String(item_id)})
			return &""
		uid = StringName("item_%d" % _next_item_uid)
		_next_item_uid += 1
		inventory.add(uid, item_id, spot.cell, spot.rot)
		items.append({"uid": uid, "id": item_id})
		p.set_stat_source(uid, ItemDefs.stat_mods(item_id))
	p.world.emit_event("item:added", {"player_id": p.id, "item": String(item_id), "uid": String(uid)})
	return uid


func remove_item(p: Player, uid: StringName) -> void:
	inventory.remove(uid)
	for i in items.size():
		if items[i].uid == uid:
			items.remove_at(i)
			p.remove_stat_source(uid)
			ItemEffects.forget_item(p, uid)
			return


func clear_items(p: Player) -> void:
	for it: Dictionary in items.duplicate():
		remove_item(p, it.uid)


# 撿起隊友的屍體放進背包（占 corpse 形狀的格子、沒有效果）；放不下回傳 false 並發出 inventory:full
func add_corpse(p: Player, owner_peer: int) -> bool:
	var spot := inventory.find_spot(&"corpse")
	if spot.is_empty():
		p.world.emit_event("inventory:full", {"player_id": p.id, "item": "corpse"})
		return false
	inventory.add(Player.corpse_uid(owner_peer), &"corpse", spot.cell, spot.rot)
	p.world.emit_event("item:added", {"player_id": p.id, "item": "corpse", "uid": String(Player.corpse_uid(owner_peer))})
	return true


# 客戶端：背包以房主的快照為準（[[uid, id, x, y, rot], …]），增減的道具同步加減屬性（本機預測移動要用到移速等）
func sync_inventory(p: Player, arr: Array) -> void:
	var keep := {}
	inventory.entries.clear()
	for a: Array in arr:
		var uid := StringName(a[0])
		var w := WeaponDropDefs.from_array(a[5])
		inventory.add(uid, StringName(a[1]), Vector2i(a[2], a[3]), a[4], w)
		if w.is_empty() and ItemDefs.ITEMS[StringName(a[1])].kind == &"item":   # 背包裡的武器、屍體沒有效果
			keep[uid] = StringName(a[1])
	for it: Dictionary in items.duplicate():
		if not keep.has(it.uid):
			items.erase(it)
			p.remove_stat_source(it.uid)
			ItemEffects.forget_item(p, it.uid)
	for uid: StringName in keep:
		if not items.any(func(it: Dictionary) -> bool: return it.uid == uid):
			items.append({"uid": uid, "id": keep[uid]})
			p.set_stat_source(uid, ItemDefs.stat_mods(keep[uid]))


# 客戶端：裝備欄以房主的快照為準（[武器, 武器]，見 WeaponDropDefs.to_array）；手上哪一格由呼叫端決定要不要同步
func sync_weapon_slots(p: Player, arr: Array, p_active: int) -> void:
	for i in weapon_slots.size():
		weapon_slots[i] = WeaponDropDefs.from_array(arr[i])
	active_slot = p_active
	p.apply_active_weapon()


func queue_ops(ops: Array) -> void:
	_ops.append_array(ops)


func clear_ops() -> void:
	_ops.clear()


# 背包操作（InputCmd.inv_ops）：
#   [OP_MOVE, uid, x, y, rot] 搬到背包 (x, y)（道具或武器；武器可以從裝備欄搬進背包，但手上至少留一把）
#   [OP_DROP, uid] 丟到面前的地上；[OP_EQUIP, uid, slot] 武器放進裝備欄；[OP_MERGE, uid_a, uid_b] 把 a 拖到 b 上合成
func apply_ops(p: Player) -> void:
	for op: Array in _ops:
		var uid := StringName(op[1])
		match int(op[0]):
			InputCmd.OP_MOVE:
				var w := _find_weapon(uid)
				if w.has("slot"):
					if equipped_count() > 1 and inventory.fits(w.inst.base, Vector2i(op[2], op[3]), op[4]):
						weapon_slots[w.slot] = {}
						inventory.add(uid, w.inst.base, Vector2i(op[2], op[3]), op[4], w.inst)
						p.apply_active_weapon()
				else:
					inventory.move(uid, Vector2i(op[2], op[3]), op[4])
			InputCmd.OP_DROP:
				_drop(p, uid)
			InputCmd.OP_EQUIP:
				_equip_from(p, uid, int(op[2]))
			InputCmd.OP_MERGE:
				merge(p, uid, StringName(op[2]))
	_ops.clear()


# 丟到面前的地上：道具移除效果；武器從裝備欄丟時手上至少留一把
func _drop(p: Player, uid: StringName) -> void:
	var at := p.pos + MathUtil.dir_from_angle(p.facing) * LootDefs.DROP_DISTANCE
	var w := _find_weapon(uid)
	if not w.is_empty():
		if w.has("slot") and equipped_count() <= 1:
			return
		_take_weapon(w)
		p.apply_active_weapon()
		p.world.drop_weapon(w.inst, at)
		return
	var entry := inventory.find(uid)
	if entry.is_empty():
		return
	remove_item(p, uid)
	if entry.id == &"corpse":
		p.world.drop_corpse(String(uid).get_slice("_", 1).to_int(), at)
	else:
		p.world.drop_item(entry.id, at)
