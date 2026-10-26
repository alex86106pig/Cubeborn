# 多人連線（C1~C4）的自動檢查，由 tests/check.gd 呼叫；每個函式回傳 "" = 通過，否則是失敗原因
# 房主與客戶端在同一個程序裡用 _Link 接起來（可設延遲步數與掉包），資料經過 var_to_bytes 來回模擬網路傳送
class_name NetChecks

const DT := 1.0 / 60.0

static var _made: Array[World] = []   # 建立過的 World：檢查中途失敗也能在最後 cleanup() 切斷循環參照


static func cleanup() -> void:
	for w in _made:
		w.clear()
	_made.clear()


# 假的網路：房主 World + NetHost ⇄ NetClient，單程延遲 latency 步、unreliable 掉包比例 loss（reliable 不掉）
class _Link:
	var host_world := World.new(&"test_arena")
	var host: NetHost
	var client: NetClient
	var latency := 0
	var loss := 0.0
	var rng := RandomNumberGenerator.new()
	var t := 0
	var host_events: Array[Dictionary] = []
	var client_events: Array[Dictionary] = []
	var host_states: Dictionary = {}   # 房主 tick -> { kills, wave, hp: { id: hp } }（record_states 時才記）
	var record_states := false
	var _to_host: Array = []     # [送達步, 輸入陣列]
	var _to_client: Array = []   # [送達步, &"snap" | &"events", 資料]

	func _init(seed_value: int, peers: Array[int], p_latency: int, p_loss: float, spawn: bool) -> void:
		latency = p_latency
		loss = p_loss
		rng.seed = seed_value
		host_world.reset(seed_value, peers)
		host_world.spawner.finished = not spawn
		host = NetHost.new(host_world)
		client = NetClient.new(peers[1])
		client.world.load_map(&"test_arena")   # 房主與客戶端要同一張地圖
		NetChecks._made.append_array([host_world, client.world])
		host_events.append_array(host_world.events)   # reset 的 game:restart
		_send_events()

	func step(host_cmd: InputCmd, client_cmd: InputCmd) -> void:
		t += 1
		client_events.append_array(client.step(client_cmd, DT))
		if not _lost():
			_to_host.append([t + latency, _wire(client.outgoing_inputs())])
		while not _to_host.is_empty() and _to_host[0][0] <= t:
			host.receive_inputs(client.peer_id, _to_host.pop_front()[1])
		var cmds := host.take_cmds()
		cmds[World.HOST_PEER_ID] = host_cmd
		host_world.step(cmds, DT)
		host_events.append_array(host_world.events)
		_send_events()
		if host_world.tick % Config.NET.snapshot_interval == 0 and not _lost():
			_to_client.append([t + latency, &"snap", _wire(host.snapshots()[client.peer_id])])
		if record_states:
			# v0.35.0 起快照只帶客戶端玩家附近的實體：比對範圍同房主送出的範圍
			var hp := {}
			var viewer: Player = host_world.players.get(client.peer_id)
			for e: Entity in host_world.enemies:
				if host.in_interest(e, viewer):
					hp[e.id] = e.hp
			host_states[host_world.tick] = {"kills": host_world.stats.kills, "wave": host_world.stats.wave, "hp": hp}
		while not _to_client.is_empty() and _to_client[0][0] <= t:
			var m: Array = _to_client.pop_front()
			if m[1] == &"snap":
				client.receive_snapshot(m[2])
			else:
				client.receive_events(m[2][0], m[2][1], m[2][2])

	func _send_events() -> void:
		if not host_world.events.is_empty():
			_to_client.append([t + latency, &"events", _wire([host_world.run_id, host_world.tick, host_world.events])])

	func _lost() -> bool:
		return loss > 0.0 and rng.randf() < loss

	static func _wire(v: Variant) -> Variant:
		return bytes_to_var(var_to_bytes(v))

	func clear() -> void:
		host_world.clear()
		client.world.clear()


static func _cmd(move: Vector2, buttons: int = 0, aim: Vector2 = Vector2(0, 5)) -> InputCmd:
	var c := InputCmd.new()
	c.move = move
	c.aim = aim
	c.buttons = buttons
	return c


static func _world(peers: Array[int]) -> World:
	var w := World.new(&"test_arena")
	w.reset(7, peers)
	w.spawner.finished = true
	_made.append(w)
	return w


static func _named(events: Array[Dictionary], name: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.name == name)


# ───────── C2：誤傷、人數血量 ─────────

static func check_friendly_fire() -> String:
	var w := _world([1, 2])
	var p1: Player = w.players[1]
	var p2: Player = w.players[2]
	p1.pos = Vector2(0, 0)
	p2.pos = Vector2(0, 1.2)
	var events: Array[Dictionary] = []
	for i in 20:
		w.step({1: _cmd(Vector2.ZERO, InputCmd.BTN_ATTACK, Vector2(0, 5)), 2: _cmd(Vector2.ZERO)}, DT)
		events.append_array(w.events)
	var hits := _named(events, "entity:damaged")
	var err := ""
	if hits.is_empty() or hits[0].target_id != p2.id or hits[0].amount != 12:
		err = "P1 揮劍應打中前方的 P2 造成 12 傷害，實際 %s" % [hits]
	elif hits.any(func(e: Dictionary) -> bool: return e.target_id == p1.id):
		err = "出招者不應打到自己"
	# 法杖魔彈：不會打到發射者，會打到前方的隊友
	if err == "":
		var w2 := _world([1, 2])
		var a: Player = w2.players[1]
		var b: Player = w2.players[2]
		a.equip_weapon(&"staff")
		a.pos = Vector2.ZERO
		b.pos = Vector2(0, 4)
		var ev2: Array[Dictionary] = []
		for i in 60:
			w2.step({1: _cmd(Vector2.ZERO, InputCmd.BTN_ATTACK, Vector2(0, 8)), 2: _cmd(Vector2.ZERO)}, DT)
			ev2.append_array(w2.events)
		var bolt_hits := _named(ev2, "entity:damaged")
		if bolt_hits.is_empty() or bolt_hits[0].target_id != b.id:
			err = "魔彈應打中前方的隊友"
		elif bolt_hits.any(func(e: Dictionary) -> bool: return e.target_id == a.id):
			err = "魔彈不應打到發射者"
		w2.clear()
	# 單機：玩家方的目標只有敵人（沒有其他玩家）
	if err == "":
		var w3 := _world([1])
		if not Combat.hostiles_of(w3, &"player", w3.players[1].id).is_empty():
			err = "單機時玩家方的攻擊目標不應包含自己"
		w3.clear()
	w.clear()
	return err


static func check_player_count_scaling() -> String:
	var out: Array[String] = []
	for n: int in [1, 2, 4]:
		var peers: Array[int] = []
		for i in n:
			peers.append(i + 1)
		var w := _world(peers)
		var g := w.spawner.spawn_at(w, &"grunt", Vector2(5, 5))
		var b := w.spawner.spawn_at(w, &"boss", Vector2(-5, -5))
		var mul := 1.0 + 0.5 * (n - 1)
		if absf(g.max_hp - EnemyDefs.ENEMIES[&"grunt"].max_hp * mul) > 0.01 or absf(b.max_hp - EnemyDefs.ENEMIES[&"boss"].max_hp * mul) > 0.01:
			out.append("%d 人：骷髏 %.1f、Boss %.1f，預期 ×%.1f" % [n, g.max_hp, b.max_hp, mul])
		w.clear()
	return "；".join(out)


