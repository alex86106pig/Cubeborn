# 畫面層敵人動畫：依模擬層的 enemy.anim（狀態、經過秒數、招式階段）擺姿勢，並畫 Boss 砸地的地板裂紋
# 怪物攻擊不畫預警圈：每招靠自己的預備動作與場景特效讓玩家判斷（設計方向「怪物攻擊不畫紅圈」）
# 姿勢公式照搬網頁版 Enemy.js（爬出 / 受擊 / 死亡 / 走路）、MeleeEnemy.js、RangedEnemy.js、Boss.js
class_name EnemyAnimator
extends RefCounted

const HURT_ARM_SHARPNESS := 20.0
const DEATH_FALL_TIME := 0.4
const CORPSE_SINK_START := 0.6   # 屍體停留時間的 60% 後開始沉入地面
const CORPSE_SINK_DEPTH := 0.8
const SLAM_FOLLOW_TIME := 0.12   # 重砸落地後手臂揮下的秒數
const SLAM_CROUCH := 0.25        # 砸地落地時蹲低多少
# 砸地的地板裂紋：從 Boss 腳下往外爬，比那一圈爆開早 lead 秒爬到外緣，之後越來越亮，爆開後淡掉
const CRACK_COLOR := Color("ffb04a")
const CRACK_LINES := 9           # 往外爬的裂紋條數
const CRACK_JITTER := 0.28       # 每一圈的轉折角度（弧度）
const CRACK_WIDTH := 0.13
const CRACK_GROWN_GLOW := 0.35   # 爬到外緣時的亮度，之後到爆開時升到 1
const CRACK_FADE := 0.4          # 爆開後淡掉的秒數
const CRACK_LEAD_MAX_WINDUP := 0.75   # 舉手時間很短時（瞬移砸地），提前量最多是舉手時間的這個比例
const VOLATILE_SWELL := 0.35     # 死亡爆炸的屍體爆開前膨脹到多大（倍率 +35%）
const BLOATER_SWELL := 0.5       # 膨脹屍炸開前脹到 +50%
# 骷髏弓手不瞄準時左手垂直地面：弓固定在骨手上，手垂直時弓平放（弓梢朝前後、弦在上），手平舉瞄準時弓自然直立
const BOW_ARM_REST := 0.0
const BOW_ARM_AIM := -1.55       # 瞄準時弓手平舉
const BOW_ARM_READY := -1.0      # 目標在射擊距離內、拉開距離時的預備高度：比瞄準低，瞄準時再舉平，玩家才看得出要射了
const BOW_ARM_SHARPNESS := 18.0  # 弓手舉起 / 放下、射完右手放下的速度（同玩家放下弓）

const BEETLE_HIDE := -0.6       # 屍甲蟲鑽地時整隻在地面下多深
const SPEAR_ARM_GUARD := -0.9    # 盾槍兵持槍：手臂往前，槍尖朝前下方
const SHIELD_ARM_GUARD := -1.25  # 盾槍兵舉盾：左手臂往前抬，盾擋在胸前
var rig   # Rig（Boss）或 SkinnedRig（小怪，D5）：關節介面相同
var walk_phase := 0.0
var _prev_state: StringName = &""
var _crack_root: Node3D = null              # Boss 砸地的裂紋（掛在 rig 下，蹲低時抵銷高度，留在地面）
var _cracks: Array[Dictionary] = []         # 每一段：{ node, ring, start, dir, length }
var _crack_mats: Array[StandardMaterial3D] = []   # 每一圈共用一個材質（同一圈同時變亮）
var _base_body_scale := Vector3.ZERO        # 稀有度放大後的身體大小（第一次 update 時記下，膨脹以它為準）
var _zombie := false      # 腐屍、膨脹屍：走路時雙手往前伸、駝背
var _bloater := false     # 膨脹屍：脹大時身體放大、閃白，炸開後整隻不見
var _hound := false       # 屍犬（四足）：所有狀態都走 _pose_hound（arm = 前腳、leg = 後腳）
var _keeper := false      # 守墓人：右手鐵鏟、左手提燈；駝背
var _holds_bow := false   # 骷髏弓手：左手拿弓，不瞄準時照 _bow_arm_target
var _spearman := false    # 骷髏盾槍兵：左手塔盾舉在胸前、右手長槍
var _wheel := false       # 骨輪：所有狀態都走 _pose_wheel（整個輪子在 head 關節上）
var _beetle := false      # 屍甲蟲：所有狀態都走 _pose_beetle（鑽地時整隻藏在地面下）
var _spider := false      # 墓穴蜘蛛：所有狀態都走 _pose_spider
var _hive := false        # 蟲巢：所有狀態都走 _pose_hive（不會動，只有鼓動、鼓酸泡、塌掉）
var _worm := false        # 噬墓巨蟲（form 0）：所有狀態都走 _pose_worm
var _worm_hide := 0.0     # 噬墓巨蟲藏進地裡的比例（0 = 整隻在地面上、1 = 全部在地底），畫面自己補間
var _moth_alt := 0.0      # 屍蛾女王畫面上飛多高（畫面自己補間到 def.moth.altitude 或 0）
var _spin := 0.0          # 骨輪滾動的角度（畫面自己累加）
var _bow_arm_target := BOW_ARM_REST
var _dt := 0.0


func _init(p_rig: Node3D, e: Enemy) -> void:
	rig = p_rig
	_holds_bow = e.def.visual == &"ranged"
	_zombie = e.def.visual == &"zombie" or e.def.visual == &"bloater"
	_bloater = e.def.visual == &"bloater"
	_hound = e.def.visual == &"hound"
	_spearman = e.def.visual == &"spearman"
	_wheel = e.def.visual == &"bone_wheel"
	_beetle = e.def.visual == &"beetle"
	_spider = e.def.visual == &"spider"
	_hive = e.def.visual == &"hive"
	_worm = e.def.visual == &"grave_worm"
	walk_phase = randf() * TAU   # 畫面用隨機，與模擬無關
	if e.def.has("slam"):
		_build_cracks(e)
	_keeper = e.def.visual == &"gravekeeper"


