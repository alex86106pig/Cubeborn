# 畫面層敵人動畫：依模擬層的 enemy.anim（狀態、經過秒數、招式階段）擺姿勢，並畫 Boss 砸地的地板裂紋
# 怪物攻擊不畫預警圈：每招靠自己的預備動作與場景特效讓玩家判斷（設計方向「怪物攻擊不畫紅圈」）
# 人形怪：上身前傾從髖部彎、雙腳踩地（BodyPose.plant），走路照真實步態（腐屍拖著腳、狼人壓低身子跑）；
# 出手照發力順序（舉手時手肘彎著蓄力、砸下去手肘打直、膝蓋跟著蹲）。屍犬四腳 IK、對角小跑；蜘蛛、甲蟲的腳關節往上拱。
# 參考數字見 docs/動作參考.md
class_name EnemyAnimator
extends RefCounted

const HURT_ARM_SHARPNESS := 20.0
const DEATH_FALL_TIME := 0.4
const CORPSE_SINK_START := 0.6   # 屍體停留時間的 60% 後開始沉入地面
const CORPSE_SINK_DEPTH := 0.8
const SLAM_FOLLOW_TIME := 0.12   # 重砸落地後手臂揮下的秒數
const SLAM_CROUCH := 0.25        # 砸地落地時蹲低多少（× 腿長，膝蓋彎下去）
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
const ARCHER_DRAW := 0.42        # 弓手拉滿時拉弦手離弓手多遠（拉到下巴）

