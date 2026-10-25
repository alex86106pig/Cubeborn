# 玩家：讀取 InputCmd、雙層狀態機（移動層 / 動作層）、武器、輸入緩衝、主動欄位與增益效果；照搬網頁版 Player.js
class_name Player
extends Entity

const ROLL_CD := "player.roll"
const PARRY_ANIM_TIME := 0.2

var peer_id := 0
var move_input := Vector2.ZERO
var aim_point := Vector2(0.0, 5.0)
var is_attack_held := false
var weapon: Dictionary = {}            # 手上武器的招式資料（WeaponDefs）
var weapon_id: StringName = &""
var weapon_slots: Array[Dictionary] = [{}, {}]   # 裝備欄 2 格（D4）：武器實例（WeaponDropDefs）或 {}
var active_slot := 0
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
var pending_parry := false             # 本步完美格擋，下一步開頭執行盾反
var parry_timer := 0.0                 # 盾反動作剩餘秒數（畫面用）
var items: Array[Dictionary] = []     # 背包裡生效的道具實例 { uid, id }；uid 同時是屬性加成的來源名稱
var inventory := Inventory.new()       # 背包的擺放（D3）；items 與它同步
var _next_item_uid := 1
var is_interact_held := false          # F 按住（救援隊友）；剛按下那一步撿道具 / 開寶箱（D3）
var view_tick := 0                     # 最近一筆輸入的畫面時間（InputCmd.view_tick；房主延遲補償用，v0.38.0）
var _interact_was_held := false
var _inventory_ops: Array = []         # 本步收到的背包操作（InputCmd.inv_ops），只在權威端執行
var is_downed := false                 # 倒地假死（C4）：倒數 down_timer 秒，隊友救起前不能動
var down_timer := 0.0
var revive_progress := 0.0             # 隊友已累積的救援秒數（到 REVIVE.revive_time 救起）
var revive_target_id := 0              # 自己正在救的倒地隊友（實體 id；0 = 沒有在救）
var forced_velocity := Vector2.ZERO
var has_forced_velocity := false
var locomotion: StateMachine
var action: StateMachine
# 畫面層算姿勢用的資料（15.5）：只放名稱與數值，連線時同步這份就能畫出同樣動作
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
# from 是攻擊來的位置（近戰為攻擊者、投射物為飛來的方向）；按下格擋後 perfect_window 內擋下 = 完美格擋，下一步盾反
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
	var perfect: bool = block_time <= def.perfect_window + 1e-6
	world.emit_event("player:blocked", {"player_id": id, "perfect": perfect})
	world.emit_event("sfx:cue", {"cue": def.sfx_parry if perfect else def.sfx_block})
	if perfect:
		pending_parry = true
	return true


# 盾反：對前方扇形造成傷害（隨攻擊力），然後結束格擋
# 盾反由房主的格擋判定觸發、客戶端沒辦法預測，事件不標行動者（客戶端照常播）
func _parry() -> void:
	var actor := world.event_actor
	world.event_actor = 0
	_do_parry()
	world.event_actor = actor


func _do_parry() -> void:
	var pr: Dictionary = weapon.special.parry
	Hitbox.strike(world, self, pos, facing, {"shape": &"sector", "range": pr.range, "arc": pr.arc}, {
		"damage": pr.damage * damage_mul, "knockback": pr.knockback, "hit_stop": pr.hit_stop,
		"shake": pr.shake, "is_heavy": true, "blockable": false, "color": pr.color,
	})
	world.emit_event("fx:parry", {"pos": pos, "height": height, "radius": pr.range, "facing": facing, "arc": pr.arc, "color": pr.color})
	parry_timer = PARRY_ANIM_TIME
	action.change(&"ready")


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


# 撿起隊友的屍體放進背包（占 corpse 形狀的格子、沒有效果）；放不下回傳 false 並發出 inventory:full
func add_corpse(owner_peer: int) -> bool:
	var spot := inventory.find_spot(&"corpse")
	if spot.is_empty():
		world.emit_event("inventory:full", {"player_id": id, "item": "corpse"})
		return false
	inventory.add(corpse_uid(owner_peer), &"corpse", spot.cell, spot.rot)
	world.emit_event("item:added", {"player_id": id, "item": "corpse", "uid": String(corpse_uid(owner_peer))})
	return true


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


