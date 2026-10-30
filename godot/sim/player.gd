# 玩家：讀取 InputCmd、雙層狀態機（移動層 / 動作層）、武器、輸入緩衝、主動欄位與增益效果；照搬網頁版 Player.js
# 裝備欄、背包、道具、合成、丟棄在 Loadout（sim/loadout.gd）；這裡保留原本的名稱轉過去，外部程式照舊用 player.add_item() 等
class_name Player
extends Entity

const ROLL_CD := "player.roll"
const PARRY_ANIM_TIME := 0.2
const HELD_REACH := 0.9   # 鐵鏟舉著的怪離身體邊緣多遠：放在鏟面上（2026-10-27 網頁版實測：原本 0.2，怪浮在手邊、鏟面在牠下方的地上）

var peer_id := 0
var move_input := Vector2.ZERO
var aim_point := Vector2(0.0, 5.0)
var is_attack_held := false
var is_special_held := false           # 右鍵按住（劍盾按住格擋，v0.41.0）
var attack_pressed := false            # 本步剛按下左鍵（格擋中按左鍵 = 招架）
var _attack_was_held := false
var weapon: Dictionary = {}            # 手上的招式資料：主手＋副手組合出來的（WeaponDefs.def_of）
var weapon_id: StringName = &""        # 組合 id（WeaponDefs.combo_id：「主手」或「主手+副手」），快照的 P_WEAPON
var class_id := ClassDefs.NONE        # 職業（F2，ClassDefs）；NONE = 共用基準數值
var torch_stance := false              # 火把準備姿態（F8）：按住右鍵舉著，左鍵換成噴火
var running := false                   # 跑步（Ctrl 切換）：跳躍、翻滾、開寶箱不取消；進入待機與翻滾以外的動作就取消
var quiver := 6                        # 箭袋裡剩幾支（短弓，F4 回饋）：射完自動裝填
var reload_timer := 0.0                # 裝填剩餘秒數；> 0 時不能射、移速變慢
var held_enemy_id := 0                # 鐵鏟舉著的怪（F9）；0 = 沒有
var hold_timer := 0.0                  # 舉著的剩餘秒數，到 0 怪掙脫
var loadout := Loadout.new()           # 裝備欄、背包、生效的道具（sim/loadout.gd）
var weapon_slots: Array[Dictionary]:   # [主手, 副手]（Loadout.MAIN / OFF）：武器實例（WeaponDropDefs）或 {}
	get:
		return loadout.weapon_slots
var items: Array[Dictionary]:          # 生效的道具實例 { uid, id }（鑲在主手 / 副手格子上的）；uid 同時是屬性加成的來源名稱
	get:
		return loadout.items
var inventory: Inventory:              # 背包的擺放（D3）；只放東西，沒有效果
	get:
		return loadout.inventory
var _applied_weapon_uid := &""
var _air_jumps_used := 0               # 這次離地後用掉的空中跳躍（落地歸零）
var descended := false                 # 已離開這一層、等其他人（不見、不能被打）；換層改成墳墓互動 + 投票後沒有地方設成 true，畫面與快照仍支援
var stun_timer := 0.0                  # 暈眩剩餘秒數（v0.27.0：Boss 衝鋒撞到）：不能移動、出招、翻滾、跳
var grabbed_by := 0                    # 被腐屍抓住：抓住的怪 id（客戶端只知道有沒有被抓，填 -1）；同暈眩，但按翻滾立刻掙脫
var combo_step := 0
var combo_timer := 0.0
var buffered_action: Dictionary = {}   # { type: &"special" | &"slot" | &"roll", index?, time }；空 = 沒有緩衝
var slots := ActiveSlots.new(Config.PLAYER.slots)
var buffs: Dictionary = {}             # id -> { remaining, stats?（屬性加成，見 sim/stats.gd）, trail_color? }
var kill_timers: Dictionary = {}       # 道具 uid -> 「擊殺後幾秒」條件剩下的秒數（sim/item_effects.gd）
var roll_timers: Dictionary = {}       # 道具 uid -> 「翻滾後幾秒」條件剩下的秒數（G2）
var proc_timers: Dictionary = {}       # 道具效果的內部冷卻：動作 / 屬性名稱 -> 剩下的秒數（ItemEffects.icd_ready）
var cond_values: Dictionary = {}       # 條件加成目前套上的數值（「cond:uid」-> 數值），疊層變了才重設
var floor_kills := 0                   # 本層擊殺數（G2 亡者之契；換層歸零）
var interval_timers: Dictionary = {}   # 道具 uid -> 下次「每隔固定秒數」觸發還剩幾秒（G4 雷霆鈴）
var shield := 0.0                      # 護盾剩多少（G4 骨製護盾，房主算；客戶端看快照的 anim.shield）
var shield_delay := 0.0                # 還要幾秒沒受傷才回充
var guardian_uses := 0                 # 這一層用掉幾次守護亡靈（G5；每個道具每層一次）
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
	loadout.equip_offhand_new(self, Config.PLAYER.start_offhand)
	roll_charges = roll_max()
	_update_anim()