const BEETLE_HIDE := -0.6       # 屍甲蟲鑽地時整隻在地面下多深
const SPEAR_ARM_GUARD := -0.9    # 盾槍兵持槍：上臂往前，槍尖朝前下方
const SHIELD_ARM_GUARD := -1.25  # 盾槍兵舉盾：左上臂往前抬、前臂橫在胸前，盾擋在胸前
const ELBOW_REST := 0.3          # 人形怪手臂自然下垂時手肘微彎
const ZOMBIE_SHUFFLE := 0.55     # 腐屍拖著腳走：步伐只有正常的這個比例（抬腳低、步子小）
const QUAD_DUTY := Vector2(0.5, 0.3)   # 四足小跑每隻腳著地的比例（慢 → 快）
const QUAD_LIFT := 0.28          # 四足擺盪時腳抬多高（× 腿長）
var rig   # Rig（Boss）或 SkinnedRig（小怪，D5）：關節介面相同
var walk_phase := 0.0
var _prev_state: StringName = &""
var _crack_root: Node3D = null              # Boss 砸地的裂紋（掛在 rig 下，留在地面）
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
var _lich := false        # 屍巫：唸咒（aim）時雙手往前合攏，其餘同一般小怪
var _spin := 0.0          # 骨輪滾動的角度（畫面自己累加）
var _bow_arm_target := BOW_ARM_REST
var _draw := 0.0          # 弓手拉弦的進度（0 = 沒拉、1 = 拉到下巴；射完平滑放下）
var _dt := 0.0
var _speed := 0.0
var _walk_amount := 0.0
# 這一幀的站姿：_free = 腿照姿勢給的角度（倒地、空中）；否則雙腳踩地，_stance_w > 0 時往指定腳位靠
var _free := false
var _gait: Dictionary = {}
var _stance_w := 0.0
var _stance := Vector3.ZERO   # (drop, 右腳往前, 左腳往前)，× 腿長
var _lift_r := Vector2.ZERO   # 右腳額外的 (往前, 抬高)，× 腿長（衝鋒前刨地）
var _stepped := false         # 這一幀的步態相位推過了（同一幀呼叫好幾次 _walk 只推一次）


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
	_lich = e.def.visual == &"lich"
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
		rig.head.rotation = Vector3.ZERO
		rig.position.y = 0.0
		_prev_state = state
	_speed = e.velocity.length()
	var moving := _speed > 0.1
	_walk_amount = MathUtil.damp(_walk_amount, 1.0 if moving else 0.0, 12.0, dt)
	BodyPose.straighten(rig)
	rig.body.rotation = Vector3.ZERO
	rig.body.position = Vector3.ZERO
	_free = false
	_stance_w = 0.0
	_lift_r = Vector2.ZERO
	_stepped = false
	_gait = {}
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
	match &"cast" if _lich and state == &"aim" else &"worm" if _worm and a.get("form", 0) == 0 else &"moth" if _worm else &"hive" if _hive else &"hound" if _hound else (&"wheel" if _wheel else (&"beetle" if _beetle else (&"spider" if _spider else (&"colossus" if colossus else (&"keeper" if _keeper and state != &"spawn" and state != &"dead" else state))))):
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
		&"shriek":   # 尖嘯幽影：先縮身（吸氣），尖嘯時雙手張開、身體往前探
			var w: float = def.shriek.windup
			if t < w:
				var k := clampf(t / w, 0.0, 1.0)
				_pose_arms(lerpf(-0.2, -0.9, k), lerpf(0.0, -0.3, k))
				rig.body.rotation.x = -0.25 * k
			else:
				_pose_arms(-1.3, 1.1)
				rig.body.rotation.x = 0.3
		&"cast":   # 屍巫唸咒：雙手往前抬、往中間合攏，身體微微後仰
			var k := MathUtil.ease_out_cubic(clampf(t / def.aim_time, 0.0, 1.0))
			_pose_arms(lerpf(-0.3, -1.5, k), lerpf(0.0, 0.45, k))
			rig.body.rotation.x = -0.1 * k
			rig.leg_r.rotation.x = 0.0
			rig.leg_l.rotation.x = 0.0
		&"moth":
			_pose_moth(e, a, state, t, dt)
		&"hound":
			_pose_hound(e, a, state, t, dt)
		&"wheel":
			_pose_wheel(e, state, t, dt)
		&"keeper":
			_pose_keeper(e, a, state, t, dt)
		&"spawn":
			# 從地下爬出：雙手輪流往上扒、上身前傾，整隻慢慢升上來
			var k := MathUtil.ease_out_cubic(clampf(t / def.spawn_time, 0.0, 1.0))
			rig.position.y = lerpf(-rig.height, 0.0, k)
			var claw := sin(t * 9.0)
			BodyPose.arm(rig, true, -2.0 + 0.5 * claw, -0.2, 0.9 - 0.5 * claw)
			BodyPose.arm(rig, false, -2.0 - 0.5 * claw, 0.2, 0.9 + 0.5 * claw)
			rig.body.rotation.x = 0.35 * (1.0 - k)
			_set_stance(0.15 * (1.0 - k), 0.2, -0.15)
		&"dormant":
			_walk(0.0, -0.3, -0.2)   # 怪群休眠：站著、手垂著
			rig.body.rotation.x = 0.08
		&"hurt":
			# 受擊：上身往後仰、退半步、手往前甩
			var k := sin(clampf(t / def.hurt_time, 0.0, 1.0) * PI)
			_walk(0.0, -0.6, -0.6)
			rig.body.rotation.x = -0.35 * k
			rig.head.rotation.x = -0.2 * k
			BodyPose.arm(rig, true, -0.6 - 0.3 * k, -0.2 * k, 0.4 + 0.6 * k)
			BodyPose.arm(rig, false, -0.6 - 0.3 * k, 0.2 * k, 0.4 + 0.6 * k)
			_set_stance(0.08 * k, 0.05, -0.3, k)
		&"dead":
			# 倒下：膝蓋先軟掉往下沉、再往後倒成仰躺，手往兩側攤開
			_free = true
			var fall := clampf(t / DEATH_FALL_TIME, 0.0, 1.0)
			var f := MathUtil.ease_out_cubic(fall)
			rig.body.rotation.x = lerpf(0.0, -PI / 2.0, f)
			rig.body.position.y = (0.36 if e.is_boss() else 0.2) * rig.body.scale.y * fall   # 仰躺：背的厚度（Boss 有盔甲、披風、外套），不穿進地板
			BodyPose.leg(rig, true, -0.5 * sin(PI * fall) + 0.1 * f, 1.0 * sin(PI * fall) + 0.25 * f)
			BodyPose.leg(rig, false, -0.3 * sin(PI * fall), 0.8 * sin(PI * fall) + 0.1 * f)
			rig.arm_r.rotation = Vector3(-0.3 * f, 0.0, -1.3 * f)   # 雙手往兩側攤在地上
			rig.arm_l.rotation = Vector3(-0.2 * f, 0.0, 1.2 * f)
			rig.forearm_r.rotation.x = -0.5 * f
			rig.forearm_l.rotation.x = -0.4 * f
			var corpse: float = def.corpse_time
			var sink_start := corpse * CORPSE_SINK_START
			rig.position.y = -CORPSE_SINK_DEPTH * clampf((t - sink_start) / (corpse - sink_start), 0.0, 1.0)
			# 死亡爆炸詞條：爆開前屍體一下一下脹大、閃白（不畫預警圈）
			var swell := volatile_swell(e, t)
			rig.body.scale = _sized_scale(a) * (1.0 + swell)
		&"launch":
			# 從挖墳點噴出來：雙手往上亂甩、腿縮起來
			_free = true
			BodyPose.arm(rig, true, -2.4 + 0.3 * sin(t * 18.0), -0.3, 0.6)
			BodyPose.arm(rig, false, -2.4 - 0.3 * sin(t * 18.0), 0.3, 0.6)
			BodyPose.leg(rig, true, -0.6, 1.3)
			BodyPose.leg(rig, false, 0.2, 1.1)
		&"chase", &"patrol":
			if e.is_boss():
				_walk(1.0, -0.5, -0.3, 0.6)
			elif _spearman:
				_walk(0.7, SPEAR_ARM_GUARD, SHIELD_ARM_GUARD, 0.6)
				_spear_guard()
			elif _zombie:
				_walk(ZOMBIE_SHUFFLE, -1.35, -1.45, 0.15)
				rig.body.rotation.x = 0.2
				rig.head.rotation.x = 0.15
			else:
				_walk(1.0, -0.6, -0.3, 0.5)
		&"swing":
			_walk(0.0, -0.6, -0.3)
			_pose_melee_swing(t, def.swing)
		&"thrust":
			_walk(0.0, SPEAR_ARM_GUARD, SHIELD_ARM_GUARD)
			_spear_guard()
			_pose_thrust(t, def.thrust)
		&"guard_broken":
			# 破防：盾甩到外側（手肘打開）、上身往後仰、退一步，break_time 內慢慢收回
			var k := clampf(t / def.shield.break_time, 0.0, 1.0)
			var out := 1.0 - MathUtil.ease_out_cubic(k)
			_walk(0.0, -0.4, -0.3)
			BodyPose.arm(rig, false, lerpf(SHIELD_ARM_GUARD, -0.4, out), -1.1 * out, lerpf(1.3, 0.3, out))
			rig.body.rotation.x = -0.28 * out
			rig.head.rotation.x = -0.3 * out
			_set_stance(0.06 * out, 0.1, -0.35, out)
		&"kite":
			_walk(1.0, -0.2, -0.5, 0.4)
		&"aim":
			# 拉弓：弓手平舉（手肘微彎），拉弦手勾著弦拉到下巴、手肘抬到箭的直線後面；側身站開
			var draw := MathUtil.ease_out_cubic(minf(1.0, t / def.aim_time * 1.5))
			var held: float = rig.arm_l.rotation.x
			_walk(0.0, -0.2, -0.5)
			# 已經舉在預備高度（目標一直在射擊距離內）就從那裡往上舉，不先放下
			rig.arm_l.rotation.x = minf(held, lerpf(BOW_ARM_REST, BOW_ARM_AIM, draw))
			_draw = draw
			rig.body.rotation.y = -0.5 * draw
			_set_stance(0.04, 0.2, -0.2)
		&"slam":
			_pose_slam(a)
		&"charge":
			_pose_charge(a, dt, def.charge)
		&"cleave":
			# 直劈（沒有地面預警）：比骷髏揮砍更誇張地把劍舉過頭、身體後仰，看動作就知道要劈下來
			_walk(0.0, -0.5, -0.3)
			var c: Dictionary = def.cleave
			_pose_melee_swing(t, {"windup": a.get("windup", c.windup), "active": c.active, "recovery": c.recovery})
			if t < a.get("windup", c.windup):
				rig.body.rotation.x = lerpf(0.0, -0.32, MathUtil.ease_out_cubic(t / a.get("windup", c.windup)))
		&"rush":
			_pose_rush(a, dt, def.rush)
		&"lunge":
			_pose_lunge(a, def.lunge)
		&"fetch":
			# 撿武器：走過去照常走路；蹲下（彎膝蓋）、上身前彎、右手伸到地上撿
			if a.get("phase", &"walk") == &"bend":
				var k := MathUtil.ease_out_cubic(clampf(a.get("phase_time", 0.0) / def.pickup.bend, 0.0, 1.0))
				_walk(0.0, -0.6, -0.4)
				rig.body.rotation.x = lerpf(0.1, 0.65, k)
				rig.head.rotation.x = 0.3 * k
				_set_stance(0.25 * k, 0.25, -0.15)
				_finish()
				var ground := _root_to_body(Vector3(-0.15, 0.08, 0.55))
				BodyPose.arm_ik(rig, true, BodyPose.hand_pos(rig, true).lerp(ground, k), BodyPose.elbow_pole(true))
				_free = true   # 腳已經踩好了
			else:
				_walk(1.0, -1.35, -1.45, 0.15)
		&"armed_move":
			_pose_armed(a, dt)
		&"swell":
			# 膨脹屍脹大：站定、雙手抱著肚子、身體往後仰抖動（放大與閃白在下面 bloater_swell）；抱住玩家時雙手往前環抱
			if a.get("hugging", false):
				_walk(0.0, -1.3, -1.3)
				BodyPose.arm(rig, true, -1.3, -0.45, 0.9)
				BodyPose.arm(rig, false, -1.3, 0.45, 0.9)
				rig.body.rotation.x = 0.1 + sin(t * 30.0) * 0.04
			else:
				_walk(0.0, -0.7, -0.7)
				rig.body.rotation.x = -0.15 + sin(t * 30.0) * 0.04
				BodyPose.arm_ik(rig, true, Vector3(-0.18, 1.0, 0.5), BodyPose.elbow_pole(true))   # 肚子的表面（DarkFantasy.bloater 的肉球前緣 z ≈ 0.5）
				BodyPose.arm_ik(rig, false, Vector3(0.18, 1.12, 0.5), BodyPose.elbow_pole(false))
			_set_stance(0.06, 0.15, -0.15)
		&"hug":
			# 膨脹屍撲抱：挺肚子（後仰）、雙手往兩側張開 → 撲出去雙手往前合抱（手肘彎、往內收）
			var h: Dictionary = def.hug
			var pt: float = a.get("phase_time", 0.0)
			if a.get("phase", &"windup") == &"windup":
				var k := MathUtil.ease_out_cubic(clampf(pt / h.windup, 0.0, 1.0))
				_walk(0.0, -0.6, -0.6)
				BodyPose.arm(rig, true, lerpf(-0.6, -1.4, k), lerpf(-0.2, -1.0, k), 0.3)
				BodyPose.arm(rig, false, lerpf(-0.6, -1.4, k), lerpf(0.2, 1.0, k), 0.3)
				rig.body.rotation.x = lerpf(0.0, -0.3, k)
				_set_stance(0.1 * k, 0.15, -0.25)
			else:
				_walk(1.0, -1.5, -1.5)
				BodyPose.arm(rig, true, -1.5, -0.35, 0.85)
				BodyPose.arm(rig, false, -1.5, 0.35, 0.85)
				rig.body.rotation.x = 0.25
		&"fallen":
			# 撲抱被擋下：往後一屁股坐在地上（膝蓋屈起、雙手往後撐），最後撐起來
			_free = true
			var up_at: float = def.hug.blocked_fall - 0.15
			var k := MathUtil.ease_out_cubic(clampf(t / 0.2, 0.0, 1.0)) if t < up_at else 1.0 - clampf((t - up_at) / 0.15, 0.0, 1.0)
			var hip: float = rig.leg_r.position.y * rig.body.scale.y
			rig.body.position = Vector3(0.0, -hip * 0.85 * k, -0.25 * k)
			rig.body.rotation.x = -0.35 * k
			BodyPose.leg(rig, true, -1.3 * k, 0.6 * k)
			BodyPose.leg(rig, false, -1.15 * k, 0.9 * k)
			BodyPose.arm(rig, true, 0.7 * k, -0.2 * k, 0.15)
			BodyPose.arm(rig, false, 0.7 * k, 0.2 * k, 0.15)
		&"bite":
			# 啃咬：雙手抓著往自己拉（手肘彎）、上身前壓、頭一下一下咬下去
			_walk(0.0, -1.2, -1.25)
			BodyPose.arm(rig, true, -1.2 + sin(t * 20.0) * 0.08, -0.3, 1.0)
			BodyPose.arm(rig, false, -1.25 - sin(t * 20.0) * 0.08, 0.3, 1.0)
			rig.body.rotation.x = 0.35
			rig.head.rotation.x = 0.25 + 0.25 * maxf(0.0, sin(t * TAU / def.lunge.bite_interval))
			_set_stance(0.1, 0.3, -0.2)
		&"stagger":
			# 撲抱被擋下：往後踉蹌（退一步）、雙手亂揮
			var k := clampf(t / def.lunge.blocked_stagger, 0.0, 1.0)
			_walk(0.0, -0.8, -0.8)
			rig.body.rotation.x = -0.35 * sin(k * PI)
			BodyPose.arm(rig, true, -0.8 + sin(t * 18.0) * 0.4, -0.3, 0.7)
			BodyPose.arm(rig, false, -0.8 - sin(t * 18.0) * 0.4, 0.3, 0.7)
			_set_stance(0.1 * sin(k * PI), 0.1, -0.4 * sin(k * PI))
		&"transform":
			if def.has("colossus"):
				# 骸骨將軍脫甲：單膝跪下（右膝著地）、低頭、雙手垂到地上，盔甲碎片往外飛（特效）
				var k := MathUtil.ease_out_cubic(clampf(t / 0.4, 0.0, 1.0))
				_walk(0.0, -0.3, -0.3)
				rig.body.rotation.x = 0.45 * k + sin(t * 25.0) * 0.03
				rig.head.rotation.x = 0.4 * k
				BodyPose.arm(rig, true, lerpf(-0.3, -0.9, k), -0.2, 0.3)
				BodyPose.arm(rig, false, lerpf(-0.3, -0.9, k), 0.2, 0.3)
				_set_stance(0.45 * k, -0.55, 0.4)
		&"summon":
			# 召喚：雙臂往兩側上方張開（手肘微彎）、身體後仰、抬頭看天（和砸地的雙手高舉分開）
			var k := MathUtil.ease_out_cubic(clampf(t / def.summon.windup, 0.0, 1.0))
			_walk(0.0, -0.4, -0.4)
			BodyPose.arm(rig, true, lerpf(-0.4, -1.5, k), lerpf(-0.3, -1.3, k), 0.35)
			BodyPose.arm(rig, false, lerpf(-0.4, -1.5, k), lerpf(0.3, 1.3, k), 0.35)
			rig.body.rotation.x = lerpf(0.0, -0.35, k)
			rig.head.rotation.x = lerpf(0.0, -0.45, k)
			_set_stance(0.05 * k, 0.15, -0.15)
		_:
			_walk(0.0, -0.5, -0.4)

	if _holds_bow and _draw > 0.02:
		_archer_draw_hand()
	if not _free and not (_hound or _spider or _beetle or _wheel):
		_finish()
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


