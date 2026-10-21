# 模擬核心：持有所有實體、CD、隨機數與事件，step() 推進一個固定步（只在權威端執行）
class_name World
extends RefCounted

const HOST_PEER_ID := 1   # 房主；單機時唯一的玩家也是 1
const TIME_EPSILON := 1e-6

var tick := 0
var rng := RandomNumberGenerator.new()
var cooldowns := CooldownManager.new()
var events: Array[Dictionary] = []   # 本步事件，只放 id 與數值，才能透過網路傳送
var entities: Dictionary = {}        # id -> Entity
var players: Dictionary = {}         # peer_id -> Player
var enemies: Array[Entity] = []
var projectiles: Array[Entity] = []
var stats := {"wave": 0, "kills": 0, "time": 0.0}
var is_over := false                 # 通關後為 true
var hit_stop_timer := 0.0            # 剩餘的命中停頓（真實秒數），由主迴圈換算成時間縮放
var arena_half_size: float = Config.WORLD.arena_half_size

var _next_id := 1
var _bodies: Array[Entity] = []


func reset(seed_value: int, peer_ids: Array[int] = [HOST_PEER_ID]) -> void:
	clear()
	tick = 0
	rng.seed = seed_value
	cooldowns.reset_all()
	stats = {"wave": 0, "kills": 0, "time": 0.0}
	is_over = false
	hit_stop_timer = 0.0
	_next_id = 1
	for peer_id in peer_ids:
		add_entity(Player.new(self, peer_id))
	emit_event("game:restart", {})


# 實體與 World 互相參照（RefCounted 循環），移除時必須 detach() 才會釋放
func clear() -> void:
	for e: Entity in entities.values():
		e.detach()
	events.clear()
	entities.clear()
	players.clear()
	enemies.clear()
	projectiles.clear()


func add_entity(e: Entity) -> Entity:
	e.id = _next_id
	_next_id += 1
	e.prev_pos = e.pos
	e.prev_facing = e.facing
	entities[e.id] = e
	if e is Player:
		players[e.peer_id] = e
	return e


# 投射物在玩家 / 敵人更新途中產生，同一步就會接著被更新（同網頁版）
func spawn_projectile(p: Projectile) -> Projectile:
	add_entity(p)
	projectiles.append(p)
	return p


# payload 的 "name" 欄位保留給事件名稱（例如 sfx:cue 的音效名稱放在 "cue"）
func emit_event(name: String, payload: Dictionary) -> void:
	assert(not payload.has("name"), "payload 的 name 欄位保留給事件名稱：%s" % name)
	payload["name"] = name
	events.append(payload)


func hit_stop(duration: float) -> void:
	hit_stop_timer = maxf(hit_stop_timer, duration)


# 主迴圈每個真實固定步呼叫一次：回傳這段時間的邏輯時間縮放
func consume_hit_stop(real_dt: float) -> float:
	if hit_stop_timer <= TIME_EPSILON:   # 浮點殘差（例如 0.1 - 6/60）不算多停一步
		return 1.0
	hit_stop_timer -= real_dt
	return Config.HIT_STOP_TIME_SCALE


func is_any_player_alive() -> bool:
	for p: Player in players.values():
		if not p.is_dead:
			return true
	return false


# cmds：peer_id -> InputCmd；沒送輸入的玩家沿用上一步的輸入
func step(cmds: Dictionary, dt: float) -> void:
	events.clear()
	tick += 1
	for e: Entity in entities.values():
		e.prev_pos = e.pos
		e.prev_facing = e.facing

	cooldowns.tick(dt)

	for peer_id: int in players:
		var p: Player = players[peer_id]
		if cmds.has(peer_id):
			p.apply_cmd(cmds[peer_id])
		p.update(dt)
	for e in enemies:
		e.update(dt)
	for e in projectiles:
		e.update(dt)

	_bodies.clear()
	for p: Player in players.values():
		_bodies.append(p)
	_bodies.append_array(enemies)
	for b in _bodies:
		b.integrate(dt)
	SimPhysics.separate(_bodies, rng)
	for b in _bodies:
		SimPhysics.clamp_to_arena(b, arena_half_size)
	_bodies.clear()   # 不留參照，已移除的實體才能立即釋放

	_remove_dead_entities()
	if not is_over and is_any_player_alive():
		stats.time += dt


func _remove_dead_entities() -> void:
	for id: int in entities.keys():
		var e: Entity = entities[id]
		if e.is_removed:
			e.detach()
			entities.erase(id)
			if e is Player:
				players.erase(e.peer_id)
	enemies.assign(enemies.filter(func(e: Entity) -> bool: return not e.is_removed))
	projectiles.assign(projectiles.filter(func(e: Entity) -> bool: return not e.is_removed))
