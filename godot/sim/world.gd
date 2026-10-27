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
var player_classes: Dictionary = {}  # peer id → 職業（F2，ClassDefs）；reset 不清，重新開始照舊
var difficulty_mode: StringName = EventDefs.DEFAULT_MODE   # 選角畫面選的難度（EventDefs.MODES）；reset 不清，重新開始照舊
var player_list: Array[Player] = []  # 同 players.values()（加入順序），每步大量查詢時不必每次配置新陣列（D5）
var enemies: Array[Entity] = []
var allies: Array[Entity] = []       # enemies 裡隊伍是玩家方的（G6 骷髏僕從）：怪的攻擊只要多看這幾隻，不必掃全部 enemies
var projectiles: Array[Entity] = []
var torches: Array[Entity] = []     # 插在地上的火把（F8，sim/torch.gd）
var zones: Array[Dictionary] = []   # 地上的持續區域（F7 聖光圈，GroundZones）
var chests: Array[Entity] = []       # 寶箱（D3）
var pickups: Array[Entity] = []      # 掉在地上的道具（D3）
var coins: Array[Entity] = []        # 掉在地上的金幣（v0.45，sim/coin.gd）
var souls := 0                        # 共用的靈魂（局內貨幣，D3）：殺怪賺、開祭壇 / 石棺花
var debug_drop_all := false          # 除錯（--loot-test）：每隻怪死掉都掉武器
var soul_carry := 0.0                 # 靈魂道具多給的小數部分（G1：小怪一隻只給 2，+15% 要累積才湊得到 1）
var run_coins := 0                   # 本局拿到的金幣（v0.45，局外貨幣）：多人時是每人各自拿到的數量（全員一樣）；Profile 存累計
var coin_rng := RandomNumberGenerator.new()   # 掉金幣專用的亂數：不動 rng 的序列，怪群、寶箱、武器掉落維持原樣
var packs: Array[Dictionary] = []    # 地圖預放的怪群（D5）：{ center, ids, awake }，只在權威端
var spawn_packs := true              # reset 時是否散放怪群（地圖要有 "packs": true；check.gd 大部分檢查關掉）
var stats := {"wave": 0, "kills": 0, "time": 0.0}
var is_over := false                 # 通關後為 true（挖墳事件的地圖沒有通關，一層一層往下）
# 挖墳事件與層數（D6，sim/dig_event.gd）：每層基礎難度 = (層數 − 1) × DIFFICULTY.per_floor
var floor_num := 1
var base_difficulty := 0.0
var event := DigEvent.new()
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
# 連線（docs/系統說明.md §8）：房主 / 單機為權威端；客戶端的 World 只是快照的鏡像，加上本機預測自己的角色（不扣血、不產生實體）
var is_authority := true
var run_id := 0                      # 每次 reset 加 1：客戶端靠它知道房主重新開始了
# 正在更新哪位玩家（peer id；0 = 不是玩家的動作）：這段期間的事件標上 actor，客戶端丟掉自己已經預測播過的
var event_actor := 0
# 延遲補償（v0.38.0，房主開了才記）：每步結束記下敵人與玩家的位置；更新某位客戶端玩家時 rewind_tick = 他畫面上的時間，
# 他的近戰判定（Hitbox.query）就用那時的位置——他看到打中就是打中。只補償近戰判定，投射物照房主的時間飛
var rewind_enabled := false
var rewind_tick := 0
var _pos_history: Array = []   # [[tick, {id: pos}], ...]，最舊在前，最多 Config.NET.rewind_max_ticks 筆

var _next_id := 1
var _next_weapon_uid := 0   # 武器實例的 uid（全場唯一：武器會在玩家之間經過地上轉手）
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
	event.point = MapDefs.to_world(map, map.dig)   # 客戶端不跑 reset，挖墳點在這裡就設好（本機預測要判斷挖不挖得到）


func nav_for(radius: float) -> Nav:
	return nav_large if radius > Config.NAV.large_radius else nav


func reset(seed_value: int, peer_ids: Array[int] = [HOST_PEER_ID]) -> void:
	clear()
	tick = 0
	rng.seed = seed_value
	coin_rng.seed = hash([seed_value, &"coin"])
	cooldowns.reset_all()
	stats = {"wave": 0, "kills": 0, "time": 0.0, "floor": 1}
	is_over = false
	hit_stop_timer = 0.0
	boss_id = 0
	victory_timer = 0.0
	is_defeated = false
	event_actor = 0
	rewind_tick = 0
	_pos_history.clear()
	run_id += 1
	spawner.reset()
	_next_id = 1
	_next_weapon_uid = 0
	for peer_id in peer_ids:
		var p := Player.new(self, peer_id)
		p.apply_class(player_classes.get(peer_id, ClassDefs.NONE))
		p.pos = spawn_point
		p.height = terrain.ground_at(spawn_point)
		add_entity(p)
	souls = 0
	soul_carry = 0.0
	run_coins = 0
	floor_num = 1
	base_difficulty = 0.0
	_populate_floor()
	emit_event("game:restart", {})


