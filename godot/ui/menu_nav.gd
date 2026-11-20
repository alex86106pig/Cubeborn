# 選單的鍵盤操作（YangHsu 2026-11-20：能用鍵盤操作介面，WASD 切換目前選的）：WASD 移動目前選的那一個、F 按下（跟遊戲裡互動一樣）。主選單、暫停、結算用這個框框；選角與選獎勵用 dir_of / is_confirm 自己處理
# 不用 Godot 的焦點（ui_left 這些動作）：按鈕都是 FOCUS_NONE（遊戲中空白鍵、Enter 不能被按鈕吃掉），
# 而且多人頁的輸入框打字時 A / D 不能被當成移動；有輸入框在打字時這裡什麼都不收
class_name MenuNav
extends RefCounted

const FRAME_PAD := 5.0
const FRAME_COLOR := Color("ffd84a")

var sel := -1              # 目前選的是 items 的第幾個（-1 = 還沒選，下一次 refresh 選第一個能按的）
var frame := Panel.new()   # 選到的那個外面的金框（top_level，照它的位置與大小擺）


func _init(host: Control) -> void:
	frame.top_level = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.visible = false
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = FRAME_COLOR
	box.set_border_width_all(3)
	box.set_corner_radius_all(9)
	frame.add_theme_stylebox_override(&"panel", box)
	host.add_child(frame)


# WASD（照實體按鍵位置；YangHsu 2026-11-20：不要方向鍵，只用 WASD）
static func dir_of(event: InputEvent) -> Vector2i:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return Vector2i.ZERO
	match k.physical_keycode:
		KEY_W:
			return Vector2i.UP
		KEY_S:
			return Vector2i.DOWN
		KEY_A:
			return Vector2i.LEFT
		KEY_D:
			return Vector2i.RIGHT
	return Vector2i.ZERO


# 確定：F（YangHsu 2026-11-20：選獎勵那些都用 F 確認，跟遊戲裡互動一樣；按住不放的連發不算）
static func is_confirm(event: InputEvent) -> bool:
	var k := event as InputEventKey
	return k != null and k.pressed and not k.echo and k.physical_keycode == KEY_F


static func is_back(event: InputEvent) -> bool:
	var k := event as InputEventKey
	return k != null and k.pressed and not k.echo and k.physical_keycode == KEY_ESCAPE


# 有輸入框正在打字（房號、IP、名字）：按鍵給它
static func typing(vp: Viewport) -> bool:
	var f := vp.gui_get_focus_owner() if vp != null else null
	return f is LineEdit or f is TextEdit


# node 底下看得到的按鈕（照樹的順序）
static func buttons_in(node: Node) -> Array:
	var out := []
	for c in node.get_children():
		if c is Control and not (c as Control).visible:
			continue
		if c is Button:
			out.append(c)
		out.append_array(buttons_in(c))
	return out


static func _usable(c: Control) -> bool:
	return is_instance_valid(c) and c.is_visible_in_tree() and not (c is BaseButton and (c as BaseButton).disabled)


# items 裡從 current 往 dir 走、畫面上最近的那一個（沿著方向的距離 + 偏離的距離 × 2）；那邊沒有就留在原地；
# current 不能選（-1、看不到、停用）時回傳第一個能選的；都不能選回傳 -1
static func step(items: Array, current: int, dir: Vector2i) -> int:
	var first := -1
	for i in items.size():
		if _usable(items[i]):
			first = i
			break
	if first < 0:
		return -1
	if current < 0 or current >= items.size() or not _usable(items[current]):
		return first
	if dir == Vector2i.ZERO:
		return current
	var from: Vector2 = (items[current] as Control).get_global_rect().get_center()
	var fwd := Vector2(dir)
	var best := current
	var best_score := INF
	for i in items.size():
		if i == current or not _usable(items[i]):
			continue
		var d: Vector2 = (items[i] as Control).get_global_rect().get_center() - from
		var along := d.dot(fwd)
		if along <= 1.0:
			continue
		var score := along + absf(d.dot(Vector2(-fwd.y, fwd.x))) * 2.0
		if score < best_score:
			best_score = score
			best = i
	return best


# 處理一個輸入：移動回傳 true、按下回傳 true（呼叫的人 set_input_as_handled）；滑鼠移到某個按鈕上，框框跟過去
func handle(event: InputEvent, items: Array, vp: Viewport) -> bool:
	if typing(vp):
		return false
	if event is InputEventMouseMotion:
		for i in items.size():
			if _usable(items[i]) and (items[i] as Control).get_global_rect().has_point((event as InputEventMouseMotion).position):
				sel = i
		return false
	var dir := dir_of(event)
	if dir != Vector2i.ZERO:
		sel = step(items, sel, dir)
		refresh(items)
		return true
	if is_confirm(event):
		sel = step(items, sel, Vector2i.ZERO)
		if sel >= 0 and items[sel] is BaseButton:
			(items[sel] as BaseButton).pressed.emit()
			return true
	return false


# 每幀：選的那個不能選了（換頁、藏起來）就換第一個；框框擺到它外面
func refresh(items: Array) -> void:
	sel = step(items, sel, Vector2i.ZERO)
	frame.visible = sel >= 0
	if sel >= 0:
		var r: Rect2 = (items[sel] as Control).get_global_rect().grow(FRAME_PAD)
		frame.position = r.position
		frame.size = r.size


func hide() -> void:
	frame.visible = false
	sel = -1
