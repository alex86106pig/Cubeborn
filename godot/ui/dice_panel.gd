# 骰子模式的畫面（DiceRun，docs/系統說明.md §55）：擲骰時蓋在畫面中間（6 顆骰子、限時條、擲 / 重擲 / 完成、這一手的結果），
# 全部擲完 3、2、1，打完 3 選 1 獎勵；戰鬥與逛地圖時只在技能欄上方留一行「右鍵：旋風斬 ×3 強化…」
# 結果由權威端決定，這裡照 Seat.roll_seq 播轉動畫（DiceDefs.SETTLE_TIME 內停完）；操作走 op_requested → InputCmd.inv_ops（OP_DICE_*）
# 鍵盤由 InputCollector 交給 handle_key：空白鍵擲 / 重擲、R 重擲、Enter 完成、數字鍵選獎勵；逛地圖與戰鬥中 R 花 1 次自己擲
class_name DicePanel
extends Control

signal op_requested(op: Array)

const DIE_SIZE := 116.0
const DIE_GAP := 22
const KIND_COLORS := {&"skill": Color("e8963a"), &"effect": Color("4fa3d9"), &"team": Color("5fd08a"),
	&"blank": Color("2c2836"), &"grey": Color("55505e")}
const SPIN_STEP := 0.06          # 轉的時候每幾秒換一面
const SPIN_FIRST_STOP := 0.35    # 第一顆停下的時間，之後每顆晚 SPIN_STAGGER（都要在 DiceDefs.SETTLE_TIME 內）
const SPIN_STAGGER := 0.1
const BANNER_TIME := 1.4
const FIGHT_FLASH := 0.7         # 「開打！」留多久
const CARD_W := 400.0
const DIM := Color(0.02, 0.03, 0.06, 0.62)

var _overlay := Control.new()     # 擲骰、倒數、獎勵時蓋住畫面（擋住滑鼠）
var _roll_box := VBoxContainer.new()
var _title := UiKit.label("", UiKit.FONT_HEADING, UiKit.GOLD)
var _timer_bg := UiKit.rect(Color(1, 1, 1, 0.12), Vector2(560, 8))
var _timer_fill := UiKit.rect(Color("e8963a"))   # 不給最小尺寸：寬度每幀照剩下的秒數設
var _dice_row := HBoxContainer.new()
var _hint := UiKit.label("", UiKit.FONT_NOTE, Color(1, 1, 1, 0.75))
var _btn_roll := UiKit.button("擲骰（空白鍵）", UiKit.BUTTON_M)
var _btn_reroll := UiKit.button("", UiKit.BUTTON_M)
var _btn_done := UiKit.button("完成（Enter）", UiKit.BUTTON_M)
var _result := UiKit.label("", UiKit.FONT_BODY, Color("ffcf7a"))
var _result_sub := UiKit.label("", UiKit.FONT_NOTE)
var _effects := UiKit.label("", UiKit.FONT_NOTE, Color("9fd8ff"))
var _cands := HBoxContainer.new()
var _count := UiKit.label("", 150, UiKit.GOLD, 6)
var _banner := UiKit.label("", 64, UiKit.GOLD, 5)
var _reward_box := VBoxContainer.new()
var _reward_cards := HBoxContainer.new()
var _status := UiKit.label("", UiKit.FONT_NOTE, Color(1, 1, 1, 0.9))
var _dice: Array[DieView] = []

