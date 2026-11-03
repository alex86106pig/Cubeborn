# 技能的檢查：按鍵袋（數字鍵順序、放置規則）、每個技能放得出來而且有效果、等級、同一袋的修飾、技能遺物
class_name SkillChecks
extends CheckKit


static func _setup(weapon: StringName) -> Array:
	var w := _new_world()
	var p := _player(w)
	p.loadout.equip_new(p, weapon)
	return [w, p]


static func _slot_of(p: Player, id: StringName) -> int:
	for i in ActiveSlots.GEM_SLOTS:
		var s: Variant = p.slots.get_slot(p, i)
		if s != null and s.id == id:
			return i
	return -1


# 面前、準星、左右後各放一隻不會死的怪（技能的範圍、落點、衝刺路線都打得到）
static func _targets(w: World) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for at: Vector2 in [Vector2(0, 3), Vector2(0, 5), Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, -1.5)]:
		var e := LootChecks._item_dummy(w, at, 100000.0)
		e.set_resists({})
		out.append(e)
	return out


# 放置規則：主袋不放技能、袋子收技能與效果、倉庫什麼都收；自動擺放先找按鍵袋、滿了找別的袋子、都滿進倉庫；
# 數字鍵 = 按鍵袋由左到右（袋子裡第一個技能），Q 是治療藥水；技能不算生效的數值道具
static func check_gem_rules() -> String:
	var s := _setup(&"longsword")
	var p: Player = s[1]
	var key: Dictionary = p.loadout.key_bags()[0]
	if p.loadout.core.fits(&"whirlwind", Vector2i.ZERO, 0) or not Inventory.for_bag(key).fits(&"meteor", Vector2i.ZERO, 0) \
			or Inventory.for_bag(key).fits(&"whetstone", Vector2i.ZERO, 0) or not p.inventory.fits(&"meteor", Vector2i.ZERO, 0):
		return "主袋不放技能、袋子放技能不放數值道具、倉庫都放得下"
	var a := p.add_item(&"whirlwind")
	if p.loadout.find_item(a).get("where", -9) != 0:
		return "技能應自動放進按鍵袋：%s" % [p.loadout.find_item(a)]
	var key2 := _bag(p, &"key", &"top")
	var b := _put(p, key2, &"shield_slam")
	if b == &"" or _slot_of(p, &"whirlwind") != 0 or _slot_of(p, &"shield_slam") != 1 or p.slots.get_slot(p, ActiveSlots.HEAL_INDEX).def.behavior != &"heal":
		return "數字鍵順序：1 左邊的按鍵袋、2 右邊的、Q 治療藥水：%d / %d" % [_slot_of(p, &"whirlwind"), _slot_of(p, &"shield_slam")]
	key2.offset = 4
	key.offset = 6
	if _slot_of(p, &"whirlwind") != 1 or _slot_of(p, &"shield_slam") != 0:
		return "按鍵袋換位置後數字鍵跟著換：%d / %d" % [_slot_of(p, &"whirlwind"), _slot_of(p, &"shield_slam")]
	for id: StringName in [&"meteor", &"chain_bolt", &"volley", &"snipe", &"taunt", &"blessing", &"ambush"]:
		p.add_item(id)
	if not p.inventory.entries.any(func(e: Dictionary) -> bool: return ItemDefs.is_skill(e.id)):
		return "兩個按鍵袋都滿了，技能應放進倉庫"
	if p.items.any(func(it: Dictionary) -> bool: return ItemDefs.is_skill(it.id)):
		return "技能不算生效的數值道具"
	return ""


