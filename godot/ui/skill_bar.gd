# 技能欄（照搬網頁版 HUD 的 skillbar）：左鍵、右鍵、數字鍵 1~5；CD 扇形遮罩與秒數、剩餘次數、閃爍回饋
class_name SkillBar
extends HBoxContainer

const SLOT_SIZE := 58.0
const FLASH_DENY_TIME := 0.3
const FLASH_USED_TIME := 0.25
# 打包的字型（Noto Sans TC）沒有這幾個符號，改用向量圖形畫；網頁版沒有系統字型可借
const DRAWN_ICONS: Array[String] = ["⚔", "🛡", "✦", "✺"]

var _slots: Dictionary = {}   # cd key -> Slot
var _weapon_id: StringName = &""


func _init() -> void:
	add_theme_constant_override(&"separation", 8)
	alignment = BoxContainer.ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func reset() -> void:
	_weapon_id = &""


# 武器換了（含重新開始）就重建
func refresh(world: World, player: Player) -> void:
	if player.weapon_id != _weapon_id:
		_build(player)
	for key: String in _slots:
		var slot: Slot = _slots[key]
		slot.cd_left = world.cooldowns.remaining(key)
		slot.cd_ratio = 1.0 - world.cooldowns.progress(key)
		if slot.index >= 0:
			var data: Variant = player.slots.slots[slot.index]
			if data != null and data.def.mode == &"charges":
				slot.charges.text = str(data.charges)
				slot.icon.modulate.a = 0.3 if data.charges <= 0 else 1.0
		slot.queue_redraw()


func flash(key: String, deny: bool) -> void:
	if _slots.has(key):
		_slots[key].flash(deny)


func _build(player: Player) -> void:
	for c in get_children():
		c.queue_free()
	_slots.clear()
	var w := player.weapon
	_add_slot("", w.attack.icon, "左鍵", -1, false)
	_add_slot("player.special", w.special.icon, "右鍵", -1, false)
	var divider := UiKit.rect(Color(1, 1, 1, 0.25), Vector2(2, 48))
	divider.size_flags_vertical = Control.SIZE_SHRINK_END
	add_child(divider)
	for i in ActiveSlots.SLOT_COUNT:
		var data: Variant = player.slots.slots[i]
		_add_slot(ActiveSlots.cd_key(i), data.def.icon if data != null else "", str(i + 1), i, data == null)
	_weapon_id = player.weapon_id


func _add_slot(key: String, icon: String, key_label: String, index: int, empty: bool) -> void:
	var slot := Slot.new(icon, key_label, index)
	if empty:
		slot.modulate.a = 0.35
	add_child(slot)
	if key != "":
		_slots[key] = slot


class Slot extends Control:
	var index := -1
	var icon: Label
	var drawn_icon := ""        # DRAWN_ICONS 之一時由 _draw 畫，icon 文字留空
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
		if p_icon in DRAWN_ICONS:
			drawn_icon = p_icon
			p_icon = ""
		icon = _centered(UiKit.label(p_icon, 28))
		cd_text = _centered(UiKit.label("", 18))
		charges = UiKit.label("", 13, UiKit.CHARGES, 1)
		charges.position = Vector2(SLOT_SIZE - 16, -1)
		add_child(charges)
		var key := UiKit.label(key_label, 11, Color(1, 1, 1, 0.8), 1)
		key.position = Vector2(4, SLOT_SIZE - 18)
		add_child(key)

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
		if cd_ratio > 0.0:
			# 從 12 點鐘方向順時針的扇形遮罩（網頁版 conic-gradient）
			var c := size / 2.0
			var pts := PackedVector2Array([c])
			var steps := 32
			for i in steps + 1:
				var a := -PI / 2.0 + TAU * cd_ratio * i / steps
				pts.append(c + Vector2(cos(a), sin(a)) * SLOT_SIZE)
			var clipped := Geometry2D.intersect_polygons(pts, PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]))
			for poly in clipped:
				draw_colored_polygon(poly, Color(0, 0, 0, 0.7))

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
