# 場上物件的文字（D3）：沒開的祭壇 / 石棺上方顯示名稱與價格（靈魂不夠時紅色），地上的道具顯示名稱（稀有度顏色）；魔法 / 稀有怪的詞條與名字（D5）
# 本機玩家按得到 F 的那一個加上「[F] 開啟 / 撿起」提示，地上道具再加一張道具卡（形狀、占幾格、效果）；視野外的不顯示（sim/vision.gd）
class_name WorldLabels
extends Control

const CHEST_OFFSET := 1.6   # 文字在物件腳底上方的高度（世界單位）
const PICKUP_OFFSET := 1.1
const ENEMY_OFFSET := 0.35  # 魔法 / 稀有怪的詞條在頭頂上方多高
const GRAVE_OFFSET := 1.8   # 挖墳點文字的高度（D6）
const CARD_W := 400         # 地上道具卡的寬度（px）：武器的「單手・攻擊力・攻速・範圍」與最長的分支詞條各塞一行
const CARD_PAD := 8
const CARD_CELL := 10.0     # 道具卡形狀小圖每格的大小
const CARD_GAP := 24        # 道具卡底部離名稱那一行的距離
const GHOST_COLOR := Color("8fd0ff")
const ARMED_COLOR := Color("d8d2bf")   # 持武器腐屍的名字
const EXIT_COLOR := Color("8fd0ff")
const FORGE_COLOR := Color("ffb070")   # 鍛造祭壇的名稱（Build 改版第 8 步）
const NPC_COLOR := Color("5fd27a")      # 假裝 NPC 的守墓人：名字與頭上的綠色血條
const NPC_BAR := Vector2(90, 9)
const KEEPER_LINE := "又一頭肥羊……"
const LABEL_W := 300        # 名稱文字置中的寬度（px）
const LABEL_GAP := 4        # 物件名稱互相錯開時的間距（px）
const LABEL_TRIES := 4      # 最多往上錯開幾次（再多就疊著畫）

const WARM_SIZES: Array[int] = [13, 14, 15, 16, 17, 18, 22]   # 這裡用到的字級（_text、道具卡的 size）
const OUTLINE := 4

