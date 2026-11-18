# 畫面風格的試做（YangHsu 2026-11-18：「現在遊戲畫面沒有自己的風格、還很粗糙」「牆過於統一」「墓碑看不出來是墓碑」）
# 只給比較用：debug 匯出的網址參數 / 指令列 --style=moon|diorama|etching 切換，預設空字串 = 現在的畫面完全不變。
# 選定一種後，把它的數字併進 Config.ENVIRONMENTS / ArenaView.BLOCK_COLORS，其他的連同本檔刪掉。
# 目前只有第 1 層（graveyard）有配色；其他層照舊。
class_name ArtStyle
extends RefCounted

static var current: StringName = &""   # main.gd 開場照 LaunchArgs.art_style 設


const PRESETS := {
	# A 月光與火光：場景壓暗、冷藍月光，玩家身上一盞暖色手提燈照出一圈（跟視野對上）；牆頂比側面亮一階
	&"moon": {
		"background": Color("05070d"),
		"ambient": Color("4a5a7e"), "ambient_energy": 0.7,
		"sun_color": Color("a8bcff"), "sun_energy": 0.9,
		"fog": {"color": Color("0c1222"), "density": 0.006},
		"lantern": {"color": Color("ffa850"), "energy": 5.0, "range": 13.0},
		"ground": [Color("25302a"), Color("2c3830"), Color("354036")], "ground_cell": 1.1, "ground_jitter": 0.05,
		"blocks": {
			&"wall": [Color("343a45"), Color("6a7384")],
			&"tomb": [Color("7d838c"), Color("aeb5be")],
			&"platform": [Color("3a3f49"), Color("666e7c")],
		},
		"moss": Color("243a2c"), "dirt": Color("2a231d"),
		"post": {"vignette": 0.8, "saturation": 0.9, "contrast": 1.06, "tint": Color("e6ecff")},
	},
	# C 桌上模型：像桌遊小模型，暖色柔光、亮一點的草地與石頭、畫面上下緣模糊（移軸）
	&"diorama": {
		"background": Color("2a2320"),
		"ambient": Color("c8bca8"), "ambient_energy": 0.95,
		"sun_color": Color("fff0d8"), "sun_energy": 1.25,
		"ground": [Color("4d6b3c"), Color("5d7a45"), Color("6e8450")], "ground_cell": 1.3, "ground_jitter": 0.06,
		"blocks": {
			&"wall": [Color("8a8073"), Color("b3a996")],
			&"tomb": [Color("b8b2a6"), Color("d8d2c4")],
			&"platform": [Color("8a6a52"), Color("a88a6c")],
		},
		"moss": Color("4f7a3a"), "dirt": Color("5a4330"),
		"post": {"vignette": 0.35, "saturation": 1.15, "contrast": 1.02, "tint": Color("fff6ea"), "tilt_blur": 1.0},
	},
	# D 褪色古版畫：場景整片灰褐單色，只有飽和的東西（血、魔法、戰利品、發光的眼）保留顏色；紙紋與暗角
	&"etching": {
		"background": Color("120f0b"),
		"ambient": Color("b8a888"), "ambient_energy": 0.75,
		"sun_color": Color("f2e4c8"), "sun_energy": 1.15,
		"ground": [Color("3f3a30"), Color("4a4438"), Color("554e40")], "ground_cell": 1.2, "ground_jitter": 0.07,
		"blocks": {
			&"wall": [Color("38322a"), Color("6a6152")],
			&"tomb": [Color("857d6c"), Color("aaa08a")],
			&"platform": [Color("4a4337"), Color("6f6654")],
		},
		"moss": Color("3c3a2e"), "dirt": Color("2c261e"),
		"post": {"vignette": 0.75, "saturation": 0.0, "keep_accent": 1.0, "contrast": 1.12, "tint": Color("f0dcb8"), "grain": 0.06},
	},
}


static func active() -> bool:
	return PRESETS.has(current)


# 這一層有沒有這種風格的配色（目前只做了第 1 層）
static func for_theme(theme: StringName) -> Dictionary:
	if not active() or theme != &"graveyard":
		return {}
	return PRESETS[current]


# 全畫面後製：讀 3D 畫好的畫面，做飽和度 / 留下鮮豔色 / 色調 / 對比 / 暗角 / 紙紋 / 上下緣模糊；
# 掛在 layer -1，介面（HUD、名字、傷害數字）畫在它後面，不受影響
const POST_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float vignette = 0.5;
uniform float saturation = 1.0;
uniform float keep_accent = 0.0;
uniform float contrast = 1.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float grain = 0.0;
uniform float tilt_blur = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = texture(screen_tex, uv).rgb;
	if (tilt_blur > 0.0) {
		float d = smoothstep(0.18, 0.5, abs(uv.y - 0.52)) * tilt_blur * 6.0;
		if (d > 0.05) {
			vec2 px = SCREEN_PIXEL_SIZE * d;
			vec3 acc = c;
			acc += texture(screen_tex, uv + px * vec2(1.0, 0.0)).rgb;
			acc += texture(screen_tex, uv + px * vec2(-1.0, 0.0)).rgb;
			acc += texture(screen_tex, uv + px * vec2(0.0, 1.0)).rgb;
			acc += texture(screen_tex, uv + px * vec2(0.0, -1.0)).rgb;
			acc += texture(screen_tex, uv + px * vec2(0.7, 0.7)).rgb;
			acc += texture(screen_tex, uv + px * vec2(-0.7, 0.7)).rgb;
			acc += texture(screen_tex, uv + px * vec2(0.7, -0.7)).rgb;
			acc += texture(screen_tex, uv + px * vec2(-0.7, -0.7)).rgb;
			acc += texture(screen_tex, uv + px * vec2(2.0, 0.0)).rgb;
			acc += texture(screen_tex, uv + px * vec2(-2.0, 0.0)).rgb;
			acc += texture(screen_tex, uv + px * vec2(0.0, 2.0)).rgb;
			acc += texture(screen_tex, uv + px * vec2(0.0, -2.0)).rgb;
			c = acc / 13.0;
		}
	}
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 g = mix(vec3(l), c, saturation) * tint.rgb;
	if (keep_accent > 0.0) {
		float s = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
		g = mix(g, c * 1.1, smoothstep(0.22, 0.42, s) * keep_accent);
	}
	g = (g - 0.5) * contrast + 0.5;
	vec2 v = uv - 0.5;
	g *= clamp(1.0 - dot(v, v) * vignette * 1.6, 0.0, 1.0);
	if (grain > 0.0) {
		g += (fract(sin(dot(floor(FRAGCOORD.xy / 2.0), vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * grain;
	}
	COLOR = vec4(g, 1.0);
}
"""


# 沒有風格時回傳 null
static func make_post_layer() -> CanvasLayer:
	if not active():
		return null
	var post: Dictionary = PRESETS[current].post
	var layer := CanvasLayer.new()
	layer.layer = -1
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = POST_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	for key: String in post:
		m.set_shader_parameter(key, post[key])
	rect.material = m
	layer.add_child(rect)
	return layer
