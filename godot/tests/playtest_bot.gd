# 自動試玩的一個機器人（tests/playtest.gd 用）：每步看世界決定輸入（decide），步完讀事件記自己的統計（after_step）
# 打法：身邊有怪先打 → 撿武器 → 遺物 / 鐵砧 / 寶箱 → 打怪群與 Boss → 挖墳；smart 另外躲招、舉盾招架、遠程拉開、喝藥水、
# 換更好的武器、整理背包、走出怪物的地面效果、救倒地的隊友
extends RefCounted

const DT := 1.0 / 60.0
# 躲招：怪物在這些狀態以外就當成正在出招（新怪的狀態不用登記也會躲）；瞄準（aim）不躲人，改躲射出來的投射物
const SAFE_STATES: Array[StringName] = [&"chase", &"patrol", &"spawn", &"hurt", &"dead", &"train", &"dormant", &"dazed", &"fallen",
	&"collapse", &"guard_broken", &"stagger", &"fetch", &"kite", &"aim", &"stalk", &"wolf_chase", &"colossus_chase", &"reveal", &"grow",
	&"transform", &"wheel_stun", &"burrow", &"surface", &"summon", &"whistle", &"howl"]
const LUNGE_STATES: Array[StringName] = [&"charge", &"leap", &"pounce", &"lunge", &"rush", &"roll", &"wheel", &"hop"]   # 衝過來的招：往側面滾
const THREAT_REACH := 3.0              # 一般招式：雙方身體邊緣距離這麼近才躲
const LUNGE_REACH := 8.0               # 衝刺類的招
const BOSS_EXTRA := 2.0                # Boss 的招大一圈
const DODGE_ANGLE := 0.7               # 一般招式往「遠離怪物」偏這麼多弧度滾（斜後方，比正後方不容易被追上）
const PROJ_WARN := 0.35                # 投射物這麼多秒內會打到就躲
const ROLL_LEAD := 0.15                # 預兆結束前這麼多秒才滾（無敵 0.2 秒蓋住打下來那一刻）；太早滾，會轉向追人的招照樣打到
const JUMP_LEAD := 0.1                 # 跳得過的招（資料有 low_max_air）：打下來前這麼多秒起跳，那一刻腳已經離地
const COMMIT_TIME := 0.6               # 躲完之後這麼久只躲 Boss 的招，先打一輪（一群屍犬輪流撲時才不會一直滾、打不到 Boss）
const CONE_HUG_MAX := 4.5              # 持續的扇形招：離中心這麼近就貼身繞到背後，更遠就往外跑出射程
const CONE_STEP := 0.9                 # 貼身繞的時候每次往前繞這麼多弧度的點走
const CONE_BEHIND := 0.6               # 在牠背後 ±這麼多弧度內就算繞到了
const ATTACK_LOCK := 0.0               # 揮刀中盾舉不起來的時間也算進「來不及」（Boss 的招預兆 < 反應 + ROLL_LEAD + 這個就先舉盾）：試過 0.3（含鏟擊、提燈），提燈 7.5 格外就一直舉盾、幾乎不出手，死時 Boss 剩 42% → 75%
const PREBLOCK_EARLY := 0.5            # 那招的冷卻剩這麼多秒就不再出手、先舉盾（長劍一刀 0.36~0.48 秒，揮到一半冷卻好了牠 0.15 秒就出招）
const PREBLOCK_PAD := 0.5              # 來不及反應的招：離牠這招的發動距離（trigger_distance）+ 這麼多以內、冷卻好了就先舉盾
const EVADE_MAX := 1.2                 # 躲過一招後最多退這麼久就回去打（慢動作、連續出招的 Boss 不會一直退）
const ROCK_WARN := 0.5                 # 從天上落下的石頭（守墓人鏟土）：這麼多秒內會落地、我在範圍內就走開（影子看得到）
const DEATH_BLAST := 1.0               # 死後會爆的怪：死後這麼多秒內都算威脅（膨脹屍 0.5、死亡爆炸詞條 0.8 秒後爆）
const KITE_DIST := 3.5                 # 遠程職業：怪貼到這麼近就往後退
const CROWD_MAX := 0                   # 近戰：身邊 CROWD_RANGE 內醒著的怪到這麼多就往外退（0 = 不退；16 種子實測退不退差不多、門檻 5 反而更差，預設關，--crowd 做實驗）
const CROWD_RANGE := 2.5
const AWAKE_FIRST := 15.0              # 這麼近有醒著的怪就先打完，不去撿東西、開寶箱（路上可能吵醒下一群）
const PACK_AVOID := 3.0                # 往外退的方向避開休眠怪群：離群中心 wake_distance + 這麼多以內的會把方向推開
const POTION_AT := 0.4                 # 生命低於最大生命的這個比例就喝藥水
const POTION_URGENT := 0.2             # 正在擋 / 躲時，低於這個比例才喝
const REROLL_BELOW := 0.5              # 3 選 1 最好的選項分數低於這個、還有骰子就重擲
const PATH_REFRESH := 0.5              # 每隔幾秒重新找路
const STUCK_TIME := 25.0               # 追同一個目標這麼久、血都沒掉（打不到）就放棄它；有在掉血就繼續打（Boss 血多，25 秒打不完）
const LOOT_RANGE := INF                # 多遠的武器都去撿（量「全撿」的上限；身邊沒怪才去）
const SAFE_RANGE := 5.0                # 身邊這麼近有怪就先打怪
const DIG_GUARD := 3.5                 # 挖墳時身邊這麼近有怪就停下來打
const MINION_CLOSE := 3.0              # Boss 叫出來的小怪貼到這麼近、又比 Boss 近，就先打掉
const SUMMONER_RANGE := 15.0           # 這麼近有帶召喚詞條的怪就先打它（不然叫出來的打不完）
const RANGED := [&"staff", &"shortbow", &"longbow"]
const RANGED_STANDOFF := 0.7           # 遠程離目標的距離 = 普攻射程 × 這個比例（夾在 5~9）
const SPLASH := 2.0                    # 組隊：隊友離目標這麼近，遠程的爆炸 / 範圍招會一起打到（Config.NET.friendly_fire）

var w: World
var p: Player
var peer := World.HOST_PEER_ID
var smart_play := true
var smart_pick := true
var react := 0.25
var real_death := false                # true：倒下就真的倒下（單人就是這場結束）；false：倒下記一次、原地滿血救起
var reach := 1.4
var crowd_max := CROWD_MAX
var style := "full"

# 這一層的統計（begin_floor 歸零）
var casts := 0                         # 放了幾次技能（數字鍵）與耗魔的右鍵
var spent := 0                         # 開寶箱花掉的靈魂
var opened := 0                        # 開了幾個寶箱
var downs := 0                         # 倒下幾次
var down_by := {}                      # 打出最後一下的「怪物·招式」→ 次數
var taken := 0.0                       # 受到的傷害
var acts := {"roll": 0, "jump": 0, "block": 0, "potion": 0, "swap": 0, "drop": 0, "socket": 0, "reroll": 0, "rescue": 0}
var hit_by := {}                       # 「怪物·招式」→ 受到的傷害
var full_seen := false                 # 有武器撿不下
var real_from := 0                     # --real-from=N：第 1 層第 N 小關起（第 2 層起全部）才真的會死，之前照 revive；進那一關時補滿血
var _real_now := false
var died_at := ""                      # real_death 真的死掉：「層-小關 時間（招式）」
var is_out := false                    # real_death 死掉了：之後不再出輸入

