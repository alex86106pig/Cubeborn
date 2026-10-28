# 挖墳事件（規格見 docs/系統說明.md §15；數值在 defs/event_defs.gd）
# Boss 開局就在挖墳點巡邏（spawn_boss）。有人在挖墳點按住 F（玩家動作 dig）就累積進度，第一下開始事件：
# 怪潮（玩家周圍冒怪）與挖墳點噴怪同時開始、難度往上加；每次噴怪進度 +10%；沒人挖時進度不掉
# 挖完（OPEN）停止生怪、難度不再漲，場上的怪留著；再到墳墓按 F：單人直接走，多人發起投票（全員同意或時間到就走，有人反對就取消）
# 只有地圖資料 "dig_event": true 的地圖才有（測試場地照舊用波次）；不持有 World，每次呼叫時傳入；只在權威端更新
class_name DigEvent
extends RefCounted

const IDLE := &"idle"       # 還沒人挖
const ACTIVE := &"active"   # 事件進行中（挖墳中或沒人挖）
const OPEN := &"open"       # 挖完：不再生怪，等玩家到墳墓互動

var state := IDLE
var progress := 0.0         # 0~1
var horde := false          # 正在生怪（事件進行中；挖完就停）
var time := 0.0             # 事件開始後的秒數（難度用；挖完就停）
var point := Vector2.ZERO   # 挖墳點（世界座標）
var spawn_timer := 0.0
var erupt_timer := 0.0      # 距離下一次噴怪的秒數
var _erupt_warned := false
var _boss_placed := false   # 這一層的 Boss 放了沒（第一步才放：--no-spawn 與檢查在 reset 之後才設 spawner.finished）
# 投票（OPEN 後；快照同步給客戶端畫面用）
var vote_by := 0            # 發起投票的 peer id（0 = 沒有投票）
var vote_left := 0.0        # 剩餘秒數
var vote_yes: Array[int] = []   # 同意的 peer id（含發起人）


func reset(world: World) -> void:
	state = IDLE
	progress = 0.0
	horde = false
	time = 0.0
	spawn_timer = 0.0
	erupt_timer = 0.0
	_erupt_warned = false
	_boss_placed = false
	_clear_vote()
	point = MapDefs.to_world(world.map, world.map.dig)


static func enabled(world: World) -> bool:
	return world.map.get("dig_event", false)


func difficulty(world: World) -> float:
	return world.base_difficulty + time * EventDefs.DIFFICULTY.per_second * EventDefs.MODES[world.difficulty_mode].rate


# 玩家站得到這裡挖嗎（出口打開後就不能再挖）
func can_dig(world: World, p: Player) -> bool:
	return enabled(world) and state != OPEN and p.pos.distance_to(point) <= EventDefs.DIG.range


# 挖完後站在墳墓旁按 F：前往下一層（或通關）
func can_exit(world: World, p: Player) -> bool:
	return enabled(world) and state == OPEN and p.pos.distance_to(point) <= EventDefs.DIG.range


func is_voting() -> bool:
	return vote_by != 0


# 投票中、這位玩家還沒同意（畫面顯示 Enter / Esc 提示、輸入攔下 Esc 用）
func awaits_vote(peer_id: int) -> bool:
	return is_voting() and not vote_yes.has(peer_id)


# 挖完一層要的總量：每位活著（含倒地）的玩家 DIG.time 秒
func dig_total(world: World) -> float:
	var n := 0
	for p in world.player_list:
		if not p.is_dead:
			n += 1
	return EventDefs.DIG.time * maxi(1, n)


# 開局（每一層）就放在挖墳點：在 map.boss_room 裡巡邏，看到玩家才追；--no-spawn 不放
func spawn_boss(world: World) -> void:
	if world.spawner.finished:
		return
	var type: StringName = EventDefs.DIG.boss_type
	var at := world.nav_for(EnemyDefs.ENEMIES[type].radius).nearest_walkable(point)
	var boss := world.spawner.spawn_at(world, type, at, {"initial_state": &"patrol"}) as Boss
	var room: Array = world.map.get("boss_room", [])
	if not room.is_empty():
		var lo := MapDefs.to_world(world.map, Vector2(room[0], room[1]))
		boss.patrol_rect = Rect2(lo, Vector2(room[2], room[3]))


func update(world: World, dt: float) -> void:
	if not enabled(world):
		return
	if not _boss_placed:
		_boss_placed = true
		spawn_boss(world)
	var diggers := 0.0   # 挖墳速度的合計：一人 1；掘墓人被動 +40%（F9）
	for p in world.player_list:
		if p.is_digging():
			diggers += p.class_passive("dig_speed", 1.0)
	if diggers > 0 and state == IDLE:
		_start(world)
	if state == ACTIVE:
		if diggers > 0:
			progress += diggers * dt / dig_total(world)
		else:
			progress -= EventDefs.DIG.decay * dt
		time += dt
		_spawn(world, dt)
		_erupt(world, dt)
		progress = clampf(progress, 0.0, 1.0)
		if progress >= 1.0 - 1e-6:
			_open(world)
	elif state == OPEN:
		_update_vote(world, dt)


func _start(world: World) -> void:
	state = ACTIVE
	horde = true
	spawn_timer = EventDefs.SPAWN.interval_start
	erupt_timer = EventDefs.ERUPT.interval
	world.emit_event("event:started", {"pos": point})