# ───────── C4：倒下與救援 ─────────

static func check_downed() -> String:
	var w := _world([1, 2])
	var p1: Player = w.players[1]
	var p2: Player = w.players[2]
	p1.pos = Vector2(-5, 0)
	p2.pos = Vector2(5, 0)
	p2.take_damage(1000.0, Vector2(1, 0), 0.0, 0)
	if not p2.is_downed or p2.is_dead or _named(w.events, "player:downed").is_empty():
		return "多人時生命歸零應倒地假死（is_downed、發出 player:downed），不是死亡"
	if p2.can_be_hit() or p2.is_targetable():
		return "倒地的玩家不能再被打、也不是怪物的目標"
	var g := w.spawner.spawn_at(w, &"grunt", Vector2(4, 0))
	if g.nearest_player() != p1:
		return "怪物應追站著的 P1，不追倒地的 P2"
	g.remove()   # 只檢查目標選擇；留著會一路推擠倒地的 P2、砍倒 P1
	var events: Array[Dictionary] = []
	var start := p2.pos
	var steps := 0
	while not p2.is_dead and steps < 700:
		w.step({1: _cmd(Vector2.ZERO), 2: _cmd(Vector2(1, 0), InputCmd.BTN_ATTACK)}, DT)
		events.append_array(w.events)
		steps += 1
	if p2.pos.distance_to(start) > 0.01:
		return "倒地時不能移動（移動 %.3f）" % p2.pos.distance_to(start)
	if not p2.is_dead or absf(steps * DT - Config.REVIVE.down_time) > 2.0 * DT:
		return "沒人救應在 %.0f 秒後死亡，實際 %d 步（%.2f 秒）" % [Config.REVIVE.down_time, steps, steps * DT]
	if _named(events, "player:died").is_empty() or not _named(events, "game:defeat").is_empty():
		return "P2 死亡應發出 player:died；P1 還站著，不應 game:defeat"
	# P1 也倒下：沒有站著的人 → 全員死亡、game:defeat
	p1.take_damage(1000.0, Vector2(1, 0), 0.0, 0)
	w.step({}, DT)
	if not p1.is_dead or _named(w.events, "game:defeat").is_empty():
		return "最後一位站著的玩家倒下時，應直接死亡並發出 game:defeat"
	w.clear()
	# 單機：倒下就是死亡（和以前一樣），下一步發出 game:defeat
	var s := _world([1])
	var sp: Player = s.players[1]
	sp.take_damage(1000.0, Vector2(1, 0), 0.0, 0)
	if not sp.is_dead or sp.is_downed:
		return "單機生命歸零應直接死亡"
	s.step({}, DT)
	var defeat := _named(s.events, "game:defeat")
	s.step({}, DT)
	if defeat.size() != 1 or not _named(s.events, "game:defeat").is_empty():
		return "單機死亡後應發出一次 game:defeat"
	s.clear()
	return ""


static func check_revive() -> String:
	var w := _world([1, 2])
	var p1: Player = w.players[1]
	var p2: Player = w.players[2]
	p1.pos = Vector2(0, 0)
	p2.pos = Vector2(0, 1.0)
	p2.take_damage(1000.0, Vector2(1, 0), 0.0, 0)
	var rv: Dictionary = Config.REVIVE
	var hold := _cmd(Vector2(1, 0), InputCmd.BTN_INTERACT | InputCmd.BTN_ATTACK | InputCmd.BTN_JUMP)
	for i in 180:   # 按住 3 秒（同時按移動、攻擊、跳躍：救援中都不應生效）
		w.step({1: hold, 2: _cmd(Vector2.ZERO)}, DT)
	if p1.pos.distance_to(Vector2.ZERO) > 0.01 or not p1.action.is_in(&"revive") or p1.height > 0.0:
		return "按住 F 救援時不能移動、攻擊、跳躍（位置 %s、動作 %s、高度 %.2f）" % [p1.pos, p1.action.current_name, p1.height]
	if absf(p2.revive_progress - 3.0) > 0.02 or absf(p2.down_timer - rv.down_time) > 0.02:
		return "救援 3 秒：進度應 3.0、倒數暫停在 %.1f，實際 %.3f / %.3f" % [rv.down_time, p2.revive_progress, p2.down_timer]
	for i in 60:    # 放開 1 秒：進度每秒 −decay_rate、倒數照走
		w.step({1: _cmd(Vector2.ZERO), 2: _cmd(Vector2.ZERO)}, DT)
	var left: float = 3.0 - rv.decay_rate
	if absf(p2.revive_progress - left) > 0.02 or absf(p2.down_timer - (rv.down_time - 1.0)) > 0.02:
		return "放開 1 秒：進度應 %.1f、倒數 %.1f，實際 %.3f / %.3f" % [left, rv.down_time - 1.0, p2.revive_progress, p2.down_timer]
	if not p1.action.is_in(&"ready"):
		return "放開 F 應結束救援，實際 %s" % p1.action.current_name
	var events: Array[Dictionary] = []
	var steps := 0
	while p2.is_downed and steps < 400:
		w.step({1: _cmd(Vector2.ZERO, InputCmd.BTN_INTERACT), 2: _cmd(Vector2.ZERO)}, DT)
		events.append_array(w.events)
		steps += 1
	var more: float = rv.revive_time - left
	if p2.is_downed or absf(steps * DT - more) > 2.0 * DT:
		return "再按住 %.1f 秒（累積到 %.1f 秒）應救起，實際 %d 步" % [more, rv.revive_time, steps]
	var revived_hp := roundf(p2.max_hp * rv.revive_hp_ratio)
	if p2.hp != revived_hp or _named(events, "player:revived").is_empty() or not p2.locomotion.is_in(&"idle"):
		return "救起後血量應為最大生命 %.0f%%（%.0f），實際 %.1f；應發出 player:revived 並站起來" % [rv.revive_hp_ratio * 100.0, revived_hp, p2.hp]
	# 超出範圍：救援中斷
	var w2 := _world([1, 2])
	var a: Player = w2.players[1]
	var b: Player = w2.players[2]
	b.pos = Vector2(0, Config.REVIVE.range + 0.5)
	b.take_damage(1000.0, Vector2(1, 0), 0.0, 0)
	for i in 30:
		w2.step({1: _cmd(Vector2.ZERO, InputCmd.BTN_INTERACT), 2: _cmd(Vector2.ZERO)}, DT)
	var far_err := "" if a.action.is_in(&"ready") and b.revive_progress == 0.0 else "倒地者在範圍外時不應開始救援"
	# 救援中照樣跟著滑鼠轉向（v0.38.0 使用者要求）：倒地隊友在 +Z，瞄準正東 → facing = π/2
	var w3 := _world([1, 2])
	var r: Player = w3.players[1]
	var d: Player = w3.players[2]
	d.pos = Vector2(0, 1.0)
	d.take_damage(1000.0, Vector2(1, 0), 0.0, 0)
	var look := _cmd(Vector2.ZERO, InputCmd.BTN_INTERACT, Vector2(10, 0))
	for i in 20:
		w3.step({1: look, 2: _cmd(Vector2.ZERO)}, DT)
	if far_err == "" and (not r.action.is_in(&"revive") or absf(angle_difference(r.facing, PI / 2.0)) > 0.01):
		far_err = "救援中應跟著滑鼠轉向：動作 %s、朝向 %.2f（預期 %.2f）" % [r.action.current_name, r.facing, PI / 2.0]
	w.clear()
	w2.clear()
	w3.clear()
	return far_err