# ───────── 人形怪共用 ─────────

# 走路 / 站著：腳照步態（amount 0 = 站、1 = 照移動速度走；< 1 = 步子小，像拖著腳），手臂照步態擺、手肘微彎
func _walk(amount: float, arm_r: float, arm_l: float, elbow := ELBOW_REST) -> void:
	var leg := BodyPose.leg_length(rig)
	var amt := _walk_amount * amount
	if _speed > 0.1 and amount > 0.0 and not _stepped:   # 步子小（amount < 1）就踩得快，腳才不會在地上滑
		walk_phase = fmod(walk_phase + TAU * _speed * _dt / (BodyPose.stride(_speed, leg) * maxf(amount, 0.3)), TAU)
		_stepped = true
	_gait = BodyPose.gait(rig, walk_phase, amt, maxf(_speed, 0.5))
	var sw := cos(TAU * _gait.u) * lerpf(BodyPose.ARM_SWING_WALK, BodyPose.ARM_SWING_RUN, _gait.run) * amt
	if _holds_bow:   # 拿弓的手走路時不擺；兩手的舉起、放下（含射完從拉弦姿勢放下右手）都平滑轉過去
		var s := BOW_ARM_SHARPNESS
		rig.arm_l.rotation.x = MathUtil.damp(rig.arm_l.rotation.x, _bow_arm_target, s, _dt)
		rig.arm_l.rotation.y = 0.0
		rig.arm_l.rotation.z = 0.0
		rig.forearm_l.rotation.x = -0.12
		_draw = MathUtil.damp(_draw, 0.0, s, _dt)   # 射完拉弦手平滑放下（收尾時從拉弦姿勢往這個待機姿勢靠，見 _archer_draw_hand）
		BodyPose.arm(rig, true, arm_r + sw * 0.4, 0.0, elbow)
	else:
		BodyPose.arm(rig, true, arm_r + sw * 0.5, 0.0, elbow + maxf(0.0, -sw) * 0.4)
		BodyPose.arm(rig, false, arm_l - sw * 0.6, 0.0, elbow + maxf(0.0, sw) * 0.4)


# 弓手的拉弦手：拉滿 = 弓手往後 ARCHER_DRAW（箭的直線上、下巴旁），手肘往後外上方抬；
# 從目前的待機姿勢照 _draw（0~1）移過去，射完 _draw 慢慢降回 0，手就平滑放下
func _archer_draw_hand() -> void:
	var rest := BodyPose.hand_pos(rig, true)
	var drawn := BodyPose.hand_pos(rig, false) + Vector3(-0.1, 0.06, -ARCHER_DRAW)
	BodyPose.arm_ik(rig, true, rest.lerp(drawn, smoothstep(0.0, 1.0, _draw)), BodyPose.elbow_pole(true).lerp(Vector3(-0.8, 0.3, -1.0), _draw))


# 站姿：drop = 髖部往下（× 腿長）、r / l = 右 / 左腳往前（× 腿長）
func _set_stance(drop: float, r: float, l: float, weight := 1.0) -> void:
	_stance_w = clampf(weight, 0.0, 1.0)
	_stance = Vector3(drop, r, l)


# 收尾：雙腳踩地（步態的腳位，往 _set_stance 的站姿靠），上身照 body.rotation 從髖部彎
func _finish() -> void:
	var leg := BodyPose.leg_length(rig)
	var s: float = rig.body.scale.x
	if _gait.is_empty():
		_gait = BodyPose.gait(rig, walk_phase, 0.0, 1.0)
	var fr: Vector3 = _gait.r
	var fl: Vector3 = _gait.l
	var drop: float = _gait.drop
	rig.body.rotation.x += _gait.lean
	var w := _stance_w * (1.0 - 0.6 * _walk_amount)
	if w > 0.0:
		fr = fr.lerp(Vector3(rig.leg_r.position.x * s, 0.0, _stance.y * leg), w)
		fl = fl.lerp(Vector3(rig.leg_l.position.x * s, 0.0, _stance.z * leg), w)
		drop = lerpf(drop, _stance.x * leg, w)
	fr += Vector3(0.0, _lift_r.y, _lift_r.x) * leg
	BodyPose.plant(rig, fr, fl, drop)


# 角色座標 → 身體座標
func _root_to_body(p: Vector3) -> Vector3:
	var body = rig.body
	return Transform3D(Basis.from_euler(body.rotation, EULER_ORDER_YXZ).scaled_local(body.scale), body.position).affine_inverse() * p


# 盾槍兵持槍、舉盾：槍手前臂往前、盾手前臂橫在胸前
func _spear_guard() -> void:
	BodyPose.arm(rig, true, SPEAR_ARM_GUARD, 0.0, 0.6)
	BodyPose.arm(rig, false, SHIELD_ARM_GUARD, 0.35, 1.3)


# 骷髏戰士揮砍：舉刀過頭（上臂高舉、手肘彎、刀在頭後，上身後仰，看得出要出手）→ 揮下（手肘打直、上身前壓、左腳踏出、膝蓋沉）→ 收招
func _pose_melee_swing(t: float, s: Dictionary) -> void:
	var windup: float = s.windup
	var active: float = s.active
	if t < windup:
		var k := MathUtil.ease_out_cubic(t / windup)
		BodyPose.arm(rig, true, lerpf(-0.6, -2.9, k), -0.1 * k, lerpf(ELBOW_REST, 1.4, k))
		rig.body.rotation.x = lerpf(0.0, -0.18, k)
		_set_stance(0.0, -0.05, 0.25, k)
	elif t < windup + active:
		var k := (t - windup) / active
		# 砍到底停在腰前（手臂相對身體 -0.8、上身前傾 0.25 → 實際往前約 0.55），刀尖不插進地裡
		BodyPose.arm(rig, true, lerpf(-2.9, -0.8, k), -0.1, lerpf(1.4, 0.05, minf(1.0, k * 1.5)))
		rig.body.rotation.x = lerpf(-0.18, 0.25, k)
		_set_stance(0.14 * k, -0.15, 0.4)
	else:
		var k := clampf((t - windup - active) / s.recovery, 0.0, 1.0)
		BodyPose.arm(rig, true, lerpf(-0.8, -0.6, k), 0.0, lerpf(0.05, ELBOW_REST, k))
		rig.body.rotation.x = lerpf(0.25, 0.0, k)
		_set_stance(0.14 * (1.0 - k), -0.15, 0.4, 1.0 - k)
	BodyPose.arm(rig, false, -0.5, 0.2, 0.9)


