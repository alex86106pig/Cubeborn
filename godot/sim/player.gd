# 玩家：讀取 InputCmd、雙層狀態機（移動層 / 動作層）、武器、輸入緩衝、主動欄位與增益效果；照搬網頁版 Player.js
# 裝備欄、背包、道具、合成、丟棄在 Loadout（sim/loadout.gd）；這裡保留原本的名稱轉過去，外部程式照舊用 player.add_item() 等
class_name Player
extends Entity

const ROLL_CD := "player.roll"
const PARRY_ANIM_TIME := 0.2

var peer_id := 0
var move_input := Vector2.ZERO
var aim_point := Vector2(0.0, 5.0)
var is_attack_held := false
var is_special_held := false           # 右鍵按住（劍盾按住格擋，v0.41.0）
var attack_pressed := false            # 本步剛按下左鍵（格擋中按左鍵 = 招架）
var _attack_was_held := false
var weapon: Dictionary = {}            # 手上武器的招式資料（WeaponDefs）
var weapon_id: StringName = &""
var class_id := ClassDefs.NONE        # 職業（F2，ClassDefs）；NONE = 共用基準數值
var loadout := Loadout.new()           # 裝備欄、背包、生效的道具（sim/loadout.gd）
var weapon_slots: Array[Dictionary]:   # 裝備欄 2 格（D4）：武器實例（WeaponDropDefs）或 {}
	get:
		return loadout.weapon_slots
var active_slot: int:
	get:
		return loadout.active_slot
	set(value):
		loadout.active_slot = value
var items: Array[Dictionary]:          # 背包裡生效的道具實例 { uid, id }；uid 同時是屬性加成的來源名稱
	get:
		return loadout.items
var inventory: Inventory:              # 背包的擺放（D3）；items 與它同步
	get:
		return loadout.inventory
var _applied_weapon_uid := &""
var _air_jumps_used := 0               # 這次離地後用掉的空中跳躍（落地歸零）
var descended := false                 # 已走進出口（D6）：等其他人到齊才換層，期間不見、不能被打
var stun_timer := 0.0                  # 暈眩剩餘秒數（v0.27.0：Boss 衝鋒撞到）：不能移動、出招、翻滾、跳
var combo_step := 0
var combo_timer := 0.0
var buffered_action: Dictionary = {}   # { type: &"special" | &"slot" | &"roll", index?, time }；空 = 沒有緩衝
var slots := ActiveSlots.new(Config.PLAYER.slots)
var buffs: Dictionary = {}             # id -> { remaining, stats?（屬性加成，見 sim/stats.gd）, trail_color? }
var kill_timers: Dictionary = {}       # 道具 uid -> 「擊殺後幾秒」條件剩下的秒數（sim/item_effects.gd）
var roll_charges := 0                  # 目前可用的翻滾次數（上限為 roll_charges 屬性）
var dodge_timer := 0.0                 # 翻滾無敵剩餘秒數
var block_time := -1.0                 # 格擋開始後經過的秒數；< 0 = 沒有在格擋（weapon_behaviors 的 ShieldBlock）
var parry_time := -1.0                 # 招架判定開始後經過的秒數；< 0 = 沒有在招架（v0.41.0）
var pending_parry := false             # 本步招架成功，下一步開頭執行盾反
var parry_timer := 0.0                 # 盾反動作剩餘秒數（畫面用）
var is_interact_held := false          # F 按住（救援隊友）；剛按下那一步撿道具 / 開寶箱（D3）
var view_tick := 0                     # 最近一筆輸入的畫面時間（InputCmd.view_tick；房主延遲補償用，v0.38.0）
var _interact_was_held := false
var is_downed := false                 # 倒地假死（C4）：倒數 down_timer 秒，隊友救起前不能動
var down_timer := 0.0
var revive_progress := 0.0             # 隊友已累積的救援秒數（到 REVIVE.revive_time 救起）
var revive_target_id := 0              # 自己正在救的倒地隊友（實體 id；0 = 沒有在救）
var forced_velocity := Vector2.ZERO
var has_forced_velocity := false
var locomotion: StateMachine
var action: StateMachine
# 畫面層算姿勢用的資料（PROJECT_GUIDELINES.md 第 11 節）：只放名稱與數值，連線時同步這份就能畫出同樣動作
var anim: Dictionary = {}

var _pressed := 0   # 本步按下的按鈕；讀過就清除，沒收到新輸入時不會重複觸發


