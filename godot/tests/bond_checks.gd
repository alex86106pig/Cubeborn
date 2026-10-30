# 羈絆的檢查（Build 改版第 5 步）：每個羈絆一個子檢查，依序湊到每一階驗證效果；數字從 BondDefs 讀
# 傷害用道具效果的傷害（proc）打，才不會觸發身上機率型的命中道具
class_name BondChecks
extends CheckKit


static func _bdummy(w: World, at: Vector2, hp: float = 1000.0) -> Enemy:
	var e := LootChecks._item_dummy(w, at, hp)
	e.set_resists({})
	return e


# 長劍＋木盾，依序鑲上 ids（自動擺放）；有一件沒鑲上武器就回傳錯誤
static func _setup(ids: Array) -> Array:
	var w := _new_world()
	var p := _player(w)
	p.loadout.equip_new(p, &"longsword")
	p.loadout.equip_offhand_new(p, &"woodShield")
	for id: StringName in ids:
		var uid := p.add_item(id)
		if uid == &"" or p.loadout.find_item(uid).get("where", Loadout.BAG) == Loadout.BAG:
			return [w, p, "%s 沒有鑲上武器" % id]
	return [w, p, ""]


static func _hit(w: World, p: Player, e: Enemy, damage: float, type: StringName, extra := {}) -> float:
	var before := e.hp
	var hit := ItemEffects.proc_hit(damage, e, Color.WHITE, 0.0, type)
	hit.merge(extra, true)
	Combat.apply_damage(w, p, e, hit)
	return before - e.hp


static func _ids(bond: StringName, n: int) -> Array:
	var out := []
	for id: StringName in BOND_ORDER[bond]:
		if out.size() < n:
			out.append(id)
	return out


# 測試用的鑲法順序（形狀放得進長劍＋木盾；避開會自己動的鬼火燈與會擾亂的道具）
const BOND_ORDER := {
	&"phys": [&"whetstone", &"light_gloves", &"loaded_dice", &"lead_weight", &"hound_collar", &"war_drum", &"berserker_charm", &"pact_of_dead", &"sleeve_knife", &"rift_blade"],
	&"fire": [&"ember_core", &"lamp_oil", &"powder_pouch", &"incense_burner", &"oil_jar", &"blast_quiver", &"tomb_heart"],
	&"cold": [&"frost_crystal", &"cold_iron_charm", &"winter_charm", &"frost_boots", &"ice_coffin_nail", &"frost_bell", &"frost_heart"],
	&"guard": [&"stale_bread", &"bandage_roll", &"rusty_breastplate", &"thorn_mail", &"bone_buckler", &"iron_cloak", &"guardian_spirit", &"resurrection_cross", &"obsidian_skin"],
	&"wisp": [&"white_wisp_lamp", &"wick", &"soul_banner", &"wisp_jar", &"blue_wisp_lamp", &"red_wisp_lamp", &"nether_lamp", &"soul_eater_lamp", &"wisp_lantern"],
}


static func _at_tier(bond: StringName, t: int) -> Array:
	return _setup(_ids(bond, BondDefs.BONDS[bond].thresholds[t - 1]))


