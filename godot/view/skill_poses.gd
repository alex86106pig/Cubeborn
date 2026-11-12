# 戰技的角色動作（畫面層）：Player.anim 的 skill（哪一招）與 skill_time（做了幾秒）→ 姿勢，蓋過動作層（普攻、右鍵）。
# 長度照 SkillDefs.pose_time；只是動作，不影響出招時機與判定。每招照真實的發力方式做：
#   揮砍類 = 蓄力時腰往反方向扭、手肘收起，出手轉腰帶動肩膀、手肘在打中時打直；刺 = 擊劍的弓步（同側腳踏出、後腿蹬直、後手往後平衡）；
#   砸地 = 舉過頭時手肘彎、往下砸時膝蓋跟著蹲（彎膝不彎腰）；衝刺 = 跑步姿勢加大前傾；拉弓沿用 Animator.pose_bow
# 手上的武器不符（幻影修飾放的）也照做：弓的招沒有弓時改成往前一指
class_name SkillPoses
extends RefCounted

const SPIN_RATE := 1.6      # 千刃風暴每秒轉幾圈
const BOW_SKILLS: Array[StringName] = [&"volley", &"leap_shot", &"lightning_arrow", &"snipe", &"frost_arrow"]


static func apply(an: Animator, p: Player, a: Dictionary, _dt: float) -> void:
	var id: StringName = a.skill
	if not SkillDefs.SKILLS.has(id):
		return
	var t: float = a.skill_time
	var total := SkillDefs.pose_time(id)
	var k := clampf(t / total, 0.0, 1.0)
	var rig := an.rig
	rig.body.rotation = Vector3.ZERO
	an.stance.weight = 0.0
	if id in BOW_SKILLS and not (rig.weapon_model in Animator.BOW_MODELS):
		_point(an, k)
		return
	match id:
		&"whirlwind":
			_whirlwind(an, k)
		&"blade_storm":
			_blade_storm(an, t, total)
		&"charge_slash":
			_charge_slash(an, k)
		&"thrust":
			_lunge_thrust(an, k)
		&"shield_charge":
			_shield_charge(an, k)
		&"shield_slam":
			_shield_slam(an, k)
		&"soul_reaver":
			_reaver(an, k)
		&"ambush":
			_ambush(an, k)
		&"flame_dash":
			_flame_dash(an, k)
		&"volley":
			_volley(an, t, SkillDefs.SKILLS[id])
		&"leap_shot":
			_leap_shot(an, k)
		&"lightning_arrow", &"frost_arrow":
			_shot(an, k, 0.45, 0.6)
		&"snipe":
			_snipe(an, t, SkillDefs.SKILLS[id])
		&"ground_slam":
			_ground_slam(an, k)
		&"dirt_toss":
			_dirt_toss(an, k)
		&"burrow":
			_burrow(an, t, SkillDefs.SKILLS[id])
		&"bury":
			_bury(an, k)
		_:
			_point(an, k)
	if p.weapon.model in Animator.UPRIGHT_MODELS:
		an.weapon_tilt = lerpf(an.weapon_tilt, 1.2, 0.5)   # 火把、權杖往前倒，像拿著揮


# 0~1 的進度切成三段（前搖 / 出手 / 收招）：回傳 [段, 段內進度（已緩動）]
static func _seg(k: float, w: float, act: float) -> Array:
	if k < w:
		return [0, MathUtil.ease_out_cubic(k / w)]
	if k < act:
		return [1, (k - w) / (act - w)]
	return [2, MathUtil.ease_out_cubic((k - act) / (1.0 - act))]


# 往前一指（沒有對應的武器時）：手臂抬平、手肘從彎到直
static func _point(an: Animator, k: float) -> void:
	var s := _seg(k, 0.3, 0.6)
	var e: float = s[1]
	var reach: float = [e, 1.0, 1.0 - e][s[0]]
	BodyPose.arm(an.rig, true, lerpf(-0.4, -1.5, reach), 0.1, lerpf(1.2, 0.1, reach))
	an.set_stance(0.06 * reach, -0.1, 0.3 * reach)