# 盾槍兵直刺：盾往外偏、槍收到腰側（手肘往後收）→ 弓步往前刺到手臂打直（右腳踏出、上身前傾）→ 收回舉盾
func _pose_thrust(t: float, s: Dictionary) -> void:
	var windup: float = s.windup
	var active: float = s.active
	if t < windup:
		var k := MathUtil.ease_out_cubic(t / windup)
		BodyPose.arm(rig, true, lerpf(SPEAR_ARM_GUARD, 0.3, k), 0.05, lerpf(0.6, 1.7, k))
		BodyPose.arm(rig, false, SHIELD_ARM_GUARD, lerpf(0.35, -0.7, k), 1.3)
		rig.body.rotation.x = lerpf(0.0, -0.12, k)
	elif t < windup + active:
		var k := (t - windup) / active
		BodyPose.arm(rig, true, lerpf(0.3, -1.6, k), 0.05, lerpf(1.7, 0.05, k))
		BodyPose.arm(rig, false, SHIELD_ARM_GUARD, -0.7, 1.3)
		rig.body.rotation.x = lerpf(-0.12, 0.22, k)
		_set_stance(0.16 * k, 0.5 * k, -0.4 * k)
	else:
		var k := clampf((t - windup - active) / s.recovery, 0.0, 1.0)
		BodyPose.arm(rig, true, lerpf(-1.6, SPEAR_ARM_GUARD, k), 0.0, lerpf(0.05, 0.6, k))
		BodyPose.arm(rig, false, SHIELD_ARM_GUARD, lerpf(-0.7, 0.35, k), 1.3)
		rig.body.rotation.x = lerpf(0.22, 0.0, k)
		_set_stance(0.16, 0.5, -0.4, 1.0 - k)


# 砸地：warn（狂暴瞬移前，低頭蓄力）→ windup（雙手合握、筆直高舉，手肘微彎）→ impact（膝蓋深蹲、把劍插進地裡）
func _pose_slam(a: Dictionary) -> void:
	var pt: float = a.get("phase_time", 0.0)
	_walk(0.0, -0.4, -0.4)
	match a.get("phase", &"windup"):
		&"warn":
			BodyPose.arm(rig, true, -0.4 + sin(pt * 20.0) * 0.1, -0.3, 0.6)
			BodyPose.arm(rig, false, -0.4 + sin(pt * 20.0) * 0.1, 0.3, 0.6)
			rig.body.rotation.x = 0.2
			_set_stance(0.1, 0.15, -0.15)
		&"windup":
			var k := MathUtil.ease_out_cubic(clampf(pt / maxf(a.get("windup", 0.7), 0.01), 0.0, 1.0))
			BodyPose.arm(rig, true, lerpf(-0.4, -3.1, k), lerpf(-0.3, 0.0, k), lerpf(0.6, 0.35, k))
			BodyPose.arm(rig, false, lerpf(-0.4, -3.1, k), lerpf(0.3, 0.0, k), lerpf(0.6, 0.35, k))
			rig.body.rotation.x = lerpf(0.0, -0.15, k)
			_set_stance(0.0, 0.2, -0.2)
		_:
			var k := clampf(pt / SLAM_FOLLOW_TIME, 0.0, 1.0)
			BodyPose.arm(rig, true, lerpf(-3.1, -0.6, k), 0.0, lerpf(0.35, 0.05, k))
			BodyPose.arm(rig, false, lerpf(-3.1, -0.6, k), 0.0, lerpf(0.35, 0.05, k))
			rig.body.rotation.x = lerpf(-0.15, 0.55, k)
			_set_stance(SLAM_CROUCH * k * 1.6, 0.35, -0.35)


# 骷髏戰士衝撞：蓄力前傾（雙手往後、膝蓋一沉）→ 低頭衝刺（跑步）→ 收招
func _pose_rush(a: Dictionary, _dt: float, r: Dictionary) -> void:
	var pt: float = a.get("phase_time", 0.0)
	match a.get("phase", &"windup"):
		&"windup":
			var k := MathUtil.ease_out_cubic(clampf(pt / r.windup, 0.0, 1.0))
			_walk(0.0, -0.6, -0.6)
			BodyPose.arm(rig, true, lerpf(-0.6, -0.65, k), -0.15, lerpf(0.5, 0.9, k))   # 拿刀的手低握、刀尖朝前（前傾時手臂相對身體要多往前）
			BodyPose.arm(rig, false, lerpf(-0.6, 0.5, k), 0.15, 0.5)
			rig.body.rotation.x = lerpf(0.0, 0.4, k)
			_set_stance(0.15 * k, 0.2, -0.3)
		&"dash":
			_walk(1.0, 0.5, 0.5, 0.8)
			BodyPose.arm(rig, true, -0.65, -0.15, 0.9)
			rig.body.rotation.x = 0.4
		_:
			_walk(0.0, -0.6, -0.6)
			rig.body.rotation.x = lerpf(0.4, 0.0, clampf(pt / r.recovery, 0.0, 1.0))


func _pose_charge(a: Dictionary, _dt: float, c: Dictionary) -> void:
	var pt: float = a.get("phase_time", 0.0)
	match a.get("phase", &"windup"):
		&"windup":
			# 衝鋒：壓低身體、肩膀往前頂，右腳往後刨地兩下（effects 在刨地時揚起塵土）
			var kl := clampf(pt / maxf(a.get("windup", c.windup), 0.01), 0.0, 1.0)
			var k := MathUtil.ease_out_cubic(kl)
			_walk(0.0, -0.4, -0.4)
			BodyPose.arm(rig, true, lerpf(-0.4, -0.6, k), -0.2, lerpf(0.6, 0.9, k))   # 劍低握、劍尖朝前（前傾 0.45 時手臂相對身體 -0.6 → 實際往前約 0.15，前臂往前）
			BodyPose.arm(rig, false, lerpf(-0.4, 0.6, k), 0.2, 0.7)
			rig.body.rotation.x = lerpf(0.0, 0.45, k)
			_set_stance(0.15 * k, -0.25, 0.3)
			var scrape := charge_scrape(kl)
			_lift_r = Vector2(-sin(scrape) * 0.6, (1.0 - cos(scrape)) * 0.5)
		&"dash":
			_walk(1.0, 0.6, 0.6, 0.9)
			BodyPose.arm(rig, true, -0.6, -0.2, 0.9)
			rig.body.rotation.x = 0.35
		&"stunned":
			_walk(0.0, -0.3, -0.3, 0.15)
			rig.body.rotation.x = -0.25 + sin(pt * 18.0) * 0.05
			rig.head.rotation.y = sin(pt * 6.0) * 0.4
			_set_stance(0.1, 0.1, -0.15)
		_:
			_walk(0.0, -0.3, -0.3)
			rig.body.rotation.x = lerpf(0.35, 0.0, clampf(pt / c.recovery, 0.0, 1.0))


# 衝鋒預備時後腳的角度：往後刨地兩下（kl = 預備進度 0~1）
static func charge_scrape(kl: float) -> float:
	return 0.25 + 0.55 * maxf(0.0, sin(kl * 2.0 * TAU))


# 腐屍撲抱：windup 雙手舉高、身體後仰、膝蓋蓄力（看得出要撲）→ dash 雙手往前抓（手肘打直）、身體前撲 → recovery 慢慢收回
func _pose_lunge(a: Dictionary, l: Dictionary) -> void:
	var pt: float = a.get("phase_time", 0.0)
	match a.get("phase", &"windup"):
		&"windup":
			var k := MathUtil.ease_out_cubic(clampf(pt / l.windup, 0.0, 1.0))
			_walk(0.0, lerpf(-1.35, -2.7, k), lerpf(-1.45, -2.7, k), lerpf(0.15, 0.5, k))
			rig.body.rotation.x = lerpf(0.18, -0.3, k)
			rig.head.rotation.x = lerpf(0.0, -0.3, k)
			_set_stance(0.16 * k, 0.25, -0.25)
		&"dash":
			var k := clampf(pt / l.duration, 0.0, 1.0)
			_walk(1.0, lerpf(-2.7, -1.5, k), lerpf(-2.7, -1.5, k), 0.05)
			rig.body.rotation.x = lerpf(-0.3, 0.5, k)
		_:
			var k := clampf(pt / l.recovery, 0.0, 1.0)
			_walk(0.0, lerpf(-1.5, -1.35, k), lerpf(-1.5, -1.45, k), 0.15)
			rig.body.rotation.x = lerpf(0.5, 0.18, k)
			_set_stance(0.12 * (1.0 - k), 0.35, -0.2)


