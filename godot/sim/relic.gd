# 遺物（Build 改版第 6 步）：祭壇 / 石棺開出、Boss 掉的獎勵，放在地上；每個玩家按 F 打開自己的 N 選 1（N = 選項數屬性，基本 3）
# 每個選項的稀有度照 tier（祭壇 / 石棺）的機率各自擲、看那位玩家的尋寶；3 個是不同的道具。選項擲過就固定，關掉再開還是同一組
# 骰子（Player.dice）用掉 1 顆把全部選項重擲。每人只能選一次，在場的玩家都選過才消失
# 選項存在遺物上（offers），快照照送，客戶端的面板直接讀；選、重骰、關掉走背包操作（InputCmd.OP_RELIC_*），只在權威端執行
# 技能遺物（relic_kind &"skill"，第 7 步）：選項從全部技能抽（SkillDefs.relic_pool，沒有稀有度），其中 1 個保證是手上武器能用、還沒滿級的；選到身上已經有的技能就升 1 級（Player.skill_levels）
# 鐵砧（relic_kind &"anvil"，地圖改版第 4 步）：小關起點旁的固定設施，每人用一次、用完不消失：第一步主手武器升一個稀有度、
# 從 N 條新詞條選 1（WeaponDropDefs.roll_affixes，不跟現有的重複）；第二步從這把武器的技能選 1（同技能遺物：已經有就升 1 級）。
# 主手沒有武器、已經傳說、抽不到新詞條就直接到第二步
class_name Relic
extends Entity

var relic_kind: StringName = &"item"
var tier: StringName = &"small"
var offers := {}   # peer id → 選項（道具 id 的陣列）
var taken := {}    # peer id → true：選過了
var anvil_done := {}   # 鐵砧：peer id → true 已經升級過（第二步選技能）；只在權威端


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
	var out: Array[StringName] = []
	var n := maxi(1, roundi(p.stats.value(&"relic_choices")))
	if relic_kind == &"anvil" and not anvil_done.has(p.peer_id):
		out = _anvil_affixes(p, n)
		if not out.is_empty():
			offers[p.peer_id] = out
			return
		anvil_done[p.peer_id] = true
	if relic_kind == &"anvil":
		# 第二步：主手武器的技能（每種武器 3 個）；沒有武器就從全部技能抽
		var base := Loadout.weapon_of(p.weapon_slots[Loadout.MAIN])
		var pool := SkillDefs.relic_pool().filter(func(id: StringName) -> bool: return base == &"" or SkillDefs.can_socket(id, base))
		for i in mini(n, pool.size()):
			var left := pool.filter(func(id: StringName) -> bool: return not out.has(id))
			out.append(left[world.rng.randi_range(0, left.size() - 1)])
		offers[p.peer_id] = out
		return
	if relic_kind == &"skill":
		var skills := SkillDefs.relic_pool()
		# 保證 1 個是手上武器（主手、副手）能鑲、還沒滿級的技能；都滿級了就照舊全隨機
		var own := skills.filter(func(id: StringName) -> bool: return _fits_hands(p, id) and p.skill_levels.get(id, 1) < SkillDefs.LEVEL.max)
		if not own.is_empty():
			out.append(own[world.rng.randi_range(0, own.size() - 1)])
		for i in mini(n, skills.size()) - out.size():
			var left := skills.filter(func(id: StringName) -> bool: return not out.has(id))
			out.append(left[world.rng.randi_range(0, left.size() - 1)])
		for i in range(out.size() - 1, 0, -1):   # 打亂順序，保證的那個不會固定在第一張
			var j := world.rng.randi_range(0, i)
			var t := out[i]
			out[i] = out[j]
			out[j] = t
		offers[p.peer_id] = out
		return
	for i in n:
		var rarity := LootDefs.roll_rarity(tier, world.rng, p.stats.value(&"treasure"))
		var pool := LootDefs.drop_pool(rarity).filter(func(id: StringName) -> bool: return not out.has(id))
		if pool.is_empty():
			pool = LootDefs.drop_pool(rarity)
		out.append(pool[world.rng.randi_range(0, pool.size() - 1)])
	offers[p.peer_id] = out


