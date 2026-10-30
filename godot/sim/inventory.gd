# 格子容器：背包（D3，ItemDefs.BAG_SIZE 8 × 6 格）與武器格子（Build 改版第 3 步，for_weapon：只有 mask 裡的格子能放）
# 道具依 ItemDefs.SHAPES 的形狀占格、可轉 0 / 90 / 180 / 270 度
# 只管擺放；屬性效果由 Loadout 依 uid 套上（鑲在主手 / 副手的格子才生效）。純資料，客戶端從快照整份覆蓋
class_name Inventory
extends RefCounted

var size: Vector2i = ItemDefs.BAG_SIZE
var entries: Array[Dictionary] = []   # { uid: StringName, id: StringName, cell: Vector2i, rot: int, weapon?: 武器實例（D4，放在背包的武器沒有效果） }
var mask: Dictionary = {}            # 武器格子：能放的格子（WeaponDefs.grid_cells）；空 = size 內每一格都能放（背包）


# 武器實例的格子：entries 直接用實例的 sockets（同一個陣列，改這裡就是改武器上鑲的東西；沒有就建一個空的）
static func for_weapon(inst: Dictionary) -> Inventory:
	var inv := Inventory.new()
	var id: StringName = ItemDefs.ITEMS[inst.base].weapon
	inv.size = WeaponDefs.grid_size(id)
	inv.mask = WeaponDefs.grid_cells(id)
	if not inst.has("sockets"):
		inst["sockets"] = [] as Array[Dictionary]
	inv.entries = inst.sockets
	return inv


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


# 道具碰到的武器部位（WeaponDefs.PARTS 的字元，不重複，依道具格子的順序）；背包沒有部位，回傳 ""
func parts_of(e: Dictionary) -> String:
	var out := ""
	for c in cells_of(e.id, e.rot):
		var part: String = mask.get(e.cell + c, "")
		if part != "" and not out.contains(part):
			out += part
	return out


func find(uid: StringName) -> Dictionary:
	for e in entries:
		if e.uid == uid:
			return e
	return {}


# 每一格被哪個 uid 占用（ignore 的不算）
func occupied(ignore: StringName = &"") -> Dictionary:
	var out := {}
	for e in entries:
		if e.uid == ignore:
			continue
		for c in cells_of(e.id, e.rot):
			out[e.cell + c] = e.uid
	return out


func fits(id: StringName, cell: Vector2i, rot: int, ignore: StringName = &"") -> bool:
	return _fits_cells(occupied(ignore), cells_of(id, rot), cell)


func _fits_cells(taken: Dictionary, cells: Array[Vector2i], at: Vector2i) -> bool:
	for c in cells:
		var p := at + c
		if p.x < 0 or p.y < 0 or p.x >= size.x or p.y >= size.y or taken.has(p) or (not mask.is_empty() and not mask.has(p)):
			return false
	return true


# 第一個放得下的位置：由上到下、由左到右，每格先試不轉、再依序轉 90 / 180 / 270；武器格子先找合部位偏好的（_preferred）；放不下回傳 {}
# ignore：當作那一件不在背包裡（算「拿掉它放不放得下」）。占用表與四個方向的形狀只算一次（suggest_removal 會連叫很多次）
func find_spot(id: StringName, ignore: StringName = &"") -> Dictionary:
	var taken := occupied(ignore)
	var shapes: Array[Array] = []
	for rot in 4:
		shapes.append(cells_of(id, rot))
	var fallback := {}
	for y in size.y:
		for x in size.x:
			for rot in 4:
				if _fits_cells(taken, shapes[rot], Vector2i(x, y)):
					if mask.is_empty() or _preferred(id, shapes[rot], Vector2i(x, y)):
						return {"cell": Vector2i(x, y), "rot": rot}
					if fallback.is_empty():
						fallback = {"cell": Vector2i(x, y), "rot": rot}
	return fallback


# 武器格子的自動擺放偏好：看部位發動的道具要碰到攻擊部位（每次命中都發動）；
# 其他道具不佔攻擊部位、末端、防禦部位（留給觸發道具）。沒有合偏好的位置時 find_spot 用第一個放得下的
func _preferred(id: StringName, cells: Array, at: Vector2i) -> bool:
	var is_trigger := ItemDefs.part_timed_trigger(id) != &""
	for c: Vector2i in cells:
		var part: String = mask[at + c]
		if is_trigger and part == "A":
			return true
		if not is_trigger and part in ["A", "E", "D"]:
			return false
	return not is_trigger


# 放不下 id 時，拿掉哪一件就放得下（有好幾件時挑占格最少的）；本來就放得下、或拿掉一件也不夠時回傳 &""
func suggest_removal(id: StringName) -> StringName:
	if not find_spot(id).is_empty():
		return &""
	var best := &""
	var best_cells := 1 << 20
	for e in entries:
		var n := cells_of(e.id, e.rot).size()
		if n < best_cells and not find_spot(id, e.uid).is_empty():
			best = e.uid
			best_cells = n
	return best


func add(uid: StringName, id: StringName, cell: Vector2i, rot: int, weapon: Dictionary = {}) -> void:
	var e := {"uid": uid, "id": id, "cell": cell, "rot": posmod(rot, 4)}
	if not weapon.is_empty():
		e["weapon"] = weapon
	entries.append(e)


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


# 快照用：[[uid, id, x, y, rot, 武器（WeaponDropDefs.to_array，不是武器為 []）], …]（武器格子裡只有道具，用 sockets_to_array）
func to_array() -> Array:
	var out := []
	for e in entries:
		out.append([String(e.uid), String(e.id), e.cell.x, e.cell.y, e.rot, WeaponDropDefs.to_array(e.get("weapon", {}))])
	return out
