# 骰子模式（DiceRun / DiceDefs，docs/系統說明.md §55）：結算、一場的流程（暫停、擲 / 鎖 / 重擲 / 完成、倒數、右鍵、打完選獎勵）、限時自動擲、Boss 開追也開一場
# 由 tests/check.gd 呼叫；每個 check_* 回傳 "" = 通過，否則是失敗原因
class_name DiceChecks
extends CheckKit


static func _dice_world() -> World:
	var w := _new_world()
	w.dice = DiceRun.new()
	w.dice.reset()
	w.dice.on_stage_start(w)   # 開局的擲骰次數（正式流程在 World.reset 的 _populate_floor 給）
	return w


# 菁英怪（稀有）：碰到才會免費擲骰；一般的怪群直接開打
static func _elite(w: World, at: Vector2) -> Enemy:
	var e := _spawn(w, &"grunt", at)
	e.set_rarity(&"rare", [])
	return e


# 一隻怪自己一群（地圖預放的怪群那樣登記），回傳群的編號
static func _lone_pack(w: World, e: Enemy) -> int:
	var i := w.packs.size()
	w.packs.append({"center": e.pos, "ids": [e.id], "awake": false, "template": &"plain", "loot": false, "ambush": false})
	e.pack_id = i
	return i


static func _op_cmd(op: Array) -> InputCmd:
	var c := _cmd(Vector2.ZERO)
	c.inv_ops = [op]
	return c


static func _wait(w: World, seconds: float) -> void:
	_run(w, _cmd(Vector2.ZERO), ceili(seconds / DT) + 1)


# 這一場的怪全倒之後：等清場（CLEAR_TIME）跑完，進選獎勵（或回到逛地圖）
static func _clear_out(w: World) -> void:
	_wait(w, DiceDefs.CLEAR_TIME)


# 開一場之後擲骰（限時到自動擲、自動完成）、倒數，跑到開打為止（最多 60 秒）
static func _to_fight(w: World) -> void:
	for i in ceili(60.0 / DT):
		if w.dice.phase == DiceRun.FIGHT:
			return
		_run(w, _cmd(Vector2.ZERO), 1)


# 結算：同一招（這把武器能放的）數幾次、別的武器的技能當空白、出現 BIG_FROM 次以上換大招、骰到好幾種可以自己選、效果面各幾面
static func check_dice_evaluate() -> String:
	var ww: Array[StringName] = DiceDefs.weapon_die(&"swordShield")
	var skill: StringName = ww[0]
	var eff: StringName = &"fx_dmg"
	var r := DiceDefs.evaluate([skill, skill, skill, eff, eff, DiceDefs.BLANK], &"swordShield")
	if r.skill != skill or r.count != 3 or r.effects.get(eff, 0) != 2:
		return "3 個 %s + 2 個傷害面 → %s ×%d、效果 %s" % [skill, r.skill, r.count, r.effects]
	var other: StringName = DiceDefs.weapon_die(&"dagger")[0]
	r = DiceDefs.evaluate([other, other, skill, DiceDefs.BLANK, DiceDefs.BLANK, DiceDefs.BLANK], &"swordShield")
	if r.skill != skill or r.count != 1:
		return "別的武器的技能（%s）應當空白：結果 %s ×%d" % [other, r.skill, r.count]
	r = DiceDefs.evaluate([skill, skill, skill, skill, DiceDefs.BLANK, DiceDefs.BLANK], &"swordShield")
	var big: StringName = DiceDefs.BIG.get(skill, skill)
	if r.count != DiceDefs.BIG_FROM or r.skill != big or r.base != skill:
		return "%d 個 %s 應換成大招 %s：結果 %s（底 %s）" % [DiceDefs.BIG_FROM, skill, big, r.skill, r.base]
	var pool := DiceDefs.skills_for(&"swordShield")
	var second: StringName = pool[1] if pool[0] == skill else pool[0]
	r = DiceDefs.evaluate([skill, skill, second, second, DiceDefs.BLANK, eff], &"swordShield", second)
	if r.skill != second or r.count != 2 or r.cands.size() != 2:
		return "骰到兩種、選 %s：結果 %s ×%d、候選 %s" % [second, r.skill, r.count, r.cands]
	if DiceDefs.effect_text(eff, 2).find("20") < 0:
		return "2 面傷害的說明應寫 20%%：%s" % DiceDefs.effect_text(eff, 2)
	return _check_combos(skill)


# 組合（DiceDefs.COMBOS）：順子（6 面不一樣、沒空白）、葫蘆（3 招 + 2 同效果，威力 +1 級但不換大招）、三條（×1.5）、兩對（各 +1 面）
static func _check_combos(skill: StringName) -> String:
	var B := DiceDefs.BLANK
	var r := DiceDefs.evaluate([skill, &"fx_dmg", &"fx_shield", &"fx_haste", &"fx_crit", &"fx_speed"], &"swordShield")
	if r.combos != [&"straight"] or r.tier_count != 2 or not is_equal_approx(r.effects[&"fx_dmg"], 2.0):
		return "順子：組合 %s、威力等級 %d（應 2）、傷害面 %s（應 2）" % [r.combos, r.tier_count, r.effects.get(&"fx_dmg")]
	r = DiceDefs.evaluate([skill, &"fx_dmg", &"fx_shield", &"fx_haste", &"fx_crit", B], &"swordShield")
	if r.combos.has(&"straight"):
		return "有空白不算順子"
	r = DiceDefs.evaluate([skill, skill, skill, &"fx_dmg", &"fx_dmg", B], &"swordShield")
	if r.combos != [&"full_house"] or r.tier_count != 4 or r.skill != skill:
		return "葫蘆：組合 %s、威力等級 %d（應 4）、招式 %s（3 個不換大招）" % [r.combos, r.tier_count, r.skill]
	r = DiceDefs.evaluate([&"fx_dmg", &"fx_dmg", &"fx_dmg", B, B, B], &"swordShield")
	if r.combos != [&"three"] or not is_equal_approx(r.effects[&"fx_dmg"], 4.5) or r.tier_count != 0:
		return "三條：組合 %s、傷害面 %s（應 4.5）、沒技能威力 %d" % [r.combos, r.effects.get(&"fx_dmg"), r.tier_count]
	r = DiceDefs.evaluate([&"fx_dmg", &"fx_dmg", &"fx_crit", &"fx_crit", B, B], &"swordShield")
	if r.combos != [&"two_pair"] or not is_equal_approx(r.effects[&"fx_dmg"], 3.0) or not is_equal_approx(r.effects[&"fx_crit"], 3.0):
		return "兩對：組合 %s、效果 %s（各應 3）" % [r.combos, r.effects]
	return ""


# 一場：怪群發現玩家就暫停（怪不動、冷卻不走）→ 擲（轉的時候不收操作）→ 鎖住的那顆重擲不變 → 完成：右鍵換成骰到的技能、效果面掛上 →
# 倒數完才開打 → 右鍵放骰到的技能（不耗魔、照威力、進冷卻）→ 這一場的怪全倒 → 3 選 1 獎勵（暫停）→ 選了回到逛地圖
static func check_dice_fight() -> String:
	var w := _dice_world()
	var p := _player(w)
	var e := _elite(w, p.pos + Vector2(8, 0))
	if p.slots.get_slot(p, ActiveSlots.DICE_INDEX) != null:
		return "還沒擲骰就有右鍵技能"
	w.alert_pack(_lone_pack(w, e), e, p)
	if w.dice.phase != DiceRun.ROLL or not w.dice.foes.has(e.id):
		return "菁英群發現玩家後應開始擲骰：phase %s、foes %s" % [w.dice.phase, w.dice.foes]
	var at := e.pos
	_wait(w, 1.0)
	if e.pos != at or w.dice.phase != DiceRun.ROLL:
		return "擲骰時怪應停住：%s → %s" % [at, e.pos]
	var s := w.dice.seat_of(p)
	_run(w, _op_cmd([InputCmd.OP_DICE_ROLL]), 1)
	if not s.rolled or s.roll_seq != 1 or w.dice.settle <= 0.0:
		return "按擲骰後應擲出、骰子在轉：rolled %s seq %d settle %.2f" % [s.rolled, s.roll_seq, w.dice.settle]
	_run(w, _op_cmd([InputCmd.OP_DICE_DONE]), 1)
	if s.done:
		return "骰子還在轉時不該收完成"
	_wait(w, DiceDefs.SETTLE_TIME)
	_run(w, _op_cmd([InputCmd.OP_DICE_LOCK, 0]), 1)
	var kept: int = s.face[0]
	_run(w, _op_cmd([InputCmd.OP_DICE_ROLL]), 1)
	if not s.locked[0] or s.face[0] != kept or s.rerolls != DiceDefs.REROLLS - 1 or s.roll_seq != 2:
		return "鎖住第 1 顆再重擲：鎖 %s、面 %d → %d、剩 %d 次、seq %d" % [s.locked[0], kept, s.face[0], s.rerolls, s.roll_seq]
	_wait(w, DiceDefs.SETTLE_TIME)
	# 擺好結果再完成：3 顆技能面、1 顆護盾、1 顆傷害、1 顆空白（開局的武器骰：技能、護盾、傷害、空白…）
	var die: Array = s.pool[0]
	var skill: StringName = die[0]
	s.face = [0, 0, 0, die.find(&"fx_shield"), die.find(&"fx_dmg"), die.find(DiceDefs.BLANK)]
	var dmg_before := p.stats.value(&"damage")
	_run(w, _op_cmd([InputCmd.OP_DICE_DONE]), 1)
	var slot: Variant = p.slots.get_slot(p, ActiveSlots.DICE_INDEX)
	if slot == null or slot.id != skill or not is_equal_approx(slot.power, DiceDefs.tier_of(3).mul):
		return "完成後右鍵應是 %s ×%s：%s" % [skill, DiceDefs.tier_of(3).mul, slot]
	var dmg_face: Array = DiceDefs.EFFECTS[&"fx_dmg"].stat
	if not is_equal_approx(p.stats.value(&"damage"), dmg_before * (1.0 + float(dmg_face[2]))):
		return "傷害面應加 %s：%.3f → %.3f" % [dmg_face[2], dmg_before, p.stats.value(&"damage")]
	if not is_equal_approx(p.basic_attack_mul, DiceDefs.BASIC_ATTACK_MUL):
		return "普攻倍率 %.2f（應 %s）" % [p.basic_attack_mul, DiceDefs.BASIC_ATTACK_MUL]
	if w.dice.phase != DiceRun.COUNTDOWN:
		return "全部擲完應倒數：%s" % w.dice.phase
	_wait(w, DiceDefs.COUNTDOWN * 0.5)
	if e.pos != at:
		return "倒數時怪應停住"
	_wait(w, DiceDefs.COUNTDOWN * 0.5)
	if w.dice.phase != DiceRun.FIGHT:
		return "倒數完應開打：%s" % w.dice.phase
	if not is_equal_approx(p.fight_shield, DiceDefs.EFFECTS[&"fx_shield"].value):
		return "開打時給開場護盾 %.1f（應 %s）" % [p.fight_shield, DiceDefs.EFFECTS[&"fx_shield"].value]
	var ctx: Dictionary = ActiveSlots.cast_context(p, slot)
	var expect: float = SkillDefs.damage_mul(skill, 1) * SkillDefs.scale_mul(slot.def, p.weapon) * DiceDefs.tier_of(3).mul
	if not is_equal_approx(ctx.mul, expect):
		return "右鍵的傷害倍率 %.3f，應 %.3f（威力 ×%s）" % [ctx.mul, expect, DiceDefs.tier_of(3).mul]
	var mana := p.mana
	_run(w, _cmd(Vector2.ZERO, Vector2(8, 0), InputCmd.BTN_SPECIAL), 1)
	_run(w, _cmd(Vector2.ZERO, Vector2(8, 0)), _wind_steps(skill) + 2)
	var cd := w.cooldowns.remaining(p.cd("player.special"))
	var want_cd := DiceDefs.cooldown_of(skill, 0.0)
	if cd <= 0.0 or cd > want_cd + EPS:
		return "放右鍵後 player.special 應進 %.2f 秒冷卻：剩 %.2f" % [want_cd, cd]
	if p.mana < mana - EPS:
		return "骰子的右鍵不該耗魔：%.1f → %.1f" % [mana, p.mana]
	e.die(p.id)
	if w.dice.phase != DiceRun.CLEAR or w.dice.is_frozen() or not s.offers.is_empty():
		return "這一場的怪全倒應先清場（世界照常動、還沒跳獎勵）：phase %s、暫停 %s、選項 %d" % [w.dice.phase, w.dice.is_frozen(), s.offers.size()]
	_wait(w, DiceDefs.CLEAR_TIME * 0.6)
	if w.dice.phase != DiceRun.CLEAR:
		return "清場 %.1f 秒內不該跳獎勵：%s" % [DiceDefs.CLEAR_TIME, w.dice.phase]
	_wait(w, DiceDefs.CLEAR_TIME * 0.5)
	if w.dice.phase != DiceRun.REWARD or s.offers.size() != DiceDefs.REWARD_CHOICES:
		return "清場完應 %d 選 1：phase %s、選項 %d" % [DiceDefs.REWARD_CHOICES, w.dice.phase, s.offers.size()]
	var kinds := {}
	for o0: Dictionary in s.offers:
		kinds[o0.kind] = true
	if kinds.size() != s.offers.size() or w.dice.reward_tier != &"elite":
		return "獎勵種類不重複、稀有度照菁英：%s、%s" % [s.offers.map(func(x: Dictionary) -> String: return String(x.kind)), w.dice.reward_tier]
	var tick := w.tick
	var cd_at := w.cooldowns.remaining(p.cd("player.special"))
	_wait(w, 0.5)
	if not w.dice.is_frozen() or not is_equal_approx(w.cooldowns.remaining(p.cd("player.special")), cd_at):
		return "選獎勵時應暫停（冷卻不走）：%.2f → %.2f" % [cd_at, w.cooldowns.remaining(p.cd("player.special"))]
	var pick := _simple_pick(s)
	var o: Dictionary = s.offers[pick]
	_run(w, _op_cmd([InputCmd.OP_DICE_REWARD, pick]), 1)
	if w.dice.phase != DiceRun.EXPLORE or not s.offers.is_empty():
		return "選完獎勵應回到逛地圖：%s（tick %d → %d）" % [w.dice.phase, tick, w.tick]
	match o.kind:
		&"item":
			if not p.stats.has_source(&"dice_item:0"):
				return "數值道具應掛上屬性來源 dice_item:0"
		&"die":
			if not s.pool.has(o.faces):
				return "新骰子應放進這場帶的骰子"
		&"weapon":
			if s.spares.size() != 1 or s.spares[0].uid != o.weapon.uid:
				return "新武器應放進備用武器"
	return ""


# 選一個不用再操作的獎勵（數值道具、新骰子、新武器；刻面要再點一面，另外檢查）
static func _simple_pick(s: DiceRun.Seat) -> int:
	for i in s.offers.size():
		if s.offers[i].kind in [&"item", &"die", &"weapon"]:
			return i
	return 0


static func _blank_count(s: DiceRun.Seat) -> int:
	var n := 0
	for die: Array in s.pool:
		n += die.count(DiceDefs.BLANK)
	return n


