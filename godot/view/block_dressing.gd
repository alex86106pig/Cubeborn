# 地形石台的造型（桌上模型風格，YangHsu 2026-11-18 選定；三層各自的配色與造型在 PALETTES，沒列的主題照舊用 ArenaView.create_blocks）：
# 碰撞照舊是 World.terrain 的長方體，畫面照種類換成看得出是什麼的樣子
# - 崖壁（地圖邊界：MapGen 把吃進來的邊與地圖外面都記成牆，排在 blocks 最前面 edge_count 個）：外露的邊排一圈高低不一的岩柱、
#   畫成矮土坡，每 6 ~ 12 單位一段各自是鐵柵欄、岩崖、灌木叢或殘牆，碰撞照舊（YangHsu 2026-11-18：墓園用牆框起來很怪、可以做隱形牆、不用全是樹跟柵欄）
# - 牆（地圖裡的障礙物：廢墟殘牆、陵墓）：一段一段砌、每段高低不齊、段與段之間立柱、頂上壓一條蓋石、側面凸出幾塊石頭、底部一圈苔、少數段崩掉一截（腳邊碎石）
#   厚的牆（> WIDE）當成圍起來的一塊：四邊砌牆、中間填土頂
# - 墓碑：圓頂、十字、尖頂、斷碑、肩頂 5 種（照位置挑，大家看到的一樣），底座、刻字面、往鏡頭那邊一塊墳土，微微傾斜
# - 高台：台身 + 外凸的頂石 + 四角石墩
# - 每塊外露的邊腳下一段段的乾草叢（墓園）或碎石（地底，_base_tufts）
# 依主題換的造型（PALETTES 的 wall_mode / fill / tomb_mode / base / eggs）：牆砌石或堆岩塊、厚牆頂是屋頂或粗岩面、墓碑是石碑或蟲卵囊
# 全部疊進同一個頂點色網格，一張圖只畫 1 次（同 ArenaView.create_blocks）
class_name BlockDressing
extends RefCounted

const WIDE := 2.6          # 比這個厚的牆當成圍起來的一塊
const SEG_LEN := 2.0       # 牆每段大約多長
const PLINTH_H := 0.35     # 牆腳那圈石的高度
const CAP_T := 0.16        # 蓋石厚度
const BANK_H := 0.9        # 邊界土坡畫多高（碰撞照舊是牆的高度，隱形）
const FENCE_IN := 0.45     # 鐵柵欄離邊界多遠（往內）
const PLANT_EDGE := 0.4    # 邊界的樹與灌木離土坡另一邊至少多遠
const PLANT_MIN_DEPTH := 0.6   # 土坡往裡擺得下的深度不到這麼多就不擺樹與灌木
const TUFT_MAX := 4000     # 腳邊的乾草叢最多幾叢（每叢約 30 個三角形）

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var _rng := RandomNumberGenerator.new()
var _style: Dictionary
var _to_cam := Vector2(sin(Config.CAMERA.azimuth), cos(Config.CAMERA.azimuth))   # 地面上往鏡頭的方向
var _tuft_count := 0
var _bank_plants := PackedVector2Array()   # 邊界土坡上的樹與灌木站在哪（檢查用：都要站在土坡上，不能浮在旁邊的平地）

# 有造型的主題的配色（頂點色；打光後畫面上約亮 1.3 ~ 1.4 倍）。blocks 是各種石台的 [側面, 頂面]
const PALETTES := {
	&"graveyard": {
		"blocks": {
			# 牆、墓碑、陵墓壓暗（YangHsu 2026-11-18：米白是畫面上最亮的）：牆 #8a8073 / #b3a996、墓碑 #b8b2a6 / #d8d2c4 各暗 12% / 10%
			&"wall": [Color("7a7166"), Color("9e9584")],
			&"tomb": [Color("a6a095"), Color("c2bdb0")],
			&"platform": [Color("5a4d3f"), Color("6e604d")],   # 高台頂面也是地面：跟著壓暗（#a88a6c 在暗土上最刺眼）
		},
		"moss": Color("56683e"), "dirt": Color("5a4330"),
		# 地面（GroundDressing）：墓園內是土色、不要綠、不要太亮（YangHsu 2026-11-18）→ 照 media.io 墓園配色「Dusk Lantern」(#4F3B2B ~ #8A6B4D) 的暗灰褐土
		"grass": [Color("4a3f33"), Color("554a3c"), Color("605345")], "ground_dirt": Color("3f362c"), "dirt_mix": 0.35,
		"roof": Color("7e766a"),
		"tuft": [Color("6e6248"), Color("786a4c"), Color("665c46")],   # 乾草尖：只比地面亮一點、偏黃一點
		"cliff": [Color("6c6359"), Color("5f6e45")], "foliage": Color("4b5d38"), "iron": Color("2a282d"), "bark": Color("4a3a2c"),
		"wall_mode": &"masonry", "fill": &"roof", "tomb_mode": &"headstone", "base": &"tuft",
	},
	# 第 2 層地下墓窟（YangHsu 2026-11-18：2、3 層也改）：冷灰褐的石地、砌石牆、厚岩壁頂是粗岩面；墓碑是骨白石碑（地底不放墳土）、牆腳碎石
	&"catacomb": {
		"blocks": {
			&"wall": [Color("55585c"), Color("6c6f73")],   # 冷灰石（三層要一眼分得出：墓園暖褐、墓窟藍灰、墓道灰綠）
			&"tomb": [Color("8b8477"), Color("a29c8c")],
			&"platform": [Color("554a40"), Color("665a4d")],   # 舊石台
		},
		"moss": Color("3d4434"),
		"grass": [Color("4a4e54"), Color("53575d"), Color("5c6066")], "ground_dirt": Color("3f4348"), "dirt_mix": 0.35,   # 藍灰石地（暖光下畫面上是冷灰，跟墓園的褐土分開）
		"rock_top": Color("3a3530"), "rubble": [Color("5a544c"), Color("6a6358"), Color("4c463f")],
		"wall_mode": &"masonry", "fill": &"rock", "tomb_mode": &"stele", "base": &"rubble",
	},
	# 第 3 層蟲蝕墓道：濕的橄欖褐土、牆是一排高低不齊的岩塊（不砌）、墓碑是蟲卵囊、高台是結殼的土丘上面一窩窩蟲卵
	&"burrow": {
		"blocks": {
			&"wall": [Color("3e3a31"), Color("524d41")],   # 深灰褐的岩塊，跟地面拉開（同色會糊成一片）
			&"tomb": [Color("77755a"), Color("8e8c69")],   # 卵囊：原本 #8c8a5e / #a8a670 太亮、太黃（像仙人掌）
			&"platform": [Color("4f4636"), Color("61573f")],
		},
		"grass": [Color("4a5045"), Color("52594c"), Color("5b6254")], "ground_dirt": Color("404539"), "dirt_mix": 0.35,   # 灰綠的苔蘚濕土（彩度壓低；偏黃的像沙漠、灰褐的跟墓窟分不出來）
		"rock_top": Color("37332a"), "rubble": [Color("524b3c"), Color("463f33"), Color("5d5544")], "egg": [Color("b4b884"), Color("a6ab78")],
		"wall_mode": &"rock", "fill": &"rock", "tomb_mode": &"pod", "base": &"rubble", "eggs": true,
	},
}


