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


func can_use(owner: Player, index: int) -> bool:
	var slot: Variant = slots[index]
	if slot == null or slot.charges == 0:
		return false
	if not owner.world.cooldowns.is_ready(cd_key(index)):
		return false
	return SkillBehaviors.BEHAVIORS[slot.def.behavior].can_use(owner, slot.def)


func use(owner: Player, index: int) -> bool:
	if not can_use(owner, index):
		return false
	var slot: Dictionary = slots[index]
	SkillBehaviors.BEHAVIORS[slot.def.behavior].activate(owner, slot.def)
	if slot.def.mode == &"charges":
		slot.charges -= 1
	var key := cd_key(index)
	owner.world.cooldowns.start(key, slot.def.cooldown)
	owner.world.emit_event("skill:used", {"key": key, "player_id": owner.id})
	return true


# 無法使用時給 HUD 的回饋（空欄位不提示）
func notify_blocked(owner: Player, index: int) -> void:
	if slots[index] != null:
		owner.world.emit_event("skill:onCooldown", {"key": cd_key(index), "player_id": owner.id})
