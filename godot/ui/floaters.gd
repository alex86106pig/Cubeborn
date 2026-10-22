# 浮動數字（照搬網頁版 HUD 的 floaters）：傷害、暴擊、玩家受傷、治療；從角色頭頂往上飄並淡出
class_name Floaters
extends Control

const LIFE := 0.8
const RISE_SPEED := 1.6       # 世界單位 / 秒
const JITTER := 0.6           # 水平隨機偏移（世界單位）
const HEAD_OFFSET := 0.3
# 角色頭頂高度（view/rig.gd 的關節高度）
const HEIGHTS := {
	&"player": 2.1, &"grunt": 1.95, &"archer": 1.95, &"boss": 2.1 * 1.85,
}
const STYLES := {
	&"dmg": [20, Color.WHITE],
	&"crit": [28, UiKit.GOLD],
	&"player": [24, UiKit.PLAYER_HURT],
	&"heal": [24, UiKit.HEAL],
}

var camera: Camera3D
var _items: Array[Dictionary] = []   # { node, world, life }


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func spawn(target: Entity, text: String, style: StringName) -> void:
	var s: Array = STYLES[style]
	var node := UiKit.label(text, s[0], s[1])
	add_child(node)
	var height: float = HEIGHTS.get(target.kind, 2.0)
	var at := Vector3(target.pos.x + (randf() - 0.5) * JITTER, target.height + height + HEAD_OFFSET, target.pos.y)
	_items.append({"node": node, "world": at, "life": LIFE})
	_place(_items[-1])


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
	node.modulate.a = minf(1.0, k * 2.5)
	if camera != null and camera.is_inside_tree():
		node.position = camera.unproject_position(it.world) - node.size / 2.0