func _init(p_world: World, p_peer_id: int) -> void:
	super(p_world, &"player", &"player", Config.PLAYER.radius, Config.PLAYER.max_hp, Config.PLAYER.mass)
	stats.set_base(&"move_speed", Config.PLAYER.move_speed)
	peer_id = p_peer_id
	locomotion = StateMachine.new(self, PlayerStates.locomotion_states(), &"idle")
	action = StateMachine.new(self, PlayerStates.action_states())
	equip_weapon(Config.PLAYER.start_weapon)
	roll_charges = roll_max()
	_update_anim()


# 跳躍：站在地面上隨時可以跳（攻擊、翻滾中也行），受擊硬直與倒地時不行；只有一段跳
func try_jump() -> bool:
	if is_dead or is_downed or action.is_in(&"stagger") or action.is_in(&"revive") or action.is_in(&"dig"):
		return false
	if not is_grounded():
		# 二段跳（道具能力 double_jump，v0.27.0）：空中可以再跳一次，高度同第一段（從目前高度往上 JUMP.height）
		if _air_jumps_used >= air_jumps():
			return false
		_air_jumps_used += 1
	vz = 4.0 * Config.JUMP.height / Config.JUMP.air_time
	return true


# 被擊飛（v0.27.0：Boss 砸地）：往上給一個速度，照常受重力落地
func knock_up(speed: float) -> void:
	if is_dead or is_downed:
		return
	vz = maxf(vz, speed)


# 暈眩（v0.27.0：Boss 衝鋒）：期間不能移動、出招、翻滾、跳；動作中斷
func stun(duration: float) -> void:
	if is_dead or is_downed:
		return
	stun_timer = maxf(stun_timer, duration)
	if not action.is_in(&"dig"):   # 挖墳被打不中斷（D6）
		action.change(&"ready")
	buffered_action = {}
	world.emit_event("player:stunned", {"player_id": id, "duration": duration})


# 空中還能跳幾次：背包裡每個有 double_jump 能力的道具 +1（同一種拿兩個也只算 1 次）
func air_jumps() -> int:
	for it: Dictionary in items:
		for eff: Dictionary in ItemDefs.ITEMS[it.id].effects:
			if eff.get("ability", &"") == &"double_jump":
				return 1
	return 0


# 由 Combat.apply_damage 對能格擋的攻擊呼叫：格擋中、攻擊來自正前方 block_arc 內就擋下（不扣血、自己被推退一點）
# from 是攻擊來的位置（近戰為攻擊者、投射物為飛來的方向）；招架判定中（parry_time）擋下 = 招架成功，下一步全額盾反（v0.41.0）
func try_block(from: Vector2, hit: Dictionary) -> bool:
	if block_time < 0.0:
		return false
	var def: Dictionary = weapon.special
	var to_source := from - pos
	if to_source.length_squared() > 1e-6:
		if absf(angle_difference(facing, atan2(to_source.x, to_source.y))) > def.block_arc / 2.0:
			return false
		# 攻擊可以指定擋下時的推退比例（Boss 衝鋒 100%），沒指定就用盾的 block_knockback_mul（30%）
		var push_mul: float = hit.get("block_knockback_mul", def.block_knockback_mul)
		knockback -= to_source.normalized() * (hit.get("knockback", 0.0) * push_mul / mass)
	# perfect：招架成功（事件名稱沿用；HUD 顯示「招架！」）
	var perfect := parry_time >= 0.0
	world.emit_event("player:blocked", {"player_id": id, "perfect": perfect})
	world.emit_event("sfx:cue", {"cue": def.sfx_parry if perfect else def.sfx_block, "pos": pos})
	if perfect:
		parry_time = -1.0
		pending_parry = true
	return true


# 盾反：招架成功時全額、判定時間內沒擋到時傷害 × fail_damage_mul（v0.41.0）；之後右鍵還按著就繼續格擋
# 招架成功由房主的格擋判定觸發、客戶端沒辦法預測，事件不標行動者（客戶端照常播）
func _parry(success: bool) -> void:
	var actor := world.event_actor
	if success:
		world.event_actor = 0
	_do_parry(success)
	world.event_actor = actor