# 這個主題有沒有造型的配色；沒有回傳空的（照舊用 ArenaView.create_blocks 的方塊）
static func palette(theme: StringName) -> Dictionary:
	return PALETTES.get(theme, {})
var _walls: Array[Dictionary] = []   # 全部的牆（算哪一邊跟別的牆貼著、不用砌）


# edge_count：blocks 最前面幾個是地圖邊界（World.map.edge_blocks）
static func build(blocks: Array[Dictionary], style: Dictionary, seed_value: int, edge_count := 0) -> MeshInstance3D:
	var d := BlockDressing.new()
	d._style = style
	d._rng.seed = seed_value
	for b in blocks:
		if b.kind == &"wall":
			d._walls.append(b)
	for i in blocks.size():
		var b := blocks[i]
		if i < edge_count:
			d._cliff(b)
			continue
		var c: Array = style.blocks.get(b.kind, style.blocks[&"platform"])
		match b.kind:
			&"wall":
				d._wall(b, c)
			&"tomb":
				d._tomb(b, c)
			_:
				d._platform(b, c)
	d._base_tufts(blocks)
	var mi := MeshInstance3D.new()
	mi.mesh = PartKit.array_mesh(d.verts, d.normals, d.colors)
	mi.set_meta(&"tufts", d._tuft_count)   # 檢查用（map_checks：草叢的程式中途出錯會一叢都沒有、不會報錯）
	mi.set_meta(&"bank_plants", d._bank_plants)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	mi.material_override = m
	return mi


