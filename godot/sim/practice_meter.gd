# 武器測試場的傷害統計（測試面板上那一行）：本機玩家（含僕從）對怪造成的傷害——最近 WINDOW 秒的秒傷、總傷害、最高一擊、打了幾下
# main.gd 每步把 World 這一步的事件餵進來（feed）；時間用模擬的步數算，暫停時不會跑
class_name PracticeMeter
extends RefCounted

const WINDOW := 5.0     # 秒傷看最近幾秒
const MIN_SPAN := 1.0   # 剛開打時至少除以這麼多秒：第一下不會算出很大的秒傷

var total := 0.0
var peak := 0.0
var hits := 0           # 不含附帶的小傷害（持續傷害的一跳、附加屬性傷害）
var _times: Array[float] = []
var _amounts: Array[float] = []
var _first := -1.0      # 歸零後第一下的時間


func reset() -> void:
	total = 0.0
	peak = 0.0
	hits = 0
	_times.clear()
	_amounts.clear()
	_first = -1.0


# 這一步的事件裡，player_id 這位玩家（或他的僕從）打在別人身上的傷害
func feed(world: World, player_id: int) -> void:
	var now := world.tick * Config.FIXED_DT
	for ev: Dictionary in world.events:
		if ev.name != "entity:damaged" or ev.target_id == player_id or ev.amount <= 0.0:
			continue
		if ev.source_id == player_id or ev.get("by", 0) == player_id:
			add(ev.amount, now, ev.get("minor", false))


func add(amount: float, now: float, is_minor := false) -> void:
	if _first < 0.0 or now < _first:
		reset()
		_first = now
	total += amount
	peak = maxf(peak, amount)
	if not is_minor:
		hits += 1
	_times.append(now)
	_amounts.append(amount)


# 最近 WINDOW 秒的傷害 ÷ 經過的秒數（開打不到 WINDOW 秒時除以開打到現在，至少 MIN_SPAN）
func dps(now: float) -> float:
	if _first < 0.0:
		return 0.0
	while not _times.is_empty() and _times[0] <= now - WINDOW:
		_times.pop_front()
		_amounts.pop_front()
	var sum := 0.0
	for a in _amounts:
		sum += a
	return sum / clampf(now - _first, MIN_SPAN, WINDOW)


func text(now: float) -> String:
	return "秒傷 %.0f（最近 %d 秒）　總 %.0f　最高 %.0f　%d 下" % [dps(now), int(WINDOW), total, peak, hits]