# 每個技能：放進按鍵袋 1（不綁武器；照資料寫的武器拿著，動作才對），按數字鍵放出來，2.5 秒內打到旁邊的怪，或者有它自己的效果（煙、嘲諷、召喚、祝福、火把）
static func check_every_skill() -> String:
	for id: StringName in SkillDefs.gem_skill_ids():
		var def: Dictionary = SkillDefs.SKILLS[id]
		var weapon: StringName = def.weapons[0]
		var s := _setup(&"longsword" if weapon == &"woodShield" else weapon)
		var w: World = s[0]
		var p: Player = s[1]
		if weapon == &"woodShield":
			p.loadout.equip_offhand_new(p, &"woodShield")
		if p.loadout.find_item(p.add_item(id)).get("where", -9) != 0:
			return "%s 應放進按鍵袋" % ItemDefs.ITEMS[id].name
		var targets := _targets(w)
		var hp0 := targets.map(func(e: Enemy) -> float: return e.hp)
		var torches := w.torches.size()
		var allies := w.allies.size()
		var idx := _slot_of(p, id)
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.slot_bit(idx)), 1)
		var ready := w.cooldowns.is_ready(p.cd(ActiveSlots.cd_key(idx)))
		var smoked := w.zones.any(func(z: Dictionary) -> bool: return z.get("smoke", 0.0) > 0.0)
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 5)), roundi(2.5 / DT))
		var hurt := false
		for i in targets.size():
			hurt = hurt or targets[i].hp < hp0[i]
		var effect := hurt
		match def.behavior:
			&"smoke":
				effect = smoked
			&"taunt":
				effect = targets.any(func(e: Enemy) -> bool: return e.taunt_id == p.id)
			&"summon":
				effect = w.allies.size() >= allies + def.count
			&"bless":
				effect = p.buffs.has(&"blessing") or ready == false
			&"plantTorch":
				effect = w.torches.size() == torches + 1
		if ready or not effect:
			return "%s（%s）：按數字鍵 %d 應放出來（進冷卻）並有效果：冷卻 %s、效果 %s" % [ItemDefs.ITEMS[id].name, weapon, idx + 1, not ready, effect]
	return ""