# 旋風斬：蹲低、腰往右扭、劍收到右後方 → 往左轉一整圈，劍平舉往外甩（手肘幾乎伸直）、左手往另一邊張開平衡 → 收回
static func _whirlwind(an: Animator, k: float) -> void:
	var rig := an.rig
	var s := _seg(k, 0.22, 0.78)
	var e: float = s[1]
	match s[0]:
		0:
			rig.body.rotation.y = lerpf(0.0, -0.7, e)
			BodyPose.arm(rig, true, lerpf(-0.6, -1.3, e), lerpf(0.0, -1.1, e), lerpf(0.9, 1.1, e))
			BodyPose.arm(rig, false, lerpf(-0.3, -1.0, e), 0.6 * e, 1.2)
			an.set_stance(0.14 * e, -0.15, 0.15, e)
		1:
			rig.body.rotation.y = -0.7 + (TAU + 0.7) * smoothstep(0.0, 1.0, e)
			BodyPose.arm(rig, true, -1.5, -1.15, lerpf(1.1, 0.12, minf(1.0, e * 3.0)))
			BodyPose.arm(rig, false, -1.3, 1.0, 0.45)
			an.set_stance(0.16, -0.15, 0.15)
		_:
			BodyPose.arm(rig, true, lerpf(-1.5, -0.6, e), lerpf(-1.15, 0.0, e), lerpf(0.12, 0.9, e))
			BodyPose.arm(rig, false, lerpf(-1.3, -0.3, e), lerpf(1.0, 0.0, e), 1.0)
			an.set_stance(0.16 * (1.0 - e), -0.15, 0.15, 1.0 - e)


# 千刃風暴：一直轉（SPIN_RATE 圈 / 秒），雙臂往兩側張開、劍平舉；站著時兩腳站開蹲低，走動時腳照走；最後 0.2 秒收回
static func _blade_storm(an: Animator, t: float, total: float) -> void:
	var rig := an.rig
	var settle := clampf((total - t) / 0.2, 0.0, 1.0)
	var open := minf(1.0, t / 0.15) * settle
	rig.body.rotation.y = fmod(t * TAU * SPIN_RATE, TAU) * settle
	rig.body.rotation.x = 0.08 * open
	BodyPose.arm(rig, true, lerpf(-0.6, -1.5, open), lerpf(0.0, -1.2, open), lerpf(0.9, 0.15, open))
	BodyPose.arm(rig, false, lerpf(-0.3, -1.4, open), lerpf(0.0, 1.1, open), lerpf(1.0, 0.35, open))
	an.set_stance(0.15 * open, -0.2, 0.2, open)


# 衝鋒斬：衝刺時上身大幅前傾、劍拖在右後下方、左手跟著跑步擺 → 衝到底時一刀往左橫掃（左腳踏出、手肘打直）→ 收
static func _charge_slash(an: Animator, k: float) -> void:
	var rig := an.rig
	var s := _seg(k, 0.6, 0.85)
	var e: float = s[1]
	match s[0]:
		0:
			rig.body.rotation.x = 0.35
			BodyPose.arm(rig, true, 0.55, -0.35, 0.45)
			BodyPose.arm(rig, false, -0.9 + 0.5 * sin(k * 30.0), 0.1, 1.5)
		1:
			rig.body.rotation.y = lerpf(-0.5, 0.45, smoothstep(0.0, 0.7, e))
			rig.body.rotation.x = lerpf(0.35, 0.2, e)
			BodyPose.arm(rig, true, -1.4, lerpf(-1.25, 1.15, e), lerpf(1.2, 0.1, smoothstep(0.0, 0.5, e)))
			BodyPose.arm(rig, false, -0.6, 0.3, 1.4)
			an.set_stance(0.18, -0.35, 0.5)
		_:
			rig.body.rotation.y = lerpf(0.45, 0.0, e)
			rig.body.rotation.x = lerpf(0.2, 0.0, e)
			BodyPose.arm(rig, true, lerpf(-1.4, -0.35, e), lerpf(1.15, 0.0, e), lerpf(0.2, 0.95, e))
			BodyPose.arm(rig, false, lerpf(-0.6, -0.1, e), 0.3 * (1.0 - e), lerpf(1.4, 0.5, e))
			an.set_stance(0.18 * (1.0 - e), -0.35, 0.5, 1.0 - e)


