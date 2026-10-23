# 模擬核心：持有所有實體、CD、隨機數與事件，step() 推進一個固定步（只在權威端執行）
class_name World
extends RefCounted

const HOST_PEER_ID := 1   # 房主；單機時唯一的玩家也是 1
const TIME_EPSILON := 1e-6

var tick := 0
var rng := RandomNumberGenerator.new()
var cooldowns := CooldownManager.new()
var events: Array[Dictionary] = []   # 本步事件，只放 id 與數值，才能透過網路傳送
var hitboxes: Array[Dictionary] = [] # 本步出現的攻擊判定（sim/hitbox.gd 記錄；畫面層 F2 顯示用，不影響模擬）
var entities: Dictionary = {}        # id -> Entity
var players: Dictionary = {}         # peer_id -> Player
var enemies: Array[Entity] = []
var projectiles: Array[Entity] = []
var stats := {"wave": 0, "kills": 0, "time": 0.0}
var is_over := false                 # 通關後為 true
var hit_stop_timer := 0.0            # 剩餘的整體放慢（真實秒數），由主迴圈換算成時間縮放；v0.18.3 起只有打倒 Boss 時使用（一般命中改成畫面定格）
# 地圖（D1，defs/map_defs.gd）：場地大小、地形、尋路格子、出生點；房主與客戶端用同一張（目前固定 Config.WORLD.default_map）
var map_id: StringName
var map: Dictionary
var half_extents := Vector2.ZERO     # 場地的一半大小（世界原點在中央）
var terrain: Terrain
var nav: Nav                         # 小怪用的尋路格子；Boss 用 nav_large（nav_for 依半徑選）
var nav_large: Nav
var spawn_point := Vector2.ZERO
var spawner := Spawner.new()
var boss_id := 0                     # 目前的 Boss（0 = 沒有），HUD 的 Boss 血條用
var victory_timer := 0.0
var is_defeated := false             # 全員倒下（已發出 game:defeat）
# 連線（15.18）：房主 / 單機為權威端；客戶端的 World 只是快照的鏡像，加上本機預測自己的角色（不扣血、不產生實體）
var is_authority := true
var run_id := 0                      # 每次 reset 加 1：客戶端靠它知道房主重新開始了
# 正在更新哪位玩家（peer id；0 = 不是玩家的動作）：這段期間的事件標上 actor，客戶端丟掉自己已經預測播過的
var event_actor := 0

var _next_id := 1
var _bodies: Array[Entity] = []


func _init(p_map_id: StringName = Config.WORLD.default_map) -> void:
	load_map(p_map_id)


func load_map(p_map_id: StringName) -> void:
	map_id = p_map_id
	map = MapDefs.get_map(p_map_id)
	half_extents = (map.size as Vector2) / 2.0
	terrain = Terrain.new(MapDefs.world_blocks(map))
	nav = Nav.new(terrain, half_extents, Config.NAV.margin)
	nav_large = Nav.new(terrain, half_extents, Config.NAV.margin_large)
	spawn_point = MapDefs.to_world(map, map.spawn)


func nav_for(radius: float) -> Nav:
	return nav_large if radius > Config.NAV.large_radius else nav


func reset(seed_value: int, peer_ids: Array[int] = [HOST_PEER_ID]) -> void:
	clear()
	tick = 0
	rng.seed = seed_value
	cooldowns.reset_all()
	stats = {"wave": 0, "kills": 0, "time": 0.0}
	is_over = false
	hit_stop_timer = 0.0
	boss_id = 0
	victory_timer = 0.0
	is_defeated = false
	event_actor = 0
	run_id += 1
	spawner.reset()
	_next_id = 1
	for peer_id in peer_ids:
		var p := Player.new(self, peer_id)
		p.pos = spawn_point
		p.height = terrain.ground_at(spawn_point)
		add_entity(p)
	emit_event("game:restart", {})


# 實體與 World 互相參照（RefCounted 循環），移除時必須 detach() 才會釋放
func clear() -> void:
	for e: Entity in entities.values():
		e.detach()
	events.clear()
	hitboxes.clear()
	entities.clear()
	players.clear()
	enemies.clear()
	projectiles.clear()


func add_entity(e: Entity) -> Entity:
	return add_entity_with_id(e, _next_id)


# 客戶端的鏡像實體沿用房主給的 id（_next_id 只在權威端遞增）
func add_entity_with_id(e: Entity, p_id: int) -> Entity:
	e.id = p_id
	_next_id = maxi(_next_id, p_id + 1)
	e.prev_pos = e.pos
	e.prev_facing = e.facing
	e.prev_height = e.height
	entities[e.id] = e
	if e is Player:
		players[e.peer_id] = e
	elif e is Enemy:
		e.on_added()
	return e


func add_enemy(e: Enemy, p_id: int = 0) -> Enemy:
	if p_id > 0:
		add_entity_with_id(e, p_id)
	else:
		add_entity(e)
	enemies.append(e)
	if e.is_boss():
		boss_id = e.id
	return e