# 魔力：開局滿、每秒回 mana_regen、不超過上限；魔力不夠放不出技能（發 skill:onCooldown、不扣魔）；
# 魔力道具（回魔、耗魔縮減、命中回魔有內部冷卻）照資料生效、會掉落；魔力進快照
static func check_mana() -> String:
	var s := _setup(&"longsword")
	var w: World = s[0]
	var p: Player = s[1]
	if absf(p.mana - Config.MANA.max) > 1e-3 or absf(p.max_mana() - Config.MANA.max) > 1e-3:
		return "開局魔力應是滿的 %.0f：%.1f / %.1f" % [Config.MANA.max, p.mana, p.max_mana()]
	p.mana = 0.0
	_run(w, _cmd(Vector2.ZERO), roundi(1.0 / DT))
	if absf(p.mana - Config.MANA.regen) > 0.2:
		return "1 秒應回 %.1f 魔力，實際 %.2f" % [Config.MANA.regen, p.mana]
	_run(w, _cmd(Vector2.ZERO), roundi(20.0 / DT))
	if absf(p.mana - p.max_mana()) > 1e-3:
		return "回滿後應停在上限 %.0f，實際 %.2f" % [p.max_mana(), p.mana]
	# 魔力不夠：放不出旋風斬
	p.add_item(&"whirlwind")
	var e := LootChecks._item_dummy(w, Vector2(0, 1.5), 100000.0)
	var cost := ActiveSlots.mana_cost(p, p.slots.get_slot(p, 0))
	p.set_stat_source(&"test", [[&"mana_regen", Stats.MUL, 0.0]])
	p.mana = cost - 1.0
	var events: Array[Dictionary] = []
	var hp0 := e.hp
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.slot_bit(0)), 1, events)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5)), 20)
	if e.hp != hp0 or absf(p.mana - (cost - 1.0)) > 1e-3 or _named(events, "skill:onCooldown").is_empty():
		return "魔力 %.0f 不夠放旋風斬（%.0f）：不應出招、不扣魔、要提示（傷害 %.1f、魔力 %.1f、提示 %d）" % [cost - 1.0, cost, hp0 - e.hp, p.mana, _named(events, "skill:onCooldown").size()]
	p.remove_stat_source(&"test")
	# 魔力道具
	var regen0 := p.stats.value(&"mana_regen")
	p.add_item(&"wormwood")
	p.add_item(&"hourglass")
	var want_regen: float = regen0 + LootChecks._effect_value(&"wormwood", &"mana_regen")
	var want_cost: float = SkillDefs.SKILLS.whirlwind.mana * LootChecks._effect_value(&"hourglass", &"mana_cost")
	if absf(p.stats.value(&"mana_regen") - want_regen) > 1e-3 or absf(ActiveSlots.mana_cost(p, p.slots.get_slot(p, 0)) - want_cost) > 1e-3:
		return "苦艾酒回魔應 %.1f、時之沙漏後旋風斬耗魔應 %.1f：%.2f / %.2f" % [want_regen, want_cost, p.stats.value(&"mana_regen"), ActiveSlots.mana_cost(p, p.slots.get_slot(p, 0))]
	for id: StringName in [&"wormwood", &"soul_scythe", &"hourglass", &"mana_shard", &"prayer_beads", &"mana_crystal", &"mage_heart", &"abyss_chalice"]:
		if not LootDefs.drop_pool(ItemDefs.ITEMS[id].rarity).has(id):
			return "魔力道具 %s 應在掉落池" % id
	# 最大魔力：(基礎 + 加的) × (1 + 百分比)；法師之心 +60 與回魔 +1、深淵之杯 +30% 與回魔 +2
	var regen1 := p.stats.value(&"mana_regen")
	p.add_item(&"mage_heart")
	p.add_item(&"abyss_chalice")
	var want_max := (Config.MANA.max + 60.0) * 1.3
	if absf(p.max_mana() - want_max) > 1e-3 or absf(p.stats.value(&"mana_regen") - regen1 - 3.0) > 1e-3:
		return "法師之心 + 深淵之杯：最大魔力應 %.0f、回魔 +3，實際 %.1f / +%.2f" % [want_max, p.max_mana(), p.stats.value(&"mana_regen") - regen1]
	# 命中回魔：每 ItemDefs.PROCS.mana_on_hit.icd 秒最多一次
	p.set_stat_source(&"test", [[&"mana_regen", Stats.MUL, 0.0], [&"mana_on_hit", Stats.ADD, 1.0]])
	p.mana = 0.0
	ItemEffects.on_dealt(w, p, 5.0)
	ItemEffects.on_dealt(w, p, 5.0)
	if absf(p.mana - 1.0) > 1e-3:
		return "命中回魔同一瞬間打兩下應只回 1，實際 %.2f" % p.mana
	_run(w, _cmd(Vector2.ZERO), ceili(ItemDefs.PROCS.mana_on_hit.icd / DT) + 1)
	ItemEffects.on_dealt(w, p, 5.0)
	if absf(p.mana - 2.0) > 1e-3:
		return "內部冷卻過後命中應再回 1，實際 %.2f" % p.mana
	# 快照帶魔力（客戶端的魔力條、技能欄以房主為準）
	p.mana = 37.0
	var extra: Array = NetCodec.entity_fields(p)[NetCodec.E_EXTRA]
	if absf(extra[NetCodec.P_MANA] - 37.0) > 0.05:
		return "快照的魔力應是 37，實際 %s" % [extra[NetCodec.P_MANA]]
	_note("魔力 %.0f、每秒回 %.0f；旋風斬耗魔 %.0f" % [Config.MANA.max, Config.MANA.regen, SkillDefs.SKILLS.whirlwind.mana])
	return ""