# 持武器的腐屍出招（各招式的預兆不重複）：
# 揮擊 = 右手舉過頭後拉（手肘彎）；射擊 = 雙手往前拉弓 / 法杖平舉；舉盾 = 左前臂橫在胸前；爆裂 = 法杖舉到最高；
# 影步 = 蹲低；治療 = 雙臂張開仰頭；噴火 = 火把往前推、身體後仰；鏟起 = 蹲低、鏟面貼地
func _pose_armed(a: Dictionary, _dt: float) -> void:
	var pt: float = a.get("phase_time", 0.0)
	var winding: bool = a.get("phase", &"windup") == &"windup"
	var k := MathUtil.ease_out_cubic(clampf(pt / 0.4, 0.0, 1.0))
	var active: bool = a.get("phase", &"") == &"active"
	match a.get("move_type", &"melee"):
		&"melee":
			if winding:
				_walk(0.0, lerpf(-1.2, -2.8, k), -0.6, lerpf(0.3, 1.4, k))
				rig.body.rotation.x = lerpf(0.0, -0.2, k)
			else:
				_walk(0.0, -0.7, -0.6, 0.1)
				rig.body.rotation.x = 0.25 if active else 0.1
				_set_stance(0.12, -0.15, 0.35)
		&"shot":
			_walk(0.0, -1.55, -1.5, 0.2)
			BodyPose.arm(rig, true, -1.5, 0.3, 1.2 * k)
			rig.body.rotation.x = -0.1 * k if winding else 0.0
		&"shield":
			_walk(0.0, -0.8, -0.6, 0.6)
			BodyPose.arm(rig, false, lerpf(-0.6, -1.4, k), 0.5 * k, lerpf(0.3, 1.3, k))
			rig.body.rotation.x = 0.15 * k
			_set_stance(0.1 * k, -0.15, 0.3)
		&"burst":
			_walk(0.0, lerpf(-1.2, -3.1, k) if winding else -1.0, -0.4, 0.3)
			rig.head.rotation.x = -0.3 * k if winding else 0.0
		&"blink":
			_walk(0.0, -0.4, -0.4, 0.8)
			rig.body.rotation.x = 0.5 * k
			_set_stance(0.3 * k, 0.2, -0.2)
		&"heal":
			_walk(0.0, -1.3, -1.3)
			BodyPose.arm(rig, true, -1.3, lerpf(-0.3, -1.2, k), 0.35)
			BodyPose.arm(rig, false, -1.3, lerpf(0.3, 1.2, k), 0.35)
			rig.head.rotation.x = -0.35 * k
		&"breath":
			_walk(0.0, -1.7, -0.5, 0.2)
			rig.body.rotation.x = -0.25 * k if winding else -0.1
			_set_stance(0.05, -0.2, 0.3)
		&"scoop":
			_walk(0.0, lerpf(-0.6, -0.2, k), lerpf(-0.6, -0.3, k), 0.3)
			rig.body.rotation.x = lerpf(0.0, 0.5, k) if winding else -0.2
			_set_stance(lerpf(0.0, 0.25, k) if winding else 0.05, -0.2, 0.35)


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


# ───────── 多足（屍犬、蜘蛛、甲蟲）：四隻會動的腳用 IK 踩在 feet（角色座標的腳底）─────────

# feet = [前右, 前左, 後右, 後左]；drop = 身體往下；knee_up = 蜘蛛、甲蟲的腳關節往上拱（不然前腳關節往前凸、後腳往後凸，像狗）
func _plant_limbs(feet: Array, drop: float, knee_up := false, lengths := Vector2.ZERO) -> void:
	var body = rig.body
	body.position = Vector3(0.0, -drop, 0.0)
	var to_body := Transform3D(Basis.from_euler(body.rotation, EULER_ORDER_YXZ).scaled_local(body.scale), body.position).affine_inverse()
	var limbs := [[rig.arm_r, rig.forearm_r, true], [rig.arm_l, rig.forearm_l, true], [rig.leg_r, rig.shin_r, false], [rig.leg_l, rig.shin_l, false]]
	for i in 4:
		var root = limbs[i][0]
		var mid = limbs[i][1]
		var target: Vector3 = to_body * (feet[i] as Vector3)
		if knee_up:
			var out := Vector3(signf(root.position.x), 0.0, 0.0)
			BodyPose.two_bone(root, mid, target, lengths.x, lengths.y, Vector3.UP * 1.5 + out, 1.0)
		else:
			BodyPose.leg_ik(rig, root, mid, target, limbs[i][2])   # 前腳的腕關節往前凸（腳掌往後收）、後腳的跗關節往後凸


# 四足的步態腳位：offsets = 四隻腳在循環裡的相位差 [前右, 前左, 後右, 後左]；rest = 站著時的腳底位置
func _quad_feet(rest: Array, offsets: Array, amount: float, run: float, leg: float) -> Array:
	var duty := lerpf(QUAD_DUTY.x, QUAD_DUTY.y, run)
	var reach := BodyPose.stride(maxf(_speed, 0.5), leg) * duty * 0.9 * amount
	var out := []
	for i in 4:
		var f := BodyPose.foot_path(walk_phase / TAU + offsets[i], duty, reach, leg * QUAD_LIFT * amount, run)
		out.append((rest[i] as Vector3) + Vector3(0.0, f.y, f.x))
	return out


# 屍犬（四足）：慢的時候小跑（對角的兩腳一起）、快的時候奔跑（前後腳各自一前一後落地、身體前後起伏）；
# 飛撲 windup 伏低收腳（看得出要撲）→ dash 前腳往前伸、後腳往後蹬直 → recovery 收回；死掉往側邊倒
func _pose_hound(e: Enemy, a: Dictionary, state: StringName, t: float, dt: float) -> void:
	var def := e.def
	var s: float = rig.body.scale.x
	var leg: float = rig.leg_r.position.y * s
	var rest := [
		Vector3(rig.arm_r.position.x * s, 0.0, rig.arm_r.position.z * s), Vector3(rig.arm_l.position.x * s, 0.0, rig.arm_l.position.z * s),
		Vector3(rig.leg_r.position.x * s, 0.0, rig.leg_r.position.z * s), Vector3(rig.leg_l.position.x * s, 0.0, rig.leg_l.position.z * s),
	]
	var feet := rest.duplicate()
	var drop := 0.0
	rig.body.rotation = Vector3.ZERO
	match state:
		&"spawn":
			rig.position.y = lerpf(-rig.height, 0.0, MathUtil.ease_out_cubic(clampf(t / def.spawn_time, 0.0, 1.0)))
		&"chase", &"dormant":
			walk_phase = BodyPose.advance(walk_phase, _speed, leg, dt)
			var run := BodyPose.run_amount(_speed, leg)
			var trot := [0.0, 0.5, 0.5, 0.0]
			var gallop := [0.4, 0.5, 0.1, 0.0]
			var offsets := []
			for i in 4:
				offsets.append(lerpf(trot[i], gallop[i], run))
			feet = _quad_feet(rest, offsets, _walk_amount, run, leg)
			rig.body.rotation.x = 0.08 * sin(walk_phase) * run * _walk_amount   # 奔跑時身體前後起伏
			drop = 0.04 * leg * _walk_amount
			rig.head.rotation.x = -0.1 * run * _walk_amount
		&"pounce":
			var c: Dictionary = def.pounce
			var pt: float = a.get("phase_time", 0.0)
			match a.get("phase", &"windup"):
				&"windup":
					var k := MathUtil.ease_out_cubic(clampf(pt / c.windup, 0.0, 1.0))
					drop = 0.22 * leg * k
					rig.body.rotation.x = 0.15 * k
					rig.head.rotation.x = 0.25 * k
					feet[0] += Vector3(0.0, 0.0, 0.08 * k)
					feet[1] += Vector3(0.0, 0.0, 0.08 * k)
					feet[2] += Vector3(0.0, 0.0, 0.12 * k)   # 後腳往前收，準備蹬
					feet[3] += Vector3(0.0, 0.0, 0.12 * k)
				&"dash":
					drop = -0.1 * leg
					rig.body.rotation.x = -0.1
					rig.head.rotation.x = -0.2
					for i in 2:
						feet[i] += Vector3(0.0, 0.25 * leg, 0.6 * leg)
						feet[i + 2] += Vector3(0.0, 0.2 * leg, -0.6 * leg)
				_:
					var k := clampf(pt / c.recovery, 0.0, 1.0)
					rig.body.rotation.x = lerpf(-0.1, 0.0, k)
					rig.head.rotation.x = lerpf(-0.2, 0.0, k)
					drop = 0.12 * leg * sin(PI * k)   # 落地一沉
		&"snap":   # 快咬：低頭、齜牙（頭壓低往前、前腳一撐）→ 往前竄、張嘴咬
			var c: Dictionary = def.snap
			var pt: float = a.get("phase_time", 0.0)
			if a.get("phase", &"windup") == &"windup":
				var k := MathUtil.ease_out_cubic(clampf(pt / c.windup, 0.0, 1.0))
				rig.body.rotation.x = 0.12 * k
				rig.head.rotation.x = 0.45 * k
				drop = 0.1 * leg * k
			else:
				rig.body.rotation.x = -0.05
				rig.head.rotation.x = -0.35
				feet[0] += Vector3(0.0, 0.1 * leg, 0.35 * leg)
				feet[1] += Vector3(0.0, 0.0, 0.2 * leg)
				feet[2] += Vector3(0.0, 0.0, -0.25 * leg)
				feet[3] += Vector3(0.0, 0.0, -0.15 * leg)
		&"hop":   # 側跳、往後跳：四腳收起
			rig.head.rotation.x = 0.1
			drop = -0.15 * leg
			for i in 4:
				feet[i] += Vector3(0.0, 0.3 * leg, 0.0)
		&"dazed":   # 被盾擋下：甩頭、站不穩
			rig.head.rotation.x = 0.2
			rig.body.rotation.z = 0.15 * sin(t * 18.0)
			drop = 0.06 * leg
		&"hurt":
			rig.body.rotation.z = 0.25 * sin(clampf(t / def.hurt_time, 0.0, 1.0) * PI)
		&"dead":
			var fall := clampf(t / DEATH_FALL_TIME, 0.0, 1.0)
			rig.body.rotation.z = lerpf(0.0, PI / 2.0, MathUtil.ease_out_cubic(fall))
			var sink_start: float = def.corpse_time * CORPSE_SINK_START
			rig.position.y = -CORPSE_SINK_DEPTH * clampf((t - sink_start) / (def.corpse_time - sink_start), 0.0, 1.0)
			for limb in [[rig.arm_r, rig.forearm_r, 0.3, 0.6], [rig.arm_l, rig.forearm_l, -0.2, 0.4], [rig.leg_r, rig.shin_r, -0.3, -0.5], [rig.leg_l, rig.shin_l, 0.2, -0.3]]:
				limb[0].rotation = Vector3(limb[2], 0.0, 0.0)
				limb[1].rotation = Vector3(limb[3], 0.0, 0.0)
			rig.body.position = Vector3.ZERO
			return
	_plant_limbs(feet, drop)