func _do_parry(success: bool = true) -> void:
	var pr: Dictionary = weapon.special.parry
	var mul: float = 1.0 if success else pr.fail_damage_mul
	Hitbox.strike(world, self, pos, facing, {"shape": &"sector", "range": pr.range, "arc": pr.arc}, {
		"damage": move_damage(pr) * mul, "damage_type": weapon.damage_type, "knockback": pr.knockback * mul, "hit_stop": pr.hit_stop,
		"shake": pr.shake * mul, "is_heavy": success, "blockable": false, "color": pr.color,
	})
	world.emit_event("fx:parry", {"pos": pos, "height": height, "radius": pr.range, "facing": facing, "arc": pr.arc, "color": pr.color})
	parry_timer = PARRY_ANIM_TIME


func roll_max() -> int:
	return int(stats.value(&"roll_charges"))


# CD 的實際 key：每位玩家各自計時（多人時大家都有 player.special）；事件與 HUD 仍用 key 本身
func cd(key: String) -> String:
	return "%s@%d" % [key, peer_id]


func can_be_hit() -> bool:
	return super() and not is_downed and not descended


func is_targetable() -> bool:
	return not is_dead and not is_downed and not descended


# ───────── 挖墳、下一層、屍體（D6）─────────

static func corpse_uid(p_peer_id: int) -> StringName:
	return StringName("corpse_%d" % p_peer_id)


func is_digging() -> bool:
	return not is_dead and not is_downed and not descended and action != null and action.is_in(&"dig")


# 走進出口：從這一層消失（不能被打、不被追），等其他人
func descend() -> void:
	descended = true
	velocity = Vector2.ZERO
	has_forced_velocity = false
	buffered_action = {}
	action.change(&"ready")
	world.emit_event("player:descended", {"player_id": id})


# 新的一層：回到出生點（死者也搬過去，等冤魂被打倒才在冤魂的位置站起來）
func arrive_floor(at: Vector2, ground: float) -> void:
	descended = false
	pos = at
	prev_pos = at
	height = ground
	prev_height = ground
	vz = 0.0
	knockback = Vector2.ZERO
	velocity = Vector2.ZERO


# 冤魂被打倒：在 at 復活，生命 = 最大生命 × ratio，短暫無敵
func resurrect(at: Vector2, ratio: float) -> void:
	is_dead = false
	is_downed = false
	down_timer = 0.0
	revive_progress = 0.0
	pos = at
	height = world.terrain.ground_at(at)
	hp = maxf(1.0, roundf(max_hp * ratio))
	invuln_timer = Config.REVIVE.revive_invuln
	action.change(&"ready")
	locomotion.change(&"idle")
	world.emit_event("player:revived", {"player_id": id})


func add_corpse(owner_peer: int) -> bool:
	return loadout.add_corpse(self, owner_peer)


# 範圍內最近的倒地隊友（救援對象）；沒有回傳 null
func find_revive_target() -> Player:
	var best: Player = null
	var best_d: float = Config.REVIVE.range
	for p: Player in world.players.values():
		if p == self or not p.is_downed:
			continue
		var d := p.pos.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = p
	return best


# 多人時生命歸零先倒地假死（C4）；單機、或已經倒地後倒數結束 / 全員倒下，才真的死亡
func die(source_id: int = 0) -> void:
	if is_dead:
		return
	if not is_downed and world.players.size() > 1:
		_go_down()
		return
	super(source_id)


func _go_down() -> void:
	is_downed = true
	hp = 0.0
	down_timer = Config.REVIVE.down_time
	revive_progress = 0.0
	velocity = Vector2.ZERO
	buffered_action = {}
	action.change(&"ready")   # 讓進行中的動作執行 exit 清理
	has_forced_velocity = false
	locomotion.change(&"downed")
	world.emit_event("player:downed", {"player_id": id})


# 救起：回到最大生命的 REVIVE.revive_hp_ratio，短暫無敵
func revive() -> void:
	is_downed = false
	down_timer = 0.0
	revive_progress = 0.0
	hp = maxf(1.0, roundf(max_hp * Config.REVIVE.revive_hp_ratio))
	invuln_timer = Config.REVIVE.revive_invuln
	locomotion.change(&"idle")
	world.emit_event("player:revived", {"player_id": id})


# 客戶端自己的角色（C3）：倒地 / 死亡以房主為準，本機狀態機跟著切換（不發事件，事件由房主送來）
func net_sync_life(dead: bool, downed: bool, p_down_timer: float, p_revive: float) -> void:
	down_timer = p_down_timer
	revive_progress = p_revive
	if dead and not is_dead:
		is_dead = true
		is_downed = false
		action.change(&"ready")
		has_forced_velocity = false
		velocity = Vector2.ZERO
		locomotion.change(&"dead")
	elif downed and not is_downed and not is_dead:
		is_downed = true
		action.change(&"ready")
		has_forced_velocity = false
		velocity = Vector2.ZERO
		locomotion.change(&"downed")
	elif not downed and is_downed:
		is_downed = false
		locomotion.change(&"idle")
	elif not dead and is_dead:   # 冤魂被打倒、在下一層復活（D6）
		is_dead = false
		locomotion.change(&"idle")