# 等級：技能遺物選到身上已經有的技能就升 1 級（最高 LEVEL.max）；每級傷害 +LEVEL.damage、耗魔 −LEVEL.mana
static func check_skill_level() -> String:
	var dealt := []
	for lv in [1, 3]:
		var s := _setup(&"longsword")
		var w: World = s[0]
		var p: Player = s[1]
		p.add_item(&"whirlwind")
		p.skill_levels[&"whirlwind"] = lv
		p.set_stat_source(&"test", [[&"mana_regen", Stats.MUL, 0.0]])
		var e := LootChecks._item_dummy(w, Vector2(0, 1.5), 100000.0)
		e.set_resists({})
		var hp0 := e.hp
		var mana0 := p.mana
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.slot_bit(0)), 1)
		dealt.append(hp0 - e.hp)
		var cost: float = SkillDefs.SKILLS.whirlwind.mana * (1.0 - SkillDefs.LEVEL.mana * (lv - 1))
		if absf(mana0 - p.mana - cost) > 1e-3:
			return "%d 級應扣 %.1f 魔力，實際 %.2f" % [lv, cost, mana0 - p.mana]
	var want: float = (1.0 + SkillDefs.LEVEL.damage * 2) / 1.0
	if dealt[0] <= 0.0 or absf(dealt[1] / dealt[0] - want) > 0.02:
		return "3 級傷害應是 1 級的 %.2f 倍：%s" % [want, dealt]
	# 技能遺物：選項都是技能；選到已經有的升 1 級、沒有的拿到技能
	var s2 := _setup(&"longsword")
	var w2: World = s2[0]
	var p2: Player = s2[1]
	var relic := w2.drop_relic(&"small", p2.pos + Vector2(1, 0), &"skill")
	relic.open_for(p2)
	var offer: Array = relic.offers[p2.peer_id]
	if offer.is_empty() or not offer.all(func(id: StringName) -> bool: return ItemDefs.is_skill(id) and not SkillDefs.SKILLS[id].get("no_relic", false)):
		return "技能遺物的選項應都是技能：%s" % [offer]
	var have: StringName = offer[0]
	p2.add_item(have)
	relic.pick(p2, 0)
	if p2.skill_levels.get(have, 1) != 2:
		return "選到已經有的技能應升到 2 級：%s" % p2.skill_levels
	var r2 := w2.drop_relic(&"small", p2.pos + Vector2(1, 0), &"skill")
	r2.open_for(p2)
	var fresh: StringName = r2.offers[p2.peer_id].filter(func(id: StringName) -> bool: return not p2.loadout.has_item(id))[0]
	r2.pick(p2, (r2.offers[p2.peer_id] as Array).find(fresh))
	if not p2.loadout.has_item(fresh) or p2.skill_levels.has(fresh):
		return "選到沒有的技能應拿到它（1 級）"
	return _check_skill_relic_rules()



# 等級看得到：說明框標題寫幾級、第二行的傷害倍率與耗魔照等級算（沒傷害的技能不寫傷害）、遺物卡寫升級前後；技能欄 2 級以上左上角寫等級
static func check_level_text() -> String:
	var sk: Dictionary = SkillDefs.SKILLS.whirlwind
	var lv1 := UiKit.item_info(&"whirlwind", {}, 1)
	var lv3 := UiKit.item_info(&"whirlwind", {}, 3)
	var want_cost := "耗魔 %d" % roundi(sk.mana * SkillDefs.level_mana_mul(3))
	var want_mul := "傷害 ×%s" % UiKit.level_mul_text(SkillDefs.level_damage_mul(3))
	if lv1.title.contains("級") or (lv1.lines[1] as String).contains("傷害 ×"):
		return "1 級不應寫等級與傷害倍率：%s" % [lv1]
	if not lv3.title.contains("3 級") or not (lv3.lines[1] as String).contains(want_cost) or not (lv3.lines[1] as String).contains(want_mul):
		return "3 級說明框應寫「3 級」「%s」「%s」：%s" % [want_mul, want_cost, lv3]
	var no_damage: StringName = SkillDefs.gem_skill_ids().filter(func(id: StringName) -> bool: return SkillDefs.SKILLS[id].has("mana") and not SkillDefs.SKILLS[id].has("damage_pct"))[0]
	if UiKit.skill_line(no_damage, 3).contains("傷害 ×") or UiKit.skill_upgrade_line(no_damage, 2).contains("傷害"):
		return "沒傷害的技能（%s）不應寫傷害倍率" % no_damage
	var up := UiKit.skill_upgrade_line(&"whirlwind", 2)
	for want in ["傷害 ×%s → ×%s" % [UiKit.level_mul_text(SkillDefs.level_damage_mul(2)), UiKit.level_mul_text(SkillDefs.level_damage_mul(3))],
			"耗魔 %d → %d" % [roundi(sk.mana * SkillDefs.level_mana_mul(2)), roundi(sk.mana * SkillDefs.level_mana_mul(3))]]:
		if not up.contains(want):
			return "遺物卡的升級預覽缺「%s」：%s" % [want, up]
	var slot := SkillBar.Slot.new("", "1", 0)
	slot.show_level(1)
	var t1 := slot.level.text
	slot.show_level(2)
	var t2 := slot.level.text
	slot.free()
	if t1 != "" or not t2.contains("2"):
		return "技能欄：1 級不寫、2 級寫等級，實際「%s」「%s」" % [t1, t2]
	return ""