# 跳躍：站在地面上隨時可以跳（攻擊、翻滾中也行），受擊硬直與倒地時不行；只有一段跳
func try_jump() -> bool:
	if is_dead or is_downed or held_enemy_id != 0 or action.is_in(&"stagger") or action.is_in(&"revive") or action.is_in(&"dig"):
		return false
	if not is_grounded():
		# 二段跳（道具能力 double_jump，v0.27.0）：空中可以再跳一次，高度同第一段（從目前高度往上 JUMP.height）
		if _air_jumps_used >= air_jumps():
			return false
		_air_jumps_used += 1
	vz = 4.0 * Config.JUMP.height / Config.JUMP.air_time
	torch_stance = false   # 跳躍取消火把準備姿態（F8）
	return true


# 被擊飛（v0.27.0：Boss 砸地）：往上給一個速度，照常受重力落地
func knock_up(speed: float) -> void:
	if is_dead or is_downed:
		return
	vz = maxf(vz, speed)


# 暈眩（v0.27.0：Boss 衝鋒）：期間不能移動、出招、翻滾、跳；動作中斷
# p_grabbed_by：被腐屍抓住（抓住的怪 id）：同暈眩，但按翻滾立刻掙脫（update）、怪被打會鬆手（release_grab）
func stun(duration: float, p_grabbed_by: int = 0) -> void:
	if is_dead or is_downed:
		return
	stun_timer = maxf(stun_timer, duration)
	if p_grabbed_by != 0:
		grabbed_by = p_grabbed_by
	if not action.is_in(&"dig"):   # 挖墳被打不中斷（D6）
		action.change(&"ready")
	buffered_action = {}
	world.emit_event("player:stunned", {"player_id": id, "duration": duration, "grabbed": p_grabbed_by != 0})


# 從抓住中放開（掙脫、腐屍被打或時間到）：暈眩一起結束
func release_grab() -> void:
	if grabbed_by == 0:
		return
	grabbed_by = 0
	stun_timer = 0.0


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


# 新的一層：回到出生點（死者也搬過去，等冤魂被打倒才在冤魂的位置站起來）
func arrive_floor(at: Vector2, ground: float) -> void:
	descended = false
	loadout.refill_slot_charges()   # 新的一關：身上武器的技能次數補滿（火把的插火把，F8）
	floor_kills = 0   # 亡者之契的疊層只算本層（G2）
	guardian_uses = 0   # 守護亡靈每層一次（G5）
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
# 守護亡靈、復活十字（G5）在倒地 / 單機死亡之前攔下；已經倒地後倒數結束的死亡不攔
func die(source_id: int = 0) -> void:
	if is_dead:
		return
	if not is_downed and world.is_authority and ItemEffects.on_lethal(world, self):
		return
	if not is_downed and world.players.size() > 1:
		_go_down()
		return
	super(source_id)


func _go_down() -> void:
	is_downed = true
	torch_stance = false
	running = false
	if held_enemy_id != 0:
		release_enemy()
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
# hp_ratio：救起後的血量比例（驅魔神官救的比較多，F7）
func revive(hp_ratio: float = Config.REVIVE.revive_hp_ratio) -> void:
	is_downed = false
	down_timer = 0.0
	revive_progress = 0.0
	hp = maxf(1.0, roundf(max_hp * hp_ratio))
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
	loadout.equip_offhand_new(self, c.get("offhand", &""))
	hp = max_hp
	roll_charges = roll_max()


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


# 換上一把新的白色武器（Loadout.equip_new：盾放副手，其他放主手）
func equip_weapon(id: StringName) -> void:
	loadout.equip_new(self, id)


