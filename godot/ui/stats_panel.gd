# 屬性面板（Tab 開關）：列出玩家目前已啟用的屬性；和基礎值不同的數值以金色標示（有加成）
class_name StatsPanel
extends PanelContainer

var _values: Dictionary = {}   # stat -> Label
var _optional: Dictionary = {} # stat -> 名稱的 Label（StatDefs 的 optional：是基礎值時名稱與數值都不顯示）


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = UiKit.SLOT_BG
	bg.border_color = UiKit.SLOT_OUTLINE
	bg.set_border_width_all(1)
	bg.set_content_margin_all(14)
	add_theme_stylebox_override(&"panel", bg)

	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	box.add_child(UiKit.label("屬性", UiKit.FONT_BODY))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 24)
	grid.add_theme_constant_override(&"v_separation", 4)
	for stat: StringName in StatDefs.STATS:
		if not StatDefs.STATS[stat].in_use:
			continue
		grid.add_child(UiKit.label(StatDefs.STATS[stat].name, UiKit.FONT_NOTE, Color(1, 1, 1, 0.75), 1))   # 15 → 20（2026-10-27 使用者：太小）
		var value := UiKit.label("", UiKit.FONT_NOTE, Color.WHITE, 1)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
		_values[stat] = value
		if StatDefs.STATS[stat].get("optional", false):
			_optional[stat] = grid.get_child(grid.get_child_count() - 2)   # 名稱那一格，和數值一起藏
			_optional[stat].visible = false
			value.visible = false
	box.add_child(grid)
	add_child(box)


func refresh(entity: Entity) -> void:
	for stat: StringName in _values:
		var v := entity.stats.value(stat)
		var label: Label = _values[stat]
		label.text = StatDefs.format_value(stat, v)
		var modified := not is_equal_approx(v, entity.stats.base(stat))
		label.add_theme_color_override(&"font_color", UiKit.GOLD if modified else Color.WHITE)
		if _optional.has(stat):
			label.visible = modified
			_optional[stat].visible = modified
