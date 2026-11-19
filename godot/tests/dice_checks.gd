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
	if w.dice.phase != DiceRun.REWARD or s.offers.size() != DiceDefs.REWARD_CHOICES:
		return "這一場的怪全倒應 %d 選 1：phase %s、選項 %d" % [DiceDefs.REWARD_CHOICES, w.dice.phase, s.offers.size()]
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



# 擲骰次數（YangHsu 2026-11-19）：開局 CHARGES_STAGE 次；一般的怪群碰到不暫停、直接開打（開場護盾照手上的結果給）；
# 戰鬥中按 R 花 1 次擲、擲完倒數再接著打（不再給開場護盾）；打完 +CHARGES_PER_FIGHT；逛地圖按 R 花 1 次、擲完回到逛地圖；
# 0 次按 R 沒反應；換關 +CHARGES_STAGE、最多 CHARGES_MAX
static func check_dice_charges() -> String:
	var w := _dice_world()
	var p := _player(w)
	var s := w.dice.seat_of(p)
	if w.dice.charges_of(p) != DiceDefs.CHARGES_STAGE:
		return "開局應有 %d 次：%d" % [DiceDefs.CHARGES_STAGE, w.dice.charges_of(p)]
	var e := _spawn(w, &"grunt", p.pos + Vector2(8, 0))
	w.alert_pack(_lone_pack(w, e), e, p)
	if w.dice.phase != DiceRun.FIGHT or w.dice.is_frozen():
		return "一般的怪群應直接開打、不暫停：%s" % w.dice.phase
	_run(w, _op_cmd([InputCmd.OP_DICE_ROLL]), 1)
	if w.dice.phase != DiceRun.ROLL or w.dice.charges_of(p) != DiceDefs.CHARGES_STAGE - 1 or not s.rolled:
		return "戰鬥中按 R 應花 1 次擲出去：%s、剩 %d、rolled %s" % [w.dice.phase, w.dice.charges_of(p), s.rolled]
	_wait(w, DiceDefs.SETTLE_TIME)
	s.face[0] = s.pool[0].find(&"fx_shield")
	var shield := p.fight_shield
	_run(w, _op_cmd([InputCmd.OP_DICE_DONE]), 1)
	if w.dice.phase != DiceRun.COUNTDOWN:
		return "戰鬥中擲完應倒數再接著打：%s" % w.dice.phase
	_wait(w, DiceDefs.COUNTDOWN)
	if w.dice.phase != DiceRun.FIGHT:
		return "倒數完應接著打：%s" % w.dice.phase
	if not is_equal_approx(p.fight_shield, shield):
		return "戰鬥中重擲不該再給開場護盾：%.1f → %.1f" % [shield, p.fight_shield]
	e.die(p.id)
	if w.dice.charges_of(p) != DiceDefs.CHARGES_STAGE - 1 + DiceDefs.CHARGES_PER_FIGHT:
		return "打完一群應 +%d 次：%d" % [DiceDefs.CHARGES_PER_FIGHT, w.dice.charges_of(p)]
	_run(w, _op_cmd([InputCmd.OP_DICE_REWARD, _simple_pick(s)]), 1)
	var e2 := _spawn(w, &"grunt", p.pos + Vector2(8, 0))
	w.alert_pack(_lone_pack(w, e2), e2, p)
	var want: float = DiceDefs.EFFECTS[&"fx_shield"].value * s.result.effects.get(&"fx_shield", 0)
	if w.dice.phase != DiceRun.FIGHT or want <= 0.0 or not is_equal_approx(p.fight_shield, want):
		return "下一群直接開打時照手上的結果給開場護盾 %.1f：%.1f（%s）" % [want, p.fight_shield, w.dice.phase]
	e2.die(p.id)
	_run(w, _op_cmd([InputCmd.OP_DICE_REWARD, _simple_pick(s)]), 1)
	var before := w.dice.charges_of(p)
	_run(w, _op_cmd([InputCmd.OP_DICE_ROLL]), 1)
	if w.dice.phase != DiceRun.ROLL or w.dice.charges_of(p) != before - 1:
		return "逛地圖按 R 應花 1 次擲：%s、%d → %d" % [w.dice.phase, before, w.dice.charges_of(p)]
	_wait(w, DiceDefs.SETTLE_TIME)
	_run(w, _op_cmd([InputCmd.OP_DICE_DONE]), 1)
	if w.dice.phase != DiceRun.EXPLORE:
		return "逛地圖擲完應回到逛地圖：%s" % w.dice.phase
	w.dice.charges[p.peer_id] = 0
	_run(w, _op_cmd([InputCmd.OP_DICE_ROLL]), 1)
	if w.dice.phase != DiceRun.EXPLORE:
		return "0 次時按 R 不該擲：%s" % w.dice.phase
	w.dice.on_stage_start(w)
	if w.dice.charges_of(p) != DiceDefs.CHARGES_STAGE:
		return "換關應 +%d 次：%d" % [DiceDefs.CHARGES_STAGE, w.dice.charges_of(p)]
	w.dice.on_stage_start(w)
	if w.dice.charges_of(p) != DiceDefs.CHARGES_MAX:
		return "最多存 %d 次：%d" % [DiceDefs.CHARGES_MAX, w.dice.charges_of(p)]
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
	DiceRun.make_weapon_dice(inst, w.rng)
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
	DiceRun.make_weapon_dice(ground, w.rng)
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
	_run(w, _op_cmd([InputCmd.OP_DICE_ROLL]), 1)
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


# 骰子模式的介面放得下（介面最大檔）：骰子與武器面板（帶 6 顆 + 沒帶的 8 顆 + 備用武器 2 把）、4 張獎勵卡、刻面（6 顆 × 6 面 + 3 個技能）、物理擲骰畫面
static func check_dice_panels() -> String:
	var w := _dice_world()
	var p := _player(w)
	var s := w.dice.seat_of(p)
	for i in 8:
		s.loose.append(DiceDefs.make_die(&"blue", DiceDefs.skills_for(p.weapon_id), w.rng))
	for b: StringName in [&"longbow", &"staff"]:
		var inst := WeaponDropDefs.make(w.new_weapon_uid(), b, &"purple", w.rng)
		DiceRun.make_weapon_dice(inst, w.rng)
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
	table.queue_free()
	return err


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