# 一層開始時的地圖內容：寶箱、怪群、挖墳事件歸零
func _populate_floor() -> void:
	event.reset(self)   # 先歸零：怪群的難度倍率要用這一層的基礎難度
	if spawn_packs and map.get("packs", false):
		spawner.spawn_packs(self)
	_place_chests()   # 放在怪群之後：寶箱用掉的亂數不改變怪群的位置


# 寶箱（v0.44.0 隨機放）：每種數量 × 人數倍率；可走、走得到出生點、離出生點 / 挖墳點 / 地圖邊緣 / 其他寶箱夠遠
# 找不到夠遠的位置時，寶箱之間的距離逐步放寬（× 0.5、× 0）
func _place_chests() -> void:
	var c: Dictionary = LootDefs.CHEST_PLACEMENT
	var tiers: Array[StringName] = []
	var counts: Dictionary = map.get("chest_count", {})
	for tier: StringName in counts:
		for i in roundi(counts[tier] * LootDefs.player_mul(player_list.size())):
			tiers.append(tier)
	var lim: Vector2 = half_extents - Vector2(c.edge_margin, c.edge_margin)
	var placed: Array[Vector2] = []
	for gap_mul: float in [1.0, 0.5, 0.0]:
		for attempt in c.attempts:
			if placed.size() >= tiers.size():
				break
			var at := Vector2(rng.randf_range(-lim.x, lim.x), rng.randf_range(-lim.y, lim.y))
			if at.distance_to(spawn_point) < c.min_spawn_distance or at.distance_to(event.point) < c.min_dig_distance:
				continue
			if not nav.is_walkable(at) or not nav.same_region(at, spawn_point):
				continue
			if placed.any(func(o: Vector2) -> bool: return o.distance_to(at) < c.min_chest_distance * gap_mul):
				continue
			placed.append(at)
	for i in placed.size():
		var chest := Chest.new(self, tiers[i], placed[i])
		add_entity(chest)
		chests.append(chest)


# 目前難度（D6）：沒有挖墳事件的地圖固定 0
func difficulty() -> float:
	return event.difficulty(self) if DigEvent.enabled(self) else 0.0


# 全員走進出口（D6）：同一張地圖重新來過、基礎難度 +per_floor；玩家保留背包、武器、生命與共用的靈魂
# 地上的東西、敵人、投射物、寶箱全部清掉重新放；有人背著死者的屍體時，死者在新的一層變成冤魂
func next_floor() -> void:
	gain_coins(LootDefs.RUN_COINS.floor_clear_per_floor * floor_num, &"floor")   # 過關的金幣（v0.45）：越後面的層越多
	floor_num += 1
	base_difficulty = (floor_num - 1) * EventDefs.DIFFICULTY.per_floor
	stats["floor"] = floor_num
	for e: Entity in entities.values():
		if not e is Player:
			e.remove()
	_remove_dead_entities()
	packs.clear()
	boss_id = 0
	for p in player_list:
		p.arrive_floor(spawn_point, terrain.ground_at(spawn_point))
	_populate_floor()
	for p in player_list:
		if p.is_dead and not corpse_carrier(p.peer_id).is_empty():
			_spawn_ghost(p)
	emit_event("floor:started", {"floor": floor_num, "difficulty": base_difficulty})


# 背著某位死者屍體的玩家與背包條目 uid；沒有回傳 {}
func corpse_carrier(peer_id: int) -> Dictionary:
	var uid := Player.corpse_uid(peer_id)
	for p in player_list:
		if not p.is_dead and not p.inventory.find(uid).is_empty():
			return {"player": p, "uid": uid}
	return {}


# 冤魂：出生點附近 GHOST.distance 內、走得到的地方
func _spawn_ghost(dead: Player) -> void:
	var g: Dictionary = EventDefs.GHOST
	var at := spawn_point
	for attempt in 20:
		var a := rng.randf() * TAU
		var c := nav.nearest_walkable(spawn_point + Vector2(sin(a), cos(a)) * rng.randf_range(g.distance[0], g.distance[1]))
		if nav.is_walkable(c) and nav.same_region(c, spawn_point):
			at = c
			break
	var ghost := spawner.spawn_at(self, &"ghost", at)
	ghost.ghost_of = dead.peer_id
	emit_event("ghost:spawned", {"player_id": dead.id, "pos": at})


