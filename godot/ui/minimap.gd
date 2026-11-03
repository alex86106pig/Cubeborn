# 右上角的小地圖：只畫本機玩家走過、看過的地方（視野距離內一圈，不管牆），轉 45° 跟畫面的方向一致；
# 地形一格 1 單位畫成一個像素（地面 / 牆與實心 / 墓碑 / 高台），上面標自己（含面向）、隊友、出口的門 / 挖墳點、遺物（含鐵砧）、沒開的寶箱
# 地圖放得進框就整張置中，放不進就以自己為中心（框外裁掉）；換地圖（World.layout_key 變了）清掉走過的紀錄
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
const SELF := Color("ffffff")
const ALLY := Color("7fe3ff")
const DOOR := Color("8fd0ff")
const DIG := Color("ffd84a")
const RELIC := Color("c88cff")
const CHEST := Color("e0b050")

var world: World
var local_player: Callable   # 回傳 Player（可能是 null），HUD 給

var _key := []
var _size := Vector2i.ZERO
var _base := PackedByteArray()   # 每格的地形種類：0 地面、1 實心、2 墓碑、3 高台
var _seen := PackedByteArray()
var _img: Image
var _tex: ImageTexture
var _timer := 0.0


func _init() -> void:
	custom_minimum_size = VIEW
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if is_visible_in_tree():
		refresh(delta)
		queue_redraw()


# 換地圖就重畫、每 REVEAL_INTERVAL 秒把本機玩家視野距離內標成看過
func refresh(delta: float) -> void:
	if world == null:
		return
	if world.layout_key != _key:
		_rebuild()
	_timer -= delta
	if _timer <= 0.0:
		_timer = REVEAL_INTERVAL
		var me: Player = local_player.call()
		if me != null and _reveal(me.pos, Vision.view_range(me)):
			_tex.update(_img)


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
	_tex = ImageTexture.create_from_image(_img)
	_timer = 0.0


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x + world.half_extents.x), floori(p.y + world.half_extents.y))


# 把 center 周圍 r 內的格子標成看過、畫進圖；有新的格子回傳 true
func _reveal(center: Vector2, r: float) -> bool:
	var c := _cell(center)
	var ri := ceili(r)
	var r2 := r * r
	var changed := false
	for y in range(maxi(c.y - ri, 0), mini(c.y + ri, _size.y - 1) + 1):
		for x in range(maxi(c.x - ri, 0), mini(c.x + ri, _size.x - 1) + 1):
			var i := y * _size.x + x
			if _seen[i] or float((x - c.x) * (x - c.x) + (y - c.y) * (y - c.y)) > r2:
				continue
			_seen[i] = 1
			_img.set_pixel(x, y, [FLOOR, SOLID, TOMB, PLATFORM][_base[i]])
			changed = true
	return changed


func is_seen(p: Vector2) -> bool:
	var c := _cell(p)
	return c.x >= 0 and c.y >= 0 and c.x < _size.x and c.y < _size.y and _seen[c.y * _size.x + c.x] == 1


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
		if is_seen(at):
			var v := _to_view(at, focus, scale_)
			draw_rect(Rect2(v - Vector2(4, 4), Vector2(8, 8)), DOOR)
	if DigEvent.enabled(world) and is_seen(ev.point):
		_draw_cross(_to_view(ev.point, focus, scale_), DIG)
	for r in world.relics:
		if not r.is_removed and is_seen(r.pos):
			_draw_diamond(_to_view(r.pos, focus, scale_), 5.0, RELIC)
	for c in world.chests:
		if not c.is_removed and not (c as Chest).opened and is_seen(c.pos):
			draw_circle(_to_view(c.pos, focus, scale_), 3.0, CHEST)
	for p in world.player_list:
		if p != me and not p.is_dead:
			draw_circle(_to_view(p.pos, focus, scale_), 4.0, ALLY)
	if me != null:
		var v := _to_view(me.pos, focus, scale_)
		var f := Vector2.from_angle(me.view_facing())
		var fwd := Vector2(f.x - f.y, f.x + f.y).normalized()
		var side := Vector2(-fwd.y, fwd.x)
		draw_colored_polygon(PackedVector2Array([v + fwd * 8.0, v - fwd * 5.0 + side * 5.0, v - fwd * 5.0 - side * 5.0]), SELF)


func _draw_cross(v: Vector2, color: Color) -> void:
	draw_line(v - Vector2(5, 5), v + Vector2(5, 5), color, 3.0)
	draw_line(v - Vector2(5, -5), v + Vector2(5, -5), color, 3.0)


func _draw_diamond(v: Vector2, r: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([v + Vector2(0, -r), v + Vector2(r, 0), v + Vector2(0, r), v + Vector2(-r, 0)]), color)