var world: World
var camera: Camera3D
var local_peer := World.HOST_PEER_ID
var view_peer := 0   # 觀戰中的隊友（0 = 本機）：看不看得到改用他的視野
var fade_of := Callable()   # 實體 id → 模型的顯示程度 0~1（WorldView.fade_level）：祭壇 / 石棺的名稱跟著模型淡入淡出；沒設定就照看不看得到直接出現 / 消失
var detail_held := false   # 按住 Alt（每幀更新）：按得到 F 的地上武器 / 道具才畫說明卡（2026-10-30 使用者）
var warm := ""   # 開場預熱（v0.37.2）：HUD 蓋著「準備中」時設定，用同樣的字級與描邊先畫一次，字形在這時候產生
var _placed: Array[Rect2] = []   # 這一幀已經畫的物件名稱（鍛造祭壇、寶箱、地上道具）的範圍，後畫的碰到就往上錯開


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	detail_held = Input.is_key_pressed(KEY_ALT)
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
	_placed.clear()
	# 按得到 F 的地上道具先畫（名稱留在原位，其他名稱讓開）；說明卡最後畫，蓋在所有名稱上面
	var card: ItemPickup = null
	var focus_pickup := focus as ItemPickup
	if focus_pickup != null and Vision.entity_visible(world, viewer, focus_pickup):
		_text(font, focus_pickup, PICKUP_OFFSET, pickup_text(focus_pickup.display_name(), true, detail_held), ItemDefs.RARITIES[focus_pickup.rarity()].color, 17, Vector2.ZERO, true)
		if detail_held:
			card = focus_pickup
	for f: Entity in world.forges:
		if f.is_removed or not Vision.entity_visible(world, viewer, f):
			continue
		_text(font, f, CHEST_OFFSET, ("[F] 合成武器 " if f == focus else "") + "鍛造祭壇", FORGE_COLOR, 17, Vector2.ZERO, true)
	# 鐵砧（小關起點旁）：自己還沒用過、走得到時提示 [F]
	for r: Entity in world.relics:
		var relic := r as Relic
		if relic.relic_kind != &"anvil" or relic.is_removed or not Vision.entity_visible(world, viewer, relic):
			continue
		var used := me != null and relic.taken.has(me.peer_id)
		var key := "[F] 升級武器 " if me != null and not used and world.can_reach(me, relic) else ""
		_text(font, relic, CHEST_OFFSET, key + ("鐵砧（用過了）" if used else "鐵砧"), FORGE_COLOR, 17, Vector2.ZERO, true)
	for c: Entity in world.chests:
		var chest := c as Chest
		if chest.opened:
			continue
		var level: float = fade_of.call(chest.id) if fade_of.is_valid() else (1.0 if Vision.entity_visible(world, viewer, chest) else 0.0)
		if level <= 0.0:
			continue
		var def: Dictionary = LootDefs.CHESTS[chest.tier]
		var cost := chest.price_for(me)   # 撬鎖工具（G1）：顯示自己開的價格
		var color := UiKit.SOUL if world.souls >= cost else UiKit.ALERT
		var text := "%s  %d 靈魂" % [def.name, cost]
		if chest == focus:
			text = "[F] 開啟 " + text
		_text(font, chest, CHEST_OFFSET, text, color, 17, Vector2.ZERO, true, level)
	for p: Entity in world.pickups:
		var pickup := p as ItemPickup
		if pickup == focus or pickup.is_removed or not Vision.entity_visible(world, viewer, pickup):
			continue
		_text(font, pickup, PICKUP_OFFSET, pickup.display_name(), ItemDefs.RARITIES[pickup.rarity()].color, 17, Vector2.ZERO, true)
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
	# 撿到武器的腐屍：頭上「持〇腐屍」（客戶端看動畫欄位 weapon），魔法 / 稀有怪疊在詞條與名字上面
	for e: Entity in world.enemies:
		var en := e as Enemy
		if en == null or en.is_dead or not en.anim.has("weapon") or not Vision.entity_visible(world, viewer, en):
			continue
		var lift := 0.0 if en.rarity == MonsterRarityDefs.NORMAL else (-36.0 if en.rare_name != "" else -18.0)
		_text(font, en, en.body_height + ENEMY_OFFSET, "持%s腐屍" % EnemyDefs.armed_kit(StringName(en.anim.weapon)).name, ARMED_COLOR, 14, Vector2(0, lift))
	for g: Player in world.ghosts:
		if not g.is_dead and Vision.entity_visible(world, viewer, g):
			_text(font, g, g.body_height + ENEMY_OFFSET, ghost_label(world, g), GHOST_COLOR, 15)
	_draw_keeper(font, me, viewer)
	_draw_grave(font, me)
	_draw_doors(font, me)
	if card != null:
		_draw_card(font, card)


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
		var at := WorldView.render_pos(keeper, top)
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
	var style := EventDefs.exit_style(world.floor_num)
	var text: String = "%s %d%%" % [style.doing, floori(ev.progress * 100.0)] if ev.state == DigEvent.ACTIVE else style.idle
	if near:
		text = "[F] %s  %s" % [style.hold, text]
	_text_at(font, at, text, UiKit.GOLD if ev.state == DigEvent.ACTIVE else Color.WHITE)


# 小關出口的門：門上寫下一關與獎勵（一扇門的關：下一關有鐵砧），站在門前提示 [F]（投票中由 HUD 顯示）
func _draw_doors(font: Font, me: Player) -> void:
	var list := DigEvent.doors(world)
	var mine := DigEvent.door_at(world, me) if me != null else -1
	for i in list.size():
		var d: Dictionary = list[i]
		var p := MapDefs.to_world(world.map, d.at)
		var at := Vector3(p.x, world.terrain.ground_at(p) + GRAVE_OFFSET, p.y)
		var key := "[F] " if i == mine and not world.event.is_voting() else ""
		_text_at(font, at, "%s%s" % [key, door_text(world, d)], EXIT_COLOR)