# 客戶端自己的角色被房主判定打中：受擊硬直與無敵在本機立刻反應（同 _on_damaged，但不扣血、不發事件）
func net_hurt() -> void:
	if is_dead or is_downed:
		return
	flash_timer = Config.COMBAT.flash_time
	invuln_timer = Config.PLAYER.invuln_time
	if not action.is_in(&"special"):
		action.change(&"stagger")


# Q / 滑鼠滾輪（D4）：換到另一格裝備欄的武器
func swap_weapon() -> void:
	loadout.swap(self)


func is_dodging() -> bool:
	return dodge_timer > 1e-6


# 翻滾的位移速度：基礎距離 ÷ 時間，再依移速屬性相對基礎移速等比放大（動作中的走路減速不算）
func roll_speed() -> float:
	return Config.ROLL.distance / Config.ROLL.duration * stats.value(&"move_speed") / Config.PLAYER.move_speed


# 充能：回充中（ROLL_CD 計時）結束就加 1 次，還沒滿就接著回充下一次；上限提高時立刻補 1 次
func _tick_roll_charges() -> void:
	var max_charges := roll_max()
	roll_charges = mini(roll_charges, max_charges)
	if roll_charges < max_charges and world.cooldowns.is_ready(cd(ROLL_CD)):
		roll_charges += 1
		if roll_charges < max_charges:
			world.cooldowns.start(cd(ROLL_CD), roll_cooldown())


func roll_cooldown() -> float:
	return Config.ROLL.cooldown * stats.value(&"roll_cooldown")


# 消耗 1 次充能；沒有在回充時開始回充
func consume_roll_charge() -> void:
	roll_charges -= 1
	if world.cooldowns.is_ready(cd(ROLL_CD)):
		world.cooldowns.start(cd(ROLL_CD), roll_cooldown())


# 權威端不信任輸入：移動向量長度一律限制在 1 以內
func apply_cmd(cmd: InputCmd) -> void:
	move_input = cmd.move.limit_length(1.0)
	aim_point = cmd.aim
	is_attack_held = cmd.has(InputCmd.BTN_ATTACK)
	is_special_held = cmd.has(InputCmd.BTN_SPECIAL_HELD)
	is_interact_held = cmd.has(InputCmd.BTN_INTERACT)
	_pressed |= cmd.buttons
	loadout.queue_ops(cmd.inv_ops)
	view_tick = cmd.view_tick


# 套用職業（F2）：基礎數值、起始武器、被動（屬性來源 &"class"）；開局時 World.reset 呼叫，NONE 不改
func apply_class(id: StringName) -> void:
	class_id = id
	if id == ClassDefs.NONE:
		return
	var c: Dictionary = ClassDefs.CLASSES[id]
	for stat: StringName in c.stats:
		stats.set_base(stat, c.stats[stat])
	set_stat_source(&"class", c.passive.get("mods", []))
	equip_weapon(c.weapon)
	hp = max_hp


# 職業被動的一個欄位（ClassDefs passive）；沒選職業或沒有這個欄位回傳 default
func class_passive(key: String, default: Variant) -> Variant:
	if class_id == ClassDefs.NONE:
		return default
	return ClassDefs.CLASSES[class_id].passive.get(key, default)


# 被隊友（誤傷）打到時的傷害倍率：守墓騎士被動，攻擊來自背後（和面向差超過 90°）才減傷（F2）
func friendly_back_mul(from: Vector2) -> float:
	if class_id == ClassDefs.NONE:
		return 1.0
	var mul: float = class_passive("friendly_back_mul", 1.0)
	var d := from - pos
	if mul == 1.0 or d.length_squared() < 1e-6:
		return 1.0
	return mul if absf(MathUtil.wrap_angle(atan2(d.x, d.y) - facing)) > PI / 2.0 else 1.0


func equip_weapon(id: StringName) -> void:
	loadout.equip_new(self, id)


