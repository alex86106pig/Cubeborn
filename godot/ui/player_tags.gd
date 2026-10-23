# 多人時每位玩家頭上的名牌（P1~P4，自己金色）；倒地時顯示假死倒數（紅）與救援進度（綠）
# 單機時不顯示
class_name PlayerTags
extends Control

const HEAD_OFFSET := 2.6        # 名牌在腳底上方的高度（世界單位）
const BAR_SIZE := Vector2(64, 7)

var world: World
var camera: Camera3D
var local_peer := World.HOST_PEER_ID


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null or camera == null or world.players.size() < 2:
		return
	var font := get_theme_default_font()
	var peers: Array = world.players.keys()
	peers.sort()
	for peer_id: int in peers:
		var p: Player = world.players[peer_id]
		if p.descended or not Vision.entity_visible(world, world.players.get(local_peer), p):   # 視野外、已走進出口（D6）的隊友連名牌都看不到（D2）
			continue
		var at := Vector3(p.pos.x, p.height + HEAD_OFFSET, p.pos.y)
		if camera.is_position_behind(at):
			continue
		var s := camera.unproject_position(at)
		var label := "P%d" % (peers.find(peer_id) + 1)
		if p.is_dead:
			label += " 陣亡"
		var color := UiKit.GOLD if peer_id == local_peer else Color.WHITE
		draw_string_outline(font, s + Vector2(-40, 0), label, HORIZONTAL_ALIGNMENT_CENTER, 80, 18, 4, Color(0, 0, 0, 0.8))
		draw_string(font, s + Vector2(-40, 0), label, HORIZONTAL_ALIGNMENT_CENTER, 80, 18, color)
		if p.is_downed:
			_bar(s + Vector2(-BAR_SIZE.x / 2.0, 8), p.down_timer / Config.REVIVE.down_time, UiKit.ALERT)
			_bar(s + Vector2(-BAR_SIZE.x / 2.0, 18), p.revive_progress / Config.REVIVE.revive_time, Color("4ade80"))


func _bar(at: Vector2, ratio: float, color: Color) -> void:
	draw_rect(Rect2(at, BAR_SIZE), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(at, Vector2(BAR_SIZE.x * clampf(ratio, 0.0, 1.0), BAR_SIZE.y)), color)