# 墓穴蜘蛛：腳關節往上拱、腳尖撐在身體外側；走路時對角的腳一起抬（前右 + 後左、前左 + 後右）；
# 瞄準時前腳往前上方抬起、身體往前壓（腹部翹起）；受傷抖一下；死掉縮腳翻肚
func _pose_spider(e: Enemy, state: StringName, t: float, dt: float) -> void:
	rig.position.y = 0.0
	rig.body.rotation = Vector3.ZERO
	var s: float = rig.body.scale.x
	var lengths := Vector2(0.22, 0.2)
	var rest := [Vector3(-0.42, 0.0, 0.42) * s, Vector3(0.42, 0.0, 0.42) * s, Vector3(-0.4, 0.0, -0.4) * s, Vector3(0.4, 0.0, -0.4) * s]
	var feet := rest.duplicate()
	var drop := 0.1 * s
	match state:
		&"aim":
			var k := MathUtil.ease_out_cubic(clampf(t / e.def.aim_time, 0.0, 1.0))
			feet[0] = rest[0].lerp(Vector3(-0.22, 0.6, 0.62) * s, k)
			feet[1] = rest[1].lerp(Vector3(0.22, 0.6, 0.62) * s, k)
			rig.body.rotation.x = lerpf(0.0, 0.35, k)
		&"hurt":
			rig.body.rotation.z = sin(t * 60.0) * 0.12
		&"spawn":
			rig.position.y = lerpf(-rig.height, 0.0, clampf(t / e.def.spawn_time, 0.0, 1.0))
		&"dead":
			var k := MathUtil.ease_out_cubic(clampf(t / 0.3, 0.0, 1.0))
			rig.body.rotation.z = PI * k
			rig.body.position = Vector3(0.0, 0.6 * k, 0.0)
			for limb in [[rig.arm_r, rig.forearm_r], [rig.arm_l, rig.forearm_l], [rig.leg_r, rig.shin_r], [rig.leg_l, rig.shin_l]]:
				limb[0].rotation = Vector3(-1.0 * k, 0.0, 0.0)
				limb[1].rotation = Vector3(1.6 * k, 0.0, 0.0)   # 死掉的蜘蛛腳往內縮
			return
		_:
			walk_phase = BodyPose.advance(walk_phase, _speed, 0.38 * s, dt)
			var amount := _walk_amount
			var lift := 0.15 * s * amount
			for i in 4:
				var u := fposmod(walk_phase / TAU + (0.0 if i == 0 or i == 3 else 0.5), 1.0)
				var f := BodyPose.foot_path(u, 0.55, 0.3 * s * amount, lift, 0.0)
				feet[i] = (rest[i] as Vector3) + Vector3(0.0, f.y, f.x)
	_plant_limbs(feet, drop, true, lengths)


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


# 屍甲蟲：鑽地時藏在地面下（BEETLE_HIDE）；冒出前在地面下抖、露出一點殼；冒出來往上跳一下；在地面上腳一直快速倒換；
# 爬出照一般從地下升起；死掉翻肚
func _pose_beetle(e: Enemy, state: StringName, t: float, _dt: float) -> void:
	rig.body.rotation = Vector3.ZERO
	rig.position.y = 0.0
	var s: float = rig.body.scale.x
	var rest := [Vector3(-0.26, 0.0, 0.26) * s, Vector3(0.26, 0.0, 0.26) * s, Vector3(-0.26, 0.0, -0.24) * s, Vector3(0.26, 0.0, -0.24) * s]
	var feet := []
	for i in 4:   # 腳一直快速倒換（對角的一起）
		var u := fposmod(t * 6.0 + (0.0 if i == 0 or i == 3 else 0.5), 1.0)
		var f := BodyPose.foot_path(u, 0.5, 0.1 * s, 0.06 * s, 0.0)
		feet.append((rest[i] as Vector3) + Vector3(0.0, f.y, f.x))
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
			rig.body.position = Vector3(0.0, 0.25, 0.0)
			rig.position.y = -CORPSE_SINK_DEPTH * 0.5 * clampf((t - e.def.corpse_time * CORPSE_SINK_START) / (e.def.corpse_time * (1.0 - CORPSE_SINK_START)), 0.0, 1.0)
			for limb in [[rig.arm_r, rig.forearm_r], [rig.arm_l, rig.forearm_l], [rig.leg_r, rig.shin_r], [rig.leg_l, rig.shin_l]]:
				limb[0].rotation = Vector3(sin(t * 30.0) * 0.4 * maxf(0.0, 1.0 - t), 0.0, 0.0)   # 翻肚後腳亂踢一陣
				limb[1].rotation = Vector3(1.2, 0.0, 0.0)
			return
	_plant_limbs(feet, 0.05 * s, true, Vector2(0.1, 0.11))


