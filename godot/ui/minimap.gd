# 右上角的小地圖：只畫本機玩家探索過的地方（視野距離內、視線沒被牆擋住的，牆本身看得到），轉 45° 跟畫面的方向一致；
# 地形一格 1 單位畫成一個像素（地面 / 牆與實心 / 墓碑 / 高台），上面標自己（含面向）、隊友（倒地的閃紅點 + 剩幾秒）、出口的門 / 挖墳點、
# 遺物 / 鐵砧（自己還沒選的白框菱形、選過的半透明；隊上有人看過就畫，自己沒走過的地方也畫）、沒開的寶箱
# 地圖放得進框就整張置中，放不進就以自己為中心（框外裁掉）；換地圖（World.layout_key 變了）清掉走過的紀錄
# 看過的場地外框（貼著場地外的 EDGE_CELLS 格）畫成亮色：地面接到亮邊是到底了，接到空白是還沒探索
class_name Minimap
extends Control

const VIEW := Vector2(260, 260)
const MIN_SCALE := 1.6          # 每單位至少幾個像素：地圖太大就不整張塞進框，改成跟著自己
const REVEAL_INTERVAL := 0.2    # 幾秒更新一次走過的範圍
const FRAME_BG := Color(0.03, 0.04, 0.07, 0.6)
const FRAME_LINE := Color(1, 1, 1, 0.25)
const FLOOR := Color(0.42, 0.44, 0.48, 0.85)
const SOLID := Color(0.12, 0.12, 0.14, 0.9)
const TOMB := Color(0.62, 0.6, 0.56, 0.95)
const PLATFORM := Color(0.55, 0.5, 0.4, 0.9)
const EDGE := Color(0.85, 0.9, 1.0, 0.95)       # 看過的場地外框
const EDGE_CELLS := 2           # 外框幾格粗（每格 MIN_SCALE 像素以上）
const KIND_COLORS: Array[Color] = [FLOOR, SOLID, TOMB, PLATFORM]   # 照 _base 的種類
const RAY_STEP := 0.6           # 視線每次往前走幾格（小於 1 才不會跳過牆）
const RAYS_PER_CELL := 1.5      # 視野最外圈每格幾條視線
const DOOR_SEEN_CELLS := 3      # 門嵌在牆裡：看到門旁邊這麼近的格子就算看到門
const SELF := Color("ffffff")
const ALLY := Color("7fe3ff")
const DOOR := Color("8fd0ff")
const DIG := Color("ffd84a")
const RELIC := Color("c88cff")
const CHEST := Color("e0b050")
const DOWNED := Color("ff4a4a")
const BLINK_HZ := 3.0           # 倒地隊友的紅點每秒閃幾次

var world: World
var local_player: Callable   # 回傳 Player（可能是 null），HUD 給

var _key := []
var _size := Vector2i.ZERO
var _base := PackedByteArray()   # 每格的地形種類：0 地面、1 實心、2 墓碑、3 高台
var _seen := PackedByteArray()
var _edge := PackedByteArray()   # 1 = 場地外框的格子（_mark_edges）
var _img: Image
var _tex: ImageTexture
var _timer := 0.0
var _reveal_cell := Vector2i(-1, -1)   # 上次掃視線時站的格子與視野距離，沒變就不用重掃
var _reveal_range := 0.0


func _init() -> void:
	custom_minimum_size = VIEW
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if is_visible_in_tree():
		refresh(delta)
		queue_redraw()


# 換地圖就重畫、每 REVEAL_INTERVAL 秒把本機玩家看得到的格子標成看過
func refresh(delta: float) -> void:
	if world == null:
		return
	if world.layout_key != _key:
		_rebuild()
	_timer -= delta
	if _timer <= 0.0:
		_timer = REVEAL_INTERVAL
		var me: Player = local_player.call()
		if me == null:
			return
		var cell := _cell(me.pos)
		var r := Vision.view_range(me)
		if (cell != _reveal_cell or r != _reveal_range) and _reveal(me.pos, r):
			_tex.update(_img)
		_reveal_cell = cell
		_reveal_range = r


