# 骰子模式的場上標示（畫面層；docs/系統說明.md §55「霧牆」「怪群難度」）：
#   戰場霧牆：照 World.dice 的 arena_center / arena_radius 畫一圈半透明的霧，下面濃、往上淡、繞著圈慢慢流動；開打時淡入、打完淡出
#     （碰撞：出不去、圈外的怪不會發現，在模擬層 DiceRun）
#   怪群難度：逛地圖時每群還沒醒的怪頭上立一張遭遇卡「一般 ×3 / 菁英 ×4」（幾隻活著）、Boss 標「Boss」，離自己 TAG_RANGE 內才標
#     （桌邊配件，對比頁方案 1：紙色卡片、框色照難度）
class_name DiceArenaView
extends Node3D

const HEIGHT := 3.2
const FADE_TIME := 0.5
const TAG_RANGE := 34.0
const TAG_HEIGHT := 3.4
const TAG_COLORS := {&"normal": Color("7a5a38"), &"elite": Color("e0a020"), &"boss": Color("d0402f")}   # 遭遇卡的框
const TAG_PAPER := Color("efe4cc")
const TAG_INK := Color("3a2a1a")
const TAG_PAD := Vector2(0.45, 0.3)   # 卡片比字多出來的邊（左右、上下各一半）
const TAG_BORDER := 0.09
const TAG_WARM := "一般菁英Boss ×0123456789"
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.84, 0.87, 0.92, 1.0);
uniform float strength = 0.0;
void fragment() {
	float low = pow(clamp(UV.y, 0.0, 1.0), 1.4);
	float a = sin(UV.x * 50.0 + TIME * 0.7 + UV.y * 4.0) * 0.5 + 0.5;
	float b = sin(UV.x * 21.0 - TIME * 0.45 - UV.y * 7.0) * 0.5 + 0.5;
	ALBEDO = tint.rgb;
	ALPHA = strength * low * (0.55 + 0.4 * a * b);
}
"""

var strength := 0.0   # 現在的濃度（0~1，檢查讀）
var warming := false  # 開場預熱中：霧擺在鏡頭前露出來（WorldView.warm_up），不照 World.dice
var _mesh := MeshInstance3D.new()
var _mat := ShaderMaterial.new()
var _tags: Array[Label3D] = []
var tag_texts: Array[String] = []   # 這一幀標了哪些（檢查讀）


func _init() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = HEIGHT
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 96
	cyl.rings = 1
	var shader := Shader.new()
	shader.code = SHADER
	_mat.shader = shader
	cyl.material = _mat
	_mesh.mesh = cyl
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.position.y = HEIGHT / 2.0 - 0.2
	_mesh.visible = false
	add_child(_mesh)   # 只藏霧（藏整個節點的話，頭上的難度標示也會一起不見）


# 每幀（WorldView.sync）：有霧牆就移到圈上、淡入；沒有就淡出（停在原地）；me：照誰的位置決定標哪些怪群
func sync(world: World, dt: float, me: Player = null) -> void:
	if warming:
		return
	var dice := world.dice if world != null else null
	_sync_tags(world, dice, me)
	var on := dice != null and dice.arena_radius > 0.0
	if on:
		_mesh.position = Vector3(dice.arena_center.x, HEIGHT / 2.0 - 0.2, dice.arena_center.y)
		_mesh.scale = Vector3(dice.arena_radius, 1.0, dice.arena_radius)
	strength = move_toward(strength, 1.0 if on else 0.0, dt / FADE_TIME)
	_mesh.visible = strength > 0.0
	_mat.set_shader_parameter(&"strength", strength)


# 霧現在看不看得到、圈的中心（地上）與半徑（檢查讀）
func fog_shown() -> bool:
	return _mesh.visible


# 畫面上真的看得到的難度標示幾個（含上層節點有沒有藏起來）
func visible_tags() -> int:
	return _tags.filter(func(t: Label3D) -> bool: return t.is_visible_in_tree()).size()


func fog_circle() -> Vector3:
	return Vector3(_mesh.position.x, _mesh.scale.x, _mesh.position.z)


# 開場預熱：霧在 center 圍一小圈露出來畫幾幀（第一次開打才不會當場編譯霧的著色器）、立一張寫滿會用到的字的遭遇卡
# （卡片的材質與 3D 字的字形先產生）；end_warm_up 收掉
func warm_up(center: Vector3) -> void:
	warming = true
	_put_tag(0, Vector2(center.x, center.z), &"elite", 0)
	_tags[0].text = TAG_WARM
	_mesh.position = center + Vector3(0, HEIGHT / 2.0 - 0.2, 0)
	_mesh.scale = Vector3(4.0, 1.0, 4.0)
	_mesh.visible = true
	_mat.set_shader_parameter(&"strength", 1.0)


func end_warm_up() -> void:
	warming = false
	clear()
	_mat.set_shader_parameter(&"strength", 0.0)


func clear() -> void:
	strength = 0.0
	_mesh.visible = false
	for t in _tags:
		t.visible = false


func _sync_tags(world: World, dice: DiceRun, me: Player) -> void:
	tag_texts.clear()
	var n := 0
	if dice != null and dice.phase == DiceRun.EXPLORE:
		var r2 := TAG_RANGE * TAG_RANGE
		for pk: Dictionary in world.packs:
			if pk.awake:
				continue
			var alive := 0
			var elite := false
			for id: int in pk.ids:
				var e := world.entities.get(id) as Enemy
				if e != null and not e.is_dead:
					alive += 1
					elite = elite or e.rarity != MonsterRarityDefs.NORMAL
			if alive == 0 or (me != null and me.pos.distance_squared_to(pk.center) > r2):
				continue
			_put_tag(n, pk.center, &"elite" if elite else &"normal", alive)
			n += 1
		var boss := world.entities.get(world.boss_id) as Enemy
		if boss != null and not boss.is_dead and (me == null or me.pos.distance_squared_to(boss.pos) <= r2):
			_put_tag(n, boss.pos, &"boss", 1)
			n += 1
	for i in range(n, _tags.size()):
		_tags[i].visible = false


func _put_tag(i: int, at: Vector2, tier: StringName, count: int) -> void:
	if i >= _tags.size():
		var t := Label3D.new()
		t.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		t.no_depth_test = true
		t.font = load("res://assets/fonts/hud_font.tres")
		t.font_size = 56
		t.outline_size = 0
		t.pixel_size = 0.012
		t.modulate = TAG_INK
		t.render_priority = 2
		for k in 2:   # 卡片：先畫框（大一圈），再畫紙；都面向鏡頭、看穿牆，字畫在最上面
			var card := MeshInstance3D.new()
			card.mesh = QuadMesh.new()
			card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mat.no_depth_test = true
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = TAG_PAPER
			mat.render_priority = k
			card.material_override = mat
			t.add_child(card)
		add_child(t)
		_tags.append(t)
	var tag := _tags[i]
	var text: String = ("%s ×%d" % [DiceDefs.FIGHT_TIERS[tier].name, count]) if tier != &"boss" else "Boss"
	if tag.text != text:
		tag.text = text
		var w := tag.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, tag.font_size).x * tag.pixel_size
		var paper := Vector2(w, tag.font_size * tag.pixel_size * 1.1) + TAG_PAD
		(tag.get_child(0).mesh as QuadMesh).size = paper + Vector2.ONE * TAG_BORDER * 2.0
		(tag.get_child(1).mesh as QuadMesh).size = paper
	(tag.get_child(0).material_override as StandardMaterial3D).albedo_color = TAG_COLORS[tier]
	tag.position = Vector3(at.x, TAG_HEIGHT, at.y)
	tag.visible = true
	tag_texts.append(text)