# 骰子模式用的材質（ArenaView.build 的 cuttable）：看起來同上面的 StandardMaterial3D（頂點色當底色、sRGB、Lambert、不反光），
# 多了 cut_*：擲骰時骰盤（連台座）那塊長方形裡高出地面的頂點壓到地面下（牆、墓碑、樹、土坡都在這個網格裡）。
# 只動頂點、不用 discard（網頁版 discard 會關掉提早的深度測試）；網格要擺在原點、不轉不縮放（ArenaView 照這樣加）
const CUT_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec2 cut_center;
uniform vec2 cut_right = vec2(1.0, 0.0);
uniform vec2 cut_half;
uniform float cut_floor;
uniform float cut_amount;
void vertex() {
	if (cut_amount > 0.0) {
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 d = w.xz - cut_center;
		vec2 l = vec2(dot(d, cut_right), dot(d, vec2(-cut_right.y, cut_right.x)));
		if (abs(l.x) < cut_half.x && abs(l.y) < cut_half.y && w.y > cut_floor - 0.05) {
			VERTEX.y -= (w.y - cut_floor + 0.05) * cut_amount;
		}
	}
	COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""
static var _cut_shader: Shader


static func cut_material() -> ShaderMaterial:
	if _cut_shader == null:
		_cut_shader = Shader.new()
		_cut_shader.code = CUT_SHADER
	var m := ShaderMaterial.new()
	m.shader = _cut_shader
	return m


# ---------- 牆 ----------

func _wall(b: Dictionary, c: Array) -> void:
	var size: Vector2 = b.max - b.min
	if minf(size.x, size.y) > WIDE:
		_enclosure(b, c)
		return
	var along_x := size.x >= size.y
	var length := size.x if along_x else size.y
	var thick := size.y if along_x else size.x
	var mid: Vector2 = (b.min + b.max) / 2.0
	var axis := Vector2(1, 0) if along_x else Vector2(0, 1)
	var side := Vector2(0, 1) if along_x else Vector2(1, 0)
	if _style.wall_mode == &"rock":
		_rock_run(mid - axis * length / 2.0, axis, length, thick, b.top, c)
		return
	_wall_run(mid - axis * length / 2.0, axis, side, length, thick, b.top, c)


# 岩壁（wall_mode = rock）：沿 axis 一塊接一塊高低不齊的大岩塊，最多凸出碰撞 0.2；碰撞照舊是長方體
func _rock_run(start: Vector2, axis: Vector2, length: float, thick: float, top: float, c: Array) -> void:
	var r_max := thick / 2.0 + 0.2
	var u := 0.0
	while u < length - 0.05:
		var r := minf(_rng.randf_range(0.55, 0.95), r_max)
		var p := start + axis * clampf(u + r * 0.7, r * 0.5, length - r * 0.5)
		var rc := _jitter(c[0], 0.08)
		_rock(p, r, top * _rng.randf_range(0.72, 1.0), rc, _jitter(c[1], 0.08))
		u += r * _rng.randf_range(0.9, 1.3)


# 一道牆：起點 start、沿 axis 走 length、厚 thick（side 是厚的方向）
func _wall_run(start: Vector2, axis: Vector2, side: Vector2, length: float, thick: float, top: float, c: Array) -> void:
	var n := maxi(1, roundi(length / SEG_LEN))
	var seg := length / n
	var side_col: Color = c[0]
	var top_col: Color = c[1]
	# 牆腳一圈（比牆身外凸一點、暗一點）
	_obox(start + axis * length / 2.0, 0.0, PLINTH_H, axis, length + 0.1, thick + 0.12, _shade(side_col, 0.82), _shade(top_col, 0.8))
	# 苔：牆腳上緣一圈薄的
	_obox(start + axis * length / 2.0, PLINTH_H - 0.05, 0.18, axis, length + 0.02, thick + 0.06, _style.moss, _style.moss)
	for i in n:
		var center := start + axis * (seg * (i + 0.5))
		var broken := n >= 2 and _rng.randf() < 0.12
		var h := top - 0.2 + _rng.randf_range(-0.08, 0.08)
		if broken:
			h = top * _rng.randf_range(0.5, 0.7)
		var col := _jitter(side_col, 0.07)
		_obox(center, PLINTH_H, h - PLINTH_H, axis, seg - 0.04, thick, col, _jitter(top_col, 0.06))
		if broken:
			# 崩掉的頂：兩塊高低不一的殘石，腳邊幾顆碎石
			for k in 2:
				var off := _rng.randf_range(-seg * 0.3, seg * 0.3)
				_obox(center + axis * off, h, _rng.randf_range(0.2, 0.6), axis, _rng.randf_range(0.4, 0.7), thick * 0.8, col, _jitter(top_col, 0.08))
			for k in _rng.randi_range(3, 5):
				var p := center + axis * _rng.randf_range(-seg / 2.0, seg / 2.0) + side * (thick / 2.0 + _rng.randf_range(0.1, 0.6)) * (1.0 if _rng.randf() < 0.5 else -1.0)
				var s := _rng.randf_range(0.18, 0.4)
				_obox(p, 0.0, s * 0.7, Vector2.from_angle(_rng.randf() * TAU), s, s, _jitter(side_col, 0.1), _jitter(top_col, 0.1))
		else:
			# 蓋石：比牆身寬一點、亮一點
			_obox(center, h, CAP_T, axis, seg - 0.02, thick + 0.16, _shade(top_col, 0.9), _shade(top_col, 1.12))
		# 側面凸出的石塊（像砌的磚）
		for k in _rng.randi_range(0, 2):
			var sgn := 1.0 if _rng.randf() < 0.5 else -1.0
			var p := center + axis * _rng.randf_range(-seg * 0.4, seg * 0.4) + side * sgn * (thick / 2.0 + 0.03)
			var y := _rng.randf_range(PLINTH_H + 0.1, h - 0.4)
			_obox(p, y, _rng.randf_range(0.18, 0.3), axis, _rng.randf_range(0.35, 0.7), 0.1, _jitter(side_col, 0.12), _jitter(side_col, 0.12))
	# 立柱：兩端與段之間，比牆高、外凸，頂上一塊方帽
	var pillar_every := 2 if n >= 3 else 1
	for i in range(0, n + 1, pillar_every):
		var p := start + axis * (seg * i)
		var ph := top + 0.2
		_obox(p, 0.0, ph, axis, 0.55, thick + 0.28, _shade(side_col, 1.05), _shade(top_col, 1.05))
		_obox(p, ph, 0.14, axis, 0.7, thick + 0.42, _shade(top_col, 0.95), _shade(top_col, 1.15))


# 厚的一塊：中間填土頂（比牆低一點、長苔），只在外露的邊砌牆（跟別的牆貼著的那段不砌，不然接縫處會冒出一堆內牆）
func _enclosure(b: Dictionary, c: Array) -> void:
	var x0: float = b.min.x
	var z0: float = b.min.y
	var x1: float = b.max.x
	var z1: float = b.max.y
	var t: float = b.top
	var w := 0.8
	var mid := Vector2((x0 + x1) / 2.0, (z0 + z1) / 2.0)
	var sx := x1 - x0
	var sz := z1 - z0
	if _style.fill == &"rock":
		_rock_fill(b, c, mid, sx, sz)
		return
	# 中間是建築：石頭屋頂（外凸一點）+ 沿長邊的一道屋脊（YangHsu 2026-11-18：原本填草像花台）
	var roof: Color = _style.get("roof", _shade(c[1], 0.8))
	_obox(mid, 0.0, t - 0.1, Vector2(1, 0), sx, sz, _shade(c[0], 0.85), roof)
	_obox(mid, t - 0.1, 0.14, Vector2(1, 0), sx + 0.3, sz + 0.3, _shade(roof, 0.85), roof)
	var along_x := sx >= sz
	var ridge_len := (sx if along_x else sz) - 0.6
	var span := (sz if along_x else sx) + 0.2
	var ridge_h := minf(1.4, span * 0.35)
	var gable := PackedVector2Array([Vector2(-span / 2.0, 0.0), Vector2(span / 2.0, 0.0), Vector2(0.0, ridge_h)])
	var basis := Basis(Vector3.UP, 0.0 if along_x else PI / 2.0) * Basis(Vector3.UP, PI / 2.0)
	_prism(gable, Vector2(0.0, ridge_h / 3.0), ridge_len, Transform3D(basis, Vector3(mid.x, t + 0.04, mid.y)), _shade(roof, 0.9), _shade(roof, 1.05))
	for seg in _exposed(b, &"N"):
		_wall_run(Vector2(seg.x, z0 + w / 2.0), Vector2(1, 0), Vector2(0, 1), seg.y - seg.x, w, t, c)
	for seg in _exposed(b, &"S"):
		_wall_run(Vector2(seg.x, z1 - w / 2.0), Vector2(1, 0), Vector2(0, 1), seg.y - seg.x, w, t, c)
	for seg in _exposed(b, &"W"):
		_wall_run(Vector2(x0 + w / 2.0, seg.x), Vector2(0, 1), Vector2(1, 0), seg.y - seg.x, w, t, c)
	for seg in _exposed(b, &"E"):
		_wall_run(Vector2(x1 - w / 2.0, seg.x), Vector2(0, 1), Vector2(1, 0), seg.y - seg.x, w, t, c)


# 厚的岩壁（fill = rock，地底）：頂是低一點的粗岩面、上面散幾塊岩石；外露的邊照 wall_mode 砌石牆或堆岩塊
func _rock_fill(b: Dictionary, c: Array, mid: Vector2, sx: float, sz: float) -> void:
	var t: float = b.top
	var fill_h := t - 0.35
	var rock_top: Color = _style.rock_top
	_obox(mid, 0.0, fill_h, Vector2(1, 0), sx, sz, _shade(c[0], 0.8), rock_top)
	# 頂上幾塊大岩石（太多太小會像一坑六角形的小餅）
	for k in int(sx * sz / 14.0):
		var p := mid + Vector2(_rng.randf_range(-sx / 2.0 + 1.2, sx / 2.0 - 1.2), _rng.randf_range(-sz / 2.0 + 1.2, sz / 2.0 - 1.2))
		var r := _rng.randf_range(0.6, 1.2)
		_rock(p, r, _rng.randf_range(0.35, 0.8), _jitter(rock_top, 0.1), _jitter(rock_top, 0.1).lightened(0.08), fill_h)
	var w := 0.8
	var rock: bool = _style.wall_mode == &"rock"
	for edge: StringName in [&"N", &"S", &"W", &"E"]:
		var horizontal := edge == &"N" or edge == &"S"
		var line: float
		match edge:
			&"N": line = b.min.y + w / 2.0
			&"S": line = b.max.y - w / 2.0
			&"W": line = b.min.x + w / 2.0
			_: line = b.max.x - w / 2.0
		var axis := Vector2(1, 0) if horizontal else Vector2(0, 1)
		var side := Vector2(0, 1) if horizontal else Vector2(1, 0)
		for seg in _exposed(b, edge):
			var start := Vector2(seg.x, line) if horizontal else Vector2(line, seg.x)
			if rock:
				_rock_run(start, axis, seg.y - seg.x, w, t, c)
			else:
				_wall_run(start, axis, side, seg.y - seg.x, w, t, c)


# 這塊牆某一邊（N = min.y、S = max.y、W = min.x、E = max.x）沒有被別的牆貼住的區段 [起, 迄]（沿那一邊的座標）
func _exposed(b: Dictionary, edge: StringName) -> Array[Vector2]:
	var horizontal := edge == &"N" or edge == &"S"
	var lo: float = b.min.x if horizontal else b.min.y
	var hi: float = b.max.x if horizontal else b.max.y
	var outside: float
	match edge:
		&"N": outside = b.min.y - 0.05
		&"S": outside = b.max.y + 0.05
		&"W": outside = b.min.x - 0.05
		_: outside = b.max.x + 0.05
	var free: Array[Vector2] = [Vector2(lo, hi)]
	for o: Dictionary in _walls:
		if o == b:
			continue
		var o_perp_lo: float = o.min.y if horizontal else o.min.x
		var o_perp_hi: float = o.max.y if horizontal else o.max.x
		if outside <= o_perp_lo or outside >= o_perp_hi:
			continue
		var c0: float = o.min.x if horizontal else o.min.y
		var c1: float = o.max.x if horizontal else o.max.y
		var next: Array[Vector2] = []
		for f in free:
			if c1 <= f.x or c0 >= f.y:
				next.append(f)
				continue
			if c0 > f.x:
				next.append(Vector2(f.x, c0))
			if c1 < f.y:
				next.append(Vector2(c1, f.y))
		free = next
	return free.filter(func(f: Vector2) -> bool: return f.y - f.x > 0.6)


# ---------- 崖壁 ----------

# 地圖邊界的一塊（碰撞照舊是隱形的長方體）：矮土坡（BANK_H，頂上長草）；外露的邊每 6 ~ 12 單位一段，
# 各自是鐵柵欄（+ 枯樹）、岩崖（高岩柱 + 灌木）、灌木叢、殘牆（+ 稀疏的樹），見 _border；石頭最多凸出碰撞邊界 0.25
func _cliff(b: Dictionary) -> void:
	var rock: Color = _style.cliff[0]
	var grass: Color = _style.cliff[1]
	var mid: Vector2 = (b.min + b.max) / 2.0
	var size: Vector2 = b.max - b.min
	_obox(mid, 0.0, BANK_H, Vector2(1, 0), size.x, size.y, _shade(rock, 0.8), grass)
	for edge: StringName in [&"N", &"S", &"W", &"E"]:
		var horizontal := edge == &"N" or edge == &"S"
		var line: float
		var inward: Vector2
		match edge:
			&"N":
				line = b.min.y
				inward = Vector2(0, 1)
			&"S":
				line = b.max.y
				inward = Vector2(0, -1)
			&"W":
				line = b.min.x
				inward = Vector2(1, 0)
			_:
				line = b.max.x
				inward = Vector2(-1, 0)
		var along := Vector2(1, 0) if horizontal else Vector2(0, 1)
		for seg in _exposed(b, edge):
			# 每 6 ~ 12 單位一段，各自抽一種邊界（剩不到 3 的併進這段）
			var cs := seg.x
			while cs < seg.y - 0.01:
				var ce := minf(seg.y, cs + _rng.randf_range(6.0, 12.0))
				if seg.y - ce < 3.0:
					ce = seg.y
				var kind := _pick_border()
				_border(kind, cs, ce, line, horizontal, inward, along, rock, grass, size.y if horizontal else size.x)
				cs = ce


# 邊界的種類（YangHsu 2026-11-18：不用全部都是樹跟柵欄）：柵欄 35%、岩崖 25%、灌木叢 20%、殘牆 20%
func _pick_border() -> StringName:
	var r := _rng.randf()
	if r < 0.35:
		return &"fence"
	if r < 0.6:
		return &"cliff"
	if r < 0.8:
		return &"hedge"
	return &"ruin"


# 邊界的一段 [a, b]（沿 line 那條邊；inward 往碰撞裡面、along 沿著邊；depth = 這塊往裡有多厚，樹與灌木不擺出去）
func _border(kind: StringName, a: float, b: float, line: float, horizontal: bool, inward: Vector2, along: Vector2, rock: Color, grass: Color, depth: float) -> void:
	var at_edge := func(u: float) -> Vector2: return Vector2(u, line) if horizontal else Vector2(line, u)
	# 腳下一排石頭：岩崖是矮而寬的大石塊（高 1.1 ~ 1.9，不是細長柱），其他是矮的護坡；
	# 頂面用亮一點的石色（YangHsu 2026-11-18：看起來怪怪的——草色頂面 + 棕色側面像一排樹樁）
	var tall := kind == &"cliff"
	var u := a + _rng.randf_range(0.0, 0.4)
	while u < b - 0.2:
		var r := _rng.randf_range(0.9, 1.4) if tall else _rng.randf_range(0.4, 0.7)
		var p: Vector2 = at_edge.call(u) + inward * (r - 0.25)
		var h := _rng.randf_range(1.1, 1.9) if tall else BANK_H * _rng.randf_range(0.85, 1.15)
		var rc := _jitter(rock, 0.1)
		_rock(p, r, h, rc, rc.lightened(0.14))
		if _rng.randf() < 0.35:   # 腳邊碎石
			var q := p - inward * (r + _rng.randf_range(-0.1, 0.1)) + along * _rng.randf_range(-0.4, 0.4)
			var s := _rng.randf_range(0.12, 0.25)
			_rock(q, s, s * 0.9, _jitter(rock, 0.12), _jitter(rock, 0.12).lightened(0.08))
		u += r * _rng.randf_range(1.1, 1.6)
	match kind:
		&"fence":
			_fence(at_edge.call(a) + inward * FENCE_IN, along, b - a)
			_border_plants(a, b, at_edge, inward, depth, 0.6, 1.2, 2.4)
		&"cliff":
			_border_plants(a, b, at_edge, inward, depth, 0.15, 1.6, 3.0)
		&"hedge":
			# 一排密的灌木（高 1.2 ~ 1.9），零星幾棵樹
			var v := a + _rng.randf_range(0.0, 0.3)
			while v < b - 0.2:
				var s := _rng.randf_range(0.5, 0.8)
				var q: Vector2 = at_edge.call(v) + inward * (s + 0.2)
				_rock(q, s, _rng.randf_range(1.2, 1.9) - BANK_H, _jitter(_style.foliage, 0.14), _jitter(_style.foliage, 0.12).lightened(0.08), BANK_H)
				v += s * _rng.randf_range(0.9, 1.3)
			_border_plants(a, b, at_edge, inward, depth, 0.3, 2.5, 3.0)
		_:
			# 矮的崩塌石牆（立在土坡上，總高約 2），後面稀疏的樹
			var c: Array = _style.blocks[&"wall"]
			_wall_run(at_edge.call(a) + inward * 0.55, along, inward, b - a, 0.6, BANK_H + _rng.randf_range(0.9, 1.3), c)
			_border_plants(a, b, at_edge, inward, depth, 0.4, 1.6, 3.2)


# 邊界後面（碰撞裡面 1.3 ~ 4.5，不超過這塊的厚度 depth − PLANT_EDGE）：每 step_min ~ step_max 放一棵枯樹（機率 tree_p）或一叢灌木
# 土坡比這薄時往裡擺不下：擺到另一邊的平地上會浮在坡頂高度（YangHsu 2026-11-20 試玩），所以縮到坡裡；太薄（< PLANT_MIN_DEPTH）就不擺
func _border_plants(a: float, b: float, at_edge: Callable, inward: Vector2, depth: float, tree_p: float, step_min: float, step_max: float) -> void:
	var far := minf(4.5, depth - PLANT_EDGE)
	if far < PLANT_MIN_DEPTH:
		return
	var near := minf(1.3, far)
	var u := a + _rng.randf_range(0.3, 1.5)
	while u < b - 0.3:
		var q: Vector2 = at_edge.call(u) + inward * _rng.randf_range(near, far)
		_bank_plants.append(q)
		if _rng.randf() < tree_p:
			_dead_tree(q, _rng.randf_range(2.0, 3.4))
		else:
			var s := _rng.randf_range(0.35, 0.6)
			_rock(q, s, s * 1.2, _jitter(_style.foliage, 0.12), _jitter(_style.foliage, 0.12).lightened(0.06), BANK_H)
		u += _rng.randf_range(step_min, step_max)


# 尖頭鐵柵欄：從 start 沿 along 走 length，立在坡頂；每 2 單位一根粗柱，中間每 0.28 一根細欄杆，上下兩條橫桿
func _fence(start: Vector2, along: Vector2, length: float) -> void:
	var iron: Color = _style.iron
	var y0 := BANK_H
	var a := Vector3(along.x, 0.0, along.y)
	var s0 := Vector3(start.x, y0, start.y)
	for h in [0.22, 1.35]:
		_beam(s0 + Vector3(0, h, 0), s0 + a * length + Vector3(0, h, 0), 0.07, iron)
	var n := maxi(1, roundi(length / 0.28))
	for k in n + 1:
		var p := s0 + a * (length * k / n)
		var post := k % 7 == 0 or k == n
		var h := 1.75 if post else 1.55
		_beam(p, p + Vector3(0, h, 0), 0.14 if post else 0.06, iron)
		# 尖頭：一個小菱形
		var tip := p + Vector3(0, h, 0)
		_beam(tip, tip + Vector3(0, 0.16 if post else 0.12, 0), 0.1 if post else 0.07, iron)


# 枯樹：主幹（底粗頂細兩截）＋ 3 ~ 4 根往上斜的枝、枝上再分一小枝
func _dead_tree(at: Vector2, h: float) -> void:
	var bark: Color = _jitter(_style.bark, 0.1)
	var base := Vector3(at.x, BANK_H, at.y)
	var lean := Vector3(_rng.randf_range(-0.15, 0.15), 0.0, _rng.randf_range(-0.15, 0.15))
	var mid := base + Vector3(0, h * 0.55, 0) + lean * 0.5
	var top := base + Vector3(0, h, 0) + lean
	_beam(base, mid, 0.26, bark)
	_beam(mid, top, 0.16, bark)
	for k in _rng.randi_range(3, 4):
		var from := base.lerp(top, _rng.randf_range(0.45, 0.9))
		var ang := _rng.randf() * TAU
		var len := h * _rng.randf_range(0.25, 0.4)
		var to := from + Vector3(cos(ang) * len, len * _rng.randf_range(0.5, 0.9), sin(ang) * len)
		_beam(from, to, 0.09, bark)
		var twig := to + Vector3(cos(ang + 0.8) * len * 0.4, len * 0.35, sin(ang + 0.8) * len * 0.4)
		_beam(to.lerp(from, 0.3), twig, 0.05, bark)


# 兩點之間的方柱（寬 w）：枝幹、欄杆
func _beam(a: Vector3, b: Vector3, w: float, color: Color) -> void:
	var dir := b - a
	if dir.length_squared() < 1e-8:
		return
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized() * (w / 2.0)
	var z := y.cross(x).normalized() * (w / 2.0)
	var inside := (a + b) / 2.0
	var c := [a - x - z, a + x - z, a + x + z, a - x + z]
	var d := [b - x - z, b + x - z, b + x + z, b - x + z]
	for k in 4:
		_quad(c[k], c[(k + 1) % 4], d[(k + 1) % 4], d[k], color, inside)
	_quad(d[0], d[1], d[2], d[3], color, inside)


# 一塊岩石：不規則的多邊形（7 點）往上擠出 h，上半截再縮小一層；base_y 是底的高度
func _rock(center: Vector2, r: float, h: float, side: Color, top: Color, base_y := 0.0) -> void:
	var pts := PackedVector2Array()
	var a0 := _rng.randf() * TAU
	for k in 7:
		var a := a0 + TAU * k / 7.0 + _rng.randf_range(-0.25, 0.25)
		pts.append(Vector2(cos(a), sin(a)) * r * _rng.randf_range(0.75, 1.0))
	var lower := h * _rng.randf_range(0.55, 0.75)
	var up_basis := Basis(Vector3.RIGHT, -PI / 2.0)   # 輪廓的 (x, y) → 地面的 (x, −z)，擠出方向 → 往上
	_prism(pts, Vector2.ZERO, lower, Transform3D(up_basis, Vector3(center.x, base_y + lower / 2.0, center.y)), side, top)
	var shrink := PackedVector2Array()
	for p in pts:
		shrink.append(p * 0.72)
	_prism(shrink, Vector2.ZERO, h - lower, Transform3D(up_basis, Vector3(center.x, base_y + lower + (h - lower) / 2.0, center.y)), side, top)


# ---------- 墓碑 ----------

func _tomb(b: Dictionary, c: Array) -> void:
	var size: Vector2 = b.max - b.min
	var mid: Vector2 = (b.min + b.max) / 2.0
	var along_x := size.x >= size.y
	var width := maxf(size.x, size.y)
	var thick := minf(size.x, size.y)
	var axis := Vector2(1, 0) if along_x else Vector2(0, 1)
	var face := Vector2(0, 1) if along_x else Vector2(1, 0)
	if face.dot(_to_cam) < 0.0:
		face = -face   # 刻字面朝鏡頭
	if _style.tomb_mode == &"pod":
		_pod(mid, axis, face, width, b.top, c)
		return
	var shape := absi(hash(Vector2i(roundi(mid.x * 10.0), roundi(mid.y * 10.0)))) % 5
	var stone := _jitter(c[0], 0.06)
	var light := _jitter(c[1], 0.06)
	var top: float = b.top
	# 墳土：刻字面那一側，低矮一塊（地底的石碑不放）
	if _style.tomb_mode == &"headstone":
		_obox(mid + face * (thick / 2.0 + 0.75), 0.0, 0.14, axis, width * 0.85, 1.3, _jitter(_style.dirt, 0.08), _jitter(_style.dirt, 0.08).lightened(0.06))
	# 底座
	_obox(mid, 0.0, 0.2, axis, width, thick, _shade(stone, 0.85), _shade(light, 0.9))
	var w := width * 0.82
	var t := thick * 0.55
	var tilt := _rng.randf_range(-0.07, 0.07)
	var lean := _rng.randf_range(-0.05, 0.05)
	var basis := Basis(Vector3.UP, -atan2(axis.y, axis.x)) * Basis(Vector3.BACK, lean) * Basis(Vector3.RIGHT, tilt)
	var origin := Vector3(mid.x, 0.2, mid.y)
	var h := top - 0.2
	match shape:
		0:   # 圓頂
			var pts := PackedVector2Array([Vector2(-w / 2.0, 0.0), Vector2(w / 2.0, 0.0)])
			var r := w / 2.0
			for k in range(0, 9):
				var a := PI * k / 8.0
				pts.append(Vector2(cos(a) * r, h - r + sin(a) * r))
			_prism(pts, Vector2(0, h * 0.4), t, Transform3D(basis, origin), stone, light)
		1:   # 十字
			var bw := w * 0.3
			_prism(_rect(-bw / 2.0, 0.0, bw / 2.0, h), Vector2(0, h / 2.0), t, Transform3D(basis, origin), stone, light)
			_prism(_rect(-w / 2.0, h * 0.58, w / 2.0, h * 0.58 + bw), Vector2(0, h * 0.58 + bw / 2.0), t, Transform3D(basis, origin), stone, light)
		2:   # 尖頂
			var pts := PackedVector2Array([Vector2(-w / 2.0, 0.0), Vector2(w / 2.0, 0.0), Vector2(w / 2.0, h * 0.7), Vector2(0.0, h), Vector2(-w / 2.0, h * 0.7)])
			_prism(pts, Vector2(0, h * 0.4), t, Transform3D(basis, origin), stone, light)
		3:   # 斷碑：上緣參差，斷下來的一塊倒在旁邊
			var pts := PackedVector2Array([Vector2(-w / 2.0, 0.0), Vector2(w / 2.0, 0.0), Vector2(w / 2.0, h * 0.5), Vector2(w * 0.15, h * 0.68), Vector2(-w * 0.1, h * 0.55), Vector2(-w / 2.0, h * 0.74)])
			_prism(pts, Vector2(0, h * 0.3), t, Transform3D(basis, origin), stone, light)
			var piece := mid + face * (thick / 2.0 + 0.45) + axis * (w * 0.3)
			_obox(piece, 0.14, 0.12, axis.rotated(0.5), w * 0.45, 0.35, stone, light)
		_:   # 肩頂：中間高、兩肩低
			var s := w * 0.18
			var pts := PackedVector2Array([Vector2(-w / 2.0, 0.0), Vector2(w / 2.0, 0.0), Vector2(w / 2.0, h * 0.78), Vector2(w / 2.0 - s, h * 0.86), Vector2(w / 2.0 - s * 1.4, h), Vector2(-w / 2.0 + s * 1.4, h), Vector2(-w / 2.0 + s, h * 0.86), Vector2(-w / 2.0, h * 0.78)])
			_prism(pts, Vector2(0, h * 0.4), t, Transform3D(basis, origin), stone, light)
	# 刻字面：深一點的長方形貼在朝鏡頭那面（斷碑與十字不畫）
	if shape == 0 or shape == 2 or shape == 4:
		var plate := Transform3D(basis, origin + basis * Vector3(0.0, 0.0, 0.0))
		var sgn := signf(face.dot(Vector2(-axis.y, axis.x)))   # face 在 basis 的 +z 還是 −z
		var z := (t / 2.0 + 0.012) * (sgn if sgn != 0.0 else 1.0)
		_prism(_rect(-w * 0.3, h * 0.3, w * 0.3, h * 0.62), Vector2(0, h * 0.46), 0.02, plate.translated_local(Vector3(0, 0, z)), _shade(stone, 0.72), _shade(stone, 0.72))


# 蟲卵囊（tomb_mode = pod，蟲蝕墓道的墓碑）：一顆大的結殼卵囊，旁邊兩顆小的；高度同碰撞（擋得住箭）
func _pod(mid: Vector2, axis: Vector2, face: Vector2, width: float, top: float, c: Array) -> void:
	var r := width * 0.42
	_rock(mid, r, top, _jitter(c[0], 0.06), _jitter(c[1], 0.06))
	for sgn: float in [-1.0, 1.0]:
		var p := mid + axis * (r * 0.9 * sgn) + face * _rng.randf_range(0.1, 0.35)
		_rock(p, r * 0.5, top * _rng.randf_range(0.35, 0.5), _jitter(c[0], 0.08), _jitter(c[1], 0.08))


# ---------- 高台 ----------

func _platform(b: Dictionary, c: Array) -> void:
	var size: Vector2 = b.max - b.min
	var mid: Vector2 = (b.min + b.max) / 2.0
	var t: float = b.top
	_obox(mid, 0.0, t - 0.12, Vector2(1, 0), size.x, size.y, _jitter(c[0], 0.05), c[1])
	_obox(mid, t - 0.12, 0.12, Vector2(1, 0), size.x + 0.12, size.y + 0.12, _shade(c[1], 0.92), _shade(c[1], 1.08))
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var p: Vector2 = mid + Vector2(corner.x * (size.x / 2.0), corner.y * (size.y / 2.0))
		_obox(p, 0.0, t + 0.12, Vector2(1, 0), 0.45, 0.45, _shade(c[0], 1.1), _shade(c[1], 1.15))
	if _style.get("eggs", false):
		# 結殼的卵丘：頂上 1 ~ 3 窩蟲卵，每窩 4 ~ 7 顆
		var eggs: Array = _style.egg
		for n in _rng.randi_range(1, 3):
			var at := mid + Vector2(_rng.randf_range(-size.x / 2.0 + 0.6, size.x / 2.0 - 0.6), _rng.randf_range(-size.y / 2.0 + 0.6, size.y / 2.0 - 0.6))
			for k in _rng.randi_range(4, 7):
				var q := at + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 0.3)
				var e: Color = eggs[_rng.randi() % eggs.size()]
				_rock(q, _rng.randf_range(0.09, 0.14), _rng.randf_range(0.18, 0.28), _jitter(e, 0.06), _jitter(e, 0.06).lightened(0.08), t)


