# 技能欄與選角畫面的向量圖示：打包字型沒有 ⚔ 🛡 ✦ ✺ ⟳（翻滾），其他招式原本只寫兩個字（2026-10-27 補畫），直接用線條與多邊形畫（約 28 像素見方）
# 招式的 icon（WeaponDefs）是這裡的名稱；不在 DRAWN 裡的照字面顯示文字
class_name SkillIcons

const DRAWN: Array[String] = ["⚔", "🛡", "✦", "✺", "⟳", "parry", "passive",
	"bow_shot", "bow_fan", "bow_heavy", "bow_pierce", "dagger_combo", "shadow_step", "mace_smash", "holy_circle",
	"torch_swing", "torch_raise", "torch_plant", "fire_breath", "shovel_dig", "shovel_grab", "shovel_throw", "shovel_bury"]

const STEEL := Color("dfe8ff")
const HILT := Color("c9a46a")
const SHIELD := Color("6f86b8")
const SHIELD_RIM := Color("dfe8ff")
const BOLT := Color("7fd8ff")      # 魔彈顏色（weapon_defs 的 staff.attack.color）
const BURST := Color("c77dff")     # 奧術爆裂顏色（staff.special.color）
const ROLL := Color("e8eef8")
const OUTLINE := Color(0, 0, 0, 0.9)
const WOOD := Color("9a7048")
const FEATHER := Color("e8e2d0")
const FIRE := Color("ff9a2e")
const FIRE_CORE := Color("ffe27a")
const HOLY := Color("ffe9a0")
const SHADOW := Color("a99bff")
const DIRT := Color("8a6440")
const SPARK := Color("fff07a")
const ENEMY := Color("d8d2c0")   # 被鏟起 / 拋出的怪（骷髏頭的顏色）


static func has(icon: String) -> bool:
	return icon in DRAWN


