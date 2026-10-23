# 格子背包（D3）：ItemDefs.BAG_SIZE（8 × 6）格，道具依 ItemDefs.SHAPES 的形狀占格、可轉 0 / 90 / 180 / 270 度
# 只管擺放；屬性效果由 Player 依 uid 套上（放進背包才生效）。純資料，客戶端從快照整份覆蓋
class_name Inventory
extends RefCounted

var size: Vector2i = ItemDefs.BAG_SIZE
var entries: Array[Dictionary] = []   # { uid: StringName, id: StringName, cell: Vector2i, rot: int, weapon?: 武器實例（D4，放在背包的武器沒有效果） }


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
	var taken := occupied(ignore)
	for c in cells_of(id, rot):
		var p := cell + c
		if p.x < 0 or p.y < 0 or p.x >= size.x or p.y >= size.y or taken.has(p):
			return false
	return true


# 第一個放得下的位置：由上到下、由左到右，每格先試不轉、再依序轉 90 / 180 / 270；放不下回傳 {}
func find_spot(id: StringName) -> Dictionary:
	for y in size.y:
		for x in size.x:
			for rot in 4:
				if fits(id, Vector2i(x, y), rot):
					return {"cell": Vector2i(x, y), "rot": rot}
	return {}


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


# 快照用：[[uid, id, x, y, rot, 武器（WeaponDropDefs.to_array，不是武器為 []）], …]
func to_array() -> Array:
	var out := []
	for e in entries:
		out.append([String(e.uid), String(e.id), e.cell.x, e.cell.y, e.rot, WeaponDropDefs.to_array(e.get("weapon", {}))])
	return out