# ---------- 腳邊的草 ----------

# 乾草叢（地底是碎石）只長在不常踩的地方：每塊石台外露的邊（牆腳、墓碑腳、邊界土坡腳）往外 0.06 ~ 0.45，一段有一段沒有（墓碑腳下一律長）
# （YangHsu 2026-11-18：空地上一叢叢的乾草看起來很怪——像紙片、散成雜點、比地面亮）
func _base_tufts(blocks: Array[Dictionary]) -> void:
	var placed := 0
	# 倒著排：地圖邊界排在最前面而且邊很長，萬一碰到 TUFT_MAX，先少的是邊界、不是墓碑腳
	for bi in range(blocks.size() - 1, -1, -1):
		var b := blocks[bi]
		for edge: StringName in [&"N", &"S", &"W", &"E"]:
			var horizontal := edge == &"N" or edge == &"S"
			var line: float
			var out: Vector2
			match edge:
				&"N":
					line = b.min.y
					out = Vector2(0, -1)
				&"S":
					line = b.max.y
					out = Vector2(0, 1)
				&"W":
					line = b.min.x
					out = Vector2(-1, 0)
				_:
					line = b.max.x
					out = Vector2(1, 0)
			# 墓碑沒有登記在 _walls（_exposed 只扣掉跟牆貼著的段），整條邊都算
			var segs: Array[Vector2] = [Vector2(b.min.x, b.max.x) if horizontal else Vector2(b.min.y, b.max.y)]
			if b.kind == &"wall":
				segs = _exposed(b, edge)
			for seg in segs:
				var s := seg.x + _rng.randf_range(0.0, 0.4)
				while s < seg.y and placed < TUFT_MAX:
					var at := (Vector2(s, line) if horizontal else Vector2(line, s)) + out * _rng.randf_range(0.06, 0.45)
					s += _rng.randf_range(0.18, 0.45)
					if b.kind != &"tomb" and ArenaView.soft_noise(at.x * 0.6 - 7.0, at.y * 0.6 + 19.0) < 0.42:
						continue   # 這一段不長（墓碑腳下一律長）
					if _style.base == &"rubble":
						if _rng.randf() < 0.5:
							continue   # 碎石比草叢稀
						_pebbles(at)
					else:
						_tuft(at)
					placed += 1
	_tuft_count = placed


