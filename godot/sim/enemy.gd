# 敵人基底（照搬網頁版 Enemy.js）：數值套用（屬性 + 波次倍率來源 &"wave"）、共用狀態（爬出 / 受擊 / 死亡）
# v0.17.0 起沒有接觸傷害（設計方向：每種怪物都靠自己的招式攻擊，見 sim/hitbox.gd）
# 子類別把自己的狀態合併進 base_states()，並指定 main_state（爬出與受擊結束後回到哪個狀態）
# 姿勢由畫面層依 anim 計算；這裡只記錄狀態名稱、經過秒數與少量動畫參數
class_name Enemy
extends Entity

var def: Dictionary
var type: StringName
var speed: float:   # 移速屬性的捷徑（基礎值含個體隨機差異，波次倍率是 &"wave" 來源）
	get:
		return stats.value(&"move_speed")
var main_state: StringName = &"chase"
var fsm: StateMachine
var anim: Dictionary = {}
var _cd_keys: Dictionary = {}       # 名稱 -> CD key（enemy<id>.<名稱>），移除時全部 reset
# 尋路與跳躍（D1，只在權威端；見 sim/nav.gd）
var _nav_timer := 0.0
var _nav_far := false                # 上次判斷時離目標超過 NAV.far_distance（降低重新判斷的頻率）
var _path := PackedVector2Array()   # 空 = 看得到目標，直接走過去
var _jump_windup := 0.0
var _jump_dir := Vector2.ZERO        # 起跳方向；空中往這個方向至少 NAV.jump_air_speed，落地後清掉
# 稀有度與詞條（D5，defs/monster_rarity_defs.gd）；客戶端的鏡像只有這三個欄位與體型（數值以快照為準）
var rarity: StringName = MonsterRarityDefs.NORMAL
var affixes: Array[StringName] = []
var rare_name := ""
var pack_id := -1                    # 地圖預放的怪群（-1 = 波次或召喚出來的）
var dormant := false:                # 怪群休眠中：站著不動，整群醒來後才開始追（World.wake_pack）
	set(v):
		dormant = v
		fixed = v
var wave_member := false             # 波次生成的：場上的波次怪都死了才開下一波（怪群不算）
var action_speed := 1.0              # 狀態機時間的倍率（狂暴詞條 1.4：舉刀、瞄準、收招與冷卻都變快）
var summoner_id := 0                 # 召喚詞條叫出來的：召喚者的 id
var no_souls := false                 # 召喚出來的（召喚詞條、Boss 召喚）：死了不給靈魂（v0.44.0，避免刷錢）
var ghost_of := 0                    # 冤魂（D6）：死去玩家的 peer id，打倒後那位玩家復活
var _frenzied := false
var _exploded := false
var _summon_timer := 0.0
# 道具造成的狀態（v0.33.0，ItemDefs.PROCS）：只在權威端推進；畫面看 anim 的 frozen / poisoned
var frozen_timer := 0.0              # 冰凍剩餘秒數：不能動、不出招
var grabbed_by := 0                  # 被鐵鏟舉著（F9）：舉著的玩家 id；期間不能動、不出招，位置由玩家擺
var buried_timer := 0.0              # 被埋進土裡（F9）：剩餘秒數，不能動、不出招
var poison_timer := 0.0              # 中毒剩餘秒數
var poison_tick_damage := 0.0        # 每次扣的傷害
var poison_source_id := 0            # 下毒的玩家（傷害與擊殺算他的）
var burn_timer := 0.0                # 燃燒（F8 火把）剩餘秒數；每 BURN_TICK 秒扣 burn_tick_damage（= 層數 × 每層每秒 × BURN_TICK）
var burn_tick_damage := 0.0
var burn_stacks := 0                 # 燃燒層數（火焰羈絆第 1 階起才會超過 1）
var burn_stack_dps := 0.0            # 每層每秒的傷害
var burn_source_id := 0
var _burn_tick := 0.0
var burn_spread := false             # 會擴散的燃燒（G3 永恆之焰）
var slow_timer := 0.0                # 被停滯懷錶減速（G4）剩餘秒數：移速（屬性來源 &"slow"）與狀態機時間都乘 slow_mul
var slow_mul := 1.0
var chill_stacks := 0                # 冰冷層數（冰霜羈絆）：每層減速 chill_slow_per，移速與狀態機時間都乘 chill_mul
var chill_timer := 0.0               # 沒再疊就在這麼久後全部消掉
var chill_slow_per := 0.0
var chill_mul := 1.0
var freeze_source_id := 0            # 冰霜羈絆凍住的：凍住它的玩家（第 3 階凍結中被殺沒有死亡效果）
var ice_coffin := false              # 這次凍結是冰棺（分支・冰棺，第 8c 步）：不碎冰、受到的傷害分給旁邊的怪
var poise := 0.0                     # 失衡值（物理羈絆第 2 階）：累積到最大生命的 poise_ratio 就失衡
var poise_timer := 0.0               # 這麼久沒再累積就歸零
var stagger_timer := 0.0             # 失衡剩餘秒數：不能動、不出招，受到的傷害變多（BondEffects.damage_mul）
var ram_timer := 0.0                 # 物理羈絆第 3 階：被擊退的這段時間撞到別的怪，兩隻各受 ram_damage
var ram_damage := 0.0
var ram_source_id := 0
var stun_timer := 0.0                # 被技能暈眩（盾衝、震地…）：不能動、不出招（Boss 不會被暈）
var taunt_id := 0                    # 被嘲諷：這段時間只追這位玩家（Boss 不會被嘲諷）
var taunt_timer := 0.0
var blind_timer := 0.0               # 在煙霧裡：打玩家的攻擊一半會打偏（Combat）
var no_death_effect := false         # 死亡爆炸詞條、膨脹屍死後爆炸不發動（冰霜羈絆第 3 階：凍結中被殺）
var _spread_timer := 0.0
const BURN_TICK := 0.5
const BURN_COLOR := Color("ff8a30")
const CHILL_COLOR := Color("8fd8ff")
const STAGGER_COLOR := Color("ffe08a")
const CHILL_MIN_MUL := 0.1          # 冰冷再多層，移速與動作也不會低於原本的 10%
var _poison_tick := 0.0


