# 挖墳事件、難度、換層、Boss 獎勵、屍體與冤魂（D6）的自動檢查，由 tests/check.gd 呼叫；每個函式回傳 "" = 通過，否則是失敗原因
class_name EventChecks

const DT := 1.0 / 60.0
const EPS := 1e-3

static var _made: Array[World] = []


static func cleanup() -> void:
	for w in _made:
		w.clear()
	_made.clear()


# 地圖 A（不放怪群）；spawn = false 時事件不生怪（只測挖墳本身）
static func _world(peers: Array[int] = [World.HOST_PEER_ID], spawn := false) -> World:
	var w := World.new(&"graveyard_a")
	w.spawn_packs = false
	w.reset(12345, peers)
	w.spawner.finished = not spawn
	_made.append(w)
	return w


static func _cmd(buttons := 0, move := Vector2.ZERO) -> InputCmd:
	var c := InputCmd.new()
	c.buttons = buttons
	c.move = move
	c.aim = Vector2(0, 5)
	return c


# 所有人同一個輸入跑 n 步（keep_hp：每步補滿血）
static func _step(w: World, n: int, cmds: Dictionary = {}, keep_hp := true) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in n:
		var c := {}
		for peer: int in w.players:
			c[peer] = cmds.get(peer, _cmd())
		w.step(c, DT)
		events.append_array(w.events)
		if keep_hp:
			for p in w.player_list:
				if not p.is_dead and not p.is_downed:
					p.hp = p.max_hp
	return events


static func _named(events: Array[Dictionary], name: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.name == name)


static func _p(w: World, peer: int = World.HOST_PEER_ID) -> Player:
	return w.players[peer]


# ───────── 挖墳 ─────────

static func check_dig() -> String:
	var w := _world()
	var p := _p(w)
	p.pos = w.event.point + Vector2(1.5, 0.0)
	var dig := {World.HOST_PEER_ID: _cmd(InputCmd.BTN_INTERACT)}
	var ev := _step(w, 1, dig)
	if w.event.state != DigEvent.ACTIVE or _named(ev, "event:started").is_empty() or not p.is_digging():
		return "按住 F 第一步應開始事件並進入挖墳（狀態 %s、動作 %s）" % [w.event.state, p.action.current_name]
	# 挖墳中不能移動、不能跳
	var at := p.pos
	_step(w, 30, {World.HOST_PEER_ID: _cmd(InputCmd.BTN_INTERACT | InputCmd.BTN_JUMP, Vector2(1, 0))})
	if p.pos.distance_to(at) > EPS or p.height > EPS:
		return "挖墳中移動了 %.3f、高度 %.2f" % [p.pos.distance_to(at), p.height]
	# 30 秒 = 50%
	_step(w, 60 * 30 - 31, dig)
	if absf(w.event.progress - 0.5) > 0.01:
		return "挖 30 秒進度 %.3f，預期 0.5" % w.event.progress
	# 被打不中斷、不會被擊退出挖墳範圍
	var hit_at := p.pos
	p.take_damage(10.0, Vector2(1, 0), 20.0, 0)
	_step(w, 20, dig)
	if not p.is_digging() or p.pos.distance_to(hit_at) > 0.05:
		return "挖墳中被打就中斷了或被擊退（動作 %s、移動 %.2f）" % [p.action.current_name, p.pos.distance_to(hit_at)]
	# 一圈骷髏擠過來也推不走（3 秒）
	for i in 8:
		var a := TAU * i / 8.0
		w.spawner.spawn_at(w, &"grunt", p.pos + Vector2(sin(a), cos(a)) * 1.2)
	_step(w, 180, dig)
	var crowd_ok := p.is_digging() and p.pos.distance_to(hit_at) < 0.1
	for e in w.enemies:
		e.remove()
	if not crowd_ok:
		return "被骷髏圍住時被擠走 %.2f 或中斷挖墳" % p.pos.distance_to(hit_at)	# 放手 10 秒掉 10%
	var before := w.event.progress
	_step(w, 600)
	if p.is_digging() or absf(before - w.event.progress - 0.1) > 0.005:
		return "放手 10 秒進度 %.3f → %.3f，預期少 0.1" % [before, w.event.progress]
	# 兩個人一起挖速度相加
	var w2 := _world([1, 2])
	_p(w2, 1).pos = w2.event.point + Vector2(1.5, 0.0)
	_p(w2, 2).pos = w2.event.point + Vector2(-1.5, 0.0)
	_step(w2, 600, {1: _cmd(InputCmd.BTN_INTERACT), 2: _cmd(InputCmd.BTN_INTERACT)})
	if absf(w2.event.progress - 1.0 / 3.0) > 0.01:
		return "兩人一起挖 10 秒進度 %.3f，預期 0.333" % w2.event.progress
	# 挖完：出口打開，不能再挖
	var w3 := _world()
	_p(w3).pos = w3.event.point + Vector2(1.5, 0.0)
	var ev3 := _step(w3, 60 * 60 + 2, {World.HOST_PEER_ID: _cmd(InputCmd.BTN_INTERACT)})
	if w3.event.state != DigEvent.OPEN or _named(ev3, "event:exit_open").size() != 1 or _p(w3).is_digging():
		return "挖滿 60 秒應打開出口並停止挖墳（狀態 %s）" % w3.event.state
	# 太遠挖不到
	var w4 := _world()
	_p(w4).pos = w4.event.point + Vector2(EventDefs.DIG.range + 0.3, 0.0)
	_step(w4, 10, {World.HOST_PEER_ID: _cmd(InputCmd.BTN_INTERACT)})
	if w4.event.state != DigEvent.IDLE:
		return "離挖墳點 %.1f 也挖得到" % (EventDefs.DIG.range + 0.3)
	return ""