# 物理：第 1 階物理傷害、第 2 階失衡（累積到門檻、失衡中不能動與加傷）、第 3 階擊退與撞怪、第 4 階無視物理抗性、第 5 階必爆擊與處決
static func check_phys() -> String:
	var c: Dictionary = BondDefs.BONDS.phys.params
	var s := _at_tier(&"phys", 1)
	if s[2] != "":
		return s[2]
	var p: Player = s[1]
	if absf(p.stats.value(&"phys_damage") - (1.0 + c.phys_damage)) > EPS:
		return "物理 1 階：物理傷害應為 %.2f，實際 %.2f" % [1.0 + c.phys_damage, p.stats.value(&"phys_damage")]
	s = _at_tier(&"phys", 2)
	if s[2] != "":
		return s[2]
	var w: World = s[0]
	p = s[1]
	var a := _bdummy(w, Vector2(0, 5), 1000.0)
	var need: float = a.max_hp * c.poise_ratio
	var dealt := 0.0
	for i in 20:
		if a.stagger_timer > 0.0:
			break
		var before := a.hp
		Combat.apply_damage(w, p, a, {"damage": 40.0, "damage_type": &"phys"})
		dealt += before - a.hp
	if a.stagger_timer <= 0.0 or dealt + EPS < need:
		return "物理 2 階：累積 %.0f 才該失衡，實際累積 %.0f、失衡 %.2f 秒" % [need, dealt, a.stagger_timer]
	var plain := _bdummy(w, Vector2(6, 5))
	var normal := _hit(w, p, plain, 50.0, &"phys")
	var more := _hit(w, p, a, 50.0, &"phys")
	if absf(more - normal * c.stagger_damage_taken) > 0.01:
		return "失衡的怪受到的傷害應 ×%.2f：%.2f vs %.2f" % [c.stagger_damage_taken, more, normal]
	var at := a.pos
	_run(w, _cmd(Vector2.ZERO), roundi(c.stagger_time / DT) - 5)
	if a.pos.distance_to(at) > 0.05:
		return "失衡中不該移動：移動 %.2f" % a.pos.distance_to(at)
	# 第 3 階：擊退屬性；被打退撞到旁邊的怪，兩隻各受那一下的 ram_ratio
	s = _at_tier(&"phys", 3)
	if s[2] != "":
		return s[2]
	w = s[0]
	p = s[1]
	if absf(p.stats.value(&"knockback") - (1.0 + c.knockback + _item_knockback(p))) > EPS:   # 百分比同類相加
		return "物理 3 階：擊退應 +%.0f%%，實際 %.2f" % [c.knockback * 100, p.stats.value(&"knockback")]
	var x := _bdummy(w, Vector2(0, 5))
	var y := _bdummy(w, Vector2(0, 5 + x.radius + 1.0))
	var x0 := x.hp
	var y0 := y.hp
	Combat.apply_damage(w, p, x, {"damage": 40.0, "damage_type": &"phys", "knockback": 30.0, "origin": Vector2(0, 4)})
	var first := x0 - x.hp
	_run(w, _cmd(Vector2.ZERO), roundi(c.ram_window / DT))
	if y.hp >= y0 or x0 - x.hp <= first + EPS:
		return "物理 3 階：被打退撞到旁邊的怪，兩隻都要受傷：前面 %.1f → %.1f、後面 %.1f → %.1f" % [x0, x.hp, y0, y.hp]
	# 第 4 階：物理抗性 50% 的怪，只算 50% × (1 − resist_pierce)
	s = _at_tier(&"phys", 4)
	if s[2] != "":
		return s[2]
	w = s[0]
	p = s[1]
	var armored := _bdummy(w, Vector2(0, 5))
	armored.set_resists({&"phys": 0.5})
	var bare := _bdummy(w, Vector2(6, 5))
	var got := _hit(w, p, armored, 100.0, &"phys") / _hit(w, p, bare, 100.0, &"phys")
	var want: float = (1.0 - 0.5 * (1.0 - c.resist_pierce))
	if absf(got - want) > 0.01:
		return "物理 4 階：物理抗性 50%% 的怪應受 %.2f 倍，實際 %.2f" % [want, got]
	# 第 5 階：打失衡的怪必爆擊；失衡中生命低於 execute_hp 的直接處決（Boss 不會）
	s = _at_tier(&"phys", 5)
	if s[2] != "":
		return s[2]
	w = s[0]
	p = s[1]
	var st := _bdummy(w, Vector2(0, 5))
	st.stagger_timer = 1.0
	w.events.clear()
	Combat.apply_damage(w, p, st, {"damage": 10.0, "damage_type": &"phys"})
	if not _named(w.events, "entity:damaged").any(func(ev: Dictionary) -> bool: return ev.is_crit):
		return "物理 5 階：打失衡的怪應必爆擊"
	st.hp = st.max_hp * c.execute_hp * 0.9
	Combat.apply_damage(w, p, st, {"damage": 1.0, "damage_type": &"phys"})
	if not st.is_dead:
		return "物理 5 階：失衡中生命低於 %.0f%% 應直接處決" % (c.execute_hp * 100)
	return ""


# 道具本身的擊退百分比（鉛墜）
static func _item_knockback(p: Player) -> float:
	var v := 0.0
	for it: Dictionary in p.items:
		for eff: Dictionary in ItemDefs.ITEMS[it.id].effects:
			if eff.get("stat", &"") == &"knockback":
				v += eff.value
	return v