# 限時：沒動作 ROLL_TIME 秒自動擲，再 ROLL_TIME 秒自動完成，倒數後開打；Boss 開追也開一場；一般模式（dice = null）發現玩家不暫停
static func check_dice_auto() -> String:
	var w := _dice_world()
	var p := _player(w)
	var e := _elite(w, p.pos + Vector2(8, 0))
	w.alert_pack(_lone_pack(w, e), e, p)
	_wait(w, DiceDefs.ROLL_TIME)
	var s := w.dice.seat_of(p)
	if not s.rolled:
		return "%.0f 秒沒動作應自動擲" % DiceDefs.ROLL_TIME
	_wait(w, DiceDefs.SETTLE_TIME + DiceDefs.ROLL_TIME + DiceDefs.COUNTDOWN)
	if w.dice.phase != DiceRun.FIGHT or not s.done:
		return "自動擲完、限時到應自動完成並開打：%s" % w.dice.phase
	var wb := _dice_world()
	var b: Boss = _spawn(wb, &"boss", _player(wb).pos + Vector2(0, -12))
	b.fsm.change(&"patrol")
	b.aggro()
	if wb.dice.phase != DiceRun.ROLL or not wb.dice.foes.has(b.id):
		return "Boss 開追應開一場：%s %s" % [wb.dice.phase, wb.dice.foes]
	var wn := _new_world()
	var pn := _player(wn)
	var en := _spawn(wn, &"grunt", pn.pos + Vector2(8, 0))
	wn.alert_pack(_lone_pack(wn, en), en, pn)
	var at := en.pos
	_wait(wn, 2.0)
	if en.pos == at:
		return "一般模式發現玩家後怪應照常行動（沒有暫停）"
	return ""


# 骰子模式沒有背包（§55）：開局不放寶箱 / 祭壇 / 石棺 / 鍛造祭壇 / 鐵砧；殺菁英（連必掉武器的除錯開關）不掉袋子、金幣，也不給靈魂；
# 打倒 Boss 不掉遺物（武器照掉，帶自己的骰子）；HUD 開背包（Tab、遺物面板走的 set_bag_open）只開屬性面板。同一張地圖一般模式要有寶箱，這項才有在測東西
static func check_dice_no_loot() -> String:
	var plain := _new_world(4, false, &"graveyard_a")
	if plain.chests.is_empty():
		return "一般模式的 graveyard_a 應有寶箱（不然這項測不到東西）"
	var w := World.new(&"graveyard_a")
	w.spawn_packs = false
	w.dice = DiceRun.new()
	w.reset(4)
	w.spawner.finished = true
	_worlds.append(w)
	if not w.chests.is_empty() or not w.forges.is_empty() or not w.relics.is_empty():
		return "骰子模式開局不該有寶箱 / 鍛造祭壇 / 遺物：寶箱 %d、祭壇 %d、遺物 %d" % [w.chests.size(), w.forges.size(), w.relics.size()]
	var p := _player(w)
	w.debug_drop_all = true
	var e := _spawn(w, &"grunt", p.pos + Vector2(6, 0))
	e.set_rarity(&"rare", [])
	e.die(p.id)
	w.on_boss_defeated(_spawn(w, &"grunt", p.pos + Vector2(-6, 0)))
	_wait(w, 0.2)
	var others := w.pickups.filter(func(ip: ItemPickup) -> bool: return not ip.is_weapon())
	if not others.is_empty() or not w.relics.is_empty() or w.souls != 0:
		return "骰子模式殺怪 / 打倒 Boss 只該掉武器、沒有靈魂：其他掉落 %d 件、遺物 %d、靈魂 %d" % [others.size(), w.relics.size(), w.souls]
	if w.pickups.size() != 1 or (w.pickups[0] as ItemPickup).weapon.get("dice", []).size() != DiceDefs.DICE_COUNT:
		return "必掉武器的開關下殺怪應掉 1 把帶 6 顆骰子的武器：%d 件" % w.pickups.size()
	var cam := Camera3D.new()
	_scene_root().add_child(cam)
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w, cam)
	_scene_root().add_child(hud)
	hud.set_bag_open(true)
	var err := ""
	if hud.inventory_panel.visible or not hud.is_stats_panel_open():
		err = "骰子模式開背包應只開屬性面板：背包 %s、屬性 %s" % [hud.inventory_panel.visible, hud.is_stats_panel_open()]
	hud.queue_free()
	cam.queue_free()
	return err



# 每一場都擲、重擲券、附近的怪群併成一場（YangHsu 2026-11-19 改回構想的流程）：一般的怪群碰到也先暫停擲骰；
# MERGE_RANGE 內還沒醒的怪群一起醒、併進這一場，更遠的不會；免費重擲用完再丟沒留的花 1 張重擲券、0 張丟不了；
# 逛地圖、戰鬥中按 R 不會擲；打完 +CHARGES_PER_FIGHT；換關 +CHARGES_STAGE、最多 CHARGES_MAX
static func check_dice_charges() -> String:
	var w := _dice_world()
	var p := _player(w)
	var s := w.dice.seat_of(p)
	if w.dice.charges_of(p) != DiceDefs.CHARGES_STAGE:
		return "開局應有 %d 張重擲券：%d" % [DiceDefs.CHARGES_STAGE, w.dice.charges_of(p)]
	var e := _spawn(w, &"grunt", p.pos + Vector2(8, 0))
	var near := _spawn(w, &"grunt", e.pos + Vector2(0, 6))
	var far := _spawn(w, &"grunt", e.pos + Vector2(DiceDefs.MERGE_RANGE + 6.0, 0))
	var near_i := _lone_pack(w, near)
	var far_i := _lone_pack(w, far)
	w.alert_pack(_lone_pack(w, e), e, p)
	if w.dice.phase != DiceRun.ROLL or not w.dice.is_frozen():
		return "一般的怪群碰到也應先暫停擲骰：%s" % w.dice.phase
	if not w.dice.foes.has(near.id) or not w.packs[near_i].awake or w.dice.foes.has(far.id) or w.packs[far_i].awake:
		return "%.0f 內的怪群應一起醒、併進這一場，更遠的不會：foes %s、近的醒 %s、遠的醒 %s" % [DiceDefs.MERGE_RANGE, w.dice.foes, w.packs[near_i].awake, w.packs[far_i].awake]
	_run(w, _op_cmd([InputCmd.OP_DICE_ROLL]), 1)
	_wait(w, DiceDefs.SETTLE_TIME)
	_run(w, _op_cmd([InputCmd.OP_DICE_LOCK, 0]), 1)
	_run(w, _op_cmd([InputCmd.OP_DICE_ROLL]), 1)
	if s.roll_seq != 2 or s.rerolls != DiceDefs.REROLLS - 1 or w.dice.charges_of(p) != DiceDefs.CHARGES_STAGE:
		return "先用免費的重擲：seq %d、免費剩 %d、券 %d" % [s.roll_seq, s.rerolls, w.dice.charges_of(p)]
	_wait(w, DiceDefs.SETTLE_TIME)
	_run(w, _op_cmd([InputCmd.OP_DICE_ROLL]), 1)
	if s.roll_seq != 3 or w.dice.charges_of(p) != DiceDefs.CHARGES_STAGE - 1:
		return "免費的用完再丟應花 1 張重擲券：seq %d、券 %d" % [s.roll_seq, w.dice.charges_of(p)]
	_wait(w, DiceDefs.SETTLE_TIME)
	w.dice.charges[p.peer_id] = 0
	_run(w, _op_cmd([InputCmd.OP_DICE_ROLL]), 1)
	if s.roll_seq != 3:
		return "沒有重擲券時不能再丟：seq %d" % s.roll_seq
	_run(w, _op_cmd([InputCmd.OP_DICE_DONE]), 1)
	_wait(w, DiceDefs.COUNTDOWN)
	if w.dice.phase != DiceRun.FIGHT:
		return "倒數完應開打：%s" % w.dice.phase
	w.dice.charges[p.peer_id] = 1
	var seq := s.roll_seq
	_run(w, _op_cmd([InputCmd.OP_DICE_ROLL]), 1)
	if w.dice.phase != DiceRun.FIGHT or s.roll_seq != seq or w.dice.charges_of(p) != 1:
		return "戰鬥中按 R 不該擲：%s、seq %d → %d、券 %d" % [w.dice.phase, seq, s.roll_seq, w.dice.charges_of(p)]
	e.die(p.id)
	near.die(p.id)
	if w.dice.charges_of(p) != 1 + DiceDefs.CHARGES_PER_FIGHT:
		return "打完一場應 +%d 張：%d" % [DiceDefs.CHARGES_PER_FIGHT, w.dice.charges_of(p)]
	_clear_out(w)
	_run(w, _op_cmd([InputCmd.OP_DICE_REWARD, _simple_pick(s)]), 1)
	if w.dice.phase != DiceRun.EXPLORE:
		return "選完獎勵應回到逛地圖：%s" % w.dice.phase
	_run(w, _op_cmd([InputCmd.OP_DICE_ROLL]), 1)
	if w.dice.phase != DiceRun.EXPLORE:
		return "逛地圖按 R 不該擲：%s" % w.dice.phase
	w.dice.charges[p.peer_id] = 0
	w.dice.on_stage_start(w)
	if w.dice.charges_of(p) != DiceDefs.CHARGES_STAGE:
		return "換關應 +%d 張：%d" % [DiceDefs.CHARGES_STAGE, w.dice.charges_of(p)]
	w.dice.on_stage_start(w)
	if w.dice.charges_of(p) != DiceDefs.CHARGES_MAX:
		return "最多存 %d 張：%d" % [DiceDefs.CHARGES_MAX, w.dice.charges_of(p)]
	return ""



# 成長（YangHsu 2026-11-19）：刻技能面 3 選 1 再自己選刻在哪一面、刻效果面自己選；新骰子放進備用、自動換掉空白最多的那顆、可以換回來；
# 武器骰存在武器上：換武器時 6 顆一起換、刻過的面跟著舊武器走；備用武器滿了，拿到的直接換到手上、舊的掉在腳邊；地上的武器按 F 撿進備用；
# 獎勵稀有度看難度（Boss 不出白、一般群會出白）；門：遺物門 4 選 1、骰子門這一關重擲 +1（換關歸零），門上的字照骰子模式寫
static func check_dice_growth() -> String:
	var w := _dice_world()
	var p := _player(w)
	var s := w.dice.seat_of(p)
	var weapon_skills := DiceDefs.skills_for(p.weapon_id)
	# 刻技能面
	w.dice.phase = DiceRun.REWARD
	s.offers = [{"kind": &"carve_skill", "title": "", "desc": ""}]
	_run(w, _op_cmd([InputCmd.OP_DICE_REWARD, 0]), 1)
	var cands: Array = s.carve.get("skills", [])
	if cands.size() != mini(DiceDefs.CARVE_SKILL_CHOICES, weapon_skills.size()) or not cands.all(func(id: StringName) -> bool: return weapon_skills.has(id)):
		return "刻技能面應從武器能用的技能 %d 選 1：%s" % [DiceDefs.CARVE_SKILL_CHOICES, cands]
	if w.dice.phase != DiceRun.REWARD:
		return "還沒選刻在哪一面不該結束獎勵：%s" % w.dice.phase
	var pick: int = cands.size() - 1
	_run(w, _op_cmd([InputCmd.OP_DICE_CARVE, 0, 5, pick]), 1)
	if s.pool[0][5] != cands[pick] or s.wdice[0][5] != cands[pick] or w.dice.phase != DiceRun.EXPLORE:
		return "刻在第 1 顆第 6 面應是 %s（武器骰也改到）：%s、%s" % [cands[pick], s.pool[0][5], w.dice.phase]
	if s.wdice[1][5] == cands[pick] and DiceDefs.weapon_die(p.weapon_id)[5] != cands[pick]:
		return "刻面只改那一顆，不該改到其他武器骰"
	# 刻效果面
	w.dice.phase = DiceRun.REWARD
	s.offers = [{"kind": &"carve_effect", "title": "", "desc": "", "face": &"fx_crit"}]
	_run(w, _op_cmd([InputCmd.OP_DICE_REWARD, 0]), 1)
	_run(w, _op_cmd([InputCmd.OP_DICE_CARVE, 3, 0, 0]), 1)
	if s.pool[3][0] != &"fx_crit":
		return "刻效果面應刻在選的那一面：%s" % s.pool[3][0]
	# 新骰子：放進備用、換掉空白最多的那顆；可以換回來
	var faces: Array[StringName] = [&"fx_dmg", &"fx_dmg", &"fx_dmg", &"fx_dmg", &"fx_dmg", &"fx_dmg"]
	w.dice.phase = DiceRun.REWARD
	s.offers = [{"kind": &"die", "title": "", "desc": "", "faces": faces}]
	_run(w, _op_cmd([InputCmd.OP_DICE_REWARD, 0]), 1)
	var slot := s.carry.find(DiceDefs.DICE_COUNT)
	if s.loose.size() != 1 or slot < 0 or s.pool[slot] != faces:
		return "新骰子應放進備用並換上：備用 %d 顆、帶著 %s" % [s.loose.size(), s.carry]
	_run(w, _op_cmd([InputCmd.OP_DICE_CARRY, slot, slot]), 1)
	if not s.carry.has(slot) or s.carry.has(DiceDefs.DICE_COUNT) or s.carry.size() != DiceDefs.DICE_COUNT:
		return "換回原本的武器骰：%s" % [s.carry]
	# 換武器：武器骰跟著武器走
	var old_uid: StringName = StringName(p.active_weapon().uid)
	var carved: StringName = s.wdice[0][5]
	var inst := WeaponDropDefs.make(w.new_weapon_uid(), &"longbow", &"blue", w.rng)
	DiceRun.make_weapon_dice(inst)
	# 掉落 / 獎勵武器的武器骰：6 顆是開局骰子，稀有度決定幾顆把一面空白換成同一招
	for rar: StringName in DiceDefs.WEAPON_EXTRA_SKILLS:
		var wi := WeaponDropDefs.make(w.new_weapon_uid(), &"torch", rar, w.rng)
		DiceRun.make_weapon_dice(wi)
		var start := DiceDefs.weapon_die(&"torch")
		var plus := 0
		for d: Array in wi.dice:
			if d == Array(start):
				continue
			var want := start.duplicate()
			want[want.find(DiceDefs.BLANK)] = &"fire_nova"
			if d != Array(want):
				return "%s 火把的武器骰應是開局骰子或多一面火焰爆發：%s" % [rar, d]
			plus += 1
		if wi.dice.size() != DiceDefs.DICE_COUNT or plus != DiceDefs.WEAPON_EXTRA_SKILLS[rar]:
			return "%s 武器應有 %d 顆多一面技能：%d 顆" % [rar, DiceDefs.WEAPON_EXTRA_SKILLS[rar], plus]
	if not w.dice.receive_weapon(w, p, inst) or s.spares.size() != 1:
		return "拿到武器應先放進備用：%d 把" % s.spares.size()
	s.result = {"skill": &"", "count": 0, "effects": {}}
	_run(w, _op_cmd([InputCmd.OP_DICE_WEAPON, 0]), 1)
	s = w.dice.seat_of(p)
	if p.weapon_id != &"longbow" or not is_same(s.wdice, inst.dice) or not s.result.is_empty():
		return "換上備用武器：手上 %s、武器骰是新武器的、手上的結果清掉（%s）" % [p.weapon_id, s.result]
	if s.spares.size() != 1 or StringName(s.spares[0].uid) != old_uid or s.spares[0].dice[0][5] != carved:
		return "舊武器應回到備用、刻過的面跟著它：備用 %d 把" % s.spares.size()
	_run(w, _op_cmd([InputCmd.OP_DICE_WEAPON, 0]), 1)
	s = w.dice.seat_of(p)
	if StringName(p.active_weapon().uid) != old_uid or s.wdice[0][5] != carved:
		return "換回舊武器，刻過的面還在"
	# 地上的武器按 F 撿進備用；備用滿了直接換到手上、舊的掉在腳邊
	var ground := WeaponDropDefs.make(w.new_weapon_uid(), &"dagger", &"white", w.rng)
	DiceRun.make_weapon_dice(ground)
	var ip := w.drop_weapon(ground, p.pos + Vector2(0.5, 0))
	if not Interactables.use(w, p, ip.id) or s.spares.size() != 2 or not ip.is_removed:
		return "地上的武器按 F 應撿進備用：備用 %d 把" % s.spares.size()
	var third := WeaponDropDefs.make(w.new_weapon_uid(), &"staff", &"white", w.rng)
	w.dice.receive_weapon(w, p, third)
	var dropped := w.pickups.filter(func(x: ItemPickup) -> bool: return not x.is_removed and x.is_weapon())
	if p.weapon_id != &"staff" or s.spares.size() != DiceDefs.SPARE_WEAPONS or dropped.size() != 1 or StringName((dropped[0] as ItemPickup).weapon.uid) != old_uid:
		return "備用滿了應直接換上、舊的掉在腳邊：手上 %s、地上 %d 把" % [p.weapon_id, dropped.size()]
	# 稀有度看難度
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var seen := {&"normal": {}, &"boss": {}}
	for i in 300:
		for t: StringName in seen:
			seen[t][DiceDefs.roll_rarity(t, r)] = true
	if seen[&"boss"].has(&"white") or not seen[&"normal"].has(&"white"):
		return "Boss 的獎勵不該出白、一般群會出白：%s" % [seen]
	# 門
	w.dice.on_stage_start(w)
	w.dice.door_reward(w, &"relic")
	if w.dice.phase != DiceRun.REWARD or s.offers.size() != DiceDefs.REWARD_CHOICES or not w.dice.door_pick:
		return "遺物門應給一次 %d 選 1：%s、%d 個" % [DiceDefs.REWARD_CHOICES, w.dice.phase, s.offers.size()]
	_run(w, _op_cmd([InputCmd.OP_DICE_REWARD, _simple_pick(s)]), 1)
	w.dice.door_reward(w, &"dice")
	var ed := _spawn(w, &"grunt", _player(w).pos + Vector2(8, 0))
	w.alert_pack(_lone_pack(w, ed), ed, _player(w))   # 碰到怪開一場擲骰
	if s.rerolls != DiceDefs.REROLLS + DiceDefs.DOOR_REROLLS:
		return "骰子門這一關每次擲骰的重擲應 +%d：%d" % [DiceDefs.DOOR_REROLLS, s.rerolls]
	_wait(w, DiceDefs.SETTLE_TIME)
	_run(w, _op_cmd([InputCmd.OP_DICE_DONE]), 1)
	w.dice.on_stage_start(w)
	if w.dice.bonus_rerolls != 0:
		return "換關後門的重擲加成應歸零"
	if UiKit.reward_name(w, &"souls") != DiceDefs.DOOR_REWARDS[&"souls"].name or UiKit.reward_amount(w, &"souls") != "":
		return "骰子模式門上的字應是「%s」：%s%s" % [DiceDefs.DOOR_REWARDS[&"souls"].name, UiKit.reward_name(w, &"souls"), UiKit.reward_amount(w, &"souls")]
	return ""


