# 新手提示框（v0.31.0）：畫面下方、技能欄上面；條件第一次成立時排隊顯示，每種只出現一次（文字見 defs/hint_defs.gd）
# 看過的記在 user://settings.cfg 的 [hints]；暫停選單的「重新顯示提示」清掉。只讀模擬狀態，客戶端讀鏡像 World 也一樣
class_name Hints
extends PanelContainer

const SECTION := "hints"

var save_path := "user://settings.cfg"   # 和 audio/sound.gd 的靜音設定同一個檔案；測試設成 "" 就不讀寫檔案
var seen: Dictionary = {}              # 提示 id -> true（已經顯示過）
var queue: Array[StringName] = []      # 條件成立、等著顯示的提示
var current: StringName = &""          # 正在顯示的提示；"" = 沒有
var _label := UiKit.label("", 20, Color.WHITE, 2)
var _time := 0.0                       # current 已顯示的秒數
var _wait := HintDefs.START_DELAY      # 下一則之前還要等幾秒


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(10 / 255.0, 12 / 255.0, 20 / 255.0, 0.82)
	box.border_color = Color(UiKit.GOLD, 0.7)
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	add_theme_stylebox_override(&"panel", box)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
	visible = false


func _ready() -> void:
	load_seen()


func load_seen() -> void:
	seen.clear()
	if save_path == "":
		return
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK:
		for id: String in cfg.get_value(SECTION, "seen", []):
			seen[StringName(id)] = true


# 暫停選單「重新顯示提示」：全部當成沒看過，條件成立時再跳一次
func reset_seen() -> void:
	seen.clear()
	queue.clear()
	_save()


# 每幀由 HUD 呼叫：把剛成立的條件排進佇列、播完一則再換下一則
func update(delta: float, world: World, player: Player, bag_open: bool) -> void:
	if world == null or player == null:
		return
	poll(world, player, bag_open)
	if current != &"":
		_time += delta
		modulate.a = clampf(minf(_time, HintDefs.SHOW_TIME - _time) / HintDefs.FADE_TIME, 0.0, 1.0)
		if _time >= HintDefs.SHOW_TIME:
			current = &""
			visible = false
			_wait = HintDefs.GAP_TIME
		return
	_wait -= delta
	while _wait <= 0.0 and not queue.is_empty():
		var id: StringName = queue.pop_front()
		if _condition(id, world, player, bag_open):   # 排隊期間情況可能變了（例如隊友已經被救起），不成立就跳過、之後再成立會重排
			show_hint(id)
			return


func poll(world: World, player: Player, bag_open: bool) -> void:
	for id: StringName in HintDefs.HINTS:
		if seen.has(id) or queue.has(id) or id == current:
			continue
		if _condition(id, world, player, bag_open):
			queue.append(id)


func show_hint(id: StringName) -> void:
	current = id
	_time = 0.0
	seen[id] = true
	_save()
	_label.text = HintDefs.HINTS[id]
	modulate.a = 0.0
	visible = true


func _condition(id: StringName, world: World, player: Player, bag_open: bool) -> bool:
	match id:
		&"controls":
			return true
		&"dig_goal":
			return DigEvent.enabled(world) and world.event.state == DigEvent.IDLE
		&"bag_open":
			return not player.items.is_empty() or not player.inventory.entries.is_empty() or not player.weapon_slots[1].is_empty()
		&"bag_ops":
			return bag_open
		&"craft":
			return has_merge_pair(player)
		&"exit":
			return DigEvent.enabled(world) and world.event.state == DigEvent.OPEN
		&"revive":
			for p in world.player_list:
				if p != player and p.is_downed:
					return true
			return false
	return false


# 裝備欄與背包裡有沒有兩把可以合成的武器（WeaponDropDefs.can_merge）
static func has_merge_pair(player: Player) -> bool:
	var list: Array[Dictionary] = []
	for inst in player.weapon_slots:
		if not inst.is_empty():
			list.append(inst)
	for e in player.inventory.entries:
		if e.has("weapon"):
			list.append(e.weapon)
	for i in list.size():
		for j in range(i + 1, list.size()):
			if WeaponDropDefs.can_merge(list[i], list[j]):
				return true
	return false


func _save() -> void:
	if save_path == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(save_path)
	var ids: Array[String] = []
	for id: StringName in seen:
		ids.append(String(id))
	cfg.set_value(SECTION, "seen", ids)
	cfg.save(save_path)
