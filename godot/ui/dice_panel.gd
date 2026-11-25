# 骰子模式的畫面（DiceRun，docs/系統說明.md §55）：擲骰時蓋在畫面中間（6 顆骰子、限時條、擲 / 重擲 / 完成、這一手的結果），
# 全部擲完 3、2、1，打完閃「清場！」再 4 選 1 獎勵；戰鬥與逛地圖時的右鍵、效果、重擲券在 DiceProps（右下的牌與籌碼）
# 結果由權威端決定，這裡照 Seat.roll_seq 播轉動畫（DiceDefs.SETTLE_TIME 內停完）；操作走 op_requested → InputCmd.inv_ops（OP_DICE_*）
# 鍵盤由 InputCollector 交給 handle_key：空白鍵擲 / 重擲、R 重擲（免費的用完花重擲券）、Enter 完成、數字鍵選獎勵
class_name DicePanel
extends Control

signal op_requested(op: Array)
signal sfx(cue: String, gain: float, pitch: float)   # 撞擊聲、揭曉的叮叮聲與中獎 / 可惜（main.gd 接到 Sound.play）

const DIE_SIZE := 116.0
const DIE_GAP := 22
const KIND_COLORS := {&"skill": Color("e8963a"), &"effect": Color("4fa3d9"), &"team": Color("5fd08a"),
	&"blank": Color("2c2836"), &"grey": Color("55505e")}
const SPIN_STEP := 0.06          # 轉的時候每幾秒換一面
const SPIN_FIRST_STOP := 0.35    # 第一顆停下的時間，之後每顆晚 SPIN_STAGGER（都要在 DiceDefs.SETTLE_TIME 內）
const SPIN_STAGGER := 0.1
const BANNER_TIME := 1.4
const FIGHT_FLASH := 0.7         # 「開打！」留多久
const CARD_SIZE := Vector2(230, 320)   # 獎勵卡：直式桌遊卡（YangHsu 2026-11-24 從對比頁選方案 2：大圖在上、名字在下）
const CARD_LIFT := 16.0          # 選到的那張往上抬多少、歪一點
const CARD_TILT := -0.03
const ART_PAPER := Color("e2d4b4")   # 卡上放圖那一塊（比卡紙深一點）
const ART_EDGE := Color("c9b48c")
const CHIP_BG := Color("5b3f8f")     # 擲骰、刻面的按鈕做成籌碼（跟重擲券同一種紫）
const CHIP_RIM := Color("d8c8f0")
const FLAT_SIDE := 46.0       # 獎勵畫面骰子底下攤平的 6 面：每個小方塊多大（字 = 邊長 × 0.36 = 16，預熱過的字級；3 格寬 146 < 骰子間距約 157）
const FLAT_GAP := 4.0
const CARVE_DIE := 64.0          # 刻面時每一面的大小（6 顆 × 6 面）
const DIM := Color(0.02, 0.03, 0.06, 0.62)

var _overlay := Control.new()     # 擲骰、倒數、獎勵時蓋住畫面（擋住滑鼠）
var _roll_box := VBoxContainer.new()
var _title := UiKit.label("", UiKit.FONT_HEADING, UiKit.GOLD)
var _timer_bg := UiKit.rect(Color(1, 1, 1, 0.12), Vector2(560, 8))
var _timer_fill := UiKit.rect(Color("e8963a"))   # 不給最小尺寸：寬度每幀照剩下的秒數設
var _dice_row := HBoxContainer.new()
var _hint := UiKit.label("", UiKit.FONT_NOTE, Color(1, 1, 1, 0.75))
var _btn_roll := UiKit.button("擲骰（空白鍵）", UiKit.BUTTON_M)
var _btn_reroll := UiKit.button("重擲（R）", UiKit.BUTTON_M)
var _reroll_chip := HBoxContainer.new()   # 重擲按鈕旁邊一枚次數籌碼：免費還有幾次、用完了寫剩幾張重擲券
var reroll_chip_text := ""               # 那枚籌碼的完整說明（滑鼠提示；檢查讀）
var _btn_done := UiKit.button("完成（Enter）", UiKit.BUTTON_M)
var _result := UiKit.label("", UiKit.FONT_BODY, Color("ffcf7a"))
var _result_sub := UiKit.label("", UiKit.FONT_NOTE)
var _effects := UiKit.label("", UiKit.FONT_NOTE, Color("9fd8ff"))
var world_table := false            # 骰盤放在遊戲世界裡戰場旁（use_world_table）：不蓋中間、不變暗，鏡頭轉過去
var tray_right := Vector3.RIGHT     # 螢幕右邊在地面上的方向（骰盤擺在戰場右邊）
var tray_yaw := 0.0                 # 骰盤轉多少才正對遊戲的鏡頭
const EDGE_INSET := 1.0              # 骰盤不超出地圖外框往內這麼多：外框外的墓碑、樹、外框岩石合併成一個網格，壓不平
const CUT_MARGIN := 0.3              # 壓平的範圍比台座每邊多一點（斜切過邊界的三角形藏進台座）
var _table_box: CenterContainer
var _roll_only: Array[Control] = []   # 擲骰的字、計時條、按鈕、結果：骰盤在遊戲世界時，倒數只留結果總覽（鏡頭回到角色，看得到配置）
var _dim: Control
var _summary := UiKit.label("", UiKit.FONT_NOTE, Color(1, 1, 1, 0.92))   # 結果總覽：大家都擲完、倒數時列每個人的右鍵與效果
var _cands := HBoxContainer.new()
var _count := UiKit.label("", 150, UiKit.GOLD, 6)
var _banner := UiKit.label("", 64, UiKit.GOLD, 5)
var _stakes := UiKit.label("", 64, UiKit.GOLD, 5)   # 醞釀時畫面上方：「再一顆 旋風斬 → 強化！」，揭曉換成中了 / 差一點
var _vignette := TextureRect.new()                  # 醞釀時四周壓暗
var _suspense_a := 0.0                              # 醞釀畫面淡入的程度（0~1）
var _reward_box := VBoxContainer.new()
var _reward_cards := HBoxContainer.new()
var _reward_title := UiKit.label("", UiKit.FONT_HEADING, UiKit.GOLD)
var _inspect_faces := HBoxContainer.new()   # 獎勵卡下面一條：你帶的 6 顆各自攤平 6 面（3 × 2）；指著新骰子 / 新武器卡時後面多那顆
# （YangHsu 2026-11-24 照 Claude 的評估：原本上面還有一排可以拖著轉的 3D 骰子，跟攤平的 6 面重複，只留攤平：一眼看完）
var _faces_key: Array = []
var _painted_hover := -2           # 卡片上次照哪一張畫的（_hover_offer 變了就重畫：滑鼠、鍵盤、程式設的都跟上）
var _hover_offer := -1               # 滑鼠指著第幾張獎勵卡（-1 = 沒有）：指著新骰子 / 新武器才在骰子那排後面放那張卡的骰子
var _carve_box := VBoxContainer.new()
var _carve_title := UiKit.label("", UiKit.FONT_HEADING, UiKit.GOLD)
var _carve_skills := HBoxContainer.new()
var _carve_rows := VBoxContainer.new()
var _carve_hint := UiKit.label("", UiKit.FONT_NOTE, Color(1, 1, 1, 0.75))
var _carve_views: Array[DieView] = []   # 6 顆 × 6 面，index = 第幾顆 × 6 + 第幾面
var _carve_skill := -1            # 刻技能面：本機選了第幾個候選（還沒選 = -1，面不能點）
var _carve_key := {}
var _status := UiKit.label("", UiKit.FONT_NOTE, Color(1, 1, 1, 0.9))
var _dice: Array[DieView] = []

