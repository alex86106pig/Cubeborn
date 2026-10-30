# 技能欄（照搬網頁版 HUD 的 skillbar）：左鍵、右鍵、Shift 翻滾（Godot 版新增）、數字鍵 1~4（寶石座的技能）與 Q（治療藥水）；CD 扇形遮罩與秒數、剩餘次數、閃爍回饋
class_name SkillBar
extends HBoxContainer

const SLOT_SIZE := 58.0
const FLASH_DENY_TIME := 0.3
const FLASH_USED_TIME := 0.25
const ROLL_ICON := "⟳"   # 圖示都是 SkillIcons 畫的（打包字型沒有這些符號）

var _slots: Dictionary = {}   # cd key -> Slot
var _weapon_id: StringName = &""
var _slot_sig := ""                    # 寶石座上的技能（ActiveSlots.signature），變了就重建
var _attack_slot: Slot        # 左鍵：平常是普攻
var _parry_slot: Slot         # 劍盾格擋中左鍵改成招架（v0.41.0）：同一個位置，兩格輪流顯示
var _special_slot: Slot       # 右鍵：平常是武器特殊技
var _alt_left: Slot           # 火把準備姿態 / 鐵鏟舉著怪時的左右鍵（2026-10-27）：和平常的格子同位置輪流顯示
var _alt_right: Slot


func _init() -> void:
	add_theme_constant_override(&"separation", 8)
	alignment = BoxContainer.ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func reset() -> void:
	_weapon_id = &""


# 武器換了（含重新開始）、寶石座上的技能換了就重建
func refresh(world: World, player: Player) -> void:
	var sig := player.slots.signature(player)
	if player.weapon_id != _weapon_id or sig != _slot_sig:
		_slot_sig = sig
		_build(player)
	if _parry_slot != null:
		_parry_slot.visible = player.block_time >= 0.0
		_attack_slot.visible = not _parry_slot.visible
	if _alt_left != null:
		_refresh_alt(player)
	var atk: Dictionary = player.weapon.attack
	if atk.has("quiver") and _attack_slot != null:
		# 短弓：左鍵格顯示箭袋剩幾支，裝填中蓋遮罩倒數
		_attack_slot.charges.text = str(player.quiver)
		_attack_slot.cd_left = player.reload_timer
		_attack_slot.cd_ratio = player.reload_timer / atk.reload_time if player.reload_timer > 0.0 else 0.0
		_attack_slot.icon.modulate.a = 0.3 if player.reload_timer > 0.0 else 1.0
		_attack_slot.queue_redraw()
		_attack_slot.mask.queue_redraw()
	for key: String in _slots:
		var slot: Slot = _slots[key]
		slot.cd_left = world.cooldowns.remaining(player.cd(key))   # 每位玩家各自的 CD（Player.cd）
		slot.cd_ratio = 1.0 - world.cooldowns.progress(player.cd(key))
		if slot.index >= 0:
			var data: Variant = player.slots.get_slot(player, slot.index)   # 寶石座的技能（含火把的插火把）
			if data != null and data.def.mode == &"charges":
				slot.charges.text = str(data.charges)
				slot.icon.modulate.a = 0.3 if data.charges <= 0 else 1.0
		elif key == Player.ROLL_CD:
			# 翻滾：顯示剩餘次數；還有次數時不蓋遮罩（回充秒數照樣顯示）
			slot.charges.text = str(player.roll_charges)
			slot.icon.modulate.a = 0.3 if player.roll_charges <= 0 else 1.0
			if player.roll_charges > 0:
				slot.cd_ratio = 0.0
		slot.queue_redraw()
		slot.mask.queue_redraw()


# 火把舉著時（左鍵噴火 + 冷卻；右鍵格照舊是舉火把）、鐵鏟舉著怪（左鍵拋出、右鍵埋入）時換成那兩格
func _refresh_alt(player: Player) -> void:
	var w := player.weapon
	var stance: bool = player.torch_stance and w.has("stance")
	var holding: bool = w.has("grab") and (player.held_enemy_id != 0 or player.anim.get("holding", false))
	var on: bool = stance or holding
	_alt_left.visible = on
	_attack_slot.visible = not on and (_parry_slot == null or not _parry_slot.visible)
	if _alt_right != null:
		_alt_right.visible = on
		_special_slot.visible = not on


func flash(key: String, deny: bool) -> void:
	if _slots.has(key):
		_slots[key].flash(deny)


func _build(player: Player) -> void:
	for c in get_children():
		c.queue_free()
	_slots.clear()
	var w := player.weapon
	_attack_slot = _add_slot("", w.attack.icon, "左鍵", -1, false)
	_parry_slot = null
	if w.special.has("parry") and w.special.parry.has("name"):
		_parry_slot = _add_slot("player.parry", w.special.parry.get("icon", w.special.parry.name), "左鍵", -1, false)
		_parry_slot.visible = false
	var alt: Dictionary = w.get("stance", w.get("grab", {}))
	_alt_left = null
	_alt_right = null
	if not alt.is_empty():
		_alt_left = _add_slot(alt.attack.get("cd_key", ""), alt.attack.icon, "左鍵", -1, false)   # 噴火的冷卻照一般格子更新
		_alt_left.visible = false
	_special_slot = _add_slot("player.special", w.special.icon, "右鍵", -1, false)
	if alt.has("special"):   # 火把舉著時只換左鍵（右鍵就是按住的舉火把）
		_alt_right = _add_slot("", alt.special.icon, "右鍵", -1, false)
		_alt_right.visible = false
	_add_slot(Player.ROLL_CD, ROLL_ICON, "Shift", -1, false)
	var divider := UiKit.rect(Color(1, 1, 1, 0.25), Vector2(2, 48))
	divider.size_flags_vertical = Control.SIZE_SHRINK_END
	add_child(divider)
	for i in ActiveSlots.SLOT_COUNT:
		var data: Variant = player.slots.get_slot(player, i)
		_add_slot(ActiveSlots.cd_key(i), data.def.icon if data != null else "", ActiveSlots.KEY_LABELS[i], i, data == null)
	_weapon_id = player.weapon_id