# ───────── C2 / C3：快照、同步、預測 ─────────

# v0.38.0：客戶端打中的回饋不等網路——單程延遲 6 步（100 ms）時，火花 / 音效 / 閃白（hit:predicted）和單機一樣在出招當下；
# 房主的同一下到了標 predicted（只顯示傷害數字）；側移的怪：客戶端看到打中，房主用延遲補償也判定打中
static func check_hit_prediction(feel: Array[String]) -> String:
	var setup := func(lat: int) -> Array:
		var link := _Link.new(7, [1, 2], lat, 0.0, false)
		var hw := link.host_world
		hw.players[1].pos = Vector2(-10, -10)
		hw.players[2].pos = Vector2.ZERO
		var g: Enemy = hw.spawner.spawn_at(hw, &"grunt", Vector2(0, 1.6))
		hw.cooldowns.start(g.cd("swing"), 999.0)
		return [link, g]
	var idle := _cmd(Vector2.ZERO)
	var press := _cmd(Vector2.ZERO, InputCmd.BTN_ATTACK)
	# 單機出招到打中幾步（基準）
	var a: Dictionary = WeaponDefs.WEAPONS[&"swordShield"].attack
	var solo := ceili(a.windup / DT) + 1
	var s: Array = setup.call(6)
	var link: _Link = s[0]
	var g: Enemy = s[1]
	for i in 90:
		g.pos = Vector2(0, 1.6)
		link.step(idle, idle)
	link.client_events.clear()
	var fx := -1
	var number: Dictionary = {}
	for i in 60:
		g.pos = Vector2(0, 1.6)
		link.step(idle, press if i == 0 else idle)
		for e in link.client_events:
			if e.get("target_id", 0) == g.id and e.name == "hit:predicted" and fx < 0:
				fx = i + 1
			if e.get("target_id", 0) == g.id and e.name == "entity:damaged" and number.is_empty():
				number = e
	var preds := link.client_events.filter(func(e: Dictionary) -> bool: return e.name == "hit:predicted").size()
	link.clear()
	if fx < 0 or fx > solo + 1 or preds != 1:
		return "延遲 100 ms 時打中回饋應在第 %d 步左右出現一次（同單機），實際第 %d 步、%d 次" % [solo, fx, preds]
	if number.is_empty() or not number.get("predicted", false):
		return "房主的同一下應標 predicted（不再播火花與音效）：%s" % [number]
	# 側移 3 單位/秒的怪：在不同時機出手，客戶端看到打中的每一次，房主都要判定打中
	var seen := 0
	var agreed := 0
	for k in 12:
		var m: Array = setup.call(6)
		var ml: _Link = m[0]
		var mg: Enemy = m[1]
		var x := -6.0
		var host_hit := false
		var at := 120 + k * 9
		for i in 280:
			x += 3.0 * DT
			mg.pos = Vector2(x, 1.9)
			mg.velocity = Vector2(3.0, 0)
			ml.step(idle, press if i == at else idle)
			for e in ml.host_world.events:
				if e.name == "entity:damaged" and e.target_id == mg.id:
					host_hit = true
		if not ml.client_events.filter(func(e: Dictionary) -> bool: return e.name == "hit:predicted").is_empty():
			seen += 1
			agreed += 1 if host_hit else 0
		ml.clear()
	feel.append("v0.38.0 打中回饋：延遲 100 ms 時第 %d 步出現（單機 %d 步、修正前 %d 步）；側移的怪客戶端看到打中 %d 次、房主判定打中 %d 次" % [fx, solo, solo + 6 + 2 * 6, seen, agreed])
	if seen < 4 or agreed != seen:
		return "側移的怪：客戶端看到打中 %d 次，房主只判定 %d 次（延遲補償沒對上）" % [seen, agreed]
	return ""


# v0.45 局外金幣：房主掉在地上的金幣客戶端看得到；客戶端的角色走過去 → 房主判定撿起，兩邊的本局金幣都是 1、地上都沒了，
# 客戶端也收到 coins:gained（main.gd 靠它存檔）
static func check_net_coins() -> String:
	var link := _Link.new(43, [1, 2], 3, 0.0, false)
	var hw := link.host_world
	var hp2: Player = hw.players[2]
	hp2.pos = Vector2(0, 0)
	(hw.players[1] as Player).pos = Vector2(-8, -8)
	var coin := hw.drop_coin(Vector2(4, 0))
	for i in 20:
		link.step(_cmd(Vector2.ZERO), _cmd(Vector2.ZERO))
	var cw := link.client.world
	if cw.coins.size() != 1 or not cw.entities.has(coin.id):
		return "客戶端應看到地上 1 枚金幣，實際 %d" % cw.coins.size()
	for i in 40:
		link.step(_cmd(Vector2.ZERO), _cmd(Vector2(1, 0)))
	for i in 20:
		link.step(_cmd(Vector2.ZERO), _cmd(Vector2.ZERO))
	var got := link.client_events.filter(func(e: Dictionary) -> bool: return e.name == "coins:gained")
	if hw.run_coins != 1 or cw.run_coins != 1 or not cw.coins.is_empty() or got.size() != 1:
		return "撿起後：房主 %d、客戶端 %d 金幣（應 1 / 1）、客戶端地上 %d、客戶端收到 coins:gained %d 次（應 1）" % [
			hw.run_coins, cw.run_coins, cw.coins.size(), got.size()]
	return ""


