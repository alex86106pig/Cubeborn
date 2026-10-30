# 技能欄（Build 改版第 7 步）：數字鍵 1~4 = 主手、副手寶石座上的技能（主手先、由上到下、由左到右），Q = 治療藥水
# 使用條件（CD、次數、技能自訂條件）與觸發；技能的等級（Player.skill_levels）與相鄰的輔助道具在這裡算好，交給 SkillBehaviors
# 不持有玩家（避免循環參照），每次呼叫時傳入
class_name ActiveSlots
extends RefCounted

const SLOT_COUNT := InputCmd.SLOT_COUNT
const GEM_SLOTS := 4                   # 數字鍵 1~4
const HEAL_INDEX := GEM_SLOTS          # Q
const KEY_LABELS: Array[String] = ["1", "2", "3", "4", "Q"]

var heal := {"def": SkillDefs.SKILLS.heal, "charges": SkillDefs.SKILLS.heal.charges}
var _gems: Array[Dictionary] = []      # gems() 的結果（每次重算，重複用同一個陣列）


static func cd_key(index: int) -> String:
	return "player.slot%d" % (index + 1)


# 寶石座上的技能，依順序：[{ id, def, where, inst, entry }]
func gems(owner: Player) -> Array[Dictionary]:
	_gems.clear()
	for where: int in [Loadout.MAIN, Loadout.OFF]:
		var inst: Dictionary = owner.weapon_slots[where]
		if inst.is_empty():
			continue
		var list: Array = inst.get("sockets", []).filter(func(e: Dictionary) -> bool: return ItemDefs.is_skill(e.id))
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.cell.y < b.cell.y or (a.cell.y == b.cell.y and a.cell.x < b.cell.x))
		for e: Dictionary in list:
			_gems.append({"id": e.id, "def": SkillDefs.SKILLS[e.id], "where": where, "inst": inst, "entry": e})
	return _gems


# 第 index 格目前的內容：null 或 { def, charges, id?, level? }（charges = -1 表示不限次數）
func get_slot(owner: Player, index: int) -> Variant:
	if index == HEAL_INDEX:
		return heal
	var list := gems(owner)
	if index >= list.size():
		return null
	var g: Dictionary = list[index]
	var charges := -1
	if g.def.get("weapon_charges", false):
		charges = WeaponDropDefs.slot_charges(g.inst)
	return {"def": g.def, "charges": charges, "id": g.id, "level": owner.skill_levels.get(g.id, 1), "gem": g}


# 技能欄的內容有沒有變（技能欄介面重建用）
func signature(owner: Player) -> String:
	var ids := []
	for g in gems(owner):
		ids.append(g.id)
	return ",".join(ids)


func can_use(owner: Player, index: int) -> bool:
	var slot: Variant = get_slot(owner, index)
	if slot == null or slot.charges == 0:
		return false
	if not owner.world.cooldowns.is_ready(owner.cd(cd_key(index))):
		return false
	return SkillBehaviors.BEHAVIORS[slot.def.behavior].can_use(owner, slot.def)


func use(owner: Player, index: int) -> bool:
	if not can_use(owner, index):
		return false
	var slot: Dictionary = get_slot(owner, index)
	var ctx := cast_context(owner, slot)
	SkillBehaviors.cast(owner, slot.def, ctx)
	if slot.def.get("weapon_charges", false):
		slot.gem.inst["slot_charges"] = slot.charges - 1   # 次數跟著武器（丟掉、給隊友都帶著）
	elif index == HEAL_INDEX:
		heal.charges -= 1
	var key := cd_key(index)
	var cd: float = slot.def.cooldown * owner.stats.value(&"cooldown") * (1.0 - SkillDefs.LEVEL.cooldown * (slot.get("level", 1) - 1))
	owner.world.cooldowns.start(owner.cd(key), cd)
	owner.world.emit_event("skill:used", {"key": key, "player_id": owner.id})
	return true


# 這次施放的參數：等級的傷害倍率、相鄰輔助道具（標籤相符的才算）的效果
static func cast_context(owner: Player, slot: Dictionary) -> Dictionary:
	var ctx := {"mul": 1.0 + SkillDefs.LEVEL.damage * (slot.get("level", 1) - 1), "area": 1.0, "type": slot.def.get("damage_type", &"phys"), "split": false}
	if slot.has("gem"):
		for sup: Dictionary in supports_of(owner, slot.gem):
			match sup.mode:
				&"split":
					ctx.split = true
				&"extend":
					ctx.area = 1.5
				&"fire", &"cold":
					ctx.type = sup.mode
	return ctx


# 貼著這個寶石座（上下左右）、標籤和技能相符的輔助道具效果
static func supports_of(owner: Player, gem: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tags: Array = gem.def.get("tags", [])
	var cell: Vector2i = gem.entry.cell
	var inv := owner.loadout.container(gem.where)
	if inv == null:
		return out
	for e: Dictionary in inv.entries:
		var sup := ItemDefs.support_of(e.id)
		if sup.is_empty() or not (sup.tags as Array).any(func(t: StringName) -> bool: return tags.has(t)):
			continue
		for c in Inventory.cells_of(e.id, e.rot):
			if (e.cell + c - cell).abs().x + (e.cell + c - cell).abs().y == 1:
				out.append(sup)
				break
	return out


# 無法使用時給 HUD 的回饋（空欄位不提示）
func notify_blocked(owner: Player, index: int) -> void:
	if get_slot(owner, index) != null:
		owner.world.emit_event("skill:onCooldown", {"key": cd_key(index), "player_id": owner.id})
