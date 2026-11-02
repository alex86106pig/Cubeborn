# 寶石座技能的檢查（Build 改版第 7 步）：鑲嵌規則、數字鍵順序、每個技能放得出來而且有效果、等級、輔助道具、技能遺物
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


# 鑲嵌規則：寶石座只放技能、技能只放寶石座、只能鑲在能用的武器上；自動擺放先找主手、副手的寶石座，鑲不上進背包
static func check_gem_rules() -> String:
	var s := _setup(&"longsword")
	var p: Player = s[1]
	p.loadout.equip_offhand_new(p, &"woodShield")
	var main := p.loadout.container(Loadout.MAIN)
	var gems: Array = main.mask.keys().filter(func(c: Vector2i) -> bool: return main.mask[c] == "G")
	var plain: Array = main.mask.keys().filter(func(c: Vector2i) -> bool: return main.mask[c] == "A")
	if not main.fits(&"whirlwind", gems[0], 0) or main.fits(&"whirlwind", plain[0], 0):
		return "長劍的技能應只放得進寶石座"
	if main.fits(&"whetstone", gems[0], 0) or main.fits(&"meteor", gems[0], 0):
		return "寶石座不放一般道具、長劍的寶石座不放法杖的技能"
	if not p.inventory.fits(&"meteor", Vector2i(0, 0), 0):
		return "背包什麼技能都放得下"
	var a := p.add_item(&"whirlwind")
	var b := p.add_item(&"shield_slam")
	var c := p.add_item(&"meteor")
	if p.loadout.find_item(a).where != Loadout.MAIN or p.loadout.find_item(b).where != Loadout.OFF or p.loadout.find_item(c).where != Loadout.BAG:
		return "自動擺放：長劍的技能進主手、盾的進副手、用不了的進背包：%s / %s / %s" % [p.loadout.find_item(a).where, p.loadout.find_item(b).where, p.loadout.find_item(c).where]
	# 數字鍵：主手的寶石座先，再來副手；Q 是治療藥水
	if _slot_of(p, &"whirlwind") != 0 or _slot_of(p, &"shield_slam") != 1 or p.slots.get_slot(p, ActiveSlots.HEAL_INDEX).def.behavior != &"heal":
		return "數字鍵順序：1 主手的技能、2 副手的技能、Q 治療藥水：%d / %d" % [_slot_of(p, &"whirlwind"), _slot_of(p, &"shield_slam")]
	if p.items.any(func(it: Dictionary) -> bool: return ItemDefs.is_skill(it.id)):
		return "寶石座的技能不算生效的道具"
	return ""


# 每個技能：鑲在第一種能用的武器上，按數字鍵放出來，2.5 秒內打到旁邊的怪，或者有它自己的效果（煙、嘲諷、召喚、祝福、火把）
static func check_every_skill() -> String:
	for id: StringName in SkillDefs.gem_skill_ids():
		var def: Dictionary = SkillDefs.SKILLS[id]
		var weapon: StringName = def.weapons[0]
		var s := _setup(&"longsword" if weapon == &"woodShield" else weapon)
		var w: World = s[0]
		var p: Player = s[1]
		if weapon == &"woodShield":
			p.loadout.equip_offhand_new(p, &"woodShield")
		if _slot_of(p, id) < 0:
			for g: Dictionary in p.slots.gems(p).duplicate():   # 火把只有一個寶石座、出廠鑲著插火把：先拿下來
				p.loadout.remove_item(p, g.entry.uid)
			var uid := p.add_item(id)
			if p.loadout.find_item(uid).get("where", Loadout.BAG) == Loadout.BAG:
				return "%s 鑲不上 %s 的寶石座" % [ItemDefs.ITEMS[id].name, weapon]
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
	for id: StringName in [&"wormwood", &"soul_scythe", &"hourglass"]:
		if not LootDefs.drop_pool(ItemDefs.ITEMS[id].rarity).has(id):
			return "魔力道具 %s 應在掉落池" % id
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


# 技能遺物的來源與保證：石棺必開出技能遺物、祭壇只開道具遺物；3 個選項至少 1 個是手上武器（主手或副手）能鑲、還沒滿級的技能，
# 手上武器的技能都滿級了就照舊全隨機；保證的那個不固定在第一張
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
	for loadout: Array in [[&"longsword", &"woodShield"], [&"staff", &""], [&"dagger", &"dagger"]]:
		for i in 30:
			var s := _setup(loadout[0])
			var w: World = s[0]
			var p: Player = s[1]
			if loadout[1] != &"":
				p.loadout.equip_offhand_new(p, loadout[1])
			var relic := w.drop_relic(&"big", p.pos + Vector2(1, 0), &"skill")
			relic.open_for(p)
			var offer: Array = relic.offers[p.peer_id]
			var own := offer.filter(func(id: StringName) -> bool: return Relic._fits_hands(p, id))
			if own.is_empty():
				return "%s 的技能遺物選項應至少 1 個手上武器能用：%s" % [loadout, offer]
			var uniq := {}
			for id: StringName in offer:
				uniq[id] = true
			if offer.size() != 3 or uniq.size() != 3:
				return "技能遺物應有 3 個不重複的選項：%s" % [offer]
			if Relic._fits_hands(p, offer[0]):
				first_hits += 1
	if first_hits == 90:
		return "保證的技能每次都在第一張，應打亂順序"
	# 手上武器的技能都滿級：不保證（照舊全隨機），選項照樣是 3 個技能
	var s3 := _setup(&"longsword")
	var p3: Player = s3[1]
	for id: StringName in SkillDefs.relic_pool():
		if Relic._fits_hands(p3, id):
			p3.skill_levels[id] = SkillDefs.LEVEL.max
	var r3 := (s3[0] as World).drop_relic(&"big", p3.pos + Vector2(1, 0), &"skill")
	r3.open_for(p3)
	if (r3.offers[p3.peer_id] as Array).size() != 3:
		return "手上武器的技能都滿級時照樣要有 3 個選項：%s" % [r3.offers[p3.peer_id]]
	return ""