func update(e: Enemy, dt: float) -> void:
	_dt = dt
	var a := e.anim
	var state: StringName = a.state
	var t: float = a.time
	if _base_body_scale == Vector3.ZERO:
		_base_body_scale = rig.body.scale
	if state != _prev_state:
		# 網頁版各狀態 exit 時的還原
		rig.body.rotation.x = 0.0
		rig.head.rotation.x = 0.0
		rig.head.rotation.y = 0.0
		rig.arm_r.rotation.y = 0.0
		rig.position.y = 0.0
		_prev_state = state
	var moving := e.velocity.length_squared() > 0.01
	var def := e.def
	_bow_arm_target = BOW_ARM_REST
	if _holds_bow and state == &"kite":
		# 目標在射擊距離內就舉著弓：每台用同步過來的位置自己算，不經連線；
		# 距離條件同 RangedEnemy 的 Kite（射程上限 + fire_reach），但不看牆，繞牆時也舉著
		var target: Entity = e.nearest_target()
		if target != null and e.pos.distance_to(target.pos) <= def.preferred_range[1] + def.fire_reach:
			_bow_arm_target = BOW_ARM_READY

	if _zombie and rig is SkinnedRig:   # 持武器的腐屍：手上拿撿到的武器
		var base: StringName = StringName(a.get("weapon", ""))
		var kit: Dictionary = EnemyDefs.armed_kit(base) if base != &"" else {}
		(rig as SkinnedRig).set_held_weapon(kit.get("model", &""), kit.get("offhand_model", &""))

	var colossus: bool = def.has("colossus") and a.get("form", 0) > 0 and state != &"dead"
	match &"worm" if _worm and a.get("form", 0) == 0 else &"moth" if _worm else &"hive" if _hive else &"hound" if _hound else (&"wheel" if _wheel else (&"beetle" if _beetle else (&"spider" if _spider else (&"colossus" if colossus else (&"keeper" if _keeper and state != &"spawn" and state != &"dead" else state))))):
		&"colossus":
			_pose_colossus(e, a, state, t, dt)
		&"beetle":
			_pose_beetle(e, state, t, dt)
		&"spider":
			_pose_spider(e, state, t, dt)
		&"hive":
			_pose_hive(e, state, t)
		&"worm":
			_pose_worm(e, a, state, t, dt)
		&"moth":
			_pose_moth(e, a, state, t, dt)
		&"hound":
			_pose_hound(e, a, state, t, dt)
		&"wheel":
			_pose_wheel(e, state, t, dt)
		&"keeper":
			_pose_keeper(e, a, state, t, dt)
		&"spawn":
			var k := MathUtil.ease_out_cubic(clampf(t / def.spawn_time, 0.0, 1.0))
			rig.position.y = lerpf(-rig.height, 0.0, k)
			_pose_walk(0.0, -0.4, -0.2)
		&"dormant":
			_pose_walk(0.0, -0.6, -0.3)   # 怪群休眠：站著
		&"hurt":
			var k := clampf(t / def.hurt_time, 0.0, 1.0)
			rig.body.rotation.x = -0.35 * sin(k * PI)
			rig.arm_r.rotation.x = MathUtil.damp(rig.arm_r.rotation.x, -0.6, HURT_ARM_SHARPNESS, dt)
			rig.arm_l.rotation.x = MathUtil.damp(rig.arm_l.rotation.x, -0.6, HURT_ARM_SHARPNESS, dt)
		&"dead":
			var fall := clampf(t / DEATH_FALL_TIME, 0.0, 1.0)
			rig.body.rotation.x = lerpf(0.0, -PI / 2.0, MathUtil.ease_out_cubic(fall))
			rig.body.position.y = 0.13 * fall
			var corpse: float = def.corpse_time
			var sink_start := corpse * CORPSE_SINK_START
			rig.position.y = -CORPSE_SINK_DEPTH * clampf((t - sink_start) / (corpse - sink_start), 0.0, 1.0)
			# 死亡爆炸詞條：爆開前屍體一下一下脹大、閃白（不畫預警圈）
			var swell := volatile_swell(e, t)
			rig.body.scale = _sized_scale(a) * (1.0 + swell)
		&"launch":
			# 從挖墳點噴出來：雙手往上甩、腿縮起來
			rig.arm_r.rotation.x = -2.4 + 0.3 * sin(t * 18.0)
			rig.arm_l.rotation.x = -2.4 - 0.3 * sin(t * 18.0)
			rig.leg_r.rotation.x = 0.6
			rig.leg_l.rotation.x = 0.4
		&"chase", &"patrol":
			if e.is_boss():
				walk_phase += dt * e.velocity.length() * 1.6
				_pose_walk(1.0 if moving else 0.0, -0.5, -0.3)
			elif _spearman:
				walk_phase += dt * e.velocity.length() * 1.8
				_pose_walk(0.6 if moving else 0.0, SPEAR_ARM_GUARD, SHIELD_ARM_GUARD)
				rig.arm_l.rotation.y = 0.35   # 盾往身體正前方收
			elif _zombie:
				walk_phase += dt * e.velocity.length() * 2.6
				_pose_walk(0.6 if moving else 0.0, -1.35, -1.45)
				rig.body.rotation.x = 0.18
			else:
				walk_phase += dt * e.velocity.length() * 2.2
				_pose_walk(1.0 if moving else 0.0, -0.6, -0.3)
		&"swing":
			_pose_walk(0.0, -0.6, -0.3)
			_pose_melee_swing(t, def.swing)
		&"thrust":
			_pose_walk(0.0, SPEAR_ARM_GUARD, SHIELD_ARM_GUARD)
			_pose_thrust(t, def.thrust)
		&"guard_broken":
			# 破防：盾甩到外側、身體往後仰，break_time 內慢慢收回
			var k := clampf(t / def.shield.break_time, 0.0, 1.0)
			var out := 1.0 - MathUtil.ease_out_cubic(k)
			_pose_walk(0.0, -0.4, -0.3)
			rig.arm_l.rotation.y = -1.1 * out
			rig.arm_l.rotation.x = lerpf(SHIELD_ARM_GUARD, -0.4, out)
			rig.body.rotation.x = -0.28 * out
			rig.head.rotation.x = -0.3 * out
		&"kite":
			walk_phase += dt * e.velocity.length() * 2.2
			_pose_walk(1.0 if moving else 0.0, -0.2, -0.5)
		&"aim":
			var draw := MathUtil.ease_out_cubic(minf(1.0, t / def.aim_time * 1.5))
			# 已經舉在預備高度（目標一直在射擊距離內）就從那裡往上舉，不先放下
			rig.arm_l.rotation.x = minf(rig.arm_l.rotation.x, lerpf(BOW_ARM_REST, BOW_ARM_AIM, draw))
			rig.arm_r.rotation.x = lerpf(-0.2, -1.45, draw)
			rig.arm_r.rotation.y = lerpf(0.0, 0.5, draw)
			rig.leg_r.rotation.x = 0.0
			rig.leg_l.rotation.x = 0.0
		&"slam":
			_pose_slam(a)
		&"charge":
			_pose_charge(a, dt, def.charge)
		&"cleave":
			# 直劈（沒有地面預警）：比骷髏揮砍更誇張地把劍舉過頭、身體後仰，看動作就知道要劈下來
			_pose_walk(0.0, -0.5, -0.3)
			var c: Dictionary = def.cleave
			_pose_melee_swing(t, {"windup": a.get("windup", c.windup), "active": c.active, "recovery": c.recovery})
			if t < a.get("windup", c.windup):
				rig.body.rotation.x = lerpf(0.0, -0.32, MathUtil.ease_out_cubic(t / a.get("windup", c.windup)))
		&"rush":
			_pose_rush(a, dt, def.rush)
		&"lunge":
			_pose_lunge(a, def.lunge)
		&"fetch":
			# 撿武器：走過去照常走路；彎腰伸手往地上撿
			if a.get("phase", &"walk") == &"bend":
				var k := MathUtil.ease_out_cubic(clampf(a.get("phase_time", 0.0) / def.pickup.bend, 0.0, 1.0))
				_pose_walk(0.0, lerpf(-0.6, -0.3, k), -0.4)
				rig.body.rotation.x = lerpf(0.1, 0.8, k)
				rig.head.rotation.x = 0.3 * k
			else:
				walk_phase += dt * e.velocity.length() * 2.0
				_pose_walk(1.0 if moving else 0.0, -1.35, -1.45)
		&"armed_move":
			_pose_armed(a, dt)
		&"swell":
			# 膨脹屍脹大：站定、雙手抱著肚子、身體往後仰抖動（放大與閃白在下面 bloater_swell）；抱住玩家時雙手往前環抱
			if a.get("hugging", false):
				_pose_walk(0.0, -1.3, -1.3)
				rig.body.rotation.x = 0.1 + sin(t * 30.0) * 0.04
			else:
				_pose_walk(0.0, -0.7, -0.7)
				rig.body.rotation.x = -0.15 + sin(t * 30.0) * 0.04
		&"hug":
			# 膨脹屍撲抱：挺肚子（後仰）、雙手往兩側張開 → 撲出去雙手往前合抱
			var h: Dictionary = def.hug
			var pt: float = a.get("phase_time", 0.0)
			if a.get("phase", &"windup") == &"windup":
				var k := MathUtil.ease_out_cubic(clampf(pt / h.windup, 0.0, 1.0))
				_pose_arms(lerpf(-0.6, -1.4, k), lerpf(0.2, 1.0, k))
				rig.body.rotation.x = lerpf(0.0, -0.3, k)
			else:
				_pose_walk(0.0, -1.5, -1.5)
				rig.body.rotation.x = 0.25
		&"fallen":
			# 撲抱被擋下：往後倒坐在地上
			var k := MathUtil.ease_out_cubic(clampf(t / 0.2, 0.0, 1.0))
			rig.body.rotation.x = lerpf(0.0, -0.9, k) if t < def.hug.blocked_fall - 0.15 else lerpf(-0.9, 0.0, (t - def.hug.blocked_fall + 0.15) / 0.15)
			_pose_arms(-0.4)
		&"bite":
			# 啃咬：雙手抓著往前、頭一下一下咬下去
			_pose_walk(0.0, -1.2 + sin(t * 20.0) * 0.08, -1.25 - sin(t * 20.0) * 0.08)
			rig.body.rotation.x = 0.35
			rig.head.rotation.x = 0.25 + 0.25 * maxf(0.0, sin(t * TAU / def.lunge.bite_interval))
		&"stagger":
			# 撲抱被擋下：往後踉蹌、雙手亂揮
			var k := clampf(t / def.lunge.blocked_stagger, 0.0, 1.0)
			rig.body.rotation.x = -0.35 * sin(k * PI)
			_pose_arms(-0.8 + sin(t * 18.0) * 0.4)
		&"transform":
			if def.has("colossus"):
				# 骸骨將軍脫甲：跪下、低頭、雙手撐地，盔甲碎片往外飛（特效）
				var k := MathUtil.ease_out_cubic(clampf(t / 0.4, 0.0, 1.0))
				rig.body.position.y = -0.35 * k
				rig.body.rotation.x = 0.45 * k + sin(t * 25.0) * 0.03
				rig.head.rotation.x = 0.4 * k
				_pose_arms(lerpf(-0.3, -0.9, k), 0.2)
				rig.leg_r.rotation.x = -1.3 * k
				rig.leg_l.rotation.x = 0.5 * k
		&"summon":
			# 召喚：雙臂往兩側張開、身體後仰、抬頭看天（和砸地的雙手高舉分開）
			var k := MathUtil.ease_out_cubic(clampf(t / def.summon.windup, 0.0, 1.0))
			_pose_arms(lerpf(-0.4, -1.5, k), lerpf(0.3, 1.3, k))
			rig.body.rotation.x = lerpf(0.0, -0.35, k)
			rig.head.rotation.x = lerpf(0.0, -0.45, k)

	if _crack_root != null:
		_update_cracks(e, a)
	var flash_time: float = Config.COMBAT.flash_time
	var flash := 0.9 * e.flash_timer / flash_time if e.flash_timer > 0.0 else 0.0
	if state == &"dead":
		flash = maxf(flash, volatile_flash(e, t))
	if _bloater:
		var k := bloater_swell(e, state, t)
		flash = maxf(flash, 0.7 * k * pow(sin(k * (3.0 + 8.0 * k) * PI), 2.0))
		rig.body.scale = _base_body_scale * (1.0 + BLOATER_SWELL * k * (0.85 + 0.15 * sin(k * 10.0 * PI)))
		rig.scale = Vector3.ONE * (0.01 if a.get("burst", false) else 1.0)   # 炸開了：屍體不見（腐氣還在）
	rig.set_flash(flash)
	if rig is SkinnedRig:
		rig.flush()