# D3：客戶端靠近寶箱按 F → 房主開箱扣靈魂、道具掉在地上；再按 F 撿起；拖曳搬動、丟掉。兩邊的寶箱、靈魂、背包一致
static func check_net_loot() -> String:
	var link := _Link.new(41, [1, 2], 3, 0.0, false)
	var hw := link.host_world
	var chest := Chest.new(hw, &"small", Vector2(3, 0))
	hw.add_entity(chest)
	hw.chests.append(chest)
	hw.souls = 30
	var hp2: Player = hw.players[2]
	hp2.pos = Vector2(1.5, 0)
	var idle := func(n: int) -> void:
		for i in n:
			link.step(_cmd(Vector2.ZERO), _cmd(Vector2.ZERO))
	idle.call(20)
	link.step(_cmd(Vector2.ZERO), _cmd(Vector2.ZERO, InputCmd.BTN_INTERACT))
	idle.call(20)
	var cw := link.client.world
	var left: int = 30 - LootDefs.CHESTS[&"small"].price
	if not chest.opened or hw.souls != left or hw.pickups.size() != 1:
		return "房主：寶箱應打開、靈魂 30 → %d、地上 1 個道具：%s / %d / %d" % [left, chest.opened, hw.souls, hw.pickups.size()]
	var mirror: Chest = cw.entities.get(chest.id)
	if mirror == null or not mirror.opened or cw.souls != left or cw.pickups.size() != 1:
		return "客戶端：寶箱 %s、靈魂 %d、地上道具 %d（應為 已開 / %d / 1）" % [mirror.opened if mirror else null, cw.souls, cw.pickups.size(), left]
	link.step(_cmd(Vector2.ZERO), _cmd(Vector2.ZERO, InputCmd.BTN_INTERACT))
	idle.call(20)
	var me := link.client.local_player()
	if hp2.inventory.entries.size() != 1 or me.inventory.entries.size() != 1 or me.items.size() != 1 or not cw.pickups.is_empty():
		return "撿起後：房主背包 %d、客戶端背包 %d、客戶端生效道具 %d、客戶端地上 %d（應為 1 / 1 / 1 / 0）" % [
			hp2.inventory.entries.size(), me.inventory.entries.size(), me.items.size(), cw.pickups.size()]
	var uid: String = me.inventory.entries[0].uid
	var move := _cmd(Vector2.ZERO)
	move.inv_ops = [[InputCmd.OP_MOVE, uid, 5, 3, 1]]
	link.step(_cmd(Vector2.ZERO), move)
	idle.call(20)
	var e: Dictionary = me.inventory.entries[0]
	if e.cell != Vector2i(5, 3) or e.rot != 1 or hp2.inventory.entries[0].cell != Vector2i(5, 3):
		return "搬到 (5, 3) 轉 90°：客戶端 %s / %d、房主 %s" % [e.cell, e.rot, hp2.inventory.entries[0].cell]
	var drop := _cmd(Vector2.ZERO)
	drop.inv_ops = [[InputCmd.OP_DROP, uid]]
	link.step(_cmd(Vector2.ZERO), drop)
	idle.call(20)
	if not me.inventory.entries.is_empty() or not me.items.is_empty() or cw.pickups.size() != 1 or hw.pickups.size() != 1:
		return "丟掉後：客戶端背包 %d、生效 %d、地上 客戶端 %d / 房主 %d（應為 0 / 0 / 1 / 1）" % [
			me.inventory.entries.size(), me.items.size(), cw.pickups.size(), hw.pickups.size()]
	return ""


# D4：客戶端按 X 切到第 2 格、拖曳合成背包裡兩把白法杖；Boss 掉的武器兩邊都看得到
static func check_net_weapons() -> String:
	var link := _Link.new(43, [1, 2], 3, 0.0, false)
	var hw := link.host_world
	var hp2: Player = hw.players[2]
	var mk := func(uid: String) -> Dictionary:
		return {"uid": StringName(uid), "base": &"staff", "rarity": &"white", "affixes": [] as Array[StringName]}
	hp2.add_weapon(mk.call("x"))
	hp2.add_weapon(mk.call("m1"))
	hp2.add_weapon(mk.call("m2"))
	var idle := func(n: int) -> void:
		for i in n:
			link.step(_cmd(Vector2.ZERO), _cmd(Vector2.ZERO))
	idle.call(20)
	link.step(_cmd(Vector2.ZERO), _cmd(Vector2.ZERO, InputCmd.BTN_SWAP_WEAPON))
	idle.call(20)
	var me := link.client.local_player()
	if hp2.active_slot != 1 or me.active_slot != 1 or me.weapon_id != &"staff" or hp2.weapon_id != &"staff":
		return "按 X 後兩邊都應換到第 2 格的法杖：房主 %d %s、客戶端 %d %s" % [hp2.active_slot, hp2.weapon_id, me.active_slot, me.weapon_id]
	var merge := _cmd(Vector2.ZERO)
	merge.inv_ops = [[InputCmd.OP_MERGE, "m1", "m2"]]
	link.step(_cmd(Vector2.ZERO), merge)
	idle.call(20)
	var host_e := hp2.inventory.find(&"m2")
	var mine := me.inventory.find(&"m2")
	if host_e.is_empty() or mine.is_empty() or host_e.weapon.rarity != &"green" or mine.weapon.rarity != &"green" \
			or mine.weapon.affixes != host_e.weapon.affixes or not me.inventory.find(&"m1").is_empty():
		return "合成後兩邊背包的 m2 都應是綠色、詞條相同：房主 %s、客戶端 %s" % [host_e.get("weapon"), mine.get("weapon")]
	var before := link.client.world.pickups.size()
	hw.spawner.spawn_at(hw, &"boss", Vector2(8, 8)).die()
	idle.call(20)
	var drops := link.client.world.pickups.filter(func(e: Entity) -> bool: return (e as ItemPickup).is_weapon())
	if link.client.world.pickups.size() != before + 1 or drops.size() != 1:
		return "Boss 掉的武器客戶端應看得到：地上 %d 個、武器 %d 把" % [link.client.world.pickups.size(), drops.size()]
	return ""


static func check_codec() -> String:
	var w := _world([1, 2])
	w.spawner.spawn_at(w, &"grunt", Vector2(5, 5))
	w.spawner.spawn_at(w, &"boss", Vector2(-5, -5))
	w.players[1].equip_weapon(&"staff")
	for i in 40:
		w.step({1: _cmd(Vector2(1, 0), InputCmd.BTN_ATTACK, Vector2(0, 8))}, DT)
	var host := NetHost.new(w)
	var snap: Array = _Link._wire(host.snapshots()[2])
	var c := NetClient.new(2)
	_made.append(c.world)
	c.receive_snapshot(snap)
	c.step(_cmd(Vector2.ZERO), DT)
	var err := ""
	for id: int in w.entities:
		var e: Entity = w.entities[id]
		var m: Entity = c.world.entities.get(id)
		if m == null or m.get_script() != e.get_script():
			err = "實體 %d（%s）沒有建立成同樣的類別" % [id, e.kind]
			break
		if m.pos.distance_to(e.pos) > 1e-4 or absf(m.hp - e.hp) > 1e-4 or absf(m.max_hp - e.max_hp) > 1e-4:
			err = "實體 %d（%s）位置或血量不同：%s / %s、%.1f / %.1f、%.1f / %.1f" % [id, e.kind, m.pos, e.pos, m.hp, e.hp, m.max_hp, e.max_hp]
			break
		if (e is Player or e is Enemy) and m != c.local_player() and m.anim != e.anim:   # 自己的角色是本機預測的
			err = "實體 %d（%s）動畫資料經過壓縮後不同：%s / %s" % [id, e.kind, m.anim, e.anim]
			break
	if err == "" and c.world.entities.size() != w.entities.size():
		err = "鏡像實體數 %d，房主 %d" % [c.world.entities.size(), w.entities.size()]
	if err == "" and (c.world.players[1] as Player).weapon_id != &"staff":
		err = "其他玩家的武器沒有同步"
	# 動畫補間：狀態相同時數值欄位線性補間，不同時用前一筆
	var la := NetCodec.lerp_anim({"state": &"chase", "time": 1.0}, {"state": &"chase", "time": 2.0}, 0.25)
	var lb := NetCodec.lerp_anim({"state": &"chase", "time": 1.0}, {"state": &"hurt", "time": 0.1}, 0.5)
	if err == "" and (absf(la.time - 1.25) > 1e-6 or lb.state != &"chase" or lb.time != 1.0):
		err = "動畫補間錯誤：%s / %s" % [la, lb]
	w.clear()
	c.world.clear()
	return err


