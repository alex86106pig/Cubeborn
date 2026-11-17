# 視野外出招的提示：以本機玩家為目標、他看不到的小怪正在出招（前搖、瞄準到出手）時，在角色周圍朝那個方向畫一道弧，招式結束就淡掉
# 只提示「正在出招」的，不提示「在那裡」的（不然等於把視野限制取消）；Boss 不提示。設定頁「玩法（測試）」可以關
class_name ThreatMarks
extends Control

const RANGE := 22.0          # 離這麼遠以內的才提示（比視野 18 遠一點：遠程在視野外緣瞄準）
const RADIUS := 130.0        # 弧離角色在畫面上的位置多遠（像素）
const HALF_ARC := 0.32       # 弧的半寬（弧度）
const WIDTH := 7.0
const FADE := 8.0            # 每秒淡入 / 淡出多少（1 / FADE 秒到位）
const COLOR := Color(1.0, 0.36, 0.2)
const CHEST := 0.9           # 角色胸口的高度（弧以這裡為中心）

var world: World
var camera: Camera3D
var local_peer := World.HOST_PEER_ID
var settings: SettingsPanel          # 有給就照設定頁的 threat_marks 開關
var _alpha: Dictionary = {}          # 怪的 id → 目前的顯示程度 0~1
var _dir: Dictionary = {}            # 怪的 id → 最後一次的方向（淡出時沿用）
var _time := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# 現在要提示的：[{ id, dir }]，dir 是模擬座標裡從玩家指向那隻怪的單位向量
static func threats(w: World, me: Player) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if w == null or me == null or me.is_dead or me.is_downed:
		return out
	for x in w.enemies:
		var e := x as Enemy
		if e == null or e.is_dead or e.is_removed or e.team == me.team:
			continue
		if not e.attack_states().has(e.anim.get("state", &"")):
			continue
		var d := e.pos - me.pos
		if d.length() > RANGE or d.length_squared() < 1e-6 or not aimed_at(w, e, me):
			continue
		if Vision.entity_visible(w, me, e):
			continue
		out.append({"id": e.id, "dir": d.normalized()})
	return out


# 這隻怪這次出招是不是對著 me：房主照出招時記下的目標；客戶端沒有這個資料，用「離牠最近的玩家是不是我」
static func aimed_at(w: World, e: Enemy, me: Player) -> bool:
	if w.is_authority and e.attack_target_id != 0:
		return e.attack_target_id == me.id
	var mine := e.pos.distance_squared_to(me.pos)
	for peer: int in w.players:
		var o: Player = w.players[peer]
		if o != me and not o.is_dead and not o.is_downed and e.pos.distance_squared_to(o.pos) < mine:
			return false
	return true


func is_on() -> bool:
	return settings == null or settings.values.get("threat_marks", true)


func _process(delta: float) -> void:
	_time += delta
	var me: Player = world.players.get(local_peer) if world != null else null
	var live := {}
	if is_on():
		for t in threats(world, me):
			live[t.id] = true
			_dir[t.id] = t.dir
	for id: int in live:
		_alpha[id] = minf(1.0, _alpha.get(id, 0.0) + delta * FADE)
	for id: int in _alpha.keys():
		if not live.has(id):
			_alpha[id] -= delta * FADE
			if _alpha[id] <= 0.0:
				_alpha.erase(id)
				_dir.erase(id)
	queue_redraw()


func _draw() -> void:
	var me: Player = world.players.get(local_peer) if world != null else null
	if me == null or camera == null or _alpha.is_empty():
		return
	var chest := WorldView.render_pos(me, CHEST)
	var center := camera.unproject_position(chest)
	var pulse := 0.75 + 0.25 * sin(_time * 14.0)
	for id: int in _alpha:
		var dir: Vector2 = _dir[id]
		var s := camera.unproject_position(chest + Vector3(dir.x, 0.0, dir.y) * 2.0) - center
		if s.length_squared() < 1e-6:
			continue
		var a := s.angle()
		draw_arc(center, RADIUS, a - HALF_ARC, a + HALF_ARC, 14, Color(0, 0, 0, 0.45 * _alpha[id]), WIDTH + 4.0, true)
		draw_arc(center, RADIUS, a - HALF_ARC, a + HALF_ARC, 14, Color(COLOR, _alpha[id] * pulse), WIDTH, true)
