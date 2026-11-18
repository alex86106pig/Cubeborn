# 骰子模式的一局（World.dice；一般模式是 null，docs/系統說明.md §55）：
#   逛地圖 → 怪群發現玩家 / Boss 開追 → 世界暫停、照 world.player_list 輪流擲骰 → 3、2、1 → 戰鬥 → 這一場的怪全倒 → 3 選 1 獎勵（暫停）→ 逛地圖
# 擲骰、倒數、選獎勵時 World.step 只跑這裡（step_frozen），其他實體都停住。骰子的結果先決定好（world.rng），畫面照 roll_seq 播動畫
# 結果留到下一場擲完才換（沒擲骰就打起來的怪：挖墳噴的、戰鬥中才進來的，照上一場的打）
class_name DiceRun
extends RefCounted

const EXPLORE := &"explore"
const ROLL := &"roll"
const COUNTDOWN := &"countdown"
const FIGHT := &"fight"
const REWARD := &"reward"

var phase: StringName = EXPLORE
var fights := 0                 # 這一局開了幾場（畫面標題用）
var turn := 0                   # 輪到 world.player_list 的第幾位
var timer := 0.0                # 這一位擲骰剩幾秒（ROLL）／倒數剩幾秒（COUNTDOWN）
var settle := 0.0               # 骰子還在轉的秒數：這段不收操作、不倒數
var foes: Array[int] = []       # 這一場要打倒的怪（怪群成員、Boss）
var states: Dictionary = {}     # peer_id -> Seat


# 一位玩家的骰子：pool 是 6 顆骰子（每顆 6 面），face 是每顆朝上的那面
class Seat:
	var pool: Array = []
	var face: Array[int] = [0, 0, 0, 0, 0, 0]
	var locked: Array[bool] = [false, false, false, false, false, false]
	var rolled := false
	var rerolls := 0
	var done := false
	var choice: StringName = &""
	var result: Dictionary = {}   # DiceDefs.evaluate + cdr；空 = 還沒有右鍵
	var roll_seq := 0             # 擲了幾次（畫面看它變了就播動畫）
	var offers: Array = []        # 這一輪的獎勵選項；空 = 沒在選
	var item_count := 0           # 拿過幾個數值道具（屬性來源 dice_item:N）

	func up_faces() -> Array[StringName]:
		var out: Array[StringName] = []
		for i in pool.size():
			out.append(pool[i][face[i]])
		return out


func reset() -> void:
	phase = EXPLORE
	fights = 0
	turn = 0
	timer = 0.0
	settle = 0.0
	foes.clear()
	states.clear()


func is_frozen() -> bool:
	return phase == ROLL or phase == COUNTDOWN or phase == REWARD


func seat_of(p: Player) -> Seat:
	if not states.has(p.peer_id):
		var s := Seat.new()
		var die := DiceDefs.weapon_die(p.weapon_id)
		for i in DiceDefs.DICE_COUNT:
			s.pool.append(die.duplicate())
		states[p.peer_id] = s
		p.basic_attack_mul = DiceDefs.BASIC_ATTACK_MUL
	return states[p.peer_id]


# 輪到誰擲（不在擲骰時回傳 null）
func current(world: World) -> Player:
	return _turn_player(world) if phase == ROLL else null


# ---------- 流程 ----------

# 怪群被發現、Boss 開追（World.alert_pack、Boss.aggro）：逛地圖時開一場；已經在這一場裡就併進來，不重擲
func on_alert(world: World, ids: Array) -> void:
	for id: int in ids:
		var e := world.entities.get(id) as Enemy
		if e != null and not e.is_dead and not foes.has(id):
			foes.append(id)
	if phase != EXPLORE or foes.is_empty():
		return
	phase = ROLL
	fights += 1
	turn = 0
	settle = 0.0
	timer = DiceDefs.ROLL_TIME
	for p in world.player_list:
		var s := seat_of(p)
		s.locked.fill(false)
		s.rolled = false
		s.rerolls = DiceDefs.REROLLS
		s.choice = &""
		s.done = not _can_roll(p)
	for p in world.player_list:
		p.fight_shield = 0.0
	world.emit_event("dice:encounter", {"fight": fights, "foes": foes.size()})
	_skip_done(world)


