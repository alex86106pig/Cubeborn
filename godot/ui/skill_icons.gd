# 技能欄的向量圖示：打包字型沒有 ⚔ 🛡 ✦ ✺ ⟳（翻滾），直接用線條與多邊形畫（約 28 像素見方）
class_name SkillIcons

const STEEL := Color("dfe8ff")
const HILT := Color("c9a46a")
const SHIELD := Color("6f86b8")
const SHIELD_RIM := Color("dfe8ff")
const BOLT := Color("7fd8ff")      # 魔彈顏色（weapon_defs 的 staff.attack.color）
const BURST := Color("c77dff")     # 奧術爆裂顏色（staff.special.color）
const ROLL := Color("e8eef8")
const OUTLINE := Color(0, 0, 0, 0.9)


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


# points 個尖角的星形，從正上方開始
static func _star(c: Vector2, points: int, outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var a := -PI / 2.0 + PI * i / points
		pts.append(c + Vector2(cos(a), sin(a)) * (outer if i % 2 == 0 else inner))
	return pts


static func _a(color: Color, alpha: float) -> Color:
	return Color(color, color.a * alpha)
