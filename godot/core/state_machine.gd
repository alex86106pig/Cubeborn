# 通用有限狀態機：狀態物件可實作 enter / update / exit / can_exit，皆為選用
class_name StateMachine
extends RefCounted

var ctx: Object
var states: Dictionary      # StringName -> 狀態物件
var current: Object = null
var current_name: StringName = &""
var previous_name: StringName = &""
var time := 0.0             # 進入目前狀態後經過的秒數
var data: Dictionary = {}   # 每次進入狀態時重建，供狀態存放本次執行的暫存資料


func _init(p_ctx: Object, p_states: Dictionary, initial: StringName = &"") -> void:
	ctx = p_ctx
	states = p_states
	if initial != &"":
		change(initial)


func change(name: StringName, p_data: Dictionary = {}) -> bool:
	assert(states.has(name), "Unknown state: %s" % name)
	var next: Object = states[name]
	var prev := current
	if prev and prev.has_method(&"can_exit") and not prev.can_exit(ctx, name, self):
		return false
	if prev and prev.has_method(&"exit"):
		prev.exit(ctx, self)
	previous_name = current_name
	current = next
	current_name = name
	time = 0.0
	data = p_data.duplicate()
	if next.has_method(&"enter"):
		next.enter(ctx, data, self)
	return true


func update(dt: float) -> void:
	time += dt
	if current and current.has_method(&"update"):
		current.update(ctx, dt, self)


func is_in(name: StringName) -> bool:
	return current_name == name