# 骰子模式的介面放得下（介面最大檔）：骰子與武器面板（帶 6 顆 + 沒帶的 8 顆 + 備用武器 2 把）、桌邊配件（角色卡 + 技能欄 + 右下的牌一排）、4 張獎勵卡、刻面（6 顆 × 6 面 + 3 個技能）、物理擲骰畫面
static func check_dice_panels() -> String:
	var w := _dice_world()
	var p := _player(w)
	var s := w.dice.seat_of(p)
	for i in 8:
		s.loose.append(DiceDefs.make_die(&"blue", DiceDefs.skills_for(p.weapon_id), w.rng))
	for b: StringName in [&"longbow", &"staff"]:
		var inst := WeaponDropDefs.make(w.new_weapon_uid(), b, &"purple", w.rng)
		DiceRun.make_weapon_dice(inst)
		w.dice.receive_weapon(w, p, inst)
	var cam := Camera3D.new()
	_scene_root().add_child(cam)
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w, cam)
	_scene_root().add_child(hud)
	var base := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	var room: Vector2 = base / (SettingsPanel.UI_SCALES.max() * SettingsPanel.BASE_UI_SCALE)
	var err := ""
	var lo: DiceLoadoutPanel = hud.dice_loadout
	lo.refresh(w, p)
	var need: Vector2 = lo.get_combined_minimum_size()
	if need.x > room.x or need.y > room.y:
		err = "骰子與武器面板 %s 超出介面最大檔 %s" % [need, room]
	if err == "":   # 桌邊配件：效果 6 種、組合全中時，左下角色卡、置中的技能欄、右下的牌放在同一排不疊到
		var fx := {}
		for id: StringName in DiceDefs.EFFECTS.keys().slice(0, DiceDefs.DICE_COUNT):
			fx[id] = 2.0
		s.result = {"skill": DiceDefs.skills_for(p.weapon_id)[0], "count": 3, "tier_count": 3, "effects": fx, "combos": DiceDefs.COMBOS.keys()}
		var props: DiceProps = hud.dice_props
		props.refresh(w, p, false)
		hud._skill_bar.refresh(w, p)
		var side := maxf(props.hero.get_combined_minimum_size().x, props.hand.get_combined_minimum_size().x)
		var bar: float = hud._skill_bar.get_combined_minimum_size().x
		var track: float = props.track.get_combined_minimum_size().x
		if not props.hand.visible or side * 2.0 + bar + 16.0 * 4.0 > room.x or track > room.x:
			err = "桌邊配件放不下：角色卡 / 牌最寬 %.0f ×2 + 技能欄 %.0f 超出介面最大檔 %s（牌顯示 %s）、階段條 %.0f" % [side, bar, room, props.hand.visible, track]
		s.result = {}
	if err == "":
		w.dice.door_reward(w, &"relic")
		var dp: DicePanel = hud.dice_panel
		dp.refresh(w, p, 0.016)
		need = dp._reward_box.get_combined_minimum_size()
		if not dp._reward_box.visible or dp._reward_cards.get_child_count() != DiceDefs.REWARD_CHOICES or need.x > room.x or need.y > room.y:
			err = "4 張獎勵卡 %s（%d 張、顯示 %s）超出介面最大檔 %s" % [need, dp._reward_cards.get_child_count(), dp._reward_box.visible, room]
		if err == "":
			s.offers = []
			s.carve = {"kind": &"carve_skill", "skills": DiceDefs.skills_for(p.weapon_id).slice(0, 3)}
			dp.refresh(w, p, 0.016)
			need = dp._carve_box.get_combined_minimum_size()
			if not dp._carve_box.visible or need.x > room.x or need.y > room.y:
				err = "刻面畫面 %s（顯示 %s）超出介面最大檔 %s" % [need, dp._carve_box.visible, room]
		if err == "":   # 物理擲骰的擲骰畫面：桌子、力道條、四個按鈕、結果與效果
			s.carve = {}
			w.dice.phase = DiceRun.EXPLORE
			w.dice.physics = true
			dp.physics = true
			var e := _elite(w, p.pos + Vector2(8, 0))
			w.alert_pack(_lone_pack(w, e), e, p)
			s.rolled = true
			s.result = {}
			dp.refresh(w, p, 0.016)
			need = dp._roll_box.get_combined_minimum_size()
			if not dp._roll_box.visible or not dp.table.visible or need.x > room.x or need.y > room.y:
				err = "物理擲骰畫面 %s（顯示 %s、桌子 %s）超出介面最大檔 %s" % [need, dp._roll_box.visible, dp.table.visible, room]
	hud.queue_free()
	cam.queue_free()
	return err


# 物理擲骰（DiceRun.physics + DiceTable）：
# 模擬層：擲了先等（不定面），OP_DICE_FACES 回報才定面、鎖住的不變；等超過 PHYSICS_WAIT 自己抽、流程不卡
# 桌子（真的跑 Godot 物理）：蓄力條、骰盅（滑鼠按住拖動放開）各丟一次，SETTLE_TIMEOUT 內停好、都在桌面上、朝上那面是平的（斜靠的有推開）、
# 回報的面 = 朝上的面；保留區的骰子不動、照原本的面；骰盅甩的時候骰子都在裡面
static func check_dice_physics() -> String:
	var w := _dice_world()
	w.dice.physics = true
	var p := _player(w)
	var s := w.dice.seat_of(p)
	var e := _elite(w, p.pos + Vector2(8, 0))
	w.alert_pack(_lone_pack(w, e), e, p)
	_run(w, _op_cmd([InputCmd.OP_DICE_ROLL]), 1)
	if not w.dice.waiting or s.roll_seq != 1:
		return "物理擲骰：按擲之後應等桌子回報：waiting %s、seq %d" % [w.dice.waiting, s.roll_seq]
	_run(w, _op_cmd([InputCmd.OP_DICE_FACES, 1, 2, 3, 4, 5, 0]), 1)
	if w.dice.waiting or s.face != [1, 2, 3, 4, 5, 0]:
		return "回報的面應照收：%s" % [s.face]
	_run(w, _op_cmd([InputCmd.OP_DICE_LOCK, 0]), 1)
	_run(w, _op_cmd([InputCmd.OP_DICE_ROLL]), 1)
	_run(w, _op_cmd([InputCmd.OP_DICE_FACES, 5, 5, 5, 5, 5, 5]), 1)
	if s.face[0] != 1 or s.face[1] != 5:
		return "重擲時鎖住的那顆不變：%s" % [s.face]
	var w2 := _dice_world()
	w2.dice.physics = true
	var p2 := _player(w2)
	var e2 := _elite(w2, p2.pos + Vector2(8, 0))
	w2.alert_pack(_lone_pack(w2, e2), e2, p2)
	_run(w2, _op_cmd([InputCmd.OP_DICE_ROLL]), 1)
	_wait(w2, DiceDefs.PHYSICS_WAIT + 0.1)
	if w2.dice.waiting or not w2.dice.seat_of(p2).rolled:
		return "桌子一直沒回報，%.0f 秒後模擬層應自己抽" % DiceDefs.PHYSICS_WAIT
	# 真的桌子
	var table := DiceTable.new()
	_scene_root().add_child(table)
	var faces: Array = []
	for i in DiceDefs.DICE_COUNT:
		faces.append(DiceDefs.weapon_die(&"swordShield"))
	table.set_faces(faces, &"swordShield")
	await (Engine.get_main_loop() as SceneTree).physics_frame
	var err := ""
	for attempt in 2:
		table.reset_round()
		table.can_throw = true
		var kept: Array[bool] = [attempt == 1, false, false, false, false, false]
		var shelf_face: Array[int] = [3, 0, 0, 0, 0, 0]
		table.set_kept(kept, shelf_face)
		var got: Array = []
		var on_settle := func(f: Array) -> void: got.append(f)
		table.settled.connect(on_settle)
		if attempt == 0:
			table.auto_throw(0.8)
		else:   # 骰盅：按住、往右上甩幾下、放開
			var c := Vector2(DiceTable.VIEW_SIZE) / 2.0
			table._gui_input(_mouse_button(c, true))
			for k in 24:
				var mv := InputEventMouseMotion.new()
				mv.position = c + Vector2(sin(k * 0.9) * 180.0 + k * 6.0, cos(k * 0.9) * 60.0)
				table._gui_input(mv)
				await (Engine.get_main_loop() as SceneTree).physics_frame
			for i in DiceDefs.DICE_COUNT:   # 甩的時候骰子都在骰盅裡（骰盅剛出現時曾把骰子彈飛到桌外）
				var d: RigidBody3D = table._dice[i]
				var off := d.position - table._cup.position
				if not kept[i] and (Vector2(off.x, off.z).length() > DiceTable.CUP_RADIUS or off.y > DiceTable.CUP_HEIGHT):
					err = "骰盅：甩的時候第 %d 顆跑出骰盅（離中心 %s）" % [i + 1, off]
			if err != "":
				break
			table._gui_input(_mouse_button(c + Vector2(320, -40), false))
		var frames := 0
		while got.is_empty() and frames < int((DiceTable.SETTLE_TIMEOUT + 1.0) * 60):
			await (Engine.get_main_loop() as SceneTree).physics_frame
			frames += 1
		table.settled.disconnect(on_settle)
		var how := "蓄力條" if attempt == 0 else "骰盅（保留 1 顆）"
		if got.is_empty():
			err = "%s：%.1f 秒內沒停好" % [how, DiceTable.SETTLE_TIMEOUT + 1.0]
			break
		var reported: Array = got[0]
		if reported != Array(table.up_faces()):
			err = "%s：回報的面 %s ≠ 朝上的面 %s" % [how, reported, table.up_faces()]
			break
		for i in DiceDefs.DICE_COUNT:
			var d: RigidBody3D = table._dice[i]
			if kept[i]:
				if reported[i] != 3 or d.position.z > DiceTable.SHELF_Z + 0.5:
					err = "%s：保留區那顆應不動、照原本的面 3：面 %d、位置 %s" % [how, reported[i], d.position]
			elif absf(d.position.x) > DiceTable.PLAY.x / 2.0 or absf(d.position.z) > DiceTable.PLAY.y / 2.0 or d.position.y < 0.2 or d.position.y > 1.6:
				err = "%s：第 %d 顆停在桌面外 %s" % [how, i + 1, d.position]
			elif DiceTable.up_dot(d) < DiceTable.FLAT_DOT and frames < int(DiceTable.SETTLE_TIMEOUT * 60):
				err = "%s：第 %d 顆斜靠著（朝上那面 %.2f）沒被推開" % [how, i + 1, DiceTable.up_dot(d)]
		if err != "":
			break
		_note("物理擲骰 %s：%.2f 秒停好、推了 %d 次、面 %s" % [how, frames / 60.0, table._nudges, reported])
	if err == "":
		err = await _check_stacked_die(table)
	table.queue_free()
	return err


