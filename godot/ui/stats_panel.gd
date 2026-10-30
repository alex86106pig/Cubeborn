# 屬性面板（Tab 開關）：依 StatDefs.PANEL_GROUPS 分組列出屬性，核心屬性一直顯示、其他有加成才顯示；和基礎值不同的數值以金色標示（有加成）
class_name StatsPanel
extends PanelContainer

const HEADER_COLOR := Color(1, 1, 1, 0.45)
const HEADER_GAP := 10   # 分組標題上方多空的距離（第一組不空）

var _values: Dictionary = {}   # stat -> 數值的 Label
var _names: Dictionary = {}    # stat -> 名稱的 Label（和數值一起藏）
var _groups: Array = []        # [標題那一列的兩格, 這組的 stats]：整組都藏起來時標題也藏


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
	# 同一個格子放全部的組，數值欄才會上下對齊
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 24)
	grid.add_theme_constant_override(&"v_separation", 4)
	for group: Dictionary in StatDefs.PANEL_GROUPS:
		var header := UiKit.label(group.name, UiKit.FONT_NOTE, HEADER_COLOR, 1)
		header.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		if not _groups.is_empty():
			header.custom_minimum_size.y = header.get_combined_minimum_size().y + HEADER_GAP
		var filler := Control.new()
		filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(header)
		grid.add_child(filler)
		var stats: Array[StringName] = []
		for stat: StringName in group.stats:
			if not StatDefs.STATS[stat].in_use:
				continue
			var stat_name := UiKit.label(StatDefs.STATS[stat].name, UiKit.FONT_NOTE, Color(1, 1, 1, 0.75), 1)
			var value := UiKit.label("", UiKit.FONT_NOTE, Color.WHITE, 1)
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(stat_name)
			grid.add_child(value)
			_names[stat] = stat_name
			_values[stat] = value
			stats.append(stat)
			_show(stat, StatDefs.PANEL_CORE.has(stat))   # 還沒 refresh 前先當作都是基礎值
		_groups.append([[header, filler], stats])
	_update_groups()
	box.add_child(grid)
	add_child(box)


func refresh(entity: Entity) -> void:
	for stat: StringName in _values:
		var v := entity.stats.value(stat)
		var label: Label = _values[stat]
		label.text = StatDefs.format_value(stat, v)
		var modified := not is_equal_approx(v, entity.stats.base(stat))
		label.add_theme_color_override(&"font_color", UiKit.GOLD if modified else Color.WHITE)
		_show(stat, modified or StatDefs.PANEL_CORE.has(stat))
	_update_groups()


func is_stat_shown(stat: StringName) -> bool:
	return _values.has(stat) and _values[stat].visible


func shown_groups() -> Array[String]:
	var names: Array[String] = []
	for g: Array in _groups:
		if g[0][0].visible:
			names.append(g[0][0].text)
	return names


func _show(stat: StringName, shown: bool) -> void:
	_values[stat].visible = shown
	_names[stat].visible = shown


func _update_groups() -> void:
	for g: Array in _groups:
		var any_shown := (g[1] as Array).any(is_stat_shown)
		for cell: Control in g[0]:
			cell.visible = any_shown