var phase: StringName = &""
var my_turn := false
var _seen_seq := -1
var _spin_t := 99.0               # 這次擲出去後經過幾秒（大於最後一顆停下的時間 = 不在轉）
var _spinning: Array[bool] = []
var _banner_t := 0.0
var _contest_seen := -1             # 看過的 DiceRun.contest_seq（多人暗選撞到、比骰子：變了就跳橫幅）
var _show_key := ""                 # 揭曉過的那一次擲（peer|roll_seq）：每次擲完揭曉一次
var _show_queue: Array = []         # 揭曉的音效排程：[第幾秒, 音效, 音高]
var _show_t := 0.0
var _fight_t := 0.0
var _cand_key := []
var _offer_key := []
var _picked := false
var _last_phase: StringName = &""
# 物理擲骰（DiceTable）：main.gd 開 physics；擲法看設定頁 dice_cup（骰盅 / 蓄力條，即時切換）
var physics := false
var _gui_press := false          # 這一下左鍵按在面板的控制項上（放開也不轉給骰盤）
var _warming := false            # 開場預熱中：骰盤露出來（warm_up / end_warm_up）
var settings: SettingsPanel
var hints: Hints                  # HUD 給：操作說明只教一次，看過的記在同一份紀錄（重新顯示提示會再教）
var _teaching := {}               # 這一段（擲骰 / 獎勵 / 刻面）正在教的說明 id：第一次出現就記成看過，這一段結束前照樣顯示
var table := DiceTable.new()
var _charge_bg := UiKit.rect(Color(1, 1, 1, 0.12), Vector2(420, 14))
var _charge_fill := UiKit.rect(Color("ffd84a"))
var _pending_throw := false       # 桌子丟出去、OP_DICE_ROLL 送了還沒看到 roll_seq +1
var _table_seq := -1              # 桌子處理過的 roll_seq（變了又不是自己丟的 = 時間到自動擲，桌子跟著丟）
var _table_round := ""            # 這一輪擲骰（場次 / 輪到誰 / 花次數）：變了桌子重排


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := UiKit.rect(DIM)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim = dim
	_overlay.add_child(dim)
	add_child(_overlay)

	_roll_box.add_theme_constant_override(&"separation", 16)
	_roll_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_roll_box.set_anchors_preset(Control.PRESET_CENTER)
	_roll_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_roll_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_roll_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for l: Label in [_title, _hint, _result, _result_sub, _effects, _summary]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_roll_box.add_child(_title)
	var timer := CenterContainer.new()
	timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer.add_child(_timer_bg)
	_timer_bg.add_child(_timer_fill)
	_roll_box.add_child(timer)
	var table_box := CenterContainer.new()
	_table_box = table_box
	table_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table_box.add_child(table)
	_roll_box.add_child(table_box)
	table.visible = false
	table.thrown.connect(func() -> void:
		_pending_throw = true
		op_requested.emit([InputCmd.OP_DICE_ROLL]))
	table.settled.connect(func(faces: Array) -> void: op_requested.emit([InputCmd.OP_DICE_FACES] + faces))
	table.die_clicked.connect(func(i: int) -> void: op_requested.emit([InputCmd.OP_DICE_LOCK, i]))
	table.clacked.connect(func(g: float) -> void: sfx.emit("diceClack", g, 1.0))
	var charge_box := CenterContainer.new()
	charge_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	charge_box.add_child(_charge_bg)
	_charge_bg.add_child(_charge_fill)
	_roll_box.add_child(charge_box)
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
	for b: Button in [_btn_roll, _btn_reroll, _btn_done]:   # 擲法（骰盅 / 蓄力條）是偏好，在設定頁（YangHsu 2026-11-24）
		chip_button(b)
		btns.add_child(b)
		if b == _btn_reroll:
			_reroll_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btns.add_child(_reroll_chip)
	_btn_roll.pressed.connect(_press_throw)
	_btn_reroll.pressed.connect(_press_throw)
	_btn_done.pressed.connect(func() -> void: op_requested.emit([InputCmd.OP_DICE_DONE]))
	_roll_box.add_child(btns)
	_roll_box.add_child(_result)
	_roll_box.add_child(_result_sub)
	_cands.add_theme_constant_override(&"separation", 10)
	_cands.alignment = BoxContainer.ALIGNMENT_CENTER
	_cands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roll_box.add_child(_cands)
	_roll_box.add_child(_effects)
	_roll_box.add_child(_summary)
	_roll_only = [_title, timer, _hint, btns, _result, _result_sub, _cands, _effects]
	_overlay.add_child(_roll_box)

	_reward_box.add_theme_constant_override(&"separation", 20)
	_reward_box.set_anchors_preset(Control.PRESET_CENTER)
	_reward_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_reward_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_reward_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reward_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reward_box.add_child(_reward_title)
	_reward_cards.add_theme_constant_override(&"separation", 18)
	_reward_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_reward_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reward_box.add_child(_reward_cards)
	_inspect_faces.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect_faces.alignment = BoxContainer.ALIGNMENT_CENTER
	_inspect_faces.add_theme_constant_override(&"separation", 18)
	_reward_box.add_child(_inspect_faces)
	_overlay.add_child(_reward_box)

	# 刻面：選了刻技能 / 刻效果的卡之後，點這場帶的 6 顆骰子的其中一面（空白面金框，是建議刻的地方）
	_carve_box.add_theme_constant_override(&"separation", 14)
	_carve_box.set_anchors_preset(Control.PRESET_CENTER)
	_carve_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_carve_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_carve_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for l: Label in [_carve_title, _carve_hint]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_carve_box.add_child(_carve_title)
	_carve_skills.add_theme_constant_override(&"separation", 12)
	_carve_skills.alignment = BoxContainer.ALIGNMENT_CENTER
	_carve_skills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_carve_box.add_child(_carve_skills)
	_carve_rows.add_theme_constant_override(&"separation", 8)
	_carve_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for d in DiceDefs.DICE_COUNT:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 6)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for f in DiceDefs.FACES:
			var v := DieView.new(d * DiceDefs.FACES + f, CARVE_DIE)
			v.clicked.connect(_on_carve_face)
			_carve_views.append(v)
			row.add_child(v)
		_carve_rows.add_child(row)
	_carve_box.add_child(_carve_rows)
	_carve_box.add_child(_carve_hint)
	_overlay.add_child(_carve_box)

	var vg := GradientTexture2D.new()
	vg.fill = GradientTexture2D.FILL_RADIAL
	vg.fill_from = Vector2(0.5, 0.5)
	vg.fill_to = Vector2(1.05, 0.5)
	vg.gradient = Gradient.new()
	vg.gradient.set_color(0, Color(0, 0, 0, 0))
	vg.gradient.set_color(1, Color(0, 0, 0, 0.7))
	vg.gradient.add_point(0.55, Color(0, 0, 0, 0))
	_vignette.texture = vg
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.visible = false
	add_child(_vignette)
	_stakes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stakes.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 110)
	_stakes.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stakes.visible = false
	add_child(_stakes)
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


