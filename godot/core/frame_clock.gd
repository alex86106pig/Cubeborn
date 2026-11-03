# 實際的幀間隔（秒）：量卡頓與 FPS 用。_process 的 delta 遇到很慢的幀會失真（很慢的那幀給得很小、下一幀才補上一部分，
# 連續兩幀慢只量得到一筆、還被壓低），改用 Time.get_ticks_usec 量相鄰兩次呼叫的間隔
# 每幀呼叫一次 tick；上一次不是前一幀呼叫的（第一次、中間有幾幀沒呼叫）就用 delta
class_name FrameClock
extends RefCounted

var _last_usec := 0
var _last_frame := -2


func tick(delta: float) -> float:
	var now := Time.get_ticks_usec()
	var frame := Engine.get_process_frames()
	var seconds := (now - _last_usec) / 1000000.0 if frame == _last_frame + 1 else delta
	_last_usec = now
	_last_frame = frame
	return seconds