# 技能遺物的來源與保證：石棺必開出技能遺物、祭壇只開道具遺物；身上有還沒滿級的技能時，3 個選項至少 1 個是它（升級）、
# 不固定在第一張；都滿級了就照舊全隨機，選項照樣 3 個不重複
static func _check_skill_relic_rules() -> String:
	for tier: StringName in [&"big", &"small"]:
		for i in 10:
			var s := _setup(&"longsword")
			var w: World = s[0]
			var chest := Chest.new(w, tier, Vector2(0, 2))
			w.add_entity(chest)
			w.souls = 1000
			chest.try_open(s[1])
			var relic: Relic = w.relics.back()
			var want := &"skill" if tier == &"big" else &"item"
			if relic.relic_kind != want:
				return "%s 應開出%s遺物，實際 %s" % ["石棺" if tier == &"big" else "祭壇", "技能" if want == &"skill" else "道具", relic.relic_kind]
	var first_hits := 0
	for i in 30:
		var s := _setup(&"longsword")
		var w: World = s[0]
		var p: Player = s[1]
		p.add_item(&"whirlwind")
		var relic := w.drop_relic(&"big", p.pos + Vector2(1, 0), &"skill")
		relic.open_for(p)
		var offer: Array = relic.offers[p.peer_id]
		var uniq := {}
		for id: StringName in offer:
			uniq[id] = true
		if not offer.has(&"whirlwind") or offer.size() != 3 or uniq.size() != 3:
			return "有還沒滿級的旋風斬時，技能遺物應有 3 個不重複的選項、其中一個是旋風斬：%s" % [offer]
		if offer[0] == &"whirlwind":
			first_hits += 1
	if first_hits == 30:
		return "保證的技能每次都在第一張，應打亂順序"
	var s3 := _setup(&"longsword")
	var p3: Player = s3[1]
	p3.add_item(&"whirlwind")
	p3.skill_levels[&"whirlwind"] = SkillDefs.LEVEL.max
	var r3 := (s3[0] as World).drop_relic(&"big", p3.pos + Vector2(1, 0), &"skill")
	r3.open_for(p3)
	if (r3.offers[p3.peer_id] as Array).size() != 3:
		return "技能都滿級時照樣要有 3 個選項：%s" % [r3.offers[p3.peer_id]]
	return ""