# Q / 滑鼠滾輪（D4）：換到另一格裝備欄的武器；另一格是空的就不換
func swap_weapon() -> void:
	var other := 1 - active_slot
	if not weapon_slots[other].is_empty():
		active_slot = other
		_apply_active_weapon()


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
	is_interact_held = cmd.has(InputCmd.BTN_INTERACT)
	_pressed |= cmd.buttons
	_inventory_ops.append_array(cmd.inv_ops)
	view_tick = cmd.view_tick


# 把手上這格換成一把新的白色武器（開場、--weapon、測試與除錯用；正式取得武器走 add_weapon）
func equip_weapon(id: StringName) -> void:
	assert(WeaponDefs.WEAPONS.has(id), "Unknown weapon: %s" % id)
	weapon_slots[active_slot] = {"uid": world.new_weapon_uid(), "base": id, "rarity": &"white", "affixes": [] as Array[StringName]}
	_apply_active_weapon()


# 套用手上那格武器：招式資料與詞條（只有手上的那把生效，屬性來源 &"weapon"）
func _apply_active_weapon() -> void:
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
	return weapon_slots[active_slot]


# 手上武器稀有度的範圍倍率（揮砍距離、魔彈射程）
func weapon_range_mul() -> float:
	var inst := active_weapon()
	return WeaponDropDefs.RARITY_BASE[inst.rarity].range if not inst.is_empty() else 1.0


# 撿到武器（D4）：裝備欄有空先放裝備欄（不換手上的），滿了放背包；都放不下回傳 false、發出 inventory:full
func add_weapon(inst: Dictionary) -> bool:
	for i in weapon_slots.size():
		if weapon_slots[i].is_empty():
			weapon_slots[i] = inst
			world.emit_event("weapon:added", {"player_id": id, "uid": String(inst.uid), "slot": i})
			return true
	var spot := inventory.find_spot(inst.base)
	if spot.is_empty():
		world.emit_event("inventory:full", {"player_id": id, "item": String(inst.base)})
		return false
	inventory.add(inst.uid, inst.base, spot.cell, spot.rot, inst)
	world.emit_event("weapon:added", {"player_id": id, "uid": String(inst.uid), "slot": -1})
	return true


# 依 uid 找武器在哪：{ slot: 0 / 1 } 或 { bag: 背包條目 }；找不到回傳 {}
func _find_weapon(uid: StringName) -> Dictionary:
	for i in weapon_slots.size():
		if not weapon_slots[i].is_empty() and weapon_slots[i].uid == uid:
			return {"slot": i, "inst": weapon_slots[i]}
	var e := inventory.find(uid)
	if not e.is_empty() and e.has("weapon"):
		return {"bag": e, "inst": e.weapon}
	return {}


func _take_weapon(where: Dictionary) -> void:
	if where.has("slot"):
		weapon_slots[where.slot] = {}
	else:
		inventory.remove(where.bag.uid)


# 武器放進裝備欄 slot：從另一格來就互換；從背包來時原本那把放回背包（放不下就不換）
func _equip_from(uid: StringName, slot: int) -> bool:
	var src := _find_weapon(uid)
	if src.is_empty() or slot < 0 or slot >= weapon_slots.size():
		return false
	if src.has("slot"):
		var tmp: Dictionary = weapon_slots[slot]
		weapon_slots[slot] = weapon_slots[src.slot]
		weapon_slots[src.slot] = tmp
	else:
		var old: Dictionary = weapon_slots[slot]
		inventory.remove(uid)
		if not old.is_empty():
			var spot := inventory.find_spot(old.base)
			if spot.is_empty():
				inventory.add(uid, src.bag.id, src.bag.cell, src.bag.rot, src.inst)
				return false
			inventory.add(old.uid, old.base, spot.cell, spot.rot, old)
		weapon_slots[slot] = src.inst
	_apply_active_weapon()
	return true