# 突刺（劍）：擊劍的弓步。手肘先收到腰側 → 劍手打直往前（肩膀往前送、腰轉向劍側）、右腳往前踏到膝蓋約直角、
# 左腿往後蹬直、左手往後上方伸開平衡 → 收回
static func _lunge_thrust(an: Animator, k: float) -> void:
	var rig := an.rig
	var s := _seg(k, 0.15, 0.55)
	var e: float = s[1]
	var reach: float = [0.0, smoothstep(0.0, 1.0, minf(1.0, e * 1.6)), 1.0 - e][s[0]]
	if s[0] == 0:
		BodyPose.arm(rig, true, lerpf(-0.4, 0.45, e), 0.05, lerpf(0.9, 1.85, e))
	else:
		BodyPose.arm(rig, true, lerpf(0.45, -1.55, reach), 0.05, lerpf(1.85, 0.03, reach))
	BodyPose.arm(rig, false, lerpf(-0.3, 0.7, reach), lerpf(0.0, -0.35, reach), lerpf(0.6, 0.35, reach))
	rig.body.rotation.y = 0.4 * reach
	rig.body.rotation.x = 0.22 * reach
	an.set_stance(0.26 * reach, 0.7 * reach, -0.75 * reach, maxf(reach, 0.3))


# 盾衝：盾橫在身前（左前臂擋在胸口）、肩膀頂著盾、上身前傾低頭往前衝，劍收在右腰；撞到底時兩腳一撐煞住
static func _shield_charge(an: Animator, k: float) -> void:
	var rig := an.rig
	var brace := smoothstep(0.62, 0.8, k) * (1.0 - smoothstep(0.85, 1.0, k))
	var hold := 1.0 - smoothstep(0.85, 1.0, k)
	rig.body.rotation.x = 0.42 * hold
	rig.body.rotation.y = 0.35 * hold   # 左肩在前
	rig.head.rotation.x = 0.15 * hold
	BodyPose.arm(rig, false, lerpf(-0.1, -1.3, hold), lerpf(0.0, -0.65, hold), lerpf(0.3, 1.45, hold))
	BodyPose.arm(rig, true, lerpf(-0.35, 0.35, hold), 0.0, lerpf(0.9, 1.1, hold))
	if brace > 0.0:
		an.set_stance(0.2, -0.45, 0.45, brace)


# 震盾：盾舉過頭（手肘微彎、身體往上挺）→ 往前下方砸向地面、膝蓋深蹲、上身前壓 → 收回
static func _shield_slam(an: Animator, k: float) -> void:
	var rig := an.rig
	var s := _seg(k, 0.4, 0.62)
	var e: float = s[1]
	match s[0]:
		0:
			BodyPose.arm(rig, false, lerpf(-0.2, -2.7, e), lerpf(0.0, -0.25, e), lerpf(0.4, 0.6, e))
			BodyPose.arm(rig, true, lerpf(-0.35, -0.6, e), 0.0, 1.0)
			rig.body.rotation.x = -0.15 * e
			an.set_stance(0.0, -0.1, 0.2, e)
		1:
			BodyPose.arm(rig, false, lerpf(-2.7, -0.75, e), -0.25, lerpf(0.6, 0.15, e))
			BodyPose.arm(rig, true, -0.4, 0.0, 1.0)
			rig.body.rotation.x = lerpf(-0.15, 0.5, e)
			an.set_stance(0.36 * e, -0.3, 0.45)
		_:
			BodyPose.arm(rig, false, lerpf(-0.75, -0.1, e), lerpf(-0.25, 0.0, e), lerpf(0.15, 0.3, e))
			BodyPose.arm(rig, true, lerpf(-0.4, -0.35, e), 0.0, lerpf(1.0, 0.95, e))
			rig.body.rotation.x = lerpf(0.5, 0.0, e)
			an.set_stance(0.36 * (1.0 - e), -0.3, 0.45, 1.0 - e)