# 身體大小：稀有度放大後 × 守墓人開打後的體型（動畫欄位 size）
func _sized_scale(a: Dictionary) -> Vector3:
	return _base_body_scale * float(a.get("size", 1.0))


func _pose_walk(amount: float, arm_r: float, arm_l: float) -> void:
	var swing := sin(walk_phase) * 0.8 * amount
	rig.leg_r.rotation.x = swing
	rig.leg_l.rotation.x = -swing
	if _holds_bow:   # 拿弓的手走路時不擺；兩手的舉起、放下（含射完從拉弦姿勢放下右手）都平滑轉過去
		var s := BOW_ARM_SHARPNESS
		rig.arm_l.rotation.x = MathUtil.damp(rig.arm_l.rotation.x, _bow_arm_target, s, _dt)
		rig.arm_r.rotation.x = MathUtil.damp(rig.arm_r.rotation.x, arm_r - swing * 0.4, s, _dt)
		rig.arm_r.rotation.y = MathUtil.damp(rig.arm_r.rotation.y, 0.0, s, _dt)
	else:
		rig.arm_r.rotation.x = arm_r - swing * 0.4
		rig.arm_l.rotation.x = arm_l + swing * 0.5
		rig.arm_r.rotation.y = 0.0
	rig.arm_l.rotation.y = 0.0
	rig.body.position.y = absf(sin(walk_phase)) * 0.04 * amount


func _pose_arms(rx: float, ry: float = 0.0) -> void:
	rig.arm_r.rotation = Vector3(rx, -ry, 0.0)
	rig.arm_l.rotation = Vector3(rx, ry, 0.0)


# 骷髏戰士揮砍：舉刀（手臂高舉、身體後仰，看得出要出手）→ 揮下（由上往下砸、身體前傾）→ 收招回到持刀姿勢
func _pose_melee_swing(t: float, s: Dictionary) -> void:
	var arm = rig.arm_r   # Node3D 或 SkinnedRig.Joint
	var windup: float = s.windup
	var active: float = s.active
	if t < windup:
		var k := MathUtil.ease_out_cubic(t / windup)
		arm.rotation.x = lerpf(-0.6, -2.9, k)
		rig.body.rotation.x = lerpf(0.0, -0.18, k)
	elif t < windup + active:
		var k := (t - windup) / active
		arm.rotation.x = lerpf(-2.9, -0.3, k)
		rig.body.rotation.x = lerpf(-0.18, 0.25, k)
	else:
		var k := clampf((t - windup - active) / s.recovery, 0.0, 1.0)
		arm.rotation.x = lerpf(-0.3, -0.6, k)
		rig.body.rotation.x = lerpf(0.25, 0.0, k)


# 骨輪：滾的時候輪子照移動距離轉（÷ 半徑）；蓄力原地喀啦晃、往後轉一點；撞牆倒下散開、最後 reform 秒立回來；
# 死掉倒下沉入地面；爬出照一般的從地下升起
func _pose_wheel(e: Enemy, state: StringName, t: float, dt: float) -> void:
	var head = rig.head
	var r := DarkFantasy.WHEEL_RADIUS
	_spin += e.velocity.length() * dt / r
	head.rotation = Vector3(_spin, 0.0, 0.0)
	head.position.y = r
	head.scale = Vector3.ONE
	rig.position.y = 0.0
	match state:
		&"spawn":
			rig.position.y = lerpf(-rig.height, 0.0, MathUtil.ease_out_cubic(clampf(t / e.def.spawn_time, 0.0, 1.0)))
		&"windup":
			_spin -= dt * 1.5
			head.rotation = Vector3(_spin, 0.0, sin(t * 45.0) * 0.08)
			head.scale = Vector3(1.0, 0.94, 0.94)
		&"collapse", &"dead":
			var c: Dictionary = e.def.roll
			var fall := MathUtil.ease_out_cubic(clampf(t / 0.25, 0.0, 1.0))
			var up := 0.0 if state == &"dead" else clampf((t - (c.collapse - c.reform)) / c.reform, 0.0, 1.0)
			var lie := fall * (1.0 - up)
			head.rotation = Vector3(_spin, 0.0, lerpf(0.0, PI / 2.0, lie))
			head.position.y = lerpf(r, 0.12, lie)
			head.scale = Vector3(1.0 + 0.3 * lie, 1.0, 1.0 + 0.3 * lie)   # 散開：攤成一圈骨堆
			if state == &"dead":
				rig.position.y = -CORPSE_SINK_DEPTH * clampf((t - e.def.corpse_time * CORPSE_SINK_START) / (e.def.corpse_time * (1.0 - CORPSE_SINK_START)), 0.0, 1.0)


# 墓穴蜘蛛：走路腳交錯擺；瞄準時前腳抬起、身體往前壓（腹部翹起）；受傷抖一下；死掉縮腳翻肚
func _pose_spider(e: Enemy, state: StringName, t: float, dt: float) -> void:
	rig.position.y = 0.0
	rig.body.rotation = Vector3.ZERO
	rig.body.position.y = 0.0
	match state:
		&"aim":
			var k := MathUtil.ease_out_cubic(clampf(t / e.def.aim_time, 0.0, 1.0))
			rig.arm_r.rotation.x = lerpf(0.0, -1.5, k)
			rig.arm_l.rotation.x = lerpf(0.0, -1.5, k)
			rig.leg_r.rotation.x = 0.0
			rig.leg_l.rotation.x = 0.0
			rig.body.rotation.x = lerpf(0.0, 0.35, k)
		&"hurt":
			rig.body.rotation.z = sin(t * 60.0) * 0.12
		&"spawn":
			rig.position.y = lerpf(-rig.height, 0.0, clampf(t / e.def.spawn_time, 0.0, 1.0))
		&"dead":
			var k := MathUtil.ease_out_cubic(clampf(t / 0.3, 0.0, 1.0))
			rig.body.rotation.z = PI * k
			rig.body.position.y = 0.6 * k
			for limb in [rig.arm_r, rig.arm_l, rig.leg_r, rig.leg_l]:
				limb.rotation.x = -1.0 * k
		_:
			walk_phase += dt * e.velocity.length() * 4.0
			var swing := sin(walk_phase) * 0.6 * (1.0 if e.velocity.length_squared() > 0.01 else 0.0)
			rig.arm_r.rotation.x = swing
			rig.leg_l.rotation.x = swing
			rig.arm_l.rotation.x = -swing
			rig.leg_r.rotation.x = -swing