var _path := PackedVector2Array()
var _path_goal := Vector2.INF
var _path_timer := 0.0
var _target_id := 0
var _target_time := 0.0
var _target_hp := 0.0                  # 這次開始計時時目標的血
var _skip: Dictionary = {}             # 放棄的目標 id
var _tap := false                      # F 要放開再按才算「剛按下」
var _relic_skip: Dictionary = {}       # 走不到的遺物 id
var _relic_time := 0.0
var _relic_target := 0
var _rng := RandomNumberGenerator.new()   # --pick=random 用，跟著種子
var _reacted := {}                     # 怪物 id → 已經反應過的出招狀態（同一招只躲一次）
var _jumped := {}                      # 怪物 id → 這招已經跳過（接著躲同一招的第二下）
var _proj_seen := {}                   # 已經躲過的投射物 id
var _rerolled := {}                    # 重擲過的遺物 id
var _block_id := 0                     # 正在對著舉盾的怪（0 = 沒有）
var _block_broken := false             # 舉盾還被那隻怪打到（那招擋不住）
var _block_time := 0.0                 # 對著投射物舉盾剩幾秒
var _evade_id := 0                     # 正在躲的那隻怪：那招結束前不走回去
var _evade_time := 0.0                 # 這次已經退了幾秒
var _evade_side := 1.0                 # 往哪一邊偏（跟翻滾同一邊）
var _commit := 0.0                     # 躲完後先打的剩餘秒數
var _moves := {}                       # 「怪物種類·狀態」→ 資料裡那一招的表（{} = 查不到），查過就記著
var _forms := {}                       # 怪物 id → 上次認出的形態（資料子表名稱，例 wolf）
var _fast_moves := {}                  # 「怪物種類·形態」→ 來不及反應的招 [[名稱, 表]]（預兆 ≤ 反應 + ROLL_LEAD），查過就記著
var _unblockable := {}                 # 舉盾還被打到的「怪物種類·狀態」：之後這招改滾（每個種子重新學）
var _hands := ["", ""]                 # 主手 / 副手武器的 uid：變了就是換過武器
var _was_down := false
var _last_hit := "不明"                # 最後打中自己的「怪物·招式」（倒下時記這個）
var _blocked_loot: ItemPickup = null   # 背包放不下、稀有度最高的地上武器
var _dropped := {}                     # 自己丟掉的武器 uid：不再撿回來
var trace := false                     # --trace=1：倒下時印出之前最後 TRACE_N 下是怎麼被打的
var _recent: Array[String] = []
const TRACE_N := 10
var _socket_tried := {}                # 試過搬上武器格的道具 uid（搬不上去的不一直試）
var _was_reviving := false


func _init(p_world: World, p_player: Player, opts: Dictionary, seed_value: int) -> void:
	w = p_world
	p = p_player
	peer = p.peer_id
	smart_play = String(opts.get("play", "smart")) != "dumb"
	smart_pick = String(opts.get("pick", "smart")) != "random"
	react = float(opts.get("react", "0.25"))
	real_death = String(opts.get("death", "revive")) == "real"
	real_from = int(opts.get("real-from", "0"))
	style = String(opts.get("style", "full"))
	trace = opts.has("trace")
	crowd_max = int(opts.get("crowd", str(CROWD_MAX)))
	reach = 1.4
	var wid: StringName = ClassDefs.CLASSES[p.class_id].weapon
	if wid in RANGED:   # 遠程站在普攻射程的 70%（5~9）：站得比守墓人提燈的發動距離（7）遠，不會一直被噴
		reach = clampf(float(WeaponDefs.WEAPONS[wid].attack.get("range", 8.0)) * RANGED_STANDOFF, 5.0, 9.0)
	_rng.seed = hash([seed_value, peer])
	_hands = [p.weapon_slots[Loadout.MAIN].get("uid", ""), p.weapon_slots[Loadout.OFF].get("uid", "")]


func begin_floor() -> void:
	casts = 0
	spent = 0
	opened = 0
	downs = 0
	down_by.clear()
	taken = 0.0
	hit_by.clear()
	full_seen = false
	for k: String in acts:
		acts[k] = 0
	_skip.clear()
	_target_id = 0
	_reacted.clear()
	_jumped.clear()
	_proj_seen.clear()
	_block_id = 0
	_block_broken = false
	_block_time = 0.0
	_evade_id = 0
	_commit = 0.0


# 步完：讀這一步的事件記統計；換武器看手上的 uid；倒下照模式處理（救起或記下死在哪）
func after_step(t: float) -> void:
	for i in Loadout.OFF + 1:
		var uid: Variant = p.weapon_slots[i].get("uid", "")
		if uid != _hands[i]:
			_hands[i] = uid
			acts.swap += 1
	for ev in w.events:
		var mine: bool = ev.get("player_id", 0) == p.id
		match ev.name:
			"entity:damaged":
				if ev.get("target_id", 0) == p.id:
					taken += ev.amount
					var blocked_by := w.entities.get(_block_id) as Enemy if _block_id != 0 else null
					if blocked_by != null and ev.get("source_id", 0) == _block_id and _shield_faces(ev.get("origin", p.pos)) and not _multi_hit(_move_def(blocked_by)):
						# 盾舉起來了、打過來的方向在盾的範圍內還是被打到：這招擋不住（盾還沒舉好、從側面被打到的不算）
						# 記成反應的那一招（膨脹屍脹大 swell 後自爆，打到時狀態已經是 dead，照當下的狀態記會一直學不到）
						_unblockable["%s·%s" % [blocked_by.type, _reacted.get(blocked_by.id, blocked_by.fsm.current_name)]] = true
						_block_broken = true
					_last_hit = _move_name(ev)
					hit_by[_last_hit] = hit_by.get(_last_hit, 0.0) + ev.amount
					if trace:
						_recent.append("%s %s %d（剩 %d 血、%s、翻滾 %d、身邊 3 內 %d 隻、%s）" % [_mmss(t), _last_hit, roundi(ev.amount), roundi(p.hp),
							p.action.current_name, p.roll_charges, _crowd(3.0), _guard_note(ev.get("source_id", 0))])
						if _recent.size() > TRACE_N:
							_recent.pop_front()
			"chest:opened":
				var c := w.entities.get(ev.get("chest_id", 0)) as Chest
				if mine and c != null:
					spent += c.price_for(p)
					opened += 1
			"skill:used":
				if not mine:
					pass
				elif ev.get("key", "") == ActiveSlots.cd_key(ActiveSlots.HEAL_INDEX):
					acts.potion += 1
				elif ev.get("key", "") == Player.ROLL_CD:
					acts.roll += 1
				else:
					casts += 1
			"player:blocked":
				if mine:
					acts.block += 1
			"relic:rerolled":
				if mine:
					acts.reroll += 1
			"player:revived":
				pass
	var down := p.is_dead or p.is_downed
	if down and not _was_down:
		downs += 1
		down_by[_last_hit] = down_by.get(_last_hit, 0) + 1
		if trace:
			print("— %s 第 %d-%d 倒下前：\n  %s" % [ClassDefs.CLASSES[p.class_id].name, w.floor_num, w.stage_num, "\n  ".join(PackedStringArray(_recent))])
			_recent.clear()
	_was_down = down
	if real_from > 0 and not _real_now and (w.floor_num > 1 or w.stage_num >= real_from):
		_real_now = true
		p.hp = p.max_hp   # 進真的會死的那一關：補滿血、藥水補回整局的量（之前是倒下就救起的量法，機器人在那幾關快死時就把藥喝光了，
		p.slots.heal.charges = int(SkillDefs.SKILLS.heal.charges)   # 真人打過來時血掉得少、藥水通常還在；8 場量到進 Boss 關時 7 場 0 瓶）
	if not down:
		return
	if not (real_death or _real_now):
		if p.is_dead:
			p.resurrect(p.pos, 1.0)
		else:
			p.revive(1.0)
		w.is_defeated = false   # 同 Practice：全員倒下的判定清掉，世界照常跑
		_was_down = false
	elif p.is_dead and died_at == "":
		is_out = true
		var boss := w.entities.get(w.boss_id) as Enemy
		var left := "、Boss 剩 %d%%" % roundi(100.0 * boss.hp / boss.max_hp) if boss != null and not boss.is_dead and _boss_awake(boss) else ""
		died_at = "%d-%d %s（%s%s）" % [w.floor_num, w.stage_num, _mmss(t), _last_hit, left]


# 受傷事件是哪一招打的：「怪物·狀態」；打到時怪物已經不在出招（射完箭在拉開距離、地上的毒霧）記成「射出的」，怪物不在了記種類
func _move_name(ev: Dictionary) -> String:
	var ally := w.entities.get(ev.get("source_id", 0)) as Player
	if ally != null:
		return "隊友誤傷·%s" % ally.action.current_name
	var who: String = RunLog.name_of(ev.get("source_kind", &""))
	var src := w.entities.get(ev.get("source_id", 0)) as Enemy
	if src == null or src.fsm == null:
		return who
	if ev.get("minor", false):
		return "%s·地上的火 / 毒" % who   # 持續傷害（殘火、腐氣）：來源怪物當下的狀態不是打出這一下的招
	return "%s·%s" % [who, "射出的" if src.fsm.current_name in SAFE_STATES and not src.is_dead else String(src.fsm.current_name)]