# mul：波次倍率 { hp, damage, speed }；選填 dormant = true 時以休眠狀態出生（怪群，不播爬出動畫與音效）
func _init(p_world: World, p_type: StringName, at: Vector2, mul: Dictionary, states: Dictionary) -> void:
	var d: Dictionary = EnemyDefs.ENEMIES[p_type]
	super(p_world, p_type, &"enemy", d.radius, d.max_hp, d.mass)
	def = d
	type = p_type
	var variance: float = d.speed_variance
	stats.set_base(&"move_speed", d.move_speed * p_world.rng.randf_range(1.0 - variance, 1.0 + variance))
	stats.set_base(&"knockback_taken", d.get("knockback_mul", 1.0))
	set_resists(d.get("resists", {}))
	stats.set_source(&"wave", [
		[&"max_hp", Stats.MUL, mul.hp], [&"damage", Stats.MUL, mul.damage], [&"move_speed", Stats.MUL, mul.speed],
	])
	hp = max_hp
	pos = at
	height = p_world.terrain.ground_at(at)
	var target := nearest_player()
	if target != null:
		facing = MathUtil.angle_to(pos, target.pos)
	dormant = mul.get("dormant", false)
	states[&"dormant"] = Dormant.new()
	states[&"launch"] = Launch.new()
	fsm = StateMachine.new(self, states, mul.get("initial_state", &"dormant" if dormant else &"spawn"))
	_update_anim()


# 設定稀有度、詞條與名字（體型跟著變）；權威端接著呼叫 apply_rarity_stats，客戶端的鏡像只要外觀
func set_rarity(p_rarity: StringName, p_affixes: Array, p_name: String = "") -> void:
	var s: float = MonsterRarityDefs.RARITIES[p_rarity].scale
	var before: float = MonsterRarityDefs.RARITIES[rarity].scale
	rarity = p_rarity
	affixes.assign(p_affixes)
	rare_name = p_name
	radius *= s / before
	body_height *= s / before


# 稀有度倍率（&"rarity"）、詞條加成（&"affixes"）、再生（依最大生命）；目前生命跟著最大生命增加
func apply_rarity_stats() -> void:
	var r: Dictionary = MonsterRarityDefs.RARITIES[rarity]
	set_stat_source(&"rarity", [[&"max_hp", Stats.MUL, r.hp], [&"damage", Stats.MUL, r.damage]])
	var mods := []
	for id in affixes:
		mods.append_array(MonsterRarityDefs.AFFIXES[id].get("mods", []))
	set_stat_source(&"affixes", mods)
	if has_affix(&"regen"):
		set_stat_source(&"affix_regen", [[&"hp_regen", Stats.ADD, max_hp * MonsterRarityDefs.AFFIXES.regen.regen_ratio]])
	if has_affix(&"summoner"):
		_summon_timer = MonsterRarityDefs.AFFIXES.summoner.interval


