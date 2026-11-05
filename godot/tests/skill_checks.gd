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


# 放置規則：主袋不放技能、袋子收技能、效果與數值道具（第 8 步 a）、倉庫什麼都收；自動擺放先找按鍵袋、滿了找別的袋子、都滿進倉庫；
# 數字鍵 = 按鍵袋由左到右（袋子裡第一個技能），Q 是治療藥水；技能不算生效的數值道具
static func check_gem_rules() -> String:
	var s := _setup(&"swordShield")
	var p: Player = s[1]
	var key: Dictionary = p.loadout.key_bags()[0]
	if p.loadout.core.fits(&"whirlwind", Vector2i.ZERO, 0) or not Inventory.for_bag(key).fits(&"meteor", Vector2i.ZERO, 0) \
			or not Inventory.for_bag(key).fits(&"whetstone", Vector2i.ZERO, 0) or not p.inventory.fits(&"meteor", Vector2i.ZERO, 0):
		return "主袋不放技能、袋子放得下技能與數值道具、倉庫都放得下"
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
		var s := _setup(weapon)
		var w: World = s[0]
		var p: Player = s[1]
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
	var s := _setup(&"swordShield")
	var w: World = s[0]
	var p: Player = s[1]
	if absf(p.mana - Config.MANA.max) > 1e-3 or absf(p.max_mana() - Config.MANA.max) > 1e-3:
		return "開局魔力應是滿的 %.0f：%.1f / %.1f" % [Config.MANA.max, p.mana, p.max_mana()]
	p.mana = 0.0
	_run(w, _cmd(Vector2.ZERO), roundi(1.0 / DT))
	if absf(p.mana - Config.MANA.regen) > 0.2:
		return "1 秒應回 %.1f 魔力，實際 %.2f" % [Config.MANA.regen, p.mana]
	_run(w, _cmd(Vector2.ZERO), roundi((p.max_mana() / Config.MANA.regen + 1.0) / DT))
	if absf(p.mana - p.max_mana()) > 1e-3:
		return "回滿後應停在上限 %.0f，實際 %.2f" % [p.max_mana(), p.mana]
	# 魔力照手上的武器（WeaponDefs 的 max_mana / mana_regen）；換武器時目前魔力照比例縮放
	p.mana = p.max_mana() * 0.5
	p.equip_weapon(&"shovel")
	var sd: Dictionary = WeaponDefs.WEAPONS.shovel
	if absf(p.max_mana() - sd.max_mana) > 1e-3 or absf(p.stats.value(&"mana_regen") - sd.mana_regen) > 1e-3 or absf(p.mana - sd.max_mana * 0.5) > 1e-3:
		return "換鐵鏟：魔力應 %.0f / %.0f、回魔 %.2f，實際 %.1f / %.1f、%.2f" % [sd.max_mana * 0.5, sd.max_mana, sd.mana_regen, p.mana, p.max_mana(), p.stats.value(&"mana_regen")]
	p.equip_weapon(&"swordShield")
	if absf(p.max_mana() - Config.MANA.max) > 1e-3 or absf(p.mana - Config.MANA.max * 0.5) > 1e-3:
		return "換回劍盾：魔力應 %.0f / %.0f，實際 %.1f / %.1f" % [Config.MANA.max * 0.5, Config.MANA.max, p.mana, p.max_mana()]
	p.mana = p.max_mana()
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
	var want_regen: float = regen0 + Config.MANA.regen * LootChecks._effect_value(&"wormwood", &"mana_regen")   # % 加在武器的基礎回魔上
	var want_cost: float = SkillDefs.SKILLS.whirlwind.mana * LootChecks._effect_value(&"hourglass", &"mana_cost")
	if absf(p.stats.value(&"mana_regen") - want_regen) > 1e-3 or absf(ActiveSlots.mana_cost(p, p.slots.get_slot(p, 0)) - want_cost) > 1e-3:
		return "苦艾酒回魔應 %.1f、時之沙漏後旋風斬耗魔應 %.1f：%.2f / %.2f" % [want_regen, want_cost, p.stats.value(&"mana_regen"), ActiveSlots.mana_cost(p, p.slots.get_slot(p, 0))]
	for id: StringName in [&"wormwood", &"soul_scythe", &"hourglass", &"mana_shard", &"prayer_beads", &"mana_crystal", &"mage_heart", &"abyss_chalice"]:
		if not LootDefs.drop_pool(ItemDefs.ITEMS[id].rarity).has(id):
			return "魔力道具 %s 應在掉落池" % id
	# 魔力道具都是 %（魔力照武器）：法師之心最大魔力 +50%、回魔 +20%，深淵之杯 +30%、回魔 +40%（百分比相加）
	var regen1 := p.stats.value(&"mana_regen")
	p.add_item(&"mage_heart")
	p.add_item(&"abyss_chalice")
	var want_max := Config.MANA.max * 1.8
	var want_regen2 := regen1 + Config.MANA.regen * 0.6
	if absf(p.max_mana() - want_max) > 1e-3 or absf(p.stats.value(&"mana_regen") - want_regen2) > 1e-3:
		return "法師之心 + 深淵之杯：最大魔力應 %.0f、回魔 %.2f，實際 %.1f / %.2f" % [want_max, want_regen2, p.max_mana(), p.stats.value(&"mana_regen")]
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
		var s := _setup(&"swordShield")
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
	var s2 := _setup(&"swordShield")
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