# 噬墓巨蟲：地底時整隻藏在地面下；巡邏只露出半截；冒在地面時左右搖、大顎開合；噴酸頭後仰再往前甩；
# 吞噬嘴往前伸、大顎張到最開、整隻發抖；產卵往前趴；鑽下去沉進地裡；死掉倒下
func _pose_worm(e: Enemy, a: Dictionary, state: StringName, t: float, dt: float) -> void:
	var hide := 0.0
	var lean := 0.0
	var jaws := 0.35 + 0.15 * sin(t * 5.0)
	rig.body.rotation = Vector3(0.0, 0.0, sin(walk_phase) * 0.05)
	walk_phase += dt * 2.0
	match state:
		&"tunnel", &"lurk":
			hide = 1.0
		&"patrol", &"dormant":
			hide = 0.55
		&"dive":
			hide = clampf(t / e.def.tunnel.dive, 0.0, 1.0)
		&"spawn":
			hide = 1.0 - clampf(t / e.def.spawn_time, 0.0, 1.0)
		&"acid":
			var w: float = e.def.acid.windup
			lean = lerpf(0.0, -0.5, clampf(t / w, 0.0, 1.0)) if t < w else lerpf(-0.5, 0.45, clampf((t - w) / 0.12, 0.0, 1.0))
			jaws = 0.9
		&"devour":
			lean = 0.5
			jaws = 1.2
			if a.get("phase", &"windup") == &"pull":
				rig.body.rotation.z = sin(t * 50.0) * 0.04
		&"eggs":
			lean = 0.35
		&"pupate":   # 結蛹：縮進地裡一半、大顎合起來、整隻發抖
			hide = 0.45
			jaws = 0.0
			rig.body.rotation.z = sin(t * 35.0) * 0.03
		&"dead":
			var k := MathUtil.ease_out_cubic(clampf(t / 0.6, 0.0, 1.0))
			rig.body.rotation.z = 1.35 * k
			hide = 0.4 * clampf((t - e.def.corpse_time * CORPSE_SINK_START) / (e.def.corpse_time * (1.0 - CORPSE_SINK_START)), 0.0, 1.0)
	if a.get("burrowed", false):
		hide = 1.0
	_worm_hide = move_toward(_worm_hide, hide, dt * 5.0)
	rig.position.y = -(rig.height + 0.4) * _worm_hide
	rig.body.rotation.x = lean
	rig.head.rotation.x = lean * 0.6
	rig.arm_r.rotation.y = -jaws
	rig.arm_l.rotation.y = jaws


# 屍蛾女王（噬墓巨蟲 form 1）：飛著時整隻抬高到 moth.altitude、翅膀一直拍；撒鱗粉拍得又快又小；拍翅狂風翅膀先往後張再往前扇；
# 俯衝先收翅拉高、衝的時候身體前傾貼地；落地翅膀攤平慢慢動；死掉掉到地上翻倒
func _pose_moth(e: Enemy, a: Dictionary, state: StringName, t: float, dt: float) -> void:
	var m: Dictionary = e.def.moth
	var alt: float = m.altitude if a.get("flying", false) else 0.0
	var flap_speed := 14.0
	var flap := 0.55
	var spread := 0.25   # 翅膀平均往上抬的角度
	var sweep := 0.0     # 翅膀往後張（+）/ 往前扇（−）
	rig.body.rotation = Vector3.ZERO
	match state:
		&"dust":
			flap_speed = 34.0
			flap = 0.2
		&"gust":
			var w: float = m.gust.windup
			sweep = lerpf(0.0, 0.9, clampf(t / w, 0.0, 1.0)) if t < w else lerpf(0.9, -0.8, clampf((t - w) / 0.12, 0.0, 1.0))
			rig.body.rotation.x = -0.3 if t < w else 0.2
			flap = 0.1
		&"swoop":
			match a.get("phase", &"windup"):
				&"windup":
					alt = m.altitude + 1.2
					spread = 1.2
					flap = 0.05
				&"dash":
					alt = 0.5
					spread = 0.1
					flap = 0.05
					rig.body.rotation.x = 0.6
				_:
					alt = 0.3
		&"land":
			flap_speed = 3.0
			flap = 0.15
			spread = 0.05
		&"dead":
			alt = 0.0
			flap = 0.0
			spread = -0.1
			rig.body.rotation.z = 1.2 * MathUtil.ease_out_cubic(clampf(t / 0.5, 0.0, 1.0))
	walk_phase += dt * flap_speed
	_moth_alt = move_toward(_moth_alt, alt, dt * 7.0)
	rig.position.y = _moth_alt + (0.12 * sin(walk_phase * 0.25) if alt > 0.0 else 0.0)
	var up := spread + flap * sin(walk_phase)
	rig.arm_r.rotation = Vector3(0.0, sweep, -up)
	rig.arm_l.rotation = Vector3(0.0, -sweep, up)
	rig.leg_r.rotation.x = 0.3
	rig.leg_l.rotation.x = 0.3


# 蟲巢：平常慢慢鼓動；噴酸前整顆抽搐、卵囊鼓起來；被打破塌成一攤沉下去；爬出從地下升起
func _pose_hive(e: Enemy, state: StringName, t: float) -> void:
	rig.position.y = 0.0
	rig.body.rotation = Vector3.ZERO
	var swell := 1.0 + 0.03 * sin(t * 3.0)
	var sacs := 1.0
	var squash := 1.0
	match state:
		&"spit":
			var k := clampf(t / e.def.acid.windup, 0.0, 1.0)
			swell = 1.0 + 0.12 * k
			sacs = 1.0 + 0.5 * k
			rig.body.rotation.z = sin(t * 55.0) * 0.06
		&"spawn":
			rig.position.y = lerpf(-rig.height, 0.0, clampf(t / e.def.spawn_time, 0.0, 1.0))
		&"dead":
			squash = lerpf(1.0, 0.2, MathUtil.ease_out_cubic(clampf(t / 0.35, 0.0, 1.0)))
			sacs = squash
			rig.position.y = -CORPSE_SINK_DEPTH * 0.5 * clampf((t - e.def.corpse_time * CORPSE_SINK_START) / (e.def.corpse_time * (1.0 - CORPSE_SINK_START)), 0.0, 1.0)
	rig.body.scale = _base_body_scale * Vector3(swell, swell * squash, swell)
	rig.head.scale = Vector3.ONE * sacs
	for limb in [rig.arm_r, rig.arm_l, rig.leg_r, rig.leg_l]:
		limb.scale = Vector3.ONE * sacs


# 屍甲蟲：鑽地時藏在地面下（BEETLE_HIDE）；冒出前在地面下抖、露出一點殼；冒出來往上跳一下；在地面上腳一直抖；
# 爬出照一般從地下升起；死掉翻肚
func _pose_beetle(e: Enemy, state: StringName, t: float, dt: float) -> void:
	rig.body.rotation = Vector3.ZERO
	rig.position.y = 0.0
	var scurry := sin(t * 40.0) * 0.5
	for leg in [rig.arm_r, rig.leg_l]:
		leg.rotation.x = scurry
	for leg in [rig.arm_l, rig.leg_r]:
		leg.rotation.x = -scurry
	match state:
		&"burrow", &"dormant":
			rig.position.y = BEETLE_HIDE if state == &"burrow" else 0.0
		&"emerge":
			rig.position.y = lerpf(BEETLE_HIDE, -0.2, clampf(t / e.def.burrow.emerge, 0.0, 1.0)) + sin(t * 50.0) * 0.03
		&"surface":
			rig.position.y = maxf(0.0, 0.5 * sin(clampf(t / 0.3, 0.0, 1.0) * PI)) if t < 0.3 else 0.0
		&"spawn":
			rig.position.y = lerpf(-rig.height, 0.0, clampf(t / e.def.spawn_time, 0.0, 1.0))
		&"dead":
			rig.body.rotation.z = PI * MathUtil.ease_out_cubic(clampf(t / 0.3, 0.0, 1.0))
			rig.body.position.y = 0.25
			rig.position.y = -CORPSE_SINK_DEPTH * 0.5 * clampf((t - e.def.corpse_time * CORPSE_SINK_START) / (e.def.corpse_time * (1.0 - CORPSE_SINK_START)), 0.0, 1.0)
	if state != &"dead":
		rig.body.position.y = 0.0