func has_affix(id: StringName) -> bool:
	return id in affixes


func affix(id: StringName) -> Dictionary:
	return MonsterRarityDefs.AFFIXES[id]


func is_boss() -> bool:
	return def.get("is_boss", false)


func is_spawning() -> bool:
	return fsm.is_in(&"spawn")


func is_launching() -> bool:
	return fsm.is_in(&"launch")


# 噴出去（狀態 launch）：seconds 秒後落在 to（同高度的拋物線，最高點 = 重力 × seconds² ÷ 8）
func launch_to(to: Vector2, seconds: float) -> void:
	if not fsm.is_in(&"launch"):
		fsm.change(&"launch")
	fsm.data["velocity"] = (to - pos) / seconds
	fsm.data["flight_time"] = seconds
	vz = Entity.gravity() * seconds * 0.5
	facing = MathUtil.angle_to(pos, to)


# 被鐵鏟拋出（F9）：同 launch_to 飛過去；飛行中身體 width 內碰到的怪受 path_hit（每隻一次），落地受 land_hit。
# 傷害來源是丟的人（落地時已經不在就不算傷害）
func throw_to(to: Vector2, seconds: float, thrower: Entity, dir: Vector2, width: float, path_hit: Dictionary, land_hit: Dictionary) -> void:
	launch_to(to, seconds)
	fsm.data["thrown"] = {"source_id": thrower.id, "team": thrower.team, "dir": dir, "width": width,
		"path_hit": path_hit, "land_hit": land_hit, "hit": {}}


# 被拋出的怪落地：落地傷害（往前擊退）與塵土
static func land_throw(e: Enemy, thrower: Entity, hit: Dictionary, dir: Vector2) -> void:
	if thrower != null and not e.is_dead:
		var h := hit.duplicate()
		h["origin"] = e.pos - dir
		Combat.apply_damage(e.world, thrower, e, h)
	e.world.emit_event("fx:explosion", {"pos": e.pos, "height": e.world.terrain.ground_at(e.pos), "radius": 1.2, "color": hit.color})


func _update_throw_path(th: Dictionary) -> void:
	var thrower: Entity = world.entities.get(th.source_id)
	if thrower == null:
		return
	for o in world.enemies:
		if o == self or o.is_dead or o.team == th.team or th.hit.has(o.id):
			continue
		if o.pos.distance_to(pos) <= th.width + o.radius:
			th.hit[o.id] = true
			var h: Dictionary = th.path_hit.duplicate()
			h["origin"] = pos - th.dir
			Combat.apply_damage(world, thrower, o, h)


# 字串只組一次（D5：200 隻怪每步都查冷卻，每次 format 太慢）
func cd(name: String) -> String:
	var key: String = _cd_keys.get(name, "")
	if key == "":
		key = "enemy%d.%s" % [id, name]
		_cd_keys[name] = key
	return key


# 由 World.add_entity 在取得 id 之後呼叫（CD key 需要 id）
func on_added() -> void:
	pass


# 近戰 / 遠程 AI 追的對象：最近的玩家或玩家方的骷髏僕從（G6，Boss 只追玩家）；僕從自己覆寫成最近的怪
func nearest_target() -> Entity:
	var best: Entity = nearest_player()
	if is_boss() or world.allies.is_empty() or taunt_timer > 0.0:
		return best
	var best_d := best.pos.distance_squared_to(pos) if best != null else INF
	for a in world.allies:
		if a.is_dead:
			continue
		var d := a.pos.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = a
	return best


func nearest_player() -> Player:
	if taunt_timer > 0.0:   # 被嘲諷（盾的技能）：只追嘲諷的人
		var t := world.entities.get(taunt_id) as Player
		if t != null and t.is_targetable():
			return t
	var best: Player = null
	var best_d := INF
	for p in world.player_list:
		if not p.is_targetable():   # 倒地的玩家不追
			continue
		var d := p.pos.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = p
	return best