# 火焰：沒有羈絆時火焰傷害不點燃、道具點燃最多 1 層；第 1 階疊到 max_stacks、每跳 = 層數 × 每層；第 2 階疊滿爆炸並清空；第 3 階死亡時傳給最近的 spread_count 隻
static func check_fire() -> String:
	var c: Dictionary = BondDefs.BONDS.fire.params
	var s := _setup([])
	var w: World = s[0]
	var p: Player = s[1]
	var a := _bdummy(w, Vector2(0, 5))
	_hit(w, p, a, 1.0, &"fire")
	if a.burn_stacks != 0:
		return "沒有火焰羈絆時火焰傷害不該點燃，實際 %d 層" % a.burn_stacks
	for i in 3:
		BondEffects.add_burn(w, p, a, 1)   # 焚香爐、火油罐這類道具
	if a.burn_stacks != 1:
		return "沒有火焰羈絆時道具點燃最多 1 層，實際 %d" % a.burn_stacks
	s = _at_tier(&"fire", 1)
	if s[2] != "":
		return s[2]
	w = s[0]
	p = s[1]
	a = _bdummy(w, Vector2(0, 5))
	for i in c.max_stacks + 2:
		_hit(w, p, a, 1.0, &"fire")
	var per: float = BondEffects.elem_damage(p, c.stack_pct) * p.stats.value(&"burn_damage")
	if a.burn_stacks != c.max_stacks or absf(a.burn_tick_damage - per * c.max_stacks * Enemy.BURN_TICK) > EPS:
		return "火焰 1 階：應疊到 %d 層、每跳 %.2f，實際 %d 層、%.2f" % [c.max_stacks, per * c.max_stacks * Enemy.BURN_TICK, a.burn_stacks, a.burn_tick_damage]
	s = _at_tier(&"fire", 2)
	if s[2] != "":
		return s[2]
	w = s[0]
	p = s[1]
	a = _bdummy(w, Vector2(0, 5))
	var b := _bdummy(w, Vector2(0, 5 + c.burst_radius * 0.5))
	var b0 := b.hp
	for i in c.max_stacks:
		_hit(w, p, a, 1.0, &"fire")
	if a.burn_stacks != 0 or b.hp >= b0:
		return "火焰 2 階：疊滿 %d 層應爆炸（清空層數、旁邊的怪受傷）：剩 %d 層、旁邊 %.1f → %.1f" % [c.max_stacks, a.burn_stacks, b0, b.hp]
	s = _at_tier(&"fire", 3)
	if s[2] != "":
		return s[2]
	w = s[0]
	p = s[1]
	a = _bdummy(w, Vector2(0, 5), 50.0)
	var n1 := _bdummy(w, Vector2(1.5, 5))
	var n2 := _bdummy(w, Vector2(-1.5, 5))
	var n3 := _bdummy(w, Vector2(0, 5 + c.spread_range - 0.5))
	var far := _bdummy(w, Vector2(0, 5 + c.spread_range + 2.0))
	for i in 3:
		_hit(w, p, a, 1.0, &"fire")
	var stacks := a.burn_stacks
	_hit(w, p, a, 1000.0, &"phys")
	if not a.is_dead or n1.burn_stacks != stacks or n2.burn_stacks != stacks or n3.burn_stacks != 0 or far.burn_stacks != 0:
		return "火焰 3 階：燃燒 %d 層的怪死掉應傳給最近的 %d 隻：%d / %d / %d / 遠的 %d" % [stacks, c.spread_count, n1.burn_stacks, n2.burn_stacks, n3.burn_stacks, far.burn_stacks]
	return ""