# 碎石（base = rubble，地底的牆腳）：1 ~ 2 顆矮的五角石塊
func _pebbles(at: Vector2) -> void:
	var cols: Array = _style.rubble
	var up := Basis(Vector3.RIGHT, -PI / 2.0)
	for k in _rng.randi_range(1, 2):
		var r := _rng.randf_range(0.07, 0.17)
		var q := at + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 0.15)
		var pts := PackedVector2Array()
		var a0 := _rng.randf() * TAU
		for i in 5:
			pts.append(Vector2.from_angle(a0 + TAU * i / 5.0) * r * _rng.randf_range(0.7, 1.0))
		var col: Color = _jitter(cols[_rng.randi() % cols.size()], 0.08)
		var h := r * _rng.randf_range(0.5, 0.8)
		_prism(pts, Vector2.ZERO, h, Transform3D(up, Vector3(q.x, h / 2.0, q.y)), _shade(col, 0.85), col)


# 一叢 12 ~ 18 片細葉：從根部往外倒，根是暗土色、尖是乾草色（頂點色漸變）；葉片兩面都畫，法線一律朝上（受光跟地面一樣，不然背光的面是深色雜點）
func _tuft(at: Vector2) -> void:
	var root_col := _shade(_style.grass[0], 0.8)
	var tips: Array = _style.tuft
	var tip_col: Color = tips[_rng.randi() % tips.size()]
	for k in _rng.randi_range(12, 18):
		var ang := _rng.randf() * TAU
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var lean := _rng.randf_range(0.15, 0.65)
		var h := _rng.randf_range(0.18, 0.38)
		var root := Vector3(at.x, 0.0, at.y) + dir * _rng.randf_range(0.0, 0.07)
		var half_w := Vector3(-dir.z, 0.0, dir.x) * _rng.randf_range(0.016, 0.028)
		var tip := root + dir * h * sin(lean) + Vector3.UP * h * cos(lean)
		var c := _jitter(tip_col, 0.06)
		for order: Array in [[root - half_w, root + half_w, tip], [root + half_w, root - half_w, tip]]:
			for i in 3:
				verts.append(order[i])
				normals.append(Vector3.UP)
				colors.append(c if i == 2 else root_col)


