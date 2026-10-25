# --perf 效能量測（D5、v0.36.3；2026-10-25 從 main.gd 搬出來）：關垂直同步，開場 WARMUP 秒後記錄幀時間、
# 每步邏輯與每幀畫面同步的耗時；超過 HITCH_MS 的幀當場印出（附上前一幀第一次畫出來的東西），結束時印出報表
class_name PerfMeter
extends RefCounted

const WARMUP := 2.0     # 開場幾秒不記錄（建模與第一次編譯著色器）
const HITCH_MS := 33.0  # 超過這麼久的幀算卡頓（30 FPS 以下）

var prev_first: Array[String] = []   # 前一幀第一次畫出來的東西（模型種類、特效）
# 卡頓的拆解：這一幀的 delta = 這次 _process 前跑的模擬步（邏輯 + 事件處理）+ 上一幀的畫面同步 + 其餘（多半是瀏覽器 / 驅動在渲染）
var prev_sync_usec := 0              # 上一幀 WorldView.sync 的耗時
var prev_created := 0                # 上一幀新建的模型數
var _frame_logic_usec := 0           # 上次 _process 之後跑的模擬步：World.step
var _frame_event_usec := 0           # 上次 _process 之後跑的模擬步：事件交給畫面層、HUD、音效（GameEvents.emit_all）
var _frame_steps := 0
var _frames := PackedFloat32Array()
var _hitches: Array[float] = []      # 超過 HITCH_MS 的幀（毫秒）
var _warm_ms := 0.0                  # 預熱那幾幀合計多久
var _step_usec := 0
var _steps := 0
var _sync_usec := 0
var _syncs := 0


func _init() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0


func recording(elapsed: float) -> bool:
	return elapsed >= WARMUP


func add_step(usec: int, elapsed: float, event_usec: int = 0) -> void:
	_frame_logic_usec += usec
	_frame_event_usec += event_usec
	_frame_steps += 1
	if recording(elapsed):
		_step_usec += usec
		_steps += 1


func add_frame(delta: float, sync_usec: int, elapsed: float) -> void:
	if recording(elapsed):
		_sync_usec += sync_usec
		_syncs += 1
		_frames.append(delta)


# 卡頓紀錄：這一幀的 delta 包含前一幀第一次畫的東西的成本（編譯著色器、產生字形）
func log_hitch(delta: float, elapsed: float, warming: bool) -> void:
	var ms := delta * 1000.0
	var logic := _frame_logic_usec / 1000.0
	var events := _frame_event_usec / 1000.0
	var steps := _frame_steps
	_frame_logic_usec = 0
	_frame_event_usec = 0
	_frame_steps = 0
	if warming:
		_warm_ms += ms   # 預熱那幾幀本來就會慢（蓋著「準備中」），另外記、不算卡頓
		return
	if ms < HITCH_MS or elapsed <= 0.0:
		return
	_hitches.append(ms)
	var sync := prev_sync_usec / 1000.0
	print("perf hitch t=%.2f ms=%.1f first=%s | logic=%.1f(%d步) events=%.1f prev_sync=%.1f created=%d other=%.1f" % [
		elapsed, ms, ", ".join(prev_first) if not prev_first.is_empty() else "-",
		logic, steps, events, sync, prev_created, ms - logic - events - sync])


# 平均 FPS、最慢 1% 的幀、每步邏輯與每幀畫面同步的平均耗時、活著的敵人與畫出來的數量
func print_report(world: World, world_view: WorldView) -> void:
	var frames := _frames.duplicate()
	frames.sort()
	var n := frames.size()
	if n == 0:
		return
	var total := 0.0
	for f in frames:
		total += f
	var alive := 0
	for e in world.enemies:
		alive += 0 if e.is_dead else 1
	print("perf frames=%d avg_fps=%.1f p99_ms=%.2f worst_ms=%.2f logic_ms_per_step=%.3f view_sync_ms=%.3f enemies=%d visible=%d draw_calls=%d" % [
		n, n / total, frames[mini(n - 1, int(n * 0.99))] * 1000.0, frames[n - 1] * 1000.0,
		_step_usec / 1000.0 / maxi(1, _steps), _sync_usec / 1000.0 / maxi(1, _syncs),
		alive, world.enemies.size() - world_view.hidden_enemy_count(world),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	var over50 := _hitches.filter(func(ms: float) -> bool: return ms >= 50.0).size()
	var over100 := _hitches.filter(func(ms: float) -> bool: return ms >= 100.0).size()
	print("perf hitches over33=%d over50=%d over100=%d worst_hitch_ms=%.1f warmup_ms=%.1f" % [_hitches.size(), over50, over100, _hitches.max() if not _hitches.is_empty() else 0.0, _warm_ms])
	var parts := ""
	for k: StringName in world_view.profile_usec:
		parts += " %s=%.3f" % [k, world_view.profile_usec[k] / 1000.0 / maxi(1, _syncs)]
	print("perf view_sync_parts_ms:" + parts)
