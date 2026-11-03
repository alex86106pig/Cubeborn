# 多人時每位玩家頭上的名牌（P1~P4，自己金色）；倒地時顯示假死倒數（紅，加剩幾秒）與救援進度（綠），走進救援範圍時寫「[F] 按住救援」
# 倒地的隊友在視野外或畫面外時，畫面邊緣畫紅色箭頭指過去（不受視野限制：要讓人找得到去救）
# 單機時不顯示
class_name PlayerTags
extends Control

const HEAD_OFFSET := 2.6        # 名牌在腳底上方的高度（世界單位）
const BAR_SIZE := Vector2(64, 7)
const EDGE_INSET := 56.0        # 邊緣箭頭離畫面邊多遠
const ARROW_SIZE := 18.0
const REVIVE_HINT := "[F] 按住救援"

var world: World
var camera: Camera3D
var local_peer := World.HOST_PEER_ID
var view_peer := 0   # 觀戰中的隊友（0 = 本機）


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
	var viewer: Player = world.players.get(view_peer if view_peer != 0 else local_peer)
	var screen := Rect2(Vector2.ZERO, size)
	for peer_id: int in peers:
		var p: Player = world.players[peer_id]
		if p.descended:
			continue
		var seen := Vision.entity_visible(world, viewer, p)
		if p.is_downed and peer_id != local_peer:
			var at_feet := camera.unproject_position(WorldView.render_pos(p, 0.0))
			if not seen or not screen.grow(-EDGE_INSET * 0.5).has_point(at_feet):
				_edge_arrow(font, at_feet, "P%d %d" % [peers.find(peer_id) + 1, ceili(p.down_timer)])
		if not seen:   # 視野外、已走進出口（D6）的隊友連名牌都看不到（D2）；觀戰時用隊友的視野
			continue
		var at := WorldView.render_pos(p, HEAD_OFFSET)
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
			_outlined(font, s + Vector2(BAR_SIZE.x / 2.0 + 6, 16), str(ceili(p.down_timer)), HORIZONTAL_ALIGNMENT_LEFT, 18, UiKit.ALERT)
			var me: Player = world.players.get(local_peer)
			if peer_id != local_peer and me != null and view_peer == 0 and not me.is_dead and not me.is_downed and me.pos.distance_to(p.pos) <= Config.REVIVE.range:
				_outlined(font, s + Vector2(-80, 46), REVIVE_HINT, HORIZONTAL_ALIGNMENT_CENTER, 20, Color("4ade80"), 160)


# 畫面邊緣的箭頭：從畫面中央往 target 的方向，貼在內縮 EDGE_INSET 的框上，旁邊寫「P2 7」（誰、剩幾秒）
func _edge_arrow(font: Font, target: Vector2, label: String) -> void:
	var center := size / 2.0
	var dir := target - center
	if dir.length_squared() < 1.0:
		dir = Vector2.UP
	dir = dir.normalized()
	var half := center - Vector2(EDGE_INSET, EDGE_INSET)
	var t := minf(half.x / maxf(absf(dir.x), 1e-4), half.y / maxf(absf(dir.y), 1e-4))
	var tip := center + dir * t
	var side := Vector2(-dir.y, dir.x)
	var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.01)
	draw_colored_polygon(PackedVector2Array([tip + dir * ARROW_SIZE, tip - dir * ARROW_SIZE * 0.6 + side * ARROW_SIZE * 0.8, tip - dir * ARROW_SIZE * 0.6 - side * ARROW_SIZE * 0.8]), Color(UiKit.ALERT, pulse))
	_outlined(font, tip - dir * (ARROW_SIZE * 1.6) - Vector2(40, -6), label, HORIZONTAL_ALIGNMENT_CENTER, 18, UiKit.ALERT)


func _outlined(font: Font, at: Vector2, text: String, align: HorizontalAlignment, font_size: int, color: Color, width := 80.0) -> void:
	draw_string_outline(font, at, text, align, width, font_size, 4, Color(0, 0, 0, 0.8))
	draw_string(font, at, text, align, width, font_size, color)


func _bar(at: Vector2, ratio: float, color: Color) -> void:
	draw_rect(Rect2(at, BAR_SIZE), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(at, Vector2(BAR_SIZE.x * clampf(ratio, 0.0, 1.0), BAR_SIZE.y)), color)