# 套用手上那格武器：招式資料與詞條（只有手上的那把生效，屬性來源 &"weapon"）；Loadout 換了武器就呼叫
func apply_active_weapon() -> void:
	if weapon_slots[active_slot].is_empty():
		active_slot = 1 - active_slot
	var inst: Dictionary = weapon_slots[active_slot]
	if inst.is_empty():
		return
	# 換了一把（uid 不同）才重設連段與動作；只是合成 / 搬動別的武器時不打斷手上的動作
	show_weapon(ItemDefs.ITEMS[inst.base].weapon, inst.uid != _applied_weapon_uid)
	_applied_weapon_uid = inst.uid
	set_stat_source(&"weapon", WeaponDropDefs.stat_mods(inst))


# 只換招式資料與模型（客戶端畫別人的角色也用這個）；force 時同一種也重設連段與動作
func show_weapon(id: StringName, force := false) -> void:
	if weapon_id == id and not force:
		return
	weapon = WeaponDefs.WEAPONS[id]
	weapon_id = id
	combo_step = 0
	combo_timer = 0.0
	action.change(&"ready")


func active_weapon() -> Dictionary:
	return loadout.active_weapon()


# 招式傷害 = 武器基礎傷害 × 招式 % × 攻擊力 × 物理 / 魔法傷害（F1）
func move_damage(move: Dictionary) -> float:
	return WeaponDefs.move_base_damage(weapon, move) * damage_mul * stats.value(StatDefs.type_damage_stat(weapon.damage_type))


func weapon_range_mul() -> float:
	return loadout.weapon_range_mul()


func add_weapon(inst: Dictionary) -> bool:
	return loadout.add_weapon(self, inst)


# 增益：同一個 id 再加一次會重新計時；mods.stats 以增益 id 為來源套上屬性加成，到期時移除
func add_buff(id: StringName, duration: float, mods: Dictionary) -> void:
	var buff := mods.duplicate()
	buff["remaining"] = duration
	buffs[id] = buff
	if buff.has("stats"):
		set_stat_source(id, buff.stats)


func add_item(item_id: StringName) -> StringName:
	return loadout.add_item(self, item_id)


func remove_item(uid: StringName) -> void:
	loadout.remove_item(self, uid)


func sync_inventory(arr: Array) -> void:
	loadout.sync_inventory(self, arr)


func sync_weapon_slots(arr: Array, p_active: int) -> void:
	loadout.sync_weapon_slots(self, arr, p_active)


# 剛按下 F：附近有倒地隊友時讓給救援（動作層 Ready 處理）；否則先撿最近的道具，沒有道具才開最近的寶箱
func _try_interact() -> void:
	if find_revive_target() != null:
		return
	var pickup := world.nearest_interactable(self, world.pickups)
	if pickup != null:
		var ip := pickup as ItemPickup
		var taken: bool
		if ip.corpse_of != 0:
			taken = add_corpse(ip.corpse_of)
		elif ip.is_weapon():
			taken = add_weapon(ip.weapon)
		else:
			taken = add_item(ip.item_id) != &""
		if taken:
			pickup.remove()
		return
	var chest := world.nearest_interactable(self, world.chests)
	if chest != null:
		(chest as Chest).try_open(self)


func clear_items() -> void:
	loadout.clear_items(self)


func update(dt: float) -> void:
	_tick_timers(dt)
	if is_dead or is_downed or descended or stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - dt)
		if stun_timer > 0.0:
			move_input = Vector2.ZERO   # 暈眩時站著不動（移動層回到 idle）
		_pressed = 0
		loadout.clear_ops()
		_interact_was_held = is_interact_held
		_attack_was_held = is_attack_held
		velocity = Vector2.ZERO
		locomotion.update(dt)
		_update_anim()
		return

	if is_grounded():
		_air_jumps_used = 0
	_read_input()
	# 撿道具、開寶箱、整理背包只在權威端（客戶端本機預測不做，等快照）
	if world.is_authority:
		if is_interact_held and not _interact_was_held:
			_try_interact()
		loadout.apply_ops(self)
	else:
		loadout.clear_ops()
	_interact_was_held = is_interact_held
	attack_pressed = is_attack_held and not _attack_was_held
	_attack_was_held = is_attack_held
	if pending_parry:
		pending_parry = false
		if block_time >= 0.0:
			_parry(true)
	action.update(dt)

	var data := action.data
	if has_forced_velocity:
		velocity = forced_velocity
	else:
		var slow: float = data.get("move_speed_mul", 1.0)
		if action.is_in(&"attack") and class_passive("attack_no_slow", false):
			slow = 1.0   # 盜墓遊俠被動：移動中普攻不減速（F4）
		velocity = move_input * (stats.value(&"move_speed") * slow)

	if not data.get("lock_facing", false):
		var target := MathUtil.angle_to(pos, aim_point)
		facing = MathUtil.turn_towards(facing, target, Config.PLAYER.turn_speed * dt)

	locomotion.update(dt)
	_update_anim()


