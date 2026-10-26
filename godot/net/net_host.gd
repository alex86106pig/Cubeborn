# 房主端的連線邏輯（不碰傳輸層）：收各玩家的輸入排隊、每步取一筆給 World.step、記錄 ack、產生快照
# 單機 = 沒有連線的房主（PROJECT_GUIDELINES.md 第 2 節）：房主自己的輸入不經過這裡，由 main.gd 直接放進 cmds
class_name NetHost
extends RefCounted

var world: World
var acks: Dictionary = {}       # peer_id -> 最後套用的輸入編號（客戶端的 tick）
var spectating: Dictionary = {} # peer_id -> 陣亡後觀戰的隊友 peer id（最新一筆輸入的 InputCmd.spectate；0 = 沒在觀戰）
var _queues: Dictionary = {}    # peer_id -> Array[InputCmd]（依 tick 遞增）
var input_gap_max_ms: Dictionary = {}   # peer_id -> 兩次收到輸入最長隔多久（遊玩紀錄；以房主的模擬步換算毫秒）
var _last_input_tick: Dictionary = {}   # peer_id -> 上次收到輸入時的 world.tick


func _init(p_world: World) -> void:
	world = p_world
	world.rewind_enabled = true   # 延遲補償：客戶端玩家的近戰照他畫面上的位置判定（v0.38.0）


func remove_peer(peer_id: int) -> void:
	_queues.erase(peer_id)
	acks.erase(peer_id)
	input_gap_max_ms.erase(peer_id)
	_last_input_tick.erase(peer_id)


# arrays：客戶端送來的最近幾筆輸入（InputCmd.to_array，舊到新）；已經套用或已在排隊的跳過（重送的備份）
func receive_inputs(peer_id: int, arrays: Array) -> void:
	var last: int = _last_input_tick.get(peer_id, -1)
	if last >= 0 and world.tick >= last:   # 重新開始時 tick 歸零：跳過那一次
		input_gap_max_ms[peer_id] = maxi(input_gap_max_ms.get(peer_id, 0), roundi((world.tick - last) * Config.FIXED_DT * 1000.0))
	_last_input_tick[peer_id] = world.tick
	var q: Array = _queues.get_or_add(peer_id, [])
	var newest: int = q.back().tick if not q.is_empty() else acks.get(peer_id, 0)
	for a: Array in arrays:
		var cmd := InputCmd.from_array(a)
		if cmd.tick > newest:
			q.append(cmd)
			newest = cmd.tick


# 每個模擬步：每位玩家取一筆輸入（沒有就不給，World 沿用上一筆的移動與按住）
# 排太多筆時把最舊的併進下一筆（本步按下的按鈕保留），延遲才不會越積越多
func take_cmds() -> Dictionary:
	var out := {}
	var limit: int = Config.NET.input_queue_max
	for peer_id: int in _queues:
		var q: Array = _queues[peer_id]
		if q.is_empty():
			continue
		var cmd: InputCmd = q.pop_front()
		while q.size() > limit:
			var next: InputCmd = q.pop_front()
			next.buttons |= cmd.buttons & ~InputCmd.HELD_BUTTONS
			next.inv_ops = cmd.inv_ops + next.inv_ops
			cmd = next
		acks[peer_id] = cmd.tick
		spectating[peer_id] = cmd.spectate
		out[peer_id] = cmd
	return out


# 每位客戶端各一份：只送該玩家附近（NET.interest_radius）的實體，玩家與 Boss 一律送（v0.35.0，網頁 WebRTC 單則訊息有大小上限）
# 每個實體只編碼一次，再依玩家挑選；附近以外的怪客戶端本來就看不到（視野 18），離開範圍就從鏡像移除、回來再建立
func snapshots() -> Dictionary:
	var entities := NetCodec.encode_entities(world)
	var out := {}
	for peer_id: int in world.players:
		if peer_id != World.HOST_PEER_ID:
			var viewer := viewer_of(peer_id)
			var picked := entities.filter(func(rec: Array) -> bool: return in_interest(rec[2], viewer))
			out[peer_id] = NetCodec.make_snapshot(world, picked, acks.get(peer_id, 0), peer_id)
	return out


# 這位客戶端的快照以誰為中心挑實體：自己；陣亡後觀戰時是他看的隊友（InputCmd.spectate）
func viewer_of(peer_id: int) -> Player:
	var me: Player = world.players.get(peer_id)
	var target: Player = world.players.get(spectating.get(peer_id, 0))
	return target if me != null and me.is_dead and target != null else me


func in_interest(e: Entity, viewer: Player) -> bool:
	if viewer == null or e is Player or e.id == world.boss_id:
		return true
	var r: float = Config.NET.interest_radius
	return e.pos.distance_squared_to(viewer.pos) <= r * r