func _add_slot(key: String, icon: String, key_label: String, index: int, empty: bool) -> Slot:
	var slot := Slot.new(icon, key_label, index)
	if empty:
		slot.modulate.a = 0.35
	add_child(slot)
	if key != "":
		_slots[key] = slot
	return slot


class Slot extends Control:
	var index := -1
	var icon: Label
	var icon_id := ""           # 招式的 icon（WeaponDefs）
	var drawn_icon := ""        # SkillIcons 畫得出來時由 _draw 畫，icon 文字留空
	var mask: Control           # CD 扇形遮罩；子節點會畫在格子的 _draw 上面，獨立一層才能蓋住文字圖示、又墊在秒數底下
	var charges: Label
	var cd_text: Label
	var cd_left := 0.0
	var cd_ratio := 0.0         # 0~1，尚未冷卻完成的比例（扇形遮罩）
	var _outline := UiKit.SLOT_OUTLINE
	var _tween: Tween

	func _init(p_icon: String, key_label: String, p_index: int) -> void:
		index = p_index
		custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		pivot_offset = custom_minimum_size / 2.0
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon = _centered(UiKit.label("", 28))
		set_icon(p_icon)
		mask = Control.new()
		mask.size = Vector2(SLOT_SIZE, SLOT_SIZE)
		mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mask.draw.connect(_draw_mask)
		add_child(mask)
		cd_text = _centered(UiKit.label("", 24))
		cd_text.add_theme_color_override(&"font_outline_color", UiKit.SHADOW)
		cd_text.add_theme_constant_override(&"outline_size", 6)
		charges = UiKit.label("", 13, UiKit.CHARGES, 1)
		charges.position = Vector2(SLOT_SIZE - 16, -1)
		add_child(charges)
		var key := UiKit.label(key_label, 11, Color(1, 1, 1, 0.8), 1)
		key.position = Vector2(4, SLOT_SIZE - 18)
		add_child(key)

	# 換圖示（火把準備姿態的左鍵在插火 / 揮擊之間換）
	func set_icon(p_icon: String) -> void:
		icon_id = p_icon
		drawn_icon = p_icon if SkillIcons.has(p_icon) else ""
		icon.text = "" if drawn_icon != "" else p_icon
		icon.add_theme_font_size_override(&"font_size", 20 if p_icon.length() > 1 else 28)   # 沒畫的兩個字縮小才塞得進
		queue_redraw()

	func _centered(l: Label) -> Label:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size = Vector2(SLOT_SIZE, SLOT_SIZE)
		add_child(l)
		return l

	func _process(_delta: float) -> void:
		cd_text.text = ("%.1f" % cd_left if cd_left < 1.0 else "%d" % ceili(cd_left)) if cd_left > 0.0 else ""

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(2.0), _outline)
		draw_rect(r, Color("0b0d14"))
		draw_rect(r.grow(-3.0), UiKit.SLOT_BG)
		if drawn_icon != "":
			SkillIcons.draw(self, drawn_icon, size / 2.0, icon.modulate.a)

	# 從 12 點鐘方向順時針的扇形遮罩（網頁版 conic-gradient）；隨冷卻從 12 點鐘逆時針露出圖示
	func _draw_mask() -> void:
		if cd_ratio > 0.0:
			var c := size / 2.0
			var pts := PackedVector2Array([c])
			var steps := 32
			for i in steps + 1:
				var a := -PI / 2.0 + TAU * cd_ratio * i / steps
				pts.append(c + Vector2(cos(a), sin(a)) * SLOT_SIZE)
			var clipped := Geometry2D.intersect_polygons(pts, PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]))
			for poly in clipped:
				mask.draw_colored_polygon(poly, Color(0, 0, 0, 0.7))

	func flash(deny: bool) -> void:
		if _tween:
			_tween.kill()
		_tween = create_tween()
		if deny:
			_outline = UiKit.DENY
			var t := FLASH_DENY_TIME / 4.0
			_tween.tween_property(self, ^"position:x", position.x - 4.0, t)
			_tween.tween_property(self, ^"position:x", position.x + 4.0, t * 2.0)
			_tween.tween_property(self, ^"position:x", position.x, t)
		else:
			_outline = Color.WHITE
			_tween.tween_property(self, ^"scale", Vector2.ONE * 1.12, FLASH_USED_TIME * 0.4)
			_tween.tween_property(self, ^"scale", Vector2.ONE, FLASH_USED_TIME * 0.6)
		_tween.finished.connect(func() -> void:
			_outline = UiKit.SLOT_OUTLINE
			queue_redraw())
		queue_redraw()