# 套用主手與副手：組合招式資料（WeaponDefs.def_of）與詞條（屬性來源 &"weapon" 主手、&"offhand" 副手）；Loadout 換了武器就呼叫
func apply_active_weapon() -> void:
	var main: Dictionary = weapon_slots[Loadout.MAIN]
	if main.is_empty():
		return
	var off: Dictionary = weapon_slots[Loadout.OFF]
	var uids := StringName(String(main.uid) + "/" + String(off.get("uid", "")))
	# 主手或副手換了一把（uid 不同）才重設連段與動作；只是合成 / 搬動別的武器時不打斷手上的動作
	show_weapon(WeaponDefs.combo_id(Loadout.weapon_of(main), Loadout.weapon_of(off)), uids != _applied_weapon_uid)
	_applied_weapon_uid = uids
	set_stat_source(&"weapon", WeaponDropDefs.stat_mods(main))
	if off.is_empty():
		remove_stat_source(&"offhand")
	else:
		set_stat_source(&"offhand", WeaponDropDefs.offhand_mods(off))
	loadout.refresh_items(self)   # 鑲在主手 / 副手上的道具才生效


# 只換招式資料與模型（客戶端畫別人的角色也用這個）；force 時同一種也重設連段與動作
func show_weapon(id: StringName, force := false) -> void:
	if weapon_id == id and not force:
		return
	weapon = WeaponDefs.def_of(id)
	weapon_id = id
	torch_stance = false
	reload_timer = 0.0   # 換到有箭袋的弓就是滿的（換武器本身就要花時間；翻滾也能瞬間補滿）
	quiver = weapon.attack.get("quiver", 0)
	if held_enemy_id != 0:
		release_enemy()
	combo_step = 0
	combo_timer = 0.0
	action.change(&"ready")


# 主手的武器實例（稀有度光、HUD 的武器名稱）
func active_weapon() -> Dictionary:
	return loadout.main_weapon()


# 招式傷害 = 武器基礎傷害 × 招式 % × 攻擊力 × 物理 / 屬性傷害
func move_damage(move: Dictionary) -> float:
	return pct_damage(move.damage_pct)


# 武器基礎傷害的 pct 倍，乘上攻擊力與物理 / 屬性傷害（燃燒每秒傷害也用這個，F8）
func pct_damage(pct: float) -> float:
	return weapon.base_damage * pct * damage_mul * stats.value(StatDefs.type_damage_stat(weapon.damage_type))


# 動作層要用的招式資料：火把準備姿態中換成 stance 的左右鍵（F8），其餘就是武器的 attack / special
func action_def(kind: StringName) -> Dictionary:
	if held_enemy_id != 0 and weapon.has("grab"):
		return weapon.grab[kind]   # 鐵鏟舉著怪：左鍵拋出、右鍵埋入（F9）
	if torch_stance and weapon.has("stance") and weapon.stance.has(kind):
		return weapon.stance[kind]   # 舉著火把：左鍵噴火
	return weapon[kind]


# 射出一支箭（有箭袋的弓）：射空就開始裝填
func use_arrow(def: Dictionary) -> void:
	quiver = maxi(0, quiver - 1)
	if quiver == 0:
		reload_timer = def.reload_time


# 普攻能不能出手：有箭袋的弓在裝填中不能射
func can_attack() -> bool:
	return not weapon.attack.has("quiver") or (reload_timer <= 0.0 and quiver > 0)


# 箭袋補滿（裝填完、翻滾）
func refill_quiver() -> void:
	if weapon.attack.has("quiver"):
		quiver = weapon.attack.quiver
		reload_timer = 0.0


# 鐵鏟舉起一隻怪（F9）：怪停住、跟在面前，seconds 秒內沒拋出 / 埋入就掙脫
func grab_enemy(e: Enemy, seconds: float) -> void:
	held_enemy_id = e.id
	hold_timer = seconds
	e.grabbed_by = id
	_follow_held()


# 放開舉著的怪（拋出、埋入、掙脫、換武器、倒地），回傳那隻怪（已經不在了回傳 null）
func release_enemy() -> Enemy:
	var e: Enemy = world.entities.get(held_enemy_id) as Enemy
	held_enemy_id = 0
	hold_timer = 0.0
	if e != null:
		e.grabbed_by = 0
	return e


func _follow_held() -> void:
	var e: Enemy = world.entities.get(held_enemy_id) as Enemy
	if e == null or e.is_dead:
		release_enemy()
		return
	e.pos = pos + MathUtil.dir_from_angle(facing) * (radius + e.radius + HELD_REACH)
	e.velocity = Vector2.ZERO


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