func update(dt: float) -> void:
	if dormant and not is_dead:
		# 休眠的怪群只推進狀態時間（呼吸動畫用），不跑狀態機、跳躍與詞條（v0.30.0 效能）；醒來後下一步由 Dormant 切到 main_state
		velocity = Vector2.ZERO
		fsm.time += dt
		if anim.is_empty():
			_update_anim()
		anim["time"] = fsm.time
		return
	_update_poison(dt)
	_update_burn(dt)
	_update_slow(dt)
	_update_chill(dt)
	_update_poise(dt)
	taunt_timer = maxf(0.0, taunt_timer - dt)
	blind_timer = maxf(0.0, blind_timer - dt)
	if (frozen_timer > 0.0 or stagger_timer > 0.0 or stun_timer > 0.0 or buried_timer > 0.0 or grabbed_by != 0) and not is_dead:
		frozen_timer = maxf(0.0, frozen_timer - dt)
		stagger_timer = maxf(0.0, stagger_timer - dt)
		stun_timer = maxf(0.0, stun_timer - dt)
		buried_timer = maxf(0.0, buried_timer - dt)
		velocity = Vector2.ZERO   # 冰凍 / 失衡 / 被埋 / 被舉著：狀態機停住（出招到一半也停），結束後接著做
		_update_anim()
		return
	_nav_timer -= dt
	_update_affixes(dt)
	fsm.update(dt * action_speed * slow_mul * chill_mul)
	_update_jump(dt)
	_update_anim()


# 中毒（v0.33.0）：再中毒重新計時，每次扣的傷害取較高的
func apply_poison(source_id: int, total: float) -> void:
	if is_dead:
		return
	var cfg: Dictionary = ItemDefs.PROCS.poison
	var per_tick: float = total / (cfg.duration / cfg.tick)
	if poison_timer <= 0.0:
		_poison_tick = cfg.tick
		poison_tick_damage = 0.0
	poison_timer = cfg.duration
	poison_tick_damage = maxf(poison_tick_damage, per_tick)
	poison_source_id = source_id
	world.emit_event("fx:status", {"pos": pos, "height": ground_height, "color": cfg.color})


# 燃燒（F8 火把）：點燃 = 1 層，每秒 per_sec、持續 duration 秒；持續傷害不算命中（不觸發道具）
# spread（G3 永恆之焰）：燒著的時候每 spread_interval 秒把剩下的燃燒傳給 spread_range 內一隻沒在燒的怪（傳過去的也會擴散）
func apply_burn(source_id: int, per_sec: float, duration: float, spread := false) -> void:
	add_burn(source_id, per_sec, duration, 1, 1, spread)


# 加 stacks 層燃燒：最多到 max_stacks（施加的人能疊到幾層，火焰羈絆；已經比較多就不減少）；
# 再點燃重新計時（取較長的）、每層的傷害取較高的
func add_burn(source_id: int, per_stack_dps: float, duration: float, stacks: int, max_stacks: int, spread := false) -> void:
	if is_dead:
		return
	if burn_timer <= 0.0:
		_burn_tick = BURN_TICK
		burn_stacks = 0
		burn_stack_dps = 0.0
		burn_spread = false
		_spread_timer = ItemDefs.PROCS.ignite.spread_interval
	burn_spread = burn_spread or spread
	burn_timer = maxf(burn_timer, duration)
	burn_stack_dps = maxf(burn_stack_dps, per_stack_dps)
	burn_stacks = mini(burn_stacks + stacks, maxi(max_stacks, burn_stacks))
	burn_tick_damage = burn_stack_dps * burn_stacks * BURN_TICK
	burn_source_id = source_id
	world.emit_event("fx:status", {"pos": pos, "height": ground_height, "color": BURN_COLOR})


func clear_burn() -> void:
	burn_timer = 0.0
	burn_stacks = 0
	burn_stack_dps = 0.0
	burn_tick_damage = 0.0


func _update_burn(dt: float) -> void:
	if burn_timer <= 0.0 or is_dead:
		return
	burn_timer -= dt
	_burn_tick -= dt
	if burn_spread:
		_spread_timer -= dt
		if _spread_timer <= 1e-6:
			_spread_timer += ItemDefs.PROCS.ignite.spread_interval
			_spread_burn()
	if _burn_tick > 1e-6:
		return
	_burn_tick += BURN_TICK
	var src: Entity = world.entities.get(burn_source_id)
	if src != null:
		var hit := ItemEffects.proc_hit(burn_tick_damage, self, BURN_COLOR)
		hit["damage_type"] = &"fire"
		hit["no_status"] = true   # 燒的那一下不再疊燃燒
		Combat.apply_damage(world, src, self, hit)
	if burn_timer <= 0.0:
		clear_burn()


