# 格子容器：倉庫（ItemDefs.BAG_SIZE，什麼都放、沒有效果、每格一件不管形狀）、主袋（BagDefs.MAIN_SIZE，只放數值道具）、
# 觸發袋（for_bag：袋子實例的 length × depth，放道具與技能；裡面的數值道具一樣生效）
# 主袋與袋子裡的道具依 ItemDefs.SHAPES 的形狀占格、可轉 0 / 90 / 180 / 270 度。只管擺放；效果由 Loadout 依 uid 套上。純資料，客戶端從快照整份覆蓋
class_name Inventory
extends RefCounted

const STORAGE := &"storage"
const CORE := &"core"
const BAG := &"bag"
const ONE_CELL: Array[Vector2i] = [Vector2i.ZERO]

var size: Vector2i = ItemDefs.BAG_SIZE
var entries: Array[Dictionary] = []   # { uid: StringName, id: StringName, cell: Vector2i, rot: int, weapon?: 武器實例, bag?: 袋子實例, charges?: int }
var mode: StringName = STORAGE


static func core() -> Inventory:
	var inv := Inventory.new()
	inv.size = BagDefs.MAIN_SIZE
	inv.mode = CORE
	return inv


# 袋子實例的格子：entries 直接用實例的 entries（同一個陣列，改這裡就是改袋子裡的東西）
static func for_bag(bag: Dictionary) -> Inventory:
	var inv := Inventory.new()
	inv.size = Vector2i(bag.length, bag.depth)
	inv.mode = BAG
	inv.entries = bag.entries
	return inv


# 這種容器收不收這個東西：主袋只收數值道具；袋子收數值、效果、技能、修飾；倉庫都收（武器、袋子、屍體只進倉庫）
func accepts(id: StringName) -> bool:
	match mode:
		CORE:
			return ItemDefs.role_of(id) == ItemDefs.ROLE_STAT
		BAG:
			return ItemDefs.role_of(id) in [ItemDefs.ROLE_STAT, ItemDefs.ROLE_EFFECT, ItemDefs.ROLE_SKILL, ItemDefs.ROLE_MOD]   # 數值放袋子也生效（第 8 步 a）
	return true