# 萬骨聚合體（骸骨將軍 form 1）：追擊駝背拖著走；骨刺陣雙臂高舉 → 插進地面；多臂橫掃先扭到底、低掃（彎腰）轉一圈、
# 高掃（挺胸）再轉一圈；巨骨輪蜷成球、滾的時候晃；撞牆暈倒仰躺；吞屍雙臂張開、胸口往前挺
func _pose_colossus(e: Enemy, a: Dictionary, state: StringName, t: float, dt: float) -> void:
	var c: Dictionary = e.def.colossus
	rig.body.position.y = 0.0
	rig.body.rotation = Vector3(0.25, 0.0, 0.0)
	rig.leg_r.rotation.x = 0.0
	rig.leg_l.rotation.x = 0.0
	match state:
		&"spikes":
			var w: float = c.spikes.windup
			var k := MathUtil.ease_out_cubic(clampf(t / w, 0.0, 1.0))
			if t < w:
				_pose_arms(lerpf(-0.5, -2.9, k), 0.25)
				rig.body.rotation.x = lerpf(0.25, -0.2, k)
			else:
				var d := MathUtil.ease_out_cubic(clampf((t - w) / 0.12, 0.0, 1.0))
				_pose_arms(lerpf(-2.9, -0.35, d), 0.25)
				rig.body.rotation.x = lerpf(-0.2, 0.6, d)
		&"sweep":
			var s: Dictionary = c.sweep
			var pt: float = a.get("phase_time", t)
			match a.get("phase", &"windup"):
				&"windup":
					var k := MathUtil.ease_out_cubic(clampf(pt / s.windup, 0.0, 1.0))
					rig.body.rotation.y = -1.3 * k
					_pose_arms(-1.2, lerpf(0.3, 1.4, k))
				&"low":
					rig.body.rotation = Vector3(0.55, -1.3 + TAU * clampf(pt / s.gap, 0.0, 1.0), 0.0)
					_pose_arms(-0.9, 1.5)
				&"high":
					rig.body.rotation = Vector3(-0.15, -1.3 + TAU * clampf(pt / 0.3, 0.0, 1.0), 0.0)
					_pose_arms(-1.6, 1.5)
		&"wheel":
			_pose_arms(-2.4, 0.4)
			rig.leg_r.rotation.x = -1.2
			rig.leg_l.rotation.x = -1.2
			rig.body.position.y = -0.2
			rig.body.rotation.x = 1.0
			rig.head.rotation.x = 0.6
			if a.get("phase", &"windup") == &"roll":
				rig.body.rotation.z = sin(t * 22.0) * 0.15
				rig.body.position.y = -0.2 + absf(sin(t * 11.0)) * 0.15
		&"wheel_stun":
			rig.body.rotation.x = -0.55
			rig.body.position.y = -0.3
			_pose_arms(-0.3, 1.2)
			rig.head.rotation.x = -0.4 + sin(t * 3.0) * 0.1
		&"devour":
			var k := MathUtil.ease_out_cubic(clampf(t / c.devour.windup, 0.0, 1.0))
			_pose_arms(lerpf(-0.6, -1.4, k), lerpf(0.3, 1.4, k))
			rig.body.rotation.x = lerpf(0.25, -0.35, k)
			rig.head.rotation.x = lerpf(0.0, -0.4, k)
		_:
			walk_phase += dt * e.velocity.length() * 1.3
			_pose_walk(1.0 if e.velocity.length_squared() > 0.01 else 0.0, -0.4, -0.4)
			rig.body.rotation.x = 0.25


# 盾槍兵直刺：盾往外偏、槍收到腰間（windup）→ 往前刺到手臂打直、身體前傾（active）→ 收回舉盾（recovery）
func _pose_thrust(t: float, s: Dictionary) -> void:
	var windup: float = s.windup
	var active: float = s.active
	if t < windup:
		var k := MathUtil.ease_out_cubic(t / windup)
		rig.arm_r.rotation.x = lerpf(SPEAR_ARM_GUARD, -0.15, k)
		rig.arm_l.rotation.y = lerpf(0.35, -0.7, k)
		rig.body.rotation.x = lerpf(0.0, -0.12, k)
	elif t < windup + active:
		var k := (t - windup) / active
		rig.arm_r.rotation.x = lerpf(-0.15, -1.65, k)
		rig.arm_l.rotation.y = -0.7
		rig.body.rotation.x = lerpf(-0.12, 0.22, k)
	else:
		var k := clampf((t - windup - active) / s.recovery, 0.0, 1.0)
		rig.arm_r.rotation.x = lerpf(-1.65, SPEAR_ARM_GUARD, k)
		rig.arm_l.rotation.y = lerpf(-0.7, 0.35, k)
		rig.body.rotation.x = lerpf(0.22, 0.0, k)


# 砸地：warn（狂暴瞬移前，低頭蓄力）→ windup（雙手合握、筆直高舉）→ impact（蹲低、把劍插進地裡）
func _pose_slam(a: Dictionary) -> void:
	var pt: float = a.get("phase_time", 0.0)
	match a.get("phase", &"windup"):
		&"warn":
			_pose_arms(-0.4 + sin(pt * 20.0) * 0.1, 0.3)
			rig.body.rotation.x = 0.2
		&"windup":
			var k := MathUtil.ease_out_cubic(clampf(pt / maxf(a.get("windup", 0.7), 0.01), 0.0, 1.0))
			_pose_arms(lerpf(-0.4, -3.1, k), lerpf(0.3, 0.0, k))
			rig.body.rotation.x = lerpf(0.0, -0.15, k)
		_:
			var k := clampf(pt / SLAM_FOLLOW_TIME, 0.0, 1.0)
			_pose_arms(lerpf(-3.1, -0.6, k), 0.0)
			rig.body.rotation.x = lerpf(-0.15, 0.55, k)
			rig.position.y = -SLAM_CROUCH * k