# 骰子模式的遊戲畫面（main.gd）：骰盤放進遊戲的 3D 世界、擺在戰場旁，用遊戲的鏡頭看；擲骰的字與按鈕移到畫面下方
func use_world_table(parent: Node3D, cam: Camera3D, right: Vector3, yaw: float) -> void:
	world_table = true
	tray_right = right
	tray_yaw = yaw
	table.use_world(parent, cam)
	_table_box.visible = false
	_roll_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24)
	_roll_box.grow_vertical = Control.GROW_DIRECTION_BEGIN


# 骰子模式的大字要預熱的（HUD.set_loading）：[文字, 字級, 描邊]。倒數與「開打！」「清場！」150 號、中獎橫幅 64 號
# （網頁版：大字第一次出現才產生字形，會卡一下；只放會出現的字，大字級整段全放太佔貼圖）
static func warm_big_text() -> Array:
	var banner := "你隊友擲出個！＋　比骰子「」：·→拿到0123456789再一顆差一點……中了？"
	for t: Dictionary in DiceDefs.TIERS:
		banner += t.name
	for c: StringName in DiceDefs.COMBOS:
		banner += DiceDefs.COMBOS[c].name
	for weapon: StringName in DiceDefs.WEAPON_DICE:
		for face: StringName in DiceDefs.weapon_die(weapon):
			if face != DiceDefs.BLANK and not DiceDefs.is_effect(face):
				banner += DiceDefs.name_of(face)
	return [["123開打！清場", 150, 6], [banner, 64, 5]]


# 開場預熱（main.gd 跟 WorldView.warm_up 一起）：骰盤擺到 center 露出來、骰面畫上 faces（字也先產生）、獎勵畫面那排骰子藏著先畫，預熱完收起來
func warm_up(center: Vector3, faces: Array, weapon_id: StringName) -> void:
	if not world_table:
		return
	_warming = true
	table.set_faces(faces, weapon_id)
	table.set_origin(Transform3D(Basis(Vector3.UP, tray_yaw), center))
	table.warm_up(true)


func end_warm_up() -> void:
	if not _warming:
		return
	_warming = false
	table.warm_up(false)


# 骰盤擺哪：地圖有擲骰台（MapGen._place_dice_spots，每塊打怪的區域旁邊一格牆外的空小格）就用離中心最近、不壓到霧牆與出口的那一塊；
# 沒有（固定地圖、測試場）或都太遠才臨時找：有霧牆就在圈外，沒有（逛地圖花次數擲）就在擲的人旁邊；轉成正對鏡頭
# 臨時找：圍著中心試幾個方向與距離（右邊優先），優先擺在牆外：底下的牆、墓碑、樹在擲骰時壓平（ArenaView.update_cut），
# 牆外角色與怪走不到，不會被蓋住；避開蓋到戰場、出口、地圖外框外、地面高低差太大的；每台照同樣的地形算，擺的位置一樣
func tray_transform(world: World, dice: DiceRun, p: Player) -> Transform3D:
	var anchor := dice.arena_center if dice.arena_radius > 0.0 else (p.pos if p != null else Vector2.ZERO)
	var near := (dice.arena_radius if dice.arena_radius > 0.0 else 2.0) + DiceTable.PLINTH.y / 2.0 + 0.5
	var right := Vector2(tray_right.x, tray_right.z)
	var up := Vector2(-right.y, right.x)
	var avoid := _tray_avoid(world)
	var edges: Array[Dictionary] = world.terrain.blocks.slice(0, world.map.get("edge_blocks", 0))
	var best := Vector2.ZERO
	var best_score := INF
	var best_ground := 0.0
	# 地圖的擲骰台（整張地圖一個，YangHsu 2026-11-20）：每一場都擺那裡
	var spots: Array = world.map.get("dice_spots", [])
	if not spots.is_empty():
		var at := MapDefs.to_world(world.map, spots[0])
		var r := _tray_score(world, at, right, up, anchor, dice.arena_radius, avoid, edges)
		return Transform3D(Basis(Vector3.UP, tray_yaw), Vector3(at.x, r[1] + DiceDefs.TRAY_LIFT, at.y))
	# 沒有擲骰台的地圖（測試場、固定地圖）才在霧牆外臨時找
	for dist: float in [1.0, 1.35]:
		for dir: Vector2 in [right, -right, up, -up, (right + up).normalized(), (right - up).normalized(), (-right + up).normalized(), (-right - up).normalized()]:
			var reach := near + absf(dir.dot(right)) * (DiceTable.PLINTH.x - DiceTable.PLINTH.y) / 2.0   # 往左右擺要多讓半張桌子的長邊
			var at := anchor + dir * reach * dist
			var r := _tray_score(world, at, right, up, anchor, dice.arena_radius, avoid, edges)
			if r[0] < best_score - 0.01:
				best_score = r[0]
				best = at
				best_ground = r[1]
	return Transform3D(Basis(Vector3.UP, tray_yaw), Vector3(best.x, best_ground + DiceDefs.TRAY_LIFT, best.y))


# 骰盤不該蓋住的東西：[位置, 半徑]（出口的門、挖墳點；門在邊界的牆上，牆外擺骰盤時會碰到）
static func _tray_avoid(world: World) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for d: Dictionary in DigEvent.doors(world):
		var at := MapDefs.to_world(world.map, d.at)
		out.append(Vector3(at.x, at.y, 3.0))
	if DigEvent.enabled(world):
		out.append(Vector3(world.event.point.x, world.event.point.y, 3.0))
	return out


# 骰盤（連台座）擺在 at：底下每 1.5 取一點，[分數, 最高的地面（畫面上的：牆與墓碑不算，會被壓平；地圖邊界那圈畫成 BlockDressing.BANK_H 高的土坡）]
# 分數（每個取樣點）：蓋到戰場 6、蓋到出口 4、超出地圖外框 1、走得到的地面 1（牆外擺得下就擺牆外）、高低差超過一階每階 0.5
static func _tray_score(world: World, at: Vector2, right: Vector2, up: Vector2, arena: Vector2, arena_radius: float, avoid: Array[Vector3], edges: Array[Dictionary]) -> Array:
	var score := 0.0
	var top := -INF
	var low := INF
	var half := DiceTable.PLINTH / 2.0
	var ring := arena_radius + 0.3
	var x := -half.x
	while x <= half.x + 0.01:
		var y := -half.y
		while y <= half.y + 0.01:
			var pt := at + right * x + up * y
			if arena_radius > 0.0 and pt.distance_squared_to(arena) < ring * ring:
				score += 6.0
			for a in avoid:
				if pt.distance_squared_to(Vector2(a.x, a.y)) < a.z * a.z:
					score += 4.0
					break
			if absf(pt.x) > world.half_extents.x - EDGE_INSET or absf(pt.y) > world.half_extents.y - EDGE_INSET:
				score += 1.0
			elif not world.terrain.blocks_nav(pt, 0.0):
				score += 1.0
			var g := world.terrain.floor_at(pt)
			for b in edges:
				if pt.x >= b.min.x and pt.x <= b.max.x and pt.y >= b.min.y and pt.y <= b.max.y:
					g = maxf(g, BlockDressing.BANK_H)
					break
			top = maxf(top, g)
			low = minf(low, g)
			y += 1.5
		x += 1.5
	if top - low > Config.HEIGHT.step:
		score += 0.5 * (top - low) / Config.HEIGHT.step
	return [score, top]