# 冤魂頭上的字：「P2 的冤魂：打倒就能復活」（P 幾照 peer id 排序，同 PlayerTags）
static func ghost_label(world: World, g: Player) -> String:
	var peers: Array = world.players.keys()
	peers.sort()
	var i := peers.find(g.ghost_of)
	return "%s的冤魂：打倒就能復活" % ("P%d " % (i + 1) if i >= 0 else "隊友")


# 「前往 1-3 · 遺物」；一扇門的關沒有獎勵、下一關有鐵砧
static func door_text(world: World, d: Dictionary) -> String:
	var dest := "前往 %s" % World.level_name(world.floor_num, world.stage_num + 1)
	var reward: StringName = d.get("reward", &"")
	if reward == &"":
		return dest + " · 鐵砧"
	return "%s · %s" % [dest, UiKit.reward_name(world, reward)]


# 按得到 F 的地上道具：名稱上方的道具卡，撿之前就看得到形狀、占幾格、效果 / 詞條（和背包的說明欄同一份文字）
# 地上道具 / 武器的名稱：按得到 F 的那一件加「[F] 撿起」，沒按 Alt 時再提示「[Alt] 詳細」（按住 Alt 才畫說明卡）
static func pickup_text(name: String, is_focus: bool, held: bool) -> String:
	if not is_focus:
		return name
	return "[F] 撿起 " + name + ("" if held else "  [Alt] 詳細")


func _draw_card(font: Font, pickup: ItemPickup) -> void:
	var at := Vector3(pickup.pos.x, pickup.height + PICKUP_OFFSET, pickup.pos.y)
	if camera.is_position_behind(at):
		return
	var info := UiKit.item_info(pickup.item_id, pickup.weapon)
	var color: Color = info.color
	var shape := UiKit.shape_size(pickup.item_id, CARD_CELL)
	var text_w := CARD_W - CARD_PAD * 2
	var body_h := UiKit.draw_rich_lines(null, font, Vector2.ZERO, info.lines, text_w, 14)
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
	UiKit.draw_rich_lines(self, font, Vector2(p.x, p.y + head_h + 6), info.lines, text_w, 14)


# avoid：物件名稱（不會動的東西）碰到這一幀已經畫的名稱就往上錯開一行；怪物頭上的字不錯開（會跟著動、錯開會跳來跳去）
func _text(font: Font, e: Entity, offset: float, text: String, color: Color, size := 17, shift := Vector2.ZERO, avoid := false, alpha := 1.0) -> void:
	_text_at(font, WorldView.render_pos(e, offset), text, color, size, shift, avoid, alpha)


# alpha：文字與描邊一起淡（跟著模型淡入淡出）
func _text_at(font: Font, at: Vector3, text: String, color: Color, size := 17, shift := Vector2.ZERO, avoid := false, alpha := 1.0) -> void:
	if camera.is_position_behind(at):
		return
	var s := camera.unproject_position(at) + Vector2(-LABEL_W / 2.0, 0) + shift
	if avoid:
		s.y = place_label(_placed, s.x + LABEL_W / 2.0, s.y, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x, size)
	draw_string_outline(font, s, text, HORIZONTAL_ALIGNMENT_CENTER, LABEL_W, size, OUTLINE, Color(0, 0, 0, 0.85 * alpha))
	draw_string(font, s, text, HORIZONTAL_ALIGNMENT_CENTER, LABEL_W, size, Color(color, color.a * alpha))


# 名稱的基線 y：從 y 開始，碰到 placed 裡的範圍就往上一行，最多 LABEL_TRIES 次；放好的範圍加進 placed
static func place_label(placed: Array[Rect2], center_x: float, y: float, width: float, size: int) -> float:
	var r := Rect2(center_x - width / 2.0, y - size, width, size + LABEL_GAP)
	for i in LABEL_TRIES:
		var hit := false
		for other in placed:
			if other.intersects(r):
				r.position.y = other.position.y - r.size.y
				hit = true
				break
		if not hit:
			break
	placed.append(r)
	return r.position.y + size