# 守墓人（老人）：四招的預備動作兩兩不同（設計方向「怪物攻擊不畫紅圈」）
#   鐵鏟揮擊 = 鏟子扛到右肩後、身體往右扭；鏟土拋擲 = 彎腰把鏟子插進地裡、再往後撬；
#   提燈噴火 = 左手把提燈舉到臉前、身體後仰吸氣；口哨 = 右手兩指放進嘴裡、抬頭
func _pose_keeper(e: Enemy, a: Dictionary, state: StringName, t: float, dt: float) -> void:
	if a.get("form", 0) > 0:
		_pose_wolf(e, a, state, t, dt)
		return
	var def := e.def
	var pt: float = a.get("phase_time", 0.0)
	rig.body.rotation.y = 0.0
	rig.body.scale = _sized_scale(a)
	match state:
		&"transform":
			# 變身：彎腰咳嗽、全身抖、身體一下一下脹大（結束時換成狼人模型）
			var k := clampf(t / def.transform.time, 0.0, 1.0)
			rig.body.rotation.x = 0.6 * minf(1.0, k * 3.0) + sin(t * 40.0) * 0.05
			_pose_arms(-0.4 - 0.6 * k + sin(t * 30.0) * 0.1, 0.6 * k)
			rig.body.scale = _sized_scale(a) * (1.0 + 0.15 * k * (0.7 + 0.3 * sin(t * 18.0)))
		&"grow":
			# 變大：挺直、雙臂往兩側撐開、仰頭，全身抖（大小照 size 慢慢放大）
			var k := MathUtil.ease_out_cubic(clampf(t / def.grow.time, 0.0, 1.0))
			_pose_arms(lerpf(-0.5, -0.9, k) + sin(t * 30.0) * 0.08, lerpf(0.0, 0.9, k))
			rig.body.rotation.x = lerpf(0.3, -0.2, k)
			rig.head.rotation.x = lerpf(0.0, -0.35, k)
		&"patrol":
			# 掃地：走的時候駝背慢走，停下來時鏟子左右掃地
			var moving := e.velocity.length_squared() > 0.01
			walk_phase += dt * e.velocity.length() * 2.0
			_pose_walk(1.0 if moving else 0.0, -0.8, -0.5)
			rig.body.rotation.x = 0.3
			if not moving:
				rig.arm_r.rotation = Vector3(-0.9, 0.5 * sin(t * 2.5), 0.0)
		&"reveal":
			# 揭穿：挺直腰、轉頭看人
			var k := MathUtil.ease_out_cubic(clampf(t / 0.5, 0.0, 1.0))
			_pose_walk(0.0, -0.5, -0.4)
			rig.body.rotation.x = lerpf(0.3, -0.05, k)
			rig.head.rotation.x = lerpf(0.0, -0.15, k)
		&"chase":
			walk_phase += dt * e.velocity.length() * 2.0
			_pose_walk(1.0 if e.velocity.length_squared() > 0.01 else 0.0, -0.6, -0.5)
			rig.body.rotation.x = 0.25
		&"shovel":
			var s: Dictionary = def.shovel
			if t < s.windup:
				var k := MathUtil.ease_out_cubic(t / s.windup)
				rig.arm_r.rotation = Vector3(lerpf(-0.6, -2.6, k), lerpf(0.0, 0.9, k), 0.0)
				rig.body.rotation.y = lerpf(0.0, -0.5, k)
			else:
				var k := clampf((t - s.windup) / (s.active + 0.1), 0.0, 1.0)
				rig.arm_r.rotation = Vector3(lerpf(-2.6, -1.3, k), lerpf(0.9, -0.9, k), 0.0)
				rig.body.rotation.y = lerpf(-0.5, 0.5, k)
			rig.arm_l.rotation = Vector3(-0.5, 0.0, 0.0)
			rig.body.rotation.x = 0.15
		&"dig":
			# 瘋狂鏟土：彎腰把鏟子插進地裡（windup）→ 鏟子一下一下往後狂甩土、身體跟著上下 → 收招
			var l: Dictionary = def.dig
			match a.get("phase", &"windup"):
				&"windup":
					var k := MathUtil.ease_out_cubic(clampf(pt / l.windup, 0.0, 1.0))
					rig.body.rotation.x = lerpf(0.25, 0.7, k)
					rig.arm_r.rotation = Vector3(lerpf(-0.6, 0.2, k), 0.0, 0.0)
					rig.arm_l.rotation = Vector3(lerpf(-0.5, 0.1, k), 0.0, 0.0)
				&"dig":
					var s := sin(pt * 22.0)   # 一秒約 3.5 下
					rig.body.rotation.x = 0.55 + 0.2 * s
					rig.arm_r.rotation = Vector3(lerpf(0.2, -2.4, 0.5 + 0.5 * s), 0.3 * s, 0.0)
					rig.arm_l.rotation = Vector3(lerpf(0.1, -1.6, 0.5 + 0.5 * s), -0.2, 0.0)
					rig.head.rotation.x = 0.2
				_:
					var k := clampf(pt / l.recovery, 0.0, 1.0)
					rig.body.rotation.x = lerpf(0.55, 0.25, k)
					rig.arm_r.rotation = Vector3(lerpf(-1.2, -0.6, k), 0.0, 0.0)
		&"scoop":
			# 鏟起：鏟面貼地往前滑（彎腰、鏟子平伸）→ 拋飛：鏟子往後上方甩 → 埋地：鏟子往下壓、再退一步舉燈 → 直噴
			var s: Dictionary = def.scoop
			match a.get("phase", &"windup"):
				&"windup":
					var k := MathUtil.ease_out_cubic(clampf(pt / s.windup, 0.0, 1.0))
					rig.body.rotation.x = lerpf(0.25, 0.8, k)
					rig.arm_r.rotation = Vector3(lerpf(-0.6, -1.1, k), lerpf(0.0, -0.5, k), 0.0)
					rig.arm_l.rotation = Vector3(lerpf(-0.5, -1.0, k), lerpf(0.0, 0.4, k), 0.0)
					rig.head.rotation.x = 0.3 * k
				&"throw":
					var k := MathUtil.ease_out_cubic(clampf(pt / 0.25, 0.0, 1.0))
					rig.body.rotation.x = lerpf(0.8, -0.3, k)
					_pose_arms(lerpf(-1.1, -3.0, k), 0.2)
				&"bury":
					var b: Dictionary = s.bury
					if pt < b.step_time:
						var k := clampf(pt / b.step_time, 0.0, 1.0)
						rig.body.rotation.x = lerpf(0.8, 0.4, k)
						rig.arm_r.rotation = Vector3(lerpf(-1.1, 0.1, k), 0.0, 0.0)
					else:
						var k := MathUtil.ease_out_cubic(clampf((pt - b.step_time) / b.open, 0.0, 1.0))
						rig.arm_l.rotation = Vector3(lerpf(-0.5, -1.5, k), lerpf(0.0, -0.4, k), 0.0)
						rig.arm_r.rotation = Vector3(-0.4, 0.0, 0.0)
						rig.body.rotation.x = lerpf(0.4, 0.15, k)
				_:
					rig.body.rotation.x = lerpf(0.8, 0.25, clampf(pt / s.miss_recovery, 0.0, 1.0))
					rig.arm_r.rotation = Vector3(-0.8, 0.0, 0.0)
		&"lantern":
			var f: Dictionary = def.lantern
			match a.get("phase", &"windup"):
				&"windup":
					var k := MathUtil.ease_out_cubic(clampf(pt / f.windup, 0.0, 1.0))
					rig.arm_l.rotation = Vector3(lerpf(-0.5, -1.5, k), lerpf(0.0, -0.4, k), 0.0)
					rig.body.rotation.x = lerpf(0.25, -0.2, k)
					rig.head.rotation.x = lerpf(0.0, -0.2, k)
				&"spin_windup":
					# 轉圈前的預備：提燈往回收、身體後仰，看得出下一下要掃一圈
					var k := MathUtil.ease_out_cubic(clampf(pt / f.spin_windup, 0.0, 1.0))
					rig.arm_l.rotation = Vector3(-1.5, lerpf(-0.4, 0.8, k), 0.0)
					rig.body.rotation.x = lerpf(0.2, -0.25, k)
					rig.head.rotation.x = lerpf(0.1, -0.2, k)
				&"flame", &"spin":
					# 追著噴：腳照常走；轉圈時提燈往外伸
					walk_phase += dt * e.velocity.length() * 2.0
					_pose_walk(1.0 if e.velocity.length_squared() > 0.01 else 0.0, -0.4, -1.5)
					rig.arm_l.rotation = Vector3(-1.5, -0.9 if a.get("phase") == &"spin" else -0.4, 0.0)
					rig.body.rotation.x = 0.2
					rig.head.rotation.x = 0.1
				_:
					var k := clampf(pt / f.recovery, 0.0, 1.0)
					rig.arm_l.rotation = Vector3(lerpf(-1.5, -0.5, k), lerpf(-0.4, 0.0, k), 0.0)
					rig.body.rotation.x = lerpf(0.2, 0.25, k)
			rig.arm_r.rotation = Vector3(-0.4, 0.0, 0.0)
		&"whistle":
			var k := MathUtil.ease_out_cubic(clampf(t / def.whistle.windup, 0.0, 1.0))
			rig.arm_r.rotation = Vector3(lerpf(-0.6, -2.3, k), lerpf(0.0, -0.7, k), 0.0)
			rig.arm_l.rotation = Vector3(-0.5, 0.0, 0.0)
			rig.body.rotation.x = lerpf(0.25, -0.1, k)
			rig.head.rotation.x = lerpf(0.0, -0.4, k)


# 墓園狼人：三招的預備動作兩兩不同
#   三連爪 = 雙爪往後拉、張開；飛撲 = 四肢著地蹲低；狼嚎 = 仰頭、雙臂張開挺胸；隱入黑暗 = 壓低身體奔跑
func _pose_wolf(e: Enemy, a: Dictionary, state: StringName, t: float, dt: float) -> void:
	var w: Dictionary = e.def.wolf
	var pt: float = a.get("phase_time", 0.0)
	rig.body.rotation.y = 0.0
	rig.body.scale = _sized_scale(a)
	match state:
		&"wolf_chase", &"stalk":
			walk_phase += dt * e.velocity.length() * 1.6
			_pose_walk(1.0 if e.velocity.length_squared() > 0.01 else 0.0, 0.3, 0.3)
			rig.body.rotation.x = 0.7 if state == &"stalk" else 0.45
		&"claw":
			var c: Dictionary = w.claw
			if t < c.windup:
				var k := MathUtil.ease_out_cubic(t / c.windup)
				_pose_arms(0.9 * k, 0.6 * k)
				rig.body.rotation.x = 0.2 * k
				rig.head.rotation.x = 0.1 * k
			else:
				var n := clampi(floori((t - c.windup) / c.interval), 0, 2)   # 第幾下（0~2）
				var k := clampf((t - c.windup - n * c.interval) / c.interval, 0.0, 1.0)
				var swing := lerpf(0.9, -1.6, k)
				if n == 2:
					_pose_arms(swing, 0.2)   # 第三下雙爪一起往前撲
					rig.body.rotation.x = lerpf(0.2, 0.6, k)
				else:
					rig.arm_r.rotation = Vector3(swing if n == 0 else 0.9, -0.3, 0.0)
					rig.arm_l.rotation = Vector3(swing if n == 1 else 0.9, 0.3, 0.0)
					rig.body.rotation.x = 0.25
		&"leap":
			var l: Dictionary = w.leap
			match a.get("phase", &"windup"):
				&"windup":
					var k := MathUtil.ease_out_cubic(clampf(pt / l.windup, 0.0, 1.0))
					rig.body.rotation.x = lerpf(0.45, 1.0, k)
					_pose_arms(lerpf(0.3, -1.2, k))
					rig.position.y = -0.3 * k
					rig.head.rotation.x = -0.4 * k
				&"air":
					rig.position.y = 0.0
					rig.body.rotation.x = 0.3
					_pose_arms(-2.0, 0.3)
					rig.leg_r.rotation.x = 0.8
					rig.leg_l.rotation.x = 0.8
				_:
					var k := clampf(pt / l.recovery, 0.0, 1.0)
					rig.body.rotation.x = lerpf(0.8, 0.45, k)
					_pose_arms(lerpf(-1.2, 0.3, k))
		&"howl":
			var k := MathUtil.ease_out_cubic(clampf(t / w.howl.windup, 0.0, 1.0))
			_pose_arms(lerpf(0.3, -0.6, k), lerpf(0.0, 1.0, k))
			rig.body.rotation.x = lerpf(0.45, -0.2, k)
			rig.head.rotation.x = lerpf(0.0, -0.7, k)