# 把武器 a 拖到 b 上面合成（D4）：同種、同稀有度才行；b 的位置換成高一級、詞條重新抽的新武器，a 消失
func _merge(uid_a: StringName, uid_b: StringName) -> bool:
	var a := _find_weapon(uid_a)
	var b := _find_weapon(uid_b)
	if a.is_empty() or b.is_empty() or not WeaponDropDefs.can_merge(a.inst, b.inst):
		world.emit_event("weapon:merge_denied", {"player_id": id})
		return false
	var merged := WeaponDropDefs.make(b.inst.uid, b.inst.base, WeaponDropDefs.next_rarity(b.inst.rarity), world.rng)
	if a.has("slot") and b.has("bag") and _equipped_count() <= 1:
		# 手上唯一的一把拖到背包的武器上：合成結果留在裝備欄（手上不能沒有武器），背包那把消失
		inventory.remove(b.bag.uid)
		weapon_slots[a.slot] = merged
	elif b.has("slot"):
		_take_weapon(a)
		weapon_slots[b.slot] = merged
	else:
		_take_weapon(a)
		b.bag.weapon = merged
	_apply_active_weapon()
	world.emit_event("weapon:merged", {"player_id": id, "uid": String(merged.uid), "base": String(merged.base), "rarity": String(merged.rarity)})
	return true


# 增益：同一個 id 再加一次會重新計時；mods.stats 以增益 id 為來源套上屬性加成，到期時移除
func add_buff(id: StringName, duration: float, mods: Dictionary) -> void:
	var buff := mods.duplicate()
	buff["remaining"] = duration
	buffs[id] = buff
	if buff.has("stats"):
		set_stat_source(id, buff.stats)


# 道具放進背包（D3）：自動放到第一個放得下的位置，放進去就生效（屬性效果以實例 uid 為來源套上）；武器則直接換上
# 同一個道具拿兩個就是兩個實例、加成相加。背包放不下時回傳 &""、發出 inventory:full
func add_item(item_id: StringName) -> StringName:
	assert(ItemDefs.ITEMS.has(item_id), "Unknown item: %s" % item_id)
	var def: Dictionary = ItemDefs.ITEMS[item_id]
	var uid := &""
	if def.kind == &"weapon":
		equip_weapon(def.weapon)
	else:
		var spot := inventory.find_spot(item_id)
		if spot.is_empty():
			world.emit_event("inventory:full", {"player_id": id, "item": String(item_id)})
			return &""
		uid = StringName("item_%d" % _next_item_uid)
		_next_item_uid += 1
		inventory.add(uid, item_id, spot.cell, spot.rot)
		items.append({"uid": uid, "id": item_id})
		set_stat_source(uid, ItemDefs.stat_mods(item_id))
	world.emit_event("item:added", {"player_id": id, "item": String(item_id), "uid": String(uid)})
	return uid


func remove_item(uid: StringName) -> void:
	inventory.remove(uid)
	for i in items.size():
		if items[i].uid == uid:
			items.remove_at(i)
			remove_stat_source(uid)
			ItemEffects.forget_item(self, uid)
			return


# 客戶端：背包以房主的快照為準（[[uid, id, x, y, rot], …]），增減的道具同步加減屬性（本機預測移動要用到移速等）
func sync_inventory(arr: Array) -> void:
	var keep := {}
	inventory.entries.clear()
	for a: Array in arr:
		var uid := StringName(a[0])
		var w := WeaponDropDefs.from_array(a[5])
		inventory.add(uid, StringName(a[1]), Vector2i(a[2], a[3]), a[4], w)
		if w.is_empty() and ItemDefs.ITEMS[StringName(a[1])].kind == &"item":   # 背包裡的武器、屍體沒有效果
			keep[uid] = StringName(a[1])
	for it: Dictionary in items.duplicate():
		if not keep.has(it.uid):
			items.erase(it)
			remove_stat_source(it.uid)
			ItemEffects.forget_item(self, it.uid)
	for uid: StringName in keep:
		if not items.any(func(it: Dictionary) -> bool: return it.uid == uid):
			items.append({"uid": uid, "id": keep[uid]})
			set_stat_source(uid, ItemDefs.stat_mods(keep[uid]))