# 客戶端：快照裡已經沒有的實體立刻移除（權威端照常走 is_removed → _remove_dead_entities）
func remove_entity_now(p_id: int) -> void:
	var e: Entity = entities.get(p_id)
	if e == null:
		return
	e.is_removed = true
	_remove_dead_entities()


func first_alive_player() -> Player:
	for p: Player in players.values():
		if not p.is_dead:
			return p
	return null


func on_enemy_died(_e: Enemy) -> void:
	stats.kills += 1


# 打倒 Boss：通關，其餘敵人一起倒下、敵方投射物消失，延遲後發出 game:victory
func on_boss_defeated(boss: Enemy) -> void:
	is_over = true
	victory_timer = Config.WORLD.victory_delay
	hit_stop(Config.WORLD.victory_hit_stop)
	emit_event("camera:shake", {"amount": Config.WORLD.victory_shake, "duration": Config.WORLD.victory_shake_duration})
	for e in enemies:
		if e != boss and not e.is_dead:
			e.die()
	for p in projectiles:
		if p.team == &"enemy":
			p.remove()


# 投射物在玩家 / 敵人更新途中產生，同一步就會接著被更新（同網頁版）
# 客戶端本機預測時不產生（投射物由房主決定，等快照送來才出現）
func spawn_projectile(p: Projectile) -> Projectile:
	if not is_authority:
		return p
	add_entity(p)
	projectiles.append(p)
	return p


# payload 的 "name" 欄位保留給事件名稱（例如 sfx:cue 的音效名稱放在 "cue"）
func record_hitbox(h: Dictionary) -> void:
	h["tick"] = tick
	hitboxes.append(h)


func emit_event(name: String, payload: Dictionary) -> void:
	assert(not payload.has("name"), "payload 的 name 欄位保留給事件名稱：%s" % name)
	payload["name"] = name
	if event_actor != 0 and not payload.has("actor"):
		payload["actor"] = event_actor
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
	hitboxes.clear()
	tick += 1
	for e: Entity in entities.values():
		e.prev_pos = e.pos
		e.prev_facing = e.facing
		e.prev_height = e.height

	cooldowns.tick(dt)

	for peer_id: int in players:
		var p: Player = players[peer_id]
		if cmds.has(peer_id):
			p.apply_cmd(cmds[peer_id])
		event_actor = peer_id
		p.update(dt)
		event_actor = 0
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
		terrain.push_out(b)
		SimPhysics.clamp_to_arena(b, half_extents)
		b.integrate_vertical(dt, terrain)
	_bodies.clear()   # 不留參照，已移除的實體才能立即釋放

	_update_downed(dt)
	spawner.update(self, dt)
	_remove_dead_entities()
	if boss_id != 0 and not entities.has(boss_id):
		boss_id = 0
	if not is_over and is_any_player_alive():
		stats.time += dt
	if not is_defeated and not is_over and not players.is_empty() and not is_any_player_alive():
		is_defeated = true
		emit_event("game:defeat", {"stats": stats.duplicate()})
	if victory_timer > 0.0:
		victory_timer -= dt
		if victory_timer <= 0.0:
			emit_event("game:victory", {"stats": stats.duplicate()})


# 客戶端：只推進自己的角色（本機預測，C3）。順序同 step()，但不碰其他實體、不扣血、不產生投射物
func step_predicted(peer_id: int, cmd: InputCmd, dt: float) -> void:
	events.clear()
	hitboxes.clear()
	tick += 1
	var p: Player = players.get(peer_id)
	if p == null:
		return
	p.prev_pos = p.pos
	p.prev_facing = p.facing
	p.prev_height = p.height
	cooldowns.tick(dt)
	p.apply_cmd(cmd)
	event_actor = peer_id
	p.update(dt)
	event_actor = 0
	p.integrate(dt)
	terrain.push_out(p)
	SimPhysics.clamp_to_arena(p, half_extents)
	p.integrate_vertical(dt, terrain)


# 倒下與救援（C4）：有隊友按住互動鍵就累積救援時間、倒數暫停；放開時累積的時間慢慢減少
# 沒有站著的玩家時，所有倒地的人直接死亡（全員倒下就輸；單機倒下就是死亡）
func _update_downed(dt: float) -> void:
	var standing := 0
	var reviving := {}   # 倒地者 id -> true
	for p: Player in players.values():
		if not p.is_dead and not p.is_downed:
			standing += 1
			if p.revive_target_id != 0:
				reviving[p.revive_target_id] = true
	var r: Dictionary = Config.REVIVE
	for p: Player in players.values():
		if not p.is_downed:
			continue
		if standing == 0:
			p.die()
		elif reviving.has(p.id):
			p.revive_progress += dt
			if p.revive_progress >= r.revive_time - TIME_EPSILON:
				p.revive()
		else:
			p.revive_progress = maxf(0.0, p.revive_progress - r.decay_rate * dt)
			p.down_timer -= dt
			if p.down_timer <= TIME_EPSILON:
				p.die()


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