# 平平疊在別顆上面的骰子：朝上的面已經定了，移到桌上的空位、面不變，不推、不重丟（斜著放不平的才重新決定）
static func _check_stacked_die(table: DiceTable) -> String:
	table.reset_round()
	table.can_throw = true
	var none: Array[bool] = [false, false, false, false, false, false]
	var zero: Array[int] = [0, 0, 0, 0, 0, 0]
	table.set_kept(none, zero)
	var got: Array = []
	var on_settle := func(f: Array) -> void: got.append(f)
	table.settled.connect(on_settle)
	table.auto_throw(0.8)
	var stacked := false
	var face := 2
	for frames in int((DiceTable.SETTLE_TIMEOUT + 1.0) * 60):
		await (Engine.get_main_loop() as SceneTree).physics_frame
		if not got.is_empty():
			break
		if not stacked and table._rest_frames >= 1:   # 都停住、還沒判定停好：全部平放排一排（隨機丟出來斜靠著的別顆也會被推，就量不到疊著的那顆），再把第 2 顆平平疊到第 1 顆正上方
			for i in table._dice.size():
				table._place(table._dice[i], Vector3(-DiceTable.PLAY.x / 2.0 + 1.6 + i * 1.75, 0.5, 0.8), 0, false)
			var under: RigidBody3D = table._dice[0]
			table._place(table._dice[1], under.position + Vector3(0, 1.0, 0), face, false)
			stacked = true
	table.settled.disconnect(on_settle)
	if not stacked or got.is_empty():
		return "疊骰子：沒疊上去（%s）或沒停好" % stacked
	var d: RigidBody3D = table._dice[1]
	if got[0][1] != face or d.position.y > DiceTable.ON_TABLE_Y or table._nudges != 0:
		return "平平疊著的骰子應移到桌上、面不變（%d）、不推：面 %d、高 %.2f、推了 %d 次" % [face, got[0][1], d.position.y, table._nudges]
	return ""


