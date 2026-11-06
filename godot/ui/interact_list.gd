# 互動列表（許家慶 2026-11-06，參考原神撿東西）：按得到 F 的東西有兩個以上時，角色右邊列出來（由近到遠），
# 滾輪或上下鍵挑一個（InputCollector 轉給 cycle），按 F 跟選中的那個互動（InputCollector 送 [InputCmd.OP_INTERACT, selected_id]）
# 只有一個時不畫列表（場上那個東西本身有「[F] …」提示）；選中的那個場上的提示也跟著換（WorldLabels.focus_id）
class_name InteractList
extends Control

const ROW_H := 30
const ROW_W := 300
const PAD := 8
const SHIFT := Vector2(70, -40)   # 列表左上角相對角色胸口在畫面上的位置
const MAX_ROWS := 6
const FONT_SIZE := 16
const HINT := "滾輪 / 上下鍵 切換 · F 互動"   # 打包的字型沒有箭頭符號
const BG := Color(0, 0, 0, 0.6)
const PICK_BG := Color(1, 0.85, 0.4, 0.22)

var world: World
var camera: Camera3D
var local_peer := World.HOST_PEER_ID
var options: Array[Dictionary] = []   # Interactables.options（每幀更新）
var selected_id := 0                  # 選中的那個（Interactables 的 id）；0 = 沒有可互動的


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	refresh()
	queue_redraw()


# 重新列出按得到的東西；選中的那個不在了（走遠、撿走）就回到最近的，新靠近的東西不會搶走選擇
func refresh() -> void:
	var me: Player = world.players.get(local_peer) if world != null else null
	options = Interactables.options(world, me) if me != null else ([] as Array[Dictionary])
	if not options.any(func(o: Dictionary) -> bool: return o.id == selected_id):
		selected_id = options[0].id if not options.is_empty() else 0


# 有兩個以上才顯示列表、滾輪與上下鍵才拿來切換
func is_open() -> bool:
	return options.size() >= 2


# 往下（step = 1）/ 往上（-1）換一個，頭尾接起來
func cycle(step: int) -> void:
	if options.is_empty():
		return
	var i := options.find_custom(func(o: Dictionary) -> bool: return o.id == selected_id)
	selected_id = options[posmod(i + step, options.size())].id


func _draw() -> void:
	if not is_open() or camera == null:
		return
	var me: Player = world.players.get(local_peer)
	var at := WorldView.render_pos(me, me.body_height * 0.6)
	if camera.is_position_behind(at):
		return
	var font := get_theme_default_font()
	var origin := camera.unproject_position(at) + SHIFT
	var rows := mini(options.size(), MAX_ROWS)
	draw_rect(Rect2(origin, Vector2(ROW_W, rows * ROW_H + ROW_H * 0.8 + PAD)), BG)
	for i in rows:
		var o: Dictionary = options[i]
		var top := origin + Vector2(0, i * ROW_H)
		var picked: bool = o.id == selected_id
		if picked:
			draw_rect(Rect2(top, Vector2(ROW_W, ROW_H)), PICK_BG)
		var text := ("[F] " if picked else "　 ") + label(world, me, o)
		draw_string(font, top + Vector2(PAD, ROW_H * 0.7), text, HORIZONTAL_ALIGNMENT_LEFT, ROW_W - PAD * 2, FONT_SIZE, color(world, o))
	draw_string(font, origin + Vector2(PAD, rows * ROW_H + ROW_H * 0.6), HINT, HORIZONTAL_ALIGNMENT_LEFT, ROW_W - PAD * 2, FONT_SIZE - 3, Color(1, 1, 1, 0.6))


# 一列的字：動作 + 東西（「撿起 白色 長劍」「開啟 祭壇 25 靈魂」「前往第 2 層」）
static func label(w: World, me: Player, o: Dictionary) -> String:
	match o.kind:
		&"pickup":
			return "撿起 " + (w.entities[o.id] as ItemPickup).display_name()
		&"relic":
			var r := w.entities[o.id] as Relic
			return "升級武器 鐵砧" if r.relic_kind == &"anvil" else "打開遺物"
		&"chest":
			var c := w.entities[o.id] as Chest
			return "開啟 %s  %d 靈魂" % [LootDefs.CHESTS[c.tier].name, c.price_for(me)]
		&"forge":
			return "合成武器 鍛造祭壇"
		&"keeper":
			return "對話 守墓人"
		&"exit":
			var door := DigEvent.door_at(w, me)
			if door >= 0:
				return "出口：" + WorldLabels.door_text(w, DigEvent.doors(w)[door])
			return "出口：" + ("通關" if w.floor_num >= EventDefs.DIG.last_floor else "前往第 %d 層" % (w.floor_num + 1))
		&"dig":
			return EventDefs.exit_style(w.floor_num).hold
	return ""


static func color(w: World, o: Dictionary) -> Color:
	match o.kind:
		&"pickup":
			return ItemDefs.RARITIES[(w.entities[o.id] as ItemPickup).rarity()].color
		&"chest":
			return UiKit.SOUL
		&"forge", &"relic":
			return WorldLabels.FORGE_COLOR
		&"keeper":
			return WorldLabels.NPC_COLOR
		&"exit":
			return WorldLabels.EXIT_COLOR
	return Color.WHITE