# 等級看得到：說明框標題寫幾級、傷害 % 與耗魔照等級算（每個有傷害的技能都寫 %、沒傷害的不寫）、遺物卡寫升級前後；技能欄 2 級以上左上角寫等級
static func check_level_text() -> String:
	var sk: Dictionary = SkillDefs.SKILLS.whirlwind
	var lv1 := UiKit.item_info(&"whirlwind", {}, 1)
	var lv3 := UiKit.item_info(&"whirlwind", {}, 3)
	var want_cost := "耗魔 %d" % roundi(sk.mana * SkillDefs.level_mana_mul(3))
	var want_pct1 := UiKit.pct_text(sk.damage_pct)
	var want_pct3 := UiKit.pct_text(sk.damage_pct * SkillDefs.level_damage_mul(3))
	var lines1 := "\n".join(lv1.lines)
	var lines3 := "\n".join(lv3.lines)
	if lv1.title.contains("級") or not lines1.contains(want_pct1):
		return "1 級不應寫等級、應寫傷害 %s：%s" % [want_pct1, lv1]
	if not lv3.title.contains("3 級") or not lines3.contains(want_cost) or not lines3.contains(want_pct3):
		return "3 級說明框應寫「3 級」「%s」「%s」：%s" % [want_pct3, want_cost, lv3]
	for id: StringName in SkillDefs.gem_skill_ids():
		var d := UiKit.skill_damage_line(id)
		if SkillDefs.SKILLS[id].has("damage_pct") != d.contains("%"):
			return "技能 %s 的傷害 %% 應%s寫出來：「%s」" % [id, "" if SkillDefs.SKILLS[id].has("damage_pct") else "不", d]
	# 效果型技能：動作會打傷害的（爆炸、閃電、中毒、點燃、鬼火、反彈、飛刀、斬波、落雷）說明框都寫 %
	var damage_actions: Array[StringName] = [&"explode", &"chain_lightning", &"poison", &"ignite", &"wisp", &"reflect", &"throw_knife", &"slash_wave", &"lightning_strike"]
	for id: StringName in ItemDefs.ITEMS:
		if ItemDefs.role_of(id) != ItemDefs.ROLE_EFFECT:
			continue
		var hurts: bool = (ItemDefs.ITEMS[id].effects as Array).any(func(e: Dictionary) -> bool: return damage_actions.has(e.get("do", &"")))
		var line := UiKit.effect_damage_line(id)
		if hurts != line.contains("%") or (hurts and not UiKit.item_info(id, {}).lines.has(line)):
			return "效果型技能 %s 的傷害 %% 應%s寫出來：%s" % [id, "" if hurts else "不", UiKit.item_info(id, {}).lines]
	var no_damage: StringName = SkillDefs.gem_skill_ids().filter(func(id: StringName) -> bool: return SkillDefs.SKILLS[id].has("mana") and not SkillDefs.SKILLS[id].has("damage_pct"))[0]
	if UiKit.item_info(no_damage, {}, 3).lines.size() != 2 or UiKit.skill_upgrade_line(no_damage, 2).contains("傷害"):
		return "沒傷害的技能（%s）不應寫傷害" % no_damage
	var up := UiKit.skill_upgrade_line(&"whirlwind", 2)
	for want in ["傷害 %s → %s" % [UiKit.pct_text(sk.damage_pct * SkillDefs.level_damage_mul(2)), want_pct3],
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

# 技能稀有度的強度預算（SkillDefs.RARITY_BUDGET）：施放的傷害倍率 = 等級 × 預算（同等級、沒袋子倍率時就是預算），
# 說明框與遺物卡的傷害 % 也乘；每個稀有度都有預算、越稀有越高
static func check_skill_budget() -> String:
	var prev := 0.0
	for r: StringName in WeaponDropDefs.RARITY_ORDER:
		if not SkillDefs.RARITY_BUDGET.has(r) or SkillDefs.RARITY_BUDGET[r] <= prev:
			return "技能預算應每個稀有度都有、越稀有越高：%s" % [SkillDefs.RARITY_BUDGET]
		prev = SkillDefs.RARITY_BUDGET[r]
	var s := _setup(&"swordShield")
	var p: Player = s[1]
	for id: StringName in SkillDefs.gem_skill_ids():
		var def: Dictionary = SkillDefs.SKILLS[id]
		if not def.has("damage_pct"):
			continue
		for level in [1, 3]:
			var ctx := ActiveSlots.cast_context(p, {"def": def, "id": id, "level": level, "bag": {}})
			var want := SkillDefs.level_damage_mul(level) * SkillDefs.budget(id)
			if absf(ctx.mul - want) > 1e-6:
				return "%s（%s）%d 級的傷害倍率應 %.3f，實際 %.3f" % [id, ItemDefs.ITEMS[id].rarity, level, want, ctx.mul]
		var line := UiKit.skill_damage_line(id)
		if not line.contains(UiKit.pct_text(def.damage_pct * SkillDefs.budget(id))):
			return "%s 的說明框傷害應乘稀有度 %.2f：%s" % [id, SkillDefs.budget(id), line]
	return ""


# 技能遺物的來源與保證：石棺必開出技能遺物、祭壇只開道具遺物；身上有還沒滿級的技能時，3 個選項至少 1 個是它（升級）、
# 不固定在第一張；都滿級了就照舊全隨機，選項照樣 3 個不重複
static func _check_skill_relic_rules() -> String:
	# 技能稀有度：分級的數量與定案相同、實際抽到的比例接近權重算出來的（±5 個百分點）
	var counts := {}
	var pool := SkillDefs.relic_pool()
	for id: StringName in pool:
		var r: StringName = ItemDefs.ITEMS[id].rarity
		counts[r] = counts.get(r, 0) + 1
	# 使用者 2026-11-04 的分級（docs/製作計畫.md I），綠多一個突刺（2026-11-05 長劍的蓄力突刺改成技能，Claude 暫定綠）
	if counts != {&"white": 10, &"green": 8, &"blue": 7, &"purple": 3}:
		return "技能稀有度的數量應是白 10、綠 8、藍 7、紫 3：%s" % [counts]
	var drawn := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	const DRAWS := 4000
	for i in DRAWS:
		var r: StringName = ItemDefs.ITEMS[SkillDefs.pick_relic(pool, rng)].rarity
		drawn[r] = drawn.get(r, 0) + 1
	var total_weight := 0.0
	for r: StringName in counts:
		total_weight += counts[r] * SkillDefs.RELIC_WEIGHTS[r]
	for r: StringName in counts:
		var want: float = counts[r] * SkillDefs.RELIC_WEIGHTS[r] / total_weight
		var got: float = drawn.get(r, 0) / float(DRAWS)
		if absf(got - want) > 0.05:
			return "技能稀有度 %s 抽到 %.3f，權重算出來 %.3f" % [r, got, want]
	for tier: StringName in [&"big", &"small"]:
		for i in 10:
			var s := _setup(&"swordShield")
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
		var s := _setup(&"swordShield")
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
	var s3 := _setup(&"swordShield")
	var p3: Player = s3[1]
	p3.add_item(&"whirlwind")
	p3.skill_levels[&"whirlwind"] = SkillDefs.LEVEL.max
	var r3 := (s3[0] as World).drop_relic(&"big", p3.pos + Vector2(1, 0), &"skill")
	r3.open_for(p3)
	if (r3.offers[p3.peer_id] as Array).size() != 3:
		return "技能都滿級時照樣要有 3 個選項：%s" % [r3.offers[p3.peer_id]]
	return ""


# 修飾：透明格蓋在技能上、標籤相符才有效（第 8 步 f）——延長讓範圍變大、火焰化改成火焰、分裂再放一次；同一袋沒蓋到沒效
static func check_supports() -> String:
	var r: float = SkillDefs.SKILLS.whirlwind.radius
	var far_d := r * 1.3
	# 延長：本來打不到的距離打得到（1 格的修飾整件透明，蓋在旋風斬那格）
	for with_support in [false, true]:
		var s := _setup(&"swordShield")
		var w: World = s[0]
		var p: Player = s[1]
		var key: Dictionary = p.loadout.key_bags()[0]
		_put_at(p, key, &"whirlwind", Vector2i.ZERO)
		if with_support and _put_at(p, key, &"extend_support", Vector2i.ZERO) == &"":
			return "延長（透明格）應蓋得上旋風斬那格"
		var e := LootChecks._item_dummy(w, Vector2(0, far_d), 100000.0)
		var hp0 := e.hp
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.slot_bit(0)), 1)
		if (e.hp < hp0) != with_support:
			return "延長%s時 %.1f 單位的怪%s打到" % ["蓋著" if with_support else "沒有", far_d, "應" if with_support else "不該"]
	# 火焰化：透明格蓋住才改成火焰；同一袋但透明格沒蓋到技能就沒效
	for covered in [true, false]:
		var s := _setup(&"swordShield")
		var w: World = s[0]
		var p: Player = s[1]
		var key: Dictionary = p.loadout.key_bags()[0]
		_put_at(p, key, &"whirlwind", Vector2i.ZERO)
		if _put_at(p, key, &"fire_support", Vector2i(0, 0 if covered else 1)) == &"":
			return "火焰化放不進按鍵袋（%s）" % ("蓋住" if covered else "下一排")
		LootChecks._item_dummy(w, Vector2(0, 1.5), 100000.0)
		var events: Array[Dictionary] = []
		_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.slot_bit(_slot_of(p, &"whirlwind"))), 1, events)
		var fire := _named(events, "entity:damaged").any(func(ev: Dictionary) -> bool: return ev.get("damage_type", &"phys") == &"fire")
		if fire != covered:
			return "火焰化%s時旋風斬%s是火焰傷害" % ["蓋住" if covered else "同一袋沒蓋到", "應" if covered else "不該"]
	# 分裂：SPLIT_DELAY 秒後再打一次（傷害 SPLIT_MUL）
	var s3 := _setup(&"swordShield")
	var w3: World = s3[0]
	var p3: Player = s3[1]
	var k3: Dictionary = p3.loadout.key_bags()[0]
	_put_at(p3, k3, &"whirlwind", Vector2i.ZERO)
	_put_at(p3, k3, &"split_support", Vector2i.ZERO)
	var e3 := LootChecks._item_dummy(w3, Vector2(0, 1.5), 100000.0)
	e3.set_resists({})
	var ev3: Array[Dictionary] = []
	_run_collect(w3, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.slot_bit(0)), 1, ev3)
	_run_collect(w3, _cmd(Vector2.ZERO), roundi(SkillBehaviors.SPLIT_DELAY / DT) + 2, ev3)
	var hits := _named(ev3, "entity:damaged").filter(func(ev: Dictionary) -> bool: return ev.target_id == e3.id)
	if hits.size() != 2 or absf(hits[1].amount / hits[0].amount - SkillBehaviors.SPLIT_MUL) > 0.02:
		return "分裂：應打 2 次、第二次 ×%.1f：%s" % [SkillBehaviors.SPLIT_MUL, hits.map(func(ev: Dictionary) -> float: return ev.amount)]
	# 耗魔：一般修飾每顆 × (1 + 強度 × SUPPORT_MANA)，節能 × mana_mul；技能欄顯示與實際扣的一樣（1 格的技能只蓋得下一個透明格，相乘在下面的效果驗）
	var s4 := _setup(&"swordShield")
	var w4: World = s4[0]
	var p4: Player = s4[1]
	var k4: Dictionary = p4.loadout.key_bags()[0]
	_put_at(p4, k4, &"whirlwind", Vector2i.ZERO)
	var base_cost := ActiveSlots.mana_cost(p4, p4.slots.get_slot(p4, 0))
	var ext := _put_at(p4, k4, &"extend_support", Vector2i.ZERO)
	var with_extend := ActiveSlots.mana_cost(p4, p4.slots.get_slot(p4, 0))
	var want_extend: float = base_cost * (1.0 + ItemDefs.ITEMS.extend_support.power * SkillDefs.SUPPORT_MANA)
	p4.loadout.remove_item(p4, ext)
	if _put_at(p4, k4, &"conserve_support", Vector2i.ZERO) == &"":
		return "節能放不進按鍵袋"
	var cons := ActiveSlots.mana_cost(p4, p4.slots.get_slot(p4, 0))
	var want_cons: float = base_cost * ItemDefs.support_of(&"conserve_support").mana_mul
	p4.set_stat_source(&"test", [[&"mana_regen", Stats.MUL, 0.0]])
	var m0 := p4.mana
	_run(w4, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.slot_bit(0)), 1)
	if absf(with_extend - want_extend) > 1e-3 or absf(cons - want_cons) > 1e-3 or absf(m0 - p4.mana - want_cons) > 1e-3:
		return "修飾耗魔：旋風斬 %.1f，蓋延長應 %.2f（%.2f）、換成節能應 %.2f（%.2f）、實際扣 %.2f" % [base_cost, want_extend, with_extend, want_cons, cons, m0 - p4.mana]
	_note("修飾耗魔：旋風斬 %.1f → 延長 %.2f、節能 %.2f" % [base_cost, with_extend, cons])
	return _check_clear_cells()