func sync_weapon_slots(arr: Array) -> void:
	loadout.sync_weapon_slots(self, arr)


# 剛按下 F：附近有倒地隊友時讓給救援（動作層 Ready 處理）；否則先撿最近的道具，沒有道具才開最近的寶箱
func _try_interact() -> void:
	if find_revive_target() != null:
		return
	var pickup := world.nearest_interactable(self, world.pickups)
	if pickup != null:
		loadout.take_pickup(self, pickup as ItemPickup)
		return
	var chest := world.nearest_interactable(self, world.chests)
	if chest != null:
		(chest as Chest).try_open(self)
		return
	var keeper := world.entities.get(world.boss_id) as Gravekeeper
	if keeper != null and keeper.can_talk(self):
		keeper.talk()   # 跟假裝 NPC 的守墓人說話（比挖墳優先）
		return
	if world.event.can_exit(world, self):
		world.event.request_exit(world, self)


func clear_items() -> void:
	loadout.clear_items(self)


func update(dt: float) -> void:
	_tick_timers(dt)
	# 前往下一層的投票（權威端）：倒地、暈眩時也能投
	if world.is_authority and not is_dead and _pressed & (InputCmd.BTN_VOTE_YES | InputCmd.BTN_VOTE_NO):
		world.event.cast_vote(world, self, _pressed & InputCmd.BTN_VOTE_YES != 0)
	if is_dead or is_downed or descended or stun_timer > 0.0:
		if grabbed_by != 0 and (is_dead or is_downed or _pressed & InputCmd.BTN_ROLL):
			if not is_dead and not is_downed:
				world.emit_event("player:grab_escaped", {"player_id": id})   # 被抓住時按翻滾：立刻掙脫（這一步不翻滾）
			release_grab()
		stun_timer = maxf(0.0, stun_timer - dt)
		if stun_timer <= 0.0:
			grabbed_by = 0
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
	if running and not (action.is_in(&"ready") or action.is_in(&"roll")):
		running = false   # 攻擊、技能、道具、救人、挖墳、受擊硬直都打斷跑步
	if torch_stance and not is_special_held:
		torch_stance = false   # 放開右鍵就放下火把（2026-10-27 使用者）

	if reload_timer > 0.0:   # 短弓裝填（F4 回饋）
		reload_timer -= dt
		if reload_timer <= 1e-6:
			refill_quiver()
	if held_enemy_id != 0:   # 鐵鏟舉著怪（F9）：倒數到 0 掙脫，期間怪跟在面前
		hold_timer -= dt
		if hold_timer <= 1e-6:
			release_enemy()
		else:
			_follow_held()
	var data := action.data
	if has_forced_velocity:
		velocity = forced_velocity
	else:
		var slow: float = data.get("move_speed_mul", 1.0)
		if action.is_in(&"attack") and class_passive("attack_no_slow", false):
			slow = 1.0   # 盜墓遊俠被動：移動中普攻不減速（F4）
		if running:
			slow *= Config.PLAYER.run_speed_mul
		if torch_stance and action.is_in(&"ready"):
			slow *= weapon.stance.move_speed_mul   # 火把準備姿態（F8）
		if held_enemy_id != 0 and action.is_in(&"ready"):
			slow *= weapon.grab.move_speed_mul     # 舉著怪（F9）
		if reload_timer > 0.0 and weapon.attack.has("quiver"):
			slow *= weapon.attack.reload_move_mul  # 短弓裝填中
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
	if _pressed & InputCmd.BTN_RUN:
		running = not running
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
		"behavior": d.def.behavior if timed else d.get("item_behavior", &""),   # 使用技能欄時是那格的行為（插火把有自己的姿勢）
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
		"stunned": stun_timer > 0.0 and grabbed_by == 0,
		"grabbed": grabbed_by != 0,
		"torch_stance": torch_stance,
		"running": running,
		"holding": held_enemy_id != 0,   # 鐵鏟舉著怪（F9）   # 舉著火把：全隊的視野都看得到周圍（F8，Vision.lights）
		"shield": shield / max_hp if max_hp > 0.0 else 0.0,   # 護盾占最大生命的比例（G4；0 不進快照）
	}


func _absorb(amount: float) -> float:
	return ItemEffects.absorb(self, amount)


func _on_damaged(amount: float, _source_id: int) -> void:
	if is_dead or amount <= 0:
		return
	invuln_timer = Config.PLAYER.invuln_time
	regen_block_timer = Config.PLAYER.regen_delay
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