# 地形畫成每單位一格：先全部是地面，石台蓋上去（實心 = 牆高的石台與場地外，墓碑、高台照種類）
func _rebuild() -> void:
	_key = world.layout_key.duplicate()
	_size = Vector2i(ceili(world.half_extents.x * 2.0), ceili(world.half_extents.y * 2.0))
	_base.resize(_size.x * _size.y)
	_base.fill(0)
	_seen.resize(_size.x * _size.y)
	_seen.fill(0)
	for b: Dictionary in world.terrain.blocks:
		var kind := 1
		if b.kind == MapDefs.TOMB:
			kind = 2
		elif b.kind == MapDefs.PLATFORM:
			kind = 3
		var lo := _cell(b.min)
		var hi := _cell(b.max - Vector2(0.01, 0.01))
		for y in range(maxi(lo.y, 0), mini(hi.y, _size.y - 1) + 1):
			for x in range(maxi(lo.x, 0), mini(hi.x, _size.x - 1) + 1):
				_base[y * _size.x + x] = kind
	_img = Image.create_empty(maxi(_size.x, 1), maxi(_size.y, 1), false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 0))
	_mark_edges()
	_tex = ImageTexture.create_from_image(_img)
	_timer = 0.0
	_reveal_cell = Vector2i(-1, -1)


# 場地外 = 從圖的四邊往裡走得到的實心格（中間的牆不算）；外框 = 場地外裡離場地 EDGE_CELLS 格以內的（4 方向），看過才畫（_reveal）
func _mark_edges() -> void:
	var w := _size.x
	var n := _size.x * _size.y
	var outside := PackedByteArray()
	outside.resize(n)
	outside.fill(0)
	var queue := PackedInt32Array()
	for x in w:
		for y: int in [0, _size.y - 1]:
			queue.append(y * w + x)
	for y in _size.y:
		for x: int in [0, w - 1]:
			queue.append(y * w + x)
	# 往裡填實心格；碰到不是實心的鄰居（場地）時，這一格就是外框的第 1 圈
	var ring := PackedInt32Array()
	var border := queue.size()
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		if outside[i] or _base[i] != 1:
			if head <= border and _base[i] != 1:
				ring.append(i)   # 場地碰到圖的邊：那一格自己就是外框
			continue
		outside[i] = 1
		var x := i % w
		var touches := false
		for j: int in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w, i + w]:
			if j < 0 or j >= n:
				continue
			if _base[j] != 1:
				touches = true
			elif not outside[j]:
				queue.append(j)
		if touches:
			ring.append(i)
	_edge.resize(n)
	_edge.fill(0)
	for step in EDGE_CELLS:
		var next := PackedInt32Array()
		for i in ring:
			if _edge[i]:
				continue
			_edge[i] = 1
			if step + 1 < EDGE_CELLS:
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx := i % w + d.x
					var ny := i / w + d.y
					if nx >= 0 and ny >= 0 and nx < w and ny < _size.y and outside[ny * w + nx] and not _edge[ny * w + nx]:
						next.append(ny * w + nx)
		ring = next


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x + world.half_extents.x), floori(p.y + world.half_extents.y))


# 從 center 往四周掃視線，把看得到的格子標成看過、畫進圖；有新的格子回傳 true
# 跟 Terrain.sight_blocked 一樣只有牆擋（墓碑、高台不擋）。牆看得到、牆後面看不到；牆有兩格厚時多畫一格，外框才不會只有一條細線
func _reveal(center: Vector2, r: float) -> bool:
	var rays := ceili(TAU * r * RAYS_PER_CELL)
	var steps := ceili(r / RAY_STEP)
	var start := center + world.half_extents
	var changed := false
	for a in rays:
		var angle := TAU * a / rays
		var d := Vector2(cos(angle), sin(angle)) * RAY_STEP
		var p := start
		var wall := -1   # 視線碰到的第一格牆
		for s in steps + 1:
			var x := floori(p.x)
			var y := floori(p.y)
			p += d
			if x < 0 or y < 0 or x >= _size.x or y >= _size.y:
				break
			var i := y * _size.x + x
			if i == wall:
				continue
			var is_wall := _base[i] == 1 and s > 0
			if not _seen[i] and (wall < 0 or is_wall):
				_seen[i] = 1
				_img.set_pixel(x, y, EDGE if _edge[i] else KIND_COLORS[_base[i]])
				changed = true
			if wall >= 0:
				break
			if is_wall:
				wall = i
	return changed


func is_seen(p: Vector2) -> bool:
	var c := _cell(p)
	return c.x >= 0 and c.y >= 0 and c.x < _size.x and c.y < _size.y and _seen[c.y * _size.x + c.x] == 1


