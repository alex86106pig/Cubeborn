# 浮動數字（照搬網頁版 HUD 的 floaters）：傷害、暴擊、玩家受傷、治療；從角色頭頂往上飄並淡出
class_name Floaters
extends Control

const LIFE := 0.8
const RISE_SPEED := 1.6       # 世界單位 / 秒
const JITTER := 0.6           # 水平隨機偏移（世界單位）
const HEAD_OFFSET := 0.3
const STACK_WINDOW := 0.2     # 同一個目標這麼多秒內跳的數字（屬性轉換、冰棺分傷害是同一步好幾個）往上疊一層，不疊在一起
const STACK_STEP := 0.5       # 每疊一層往上幾個世界單位（約一行字高）
const STACK_MAX := 4          # 最多疊幾層，再多就換到旁邊一欄（冰棺分傷害一次 5、6 個，疊成一整欄太高）
const STACK_SIDE := 0.8       # 換欄時往左右移幾個世界單位（左右輪流）
# 角色頭頂高度（view/rig.gd 的關節高度）
const HEIGHTS := {
	&"player": 2.1, &"grunt": 1.95, &"archer": 1.95, &"zombie": 1.85, &"bloater": 1.8, &"hound": 1.0, &"boss": 2.1 * 1.85, &"gravekeeper": 2.1 * 1.3,
}
const STYLES := {
	&"dmg": [20, Color.WHITE],
	&"crit": [28, UiKit.GOLD],
	&"player": [24, UiKit.PLAYER_HURT],
	&"heal": [24, UiKit.HEAL],
	&"coin": [24, UiKit.GOLD],   # 撿到金幣（v0.45）
	&"minor": [16, Color.WHITE],   # 附帶的小傷害（持續傷害的一跳、附加屬性傷害）：小字、半透明，不佔疊層
}
const MINOR_ALPHA := 0.7

var camera: Camera3D
var _items: Array[Dictionary] = []   # { node, world, life, target }


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# color：蓋過樣式的顏色（屬性傷害的數字），alpha 0 = 照樣式
func spawn(target: Entity, text: String, style: StringName, color := Color(0, 0, 0, 0)) -> void:
	var s: Array = STYLES[style]
	var node := UiKit.label(text, s[0], s[1] if color.a == 0.0 else color)
	add_child(node)
	var is_minor := style == &"minor"
	var n := 0 if is_minor else stack_count(target.id)
	var col := floori(n / float(STACK_MAX))
	var column := ceili(col / 2.0) * (1 if col % 2 == 1 else -1)   # 第幾欄：0、+1、-1、+2…
	var height: float = HEIGHTS.get(target.kind, 2.0) + (n % STACK_MAX) * STACK_STEP
	var side := camera.global_basis.x if camera != null and camera.is_inside_tree() else Vector3.RIGHT   # 螢幕的左右
	var at := Vector3(target.pos.x + (randf() - 0.5) * JITTER, target.height + height + HEAD_OFFSET, target.pos.y) + side * column * STACK_SIDE
	_items.append({"node": node, "world": at, "life": LIFE, "target": target.id, "minor": is_minor})
	_place(_items[-1])


# 這個目標剛跳出（STACK_WINDOW 秒內）、還在畫面上的數字有幾個
func stack_count(target_id: int) -> int:
	var n := 0
	for it in _items:
		if it.target == target_id and not it.minor and it.life > LIFE - STACK_WINDOW:
			n += 1
	return n


func clear() -> void:
	for it in _items:
		it.node.queue_free()
	_items.clear()


func _process(delta: float) -> void:
	for i in range(_items.size() - 1, -1, -1):
		var it := _items[i]
		it.life -= delta
		if it.life <= 0.0:
			it.node.queue_free()
			_items.remove_at(i)
			continue
		it.world.y += delta * RISE_SPEED
		_place(it)


func _place(it: Dictionary) -> void:
	var node: Label = it.node
	var k: float = it.life / LIFE
	var s := 0.8 + 0.4 * minf(1.0, (1.0 - k) * 6.0)
	node.pivot_offset = node.size / 2.0
	node.scale = Vector2.ONE * s
	node.modulate.a = minf(1.0, k * 2.5) * (MINOR_ALPHA if it.minor else 1.0)
	if camera != null and camera.is_inside_tree():
		node.position = camera.unproject_position(it.world) - node.size / 2.0
