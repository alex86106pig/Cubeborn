# 把 Gemini 生的格狀圖示圖（白底、每個圖示外圈粗黑邊）切成一張張去背 PNG（headless，在 godot/ 內）：
#   <Godot> --headless --path . -s res://tools/slice_icons.gd -- --src=<圖的絕對路徑> --ids=左上,…,右下 [--cols=3 --rows=2] [--glow]
# 整張圖從四邊往內填掉白底（跟外圍相連、夠白的才算背景，黑邊裡面的白色亮面留著；被圖案包起來的白底也會留著，所以介面上畫圖示要墊白底）；
# 剩下的每一塊照它的中心點落在哪一格分給那一格（Gemini 的格子不完全等寬，圖案跨過格線也整塊歸自己那格）；
# 黑邊外緣的灰色反鋸齒變成半透明黑；沒有黑邊、又接近白色的部分（光柱、光暈）會被當背景去掉：
#   有帶顏色的光（暖色光柱）就加 --glow，只有中性的白（RGB 差不到 GLOW_TINT）才算背景，光照原色留著、往白底淡出；
#   純白的光加 --glow 也留不住，要請 Gemini 加黑邊或上色重生。--glow 會讓 JPEG 雜色也留下來，只用在需要的格子（其他格填 -）
# 每格照圖案範圍框成正方形、留 4% 邊，縮成 SIZE 存到 res://assets/icons/<id>.png（FaceIcons 照技能 / 效果 id 找圖）
# id 填 - 的格子跳過。存完要再 --import 一次，遊戲才讀得到新圖
extends SceneTree

const OUT_DIR := "res://assets/icons/"
const SIZE := 256
const BG_LUM := 215.0   # 比這亮、又跟外圍相連的是背景
const PAD := 0.04
const GLOW_TINT := 10    # --glow：夠亮、RGB 最大減最小不到這個才是背景（白底的 JPEG 雜色約 2）
const GLOW_RAMP := 12.0  # --glow：光從 GLOW_TINT 到 GLOW_TINT + 這個之間由透明漸變到不透明，光暈外緣不會一刀切


func _initialize() -> void:
	var src := ""
	var ids: PackedStringArray = []
	var cols := 3
	var rows := 2
	var is_glow := false
	for arg in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1)
		if arg == "--glow":
			is_glow = true
		elif arg.begins_with("--src="):
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
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()   # RGBA8，直接讀位元組比 get_pixel 快很多
	var bg := _background(data, w, h, is_glow)
	# 每一塊（四連通）的中心點 → 哪一格
	var cell_of := PackedInt32Array()
	cell_of.resize(w * h)
	cell_of.fill(-1)
	for start in w * h:
		if bg[start] == 1 or cell_of[start] != -1:
			continue
		var part := PackedInt32Array([start])
		cell_of[start] = -2
		var head := 0
		var sx := 0.0
		var sy := 0.0
		while head < part.size():
			var i := part[head]
			head += 1
			var x := i % w
			var y := i / w
			sx += x
			sy += y
			for nb: int in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w if y > 0 else -1, i + w if y < h - 1 else -1]:
				if nb >= 0 and bg[nb] == 0 and cell_of[nb] == -1:
					cell_of[nb] = -2
					part.append(nb)
		var cx := clampi(int(sx / part.size() * cols / w), 0, cols - 1)
		var cy := clampi(int(sy / part.size() * rows / h), 0, rows - 1)
		for i in part:
			cell_of[i] = cy * cols + cx
	for k in ids.size():
		var id := ids[k].strip_edges()
		if id == "" or id == "-":
			continue
		var icon := _cell_icon(data, bg, cell_of, k, w, h, is_glow)
		if icon == null:
			printerr("第 %d 格（%s）沒有圖案" % [k + 1, id])
			continue
		var path := OUT_DIR + id + ".png"
		icon.save_png(ProjectSettings.globalize_path(path))
		print("icon %s -> %s" % [id, path])
	quit(0)


static func _lum_at(data: PackedByteArray, i: int) -> float:
	return 0.3 * data[i * 4] + 0.59 * data[i * 4 + 1] + 0.11 * data[i * 4 + 2]


static func _tint_at(data: PackedByteArray, i: int) -> int:
	var r := data[i * 4]
	var g := data[i * 4 + 1]
	var b := data[i * 4 + 2]
	return maxi(r, maxi(g, b)) - mini(r, mini(g, b))


# 跟四邊相連、夠白的像素 = 1（is_glow：還要是中性的白，帶顏色的光不算）
static func _background(data: PackedByteArray, w: int, h: int, is_glow: bool) -> PackedByteArray:
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
		if bg[i] == 1 or _lum_at(data, i) < BG_LUM or (is_glow and _tint_at(data, i) >= GLOW_TINT):
			continue
		bg[i] = 1
		var x := i % w
		var y := i / w
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if y > 0: stack.append(i - w)
		if y < h - 1: stack.append(i + w)
	return bg


static func _cell_icon(data: PackedByteArray, bg: PackedByteArray, cell_of: PackedInt32Array, k: int, w: int, h: int, is_glow: bool) -> Image:
	var l := w
	var r := -1
	var t := h
	var b := -1
	for i in w * h:
		if cell_of[i] == k:
			var x := i % w
			var y := i / w
			l = mini(l, x)
			r = maxi(r, x)
			t = mini(t, y)
			b = maxi(b, y)
	if r < 0:
		return null
	var side := int(maxi(r - l, b - t) * (1.0 + PAD * 2.0)) + 1
	var ox := (l + r) / 2 - side / 2
	var oy := (t + b) / 2 - side / 2
	var out := Image.create(side, side, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for y in range(maxi(oy, 0), mini(oy + side, h)):
		for x in range(maxi(ox, 0), mini(ox + side, w)):
			var i := y * w + x
			if cell_of[i] != k:
				continue
			var edge := (x > 0 and bg[i - 1] == 1) or (x < w - 1 and bg[i + 1] == 1) or (y > 0 and bg[i - w] == 1) or (y < h - 1 and bg[i + w] == 1)
			if is_glow and _lum_at(data, i) >= BG_LUM:   # 亮的光：照原色，顏色越淡越透明
				var a := clampf((_tint_at(data, i) - GLOW_TINT) / GLOW_RAMP, 0.0, 1.0)
				out.set_pixel(x - ox, y - oy, Color8(data[i * 4], data[i * 4 + 1], data[i * 4 + 2], int(a * 255.0)))
			elif edge:   # 黑邊外緣的灰色反鋸齒：變半透明的黑，放在任何底色上都不會有白毛邊
				out.set_pixel(x - ox, y - oy, Color(0, 0, 0, minf(1.0, (1.0 - _lum_at(data, i) / 255.0) * 1.3)))
			else:
				out.set_pixel(x - ox, y - oy, Color8(data[i * 4], data[i * 4 + 1], data[i * 4 + 2]))
	out.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return out
