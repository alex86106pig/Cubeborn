# 客戶端的連線邏輯（不碰傳輸層）：用房主的快照維護鏡像 World，其他實體延遲 interp_delay_ticks 補間，
# 自己的角色本機預測（World.step_predicted），收到快照後依 ack 比對當時的預測位置修正；事件依 tick 延遲到畫面時間才播
class_name NetClient
extends RefCounted

var world := World.new()
var peer_id := 0
var render_tick := -1.0          # 其他實體的畫面時間（房主 tick，可有小數）
var last_error := 0.0            # 最近一次修正時的預測誤差（測試與除錯用）
var max_error := 0.0             # 連線後最大的預測誤差（不含直接跳過去的大誤差）
var corrections := 0             # 修正次數
var applied_tick := -1           # 目前畫面套用的快照 tick（補間的前一筆；測試用）

var _run_id := -1
var _snapshots: Array = []       # 依 tick 遞增
var _latest_tick := -1
var _since_snapshot := 0         # 收到最新快照後過了幾步（估計房主現在的 tick 用）
var _events: Array = []          # [tick, 事件陣列]，依 tick 遞增
var _history: Dictionary = {}    # 客戶端 tick -> [預測的位置, 高度]
var _pending: Array[InputCmd] = []   # 還沒被房主確認的輸入（重送用）
var _client_tick := 0
var _last_ack := 0
var _swap_tick := -1             # 最近一次按 Q / 滾輪切武器的客戶端 tick


func _init(p_peer_id: int) -> void:
	peer_id = p_peer_id
	world.is_authority = false
	world.spawner.finished = true


func local_player() -> Player:
	return world.players.get(peer_id)


# 每個模擬步：推進畫面時間並套用快照 → 預測自己的角色 → 取出到期的事件；回傳本步要交給畫面層的事件
func step(cmd: InputCmd, dt: float) -> Array[Dictionary]:
	_client_tick += 1
	cmd.tick = _client_tick
	_pending.append(cmd)
	if cmd.has(InputCmd.BTN_SWAP_WEAPON):
		_swap_tick = _client_tick
	var out: Array[Dictionary] = []
	_advance_render_clock()
	_apply_interpolated()
	var me := local_player()
	if me != null:
		world.step_predicted(peer_id, cmd, dt)
		out.append_array(world.events)
		_history[_client_tick] = [me.pos, me.height]
	else:
		world.tick += 1
	while not _events.is_empty() and _events[0][0] <= render_tick:
		out.append_array(_events.pop_front()[1])
	return out


# 要送給房主的輸入：最近 input_redundancy 筆（舊到新），掉包時下一次還會帶到
func outgoing_inputs() -> Array:
	var out := []
	var n: int = Config.NET.input_redundancy
	for i in range(maxi(0, _pending.size() - n), _pending.size()):
		out.append(_pending[i].to_array())
	return out


func receive_snapshot(snap: Array) -> void:
	NetCodec.decode_snapshot(snap)
	var run: int = snap[NetCodec.S_RUN]
	if run < _run_id:
		return
	if run > _run_id:
		_reset_mirror(run)
	var tick: int = snap[NetCodec.S_TICK]
	if tick <= _latest_tick:
		return   # 比較舊的快照晚到（unreliable 不保證順序）：丟掉
	_snapshots.append(snap)
	_latest_tick = tick
	_since_snapshot = 0
	_reconcile(snap)


# 房主的事件（reliable）：丟掉標了自己為行動者的（本機預測時已經播過），其餘排到畫面時間再播
func receive_events(run: int, tick: int, events: Array) -> void:
	if run < _run_id:
		return
	if run > _run_id:
		_reset_mirror(run)
	var kept: Array[Dictionary] = []
	var me := local_player()
	for ev: Dictionary in events:
		if ev.get("actor", 0) == peer_id:
			continue
		# 自己被打：受擊硬直與無敵在本機立刻反應（傷害與擊退以房主為準，位置由修正跟上）
		if me != null and ev.name == "entity:damaged" and ev.target_id == me.id:
			me.net_hurt()
		kept.append(ev)
	if not kept.is_empty():
		_events.append([tick, kept])


func _reset_mirror(run: int) -> void:
	_run_id = run
	world.clear()
	world.run_id = run
	_snapshots.clear()
	_latest_tick = -1
	_events.clear()
	_history.clear()
	render_tick = -1.0


# 畫面時間追著「估計的房主 tick - interp_delay_ticks」走：每步 +1，再很慢地修正偏差（速度最多差 5%，畫面才平順）；
# 房主 tick 用「最新快照 + 收到後過了幾步」估計（快照每 3 步才來一次，直接用會變成鋸齒）；差太多直接跳過去；不超過最新快照
func _advance_render_clock() -> void:
	if _latest_tick < 0:
		return
	_since_snapshot += 1
	var estimate := float(_latest_tick + mini(_since_snapshot, Config.NET.snapshot_interval * 2))
	var target := estimate - Config.NET.interp_delay_ticks
	if render_tick < 0.0 or absf(render_tick - target) > 30.0:
		render_tick = target
	else:
		render_tick += 1.0 + clampf((target - render_tick) * 0.02, -0.05, 0.05)
	render_tick = minf(render_tick, _latest_tick + Config.NET.max_extrapolate_ticks)