# 道具轉 rot 次 90 度後占的格子（以左上角為 (0, 0)）
static func cells_of(id: StringName, rot: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in ItemDefs.SHAPES[ItemDefs.ITEMS[id].shape]:
		var p := c
		for i in posmod(rot, 4):
			p = Vector2i(-p.y, p.x)
		out.append(p)
	var lo := Vector2i(1 << 20, 1 << 20)
	for p in out:
		lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
	for i in out.size():
		out[i] -= lo
	return out


# 在這個容器裡占的格子：倉庫一律一格，其他照形狀
func cells(id: StringName, rot: int) -> Array[Vector2i]:
	return ONE_CELL if mode == STORAGE else cells_of(id, rot)


# 修飾的透明格（ItemDefs.MOD_CLEAR_INDEX，只在袋子裡算；倉庫一格、主袋不收修飾）：可以和技能疊在同一格
func clear_cells(id: StringName, rot: int) -> Array[Vector2i]:
	if mode != BAG or not ItemDefs.is_mod(id):
		return []
	return [cells_of(id, rot)[ItemDefs.MOD_CLEAR_INDEX]]


# 實心格（羈絆只算這些）
func solid_cells(id: StringName, rot: int) -> Array[Vector2i]:
	var clear := clear_cells(id, rot)
	return cells(id, rot).filter(func(c: Vector2i) -> bool: return not clear.has(c))


func find(uid: StringName) -> Dictionary:
	for e in entries:
		if e.uid == uid:
			return e
	return {}


# 每一格被哪個 uid 占用（ignore 的不算；透明格和技能疊著時算技能）
func occupied(ignore: StringName = &"") -> Dictionary:
	var l := _layers(ignore)
	var out: Dictionary = l.clear.duplicate()
	out.merge(l.solid, true)
	return out


# 占用分層：solid 實心格 → uid、clear 透明格 → uid、skill 實心格是技能的格子
func _layers(ignore: StringName) -> Dictionary:
	var solid := {}
	var clear := {}
	var skill := {}
	for e in entries:
		if e.uid == ignore:
			continue
		var cl := clear_cells(e.id, e.rot)
		var sk := mode == BAG and ItemDefs.is_coverable(e.id)
		for c in cells(e.id, e.rot):
			var p: Vector2i = e.cell + c
			if cl.has(c):
				clear[p] = e.uid
			else:
				solid[p] = e.uid
				if sk:
					skill[p] = true
	return {"solid": solid, "clear": clear, "skill": skill}


func fits(id: StringName, cell: Vector2i, rot: int, ignore: StringName = &"") -> bool:
	return accepts(id) and _fits_at(_layers(ignore), cells(id, rot), clear_cells(id, rot), mode == BAG and ItemDefs.is_coverable(id), cell)


# 放得下：每一格在範圍內；透明格只能放在空格或技能上（不跟別的透明格疊）；實心格要空著，技能可以放在透明格底下
func _fits_at(l: Dictionary, cs: Array[Vector2i], cl: Array[Vector2i], is_skill: bool, at: Vector2i) -> bool:
	for c in cs:
		var p := at + c
		if p.x < 0 or p.y < 0 or p.x >= size.x or p.y >= size.y:
			return false
		if cl.has(c):
			if l.clear.has(p) or (l.solid.has(p) and not l.skill.has(p)):
				return false
		elif l.solid.has(p) or (l.clear.has(p) and not is_skill):
			return false
	return true


# 蓋在這個技能上的修飾（任何一個透明格落在技能的格子上）
func mods_on(skill: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if mode != BAG:
		return out
	var mine := {}
	for c in cells(skill.id, skill.rot):
		mine[skill.cell + c] = true
	for e in entries:
		for c in clear_cells(e.id, e.rot):
			if mine.has(e.cell + c):
				out.append(e)
				break
	return out


# 這個修飾蓋住的技能（沒蓋到回傳 {}）
func covered_by(mod: Dictionary) -> Dictionary:
	var l := _layers(mod.uid)
	for c in clear_cells(mod.id, mod.rot):
		var p: Vector2i = mod.cell + c
		if l.skill.has(p):
			return find(l.solid[p])
	return {}


# 修飾放得下、而且透明格蓋在 wants(技能 id) 為 true 的技能上的第一個位置；沒有回傳 {}
func find_cover_spot(id: StringName, wants: Callable) -> Dictionary:
	if not accepts(id) or mode != BAG:
		return {}
	var l := _layers(&"")
	for y in size.y:
		for x in size.x:
			for rot in 4:
				var at := Vector2i(x, y)
				var cl := clear_cells(id, rot)
				if not _fits_at(l, cells(id, rot), cl, false, at):
					continue
				for c in cl:
					var p := at + c
					if l.skill.has(p) and wants.call(find(l.solid[p]).id):
						return {"cell": at, "rot": rot}
	return {}


# 第一個放得下的位置：由上到下、由左到右，每格先試不轉、再依序轉 90 / 180 / 270；放不下（或不收這種東西）回傳 {}
# ignore：當作那一件不在裡面（算「拿掉它放不放得下」）。占用表與四個方向的形狀只算一次（suggest_removal 會連叫很多次）
func find_spot(id: StringName, ignore: StringName = &"") -> Dictionary:
	if not accepts(id):
		return {}
	var l := _layers(ignore)
	var shapes: Array[Array] = []
	var clears: Array[Array] = []
	for rot in 4:
		shapes.append(cells(id, rot))
		clears.append(clear_cells(id, rot))
	var sk := mode == BAG and ItemDefs.is_coverable(id)
	for y in size.y:
		for x in size.x:
			for rot in 4:
				if _fits_at(l, shapes[rot], clears[rot], sk, Vector2i(x, y)):
					return {"cell": Vector2i(x, y), "rot": rot}
	return {}


# 放不下 id 時，拿掉哪一件就放得下（有好幾件時挑占格最少的）；本來就放得下、或拿掉一件也不夠時回傳 &""
func suggest_removal(id: StringName) -> StringName:
	if not accepts(id) or not find_spot(id).is_empty():
		return &""
	var best := &""
	var best_cells := 1 << 20
	for e in entries:
		var n := cells(e.id, e.rot).size()
		if n < best_cells and not find_spot(id, e.uid).is_empty():
			best = e.uid
			best_cells = n
	return best


func add(uid: StringName, id: StringName, cell: Vector2i, rot: int, extra: Dictionary = {}) -> Dictionary:
	var e := {"uid": uid, "id": id, "cell": cell, "rot": posmod(rot, 4)}
	e.merge(extra)
	entries.append(e)
	return e


func remove(uid: StringName) -> void:
	for i in entries.size():
		if entries[i].uid == uid:
			entries.remove_at(i)
			return


# 搬到新位置 / 新方向；放不下就不動，回傳 false
func move(uid: StringName, cell: Vector2i, rot: int) -> bool:
	var e := find(uid)
	if e.is_empty() or not fits(e.id, cell, rot, uid):
		return false
	e.cell = cell
	e.rot = posmod(rot, 4)
	return true


# 快照用：[[uid, id, x, y, rot, 武器（WeaponDropDefs.to_array，不是武器為 []）, 袋子（BagDefs.to_array，不是袋子為 []）], …]
func to_array() -> Array:
	var out := []
	for e in entries:
		out.append([String(e.uid), String(e.id), e.cell.x, e.cell.y, e.rot, WeaponDropDefs.to_array(e.get("weapon", {})),
			BagDefs.to_array(e.bag) if e.has("bag") else []])
	return out


func sync_from(arr: Array) -> void:
	entries.clear()
	for a: Array in arr:
		var extra := {}
		var w := WeaponDropDefs.from_array(a[5])
		if not w.is_empty():
			extra["weapon"] = w
		if a.size() > 6 and not (a[6] as Array).is_empty():
			extra["bag"] = BagDefs.from_array(a[6])
		add(StringName(a[0]), StringName(a[1]), Vector2i(a[2], a[3]), a[4], extra)