# 冤魂被打倒：死者在冤魂的位置復活，背包裡的屍體消失
func on_ghost_defeated(ghost: Enemy) -> void:
	var dead: Player = players.get(ghost.ghost_of)
	if dead == null or not dead.is_dead:
		return
	var carrier := corpse_carrier(dead.peer_id)
	if not carrier.is_empty():
		(carrier.player as Player).remove_item(carrier.uid)
	dead.resurrect(ghost.pos, EventDefs.GHOST.revive_hp_ratio)


# 實體與 World 互相參照（RefCounted 循環），移除時必須 detach() 才會釋放
func clear() -> void:
	for e: Entity in entities.values():
		e.detach()
	events.clear()
	hitboxes.clear()
	entities.clear()
	players.clear()
	player_list.clear()
	enemies.clear()
	allies.clear()
	projectiles.clear()
	torches.clear()
	zones.clear()
	chests.clear()
	pickups.clear()
	coins.clear()
	packs.clear()


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
		player_list.assign(players.values())
	elif e is Enemy:
		e.on_added()
	return e


func add_enemy(e: Enemy, p_id: int = 0) -> Enemy:
	if p_id > 0:
		add_entity_with_id(e, p_id)
	else:
		add_entity(e)
	enemies.append(e)
	if e.team == &"player":
		allies.append(e)
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
	for p in player_list:
		if not p.is_dead:
			return p
	return null


# killer_id：打死牠的實體（投射物算發射者）；是玩家時套他的靈魂道具（G1 錢袋、G2 貪婪之手），多給的小數累積到湊滿 1
func on_enemy_died(e: Enemy, killer_id: int = 0) -> void:
	if e.team == &"player":
		return   # 骷髏僕從（G6）倒下：不算擊殺、不給東西
	stats.kills += 1
	var g := 0 if e.no_souls else roundi(LootDefs.KILL_SOULS.get(e.type, 0) * LootDefs.player_mul(player_list.size()))
	var killer: Entity = entities.get(killer_id)
	if g > 0 and killer is Player:
		soul_carry += g * (ItemEffects.soul_mul(killer as Player, e) - 1.0)
		var extra := floori(soul_carry)
		soul_carry -= extra
		g = maxi(0, g + extra)
	if g > 0:
		souls += g
		emit_event("souls:gained", {"amount": g, "pos": e.pos, "total": souls})
	# 局外金幣（v0.45）：極低機率掉 1 枚；召喚出來的不掉（和靈魂一樣避免刷）
	var coin_chance: float = LootDefs.RUN_COINS.drop_chance.get(e.type, 0.0)
	if not e.no_souls and coin_chance > 0.0 and coin_rng.randf() < coin_chance:
		drop_coin(e.pos)
	# 武器掉落（D4）：多人時也只掉一把（房主產生一個實體，先撿先得）
	var chance: float = 1.0 if debug_drop_all else WeaponDropDefs.DROP_CHANCE.get(e.type, 0.0)
	if chance > 0.0 and (chance >= 1.0 or rng.randf() < chance):
		var source := &"boss" if e.is_boss() else &"minion"
		var bases := WeaponDropDefs.bases()
		var base := bases[rng.randi_range(0, bases.size() - 1)]
		var inst := WeaponDropDefs.make(new_weapon_uid(), base, WeaponDropDefs.roll_rarity(source, rng, team_treasure()), rng)
		drop_weapon(inst, e.pos)
		emit_event("weapon:dropped", {"uid": String(inst.uid), "base": String(base), "rarity": String(inst.rarity), "pos": e.pos})


# 殺怪掉落用全隊最高的尋寶（F1，Claude 暫定）：擊殺者常常是投射物、追不到是誰，靈魂本來也是全隊共用
func team_treasure() -> float:
	var best := 0.0
	for p in player_list:
		best = maxf(best, p.stats.value(&"treasure"))
	return best


func new_weapon_uid() -> StringName:
	_next_weapon_uid += 1
	return StringName("w%d" % _next_weapon_uid)


# 隊友的屍體（D6）：一般的地上物件，撿起來進背包（Player.add_corpse）
func drop_corpse(peer_id: int, at: Vector2) -> ItemPickup:
	var pickup := drop_item(&"corpse", at)
	pickup.corpse_of = peer_id
	return pickup