# 減速（G4 停滯懷錶）：一般怪 × (1 − slow)，Boss × PROCS.slow_time.boss_mul；再被減速取較長的時間、較慢的倍率
func apply_slow(duration: float, slow: float) -> void:
	if is_dead:
		return
	var mul: float = ItemDefs.PROCS.slow_time.boss_mul if is_boss() else 1.0 - slow
	slow_mul = mul if slow_timer <= 0.0 else minf(slow_mul, mul)
	slow_timer = maxf(slow_timer, duration)
	set_stat_source(&"slow", [[&"move_speed", Stats.MUL, slow_mul]])


func _update_slow(dt: float) -> void:
	if slow_timer <= 0.0:
		return
	slow_timer -= dt
	if slow_timer <= 0.0:
		slow_mul = 1.0
		remove_stat_source(&"slow")


func _spread_burn() -> void:
	if burn_timer <= 0.0:
		return
	var r: float = ItemDefs.PROCS.ignite.spread_range
	var best: Enemy = null
	var best_d := INF
	for e in world.enemies:
		var en := e as Enemy
		if en == self or en.is_dead or en.team != team or en.burn_timer > 0.0:
			continue
		var d := en.pos.distance_to(pos) - en.radius - radius
		if d <= r and d < best_d:
			best_d = d
			best = en
	if best != null:
		best.add_burn(burn_source_id, burn_stack_dps, burn_timer, burn_stacks, burn_stacks, true)


# 技能暈眩：seconds 秒不能動、不出招（Boss 不會）；已經暈著的取較長的
func stun(seconds: float) -> void:
	if is_dead or is_boss():
		return
	stun_timer = maxf(stun_timer, seconds)
	velocity = Vector2.ZERO


# 冰冷（冰霜羈絆）：加 stacks 層，最多到 max_stacks（已經比較多就不減少）；每層減速 slow_per（取較高的），重新計時
# 回傳加完的層數
func add_chill(stacks: int, max_stacks: int, slow_per: float, duration: float) -> int:
	if is_dead:
		return 0
	chill_stacks = mini(chill_stacks + stacks, maxi(max_stacks, chill_stacks))
	chill_slow_per = maxf(chill_slow_per, slow_per)
	chill_timer = maxf(chill_timer, duration)
	_set_chill_mul()
	world.emit_event("fx:status", {"pos": pos, "height": ground_height, "color": CHILL_COLOR})
	return chill_stacks


func clear_chill() -> void:
	chill_stacks = 0
	chill_timer = 0.0
	chill_slow_per = 0.0
	_set_chill_mul()


func _set_chill_mul() -> void:
	chill_mul = maxf(CHILL_MIN_MUL, 1.0 - chill_stacks * chill_slow_per)
	if chill_stacks > 0:
		set_stat_source(&"chill", [[&"move_speed", Stats.MUL, chill_mul]])
	else:
		remove_stat_source(&"chill")


func _update_chill(dt: float) -> void:
	if chill_timer <= 0.0:
		return
	chill_timer -= dt
	if chill_timer <= 0.0:
		clear_chill()


# 物理羈絆第 2 階：累積失衡值（實際扣的血），到門檻就失衡 seconds 秒並歸零；回傳這一下有沒有讓它失衡
func add_poise(amount: float, ratio: float, decay: float, seconds: float) -> bool:
	if is_dead or stagger_timer > 0.0:
		return false
	poise += amount
	poise_timer = decay
	if poise < max_hp * ratio:
		return false
	poise = 0.0
	stagger_timer = seconds
	velocity = Vector2.ZERO
	world.emit_event("fx:status", {"pos": pos, "height": ground_height, "color": STAGGER_COLOR})
	return true


func _update_poise(dt: float) -> void:
	if poise_timer > 0.0:
		poise_timer -= dt
		if poise_timer <= 0.0:
			poise = 0.0
	if ram_timer > 0.0:
		ram_timer -= dt
		if not is_dead:
			_check_ram()


