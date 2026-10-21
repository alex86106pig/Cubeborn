# HUD（骨架版）：版號、FPS、暫停提示；血條、技能欄、波次在里程碑 4 加入
class_name HUD
extends CanvasLayer

const FPS_INTERVAL := 0.5

var _version := Label.new()
var _fps := Label.new()
var _pause := Label.new()
var _fps_timer := 0.0
var _fps_frames := 0


func _ready() -> void:
	_version.text = "v" + GameVersion.VERSION
	_version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_SIZE, 12)
	_version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_version.modulate.a = 0.6
	add_child(_version)

	_fps.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 12)
	_fps.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_fps)

	_pause.text = "暫停\nEsc 繼續"
	_pause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.add_theme_font_size_override(&"font_size", 48)
	_pause.visible = false
	add_child(_pause)

	GameEvents.event_emitted.connect(_on_event)


func _process(delta: float) -> void:
	_fps_timer += delta
	_fps_frames += 1
	if _fps_timer >= FPS_INTERVAL:
		_fps.text = "%d FPS" % roundi(_fps_frames / _fps_timer)
		_fps_timer = 0.0
		_fps_frames = 0


func _on_event(name: String, payload: Dictionary) -> void:
	match name:
		"game:paused":
			_pause.visible = payload.paused
		"game:restart":
			_pause.visible = false