# ---------- 幾何工具 ----------

# 有朝向的長方體：底面中心 center（地面座標）、底面高度 y、高 h、沿 axis 長 len、垂直方向寬 wid；頂面 top、側面 side 色（不畫底面）
func _obox(center: Vector2, y: float, h: float, axis: Vector2, len: float, wid: float, side: Color, top: Color) -> void:
	var a := Vector3(axis.x, 0.0, axis.y).normalized() * (len / 2.0)
	var s := Vector3(-axis.y, 0.0, axis.x).normalized() * (wid / 2.0)
	var o := Vector3(center.x, y, center.y)
	var up := Vector3(0.0, h, 0.0)
	var p00 := o - a - s
	var p10 := o + a - s
	var p11 := o + a + s
	var p01 := o - a + s
	var inside := o + up / 2.0
	_quad(p00 + up, p10 + up, p11 + up, p01 + up, top, inside)
	_quad(p00, p10, p10 + up, p00 + up, side, inside)
	_quad(p10, p11, p11 + up, p10 + up, side, inside)
	_quad(p11, p01, p01 + up, p11 + up, side, inside)
	_quad(p01, p00, p00 + up, p01 + up, side, inside)


# 平面輪廓 pts（x 橫、y 往上，對 fan_at 是星形）沿 z 擠出厚 depth；朝上的側面用 top 色
func _prism(pts: PackedVector2Array, fan_at: Vector2, depth: float, xf: Transform3D, side: Color, top: Color) -> void:
	var hz := depth / 2.0
	var n := pts.size()
	var cf := xf * Vector3(fan_at.x, fan_at.y, hz)
	var cb := xf * Vector3(fan_at.x, fan_at.y, -hz)
	var z_up := (xf.basis * Vector3(0, 0, 1)).normalized().y
	var front_col := top if z_up > 0.5 else side
	var back_col := top if z_up < -0.5 else side
	for i in n:
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[(i + 1) % n]
		var pf := xf * Vector3(p.x, p.y, hz)
		var qf := xf * Vector3(q.x, q.y, hz)
		var pb := xf * Vector3(p.x, p.y, -hz)
		var qb := xf * Vector3(q.x, q.y, -hz)
		var inside := xf * Vector3(fan_at.x, fan_at.y, 0.0)
		_tri(cf, pf, qf, front_col, inside)
		_tri(cb, qb, pb, back_col, inside)
		var nrm := _outward(pf, qf, qb, inside)
		_quad(pf, qf, qb, pb, top if nrm.y > 0.5 else side, inside)


static func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


# 四邊形：兩個三角形；inside 是零件內部的一點，法線一律朝離開它的那邊
func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, inside: Vector3) -> void:
	_tri(a, b, c, color, inside)
	_tri(a, c, d, color, inside)


# 三角形：法線朝外（離開 inside）；Godot 的正面是 cross(b − a, c − a) 跟法線反向，所以照這個排頂點順序
func _tri(a: Vector3, b: Vector3, c: Vector3, color: Color, inside: Vector3) -> void:
	var raw := (b - a).cross(c - a)
	if raw.length_squared() < 1e-10:
		return
	var nrm := _outward(a, b, c, inside)
	verts.append(a)
	if raw.dot(nrm) > 0.0:
		verts.append(c)
		verts.append(b)
	else:
		verts.append(b)
		verts.append(c)
	for k in 3:
		normals.append(nrm)
		colors.append(color)


static func _outward(a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> Vector3:
	var nrm := (b - a).cross(c - a).normalized()
	return -nrm if nrm.dot((a + b + c) / 3.0 - inside) < 0.0 else nrm


func _jitter(c: Color, amount: float) -> Color:
	return _shade(c, 1.0 + _rng.randf_range(-amount, amount))


static func _shade(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k)
