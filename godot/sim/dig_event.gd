# 挖墳事件（D6，規格見 docs/系統說明.md §15；數值在 defs/event_defs.gd）
# 有人在挖墳點按住 F（玩家動作 dig）就累積進度，第一下開始事件：先只有 Boss 出現；Boss 倒下後怪潮才開始（怪物依難度不斷冒出、
# 難度從這時起往上加）；沒人挖時進度慢慢掉（使用者 2026-10-25：原本 Boss 與怪潮同時來，怪太多沒空打 Boss、更沒空挖）
# 挖完墓穴變成出口：活著的玩家走進去就「下去」（descended），全部下去（沒有倒地的人）就 World.next_floor()
# 只有地圖資料 "dig_event": true 的地圖才有（測試場地照舊用波次）；不持有 World，每次呼叫時傳入；只在權威端更新
class_name DigEvent
extends RefCounted

const IDLE := &"idle"       # 還沒人挖
const ACTIVE := &"active"   # 事件進行中（挖墳中或沒人挖）
const OPEN := &"open"       # 挖完，出口打開（事件照常進行、難度照樣上升）

var state := IDLE
var progress := 0.0         # 0~1
var horde := false          # 怪潮開始了沒（Boss 倒下後；沒有 Boss 時事件一開始就是）
var time := 0.0             # 怪潮開始後的秒數（難度用）
var point := Vector2.ZERO   # 挖墳點（世界座標）
var spawn_timer := 0.0
var _boss_id := 0           # 事件叫出來的 Boss


func reset(world: World) -> void:
	state = IDLE
	progress = 0.0
	horde = false
	time = 0.0
	spawn_timer = 0.0
	_boss_id = 0
	point = MapDefs.to_world(world.map, world.map.dig)


static func enabled(world: World) -> bool:
	return world.map.get("dig_event", false)


func difficulty(world: World) -> float:
	return world.base_difficulty + time * EventDefs.DIFFICULTY.per_second * EventDefs.MODES[world.difficulty_mode].rate


# 玩家站得到這裡挖嗎（出口打開後就不能再挖）
func can_dig(world: World, p: Player) -> bool:
	return enabled(world) and state != OPEN and p.pos.distance_to(point) <= EventDefs.DIG.range


func update(world: World, dt: float) -> void:
	if not enabled(world):
		return
	var diggers := 0.0   # 挖墳速度的合計：一人 1；掘墓人被動 +40%（F9）
	for p in world.player_list:
		if p.is_digging():
			diggers += p.class_passive("dig_speed", 1.0)
	if diggers > 0 and state == IDLE:
		_start(world)
	if state == ACTIVE:
		if diggers > 0:
			progress = minf(1.0, progress + diggers * dt / EventDefs.DIG.time)
		else:
			progress = maxf(0.0, progress - EventDefs.DIG.decay * dt)
		if progress >= 1.0 - 1e-6:
			progress = 1.0
			state = OPEN
			world.emit_event("event:exit_open", {"pos": point})
			world.emit_event("sfx:cue", {"cue": "victory"})
	if state == IDLE:
		return
	if not horde:
		var boss: Entity = world.entities.get(_boss_id)
		if boss == null or boss.is_dead:
			horde = true
			spawn_timer = EventDefs.SPAWN.interval_start
			world.emit_event("event:horde", {"pos": point, "after_boss": _boss_id != 0})
	if horde:
		time += dt
		_spawn(world, dt)
	if state == OPEN:
		_update_descend(world)


func _start(world: World) -> void:
	state = ACTIVE
	world.emit_event("event:started", {"pos": point})
	if world.spawner.finished:   # --no-spawn：只挖墳、不生怪（沒有 Boss，下一步就算怪潮開始，但照樣不生怪）
		return
	var nav := world.nav_for(EnemyDefs.ENEMIES.boss.radius)
	var at := point
	for attempt in 12:
		var a := world.rng.randf() * TAU
		var c := nav.nearest_walkable(point + Vector2(sin(a), cos(a)) * EventDefs.DIG.boss_distance)
		if nav.is_walkable(c) and nav.same_region(c, point):
			at = c
			break
	_boss_id = world.spawner.spawn_at(world, EventDefs.DIG.boss_type, at).id


# 每 interval 秒在一位活著的玩家周圍冒一批（同 Spawner._around_player 的距離），稀有度依難度
func _spawn(world: World, dt: float) -> void:
	if world.spawner.finished:
		return
	spawn_timer -= dt
	if spawn_timer > 0.0:
		return
	var d := difficulty(world)
	spawn_timer = EventDefs.spawn_interval(d)
	var targets: Array[Player] = []
	for p in world.player_list:
		if p.is_targetable():
			targets.append(p)
	if targets.is_empty():
		return
	var alive := 0
	for e in world.enemies:
		if not e.is_dead and e is Enemy and (e as Enemy).wave_member:
			alive += 1
	var n := mini(EventDefs.group_size(d, world.player_list.size()), EventDefs.SPAWN.max_alive - alive)
	var target := targets[world.rng.randi_range(0, targets.size() - 1)]
	for i in n:
		var type := &"archer" if world.rng.randf() < EventDefs.SPAWN.archer_ratio else &"grunt"
		var e := world.spawner.spawn_at(world, type, Spawner._around_player(world, type, target.pos))
		e.wave_member = true
		Spawner.roll_rarity(world, e, EventDefs.roll_rarity(d, world.rng))


func _update_descend(world: World) -> void:
	var r: float = EventDefs.DIG.exit_radius
	var standing := 0
	var down := 0
	for p in world.player_list:
		if p.is_dead:
			continue
		if p.is_downed:
			standing += 1
			continue
		standing += 1
		if not p.descended and p.pos.distance_to(point) <= r:
			p.descend()
		if p.descended:
			down += 1
	if standing > 0 and down == standing:
		world.next_floor()
