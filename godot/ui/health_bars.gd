# 頭頂血條（v0.43.0）：自己與隊友綠色、怪物紅色；滿血、死亡、倒地（改顯示倒數）、視野外都不畫，Boss 用上方大血條不畫
# 怪物的血條在魔法 / 稀有怪詞條（WorldLabels）的基線下方、頭頂上方；玩家的在 P1~P4 名牌（PlayerTags）的基線下方
# 只畫受傷又看得到的，上百隻怪時也只是幾十個矩形，不另外建節點
class_name HealthBars
extends Control

const ENEMY_SIZE := Vector2(48, 5)
const PLAYER_SIZE := Vector2(64, 6)
const ENEMY_GAP := 5.0     # 血條上緣在詞條基線（WorldLabels.ENEMY_OFFSET）下方幾 px
const PLAYER_GAP := 6.0    # 血條上緣在名牌基線（PlayerTags.HEAD_OFFSET）下方幾 px
const FULL_EPSILON := 0.01 # hp 差這麼一點也算滿血（客戶端快照滿血時 hp 剛好等於 max_hp）
const BG := Color(0, 0, 0, 0.6)
const PLAYER_FILL := Color("4ade80")
const ENEMY_FILL := UiKit.HP_FILL

var world: World
var camera: Camera3D
var local_peer := World.HOST_PEER_ID
var hidden_ids: Variant = null   # WorldView.hidden_ids（每個 tick 已算過視野與牆擋）；沒接上時（測試）改用 Vision.entity_visible


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	for b: Dictionary in bars():
		var rect: Rect2 = b.rect
		draw_rect(rect, BG)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * b.ratio, rect.size.y)), b.color)


# 這一幀要畫的血條：[{entity, ratio, color, rect（畫面座標，整條的範圍）}]
func bars() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null or camera == null:
		return out
	var me: Player = world.players.get(local_peer)
	for p: Player in world.player_list:
		if p.is_downed or p.descended:
			continue
		_add(out, me, p, PlayerTags.HEAD_OFFSET, PLAYER_GAP, PLAYER_SIZE, PLAYER_FILL)
	for e: Entity in world.enemies:
		if e is Boss:
			continue
		_add(out, me, e, e.body_height + WorldLabels.ENEMY_OFFSET, ENEMY_GAP, ENEMY_SIZE, PLAYER_FILL if e.team == &"player" else ENEMY_FILL)   # 骷髏僕從（G6）綠色
	return out


func _add(out: Array[Dictionary], me: Player, e: Entity, offset: float, gap: float, size: Vector2, color: Color) -> void:
	if e.is_dead or e.is_removed or e.hp >= e.max_hp - FULL_EPSILON or not _visible(me, e):
		return
	var s: Variant = _screen(Vector3(e.pos.x, e.height + offset, e.pos.y))
	if s == null:
		return
	out.append({"entity": e, "ratio": clampf(e.hp / e.max_hp, 0.0, 1.0), "color": color,
		"rect": Rect2(s + Vector2(-size.x / 2.0, gap), size)})


# 世界座標 → 畫面座標；在相機後面回傳 null（check.gd 的相機不在場景樹裡，檢查時換成固定投影）
func _screen(at: Vector3) -> Variant:
	if camera.is_position_behind(at):
		return null
	return camera.unproject_position(at)


func _visible(me: Player, e: Entity) -> bool:
	if hidden_ids != null:
		return not (hidden_ids as Dictionary).has(e.id)
	return Vision.entity_visible(world, me, e)
