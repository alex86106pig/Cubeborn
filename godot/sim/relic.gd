# 遺物：祭壇 / 石棺開出、門與 Boss 的獎勵、鐵砧，放在地上；每個玩家按 F 打開自己的 N 選 1（N = 選項數屬性，基本 3）
# 選項擲過就固定，關掉再開還是同一組；骰子（Player.dice）用掉 1 顆把全部選項重擲。每人只能選一次，在場的玩家都選過才消失（鐵砧不消失）
# 選項存在遺物上（offers），快照照送，客戶端的面板直接讀；選、重骰、關掉走背包操作（InputCmd.OP_RELIC_*），只在權威端執行
# relic_kind：
#   item 道具（每個選項的稀有度照 tier 的機率各自擲、看尋寶；石棺有機會把一個換成詛咒袋，BagDefs.CURSED_CHANCE）
#   skill 技能（從全部技能抽，不綁武器；有還沒滿級的技能時保證 1 個是升級）；選到身上已經有的技能就升 1 級（Player.skill_levels）
#   bag 袋子（門的獎勵：小袋 N 選 1）、bag_big（Boss：大袋或強化袋 N 選 1）；選項寫成「物品 id@大小」（BagDefs.TIERS）
#   anvil 鐵砧（小關起點旁的固定設施，每人一次）：改造自己接著的一個袋子，加大一格 / 倍率 +0.25 / 換觸發（選項「anvil:種類:袋子 uid[:新種類]」）
class_name Relic
extends Entity

const ANVIL_PREFIX := "anvil:"

var relic_kind: StringName = &"item"
var tier: StringName = &"small"
var offers := {}   # peer id → 選項（StringName 的陣列）
var taken := {}    # peer id → true：選過了
var spotted := false   # 隊上有人看到過（World._spot_relics，權威端判斷、進快照）：小地圖不管自己走過沒有都畫


func _init(p_world: World, p_tier: StringName, at: Vector2, p_kind: StringName = &"item") -> void:
	super(p_world, &"relic", &"neutral", LootDefs.RELIC.radius, 1.0)
	tier = p_tier
	relic_kind = p_kind
	pos = at
	height = p_world.terrain.ground_at(at)


func can_be_hit() -> bool:
	return false


# p 按 F：還沒選過就打開（第一次打開時擲選項）
func open_for(p: Player) -> void:
	if taken.has(p.peer_id):
		return
	if not offers.has(p.peer_id):
		_roll(p)
	p.relic_id = id
	world.emit_event("relic:opened", {"relic_id": id, "player_id": p.id})


func _roll(p: Player) -> void:
	var n := maxi(1, roundi(p.stats.value(&"relic_choices")))
	var out: Array[StringName] = []
	match relic_kind:
		&"anvil":
			out = _anvil_options(p, n)
			if out.is_empty():
				out = _bag_options(n, false)   # 身上沒有能改的袋子：改成給一個新袋子
		&"skill":
			out = _skill_options(p, n)
		&"bag", &"bag_big":
			out = _bag_options(n, relic_kind == &"bag_big")
		_:
			for i in n:
				var rarity := LootDefs.roll_rarity(tier, world.rng, p.stats.value(&"treasure"))
				var pool := LootDefs.drop_pool(rarity).filter(func(id: StringName) -> bool: return not out.has(id))
				if pool.is_empty():
					pool = LootDefs.drop_pool(rarity)
				out.append(pool[world.rng.randi_range(0, pool.size() - 1)])
			if world.rng.randf() < BagDefs.CURSED_CHANCE.get(tier, 0.0):
				out[out.size() - 1] = _bag_option(_random_kind([]), &"cursed")
	offers[p.peer_id] = out


