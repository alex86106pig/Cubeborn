# autoload GameEvents：把模擬層的事件（可序列化 Dictionary）以訊號發給畫面層
extends Node

signal event_emitted(name: String, payload: Dictionary)


func emit_all(events: Array[Dictionary]) -> void:
	for e in events:
		event_emitted.emit(e.name, e)
