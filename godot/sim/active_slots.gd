# 技能欄：數字鍵 = 接在主袋上方的按鍵袋（由左到右，Loadout.key_bags；最多 BagDefs.BAGS.key.max 個），Q = 治療藥水
# 按下數字鍵：那個按鍵袋裡的效果與技能一起放（BagTriggers.run_bag）；技能欄顯示袋子裡第一個技能
# 技能的使用條件（魔力、次數、技能自訂條件）、等級（Player.skill_levels）、同一袋修飾的效果與耗魔在這裡算，交給 SkillBehaviors
# 觸發袋裡的技能也走這裡（BagTriggers.cast_skill）。不持有玩家（避免循環參照），每次呼叫時傳入
class_name ActiveSlots
extends RefCounted

const SLOT_COUNT := InputCmd.SLOT_COUNT
const GEM_SLOTS := 4                   # 數字鍵 1~4
const HEAL_INDEX := GEM_SLOTS          # Q
const DICE_INDEX := SLOT_COUNT         # 骰子模式的右鍵（DiceRun.slot_for）：走同一套前搖 / 施放，冷卻記在 player.special（技能欄右鍵格的遮罩）
const KEY_LABELS: Array[String] = ["1", "2", "3", "4", "Q"]

const PHANTOM_ID := &"phantom_support"

var heal := {"def": SkillDefs.SKILLS.heal, "charges": SkillDefs.SKILLS.heal.charges}


static func cd_key(index: int) -> String:
	return "player.special" if index == DICE_INDEX else "player.slot%d" % (index + 1)


# 袋子裡的一個技能：{ def, id, level, bag, entry, charges, fits, phantom }（charges = -1 不限次數；次數制的技能次數記在袋子條目上，換關補滿）
# fits：手上的武器放得出來（SkillDefs.fits_weapon），或不符但蓋著幻影；phantom：不符、靠幻影放（傷害 × PHANTOM_MUL、幻影的耗魔才算）
static func slot_of(owner: Player, b: Dictionary, e: Dictionary) -> Dictionary:
	var def: Dictionary = SkillDefs.SKILLS[e.id]
	var charges: int = e.get("charges", def.charges) if def.get("mode", &"") == &"charges" else -1
	var fits := SkillDefs.fits_weapon(def, owner.weapon)
	var phantom := not fits and mod_ids_on(b, e).has(PHANTOM_ID)
	return {"def": def, "id": e.id, "level": owner.skill_levels.get(e.id, 1), "bag": b, "entry": e, "charges": charges,
		"fits": fits or phantom, "phantom": phantom}


# 第 index 格目前的內容：null（沒有那個按鍵袋）或 { def, charges, id?, level?, bag }；技能欄畫袋子裡第一個技能，
# 只有效果的袋子畫第一個效果（def 是 { icon, name }）
func get_slot(owner: Player, index: int) -> Variant:
	if index == HEAL_INDEX:
		return heal
	if owner.world.dice != null:   # 骰子模式：數字鍵沒有技能，右鍵是骰到的那招
		return owner.world.dice.slot_for(owner) if index == DICE_INDEX else null
	var keys := owner.loadout.key_bags()
	if index >= keys.size():
		return null
	var b: Dictionary = keys[index]
	var list := BagTriggers.contents(b)
	for e in list:
		if ItemDefs.is_skill(e.id) and SkillDefs.SKILLS[e.id].behavior != &"bag_rule":   # 回響、共鳴、血契不畫在技能欄
			return slot_of(owner, b, e)
	for e in list:
		if ItemDefs.role_of(e.id) == ItemDefs.ROLE_EFFECT:
			return {"def": {"icon": "✦", "name": ItemDefs.ITEMS[e.id].name}, "charges": -1, "bag": b, "id": e.id, "effect": e.id}
	return null


# 技能欄的內容有沒有變（技能欄介面重建用）
func signature(owner: Player) -> String:
	var ids := []
	for b in owner.loadout.key_bags():
		ids.append(String(b.uid))
		for e in BagTriggers.contents(b):
			ids.append(String(e.id))
	return ",".join(ids)


