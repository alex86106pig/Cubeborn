# 場上物件的文字（D3）：沒開的祭壇 / 石棺上方顯示名稱與價格（靈魂不夠時紅色），地上的道具顯示名稱（稀有度顏色）；魔法 / 稀有怪的詞條與名字（D5）
# 本機玩家按得到 F 的那一個加上「[F] 開啟 / 撿起」提示，地上道具再加一張道具卡（形狀、占幾格、效果）；視野外的不顯示（sim/vision.gd）
class_name WorldLabels
extends Control

const CHEST_OFFSET := 1.6   # 文字在物件腳底上方的高度（世界單位）
const PICKUP_OFFSET := 1.1
const ENEMY_OFFSET := 0.35  # 魔法 / 稀有怪的詞條在頭頂上方多高
const GRAVE_OFFSET := 1.8   # 挖墳點文字的高度（D6）
const CARD_W := 300         # 地上道具卡的寬度（px）
const CARD_PAD := 8
const CARD_CELL := 10.0     # 道具卡形狀小圖每格的大小
const CARD_GAP := 24        # 道具卡底部離名稱那一行的距離
const GHOST_COLOR := Color("8fd0ff")
const EXIT_COLOR := Color("8fd0ff")
const FORGE_COLOR := Color("ffb070")   # 鍛造祭壇的名稱（Build 改版第 8 步）
const NPC_COLOR := Color("5fd27a")      # 假裝 NPC 的守墓人：名字與頭上的綠色血條
const NPC_BAR := Vector2(90, 9)
const KEEPER_LINE := "又一頭肥羊……"

const WARM_SIZES: Array[int] = [13, 14, 15, 16, 17, 18, 22]   # 這裡用到的字級（_text、道具卡的 size）
const OUTLINE := 4

var world: World
var camera: Camera3D
var local_peer := World.HOST_PEER_ID
var view_peer := 0   # 觀戰中的隊友（0 = 本機）：看不看得到改用他的視野
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
	var viewer: Player = world.players.get(view_peer if view_peer != 0 else local_peer)   # 看不看得到以他為準（觀戰時是隊友）
	var focus: Entity = null
	if me != null and not me.is_dead and not me.is_downed:
		focus = world.nearest_interactable(me, world.pickups)
		if focus == null:
			focus = world.nearest_interactable(me, world.chests)
		if focus == null:
			focus = world.nearest_interactable(me, world.forges)
	var font := get_theme_default_font()
	for f: Entity in world.forges:
		if f.is_removed or not Vision.entity_visible(world, viewer, f):
			continue
		_text(font, f, CHEST_OFFSET, ("[F] 合成武器 " if f == focus else "") + "鍛造祭壇", FORGE_COLOR)
	for c: Entity in world.chests:
		var chest := c as Chest
		if chest.opened or not Vision.entity_visible(world, viewer, chest):
			continue
		var def: Dictionary = LootDefs.CHESTS[chest.tier]
		var cost := chest.price_for(me)   # 撬鎖工具（G1）：顯示自己開的價格
		var color := UiKit.SOUL if world.souls >= cost else UiKit.ALERT
		var text := "%s  %d 靈魂" % [def.name, cost]
		if chest == focus:
			text = "[F] 開啟 " + text
		_text(font, chest, CHEST_OFFSET, text, color)
	for p: Entity in world.pickups:
		var pickup := p as ItemPickup
		if pickup.is_removed or not Vision.entity_visible(world, viewer, pickup):
			continue
		var text := pickup.display_name()
		if pickup == focus:
			text = "[F] 撿起 " + text
			_draw_card(font, pickup)
		_text(font, pickup, PICKUP_OFFSET, text, ItemDefs.RARITIES[pickup.rarity()].color)
	# 魔法 / 稀有怪（D5）：頭上顯示詞條（稀有怪多一行名字）
	for e: Entity in world.enemies:
		var en := e as Enemy
		if en == null or en.is_dead or en.rarity == MonsterRarityDefs.NORMAL or not Vision.entity_visible(world, viewer, en):
			continue
		var color: Color = MonsterRarityDefs.RARITIES[en.rarity].color
		var offset := en.body_height + ENEMY_OFFSET
		if en.rare_name != "":
			_text(font, en, offset, en.rare_name, color, 18, Vector2(0, -18))
		_text(font, en, offset, MonsterRarityDefs.affix_names(en.affixes), color, 14)
	for e: Entity in world.enemies:
		if e is Enemy and (e as Enemy).ghost_of != 0 and not e.is_dead and Vision.entity_visible(world, viewer, e):
			_text(font, e, e.body_height + ENEMY_OFFSET, "冤魂：打倒就能復活隊友", GHOST_COLOR, 15)
	_draw_keeper(font, me, viewer)
	_draw_grave(font, me)


