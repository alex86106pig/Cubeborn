# 骰子模式的一局（World.dice；一般模式是 null，docs/系統說明.md §55）：
#   逛地圖 → 怪群發現玩家 / Boss 開追 → 一般群直接開打；有菁英或 Boss 的先暫停、照 world.player_list 輪流免費擲骰 → 3、2、1 → 戰鬥
#   → 這一場的怪全倒 → 擲骰次數 +1、4 選 1 獎勵（暫停）→ 逛地圖；逛地圖或戰鬥中按 R 花 1 次自己擲（戰鬥中擲完也倒數）
# 擲骰、倒數、選獎勵時 World.step 只跑這裡（step_frozen），其他實體都停住。骰子的結果先決定好（world.rng），畫面照 roll_seq 播動畫
# 結果留到下一次擲完才換（沒擲骰就打起來的怪：一般群、挖墳噴的、戰鬥中才進來的，照手上的結果打）
# 骰子：手上武器的 6 顆武器骰存在武器實例的 "dice"（換武器時跟著武器走，刻上去的面也是），獎勵拿到的骰子放 Seat.loose；
# 每場擲 Seat.carry 指的 6 顆（逛地圖時在骰子與武器面板挑）
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
var tier: StringName = &"normal"   # 這一場的難度（DiceDefs.FIGHT_TIERS）：獎勵的稀有度看它
var back_to: StringName = &""   # 花次數自己擲（逛地圖 / 戰鬥中按 R）：擲完回到這個階段（戰鬥中照樣倒數）；空 = 菁英 / Boss 的開場擲骰
var resuming := false           # 這次倒數是戰鬥中擲完的：倒數完接著打，不再給開場護盾與回血
var bonus_rerolls := 0          # 這一關每次擲骰多幾次重擲（門的獎勵，DiceDefs.DOOR_REWARDS）
var reward_tier: StringName = &"normal"   # 正在選的獎勵是哪個難度給的（畫面標題用）
var door_pick := false          # 正在選的獎勵是門給的（不是打完一場：沒有擲骰次數 +1）
var physics := false            # 物理擲骰（main.gd 開：畫面的 DiceTable 丟、停好後用 OP_DICE_FACES 回報朝上的面）；false = 模擬層自己抽（檢查、沒有畫面時）
var waiting := false            # 物理擲骰：丟出去了、還在等桌子回報（settle 當等待上限，到了就自己抽）
var charges: Dictionary = {}    # peer_id -> 擲骰次數（不放 Seat：換關時補次數不該先建 Seat，Seat 建立時才照武器生骰子）
var states: Dictionary = {}     # peer_id -> Seat


# 一位玩家的骰子：pool 是這場帶的 6 顆（每顆 6 面，跟 wdice / loose 是同一個陣列，刻面直接改到），face 是每顆朝上的那面
class Seat:
	var pool: Array = []
	var wdice: Array = []         # 手上武器的 6 顆武器骰（= 武器實例的 "dice"）
	var weapon_uid: StringName = &""
	var loose: Array = []         # 獎勵拿到的骰子
	var carry: Array[int] = [0, 1, 2, 3, 4, 5]   # 這場帶哪 6 顆：0~5 武器骰、6 起 loose[i - 6]
	var spares: Array = []        # 備用武器（武器實例，各自帶 "dice"）
	var face: Array[int] = [0, 0, 0, 0, 0, 0]
	var locked: Array[bool] = [false, false, false, false, false, false]
	var rolled := false
	var rerolls := 0
	var done := false
	var choice: StringName = &""
	var result: Dictionary = {}   # DiceDefs.evaluate + cdr；空 = 還沒有右鍵
	var roll_seq := 0             # 擲了幾次（畫面看它變了就播動畫）
	var offers: Array = []        # 這一輪的獎勵選項；空 = 沒在選
	var carve: Dictionary = {}    # 選了刻面、還沒選刻在哪：{kind, face（效果面）, skills（刻技能面的候選）}；空 = 沒在刻
	var item_count := 0           # 拿過幾個數值道具（屬性來源 dice_item:N）

	func up_faces() -> Array[StringName]:
		var out: Array[StringName] = []
		for i in pool.size():
			out.append(pool[i][face[i]])
		return out

	# 全部的骰子（carry 的編號）：0~5 武器骰、6 起備用骰
	func all_dice() -> Array:
		return wdice + loose

	func choosing() -> bool:
		return not offers.is_empty() or not carve.is_empty()


