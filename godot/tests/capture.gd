# 畫面測試專用：遊戲畫在看不見的 1920×1080 SubViewport，實際視窗只有右下角一小格且不搶焦點
# 用法（在 godot/ 內）：<Godot> --path . --resolution 64x64 res://tests/capture.tscn -- --seconds=S --screenshot=路徑
# main.gd 的截圖用 get_viewport()，在這裡會拿到 SubViewport，因此是完整解析度
extends Node

const RENDER_SIZE := Vector2i(1920, 1080)
const WINDOW_SIZE := Vector2i(64, 64)
const MAIN_SCENE := preload("res://main.tscn")


func _ready() -> void:
	var window := get_window()
	window.set_flag(Window.FLAG_NO_FOCUS, true)
	window.size = WINDOW_SIZE
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
	window.position = usable.end - WINDOW_SIZE

	var viewport := SubViewport.new()
	viewport.size = RENDER_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	add_child(viewport)
	viewport.add_child(MAIN_SCENE.instantiate())
