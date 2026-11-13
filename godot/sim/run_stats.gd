# 這一局每位玩家的統計（結算畫面用）：權威端每步從 World 這一步的事件記（feed），結算時整份放進 game:defeat / game:victory 送給所有人（to_wire）。
# 進關時存一份（snapshot），「同一關重來」還原（restore）：結算看到的是「前面過的關 + 這一輪」，重來不會越加越多
class_name RunStats
extends RefCounted

# dealt / by_source 每筆的欄位
enum { D_DAMAGE, D_HITS, D_PEAK }

var players := {}   # peer_id → _blank() 那種字典：只有數字、字串、陣列、字典，可以直接放進事件


# damage：造成的傷害；taken：受到的傷害；kills：擊殺；healed：回復的生命；revives：救起隊友幾次；peak：最高一擊；
# dealt：傷害來源（Combat.credit_of 的代號，左右鍵帶武器名「p|劍盾」）→ [傷害, 次數, 最高一擊]；
# by_source：打自己的種類 → [傷害, 次數]；kill_kinds：種類 → 隻數；downs：每次倒下 / 死亡是被哪一種打倒；
# stages：第幾層第幾小關（stage_key）→ 那一關造成的傷害
static func _blank() -> Dictionary:
	return {"damage": 0.0, "taken": 0.0, "kills": 0, "healed": 0.0, "revives": 0, "peak": 0.0,
		"dealt": {}, "by_source": {}, "kill_kinds": {}, "downs": [], "stages": {}}


static func stage_key(floor_num: int, stage: int) -> int:
	return floor_num * 100 + stage


func clear() -> void:
	players.clear()


func of(peer_id: int) -> Dictionary:
	if not players.has(peer_id):
		players[peer_id] = _blank()
	return players[peer_id]


func snapshot() -> Dictionary:
	return players.duplicate(true)


func restore(saved: Dictionary) -> void:
	players = saved.duplicate(true)


# 這一步的事件（在移除死掉的實體之前呼叫：僕從、剛死的怪還查得到）
func feed(world: World) -> void:
	for ev: Dictionary in world.events:
		match ev.name:
			"entity:damaged":
				_on_damaged(world, ev)
			"entity:died":
				var peer := _peer_of(world, ev.source_id)
				if peer != 0 and ev.kind != &"player":
					var s := of(peer)
					s.kills += 1
					s.kill_kinds[String(ev.kind)] = s.kill_kinds.get(String(ev.kind), 0) + 1
			"entity:healed":
				var peer := _peer_of(world, ev.target_id)
				if peer != 0:
					of(peer).healed += ev.amount


func add_revive(peer_id: int) -> void:
	of(peer_id).revives += 1


func _on_damaged(world: World, ev: Dictionary) -> void:
	var amount: float = ev.amount
	if amount <= 0.0:
		return
	# 打出去的：有 credit 的才是玩家方打敵人（誤傷隊友不算）
	if ev.has("credit"):
		var peer := _peer_of(world, ev.get("by", ev.source_id))
		if peer != 0:
			var s := of(peer)
			var credit: String = ev.credit
			if credit == "p" or credit == "s":   # 左右鍵照當時手上的武器分開記
				var weapon: Dictionary = (world.players[peer] as Player).weapon
				if weapon.has("name"):
					credit += "|" + String(weapon.name)
			var row: Array = s.dealt.get(credit, [0.0, 0, 0.0])
			row[D_DAMAGE] += amount
			if not ev.get("minor", false):
				row[D_HITS] += 1
			row[D_PEAK] = maxf(row[D_PEAK], amount)
			s.dealt[credit] = row
			s.damage += amount
			s.peak = maxf(s.peak, amount)
			var key := stage_key(world.floor_num, world.stage_num)
			s.stages[key] = s.stages.get(key, 0.0) + amount
	# 被打的
	var target := world.entities.get(ev.target_id) as Player
	if target != null and not target.is_ghost():
		var s := of(target.peer_id)
		var kind := String(ev.get("source_kind", &"?"))
		var row: Array = s.by_source.get(kind, [0.0, 0])
		row[D_DAMAGE] += amount
		row[D_HITS] += 1
		s.by_source[kind] = row
		s.taken += amount
		if ev.get("lethal", false):
			(s.downs as Array).append(kind)


# 實體 id → 那位玩家的 peer_id（僕從算召喚者的）；不是玩家方的回傳 0
static func _peer_of(world: World, entity_id: int) -> int:
	var e: Entity = world.entities.get(entity_id)
	if e is Minion:
		e = world.entities.get((e as Minion).owner_id)
	if e is Player and not (e as Player).is_ghost():
		return (e as Player).peer_id
	return 0


# 放進結算事件的整份資料：每位玩家的統計，加上畫面要的職業、武器、順序（客戶端不必再查自己的鏡像）
func to_wire(world: World) -> Dictionary:
	var info := {}
	var peers: Array = world.players.keys()
	peers.sort()
	for i in peers.size():
		var p: Player = world.players[peers[i]]
		of(peers[i])
		info[peers[i]] = {"order": i, "class": String(p.class_id), "weapon": String(p.weapon.get("name", "")), "entity": p.id}
	return {"players": players.duplicate(true), "info": info, "tries": world.stage_tries,
		"floor": world.floor_num, "stage": world.stage_num, "kills": world.stats.kills, "time": world.stats.time, "coins": world.run_coins}