func reset() -> void:
	phase = EXPLORE
	fights = 0
	turn = 0
	timer = 0.0
	settle = 0.0
	foes.clear()
	tier = &"normal"
	back_to = &""
	resuming = false
	waiting = false
	bonus_rerolls = 0
	charges.clear()
	states.clear()


func is_frozen() -> bool:
	return phase == ROLL or phase == COUNTDOWN or phase == REWARD


# 這位玩家的骰子；武器換了（或第一次）就把 wdice 接到手上那把的 "dice"（沒有就照 DiceDefs.weapon_die 生 6 顆），pool 照 carry 重接
func seat_of(p: Player) -> Seat:
	if not states.has(p.peer_id):
		states[p.peer_id] = Seat.new()
		p.basic_attack_mul = DiceDefs.BASIC_ATTACK_MUL
	var s: Seat = states[p.peer_id]
	var inst := p.active_weapon()
	if not inst.is_empty() and (StringName(inst.uid) != s.weapon_uid or not is_same(s.wdice, inst.get("dice"))):
		ensure_dice(inst)
		s.wdice = inst.dice
		s.weapon_uid = StringName(inst.uid)
	_wire_pool(s)
	return s


func _wire_pool(s: Seat) -> void:
	var all := s.all_dice()
	s.pool.resize(DiceDefs.DICE_COUNT)
	for i in DiceDefs.DICE_COUNT:
		var k: int = s.carry[i] if i < s.carry.size() else i
		s.pool[i] = all[k] if k < all.size() else all[i]


# 武器實例沒有骰子就補上：開局的武器照 DiceDefs.weapon_die（6 顆一樣）
static func ensure_dice(inst: Dictionary) -> void:
	if inst.has("dice"):
		return
	var die := DiceDefs.weapon_die(Loadout.weapon_of(inst))
	var dice: Array = []
	for i in DiceDefs.DICE_COUNT:
		dice.append(die.duplicate())
	inst["dice"] = dice


# 掉落 / 獎勵的武器：照稀有度隨機產生一種骰子（只出這把武器能用的技能），6 顆都長這樣
static func make_weapon_dice(inst: Dictionary, rng: RandomNumberGenerator) -> void:
	var die := DiceDefs.make_die(StringName(inst.rarity), DiceDefs.skills_for(Loadout.weapon_of(inst)), rng)
	var dice: Array = []
	for i in DiceDefs.DICE_COUNT:
		dice.append(die.duplicate())
	inst["dice"] = dice


# 輪到誰擲（不在擲骰時回傳 null）
func current(world: World) -> Player:
	return _turn_player(world) if phase == ROLL else null


# ---------- 流程 ----------

func charges_of(p: Player) -> int:
	return int(charges.get(p.peer_id, 0))


func _add_charges(p: Player, n: int) -> void:
	charges[p.peer_id] = mini(DiceDefs.CHARGES_MAX, charges_of(p) + n)


# 一關開始（World._populate_floor：開局、換關、換層、同一關重來）：每人 +CHARGES_STAGE 次；門的重擲加成只算一關
func on_stage_start(world: World) -> void:
	phase = EXPLORE
	foes.clear()
	back_to = &""
	resuming = false
	bonus_rerolls = 0
	for p in world.player_list:
		_add_charges(p, DiceDefs.CHARGES_STAGE)
		if states.has(p.peer_id):
			seat_of(p).carve = {}
			seat_of(p).offers = []


# 走進門的獎勵（World._grant_stage_reward，下一關開始時）：獎勵 → 馬上一次 4 選 1（菁英的稀有度）；重擲 → 這一關每次擲骰重擲 +1
func door_reward(world: World, reward: StringName) -> void:
	var d: Dictionary = DiceDefs.DOOR_REWARDS.get(reward, {})
	match d.get("kind", &""):
		&"reroll":
			bonus_rerolls += DiceDefs.DOOR_REROLLS
		&"reward":
			tier = &"elite"
			reward_tier = tier
			door_pick = true
			var any := false
			for p in world.player_list:
				var s := seat_of(p)
				s.offers = _make_offers(world, p, s) if can_roll(p) else []
				any = any or not s.offers.is_empty()
			tier = &"normal"
			if any:
				phase = REWARD
				world.emit_event("dice:reward", {"fight": fights, "door": true})