# 網頁連線的配對（v0.36.0）：桌面版沒有內建 WebRTC，這裡只驗配對訊息、房號、傳輸方式的選擇；實際連線要在瀏覽器測
static func check_web_signaling() -> String:
	var url := PeerJsSignaling.url_for("cubeborn-mp-ABCD", "tok123")
	if url != "wss://0.peerjs.com:443/peerjs?key=peerjs&id=cubeborn-mp-ABCD&token=tok123&version=1.5.4":
		return "配對伺服器網址錯誤：%s" % url
	if PeerJsSignaling.host_id("ab2c") != "cubeborn-mp-AB2C":
		return "房主 ID 應是前綴 + 大寫房號：%s" % PeerJsSignaling.host_id("ab2c")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var chars: String = Config.NET.web_room_chars
	for i in 300:
		var code := PeerJsSignaling.random_room_code(rng)
		if code.length() != 4:
			return "房號長度 %d：%s" % [code.length(), code]
		for ch in code:
			if not chars.contains(ch) or ch in ["0", "O", "1", "I"]:
				return "房號有不該出現的字：%s" % code
	# 送出的訊息：{type, dst, payload}，payload 照 PeerJS 1.5.4 的格式（公開伺服器會檢查，v0.36.1 在瀏覽器實測確認）
	var sent: Variant = JSON.parse_string(PeerJsSignaling.encode("OFFER", "cubeborn-mp-ABCD", PeerJsSignaling.offer_payload("v=0 o", "dc_abc", 12345)))
	if not sent is Dictionary or sent.type != "OFFER" or sent.dst != "cubeborn-mp-ABCD" or sent.payload.sdp.sdp != "v=0 o" or sent.payload.sdp.type != "offer" \
			or sent.payload.type != "data" or sent.payload.connectionId != "dc_abc" or sent.payload.label != "dc_abc" or sent.payload.serialization != "binary" \
			or PeerJsSignaling.peer_id_of(sent.payload) != 12345:
		return "送出的 OFFER 不是 PeerJS 格式：%s" % [sent]
	var cand: Dictionary = PeerJsSignaling.candidate_payload("0", 0, "candidate:1 1 udp 1 1.2.3.4 5 typ host", "dc_abc")
	if cand.candidate.sdpMid != "0" or cand.candidate.sdpMLineIndex != 0 or cand.connectionId != "dc_abc" or cand.type != "data":
		return "送出的 CANDIDATE 不是 PeerJS 格式：%s" % [cand]
	if not PeerJsSignaling.random_connection_id(rng).begins_with("dc_"):
		return "connectionId 應該是 dc_ 開頭"
	# 伺服器轉來的：多一個 src，數字會變成浮點數
	var got := PeerJsSignaling.decode('{"type":"ANSWER","src":"cubeborn-mp-c-1","dst":"x","payload":{"sdp":{"sdp":"v=0 a","type":"answer"},"type":"data","connectionId":"dc_abc"}}')
	if got.type != "ANSWER" or got.src != "cubeborn-mp-c-1" or PeerJsSignaling.sdp_of(got.payload) != "v=0 a":
		return "收到的配對訊息解析錯誤：%s" % [got]
	if not PeerJsSignaling.decode("not json").is_empty() or not PeerJsSignaling.decode('{"payload":1}').is_empty():
		return "格式不對的訊息應該忽略"
	# 伺服器訊息 → 訊號
	var s := PeerJsSignaling.new()
	var log: Array[String] = []
	s.opened.connect(func() -> void: log.append("opened"))
	s.id_taken.connect(func() -> void: log.append("taken"))
	s.expired.connect(func(dst: String) -> void: log.append("expired:" + dst))
	s.failed.connect(func(reason: String) -> void: log.append("failed"))
	s.message_received.connect(func(type: String, src: String, payload: Dictionary) -> void: log.append("%s:%s:%s" % [type, src, PeerJsSignaling.candidate_of(payload)[0]]))
	for text in ['{"type":"OPEN"}', '{"type":"CANDIDATE","src":"h","payload":{"candidate":{"candidate":"c","sdpMid":"0","sdpMLineIndex":0},"type":"data","connectionId":"dc_x"}}',
			'{"type":"EXPIRE","src":"cubeborn-mp-ZZZZ"}', '{"type":"HEARTBEAT"}', '{"type":"ID-TAKEN","payload":{"msg":"ID is taken"}}',
			'{"type":"ERROR","payload":{"msg":"x"}}']:
		s._handle(PeerJsSignaling.decode(text))
	var want: Array[String] = ["opened", "CANDIDATE:h:0", "expired:cubeborn-mp-ZZZZ", "taken", "failed"]
	if log != want:
		return "伺服器訊息對應的訊號 %s，預期 %s" % [log, want]
	if not NetSession.ip_supported():
		return "桌面版應該能用 IP 連線（ENet）"
	if not NetSession.room_supported():
		return "桌面版應該能用房號連線（addons/webrtc_native 沒有載入？）"
	return ""