# 透明格（第 8 步 f）：擺放（透明格可以蓋技能或放空格、不跟透明格疊、底下不能放非技能）、蓋住多格技能的效果（延長、霜化、耗魔相乘）、
# 羈絆只算實心格、同一袋沒蓋到沒效、自動擺放先找蓋得到的技能
static func _check_clear_cells() -> String:
	var s := _setup(&"swordShield")
	var w: World = s[0]
	var p: Player = s[1]
	var b := _bag(p, &"hit", &"left")
	var inv := Inventory.for_bag(b)
	var quiver := _put_at(p, b, &"blast_quiver", Vector2i.ZERO)   # 爆裂箭袋：i3 的爆炸，占 (0~2, 0)
	if quiver == &"":
		return "爆裂箭袋放不進命中袋"
	if not inv.fits(&"whetstone", Vector2i(1, 1), 0) or _put_at(p, b, &"extend_support", Vector2i(1, 1)) == &"":
		return "1 格的修飾應放得進空格"
	if inv.fits(&"whetstone", Vector2i(1, 1), 0):
		return "透明格底下不能放數值道具"
	if inv.fits(&"split_support", Vector2i(1, 1), 1) or inv.fits(&"split_support", Vector2i(1, 0), 0):
		return "透明格不能疊透明格、實心格不能放在技能上"
	var stray := inv.find_spot(&"whetstone")
	if stray.is_empty():
		return "還有空格時數值道具應放得進"
	p.loadout.remove_item(p, inv.find(inv.occupied().get(Vector2i(1, 1), &"")).get("uid", &""))
	# 延長蓋 (0, 0)、霜化直放蓋 (1, 0)（透明格在上、實心格在下）：兩個都蓋住箭袋
	var ext := _put_at(p, b, &"extend_support", Vector2i.ZERO)
	var cold := _put_at(p, b, &"cold_support", Vector2i(1, 0), 1)
	if ext == &"" or cold == &"":
		return "延長、霜化應蓋得上爆裂箭袋（%s、%s）" % [ext, cold]
	var on := ActiveSlots.mod_ids_on(b, inv.find(quiver))
	if on.size() != 2:
		return "爆裂箭袋上應有 2 個有作用的修飾：%s" % [on]
	var want_cost := BagTriggers.effect_mana(&"blast_quiver") * (1.0 + ItemDefs.ITEMS.extend_support.power * SkillDefs.SUPPORT_MANA) * (1.0 + ItemDefs.ITEMS.cold_support.power * SkillDefs.SUPPORT_MANA)
	if absf(BagTriggers.effect_cost(b, inv.find(quiver)) - want_cost) > 1e-3:
		return "蓋兩個修飾的耗魔應相乘 %.2f，實際 %.2f" % [want_cost, BagTriggers.effect_cost(b, inv.find(quiver))]
	if p.loadout.bond_counts.get(&"cold", 0) != 1:
		return "霜化只有實心格算冰霜羈絆，應 1 格：%s" % [p.loadout.bond_counts]
	# 放一次：爆炸半徑 × 1.5（原本打不到的打得到）、改成冰霜傷害、耗魔照相乘
	var radius: float = ItemDefs.PROCS.explode.radius
	var center := LootChecks._item_dummy(w, Vector2(0, 3), 100000.0)
	var far := LootChecks._item_dummy(w, Vector2(0, 3 + radius * 1.3), 100000.0)
	var far_hp := far.hp
	p.mana = p.max_mana()
	var m0 := p.mana
	w.events.clear()
	BagTriggers.run_bag(w, p, b, center, 10.0)
	var cold_hit := _named(w.events, "entity:damaged").any(func(ev: Dictionary) -> bool: return ev.get("damage_type", &"") == &"cold")
	if far.hp >= far_hp or not cold_hit or absf(m0 - p.mana - want_cost) > 1e-3:
		return "延長 + 霜化的爆炸：%.1f 外的怪%s打到、冰霜傷害 %s、耗魔 %.2f（應 %.2f）" % [radius * 1.3, "有" if far.hp < far_hp else "沒", cold_hit, m0 - p.mana, want_cost]
	# 箭袋搬走：修飾留在原地、失效
	p.loadout.remove_item(p, quiver)
	if inv.find(ext).is_empty() or not inv.covered_by(inv.find(ext)).is_empty():
		return "技能拿走後修飾應留在原地、不再蓋到東西"
	# 自動擺放：修飾先找蓋得到、有作用的技能
	var s2 := _setup(&"swordShield")
	var p2: Player = s2[1]
	var k2: Dictionary = p2.loadout.key_bags()[0]
	_put_at(p2, k2, &"whirlwind", Vector2i(1, 1))
	var auto := p2.loadout.auto_place(&"extend_support")
	if auto.get("where", -9) != p2.loadout.bags.find(k2) or auto.get("spot", {}).get("cell", Vector2i(-1, -1)) != Vector2i(1, 1):
		return "延長自動擺放應蓋在按鍵袋 (1, 1) 的旋風斬上：%s" % [auto]
	_note("透明格：爆裂箭袋蓋延長 + 霜化 耗魔 %.2f → %.2f" % [BagTriggers.effect_mana(&"blast_quiver"), want_cost])
	return ""