# 屍犬（四足）：奔跑時前後腳交錯；飛撲 windup 伏低（看得出要撲）→ dash 前腳往前、後腳往後伸直 → recovery 收回；
# 死掉往側邊倒（橫的身體不能像人一樣往後倒）
func _pose_hound(e: Enemy, a: Dictionary, state: StringName, t: float, dt: float) -> void:
	var def := e.def
	var legs := Vector4.ZERO   # 前右、前左、後右、後左
	rig.body.rotation.z = 0.0
	match state:
		&"spawn":
			rig.position.y = lerpf(-rig.height, 0.0, MathUtil.ease_out_cubic(clampf(t / def.spawn_time, 0.0, 1.0)))
		&"chase", &"dormant":
			var amount := 1.0 if e.velocity.length_squared() > 0.01 else 0.0
			walk_phase += dt * e.velocity.length() * 2.4
			var s := sin(walk_phase) * 0.7 * amount
			var s2 := sin(walk_phase + 0.9) * 0.7 * amount
			legs = Vector4(s, -s, -s2, s2)
			rig.body.rotation.x = 0.05 * sin(walk_phase * 2.0) * amount
			rig.head.rotation.x = 0.0
		&"pounce":
			var c: Dictionary = def.pounce
			var pt: float = a.get("phase_time", 0.0)
			match a.get("phase", &"windup"):
				&"windup":
					var k := MathUtil.ease_out_cubic(clampf(pt / c.windup, 0.0, 1.0))
					rig.position.y = -0.15 * k
					rig.body.rotation.x = 0.15 * k
					rig.head.rotation.x = 0.25 * k
					legs = Vector4(-0.5, -0.5, 0.5, 0.5) * k
				&"dash":
					rig.position.y = 0.0
					rig.body.rotation.x = -0.1
					rig.head.rotation.x = -0.2
					legs = Vector4(-1.1, -1.1, 1.1, 1.1)
				_:
					var k := clampf(pt / c.recovery, 0.0, 1.0)
					rig.body.rotation.x = lerpf(-0.1, 0.0, k)
					rig.head.rotation.x = lerpf(-0.2, 0.0, k)
					legs = Vector4(-1.1, -1.1, 1.1, 1.1) * (1.0 - k)
		&"snap":   # 快咬：低頭、齜牙（頭壓低往前）→ 往前竄、張嘴咬
			var c: Dictionary = def.snap
			var pt: float = a.get("phase_time", 0.0)
			if a.get("phase", &"windup") == &"windup":
				var k := MathUtil.ease_out_cubic(clampf(pt / c.windup, 0.0, 1.0))
				rig.body.rotation.x = 0.1 * k
				rig.head.rotation.x = 0.45 * k
				legs = Vector4(-0.3, -0.3, 0.2, 0.2) * k
			else:
				rig.body.rotation.x = -0.05
				rig.head.rotation.x = -0.35
				legs = Vector4(-0.8, -0.6, 0.7, 0.5)
		&"hop":   # 側跳、往後跳：四腳收起
			rig.body.rotation.x = 0.0
			rig.head.rotation.x = 0.1
			legs = Vector4(0.6, 0.6, -0.6, -0.6)
		&"dazed":   # 被盾擋下：甩頭
			rig.head.rotation.x = 0.2
			rig.body.rotation.z = 0.15 * sin(t * 18.0)
		&"hurt":
			rig.body.rotation.z = 0.25 * sin(clampf(t / def.hurt_time, 0.0, 1.0) * PI)
		&"dead":
			var fall := clampf(t / DEATH_FALL_TIME, 0.0, 1.0)
			rig.body.rotation.z = lerpf(0.0, PI / 2.0, MathUtil.ease_out_cubic(fall))
			legs = Vector4(0.3, -0.2, -0.3, 0.2)
			var sink_start: float = def.corpse_time * CORPSE_SINK_START
			rig.position.y = -CORPSE_SINK_DEPTH * clampf((t - sink_start) / (def.corpse_time - sink_start), 0.0, 1.0)
	rig.arm_r.rotation = Vector3(legs.x, 0.0, 0.0)
	rig.arm_l.rotation = Vector3(legs.y, 0.0, 0.0)
	rig.leg_r.rotation = Vector3(legs.z, 0.0, 0.0)
	rig.leg_l.rotation = Vector3(legs.w, 0.0, 0.0)


# 持武器的腐屍出招（各招式的預兆不重複）：
# 揮擊 = 右手舉過頭後拉；射擊 = 雙手往前拉弓 / 法杖平舉；舉盾 = 左臂盾擋在胸前；爆裂 = 法杖舉到最高；
# 影步 = 蹲低；治療 = 雙臂張開仰頭；噴火 = 火把往前推、身體後仰；鏟起 = 彎腰鏟面貼地
func _pose_armed(a: Dictionary, _dt: float) -> void:
	var pt: float = a.get("phase_time", 0.0)
	var winding: bool = a.get("phase", &"windup") == &"windup"
	var k := MathUtil.ease_out_cubic(clampf(pt / 0.4, 0.0, 1.0))
	var active: bool = a.get("phase", &"") == &"active"
	match a.get("move_type", &"melee"):
		&"melee":
			if winding:
				_pose_walk(0.0, lerpf(-1.2, -2.8, k), -0.6)
				rig.body.rotation.x = lerpf(0.0, -0.2, k)
			else:
				_pose_walk(0.0, -0.7, -0.6)
				rig.body.rotation.x = 0.25 if active else 0.1
		&"shot":
			_pose_walk(0.0, -1.55, -1.5)
			rig.body.rotation.x = -0.1 * k if winding else 0.0
		&"shield":
			_pose_walk(0.0, -0.8, lerpf(-0.6, -1.5, k))
			rig.arm_l.rotation.y = 0.5 * k
			rig.body.rotation.x = 0.15 * k
		&"burst":
			_pose_walk(0.0, lerpf(-1.2, -3.1, k) if winding else -1.0, -0.4)
			rig.head.rotation.x = -0.3 * k if winding else 0.0
		&"blink":
			_pose_walk(0.0, -0.4, -0.4)
			rig.body.rotation.x = 0.5 * k
		&"heal":
			_pose_arms(-1.3, lerpf(0.3, 1.2, k))
			rig.head.rotation.x = -0.35 * k
		&"breath":
			_pose_walk(0.0, -1.7, -0.5)
			rig.body.rotation.x = -0.25 * k if winding else -0.1
		&"scoop":
			_pose_walk(0.0, lerpf(-0.6, -0.2, k), lerpf(-0.6, -0.3, k))
			rig.body.rotation.x = lerpf(0.0, 0.6, k) if winding else -0.2


# 腐屍撲抱：windup 雙手舉高、身體後仰（看得出要撲）→ dash 雙手往前抓、身體前撲 → recovery 慢慢收回
func _pose_lunge(a: Dictionary, l: Dictionary) -> void:
	var pt: float = a.get("phase_time", 0.0)
	match a.get("phase", &"windup"):
		&"windup":
			var k := MathUtil.ease_out_cubic(clampf(pt / l.windup, 0.0, 1.0))
			_pose_walk(0.0, lerpf(-1.35, -2.7, k), lerpf(-1.45, -2.7, k))
			rig.body.rotation.x = lerpf(0.18, -0.3, k)
			rig.head.rotation.x = lerpf(0.0, -0.3, k)
		&"dash":
			var k := clampf(pt / l.duration, 0.0, 1.0)
			_pose_walk(0.0, lerpf(-2.7, -1.5, k), lerpf(-2.7, -1.5, k))
			rig.body.rotation.x = lerpf(-0.3, 0.5, k)
			rig.head.rotation.x = 0.0
		_:
			var k := clampf(pt / l.recovery, 0.0, 1.0)
			_pose_walk(0.0, lerpf(-1.5, -1.35, k), lerpf(-1.5, -1.45, k))
			rig.body.rotation.x = lerpf(0.5, 0.18, k)