var phase: StringName = &""
var my_turn := false
var _seen_seq := -1
var _spin_t := 99.0               # 這次擲出去後經過幾秒（大於最後一顆停下的時間 = 不在轉）
var _spinning: Array[bool] = []
var _was_count := 0
var _banner_t := 0.0
var _fight_t := 0.0
var _cand_key := []
var _offer_key := []
var _picked := false
var _last_phase: StringName = &""
var _charges := 0                 # 本機玩家的擲骰次數（逛地圖 / 戰鬥中按 R 擲要 > 0）
var _can_roll := false            # 本機玩家活著（死掉時 R 留給重新開始）


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := UiKit.rect(DIM)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	add_child(_overlay)

	_roll_box.add_theme_constant_override(&"separation", 16)
	_roll_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_roll_box.set_anchors_preset(Control.PRESET_CENTER)
	_roll_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_roll_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_roll_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for l: Label in [_title, _hint, _result, _result_sub, _effects]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_roll_box.add_child(_title)
	var timer := CenterContainer.new()
	timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer.add_child(_timer_bg)
	_timer_bg.add_child(_timer_fill)
	_roll_box.add_child(timer)
	_dice_row.add_theme_constant_override(&"separation", DIE_GAP)
	_dice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_dice_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in DiceDefs.DICE_COUNT:
		var d := DieView.new(i)
		d.clicked.connect(func(index: int) -> void: op_requested.emit([InputCmd.OP_DICE_LOCK, index]))
		_dice.append(d)
		_spinning.append(false)
		_dice_row.add_child(d)
	_roll_box.add_child(_dice_row)
	_roll_box.add_child(_hint)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override(&"separation", 14)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for b: Button in [_btn_roll, _btn_reroll, _btn_done]:
		btns.add_child(b)
	_btn_roll.pressed.connect(func() -> void: op_requested.emit([InputCmd.OP_DICE_ROLL]))
	_btn_reroll.pressed.connect(func() -> void: op_requested.emit([InputCmd.OP_DICE_ROLL]))
	_btn_done.pressed.connect(func() -> void: op_requested.emit([InputCmd.OP_DICE_DONE]))
	_roll_box.add_child(btns)
	_roll_box.add_child(_result)
	_roll_box.add_child(_result_sub)
	_cands.add_theme_constant_override(&"separation", 10)
	_cands.alignment = BoxContainer.ALIGNMENT_CENTER
	_cands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roll_box.add_child(_cands)
	_roll_box.add_child(_effects)
	_overlay.add_child(_roll_box)

	_reward_box.add_theme_constant_override(&"separation", 20)
	_reward_box.set_anchors_preset(Control.PRESET_CENTER)
	_reward_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_reward_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_reward_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rt := UiKit.label("打倒了！擲骰次數 +1，選一個獎勵（點卡片或按數字鍵）", UiKit.FONT_HEADING, UiKit.GOLD)
	rt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reward_box.add_child(rt)
	_reward_cards.add_theme_constant_override(&"separation", 18)
	_reward_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_reward_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reward_box.add_child(_reward_cards)
	_overlay.add_child(_reward_box)

	for l: Label in [_count, _banner]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(l)
	_banner.pivot_offset = Vector2(960, 540)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 112)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_status)
	visible = false


# 每幀（HUD._process）：照 world.dice 與本機玩家的 Seat 畫
func refresh(world: World, me: Player, dt: float) -> void:
	var dice := world.dice if world != null else null
	visible = dice != null and me != null
	if not visible:
		phase = &""
		return
	phase = dice.phase
	var s := dice.seat_of(me)
	if phase != _last_phase:
		if phase == DiceRun.FIGHT and (_last_phase == DiceRun.COUNTDOWN or _last_phase == DiceRun.EXPLORE):
			_fight_t = FIGHT_FLASH   # 菁英群倒數完、一般群碰到直接開打都閃「開打！」
		if phase == DiceRun.REWARD:
			_picked = false
		_last_phase = phase
	var rolling := phase == DiceRun.ROLL
	var rewarding := phase == DiceRun.REWARD and not s.offers.is_empty() and not _picked
	_overlay.visible = rolling or phase == DiceRun.COUNTDOWN or rewarding
	_roll_box.visible = rolling or phase == DiceRun.COUNTDOWN
	_reward_box.visible = rewarding
	_charges = dice.charges_of(me)
	_can_roll = dice.can_roll(me)
	var turn_player := dice.current(world)
	my_turn = turn_player == me
	if _roll_box.visible:
		_show_roll(world, dice, turn_player if turn_player != null else me, dt)
	if rewarding:
		_show_offers(s, me)
	_show_count(dice, dt)
	_show_banner(dt)
	_status.visible = phase == DiceRun.FIGHT or phase == DiceRun.EXPLORE
	if _status.visible:
		_status.text = status_text(s, _charges)