static func _mouse_button(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = pressed
	b.position = at
	return b


# 連線的擲骰錄播（§55「連線」）：A 桌開錄影、真的丟，錄影經過 var_to_bytes 送到 B 桌播；B 的骰子不跑物理、不送 settled，
# 播完停在跟 A 一樣的位置與面、撞擊聲跟著響；量一秒要送多少
static func check_dice_replay() -> String:
	var root := _scene_root()
	var a := DiceTable.new()
	var b := DiceTable.new()
	root.add_child(a)
	root.add_child(b)
	var faces: Array = []
	for i in DiceDefs.DICE_COUNT:
		faces.append(DiceDefs.weapon_die(&"swordShield"))
	for t: DiceTable in [a, b]:
		t.set_faces(faces, &"swordShield")
		t.reset_round()
	a.record_enabled = true
	a.can_throw = true
	var bytes := [0]
	var chunks := [0]
	a.frames_recorded.connect(func(data: PackedByteArray) -> void:
		bytes[0] += data.size()
		chunks[0] += 1
		b.play_frames(bytes_to_var(var_to_bytes(data))))
	var a_faces: Array = []
	var b_settled: Array = []
	var b_clacks := [0]
	var a_clacks := [0]
	a.settled.connect(func(f: Array) -> void: a_faces.append(f))
	b.settled.connect(func(f: Array) -> void: b_settled.append(f))
	a.clacked.connect(func(_g: float) -> void: a_clacks[0] += 1)
	b.clacked.connect(func(_g: float) -> void: b_clacks[0] += 1)
	await (Engine.get_main_loop() as SceneTree).physics_frame
	a.auto_throw(0.8)
	var frames := 0
	var started := -1
	var a_done := -1
	var err := ""
	while frames < int((DiceTable.SETTLE_TIMEOUT + 3.0) * 60):
		await (Engine.get_main_loop() as SceneTree).physics_frame
		frames += 1
		if started < 0 and b.replaying:
			started = frames
			for d: RigidBody3D in b._dice:
				if not d.freeze:
					err = "播錄影時骰子應凍住、不跑物理"
		if a_done < 0 and not a_faces.is_empty():
			a_done = frames
		if a_done >= 0 and not b.replaying and b.state == DiceTable.State.SETTLED:
			break
	if err == "" and started < 0:
		err = "B 桌一直沒開始播"
	elif err == "" and a_faces.is_empty():
		err = "A 桌沒停好"
	elif err == "" and b.state != DiceTable.State.SETTLED:
		err = "B 桌播完應算停好：state %d" % b.state
	elif err == "" and not b_settled.is_empty():
		err = "播錄影不該送 settled（結果以房主的為準）"
	elif err == "" and Array(b.up_faces()) != a_faces[0]:
		err = "B 桌播完的面 %s 應同 A 桌 %s" % [b.up_faces(), a_faces[0]]
	elif err == "" and a_clacks[0] > 0 and b_clacks[0] == 0:
		err = "A 桌有撞擊聲（%d 次），B 桌播的時候也要響" % a_clacks[0]
	if err == "":
		for i in DiceDefs.DICE_COUNT:
			var gap: float = a._dice[i].position.distance_to(b._dice[i].position)
			if gap > 0.05:
				err = "第 %d 顆 B 桌停在 %s，A 桌 %s（差 %.3f）" % [i + 1, b._dice[i].position, a._dice[i].position, gap]
				break
	if err == "":
		_note("擲骰錄播：A 桌 %.2f 秒停好、B 桌第 %.2f 秒開始播、晚 %.2f 秒播完；%d 段共 %d bytes（%.0f bytes/秒）；撞擊聲 %d / %d" % [
			a_done / 60.0, started / 60.0, (frames - a_done) / 60.0, chunks[0], bytes[0], bytes[0] / (a_done / 60.0), a_clacks[0], b_clacks[0]])
	a.queue_free()
	b.queue_free()
	return err


# 多人的獎勵（§55「連線」）：共用同一組 4 個、暗選，大家都選好才揭曉；沒撞到各拿各的、撞到的比骰子（輸的隨機拿沒人選的）；
# 還沒選的人倒地就不等他；新骰子的技能面只出隊伍裡有人拿著的武器的（一顆上都同一把武器的）
static func check_dice_shared_reward() -> String:
	var w := World.new(&"test_arena")
	w.spawn_packs = false
	w.dice = DiceRun.new()
	w.reset(29, [1, 2, 3])
	w.spawner.finished = true
	_worlds.append(w)
	var ps: Array[Player] = [w.players[1], w.players[2], w.players[3]]
	ps[0].equip_weapon(&"swordShield")
	ps[1].equip_weapon(&"staff")
	ps[2].equip_weapon(&"swordShield")
	var picked := func() -> Dictionary:   # player_id -> 拿到的種類
		var out := {}
		for ev: Dictionary in w.events:
			if ev.name == "dice:picked":
				out[ev.player_id] = ev.kind
		return out
	var round := func() -> String:
		w.dice.phase = DiceRun.EXPLORE
		w.dice.door_reward(w, &"relic")
		if w.dice.phase != DiceRun.REWARD or not w.dice.shared:
			return "三人時門的獎勵應是共用的暗選：%s shared %s" % [w.dice.phase, w.dice.shared]
		return ""
	# 1. 沒撞到：各拿各的，不比骰子
	var err: String = round.call()
	if err != "":
		return err
	var offers: Array = w.dice.seat_of(ps[0]).offers
	for p in ps:
		if w.dice.seat_of(p).offers.map(func(o: Dictionary) -> String: return o.title) != offers.map(func(o: Dictionary) -> String: return o.title):
			return "三人的選項應一樣"
	_run(w, _op_cmd([InputCmd.OP_DICE_REWARD, 0]), 1)   # _run 的指令給 peer 1
	if w.dice.seat_of(ps[0]).offers.is_empty() or not w.dice.shared:
		return "還有人沒選就不該揭曉"
	var cmds := {2: _op_cmd([InputCmd.OP_DICE_REWARD, 1]), 3: _op_cmd([InputCmd.OP_DICE_REWARD, 2])}
	w.step(cmds, DT)
	var got: Dictionary = picked.call()
	if w.dice.shared or w.dice.contest_seq != 0 or got.get(ps[0].id) != offers[0].kind or got.get(ps[1].id) != offers[1].kind or got.get(ps[2].id) != offers[2].kind:
		return "沒撞到應各拿各的、不比骰子：拿到 %s、選項 %s" % [got, offers.map(func(o: Dictionary) -> StringName: return o.kind)]
	for p in ps:   # 拿到刻面的刻完
		if not w.dice.seat_of(p).carve.is_empty():
			var c := {p.peer_id: _op_cmd([InputCmd.OP_DICE_CARVE, 0, 5, 0])}
			w.step(c, DT)
	if w.dice.phase != DiceRun.EXPLORE:
		return "都拿完應回到逛地圖：%s" % w.dice.phase
	# 2. 三人都選同一個：比骰子，一個拿到、另外兩個從剩下的 3 個裡隨機拿（不重複）
	err = round.call()
	if err != "":
		return err
	offers = w.dice.seat_of(ps[0]).offers
	w.step({1: _op_cmd([InputCmd.OP_DICE_REWARD, 3]), 2: _op_cmd([InputCmd.OP_DICE_REWARD, 3]), 3: _op_cmd([InputCmd.OP_DICE_REWARD, 3])}, DT)
	got = picked.call()
	if w.dice.contest_seq != 1 or w.dice.contests.size() != 1:
		return "三人撞到同一個應比一次骰子：%s" % [w.dice.contests]
	var c0: Array = w.dice.contests[0]
	var rolls: Dictionary = c0[1]
	var winner: int = c0[2]
	if rolls.size() != 3 or rolls.values().max() != rolls[winner] or rolls.values().count(rolls[winner]) != 1:
		return "最大的拿（平手要再擲到分出來）：點數 %s、拿到的 %d" % [rolls, winner]
	var kinds := [got.get(ps[0].id), got.get(ps[1].id), got.get(ps[2].id)]
	var winner_kind: StringName = got.get((w.players[winner] as Player).id)
	if winner_kind != offers[3].kind or kinds.has(null) or kinds.count(offers[3].kind) != 1:
		return "贏的拿第 4 個（%s）、輸的從剩下的拿、不重複：%s" % [offers[3].kind, kinds]
	for p in ps:
		if not w.dice.seat_of(p).carve.is_empty():
			w.step({p.peer_id: _op_cmd([InputCmd.OP_DICE_CARVE, 0, 4, 0])}, DT)
	# 3. 還沒選的人倒地：剩下的都選好就揭曉
	err = round.call()
	if err != "":
		return err
	w.step({1: _op_cmd([InputCmd.OP_DICE_REWARD, 0]), 2: _op_cmd([InputCmd.OP_DICE_REWARD, 1])}, DT)
	if not w.dice.shared:
		return "第 3 位還沒選不該揭曉"
	ps[2].is_downed = true
	w.step({}, DT)
	if w.dice.shared or not w.dice.seat_of(ps[2]).offers.is_empty():
		return "還沒選的人倒地後應直接揭曉"
	ps[2].is_downed = false
	for p in ps:
		if not w.dice.seat_of(p).carve.is_empty():
			w.step({p.peer_id: _op_cmd([InputCmd.OP_DICE_CARVE, 0, 3, 0])}, DT)
	# 4. 新骰子的技能面：只出隊伍裡的武器（劍盾、法杖），一顆骰子上都同一把武器的；兩把都出現過
	var seen := {}
	for i in 40:
		w.dice.phase = DiceRun.EXPLORE
		for p in ps:
			w.dice.seat_of(p).carve = {}
		w.dice.door_reward(w, &"relic")
		for o: Dictionary in w.dice.seat_of(ps[0]).offers:
			if o.kind != &"die":
				continue
			var skills: Array = o.faces.filter(func(f: StringName) -> bool: return DiceDefs.is_skill(f))
			if skills.is_empty():
				continue
			var owner := &""
			for wid: StringName in [&"swordShield", &"staff"]:
				if skills.all(func(f: StringName) -> bool: return DiceDefs.skill_fits(f, wid)):
					owner = wid
			if owner == &"":
				return "新骰子的技能面應都是隊伍裡同一把武器能用的（劍盾或法杖）：%s" % [o.faces]
			seen[owner] = true
		for p in ps:
			w.dice.seat_of(p).offers = []
		w.dice.shared = false
	if seen.size() != 2:
		return "40 輪裡劍盾、法杖的技能骰都應出現過：%s" % [seen.keys()]
	return ""


# 戰場霧牆（§55）：菁英群開打時以牠為中心圍一圈（半徑在 ARENA_MIN~MAX），玩家往外走出不去；霧牆外的怪群就算在旁邊也不會發現玩家，
# 打完霧牆收掉才會發現；伏擊爬出來也開一場
static func check_dice_arena() -> String:
	var w := _dice_world()
	var p := _player(w)
	p.hp = 99999.0
	var e := _elite(w, p.pos + Vector2(6, 0))
	w.alert_pack(_lone_pack(w, e), e, p)
	var r: float = w.dice.arena_radius
	var c: Vector2 = w.dice.arena_center
	if r < DiceDefs.ARENA_MIN or r > DiceDefs.ARENA_MAX or c.distance_to(e.pos) > 0.01:
		return "開打應圍出霧牆：半徑 %.1f（%s~%s）、中心離菁英 %.2f" % [r, DiceDefs.ARENA_MIN, DiceDefs.ARENA_MAX, c.distance_to(e.pos)]
	_run(w, _op_cmd([InputCmd.OP_DICE_ROLL]), 1)
	_wait(w, DiceDefs.SETTLE_TIME)
	_run(w, _op_cmd([InputCmd.OP_DICE_DONE]), 1)
	_wait(w, DiceDefs.COUNTDOWN + 0.1)
	if w.dice.phase != DiceRun.FIGHT:
		return "倒數完應開打：%s" % w.dice.phase
	var out := (p.pos - c).normalized()
	var o := _spawn(w, &"grunt", c + out * (r + 2.0))
	o.dormant = true
	var outer := _lone_pack(w, o)
	_run(w, _cmd(out, out * 5.0), 180)
	var lim := r - p.radius + 0.01
	if p.pos.distance_to(c) > lim:
		return "玩家應出不了霧牆：離中心 %.2f（上限 %.2f）" % [p.pos.distance_to(c), lim]
	if w.packs[outer].awake:
		return "霧牆外的怪群不該發現玩家（離玩家 %.1f）" % o.pos.distance_to(p.pos)
	e.die()
	_clear_out(w)
	var s := w.dice.seat_of(p)
	_run(w, _op_cmd([InputCmd.OP_DICE_REWARD, _simple_pick(s)]), 1)
	if not s.carve.is_empty():
		_run(w, _op_cmd([InputCmd.OP_DICE_CARVE, 0, 5, 0]), 1)
	if w.dice.phase != DiceRun.EXPLORE or w.dice.arena_radius != 0.0:
		return "打完應收掉霧牆、回到逛地圖：%s 半徑 %.1f" % [w.dice.phase, w.dice.arena_radius]
	_wait(w, 1.0)
	if not w.packs[outer].awake:
		return "霧牆收掉後，旁邊的怪群應發現玩家（離 %.1f）" % o.pos.distance_to(p.pos)
	# 伏擊：玩家走到群中心爬出來，也開一場
	var w2 := _dice_world()
	var p2 := _player(w2)
	var a := _spawn(w2, &"grunt", p2.pos + Vector2(2, 0))
	a.set_rarity(&"rare", [])
	var ai := _lone_pack(w2, a)
	w2.packs[ai].ambush = true
	a.lurking = true
	a.dormant = true
	_run(w2, _cmd(Vector2.ZERO), 2)
	if not w2.packs[ai].awake or w2.dice.phase != DiceRun.ROLL or not w2.dice.foes.has(a.id):
		return "伏擊爬出來應開一場（菁英先擲骰）：醒 %s、%s" % [w2.packs[ai].awake, w2.dice.phase]
	return ""


# 隊長帶隊（§55）：三人逛地圖，隊長往右走 2 秒，隊友按反方向、按翻滾都不算，跟在隊長身後（不疊在一起）；
# 離太遠直接搬過去；開打之後隊友自己走
static func check_dice_follow() -> String:
	var w := World.new(&"test_arena")
	w.spawn_packs = false
	w.dice = DiceRun.new()
	w.reset(31, [1, 2, 3])
	w.spawner.finished = true
	_worlds.append(w)
	var lead: Player = w.players[1]
	var f1: Player = w.players[2]
	var f2: Player = w.players[3]
	var start := lead.pos
	var rolled := false
	for i in 120:
		w.step({1: _cmd(Vector2(1, 0)), 2: _cmd(Vector2(-1, 0), Vector2(0, 5), InputCmd.BTN_ROLL), 3: _cmd(Vector2(-1, 0))}, DT)
		rolled = rolled or f1.action.is_in(&"roll")
	for i in 60:
		w.step({}, DT)
	if lead.pos.distance_to(start) < 5.0:
		return "隊長應自己走：只走了 %.2f" % lead.pos.distance_to(start)
	if rolled:
		return "跟著隊長時按翻滾不該翻"
	for f: Player in [f1, f2]:
		var d := f.pos - lead.pos
		if d.length() > 3.5 or d.x > -0.3:
			return "隊友應跟在隊長身後（往右走 → 在左邊）：差 %s" % d
	if f1.pos.distance_to(f2.pos) < 1.2:
		return "兩位隊友不該疊在一起：差 %.2f" % f1.pos.distance_to(f2.pos)
	lead.pos += Vector2(0, 20)
	w.step({}, DT)
	if f1.pos.distance_to(lead.pos) > 4.0:
		return "離隊長太遠應直接搬過去：差 %.2f" % f1.pos.distance_to(lead.pos)
	w.dice.phase = DiceRun.FIGHT
	var at := f1.pos
	for i in 30:
		w.step({2: _cmd(Vector2(-1, 0))}, DT)
	if at.x - f1.pos.x < 1.0:
		return "開打後隊友應自己走：只走了 %.2f" % (at.x - f1.pos.x)
	return ""


# 擲骰演出（§55）：中了強化以上 → 模擬層發全隊亮起與畫面震動、畫面上全隊腳下有金光；揭曉時每個中的技能面叮一聲、一聲比一聲高，
# 接著中獎音效與「你擲出 3 個…！」橫幅；差一顆（2 個）是可惜的音效；桌子只剩最後一顆在滾、而它能湊到 3 個時放慢、鏡頭推近、
# 送 suspense_changed（音樂收小），停了恢復；霧牆畫面跟著模擬層的圈淡入淡出
static func check_dice_show() -> String:
	var w := _dice_world()
	w.dice.physics = true
	var p := _player(w)
	var e := _elite(w, p.pos + Vector2(8, 0))
	w.alert_pack(_lone_pack(w, e), e, p)
	var s := w.dice.seat_of(p)
	var die: Array = s.pool[0]
	var k := die.find(DiceDefs.weapon_die(p.weapon_id)[0])
	var b := die.find(DiceDefs.BLANK)
	var events: Array[Dictionary] = []
	_run_collect(w, _op_cmd([InputCmd.OP_DICE_ROLL]), 1, events)
	_run_collect(w, _op_cmd([InputCmd.OP_DICE_FACES, k, k, k, b, b, b]), 1, events)
	var glow := _named(events, "dice:glow")
	var shake := _named(events, "camera:shake")
	if glow.size() != 1 or not (glow[0].player_ids as Array).has(p.id) or glow[0].big or shake.size() != 1 or not is_equal_approx(shake[0].amount, DiceDefs.SHOW_SHAKE):
		return "擲中 3 個應發一次全隊亮起與震動 %.2f：亮 %s、震 %s" % [DiceDefs.SHOW_SHAKE, glow, shake]
	events.clear()
	_run_collect(w, _op_cmd([InputCmd.OP_DICE_ROLL]), 1, events)
	_run_collect(w, _op_cmd([InputCmd.OP_DICE_FACES, k, b, b, b, b, b]), 1, events)
	if not _named(events, "dice:glow").is_empty() or not _named(events, "camera:shake").is_empty():
		return "只中 1 個不該亮、不該震"
	# 畫面：金光（Effects）
	var fx := Effects.new()
	_scene_root().add_child(fx)
	fx.sync(w, 0.0)
	var before := fx.transient_count()
	fx.on_event("dice:glow", {"player_ids": [p.id], "big": true})
	var lit := fx.transient_count() > before and fx.particle_count() > 0
	fx.queue_free()
	if not lit:
		return "全隊亮起應在玩家腳下有金光、身上有光點"
	# 揭曉的音效與橫幅（不用物理桌的那條路：轉動畫停了才揭曉）
	var w2 := _dice_world()
	var p2 := _player(w2)
	var e2 := _elite(w2, p2.pos + Vector2(8, 0))
	w2.alert_pack(_lone_pack(w2, e2), e2, p2)
	var s2 := w2.dice.seat_of(p2)
	var cam := Camera3D.new()
	_scene_root().add_child(cam)
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w2, cam)
	_scene_root().add_child(hud)
	var dp: DicePanel = hud.dice_panel
	var heard: Array = []
	dp.sfx.connect(func(cue: String, _g: float, pitch: float) -> void: heard.append([cue, pitch]))
	var err := ""
	var skill: StringName = DiceDefs.weapon_die(p2.weapon_id)[0]
	for want: int in [3, 2]:
		heard.clear()
		_run(w2, _op_cmd([InputCmd.OP_DICE_ROLL]), 1)
		var d2: Array = s2.pool[0]
		for i in DiceDefs.DICE_COUNT:
			s2.face[i] = d2.find(skill) if i < want else d2.find(DiceDefs.BLANK)
		for f in 50:
			dp.refresh(w2, p2, 0.05)
		var ticks := heard.filter(func(h: Array) -> bool: return h[0] == "diceTick")
		var rising := ticks.size() == want
		for i in range(1, ticks.size()):
			rising = rising and ticks[i][1] > ticks[i - 1][1]
		var last: String = heard[-1][0] if not heard.is_empty() else ""
		var end_cue := "diceWin" if want >= 3 else "diceMiss"
		if not rising or last != end_cue:
			err = "中 %d 個：應叮 %d 聲一聲比一聲高、最後 %s：聽到 %s" % [want, want, end_cue, heard]
			break
		if want >= 3 and not dp._banner.text.begins_with("你擲出 3 個%s" % DiceDefs.name_of(skill)):
			err = "中 3 個的橫幅應寫「你擲出 3 個%s！」：%s" % [DiceDefs.name_of(skill), dp._banner.text]
			break
		_wait(w2, DiceDefs.SETTLE_TIME)
	hud.queue_free()
	cam.queue_free()
	if err != "":
		return err
	# 桌子：只剩最後一顆在滾、它能湊到 3 個 → 放慢、鏡頭推近；只有 1 個中的時候不放慢
	var table := DiceTable.new()
	_scene_root().add_child(table)
	var faces: Array = []
	for i in DiceDefs.DICE_COUNT:
		faces.append(DiceDefs.weapon_die(&"swordShield"))
	table.set_faces(faces, &"swordShield")
	await (Engine.get_main_loop() as SceneTree).physics_frame
	var sk := (faces[0] as Array).find(DiceDefs.weapon_die(&"swordShield")[0])
	var bl := (faces[0] as Array).find(DiceDefs.BLANK)
	var lay := func(up: Array) -> void:
		for i in DiceDefs.DICE_COUNT:
			table._rolling[i] = true
			table._place(table._dice[i], Vector3(-4.0 + i * 1.6, 0.5, 0.0), up[i], false)
		table._dice[5].position = Vector3(3.0, 1.5, 1.5)
		table._dice[5].linear_velocity = Vector3(4.0, 0.0, 0.0)
	lay.call([sk, bl, bl, bl, bl, sk])
	if table.suspense_candidate() != -1:
		err = "其他停好的只中 1 個，最後一顆湊不到 3 個，不該放慢"
	lay.call([sk, sk, bl, bl, bl, bl])
	var calls: Array = []
	table.suspense_changed.connect(func(on: bool) -> void: calls.append(on))
	if err == "" and table.suspense_candidate() != 5:
		err = "其他停好的中 2 個、最後一顆有那一招：應放慢第 6 顆，得到 %d" % table.suspense_candidate()
	if err == "":   # 慢慢滑的（疊成一堆靠著滑）不算在翻，不放慢（YangHsu 2026-11-24：盯著一堆不動的骰子沒期待感）
		table._dice[5].linear_velocity = Vector3(0.6, 0.0, 0.0)
		if table.suspense_candidate() != -1:
			err = "最後一顆只是慢慢滑（0.6、不翻）不該放慢"
		table._dice[5].linear_velocity = Vector3(4.0, 0.0, 0.0)
	if err == "":
		var home: Vector3 = table._camera.position
		table.state = DiceTable.State.ROLLING
		table._begin_suspense(5)
		var st := table.stake()
		if st.get("face", &"") != (faces[0] as Array)[sk] or st.get("have", 0) != 2 or st.get("hit", 0) != -1:
			err = "賭注應是 2 個%s、還沒揭曉：%s" % [(faces[0] as Array)[sk], st]
		if err == "" and table._slow != 1.0:
			err = "開始放慢那一下不該馬上變慢（%.2f），要在 %.1f 秒內慢慢變慢" % [table._slow, DiceDefs.SUSPENSE_RAMP]
		table._update_suspense(DiceDefs.SUSPENSE_RAMP / 2.0)
		if err == "" and not (table._slow < 1.0 and table._slow > DiceDefs.SUSPENSE_SLOW):
			err = "放慢到一半應在 1 與 %.1f 之間：%.2f" % [DiceDefs.SUSPENSE_SLOW, table._slow]
		table._update_suspense(DiceDefs.SUSPENSE_RAMP / 2.0)
		var space := table._viewport.find_world_3d().space
		var g: float = PhysicsServer3D.area_get_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY)
		var v: float = table._dice[5].linear_velocity.length()
		if not is_equal_approx(g, DiceTable.GRAVITY * DiceDefs.SUSPENSE_SLOW * DiceDefs.SUSPENSE_SLOW) or absf(v - 4.0 * DiceDefs.SUSPENSE_SLOW) > 0.05 or calls != [true]:
			err = "放慢：重力 %.2f、速度 %.2f（應 %.2f、%.2f）、訊號 %s" % [g, v, DiceTable.GRAVITY * DiceDefs.SUSPENSE_SLOW * DiceDefs.SUSPENSE_SLOW, 4.0 * DiceDefs.SUSPENSE_SLOW, calls]
		for f in 20:
			await (Engine.get_main_loop() as SceneTree).physics_frame
		var near := table._camera.position.distance_to(table._dice[5].position)
		if err == "" and near >= home.distance_to(table._dice[5].position) - 2.0:
			err = "放慢時鏡頭應推近那顆：%.1f（原本 %.1f）" % [near, home.distance_to(table._dice[5].position)]
		# 已中的金光、其他的淡掉、擋在鏡頭與那顆之間的透明
		var cam_pos: Vector3 = table._camera.global_position
		var block_at := table._dice[5].global_position.lerp(cam_pos, 2.0 / cam_pos.distance_to(table._dice[5].global_position))
		table._dice[4].global_position = block_at
		table._paint_stakes(5)
		var m0 := table._bodies[0].material_override as StandardMaterial3D
		var fades := [table._dice_fade(2), table._dice_fade(4), table._dice_fade(0)]
		if err == "" and (not m0.emission_enabled or not is_equal_approx(fades[0], DiceDefs.SUSPENSE_FADE_OTHER) or not is_equal_approx(fades[1], DiceDefs.SUSPENSE_FADE_BLOCK) or fades[2] != 0.0):
			err = "醞釀時：已中的第 1 顆應金光（%s）、無關的第 3 顆淡 %.2f、擋住的第 5 顆透明 %.2f、已中的不淡：%s" % [m0.emission_enabled, DiceDefs.SUSPENSE_FADE_OTHER, DiceDefs.SUSPENSE_FADE_BLOCK, fades]
		table._end_suspense()
		g = PhysicsServer3D.area_get_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY)
		if err == "" and (not is_equal_approx(g, DiceTable.GRAVITY) or calls != [true]):
			err = "不再放慢應恢復重力 %.1f、鏡頭還盯著（等揭曉）：重力 %.2f、訊號 %s" % [DiceTable.GRAVITY, g, calls]
		table.state = DiceTable.State.SETTLED
		table._place(table._dice[5], Vector3(3.0, 0.5, 1.5), sk, true)
		table._begin_hold(5)   # 第 6 顆停在那一招：中了
		if err == "" and (not table.holding() or table.stake().get("hit", -1) != 1):
			err = "停好應留一拍揭曉中了：%s %s" % [table.holding(), table.stake()]
		for f in ceili(DiceDefs.SUSPENSE_HOLD * 60.0) + 2:
			await (Engine.get_main_loop() as SceneTree).physics_frame
		if err == "" and (table.holding() or calls != [true, false] or table._dice_fade(2) != 0.0 or m0.emission_enabled):
			err = "揭曉完應拉回、送 suspense_changed(false)、骰子恢復：%s %s 淡 %.2f 金光 %s" % [table.holding(), calls, table._dice_fade(2), m0.emission_enabled]
	table.queue_free()
	if err != "":
		return err
	# 霧牆畫面
	var view := DiceArenaView.new()
	_scene_root().add_child(view)
	w.dice.arena_center = Vector2(3, 4)
	w.dice.arena_radius = 11.0
	for f in 40:
		view.sync(w, 1.0 / 60.0)
	var shown := view.fog_shown() and is_equal_approx(view.strength, 1.0) and view.fog_circle().is_equal_approx(Vector3(3, 11, 4))
	w.dice.arena_radius = 0.0
	for f in 40:
		view.sync(w, 1.0 / 60.0)
	var gone := not view.fog_shown()
	view.queue_free()
	if not shown or not gone:
		return "霧牆畫面應照模擬層的圈淡入（濃度 1、半徑 11、中心 (3, 4)）、收掉時淡出：%s %s" % [shown, gone]
	return ""