# 冰霜：沒有羈絆時冰霜傷害不冰冷、道具最多 1 層；第 1 階疊冰冷、每層減速（含凜冬護符）；第 2 階疊滿凍結、打凍結的怪加傷並碎冰；第 3 階碎冰噴冰錐、凍結中被殺沒有死亡效果
static func check_cold() -> String:
	var c: Dictionary = BondDefs.BONDS.cold.params
	var s := _setup([])
	var w: World = s[0]
	var p: Player = s[1]
	var a := _bdummy(w, Vector2(0, 5))
	_hit(w, p, a, 1.0, &"cold")
	if a.chill_stacks != 0:
		return "沒有冰霜羈絆時冰霜傷害不該冰冷，實際 %d 層" % a.chill_stacks
	for i in 3:
		BondEffects.add_chill(w, p, a, 1)   # 冰棺釘、寒霜鈴這類道具
	if a.chill_stacks != 1:
		return "沒有冰霜羈絆時道具的冰冷最多 1 層，實際 %d" % a.chill_stacks
	s = _at_tier(&"cold", 1)
	if s[2] != "":
		return s[2]
	w = s[0]
	p = s[1]
	a = _bdummy(w, Vector2(0, 5))
	var speed0 := a.stats.value(&"move_speed")
	for i in 3:
		_hit(w, p, a, 1.0, &"cold")
	var per: float = c.slow_per_stack + p.stats.value(&"chill_slow")
	if a.chill_stacks != 3 or absf(a.stats.value(&"move_speed") - speed0 * (1.0 - 3 * per)) > EPS:
		return "冰霜 1 階：3 層冰冷每層減速 %.2f：%d 層、移速 %.2f → %.2f" % [per, a.chill_stacks, speed0, a.stats.value(&"move_speed")]
	s = _at_tier(&"cold", 2)
	if s[2] != "":
		return s[2]
	w = s[0]
	p = s[1]
	a = _bdummy(w, Vector2(0, 5))
	for i in c.max_stacks:
		_hit(w, p, a, 1.0, &"cold")
	if absf(a.frozen_timer - c.freeze_time) > EPS or a.chill_stacks != 0:
		return "冰霜 2 階：疊滿 %d 層應凍結 %.1f 秒並清掉冰冷：凍結 %.2f、冰冷 %d" % [c.max_stacks, c.freeze_time, a.frozen_timer, a.chill_stacks]
	var bare := _bdummy(w, Vector2(6, 5))
	var shatter := _hit(w, p, a, 50.0, &"phys", {"no_status": false})
	var normal := _hit(w, p, bare, 50.0, &"phys")
	if absf(shatter - normal * c.shatter_mul) > 0.01 or a.frozen_timer > 0.0:
		return "冰霜 2 階：打凍結的怪應 ×%.1f 並解凍：%.2f vs %.2f、凍結 %.2f" % [c.shatter_mul, shatter, normal, a.frozen_timer]
	s = _at_tier(&"cold", 3)
	if s[2] != "":
		return s[2]
	w = s[0]
	p = s[1]
	a = _bdummy(w, Vector2(0, 5))
	for i in c.max_stacks:
		_hit(w, p, a, 1.0, &"cold")
	var shards_before := w.projectiles.size()
	_hit(w, p, a, 1.0, &"phys")
	if w.projectiles.size() - shards_before != c.shards:
		return "冰霜 3 階：碎冰應噴 %d 片冰錐，實際 %d" % [c.shards, w.projectiles.size() - shards_before]
	var z := _bdummy(w, Vector2(-6, 5), 10.0)
	for i in c.max_stacks:
		_hit(w, p, z, 0.01, &"cold")
	z.frozen_timer = c.freeze_time
	z.freeze_source_id = p.id
	z.hp = 0.5
	_hit(w, p, z, 5.0, &"lightning")
	if not z.is_dead or not z.no_death_effect:
		return "冰霜 3 階：凍結中被殺應沒有死亡效果"
	return ""


# 防禦：第 1 階護甲加成與招架回血、第 2 階招架後下一擊必爆擊並加傷、第 3 階招架消掉附近的箭與反彈傷害
static func check_guard() -> String:
	var c: Dictionary = BondDefs.BONDS.guard.params
	var s := _at_tier(&"guard", 1)
	if s[2] != "":
		return s[2]
	var w: World = s[0]
	var p: Player = s[1]
	var item_armor := 0.0
	for it: Dictionary in p.items:
		for eff: Dictionary in ItemDefs.ITEMS[it.id].effects:
			if eff.get("stat", &"") == &"armor":
				item_armor += eff.value
	if absf(p.stats.value(&"armor") - item_armor * (1.0 + c.armor)) > EPS:
		return "防禦 1 階：護甲應為 %.1f，實際 %.1f" % [item_armor * (1.0 + c.armor), p.stats.value(&"armor")]
	var foe := _bdummy(w, p.pos + Vector2(0, 2))
	p.facing = 0.0
	p.hp = p.max_hp * 0.5
	var hp0 := p.hp
	_parry(w, p, foe)
	if absf(p.hp - hp0 - p.max_hp * c.parry_heal) > 0.01:
		return "防禦 1 階：招架成功應回 %.0f%% 最大生命：%.1f → %.1f" % [c.parry_heal * 100, hp0, p.hp]
	s = _at_tier(&"guard", 2)
	if s[2] != "":
		return s[2]
	w = s[0]
	p = s[1]
	foe = _bdummy(w, p.pos + Vector2(0, 2))
	p.facing = 0.0
	_parry(w, p, foe)
	if absf(p.riposte_timer - c.riposte_time) > EPS:
		return "防禦 2 階：招架後應有 %.1f 秒反擊時間，實際 %.2f" % [c.riposte_time, p.riposte_timer]
	var t := _bdummy(w, Vector2(6, 5))
	var t0 := t.hp
	Combat.apply_damage(w, p, t, {"damage": 10.0, "damage_type": &"phys"})
	var want := LootChecks._dealt_exact(t, 10.0 * c.riposte_mul * p.stats.value(&"crit_damage"))
	if absf(t0 - t.hp - want) > 0.01 or p.riposte_timer > 0.0:
		return "防禦 2 階：招架後的下一擊應必爆擊 ×%.1f（%.2f），實際 %.2f、反擊時間剩 %.2f" % [c.riposte_mul, want, t0 - t.hp, p.riposte_timer]
	s = _at_tier(&"guard", 3)
	if s[2] != "":
		return s[2]
	w = s[0]
	p = s[1]
	foe = _bdummy(w, p.pos + Vector2(0, 2))
	var arrow := w.spawn_projectile(Projectile.new(w, {"owner": foe, "pos": p.pos + Vector2(1, 1), "direction": Vector2(0, -1), "speed": 0.0, "range": 10.0}))
	p.facing = 0.0
	_parry(w, p, foe)
	if not arrow.is_removed:
		return "防禦 3 階：招架衝擊波應消掉 %.1f 單位內的箭" % c.wave_radius
	p.block_time = -1.0
	p.invuln_timer = 0.0
	var f0 := foe.hp
	var p0 := p.hp + p.shield
	Combat.apply_damage(w, foe, p, {"damage": 20.0, "projectile": true})
	var took := p0 - p.hp - p.shield
	if took <= 0.0 or absf(f0 - foe.hp - LootChecks._dealt_exact(foe, took * c.reflect)) > 0.6:
		return "防禦 3 階：受到的傷害應反彈 %.0f%%：受傷 %.1f、攻擊者扣 %.1f" % [c.reflect * 100, took, f0 - foe.hp]
	return ""