# 鐵砧第一步的選項：主手升一級後多出的那條詞條，抽 n 條不同的（不跟現有的重複、分支最多 1 條）；不能升級回傳空的
func _anvil_affixes(p: Player, n: int) -> Array[StringName]:
	var inst: Dictionary = p.weapon_slots[Loadout.MAIN]
	var out: Array[StringName] = []
	if inst.is_empty():
		return out
	var next := WeaponDropDefs.next_rarity(inst.rarity)
	if next == &"":
		return out
	var have: Array[StringName] = []
	have.assign(inst.affixes)
	var rolled := WeaponDropDefs.roll_affixes(have.size() + n, world.rng, inst.base, have, next)
	for id in rolled.slice(have.size()):
		out.append(id)
	return out


# 鐵砧第一步選好：主手升一個稀有度、加上這條詞條（印記詞條重擲印記格），接著擲第二步（技能）的選項
func _anvil_upgrade(p: Player, affix: StringName) -> void:
	var inst: Dictionary = p.weapon_slots[Loadout.MAIN]
	inst.rarity = WeaponDropDefs.next_rarity(inst.rarity)
	var list: Array[StringName] = []
	list.assign(inst.affixes)
	list.append(affix)
	inst.affixes = list
	if WeaponDropDefs.AFFIXES[affix].kind == &"imp":
		WeaponDropDefs.roll_imprints(inst, world.rng)
	p.apply_active_weapon()
	anvil_done[p.peer_id] = true
	world.emit_event("anvil:upgraded", {"relic_id": id, "player_id": p.id, "rarity": String(inst.rarity), "affix": String(affix)})
	_roll(p)


static func _fits_hands(p: Player, skill: StringName) -> bool:
	for where: int in [Loadout.MAIN, Loadout.OFF]:
		var w := Loadout.weapon_of(p.weapon_slots[where])
		if w != &"" and SkillDefs.can_socket(skill, w):
			return true
	return false


# 用掉 1 顆骰子重擲全部選項；沒有骰子、沒打開過或選過了就不動
func reroll(p: Player) -> bool:
	if taken.has(p.peer_id) or not offers.has(p.peer_id) or p.dice <= 0:
		return false
	p.dice -= 1
	_roll(p)
	world.emit_event("relic:rerolled", {"relic_id": id, "player_id": p.id, "dice": p.dice})
	return true


# 選第 index 個：照撿道具的規則放（自動鑲上 → 背包），都放不下就掉在腳邊；在場的玩家都選過就消失
func pick(p: Player, index: int) -> bool:
	var choices: Array = offers.get(p.peer_id, [])
	if taken.has(p.peer_id) or index < 0 or index >= choices.size():
		return false
	if relic_kind == &"anvil" and WeaponDropDefs.AFFIXES.has(choices[index]):
		_anvil_upgrade(p, choices[index])   # 第一步：面板保持開著，換成技能的選項
		return true
	taken[p.peer_id] = true
	p.relic_id = 0
	var item_id: StringName = choices[index]
	world.emit_event("relic:picked", {"relic_id": id, "player_id": p.id, "item": String(item_id)})
	var lv: int = p.skill_levels.get(item_id, 1)
	if ItemDefs.is_skill(item_id) and p.loadout.has_item(item_id) and lv < SkillDefs.LEVEL.max:
		p.skill_levels[item_id] = lv + 1
		world.emit_event("skill:leveled", {"player_id": p.id, "skill": String(item_id), "level": lv + 1})
	elif p.loadout.add_item(p, item_id) == &"":
		world.drop_item(item_id, p.pos + MathUtil.dir_from_angle(p.facing) * LootDefs.DROP_DISTANCE)
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