# 怪群被發現、Boss 開追（World.alert_pack、Boss.aggro）：逛地圖時開一場；已經在這一場裡就併進來，不重擲
# 一般的怪群直接開打（用手上的結果）；有菁英（魔法 / 稀有）或 Boss 的先免費擲一次、倒數再開打
func on_alert(world: World, ids: Array) -> void:
	var big := false
	var was_explore := phase == EXPLORE
	for id: int in ids:
		var e := world.entities.get(id) as Enemy
		if e != null and not e.is_dead and not foes.has(id):
			foes.append(id)
			big = big or e.is_boss() or e.rarity != MonsterRarityDefs.NORMAL
			if e.is_boss():
				tier = &"boss"
			elif e.rarity != MonsterRarityDefs.NORMAL and tier != &"boss":
				tier = &"elite"
	if not was_explore or foes.is_empty():
		return
	fights += 1
	world.emit_event("dice:encounter", {"fight": fights, "foes": foes.size(), "roll": big})
	if big:
		_start_roll(world, null)
	else:
		_start_fight(world)


# 開始擲骰：roller = null 是開場擲骰（活著的每人輪流），否則只有那位（花次數自己擲，擲完回到 back_to）
func _start_roll(world: World, roller: Player) -> void:
	phase = ROLL
	turn = 0
	settle = 0.0
	timer = DiceDefs.ROLL_TIME
	for p in world.player_list:
		var s := seat_of(p)
		s.locked.fill(false)
		s.rolled = false
		s.rerolls = DiceDefs.REROLLS + bonus_rerolls
		s.choice = &""
		s.done = not can_roll(p) or (roller != null and p != roller)
	_skip_done(world)


# 開打：開場護盾與開場回血在這裡給（每一場一次；戰鬥中按 R 重擲不再給）
func _start_fight(world: World) -> void:
	phase = FIGHT
	for p in world.player_list:
		p.fight_shield = 0.0
	for p in world.player_list:
		var s := seat_of(p)
		if s.result.is_empty() or not can_roll(p):
			continue
		for id: StringName in s.result.effects:
			var n: float = s.result.effects[id]
			var e: Dictionary = DiceDefs.EFFECTS[id]
			match e.kind:
				&"shield":
					for q in world.player_list:
						if q == p or e.get("team", false):
							q.fight_shield += e.value * n
				&"heal":
					p.hp = minf(p.max_hp, p.hp + p.max_hp * e.value * n)
	world.emit_event("dice:fight", {"fight": fights})
	var first := world.first_alive_player()
	if first != null:
		world.emit_event("sfx:cue", {"cue": "waveStart", "pos": first.pos})


func can_roll(p: Player) -> bool:
	return not p.is_dead and not p.is_downed and not p.descended


# 擲骰、倒數、選獎勵時每步（World.step 取代其他所有更新）
func step_frozen(world: World, dt: float) -> void:
	match phase:
		ROLL:
			if settle > 0.0:
				settle = maxf(0.0, settle - dt)
				if settle <= 0.0 and waiting:   # 桌子一直沒回報：模擬層自己抽，流程不卡住
					var tp := _turn_player(world)
					if tp != null:
						_land(world, tp, [])
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
				if resuming:   # 戰鬥中擲完：接著打，開場護盾與回血這一場已經給過
					resuming = false
					phase = FIGHT
					world.emit_event("dice:fight", {"fight": fights})
				else:
					_start_fight(world)


func _turn_player(world: World) -> Player:
	return world.player_list[turn] if turn < world.player_list.size() else null


# 輪到的人跳過已經完成（倒地、死掉）的；全部完成就倒數（逛地圖時花次數擲的直接回到逛地圖）
func _skip_done(world: World) -> void:
	while turn < world.player_list.size() and seat_of(world.player_list[turn]).done:
		turn += 1
	if turn >= world.player_list.size():
		var back := back_to
		back_to = &""
		if back == EXPLORE:
			phase = EXPLORE
			world.emit_event("dice:resume", {"phase": String(phase)})
			return
		resuming = back == FIGHT
		phase = COUNTDOWN
		timer = DiceDefs.COUNTDOWN
		world.emit_event("dice:countdown", {"fight": fights})
		return
	timer = DiceDefs.ROLL_TIME
	world.emit_event("dice:turn", {"player_id": world.player_list[turn].id})