# 客戶端：裝備欄以房主的快照為準（[武器, 武器]，見 WeaponDropDefs.to_array）；手上哪一格由呼叫端決定要不要同步
func sync_weapon_slots(arr: Array, p_active: int) -> void:
	for i in weapon_slots.size():
		weapon_slots[i] = WeaponDropDefs.from_array(arr[i])
	active_slot = p_active
	_apply_active_weapon()


# 背包操作（InputCmd.inv_ops）：
#   [OP_MOVE, uid, x, y, rot] 搬到背包 (x, y)（道具或武器；武器可以從裝備欄搬進背包，但手上至少留一把）
#   [OP_DROP, uid] 丟到面前的地上；[OP_EQUIP, uid, slot] 武器放進裝備欄；[OP_MERGE, uid_a, uid_b] 把 a 拖到 b 上合成
func _apply_inventory_ops() -> void:
	for op: Array in _inventory_ops:
		var uid := StringName(op[1])
		match int(op[0]):
			InputCmd.OP_MOVE:
				var w := _find_weapon(uid)
				if w.has("slot"):
					if _equipped_count() > 1 and inventory.fits(w.inst.base, Vector2i(op[2], op[3]), op[4]):
						weapon_slots[w.slot] = {}
						inventory.add(uid, w.inst.base, Vector2i(op[2], op[3]), op[4], w.inst)
						_apply_active_weapon()
				else:
					inventory.move(uid, Vector2i(op[2], op[3]), op[4])
			InputCmd.OP_DROP:
				_drop(uid)
			InputCmd.OP_EQUIP:
				_equip_from(uid, int(op[2]))
			InputCmd.OP_MERGE:
				_merge(uid, StringName(op[2]))
	_inventory_ops.clear()


func _equipped_count() -> int:
	return weapon_slots.filter(func(s: Dictionary) -> bool: return not s.is_empty()).size()


# 丟到面前的地上：道具移除效果；武器從裝備欄丟時手上至少留一把
func _drop(uid: StringName) -> void:
	var at := pos + MathUtil.dir_from_angle(facing) * LootDefs.DROP_DISTANCE
	var w := _find_weapon(uid)
	if not w.is_empty():
		if w.has("slot") and _equipped_count() <= 1:
			return
		_take_weapon(w)
		_apply_active_weapon()
		world.drop_weapon(w.inst, at)
		return
	var entry := inventory.find(uid)
	if entry.is_empty():
		return
	remove_item(uid)
	if entry.id == &"corpse":
		world.drop_corpse(String(uid).get_slice("_", 1).to_int(), at)
	else:
		world.drop_item(entry.id, at)


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
	for it: Dictionary in items.duplicate():
		remove_item(it.uid)


func update(dt: float) -> void:
	_tick_timers(dt)
	if is_dead or is_downed or descended or stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - dt)
		if stun_timer > 0.0:
			move_input = Vector2.ZERO   # 暈眩時站著不動（移動層回到 idle）
		_pressed = 0
		_inventory_ops.clear()
		_interact_was_held = is_interact_held
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
		_apply_inventory_ops()
	else:
		_inventory_ops.clear()
	_interact_was_held = is_interact_held
	if pending_parry:
		pending_parry = false
		if block_time >= 0.0:
			_parry()
	action.update(dt)

	var data := action.data
	if has_forced_velocity:
		velocity = forced_velocity
	else:
		velocity = move_input * (stats.value(&"move_speed") * data.get("move_speed_mul", 1.0))

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


func _on_damaged(amount: int, _source_id: int) -> void:
	if is_dead or amount <= 0:
		return
	invuln_timer = Config.PLAYER.invuln_time
	# player_id：多人時只有被打的那位玩家的畫面震動
	world.emit_event("camera:shake", {"amount": Config.PLAYER.hurt_shake, "duration": Config.PLAYER.hurt_shake_duration, "player_id": id})
	# 特殊技期間有霸體，不會被打斷；挖墳被打也不中斷（D6）
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