# 桌面版 WebRTC（v0.40.0，webrtc-native）：同一程序裡兩條 WebRTCPeerConnection 直接交換 SDP / 候選位址（不經配對伺服器），
# 用和 NetSession 相同的設定建房主 / 客戶端，連上後房主送的封包客戶端收得到
static func check_desktop_webrtc(feel: Array[String]) -> String:
	var server := WebRTCMultiplayerPeer.new()
	var client := WebRTCMultiplayerPeer.new()
	var channels := [MultiplayerPeer.TRANSFER_MODE_UNRELIABLE]
	if server.create_server(channels) != OK or client.create_client(5, channels) != OK:
		return "建立 WebRTC 房主 / 客戶端失敗"
	var a := WebRTCPeerConnection.new()   # 房主那邊連到客戶端（peer 5）
	var b := WebRTCPeerConnection.new()   # 客戶端那邊連到房主（peer 1）
	for c: WebRTCPeerConnection in [a, b]:
		if c.initialize({"iceServers": []}) != OK:
			return "WebRTCPeerConnection.initialize 失敗（%s）" % c.get_class()
	# 訊號只把訊息放進信箱、迴圈裡再轉給對方：lambda 不抓連線本身，免得互相參照留到結束（WebRTC 的執行緒會讓程式關不掉）
	var mail := [[], []]   # mail[i]：要交給連線 i 的 [種類, 參數...]
	a.session_description_created.connect(func(type: String, sdp: String) -> void: mail[0].append(["local", type, sdp]); mail[1].append(["remote", type, sdp]))
	b.session_description_created.connect(func(type: String, sdp: String) -> void: mail[1].append(["local", type, sdp]); mail[0].append(["remote", type, sdp]))
	a.ice_candidate_created.connect(func(mid: String, index: int, cand: String) -> void: mail[1].append(["ice", mid, index, cand]))
	b.ice_candidate_created.connect(func(mid: String, index: int, cand: String) -> void: mail[0].append(["ice", mid, index, cand]))
	var conns: Array[WebRTCPeerConnection] = [a, b]
	server.add_peer(a, 5)
	client.add_peer(b, World.HOST_PEER_ID)
	b.create_offer()   # 和 NetSession.join_room 一樣由客戶端送 OFFER
	var got := PackedByteArray()
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 5000:
		for i in 2:
			while not mail[i].is_empty():
				var m: Array = mail[i].pop_front()
				match m[0]:
					"local": conns[i].set_local_description(m[1], m[2])
					"remote": conns[i].set_remote_description(m[1], m[2])
					"ice": conns[i].add_ice_candidate(m[1], m[2], m[3])
		server.poll()
		client.poll()
		if client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and server.has_peer(5) and server.get_peer(5).connected:
			server.set_target_peer(5)
			server.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
			server.put_packet(PackedByteArray([7, 8, 9]))
			if client.get_available_packet_count() > 0:
				got = client.get_packet()
				break
		OS.delay_msec(10)
	var ms := Time.get_ticks_msec() - start
	for c: WebRTCPeerConnection in [a, b]:
		c.close()
	server.close()
	client.close()
	if got != PackedByteArray([7, 8, 9]):
		return "5 秒內沒有連上或沒收到封包（客戶端狀態 %d）" % client.get_connection_status()
	feel.append("桌面版 WebRTC（本機兩條連線）：%d ms 連上並收到封包" % ms)
	return ""


# 快照大小（v0.35.0，網頁連線前置）：地圖 A + 怪群（約 170 隻）、4 位玩家分散；一般情境另外把 30 隻怪圍在 P2 身邊
# 每份快照（每位客戶端各一份）序列化後的位元組數要 ≤ SNAPSHOT_MAX_BYTES（WebRTC 單則訊息約 16 KB 的安全上限留 4 倍空間）
const SNAPSHOT_MAX_BYTES := 4096
const SNAPSHOT_CROWD_MAX_BYTES := 8192   # 最壞情況（身邊 120 隻）：上限的一半


static func check_snapshot_size(feel: Array[String]) -> String:
	var w := World.new(&"graveyard_a")
	_made.append(w)
	w.reset(11, [1, 2, 3, 4])
	w.spawner.finished = true
	var spots := [Vector2(0.3, 0.3), Vector2(-0.6, 0.5), Vector2(0.6, -0.6), Vector2(-0.5, -0.4)]
	for i in 4:
		var p: Player = w.players[i + 1]
		p.pos = w.nav.nearest_walkable(spots[i] * w.half_extents)
	for i in 30:
		var a := TAU * i / 30.0
		w.spawner.spawn_at(w, &"grunt" if i % 5 else &"archer", w.nav.nearest_walkable(w.players[2].pos + Vector2(sin(a), cos(a)) * (3.0 + i % 4)))
	for i in 20:
		w.step({}, DT)
	var host := NetHost.new(w)
	var snaps := host.snapshots()
	var worst := 0
	var parts := ""
	for peer: int in [2, 3, 4]:
		var bytes := var_to_bytes(snaps[peer]).size()
		worst = maxi(worst, bytes)
		parts += " P%d %d 實體 %d bytes" % [peer, _entity_count(snaps[peer]), bytes]
	# 最壞情況：挖墳事件同時最多 120 隻（EventDefs），全部圍在 P2 身邊
	for i in 90:
		var a := TAU * i / 90.0
		w.spawner.spawn_at(w, &"grunt" if i % 5 else &"archer", w.nav.nearest_walkable(w.players[2].pos + Vector2(sin(a), cos(a)) * (4.0 + i % 9)))
	for i in 5:
		w.step({}, DT)
	var crowd: Array = host.snapshots()[2]
	var crowd_bytes := var_to_bytes(crowd).size()
	feel.append("快照大小：場上 %d 個實體（敵人 %d）；一般%s；P2 被 120 隻圍住時 %d 實體 %d bytes（v0.34 每份送全部、約 28 KB）" % [
		w.entities.size(), w.enemies.size(), parts, _entity_count(crowd), crowd_bytes])
	if worst > SNAPSHOT_MAX_BYTES:
		return "最大一份快照 %d bytes，超過 %d：%s；被 120 隻圍住時 %d bytes" % [worst, SNAPSHOT_MAX_BYTES, parts, crowd_bytes]
	if crowd_bytes > SNAPSHOT_CROWD_MAX_BYTES:
		return "P2 被 120 隻圍住時快照 %d bytes，超過 %d" % [crowd_bytes, SNAPSHOT_CROWD_MAX_BYTES]
	return ""


static func _entity_count(snap: Array) -> int:
	return (NetCodec.decode_snapshot(snap.duplicate(true))[NetCodec.S_ENTITIES] as Array).size()


# C2：同一串輸入下，客戶端畫面套用的每一筆快照都和房主當時的狀態一致；事件順序也一樣
static func check_sync(feel: Array[String]) -> String:
	var link := _Link.new(31, [1, 2], 3, 0.0, true)
	link.record_states = true
	var compared := 0
	var err := ""
	for i in 1800:
		# 兩人都走向最近的怪、對著牠揮劍（房主看自己的 World，客戶端看鏡像）
		link.step(_chase_cmd(link.host_world, 1), _chase_cmd(link.client.world, link.client.peer_id))
		var tick := link.client.applied_tick
		if tick < 0 or not link.host_states.has(tick):
			continue
		var s: Dictionary = link.host_states[tick]
		var cw := link.client.world
		if cw.stats.kills != s.kills or cw.stats.wave != s.wave:
			err = "tick %d：客戶端擊殺 / 波次 %d / %d，房主 %d / %d" % [tick, cw.stats.kills, cw.stats.wave, s.kills, s.wave]
			break
		for id: int in s.hp:
			var e: Entity = cw.entities.get(id)
			if e == null or absf(e.hp - s.hp[id]) > 1e-3:
				err = "tick %d：敵人 %d 血量 客戶端 %s，房主 %.1f" % [tick, id, e.hp if e else "（沒有）", s.hp[id]]
				break
		if err != "":
			break
		compared += 1
	if err == "" and link.host_world.stats.kills < 5:
		err = "這段時間應打倒一些怪（實際 %d），檢查才有意義" % link.host_world.stats.kills
	if err == "":
		# 事件：客戶端收到的（去掉自己預測的）應是房主事件（去掉客戶端玩家的動作）的前段，順序相同
		var peer := link.client.peer_id
		var host_names := link.host_events.filter(func(e: Dictionary) -> bool: return e.get("actor", 0) != peer).map(func(e: Dictionary) -> String: return e.name)
		var client_names := link.client_events.filter(func(e: Dictionary) -> bool: return e.get("actor", 0) != peer).map(func(e: Dictionary) -> String: return e.name)
		if client_names.size() < host_names.size() * 0.9 or host_names.slice(0, client_names.size()) != client_names:
			err = "事件順序不同或缺少：客戶端 %d 筆、房主 %d 筆" % [client_names.size(), host_names.size()]
		var snap_bytes := var_to_bytes(link.host.snapshots()[peer]).size()
		feel.append("C2 同步：30 秒 2 人對打、延遲 3 步，比對 %d 筆快照的擊殺 / 波次 / 敵人血量全部一致；事件 %d 筆順序一致（房主擊殺 %d）；最後一筆快照 %d 個實體 %d bytes" % [compared, client_names.size(), link.host_world.stats.kills, link.host_world.entities.size(), snap_bytes])
	link.clear()
	return err