static func draw(ci: CanvasItem, icon: String, c: Vector2, alpha: float = 1.0) -> void:
	match icon:
		"⚔":
			for s in [-1.0, 1.0]:
				var tip := c + Vector2(12.0 * s, -12.0)
				var pommel := c + Vector2(-11.0 * s, 11.0)
				var guard := c + Vector2(-6.0 * s, 6.0)
				var perp := Vector2(1.0, s).normalized() * 5.0
				ci.draw_line(pommel, tip, _a(OUTLINE, alpha), 6.0)
				ci.draw_line(guard, tip, _a(STEEL, alpha), 3.5)
				ci.draw_line(pommel, guard, _a(HILT, alpha), 3.5)
				ci.draw_line(guard - perp, guard + perp, _a(HILT, alpha), 3.0)
		"🛡":
			var pts := PackedVector2Array([
				c + Vector2(-11, -12), c + Vector2(11, -12), c + Vector2(11, 1), c + Vector2(0, 13), c + Vector2(-11, 1),
			])
			ci.draw_colored_polygon(pts, _a(SHIELD, alpha))
			pts.append(pts[0])
			ci.draw_polyline(pts, _a(SHIELD_RIM, alpha), 2.0)
			ci.draw_line(c + Vector2(0, -10), c + Vector2(0, 10), _a(SHIELD_RIM, alpha), 2.0)
		"✦":
			ci.draw_colored_polygon(_star(c, 4, 13.0, 4.0), _a(BOLT, alpha))
		"✺":
			ci.draw_colored_polygon(_star(c, 8, 13.0, 5.5), _a(BURST, alpha))
			ci.draw_circle(c, 3.5, _a(Color.WHITE, alpha))
		"⟳":
			# 翻滾：順時針箭頭圓弧（缺口在右上），箭頭在弧的尾端
			ci.draw_arc(c, 10.0, -PI / 3.0, PI * 1.5, 24, _a(OUTLINE, alpha), 6.0)
			ci.draw_arc(c, 10.0, -PI / 3.0, PI * 1.5, 24, _a(ROLL, alpha), 3.0)
			var end := c + Vector2(cos(-PI / 3.0), sin(-PI / 3.0)) * 10.0
			ci.draw_colored_polygon(PackedVector2Array([end + Vector2(-6, -3), end + Vector2(5, -4), end + Vector2(1, 6)]), _a(ROLL, alpha))
		"parry":   # 招架：直立的劍，劍尖迸出火花
			_line(ci, c + Vector2(0, 12), c + Vector2(0, -8), STEEL, 3.5, alpha)
			_line(ci, c + Vector2(-6, 6), c + Vector2(6, 6), HILT, 3.0, alpha)
			ci.draw_colored_polygon(_star(c + Vector2(0, -9), 6, 7.0, 2.5), _a(SPARK, alpha))
		"passive":   # 職業被動：金色菱形徽章
			var d := PackedVector2Array([c + Vector2(0, -13), c + Vector2(11, 0), c + Vector2(0, 13), c + Vector2(-11, 0)])
			ci.draw_colored_polygon(d, _a(HILT, alpha))
			d.append(d[0])
			ci.draw_polyline(d, _a(OUTLINE, alpha), 2.0)
			ci.draw_colored_polygon(_star(c, 4, 6.0, 2.5), _a(Color.WHITE, alpha))
		"bow_shot":   # 快射：一支箭
			_arrow(ci, c + Vector2(-11, 11), c + Vector2(11, -11), 2.5, 6.0, alpha)
		"bow_fan":   # 散射：三支箭散開
			for deg: float in [-80.0, -45.0, -10.0]:
				var dir := Vector2.from_angle(deg_to_rad(deg))
				_arrow(ci, c + Vector2(-9, 10), c + Vector2(-9, 10) + dir * 22.0, 2.0, 5.0, alpha)
		"bow_heavy":   # 重射：粗箭
			_arrow(ci, c + Vector2(-11, 11), c + Vector2(10, -10), 4.5, 8.5, alpha)
		"bow_pierce":   # 穿透箭：箭穿過靶圈
			ci.draw_arc(c + Vector2(2, -2), 6.5, 0.0, TAU, 20, _a(Color("e0605a"), alpha), 2.5)
			_arrow(ci, c + Vector2(-12, 12), c + Vector2(12, -12), 2.5, 6.0, alpha)
		"dagger_combo":   # 五連刺：兩把匕首並排往前刺
			for o: Vector2 in [Vector2(-5, 3), Vector2(5, -3)]:
				_line(ci, c + o + Vector2(-7, 7), c + o + Vector2(-3, 3), HILT, 3.0, alpha)
				_line(ci, c + o + Vector2(-3, 3), c + o + Vector2(7, -7), STEEL, 3.0, alpha)
		"shadow_step":   # 影步：往前瞬移的人影 + 殘影線
			ci.draw_circle(c + Vector2(4, -8), 4.0, _a(SHADOW, alpha))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3), c + Vector2(9, -3), c + Vector2(8, 12), c + Vector2(1, 12)]), _a(SHADOW, alpha))
			for y: float in [-4.0, 3.0, 10.0]:
				_line(ci, c + Vector2(-13, y), c + Vector2(-4, y), Color(SHADOW, 0.6), 2.0, alpha)
		"mace_smash":   # 聖光敲擊：權杖頭往下砸
			_line(ci, c + Vector2(-11, 11), c + Vector2(2, -2), WOOD, 3.5, alpha)
			ci.draw_colored_polygon(_star(c + Vector2(5, -5), 8, 8.5, 5.0), _a(HOLY, alpha))
		"holy_circle":   # 聖光圈：發光的圓圈 + 十字
			ci.draw_arc(c, 11.0, 0.0, TAU, 28, _a(HOLY, alpha), 3.0)
			_line(ci, c + Vector2(0, -6), c + Vector2(0, 6), HOLY, 2.5, alpha)
			_line(ci, c + Vector2(-4, -2), c + Vector2(4, -2), HOLY, 2.5, alpha)
		"torch_swing":   # 火把揮擊：斜的火把 + 揮動的弧
			ci.draw_arc(c, 12.0, -PI * 0.9, -PI * 0.2, 12, _a(Color(FIRE, 0.7), alpha), 2.0)
			_line(ci, c + Vector2(-9, 11), c + Vector2(3, -1), WOOD, 3.5, alpha)
			_flame(ci, c + Vector2(4, -2), 11.0, alpha)
		"torch_raise":   # 準備姿態：舉高的火把 + 往上的箭頭
			_line(ci, c + Vector2(-2, 13), c + Vector2(-2, -1), WOOD, 3.5, alpha)
			_flame(ci, c + Vector2(-2, -1), 12.0, alpha)
			_line(ci, c + Vector2(9, 10), c + Vector2(9, -6), ROLL, 2.5, alpha)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(5, -5), c + Vector2(13, -5), c + Vector2(9, -11)]), _a(ROLL, alpha))
		"torch_plant":   # 插火把：插在地上的火把
			_line(ci, c + Vector2(-12, 11), c + Vector2(12, 11), DIRT, 3.0, alpha)
			_line(ci, c + Vector2(0, 11), c + Vector2(0, -1), WOOD, 3.5, alpha)
			_flame(ci, c + Vector2(0, -1), 12.0, alpha)
		"fire_breath":   # 噴火：往前噴的火焰扇形
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-12, 0), c + Vector2(12, -11), c + Vector2(9, 0), c + Vector2(12, 11)]), _a(FIRE, alpha))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-10, 0), c + Vector2(6, -5), c + Vector2(4, 0), c + Vector2(6, 5)]), _a(FIRE_CORE, alpha))
		"shovel_dig":   # 鏟地：斜的鐵鏟
			_line(ci, c + Vector2(-11, -11), c + Vector2(3, 3), WOOD, 3.5, alpha)
			_shovel_blade(ci, c + Vector2(6, 6), alpha)
		"shovel_grab":   # 鏟起：鏟子上托著一顆骷髏頭 + 往上的箭頭
			_line(ci, c + Vector2(-12, 10), c + Vector2(4, 10), WOOD, 3.5, alpha)
			_line(ci, c + Vector2(4, 7), c + Vector2(12, 7), STEEL, 4.0, alpha)
			ci.draw_circle(c + Vector2(8, 0), 4.5, _a(ENEMY, alpha))
			_line(ci, c + Vector2(-6, 4), c + Vector2(-6, -9), ROLL, 2.5, alpha)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-10, -8), c + Vector2(-2, -8), c + Vector2(-6, -13)]), _a(ROLL, alpha))
		"shovel_throw":   # 拋出：骷髏頭沿著弧線飛出去
			ci.draw_arc(c + Vector2(0, 8), 11.0, -PI, -PI * 0.15, 14, _a(ROLL, alpha), 2.0)
			var tip := c + Vector2(0, 8) + Vector2.from_angle(-PI * 0.15) * 11.0
			ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(-4, -4), tip + Vector2(4, -2), tip + Vector2(0, 5)]), _a(ROLL, alpha))
			ci.draw_circle(c + Vector2(-3, -5), 4.5, _a(ENEMY, alpha))
		"shovel_bury":   # 埋入：往下的箭頭插進土堆
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-13, 12), c + Vector2(-7, 5), c + Vector2(7, 5), c + Vector2(13, 12)]), _a(DIRT, alpha))
			_line(ci, c + Vector2(0, -12), c + Vector2(0, 0), ROLL, 2.5, alpha)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-5, -1), c + Vector2(5, -1), c + Vector2(0, 5)]), _a(ROLL, alpha))


