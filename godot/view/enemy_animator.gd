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

var rig   # Rig（Boss）或 SkinnedRig（小怪，D5）：關節介面相同
var walk_phase := 0.0
var _prev_state: StringName = &""
var _crack_root: Node3D = null              # Boss 砸地的裂紋（掛在 rig 下，蹲低時抵銷高度，留在地面）
var _cracks: Array[Dictionary] = []         # 每一段：{ node, ring, start, dir, length }
var _crack_mats: Array[StandardMaterial3D] = []   # 每一圈共用一個材質（同一圈同時變亮）
var _base_body_scale := Vector3.ZERO        # 稀有度放大後的身體大小（第一次 update 時記下，膨脹以它為準）
var _zombie := false      # 腐屍、膨脹屍：走路時雙手往前伸、駝背
var _bloater := false     # 膨脹屍：脹大時身體放大、閃白，炸開後整隻不見
var _holds_bow := false   # 骷髏弓手：左手拿弓，不瞄準時照 _bow_arm_target
var _bow_arm_target := BOW_ARM_REST
var _dt := 0.0


func _init(p_rig: Node3D, e: Enemy) -> void:
	rig = p_rig
	_holds_bow = e.def.visual == &"ranged"
	_zombie = e.def.visual == &"zombie" or e.def.visual == &"bloater"
	_bloater = e.def.visual == &"bloater"
	walk_phase = randf() * TAU   # 畫面用隨機，與模擬無關
	if e.is_boss():
		_build_cracks(e)


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

	match state:
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
			rig.body.scale = _base_body_scale * (1.0 + swell)
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
		&"swell":
			# 膨脹屍脹大：站定、雙手抱著肚子、身體往後仰抖動（放大與閃白在下面 bloater_swell）
			_pose_walk(0.0, -0.7, -0.7)
			rig.body.rotation.x = -0.15 + sin(t * 30.0) * 0.04
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
			return clampf(t / b.swell_time, 0.0, 1.0)
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