# 修飾：跟技能放在同一袋、標籤相符才有效——延長讓範圍變大、火焰化改成火焰、分裂再放一次；放在別的袋子沒效
static func check_supports() -> String:
	var r: float = SkillDefs.SKILLS.whirlwind.radius
	var far_d := r * 1.3
	# 延長：本來打不到的距離打得到
	for with_support in [false, true]:
		var s := _setup(&"longsword")
		var w: World = s[0]
		var p: Player = s[1]
		var key: Dictionary = p.loadout.key_bags()[0]
		_put(p, key, &"whirlwind")
		if with_support:
			_put(p, key, &"extend_support")
		var e := LootChecks._item_dummy(w, Vector2(0, far_d), 100000.0)
		var hp0 := e.hp
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.slot_bit(0)), 1)
		if (e.hp < hp0) != with_support:
			return "延長%s時 %.1f 單位的怪%s打到" % ["同一袋" if with_support else "沒有", far_d, "應" if with_support else "不該"]
	# 火焰化：傷害改成火焰；放在另一個袋子就沒效
	for same_bag in [true, false]:
		var s := _setup(&"longsword")
		var w: World = s[0]
		var p: Player = s[1]
		var key: Dictionary = p.loadout.key_bags()[0]
		_put(p, key, &"whirlwind")
		if _put(p, key if same_bag else _bag(p, &"key", &"top"), &"fire_support") == &"":
			return "火焰化放不進按鍵袋"
		LootChecks._item_dummy(w, Vector2(0, 1.5), 100000.0)
		var events: Array[Dictionary] = []
		_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.slot_bit(_slot_of(p, &"whirlwind"))), 1, events)
		var fire := _named(events, "entity:damaged").any(func(ev: Dictionary) -> bool: return ev.get("damage_type", &"phys") == &"fire")
		if fire != same_bag:
			return "火焰化%s時旋風斬%s是火焰傷害" % ["同一袋" if same_bag else "在別的袋子", "應" if same_bag else "不該"]
	# 分裂：SPLIT_DELAY 秒後再打一次（傷害 SPLIT_MUL）
	var s3 := _setup(&"longsword")
	var w3: World = s3[0]
	var p3: Player = s3[1]
	var k3: Dictionary = p3.loadout.key_bags()[0]
	_put(p3, k3, &"whirlwind")
	_put(p3, k3, &"split_support")
	var e3 := LootChecks._item_dummy(w3, Vector2(0, 1.5), 100000.0)
	e3.set_resists({})
	var ev3: Array[Dictionary] = []
	_run_collect(w3, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.slot_bit(0)), 1, ev3)
	_run_collect(w3, _cmd(Vector2.ZERO), roundi(SkillBehaviors.SPLIT_DELAY / DT) + 2, ev3)
	var hits := _named(ev3, "entity:damaged").filter(func(ev: Dictionary) -> bool: return ev.target_id == e3.id)
	if hits.size() != 2 or absf(hits[1].amount / hits[0].amount - SkillBehaviors.SPLIT_MUL) > 0.02:
		return "分裂：應打 2 次、第二次 ×%.1f：%s" % [SkillBehaviors.SPLIT_MUL, hits.map(func(ev: Dictionary) -> float: return ev.amount)]
	# 耗魔：一般修飾每顆 × (1 + 強度 × SUPPORT_MANA)，節能 × mana_mul；技能欄顯示與實際扣的一樣
	var s4 := _setup(&"longsword")
	var w4: World = s4[0]
	var p4: Player = s4[1]
	var k4: Dictionary = p4.loadout.key_bags()[0]
	_put(p4, k4, &"whirlwind")
	var base_cost := ActiveSlots.mana_cost(p4, p4.slots.get_slot(p4, 0))
	_put(p4, k4, &"extend_support")
	var with_extend := ActiveSlots.mana_cost(p4, p4.slots.get_slot(p4, 0))
	var want_extend: float = base_cost * (1.0 + ItemDefs.ITEMS.extend_support.power * SkillDefs.SUPPORT_MANA)
	if _put(p4, k4, &"conserve_support") == &"":
		return "節能放不進按鍵袋"
	var both := ActiveSlots.mana_cost(p4, p4.slots.get_slot(p4, 0))
	var want_both: float = want_extend * ItemDefs.support_of(&"conserve_support").mana_mul
	p4.set_stat_source(&"test", [[&"mana_regen", Stats.MUL, 0.0]])
	var m0 := p4.mana
	_run(w4, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.slot_bit(0)), 1)
	if absf(with_extend - want_extend) > 1e-3 or absf(both - want_both) > 1e-3 or absf(m0 - p4.mana - want_both) > 1e-3:
		return "修飾耗魔：旋風斬 %.1f，加延長應 %.2f（%.2f）、再加節能應 %.2f（%.2f）、實際扣 %.2f" % [base_cost, want_extend, with_extend, want_both, both, m0 - p4.mana]
	_note("修飾耗魔：旋風斬 %.1f → 延長 %.2f → 延長 + 節能 %.2f" % [base_cost, with_extend, both])
	return ""