# 萬骨聚合體（骸骨將軍 form 1）：追擊駝背（從髖部彎）拖著走；骨刺陣雙臂高舉 → 插進地面（深蹲）；多臂橫掃先扭到底、
# 低掃（彎腰蹲低）轉一圈、高掃（挺胸）再轉一圈；巨骨輪蜷成球（抱膝）、滾的時候晃；撞牆暈倒仰躺；吞屍雙臂張開、胸口往前挺
func _pose_colossus(e: Enemy, a: Dictionary, state: StringName, t: float, _dt: float) -> void:
	var c: Dictionary = e.def.colossus
	_walk(0.0, -0.4, -0.4, 0.5)
	rig.body.rotation = Vector3(0.25, 0.0, 0.0)
	match state:
		&"spikes":
			var w: float = c.spikes.windup
			var k := MathUtil.ease_out_cubic(clampf(t / w, 0.0, 1.0))
			if t < w:
				_arms(lerpf(-0.5, -2.9, k), 0.25, lerpf(0.5, 0.7, k))
				rig.body.rotation.x = lerpf(0.25, -0.2, k)
			else:
				var d := MathUtil.ease_out_cubic(clampf((t - w) / 0.12, 0.0, 1.0))
				_arms(lerpf(-2.9, -0.35, d), 0.25, lerpf(0.7, 0.1, d))
				rig.body.rotation.x = lerpf(-0.2, 0.6, d)
				_set_stance(0.3 * d, 0.3, -0.3)
		&"sweep":
			var s: Dictionary = c.sweep
			var pt: float = a.get("phase_time", t)
			match a.get("phase", &"windup"):
				&"windup":
					var k := MathUtil.ease_out_cubic(clampf(pt / s.windup, 0.0, 1.0))
					rig.body.rotation.y = -1.3 * k
					_arms(-1.2, lerpf(0.3, 1.4, k), 0.4)
					_set_stance(0.12 * k, -0.25, 0.25)
				&"low":
					rig.body.rotation = Vector3(0.55, -1.3 + TAU * clampf(pt / s.gap, 0.0, 1.0), 0.0)
					_arms(-0.9, 1.5, 0.2)
					_set_stance(0.3, -0.25, 0.25)
				&"high":
					rig.body.rotation = Vector3(-0.15, -1.3 + TAU * clampf(pt / 0.3, 0.0, 1.0), 0.0)
					_arms(-1.6, 1.5, 0.2)
					_set_stance(0.05, -0.25, 0.25)
		&"wheel":
			_free = true
			_arms(-2.4, 0.4, 1.6)
			BodyPose.leg(rig, true, -1.3, 2.0)
			BodyPose.leg(rig, false, -1.3, 2.0)
			rig.body.position.y = 0.1   # 蜷成球：抱膝的腿在身體下面，球要抬起來腿才不穿進地板
			rig.body.rotation.x = 1.0
			rig.head.rotation.x = 0.6
			if a.get("phase", &"windup") == &"roll":
				rig.body.rotation.z = sin(t * 22.0) * 0.15
				rig.body.position.y = 0.1 + absf(sin(t * 11.0)) * 0.15
		&"wheel_stun":
			_free = true
			rig.body.rotation.x = -0.55
			rig.body.position.y = -0.3
			_arms(-0.3, 1.2, 0.3)
			BodyPose.leg(rig, true, -0.9, 0.8)
			BodyPose.leg(rig, false, -0.5, 0.5)
			rig.head.rotation.x = -0.4 + sin(t * 3.0) * 0.1
		&"devour":
			var k := MathUtil.ease_out_cubic(clampf(t / c.devour.windup, 0.0, 1.0))
			_arms(lerpf(-0.6, -1.4, k), lerpf(0.3, 1.4, k), 0.4)
			rig.body.rotation.x = lerpf(0.25, -0.35, k)
			rig.head.rotation.x = lerpf(0.0, -0.4, k)
		_:
			_walk(1.0, -0.4, -0.4, 0.5)
			rig.body.rotation.x = 0.25


# 雙臂一起：rx 前後、ry 往兩側張開（正的往外）、elbow 手肘彎
func _arms(rx: float, ry: float, elbow := ELBOW_REST) -> void:
	BodyPose.arm(rig, true, rx, -ry, elbow)
	BodyPose.arm(rig, false, rx, ry, elbow)


# 守墓人（老人）：四招的預備動作兩兩不同（設計方向「怪物攻擊不畫紅圈」）
#   鐵鏟揮擊 = 鏟子扛到右肩後（手肘彎）、身體往右扭；鏟土拋擲 = 蹲下把鏟子插進地裡、再往後撬；
#   提燈噴火 = 左手把提燈舉到臉前（手肘彎）、身體後仰吸氣；口哨 = 右手兩指放進嘴裡、抬頭
func _pose_keeper(e: Enemy, a: Dictionary, state: StringName, t: float, _dt: float) -> void:
	if a.get("form", 0) > 0:
		_pose_wolf(e, a, state, t, _dt)
		return
	var def := e.def
	var pt: float = a.get("phase_time", 0.0)
	rig.body.scale = _sized_scale(a)
	_walk(0.0, -0.6, -0.5, 0.6)
	match state:
		&"transform":
			# 變身：彎腰咳嗽、全身抖、身體一下一下脹大（結束時換成狼人模型）
			var k := clampf(t / def.transform.time, 0.0, 1.0)
			rig.body.rotation.x = 0.6 * minf(1.0, k * 3.0) + sin(t * 40.0) * 0.05
			_arms(-0.4 - 0.6 * k + sin(t * 30.0) * 0.1, 0.6 * k, 0.9)
			rig.body.scale = _sized_scale(a) * (1.0 + 0.15 * k * (0.7 + 0.3 * sin(t * 18.0)))
			_set_stance(0.2 * k, 0.15, -0.2)
		&"grow":
			# 變大：挺直、雙臂往兩側撐開、仰頭，全身抖（大小照 size 慢慢放大）
			var k := MathUtil.ease_out_cubic(clampf(t / def.grow.time, 0.0, 1.0))
			_arms(lerpf(-0.5, -0.9, k) + sin(t * 30.0) * 0.08, lerpf(0.0, 0.9, k), 0.6)
			rig.body.rotation.x = lerpf(0.3, -0.2, k)
			rig.head.rotation.x = lerpf(0.0, -0.35, k)
			_set_stance(0.1, 0.2, -0.2)
		&"patrol":
			# 掃地：走的時候駝背慢走，停下來時鏟子左右掃地（腰跟著轉）
			_walk(0.8, -0.8, -0.5, 0.6)
			rig.body.rotation.x = 0.3
			if _speed <= 0.1:
				BodyPose.arm(rig, true, -0.9, 0.5 * sin(t * 2.5), 0.5)
				rig.body.rotation.y = 0.15 * sin(t * 2.5)
				_set_stance(0.06, 0.2, -0.15)
		&"reveal":
			# 揭穿：挺直腰、轉頭看人
			var k := MathUtil.ease_out_cubic(clampf(t / 0.5, 0.0, 1.0))
			_walk(0.0, -0.5, -0.4, 0.5)
			rig.body.rotation.x = lerpf(0.3, -0.05, k)
			rig.head.rotation.x = lerpf(0.0, -0.15, k)
		&"chase":
			_walk(1.0, -0.6, -0.5, 0.7)
			rig.body.rotation.x = 0.25
		&"shovel":
			var s: Dictionary = def.shovel
			if t < s.windup:
				var k := MathUtil.ease_out_cubic(t / s.windup)
				BodyPose.arm(rig, true, lerpf(-0.6, -2.6, k), lerpf(0.0, 0.9, k), lerpf(0.6, 1.3, k))
				rig.body.rotation.y = lerpf(0.0, -0.5, k)
				_set_stance(0.08 * k, -0.1, 0.25, k)
			else:
				var k := clampf((t - s.windup) / (s.active + 0.1), 0.0, 1.0)
				BodyPose.arm(rig, true, lerpf(-2.6, -1.3, k), lerpf(0.9, -0.9, k), lerpf(1.3, 0.15, minf(1.0, k * 1.6)))
				rig.body.rotation.y = lerpf(-0.5, 0.5, k)
				_set_stance(0.14, -0.2, 0.4)
			BodyPose.arm(rig, false, -0.5, 0.2, 0.9)
			rig.body.rotation.x = 0.15
		&"dig":
			# 瘋狂鏟土：蹲低、彎腰把鏟子插進地裡（windup）→ 鏟子一下一下往後狂甩土、身體跟著上下 → 收招
			var l: Dictionary = def.dig
			match a.get("phase", &"windup"):
				&"windup":
					var k := MathUtil.ease_out_cubic(clampf(pt / l.windup, 0.0, 1.0))
					rig.body.rotation.x = lerpf(0.25, 0.6, k)
					BodyPose.arm(rig, true, lerpf(-0.6, 0.2, k), 0.0, 0.3)
					BodyPose.arm(rig, false, lerpf(-0.5, 0.1, k), 0.0, 0.4)
					_set_stance(0.25 * k, 0.3, -0.2)
				&"dig":
					var s := sin(pt * 22.0)   # 一秒約 3.5 下
					rig.body.rotation.x = 0.5 + 0.18 * s
					BodyPose.arm(rig, true, lerpf(0.2, -2.4, 0.5 + 0.5 * s), 0.3 * s, lerpf(0.2, 1.0, 0.5 + 0.5 * s))
					BodyPose.arm(rig, false, lerpf(0.1, -1.6, 0.5 + 0.5 * s), -0.2, 0.6)
					rig.head.rotation.x = 0.2
					_set_stance(0.22 + 0.06 * s, 0.3, -0.2)
				_:
					var k := clampf(pt / l.recovery, 0.0, 1.0)
					rig.body.rotation.x = lerpf(0.5, 0.25, k)
					BodyPose.arm(rig, true, lerpf(-1.2, -0.6, k), 0.0, 0.6)
					_set_stance(0.25 * (1.0 - k), 0.3, -0.2)
		&"scoop":
			# 鏟起：蹲低、鏟面貼地往前滑（鏟子平伸）→ 拋飛：腿蹬直、鏟子往後上方甩 → 埋地：鏟子往下壓、再退一步舉燈 → 直噴
			var s: Dictionary = def.scoop
			match a.get("phase", &"windup"):
				&"windup":
					var k := MathUtil.ease_out_cubic(clampf(pt / s.windup, 0.0, 1.0))
					rig.body.rotation.x = lerpf(0.25, 0.6, k)
					BodyPose.arm(rig, true, lerpf(-0.6, -1.1, k), lerpf(0.0, -0.5, k), 0.2)
					BodyPose.arm(rig, false, lerpf(-0.5, -1.0, k), lerpf(0.0, 0.4, k), 0.4)
					rig.head.rotation.x = 0.3 * k
					_set_stance(0.28 * k, -0.15, 0.35)
				&"throw":
					var k := MathUtil.ease_out_cubic(clampf(pt / 0.25, 0.0, 1.0))
					rig.body.rotation.x = lerpf(0.6, -0.3, k)
					_arms(lerpf(-1.1, -3.0, k), 0.2, lerpf(0.2, 0.6, k))
					_set_stance(lerpf(0.28, 0.02, k), -0.15, 0.35)
				&"bury":
					var b: Dictionary = s.bury
					if pt < b.step_time:
						var k := clampf(pt / b.step_time, 0.0, 1.0)
						rig.body.rotation.x = lerpf(0.6, 0.4, k)
						BodyPose.arm(rig, true, lerpf(-1.1, 0.1, k), 0.0, lerpf(0.2, 0.5, k))
						_set_stance(0.2, -0.15, 0.35)
					else:
						var k := MathUtil.ease_out_cubic(clampf((pt - b.step_time) / b.open, 0.0, 1.0))
						BodyPose.arm(rig, false, lerpf(-0.5, -1.5, k), lerpf(0.0, -0.4, k), lerpf(0.4, 1.0, k))
						BodyPose.arm(rig, true, -0.4, 0.0, 0.5)
						rig.body.rotation.x = lerpf(0.4, 0.15, k)
						_set_stance(0.1, lerpf(-0.15, -0.4, k), 0.1)
				_:
					rig.body.rotation.x = lerpf(0.6, 0.25, clampf(pt / s.miss_recovery, 0.0, 1.0))
					BodyPose.arm(rig, true, -0.8, 0.0, 0.4)
		&"lantern":
			var f: Dictionary = def.lantern
			match a.get("phase", &"windup"):
				&"windup":
					var k := MathUtil.ease_out_cubic(clampf(pt / f.windup, 0.0, 1.0))
					BodyPose.arm(rig, false, lerpf(-0.5, -1.5, k), lerpf(0.0, -0.4, k), lerpf(0.4, 1.1, k))
					rig.body.rotation.x = lerpf(0.25, -0.2, k)
					rig.head.rotation.x = lerpf(0.0, -0.2, k)
				&"spin_windup":
					# 轉圈前的預備：提燈往回收、身體後仰，看得出下一下要掃一圈
					var k := MathUtil.ease_out_cubic(clampf(pt / f.spin_windup, 0.0, 1.0))
					BodyPose.arm(rig, false, -1.5, lerpf(-0.4, 0.8, k), 0.9)
					rig.body.rotation.x = lerpf(0.2, -0.25, k)
					rig.head.rotation.x = lerpf(0.1, -0.2, k)
				&"flame", &"spin":
					# 追著噴：腳照常走；提燈往前推（手肘打直），轉圈時提燈往外伸
					_walk(1.0, -0.4, -1.5, 0.6)
					BodyPose.arm(rig, false, -1.5, -0.9 if a.get("phase") == &"spin" else -0.4, 0.25)
					rig.body.rotation.x = 0.2
					rig.head.rotation.x = 0.1
				_:
					var k := clampf(pt / f.recovery, 0.0, 1.0)
					BodyPose.arm(rig, false, lerpf(-1.5, -0.5, k), lerpf(-0.4, 0.0, k), lerpf(0.25, 0.5, k))
					rig.body.rotation.x = lerpf(0.2, 0.25, k)
			BodyPose.arm(rig, true, -0.4, 0.0, 0.6)
		&"whistle":
			# 右手兩指放進嘴裡（手肘彎、拳頭到嘴邊）、抬頭
			var k := MathUtil.ease_out_cubic(clampf(t / def.whistle.windup, 0.0, 1.0))
			BodyPose.arm(rig, false, -0.5, 0.0, 0.5)
			rig.body.rotation.x = lerpf(0.25, -0.1, k)
			rig.head.rotation.x = lerpf(0.0, -0.4, k)
			var mouth: Vector3 = rig.head.position + Vector3(-0.04, 0.1, 0.22)
			BodyPose.arm_ik(rig, true, BodyPose.hand_pos(rig, true).lerp(mouth, k), Vector3(-1.0, -0.2, 0.3))


