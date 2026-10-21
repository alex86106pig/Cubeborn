# 統一冷卻時間管理：每個 World 一個實例，key 格式為 owner.purpose
class_name CooldownManager
extends RefCounted

var _timers: Dictionary = {}  # key -> [remaining, duration]


func start(key: String, duration: float) -> void:
	if duration <= 0.0:
		_timers.erase(key)
		return
	_timers[key] = [duration, duration]


func tick(dt: float) -> void:
	for key: String in _timers.keys():
		var timer: Array = _timers[key]
		timer[0] -= dt
		if timer[0] <= 0.0:
			_timers.erase(key)


func is_ready(key: String) -> bool:
	return not _timers.has(key)


func remaining(key: String) -> float:
	return _timers[key][0] if _timers.has(key) else 0.0


# 0~1，1 表示冷卻完成
func progress(key: String) -> float:
	if not _timers.has(key):
		return 1.0
	var timer: Array = _timers[key]
	return 1.0 - timer[0] / timer[1]


func reset(key: String) -> void:
	_timers.erase(key)


func reset_all() -> void:
	_timers.clear()