# 假裝 NPC 的守墓人：頭上名字 + 綠色血條（之後換成畫面上方的 Boss 血條），靠近時「[F] 對話」；
# 被說話揭穿時頭上冒台詞（被打或開挖揭穿的不說話）
func _draw_keeper(font: Font, me: Player, viewer: Player) -> void:
	var keeper := world.entities.get(world.boss_id) as Gravekeeper
	if keeper == null or keeper.is_dead or not Vision.entity_visible(world, viewer, keeper):
		return
	var top := keeper.body_height + ENEMY_OFFSET
	var state: StringName = keeper.anim.get("state", &"")
	if state == &"patrol":
		var label := "守墓人"
		if me != null and keeper.can_talk(me):
			label = "[F] 對話  " + label
		_text(font, keeper, top + 0.5, label, NPC_COLOR, 17, Vector2(0, -12))
		var at := Vector3(keeper.pos.x, keeper.height + top, keeper.pos.y)
		if not camera.is_position_behind(at):
			var s := camera.unproject_position(at) + Vector2(-NPC_BAR.x / 2.0, 0)
			draw_rect(Rect2(s, NPC_BAR), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(s + Vector2(1, 1), Vector2((NPC_BAR.x - 2) * keeper.hp / keeper.max_hp, NPC_BAR.y - 2)), NPC_COLOR)
	elif keeper.anim.get("spoke", false):
		_text(font, keeper, top + 0.3, KEEPER_LINE, Color.WHITE, 22)


# 挖墳點（D6）：沒開始時提示、挖的時候顯示進度、挖完提示按 F 前往下一層（投票中由 HUD 顯示）
func _draw_grave(font: Font, me: Player) -> void:
	if not DigEvent.enabled(world):
		return
	var ev := world.event
	var at := Vector3(ev.point.x, world.terrain.ground_at(ev.point) + GRAVE_OFFSET, ev.point.y)
	var near := me != null and ev.can_dig(world, me) and not me.is_digging()
	if ev.state == DigEvent.OPEN:
		var dest := "通關" if world.floor_num >= EventDefs.DIG.last_floor else "前往第 %d 層" % (world.floor_num + 1)
		var key := "[F] " if me != null and ev.can_exit(world, me) and not ev.is_voting() else ""
		_text_at(font, at, "出口：%s%s" % [key, dest], EXIT_COLOR)
		return
	var text := "挖墳 %d%%" % floori(ev.progress * 100.0) if ev.state == DigEvent.ACTIVE else "墓"
	if near:
		text = "[F] 按住挖墳  " + text
	_text_at(font, at, text, UiKit.GOLD if ev.state == DigEvent.ACTIVE else Color.WHITE)


# 按得到 F 的地上道具：名稱上方的道具卡，撿之前就看得到形狀、占幾格、效果 / 詞條（和背包的說明欄同一份文字）
func _draw_card(font: Font, pickup: ItemPickup) -> void:
	var at := Vector3(pickup.pos.x, pickup.height + PICKUP_OFFSET, pickup.pos.y)
	if camera.is_position_behind(at):
		return
	var info := UiKit.item_info(pickup.item_id, pickup.weapon)
	var color: Color = info.color
	var shape := UiKit.shape_size(pickup.item_id, CARD_CELL)
	var body := "\n".join(info.lines)
	var text_w := CARD_W - CARD_PAD * 2
	var body_h := font.get_multiline_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, text_w, 14).y
	var head_h := maxf(shape.y, 40.0)
	var h := CARD_PAD * 2 + head_h + 6 + body_h
	var r := Rect2(camera.unproject_position(at) + Vector2(-CARD_W / 2.0, -CARD_GAP - h), Vector2(CARD_W, h))
	draw_rect(r, Color(0.04, 0.05, 0.08, 0.88))
	draw_rect(r, Color(color, 0.6), false, 1.0)
	var p := r.position + Vector2(CARD_PAD, CARD_PAD)
	UiKit.draw_shape(self, pickup.item_id, p + Vector2(0, (head_h - shape.y) / 2.0), CARD_CELL, color)
	var tx := p.x + shape.x + 10
	draw_string(font, Vector2(tx, p.y + 17), info.title, HORIZONTAL_ALIGNMENT_LEFT, r.end.x - CARD_PAD - tx, 16, color)
	draw_string(font, Vector2(tx, p.y + 37), "占 %d 格" % Inventory.cells_of(pickup.item_id, 0).size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.7))
	draw_multiline_string(font, Vector2(p.x, p.y + head_h + 6 + 14), body, HORIZONTAL_ALIGNMENT_LEFT, text_w, 14, -1, Color(1, 1, 1, 0.9))


func _text(font: Font, e: Entity, offset: float, text: String, color: Color, size := 17, shift := Vector2.ZERO) -> void:
	_text_at(font, Vector3(e.pos.x, e.height + offset, e.pos.y), text, color, size, shift)


func _text_at(font: Font, at: Vector3, text: String, color: Color, size := 17, shift := Vector2.ZERO) -> void:
	if camera.is_position_behind(at):
		return
	var s := camera.unproject_position(at) + Vector2(-150, 0) + shift
	draw_string_outline(font, s, text, HORIZONTAL_ALIGNMENT_CENTER, 300, size, OUTLINE, Color(0, 0, 0, 0.85))
	draw_string(font, s, text, HORIZONTAL_ALIGNMENT_CENTER, 300, size, color)