# 遊玩紀錄的連線數據：單程延遲 latency 步時，客戶端的回應時間（輸入 → 房主快照確認）在「來回 + 快照間隔」內；
# 快照最長間隔約 snapshot_interval 步；房主收到隊友輸入的最長間隔約 1 步
static func check_net_stats(feel: Array[String]) -> String:
	var latency := 6
	var link := _Link.new(41, [1, 2], latency, 0.0, false)
	for i in 300:
		link.step(_cmd(Vector2.ZERO), _cmd(Vector2(1, 0)))
	var step_ms := Config.FIXED_DT * 1000.0
	var rtt := link.client.rtt_ms.duplicate()
	rtt.sort()
	var lo := roundi(2 * latency * step_ms)
	var hi := roundi((2 * latency + Config.NET.snapshot_interval + 1) * step_ms)
	var gap := link.client.snapshot_gap_max_ms
	var host_gap: int = link.host.input_gap_max_ms.get(link.client.peer_id, -1)
	var err := ""
	if rtt.size() < 50:
		err = "回應時間只量到 %d 次" % rtt.size()
	elif rtt[0] < lo or rtt[-1] > hi:
		err = "單程延遲 %d 步：回應時間 %d ~ %d ms，應在 %d ~ %d ms" % [latency, rtt[0], rtt[-1], lo, hi]
	elif gap <= 0 or gap > roundi(Config.NET.snapshot_interval * step_ms) + 1:
		err = "快照最長間隔 %d ms，應約 %d ms" % [gap, roundi(Config.NET.snapshot_interval * step_ms)]
	elif host_gap <= 0 or host_gap > roundi(step_ms) + 1:
		err = "房主收到隊友輸入的最長間隔 %d ms，應約 %d ms" % [host_gap, roundi(step_ms)]
	if err == "":
		feel.append("遊玩紀錄的連線數據：單程 %d ms 時回應 %d ~ %d ms（%d 次）、快照最長間隔 %d ms、房主收隊友輸入最長間隔 %d ms" % [roundi(latency * step_ms), rtt[0], rtt[-1], rtt.size(), gap, host_gap])
	link.clear()
	return err


static func _chase_cmd(w: World, peer_id: int) -> InputCmd:
	var p: Player = w.players.get(peer_id)
	if p == null:
		return _cmd(Vector2.ZERO)
	var best: Entity = null
	for e: Entity in w.enemies:
		if not e.is_dead and (best == null or e.pos.distance_squared_to(p.pos) < best.pos.distance_squared_to(p.pos)):
			best = e
	if best == null:
		return _cmd(Vector2.ZERO)
	var to := best.pos - p.pos
	return _cmd(to.normalized() if to.length() > 1.5 else Vector2.ZERO, InputCmd.BTN_ATTACK, best.pos)


# C3：單程延遲 6 步（100 ms）、掉包 10% 下，自己的角色按下就動、修正後誤差小；別人的角色每步位移平順
static func check_prediction(feel: Array[String]) -> String:
	var link := _Link.new(9, [1, 2], 6, 0.1, false)
	var me := Vector2.ZERO
	var err := ""
	# 先等快照建立鏡像
	for i in 30:
		link.step(_cmd(Vector2.ZERO), _cmd(Vector2.ZERO))
	var cp := link.client.local_player()
	if cp == null:
		link.clear()
		return "客戶端沒有建立自己的角色"
	me = cp.pos
	link.step(_cmd(Vector2.ZERO), _cmd(Vector2(1, 0)))
	var first_move := cp.pos.x - me.x
	var speed: float = Config.PLAYER.move_speed
	if absf(first_move - speed * DT) > 1e-3:
		err = "按下移動的第一步就該在本機移動 %.4f，實際 %.4f（沒有預測）" % [speed * DT, first_move]
	# 移動、跳、翻滾、轉彎、停下；房主的角色從場地下緣一直往 +Z 走（看客戶端畫面上的平順度；離客戶端的角色遠，不會互推、不會撞牆）
	(link.host_world.players[1] as Player).pos = Vector2(-8, -15)
	for i in 20:
		link.step(_cmd(Vector2.ZERO), _cmd(Vector2.ZERO))
	var remote_steps: Array[float] = []
	var hp: Player = link.client.world.players.get(1)
	for i in 300:
		var move := Vector2(1, 0) if i < 60 else (Vector2(0, 1) if i < 120 else (Vector2(-0.7, -0.7) if i < 180 else Vector2.ZERO))
		var b := 0
		if i == 70:
			b = InputCmd.BTN_JUMP
		elif i == 100 or i == 150:
			b = InputCmd.BTN_ROLL
		var before := hp.pos if hp != null else Vector2.ZERO
		link.step(_cmd(Vector2(0, 1) if i < 200 else Vector2.ZERO), _cmd(move, b))
		hp = link.client.world.players.get(1)
		if i >= 30 and i < 190 and hp != null:
			remote_steps.append(hp.pos.distance_to(before))
	for i in 60:
		link.step(_cmd(Vector2.ZERO), _cmd(Vector2.ZERO))
	var server_pos: Vector2 = (link.host_world.players[2] as Player).pos
	var final_err := cp.pos.distance_to(server_pos)
	var c := link.client
	var expected_step := speed * DT
	var worst := 0.0
	var outliers := []
	for i in remote_steps.size():
		var d := remote_steps[i]
		worst = maxf(worst, absf(d - expected_step))
		if absf(d - expected_step) > 0.02:
			outliers.append("%d:%.3f" % [i + 30, d])
	if not outliers.is_empty():
		feel.append("C3 除錯：位移異常的步 %s" % [outliers])
	feel.append("C3 預測：延遲 100 ms + 掉包 10%%，移動 / 跳 / 翻滾 300 步，修正 %d 次、最大誤差 %.4f、停下後與房主差 %.5f；別人的角色每步位移 %.4f ± %.4f" % [c.corrections, c.max_error, final_err, expected_step, worst])
	if err == "" and final_err > 0.01:
		err = "停下後本機位置與房主差 %.4f（應 < 0.01）" % final_err
	if err == "" and c.max_error > 0.25:
		err = "預測誤差最大 %.4f（應 < 0.25，約兩步的移動量）" % c.max_error
	if err == "" and worst > 0.02:
		err = "別人的角色每步位移不平順：與 %.4f 最多差 %.4f（應 < 0.02）" % [expected_step, worst]
	link.clear()
	return err