# 擲沒鎖的（第一次是全部）。物理擲骰：先記下擲了（roll_seq +1，畫面看到別人 / 時間到擲的就自己丟），等 OP_DICE_FACES 回報才定面
func _roll(world: World, p: Player) -> void:
	var s := seat_of(p)
	s.roll_seq += 1
	timer = DiceDefs.ROLL_TIME
	if physics:
		waiting = true
		settle = DiceDefs.PHYSICS_WAIT
		s.rolled = true
		return
	_land(world, p, [])


# 骰子停好：faces 是桌子回報的每顆朝上的面（空的 = 模擬層用 world.rng 抽）；鎖住的不變
func _land(world: World, p: Player, faces: Array) -> void:
	var s := seat_of(p)
	for i in s.pool.size():
		if not s.locked[i]:   # 每次開始擲骰都會解鎖（_start_roll），第一次丟一定全部重抽
			s.face[i] = clampi(int(faces[i]), 0, DiceDefs.FACES - 1) if i < faces.size() else world.rng.randi_range(0, DiceDefs.FACES - 1)
	s.rolled = true
	waiting = false
	settle = 0.0 if physics else DiceDefs.SETTLE_TIME
	timer = DiceDefs.ROLL_TIME
	var res := DiceDefs.evaluate(s.up_faces(), p.weapon_id, s.choice)
	world.emit_event("dice:rolled", {"player_id": p.id, "skill": String(res.skill), "count": res.count, "combos": res.combos})


func _finish_turn(world: World, p: Player) -> void:
	var s := seat_of(p)
	s.done = true
	_apply_result(world, p, s)
	world.emit_event("dice:done", {"player_id": p.id, "skill": String(s.result.skill), "count": s.result.count})
	turn += 1
	settle = 0.0
	_skip_done(world)


# 這一場的怪都倒了（World.on_enemy_died）：擲骰次數 +1、4 選 1 獎勵（稀有度看這一場的難度）
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
		_add_charges(p, DiceDefs.CHARGES_PER_FIGHT)
		s.offers = _make_offers(world, p, s) if can_roll(p) else []
		any = any or not s.offers.is_empty()
	reward_tier = tier
	door_pick = false
	tier = &"normal"
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
			if phase == REWARD and s.carve.is_empty() and op.size() > 1 and int(op[1]) >= 0 and int(op[1]) < s.offers.size():
				var o: Dictionary = s.offers[int(op[1])]
				s.offers = []
				_take_offer(world, p, s, o)
				_end_reward_if_done(world)
			return
		InputCmd.OP_DICE_CARVE:
			if phase == REWARD and not s.carve.is_empty() and op.size() > 3:
				if _carve(p, s, int(op[1]), int(op[2]), int(op[3])):
					world.emit_event("dice:carved", {"player_id": p.id})
					_end_reward_if_done(world)
			return
		InputCmd.OP_DICE_CARRY:
			if phase == EXPLORE and op.size() > 2:
				_carry(s, int(op[1]), int(op[2]))
			return
		InputCmd.OP_DICE_WEAPON:
			if phase == EXPLORE and op.size() > 1 and int(op[1]) >= 0 and int(op[1]) < s.spares.size():
				var inst: Dictionary = s.spares[int(op[1])]
				s.spares[int(op[1])] = p.active_weapon()
				_hold(world, p, inst)
			return
	if int(op[0]) == InputCmd.OP_DICE_ROLL and (phase == EXPLORE or phase == FIGHT):
		if charges_of(p) > 0 and can_roll(p):   # 花 1 次自己擲：暫停；物理擲骰時打開桌子等玩家丟，否則一按就擲出去
			charges[p.peer_id] = charges_of(p) - 1
			back_to = phase
			_start_roll(world, p)
			if not physics:
				_roll(world, p)
		return
	if int(op[0]) == InputCmd.OP_DICE_FACES:
		if phase == ROLL and waiting and _turn_player(world) == p and op.size() > DiceDefs.DICE_COUNT:
			_land(world, p, op.slice(1, DiceDefs.DICE_COUNT + 1))
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


