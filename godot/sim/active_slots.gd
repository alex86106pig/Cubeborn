# 數字鍵 1~5 主動欄位（照搬網頁版 ActiveSlots.js）：裝備、使用條件（CD、次數、技能自訂條件）與觸發
# 不持有玩家（避免循環參照），每次呼叫時傳入
class_name ActiveSlots
extends RefCounted

const SLOT_COUNT := InputCmd.SLOT_COUNT

var slots: Array = []   # 每格 null 或 { def, charges }（charges = -1 表示不限次數）


func _init(ids: Array) -> void:
	for i in SLOT_COUNT:
		var id: Variant = ids[i] if i < ids.size() else null
		if id == null:
			slots.append(null)
			continue
		assert(SkillDefs.SKILLS.has(id), "Unknown skill: %s" % id)
		var def: Dictionary = SkillDefs.SKILLS[id]
		slots.append({"def": def, "charges": def.charges if def.mode == &"charges" else -1})


static func cd_key(index: int) -> String:
	return "player.slot%d" % (index + 1)


# 手上武器帶的技能（火把的插火把，2026-10-27）放在第一個空格；沒有就 -1
func weapon_slot_index(owner: Player) -> int:
	if not owner.weapon.has("slot_skill"):
		return -1
	for i in SLOT_COUNT:
		if slots[i] == null:
			return i
	return -1


# 第 index 格目前的內容：null 或 { def, charges }；武器技能的次數讀手上那把武器實例（WeaponDropDefs.slot_charges）
func get_slot(owner: Player, index: int) -> Variant:
	if slots[index] != null:
		return slots[index]
	if index != weapon_slot_index(owner):
		return null
	return {"def": SkillDefs.SKILLS[owner.weapon.slot_skill], "charges": WeaponDropDefs.slot_charges(owner.active_weapon())}


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
	SkillBehaviors.BEHAVIORS[slot.def.behavior].activate(owner, slot.def)
	if slot.def.get("weapon_charges", false):
		owner.active_weapon()["slot_charges"] = slot.charges - 1   # 次數跟著武器（丟掉、給隊友都帶著）
	elif slot.def.mode == &"charges":
		slot.charges -= 1
	var key := cd_key(index)
	owner.world.cooldowns.start(owner.cd(key), slot.def.cooldown * owner.stats.value(&"cooldown"))
	owner.world.emit_event("skill:used", {"key": key, "player_id": owner.id})
	return true


# 無法使用時給 HUD 的回饋（空欄位不提示）
func notify_blocked(owner: Player, index: int) -> void:
	if get_slot(owner, index) != null:
		owner.world.emit_event("skill:onCooldown", {"key": cd_key(index), "player_id": owner.id})