# 能不能按：藥水照次數；按鍵袋要有至少一個放得出來的東西（技能照條件、效果看魔力）
func can_use(owner: Player, index: int) -> bool:
	var slot: Variant = get_slot(owner, index)
	if slot == null or slot.charges == 0:
		return false
	if not owner.world.cooldowns.is_ready(owner.cd(cd_key(index))):
		return false
	if index == HEAL_INDEX:
		return SkillBehaviors.BEHAVIORS[slot.def.behavior].can_use(owner, slot.def)
	if index == DICE_INDEX:
		return can_cast(owner, slot)
	var was_paying := owner.pay_with_hp
	owner.pay_with_hp = BagDefs.has_rule(slot.bag, &"blood_pact")   # 血契的袋子看生命夠不夠
	var ok := false
	for e in BagTriggers.contents(slot.bag):
		if ItemDefs.is_skill(e.id) and can_cast(owner, slot_of(owner, slot.bag, e)):
			ok = true
		elif ItemDefs.role_of(e.id) == ItemDefs.ROLE_EFFECT and owner.has_mana(BagTriggers.effect_cost(slot.bag, e)):
			ok = true
		if ok:
			break
	owner.pay_with_hp = was_paying
	return ok


# 按鍵袋帶頭的戰技（BagTriggers.lead_art）：按下時角色先做它的前搖（PlayerStates.UseItem），做完才 use；不是戰技帶頭、或放不出來回傳 &""
func lead_art(owner: Player, index: int) -> StringName:
	if index == HEAL_INDEX:
		return &""
	if index == DICE_INDEX:
		var slot: Variant = get_slot(owner, index)
		return slot.id if slot != null and SkillDefs.cast_windup(slot.id) > 0.0 else &""
	var keys := owner.loadout.key_bags()
	return BagTriggers.lead_art(owner, keys[index]) if index < keys.size() else &""


# served：帶頭那招戰技的前搖已經由動作層做完了（lead_art 的 id），這次直接出判定
func use(owner: Player, index: int, served: StringName = &"") -> bool:
	if not can_use(owner, index):
		return false
	var slot: Dictionary = get_slot(owner, index)
	var key := cd_key(index)
	if index == HEAL_INDEX:
		SkillBehaviors.cast(owner, slot.def, {"mul": 1.0, "area": 1.0, "type": &"phys", "split": false})
		heal.charges -= 1
		owner.world.cooldowns.start(owner.cd(key), slot.def.cooldown)   # 藥水：次數制，冷卻只是防連按
	elif index == DICE_INDEX:
		cast(owner, slot, null, slot.id == served)
		owner.world.cooldowns.start(owner.cd(key), owner.world.dice.cooldown_for(owner))
	else:
		if owner.world.is_authority:
			BagTriggers.run_bag(owner.world, owner, slot.bag, null, 0.0, false, served)
		else:
			_predict(owner, slot.bag, served)
		owner.world.cooldowns.start(owner.cd(key), Config.MANA.cast_gap)
	owner.world.emit_event("skill:used", {"key": key, "player_id": owner.id})
	return true


# 客戶端的本機預測：只放技能的位移（衝刺、瞬移、後跳）與耗魔，效果與傷害等房主
func _predict(owner: Player, b: Dictionary, served: StringName = &"") -> void:
	for e in BagTriggers.contents(b):
		if ItemDefs.is_skill(e.id):
			var slot := slot_of(owner, b, e)
			if can_cast(owner, slot):
				cast(owner, slot, null, e.id == served)
			served = &""


# target：觸發袋的目標（命中、擊殺、受傷）；按鍵與沒有目標的袋子是 null
static func can_cast(owner: Player, slot: Dictionary, target: Entity = null) -> bool:
	if slot.charges == 0 or not slot.get("fits", true):
		return false
	if slot.def.has("mana") and not slot.get("free", false) and not owner.has_mana(mana_cost(owner, slot)):
		return false
	var behavior: SkillBehaviors.Behavior = SkillBehaviors.BEHAVIORS[slot.def.behavior]
	return behavior.can_use(owner, slot.def) if target == null else behavior.can_use_on(owner, slot.def, target)


# 放一個技能（呼叫端先確認 can_cast）：扣魔力、次數
# wound_up：這招的前搖已經做完（動作從前搖開始時就在播了）；沒做前搖直接放的（回響再放的那次）動作從出手那一刻接著播
static func cast(owner: Player, slot: Dictionary, target: Entity = null, wound_up := false) -> void:
	var ctx := cast_context(owner, slot)
	if target != null:
		SkillBehaviors.aim_at(owner, ctx, target)
	Combat.scoped(ctx.credit, func() -> void: SkillBehaviors.cast(owner, slot.def, ctx))
	# 戰技：角色做這招的動作（新放的蓋掉還沒做完的）；被自動觸發、在命中點出的那幾招不做（SkillDefs.trigger_at）
	if SkillDefs.poses_on_cast(slot.id, target != null) and not (wound_up and owner.skill_pose == slot.id):
		owner.start_skill_pose(slot.id, SkillDefs.cast_windup(slot.id))
	if slot.charges > 0:
		slot.entry["charges"] = slot.charges - 1
	if slot.def.has("mana") and not slot.get("free", false):   # free：骰子模式的右鍵用冷卻、不耗魔
		owner.spend_mana(mana_cost(owner, slot))


