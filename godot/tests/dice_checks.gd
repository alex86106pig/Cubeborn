# 骰子模式（DiceRun / DiceDefs，docs/系統說明.md §55）：結算、一場的流程（暫停、擲 / 鎖 / 重擲 / 完成、倒數、右鍵、打完選獎勵）、限時自動擲、Boss 開追也開一場
# 由 tests/check.gd 呼叫；每個 check_* 回傳 "" = 通過，否則是失敗原因
class_name DiceChecks
extends CheckKit


static func _dice_world() -> World:
	var w := _new_world()
	w.dice = DiceRun.new()
	w.dice.reset()
	return w


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
	return ""


# 一場：怪群發現玩家就暫停（怪不動、冷卻不走）→ 擲（轉的時候不收操作）→ 鎖住的那顆重擲不變 → 完成：右鍵換成骰到的技能、效果面掛上 →
# 倒數完才開打 → 右鍵放骰到的技能（不耗魔、照威力、進冷卻）→ 這一場的怪全倒 → 3 選 1 獎勵（暫停）→ 選了回到逛地圖
static func check_dice_fight() -> String:
	var w := _dice_world()
	var p := _player(w)
	var e := _spawn(w, &"grunt", p.pos + Vector2(8, 0))
	if p.slots.get_slot(p, ActiveSlots.DICE_INDEX) != null:
		return "還沒擲骰就有右鍵技能"
	w.alert_pack(_lone_pack(w, e), e, p)
	if w.dice.phase != DiceRun.ROLL or not w.dice.foes.has(e.id):
		return "怪群發現玩家後應開始擲骰：phase %s、foes %s" % [w.dice.phase, w.dice.foes]
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
	if not is_equal_approx(p.fight_shield, DiceDefs.EFFECTS[&"fx_shield"].value) or not is_equal_approx(p.basic_attack_mul, DiceDefs.BASIC_ATTACK_MUL):
		return "開場護盾 %.1f（應 %s）、普攻倍率 %.2f（應 %s）" % [p.fight_shield, DiceDefs.EFFECTS[&"fx_shield"].value, p.basic_attack_mul, DiceDefs.BASIC_ATTACK_MUL]
	if w.dice.phase != DiceRun.COUNTDOWN:
		return "全部擲完應倒數：%s" % w.dice.phase
	_wait(w, DiceDefs.COUNTDOWN * 0.5)
	if e.pos != at:
		return "倒數時怪應停住"
	_wait(w, DiceDefs.COUNTDOWN * 0.5)
	if w.dice.phase != DiceRun.FIGHT:
		return "倒數完應開打：%s" % w.dice.phase
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
	if w.dice.phase != DiceRun.REWARD or s.offers.is_empty() or s.offers.size() > DiceDefs.REWARD_CHOICES:
		return "這一場的怪全倒應選獎勵：phase %s、選項 %d" % [w.dice.phase, s.offers.size()]
	var tick := w.tick
	var cd_at := w.cooldowns.remaining(p.cd("player.special"))
	_wait(w, 0.5)
	if not w.dice.is_frozen() or not is_equal_approx(w.cooldowns.remaining(p.cd("player.special")), cd_at):
		return "選獎勵時應暫停（冷卻不走）：%.2f → %.2f" % [cd_at, w.cooldowns.remaining(p.cd("player.special"))]
	var pick := 0
	for i in s.offers.size():
		if s.offers[i].kind == &"item":
			pick = i
	var o: Dictionary = s.offers[pick]
	var blanks_before := _blank_count(s)
	_run(w, _op_cmd([InputCmd.OP_DICE_REWARD, pick]), 1)
	if w.dice.phase != DiceRun.EXPLORE or not s.offers.is_empty():
		return "選完獎勵應回到逛地圖：%s（tick %d → %d）" % [w.dice.phase, tick, w.tick]
	match o.kind:
		&"item":
			if not p.stats.has_source(&"dice_item:0"):
				return "數值道具應掛上屬性來源 dice_item:0"
		&"carve_skill", &"carve_effect":
			if _blank_count(s) != blanks_before - 1:
				return "刻面後空白應少 1：%d → %d" % [blanks_before, _blank_count(s)]
		&"die":
			if not s.pool.has(o.faces):
				return "新骰子應放進骰子裡"
	return ""


static func _blank_count(s: DiceRun.Seat) -> int:
	var n := 0
	for die: Array in s.pool:
		n += die.count(DiceDefs.BLANK)
	return n


# 限時：沒動作 ROLL_TIME 秒自動擲，再 ROLL_TIME 秒自動完成，倒數後開打；Boss 開追也開一場；一般模式（dice = null）發現玩家不暫停
static func check_dice_auto() -> String:
	var w := _dice_world()
	var p := _player(w)
	var e := _spawn(w, &"grunt", p.pos + Vector2(8, 0))
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