# 讓 foe 打一下正在招架的 p
static func _parry(w: World, p: Player, foe: Enemy) -> void:
	p.block_time = 0.0
	p.parry_time = 0.0
	Combat.apply_damage(w, foe, p, {"damage": 5.0, "blockable": true})


# 鬼火：鬼火燈自帶；第 1 階其他鬼火道具各帶 1 顆；第 3 階加倍；碰到怪造成 pct；第 2 階定時衝向附近的怪
static func check_wisp() -> String:
	var c: Dictionary = BondDefs.BONDS.wisp.params
	var counts := [1, BondDefs.BONDS.wisp.thresholds[0], BondDefs.BONDS.wisp.thresholds[2]]
	for n: int in counts:
		var s := _setup(_ids(&"wisp", n))
		if s[2] != "":
			return s[2]
		var w: World = s[0]
		var p: Player = s[1]
		var want := BondEffects.wisp_plan(p).size()
		_run(w, _cmd(Vector2.ZERO), 1)
		var alive := p.wisps.filter(func(x: OrbitWisp) -> bool: return not x.is_removed).size()
		if alive != want or want == 0:
			return "鬼火 %d 件：應有 %d 顆鬼火，實際 %d" % [n, want, alive]
	# 1 件：繞著轉、碰到怪打 pct（秘術）
	var s1 := _setup(_ids(&"wisp", 1))
	var w1: World = s1[0]
	var p1: Player = s1[1]
	var near := _bdummy(w1, p1.pos + Vector2(c.orbit_radius, 0))
	var n0 := near.hp
	_run(w1, _cmd(Vector2.ZERO), roundi(TAU / c.orbit_speed / DT) + 2)
	var hit_once := LootChecks._dealt_exact(near, BondEffects.elem_damage(p1, c.pct) * p1.stats.value(&"wisp_damage"), &"arcane")
	if n0 - near.hp < hit_once - 0.01:
		return "鬼火轉一圈應碰到旁邊的怪（每下 %.2f），實際扣 %.2f" % [hit_once, n0 - near.hp]
	# 第 2 階：衝向 dash_range 內、轉圈碰不到的怪
	var s2 := _at_tier(&"wisp", 2)
	if s2[2] != "":
		return s2[2]
	var w2: World = s2[0]
	var p2: Player = s2[1]
	var target := _bdummy(w2, p2.pos + Vector2(0, c.orbit_radius + 3.0))
	var t0 := target.hp
	_run(w2, _cmd(Vector2.ZERO), roundi((c.dash_interval + 1.0) / DT))
	if target.hp >= t0:
		return "鬼火 2 階：應衝向 %.1f 單位外的怪" % (c.orbit_radius + 3.0)
	return ""