# 換關時（main.gd）：台座的石頭照這一層的牆配色
func set_ground_theme(theme: StringName) -> void:
	var style := BlockDressing.palette(theme)
	if not style.is_empty():
		var c: Array = style.blocks[&"wall"]
		table.set_plinth_colors(c[0], c[1])


# 擲骰時骰盤（連台座）佔的地面：{center, right（桌子長邊的方向）, half, floor（地面高）}，ArenaView 把這塊上面的地形壓平；
# 沒顯示（或預熱中）回傳 null
func tray_cut() -> Variant:
	if not world_table or _warming or not table.is_shown():
		return null
	var t := table.origin()
	return {"center": Vector2(t.origin.x, t.origin.z), "right": Vector2(t.basis.x.x, t.basis.x.z).normalized(),
		"half": DiceTable.PLINTH / 2.0 + Vector2(CUT_MARGIN, CUT_MARGIN), "floor": t.origin.y - DiceDefs.TRAY_LIFT}


# 鏡頭該看哪裡（main.gd）：擲骰時看骰盤（放慢時看那一顆），其他時候 null（照舊跟著自己）
# 倒數也回到自己：3、2、1 是讓玩家看清楚角色與怪的配置（許家慶 2026-11-24）
func camera_focus() -> Variant:
	if not world_table or not visible or phase != DiceRun.ROLL:
		return null
	var f: Variant = table.focus_point()
	if f != null:   # 不直接對準那顆：在牆邊時骰盤會被推出畫面，看起來像往旁邊滑
		return table.center().lerp(f, DiceDefs.SUSPENSE_CAM_TOWARD)
	return table.center() - Vector3.UP.cross(tray_right) * DiceDefs.TRAY_SCREEN_UP   # 鏡頭對準骰盤下面一點：骰盤在畫面偏上，下方留給擲骰的字與按鈕


# 放進遊戲世界時：滑鼠事件轉給骰盤。按在面板上點得到的東西（按鈕、下排骰子、技能候選）的不轉，那一下的放開也不轉
# （按鈕放開才觸發：只放過按下、放開被骰盤吃掉，按鈕就點不了）
func _input(event: InputEvent) -> void:
	if not world_table or not visible or phase != DiceRun.ROLL or not (event is InputEventMouse):
		_gui_press = false
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_gui_press = _control_at(self, event.position)
		elif _gui_press:
			_gui_press = false
			return
	if _gui_press:
		return
	if table.world_input(event):
		get_viewport().set_input_as_handled()


# at 落在 node 底下看得到、收滑鼠的控制項上（擲骰時整片底圖不收滑鼠，落在空的地方 = 指著骰盤）
# 照座標找、不看 hover：滑鼠沒先移過去就按下時 hover 還是舊的
func _control_at(node: Node, at: Vector2) -> bool:
	for c in node.get_children():
		var ctl := c as Control
		if ctl == null or not ctl.visible:
			continue
		if ctl != _overlay and ctl.mouse_filter != Control.MOUSE_FILTER_IGNORE and ctl.get_global_rect().has_point(at):
			return true
		if _control_at(ctl, at):
			return true
	return false


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
		_teaching.clear()
		if phase == DiceRun.FIGHT and (_last_phase == DiceRun.COUNTDOWN or _last_phase == DiceRun.EXPLORE):
			_fight_t = FIGHT_FLASH   # 倒數完閃「開打！」
		if phase == DiceRun.REWARD:
			_picked = false
		if phase == DiceRun.ROLL:
			_table_round = ""
			if world_table:   # 每次進擲骰擺一次（同一輪換人不搬，大家看同一個骰盤）
				var tp := dice.current(world)
				table.set_origin(tray_transform(world, dice, tp if tp != null else me))
		_last_phase = phase
	var rolling := phase == DiceRun.ROLL
	var rewarding := phase == DiceRun.REWARD and not s.offers.is_empty() and not _picked
	var carving := phase == DiceRun.REWARD and not s.carve.is_empty()
	_overlay.visible = rolling or phase == DiceRun.COUNTDOWN or rewarding or carving
	if world_table:   # 骰盤在遊戲世界裡：擲骰、倒數時不變暗、不擋滑鼠（滑鼠要點到骰盤）；倒數時骰盤收起來（鏡頭回到角色）
		var on_field := rolling or phase == DiceRun.COUNTDOWN
		_dim.visible = not on_field
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE if on_field else Control.MOUSE_FILTER_STOP
		table.set_shown(rolling or _warming)
	_roll_box.visible = rolling or phase == DiceRun.COUNTDOWN
	_reward_box.visible = rewarding and not carving
	_carve_box.visible = carving
	if carving:
		_show_carve(s, me)
	elif not _carve_key.is_empty():
		_carve_key = {}
		_carve_skill = -1
	var turn_player := dice.current(world)
	my_turn = turn_player == me
	if _roll_box.visible:
		_show_roll(world, dice, turn_player if turn_player != null else me, dt)
		if world_table:   # 倒數只留結果總覽；骰子列、蓄力條 _show_roll 每幀重設，所以放在它後面
			var counting := phase == DiceRun.COUNTDOWN
			for c in _roll_only:
				c.visible = not counting
			if counting:
				_dice_row.visible = false
				_charge_bg.get_parent().visible = false
	_show_stakes(dt)
	if rewarding:
		_reward_title.text = "走進門的獎勵：選一個" if dice.door_pick else "選一個獎勵"   # 重擲券 +1 是清場時一枚籌碼飛進右下（DiceProps.fly_ticket）
		var how := _teach(&"dice_reward_keys", "（點卡片、按數字鍵，或 A / D 選再按 F）")
		if dice.shared:
			how += ("\n" if how != "" else "") + _teach(&"dice_shared_pick", "大家暗選，撞到同一個就比骰子，輸的隨機拿沒人選的")
		_reward_title.text += how
		_show_offers(s, me)
		if _painted_hover != _hover_offer:
			_paint_cards()
		_show_inspect(dice, s, me)
	_show_contest(world, dice, me)
	_play_show(dt)
	_show_count(dice, dt)
	_show_banner(dt)
	var waiting_mates := phase == DiceRun.REWARD and dice.shared and _picked and s.carve.is_empty()
	_status.visible = waiting_mates   # 右鍵、效果、重擲券改成右下的牌與籌碼（DiceProps）
	_status.text = "選好了，等隊友選……"


