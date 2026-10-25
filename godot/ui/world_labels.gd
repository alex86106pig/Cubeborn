# 場上物件的文字（D3）：沒開的祭壇 / 石棺上方顯示名稱與價格（靈魂不夠時紅色），地上的道具顯示名稱（稀有度顏色）；魔法 / 稀有怪的詞條與名字（D5）
# 本機玩家按得到 F 的那一個加上「[F] 開啟 / 撿起」提示；視野外的不顯示（sim/vision.gd）
class_name WorldLabels
extends Control

const CHEST_OFFSET := 1.6   # 文字在物件腳底上方的高度（世界單位）
const PICKUP_OFFSET := 1.1
const ENEMY_OFFSET := 0.35  # 魔法 / 稀有怪的詞條在頭頂上方多高
const GRAVE_OFFSET := 1.8   # 挖墳點文字的高度（D6）
const GHOST_COLOR := Color("8fd0ff")
const EXIT_COLOR := Color("8fd0ff")

const WARM_SIZES: Array[int] = [14, 15, 17, 18]   # 這裡用到的字級（_text 的 size）
const OUTLINE := 4

var world: World
var camera: Camera3D
var local_peer := World.HOST_PEER_ID
var warm := ""   # 開場預熱（v0.37.2）：HUD 蓋著「準備中」時設定，用同樣的字級與描邊先畫一次，字形在這時候產生


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if warm != "":
		var font := get_theme_default_font()
		for i in WARM_SIZES.size():
			var at := Vector2(40, 60 + i * 120)
			draw_multiline_string_outline(font, at, warm, HORIZONTAL_ALIGNMENT_LEFT, 1800, WARM_SIZES[i], -1, OUTLINE, Color(0, 0, 0, 0.02))
			draw_multiline_string(font, at, warm, HORIZONTAL_ALIGNMENT_LEFT, 1800, WARM_SIZES[i], -1, Color(1, 1, 1, 0.02))
	if world == null or camera == null:
		return
	var me: Player = world.players.get(local_peer)
	var focus: Entity = null
	if me != null and not me.is_dead and not me.is_downed:
		focus = world.nearest_interactable(me, world.pickups)
		if focus == null:
			focus = world.nearest_interactable(me, world.chests)
	var font := get_theme_default_font()
	for c: Entity in world.chests:
		var chest := c as Chest
		if chest.opened or not Vision.entity_visible(world, me, chest):
			continue
		var def: Dictionary = LootDefs.CHESTS[chest.tier]
		var color := UiKit.SOUL if world.souls >= chest.price() else UiKit.ALERT
		var text := "%s  %d 靈魂" % [def.name, chest.price()]
		if chest == focus:
			text = "[F] 開啟 " + text
		_text(font, chest, CHEST_OFFSET, text, color)
	for p: Entity in world.pickups:
		var pickup := p as ItemPickup
		if pickup.is_removed or not Vision.entity_visible(world, me, pickup):
			continue
		var text := pickup.display_name()
		if pickup == focus:
			text = "[F] 撿起 " + text
		_text(font, pickup, PICKUP_OFFSET, text, ItemDefs.RARITIES[pickup.rarity()].color)
	# 魔法 / 稀有怪（D5）：頭上顯示詞條（稀有怪多一行名字）
	for e: Entity in world.enemies:
		var en := e as Enemy
		if en == null or en.is_dead or en.rarity == MonsterRarityDefs.NORMAL or not Vision.entity_visible(world, me, en):
			continue
		var color: Color = MonsterRarityDefs.RARITIES[en.rarity].color
		var offset := en.body_height + ENEMY_OFFSET
		if en.rare_name != "":
			_text(font, en, offset, en.rare_name, color, 18, Vector2(0, -18))
		_text(font, en, offset, MonsterRarityDefs.affix_names(en.affixes), color, 14)
	for e: Entity in world.enemies:
		if e is Enemy and (e as Enemy).ghost_of != 0 and not e.is_dead and Vision.entity_visible(world, me, e):
			_text(font, e, e.body_height + ENEMY_OFFSET, "冤魂：打倒就能復活隊友", GHOST_COLOR, 15)
	_draw_grave(font, me)


# 挖墳點（D6）：沒開始時提示、挖的時候顯示進度、挖完顯示出口與到齊人數
func _draw_grave(font: Font, me: Player) -> void:
	if not DigEvent.enabled(world):
		return
	var ev := world.event
	var at := Vector3(ev.point.x, world.terrain.ground_at(ev.point) + GRAVE_OFFSET, ev.point.y)
	var near := me != null and ev.can_dig(world, me) and not me.is_digging()
	if ev.state == DigEvent.OPEN:
		var total := 0
		var down := 0
		for p in world.player_list:
			if not p.is_dead:
				total += 1
				down += 1 if p.descended else 0
		_text_at(font, at, "出口：走進去前往第 %d 層（%d / %d 人）" % [world.floor_num + 1, down, total], EXIT_COLOR)
		return
	var text := "挖墳 %d%%" % floori(ev.progress * 100.0) if ev.state == DigEvent.ACTIVE else "墓"
	if near:
		text = "[F] 按住挖墳  " + text
	_text_at(font, at, text, UiKit.GOLD if ev.state == DigEvent.ACTIVE else Color.WHITE)


func _text(font: Font, e: Entity, offset: float, text: String, color: Color, size := 17, shift := Vector2.ZERO) -> void:
	_text_at(font, Vector3(e.pos.x, e.height + offset, e.pos.y), text, color, size, shift)


func _text_at(font: Font, at: Vector3, text: String, color: Color, size := 17, shift := Vector2.ZERO) -> void:
	if camera.is_position_behind(at):
		return
	var s := camera.unproject_position(at) + Vector2(-150, 0) + shift
	draw_string_outline(font, s, text, HORIZONTAL_ALIGNMENT_CENTER, 300, size, OUTLINE, Color(0, 0, 0, 0.85))
	draw_string(font, s, text, HORIZONTAL_ALIGNMENT_CENTER, 300, size, color)