func _end_reward_if_done(world: World) -> void:
	for q in world.player_list:
		if seat_of(q).choosing():
			return
	phase = EXPLORE
	world.emit_event("dice:explore", {"fight": fights})


# 帶著的第 slot 顆換成 k（全部骰子的編號）；k 已經帶著就兩顆互換位置
func _carry(s: Seat, slot: int, k: int) -> bool:
	if slot < 0 or slot >= DiceDefs.DICE_COUNT or k < 0 or k >= s.all_dice().size():
		return false
	var at := s.carry.find(k)
	if at >= 0:
		s.carry[at] = s.carry[slot]
	s.carry[slot] = k
	_wire_pool(s)
	return true


# 刻面：刻在帶著的第 slot 顆的第 face 面（空白優先由畫面引導，其他面也可以蓋掉）；刻技能面用 skill 選第幾個候選
func _carve(p: Player, s: Seat, slot: int, face: int, skill: int) -> bool:
	if slot < 0 or slot >= s.pool.size() or face < 0 or face >= DiceDefs.FACES:
		return false
	var id: StringName
	if s.carve.kind == &"carve_skill":
		var skills: Array = s.carve.skills
		if skill < 0 or skill >= skills.size():
			return false
		id = skills[skill]
	else:
		id = s.carve.face
	(s.pool[slot] as Array)[face] = id
	s.carve = {}
	return true


# 換一把武器到手上（舊的不在這裡處理）：左鍵與 6 顆武器骰一起換；手上的結果清掉（技能面是舊武器的），要重擲
func _hold(world: World, p: Player, inst: Dictionary) -> void:
	ensure_dice(inst)
	p.loadout.hold_weapon(p, inst)
	var s := seat_of(p)
	s.result = {}
	s.choice = &""
	p.set_stat_source(&"dice", [])
	var team_source := StringName("dice_team:%d" % p.peer_id)
	for q in world.player_list:
		q.set_stat_source(team_source, [])
	p.basic_attack_mul = DiceDefs.BASIC_ATTACK_MUL
	world.emit_event("dice:weapon", {"player_id": p.id, "base": String(inst.base)})


# 拿到一把武器（地上撿的、獎勵）：放進備用；備用滿了就直接換到手上、手上那把（連它的骰子）掉在腳邊。滿了又不在逛地圖時不拿，回傳 false
func receive_weapon(world: World, p: Player, inst: Dictionary) -> bool:
	var s := seat_of(p)
	if s.spares.size() < DiceDefs.SPARE_WEAPONS:
		ensure_dice(inst)
		s.spares.append(inst)
		world.emit_event("dice:weapon_stored", {"player_id": p.id, "base": String(inst.base)})
		return true
	if phase != EXPLORE and phase != REWARD:
		return false
	var old := p.active_weapon()
	_hold(world, p, inst)
	if not old.is_empty():
		world.drop_weapon(old, p.pos)
	return true


# 撿地上的武器（Interactables.use 在骰子模式轉來這裡）
func take_pickup(world: World, p: Player, ip: ItemPickup) -> bool:
	if not ip.is_weapon() or not receive_weapon(world, p, ip.weapon):
		return false
	ip.remove()
	return true


# ---------- 結果 ----------

# 擲完：右鍵換成骰到的那招，效果面掛上去（stat 掛屬性來源 dice、全隊的每位擲的人各一個來源）；護盾與回血等開打才給（_start_fight）
func _apply_result(world: World, p: Player, s: Seat) -> void:
	var res := DiceDefs.evaluate(s.up_faces(), p.weapon_id, s.choice)
	var own: Array = []
	var team: Array = []
	var basic := 0.0
	var cdr := 0.0
	for id: StringName in res.effects:
		var n: float = res.effects[id]
		var e: Dictionary = DiceDefs.EFFECTS[id]
		match e.kind:
			&"stat":
				(team if e.get("team", false) else own).append([e.stat[0], e.stat[1], float(e.stat[2]) * n])
			&"basic":
				basic += e.value * n
			&"cdr":
				cdr += e.value * n
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
		"power": DiceDefs.tier_of(s.result.tier_count).mul, "count": s.result.count}


func cooldown_for(p: Player) -> float:
	var s: Seat = states.get(p.peer_id)
	return DiceDefs.cooldown_of(s.result.skill, s.result.get("cdr", 0.0)) if s != null and not s.result.is_empty() else DiceDefs.COOLDOWN_MIN