# 噬魂刃：劍舉到右肩後上方（手肘彎、腰往右扭、上身後仰）→ 斜劈往左下（轉腰、手肘打直、左腳踏出、膝蓋沉）→ 收
static func _reaver(an: Animator, k: float) -> void:
	var rig := an.rig
	var s := _seg(k, 0.35, 0.6)
	var e: float = s[1]
	match s[0]:
		0:
			BodyPose.arm(rig, true, lerpf(-0.5, -2.6, e), lerpf(0.0, -0.6, e), lerpf(0.9, 1.4, e))
			BodyPose.arm(rig, false, lerpf(-0.3, -0.9, e), 0.3, 1.2)
			rig.body.rotation.y = -0.5 * e
			rig.body.rotation.x = -0.1 * e
			an.set_stance(0.04 * e, -0.1, 0.2, e)
		1:
			BodyPose.arm(rig, true, lerpf(-2.6, -0.4, e), lerpf(-0.6, 0.9, e), lerpf(1.4, 0.08, smoothstep(0.0, 0.6, e)))
			BodyPose.arm(rig, false, -0.6, 0.3, 1.4)
			rig.body.rotation.y = lerpf(-0.5, 0.4, e)
			rig.body.rotation.x = lerpf(-0.1, 0.35, e)
			an.set_stance(0.22 * e, -0.3, 0.5)
		_:
			BodyPose.arm(rig, true, lerpf(-0.4, -0.35, e), lerpf(0.9, 0.0, e), lerpf(0.08, 0.95, e))
			BodyPose.arm(rig, false, lerpf(-0.6, -0.1, e), lerpf(0.3, 0.0, e), lerpf(1.4, 0.5, e))
			rig.body.rotation.y = lerpf(0.4, 0.0, e)
			rig.body.rotation.x = lerpf(0.35, 0.0, e)
			an.set_stance(0.22 * (1.0 - e), -0.3, 0.5, 1.0 - e)


# 背刺突襲：瞬移到怪背後時壓低蹲著（手肘收在腰側）→ 雙手匕首由下往前上刺進背心、身體往上頂 → 收
static func _ambush(an: Animator, k: float) -> void:
	var rig := an.rig
	var s := _seg(k, 0.25, 0.55)
	var e: float = s[1]
	var drop := 0.0
	var reach := 0.0
	match s[0]:
		0:
			drop = 0.35
		1:
			drop = lerpf(0.35, 0.18, e)
			reach = e
		_:
			drop = 0.18 * (1.0 - e)
			reach = 1.0 - e
	for right: bool in [true, false]:
		BodyPose.arm(rig, right, lerpf(0.4, -1.3, reach), 0.12 * (1.0 if right else -1.0), lerpf(1.9, 0.1, reach))
	rig.body.rotation.x = lerpf(0.5, 0.25, reach)
	an.set_stance(drop, 0.3, -0.35, 1.0 if s[0] < 2 else 1.0 - e)


# 火焰衝刺：衝刺時上身前傾、火把往前下方伸（手肘半彎）、左手跟著跑步擺；衝到底兩腳一撐煞住
static func _flame_dash(an: Animator, k: float) -> void:
	var rig := an.rig
	var hold := 1.0 - smoothstep(0.75, 1.0, k)
	var brace := smoothstep(0.6, 0.72, k) * hold
	rig.body.rotation.x = 0.32 * hold
	BodyPose.arm(rig, true, lerpf(-0.4, -1.0, hold), 0.1, lerpf(0.7, 0.5, hold))
	BodyPose.arm(rig, false, -0.3 + 0.7 * sin(k * 28.0) * hold, 0.0, lerpf(0.3, 1.5, hold))
	if brace > 0.0:
		an.set_stance(0.18, 0.4, -0.3, brace)


# 弓的一發（閃電箭、冰霜箭）：前搖抽箭搭弦拉滿（到 draw_end）→ 放箭（到 release_end）→ 收招回箭袋
static func _shot(an: Animator, k: float, draw_end: float, release_end: float) -> void:
	if k < draw_end:
		var e := MathUtil.ease_out_cubic(k / draw_end)
		an.pose_bow({"phase": &"windup", "k": k / draw_end}, e, false)
	elif k < release_end:
		an.pose_bow({"phase": &"active", "k": 1.0}, (k - draw_end) / (release_end - draw_end), false)
	else:
		an.pose_bow({"phase": &"recovery", "k": 1.0}, MathUtil.ease_out_cubic((k - release_end) / (1.0 - release_end)), false)


# 連珠箭：箭先拿在拉弦手裡（速射的拿法），舉弓後一支接一支快速半拉就放（每 interval 秒一支）；射完收回
static func _volley(an: Animator, t: float, d: Dictionary) -> void:
	var interval: float = d.interval
	var raise := 0.12
	if t < raise:
		an.pose_bow({"phase": &"windup", "k": t / raise}, MathUtil.ease_out_cubic(t / raise) * Animator.BRING_PART, false)
		return
	var shots: int = d.count
	var u := (t - raise) / interval
	if u < shots:
		var c := fmod(u, 1.0)
		if c < 0.6:   # 半拉：從搭弦拉到七成
			var draw := c / 0.6 * 0.7
			an.pose_bow({"phase": &"windup", "k": 1.0}, Animator.BRING_PART + (1.0 - Animator.BRING_PART) * draw, false)
		else:
			an.pose_bow({"phase": &"active", "k": 1.0}, (c - 0.6) / 0.4 * 0.5, false)
		return
	var rest := SkillDefs.pose_time(&"volley") - raise - shots * interval
	an.pose_bow({"phase": &"recovery", "k": 1.0}, MathUtil.ease_out_cubic(clampf((u - shots) * interval / maxf(rest, 0.01), 0.0, 1.0)), false)