# 墓園狼人：獵食的姿勢（上身從髖部前傾、膝蓋微彎、爪子在前）；三招的預備動作兩兩不同
#   三連爪 = 雙爪往後上方拉開（手肘彎）；飛撲 = 深蹲、雙手往後；狼嚎 = 仰頭、雙臂張開挺胸；隱入黑暗 = 壓低身體奔跑
func _pose_wolf(e: Enemy, a: Dictionary, state: StringName, t: float, _dt: float) -> void:
	var w: Dictionary = e.def.wolf
	var pt: float = a.get("phase_time", 0.0)
	rig.body.scale = _sized_scale(a)
	_walk(0.0, 0.3, 0.3, 1.0)
	rig.body.rotation.x = 0.45
	_set_stance(0.1, 0.15, -0.15)
	match state:
		&"wolf_chase", &"stalk":
			_walk(1.0, -0.2, -0.2, 1.2)
			rig.body.rotation.x = 0.7 if state == &"stalk" else 0.45
			if state == &"stalk":
				_set_stance(0.18, 0.0, 0.0, 0.6)
		&"claw":
			var c: Dictionary = w.claw
			if t < c.windup:
				var k := MathUtil.ease_out_cubic(t / c.windup)
				_arms(lerpf(0.3, -1.7, k), lerpf(0.0, 0.6, k), lerpf(1.0, 1.5, k))
				rig.body.rotation.x = lerpf(0.45, 0.2, k)
				rig.head.rotation.x = 0.1 * k
			else:
				var n := clampi(floori((t - c.windup) / c.interval), 0, 2)   # 第幾下（0~2）
				var k := clampf((t - c.windup - n * c.interval) / c.interval, 0.0, 1.0)
				var swing := lerpf(-1.7, -0.3, k)
				var elbow := lerpf(1.5, 0.2, k)
				if n == 2:
					_arms(swing, 0.2, elbow)   # 第三下雙爪一起往前下撲
					rig.body.rotation.x = lerpf(0.2, 0.6, k)
					_set_stance(0.2, 0.3, -0.35)
				else:
					BodyPose.arm(rig, true, swing if n == 0 else -1.7, -0.3, elbow if n == 0 else 1.5)
					BodyPose.arm(rig, false, swing if n == 1 else -1.7, 0.3, elbow if n == 1 else 1.5)
					rig.body.rotation.x = 0.25
					rig.body.rotation.y = 0.3 if n == 0 else -0.3   # 轉腰帶著爪子
		&"leap":
			var l: Dictionary = w.leap
			match a.get("phase", &"windup"):
				&"windup":
					var k := MathUtil.ease_out_cubic(clampf(pt / l.windup, 0.0, 1.0))
					rig.body.rotation.x = lerpf(0.45, 0.9, k)
					_arms(lerpf(0.3, 0.8, k), 0.2, 0.6)
					rig.head.rotation.x = -0.4 * k
					_set_stance(lerpf(0.1, 0.4, k), 0.15, -0.2)
				&"air":
					_free = true
					rig.body.rotation.x = 0.3
					_arms(-2.0, 0.3, 0.4)
					BodyPose.leg(rig, true, -0.6, 1.4)
					BodyPose.leg(rig, false, 0.3, 1.1)
				_:
					var k := clampf(pt / l.recovery, 0.0, 1.0)
					rig.body.rotation.x = lerpf(0.8, 0.45, k)
					_arms(lerpf(-1.2, 0.3, k), 0.2, 0.8)
					_set_stance(lerpf(0.35, 0.1, k), 0.3, -0.25)
		&"howl":
			var k := MathUtil.ease_out_cubic(clampf(t / w.howl.windup, 0.0, 1.0))
			_arms(lerpf(0.3, -0.6, k), lerpf(0.0, 1.0, k), lerpf(1.0, 0.6, k))
			rig.body.rotation.x = lerpf(0.45, -0.2, k)
			rig.head.rotation.x = lerpf(0.0, -0.7, k)
			_set_stance(0.08, 0.15, -0.15)

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