func drop_weapon(inst: Dictionary, at: Vector2) -> ItemPickup:
	return drop_item(inst.base, at, inst)


# 道具 / 武器掉在地上（開寶箱、殺怪、從背包丟出）；客戶端不產生（等快照）
func drop_item(item_id: StringName, at: Vector2, weapon: Dictionary = {}) -> ItemPickup:
	var spot := nav.nearest_walkable(at)
	var pickup := ItemPickup.new(self, item_id, spot, weapon)
	if is_authority:
		add_entity(pickup)
		pickups.append(pickup)
	return pickup


func drop_coin(at: Vector2) -> Coin:
	var coin := Coin.new(self, nav.nearest_walkable(at))
	if is_authority:
		add_entity(coin)
		coins.append(coin)
	return coin


# 金幣進帳（過關 reason = &"floor"、撿到地上的 &"pickup"）：多人時全員各拿一份，所以只記一個數字
func gain_coins(amount: int, reason: StringName, at := Vector2.ZERO) -> void:
	if amount <= 0:
		return
	run_coins += amount
	emit_event("coins:gained", {"amount": amount, "total": run_coins, "reason": String(reason), "floor": floor_num, "pos": at})


# 活著、沒倒地、還沒走進出口的玩家走近就撿起（不用按 F）
func _collect_coins() -> void:
	for c in coins:
		if c.is_removed:
			continue
		for p in player_list:
			if p.is_dead or p.is_downed or p.descended:
				continue
			if c.pos.distance_to(p.pos) - p.radius <= LootDefs.RUN_COINS.collect_range * p.stats.value(&"pickup_radius"):
				c.remove()
				gain_coins(1, &"pickup", c.pos)
				emit_event("sfx:cue", {"cue": "potion", "pos": c.pos})
				break


# 離 p 最近、按得到 F 的寶箱 / 道具（已開的寶箱、已被撿走的道具不算）；沒有回傳 null
func nearest_interactable(p: Player, list: Array[Entity]) -> Entity:
	var best: Entity = null
	var best_d := INF
	for e in list:
		if e.is_removed or (e is Chest and (e as Chest).opened):
			continue
		var d := e.pos.distance_to(p.pos) - e.radius - p.radius
		if d <= LootDefs.INTERACT_RANGE * p.stats.value(&"pickup_radius") and d < best_d:   # 磁石（G1）
			best_d = d
			best = e
	return best


# 打倒 Boss：挖墳事件的地圖（D6）不通關，額外掉一個大寶箱機率的道具（武器與金幣照 on_enemy_died）；
# 測試場地照舊通關：其餘敵人一起倒下、敵方投射物消失，延遲後發出 game:victory
func on_boss_defeated(boss: Enemy) -> void:
	if DigEvent.enabled(self):
		var pool := LootDefs.drop_pool(LootDefs.roll_rarity(&"big", rng, team_treasure()))
		var item_id: StringName = pool[rng.randi_range(0, pool.size() - 1)]
		drop_item(item_id, boss.pos + Vector2(LootDefs.DROP_DISTANCE, 0.0))
		emit_event("boss:reward", {"item": String(item_id), "pos": boss.pos})
		hit_stop(Config.WORLD.victory_hit_stop)
		emit_event("camera:shake", {"amount": Config.WORLD.victory_shake, "duration": Config.WORLD.victory_shake_duration})
		return
	is_over = true
	victory_timer = Config.WORLD.victory_delay
	hit_stop(Config.WORLD.victory_hit_stop)
	emit_event("camera:shake", {"amount": Config.WORLD.victory_shake, "duration": Config.WORLD.victory_shake_duration})
	for e in enemies:
		if e != boss and not e.is_dead and not (e is Enemy and (e as Enemy).dormant):   # 還在休眠的怪群留著（D5）
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
	for p in player_list:
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
		rewind_tick = p.view_tick if rewind_enabled else 0
		p.update(dt)
		rewind_tick = 0
		event_actor = 0
	_update_packs()
	for e in enemies:
		e.update(dt)
	for e in projectiles:
		e.update(dt)
	GroundZones.update(self, dt)

	_bodies.clear()
	for p in player_list:
		if not p.descended:   # 已走進出口的不擋路（D6）
			_bodies.append(p)
	_bodies.append_array(enemies)
	for b in _bodies:
		if not b.fixed:   # 休眠的怪群速度為 0、也不會有擊退（被打就醒），不必積分（v0.30.0）
			b.integrate(dt)
	SimPhysics.separate(_bodies, rng)
	for b in _bodies:
		# 位置和上次算過地形時一樣、站在地上的（休眠的怪群、站著出招的）已經推出牆、落地過，不必再算（D5）
		if b.pos == b.terrain_checked_pos and b.vz == 0.0 and b.height == b.ground_height:
			continue
		terrain.push_out(b)
		SimPhysics.clamp_to_arena(b, half_extents)
		b.integrate_vertical(dt, terrain)
		b.terrain_checked_pos = b.pos
	_bodies.clear()   # 不留參照，已移除的實體才能立即釋放

	_update_downed(dt)
	_collect_coins()
	spawner.update(self, dt)
	event.update(self, dt)
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
	if rewind_enabled:
		_record_positions()