# ---------- 獎勵 ----------

# 4 選 1、種類不重複（world.rng 抽）
func _make_offers(world: World, p: Player, s: Seat) -> Array:
	var kinds: Array = DiceDefs.REWARD_KINDS.duplicate()
	var out := []
	while out.size() < DiceDefs.REWARD_CHOICES and not kinds.is_empty():
		var k: StringName = kinds.pop_at(world.rng.randi_range(0, kinds.size() - 1))
		var o := _offer(world, p, s, k)
		if not o.is_empty():
			out.append(o)
	return out


func _offer(world: World, p: Player, _s: Seat, kind: StringName) -> Dictionary:
	var skills := DiceDefs.skills_for(p.weapon_id)
	var effects: Array = DiceDefs.EFFECTS.keys()
	match kind:
		&"die":
			var rarity := DiceDefs.roll_rarity(tier, world.rng)
			var faces := DiceDefs.make_die(rarity, skills, world.rng)
			return {"kind": kind, "title": "%s骰" % DiceDefs.RARITIES[rarity].name, "rarity": rarity, "faces": faces,
				"desc": "放進備用骰子，自動換掉這場帶的骰子裡空白最多的那顆（Tab 可以再換）"}
		&"weapon":
			var bases := WeaponDropDefs.bases()
			var base := bases[world.rng.randi_range(0, bases.size() - 1)]
			var inst := WeaponDropDefs.make(world.new_weapon_uid(), base, DiceDefs.roll_rarity(tier, world.rng), world.rng)
			make_weapon_dice(inst, world.rng)
			return {"kind": kind, "title": WeaponDropDefs.display_name(inst), "weapon": inst, "faces": (inst.dice[0] as Array).duplicate(),
				"base": base, "desc": "六顆武器骰都長這樣；先放進備用武器，按 Tab 換上（左鍵一起換）"}
		&"carve_skill":
			if skills.is_empty():
				return {}
			return {"kind": kind, "title": "刻技能面", "desc": "選了才揭曉：從你武器能用的技能裡三選一，自己選刻在哪顆骰子的哪一面"}
		&"carve_effect":
			var id: StringName = effects[world.rng.randi_range(0, effects.size() - 1)]
			return {"kind": kind, "title": "刻效果面：%s" % DiceDefs.effect_text(id, 1), "desc": "自己選刻在哪一面（空白優先）", "face": id}
		_:
			var i := world.rng.randi_range(0, DiceDefs.ITEMS.size() - 1)
			return {"kind": &"item", "title": DiceDefs.ITEMS[i].name, "desc": "數值道具：一直有效", "item": i}


# 帶著的骰子裡空白面最多的那顆（同樣多取後面的；都沒有空白取最後一顆）
func _most_blank_slot(s: Seat) -> int:
	var best := DiceDefs.DICE_COUNT - 1
	var best_n := -1
	for i in s.pool.size():
		var n: int = (s.pool[i] as Array).count(DiceDefs.BLANK)
		if n >= best_n:
			best = i
			best_n = n
	return best


func _take_offer(world: World, p: Player, s: Seat, o: Dictionary) -> void:
	match o.kind:
		&"die":
			s.loose.append((o.faces as Array).duplicate())
			_carry(s, _most_blank_slot(s), s.all_dice().size() - 1)
		&"weapon":
			receive_weapon(world, p, o.weapon)
		&"carve_skill":
			var pool := DiceDefs.skills_for(p.weapon_id)
			var picks: Array[StringName] = []
			while picks.size() < DiceDefs.CARVE_SKILL_CHOICES and not pool.is_empty():
				picks.append(pool.pop_at(world.rng.randi_range(0, pool.size() - 1)))
			s.carve = {"kind": &"carve_skill", "skills": picks}
		&"carve_effect":
			s.carve = {"kind": &"carve_effect", "face": o.face}
		&"item":
			var stat: Array = DiceDefs.ITEMS[o.item].stat
			p.set_stat_source(StringName("dice_item:%d" % s.item_count), [[stat[0], stat[1], float(stat[2])]])
			s.item_count += 1
	world.emit_event("dice:picked", {"player_id": p.id, "kind": String(o.kind)})