# 構想補齊的三條（§55）：倒地不倒數、這一場打完自動站起 30%（逛地圖時倒下馬上站起，全隊倒地照樣輸）；
# 倒數時的結果總覽每人一行；桌邊配件（階段條、角色卡的血量籌碼、右鍵卡、重擲券籌碼、技能欄與新手提示換成紙卡樣式，一般模式不換）；
# 逛地圖時每群還沒醒的怪頭上立遭遇卡「一般 / 菁英 ×幾隻」，醒了、開打就不標
static func check_dice_rules() -> String:
	var w := World.new(&"test_arena")
	w.spawn_packs = false
	w.dice = DiceRun.new()
	w.reset(41, [1, 2])
	w.spawner.finished = true
	_worlds.append(w)
	var p1: Player = w.players[1]
	var p2: Player = w.players[2]
	var e := _elite(w, p1.pos + Vector2(8, 0))
	e.stun(999.0)
	w.alert_pack(_lone_pack(w, e), e, p1)
	w.dice.phase = DiceRun.FIGHT
	p2.die()
	if not p2.is_downed:
		return "多人時生命歸零應先倒地"
	for i in ceili((Config.REVIVE.down_time + 3.0) / DT):
		w.step({}, DT)
	if p2.is_dead or not p2.is_downed:
		return "骰子模式倒地不倒數：過了 %.0f 秒應還倒著、沒死（死 %s、倒 %s）" % [Config.REVIVE.down_time + 3.0, p2.is_dead, p2.is_downed]
	e.die()
	w.step({}, DT)
	if p2.is_downed or absf(p2.hp - roundf(p2.max_hp * DiceDefs.DOWNED_REVIVE_HP)) > 1.0:
		return "這一場打完應自動站起、剩 %d%% 生命：倒 %s、%.0f / %.0f" % [roundi(DiceDefs.DOWNED_REVIVE_HP * 100), p2.is_downed, p2.hp, p2.max_hp]
	w.dice.phase = DiceRun.EXPLORE
	p2.die()
	w.step({}, DT)
	if p2.is_downed:
		return "逛地圖時倒下應馬上站起"
	w.dice.phase = DiceRun.FIGHT
	p1.die()
	p2.die()
	w.step({}, DT)
	if not w.is_defeated:
		return "全隊倒地應整局結束"
	# 結果總覽
	var w2 := _dice_world()
	var me := _player(w2)
	var e2 := _elite(w2, me.pos + Vector2(8, 0))
	w2.alert_pack(_lone_pack(w2, e2), e2, me)
	_run(w2, _op_cmd([InputCmd.OP_DICE_ROLL]), 1)
	_wait(w2, DiceDefs.SETTLE_TIME)
	_run(w2, _op_cmd([InputCmd.OP_DICE_DONE]), 1)
	var cam := Camera3D.new()
	_scene_root().add_child(cam)
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w2, cam)
	_scene_root().add_child(hud)
	var dp: DicePanel = hud.dice_panel
	dp.refresh(w2, me, 0.05)
	var summary: String = dp._summary.text
	var summary_phase := w2.dice.phase
	# 桌邊配件：倒數時階段條在「擲骰」、牌也擺著（2026-11-24 起擲骰畫面不再自己寫結果）；開打後階段條到「開打」、左下角色卡取代左上血條、
	# 血量 10 枚籌碼（少一成生命少一枚）、右下右鍵卡寫骰到的招、最後一枚籌碼是重擲券
	var props: DiceProps = hud.dice_props
	hud._process(0.016)
	var props_err := ""
	if not props.track.visible or props.track.step != 1 or not props.hero.visible or not props.hand.visible:
		props_err = "倒數時階段條應在擲骰（%d、顯示 %s）、角色卡與右下的牌擺著（%s、%s）" % [props.track.step, props.track.visible, props.hero.visible, props.hand.visible]
	_wait(w2, DiceDefs.COUNTDOWN)
	me.hp = me.max_hp * 0.75
	hud._process(0.016)
	var res: Dictionary = w2.dice.seat_of(me).result
	var want_skill: String = DiceDefs.name_of(res.skill) if res.count > 0 else "沒中"
	if props_err == "" and (w2.dice.phase != DiceRun.FIGHT or props.track.step != 2 or not props.hero.visible or not props.hand.visible or hud._hp.root.visible):
		props_err = "開打後階段條應到開打（%s、%d）、角色卡與牌出來（%s、%s）、左上血條收起來（%s）" % [w2.dice.phase, props.track.step, props.hero.visible, props.hand.visible, hud._hp.root.visible]
	var bar_slot: Variant = hud._skill_bar.get_child(0)
	if props_err == "" and (not bar_slot.paper or not hud.hints.paper):
		props_err = "骰子模式的技能欄與新手提示應換成紙卡樣式（技能欄 %s、提示 %s）" % [bar_slot.paper, hud.hints.paper]
	if props_err == "" and (props.hp_chips.count != 8 or props.skill_name.text != want_skill or props.chip_texts.is_empty() or not props.chip_texts[-1].begins_with("重擲券 ×%d" % w2.dice.charges_of(me))):
		props_err = "75%% 生命應 8 枚籌碼（%d）、右鍵卡寫「%s」（%s）、最後一枚是重擲券 ×%d（%s）" % [props.hp_chips.count, want_skill, props.skill_name.text, w2.dice.charges_of(me), props.chip_texts]
	# 左右鍵只在右下的牌（技能欄只剩 Shift 與 Q）、右鍵卡蓋冷卻；籌碼只寫數字，完整的字在滑鼠提示（YangHsu 2026-11-24）
	if props_err == "":
		var bar: SkillBar = hud._skill_bar
		var keys: Array = bar._slots.keys()
		if bar._attack_slot != null:
			keys.append("左鍵")
		w2.cooldowns.start(me.cd("player.special"), 4.0)
		hud._process(0.016)
		var chip: DiceProps.Chip = props.chips_row.get_child(props.chips_row.get_child_count() - 1)
		var chip_text: String = (chip.get_child(1) as Label).text
		if keys.has("左鍵") or keys.has("player.special") or not keys.has(Player.ROLL_CD) or props.skill_cd.ratio <= 0.0 or chip_text != "×%d" % w2.dice.charges_of(me) or not chip.tooltip_text.begins_with("重擲券"):
			props_err = "骰子模式技能欄不畫左右鍵（%s）、右鍵卡蓋冷卻（%.2f）、籌碼寫「×N」指著才寫完整（「%s」「%s」）" % [keys, props.skill_cd.ratio, chip_text, chip.tooltip_text]
		elif DiceProps.short_number("傷害 +10%") != "+10%":
			props_err = "效果籌碼只寫數字：「傷害 +10%%」應寫「+10%%」，得到「%s」" % DiceProps.short_number("傷害 +10%")
	hud.queue_free()
	cam.queue_free()
	if props_err == "":   # 一般模式的技能欄照舊是暗色格子
		var wn := World.new(&"test_arena")
		wn.reset(41, [1])
		_worlds.append(wn)
		var sb := SkillBar.new()
		_scene_root().add_child(sb)
		sb.refresh(wn, wn.players[1])
		if sb.get_child(0).paper:
			props_err = "一般模式的技能欄不應換成紙卡樣式"
		sb.queue_free()
	if summary_phase != DiceRun.COUNTDOWN or not summary.begins_with("你："):
		return "大家擲完倒數時應列結果總覽（你：…）：%s「%s」" % [summary_phase, summary]
	if props_err != "":
		return props_err
	# 怪群難度
	var w3 := _dice_world()
	var p3 := _player(w3)
	var a := _spawn(w3, &"grunt", p3.pos + Vector2(10, 0))
	a.dormant = true
	_lone_pack(w3, a)
	var b := _elite(w3, p3.pos + Vector2(-10, 0))
	b.dormant = true
	var bi := _lone_pack(w3, b)
	var c := _spawn(w3, &"grunt", p3.pos + Vector2(0, 10))
	var ci := _lone_pack(w3, c)
	w3.packs[ci].awake = true
	var view := DiceArenaView.new()
	_scene_root().add_child(view)
	view.sync(w3, 0.016, p3)
	var tags := view.tag_texts.duplicate()
	var seen := view.visible_tags()
	w3.alert_pack(bi, b, p3)
	view.sync(w3, 0.016, p3)
	var fighting := view.tag_texts.duplicate()
	view.queue_free()
	tags.sort()
	if tags != ["一般 ×1", "菁英 ×1"] or seen != 2 or not fighting.is_empty():
		return "逛地圖時還沒醒的怪群應立遭遇卡「一般 / 菁英 ×幾隻」（醒了的不標，畫面上看得到 %d 個）、開打不標：%s、開打時 %s" % [seen, tags, fighting]
	return ""


# 骰盤放進遊戲世界（美術方案 2：戰場旁的骰盤）：桌子轉 0.7 弧度、擺在 (30, 0, −20)，用遊戲那種正交鏡頭看；
# 真的丟：停在骰盤上（本地座標在桌面內、世界座標在擺的位置附近）、回報的面對；滑鼠指著骰盤中間，換算回桌面本地的點在中間附近；
# 擺的位置在霧牆外面（離圈中心 ≥ 半徑 + 半張桌子）；擲骰時遊戲鏡頭抬到 TRAY_ELEVATION、回去再轉回平常的俯角，移動方向（screen_forward）不變
static func check_dice_tray() -> String:
	var rig := CameraRig.new()
	rig._ready()
	var fwd := rig.screen_forward
	var pitches: Array[float] = []
	for want: float in [DiceDefs.TRAY_ELEVATION, Config.CAMERA.elevation]:
		for i in 120:
			rig.tilt(want, 1.0 / 60.0)
		rig.follow(Vector3.ZERO, 0.0, true)
		pitches.append(asin(rig.camera.transform.basis.z.y))
	var moved := rig.screen_forward.distance_to(fwd)
	rig.free()
	if absf(pitches[0] - DiceDefs.TRAY_ELEVATION) > 0.01 or absf(pitches[1] - Config.CAMERA.elevation) > 0.01 or moved > 1e-4:
		return "擲骰時鏡頭俯角應 %.1f°（實際 %.1f°）、回去應 %.1f°（實際 %.1f°），移動方向不變（差 %.4f）" % [
			rad_to_deg(DiceDefs.TRAY_ELEVATION), rad_to_deg(pitches[0]), rad_to_deg(Config.CAMERA.elevation), rad_to_deg(pitches[1]), moved]
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(1920, 1080)
	_scene_root().add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = DiceDefs.TRAY_VIEW
	vp.add_child(cam)
	cam.make_current()
	var table := DiceTable.new()
	_scene_root().add_child(table)
	var faces: Array = []
	for i in DiceDefs.DICE_COUNT:
		faces.append(DiceDefs.weapon_die(&"swordShield"))
	table.set_faces(faces, &"swordShield")
	var holder := Node3D.new()
	vp.add_child(holder)
	table.use_world(holder, cam)
	var origin := Transform3D(Basis(Vector3.UP, 0.7), Vector3(30, 0, -20))
	table.set_origin(origin)
	table.set_shown(true)
	cam.look_at_from_position(origin.origin + Vector3(sin(0.7), 1.2, cos(0.7)) * 14.0, origin.origin)
	await (Engine.get_main_loop() as SceneTree).physics_frame
	table.reset_round()
	table.can_throw = true
	var got: Array = []
	table.settled.connect(func(f: Array) -> void: got.append(f))
	table.auto_throw(0.8)
	var frames := 0
	while got.is_empty() and frames < int((DiceTable.SETTLE_TIMEOUT + 1.0) * 60):
		await (Engine.get_main_loop() as SceneTree).physics_frame
		frames += 1
	var err := ""
	if got.is_empty():
		err = "放進遊戲世界的骰盤 %.0f 秒內沒停好" % (DiceTable.SETTLE_TIMEOUT + 1.0)
	elif got[0] != Array(table.up_faces()):
		err = "回報的面 %s ≠ 朝上的面 %s" % [got[0], table.up_faces()]
	else:
		for i in DiceDefs.DICE_COUNT:
			var d: RigidBody3D = table._dice[i]
			var local := d.position
			if absf(local.x) > DiceTable.PLAY.x / 2.0 or absf(local.z) > DiceTable.PLAY.y / 2.0 or local.y < 0.2 or local.y > 1.6:
				err = "第 %d 顆停在桌面外（本地 %s）" % [i + 1, local]
				break
			if d.global_position.distance_to(origin * local) > 0.01 or d.global_position.distance_to(origin.origin) > DiceTable.PLAY.x:
				err = "第 %d 顆的世界座標 %s 應在骰盤 %s 附近" % [i + 1, d.global_position, origin.origin]
				break
	if err == "":   # 點得到每一顆（斜著看，射線不能先打到看不到的高牆：試玩時點骰子變成又丟一次）
		for i in DiceDefs.DICE_COUNT:
			var at: Vector3 = table._dice[i].global_position + Vector3(0, 0.5, 0)
			var picked: int = table._pick_die(cam.unproject_position(at))
			if picked != i:
				err = "指著第 %d 顆的頂面應點到它，點到 %d" % [i + 1, picked + 1]
				break
	if err == "" and vp.get_camera_3d() != cam:
		err = "桌子自己的鏡頭不該搶走遊戲畫面的鏡頭"
	if err == "":
		var screen := cam.unproject_position(origin.origin)
		var p: Vector3 = table._table_point(screen, 0.0)
		if Vector2(p.x, p.z).length() > 0.5:
			err = "滑鼠指著骰盤中間，換算回桌面本地應在中間附近：%s" % p
	table.queue_free()   # 桌子的節點掛在 vp 的世界裡：先放掉桌子、下一幀再放掉 vp（同一幀放掉引擎會報 scenario 是 null）
	await (Engine.get_main_loop() as SceneTree).process_frame
	vp.queue_free()
	if err != "":
		return err
	var w := _dice_world()
	var pl := _player(w)
	var e := _elite(w, pl.pos + Vector2(6, 0))
	w.alert_pack(_lone_pack(w, e), e, pl)
	var dp := DicePanel.new()
	dp.tray_right = Vector3(1, 0, 0)
	var t := dp.tray_transform(w, w.dice, pl)
	dp.free()
	# 桌面長方形（轉向照擺的）跟霧牆的圓不重疊
	var at := Vector2(t.origin.x, t.origin.z)
	var rx := Vector2(t.basis.x.x, t.basis.x.z)
	var rz := Vector2(t.basis.z.x, t.basis.z.z)
	var off := w.dice.arena_center - at
	var local := Vector2(off.dot(rx), off.dot(rz))
	var nearest := Vector2(clampf(local.x, -DiceTable.PLAY.x / 2.0, DiceTable.PLAY.x / 2.0), clampf(local.y, -DiceTable.PLAY.y / 2.0, DiceTable.PLAY.y / 2.0))
	if nearest.distance_to(local) < w.dice.arena_radius - 0.01:
		return "骰盤應擺在霧牆外：桌面離圈中心最近 %.1f（半徑 %.1f）" % [nearest.distance_to(local), w.dice.arena_radius]
	# 骰盤可以擺在牆上（底下的牆、樹擲骰時壓平）：高度照地面、不照牆頂；擺的地方有怪就換個地方
	var w4 := _dice_world()
	var p4 := _player(w4)
	var e4 := _elite(w4, p4.pos + Vector2(0, 4))
	w4.alert_pack(_lone_pack(w4, e4), e4, p4)
	var t0 := dp2_tray(w4)
	var blocks: Array[Dictionary] = w4.terrain.blocks.duplicate()
	blocks.append({"min": t0 - Vector2(3, 3), "max": t0 + Vector2(3, 3), "top": 2.0, "kind": MapDefs.WALL})
	w4.terrain = Terrain.new(blocks)
	var y_on_wall := dp2_tray_y(w4)
	if absf(y_on_wall - (w4.terrain.floor_at(t0) + DiceDefs.TRAY_LIFT)) > EPS:
		return "骰盤底下有牆時高度照地面（%.2f）、不照牆頂：%.2f" % [w4.terrain.floor_at(t0) + DiceDefs.TRAY_LIFT, y_on_wall]
	# 優先擺牆外（角色與怪走不到，不會被蓋住）：右邊是空地、左邊一整片牆 → 擺到左邊的牆上
	var w5 := _new_world(12345, false, &"practice")
	w5.dice = DiceRun.new()
	w5.dice.reset()
	var p5 := _player(w5)
	var e5 := _elite(w5, p5.pos + Vector2(0, 4))
	w5.alert_pack(_lone_pack(w5, e5), e5, p5)
	var open_at := dp2_tray(w5)
	var band: Array[Dictionary] = [{"min": Vector2(-w5.half_extents.x, -w5.half_extents.y), "max": Vector2(p5.pos.x - 12.0, w5.half_extents.y), "top": 3.0, "kind": MapDefs.WALL}]
	w5.terrain = Terrain.new(band)
	var wall_at := dp2_tray(w5)
	if not w5.terrain.blocks_nav(wall_at, 0.0) or open_at.x < p5.pos.x:
		return "旁邊有牆時骰盤應擺在牆外：沒牆時 %s（應在右邊空地）、左邊一片牆時 %s（應在牆上）" % [open_at, wall_at]
	var cut_err := _check_tray_cut()
	if cut_err != "":
		return cut_err
	var spot_err := _check_tray_spot()
	if spot_err != "":
		return spot_err
	_note("骰盤放進遊戲世界：%.2f 秒停好、面 %s" % [frames / 60.0, got[0] if not got.is_empty() else []])
	return ""