func _can_roll(p: Player) -> bool:
	return not p.is_dead and not p.is_downed and not p.descended


# 擲骰、倒數、選獎勵時每步（World.step 取代其他所有更新）
func step_frozen(world: World, dt: float) -> void:
	match phase:
		ROLL:
			if settle > 0.0:
				settle = maxf(0.0, settle - dt)
				return
			timer -= dt
			if timer <= 0.0:
				var p := _turn_player(world)
				if p == null:
					_skip_done(world)
				elif not seat_of(p).rolled:
					_roll(world, p)
				else:
					_finish_turn(world, p)
		COUNTDOWN:
			timer -= dt
			if timer <= 0.0:
				phase = FIGHT
				world.emit_event("dice:fight", {"fight": fights})
				var p := world.first_alive_player()
				if p != null:
					world.emit_event("sfx:cue", {"cue": "waveStart", "pos": p.pos})


func _turn_player(world: World) -> Player:
	return world.player_list[turn] if turn < world.player_list.size() else null


# 輪到的人跳過已經完成（倒地、死掉）的；全部完成就倒數
func _skip_done(world: World) -> void:
	while turn < world.player_list.size() and seat_of(world.player_list[turn]).done:
		turn += 1
	if turn >= world.player_list.size():
		phase = COUNTDOWN
		timer = DiceDefs.COUNTDOWN
		world.emit_event("dice:countdown", {"fight": fights})
		return
	timer = DiceDefs.ROLL_TIME
	world.emit_event("dice:turn", {"player_id": world.player_list[turn].id})


# 擲沒鎖的（第一次是全部）
func _roll(world: World, p: Player) -> void:
	var s := seat_of(p)
	for i in s.pool.size():
		if not s.rolled or not s.locked[i]:
			s.face[i] = world.rng.randi_range(0, DiceDefs.FACES - 1)
	s.rolled = true
	s.roll_seq += 1
	settle = DiceDefs.SETTLE_TIME
	timer = DiceDefs.ROLL_TIME
	var res := DiceDefs.evaluate(s.up_faces(), p.weapon_id, s.choice)
	world.emit_event("dice:rolled", {"player_id": p.id, "skill": String(res.skill), "count": res.count})


func _finish_turn(world: World, p: Player) -> void:
	var s := seat_of(p)
	s.done = true
	_apply_result(world, p, s)
	world.emit_event("dice:done", {"player_id": p.id, "skill": String(s.result.skill), "count": s.result.count})
	turn += 1
	settle = 0.0
	_skip_done(world)


# 這一場的怪都倒了（World.on_enemy_died）：3 選 1 獎勵
func on_enemy_died(world: World, e: Enemy) -> void:
	if phase != FIGHT or not foes.has(e.id):
		return
	for id in foes:
		var f := world.entities.get(id) as Enemy
		if f != null and not f.is_dead and f != e:
			return
	foes.clear()
	var any := false
	for p in world.player_list:
		var s := seat_of(p)
		s.offers = _make_offers(world, p, s) if _can_roll(p) else []
		any = any or not s.offers.is_empty()
	phase = REWARD if any else EXPLORE
	world.emit_event("dice:reward" if any else "dice:explore", {"fight": fights})


# ---------- 操作（InputCmd.OP_DICE_*，World.step 一開頭交給這裡；不管有沒有暫停） ----------

func take_ops(world: World, cmds: Dictionary) -> void:
	for peer_id: int in cmds:
		var p: Player = world.players.get(peer_id)
		if p == null:
			continue
		for op: Array in (cmds[peer_id] as InputCmd).inv_ops:
			if InputCmd.is_dice_op(op):
				_op(world, p, op)