func _open(world: World) -> void:
	progress = 1.0
	state = OPEN
	horde = false
	world.emit_event("event:exit_open", {"pos": point})
	world.emit_event("sfx:cue", {"cue": "victory"})


func _living_targets(world: World) -> Array[Player]:
	var targets: Array[Player] = []
	for p in world.player_list:
		if p.is_targetable():
			targets.append(p)
	return targets


func _alive_event_enemies(world: World) -> int:
	var alive := 0
	for e in world.enemies:
		if not e.is_dead and e is Enemy and (e as Enemy).wave_member:
			alive += 1
	return alive


# 怪潮：每 interval 秒在一位活著的玩家周圍冒一批（同 Spawner._around_player 的距離），稀有度依難度
func _spawn(world: World, dt: float) -> void:
	if world.spawner.finished:
		return
	spawn_timer -= dt
	if spawn_timer > 0.0:
		return
	var d := difficulty(world)
	spawn_timer = EventDefs.spawn_interval(d)
	var targets := _living_targets(world)
	if targets.is_empty():
		return
	var n := mini(EventDefs.group_size(d, world.player_list.size()), EventDefs.SPAWN.max_alive - _alive_event_enemies(world))
	var target := targets[world.rng.randi_range(0, targets.size() - 1)]
	for i in n:
		var type := _roll_type(world)
		var e := world.spawner.spawn_at(world, type, Spawner._around_player(world, type, target.pos))
		e.wave_member = true
		Spawner.roll_rarity(world, e, EventDefs.roll_rarity(d, world.rng))


func _roll_type(world: World) -> StringName:
	return &"archer" if world.rng.randf() < EventDefs.SPAWN.archer_ratio else &"grunt"


# 挖墳點噴怪：倒數到 warning 秒時墳土開始隆起（fx:erupt_warn），到 0 時噴出下一層的怪、進度 +ERUPT.progress（--no-spawn 只加進度）
func _erupt(world: World, dt: float) -> void:
	var c: Dictionary = EventDefs.ERUPT
	erupt_timer -= dt
	if not _erupt_warned and erupt_timer <= c.warning:
		_erupt_warned = true
		if not world.spawner.finished:
			world.emit_event("fx:erupt_warn", {"pos": point, "height": world.terrain.ground_at(point), "radius": c.radius, "life": c.warning})
	if erupt_timer > 0.0:
		return
	erupt_timer += c.interval
	_erupt_warned = false
	progress += c.progress
	world.emit_event("event:erupted", {"pos": point})
	if world.spawner.finished:
		return
	world.emit_event("camera:shake", {"amount": c.shake, "duration": c.shake_duration})
	var rise := difficulty(world) - world.base_difficulty
	var d := difficulty(world) + EventDefs.DIFFICULTY.per_floor   # 下一層的怪
	var n := mini(EventDefs.erupt_count(rise, world.player_list.size()), EventDefs.SPAWN.max_alive - _alive_event_enemies(world))
	for i in n:
		var type := _roll_type(world)
		var nav := world.nav_for(EnemyDefs.ENEMIES[type].radius)
		var a := world.rng.randf() * TAU
		var r: float = world.rng.randf_range(c.land_distance[0], c.land_distance[1])
		var to := nav.nearest_walkable(point + Vector2(sin(a), cos(a)) * r)
		var e := world.spawner.spawn_at(world, type, point, {"difficulty": d, "initial_state": &"launch"})
		e.launch_to(to, c.flight_time)
		e.wave_member = true
		Spawner.roll_rarity(world, e, EventDefs.roll_rarity(d, world.rng))


# ───────── 前往下一層 ─────────

# 玩家在墳墓旁按 F（權威端）：單人直接走；多人發起投票（投票中按 F 算同意）
func request_exit(world: World, p: Player) -> void:
	if not can_exit(world, p):
		return
	if not is_voting():
		vote_by = p.peer_id
		vote_left = EventDefs.VOTE.time
		vote_yes.assign([p.peer_id])
		if world.player_list.size() > 1:   # 單人不必投票（下面立刻通過）
			world.emit_event("vote:started", {"player_id": p.id, "peer_id": p.peer_id, "time": vote_left})
	else:
		cast_vote(world, p, true)
		return
	_check_vote(world)


# Enter 同意 / Esc 反對（權威端）；不在投票中、已經同意過的不算
func cast_vote(world: World, p: Player, agree: bool) -> void:
	if not is_voting() or p.is_dead or vote_yes.has(p.peer_id):
		return
	if not agree:
		world.emit_event("vote:canceled", {"player_id": p.id, "peer_id": p.peer_id})
		_clear_vote()
		return
	vote_yes.append(p.peer_id)
	world.emit_event("vote:agreed", {"player_id": p.id, "peer_id": p.peer_id})
	_check_vote(world)


func _update_vote(world: World, dt: float) -> void:
	if not is_voting():
		return
	vote_left -= dt
	if vote_left <= 0.0:
		_proceed(world)
		return
	_check_vote(world)


# 還沒死的玩家全部同意就走（死掉的不用投；中途有人死掉也重新算）
func _check_vote(world: World) -> void:
	for q in world.player_list:
		if not q.is_dead and not vote_yes.has(q.peer_id):
			return
	_proceed(world)


func _proceed(world: World) -> void:
	_clear_vote()
	world.emit_event("vote:passed", {})
	if world.floor_num >= EventDefs.DIG.last_floor:
		world.win()
	else:
		world.next_floor()


func _clear_vote() -> void:
	vote_by = 0
	vote_left = 0.0
	vote_yes.clear()