# 地圖有擲骰台時：開一場，骰盤擺在其中一塊擲骰台上（離這一場最近、不壓到霧牆）
# 有擲骰台的地圖（整張地圖一個），每一群開打骰盤都擺在那個擲骰台上（種子 3 第 1 小關每一群各開一場）
static func _check_tray_spot() -> String:
	var n := -1
	var i := 0
	while i != n:
		var w := World.new()
		_worlds.append(w)
		w.dice = DiceRun.new()
		w.reset(3)
		var spots: Array = w.map.get("dice_spots", [])
		if spots.is_empty() or w.packs.is_empty():
			return "第 1 小關（種子 3）應有擲骰台與怪群"
		n = w.packs.size()
		var pk: Dictionary = w.packs[i]
		var first := w.entities.get(pk.ids[0]) as Enemy
		var p := _player(w)
		p.pos = w.nav.nearest_walkable(first.pos + Vector2(0, 3))
		w.alert_pack(i, first, p)
		var at := dp2_tray(w)
		var on_spot := false
		for sp: Vector2 in spots:
			if MapDefs.to_world(w.map, sp).distance_to(at) < 0.01:
				on_spot = true
		if not on_spot:
			return "有擲骰台的地圖，骰盤應擺在擲骰台上：第 %d 群擺在 %s，擲骰台 %s" % [i, at, spots.map(func(sp: Vector2) -> Vector2: return MapDefs.to_world(w.map, sp))]
		i += 1
	return ""


static func dp2_tray_y(w: World) -> float:
	var dp := DicePanel.new()
	dp.tray_right = Vector3(1, 0, 0)
	var t := dp.tray_transform(w, w.dice, _player(w))
	dp.free()
	return t.origin.y


# 骰子模式的地形裝飾換成壓得平的材質（一般模式照舊）：擲骰時（tray_cut 有值）一下子壓平、範圍照骰盤，收起來後慢慢長回來
static func _check_tray_cut() -> String:
	var w := _new_world()
	var blocks: Array[Dictionary] = [{"min": Vector2(2, 2), "max": Vector2(4, 4), "top": 2.0, "kind": MapDefs.WALL}]
	var terrain := Terrain.new(blocks)
	var plain := ArenaView.new()
	plain.build(w.half_extents, terrain, &"graveyard", [], 1, 0, false)
	var dice := ArenaView.new()
	dice.build(w.half_extents, terrain, &"graveyard", [], 1, 0, true)
	var err := ""
	var mats: Array = []
	for view: ArenaView in [plain, dice]:
		var m: Material = null
		for c in view.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).material_override != null and c.has_meta(&"tufts"):
				m = (c as MeshInstance3D).material_override
		mats.append(m)
	if not (mats[0] is StandardMaterial3D) or not (mats[1] is ShaderMaterial):
		err = "地形裝飾的材質：一般模式應照舊（%s）、骰子模式換成壓得平的（%s）" % [mats[0], mats[1]]
	if err == "":
		var cut := {"center": Vector2(3, 3), "right": Vector2(1, 0), "half": DiceTable.PLINTH / 2.0, "floor": 0.0}
		dice.update_cut(cut, DT)
		var sm: ShaderMaterial = mats[1]
		if dice.cut_amount() < 1.0 or sm.get_shader_parameter(&"cut_center") != cut.center or sm.get_shader_parameter(&"cut_half") != cut.half:
			err = "擲骰時應一下子壓平、範圍照骰盤：壓了 %.2f、中心 %s" % [dice.cut_amount(), sm.get_shader_parameter(&"cut_center")]
		var half_way := -1.0
		for i in roundi(1.5 / DT):
			dice.update_cut(null, DT)
			if i == roundi(0.1 / DT):
				half_way = dice.cut_amount()
		if err == "" and (half_way <= 0.0 or half_way >= 1.0 or dice.cut_amount() > 0.0):
			err = "骰盤收起來後應慢慢長回來：0.1 秒時 %.2f、1.5 秒後 %.2f" % [half_way, dice.cut_amount()]
	plain.free()
	dice.free()
	return err


static func dp2_tray(w: World) -> Vector2:
	var dp := DicePanel.new()
	dp.tray_right = Vector3(1, 0, 0)
	var t := dp.tray_transform(w, w.dice, _player(w))
	dp.free()
	return Vector2(t.origin.x, t.origin.z)


# 獎勵畫面看骰子（§55）：獎勵卡下面一條攤平的骰面：你帶的 6 顆（面照帶的）、指著新骰子 / 新武器卡才多那顆；
# 新骰子會換掉的那顆（空白最多）標「會被換掉」；整個獎勵畫面放得進介面最大檔（3D 骰子 2026-11-24 拿掉，跟攤平的重複）；
# 骰面的圖示（FaceIcons）：劍盾的圖、每把武器開局骰子的技能都有圖、去了背（四角透明、中間不透明）；有圖的面貼圖、不寫字，別的武器的技能淡掉，空白面不放東西
static func check_dice_inspect() -> String:
	var icon_ids: Array[StringName] = [&"whirlwind", &"shield_charge", &"sword_wave", &"shield_slam", &"blade_storm", &"fx_shield", &"fx_dmg"]
	for wid: StringName in DiceDefs.WEAPON_DICE:   # 每把武器開局骰子的技能都要有圖
		icon_ids.append(DiceDefs.WEAPON_DICE[wid][0])
	for id: StringName in icon_ids:
		var tex := FaceIcons.texture(id)
		if tex == null:
			return "技能 / 效果 %s 應有圖示（res://assets/icons/%s.png）" % [id, id]
		var im := tex.get_image()
		if im.is_compressed():
			im.decompress()
		var n := im.get_width() - 1
		var solid := 0
		var total := 0
		for y in range(0, n, 8):
			for x in range(0, n, 8):
				total += 1
				if im.get_pixel(x, y).a > 0.9:
					solid += 1
		if im.get_pixel(0, 0).a > 0.05 or im.get_pixel(n, n).a > 0.05 or solid < total * 0.2:   # 劍氣的月牙中間是空的：不看正中間，看不透明的佔多少
			return "圖示 %s 應去背：四角透明（%.2f、%.2f）、不透明的至少兩成（%d / %d）" % [id, im.get_pixel(0, 0).a, im.get_pixel(n, n).a, solid, total]
	var holder := Node3D.new()
	var nodes := DiceTable.build_die_visual(holder, null)
	DiceTable.paint_die(nodes, [&"whirlwind", DiceDefs.BLANK, &"frost_nova", &"fx_dmg", DiceDefs.BLANK, DiceDefs.BLANK], &"swordShield")
	var quads: Array = nodes.map(func(pair: Array) -> MeshInstance3D: return pair[0])
	var labels: Array = nodes.map(func(pair: Array) -> Label3D: return pair[1])
	var icon_ok := func(k: int, alpha: float) -> bool:
		var m := (quads[k] as MeshInstance3D).material_override as StandardMaterial3D
		return quads[k].visible and m.albedo_texture != null and is_equal_approx(m.albedo_color.a, alpha) and (labels[k] as Label3D).text == ""
	var face_err := ""
	if not icon_ok.call(0, 1.0) or not icon_ok.call(3, 1.0):
		face_err = "有圖示的面應貼圖、不寫字"
	elif FaceIcons.has(&"frost_nova") and not icon_ok.call(2, 0.3):
		face_err = "別的武器的技能（法杖的冰霜新星）應淡掉（0.3）"
	elif quads[1].visible:
		face_err = "空白面不放色塊（白色骰身）"
	holder.free()
	if face_err != "":
		return face_err
	var w := _dice_world()
	var p := _player(w)
	var s := w.dice.seat_of(p)
	var blank: Array[StringName] = []
	for f in DiceDefs.FACES:
		blank.append(DiceDefs.BLANK)
	s.loose.append(blank)
	w.dice._carry(s, 2, s.all_dice().size() - 1)   # 帶著的第 3 顆全空白：新骰子應換掉它
	var new_die := DiceDefs.make_die(&"blue", DiceDefs.skills_for(p.weapon_id), w.rng)
	var weapon_die := DiceDefs.weapon_die(&"staff")
	s.offers = [{"kind": &"die", "title": "藍骰", "desc": "", "faces": new_die},
		{"kind": &"weapon", "title": "法杖", "desc": "", "faces": weapon_die, "base": &"staff"},
		{"kind": &"item", "title": "道具", "desc": "", "item": 0}]
	w.dice.phase = DiceRun.REWARD
	var cam := Camera3D.new()
	_scene_root().add_child(cam)
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w, cam)
	_scene_root().add_child(hud)
	var dp: DicePanel = hud.dice_panel
	dp.refresh(w, p, 0.05)
	var err := ""
	# 沒指著卡：只有你帶的 6 顆（還沒選，不先放獎勵的骰子），攤平的 6 面同帶的、都沒標字
	if dp.flat_count() != DiceDefs.DICE_COUNT:
		err = "沒指著卡時應只有你帶的 6 顆：%d 顆" % dp.flat_count()
	else:
		for i in DiceDefs.DICE_COUNT:
			if dp.flat_faces_of(i) != Array(s.pool[i]) or dp.flat_tag(i) != "":
				err = "第 %d 顆攤平的 6 面應同你帶的、不標字：%s / %s「%s」" % [i + 1, dp.flat_faces_of(i), s.pool[i], dp.flat_tag(i)]
				break
	# 指著新骰子卡：後面多一顆、第 3 顆（全空白）標會被換掉、新的那顆標選這張會拿到
	if err == "":
		dp._hover_offer = 0
		dp.refresh(w, p, 0.05)
		if dp.flat_count() != DiceDefs.DICE_COUNT + 1 or w.dice.most_blank_slot(s) != 2 or dp.flat_tag(2) != "會被換掉" or dp.flat_tag(6) != "選這張會拿到" or dp.flat_faces_of(6) != Array(new_die):
			err = "指著新骰子卡：應 7 顆、第 3 顆標會被換掉、第 7 顆是新骰子：%d 顆、「%s」「%s」" % [dp.flat_count(), dp.flat_tag(2), dp.flat_tag(6)]
	# 指著新武器卡：後面多一顆新武器的骰子，不標換掉
	if err == "":
		dp._hover_offer = 1
		dp.refresh(w, p, 0.05)
		if dp.flat_count() != DiceDefs.DICE_COUNT + 1 or dp.flat_tag(2) != "" or dp.flat_tag(6) != "新武器的骰子" or dp.flat_faces_of(6) != Array(weapon_die):
			err = "指著新武器卡：應 7 顆、不標換掉、第 7 顆是新武器的骰子：%d 顆、「%s」「%s」" % [dp.flat_count(), dp.flat_tag(2), dp.flat_tag(6)]
	# 鍵盤：D 從沒選換到第 1 張、再 D 第 2 張（新武器，跟滑鼠指著一樣預覽）、F 選它
	if err == "":
		dp._hover_offer = -1
		var picks: Array = []
		dp.op_requested.connect(func(op: Array) -> void: picks.append(op))
		var right := InputEventKey.new()
		right.physical_keycode = KEY_D
		right.pressed = true
		dp.handle_key(right)
		var first_card: int = dp._hover_offer
		dp.handle_key(right)
		dp.refresh(w, p, 0.05)
		var f := InputEventKey.new()
		f.physical_keycode = KEY_F
		f.pressed = true
		dp.handle_key(f)
		if first_card != 0 or dp._hover_offer != 1 or dp.flat_tag(6) != "新武器的骰子" or picks != [[InputCmd.OP_DICE_REWARD, 1]]:
			err = "獎勵卡用鍵盤：D 應選第 1 張（%d）、再 D 第 2 張（%d）並預覽新武器的骰子（%s）、F 選它（%s）" % [first_card, dp._hover_offer, dp.flat_tag(6), picks]
		dp._picked = false
		dp._hover_offer = 0
		dp.refresh(w, p, 0.05)
	# 直式桌遊卡（2026-11-24 選方案 2）：指著的那張抬起來、其他的放下；數值道具卡畫效果圖示（道具沒有自己的圖）
	if err == "":
		var slots: Array = dp._reward_cards.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())
		var lifted: float = (slots[0].get_child(0) as Control).position.y
		var rest: float = (slots[1].get_child(0) as Control).position.y
		var item_art: Node = slots[2].get_child(0).get_child(0).get_child(0).get_child(0).get_child(0)
		if dp._hover_offer != 0 or lifted != 0.0 or rest != DicePanel.CARD_LIFT or not (item_art is TextureRect):
			err = "獎勵卡：指著的第 1 張應抬起（%.0f）、第 2 張放下（%.0f）、道具卡畫圖示（%s）" % [lifted, rest, item_art.get_class()]
	# 操作說明只教一次（2026-11-24）：沒看過的第一次寫，換階段再回來就不寫；重新顯示提示後再寫一次
	if err == "":
		hud.hints.save_path = ""
		hud.hints.seen.clear()
		dp._teaching.clear()
		dp.refresh(w, p, 0.05)
		var first: String = dp._reward_title.text
		dp._last_phase = DiceRun.FIGHT
		dp.refresh(w, p, 0.05)
		var again: String = dp._reward_title.text
		hud.hints.reset_seen()
		dp._last_phase = DiceRun.FIGHT
		dp.refresh(w, p, 0.05)
		var reset: String = dp._reward_title.text
		if not first.contains("點卡片") or again.contains("點卡片") or not reset.contains("點卡片"):
			err = "選獎勵的操作說明應只教一次、重新顯示提示後再教：第一次「%s」、之後「%s」、重設後「%s」" % [first, again, reset]
	if err == "":
		var base := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
		var room: Vector2 = base / (SettingsPanel.UI_SCALES.max() * SettingsPanel.BASE_UI_SCALE)
		var need: Vector2 = dp._reward_box.get_combined_minimum_size()
		if need.x > room.x or need.y > room.y:
			err = "獎勵畫面（含骰子）%s 超出介面最大檔 %s" % [need, room]
		else:
			_note("獎勵畫面含骰子 %s（介面最大檔 %s）" % [need, room])
	hud.queue_free()
	cam.queue_free()
	return err