# 輔助道具：貼著寶石座、標籤相符才有效——延長讓範圍變大、火焰化改成火焰、分裂再放一次；隔開一格或標籤不符沒效
static func check_supports() -> String:
	var r: float = SkillDefs.SKILLS.whirlwind.radius
	var far_d := r * 1.3
	# 延長：本來打不到的距離打得到
	for with_support in [false, true]:
		var s := _setup(&"longsword")
		var w: World = s[0]
		var p: Player = s[1]
		var gem := _gem_cell(p, Loadout.MAIN)
		p.loadout.add_item(p, &"whirlwind", {"cell": gem, "rot": 0}, 0, Loadout.MAIN)
		if with_support:
			p.loadout.add_item(p, &"extend_support", {"cell": gem + Vector2i(-1, 0), "rot": 0}, 0, Loadout.MAIN)
		var e := LootChecks._item_dummy(w, Vector2(0, far_d), 100000.0)
		var hp0 := e.hp
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.slot_bit(0)), 1)
		if (e.hp < hp0) != with_support:
			return "延長%s時 %.1f 單位的怪%s打到" % ["貼著" if with_support else "沒有", far_d, "應" if with_support else "不該"]
	# 火焰化：傷害改成火焰；不貼著（隔一格）就沒效
	for adjacent in [true, false]:
		var s := _setup(&"longsword")
		var w: World = s[0]
		var p: Player = s[1]
		var gem := _gem_cell(p, Loadout.MAIN)
		p.loadout.add_item(p, &"whirlwind", {"cell": gem, "rot": 0}, 0, Loadout.MAIN)
		var spot := gem + Vector2i(0, 1) if adjacent else Vector2i(1, 1)   # 正下方（橫放）貼著；第 1 列離寶石座兩格
		if not p.loadout.container(Loadout.MAIN).fits(&"fire_support", spot, 0):
			return "火焰化放不進長劍 %s" % spot
		p.loadout.add_item(p, &"fire_support", {"cell": spot, "rot": 0}, 0, Loadout.MAIN)
		LootChecks._item_dummy(w, Vector2(0, 1.5), 100000.0)
		var events: Array[Dictionary] = []
		_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.slot_bit(0)), 1, events)
		var fire := _named(events, "entity:damaged").any(func(ev: Dictionary) -> bool: return ev.get("damage_type", &"phys") == &"fire")
		if fire != adjacent:
			return "火焰化%s時旋風斬%s是火焰傷害" % ["貼著" if adjacent else "沒貼著", "應" if adjacent else "不該"]
	# 分裂：SPLIT_DELAY 秒後再打一次（傷害 SPLIT_MUL）；嘲諷（防禦標籤）旁邊放分裂沒效
	var s3 := _setup(&"longsword")
	var w3: World = s3[0]
	var p3: Player = s3[1]
	var g3 := _gem_cell(p3, Loadout.MAIN)
	p3.loadout.add_item(p3, &"whirlwind", {"cell": g3, "rot": 0}, 0, Loadout.MAIN)
	p3.loadout.add_item(p3, &"split_support", {"cell": g3 + Vector2i(-1, 0), "rot": 1}, 0, Loadout.MAIN)   # 左邊直放
	var e3 := LootChecks._item_dummy(w3, Vector2(0, 1.5), 100000.0)
	e3.set_resists({})
	var ev3: Array[Dictionary] = []
	_run_collect(w3, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.slot_bit(0)), 1, ev3)
	_run_collect(w3, _cmd(Vector2.ZERO), roundi(SkillBehaviors.SPLIT_DELAY / DT) + 2, ev3)
	var hits := _named(ev3, "entity:damaged").filter(func(ev: Dictionary) -> bool: return ev.target_id == e3.id)
	if hits.size() != 2 or absf(hits[1].amount / hits[0].amount - SkillBehaviors.SPLIT_MUL) > 0.02:
		return "分裂：應打 2 次、第二次 ×%.1f：%s" % [SkillBehaviors.SPLIT_MUL, hits.map(func(ev: Dictionary) -> float: return ev.amount)]
	return ""


# 那隻手武器的第一個寶石座（由上到下）
static func _gem_cell(p: Player, where: int) -> Vector2i:
	var inv := p.loadout.container(where)
	var gems: Array = inv.mask.keys().filter(func(c: Vector2i) -> bool: return inv.mask[c] == "G")
	gems.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return gems[0]