func _op(world: World, p: Player, op: Array) -> void:
	var s := seat_of(p)
	match int(op[0]):
		InputCmd.OP_DICE_REWARD:
			if phase == REWARD and op.size() > 1 and int(op[1]) >= 0 and int(op[1]) < s.offers.size():
				_take_offer(world, p, s, s.offers[int(op[1])])
				s.offers = []
				for q in world.player_list:
					if not seat_of(q).offers.is_empty():
						return
				phase = EXPLORE
				world.emit_event("dice:explore", {"fight": fights})
			return
	if phase != ROLL or _turn_player(world) != p or settle > 0.0 or s.done:
		return
	match int(op[0]):
		InputCmd.OP_DICE_ROLL:
			if not s.rolled:
				_roll(world, p)
			elif s.rerolls > 0 and s.locked.has(false):
				s.rerolls -= 1
				_roll(world, p)
		InputCmd.OP_DICE_LOCK:
			if s.rolled and s.rerolls > 0 and op.size() > 1 and int(op[1]) >= 0 and int(op[1]) < s.locked.size():
				s.locked[int(op[1])] = not s.locked[int(op[1])]
		InputCmd.OP_DICE_CHOICE:
			if s.rolled and op.size() > 1:
				s.choice = StringName(op[1])
		InputCmd.OP_DICE_DONE:
			if s.rolled:
				_finish_turn(world, p)


# ---------- 結果 ----------

# 擲完：右鍵換成骰到的那招，效果面掛上去（stat 掛屬性來源 dice、全隊的每位擲的人各一個來源）、護盾與回血開場就給
func _apply_result(world: World, p: Player, s: Seat) -> void:
	var res := DiceDefs.evaluate(s.up_faces(), p.weapon_id, s.choice)
	var own: Array = []
	var team: Array = []
	var basic := 0.0
	var cdr := 0.0
	for id: StringName in res.effects:
		var n: int = res.effects[id]
		var e: Dictionary = DiceDefs.EFFECTS[id]
		var targets: Array[Player] = [p]
		if e.get("team", false):
			targets = world.player_list
		match e.kind:
			&"stat":
				(team if e.get("team", false) else own).append([e.stat[0], e.stat[1], float(e.stat[2]) * n])
			&"basic":
				basic += e.value * n
			&"cdr":
				cdr += e.value * n
			&"shield":
				for q in targets:
					q.fight_shield += e.value * n
			&"heal":
				p.hp = minf(p.max_hp, p.hp + p.max_hp * e.value * n)
	p.set_stat_source(&"dice", own)
	var team_source := StringName("dice_team:%d" % p.peer_id)
	for q in world.player_list:
		q.set_stat_source(team_source, team)
	p.basic_attack_mul = DiceDefs.BASIC_ATTACK_MUL * (1.0 + basic)
	res["cdr"] = cdr
	s.result = res


# 右鍵（ActiveSlots.DICE_INDEX）：這一場骰到的技能；沒骰到回傳 null
func slot_for(p: Player) -> Variant:
	var s: Seat = states.get(p.peer_id)
	if s == null or s.result.is_empty() or s.result.skill == &"":
		return null
	var id: StringName = s.result.skill
	return {"def": SkillDefs.SKILLS[id], "id": id, "level": 1, "charges": -1, "fits": true, "free": true,
		"power": DiceDefs.tier_of(s.result.count).mul, "count": s.result.count}


func cooldown_for(p: Player) -> float:
	var s: Seat = states.get(p.peer_id)
	return DiceDefs.cooldown_of(s.result.skill, s.result.get("cdr", 0.0)) if s != null and not s.result.is_empty() else DiceDefs.COOLDOWN_MIN


# ---------- 獎勵 ----------

