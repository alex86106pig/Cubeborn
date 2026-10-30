# 腳邊框（Tab 背包開著時浮在背包左邊、下緣對齊）：按得到 F 的地上道具
# 只負責收滑鼠與當畫布：內容、拖曳 / 點一下拿起、右鍵撿起都由 InventoryPanel 處理（位置與大小也由它每幀算）
class_name FeetPanel
extends Control

var bag: InventoryPanel


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _gui_input(event: InputEvent) -> void:
	if bag != null:
		bag.feet_input(self, event)
		accept_event()


func _draw() -> void:
	if bag != null:
		bag.draw_feet(self)