func _skill_options(p: Player, n: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var skills := SkillDefs.relic_pool()
	var own := skills.filter(func(id: StringName) -> bool: return p.loadout.has_item(id) and p.skill_levels.get(id, 1) < SkillDefs.LEVEL.max)
	if not own.is_empty():
		out.append(own[world.rng.randi_range(0, own.size() - 1)])
	for i in mini(n, skills.size()) - out.size():
		var left := skills.filter(func(id: StringName) -> bool: return not out.has(id))
		out.append(SkillDefs.pick_relic(left, world.rng))
	_shuffle(out)   # 保證的那個不會固定在第一張
	return out


# 袋子的選項：n 種不同的觸發袋（按鍵袋也算一種）；big = Boss 的，大小隨機大袋或強化袋
func _bag_options(n: int, big: bool) -> Array[StringName]:
	var out: Array[StringName] = []
	var used: Array[StringName] = []
	for i in mini(n, BagDefs.BAGS.size()):
		var kind := _random_kind(used)
		used.append(kind)
		out.append(_bag_option(kind, ([&"big", &"strong"] as Array[StringName])[world.rng.randi_range(0, 1)] if big else &"small"))
	return out


func _random_kind(exclude: Array[StringName]) -> StringName:
	var kinds: Array = BagDefs.BAGS.keys().filter(func(k: StringName) -> bool: return not exclude.has(k))
	return kinds[world.rng.randi_range(0, kinds.size() - 1)]


static func _bag_option(kind: StringName, bag_tier: StringName) -> StringName:
	return StringName("%s@%s" % [BagDefs.BAGS[kind].item, bag_tier])


# 選項是不是袋子：回傳 { kind, tier }，不是回傳 {}
static func bag_choice(choice: StringName) -> Dictionary:
	var parts := String(choice).split("@")
	var kind := BagDefs.kind_of_item(StringName(parts[0]))
	if kind == &"":
		return {}
	return {"kind": kind, "tier": StringName(parts[1]) if parts.size() > 1 else &"small"}


# 鐵砧的選項：自己接著的袋子每個能改的方式（加大一格要還接得下、倍率有上限、換成同一邊能接的別種），抽 n 個不同的
func _anvil_options(p: Player, n: int) -> Array[StringName]:
	var cands: Array[StringName] = []
	for b in p.loadout.bags:
		var grown: Dictionary = b.duplicate()
		grown.length += 1
		if p.loadout.bag_fits(grown, b.side, b.offset, b.uid):
			cands.append(StringName("%sgrow:%s" % [ANVIL_PREFIX, b.uid]))
		if b.mul + BagDefs.ANVIL.mul_step <= BagDefs.ANVIL.max_mul + 0.001:
			cands.append(StringName("%smul:%s" % [ANVIL_PREFIX, b.uid]))
		var others: Array = BagDefs.BAGS.keys().filter(func(k: StringName) -> bool: return k != b.kind and (BagDefs.BAGS[k].sides as Array).has(b.side))
		if not others.is_empty():
			cands.append(StringName("%skind:%s:%s" % [ANVIL_PREFIX, b.uid, others[world.rng.randi_range(0, others.size() - 1)]]))
	_shuffle(cands)
	return cands.slice(0, n)


func _shuffle(list: Array[StringName]) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := world.rng.randi_range(0, i)
		var t := list[i]
		list[i] = list[j]
		list[j] = t


# 鐵砧的選項拆開：{ action: grow / mul / kind, uid, kind? }；不是鐵砧的選項回傳 {}
static func anvil_choice(choice: StringName) -> Dictionary:
	var s := String(choice)
	if not s.begins_with(ANVIL_PREFIX):
		return {}
	var parts := s.substr(ANVIL_PREFIX.length()).split(":")
	var out := {"action": StringName(parts[0]), "uid": StringName(parts[1])}
	if parts.size() > 2:
		out["kind"] = StringName(parts[2])
	return out


# 套用鐵砧的改造（選的當下袋子已經不在或接不下就不做）
func _anvil_apply(p: Player, c: Dictionary) -> void:
	var b := p.loadout.find_bag(c.uid)
	if b.is_empty():
		return
	match c.action:
		&"grow":
			b.length += 1
			if b.side != &"" and not p.loadout.bag_fits(b, b.side, b.offset, b.uid):
				b.length -= 1
				return
		&"mul":
			b.mul = minf(b.mul + BagDefs.ANVIL.mul_step, BagDefs.ANVIL.max_mul)
		&"kind":
			b.kind = c.kind
	p.loadout.refresh_items(p)
	world.emit_event("anvil:upgraded", {"relic_id": id, "player_id": p.id, "bag": String(b.uid), "action": String(c.action)})


# 介面用：選項的標題、說明、是不是詛咒（道具與技能由面板照物品資料畫，這裡處理袋子與鐵砧）；都不是回傳 {}
static func option_info(p: Player, choice: StringName) -> Dictionary:
	var bc := bag_choice(choice)
	if not bc.is_empty():
		var t: Dictionary = BagDefs.TIERS[bc.tier]
		var desc := "%s。%d × %d 格" % [BagDefs.BAGS[bc.kind].desc, t.length, t.depth]
		if t.mul != 1.0:
			desc += "，裡面的傷害 ×%s" % str(t.mul)
		if t.has("curse_desc"):
			desc += "；%s" % t.curse_desc
		return {"title": t.name + BagDefs.BAGS[bc.kind].name, "desc": desc, "cursed": t.has("curse"), "item": BagDefs.BAGS[bc.kind].item}
	var ac := anvil_choice(choice)
	if ac.is_empty():
		return {}
	var b := p.loadout.find_bag(ac.uid) if p != null else {}
	var bag_name := BagDefs.bag_name(b) if not b.is_empty() else "袋子"
	var where := "（%s）" % BagDefs.SIDES[b.side].name if not b.is_empty() and b.side != &"" else ""
	match ac.action:
		&"grow":
			return {"title": "加大：%s%s" % [bag_name, where], "desc": "長度 +1 格（%d → %d）" % [b.get("length", 0), b.get("length", 0) + 1]}
		&"mul":
			return {"title": "強化：%s%s" % [bag_name, where], "desc": "裡面的技能傷害 ×%s → ×%s" % [str(b.get("mul", 1.0)), str(minf(b.get("mul", 1.0) + BagDefs.ANVIL.mul_step, BagDefs.ANVIL.max_mul))]}
	return {"title": "改成%s：%s%s" % [BagDefs.BAGS[ac.kind].name, bag_name, where], "desc": "%s。裡面的東西留著" % BagDefs.BAGS[ac.kind].desc}


# 用掉 1 顆骰子重擲全部選項；沒有骰子、沒打開過或選過了就不動
func reroll(p: Player) -> bool:
	if taken.has(p.peer_id) or not offers.has(p.peer_id) or p.dice <= 0:
		return false
	p.dice -= 1
	_roll(p)
	world.emit_event("relic:rerolled", {"relic_id": id, "player_id": p.id, "dice": p.dice})
	return true


# 選第 index 個：鐵砧改造袋子；袋子照撿到的規則接上（接不下進倉庫）；道具照撿道具的規則放；都放不下就掉在腳邊。在場的玩家都選過就消失
func pick(p: Player, index: int) -> bool:
	var choices: Array = offers.get(p.peer_id, [])
	if taken.has(p.peer_id) or index < 0 or index >= choices.size():
		return false
	taken[p.peer_id] = true
	p.relic_id = 0
	var choice: StringName = choices[index]
	world.emit_event("relic:picked", {"relic_id": id, "player_id": p.id, "item": String(choice)})
	var at := p.pos + MathUtil.dir_from_angle(p.facing) * LootDefs.DROP_DISTANCE
	var ac := anvil_choice(choice)
	var bc := bag_choice(choice)
	if not ac.is_empty():
		_anvil_apply(p, ac)
	elif not bc.is_empty():
		if p.loadout.add_bag(p, bc.kind, bc.tier) == &"":
			world.drop_item(BagDefs.BAGS[bc.kind].item, at)
	else:
		var lv: int = p.skill_levels.get(choice, 1)
		if ItemDefs.is_skill(choice) and p.loadout.has_item(choice) and lv < SkillDefs.LEVEL.max:
			p.skill_levels[choice] = lv + 1
			world.emit_event("skill:leveled", {"player_id": p.id, "skill": String(choice), "level": lv + 1})
		elif p.loadout.add_item(p, choice) == &"":
			world.drop_item(choice, at)
	if relic_kind != &"anvil" and world.player_list.all(func(o: Player) -> bool: return taken.has(o.peer_id)):
		remove()
	return true


# 每步（權威端，Player._tick_timers）：打開的遺物不見了、選過了或走遠了就關掉
static func update_player(p: Player) -> void:
	if p.relic_id == 0:
		return
	var r := p.world.entities.get(p.relic_id) as Relic
	if r == null or r.is_removed or r.taken.has(p.peer_id) or not p.world.can_reach(p, r):
		p.relic_id = 0