# ───────── 難度與生怪 ─────────

static func check_difficulty() -> String:
	if absf(EventDefs.difficulty_mul(60.0).hp - 1.3) > EPS:
		return "難度 60 怪物生命 ×%.2f，預期 ×1.3" % EventDefs.difficulty_mul(60.0).hp
	for c: Array in [[0.0, 3.0], [100.0, 2.0], [300.0, 0.8]]:
		if absf(EventDefs.spawn_interval(c[0]) - c[1]) > EPS:
			return "難度 %d 生怪間隔 %.2f，預期 %.2f" % [c[0], EventDefs.spawn_interval(c[0]), c[1]]
	for c: Array in [[0.0, 1, 2], [100.0, 1, 7], [100.0, 2, 10]]:
		if EventDefs.group_size(c[0], c[1]) != c[2]:
			return "難度 %d、%d 人每批 %d 隻，預期 %d" % [c[0], c[1], EventDefs.group_size(c[0], c[1]), c[2]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for c: Array in [[0.0, 0.05, 0.0], [200.0, 0.45, 0.16]]:
		var m := 0
		var r := 0
		for i in 20000:
			var x := EventDefs.roll_rarity(c[0], rng)
			m += 1 if x == MonsterRarityDefs.MAGIC else 0
			r += 1 if x == MonsterRarityDefs.RARE else 0
		if absf(m / 20000.0 - c[1]) > 0.015 or absf(r / 20000.0 - c[2]) > 0.015:
			return "難度 %d：魔法 %.1f%%、稀有 %.1f%%，預期 %.0f%% / %.0f%%" % [c[0], m / 200.0, r / 200.0, c[1] * 100, c[2] * 100]
	# 事件中：難度每秒 +1；Boss 在挖墳點旁邊出現；3 秒後第一批 2 隻（離玩家 8~18）；60 秒後冒出來的骷髏生命 ×1.3
	var w := _world([World.HOST_PEER_ID], true)
	var p := _p(w)
	p.pos = w.event.point + Vector2(1.5, 0.0)
	_step(w, 1, {World.HOST_PEER_ID: _cmd(InputCmd.BTN_INTERACT)})
	var boss: Enemy = w.entities.get(w.boss_id)
	if boss == null or boss.pos.distance_to(w.event.point) > EventDefs.DIG.boss_distance + 1.5:
		return "事件開始時 Boss 應出現在挖墳點旁邊"
	var spawned := func() -> Array:
		return w.enemies.filter(func(e: Entity) -> bool: return e is Enemy and (e as Enemy).wave_member)
	_step(w, roundi(3.0 / DT) - 3)
	if not spawned.call().is_empty():
		return "3 秒前就冒怪了"
	_step(w, 4)
	if spawned.call().size() != 2:
		return "3 秒後應冒 2 隻，實際 %d" % spawned.call().size()
	w.event.time = 60.0
	var g := w.spawner.spawn_at(w, &"grunt", w.event.point + Vector2(0, 6))
	if absf(w.difficulty() - 60.0) > 0.01 or absf(g.max_hp - roundf(36.0 * 1.3)) > EPS:   # 最大生命取整：46.8 → 47
		return "難度 %.1f 時骷髏生命 %.1f，預期 60 / 47" % [w.difficulty(), g.max_hp]
	# 怪群不擋事件生怪：放滿怪群（休眠）也照樣冒
	var w2 := World.new(&"graveyard_a")
	_made.append(w2)
	w2.reset(12345)
	var before := w2.enemies.size()
	w2.event._start(w2)
	_step(w2, roundi(3.0 / DT) + 2)
	if before < 50 or w2.enemies.size() < before + 3:
		return "有 %d 隻怪群時事件沒有冒怪（%d → %d）" % [before, before, w2.enemies.size()]
	return ""


# ───────── 出口與換層 ─────────

static func _open(w: World) -> void:
	w.event._start(w)
	w.event.state = DigEvent.OPEN
	w.event.progress = 1.0


static func check_next_floor() -> String:
	# 單人：走進出口就換層
	var w := _world()
	var p := _p(w)
	w.gold = 40
	p.add_item(&"whetstone")
	_open(w)
	p.pos = w.event.point + Vector2(EventDefs.DIG.exit_radius + 0.5, 0.0)
	_step(w, 5)
	if p.descended or w.floor_num != 1:
		return "還沒走進出口就下去了"
	w.drop_item(&"worn_boots", w.event.point + Vector2(5, 5))
	(w.chests[0] as Chest).opened = true
	p.pos = w.event.point
	var ev := _step(w, 1)
	if w.floor_num != 2 or absf(w.base_difficulty - 10.0) > EPS or _named(ev, "floor:started").is_empty():
		return "走進出口後應到第 2 層、基礎難度 10（實際第 %d 層、%.1f）" % [w.floor_num, w.base_difficulty]
	if p.pos.distance_to(w.spawn_point) > EPS or p.descended:
		return "新的一層應回到出生點"
	if w.gold != 40 or p.inventory.entries.size() != 1:
		return "換層後金幣 %d、背包 %d 件，應保留 40 / 1" % [w.gold, p.inventory.entries.size()]
	if not w.pickups.is_empty() or w.event.state != DigEvent.IDLE or w.chests.size() != 5 or (w.chests[0] as Chest).opened:
		return "換層後地上的東西要清掉、寶箱重放、事件歸零（地上 %d、事件 %s）" % [w.pickups.size(), w.event.state]
	if not w.enemies.is_empty():
		return "換層後還有 %d 隻怪" % w.enemies.size()
	# 第 2 層的怪群用基礎難度 10：生命 ×1.05
	var w5 := World.new(&"graveyard_a")
	_made.append(w5)
	w5.reset(7)
	w5.next_floor()
	var normal: Enemy = null
	for e in w5.enemies:
		if (e as Enemy).rarity == MonsterRarityDefs.NORMAL and e.kind == &"grunt":
			normal = e
			break
	if normal == null or absf(normal.max_hp - roundf(36.0 * 1.05)) > EPS:   # 37.8 取整 38
		return "第 2 層普通骷髏生命 %.2f，預期 38" % (normal.max_hp if normal else 0.0)

	# 兩人：先到的消失（不能被打、不被追），等另一人；有人倒地就不換層
	var w2 := _world([1, 2])
	_open(w2)
	var a := _p(w2, 1)
	var b := _p(w2, 2)
	a.pos = w2.event.point
	b.pos = w2.event.point + Vector2(6, 0)
	_step(w2, 2)
	if not a.descended or a.is_targetable() or a.can_be_hit() or w2.floor_num != 1:
		return "第一人進出口後應消失、不能被打，並等另一人"
	b.die()   # 多人：先倒地
	b.pos = w2.event.point
	_step(w2, 5, {}, false)
	if not b.is_downed or w2.floor_num != 1:
		return "有人倒地時不應換層"
	b.revive()
	_step(w2, 1)
	if w2.floor_num != 2 or a.descended or b.descended:
		return "兩人都進出口後應換層（第 %d 層）" % w2.floor_num
	return ""


# ───────── Boss 獎勵 ─────────

static func check_boss_reward() -> String:
	var w := _world([World.HOST_PEER_ID], true)
	w.event._start(w)
	var boss: Enemy = w.entities.get(w.boss_id)
	var gold := w.gold
	boss.take_damage(1e6, Vector2(1, 0), 0.0, 0)
	var ev := _step(w, 3)
	var weapons := 0
	var items := 0
	for pk in w.pickups:
		if (pk as ItemPickup).is_weapon():
			weapons += 1
		elif ItemDefs.ITEMS[(pk as ItemPickup).item_id].kind == &"item":
			items += 1
	if w.is_over or not _named(ev, "game:victory").is_empty():
		return "挖墳地圖打倒 Boss 不該通關"
	if weapons != 1 or items != 1 or w.gold != gold + 50:
		return "Boss 應掉 1 把武器、1 個道具、50 金幣（實際 %d / %d / %d）" % [weapons, items, w.gold - gold]
	return ""


# ───────── 屍體與冤魂 ─────────

static func check_corpse_ghost() -> String:
	var w := _world([1, 2])
	var a := _p(w, 1)
	var b := _p(w, 2)
	b.pos = a.pos + Vector2(3, 0)
	b.die()
	b.die()   # 倒地後再死一次 = 真的死亡
	_step(w, 1, {}, false)
	if not b.is_dead:
		return "第二次 die 後應死亡"
	var corpse: ItemPickup = null
	for pk in w.pickups:
		if (pk as ItemPickup).corpse_of == 2:
			corpse = pk
	if corpse == null:
		return "多人時死亡應留下屍體"
	# 撿起：占 6 格、沒有效果
	a.pos = corpse.pos + Vector2(0.6, 0)
	_step(w, 1, {1: _cmd(InputCmd.BTN_INTERACT)})
	var entry := a.inventory.find(Player.corpse_uid(2))
	if entry.is_empty() or Inventory.cells_of(entry.id, entry.rot).size() != 6 or not a.items.is_empty():
		return "撿起屍體應放進背包占 6 格、不算生效道具"
	# 換層：出現冤魂（離出生點 10~14）
	_open(w)
	a.pos = w.event.point
	_step(w, 1)
	var ghost: Enemy = null
	for e in w.enemies:
		if (e as Enemy).ghost_of == 2:
			ghost = e
	if w.floor_num != 2 or ghost == null or ghost.kind != &"ghost":
		return "背著屍體換層後應出現冤魂"
	var d := ghost.pos.distance_to(w.spawn_point)
	if d < EventDefs.GHOST.distance[0] - 1.0 or d > EventDefs.GHOST.distance[1] + 1.0:
		return "冤魂離出生點 %.1f，預期 10~14" % d
	# 打倒冤魂：在那裡復活 30% 血、屍體從背包消失
	var at := ghost.pos
	ghost.take_damage(1e6, Vector2(1, 0), 0.0, a.id)
	_step(w, 1, {}, false)
	if b.is_dead or absf(b.hp - roundf(b.max_hp * 0.3)) > EPS or b.pos.distance_to(at) > 0.5:
		return "打倒冤魂後應在冤魂位置復活、30%% 血（死亡 %s、血 %.0f）" % [b.is_dead, b.hp]
	if not a.inventory.find(Player.corpse_uid(2)).is_empty():
		return "復活後屍體應從背包消失"
	# 沒人帶屍體：下一層沒有冤魂
	var w2 := _world([1, 2])
	_p(w2, 2).die()
	_p(w2, 2).die()
	_open(w2)
	_p(w2, 1).pos = w2.event.point
	_step(w2, 1)
	for e in w2.enemies:
		if (e as Enemy).ghost_of != 0:
			return "沒人帶屍體也出現冤魂"
	return ""


# 連線：層數、事件狀態、進度、走進出口、屍體的主人傳到客戶端
static func check_net_event() -> String:
	var w := _world([1, 2])
	_open(w)
	w.event.progress = 1.0
	w.event.time = 12.5
	w.floor_num = 3
	w.base_difficulty = 20.0
	_p(w, 1).descended = true
	var pk := w.drop_corpse(2, Vector2(3, 3))
	var snap: Array = bytes_to_var(var_to_bytes(NetCodec.make_snapshot(w, NetCodec.encode_entities(w), 0)))
	NetCodec.decode_snapshot(snap)
	var cw := World.new(&"graveyard_a")
	cw.is_authority = false
	_made.append(cw)
	NetCodec.apply_world(cw, snap)
	for a: Array in snap[NetCodec.S_ENTITIES]:
		NetCodec.create_entity(cw, a)
	if cw.floor_num != 3 or cw.event.state != DigEvent.OPEN or absf(cw.difficulty() - 32.5) > EPS:
		return "客戶端層數 %d、事件 %s、難度 %.1f，預期 3 / open / 32.5" % [cw.floor_num, cw.event.state, cw.difficulty()]
	var mp: Player = cw.players.get(1)
	var mc: ItemPickup = cw.entities.get(pk.id)
	if mp == null or not mp.descended or mc == null or mc.corpse_of != 2:
		return "客戶端的「已進出口」或屍體主人沒同步"
	if cw.event.point.distance_to(w.event.point) > EPS:
		return "客戶端的挖墳點不同"
	return ""