# 這個技能放一次要多少魔力（含等級、耗魔屬性、同一袋的修飾）；不耗魔的是 0
static func mana_cost(owner: Player, slot: Dictionary) -> float:
	var cost := owner.mana_cost_of(slot.def, slot.get("level", 1))
	if slot.has("bag"):
		cost *= support_mana_mul(slot)
	return cost


# 蓋在技能上的修飾的耗魔倍率（相乘）：一般修飾每顆 × (1 + 道具強度 power × SkillDefs.SUPPORT_MANA)，有 mana_mul 的（節能）× mana_mul
static func support_mana_mul(slot: Dictionary) -> float:
	return mods_mana_mul(support_ids(slot))


# 一串修飾的耗魔倍率（相乘；技能與效果共用）
static func mods_mana_mul(ids: Array[StringName]) -> float:
	var mul := 1.0
	for id in ids:
		var sup := ItemDefs.support_of(id)
		mul *= sup.mana_mul if sup.has("mana_mul") else 1.0 + ItemDefs.ITEMS[id].power * SkillDefs.SUPPORT_MANA
	return mul


# 這次施放的參數：等級 × 稀有度的傷害倍率 × 袋子倍率 × 傷害來源（scale：吃武器傷害與法術強度各多少）、蓋在技能上的修飾（標籤相符的才算）的效果
# scale 另外留一份：不是照武器算的傷害（積怨的「受到的傷害 × 倍數」）要把它除掉
static func cast_context(owner: Player, slot: Dictionary) -> Dictionary:
	var bag: Dictionary = slot.get("bag", {})
	var scale := SkillDefs.scale_mul(slot.def, owner.weapon)
	var ctx := {"mul": SkillDefs.damage_mul(slot.id, slot.get("level", 1)) * (BagDefs.power_of(bag) if not bag.is_empty() else 1.0) * scale, "scale": scale, "area": 1.0,
		"type": slot.def.get("damage_type", &"phys"), "split": false,
		"credit": "k:" + String(slot.id)}   # 傷害來源（Combat.credit_scope）：持續的招式（衝刺）每步打的也算這個技能
	if slot.get("phantom", false):
		ctx.mul *= SkillDefs.PHANTOM_MUL
	ctx.mul *= slot.get("power", 1.0)   # 骰子模式：同一招骰到幾個的威力（DiceDefs.TIERS）
	for sup: Dictionary in supports_of(slot):
		match sup.mode:
			&"split":
				ctx.split = true
			&"extend":
				ctx.area = 1.5
			&"fire", &"cold":
				ctx.type = sup.mode
	return ctx


# 蓋在這個技能上、標籤相符的修飾效果
static func supports_of(slot: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in support_ids(slot):
		out.append(ItemDefs.support_of(id))
	return out


# 同上，回傳道具 id（一顆一筆）：透明格蓋在這個技能上、而且對它有作用的修飾（ItemDefs.mod_applies；第 8 步 f 取代「同一袋」）
static func support_ids(slot: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	if not slot.has("bag") or not slot.has("entry"):
		return out
	out = mod_ids_on(slot.bag, slot.entry)
	if not slot.get("phantom", false):   # 武器符合時幻影沒作用：不加耗魔
		out.erase(PHANTOM_ID)
	return out


# 袋子 b 裡蓋在條目 e（技能或效果）上、對它有作用的修飾 id
static func mod_ids_on(b: Dictionary, e: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for m in Inventory.for_bag(b).mods_on(e):
		if ItemDefs.mod_applies(m.id, e.id):
			out.append(m.id)
	return out


# 無法使用時給 HUD 的回饋（空欄位不提示）
func notify_blocked(owner: Player, index: int) -> void:
	if get_slot(owner, index) != null:
		owner.world.emit_event("skill:onCooldown", {"key": cd_key(index), "player_id": owner.id})