# 被擊退中撞到同隊的另一隻怪：兩隻各受 ram_damage 的物理傷害（算打的玩家），一次擊退只撞一次
func _check_ram() -> void:
	var src: Entity = world.entities.get(ram_source_id)
	if src == null:
		ram_timer = 0.0
		return
	for e in world.enemies:
		if e == self or e.is_dead or e.team != team:
			continue
		var r := radius + e.radius + 0.05
		if e.pos.distance_squared_to(pos) > r * r:
			continue
		ram_timer = 0.0
		for t: Entity in [self, e]:
			var hit := ItemEffects.proc_hit(ram_damage, t, Color.WHITE)
			hit["no_status"] = true
			Combat.apply_damage(world, src, t, hit)
		return


# 埋進土裡（F9 鐵鏟）：seconds 秒不能動、不出招（Boss 不會被舉起，所以也不會被埋）
func bury(seconds: float) -> void:
	if is_dead:
		return
	buried_timer = maxf(buried_timer, seconds)


# 冰凍（v0.33.0）：freeze_immune 的怪（Boss）不會被冰凍；已經凍住的取較長的
func apply_freeze(duration: float) -> void:
	if is_dead or def.get("freeze_immune", false):
		return
	frozen_timer = maxf(frozen_timer, duration)
	ice_coffin = false   # 冰棺由 BondEffects.add_chill 凍完再標
	world.emit_event("fx:status", {"pos": pos, "height": ground_height, "color": ItemDefs.PROCS.freeze.color})


func _update_poison(dt: float) -> void:
	if poison_timer <= 0.0 or is_dead:
		return
	poison_timer -= dt
	_poison_tick -= dt
	if _poison_tick > 1e-6:   # 容許浮點誤差：3 秒剛好扣滿 6 次
		return
	_poison_tick += ItemDefs.PROCS.poison.tick
	var src: Entity = world.entities.get(poison_source_id)
	if src != null:
		Combat.apply_damage(world, src, self, ItemEffects.proc_hit(poison_tick_damage, self, ItemDefs.PROCS.poison.color, 0.0, &"poison"))
	if poison_timer <= 0.0:
		poison_tick_damage = 0.0


# 各屬性的抗性設成基礎值（EnemyDefs 的 resists，沒寫的 0）；換型態時整組換掉
func set_resists(resists: Dictionary) -> void:
	for t: StringName in StatDefs.DAMAGE_TYPES:
		stats.set_base(StatDefs.DAMAGE_TYPES[t].resist, resists.get(t, 0.0))


# 冷卻秒數套用 action_speed（狂暴時攻擊間隔也縮短）
func cd_time(seconds: float) -> float:
	return seconds / action_speed


# 狂暴（生命低於門檻時加速，只觸發一次）、召喚（醒著時每 interval 秒叫幾隻，同時最多 max_alive 隻）
func _update_affixes(dt: float) -> void:
	if is_dead or dormant or is_spawning():
		return
	if has_affix(&"frenzy") and not _frenzied and hp <= max_hp * affix(&"frenzy").threshold:
		_frenzied = true
		action_speed = affix(&"frenzy").speed
		set_stat_source(&"frenzy", [[&"move_speed", Stats.MUL, action_speed]])
	if has_affix(&"summoner"):
		_summon_timer -= dt
		if _summon_timer <= 0.0:
			var s := affix(&"summoner")
			_summon_timer = s.interval
			var alive := 0
			for e in world.enemies:
				if e is Enemy and (e as Enemy).summoner_id == id and not e.is_dead:
					alive += 1
			var nav := world.nav_for(def.radius)
			for i in mini(s.count, s.max_alive - alive):
				var a := world.rng.randf() * TAU
				var spread: float = s.spread
				var at := nav.nearest_walkable(pos + Vector2(sin(a), cos(a)) * spread)
				var minion := world.spawner.spawn_at(world, type, at)   # 叫出跟自己同一種的怪（設計方向）
				minion.summoner_id = id
				minion.no_souls = true
				minion.wave_member = wave_member


# 吸血詞條：造成傷害後回血（Combat 在命中後呼叫）
func on_dealt_damage(amount: float) -> void:
	if has_affix(&"vampiric") and amount > 0:
		heal(amount * affix(&"vampiric").lifesteal)


func wake() -> void:
	dormant = false