func _apply_interpolated() -> void:
	if _snapshots.is_empty():
		return
	# a = 畫面時間之前最近的一筆，b = 下一筆
	var ai := 0
	while ai + 1 < _snapshots.size() and _snapshots[ai + 1][NetCodec.S_TICK] <= render_tick:
		ai += 1
	if ai > 0:
		_snapshots = _snapshots.slice(ai)
	var a: Array = _snapshots[0]
	var b: Array = _snapshots[1] if _snapshots.size() > 1 else []
	applied_tick = a[NetCodec.S_TICK]
	var t := 0.0
	var ahead := 0.0   # 沒有下一筆時，畫面時間超過 a 多少秒（沿速度往前推）
	var b_by_id := {}
	if b.is_empty():
		ahead = maxf(0.0, render_tick - a[NetCodec.S_TICK]) * Config.FIXED_DT
	else:
		var span: float = b[NetCodec.S_TICK] - a[NetCodec.S_TICK]
		t = clampf((render_tick - a[NetCodec.S_TICK]) / span, 0.0, 1.0)
		for arr: Array in b[NetCodec.S_ENTITIES]:
			b_by_id[arr[NetCodec.E_ID]] = arr
	var me := local_player()
	for e: Entity in world.entities.values():
		if e != me:
			e.prev_pos = e.pos
			e.prev_facing = e.facing
			e.prev_height = e.height
	var seen := {}
	for arr: Array in a[NetCodec.S_ENTITIES]:
		var id: int = arr[NetCodec.E_ID]
		seen[id] = true
		var e: Entity = world.entities.get(id)
		if NetCodec.is_player_of(arr, peer_id):
			if e == null:
				NetCodec.create_entity(world, arr)
			continue
		if e == null:
			NetCodec.create_entity(world, arr)
			continue
		NetCodec.apply_entity(e, arr, b_by_id.get(id, []), t, ahead)
	for id: int in world.entities.keys():
		if not seen.has(id):
			world.remove_entity_now(id)
	NetCodec.apply_world(world, a)


# 依 ack 修正自己的角色：房主套用到第 ack 筆輸入後的位置 − 當時本機預測的位置 = 誤差，
# 把誤差加到目前位置與之後的預測紀錄（不用倒帶重播，狀態機與計時器都不用存檔）
func _reconcile(snap: Array) -> void:
	var me := local_player()
	var a := NetCodec.find_player(snap, peer_id)
	if me == null or a.is_empty():
		return
	var ack: int = snap[NetCodec.S_ACK]
	var is_new_ack := ack > _last_ack
	if is_new_ack:
		_last_ack = ack
		while not _pending.is_empty() and _pending[0].tick <= ack:
			_pending.pop_front()
	_apply_own_authority(me, a)
	if me.is_dead or me.is_downed:
		# 倒地 / 死亡時不預測：位置直接用房主的（可能被怪推動）
		_history.clear()
		me.pos = Vector2(a[NetCodec.E_X], a[NetCodec.E_Z])
		me.height = a[NetCodec.E_H]
		me.facing = a[NetCodec.E_FACING]
		return
	if not is_new_ack:
		return
	var past: Variant = _history.get(ack)
	for k: int in _history.keys():
		if k <= ack:
			_history.erase(k)
	if past == null:
		return
	var err := Vector2(a[NetCodec.E_X], a[NetCodec.E_Z]) - (past[0] as Vector2)
	var err_h: float = a[NetCodec.E_H] - (past[1] as float)
	last_error = err.length()
	if last_error > Config.NET.snap_distance:
		corrections += 1
	elif last_error > Config.NET.correction_epsilon or absf(err_h) > Config.NET.correction_epsilon:
		max_error = maxf(max_error, last_error)
		corrections += 1
	else:
		return
	me.pos += err
	me.prev_pos += err
	me.height += err_h
	me.prev_height += err_h
	for k: int in _history:
		_history[k][0] += err
		_history[k][1] += err_h


# 自己的角色：血量、倒地 / 死亡、盾反與武器以房主為準（最新快照，不延遲）
func _apply_own_authority(me: Player, a: Array) -> void:
	var extra: Array = a[NetCodec.E_EXTRA]
	NetCodec.apply_life(me, a)
	me.net_sync_life(a[NetCodec.E_DEAD], extra[NetCodec.P_DOWNED], extra[NetCodec.P_DOWN_TIMER], extra[NetCodec.P_REVIVE])
	me.parry_timer = maxf(me.parry_timer, extra[NetCodec.P_PARRY])
	me.sync_inventory(extra[NetCodec.P_INV])   # 背包以房主為準（D3：撿、丟、搬動都在房主執行）
	# 裝備欄以房主為準；手上哪一格在房主處理完最近一次切換（Q / 滾輪）之後才跟著房主，之前保留本機預測
	var active: int = extra[NetCodec.P_ACTIVE] if _last_ack >= _swap_tick else me.active_slot
	me.sync_weapon_slots(extra[NetCodec.P_SLOTS], active)