# 有黑色描邊的線（小尺寸下才看得清楚）
static func _line(ci: CanvasItem, a: Vector2, b: Vector2, color: Color, width: float, alpha: float) -> void:
	ci.draw_line(a, b, _a(OUTLINE, alpha), width + 2.5)
	ci.draw_line(a, b, _a(color, alpha), width)


# 箭：箭桿 + 箭頭 + 尾羽（tail → tip）
static func _arrow(ci: CanvasItem, tail: Vector2, tip: Vector2, width: float, head: float, alpha: float) -> void:
	var dir := (tip - tail).normalized()
	var side := Vector2(-dir.y, dir.x)
	_line(ci, tail, tip - dir * head * 0.6, WOOD, width, alpha)
	ci.draw_colored_polygon(PackedVector2Array([tip, tip - dir * head + side * head * 0.55, tip - dir * head - side * head * 0.55]), _a(STEEL, alpha))
	for s: float in [-1.0, 1.0]:
		ci.draw_line(tail + dir * 4.0, tail + side * s * 3.5, _a(FEATHER, alpha), 2.0)


# 火焰：外圈橘、內圈黃（base 是火把頂端，往上長 h）
static func _flame(ci: CanvasItem, base: Vector2, h: float, alpha: float) -> void:
	ci.draw_colored_polygon(PackedVector2Array([base + Vector2(-5, 0), base + Vector2(-5, -h * 0.5), base + Vector2(0, -h), base + Vector2(5, -h * 0.5), base + Vector2(5, 0)]), _a(FIRE, alpha))
	ci.draw_colored_polygon(PackedVector2Array([base + Vector2(-2.5, 0), base + Vector2(-2.5, -h * 0.4), base + Vector2(0, -h * 0.7), base + Vector2(2.5, -h * 0.4), base + Vector2(2.5, 0)]), _a(FIRE_CORE, alpha))


# 鏟面：圓頭的盾形（at 是鏟面中心）
static func _shovel_blade(ci: CanvasItem, at: Vector2, alpha: float) -> void:
	var pts := PackedVector2Array([at + Vector2(-6, -2), at + Vector2(-2, -6), at + Vector2(6, 2), at + Vector2(5, 6), at + Vector2(1, 6)])
	ci.draw_colored_polygon(pts, _a(STEEL, alpha))
	pts.append(pts[0])
	ci.draw_polyline(pts, _a(OUTLINE, alpha), 1.5)


# points 個尖角的星形，從正上方開始
static func _star(c: Vector2, points: int, outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var a := -PI / 2.0 + PI * i / points
		pts.append(c + Vector2(cos(a), sin(a)) * (outer if i % 2 == 0 else inner))
	return pts


static func _a(color: Color, alpha: float) -> Color:
	return Color(color, color.a * alpha)