# 骷髏戰士衝撞（v0.27.0）：蓄力前傾 → 低頭衝刺 → 收招
func _pose_rush(a: Dictionary, dt: float, r: Dictionary) -> void:
	var pt: float = a.get("phase_time", 0.0)
	match a.get("phase", &"windup"):
		&"windup":
			var k := MathUtil.ease_out_cubic(clampf(pt / r.windup, 0.0, 1.0))
			_pose_arms(lerpf(-0.6, 0.5, k))
			rig.body.rotation.x = lerpf(0.0, 0.4, k)
		&"dash":
			walk_phase += dt * r.speed * 1.5
			_pose_walk(1.0, 0.5, 0.5)
			rig.body.rotation.x = 0.4
		_:
			rig.body.rotation.x = lerpf(0.4, 0.0, clampf(pt / r.recovery, 0.0, 1.0))
			_pose_arms(-0.6)


func _pose_charge(a: Dictionary, dt: float, c: Dictionary) -> void:
	var pt: float = a.get("phase_time", 0.0)
	match a.get("phase", &"windup"):
		&"windup":
			# 衝鋒：壓低身體、肩膀往前頂，後腳往後刨地兩下（effects 在刨地時揚起塵土）
			var kl := clampf(pt / maxf(a.get("windup", c.windup), 0.01), 0.0, 1.0)
			var k := MathUtil.ease_out_cubic(kl)
			_pose_arms(lerpf(-0.4, 0.6, k))
			rig.body.rotation.x = lerpf(0.0, 0.45, k)
			rig.leg_r.rotation.x = charge_scrape(kl)
			rig.leg_l.rotation.x = -0.3 * k
		&"dash":
			walk_phase += dt * c.speed * 1.2
			_pose_walk(1.0, 0.6, 0.6)
			rig.body.rotation.x = 0.35
		&"stunned":
			rig.body.rotation.x = -0.25 + sin(pt * 18.0) * 0.05
			rig.head.rotation.y = sin(pt * 6.0) * 0.4
			_pose_arms(-0.3)
		_:
			rig.body.rotation.x = lerpf(0.35, 0.0, clampf(pt / c.recovery, 0.0, 1.0))
			_pose_arms(-0.3)


# 衝鋒預備時後腳的角度：往後刨地兩下（kl = 預備進度 0~1）
static func charge_scrape(kl: float) -> float:
	return 0.25 + 0.55 * maxf(0.0, sin(kl * 2.0 * TAU))


# 膨脹屍脹大的進度 0~1：swell 狀態照 swell_time、被打死後照 death_delay；其他時候 0
static func bloater_swell(e: Enemy, state: StringName, t: float) -> float:
	var b: Dictionary = e.def.burst
	match state:
		&"swell":
			return clampf(t / e.anim.get("swell_time", b.swell_time), 0.0, 1.0)
		&"dead":
			return 0.0 if e.anim.get("burst", false) else clampf(t / b.death_delay, 0.0, 1.0)
	return 0.0


# ───────── 死亡爆炸詞條：屍體脹大、閃白 ─────────

# 死後 t 秒的膨脹量（0 = 原本大小）：越接近爆開脹得越大，同時一下一下抽動
static func volatile_swell(e: Enemy, t: float) -> float:
	if not e.has_affix(&"volatile"):
		return 0.0
	var delay: float = e.affix(&"volatile").delay
	if t >= delay:
		return 0.0
	var k := t / delay
	return VOLATILE_SWELL * k * (0.75 + 0.25 * sin(k * 9.0 * PI))


static func volatile_flash(e: Enemy, t: float) -> float:
	if not e.has_affix(&"volatile"):
		return 0.0
	var delay: float = e.affix(&"volatile").delay
	if t >= delay:
		return 0.0
	var k := t / delay
	return 0.6 * k * pow(sin(k * (3.0 + 6.0 * k) * PI), 2.0)   # 越來越快的閃白


# ───────── Boss 砸地的地板裂紋（不畫預警圈） ─────────

# 第 i 圈的裂紋狀態：x = 長出來的比例（0~1）、y = 亮度（0 = 不顯示）
# 時間軸以落地為 0（舉手時為負）：第 i 圈在 i × ring_delay 爆開；裂紋比爆開早 lead 秒爬到這一圈外緣，
# 爬到之後亮度從 CRACK_GROWN_GLOW 升到 1，爆開後 CRACK_FADE 秒內淡掉。lead = ring_delay（舉手時間很短時縮短）
static func slam_crack(phase: StringName, pt: float, windup: float, i: int, ring_delay: float) -> Vector2:
	var tau: float
	match phase:
		&"windup":
			tau = pt - windup
		&"impact":
			tau = pt
		_:
			return Vector2.ZERO
	var lead := minf(ring_delay, windup * CRACK_LEAD_MAX_WINDUP)
	var burst_at := i * ring_delay
	var grown_at := burst_at - lead
	var start := -windup if i == 0 else (i - 1) * ring_delay - lead
	var grow := clampf((tau - start) / maxf(grown_at - start, 0.01), 0.0, 1.0)
	if grow <= 0.0:
		return Vector2.ZERO
	var glow: float
	if tau < grown_at:
		glow = CRACK_GROWN_GLOW * grow
	elif tau < burst_at:
		glow = lerpf(CRACK_GROWN_GLOW, 1.0, (tau - grown_at) / maxf(burst_at - grown_at, 0.01))
	else:
		glow = 1.0 - (tau - burst_at) / CRACK_FADE
	return Vector2(grow, maxf(glow, 0.0))


# 第 i 圈是不是「已經爬滿、正在變亮、還沒爆開」：effects 在這一圈產生跳動的碎石
static func slam_band_charging(phase: StringName, pt: float, windup: float, i: int, ring_delay: float) -> bool:
	var c := slam_crack(phase, pt, windup, i, ring_delay)
	return c.x >= 1.0 and c.y >= CRACK_GROWN_GLOW and (phase == &"windup" or pt < i * ring_delay)


# 每條裂紋從 Boss 腳下往外，每一圈轉折一次（鋸齒狀）；同一圈的段共用材質
func _build_cracks(e: Enemy) -> void:
	_crack_root = Node3D.new()
	rig.add_child(_crack_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7   # 固定形狀：每台畫出來的裂紋一樣
	var rings: Array = e.def.slam.rings
	for i in rings.size():
		var m := StandardMaterial3D.new()   # 同 Effects 的暫時特效材質設定（著色器開場已預熱）
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(CRACK_COLOR, 0.0)
		_crack_mats.append(m)
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	for j in CRACK_LINES:
		var angle := TAU * j / CRACK_LINES + rng.randf_range(-0.2, 0.2)
		var r0: float = e.radius * 0.6
		var from := Vector3(sin(angle), 0.0, cos(angle)) * r0
		for i in rings.size():
			angle += rng.randf_range(-CRACK_JITTER, CRACK_JITTER)
			var r1: float = rings[i]
			var to := Vector3(sin(angle), 0.0, cos(angle)) * r1
			var node := MeshInstance3D.new()
			node.mesh = plane
			node.material_override = _crack_mats[i]
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.visible = false
			_crack_root.add_child(node)
			var d := to - from
			_cracks.append({"node": node, "ring": i, "start": from, "dir": d.normalized(), "length": d.length(),
				"width": CRACK_WIDTH * (1.0 - 0.25 * i)})
			from = to


func _update_cracks(e: Enemy, a: Dictionary) -> void:
	var in_slam: bool = a.state == &"slam"
	_crack_root.visible = in_slam
	if not in_slam:
		return
	_crack_root.position.y = 0.06 - rig.position.y   # 蹲低時裂紋留在地面
	var slam: Dictionary = e.def.slam
	var phase: StringName = a.get("phase", &"")
	var pt: float = a.get("phase_time", 0.0)
	var windup: float = a.get("windup", slam.windup)
	var states: Array[Vector2] = []
	for i in _crack_mats.size():
		var c := slam_crack(phase, pt, windup, i, slam.ring_delay)
		states.append(c)
		_crack_mats[i].albedo_color.a = c.y
	for c: Dictionary in _cracks:
		var s := states[c.ring]
		var node: MeshInstance3D = c.node
		node.visible = s.y > 0.0
		if not node.visible:
			continue
		var grown: float = c.length * s.x
		var dir: Vector3 = c.dir
		node.position = c.start + dir * (grown / 2.0)
		node.rotation.y = atan2(dir.x, dir.z)
		node.scale = Vector3(c.width, 1.0, maxf(grown, 0.01))