static func _mmss(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


# 這一步要做什麼：身邊有怪先打 → 附近有武器去撿 → 照打法找下一個目標（怪群 → Boss → 挖墳）
func decide() -> InputCmd:
	var cmd := InputCmd.new()
	cmd.aim = p.pos + Vector2(0, 1)
	_tap = not _tap
	if is_out or p.is_dead or p.is_downed:
		return cmd
	if p.grabbed_by != 0:   # 被腐屍抓住：照畫面的提示按翻滾掙脫
		if _tap:
			cmd.buttons |= InputCmd.BTN_ROLL
		return cmd
	if smart_play:
		_drink(cmd)
		_swap(cmd)
		_organize(cmd)
		if _guard(cmd) or _leave_zone(cmd) or _rescue(cmd):
			return cmd
	var summoner := _nearest_summoner()
	if summoner != null:
		return _fight(cmd, summoner)
	var near := _nearest_enemy(SAFE_RANGE, false)
	var digging_phase := style == "rush" or (_nearest_enemy(INF, false) == null and _boss() == null)
	var boss := _boss()
	if near != null and not (digging_phase and p.pos.distance_to(near.pos) > DIG_GUARD):
		# Boss 叫出來的小怪（不給靈魂）：Boss 醒著就直接打 Boss，不然 Boss 一直叫、小怪打不完
		if near.no_souls and near.summoner_id == 0 and boss != null and _boss_awake(boss):
			# smart：貼在身邊（MINION_CLOSE 內）、比 Boss 近的先打掉（屍犬撲咬會硬直，接著狼人爪就擋不了也滾不了）；其他照舊直接打 Boss
			if not (smart_play and p.pos.distance_to(near.pos) <= MINION_CLOSE and p.pos.distance_to(near.pos) < p.pos.distance_to(boss.pos)):
				return _fight(cmd, boss)
		return _fight(cmd, _summoner_of(near))
	var awake := _nearest_awake() if smart_play else null
	if awake != null and p.pos.distance_to(awake.pos) < AWAKE_FIRST:
		return _fight(cmd, _summoner_of(awake))   # 一次只打一群：醒著的先打完再去撿東西
	var loot := nearest_loot()
	if loot != null:
		_walk(cmd, loot.pos)
		if w.can_reach(p, loot) and _tap:
			cmd.buttons |= InputCmd.BTN_INTERACT
		return cmd
	var relic := _next_relic()
	if relic != null:
		return _use_relic(cmd, relic)
	var chest := _next_chest()
	if chest != null:
		_walk(cmd, chest.pos)
		if w.can_reach(p, chest) and _tap:
			cmd.buttons |= InputCmd.BTN_INTERACT
		return cmd
	if boss != null and _boss_awake(boss):
		return _fight(cmd, boss)   # Boss 醒了先打它（不然它一直叫小怪，機器人會打不完）
	if not digging_phase:
		var e := _nearest_awake()   # 一次只打一群：還有醒著的就先打完，不去吵醒下一群
		if e == null:
			e = _nearest_enemy(INF, false)
		if e == null:
			e = _boss()
		if e != null:
			return _fight(cmd, _summoner_of(e))
	if w.event.state == DigEvent.OPEN:
		return cmd
	var point := w.event.point
	if p.pos.distance_to(point) > EventDefs.DIG.range * 0.6:
		_walk(cmd, point)
	else:
		cmd.buttons |= InputCmd.BTN_INTERACT
	return cmd


func _fight(cmd: InputCmd, e: Entity) -> InputCmd:
	if smart_play and reach > KITE_DIST and _ally_near(e.pos, SPLASH):   # 遠程：隊友貼著這隻在打，換一隻旁邊沒隊友的
		var alt := _clear_target(reach + 3.0)
		if alt == null:
			cmd.aim = e.pos
			return cmd
		e = alt
	if e.id != _target_id:
		_target_id = e.id
		_target_time = 0.0
		_target_hp = e.hp
	_target_time += DT
	if _target_time > STUCK_TIME:
		if e.hp < _target_hp - 0.5:   # 有在掉血：重新計時
			_target_time = 0.0
			_target_hp = e.hp
		else:
			_skip[e.id] = true
	cmd.aim = e.pos
	# 舉盾的盾槍兵：正面 shield.arc 內全部擋下、舉盾時轉身慢，站在正面就先往牠身側繞（不出手），繞出盾的範圍再打
	var sp := e as Spearman
	if sp != null and sp.is_guarding():
		var to_me := p.pos - sp.pos
		if absf(angle_difference(sp.facing, atan2(to_me.x, to_me.y))) <= sp.def.shield.arc / 2.0 + 0.2:
			var front := Vector2(sin(sp.facing), cos(sp.facing))
			var side := front.orthogonal() * (1.0 if front.orthogonal().dot(to_me) >= 0.0 else -1.0)
			_walk(cmd, sp.pos + side * (reach + sp.radius + 0.5) - front * 0.5)
			cmd.aim = sp.pos
			return cmd
	var close := _nearest_enemy(KITE_DIST, true) if smart_play and reach > KITE_DIST else null
	if close != null and (close.dormant or not w.nav_for(p.radius).has_los(p.pos, close.pos)):
		close = null   # 休眠的、隔著牆的不退：不然走向目標途中經過牠旁邊會來回打轉
	if close != null:   # 遠程：怪貼上來就往後退著打（瞄準不變）
		var away := _safe_dir((p.pos - close.pos).normalized())
		_walk(cmd, p.pos + away * 4.0)
		cmd.aim = e.pos
	elif smart_play and crowd_max > 0 and reach <= KITE_DIST and _crowd(CROWD_RANGE) >= crowd_max:
		_walk(cmd, p.pos + _away_from_crowd(CROWD_RANGE + 2.0) * 3.0)   # 被包圍：往怪少的那邊退著打，把一群拉成一條線
		cmd.aim = e.pos
	elif p.pos.distance_to(e.pos) > reach + e.radius:
		_walk(cmd, e.pos)
	if smart_play and _ally_in_line(e.pos):   # 隊友擋在中間：往旁邊挪一步再打，不誤傷
		var to := (e.pos - p.pos).normalized()
		cmd.move = to.orthogonal() * _evade_side
		return cmd
	# 近戰走近的路上不按普攻（揮空的這一刀做完前盾舉不起來，狼人爪剛好打在揮空的時候）；遠程照樣邊走邊射
	if reach > KITE_DIST or p.pos.distance_to(e.pos) <= reach + e.radius + 0.5:
		cmd.buttons |= InputCmd.BTN_ATTACK
	_cast(cmd, e)
	return cmd


# 數字鍵 1~4 的技能：放得出來（魔力、冷卻、次數）、目標在技能的範圍內就放（一步放一個）；再看耗魔的右鍵
func _cast(cmd: InputCmd, e: Entity) -> void:
	var d := p.pos.distance_to(e.pos) - e.radius
	for i in ActiveSlots.GEM_SLOTS:
		var slot: Variant = p.slots.get_slot(p, i)
		if slot == null or not slot.def.has("mana") or not p.slots.can_use(p, i):
			continue
		if smart_play and slot.def.get("behavior", &"") in [&"dash", &"ambush", &"leap_shot"] and _fast_move_soon(e as Enemy):
			continue   # Boss 來不及反應的招快好了：不要衝進去（狼人爪 0.25 秒，衝過去剛好吃滿三爪）
		if d <= _skill_range(slot.def) and not (smart_play and _skill_hits_ally(slot.def, e.pos)):
			cmd.buttons |= InputCmd.slot_bit(i)
			return
	var special: Dictionary = p.weapon.get("special", {})
	if special.has("mana") and p.has_mana(p.mana_cost_of(special)) and d <= _skill_range(special):
		if not (smart_play and (_skill_hits_ally(special, e.pos) or _ally_in_line(e.pos))):
			cmd.buttons |= InputCmd.BTN_SPECIAL


# 技能打得到多遠：資料的 range（射出去）/ distance（衝刺）/ radius（身邊一圈）的 90%，都沒有就用普攻距離
# 不跟普攻距離取大：遠程站 9 格外，身邊一圈的技能（冰霜新星 3）在那裡放是白放
func _skill_range(def: Dictionary) -> float:
	for k in ["range", "distance", "radius"]:
		if def.has(k):
			return float(def[k]) * 0.9
	return reach + 1.0


# 躲招：怪物出招（不在 SAFE_STATES，或死後會爆的剛死）超過反應時間、我在牠的範圍內就反應，同一招只反應一次：
#   跳得過的招（資料有 low_max_air）→ 打下來前起跳，落地後同一招的第二下照下面躲
#   手上有盾、這招沒被記成擋不住、不是衝刺類 → 對著牠舉盾到那招結束；舉盾還被這招打到 → 記成擋不住（下次改滾），有充能就馬上滾開
#   其他 → 抓在預兆結束前翻滾（沒充能就用走的），之後那招沒結束、人還在範圍內就繼續往外退，不走回去吃下一下
# 投射物 PROJ_WARN 秒內會打到 → 有盾就舉盾，沒有就往側面滾。這一步有動作就回傳 true（不做別的事）
func _guard(cmd: InputCmd) -> bool:
	if p.action.current_name == &"roll" or not p.is_grounded():
		return false
	var has_shield: bool = p.weapon.get("special", {}).get("behavior", &"") == &"shieldBlock"
	if _block_time > 0.0:
		_block_time -= DT
		cmd.buttons |= InputCmd.BTN_SPECIAL_HELD
		return true
	_commit = maxf(0.0, _commit - DT)
	if _evade_id != 0:
		if _keep_evading(cmd):
			return true
		_commit = COMMIT_TIME
	_evade_id = 0
	_block_id = 0
	for x in w.enemies:
		var e := x as Enemy
		if e == null or e.team == &"player" or e.fsm == null:
			continue
		var threat := _threat_reach(e)
		if threat < 0.0:
			_reacted.erase(e.id)
			_jumped.erase(e.id)
			continue
		if _commit > 0.0 and e.no_souls and not e.is_boss():
			continue   # 召喚出來的（Boss 叫的屍犬）輪流撲：躲完先打一輪，不然一直滾打不到 Boss
		var state := e.fsm.current_name
		var foreseen := has_shield and e.is_boss() and _is_fast_move(e)   # 先舉盾等著的那一招：一出來就接著擋，不用再等反應時間
		if _reacted.get(e.id, &"") == state or (e.fsm.time < react and not e.is_dead and not foreseen):
			continue   # 死後會爆的不用等反應：知道牠會炸，一死就跑
		var move := _move_def(e)
		var cone: bool = move.has("arc") and move.has("range") and not e.is_dead
		if p.pos.distance_to(e.pos) - e.radius - p.radius > threat or (cone and not _in_cone(e, move)):
			continue
		var hit_at: float = move.get("windup", -1.0)
		if move.has("flight") and move.has("windup") and not e.is_dead:
			# 跳起來砸下的招（狼人飛撲：預兆 + 空中 flight 秒後落地一圈）：落地的判定只打腳底在地面 + slam_height 以下的，
			# 落地那一刻起跳就躲得掉，不用翻滾（翻滾充能常常剛用在第三爪上）
			if e.fsm.time < hit_at + float(move.flight) - JUMP_LEAD * e.action_speed:   # fsm.time 已經乘過 action_speed
				continue
			_reacted[e.id] = state
			cmd.buttons |= InputCmd.BTN_JUMP
			acts.jump += 1
			return true
		if move.has("low_max_air"):
			if not _jumped.has(e.id):
				if e.fsm.time < hit_at - JUMP_LEAD * e.action_speed:   # fsm.time 已經乘過 action_speed
					continue
				_jumped[e.id] = true
				cmd.buttons |= InputCmd.BTN_JUMP
				acts.jump += 1
				return true
			hit_at += float(move.get("gap", 0.0))   # 第二下（高掃）在 gap 秒後
		var lunge := _is_lunge(e, move)
		var blast := e.type == &"bloater" or e.has_affix(&"volatile")   # 爆炸一律擋不住（Combat）：膨脹屍脹大、死亡爆炸詞條的不擋
		var can_block := has_shield and not e.is_dead and not lunge and not blast and not _unblockable.has(_move_key(e))
		if not can_block and e.fsm.time < hit_at - ROLL_LEAD * e.action_speed:
			continue   # 看到了，等快打下來才滾（舉盾不用等，早舉沒損失）
		_reacted[e.id] = state
		_evade_id = e.id
		_evade_time = 0.0
		if can_block:
			_block_id = e.id
			cmd.aim = e.pos
			_hold_shield(cmd)
			return true
		var away := (p.pos - e.pos).normalized()
		if p.roll_charges > 0:
			_roll(cmd, away, PI / 2.0 if lunge else DODGE_ANGLE)
		else:
			cmd.move = away.rotated(DODGE_ANGLE * _evade_side)
		return true
	if _avoid_transform(cmd):
		return true
	if has_shield and _preblock(cmd):
		return true
	for x in w.projectiles:
		var pr := x as Projectile
		if pr == null or pr.is_removed or pr.team == &"player" or _proj_seen.has(pr.id) or pr.speed <= 0.0:
			continue
		if pr.traveled / pr.speed < react:
			continue
		var rel := p.pos - pr.pos
		var along := rel.dot(pr.direction)
		if along <= 0.0 or along / pr.speed > PROJ_WARN or absf(rel.cross(pr.direction)) > p.radius + pr.radius + 0.2:
			continue
		_proj_seen[pr.id] = true
		if has_shield and pr.blockable:
			cmd.aim = pr.pos
			cmd.buttons |= InputCmd.BTN_SPECIAL_HELD
			_block_time = along / pr.speed + 0.1
			return true
		if p.roll_charges > 0:
			_roll(cmd, pr.direction, PI / 2.0)
			return true
	return false


# 正在躲的那招還沒結束、人還在範圍內：舉盾的繼續舉（被打穿就滾），其他往外退；招結束、退太久或離開範圍回傳 false
func _keep_evading(cmd: InputCmd) -> bool:
	var e := w.entities.get(_evade_id) as Enemy
	_evade_time += DT
	if e == null or e.is_removed or _threat_reach(e) < 0.0 or _reacted.get(e.id, &"") != e.fsm.current_name:
		return false
	var move := _move_def(e)
	if _sustained_cone(move) and not e.is_dead and _block_id != e.id:   # 有盾就照下面一直擋（提燈的火擋得住）
		cmd.aim = e.pos
		var to_me := p.pos - e.pos
		var hug := e.radius + p.radius + 0.25
		if to_me.length() > CONE_HUG_MAX:   # 離得遠：繞不過牠轉身，往外跑出射程，招結束前不回去（牠會轉回來追著噴）
			if to_me.length() < float(move.range) + p.radius + 1.5:
				var front := MathUtil.dir_from_angle(e.facing)
				var side := front.orthogonal() * (1.0 if front.orthogonal().dot(to_me) >= 0.0 else -1.0)
				var out := _safe_dir((to_me.normalized() + side * 0.5).normalized())   # 往外帶一點側向，先離開扇形中線
				if _in_cone(e, move) and p.roll_charges > 0:
					_roll_toward(cmd, out)   # 被噴到了：每一下都硬直、走不出去，翻滾（硬直中按會等到硬直結束才滾）
				else:
					_walk(cmd, p.pos + out * 3.0)
			return true
		# 貼著身體繞到背後：繞的角速度 = 移速 ÷ 離中心的距離，貼身時比牠噴火時的轉向（turn_speed × turn_mul）快，離一步遠就追不上
		var back := -MathUtil.dir_from_angle(e.facing)
		var behind := absf(angle_difference(atan2(back.x, back.y), atan2(to_me.x, to_me.y))) < CONE_BEHIND
		var goal := e.pos + back * hug
		if not behind:
			var a := to_me.normalized().rotated(CONE_STEP)
			var b := to_me.normalized().rotated(-CONE_STEP)
			goal = e.pos + (a if a.dot(back) > b.dot(back) else b) * hug   # 往離背後近的那個方向繞
		if _in_cone(e, move) and p.roll_charges > 0:
			_roll_toward(cmd, (goal - p.pos).normalized())
			return true
		_walk(cmd, goal)
		if behind or not _in_cone(e, move):
			cmd.buttons |= InputCmd.BTN_ATTACK   # 繞出來了就打，站位跟著牠的背後
		return true
	if _move_over(e, move):
		return false
	if p.pos.distance_to(e.pos) - e.radius - p.radius > _threat_reach(e) + 1.0:
		return false
	var away := (p.pos - e.pos).normalized()
	cmd.aim = e.pos
	if _block_id == e.id:
		var multi := _multi_hit(move)
		if multi and e.fsm.time >= _last_hit_at(move) - ROLL_LEAD * e.action_speed and p.roll_charges > 0:
			_block_id = 0   # 多段招的最後一下擋不住（狼人第三爪往前撲）：前幾下擋完，最後一下前滾開
			_roll(cmd, away, PI / 2.0)
			return true
		if not _block_broken:
			_hold_shield(cmd)
			return true
		_block_id = 0
		_block_broken = false
		if p.roll_charges > 0:
			_roll(cmd, away, DODGE_ANGLE)
			return true
	_walk(cmd, p.pos + _safe_dir(away.rotated(DODGE_ANGLE * _evade_side)) * 3.0)   # 斜著退：直直往後退會順著放射狀的招（骨刺陣）一路被打
	cmd.aim = e.pos
	return true


# 這隻怪現在的威脅範圍（身體邊緣距離）；沒在出招回傳 -1。死後會爆的（膨脹屍、死亡爆炸詞條）剛死的 DEATH_BLAST 秒內也算
func _threat_reach(e: Enemy) -> float:
	if e.is_dead:
		var blasts := (e.type == &"bloater" or e.has_affix(&"volatile")) and not e.no_death_effect
		return THREAT_REACH if blasts and e.fsm.time < DEATH_BLAST else -1.0
	var state := e.fsm.current_name
	if state in SAFE_STATES:
		return -1.0
	var move := _move_def(e)
	# 資料的範圍從怪物中心算；最後一下會往前撲的（lunge：狼人第三爪往前 3）再加上撲的距離
	var data_reach := maxf(float(move.get("range", 0.0)), float(move.get("radius", 0.0))) + float(move.get("lunge", 0.0)) - e.radius
	return maxf(data_reach, (LUNGE_REACH if _is_lunge(e, move) else THREAT_REACH) + (BOSS_EXTRA if e.is_boss() else 0.0))


# 衝過來的招：狀態名稱在 LUNGE_STATES，或資料有往前滑（slide：守墓人的鏟起）→ 往側面滾、不擋
# 不看 distance：很多招都有這個欄位，全當衝刺類的話反應範圍變 8、一直滾，翻滾充能留不到屍犬撲過來（16 種子打到 1-5 從 12 掉到 7）
func _is_lunge(e: Enemy, move: Dictionary) -> bool:
	return e.fsm.current_name in LUNGE_STATES or move.has("slide")


# 怪物在變身（transform：守墓人 50% 血變狼人、骸骨將軍脫甲）：變身中無敵、打了沒用，結束時吼叫 / 噴碎片（資料的 roar_radius / shard_range）。
# 先退到那個範圍外 + 1，不出手；吼完再回去（吼叫是重硬直 0.8 秒，吃到的話狼人第一輪爪子全擋不了）
func _avoid_transform(cmd: InputCmd) -> bool:
	for x in w.enemies:
		var e := x as Enemy
		if e == null or e.is_dead or e.fsm == null or e.fsm.current_name != &"transform":
			continue
		var t: Dictionary = e.def.get("transform", {})
		var keep := float(t.get("roar_radius", t.get("shard_range", 5.0))) + p.radius + 1.0
		var to_me := p.pos - e.pos
		if to_me.length() >= keep:
			continue
		cmd.aim = e.pos
		_walk(cmd, e.pos + _safe_dir(to_me.normalized() if to_me.length_squared() > 1e-4 else Vector2(0, 1)) * (keep + 0.5))
		return true
	return false


# 多段招（資料有 interval 與 tiers：狼人的三連爪）：第 i 下在 windup + i × interval
static func _multi_hit(move: Dictionary) -> bool:
	return move.has("interval") and move.has("tiers") and move.has("windup")


static func _last_hit_at(move: Dictionary) -> float:
	return float(move.windup) + float(move.interval) * ((move.tiers as Array).size() - 1)


# 來不及反應的招（預兆 < 反應時間 + ROLL_LEAD + ATTACK_LOCK：狼人爪 0.25、鏟擊 0.45、提燈 0.55 秒；衝刺類不算，要滾）：Boss 沒在出招、我在那招的發動距離 + PREBLOCK_PAD 內、
# 那招冷卻好了（看得出牠隨時會出）就先舉盾、不出手；冷卻中就是出手的空檔。變身後的招（資料子表，例 wolf）只在狀態名稱含那個形態時算
func _preblock(cmd: InputCmd) -> bool:
	for x in w.enemies:
		var e := x as Enemy
		if e == null or e.is_dead or not e.is_boss() or e.fsm == null or not (e.fsm.current_name in SAFE_STATES) or not _boss_awake(e):
			continue   # 只對 Boss：小怪一群時一直舉盾就打不到（腐屍的飛撲預兆 0.4 秒剛好在門檻上，曾經 16 場 0 場打到 1-5）
		var d := p.pos.distance_to(e.pos)
		if d > 8.0:
			continue
		for entry: Array in _fast_moves_of(e):
			var move: Dictionary = entry[1]
			if d <= float(move.trigger_distance) + PREBLOCK_PAD and w.cooldowns.remaining(e.cd(entry[0])) <= PREBLOCK_EARLY:
				cmd.aim = e.pos
				_hold_shield(cmd)
				return true
	return false


# 這隻 Boss 有沒有來不及反應的招、冷卻快好了（PREBLOCK_EARLY 內）
func _fast_move_soon(e: Enemy) -> bool:
	if e == null or not e.is_boss() or e.fsm == null:
		return false
	for entry: Array in _fast_moves_of(e):
		if w.cooldowns.remaining(e.cd(entry[0])) <= PREBLOCK_EARLY:
			return true
	return false


# 現在這一招是不是來不及反應的招（_fast_moves_of 的其中一個）
func _is_fast_move(e: Enemy) -> bool:
	for entry: Array in _fast_moves_of(e):
		if StringName(entry[0]) == e.fsm.current_name:
			return true
	return false


func _fast_moves_of(e: Enemy) -> Array:
	var form: String = _forms.get(e.id, "")   # 出招時的狀態名稱（claw）看不出形態，沿用上次從 wolf_chase 這類名稱認出的
	for k: String in e.def:
		if e.def[k] is Dictionary and String(e.fsm.current_name).contains(k):
			form = k
	_forms[e.id] = form
	var key := "%s·%s" % [e.type, form]
	if not _fast_moves.has(key):
		var out := []
		for t: Dictionary in ([e.def] + ([e.def[form]] if form != "" else [])):
			for name: String in t:
				var m: Variant = t[name]
				if m is Dictionary and (m as Dictionary).has("windup") and (m as Dictionary).has("trigger_distance") and float(m.windup) < react + ROLL_LEAD + ATTACK_LOCK \
						and not (StringName(name) in LUNGE_STATES) and not (m as Dictionary).has("slide"):
					out.append([name, m])
		_fast_moves[key] = out
	return _fast_moves[key]


# 持續一段時間、會追著轉的扇形招（資料有 arc、range、duration：守墓人的提燈噴火）：沒盾的繞出去（_keep_evading），有盾的一直擋
# 噴的時候每一下都會硬直，被噴到之後移動時間只剩一半、繞不過牠轉身；要在預兆時就出去
static func _sustained_cone(move: Dictionary) -> bool:
	return move.has("arc") and move.has("range") and move.has("duration")


# 這招躲 / 擋到什麼時候：資料寫得出長度的（持續：預兆 + duration + 最後轉圈 spin_time；多段：最後一下）照怪物自己的時間（fsm.time）+ 0.3 算，
# 冰冷、減速會讓牠的時間變慢（Enemy.fsm.update 乘 chill_mul），用真實秒數會在第三爪前就放掉；寫不出長度的最多 EVADE_MAX 秒
func _move_over(e: Enemy, move: Dictionary) -> bool:
	if move.has("duration"):
		return e.fsm.time > float(move.get("windup", 0.0)) + float(move.duration) + float(move.get("spin_time", 0.0)) + 0.3
	if _multi_hit(move):
		return e.fsm.time > _last_hit_at(move) + 0.3
	return _evade_time > EVADE_MAX


# 扇形的招（資料有 arc 與 range，例：守墓人的提燈噴火）：我在牠面前的扇形裡（多留 0.3 弧度、1 格）
func _in_cone(e: Enemy, move: Dictionary) -> bool:
	var to_me := p.pos - e.pos
	if to_me.length() > float(move.range) + p.radius + 1.0:
		return false
	return absf(angle_difference(e.facing, atan2(to_me.x, to_me.y))) <= float(move.arc) / 2.0 + 0.3


# 盾舉著、from 在盾擋得到的正面範圍內（Player.try_block 同一條：facing 兩側各 block_arc / 2）
func _shield_faces(from: Vector2) -> bool:
	if p.block_time < 0.0:
		return false
	var to := from - p.pos
	if to.length_squared() < 1e-6:
		return true
	return absf(angle_difference(p.facing, atan2(to.x, to.y))) <= float(p.weapon.get("special", {}).get("block_arc", 0.0)) / 2.0


# 舉盾，只按住右鍵；不連按左鍵招架：招架判定（parry.window 0.2 秒）沒擋到就打出盾擊、放下盾（WeaponBehaviors.ShieldBlock），
# 連按會變成「擋 → 盾擊 → 放下 → 再舉」，中間的空檔一直被打（守墓人的提燈每 0.25 秒一下），還每次扣 20 魔力
func _hold_shield(cmd: InputCmd) -> void:
	cmd.buttons |= InputCmd.BTN_SPECIAL_HELD
	var exit := _zone_exit()
	if exit != Vector2.ZERO:   # 舉著盾也能走（移速減半）：站在殘火裡就邊擋邊走出去（提燈轉圈留的殘火剛好在貼身的距離）
		cmd.move = exit


# 這招在怪物資料裡的表：資料（含變身後的子表，一層）裡跟狀態同名的那一項；查不到回傳 {}（沒有 windup 就照反應時間滾）
func _move_def(e: Enemy) -> Dictionary:
	var key := _move_key(e)
	if not _moves.has(key):
		var found := {}
		var tables: Array = [e.def]
		for v: Variant in e.def.values():
			if v is Dictionary:
				tables.append(v)
		for t: Dictionary in tables:
			var move: Variant = t.get(String(e.fsm.current_name), null)
			if move is Dictionary:
				found = move
				break
		_moves[key] = found
	return _moves[key]


func _move_key(e: Enemy) -> String:
	return "%s·%s" % [e.type, e.fsm.current_name]


# 照 dir 直接滾（已經挑好方向的：繞到背後、跑出射程）
func _roll_toward(cmd: InputCmd, dir: Vector2) -> void:
	cmd.move = dir
	cmd.buttons |= InputCmd.BTN_ROLL


# 往 base 轉 ±angle 的方向滾：先挑落點看得到（不會滾進牆）的那一邊，兩邊都不行就照 base 滾
func _roll(cmd: InputCmd, base: Vector2, angle: float) -> void:
	var nav := w.nav_for(p.radius)
	var dir := base
	for a: float in [angle, -angle]:
		var d := base.rotated(a)
		if nav.has_los(p.pos, p.pos + d * Config.ROLL.distance):
			dir = d
			_evade_side = signf(a)
			break
	cmd.move = dir
	cmd.buttons |= InputCmd.BTN_ROLL


# 站在怪物的地面效果裡（腐氣、毒霧這類會扣血的、蜘蛛網）或快落地的石頭底下（守墓人的 rocks）：先走出去，從圈心往外走到邊緣外 1 格
func _leave_zone(cmd: InputCmd) -> bool:
	for x in w.enemies:
		var g := x as Gravekeeper
		if g == null:
			continue
		for r: Dictionary in g.rocks:
			var radius: float = r.hit.get("radius", 1.5)
			var out: Vector2 = p.pos - r.at
			if r.left > ROCK_WARN or out.length() > radius + p.radius + 0.3:
				continue
			var dir := out.normalized() if out.length_squared() > 1e-4 else Vector2(0, 1)
			_walk(cmd, r.at + dir * (radius + p.radius + 1.0))
			return true
	var exit := _zone_exit()
	if exit != Vector2.ZERO:
		_walk(cmd, p.pos + exit * 2.0)
		return true
	return false


# 站在怪物的地面效果裡（會扣血的、蜘蛛網）：往外走的方向（從圈心往外），沒站在裡面回傳 ZERO
func _zone_exit() -> Vector2:
	for z: Dictionary in w.zones:
		var hurts: bool = z.get("damage_per_sec", 0.0) > 0.0 or z.has("web_slow")
		if not hurts or z.get("remaining", 0.0) < 0.3:
			continue
		var owner := w.entities.get(z.get("owner_id", 0)) as Entity
		if owner != null and owner.team == p.team and not z.get("hits_all", false):
			continue
		var out: Vector2 = p.pos - z.pos
		if out.length() > z.radius + p.radius:
			continue
		return out.normalized() if out.length_squared() > 1e-4 else Vector2(0, 1)
	return Vector2.ZERO


# 隊友倒地：自己與隊友身邊 SAFE_RANGE 內都沒有怪才走過去按住 F 救（救要 REVIVE.revive_time 秒、不能動；有怪就照常先打，倒地能撐 down_time 秒）
func _rescue(cmd: InputCmd) -> bool:
	if p.action.current_name == &"revive":
		_was_reviving = true
	elif _was_reviving:
		_was_reviving = false
	for o: Player in w.player_list:
		if o == p or not o.is_downed:
			continue
		if _nearest_enemy(SAFE_RANGE, true) != null or _enemy_near(o.pos, SAFE_RANGE):
			return false
		if p.pos.distance_to(o.pos) > Config.REVIVE.range * 0.8:
			_walk(cmd, o.pos)
		else:
			cmd.buttons |= InputCmd.BTN_INTERACT
			if p.action.current_name != &"revive" and not _was_reviving:
				acts.rescue += 1
		return true
	return false


# 這個技能放出去會不會打到隊友（照技能的形狀）：射出去 / 衝刺 → 往目標的一條線（range / distance 長、width 或 radius 寬）；
# 打在目標身上的（落雷、箭雨這類 strike / rain / chain）→ 目標身邊 radius；其他有 radius 的（新星）→ 自己身邊 radius；有 explosion_radius 的另外看目標身邊
func _skill_hits_ally(def: Dictionary, target: Vector2) -> bool:
	var dir := (target - p.pos).normalized()
	var half := float(def.get("width", def.get("radius", 0.6) * 2.0)) / 2.0
	for o: Player in w.player_list:
		if o == p or o.is_dead or o.is_downed:
			continue
		var rel := o.pos - p.pos
		if def.has("explosion_radius") and o.pos.distance_to(target) <= float(def.explosion_radius) + o.radius:
			return true   # 打到目標會炸開（法杖右鍵的奧術爆發）
		match def.get("behavior", &""):
			&"shoot", &"dash", &"leap_shot":
				var length := float(def.get("range", def.get("distance", 6.0)))
				var along := rel.dot(dir)
				if along > 0.0 and along < length and absf(rel.cross(dir)) < half + o.radius:
					return true
			&"strike", &"rain", &"chain":
				if o.pos.distance_to(target) <= float(def.get("radius", SPLASH)) + o.radius:
					return true
			_:
				if def.has("radius") and rel.length() <= float(def.radius) + o.radius:
					return true
	return false


func _ally_near(at: Vector2, radius: float) -> bool:
	for o: Player in w.player_list:
		if o != p and not o.is_dead and not o.is_downed and o.pos.distance_to(at) <= radius + o.radius:
			return true
	return false


# 範圍內最近、旁邊沒有隊友的怪（遠程換目標用）
func _clear_target(radius: float) -> Enemy:
	var best: Enemy = null
	var best_d := radius
	for x in w.enemies:
		var e := x as Enemy
		if e == null or e.is_dead or e.team == &"player" or e.dormant or _skip.has(e.id) or _ally_near(e.pos, SPLASH):
			continue
		var d := p.pos.distance_to(e.pos)
		if d < best_d:
			best_d = d
			best = e
	return best


# 離開身邊 radius 內醒著的怪的方向（從牠們的重心往外），再避開休眠的怪群（_safe_dir）
func _away_from_crowd(radius: float) -> Vector2:
	var sum := Vector2.ZERO
	for x in w.enemies:
		var e := x as Enemy
		if e != null and not e.is_dead and e.team != &"player" and not e.dormant and e.pos.distance_to(p.pos) <= radius:
			sum += (p.pos - e.pos).normalized()
	return _safe_dir(sum.normalized() if sum.length_squared() > 1e-4 else Vector2(0, 1))


# 往 dir 退會不會吵醒休眠的怪群（World._update_packs：走到群中心 wake_distance 內整群醒）：
# 附近的休眠群把方向往外推，越近推得越用力；一次只引一群
func _safe_dir(dir: Vector2) -> Vector2:
	var limit: float = MonsterRarityDefs.PACKS.wake_distance + PACK_AVOID
	var push := Vector2.ZERO
	for pk: Dictionary in w.packs:
		if pk.awake:
			continue
		var rel: Vector2 = p.pos - pk.center
		var d := rel.length()
		if d < limit and d > 1e-3:
			push += rel / d * (limit - d) / PACK_AVOID
	var out := dir + push
	return out.normalized() if out.length_squared() > 1e-4 else dir


# --trace 用：被打的那一刻機器人對這隻怪在做什麼（擋 / 躲 / 沒反應、在不在牠的扇形裡、反應過哪一招）
func _guard_note(source_id: int) -> String:
	var e := w.entities.get(source_id) as Enemy
	if e == null or e.fsm == null:
		return "來源不在"
	var move := _move_def(e)
	var cone := "扇形內" if move.has("arc") and move.has("range") and _in_cone(e, move) else "扇形外" if move.has("arc") else "非扇形"
	var doing := "擋" if _block_id == e.id else "躲" if _evade_id == e.id else "沒反應"
	var to_me := p.pos - e.pos
	var ang := rad_to_deg(absf(angle_difference(e.facing, atan2(to_me.x, to_me.y))))
	return "%s、%s、反應過 %s、擋不住 %s、空檔 %.1f、距離 %.1f、偏離牠正面 %.0f°、牠的階段 %s %.2f" % [doing, cone, _reacted.get(e.id, &"—"),
		_unblockable.has(_move_key(e)), _commit, to_me.length(), ang, e.fsm.data.get("phase", "—"), e.fsm.data.get("phase_time", 0.0)]


# 身邊 radius 內醒著的怪有幾隻
func _crowd(radius: float) -> int:
	var n := 0
	for x in w.enemies:
		var e := x as Enemy
		if e != null and not e.is_dead and e.team != &"player" and not e.dormant and e.pos.distance_to(p.pos) <= radius:
			n += 1
	return n


func _enemy_near(at: Vector2, radius: float) -> bool:
	for x in w.enemies:
		var e := x as Enemy
		if e != null and not e.is_dead and e.team != &"player" and not e.dormant and e.pos.distance_to(at) <= radius:
			return true
	return false


# 隊友在這一下的打擊範圍裡（會誤傷）：近戰看面前 reach + 1 內、正前方 ±60°；遠程看往目標的直線兩側 1 格內；
# 有 radius 的技能傳 area：自己身邊一圈（新星）與目標身邊一圈（落雷、箭雨）都看
func _ally_in_line(target: Vector2, area: float = 0.0) -> bool:
	var dir := (target - p.pos).normalized()
	var dist := p.pos.distance_to(target)
	for o: Player in w.player_list:
		if o == p or o.is_dead or o.is_downed:
			continue
		var rel := o.pos - p.pos
		if area > 0.0 and (rel.length() <= area + o.radius or o.pos.distance_to(target) <= area + o.radius):
			return true
		var along := rel.dot(dir)
		if along <= 0.0:
			continue
		if reach > KITE_DIST:
			if along < dist + 1.0 and absf(rel.cross(dir)) < o.radius + 0.6:
				return true
		elif rel.length() <= reach + 1.0 + o.radius and absf(dir.angle_to(rel)) < PI / 3.0:
			return true
	return false


# 生命低於 POTION_AT、藥水還有次數又不在冷卻就按 Q；正在擋 / 躲的時候不喝（喝藥會放下盾），快死了（POTION_URGENT 以下）才硬喝
func _drink(cmd: InputCmd) -> void:
	# 藥水整局只有 SkillDefs.heal.charges 瓶、不會補（ActiveSlots.heal）：Boss 醒著才照 POTION_AT 喝，平常留到快死（POTION_URGENT）才喝
	var boss := _boss()
	var at := POTION_AT if boss != null and _boss_awake(boss) else POTION_URGENT
	if p.hp >= p.max_hp * at or p.slots.heal.charges <= 0:
		return
	if (_block_id != 0 or _evade_id != 0 or _block_time > 0.0) and p.hp >= p.max_hp * POTION_URGENT:
		return
	if w.cooldowns.is_ready(p.cd(ActiveSlots.cd_key(ActiveSlots.HEAL_INDEX))):
		cmd.buttons |= InputCmd.slot_bit(ActiveSlots.HEAL_INDEX)


# 背包裡有跟主手 / 副手同一種、稀有度更高的武器就換上（鑲的道具由 Loadout 搬過去）；一步換一把
func _swap(cmd: InputCmd) -> void:
	for x in p.inventory.entries:
		var inst: Dictionary = x.get("weapon", {})
		if inst.is_empty():
			continue
		for i in Loadout.OFF + 1:
			var hand: Dictionary = p.weapon_slots[i]
			if hand.is_empty() or Loadout.weapon_of(hand) != Loadout.weapon_of(inst):
				continue
			if WeaponDropDefs.RARITY_ORDER.find(inst.rarity) > WeaponDropDefs.RARITY_ORDER.find(hand.rarity):
				cmd.inv_ops.append([InputCmd.OP_EQUIP, x.uid, i])
				return


# 整理背包（一步一件）：背包裡的道具搬得上主手 / 副手的格子就搬上去（同一種已經鑲著的不搬，不多算羈絆）；
# 地上有更稀有的武器撿不下 → 丟掉背包裡最差的那把（丟掉的不再撿回來）
func _organize(cmd: InputCmd) -> void:
	for x in p.inventory.entries:
		if x.has("weapon") or _socket_tried.has(x.uid) or not ItemDefs.ITEMS.has(x.id) or not (ItemDefs.ITEMS[x.id].get("kind") in [&"item", &"skill"]):
			continue
		_socket_tried[x.uid] = true
		if p.loadout.items.any(func(it: Dictionary) -> bool: return it.id == x.id):
			continue
		for where: int in [Loadout.MAIN, Loadout.OFF]:
			var inv := p.loadout.container(where)
			var spot := inv.find_spot(x.id) if inv != null else {}
			if not spot.is_empty():
				cmd.inv_ops.append([InputCmd.OP_MOVE, x.uid, spot.cell.x, spot.cell.y, spot.rot, where])
				acts.socket += 1
				return
	if _blocked_loot == null or _blocked_loot.is_removed or _blocked_loot.is_dead:
		_blocked_loot = null
		return
	var want := WeaponDropDefs.RARITY_ORDER.find(_blocked_loot.weapon.get("rarity", &"white"))
	var worst: Dictionary = {}
	var worst_r := want
	for x in p.inventory.entries:
		var inst: Dictionary = x.get("weapon", {})
		if inst.is_empty():
			continue
		var r := WeaponDropDefs.RARITY_ORDER.find(inst.rarity)
		if r < worst_r:
			worst_r = r
			worst = x
	_blocked_loot = null
	if not worst.is_empty():
		_dropped[worst.weapon.get("uid", worst.uid)] = true
		cmd.inv_ops.append([InputCmd.OP_DROP, worst.uid])
		acts.drop += 1


# 靈魂買得起、還沒開的寶箱：石棺優先（3 選 1 的稀有度比較高），同種取最近的；走 STUCK_TIME 秒到不了就放棄
func _next_chest() -> Chest:
	var best: Chest = null
	var best_score := INF
	for x in w.chests:
		var c := x as Chest
		if c == null or c.is_removed or c.opened or _relic_skip.has(c.id) or w.souls < c.price_for(p):
			continue
		var score := p.pos.distance_to(c.pos) - (1000.0 if c.tier == &"big" else 0.0)
		if score < best_score:
			best_score = score
			best = c
	if best != null:
		if best.id != _relic_target:
			_relic_target = best.id
			_relic_time = 0.0
		_relic_time += DT
		if _relic_time > STUCK_TIME:
			_relic_skip[best.id] = true
	return best


# 還沒選過的遺物 / 鐵砧（最近的、走得到的）
func _next_relic() -> Relic:
	var best: Relic = null
	var best_d := INF
	for x in w.relics:
		var r := x as Relic
		if r == null or r.is_removed or r.taken.has(peer) or _relic_skip.has(r.id):
			continue
		var d := p.pos.distance_to(r.pos)
		if d < best_d:
			best_d = d
			best = r
	return best


# 走過去按 F 打開，打開了就選（_relic_choice）；最好的選項分數太低、還有骰子就先重擲（一個最多一次）
func _use_relic(cmd: InputCmd, r: Relic) -> InputCmd:
	if r.id != _relic_target:
		_relic_target = r.id
		_relic_time = 0.0
	_relic_time += DT
	if _relic_time > STUCK_TIME:
		_relic_skip[r.id] = true
	if p.relic_id == r.id:
		var opts: Array = r.offers.get(peer, [])
		if opts.is_empty():
			return cmd
		if not smart_pick:
			cmd.inv_ops.append([InputCmd.OP_RELIC_PICK, r.id, _rng.randi_range(0, opts.size() - 1)])
			return cmd
		var best := _relic_choice(opts)
		if _choice_score(opts[best]) < REROLL_BELOW and p.dice > 0 and not _rerolled.has(r.id):
			_rerolled[r.id] = true
			cmd.inv_ops.append([InputCmd.OP_RELIC_REROLL, r.id])
		else:
			cmd.inv_ops.append([InputCmd.OP_RELIC_PICK, r.id, best])
		return cmd
	_walk(cmd, r.pos)
	if w.can_reach(p, r) and _tap:
		cmd.buttons |= InputCmd.BTN_INTERACT
	return cmd


func _relic_choice(opts: Array) -> int:
	var best := 0
	for i in opts.size():
		if _choice_score(opts[i]) > _choice_score(opts[best]):
			best = i
	return best


# 3 選 1 每個選項的分數（越高越想要，< 0 = 拿了沒用）：
#   技能：已經有、還沒滿級（再選一次升級）10；手上武器能鑲、還沒有 9；其他（鑲不上、滿級）-1
#   道具：每個羈絆 1 + 現有件數（在走的羈絆優先），補上這件剛好湊到下一階再 +3；同一種已經鑲著（不多算羈絆）-1；沒有羈絆 0.1
#   鐵砧第一步的詞條：「羈絆 +1」照道具的算法，其他詞條 0.2
func _choice_score(id: StringName) -> float:
	if WeaponDropDefs.AFFIXES.has(id):
		var a: Dictionary = WeaponDropDefs.AFFIXES[id]
		return _bond_score(a.bond) if a.kind == &"bond" else 0.2
	if ItemDefs.is_skill(id):
		if p.skill_levels.get(id, 1) >= SkillDefs.LEVEL.max:
			return -1.0
		if p.loadout.has_item(id):
			return 10.0
		return 9.0 if _fits_hands(id) else -1.0
	if p.loadout.items.any(func(it: Dictionary) -> bool: return it.id == id):
		return -1.0
	var bonds: Array = ItemDefs.ITEMS.get(id, {}).get("bonds", [])
	if bonds.is_empty():
		return 0.1
	var s := 0.0
	for b: StringName in bonds:
		s += _bond_score(b)
	return s


func _bond_score(bond: StringName) -> float:
	var have: int = p.loadout.bond_counts.get(bond, 0)
	return 1.0 + have + (3.0 if BondDefs.next_threshold(bond, have) == have + 1 else 0.0)


func _fits_hands(skill: StringName) -> bool:
	for i in Loadout.OFF + 1:
		var wid := Loadout.weapon_of(p.weapon_slots[i])
		if wid != &"" and SkillDefs.can_socket(skill, wid):
			return true
	return false


func _walk(cmd: InputCmd, goal: Vector2) -> void:
	_path_timer -= DT
	if _path_timer <= 0.0 or goal.distance_to(_path_goal) > 1.0:
		_path_timer = PATH_REFRESH
		_path_goal = goal
		var nav := w.nav_for(p.radius)
		_path = PackedVector2Array() if nav.has_los(p.pos, goal) else nav.find_path(p.pos, goal)
	while _path.size() > 1 and p.pos.distance_to(_path[0]) < 0.6:
		_path.remove_at(0)
	var to := goal if _path.is_empty() else _path[0]
	cmd.move = (to - p.pos).normalized()
	# 高台：尋路的格子把高台當可走（怪物會跳上去），路線會經過高台，玩家要自己跳。照怪物的規則（Enemy._update_jump）看地圖：
	# 沿著要走的方向、身體邊緣再往前 jump_lookahead 的地面比腳下高出一個台階、又不超過 climb_height（墓碑太高不跳）就起跳
	var ahead := p.pos + cmd.move * (p.radius + Config.NAV.jump_lookahead)
	var rise := w.terrain.ground_at(ahead) - p.ground_height
	if p.is_grounded() and rise > Config.HEIGHT.step and rise <= Config.NAV.climb_height:
		cmd.buttons |= InputCmd.BTN_JUMP
	if cmd.aim.distance_to(p.pos + Vector2(0, 1)) < 0.01:
		cmd.aim = p.pos + cmd.move * 5.0


func _nearest_enemy(radius: float, include_boss: bool) -> Enemy:
	var best: Enemy = null
	var best_d := radius
	for x in w.enemies:
		var e := x as Enemy
		if e == null or e.is_dead or e.team == &"player" or _skip.has(e.id) or (e.is_boss() and not include_boss):
			continue
		var d := p.pos.distance_to(e.pos)
		if d < best_d:
			best_d = d
			best = e
	return best


func _nearest_awake() -> Enemy:
	var best: Enemy = null
	var best_d := INF
	for x in w.enemies:
		var e := x as Enemy
		if e == null or e.is_dead or e.dormant or e.team == &"player" or _skip.has(e.id) or e.is_boss():
			continue
		var d := p.pos.distance_to(e.pos)
		if d < best_d:
			best_d = d
			best = e
	return best


# 被召喚出來的怪：召喚者還活著就去打召喚者（只打送上門的會打不完，召喚者每隔幾秒又叫一批）
func _summoner_of(e: Enemy) -> Enemy:
	var s := w.entities.get(e.summoner_id) as Enemy if e.summoner_id != 0 else null
	if s != null and s.is_boss() and smart_play and p.pos.distance_to(e.pos) <= MINION_CLOSE and p.pos.distance_to(e.pos) < p.pos.distance_to(s.pos):
		return e   # Boss 叫的小怪貼在身邊、比 Boss 近：先打掉（屍犬撲咬的硬直會讓狼人爪擋不了）
	return s if s != null and not s.is_dead and not _skip.has(s.id) else e


func _nearest_summoner() -> Enemy:
	var best: Enemy = null
	var best_d := SUMMONER_RANGE
	for x in w.enemies:
		var e := x as Enemy
		if e == null or e.is_dead or e.team == &"player" or _skip.has(e.id) or not e.affixes.has(&"summoner"):
			continue
		var d := p.pos.distance_to(e.pos)
		if d < best_d:
			best_d = d
			best = e
	return best


func _boss() -> Enemy:
	var b := w.entities.get(w.boss_id) as Enemy
	return null if b == null or b.is_dead or _skip.has(b.id) else b


func _boss_awake(b: Enemy) -> bool:
	return not (b.has_method(&"is_npc") and b.call(&"is_npc"))


# 附近還沒撿、背包放得下的武器（自己丟掉的不算）；放不下的記下稀有度最高的那把（_organize 決定要不要丟背包裡的）
func nearest_loot() -> ItemPickup:
	var best: ItemPickup = null
	var best_d := LOOT_RANGE
	for x in w.pickups:
		var ip := x as ItemPickup
		if ip == null or ip.is_dead or ip.weapon.is_empty() or _skip.has(ip.id) or _dropped.has(ip.weapon.get("uid", "")):
			continue
		var d := p.pos.distance_to(ip.pos)
		if p.inventory.find_spot(ip.item_id).is_empty():
			full_seen = true
			if _blocked_loot == null or WeaponDropDefs.RARITY_ORDER.find(ip.weapon.rarity) > WeaponDropDefs.RARITY_ORDER.find(_blocked_loot.weapon.rarity):
				_blocked_loot = ip
			continue
		if d < best_d:
			best_d = d
			best = ip
	if best != null:
		if best.id != _target_id:
			_target_id = best.id
			_target_time = 0.0
			_target_hp = 0.0
		_target_time += DT
		if _target_time > STUCK_TIME:
			_skip[best.id] = true
	return best