func _make_offers(world: World, p: Player, s: Seat) -> Array:
	var kinds: Array = DiceDefs.REWARD_KINDS.duplicate()
	if _blank_die(s) < 0:
		kinds.erase(&"carve_skill")
		kinds.erase(&"carve_effect")
	var out := []
	while out.size() < DiceDefs.REWARD_CHOICES and not kinds.is_empty():
		var k: StringName = kinds.pop_at(world.rng.randi_range(0, kinds.size() - 1))
		var o := _offer(world, p, k)
		if not o.is_empty():
			out.append(o)
	return out


func _offer(world: World, p: Player, kind: StringName) -> Dictionary:
	var skills := DiceDefs.skills_for(p.weapon_id)
	var effects: Array = DiceDefs.EFFECTS.keys()
	match kind:
		&"die":
			var r: Dictionary = _pick_rarity(world)
			var faces: Array[StringName] = []
			for i in world.rng.randi_range(r.blanks[0], r.blanks[1]):
				faces.append(DiceDefs.BLANK)
			if not skills.is_empty():
				for i in mini(DiceDefs.FACES - faces.size(), world.rng.randi_range(r.skills[0], r.skills[1])):
					faces.append(skills[world.rng.randi_range(0, mini(2, skills.size() - 1))])
			while faces.size() < DiceDefs.FACES:
				faces.append(effects[world.rng.randi_range(0, effects.size() - 1)])
			for i in range(faces.size() - 1, 0, -1):
				var j := world.rng.randi_range(0, i)
				var t := faces[i]
				faces[i] = faces[j]
				faces[j] = t
			return {"kind": kind, "title": "%s骰" % r.name, "desc": "取代空白最多的那顆骰子", "faces": faces, "rarity": r.id}
		&"carve_skill":
			if skills.is_empty():
				return {}
			var id: StringName = skills[world.rng.randi_range(0, skills.size() - 1)]
			return {"kind": kind, "title": "刻技能面：%s" % DiceDefs.name_of(id), "desc": "刻在空白最多的那顆骰子的空白面", "face": id}
		&"carve_effect":
			var id: StringName = effects[world.rng.randi_range(0, effects.size() - 1)]
			return {"kind": kind, "title": "刻效果面：%s" % DiceDefs.effect_text(id, 1), "desc": "刻在空白最多的那顆骰子的空白面", "face": id}
		_:
			var i := world.rng.randi_range(0, DiceDefs.ITEMS.size() - 1)
			return {"kind": &"item", "title": DiceDefs.ITEMS[i].name, "desc": "數值道具：一直有效", "item": i}


func _pick_rarity(world: World) -> Dictionary:
	var total := 0
	for r: Dictionary in DiceDefs.RARITIES:
		total += int(r.weight)
	var x := world.rng.randi_range(0, total - 1)
	for r: Dictionary in DiceDefs.RARITIES:
		x -= int(r.weight)
		if x < 0:
			return r
	return DiceDefs.RARITIES[0]


# 空白面最多的那顆（同樣多取後面的；都沒有空白回傳 -1）
func _blank_die(s: Seat) -> int:
	var best := -1
	var best_n := 0
	for i in s.pool.size():
		var n: int = (s.pool[i] as Array).count(DiceDefs.BLANK)
		if n > 0 and n >= best_n:
			best = i
			best_n = n
	return best


func _take_offer(world: World, p: Player, s: Seat, o: Dictionary) -> void:
	match o.kind:
		&"die":
			var i := _blank_die(s)
			if i < 0:   # 都沒有空白：取代效果面最多的那顆（不動技能）
				i = s.pool.size() - 1
			s.pool[i] = (o.faces as Array).duplicate()
		&"carve_skill", &"carve_effect":
			var i := _blank_die(s)
			if i >= 0:
				var die: Array = s.pool[i]
				die[die.find(DiceDefs.BLANK)] = o.face
		&"item":
			var stat: Array = DiceDefs.ITEMS[o.item].stat
			p.set_stat_source(StringName("dice_item:%d" % s.item_count), [[stat[0], stat[1], float(stat[2])]])
			s.item_count += 1
	world.emit_event("dice:picked", {"player_id": p.id, "kind": String(o.kind)})