# 擲骰畫面：畫正在擲的那位（多人時大家看同一個人）
func _show_roll(world: World, dice: DiceRun, p: Player, dt: float) -> void:
	var s := dice.seat_of(p)
	var who := "你" if my_turn else _player_name(world, null, p.peer_id)
	_summary.text = summary_text(world, dice, p) if phase == DiceRun.COUNTDOWN else ""
	if phase != DiceRun.ROLL:
		_title.text = "全部擲完了"
	else:
		_title.text = "輪到%s擲骰" % who   # 第幾場、一般 / 菁英在上方階段條與遭遇卡，武器在左下角色卡
	_timer_fill.size = Vector2(_timer_bg.custom_minimum_size.x * clampf(dice.timer / DiceDefs.ROLL_TIME, 0.0, 1.0), _timer_bg.custom_minimum_size.y)
	_timer_fill.visible = phase == DiceRun.ROLL and not dice.waiting
	table.visible = physics
	_dice_row.visible = not physics
	_charge_bg.get_parent().visible = physics and not table.cup_mode
	if physics:
		_sync_table(world, dice, p, s)
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
	spinning_any = spinning_any or (physics and (dice.waiting or table.replaying or table.holding() or table.state == DiceTable.State.ROLLING))
	if not s.rolled or spinning_any:
		_result.text = ""
		_result_sub.text = _teach(&"dice_rules", "同一招骰到越多個越強；效果面全部疊上去；灰色是別的武器的技能，當空白") if not s.rolled else ""
		_effects.text = ""
		_set_cands([], p)
	else:
		_result.text = ""   # 右鍵、威力、組合、效果在右下的牌與籌碼（擲骰時也擺著），中獎另有橫幅
		_result_sub.text = ""
		_effects.text = ""
		_set_cands(res.cands if my_turn and res.cands.size() > 1 else [], p)
		var key := "%d|%d" % [p.peer_id, s.roll_seq]
		if key != _show_key and s.roll_seq > 0:
			_show_key = key
			_start_show(world, p, res)
	var busy := spinning_any or dice.settle > 0.0
	_btn_roll.visible = not s.rolled
	_btn_roll.text = "自動丟（R）" if physics else "擲骰（空白鍵）"
	_btn_reroll.visible = s.rolled
	_reroll_chip.visible = s.rolled
	_show_reroll_chip(s.rerolls, dice.charges_of(p))
	_btn_roll.disabled = not my_turn or busy or phase != DiceRun.ROLL
	_btn_reroll.disabled = not my_turn or busy or not dice.can_reroll(p) or not s.locked.has(false) or phase != DiceRun.ROLL
	_btn_done.disabled = not my_turn or busy or not s.rolled or phase != DiceRun.ROLL
	if phase != DiceRun.ROLL:
		_hint.text = ""
	elif not my_turn:
		_hint.text = "隊友擲骰中"
	elif physics and dice.waiting:
		_hint.text = ""
	elif not s.rolled and physics:
		_hint.text = _teach(&"dice_throw", "按住滑鼠拿起骰盅、甩一甩，放開就丟出去" if table.cup_mode else "按住滑鼠或空白鍵蓄力，放開就丟")
	elif not s.rolled:
		_hint.text = _teach(&"dice_throw", "按擲骰，6 顆一起擲")
	elif s.rerolls > 0:
		_hint.text = _teach(&"dice_keep", "點骰子拿到後面的保留區，剩下的再丟一次" if physics else "點骰子鎖住想留的，再重擲其他的")
	else:
		_hint.text = ""   # 計時條就是倒數；重擲要花券寫在按鈕上


# 重擲按鈕旁的籌碼：免費的還有就寫「免費 ×N」（金），用完了寫「券 ×N」（紫，跟右下的重擲券同色，0 張變淡）；有變才重建
func _show_reroll_chip(free: int, charges: int) -> void:
	var tip := "免費重擲還有 %d 次" % free if free > 0 else "免費重擲用完了：再丟要花 1 張重擲券（剩 %d 張）" % charges
	if tip == reroll_chip_text:
		return
	reroll_chip_text = tip
	for c in _reroll_chip.get_children():
		c.queue_free()
	var color := UiKit.GOLD.darkened(0.2) if free > 0 else (DiceProps.TICKET_CHIP if charges > 0 else Color(DiceProps.TICKET_CHIP, 0.4))
	_reroll_chip.add_child(DiceProps.Chip.new("免費 ×%d" % free if free > 0 else "券 ×%d" % charges, null, color, tip))


# 只教一次的說明：沒看過就記成看過並回傳 text，這一段（同一個階段）結束前照樣回傳；看過的回傳 ""
# 沒有 hints（檢查只建 DicePanel）就一直顯示
func _teach(id: StringName, text: String) -> String:
	if hints == null or _teaching.has(id):
		return text
	if hints.is_seen(id):
		return ""
	hints.mark_seen(id)
	_teaching[id] = true
	return text


# 物理擲骰：桌子跟著模擬層（骰面、保留區、能不能丟）；模擬層自己擲的（時間到）桌子跟著丟；模擬層的面跟桌子不一樣（逾時自己抽）就把桌上的骰子擺成那一面
func _sync_table(_world: World, dice: DiceRun, p: Player, s: DiceRun.Seat) -> void:
	table.cup_mode = settings == null or settings.values.get("dice_cup", true)
	var round_key := str(dice.turn)   # 進擲骰階段時 refresh 把 _table_round 清掉：每次新的擲骰、換人擲都重排
	# 上一位的錄影還在播（錄影晚一點才到，他停好馬上按完成）：播完才換下一位（骰面也先不換），不然看的人只看到一半
	if round_key != _table_round and table.replaying:
		return
	if round_key != _table_round and phase == DiceRun.ROLL:
		_table_round = round_key
		_pending_throw = false
		_table_seq = s.roll_seq
		table.reset_round()
	table.set_faces(s.pool, p.weapon_id)
	if s.roll_seq != _table_seq:
		if not _pending_throw and dice.waiting and my_turn:
			table.auto_throw(randf_range(0.45, 0.9))   # 時間到、模擬層自己擲：輪到的人的桌子照樣丟一次（隊友的桌子播他的錄影）
		_pending_throw = false
		_table_seq = s.roll_seq
	var kept: Array[bool] = []
	for i in s.locked.size():
		kept.append(s.locked[i] and s.rolled)   # 重擲時（waiting）留著的也要待在保留區
	table.set_kept(kept, s.face)
	if s.rolled and not dice.waiting and table.state == DiceTable.State.SETTLED:
		table.match_faces(s.face)
	elif s.rolled and not dice.waiting and not my_turn and not table.replaying and table.state == DiceTable.State.IDLE:
		table.match_faces(s.face)   # 隊友擲的錄影沒收到（斷線、房主逾時自己抽）：直接擺成房主的面
	var idle := phase == DiceRun.ROLL and my_turn and not dice.waiting and dice.settle <= 0.0
	table.can_throw = idle and (not s.rolled or (dice.can_reroll(p) and s.locked.has(false)))
	table.can_pick = idle and s.rolled and dice.can_reroll(p)
	_charge_fill.size = Vector2(_charge_bg.custom_minimum_size.x * table.charge, _charge_bg.custom_minimum_size.y)
	_charge_fill.visible = table.charging