# 打一場 / 擲骰 / 選獎勵的時候別群被吵醒（試玩發現：最後一下的聲音在同一步吵醒隔壁群，那群醒了卻沒開打、沒霧牆、沒擲骰、打死也沒獎勵）：
# 先記著，回到逛地圖時馬上開那一場（有菁英就擲骰）
static func check_dice_pending_alert() -> String:
	var w := _dice_world()
	var p := _player(w)
	p.hp = 99999.0
	var a := _spawn(w, &"grunt", p.pos + Vector2(4, 0))
	var b := _elite(w, p.pos + Vector2(-DiceDefs.MERGE_RANGE - 6.0, 0))   # 隔壁群：地圖預放的（開打前就在、睡著；夠遠，不會一起醒）
	b.dormant = true
	var bi := _lone_pack(w, b)
	w.alert_pack(_lone_pack(w, a), a, p)
	_to_fight(w)
	if w.dice.phase != DiceRun.FIGHT or w.dice.foes.has(b.id):
		return "應擲完開打、隔壁群不在這一場：%s、foes %s" % [w.dice.phase, w.dice.foes]
	a.die()
	_clear_out(w)
	if w.dice.phase != DiceRun.REWARD:
		return "打完應選獎勵：%s" % w.dice.phase
	w.alert_pack(bi, b, p)   # 選獎勵的時候被吵醒
	var s := w.dice.seat_of(p)
	_run(w, _op_cmd([InputCmd.OP_DICE_REWARD, _simple_pick(s)]), 1)
	if not s.carve.is_empty():
		_run(w, _op_cmd([InputCmd.OP_DICE_CARVE, 0, 5, 0]), 1)
	if w.dice.phase != DiceRun.ROLL or not w.dice.foes.has(b.id) or w.dice.arena_radius <= 0.0:
		return "選完獎勵應馬上開那一場（菁英先擲骰、有霧牆）：%s、foes %s、霧牆 %.1f" % [w.dice.phase, w.dice.foes, w.dice.arena_radius]
	return ""


# 小模型（底座）：骰子模式走路時腳不跨步、腳底（腳掌中心）在底座半徑 FIGURE_FOOT_SPAN 成內（腳掌有長度，腳尖再往前一點），
# 整隻連底座跳著走、左右晃，停下收回；一般模式照舊跨步（腳伸得比骰子模式遠得多）
static func check_dice_figure() -> String:
	var got := {}
	for dice: bool in [false, true]:
		var w := _dice_world() if dice else _new_world()
		var p := _player(w)
		var view := WorldView.new()
		_scene_root().add_child(view)
		view.sync(w, 1.0, DT)
		var node: Node3D = view._nodes[p.id]
		var rig: Rig = node as Rig
		var sole := Vector3(0.0, -(rig.leg_r.position.y + rig.shin_r.position.y), 0.0)
		var r := {"foot": 0.0, "lift": 0.0, "tilt": 0.0, "rest_lift": 0.0, "rest_tilt": 0.0}
		for i in roundi(1.5 / DT):
			var moving := i < roundi(1.0 / DT)
			_run(w, _cmd(Vector2(1, 0) if moving else Vector2.ZERO), 1)
			view.sync(w, 1.0, DT)
			var to_root := node.global_transform.affine_inverse()
			for shin: Node3D in [rig.shin_r, rig.shin_l]:
				var f := to_root * (shin.global_transform * sole)
				r.foot = maxf(r.foot, Vector2(f.x, f.z).length())
			var lift := node.position.y - p.height
			var tilt := node.basis.y.angle_to(Vector3.UP)
			if moving:
				r.lift = maxf(r.lift, lift)
				r.tilt = maxf(r.tilt, tilt)
			else:
				r.rest_lift = lift
				r.rest_tilt = tilt
		view.queue_free()
		got[dice] = r
	var base := WorldView.figure_base_radius(_player(_new_world()).radius)
	var d: Dictionary = got[true]
	var n: Dictionary = got[false]
	CheckKit._note("小模型：底座半徑 %.2f；骰子模式腳最遠 %.2f、跳 %.3f、晃 %.1f°；一般模式腳最遠 %.2f" % [base, d.foot, d.lift, rad_to_deg(d.tilt), n.foot])
	if n.foot < d.foot * 2.0 or n.lift > EPS or n.tilt > EPS:
		return "一般模式應照舊跨步、不跳：腳最遠 %.2f（骰子模式 %.2f）、跳 %.3f、晃 %.3f" % [n.foot, d.foot, n.lift, n.tilt]
	if d.foot > base * WorldView.FIGURE_FOOT_SPAN + EPS:
		return "骰子模式腳底不應踩出底座：最遠 %.2f（底座 %.2f × %.2f）" % [d.foot, base, WorldView.FIGURE_FOOT_SPAN]
	if d.lift < WorldView.FIGURE_HOP_HEIGHT * 0.9 or d.tilt < WorldView.FIGURE_HOP_TILT * 0.9:
		return "骰子模式走路應整隻跳著走、左右晃：跳 %.3f（應到 %.2f）、晃 %.3f（應到 %.2f）" % [d.lift, WorldView.FIGURE_HOP_HEIGHT, d.tilt, WorldView.FIGURE_HOP_TILT]
	if d.rest_lift > 0.01 or d.rest_tilt > 0.01:
		return "停下 0.5 秒應收回：還高 %.3f、還斜 %.3f" % [d.rest_lift, d.rest_tilt]
	return ""


# 隔著牆要繞路的怪不拉進這一場（繞的路出了霧牆會卡在圈邊，近戰打不到、這一場打不完）：
# 直線 MERGE_RANGE 內、走過去超過的怪群不併；隔牆 notice_close 內不會發現（一般模式照舊會），空地上一樣近會
static func check_dice_reach() -> String:
	var found := false
	for seed_value in range(1, 21):
		var w := World.new()
		_worlds.append(w)
		w.dice = DiceRun.new()
		w.reset(seed_value)
		var p := _player(w)
		for i in w.packs.size():
			var a: Dictionary = w.packs[i]
			var center: Vector2 = a.center
			for j in w.packs.size():
				var b: Dictionary = w.packs[j]
				if j == i or center.distance_to(b.center) > DiceDefs.MERGE_RANGE or w.nav.path_length(center, b.center) <= DiceDefs.MERGE_RANGE * 1.5:
					continue
				var first := w.entities.get(a.ids[0]) as Enemy
				p.pos = w.nav.nearest_walkable(center + Vector2(0, 3))
				w.alert_pack(i, first, p)
				for id: int in b.ids:
					if w.dice.foes.has(id) or b.awake:
						return "種子 %d：群 %d 直線 %.1f、要走 %.1f，不應併進這一場" % [seed_value, j, center.distance_to(b.center), w.nav.path_length(center, b.center)]
				found = true
				break
			if found:
				break
		if found:
			break
	if not found:
		return "種子 1~20 找不到直線近、要繞路的怪群（地圖產生改了，換種子範圍）"
	var c: Dictionary = MonsterRarityDefs.PACKS
	# [骰子模式, 中間有牆, 應不應發現]：玩家在怪背後 notice_close 內（只有靠近這一種會發現）
	for t: Array in [[true, true, false], [false, true, true], [true, false, true]]:
		var w2 := _new_world()
		if t[0]:
			w2.dice = DiceRun.new()
			w2.dice.reset()
			w2.dice.on_stage_start(w2)
		var mid := MapDefs.to_world(w2.map, Vector2(24.0, 23.5)) if t[1] else Vector2(-8, -8)   # test_arena 那道 6 × 1 的牆
		if t[1] and not w2.terrain.blocks_nav(mid, 0.0):
			return "test_arena 的牆不在 %s（地圖改了）" % mid
		var gap: float = c.notice_close * 0.45
		var e := _spawn(w2, &"grunt", mid + Vector2(0, gap))
		e.dormant = true
		e.fsm.change(&"dormant")
		e.facing = 0.0   # 面向 +y，背對玩家
		_lone_pack(w2, e)
		_player(w2).pos = mid - Vector2(0, gap)
		_run(w2, _cmd(Vector2.ZERO), c.notice_every + 1)
		if w2.packs[0].awake != t[2]:
			return "%s、%s：玩家在背後 %.1f，發現 = %s（應 %s）" % ["骰子模式" if t[0] else "一般模式", "中間有牆" if t[1] else "空地", gap * 2.0, w2.packs[0].awake, t[2]]
	return ""


# 召喚詞條叫出來的手下也算這一場的怪（試玩發現：把召喚者那群打死就跳獎勵，叫出來的還活著在打人）：
# 叫出來的進 foes、被霧牆關在圈內；召喚者死了手下還在就繼續打，手下也死光才選獎勵
static func check_dice_summoned() -> String:
	var w := _dice_world()
	var p := _player(w)
	p.hp = 99999.0
	var a := _spawn(w, &"grunt", p.pos + Vector2(4, 0))
	a.set_rarity(&"magic", [&"summoner"])
	a._summon_timer = 0.5
	w.alert_pack(_lone_pack(w, a), a, p)
	_to_fight(w)
	if w.dice.phase != DiceRun.FIGHT:
		return "菁英群擲完骰應開打：%s" % w.dice.phase
	var minions: Array[Enemy] = []
	for i in ceili(10.0 / DT):
		for e in w.enemies:
			if e is Enemy and (e as Enemy).summoner_id == a.id and not e.is_dead and not minions.has(e):
				minions.append(e as Enemy)
		if not minions.is_empty():
			break
		_run(w, _cmd(Vector2.ZERO), 1)
	if minions.is_empty():
		return "召喚詞條 10 秒內應叫出手下"
	for m in minions:
		if not w.dice.foes.has(m.id):
			return "叫出來的手下應算這一場的怪（foes %s 沒有 %d）" % [w.dice.foes, m.id]
	a.die()
	_run(w, _cmd(Vector2.ZERO), 1)
	if w.dice.phase != DiceRun.FIGHT:
		return "召喚者死了、手下還活著應繼續打：%s" % w.dice.phase
	for e in w.enemies:
		if e is Enemy and (e as Enemy).summoner_id == a.id and not e.is_dead:
			(e as Enemy).die()
	_clear_out(w)
	if w.dice.phase != DiceRun.REWARD:
		return "手下也死光、清場完應選獎勵：%s" % w.dice.phase
	return ""


# 骰盤在戰場旁時面板上的按鈕點得到（試玩發現：骰完畫面上的按鈕點不了，只能按 Enter——放開滑鼠被轉給骰盤吃掉，按鈕放開才觸發）：
# 經過 Viewport 送「按下、放開」：按在按鈕上的兩下都不給骰盤（傳得到後面，GUI 才收得到）；按在骰盤上照樣蓄力
# headless 沒有視窗、GUI 不收滑鼠，所以看「有沒有被吃掉」：_ClickSpy 擺在根節點第一個（_input 照樹倒著叫，排在面板後面），
# 面板吃掉的它就收不到；按鈕真的觸發靠網頁版試玩
class _ClickSpy extends Node:
	var got: Array = []

	func _input(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			got.append(e.pressed)


static func check_dice_panel_clicks() -> String:
	var w := _dice_world()
	var p := _player(w)
	var e := _elite(w, p.pos + Vector2(6, 0))
	w.alert_pack(_lone_pack(w, e), e, p)
	var cam := Camera3D.new()
	_scene_root().add_child(cam)
	cam.make_current()
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w, cam)
	_scene_root().add_child(hud)
	var holder := Node3D.new()
	_scene_root().add_child(holder)
	var spy := _ClickSpy.new()
	_scene_root().add_child(spy)
	_scene_root().move_child(spy, 0)
	var dp: DicePanel = hud.dice_panel
	dp.physics = true
	dp.use_world_table(holder, cam, Vector3(1, 0, 0), 0.0)
	var vp := dp.get_viewport()
	var err := ""
	for f in 3:
		dp.refresh(w, p, 0.05)
		await (Engine.get_main_loop() as SceneTree).process_frame
	dp.table.can_throw = true
	dp.table.cup_mode = false
	# 用「完成」按鈕（擲法按鈕 2026-11-24 搬到設定頁）：還沒擲時按不了，但照樣擋著、不漏給骰盤
	if w.dice.phase != DiceRun.ROLL or not dp._btn_done.visible:
		err = "應在擲骰、完成按鈕看得到：%s、%s" % [w.dice.phase, dp._btn_done.visible]
	else:
		var at: Vector2 = dp._btn_done.get_global_rect().get_center()
		vp.push_input(_mouse_button(at, true), true)
		vp.push_input(_mouse_button(at, false), true)
		if spy.got != [true, false] or dp.table.charging:
			err = "按在完成按鈕上的按下、放開應都不給骰盤（傳到後面 %s、骰盤蓄力 %s）" % [spy.got, dp.table.charging]
	if err == "":   # 按在骰盤上（不是按鈕）：照樣轉給骰盤蓄力
		spy.got.clear()
		cam.look_at_from_position(dp.table.center() + Vector3(0, 12, 10), dp.table.center())
		var tray: Vector2 = cam.unproject_position(dp.table.center())
		vp.push_input(_mouse_button(tray, true), true)
		if not dp.table.charging or not spy.got.is_empty():
			err = "按在骰盤上應給骰盤蓄力（滑鼠在 %s、蓄力 %s、漏到後面 %s）" % [tray, dp.table.charging, spy.got]
		vp.push_input(_mouse_button(tray, false), true)
	if err == "":   # 倒數：鏡頭回到自己（看得到角色與怪的配置）、骰盤收起來、只留結果總覽；回到擲骰照舊
		w.dice.phase = DiceRun.COUNTDOWN
		w.dice.timer = DiceDefs.COUNTDOWN
		dp.refresh(w, p, 0.05)
		if dp.camera_focus() != null or dp.table.is_shown() or dp._btn_done.is_visible_in_tree() or dp._title.is_visible_in_tree() \
				or not dp._summary.is_visible_in_tree() or dp._dim.visible:
			err = "倒數時鏡頭應回到自己（看骰盤 %s）、骰盤收起來（%s）、按鈕與標題收起來（%s、%s）、結果總覽留著（%s）、不變暗（%s）" % [
				dp.camera_focus() != null, dp.table.is_shown(), dp._btn_done.is_visible_in_tree(), dp._title.is_visible_in_tree(),
				dp._summary.is_visible_in_tree(), dp._dim.visible]
		w.dice.phase = DiceRun.ROLL
		dp.refresh(w, p, 0.05)
		if err == "" and (dp.camera_focus() == null or not dp.table.is_shown() or not dp._btn_done.is_visible_in_tree() or not dp._title.is_visible_in_tree()):
			err = "回到擲骰時鏡頭應看骰盤（%s）、骰盤與按鈕、標題出來（%s、%s、%s）" % [
				dp.camera_focus() != null, dp.table.is_shown(), dp._btn_done.is_visible_in_tree(), dp._title.is_visible_in_tree()]
	spy.queue_free()
	hud.queue_free()
	holder.queue_free()
	cam.queue_free()
	return err