func _record_positions() -> void:
	var at := {}
	for e in enemies:
		at[e.id] = e.pos
	for p in player_list:
		at[p.id] = p.pos
	_pos_history.append([tick, at])
	if _pos_history.size() > Config.NET.rewind_max_ticks:
		_pos_history.pop_front()


# 延遲補償：目前更新的玩家畫面上那一刻（rewind_tick 那一步結束時）的位置 {id: pos}；不用補償時回傳空的
# 太舊的夾到記錄裡最舊的那筆（補償上限 rewind_max_ticks 步，延遲再大就不完全補）；上一步就是現在的位置，也不必補
func rewound_positions() -> Dictionary:
	if rewind_tick <= 0 or _pos_history.is_empty() or rewind_tick >= tick - 1:
		return {}
	var oldest: int = _pos_history[0][0]
	var t := maxi(rewind_tick, oldest)
	return _pos_history[t - oldest][1] if t - oldest < _pos_history.size() and _pos_history[t - oldest][0] == t else {}


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


# 怪群（D5）：任一位能被當成目標的玩家走到群中心 wake_distance 以內，整群醒來
func _update_packs() -> void:
	var r: float = MonsterRarityDefs.PACKS.wake_distance
	for i in packs.size():
		if packs[i].awake:
			continue
		for p in player_list:
			if p.is_targetable() and p.pos.distance_squared_to(packs[i].center) <= r * r:
				wake_pack(i)
				break


func wake_pack(i: int) -> void:
	var pk: Dictionary = packs[i]
	if pk.awake:
		return
	pk.awake = true
	for id: int in pk.ids:
		var e: Entity = entities.get(id)
		if e is Enemy:
			(e as Enemy).wake()


# 倒下與救援（C4）：有隊友按住互動鍵就累積救援時間、倒數暫停；放開時累積的時間慢慢減少
# 沒有站著的玩家時，所有倒地的人直接死亡（全員倒下就輸；單機倒下就是死亡）
func _update_downed(dt: float) -> void:
	var standing := 0
	var reviving := {}   # 倒地者 id -> 救他的人（多人一起救取最快的；驅魔神官被動救得快、救起的血多，F7）
	for p in player_list:
		if not p.is_dead and not p.is_downed:
			standing += 1
			if p.revive_target_id != 0:
				var cur: Player = reviving.get(p.revive_target_id)
				if cur == null or p.class_passive("revive_speed", 1.0) > cur.class_passive("revive_speed", 1.0):
					reviving[p.revive_target_id] = p
	var r: Dictionary = Config.REVIVE
	for p in player_list:
		if not p.is_downed:
			continue
		if standing == 0:
			p.die()
		elif reviving.has(p.id):
			var rescuer: Player = reviving[p.id]
			p.revive_progress += dt * rescuer.class_passive("revive_speed", 1.0)
			if p.revive_progress >= r.revive_time - TIME_EPSILON:
				p.revive(rescuer.class_passive("revive_hp_ratio", r.revive_hp_ratio))
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
				player_list.erase(e)
	enemies.assign(enemies.filter(func(e: Entity) -> bool: return not e.is_removed))
	if not allies.is_empty():
		allies.assign(allies.filter(func(e: Entity) -> bool: return not e.is_removed))
	projectiles.assign(projectiles.filter(func(e: Entity) -> bool: return not e.is_removed))
	pickups.assign(pickups.filter(func(e: Entity) -> bool: return not e.is_removed))
	coins.assign(coins.filter(func(e: Entity) -> bool: return not e.is_removed))
	torches.assign(torches.filter(func(e: Entity) -> bool: return not e.is_removed))
	chests.assign(chests.filter(func(e: Entity) -> bool: return not e.is_removed))   # 換層時整批移除（D6）