# 按鈕或鍵盤丟：物理擲骰時桌子自動丟一次（力道隨機），否則直接送 OP_DICE_ROLL
func _press_throw() -> void:
	if not physics:
		op_requested.emit([InputCmd.OP_DICE_ROLL])
	elif table.can_throw and table.state != DiceTable.State.ROLLING:
		table.auto_throw(randf_range(0.45, 0.9))


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
	elif phase == DiceRun.CLEAR:
		_count.text = "清場！"
	else:
		_count.text = ""


# 結果總覽（倒數 3、2、1 的時候）：每位這次有擲的人一行「你 / P2：旋風斬 ×3 強化 ×2.6 · 傷害 +20%」
func summary_text(world: World, dice: DiceRun, me: Player) -> String:
	var lines: Array[String] = []
	for q in world.player_list:
		var s: DiceRun.Seat = dice.states.get(q.peer_id)
		if s == null or not s.rolled or not dice.can_roll(q):
			continue
		var res: Dictionary = s.result
		var head := _player_name(world, me, q.peer_id) if q != me else "你"
		var skill := "沒中" if res.is_empty() or res.count <= 0 else "%s ×%d %s ×%s" % [DiceDefs.name_of(res.skill), res.count, DiceDefs.tier_of(res.tier_count).name, str(DiceDefs.tier_of(res.tier_count).mul)]
		var fx := effects_text(res.get("effects", {}), " · ")
		lines.append("%s：%s%s%s" % [head, skill, combos_text(res.get("combos", []), " · "), (" · " + fx) if fx != "" else ""])
	return "\n".join(lines)


# 揭曉（每次擲完一次）：每個中的技能面叮一聲、一聲比一聲高；強化以上或中了組合 → 中獎音效 + 橫幅「你擲出 3 個旋風斬！」；
# 差一顆就強化 → 可惜的音效。畫面震動與全隊亮起是模擬層的事件（dice:glow、camera:shake），每台都會收到
func _start_show(world: World, p: Player, res: Dictionary) -> void:
	_show_queue.clear()
	_show_t = 0.0
	var t := 0.0
	for k in res.count:
		_show_queue.append([t, "diceTick", 1.0 + DiceDefs.SHOW_TICK_PITCH * k])
		t += DiceDefs.SHOW_TICK_GAP
	var names: Array[String] = []
	for c: StringName in res.combos:
		names.append(DiceDefs.COMBOS[c].name)
	if res.tier_count >= 3 or not names.is_empty():
		_show_queue.append([t + 0.05, "diceWin", 1.0])
		var who := "你" if my_turn else _player_name(world, null, p.peer_id)
		var head := "%s擲出 %d 個%s！" % [who, res.count, DiceDefs.name_of(res.base)] if res.count >= 3 else "%s擲出%s！" % [who, "＋".join(names)]
		if res.count >= 3 and not names.is_empty():
			head += "　%s" % "＋".join(names)
		_banner.text = head
		_banner_t = BANNER_TIME
	elif res.count == 2:
		_show_queue.append([t + 0.05, "diceMiss", 1.0])


# 醞釀（DiceTable 盯著最後一顆）：下面的字與按鈕淡出（推近時會壓在骰子上）、四周壓暗、上方寫賭注，停好那一拍寫中了沒
func _show_stakes(dt: float) -> void:
	var st := table.stake() if phase == DiceRun.ROLL and physics else {}
	_suspense_a = move_toward(_suspense_a, 1.0 if not st.is_empty() else 0.0, dt / 0.25)
	_roll_box.modulate.a = 1.0 - _suspense_a
	_vignette.visible = _suspense_a > 0.0
	_vignette.modulate.a = _suspense_a
	_stakes.visible = _suspense_a > 0.0 and not st.is_empty()
	if st.is_empty():
		return
	var need := DiceDefs.tier_of(st.have + 1).name as String
	match st.hit:
		1:
			_stakes.text = "中了！%d 個%s → %s！" % [st.have + 1, DiceDefs.name_of(st.face), need]
			_stakes.add_theme_color_override(&"font_color", UiKit.GOLD)
		0:
			_stakes.text = "差一點……"
			_stakes.add_theme_color_override(&"font_color", Color(0.8, 0.8, 0.8))
		_:
			_stakes.text = "再一顆%s → %s！" % [DiceDefs.name_of(st.face), need]
			_stakes.add_theme_color_override(&"font_color", UiKit.GOLD)
	_stakes.modulate.a = _suspense_a


func _play_show(dt: float) -> void:
	if _show_queue.is_empty():
		return
	_show_t += dt
	while not _show_queue.is_empty() and _show_queue[0][0] <= _show_t:
		var q: Array = _show_queue.pop_front()
		sfx.emit(q[1], 1.0, q[2])


# 獎勵畫面的骰子：你帶的 6 顆；滑鼠指著「新骰子」「新武器」卡時後面接那張卡的骰子（還沒選，只是看看會拿到什麼；YangHsu 2026-11-20：還沒選就出現新骰子很怪）
# 新骰子標出會換掉哪顆、箭頭指向它；都能拿起來轉，底下攤平 6 面
func _show_inspect(dice: DiceRun, s: DiceRun.Seat, me: Player) -> void:
	var extras := []
	var replace := -1
	if _hover_offer >= 0 and _hover_offer < s.offers.size():
		var o: Dictionary = s.offers[_hover_offer]
		if o.kind == &"die":
			extras.append([o.faces, me.weapon_id, "選這張會拿到"])
			replace = dice.most_blank_slot(s)
		elif o.kind == &"weapon":
			extras.append([o.faces, o.get("base", me.weapon_id), "新武器的骰子"])
	_show_flat_faces(s.pool, me.weapon_id, extras, replace)


