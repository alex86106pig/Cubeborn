# 視野外出招的提示：他看不到的攻擊再 LEAD 秒內就要打到本機玩家時，在角色周圍朝那個方向畫一道弧，打出去之後就淡掉
# - 小怪本體打人的招（揮砍、撲、滾過來）：照 Enemy.threat_eta（前搖剩多久、骨輪照距離），前搖剛開始不亮
# - 遠程：瞄準時不亮，看射出來的投射物（別人的投射物也會被視野藏起來）：直直飛過來會打中、LEAD 秒內到才亮，弧指著那顆
# 只提示「快打到了」的，不提示「在那裡」的（不然等於把視野限制取消）；Boss 不提示。設定頁「玩法（測試）」可以關
class_name ThreatMarks
extends Control

const RANGE := 22.0          # 離這麼遠以內的才提示（比視野 18 遠一點：遠程在視野外緣瞄準）
const RADIUS := 130.0        # 弧離角色在畫面上的位置多遠（像素）
const HALF_ARC := 0.32       # 弧的半寬（弧度）
const WIDTH := 7.0
const FADE := 8.0            # 每秒淡入 / 淡出多少（1 / FADE 秒到位）
const COLOR := Color(1.0, 0.36, 0.2)
const CHEST := 0.9           # 角色胸口的高度（弧以這裡為中心）
const LEAD := 0.4            # 再過幾秒就打到才亮（看到後還來得及翻滾；翻滾的無敵從按下就開始）
const AFTER := 0.3           # 打出去之後再亮多久（撲、衝刺那一段還在往前）
const MISS_MARGIN := 0.6     # 投射物直線飛過、離玩家身體邊緣這麼近以內算會打中

var world: World
var camera: Camera3D
var local_peer := World.HOST_PEER_ID
var settings: SettingsPanel          # 有給就照設定頁的 threat_marks 開關
var _alpha: Dictionary = {}          # 怪的 id → 目前的顯示程度 0~1
var _dir: Dictionary = {}            # 怪的 id → 最後一次的方向（淡出時沿用）
var _shot_pos: Dictionary = {}       # 客戶端：投射物 id → 上一幀的位置（快照沒有帶速度，用位置估）
var _shot_speed: Dictionary = {}     # 客戶端：投射物 id → 估出來的速度
var _time := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# 現在要提示的：[{ id, dir }]，id 是怪或投射物，dir 是模擬座標裡從玩家指向它的單位向量。
# shot_speed：投射物 id → 速度（客戶端估的；房主用投射物自己的 speed）
static func threats(w: World, me: Player, shot_speed := {}) -> Array[Dictionary]:
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
		var eta := e.threat_eta(me.pos)
		if eta > LEAD or eta < -AFTER or Vision.entity_visible(w, me, e):
			continue
		out.append({"id": e.id, "dir": d.normalized()})
	for x in w.projectiles:
		var pr := x as Projectile
		if pr == null or pr.is_removed or pr.team == me.team:
			continue
		var d := pr.pos - me.pos
		if d.length() > RANGE or d.length_squared() < 1e-6:
			continue
		var speed: float = pr.speed if pr.speed > 0.0 else shot_speed.get(pr.id, 0.0)
		if shot_eta(me, pr, speed) > LEAD or Vision.entity_visible(w, me, pr):
			continue
		out.append({"id": pr.id, "dir": d.normalized()})
	return out


# 投射物照現在的方向直線飛，再幾秒打到 me；飛離、會偏過去、或不知道速度回傳 INF（追蹤彈也照直線估）
static func shot_eta(me: Player, pr: Projectile, speed: float) -> float:
	if speed <= 0.0:
		return INF
	var dir := MathUtil.dir_from_angle(pr.facing)
	var r := me.pos - pr.pos
	var along := r.dot(dir)
	if along < 0.0 or (r - dir * along).length() > me.radius + pr.radius + MISS_MARGIN:
		return INF
	return maxf(0.0, along - me.radius - pr.radius) / speed


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
	_track_shots(delta)
	if is_on():
		for t in threats(world, me, _shot_speed):
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


# 客戶端的投射物沒有速度（快照只帶位置與方向）：照這一幀與上一幀的位置估，平滑一半
func _track_shots(delta: float) -> void:
	if world == null or world.is_authority or delta <= 0.0:
		return
	var seen := {}
	for x in world.projectiles:
		var pr := x as Projectile
		if pr == null:
			continue
		seen[pr.id] = true
		if _shot_pos.has(pr.id):
			var v: float = pr.pos.distance_to(_shot_pos[pr.id]) / delta
			_shot_speed[pr.id] = lerpf(_shot_speed.get(pr.id, v), v, 0.5)
		_shot_pos[pr.id] = pr.pos
	for id: int in _shot_pos.keys():
		if not seen.has(id):
			_shot_pos.erase(id)
			_shot_speed.erase(id)


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
