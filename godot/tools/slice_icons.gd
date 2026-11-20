# 把 Gemini 生的格狀圖示圖（白底、每個圖示外圈粗黑邊）切成一張張去背 PNG（headless，在 godot/ 內）：
#   <Godot> --headless --path . -s res://tools/slice_icons.gd -- --src=<圖的絕對路徑> --ids=左上,…,右下 [--cols=3 --rows=2]
# 每格從邊緣往內填掉白底（跟外圍相連、夠白的才算背景，黑邊裡面的白色亮面留著），黑邊外緣的灰色反鋸齒變成半透明黑；
# 照圖案的範圍框成正方形、留 4% 邊，縮成 SIZE 存到 res://assets/icons/<id>.png（FaceIcons 照技能 / 效果 id 找圖）
# id 填 - 的格子跳過。存完要再 --import 一次，遊戲才讀得到新圖
extends SceneTree

const OUT_DIR := "res://assets/icons/"
const SIZE := 256
const BG_LUM := 215.0   # 比這亮、又跟外圍相連的是背景
const PAD := 0.04


func _initialize() -> void:
	var src := ""
	var ids: PackedStringArray = []
	var cols := 3
	var rows := 2
	for arg in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--src="):
			src = value
		elif arg.begins_with("--ids="):
			ids = value.split(",")
		elif arg.begins_with("--cols="):
			cols = value.to_int()
		elif arg.begins_with("--rows="):
			rows = value.to_int()
	var img := Image.load_from_file(src) if src != "" else null
	if img == null or ids.size() != cols * rows:
		printerr("用法：-- --src=<圖的絕對路徑> --ids=id1,…（%d 個，左上到右下）--cols=3 --rows=2" % (cols * rows))
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var cw := img.get_width() / cols
	var ch := img.get_height() / rows
	for k in ids.size():
		var id := ids[k].strip_edges()
		if id == "" or id == "-":
			continue
		var cell := img.get_region(Rect2i((k % cols) * cw, (k / cols) * ch, cw, ch))
		var icon := _cut(cell)
		var path := OUT_DIR + id + ".png"
		icon.save_png(ProjectSettings.globalize_path(path))
		print("icon %s -> %s" % [id, path])
	quit(0)


static func _lum(c: Color) -> float:
	return (0.3 * c.r + 0.59 * c.g + 0.11 * c.b) * 255.0


static func _cut(cell: Image) -> Image:
	var w := cell.get_width()
	var h := cell.get_height()
	var bg := PackedByteArray()
	bg.resize(w * h)
	var stack := PackedInt32Array()
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if bg[i] == 1:
			continue
		var x := i % w
		var y := i / w
		if _lum(cell.get_pixel(x, y)) < BG_LUM:
			continue
		bg[i] = 1
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if y > 0: stack.append(i - w)
		if y < h - 1: stack.append(i + w)
	var l := w
	var r := 0
	var t := h
	var b := 0
	for y in h:
		for x in w:
			var i := y * w + x
			if bg[i] == 1:
				cell.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var edge := (x > 0 and bg[i - 1] == 1) or (x < w - 1 and bg[i + 1] == 1) or (y > 0 and bg[i - w] == 1) or (y < h - 1 and bg[i + w] == 1)
			if edge:   # 黑邊外緣的灰色反鋸齒：變半透明的黑，放在任何底色上都不會有白毛邊
				var a := minf(1.0, (1.0 - _lum(cell.get_pixel(x, y)) / 255.0) * 1.3)
				cell.set_pixel(x, y, Color(0, 0, 0, a))
			l = mini(l, x)
			r = maxi(r, x)
			t = mini(t, y)
			b = maxi(b, y)
	var side := int(maxi(r - l, b - t) * (1.0 + PAD * 2.0))
	var out := Image.create(side, side, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var ox := (l + r) / 2 - side / 2
	var oy := (t + b) / 2 - side / 2
	var src_rect := Rect2i(maxi(ox, 0), maxi(oy, 0), 0, 0)
	src_rect.end = Vector2i(mini(ox + side, w), mini(oy + side, h))
	out.blit_rect(cell, src_rect, src_rect.position - Vector2i(ox, oy))
	out.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return out