# 每顆攤平 6 面（3 × 2，跟卡片上的小方塊同一種畫法），上面一行小字：會被換掉的那顆（紅框）、獎勵的骰子（金框）
func _show_flat_faces(carried: Array, weapon_id: StringName, extras: Array, replace: int) -> void:
	var all := []
	for i in carried.size():
		all.append([carried[i], weapon_id, "會被換掉" if i == replace else ""])
	for e: Array in extras:
		all.append(e)
	if all == _faces_key:
		return
	_faces_key = all.duplicate(true)
	for c in _inspect_faces.get_children():   # 先拿出容器再釋放：留到幀尾才走的話，這一幀排版還算著舊的那幾顆
		_inspect_faces.remove_child(c)
		c.queue_free()
	for i in all.size():
		var col := VBoxContainer.new()
		col.add_theme_constant_override(&"separation", 4)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tag: String = all[i][2]
		var tag_color := Color("ff7a6a") if tag == "會被換掉" else UiKit.GOLD
		var l := UiKit.label(tag, 16, tag_color)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size.y = 22
		col.add_child(l)
		var frame := PanelContainer.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_theme_stylebox_override(&"panel", _card_box(tag_color if tag != "" else Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override(&"h_separation", int(FLAT_GAP))
		grid.add_theme_constant_override(&"v_separation", int(FLAT_GAP))
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for f: StringName in all[i][0]:
			var m := DieView.new(-1, FLAT_SIDE)
			m.show_face(f, all[i][1], false, false)
			grid.add_child(m)
		frame.add_child(grid)
		col.add_child(frame)
		_inspect_faces.add_child(col)


# 檢查用：攤平的有幾顆、第 i 顆上面寫什麼
func flat_count() -> int:
	return _flat_cols().size()


func flat_tag(i: int) -> String:
	return (_flat_cols()[i].get_child(0) as Label).text


func _flat_cols() -> Array:
	return _inspect_faces.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())


# 檢查用：第 i 顆底下攤平的 6 面
func flat_faces_of(i: int) -> Array:
	var out := []
	for m: DieView in _flat_cols()[i].get_child(1).get_child(0).get_children():
		out.append(m.face)
	return out


# 多人暗選揭曉、有撞到的：跳橫幅寫誰擲幾點、誰拿到（「比骰子「藍骰」：你 5 · P2 3 → 你拿到」）
func _show_contest(world: World, dice: DiceRun, me: Player) -> void:
	if dice.contest_seq == _contest_seen:
		return
	var first := _contest_seen < 0
	_contest_seen = dice.contest_seq
	if first or dice.contests.is_empty():
		return
	var lines: Array[String] = []
	for c: Array in dice.contests:
		var rolls: Array[String] = []
		for peer_id: int in c[1]:
			rolls.append("%s %d" % [_player_name(world, me, peer_id), c[1][peer_id]])
		lines.append("比骰子「%s」：%s → %s拿到" % [c[0], " · ".join(rolls), _player_name(world, me, c[2])])
	_banner.text = "\n".join(lines)
	_banner_t = BANNER_TIME


static func _player_name(world: World, me: Player, peer_id: int) -> String:
	if me != null and peer_id == me.peer_id:
		return "你"
	var p: Player = world.players.get(peer_id)
	return "P%d" % (world.player_list.find(p) + 1) if p != null else "隊友"


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
	_hover_offer = -1
	for c in _reward_cards.get_children():
		c.queue_free()
	for i in s.offers.size():
		_reward_cards.add_child(_offer_card(i, s.offers[i], me))
	_painted_hover = -2   # 新的卡還沒畫過選到的狀態


# 一張直式卡：上面一大塊放圖（骰子 / 新武器畫 6 面、刻效果面畫那一面、刻技能面畫「？」、數值道具畫對應的效果圖示），下面寫名字；
# 卡放在一個固定大小的格子裡（不是容器），選到的時候才能往上抬、歪一點而不被排版拉回去
func _offer_card(i: int, o: Dictionary, me: Player) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = CARD_SIZE + Vector2(0, CARD_LIFT)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.size = CARD_SIZE
	card.position = Vector2(0, CARD_LIFT)
	card.pivot_offset = CARD_SIZE / 2.0
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override(&"panel", _paper_card(false))
	card.mouse_entered.connect(func() -> void:
		_hover_offer = i
		_paint_cards())
	card.mouse_exited.connect(func() -> void:
		if _hover_offer == i:
			_hover_offer = -1
		_paint_cards())
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pick(i)
			card.accept_event())
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 8)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(body)
	var art := PanelContainer.new()
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_theme_stylebox_override(&"panel", DiceProps.paper_box(ART_PAPER, ART_EDGE, 1))
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_card_art(o, me))
	art.add_child(center)
	body.add_child(art)
	body.add_child(UiKit.rect(Color(ART_EDGE, 0.8), Vector2(0, 2)))
	var title := UiKit.label(o.title, 20, DiceProps.INK, 0)   # 字級用開場預熱過的（HUD.set_loading）
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(CARD_SIZE.x - 28, 58)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.add_child(title)
	slot.add_child(card)
	return slot


# 卡上的圖（不寫說明：選了就進刻面畫面 / 骰子進背包，到時候自然知道）
func _card_art(o: Dictionary, me: Player) -> Control:
	if o.has("faces"):   # 新骰子、新武器：6 面排成 3 × 2
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override(&"h_separation", 6)
		grid.add_theme_constant_override(&"v_separation", 6)
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for f: StringName in o.faces:
			var m := DieView.new(-1, 56.0)
			m.show_face(f, o.get("base", me.weapon_id), false, false)
			grid.add_child(m)
		return grid
	if o.has("face"):   # 刻效果面：那一面放大
		var m := DieView.new(-1, 110.0)
		m.show_face(o.face, me.weapon_id, false, false)
		return m
	if o.kind == &"item":   # 數值道具：照它加的數值用效果的圖示（DiceDefs.ITEMS 的 icon）
		var id: StringName = &""
		var idx: int = o.get("item", -1)
		if idx >= 0 and idx < DiceDefs.ITEMS.size():
			id = DiceDefs.ITEMS[idx].get("icon", &"")
		else:   # 客戶端的快照只帶種類、名字、說明，不帶 item 編號：照名字找
			for it: Dictionary in DiceDefs.ITEMS:
				if it.name == o.title:
					id = it.get("icon", &"")
		if FaceIcons.has(id):
			var tex := TextureRect.new()
			tex.texture = FaceIcons.texture(id)
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.custom_minimum_size = Vector2(120, 120)
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return tex
	var q := UiKit.label("？", 64, DiceProps.INK_SUB, 0)   # 刻技能面：選了才揭曉（64 號跟中獎橫幅一起預熱）
	q.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return q


# 卡紙：平常紙色深棕框，選到的亮紙金框（跟骰中的右鍵卡一樣）
static func _paper_card(on: bool) -> StyleBoxFlat:
	var box := DiceProps.paper_box(DiceProps.PAPER_LIT if on else DiceProps.PAPER, UiKit.GOLD if on else DiceProps.PAPER_EDGE, 3 if on else 2)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(12)
	if on:
		box.shadow_size = 10
		box.shadow_offset = Vector2(0, 10)
	return box


# 選到的那張（滑鼠指著或鍵盤選的，_hover_offer）抬起來、歪一點、亮紙金框
func _paint_cards() -> void:
	_painted_hover = _hover_offer
	var slots := _reward_cards.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())
	for i in slots.size():
		var on := i == _hover_offer
		var card := (slots[i] as Control).get_child(0) as Control
		card.add_theme_stylebox_override(&"panel", _paper_card(on))
		card.position.y = 0.0 if on else CARD_LIFT
		card.rotation = CARD_TILT if on else 0.0