# C4 連線：客戶端的角色倒下 / 被救起 / 救人，兩邊狀態一致
static func check_net_downed() -> String:
	var link := _Link.new(5, [1, 2], 3, 0.0, false)
	for i in 30:
		link.step(_cmd(Vector2.ZERO), _cmd(Vector2.ZERO))
	var hp1: Player = link.host_world.players[1]
	var hp2: Player = link.host_world.players[2]
	hp1.pos = Vector2(0, 0)
	hp2.pos = Vector2(0, 1.0)
	_hurt_between_steps(link, hp2)
	for i in 30:
		link.step(_cmd(Vector2.ZERO), _cmd(Vector2(1, 0)))
	var me := link.client.local_player()
	if not me.is_downed or me.locomotion.current_name != &"downed":
		return "客戶端自己的角色應跟著房主倒地（is_downed=%s、%s）" % [me.is_downed, me.locomotion.current_name]
	if me.pos.distance_to(hp2.pos) > 0.05:
		return "倒地後不能靠預測移動：客戶端 %s，房主 %s" % [me.pos, hp2.pos]
	if _named(link.client_events, "player:downed").is_empty():
		return "客戶端應收到 player:downed"
	var steps := 0
	while hp2.is_downed and steps < 400:
		link.step(_cmd(Vector2.ZERO, InputCmd.BTN_INTERACT), _cmd(Vector2.ZERO))
		steps += 1
	for i in 15:
		link.step(_cmd(Vector2.ZERO), _cmd(Vector2.ZERO))
	var revived_hp := roundf(hp2.max_hp * Config.REVIVE.revive_hp_ratio)
	if hp2.is_downed or me.is_downed or me.hp != revived_hp or not me.locomotion.is_in(&"idle"):
		return "房主救起 P2 後，客戶端應站起來、血量 %.0f（實際 downed=%s hp=%.1f %s）" % [revived_hp, me.is_downed, me.hp, me.locomotion.current_name]
	# 反過來：客戶端救倒地的房主
	_hurt_between_steps(link, hp1)
	steps = 0
	while hp1.is_downed and steps < 500:
		link.step(_cmd(Vector2.ZERO), _cmd(Vector2.ZERO, InputCmd.BTN_INTERACT))
		steps += 1
	link.clear()
	if hp1.is_downed or hp1.hp != roundf(hp1.max_hp * Config.REVIVE.revive_hp_ratio):
		return "客戶端按住 F 應能救起倒地的房主（%d 步後 downed=%s）" % [steps, hp1.is_downed]
	return ""


# 在兩步之間直接打倒玩家（正式遊戲裡傷害都發生在 step 中）：只把這次產生的事件送出去
static func _hurt_between_steps(link: _Link, p: Player) -> void:
	link.host_world.events.clear()
	p.take_damage(1000.0, Vector2(1, 0), 0.0, 0)
	link._send_events()


# C1：真的開兩個 Godot 程序（headless）用 ENet 連線：房主與客戶端各自移動 2 秒後停下，結束時兩邊印出的每位玩家位置一致
static func check_two_processes(feel: Array[String]) -> String:
	var exe := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	var dir := OS.get_user_data_dir()
	var logs := [dir.path_join("net_host.log"), dir.path_join("net_client.log")]
	for path: String in logs:
		DirAccess.remove_absolute(path)
	var port := "--net-port=%d" % (Config.NET.port + 7)
	var common := ["--headless", "--path", project]
	# --menu-flow（v0.36.2，v0.39.0 改從主選單）：照玩家的順序，在主選單的多人頁開房 / 加入（v0.36.2 之前加入後一直停在暫停，客戶端不能動）
	var host_args := common + ["--log-file", logs[0], "--", "--menu-flow", "--host", port, "--net-autostart=2", "--no-spawn", "--auto-move=1,0", "--auto-move-seconds=2", "--seconds=5"]
	var client_args := common + ["--log-file", logs[1], "--", "--menu-flow", "--join=127.0.0.1", port, "--no-spawn", "--auto-move=0,1", "--auto-move-seconds=2", "--seconds=5"]
	var host_pid := OS.create_process(exe, host_args)
	OS.delay_msec(500)
	var client_pid := OS.create_process(exe, client_args)
	var waited := 0
	while (OS.is_process_running(host_pid) or OS.is_process_running(client_pid)) and waited < 30000:
		OS.delay_msec(100)
		waited += 100
	for pid: int in [host_pid, client_pid]:
		if OS.is_process_running(pid):
			OS.kill(pid)
	var lines := []
	var states := []
	for path: String in logs:
		var f := FileAccess.open(path, FileAccess.READ)
		var found := ""
		var state := ""
		if f != null:
			for line in f.get_as_text().split("\n"):
				if line.begins_with("players "):
					found = line.strip_edges()
				elif line.begins_with("state "):
					state = line.strip_edges()
		lines.append(found)
		states.append(state)
	# 兩邊都要：沒有停在暫停、有在收輸入、特效有在走、自己的角色真的動了（各自 auto-move 2 秒，約 13 單位）
	for i in 2:
		var who := "房主" if i == 0 else "客戶端"
		var s: String = states[i]
		if s == "" or not s.contains("title=0 paused=0 input=1 effects_paused=0"):
			return "%s從主選單開房 / 加入後應該能玩（離開主選單、沒有暫停、收輸入、特效在走）：%s" % [who, s]
		var moved := s.get_slice("self_moved=", 1).to_float()
		if moved < 5.0:
			return "%s自己的角色應移動約 13 單位，實際 %.2f：%s" % [who, moved, s]
	if lines[0] == "" or lines[1] == "":
		return "沒有讀到兩邊的玩家位置（房主：%s；客戶端：%s）" % [lines[0], lines[1]]
	var host_pos := _parse_players(lines[0])
	var client_pos := _parse_players(lines[1])
	if host_pos.size() != 2 or client_pos.size() != 2:
		return "應有 2 位玩家：房主 %s；客戶端 %s" % [lines[0], lines[1]]
	var worst := 0.0
	for peer: int in host_pos:
		if not client_pos.has(peer):
			return "客戶端沒有玩家 %d" % peer
		worst = maxf(worst, (host_pos[peer] as Vector2).distance_to(client_pos[peer]))
	var moved := (host_pos.values()[0] as Vector2).length()
	feel.append("C1 兩個程序（照選單流程）：房主 %s；客戶端 %s；位置最大差 %.4f；%s / %s" % [lines[0], lines[1], worst, states[0], states[1]])
	if moved < 5.0:
		return "房主的角色應移動了約 13 單位（實際 %.2f），檢查才有意義" % moved
	return "" if worst < 0.01 else "兩邊的玩家位置差 %.4f（應 < 0.01）" % worst


static func _parse_players(line: String) -> Dictionary:
	var out := {}
	for m in RegEx.create_from_string("(\\d+)=\\(([-\\d.]+),([-\\d.]+)\\)").search_all(line):
		out[m.get_string(1).to_int()] = Vector2(m.get_string(2).to_float(), m.get_string(3).to_float())
	return out
