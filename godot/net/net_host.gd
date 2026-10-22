# 房主端的連線邏輯（不碰傳輸層）：收各玩家的輸入排隊、每步取一筆給 World.step、記錄 ack、產生快照
# 單機 = 沒有連線的房主（15.2）：房主自己的輸入不經過這裡，由 main.gd 直接放進 cmds
class_name NetHost
extends RefCounted

var world: World
var acks: Dictionary = {}       # peer_id -> 最後套用的輸入編號（客戶端的 tick）
var _queues: Dictionary = {}    # peer_id -> Array[InputCmd]（依 tick 遞增）


func _init(p_world: World) -> void:
	world = p_world


func remove_peer(peer_id: int) -> void:
	_queues.erase(peer_id)
	acks.erase(peer_id)


# arrays：客戶端送來的最近幾筆輸入（InputCmd.to_array，舊到新）；已經套用或已在排隊的跳過（重送的備份）
func receive_inputs(peer_id: int, arrays: Array) -> void:
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
			cmd = next
		acks[peer_id] = cmd.tick
		out[peer_id] = cmd
	return out


# 每位客戶端各一份（只差 ack）
func snapshots() -> Dictionary:
	var entities := NetCodec.encode_entities(world)
	var out := {}
	for peer_id: int in world.players:
		if peer_id != World.HOST_PEER_ID:
			out[peer_id] = NetCodec.make_snapshot(world, entities, acks.get(peer_id, 0))
	return out