# 後跳射：往後跳開（雙腿收起、上身後仰）同時拉滿放箭，落地時膝蓋一沉
static func _leap_shot(an: Animator, k: float) -> void:
	var rig := an.rig
	_shot(an, k, 0.35, 0.55)
	if k < 0.75:
		an.free_legs = true
		var air := sin(PI * k / 0.75)
		rig.body.position.y = 0.0
		rig.body.rotation.x = -0.22 * air
		BodyPose.leg(rig, true, lerpf(-0.2, -0.9, air), lerpf(0.2, 1.3, air))
		BodyPose.leg(rig, false, lerpf(0.1, -0.3, air), lerpf(0.2, 1.6, air))
	else:
		an.set_stance(0.22 * sin(PI * (k - 0.75) / 0.25), 0.2, -0.2)


# 狙擊：單膝跪地（右腳在前、左膝著地）穩住，抽箭拉滿後撐著蓄力（windup 秒）→ 放箭 → 起身
static func _snipe(an: Animator, t: float, d: Dictionary) -> void:
	var windup: float = d.windup
	var draw := windup * 0.55
	var kneel := minf(1.0, t / 0.2) * (1.0 - clampf((t - windup - 0.08) / 0.12, 0.0, 1.0))
	if t < draw:
		an.pose_bow({"phase": &"windup", "k": t / draw}, MathUtil.ease_out_cubic(t / draw), false)
	elif t < windup:
		an.pose_bow({"phase": &"active", "k": 1.0}, 0.0, true)
	elif t < windup + 0.1:
		an.pose_bow({"phase": &"active", "k": 1.0}, (t - windup) / 0.1, false)
	else:
		an.pose_bow({"phase": &"recovery", "k": 1.0}, MathUtil.ease_out_cubic(clampf((t - windup - 0.1) / (SkillDefs.POSE_RECOVER - 0.1), 0.0, 1.0)), false)
	an.set_stance(0.42, 0.4, -0.55, maxf(kneel, 0.0))


# 震地（鐵鏟）：雙手握鏟舉過頭（手肘彎、上身後仰）→ 鏟面往前砸進地裡、深蹲前壓（彎膝不彎腰）、左腳在前 → 拔起來收
static func _ground_slam(an: Animator, k: float) -> void:
	var rig := an.rig
	var s := _seg(k, 0.4, 0.65)
	var e: float = s[1]
	var x := 0.0
	var elbow := 0.0
	var lean := 0.0
	var drop := 0.0
	match s[0]:
		0:
			x = lerpf(-0.5, -2.75, e)
			elbow = lerpf(0.6, 1.15, e)
			lean = -0.15 * e
		1:
			x = lerpf(-2.75, -0.55, minf(1.0, e * 2.0))
			elbow = lerpf(1.15, 0.15, minf(1.0, e * 2.0))
			lean = lerpf(-0.15, 0.5, minf(1.0, e * 2.0))
			drop = 0.34 * minf(1.0, e * 2.0)
		_:
			x = lerpf(-0.55, -0.5, e)
			elbow = lerpf(0.15, 0.6, e)
			lean = lerpf(0.5, 0.0, e)
			drop = 0.34 * (1.0 - e)
	BodyPose.arm(rig, true, x, 0.1, elbow)
	rig.body.rotation.x = lean
	an.grip_shaft(0.45)
	an.set_stance(drop, -0.3, 0.45, 1.0 if s[0] < 2 else 1.0 - e)


