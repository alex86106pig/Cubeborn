# 遺物（Build 改版第 6 步）：祭壇 / 石棺開出、Boss 掉的獎勵，放在地上；每個玩家按 F 打開自己的 N 選 1（N = 選項數屬性，基本 3）
# 每個選項的稀有度照 tier（祭壇 / 石棺）的機率各自擲、看那位玩家的尋寶；3 個是不同的道具。選項擲過就固定，關掉再開還是同一組
# 骰子（Player.dice）用掉 1 顆把全部選項重擲。每人只能選一次，在場的玩家都選過才消失
# 選項存在遺物上（offers），快照照送，客戶端的面板直接讀；選、重骰、關掉走背包操作（InputCmd.OP_RELIC_*），只在權威端執行
# 技能遺物（relic_kind &"skill"，第 7 步）：選項從全部技能抽（SkillDefs.relic_pool，沒有稀有度）；選到身上已經有的技能就升 1 級（Player.skill_levels）
class_name Relic
extends Entity

var relic_kind: StringName = &"item"
var tier: StringName = &"small"
var offers := {}   # peer id → 選項（道具 id 的陣列）
var taken := {}    # peer id → true：選過了


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
	if relic_kind == &"skill":
		var skills := SkillDefs.relic_pool()
		for i in mini(n, skills.size()):
			var left := skills.filter(func(id: StringName) -> bool: return not out.has(id))
			out.append(left[world.rng.randi_range(0, left.size() - 1)])
		offers[p.peer_id] = out
		return
	for i in n:
		var rarity := LootDefs.roll_rarity(tier, world.rng, p.stats.value(&"treasure"))
		var pool := LootDefs.drop_pool(rarity).filter(func(id: StringName) -> bool: return not out.has(id))
		if pool.is_empty():
			pool = LootDefs.drop_pool(rarity)
		out.append(pool[world.rng.randi_range(0, pool.size() - 1)])
	offers[p.peer_id] = out


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
	if world.player_list.all(func(o: Player) -> bool: return taken.has(o.peer_id)):
		remove()
	return true


# 每步（權威端，Player._tick_timers）：打開的遺物不見了、選過了或走遠了就關掉
static func update_player(p: Player) -> void:
	if p.relic_id == 0:
		return
	var r := p.world.entities.get(p.relic_id) as Relic
	if r == null or r.is_removed or r.taken.has(p.peer_id) or not p.world.can_reach(p, r):
		p.relic_id = 0
