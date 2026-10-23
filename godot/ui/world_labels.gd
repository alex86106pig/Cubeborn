# 場上物件的文字（D3）：沒開的寶箱上方顯示名稱與價格（錢不夠時紅色），地上的道具顯示名稱（稀有度顏色）；魔法 / 稀有怪的詞條與名字（D5）
# 本機玩家按得到 F 的那一個加上「[F] 開啟 / 撿起」提示；視野外的不顯示（sim/vision.gd）
class_name WorldLabels
extends Control

const CHEST_OFFSET := 1.6   # 文字在物件腳底上方的高度（世界單位）
const PICKUP_OFFSET := 1.1
const ENEMY_OFFSET := 0.35  # 魔法 / 稀有怪的詞條在頭頂上方多高

var world: World
var camera: Camera3D
var local_peer := World.HOST_PEER_ID


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
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
		var color := UiKit.GOLD if world.gold >= chest.price() else UiKit.ALERT
		var text := "%s  %d 金幣" % [def.name, chest.price()]
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


func _text(font: Font, e: Entity, offset: float, text: String, color: Color, size := 17, shift := Vector2.ZERO) -> void:
	var at := Vector3(e.pos.x, e.height + offset, e.pos.y)
	if camera.is_position_behind(at):
		return
	var s := camera.unproject_position(at) + Vector2(-150, 0) + shift
	draw_string_outline(font, s, text, HORIZONTAL_ALIGNMENT_CENTER, 300, size, 4, Color(0, 0, 0, 0.85))
	draw_string(font, s, text, HORIZONTAL_ALIGNMENT_CENTER, 300, size, color)