func _tick_timers(dt: float) -> void:
	combo_timer = maxf(0.0, combo_timer - dt)
	dodge_timer = maxf(0.0, dodge_timer - dt)
	parry_timer = maxf(0.0, parry_timer - dt)
	_tick_roll_charges()
	ItemEffects.update_player(self, dt)   # 低血、擊殺後的道具條件加成（v0.33.0）
	for id: StringName in buffs.keys():
		buffs[id].remaining -= dt
		if buffs[id].remaining <= 0.0:
			if buffs[id].has("stats"):
				remove_stat_source(id)
			buffs.erase(id)
	if not buffered_action.is_empty():
		buffered_action.time -= dt
		if buffered_action.time <= 0.0:
			buffered_action = {}


func _read_input() -> void:
	var buffer_time: float = Config.PLAYER.action_buffer_time
	if _pressed & InputCmd.BTN_SPECIAL:
		buffered_action = {"type": &"special", "time": buffer_time}
	if _pressed & InputCmd.BTN_ROLL:
		buffered_action = {"type": &"roll", "time": buffer_time}
	if _pressed & InputCmd.BTN_JUMP:
		try_jump()
	if _pressed & InputCmd.BTN_SWAP_WEAPON:
		swap_weapon()
	for i in ActiveSlots.SLOT_COUNT:
		if _pressed & InputCmd.slot_bit(i):
			buffered_action = {"type": &"slot", "index": i, "time": buffer_time}
	_pressed = 0


# 目前的殘影顏色（最後加上的增益優先）；沒有則為 null
func trail_color() -> Variant:
	var color: Variant = null
	for buff: Dictionary in buffs.values():
		if buff.has("trail_color"):
			color = buff.trail_color
	return color


func _update_anim() -> void:
	var d := action.data
	var timed := d.has("phase_index")
	anim = {
		"loco": locomotion.current_name,
		"loco_time": locomotion.time,
		"action": action.current_name,
		"action_time": action.time,
		"behavior": d.def.behavior if timed else &"",
		"phase": PlayerStates.PHASES[d.phase_index] if timed and d.phase_index < PlayerStates.PHASES.size() else &"",
		"k": d.get("k", 0.0),
		"swing_dir": d.get("swing_dir", 1),
		"is_finisher": d.get("is_finisher", false),
		"trail_color": trail_color(),   # 疾跑殘影（特效里程碑再畫）
		"airborne": not is_grounded(),
		"blocking": block_time >= 0.0,
		"parry": parry_timer / PARRY_ANIM_TIME,   # 1 → 0（盾反剛發動到結束）
		"vz": vz,
		"revive": revive_progress / Config.REVIVE.revive_time,   # 倒地時被救的進度 0~1（畫面顯示用）
		"stunned": stun_timer > 0.0,
	}


func _on_damaged(amount: float, _source_id: int) -> void:
	if is_dead or amount <= 0:
		return
	invuln_timer = Config.PLAYER.invuln_time
	# player_id：多人時只有被打的那位玩家的畫面震動
	world.emit_event("camera:shake", {"amount": Config.PLAYER.hurt_shake, "duration": Config.PLAYER.hurt_shake_duration, "player_id": id})
	# 特殊技期間（含按住格擋）有霸體，不會被打斷；挖墳被打也不中斷（D6）
	if not action.is_in(&"special") and not action.is_in(&"dig"):
		action.change(&"stagger")


# 狀態機的 ctx 指回玩家，也要切斷
func detach() -> void:
	super()
	locomotion = null
	action = null


func _on_died(_source_id: int) -> void:
	var was_downed := is_downed
	is_downed = false
	hp = 0.0
	action.change(&"ready")   # 讓進行中的動作執行 exit 清理
	has_forced_velocity = false
	locomotion.change(&"dead")
	if was_downed:
		locomotion.time = Config.REVIVE.down_time   # 已經躺在地上：倒地動畫直接播完，不會先站起來再倒一次
	world.emit_event("player:died", {"player_id": id})
	# 多人時留下屍體（D6）：隊友撿進背包帶到下一層，就會在那裡變成冤魂
	if world.is_authority and world.players.size() > 1:
		world.drop_corpse(peer_id, pos)