# 擲骰、刻面的按鈕做成籌碼：紫色圓角、淺色邊（重擲券同一種紫）；按下 / 選中的金邊，不能按的淡掉
static func chip_button(b: Button) -> void:
	var states := {&"normal": [CHIP_BG, CHIP_RIM], &"hover": [CHIP_BG.lightened(0.15), Color.WHITE],
		&"pressed": [CHIP_BG.lightened(0.1), UiKit.GOLD], &"hover_pressed": [CHIP_BG.lightened(0.2), UiKit.GOLD],
		&"disabled": [Color(CHIP_BG, 0.45), Color(CHIP_RIM, 0.35)]}
	for state: StringName in states:
		var box := StyleBoxFlat.new()
		box.bg_color = states[state][0]
		box.border_color = states[state][1]
		box.set_border_width_all(3)
		box.set_corner_radius_all(40)
		box.content_margin_left = 22
		box.content_margin_right = 22
		box.shadow_color = Color(0, 0, 0, 0.5)
		box.shadow_size = 3
		box.shadow_offset = Vector2(0, 3)
		b.add_theme_stylebox_override(state, box)
	for c: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	b.add_theme_color_override(&"font_disabled_color", Color(1, 1, 1, 0.45))


static func _card_box(border: Color, bg: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(3)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(16)
	return box


# 刻面畫面：刻技能面先選一招（候選按鈕），再點一面；空白面金框
func _show_carve(s: DiceRun.Seat, me: Player) -> void:
	var skill_kind: bool = s.carve.kind == &"carve_skill"
	if s.carve != _carve_key:
		_carve_key = s.carve.duplicate(true)
		_carve_skill = -1
		for c in _carve_skills.get_children():
			c.queue_free()
		if skill_kind:
			for k in (s.carve.skills as Array).size():
				var id: StringName = s.carve.skills[k]
				var b := UiKit.button(DiceDefs.name_of(id), UiKit.BUTTON_M)
				b.toggle_mode = true
				b.custom_minimum_size.x = 200
				chip_button(b)
				if FaceIcons.has(id):
					b.icon = FaceIcons.texture(id)
					b.expand_icon = true
					b.add_theme_constant_override(&"icon_max_width", 36)
				b.pressed.connect(func() -> void: _carve_skill = k)
				_carve_skills.add_child(b)
	_carve_skills.visible = skill_kind
	for k in _carve_skills.get_child_count():
		(_carve_skills.get_child(k) as Button).set_pressed_no_signal(k == _carve_skill)
	var ready := not skill_kind or _carve_skill >= 0
	if skill_kind:
		_carve_title.text = "刻技能面：先選一招，再點要刻的那一面"
	else:
		_carve_title.text = "刻效果面：%s　·　點要刻的那一面" % DiceDefs.effect_text(s.carve.face, 1)
	_carve_hint.text = _teach(&"dice_carve", "金框是空白面（建議刻在這裡）；也可以蓋掉其他面") if ready else ""
	_carve_rows.modulate.a = 1.0 if ready else 0.4   # 還沒選招：面變暗（點不了）
	for d in DiceDefs.DICE_COUNT:
		var die: Array = s.pool[d]
		for f in DiceDefs.FACES:
			var face: StringName = die[f]
			_carve_views[d * DiceDefs.FACES + f].show_face(face, me.weapon_id, face == DiceDefs.BLANK, ready)


func _on_carve_face(index: int) -> void:
	if phase != DiceRun.REWARD:
		return
	op_requested.emit([InputCmd.OP_DICE_CARVE, index / DiceDefs.FACES, index % DiceDefs.FACES, maxi(_carve_skill, 0)])


func pick(i: int) -> void:
	if phase != DiceRun.REWARD or _picked:
		return
	op_requested.emit([InputCmd.OP_DICE_REWARD, i])
	_picked = true


# InputCollector：骰子畫面開著時先問這裡（處理了回傳 true，不再當成跳躍、重新開始、投票）
func handle_key(event: InputEvent) -> bool:
	if not visible:
		return false
	if not _overlay.visible:   # 逛地圖、戰鬥、清場：鍵盤照常（R 留給重新開始）
		return false
	if phase == DiceRun.REWARD:
		for i in DiceDefs.REWARD_CHOICES:
			if event.is_action_pressed(StringName("slot_%d" % (i + 1))):
				pick(i)
				return true
		# 鍵盤（MenuNav）：A / D 換選的卡（跟滑鼠指著一樣會預覽骰子）、F 選它
		var n := _reward_cards.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion()).size()
		var dir := MenuNav.dir_of(event)
		if n > 0 and dir.x != 0:
			_hover_offer = clampi(_hover_offer + dir.x, 0, n - 1) if _hover_offer >= 0 else (0 if dir.x > 0 else n - 1)
			_paint_cards()
			return true
		if n > 0 and MenuNav.is_confirm(event) and _hover_offer >= 0 and _hover_offer < n:
			pick(_hover_offer)
			return true
		return false
	if phase != DiceRun.ROLL or not my_turn:
		return event.is_action_pressed(&"jump") or event.is_action_pressed(&"restart") or event.is_action_pressed(&"vote_yes")
	if physics and (event.is_action_released(&"jump") or event.is_action_released(&"restart")):
		table.release_charge()
		return true
	if event.is_action_pressed(&"jump") or event.is_action_pressed(&"restart"):
		if physics and not table.cup_mode:
			table.begin_charge()   # 蓄力條：按住跑、放開丟
		else:
			_press_throw()
		return true
	if event.is_action_pressed(&"vote_yes"):
		op_requested.emit([InputCmd.OP_DICE_DONE])
		return true
	return false


# 組合的說明（「　·　順子：技能威力 +1 級、全部效果 ×2」），沒有回傳空字串
static func combos_text(combos: Array, sep: String) -> String:
	var out := ""
	for c: StringName in combos:
		out += "%s%s：%s" % [sep, DiceDefs.COMBOS[c].name, DiceDefs.COMBOS[c].text]
	return out


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
		var tex := FaceIcons.texture(face)
		var col: Color = DiceTable.DIE_WHITE if tex != null or kind == &"blank" else KIND_COLORS[kind]   # 有圖示的面跟骰子一樣是白的
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
		if tex != null:
			var s := side * (0.62 if side >= 80.0 else 0.84)
			draw_texture_rect(tex, Rect2(Vector2((side - s) / 2.0, side * (0.42 if side >= 80.0 else 0.5) - s / 2.0), Vector2(s, s)), false,
				Color(1, 1, 1, 0.3) if kind == &"grey" else Color.WHITE)
		elif SkillIcons.has(icon):
			SkillIcons.draw(self, icon, Vector2(side / 2.0, side * 0.42), 1.0)
		else:
			draw_string(font, Vector2(0, side * 0.42 + big * 0.36), icon, HORIZONTAL_ALIGNMENT_CENTER, side, big, ink)
		if side >= 80.0:
			var caption: String = DiceDefs.name_of(face) if DiceDefs.is_skill(face) else String(DiceDefs.EFFECTS[face].text).split(" ")[0]
			draw_string(font, Vector2(0, side * 0.86), caption, HORIZONTAL_ALIGNMENT_CENTER, side, int(side * 0.15), ink)
		if locked and side >= 80.0:
			draw_string(font, Vector2(0, side + 24), "鎖住", HORIZONTAL_ALIGNMENT_CENTER, side, 18, UiKit.GOLD)