# 擲骰畫面：畫正在擲的那位（多人時大家看同一個人）
func _show_roll(world: World, dice: DiceRun, p: Player, dt: float) -> void:
	var s := dice.seat_of(p)
	var who := "你" if my_turn else "隊友"
	if phase != DiceRun.ROLL:
		_title.text = "全部擲完了"
	elif dice.back_to != &"":
		_title.text = "%s花 1 次擲骰（剩 %d 次）· 擲完%s" % [who, dice.charges_of(p), "倒數後接著打" if dice.back_to == DiceRun.FIGHT else "繼續逛"]
	else:
		_title.text = "第 %d 場 · 菁英！輪到%s擲骰（%s）" % [dice.fights, who, p.weapon.get("name", "")]
	_timer_fill.size = Vector2(_timer_bg.custom_minimum_size.x * clampf(dice.timer / DiceDefs.ROLL_TIME, 0.0, 1.0), _timer_bg.custom_minimum_size.y)
	_timer_fill.visible = phase == DiceRun.ROLL
	if s.roll_seq != _seen_seq:
		if _seen_seq >= 0 or s.roll_seq > 0:
			_spin_t = 0.0
			for i in _spinning.size():
				_spinning[i] = not s.locked[i]
		_seen_seq = s.roll_seq
	_spin_t += dt
	var spinning_any := false
	for i in _dice.size():
		var d := _dice[i]
		var die: Array = s.pool[i]
		var stop := SPIN_FIRST_STOP + SPIN_STAGGER * i
		var face: StringName = die[s.face[i]]
		if not s.rolled:
			face = die[i % die.size()]   # 還沒擲：每顆露出不同的面，看得出骰子上有什麼
		elif _spinning[i] and _spin_t < stop:
			face = die[int(_spin_t / SPIN_STEP + i * 2) % die.size()]
			spinning_any = true
		elif _spinning[i]:
			_spinning[i] = false
			d.bounce()
		d.show_face(face, p.weapon_id, s.locked[i] and s.rolled, my_turn and s.rolled and s.rerolls > 0 and phase == DiceRun.ROLL)
	var res := DiceDefs.evaluate(s.up_faces(), p.weapon_id, s.choice)
	if not s.rolled or spinning_any:
		_result.text = "" if not s.rolled else "……"
		_result_sub.text = "同一招骰到越多個越強；效果面全部疊上去；灰色是別的武器的技能，當空白" if not s.rolled else ""
		_effects.text = ""
		_set_cands([], p)
	else:
		_result.text = "右鍵：%s" % (DiceDefs.name_of(res.skill) + " ×%d" % res.count if res.count > 0 else "沒中")
		var tier := DiceDefs.tier_of(res.count)
		_result_sub.text = "%s　威力 ×%s" % [tier.name, str(tier.mul)] if res.count > 0 else "沒有右鍵技能，只能普攻"
		_effects.text = effects_text(res.effects, "　")
		_set_cands(res.cands if my_turn and res.cands.size() > 1 else [], p)
		if res.count != _was_count and res.count >= 3 and s.roll_seq > 0:
			_banner.text = "%s！" % tier.name
			_banner_t = BANNER_TIME
		_was_count = res.count
	var busy := spinning_any or dice.settle > 0.0
	_btn_roll.visible = not s.rolled
	_btn_reroll.visible = s.rolled
	_btn_reroll.text = "重擲沒鎖的（R）剩 %d 次" % s.rerolls
	_btn_roll.disabled = not my_turn or busy or phase != DiceRun.ROLL
	_btn_reroll.disabled = not my_turn or busy or s.rerolls <= 0 or not s.locked.has(false) or phase != DiceRun.ROLL
	_btn_done.disabled = not my_turn or busy or not s.rolled or phase != DiceRun.ROLL
	if phase != DiceRun.ROLL:
		_hint.text = ""
	elif not my_turn:
		_hint.text = "隊友擲骰中，大家一起看"
	elif not s.rolled:
		_hint.text = "按擲骰，6 顆一起擲（%d 秒沒動作會自動擲）" % ceili(dice.timer)
	elif s.rerolls > 0:
		_hint.text = "點骰子鎖住想留的，再重擲其他的（%d 秒後自動完成）" % ceili(dice.timer)
	else:
		_hint.text = "沒有重擲次數了，按完成（%d 秒後自動完成）" % ceili(dice.timer)


# 骰到好幾種技能：選一招當右鍵
func _set_cands(cands: Array, p: Player) -> void:
	if cands == _cand_key:
		return
	_cand_key = cands.duplicate()
	for c in _cands.get_children():
		c.queue_free()
	for c: Array in cands:
		var id: StringName = c[0]
		var b := UiKit.button("%s ×%d" % [DiceDefs.name_of(id), c[1]], UiKit.BUTTON_S)
		b.custom_minimum_size.x = 180
		b.pressed.connect(func() -> void: op_requested.emit([InputCmd.OP_DICE_CHOICE, String(id)]))
		_cands.add_child(b)