# 往 target 走時下一步要朝向的點：看得到就是 target 本身，被牆或墓碑擋住就走路徑點（每 repath_interval 秒重新判斷）
# 離目標超過 far_distance（視野外）改成每 repath_interval_far 秒，依 id 錯開；走近的那一步立刻重新判斷（弓手進射程不用舊的判斷）。Boss 照舊
func steer_point(target: Vector2) -> Vector2:
	var n: Dictionary = Config.NAV
	var far: bool = not is_boss() and pos.distance_squared_to(target) > n.far_distance * n.far_distance
	if _nav_far and not far:
		_nav_timer = 0.0
	_nav_far = far
	if _nav_timer <= 0.0:
		_nav_timer = n.repath_interval_far + (id % n.far_stagger_steps) * Config.FIXED_DT if far else n.repath_interval
		var nav := world.nav_for(radius)
		_path = PackedVector2Array() if nav.has_los(pos, target) else nav.find_path(pos, target)
		_on_nav_refresh(target)
	if _path.is_empty():
		return target
	var reach: float = n.waypoint_reach
	while _path.size() > 1 and pos.distance_squared_to(_path[0]) < reach * reach:
		_path.remove_at(0)
	return _path[0]


# 目前是否直接看得到目標（沒有在繞路）
func has_direct_path() -> bool:
	return _path.is_empty()


func _can_jump() -> bool:
	return true


# 子類別在重新判斷路線時順便更新自己的資料（例如弓手的射線）
func _on_nav_refresh(_target: Vector2) -> void:
	pass


# 跳上高台：站在地上往前走、前方的地面比腳下高（超過 step、不超過 climb_height）就先蹲 jump_windup 秒再起跳（同玩家的跳躍速度）
func _update_jump(dt: float) -> void:
	if _jump_windup > 0.0:
		velocity = Vector2.ZERO
		_jump_windup -= dt
		if _jump_windup <= 0.0 and not is_dead:
			vz = 4.0 * Config.JUMP.height / Config.JUMP.air_time
		return
	if _jump_dir != Vector2.ZERO:
		if is_grounded():
			_jump_dir = Vector2.ZERO
		elif not is_dead:
			# 空中往起跳方向至少 jump_air_speed：身體整個越過高台邊緣才落地（大隻的也站得上去）
			var along := velocity.dot(_jump_dir)
			if along < Config.NAV.jump_air_speed:
				velocity += _jump_dir * (Config.NAV.jump_air_speed - along)
			return
	if is_dead or velocity == Vector2.ZERO or not is_grounded() or not _can_jump():
		return
	var ahead := pos + velocity.normalized() * (radius + Config.NAV.jump_lookahead)
	if not world.terrain.may_rise(ahead, ground_height, Config.HEIGHT.step, Config.NAV.climb_height):
		return   # 附近沒有跳得上去的高低差（多數時候），不必逐一比對石台
	var rise := world.terrain.ground_at(ahead) - ground_height
	if rise > Config.HEIGHT.step and rise <= Config.NAV.climb_height:
		_jump_windup = Config.NAV.jump_windup
		_jump_dir = velocity.normalized()
		velocity = Vector2.ZERO


# 沿用同一個 Dictionary（D5：每步每隻配置新的太慢）；快照編碼時會複製成陣列
func _update_anim() -> void:
	anim.clear()
	anim["state"] = fsm.current_name
	anim["time"] = fsm.time
	# 道具狀態（v0.33.0）：只在有的時候放，快照不必多送
	if frozen_timer > 0.0:
		anim["frozen"] = true
		if ice_coffin:
			anim["coffin"] = true
	if poison_timer > 0.0:
		anim["poisoned"] = true
	if burn_timer > 0.0:
		anim["burning"] = true
		if burn_stacks > 1:
			anim["burn_stacks"] = burn_stacks
	if chill_stacks > 0:
		anim["chill"] = chill_stacks
	if stagger_timer > 0.0 or stun_timer > 0.0:
		anim["staggered"] = true   # 失衡與技能暈眩都是頭上冒星星
	if buried_timer > 0.0:
		anim["buried"] = true
	if grabbed_by != 0:
		anim["grabbed"] = true
	_anim_extra(anim)


# 子類別補上自己的動畫參數
func _anim_extra(_a: Dictionary) -> void:
	pass


func _on_damaged(_amount: float, _source_id: int) -> void:
	if pack_id >= 0 and dormant:
		world.wake_pack(pack_id)   # 被打（例如遠距離魔彈）整群醒來
	if not is_dead and not is_spawning() and not is_launching() and fsm.states.has(&"hurt") and not suppress_stagger:
		fsm.change(&"hurt")


