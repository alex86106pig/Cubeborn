# 骰子模式 12 種效果的圖示：game-icons.net 的單色剪影 + 照規則上色的圓環（headless，在 godot/ 內）：
#   <Godot> --headless --path . -s res://tools/compose_effect_icons.gd -- --src=<放 SVG 的資料夾絕對路徑>
# SVG 是 game-icons.net 官方 repo（github.com/game-icons/icons）原檔，放在 art/icons/game-icons/（作者_名稱.svg，授權見那裡的 README）
# 原檔是黑底白圖：拿掉黑底那一塊、圖改成深色墨；畫在白色圓盤上，外圈一道色環（全隊版雙環），存 res://assets/icons/<效果 id>.png（256）
# 環的顏色（許家慶 2026-11-20）：防禦、回血、減傷綠；攻擊、攻速、暴擊紅；移速、冷卻、擊退紫。存完要再 --import 一次
# YangHsu 2026-11-24：Gemini 生的效果圖「全部都很怪」（許家慶），照 Claude 的評估換成 game-icons.net 的剪影、圖示直接套
extends SceneTree

const OUT_DIR := "res://assets/icons/"
const SIZE := 256
const RING_OUT := 124.0      # 色環外緣半徑（px）
const RING_W := 18.0         # 色環寬
const RING_GAP := 6.0        # 雙環：兩道環中間的白
const RING2_W := 8.0         # 雙環：裡面那道的寬
const RIM := 4.5             # 環外緣一圈深色邊（跟技能圖示的粗黑邊一致）
const GLYPH := 0.68          # 剪影佔圓盤內徑的比例
const INK := Color("241a12")
const RED := Color("c23b3b")
const GREEN := Color("3f9a4a")
const PURPLE := Color("7a4fbf")
# 效果 id → [SVG 檔名, 環色, 雙環]
const ICONS := {
	&"fx_dmg": ["lorc_plain-dagger.svg", RED, false],   # 細長的劍（broadsword）縮到骰面上看不清楚
	&"fx_basic": ["lorc_fist.svg", RED, false],
	&"fx_haste": ["lorc_spinning-sword.svg", RED, false],
	&"fx_crit": ["lorc_claw-slashes.svg", RED, false],   # 靶心（on-target）太細
	&"fx_shield": ["sbed_shield.svg", GREEN, false],
	&"fx_heal": ["zeromancer_heart-plus.svg", GREEN, false],
	&"fx_guard": ["lorc_breastplate.svg", GREEN, false],
	&"fx_speed": ["lorc_boots.svg", PURPLE, false],
	&"fx_cdr": ["lorc_hourglass.svg", PURPLE, false],
	&"fx_knock": ["delapouite_push.svg", PURPLE, false],
	&"fx_team_dmg": ["lorc_plain-dagger.svg", RED, true],
	&"fx_team_shield": ["sbed_shield.svg", GREEN, true],
}


func _initialize() -> void:
	var src := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--src="):
			src = arg.get_slice("=", 1)
	if src == "":
		printerr("用法：-- --src=<放 SVG 的資料夾絕對路徑>")
		quit(1)
		return
	var failed := 0
	for id: StringName in ICONS:
		var spec: Array = ICONS[id]
		var text := FileAccess.get_file_as_string(src.path_join(spec[0]))
		if text == "":
			printerr("讀不到 %s" % src.path_join(spec[0]))
			failed += 1
			continue
		var img := compose(text, spec[1], spec[2])
		var out := OUT_DIR + String(id) + ".png"
		if img == null or img.save_png(out) != OK:
			printerr("存不了 %s" % out)
			failed += 1
			continue
		print("%s ← %s" % [out, spec[0]])
	quit(1 if failed > 0 else 0)


# 一張圖示：白色圓盤 + 色環（雙環多一道細的）+ 中間的剪影
static func compose(svg: String, ring: Color, double: bool) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(SIZE, SIZE) / 2.0
	var ring_in := RING_OUT - RING_W
	var ring2_out := ring_in - RING_GAP
	var ring2_in := ring2_out - RING2_W
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(RING_OUT + RIM - d + 0.5, 0.0, 1.0)   # 整個圓（含外緣細邊）
			if a <= 0.0:
				continue
			var col := INK   # 最外緣的細邊
			if d <= RING_OUT:
				col = ring if d >= ring_in else Color.WHITE
				if double and d < ring2_out and d >= ring2_in:
					col = ring
				var k := clampf(RING_OUT - d + 0.5, 0.0, 1.0)   # 環與細邊之間反鋸齒
				col = INK.lerp(col, k)
			img.set_pixel(x, y, Color(col, a))
	var glyph := _glyph(svg, int((ring2_in if double else ring_in) * 2.0 * GLYPH))
	if glyph == null:
		return null
	var at := Vector2i((SIZE - glyph.get_width()) / 2, (SIZE - glyph.get_height()) / 2)
	img.blend_rect(glyph, Rect2i(Vector2i.ZERO, glyph.get_size()), at)
	return img


# game-icons 的原檔：拿掉整片黑底（第一個 path），白色的圖改成墨色，畫成 size × size
static func _glyph(svg: String, size: int) -> Image:
	var text := svg.replace('<path d="M0 0h512v512H0z"/>', "").replace('fill="#fff"', 'fill="#%s"' % INK.to_html(false))
	var img := Image.new()
	if img.load_svg_from_string(text, size / 512.0 * 2.0) != OK:   # 畫兩倍大再縮，邊緣比較乾淨
		return null
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return img