func _show_count(dice: DiceRun, dt: float) -> void:
	_fight_t = maxf(0.0, _fight_t - dt)
	if phase == DiceRun.COUNTDOWN:
		_count.text = str(clampi(ceili(dice.timer / (DiceDefs.COUNTDOWN / 3.0)), 1, 3))
	elif _fight_t > 0.0:
		_count.text = "開打！"
	else:
		_count.text = ""


func _show_banner(dt: float) -> void:
	_banner_t = maxf(0.0, _banner_t - dt)
	_banner.visible = _banner_t > 0.0
	if _banner.visible:
		var k := 1.0 - _banner_t / BANNER_TIME
		_banner.scale = Vector2.ONE * (0.7 + 0.3 * minf(1.0, k * 6.0))
		_banner.modulate.a = minf(1.0, _banner_t / 0.3)


func _show_offers(s: DiceRun.Seat, me: Player) -> void:
	var key := s.offers.duplicate(true)
	if key == _offer_key:
		return
	_offer_key = key
	for c in _reward_cards.get_children():
		c.queue_free()
	for i in s.offers.size():
		_reward_cards.add_child(_offer_card(i, s.offers[i], me))


func _offer_card(i: int, o: Dictionary, me: Player) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, 230)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override(&"panel", _card_box(UiKit.GOLD, Color(0.11, 0.12, 0.16, 0.96)))
	card.mouse_entered.connect(func() -> void: card.add_theme_stylebox_override(&"panel", _card_box(Color.WHITE, Color(0.17, 0.19, 0.25, 0.98))))
	card.mouse_exited.connect(func() -> void: card.add_theme_stylebox_override(&"panel", _card_box(UiKit.GOLD, Color(0.11, 0.12, 0.16, 0.96))))
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pick(i)
			card.accept_event())
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 10)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(body)
	body.add_child(UiKit.label("%d　%s" % [i + 1, {&"die": "新骰子", &"carve_skill": "刻技能面", &"carve_effect": "刻效果面", &"item": "數值道具"}[o.kind]], UiKit.FONT_NOTE, Color(1, 1, 1, 0.7)))
	var title := UiKit.label(o.title, 26, UiKit.GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = CARD_W - 40
	body.add_child(title)
	if o.has("faces"):
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for f: StringName in o.faces:
			var m := DieView.new(-1, 52.0)
			m.show_face(f, me.weapon_id, false, false)
			row.add_child(m)
		body.add_child(row)
	var desc := UiKit.label(o.desc, UiKit.FONT_NOTE, Color(1, 1, 1, 0.85))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = CARD_W - 40
	body.add_child(desc)
	return card


static func _card_box(border: Color, bg: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(3)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(16)
	return box


func pick(i: int) -> void:
	if phase != DiceRun.REWARD or _picked:
		return
	op_requested.emit([InputCmd.OP_DICE_REWARD, i])
	_picked = true


# InputCollector：骰子畫面開著時先問這裡（處理了回傳 true，不再當成跳躍、重新開始、投票）
func handle_key(event: InputEvent) -> bool:
	if not visible:
		return false
	if not _overlay.visible:   # 逛地圖 / 戰鬥中：R 花 1 次自己擲（沒次數、死掉時不吃，R 照舊給重新開始）
		if event.is_action_pressed(&"restart") and _can_roll and _charges > 0 and (phase == DiceRun.EXPLORE or phase == DiceRun.FIGHT):
			op_requested.emit([InputCmd.OP_DICE_ROLL])
			return true
		return false
	if phase == DiceRun.REWARD:
		for i in DiceDefs.REWARD_CHOICES:
			if event.is_action_pressed(StringName("slot_%d" % (i + 1))):
				pick(i)
				return true
		return false
	if phase != DiceRun.ROLL or not my_turn:
		return event.is_action_pressed(&"jump") or event.is_action_pressed(&"restart") or event.is_action_pressed(&"vote_yes")
	if event.is_action_pressed(&"jump") or event.is_action_pressed(&"restart"):
		op_requested.emit([InputCmd.OP_DICE_ROLL])
		return true
	if event.is_action_pressed(&"vote_yes"):
		op_requested.emit([InputCmd.OP_DICE_DONE])
		return true
	return false


# 戰鬥中技能欄上方那一行
static func status_text(s: DiceRun.Seat, charges: int) -> String:
	var roll := "擲骰 %d 次（R）" % charges if charges > 0 else "擲骰 0 次"
	if s.result.is_empty():
		return "還沒擲骰，沒有右鍵　·　" + roll
	if s.result.count <= 0:
		return "右鍵：沒中（只能普攻）" + ("　·　" + effects_text(s.result.effects, "　·　") if not s.result.effects.is_empty() else "") + "　·　" + roll
	var tier := DiceDefs.tier_of(s.result.count)
	var line := "右鍵：%s ×%d（%s ×%s）" % [DiceDefs.name_of(s.result.skill), s.result.count, tier.name, str(tier.mul)]
	if not s.result.effects.is_empty():
		line += "　·　" + effects_text(s.result.effects, "　·　")
	return line + "　·　" + roll


static func effects_text(effects: Dictionary, sep: String) -> String:
	var parts: Array[String] = []
	for id: StringName in effects:
		parts.append(DiceDefs.effect_text(id, effects[id]))
	return sep.join(parts)


# 一顆骰子（朝上的那面）：底色照種類（技能橘、效果藍、全隊綠、空白暗、別的武器的技能灰），中間圖示、下面名稱；鎖住金框
class DieView extends Control:
	signal clicked(index: int)

	var index := -1
	var face: StringName = &""
	var kind: StringName = &"blank"
	var locked := false
	var clickable := false
	var side := DIE_SIZE
	var _tween: Tween

	func _init(p_index: int, p_side: float = DIE_SIZE) -> void:
		index = p_index
		side = p_side
		custom_minimum_size = Vector2(side, side)
		pivot_offset = custom_minimum_size / 2.0
		mouse_filter = Control.MOUSE_FILTER_STOP if index >= 0 else Control.MOUSE_FILTER_IGNORE

	func show_face(p_face: StringName, weapon_id: StringName, p_locked: bool, p_clickable: bool) -> void:
		var k := DiceDefs.kind_of(p_face, weapon_id)
		if p_face == face and k == kind and p_locked == locked and p_clickable == clickable:
			return
		face = p_face
		kind = k
		locked = p_locked
		clickable = p_clickable
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if clickable else Control.CURSOR_ARROW
		queue_redraw()

	func bounce() -> void:
		if _tween:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(self, ^"scale", Vector2(1.12, 0.9), 0.08)
		_tween.tween_property(self, ^"scale", Vector2.ONE, 0.16)

	func _gui_input(event: InputEvent) -> void:
		if clickable and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(index)
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var col: Color = KIND_COLORS[kind]
		var box := StyleBoxFlat.new()
		box.bg_color = col
		box.set_corner_radius_all(int(side * 0.14))
		box.border_color = UiKit.GOLD if locked else Color(1, 1, 1, 0.18)
		box.set_border_width_all(5 if locked else 2)
		box.shadow_color = Color(0, 0, 0, 0.45)
		box.shadow_size = 6
		draw_style_box(box, r)
		if face == DiceDefs.BLANK:
			return
		var ink := Color(0.08, 0.06, 0.04) if kind != &"grey" else Color(0.18, 0.17, 0.2)
		var icon := DiceDefs.icon_of(face)
		var font := get_theme_default_font()
		var big := int(side * 0.36)
		if SkillIcons.has(icon):
			SkillIcons.draw(self, icon, Vector2(side / 2.0, side * 0.42), 1.0)
		else:
			draw_string(font, Vector2(0, side * 0.42 + big * 0.36), icon, HORIZONTAL_ALIGNMENT_CENTER, side, big, ink)
		if side >= 80.0:
			var caption: String = DiceDefs.name_of(face) if DiceDefs.is_skill(face) else String(DiceDefs.EFFECTS[face].text).split(" ")[0]
			draw_string(font, Vector2(0, side * 0.86), caption, HORIZONTAL_ALIGNMENT_CENTER, side, int(side * 0.15), ink)
		if locked and side >= 80.0:
			draw_string(font, Vector2(0, side + 24), "鎖住", HORIZONTAL_ALIGNMENT_CENTER, side, 18, UiKit.GOLD)