# p 周圍 cells 格內有沒有看過的格子（門嵌在牆裡，視線到不了門本身）
func is_seen_near(p: Vector2, cells: int) -> bool:
	var c := _cell(p)
	for y in range(maxi(c.y - cells, 0), mini(c.y + cells, _size.y - 1) + 1):
		for x in range(maxi(c.x - cells, 0), mini(c.x + cells, _size.x - 1) + 1):
			if _seen[y * _size.x + x] == 1:
				return true
	return false


# 世界座標（模擬層的 x, y）→ 框內座標：轉 45°（相機從 +X+Z 看過去，畫面的右邊是 +x −y）
func _to_view(p: Vector2, focus: Vector2, scale_: float) -> Vector2:
	var d := (p - focus) * scale_
	return VIEW / 2.0 + Vector2(d.x - d.y, d.x + d.y) * (sqrt(0.5))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), FRAME_BG)
	draw_rect(Rect2(Vector2.ZERO, VIEW), FRAME_LINE, false, 2.0)
	if world == null or _tex == null:
		return
	var me: Player = local_player.call()
	# 轉 45° 後整張地圖的外框寬 = (寬 + 高) / √2
	var fit := VIEW.x / ((_size.x + _size.y) * sqrt(0.5))
	var scale_ := maxf(fit, MIN_SCALE)
	var focus := Vector2.ZERO
	if scale_ > fit and me != null:
		focus = me.pos
	var origin := _to_view(-world.half_extents, focus, scale_)
	draw_set_transform(origin, PI / 4.0, Vector2(scale_, scale_))
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, Vector2(_size)), false)
	draw_set_transform(Vector2.ZERO)
	var ev := world.event
	var doors := DigEvent.doors(world)
	for d: Dictionary in doors:
		var at := MapDefs.to_world(world.map, d.at)
		if is_seen_near(at, DOOR_SEEN_CELLS):
			var v := _to_view(at, focus, scale_)
			draw_rect(Rect2(v - Vector2(4, 4), Vector2(8, 8)), DOOR)
	if DigEvent.enabled(world) and is_seen(ev.point):
		_draw_cross(_to_view(ev.point, focus, scale_), DIG)
	for r in world.relics:
		var relic := r as Relic
		if relic.is_removed or not (relic.spotted or is_seen(relic.pos)):
			continue
		var rv := _to_view(relic.pos, focus, scale_)
		if me != null and relic.taken.has(me.peer_id):
			_draw_diamond(rv, 5.0, Color(RELIC, 0.35))
		else:
			_draw_diamond(rv, 7.5, Color.WHITE)
			_draw_diamond(rv, 5.5, RELIC)
	for c in world.chests:
		if not c.is_removed and not (c as Chest).opened and is_seen(c.pos):
			draw_circle(_to_view(c.pos, focus, scale_), 3.0, CHEST)
	var blink_on := fmod(Time.get_ticks_msec() * 0.001 * BLINK_HZ, 1.0) < 0.6
	for p in world.player_list:
		if p == me or p.is_dead:
			continue
		var av := _to_view(p.pos, focus, scale_)
		if p.is_downed:
			draw_circle(av, 6.0 if blink_on else 4.5, DOWNED if blink_on else Color(DOWNED, 0.45))
			var font := get_theme_default_font()
			var secs := str(ceili(p.down_timer))
			draw_string_outline(font, av + Vector2(8, 5), secs, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.85))
			draw_string(font, av + Vector2(8, 5), secs, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, DOWNED)
		else:
			draw_circle(av, 4.0, ALLY)
	if me != null:
		var v := _to_view(me.pos, focus, scale_)
		var f := MathUtil.dir_from_angle(me.view_facing())
		var fwd := Vector2(f.x - f.y, f.x + f.y).normalized()
		var side := Vector2(-fwd.y, fwd.x)
		draw_colored_polygon(PackedVector2Array([v + fwd * 8.0, v - fwd * 5.0 + side * 5.0, v - fwd * 5.0 - side * 5.0]), SELF)


func _draw_cross(v: Vector2, color: Color) -> void:
	draw_line(v - Vector2(5, 5), v + Vector2(5, 5), color, 3.0)
	draw_line(v - Vector2(5, -5), v + Vector2(5, -5), color, 3.0)


func _draw_diamond(v: Vector2, r: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([v + Vector2(0, -r), v + Vector2(r, 0), v + Vector2(0, r), v + Vector2(-r, 0)]), color)