func _on_died(source_id: int) -> void:
	action_speed = 1.0   # 爆炸延遲、屍體時間不受狂暴影響
	BondEffects.on_enemy_died(world, self)   # 燃燒傳給旁邊的怪、凍結中被殺沒有死亡效果（羈絆）
	fsm.change(&"dead")
	world.on_enemy_died(self, source_id)
	if ghost_of != 0:
		world.on_ghost_defeated(self)


# 死亡爆炸詞條：死後 delay 秒在屍體位置爆炸（擋不住；傷害含稀有度與詞條的攻擊力）
func _explode() -> void:
	_exploded = true
	var v := affix(&"volatile")
	var blast := Vector2(ground_height - Config.HEIGHT.reach_below, ground_height + Config.HEIGHT.explosion_height)
	world.emit_event("sfx:cue", {"cue": "explosion", "pos": pos})
	Hitbox.strike(world, self, pos, facing, {"shape": &"circle", "radius": v.radius}, {
		"damage": v.damage * damage_mul, "knockback": v.knockback, "origin": pos, "is_heavy": true,
		"band": blast, "blockable": false, "color": v.color,
	})
	world.emit_event("fx:explosion", {"pos": pos, "height": ground_height, "radius": v.radius, "color": v.color})


func remove() -> void:
	if world != null:
		for key: String in _cd_keys.values():
			world.cooldowns.reset(key)
	super()


func detach() -> void:
	super()
	fsm = null


# ───────── 共用狀態 ─────────

static func base_states() -> Dictionary:
	return {&"spawn": Spawn.new(), &"hurt": Hurt.new(), &"dead": Dead.new(), &"train": Train.new()}


# 武器測試場景的木樁（--weapon-test，2026-10-27）：main_state 設成 train，爬出、受擊後都回來站著，不移動、不攻擊
class Train:
	func update(e: Enemy, _dt: float, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO


# 從挖墳點噴出來（DigEvent._erupt）：照拋物線飛到落點，空中不行動、不硬直，落地後開始追
class Launch:
	func update(e: Enemy, _dt: float, fsm: StateMachine) -> void:
		if not fsm.data.has("velocity"):
			e.velocity = Vector2.ZERO   # 還沒呼叫 launch_to（不該發生）：當成一般出生
			fsm.change(e.main_state)
			return
		e.velocity = fsm.data.velocity
		var is_thrown: bool = fsm.data.has("thrown")
		if is_thrown:
			e._update_throw_path(fsm.data.thrown)
		if fsm.time >= fsm.data.flight_time * 0.5 and e.is_grounded():
			e.velocity = Vector2.ZERO
			var th: Dictionary = fsm.data.thrown if is_thrown else {}
			fsm.change(e.main_state)   # 會換掉 fsm.data
			if is_thrown:
				Enemy.land_throw(e, e.world.entities.get(th.source_id), th.land_hit, th.dir)


# 怪群休眠（D5）：站著不動，醒來（dormant = false）後直接開始追，不播爬出動畫
class Dormant:
	func update(e: Enemy, _dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		if not e.dormant:
			fsm.change(e.main_state)


class Spawn:
	func enter(e: Enemy, _data: Dictionary, _fsm: StateMachine) -> void:
		e.world.emit_event("sfx:cue", {"cue": "enemySpawn", "pos": e.pos})
		if e.def.has("spawn_shake"):
			e.world.emit_event("camera:shake", {"amount": e.def.spawn_shake, "duration": e.def.spawn_time})

	func update(e: Enemy, _dt: float, fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO
		if fsm.time >= e.def.spawn_time:
			fsm.change(e.main_state)


class Hurt:
	func enter(e: Enemy, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO

	func update(e: Enemy, _dt: float, fsm: StateMachine) -> void:
		if fsm.time >= e.def.hurt_time:
			fsm.change(e.main_state)


# 終止狀態：倒下、沉入地面後移除（動畫在畫面層）
class Dead:
	func enter(e: Enemy, _data: Dictionary, _fsm: StateMachine) -> void:
		e.velocity = Vector2.ZERO

	func update(e: Enemy, _dt: float, fsm: StateMachine) -> void:
		if e.has_affix(&"volatile") and not e._exploded and not e.no_death_effect and not e.world.is_over and fsm.time >= e.affix(&"volatile").delay:
			e._explode()
		if fsm.time >= e.def.corpse_time:
			e.remove()
