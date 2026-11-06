# 換小關 / 換層的過場：黑幕從四周收成一個圓、縮到自己的角色上 → 換關（畫面完全蓋住，換地圖與重建場地的卡頓藏在這裡）→
# 中間顯示關卡卡片（「1-3 墓園」、基礎難度、門的獎勵、這關有沒有鐵砧）→ 從新地圖出生點的角色往外打開
# 收圈從 level:leaving 開始（模擬層等 EventDefs.LEAVE.cover 秒才換關），蓋滿之後等到地形真的換了、卡片至少顯示 HOLD 秒才打開；
# 連線時客戶端收到換關、自己照種子算完地圖才打開，比較慢的人黑幕多停一下。只畫在畫面上，不影響模擬
# 圓用 _draw 畫一個很粗的圓環（內緣就是洞），不用著色器：第一次播不必編譯
class_name LevelTransition
extends Control

const COVER_SHARE := 0.75   # 收圈在 cover 秒的這個比例內收完：全黑之後到模擬換關還有約 0.09 秒（30 FPS 也有 2 幀以上），換關卡住時畫面一定是黑的
const HOLD := 0.35          # 地形換好之後至少再停這麼久（關卡卡片）
const OPEN := 0.38          # 打開的秒數
const GIVE_UP := 3.0        # 全黑之後最多等這麼久（連線斷掉、地形沒換）就直接打開
const RING_POINTS := 96
const COLOR := Color(0.043, 0.047, 0.059)

enum Phase { IDLE, CLOSING, HOLDING, OPENING }

var phase := Phase.IDLE
var _t := 0.0
var _duration := 0.0
var _radius := 0.0
var _center := Vector2.ZERO
var _layout_before := []
var _black_for := 0.0       # 全黑之後過了幾秒
var _changed_for := -1.0    # 地形換好之後過了幾秒（-1 = 還沒換）
var _card := VBoxContainer.new()
var _title := UiKit.label("", UiKit.FONT_TITLE)
var _sub := UiKit.label("", UiKit.FONT_NOTE, UiKit.GOLD)
var _extra := UiKit.label("", UiKit.FONT_BODY)


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for l: Label in [_title, _sub, _extra]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_card.add_child(l)
	add_child(_card)
	_card.visible = false


func is_active() -> bool:
	return phase != Phase.IDLE


# 收圈：world.layout_key 之後變了才算換好
func start(cover: float, world: World) -> void:
	phase = Phase.CLOSING
	_t = 0.0
	_duration = maxf(0.05, cover * COVER_SHARE)
	_layout_before = world.layout_key.duplicate()
	_black_for = 0.0
	_changed_for = -1.0
	_card.visible = false
	visible = true


# 關卡卡片的文字（stage:started / floor:started 到了就更新；reward 是 MapGenDefs.REWARDS 的鍵，空的 = 沒有獎勵）
func set_card(world: World, p_floor: int, stage: int, difficulty: int, reward: String) -> void:
	_title.text = "%s %s" % [World.level_name(p_floor, stage), world.map.get("name", "")]
	_sub.text = "基礎難度 %d" % difficulty
	var lines: Array[String] = []
	if reward != "":
		var r: Dictionary = MapGenDefs.REWARDS[StringName(reward)]
		lines.append("獲得：%s%s" % [UiKit.reward_name(world, StringName(reward)), " +%d" % r.amount if r.has("amount") else ""])
	if world.map.has("anvil"):
		lines.append("這關有鐵砧")
	_extra.text = "\n".join(PackedStringArray(lines))
	_extra.visible = not lines.is_empty()


func is_black() -> bool:
	return phase == Phase.HOLDING


# 卡片現在顯示的字（看不到時是空字串）：標題、副標、獎勵與鐵砧，一行一個
func card_text() -> String:
	if not _card.visible:
		return ""
	var parts: Array[String] = [_title.text, _sub.text]
	if _extra.visible:
		parts.append(_extra.text)
	return "\n".join(PackedStringArray(parts))


func cancel() -> void:
	phase = Phase.IDLE
	visible = false


# 每幀（HUD）：center 是自己角色在畫面上的位置（沒有角色就用畫面中央）
func update(delta: float, world: World, center: Vector2) -> void:
	if phase == Phase.IDLE:
		return
	_center = center
	var far := _far_corner(center)
	match phase:
		Phase.CLOSING:
			_t += delta
			var k := clampf(_t / _duration, 0.0, 1.0)
			_radius = far * (1.0 - _ease(k))
			if k >= 1.0:
				phase = Phase.HOLDING
				_radius = 0.0
		Phase.HOLDING:
			_black_for += delta
			if _changed_for < 0.0 and world.layout_key != _layout_before:
				_changed_for = 0.0
				_card.visible = true
			elif _changed_for >= 0.0:
				_changed_for += delta
			if _changed_for >= HOLD or _black_for >= GIVE_UP:
				phase = Phase.OPENING
				_t = 0.0
		Phase.OPENING:
			_t += delta
			var k := clampf(_t / OPEN, 0.0, 1.0)
			_radius = far * _ease(k)
			_card.modulate.a = 1.0 - clampf(k / 0.6, 0.0, 1.0)
			if k >= 1.0:
				phase = Phase.IDLE
				visible = false
				_card.visible = false
				_card.modulate.a = 1.0
	queue_redraw()


# 圓心到最遠的角：圓放到這麼大就整個畫面都看得到
func _far_corner(c: Vector2) -> float:
	var s := size
	return maxf(maxf(c.length(), (c - Vector2(s.x, 0)).length()), maxf((c - Vector2(0, s.y)).length(), (c - s).length())) + 4.0


static func _ease(k: float) -> float:
	return 2.0 * k * k if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 2.0) / 2.0


func _draw() -> void:
	if _radius <= 0.5:
		draw_rect(Rect2(Vector2.ZERO, size), COLOR)
		return
	# 從 _radius 到最遠的角的粗圓環：寬度 w、畫在中線 _radius + w / 2
	var w := _far_corner(_center) - _radius + 2.0
	if w > 0.0:
		draw_arc(_center, _radius + w / 2.0, 0.0, TAU, RING_POINTS, COLOR, w)