# 甩土（鐵鏟）：蹲低、鏟面往前貼地插進土裡 → 腿蹬直、往前上方把土甩出去（往甩的方向踏一步）→ 收
static func _dirt_toss(an: Animator, k: float) -> void:
	var rig := an.rig
	var s := _seg(k, 0.35, 0.6)
	var e: float = s[1]
	match s[0]:
		0:
			BodyPose.arm(rig, true, lerpf(-0.5, -0.25, e), 0.1, lerpf(0.6, 0.3, e))
			rig.body.rotation.x = 0.45 * e
			an.set_stance(0.3 * e, -0.2, 0.35, e)
		1:
			BodyPose.arm(rig, true, lerpf(-0.25, -2.0, e), 0.1, lerpf(0.3, 0.45, e))
			rig.body.rotation.x = lerpf(0.45, -0.1, e)
			an.set_stance(lerpf(0.3, 0.05, e), lerpf(-0.2, -0.3, e), 0.45)
		_:
			BodyPose.arm(rig, true, lerpf(-2.0, -0.5, e), 0.1, lerpf(0.45, 0.6, e))
			rig.body.rotation.x = lerpf(-0.1, 0.0, e)
			an.set_stance(0.05, -0.3, 0.45, 1.0 - e)
	an.grip_shaft(0.45)


# 掘地（鐵鏟）：蹲下、雙手往前舉過頭往地裡鑽（身體往前栽、沉到地面下）→ 在地下移動 → 從目標地點跳出來（雙手往上、腿收起）→ 落地
static func _burrow(an: Animator, t: float, d: Dictionary) -> void:
	var rig := an.rig
	var dive := 0.15
	var under: float = d.time - 0.12
	an.free_legs = true
	if t < dive:
		var e := MathUtil.ease_out_cubic(t / dive)
		an.free_legs = false
		rig.body.rotation.x = 0.9 * e
		BodyPose.arm(rig, true, lerpf(-0.5, -2.7, e), 0.15, 0.3)
		BodyPose.arm(rig, false, lerpf(-0.3, -2.7, e), -0.15, 0.3)
		an.set_stance(0.35 * e, 0.2, -0.2)
	elif t < under:
		rig.body.rotation.x = 1.3
		rig.body.position.y = -rig.height * 0.75   # 鑽進地裡：只剩鏟子與腳尖在地面附近（墳土的特效蓋住）
		BodyPose.arm(rig, true, -2.8, 0.15, 0.2)
		BodyPose.arm(rig, false, -2.8, -0.15, 0.2)
		BodyPose.leg(rig, true, 0.2, 0.6)
		BodyPose.leg(rig, false, 0.3, 0.8)
	elif t < d.time + 0.08:
		var e := clampf((t - under) / 0.2, 0.0, 1.0)
		rig.body.rotation.x = lerpf(-0.1, 0.0, e)
		rig.body.position.y = rig.height * 0.25 * sin(PI * e)
		BodyPose.arm(rig, true, -2.8, -0.3, 0.3)
		BodyPose.arm(rig, false, -2.8, 0.3, 0.3)
		BodyPose.leg(rig, true, -0.8 * sin(PI * e), 1.2 * sin(PI * e))
		BodyPose.leg(rig, false, -0.3 * sin(PI * e), 1.4 * sin(PI * e))
	else:
		an.free_legs = false
		var e := clampf((t - d.time - 0.08) / SkillDefs.POSE_RECOVER, 0.0, 1.0)
		BodyPose.arm(rig, true, lerpf(-2.0, -0.5, e), 0.0, lerpf(0.4, 0.6, e))
		BodyPose.arm(rig, false, lerpf(-2.0, -0.3, e), 0.0, 0.4)
		an.set_stance(0.25 * (1.0 - e), 0.2, -0.2, 1.0 - e)


# 活埋（鐵鏟）：蹲低、鏟子豎起來往面前的怪身上一下一下往下鏟土（兩下）、左手扶著柄
static func _bury(an: Animator, k: float) -> void:
	var rig := an.rig
	var open := minf(1.0, k / 0.15) * (1.0 - smoothstep(0.85, 1.0, k))
	var stab := maxf(0.0, sin(clampf((k - 0.1) / 0.75, 0.0, 1.0) * TAU * 2.0))   # 兩下
	BodyPose.arm(rig, true, lerpf(-0.5, lerpf(-1.7, -0.7, stab), open), 0.1, lerpf(0.6, lerpf(1.2, 0.2, stab), open))
	rig.body.rotation.x = lerpf(0.0, 0.3 + 0.15 * stab, open)
	an.grip_shaft(0.45)
	an.set_stance(lerpf(0.0, 0.2 + 0.06 * stab, open), -0.25, 0.35, open)
