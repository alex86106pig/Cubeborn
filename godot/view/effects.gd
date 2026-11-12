# 畫面層特效（照搬網頁版 render/Effects.js）：方塊粒子、揮砍弧光、衝擊環、預警圈
# 一次性的特效由模擬層的事件觸發（fx:* 與 entity:damaged / entity:died / boss:enraged，見 PROJECT_GUIDELINES 第 9 節）
# 持續性的粒子（投射物拖尾、蓄力、爬出塵土、衝鋒揚塵、暈眩星星、召喚、疾跑殘影）依模擬層的狀態每幀產生，不佔網路
# 網頁版每個邏輯步以機率 p 產生一顆 → 這裡換算成每秒 p × 60 顆，和幀率無關
# 粒子全部畫在一個 MultiMesh（一次繪製）；弧光與環各自一個網格，數量都有上限
class_name Effects
extends Node3D

const MAX_PARTICLES := 600
const MAX_TRANSIENTS := 64
const STEPS_PER_SECOND := 60.0   # 網頁版每步一次的特效換算成每秒次數
const RING_INNER := 0.85
const RING_SEGMENTS := 48
const SLASH_SEGMENTS := 24

# 會處理的事件 → 處理函式；check.gd 會確認模擬層發出的每個 fx:* 都在這裡
const HANDLERS := {
	"entity:damaged": &"_on_damaged",
	"hit:predicted": &"_on_damaged",   # 客戶端預測自己打中（v0.38.0）：先噴火花，房主的那一下到了就不再噴
	"entity:died": &"_on_died",
	"boss:enraged": &"_on_enraged",
	"boss:transformed": &"_on_transformed",
	"fx:slash": &"_fx_slash",
	"fx:muzzle": &"_fx_muzzle",
	"fx:telegraph": &"_fx_telegraph",
	"fx:fizzle": &"_fx_fizzle",
	"fx:explosion": &"_fx_explosion",
	"fx:parry": &"_fx_parry",
	"fx:heal": &"_fx_heal",
	"fx:boss_slam": &"_fx_boss_slam",
	"fx:boss_wall": &"_fx_boss_wall",
	"fx:boss_teleport": &"_fx_boss_teleport",
	"fx:boss_teleport_warn": &"_fx_boss_teleport_warn",
	"fx:erupt_warn": &"_fx_erupt_warn",
	"fx:gas_cloud": &"_fx_gas_cloud",
	"fx:dirt_lob": &"_fx_dirt_lob",
	"fx:claw": &"_fx_claw",
	"fx:lightning": &"_fx_lightning",
	"fx:status": &"_fx_status",
	"enemy:blocked": &"_on_enemy_blocked",
	"enemy:guard_broken": &"_on_enemy_blocked",
	"enemy:crashed": &"_on_enemy_crashed",
	"fx:spike_warn": &"_fx_spike_warn",
	"fx:burrow_warn": &"_fx_burrow_warn",
	"fx:worm_egg": &"_fx_worm_egg",
	"fx:gust": &"_fx_gust",
	"fx:shriek": &"_fx_shriek",
	"fx:web": &"_fx_web",
	"fx:web_burned": &"_fx_web_burned",
	"fx:webbed": &"_fx_webbed",
	"fx:burrow_out": &"_fx_burrow_out",
	"fx:bone_spike": &"_fx_bone_spike",
	"fx:sweep": &"_fx_sweep",
	"boss:absorbed": &"_on_boss_absorbed",
	"boss:devoured": &"_on_boss_devoured",
}
const LIGHTNING_HEIGHT := 1.1   # 連鎖閃電畫在離地多高（v0.33.0）
const LIGHTNING_WIDTH := 0.09
const LIGHTNING_LIFE := 0.22

const DUST_COLOR := Color("6b4f2e")         # 骷髏爬出的泥土
const SHIELD_SPARK := Color("ffd890")       # 怪物舉盾擋下的火花
const WEB_COLOR := Color("e8e4dc")          # 蜘蛛網、蛛絲
const CHARGE_DUST_COLOR := Color("8a7a5a")  # Boss 衝鋒揚塵、砸地碎石
const WALL_DEBRIS_COLOR := Color("9a9a9a")
const SLAM_RING_COLOR := Color("9a8a6a")
const STUN_STAR_COLOR := Color("ffe14a")
const COFFIN_SHARD_COLOR := Color("e8f8ff")   # 冰棺的冰晶
const TELEPORT_COLOR := Color("b36bff")
const BONE_COLOR := Color("d8d0b8")         # 挖墳點冒出的白骨手
const COFFIN_DUST := Color("8a8070")        # 石棺噴怪前的石屑
const SEAL_COLOR := Color("b070ff")         # 石棺封印的紫光（同 WorldView.COFFIN_SEAL）
const COFFIN_TOP := 0.85                    # 石棺棺口的高度（同 WorldView.COFFIN_SIZE.y）
const MOTH_DUST_COLOR := Color("c8b890")    # 屍蛾女王的鱗粉（同 EnemyDefs 的 moth.dust.color）
const WORM_EGG_COLOR := Color("b9c08a")     # 噬墓巨蟲的卵（同 DarkFantasy.BURROW_EGG）
const COCOON_SHRED := Color("c9cdbd")       # 巨繭噴怪前飄出來的絲屑（同 WorldView.COCOON_SILK）
const COCOON_GLOW := Color("a8e04a")        # 巨繭裂口的綠光（同 WorldView.COCOON_GLOW）
const COCOON_MID := 1.2                     # 巨繭中段的高度（WorldView.COCOON_SIZE.y 的一半）
const DIRT_LOB_HEIGHT := 3.0                # 守墓人拋出的土塊飛多高
const ROCK_FALL_HEIGHT := 14.0              # 瘋狂鏟土的落石從多高掉下來
const CLAW_MARKS := 3                       # 狼人每一爪的爪痕條數
const CLAW_MARK_WIDTH := 0.16
const CLAW_MARK_GAP := 0.42                 # 爪痕之間的間距
const CLAW_MARK_TILT := 0.55                # 爪痕斜的角度（弧度；左右爪方向相反）
const CLAW_MARK_LIFE := 0.5
const LANTERN_BLUE := Color("6ab0ff")       # 提燈噴火前燈火轉藍
# 守墓人噴火的火舌（_flame）：跟判定一樣大的扇形，中心亮黃 → 外圈橘紅，最外緣 FLAME_RIM 那一圈較亮，看得出噴到哪裡
const FLAME_Y := 0.7                        # 火舌離地多高（等距視角下看得出是噴出來的火，不像地上的圈）
const FLAME_INNER := 0.5
const FLAME_RIM := 0.06                     # 外緣亮邊占範圍的比例
const FLAME_COLORS := [Color(1.0, 0.95, 0.6, 0.7), Color(1.0, 0.62, 0.2, 0.5), Color(0.95, 0.32, 0.1, 0.4)]   # 內 → 外
const FLAME_RIM_COLOR := Color(1.0, 0.55, 0.15, 0.85)
const FLAME_FLICKER := Vector2(0.0, 0.25)   # 每幀整片透明度在這之間隨機（閃爍）
const FLAME_JET := 5.0                      # 噴流粒子：每步幾顆（每秒 × 60）
const FLAME_JET_LIFE := 0.3                 # 粒子飛到範圍盡頭花幾秒
const FLAME_JET_SIZE := 0.35
# 立體火柱（_flame_stream）：從提燈往前流的一串發光火團，越遠越大、由亮黃變暗紅、越淡；跟火舌、噴流一起出現
const FLAME_BLOBS := 64                     # 一道火柱幾團
const FLAME_TRAVEL := 0.32                  # 一團火從提燈流到範圍盡頭的秒數
const FLAME_BLOB_SIZE := Vector2(0.3, 1.25) # 起點 → 盡頭的直徑（沿噴的方向再拉長 FLAME_BLOB_STRETCH 倍，像火舌）
const FLAME_BLOB_STRETCH := 1.8
const FLAME_BLOB_SPREAD := 0.85             # 火團的方向佔扇形角度的比例（外緣留給地上的火舌亮邊）
# 起點 → 中段 → 盡頭。加亮混合會疊起來：每團淡一點、偏橘紅，重疊多的中心才疊成亮黃（太亮會疊成白色的泡泡）
const FLAME_STREAM_COLORS := [Color(1.0, 0.8, 0.4, 0.5), Color(1.0, 0.42, 0.08, 0.38), Color(0.6, 0.1, 0.03, 0.0)]
# 噴火的燈光：火焰中段一盞會閃的橘色點光源，照亮地面、牆和玩家
const FLAME_LIGHT_COLOR := Color("ff8a30")
const FLAME_LIGHT_ENERGY := Vector2(2.4, 3.6)
const FLAME_LIGHT_AT := 0.4                 # 放在範圍的這個比例處
const FLAME_LIGHT_HEIGHT := 1.2
const WOLF_FUR := Color("4a4642")           # 守墓人變身：毛（同 DarkFantasy 的 wolf_fur）
const KEEPER_COAT := Color("4a3a2a")        # 撐破的外套碎片
const ERUPT_HANDS := 4
const ERUPT_HANDS_FROM := 0.45              # 墳土隆起到這個進度才冒出白骨手

var _burned_webs := {}   # 燒掉的蜘蛛網 web_id（網的零件在自己的 transient 裡看這個藏起來）
var world: World                  # 由 sync 設定；事件處理時用來查實體位置
var paused := false               # 遊戲暫停時粒子停住、不產生新的持續性粒子
var spawned_total := 0            # 累計產生過的粒子數（檢查用）
var hidden_ids: Dictionary = {}   # 本機玩家看不到的實體 id（WorldView 每幀更新）：不產生它們的持續性粒子（D2）
var first_seen: Array[String] = []   # 這一幀第一次出現的特效種類（main.gd 的卡頓紀錄取走後清空）
var visible_at: Callable             # (pos: Vector2, radius: float) -> bool；WorldView 設定，持續性地面特效每幀照它顯示 / 隱藏
var _gate: Array = []                # 處理 gated 事件時：[pos, radius]，這段期間建立的零件與持續粒子都掛上它
var _seen_fx: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _particles: Array[Dictionary] = []
var _transients: Array[Dictionary] = []
var _multimesh := MultiMesh.new()
var _ring_mesh: ArrayMesh
var _disc_mesh: Mesh                 # telegraph 的填色圓（半徑 1，用 scale 放大）
const FILL_ALPHA := 0.18
var _slash_meshes: Dictionary = {}   # "range|arc" -> ArrayMesh
var _flame_meshes: Dictionary = {}   # "range|arc" -> ArrayMesh（火舌，頂點顏色）
var _flames: Dictionary = {}         # 實體 id -> 正在噴的火舌節點（每幀沒噴的就拿掉，_retire_flames）
var _flame_seen: Dictionary = {}
var _flame_mat: StandardMaterial3D   # 所有火舌共用（開場預熱）
var _streams: Dictionary = {}        # 實體 id -> 正在噴的火柱 { node, mm: MultiMesh, light: OmniLight3D, blobs }（跟 _flames 一起收）
var _blob_mesh: SphereMesh           # 火團（直徑 1，用縮放放大；所有火柱共用）
var _warm_stream: Node = null        # 開場預熱用的火柱
var _emitters: Array[Dictionary] = []   # 一段時間內持續冒粒子的特效（事件觸發）：{ key, life, max_life, tick: Callable(k, key, dt) }
var _emitter_serial := 0
var _carry: Dictionary = {}          # 持續性粒子的小數累積：產生源 key -> 不滿一顆的部分
var _next_carry: Dictionary = {}     # 這一幀用到的 key（沒用到的產生源下一幀就丟掉）


# 網格在建立時就準備好（不在場景樹裡也能用，檢查會直接建立 Effects / WorldView）
func _init() -> void:
	_rng.randomize()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.instance_count = MAX_PARTICLES
	_multimesh.visible_instance_count = 0
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	box.material = mat
	_multimesh.mesh = box
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _multimesh
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -10, -200), Vector3(400, 60, 400))   # 粒子散在整個場地，不讓整組被視錐剔除
	add_child(mmi)
	_ring_mesh = _make_ring_mesh()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 32
	disc.rings = 1
	_disc_mesh = disc
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flame_mat.vertex_color_use_as_albedo = true
	_blob_mesh = SphereMesh.new()
	_blob_mesh.radius = 0.5
	_blob_mesh.height = 1.0
	_blob_mesh.radial_segments = 8
	_blob_mesh.rings = 4
	_blob_mesh.material = _flame_mat   # 同火舌：加亮混合 + 顏色（MultiMesh 每團的顏色）


# 開場先各畫一次（透明度 0），讓粒子與半透明材質的著色器在載入時就編譯，避免第一次出現時卡頓
# v0.37.0：要畫在鏡頭裡（WorldView.warm_up 傳入玩家附近的位置）；以前畫在原點，地圖 A 的出生點離原點很遠、顯示卡根本沒畫
func warm_up(pos: Vector3) -> void:
	burst(pos + Vector3(0, 0.05, 0), {"count": 1, "life": 0.1, "size": 0.001})
	ring(pos, 1.0, {"life": 0.1, "opacity": 0.0})
	slash(pos, 0.0, 1.0, 1.0, {"life": 0.1, "opacity": 0.0})
	telegraph(pos, 1.0, {"life": 0.1, "opacity": 0.0})
	var flame := _flame_node(_flame_mesh(1.0, 1.0))   # 火舌的材質（加亮混合 + 頂點顏色）
	flame.position = pos
	flame.transparency = 0.99
	_add_transient(flame, 0.1, func(_k: float) -> void: pass)
	var stream := _new_stream()   # 火柱（MultiMesh 的顏色）也先畫一次；燈先關著
	(stream.node as Node3D).position = pos
	(stream.mm as MultiMesh).visible_instance_count = 1
	(stream.mm as MultiMesh).set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3.ZERO))
	(stream.light as OmniLight3D).visible = false
	add_child(stream.node)
	_warm_stream = stream.node   # 畫過一幀就拿掉（_emit_continuous）


func clear() -> void:
	_particles.clear()
	_multimesh.visible_instance_count = 0
	for id: int in _flames:
		(_flames[id] as Node).queue_free()
	_flames.clear()
	for id: int in _streams:
		(_streams[id].node as Node).queue_free()
	_streams.clear()
	for t in _transients:
		t.node.queue_free()
	_transients.clear()
	_emitters.clear()


func particle_count() -> int:
	return _particles.size()


func transient_count() -> int:
	return _transients.size()


# ───────── 基本形狀（同網頁版 Effects.js 的參數與預設值） ─────────

# 方塊粒子爆發；pos 的 y 就是起始高度
func burst(pos: Vector3, o: Dictionary = {}) -> void:
	var color: Color = o.get("color", Color.WHITE)
	var count: int = o.get("count", 8)
	var speed: float = o.get("speed", 4.0)
	var size: float = o.get("size", 0.14)
	var life: float = o.get("life", 0.45)
	var gravity: float = o.get("gravity", 14.0)
	var up: float = o.get("up", 3.0)
	for i in count:
		if _particles.size() >= MAX_PARTICLES:
			return
		var angle := _rng.randf() * TAU
		var s := speed * _rng.randf_range(0.4, 1.0)
		var max_life := life * _rng.randf_range(0.6, 1.2)
		spawned_total += 1
		_particles.append({
			"pos": pos, "vel": Vector3(sin(angle) * s, up * _rng.randf_range(0.5, 1.2), cos(angle) * s),
			"rot": Vector2(_rng.randf() * 3.0, _rng.randf() * 3.0), "gravity": gravity, "color": color,
			"size": size * _rng.randf_range(0.7, 1.3), "life": max_life, "max_life": max_life,
		})


# 單顆漂浮粒子（拖尾、蓄力）
func mote(pos: Vector3, o: Dictionary = {}) -> void:
	var vy: float = o.get("vy", 0.5)
	burst(pos, {"color": o.get("color", Color.WHITE), "count": 1, "speed": 0.3, "size": o.get("size", 0.1),
		"life": o.get("life", 0.3), "gravity": -vy * 2.0, "up": vy})


# 近戰弧光：扇形面片朝 facing 展開，swing_dir = -1 時左右翻轉（反手）
func slash(pos: Vector3, facing: float, range_: float, arc: float, o: Dictionary = {}) -> void:
	var key := "%.2f|%.2f" % [range_, arc]
	if not _slash_meshes.has(key):
		_slash_meshes[key] = _make_sector_mesh(range_ * 0.35, range_, arc)
	var opacity: float = o.get("opacity", 0.75)
	var node := _transient_mesh(_slash_meshes[key], o.get("color", Color.WHITE), opacity)
	node.position = pos
	node.rotation.y = facing
	var swing: float = o.get("swing_dir", 1)
	_add_transient(node, o.get("life", 0.16), func(k: float) -> void:
		_set_alpha(node, opacity * (1.0 - k))
		node.scale = Vector3(swing, 1.0, 0.85 + 0.15 * k))


# 衝擊環：由小擴張到 radius 並淡出
func ring(pos: Vector3, radius: float, o: Dictionary = {}) -> void:
	var opacity: float = o.get("opacity", 0.8)
	var node := _transient_mesh(_ring_mesh, o.get("color", Color.WHITE), opacity)
	node.position = pos + Vector3(0, o.get("y", 0.05), 0)
	_add_transient(node, o.get("life", 0.35), func(k: float) -> void:
		var s := radius * (0.25 + 0.75 * sqrt(k))
		node.scale = Vector3(s, 1.0, s)
		_set_alpha(node, opacity * (1.0 - k)))


# 預警圈：固定大小、閃爍，用於範圍技落點
# fill：圈內再鋪一層半透明的圓（持續型的範圍，例如聖光圈）
func telegraph(pos: Vector3, radius: float, o: Dictionary = {}) -> void:
	if o.get("fill", false):
		var disc := _transient_mesh(_disc_mesh, o.get("color", Color.WHITE), FILL_ALPHA)
		disc.position = pos + Vector3(0, 0.04, 0)
		disc.scale = Vector3(radius, 1.0, radius)
		_add_transient(disc, o.get("life", 0.4), func(k: float) -> void:
			_set_alpha(disc, FILL_ALPHA * (1.0 - smoothstep(0.85, 1.0, k))))
	var node := _transient_mesh(_ring_mesh, o.get("color", Color.WHITE), 0.5)
	node.position = pos + Vector3(0, 0.05, 0)
	node.scale = Vector3(radius, 1.0, radius)
	_add_transient(node, o.get("life", 0.4), func(k: float) -> void:
		_set_alpha(node, 0.35 + 0.35 * pow(sin(k * PI * 6.0), 2.0)))


# ───────── 事件 ─────────

# gated：持續性地面特效，零件與持續粒子只在 visible_at 看得到時顯示 / 產生
func on_event(name: String, p: Dictionary, gated := false) -> void:
	var handler: StringName = HANDLERS.get(name, &"")
	if handler != &"":
		if not _seen_fx.has(name):   # --perf 的卡頓紀錄：這種特效第一次出現（v0.36.3）
			_seen_fx[name] = true
			first_seen.append(name)
		_gate = [p.pos, p.get("radius", 0.0)] if gated else []
		call(handler, p)
		_gate = []


func _gate_open(gate: Array) -> bool:
	return gate.is_empty() or not visible_at.is_valid() or visible_at.call(gate[0], gate[1])


static func _at(p: Dictionary, y_offset: float = 0.0) -> Vector3:
	var pos: Vector2 = p.pos
	return Vector3(pos.x, p.get("height", 0.0) + y_offset, pos.y)


func _entity(id: int) -> Entity:
	return world.entities.get(id) if world != null else null


static func _entity_at(e: Entity, y_offset: float) -> Vector3:
	return Vector3(e.pos.x, e.height + y_offset, e.pos.y)


func _on_damaged(p: Dictionary) -> void:
	var target := _entity(p.target_id)
	if target == null or p.get("predicted", false):
		return
	var heavy: bool = p.get("is_heavy", false) or p.get("is_crit", false)
	burst(_entity_at(target, 1.1), {"color": p.get("color", Color.WHITE), "count": 12 if heavy else 6, "speed": 6.0 if heavy else 4.0})


# 怪物舉盾擋下（盾槍兵）：盾面上噴火花；破防噴得更大、多一圈碎屑
func _on_enemy_blocked(p: Dictionary) -> void:
	var at := _at(p, 1.05) + Vector3(sin(p.facing), 0.0, cos(p.facing)) * 0.55
	var broken: bool = p.get("broken", false)
	burst(at, {"color": SHIELD_SPARK, "count": 8, "speed": 5.0, "size": 0.08, "life": 0.25})
	if broken:
		burst(at, {"color": CHARGE_DUST_COLOR, "count": 14, "speed": 6.0, "up": 2.0, "size": 0.14, "life": 0.5})


# 萬骨聚合體骨刺陣的預兆：地面沿 lines 個方向一路隆起（低低的土石條，不畫圈），windup 結束時消失
func _fx_spike_warn(p: Dictionary) -> void:
	var at := _at(p, 0.02)
	var life: float = p.life
	var lines: int = p.lines
	var start: float = p.start
	var length: float = p.length
	var ridge := BoxMesh.new()
	ridge.size = Vector3(0.5, 0.25, length - start)
	for i in lines:
		var a: float = p.facing + TAU * i / lines
		var dir := Vector3(sin(a), 0.0, cos(a))
		var node := _transient_mesh(ridge, CHARGE_DUST_COLOR, 0.9)
		node.position = at + dir * (start + (length - start) * 0.5)
		node.rotation.y = a
		_add_transient(node, life, func(k: float) -> void:
			node.scale = Vector3(1.0, 0.1 + 0.9 * MathUtil.ease_out_cubic(k) + 0.1 * sin(k * 50.0), 1.0))


# 蜘蛛網：地上一張半透明的白網（輻射的絲 + 兩圈），time 秒後淡掉；燒掉時（fx:web_burned）提早藏起來
func _fx_web(p: Dictionary) -> void:
	var at := _at(p, 0.04)
	var radius: float = p.radius
	var life: float = p.life
	var key := "web|%.2f" % radius
	if not _slash_meshes.has(key):
		var strand := BoxMesh.new()
		strand.size = Vector3(0.04, 0.01, radius * 2.0)
		_slash_meshes[key] = strand
		var ring := TorusMesh.new()
		ring.inner_radius = radius * 0.96
		ring.outer_radius = radius
		_slash_meshes[key + "|ring"] = ring
		var ring2 := TorusMesh.new()
		ring2.inner_radius = radius * 0.5
		ring2.outer_radius = radius * 0.53
		_slash_meshes[key + "|ring2"] = ring2
	var parts: Array[MeshInstance3D] = []
	for i in 4:
		var s := _transient_mesh(_slash_meshes[key], WEB_COLOR, 0.7)
		s.position = at
		s.rotation.y = PI * i / 4.0
		parts.append(s)
	for r in ["|ring", "|ring2"]:
		var n := _transient_mesh(_slash_meshes[key + r], WEB_COLOR, 0.6)
		n.position = at
		n.scale.y = 0.05
		parts.append(n)
	for n in parts:
		_add_transient(n, life, func(k: float) -> void:
			if _burned_webs.has(p.web_id):
				n.visible = false
			_set_alpha(n, 0.65 * minf(1.0, (1.0 - k) * 4.0)))


func _fx_web_burned(p: Dictionary) -> void:
	_burned_webs[p.web_id] = true
	var at := _at(p, 0.1)
	burst(at, {"color": Color("ff8a30"), "count": 14, "speed": 2.5, "up": 3.0, "size": 0.16, "life": 0.5})
	burst(at, {"color": Color("ffe070"), "count": 8, "speed": 1.5, "up": 4.0, "size": 0.1, "life": 0.4})


# 玩家被蛛絲纏住：白色的絲往身上收
func _fx_webbed(p: Dictionary) -> void:
	var at := _at(p, 1.0)
	burst(at, {"color": WEB_COLOR, "count": 12, "speed": 2.0, "up": 1.0, "size": 0.12, "life": 0.4})
	ring(_at(p, 0.6), 0.7, {"color": WEB_COLOR, "life": p.life, "opacity": 0.6})


# 屍甲蟲停在腳下準備冒出：一小塊土一直跳（不畫圈）
# radius（噬墓巨蟲要衝出來的範圍）：土塊在這個範圍的一半以內到處跳、越來越密
func _fx_burrow_warn(p: Dictionary) -> void:
	var at := _at(p, 0.05)
	var spread: float = p.get("radius", 0.0) * 0.5
	_add_emitter(p.life, func(k: float, key: String, dt: float) -> void:
		for i in _count(key, 0.5 if spread <= 0.0 else 1.5 + 2.5 * k, dt):
			var a := _rng.randf() * TAU
			var r := _rng.randf() * spread
			burst(at + Vector3(sin(a) * r, 0.0, cos(a) * r), {"color": DUST_COLOR, "count": 2, "speed": 1.0, "up": 3.0, "size": 0.12, "life": 0.3}))


# 尖嘯幽影的尖嘯：三圈灰白的聲波一圈圈往外到 radius
func _fx_shriek(p: Dictionary) -> void:
	var at := _at(p, 1.0)
	var radius: float = p.radius
	for i in 3:
		ring(at, radius * (i + 1) / 3.0, {"color": Color("dfefff"), "life": 0.25 + 0.12 * i, "opacity": 0.7 - 0.15 * i})


# 屍蛾女王拍翅狂風：前方扇形一道白色弧光，帶鱗粉的風沿著扇形往外吹
func _fx_gust(p: Dictionary) -> void:
	var at := _at(p, 1.0)
	var facing: float = p.facing
	var reach: float = p.range
	var arc: float = p.arc
	slash(at, facing, reach, arc, {"color": Color.WHITE, "opacity": 0.45, "life": 0.3})
	for i in 14:
		var a := facing + _rng.randf_range(-arc * 0.5, arc * 0.5)
		var r := _rng.randf_range(1.0, reach)
		mote(at + Vector3(sin(a) * r, _rng.randf_range(-0.6, 0.6), cos(a) * r), {"color": MOTH_DUST_COLOR, "size": 0.2, "life": 0.5, "vy": 0.4})


# 噬墓巨蟲的卵：一顆淡黃綠的卵立在地上 life 秒，越接近孵化抖得越快，最後破開
func _fx_worm_egg(p: Dictionary) -> void:
	var at := _at(p)
	if not _slash_meshes.has("worm_egg"):
		var sphere := SphereMesh.new()
		sphere.radius = 0.32
		sphere.height = 0.85
		sphere.radial_segments = 8
		sphere.rings = 5
		_slash_meshes["worm_egg"] = sphere
	var egg := _transient_mesh(_slash_meshes["worm_egg"], WORM_EGG_COLOR, 1.0)
	egg.position = at + Vector3(0, 0.4, 0)
	var popped := [false]
	_add_transient(egg, p.life, func(k: float) -> void:
		egg.rotation.z = sin(k * k * 90.0) * 0.12 * k
		if k > 0.97 and not popped[0]:
			popped[0] = true
			burst(at + Vector3(0, 0.4, 0), {"color": WORM_EGG_COLOR, "count": 8, "speed": 3.0, "up": 3.0, "size": 0.14, "life": 0.4}))


func _fx_burrow_out(p: Dictionary) -> void:
	burst(_at(p, 0.1), {"color": DUST_COLOR, "count": 10, "speed": 3.0, "up": 4.0, "size": 0.15, "life": 0.45})


# 一根骨刺竄出：白色尖錐往上刺再縮回去，噴碎石
func _fx_bone_spike(p: Dictionary) -> void:
	var at := _at(p)
	if not _slash_meshes.has("bone_spike"):
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.35
		cone.height = 1.6
		cone.radial_segments = 5
		_slash_meshes["bone_spike"] = cone
	var node := _transient_mesh(_slash_meshes["bone_spike"], BONE_COLOR, 1.0)
	node.position = at
	_add_transient(node, 0.45, func(k: float) -> void:
		var up := minf(1.0, k * 6.0) * (1.0 - maxf(0.0, (k - 0.6) / 0.4))
		node.position.y = at.y + 0.8 * up - 0.4
		node.scale = Vector3(1.0, maxf(0.05, up), 1.0))
	burst(at + Vector3(0, 0.2, 0), {"color": CHARGE_DUST_COLOR, "count": 3, "speed": 2.5, "up": 3.0, "size": 0.12, "life": 0.35})


# 多臂橫掃：低掃貼地一圈弧光（土色）、高掃齊胸一圈（白色）
func _fx_sweep(p: Dictionary) -> void:
	var low: bool = p.low
	var at := _at(p, 0.15 if low else 1.4)
	ring(at, p.radius, {"color": CHARGE_DUST_COLOR if low else Color.WHITE, "life": 0.3, "opacity": 0.7})
	slash(at, 0.0, p.radius, TAU * 0.98, {"color": CHARGE_DUST_COLOR if low else Color.WHITE, "opacity": 0.5, "life": 0.25})


# 骷髏屍體被萬骨聚合體吸過去：一串白點從屍體飛到 Boss 身上
func _on_boss_absorbed(p: Dictionary) -> void:
	var from := Vector3((p.from as Vector2).x, p.get("height", 0.0) + 0.5, (p.from as Vector2).y)
	var to := Vector3((p.pos as Vector2).x, p.get("height", 0.0) + 1.5, (p.pos as Vector2).y)
	for i in 8:
		var k := i / 8.0
		mote(from.lerp(to, k) + Vector3(0, sin(k * PI) * 1.2, 0), {"color": BONE_COLOR, "size": 0.14, "life": 0.3 + k * 0.4, "vy": 0.5})


func _on_boss_devoured(p: Dictionary) -> void:
	var e := _entity(p.boss_id)
	if e != null:
		burst(_entity_at(e, 1.6), {"color": Color("7cc48c"), "count": 10 + 3 * int(p.count), "speed": 2.5, "up": 3.0, "size": 0.16})


# 骨輪撞牆：碎骨與揚塵往外噴
func _on_enemy_crashed(p: Dictionary) -> void:
	var at := _at(p, 0.5)
	burst(at, {"color": BONE_COLOR, "count": 14, "speed": 5.5, "up": 3.5, "size": 0.12, "life": 0.55})
	burst(at, {"color": CHARGE_DUST_COLOR, "count": 10, "speed": 3.0, "up": 1.5, "size": 0.2, "life": 0.5})


func _on_died(p: Dictionary) -> void:
	var e := _entity(p.entity_id)
	if e == null or e is Projectile or e is Player:
		return
	var boss := e is Boss
	burst(_entity_at(e, e.body_height * 0.5), {
		"color": DarkFantasy.BOSS_BLOOD if boss else DarkFantasy.BLOOD,
		"count": 40 if boss else 14, "speed": 8.0 if boss else 4.0, "up": 4.0, "size": 0.3 if boss else 0.18,
	})


func _on_enraged(p: Dictionary) -> void:
	var e := _entity(p.boss_id)
	if e != null:
		ring(_entity_at(e, 0.0), 4.0, {"color": DarkFantasy.BOSS_BLOOD, "life": 0.5})


# 守墓人變身完成：撐破的衣服碎片與毛四散、嚎叫的衝擊環（震退範圍）
func _on_transformed(p: Dictionary) -> void:
	var e := _entity(p.boss_id)
	if e == null:
		return
	var at := _entity_at(e, 0.0)
	if (e as Enemy).def.has("moth"):   # 噬墓巨蟲 → 屍蛾女王：蛹殼碎片往外噴、一圈鱗粉
		ring(at, 3.0, {"color": MOTH_DUST_COLOR, "life": 0.5})
		burst(at + Vector3(0, 1.0, 0), {"color": Color("8d7f5f"), "count": 26, "speed": 6.0, "up": 5.0, "size": 0.2})
		burst(at + Vector3(0, 2.0, 0), {"color": MOTH_DUST_COLOR, "count": 18, "speed": 3.0, "up": 3.0, "size": 0.14})
		return
	if (e as Enemy).def.has("colossus"):   # 骸骨將軍 → 萬骨聚合體：骨頭往上噴、一圈白光
		ring(at, 3.0, {"color": BONE_COLOR, "life": 0.5})
		burst(at + Vector3(0, 1.5, 0), {"color": BONE_COLOR, "count": 30, "speed": 6.0, "up": 5.0, "size": 0.2})
		burst(at + Vector3(0, 2.0, 0), {"color": Color("55e0ff"), "count": 12, "speed": 3.0, "up": 3.0, "size": 0.12})
		return
	var roar: float = (e as Enemy).def.transform.roar_radius
	ring(at, roar, {"color": Color.WHITE, "life": 0.4})
	ring(at, roar * 1.3, {"color": WOLF_FUR, "life": 0.6, "opacity": 0.5})
	burst(at + Vector3(0, 1.5, 0), {"color": KEEPER_COAT, "count": 24, "speed": 7.0, "up": 5.0, "size": 0.22})
	burst(at + Vector3(0, 1.5, 0), {"color": WOLF_FUR, "count": 20, "speed": 5.0, "up": 4.0, "size": 0.16})


func _fx_slash(p: Dictionary) -> void:
	slash(_at(p, 1.0), p.facing, p.range, p.arc, {"color": p.color, "swing_dir": p.swing_dir})


func _fx_muzzle(p: Dictionary) -> void:
	burst(_at(p), {"color": p.color, "count": 5, "speed": 2.5, "up": 1.5, "size": 0.1, "life": 0.25})


func _fx_telegraph(p: Dictionary) -> void:
	telegraph(_at(p), p.radius, {"color": p.color, "life": p.life, "fill": p.get("fill", false)})


func _fx_fizzle(p: Dictionary) -> void:
	burst(_at(p), {"color": p.color, "count": 4, "speed": 2.0, "size": 0.1})


func _fx_explosion(p: Dictionary) -> void:
	ring(_at(p), p.radius, {"color": p.color, "life": 0.4})
	ring(_at(p), p.radius * 0.6, {"color": Color.WHITE, "life": 0.25})
	burst(_at(p, 0.6), {"color": p.color, "count": 26, "speed": 9.0, "up": 6.0, "size": 0.2, "life": 0.6})


# 盾反（v0.23.0）：閃一下實際打得到的扇形範圍（距離 radius、角度 arc），外緣噴金色碎光
func _fx_parry(p: Dictionary) -> void:
	var pos := _at(p, 0.08)
	var key := "parry|%.2f|%.2f" % [p.radius, p.arc]
	if not _slash_meshes.has(key):
		_slash_meshes[key] = _make_sector_mesh(0.3, p.radius, p.arc, 32)
	var node := _transient_mesh(_slash_meshes[key], p.color, 0.6)
	node.position = pos
	node.rotation.y = p.facing
	_add_transient(node, 0.35, func(k: float) -> void:
		_set_alpha(node, 0.6 * (1.0 - k) * (1.0 - k))
		var s := 0.8 + 0.2 * sqrt(k)
		node.scale = Vector3(s, 1.0, s))
	slash(pos + Vector3(0, 0.02, 0), p.facing, p.radius, p.arc, {"color": Color.WHITE, "opacity": 0.5, "life": 0.18})
	for i in 7:
		var a: float = p.facing - p.arc / 2.0 + p.arc * i / 6.0
		burst(pos + Vector3(sin(a), 0.4, cos(a)) * Vector3(p.radius, 1.0, p.radius), {"color": p.color, "count": 3, "speed": 2.5, "up": 2.0, "size": 0.12, "life": 0.3})


# 連鎖閃電（v0.33.0 道具）：points 依序連成發亮的細線，每個落點噴一點火花
func _fx_lightning(p: Dictionary) -> void:
	var y: float = p.get("height", 0.0) + LIGHTNING_HEIGHT
	var pts: Array = p.points
	for i in range(1, pts.size()):
		var a := Vector3(pts[i - 1].x, y, pts[i - 1].y)
		var b := Vector3(pts[i].x, y, pts[i].y)
		var length := a.distance_to(b)
		if length < 1e-3:
			continue
		var box := BoxMesh.new()
		box.size = Vector3(LIGHTNING_WIDTH, LIGHTNING_WIDTH, length)
		var node := _transient_mesh(box, p.color, 1.0)
		node.position = (a + b) / 2.0
		node.look_at_from_position(node.position, b, Vector3.UP)
		_add_transient(node, LIGHTNING_LIFE, func(k: float) -> void:
			_set_alpha(node, 1.0 - k))
		burst(b, {"color": p.color, "count": 6, "speed": 3.0, "up": 2.0, "size": 0.1, "life": 0.25})


# 中毒、冰凍上身（v0.33.0 道具）：一小團該顏色的粒子
func _fx_status(p: Dictionary) -> void:
	burst(_at(p, 1.0), {"color": p.color, "count": 8, "speed": 1.6, "up": 2.5, "size": 0.12, "life": 0.45})


func _fx_heal(p: Dictionary) -> void:
	ring(_at(p), 1.6, {"color": p.color, "life": 0.4})
	burst(_at(p, 0.4), {"color": p.color, "count": 14, "speed": 1.5, "up": 4.0, "gravity": -2.0, "life": 0.7})


func _fx_boss_slam(p: Dictionary) -> void:
	ring(_at(p), p.radius, {"color": Color.WHITE, "life": 0.35})
	ring(_at(p), p.radius * 1.3, {"color": SLAM_RING_COLOR, "life": 0.5, "opacity": 0.5})
	burst(_at(p, 0.2), {"color": CHARGE_DUST_COLOR, "count": 30, "speed": 7.0, "up": 6.0, "size": 0.25})


# 狂暴 Boss 瞬移（v0.27.0）：原地與目的地各一團紫色煙霧
func _fx_boss_teleport(p: Dictionary) -> void:
	var color := Color("b36bff")
	var to: Vector2 = p.to
	for at: Vector3 in [_at(p, 1.2), Vector3(to.x, p.get("height", 0.0) + 1.2, to.y)]:
		burst(at, {"color": color, "count": 24, "speed": 5.0, "up": 3.0, "size": 0.22, "life": 0.5})
	ring(Vector3(to.x, p.get("height", 0.0), to.y), 3.0, {"color": color, "life": 0.35})


# 狂暴 Boss 瞬移前：目的地冒出越來越濃的紫煙（不畫圈）
func _fx_boss_teleport_warn(p: Dictionary) -> void:
	var at := _at(p, 0.1)
	_add_emitter(p.life, func(k: float, key: String, dt: float) -> void:
		for i in _count(key, 0.3 + 0.7 * k, dt):
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(0.2, 1.3)
			mote(at + Vector3(sin(a) * r, 0.0, cos(a) * r), {"color": TELEPORT_COLOR, "size": 0.2, "life": 0.6, "vy": 1.8}))


# 挖墳點噴怪前：墳土隆起、裂開，冒出白骨手，泥土一直噴（不畫圈）
# look = sarcophagus（第 2 層的石棺）：不隆起土堆，白骨手從棺口伸出來，冒石屑與封印的紫光；cocoon（第 3 層的巨繭）：綠光與絲屑
func _fx_erupt_warn(p: Dictionary) -> void:
	var at := _at(p)
	var radius: float = p.radius
	var life: float = p.life
	var look: StringName = p.get("look", &"grave")
	var coffin := look == &"sarcophagus"
	var dust: Color = COFFIN_DUST if coffin else DUST_COLOR
	if look == &"cocoon":
		# 巨繭：不隆起、沒有白骨手，裂口一陣一陣冒綠光、絲屑往外飄
		at.y += COCOON_MID
		_add_emitter(life, func(k: float, key: String, dt: float) -> void:
			for i in _count(key, 0.4 + 0.8 * k, dt):
				var a := _rng.randf() * TAU
				var r := _rng.randf_range(0.1, 0.7)
				mote(at + Vector3(sin(a) * r, _rng.randf_range(-0.8, 0.8), cos(a) * r), {"color": COCOON_GLOW, "size": 0.16, "life": 0.5, "vy": 1.2})
			for i in _count(key + "s", 0.25 + 0.5 * k, dt):
				burst(at, {"color": COCOON_SHRED, "count": 2, "speed": 2.2, "up": 1.5, "size": 0.12, "life": 0.5}))
		return
	if coffin:
		at.y += COFFIN_TOP
		radius *= 0.6   # 手與石屑在棺口裡
		_add_emitter(life, func(k: float, key: String, dt: float) -> void:
			for i in _count(key, 0.4 + 0.6 * k, dt):
				var a := _rng.randf() * TAU
				var r := _rng.randf_range(0.2, 1.1)
				mote(at + Vector3(sin(a) * r, 0.0, cos(a) * r * 0.6), {"color": SEAL_COLOR, "size": 0.16, "life": 0.5, "vy": 1.6}))
	else:
		var mound_mesh := SphereMesh.new()
		mound_mesh.radius = 1.0
		mound_mesh.height = 1.0
		var mound := _transient_mesh(mound_mesh, DUST_COLOR, 1.0)
		mound.position = at
		_add_transient(mound, life, func(k: float) -> void:
			var e := MathUtil.ease_out_cubic(k)
			var s := radius * 0.5 * maxf(e, 0.05)
			mound.scale = Vector3(s, 0.05 + 0.45 * e + 0.04 * sin(k * 60.0), s))
	var hand_mesh := BoxMesh.new()
	hand_mesh.size = Vector3(0.1, 0.6, 0.1)
	for i in ERUPT_HANDS:
		var a := TAU * i / ERUPT_HANDS + _rng.randf_range(-0.4, 0.4)
		var r := radius * _rng.randf_range(0.15, 0.35)
		var base := at + Vector3(sin(a) * r, 0.0, cos(a) * r)
		var tilt := Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.4, 0.4))
		var hand := _transient_mesh(hand_mesh, BONE_COLOR, 0.0)
		hand.rotation = tilt
		_add_transient(hand, life, func(k: float) -> void:
			var rise := clampf((k - ERUPT_HANDS_FROM) / (1.0 - ERUPT_HANDS_FROM), 0.0, 1.0)
			_set_alpha(hand, 1.0 if rise > 0.0 else 0.0)
			hand.position = base + Vector3(0.0, -0.3 + 0.55 * rise, 0.0))
	_add_emitter(life, func(k: float, key: String, dt: float) -> void:
		for i in _count(key, 0.25 + 0.5 * k, dt):
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(0.0, radius * 0.5)
			burst(at + Vector3(sin(a) * r, 0.2, cos(a) * r), {"color": dust, "count": 2, "speed": 1.5, "up": 3.0, "size": 0.15, "life": 0.4}))


# 怪物的毒氣 / 殘火區（膨脹屍的腐氣、守墓人的殘火）：範圍內一直冒低低的煙或火苗，不畫圈；最後 0.5 秒變稀
func _fx_gas_cloud(p: Dictionary) -> void:
	var at := _at(p)
	var radius: float = p.radius
	var life: float = p.life
	var color: Color = p.color
	var fire: bool = p.get("fire", false)
	_add_emitter(life, func(k: float, key: String, dt: float) -> void:
		var thin := clampf((1.0 - k) * life / 0.5, 0.0, 1.0)
		for i in _count(key, 1.2 * thin, dt):
			var a := _rng.randf() * TAU
			var r := radius * sqrt(_rng.randf())
			if fire:
				mote(at + Vector3(sin(a) * r, 0.1, cos(a) * r), {"color": color.lerp(Color("ffe070"), _rng.randf()), "size": 0.2, "life": 0.45, "vy": 1.6})
			else:
				mote(at + Vector3(sin(a) * r, _rng.randf_range(0.1, 0.6), cos(a) * r), {"color": color, "size": 0.32, "life": 0.9, "vy": 0.35}))


# 守墓人鏟土拋擲：每坨土沿拋物線飛到落點，地上的影子跟著越來越大、越來越深（看影子躲，不畫圈）；落地噴泥土
func _fx_dirt_lob(p: Dictionary) -> void:
	var from := _at(p)
	var flight: float = p.flight
	var radius: float = p.radius
	var clod_mesh := BoxMesh.new()
	clod_mesh.size = Vector3(0.35, 0.3, 0.35)
	var shadow_only: bool = p.get("shadow_only", false)   # 狼人飛撲：只畫落點的影子（跳的是狼人本身）
	var from_sky: bool = p.get("from_sky", false)         # 瘋狂鏟土的落石：從落點正上方直直掉下來（石頭比較大）
	if from_sky:
		clod_mesh.size = Vector3(0.7, 0.55, 0.7)
	for target: Vector2 in p.targets:
		var to := Vector3(target.x, world.terrain.ground_at(target) if world != null else 0.0, target.y)
		var shadow := _transient_mesh(_disc_mesh, Color.BLACK, 0.0)
		shadow.position = to + Vector3(0, 0.04, 0)
		_add_transient(shadow, flight, func(k: float) -> void:
			var s := radius * lerpf(0.3, 1.0, k)
			shadow.scale = Vector3(s, 1.0, s)
			_set_alpha(shadow, 0.5 * k))
		if shadow_only:
			continue
		var clod := _transient_mesh(clod_mesh, p.get("color", DUST_COLOR), 1.0)
		var landed := [false]
		var start := to + Vector3(0, ROCK_FALL_HEIGHT, 0) if from_sky else from
		_add_transient(clod, flight, func(k: float) -> void:
			var pos := start.lerp(to, k * k) if from_sky else start.lerp(to, k)   # 落石：越掉越快
			if not from_sky:
				pos.y += 4.0 * DIRT_LOB_HEIGHT * k * (1.0 - k)
			clod.position = pos
			clod.rotation = Vector3(k * 9.0, k * 6.0, 0.0)
			if k > 0.97 and not landed[0]:
				landed[0] = true
				burst(to + Vector3(0, 0.2, 0), {"color": DUST_COLOR, "count": 14, "speed": 4.0, "up": 4.0, "size": 0.2}))


# 狼人爪擊：身前空中 CLAW_MARKS 條平行的紅色爪痕（橫過身前的細長條、斜著排），一下子劃出來再淡掉
# side：1 = 右爪、-1 = 左爪（斜的方向相反）、0 = 雙爪（橫的、比較長）
func _fx_claw(p: Dictionary) -> void:
	var facing: float = p.facing
	var reach: float = p.range
	var side: float = p.side
	var length := reach * (1.1 if side == 0.0 else 0.85)
	var tilt := CLAW_MARK_TILT * side
	var fwd := Vector3(sin(facing), 0.0, cos(facing))
	var center := _at(p, 1.4) + fwd * reach * 0.5
	var mesh := BoxMesh.new()
	mesh.size = Vector3(CLAW_MARK_WIDTH, CLAW_MARK_WIDTH * 0.6, length)
	for i in CLAW_MARKS:
		var off := (i - (CLAW_MARKS - 1) / 2.0) * CLAW_MARK_GAP
		var node := _transient_mesh(mesh, p.color, 1.0)
		node.position = center + Vector3(0, off, 0) + fwd * off * 0.2
		node.rotation = Vector3(tilt, facing + PI / 2.0, 0.0)   # 長邊橫過身前，再往上 / 下斜
		_add_transient(node, CLAW_MARK_LIFE, func(k: float) -> void:
			var grow := minf(1.0, k * 6.0)   # 前 1/6 時間劃出來
			node.scale = Vector3(1.0, 1.0, maxf(grow, 0.05))
			_set_alpha(node, 1.0 - k * k))
	burst(center, {"color": p.color, "count": 8, "speed": 4.0, "up": 1.5, "size": 0.1, "life": 0.25})


func _fx_boss_wall(p: Dictionary) -> void:
	ring(_at(p), 2.5, {"color": Color.WHITE, "life": 0.35})
	burst(_at(p, 1.0), {"color": WALL_DEBRIS_COLOR, "count": 20, "speed": 6.0, "up": 5.0, "size": 0.22})


# ───────── 每幀：持續性粒子 + 更新 ─────────

func sync(p_world: World, dt: float) -> void:
	world = p_world
	if paused:
		return
	if dt > 0.0:
		_emit_continuous(dt)
	_update_particles(dt)
	_update_transients(dt)


# 網頁版每步機率 chance 產生一顆 → 這一幀要產生幾顆：每秒 chance × 60 顆，不滿一顆的小數留到下一幀（key 區分每個產生源）
func _count(key: String, chance: float, dt: float) -> int:
	var total: float = _carry.get(key, 0.0) + chance * STEPS_PER_SECOND * dt
	var n := int(total)
	_next_carry[key] = total - n
	return n


func _jitter(e: Entity, spread: float, y: float) -> Vector3:
	return Vector3(e.pos.x + _rng.randf_range(-spread, spread), y, e.pos.y + _rng.randf_range(-spread, spread))


func _emit_continuous(dt: float) -> void:
	if _warm_stream != null:
		_warm_stream.queue_free()
		_warm_stream = null
	_next_carry = {}
	_flame_seen.clear()
	for e: Entity in world.entities.values():
		if e.is_removed or hidden_ids.has(e.id):
			continue
		if e is Projectile:
			var pr := e as Projectile
			for i in _count("%d" % e.id, 1.0, dt):
				mote(_entity_at(pr, 0.0), {"color": pr.color, "size": pr.radius * 0.6, "life": 0.25})
		elif e is Player:
			_emit_player(e, dt)
		elif e is Enemy:
			_emit_enemy(e, dt)
	_update_emitters(dt)   # 要在 _carry 換成這一幀的之前（不滿一顆的小數才留得下來）
	_carry = _next_carry
	_retire_flames()


# 這一幀沒在噴的（噴完、看不到、死了、移除了）火舌、火柱拿掉
func _retire_flames() -> void:
	if _flames.size() == _flame_seen.size():
		return
	for id: int in _flames.keys():
		if not _flame_seen.has(id):
			(_flames[id] as Node).queue_free()
			_flames.erase(id)
			if _streams.has(id):
				(_streams[id].node as Node).queue_free()
				_streams.erase(id)


func _emit_player(p: Player, dt: float) -> void:
	var a := p.anim
	# 暈眩（v0.27.0：被 Boss 衝鋒撞到）：頭上轉圈的星星，同 Boss 撞牆暈眩
	if a.get("stunned", false):
		for i in _count("%d:stun" % p.id, 0.2, dt):
			mote(_jitter(p, 0.4, p.height + p.body_height + 0.2), {"color": STUN_STAR_COLOR, "size": 0.13, "life": 0.4, "vy": 0.4})
	# 奧術爆裂蓄力：魔力粒子往杖頭聚集
	if a.get("behavior") == &"arcaneBurst" and a.get("phase") == &"windup":
		var c: Dictionary = p.weapon.special
		var head := p.pos + MathUtil.dir_from_angle(p.facing) * 0.3
		for i in _count("%d:charge" % p.id, 1.0, dt):
			mote(Vector3(head.x + _rng.randf_range(-0.8, 0.8), p.height + _rng.randf_range(1.6, 2.8), head.y + _rng.randf_range(-0.8, 0.8)),
				{"color": c.color, "size": 0.12, "life": 0.3, "vy": 0.8})
	# 疾跑殘影：移動中每 0.04 秒一顆
	var trail: Variant = a.get("trail_color")
	if trail != null and p.velocity.length_squared() >= 1.0:
		for i in _count("%d:trail" % p.id, 1.0 / (0.04 * STEPS_PER_SECOND), dt):
			burst(_entity_at(p, 0.3), {"color": trail, "count": 1, "speed": 0.5, "up": 0.5, "gravity": 0.0, "size": 0.18, "life": 0.35})


func _emit_enemy(e: Enemy, dt: float) -> void:
	var a := e.anim
	var key := "%d" % e.id
	_emit_bond_status(e, a, key, dt)
	match a.get("state"):
		&"spawn":
			for i in _count(key, 0.4, dt):
				burst(_entity_at(e, 0.1), {"color": DUST_COLOR, "count": 1, "speed": 2.0, "up": 3.0, "size": 0.15})
		&"dead":
			# 死亡爆炸詞條：爆開前屍體冒出該詞條顏色的氣體，越接近爆開越多
			if e.has_affix(&"volatile"):
				var v := e.affix(&"volatile")
				var t: float = a.get("time", 0.0)
				if t < v.delay:
					for i in _count(key, 0.2 + 0.6 * t / v.delay, dt):
						mote(_jitter(e, 0.5, e.height + _rng.randf_range(0.2, 0.9)), {"color": v.color, "size": 0.16, "life": 0.45, "vy": 1.2})
		&"slam":
			_emit_slam_pebbles(e, a, key, dt)
		&"lantern":
			_emit_lantern(e, a, key, dt)
		&"scoop":
			# 鏟起連段 B：退一步、開燈罩後直噴（窄扇形）
			var b: Dictionary = e.def.scoop.bury
			var t: float = a.get("phase_time", 0.0) - b.step_time - b.open
			if a.get("phase", &"") == &"bury" and t >= 0.0 and t < b.flame:
				_flame(e, b.range, b.arc, dt)
				_flame_jet(e, b.range, b.arc, key, dt)
		&"transform":
			# 守墓人變身中：身上一直冒黑毛
			for i in _count(key, 0.8, dt):
				mote(_jitter(e, 0.6, e.height + _rng.randf_range(0.8, 2.4)), {"color": WOLF_FUR, "size": 0.15, "life": 0.4, "vy": 1.5})
		&"swell":
			# 膨脹屍脹大：皮膚裂縫冒出綠氣，越接近爆開越多
			var k := EnemyAnimator.bloater_swell(e, &"swell", a.get("time", 0.0))
			for i in _count(key, 0.3 + 0.9 * k, dt):
				mote(_jitter(e, 0.5, e.height + _rng.randf_range(0.6, 1.4)), {"color": e.def.gas.color, "size": 0.16, "life": 0.4, "vy": 1.0})
		&"aim":
			var tip := e.pos + MathUtil.dir_from_angle(e.facing) * 0.7
			for i in _count(key, 0.5, dt):
				mote(Vector3(tip.x, e.height + e.body_height * 0.65, tip.y),
					{"color": e.def.projectile_color, "size": 0.08, "life": 0.25, "vy": 0.6})
		&"charge":
			if a.get("phase") == &"windup":
				# 後腳刨地揚起的塵土（姿勢見 EnemyAnimator.charge_scrape）
				var back := e.pos - MathUtil.dir_from_angle(e.facing) * 0.7
				for i in _count(key, 0.5, dt):
					burst(Vector3(back.x, e.height + 0.1, back.y), {"color": CHARGE_DUST_COLOR, "count": 2, "speed": 1.5, "up": 1.5, "size": 0.16, "life": 0.4})
			elif a.get("phase") == &"dash":
				for i in _count(key, 0.6, dt):
					burst(_entity_at(e, 0.1), {"color": CHARGE_DUST_COLOR, "count": 1, "speed": 2.0, "up": 2.0, "size": 0.2})
			elif a.get("phase") == &"stunned":
				for i in _count(key, 0.2, dt):
					mote(_jitter(e, 0.5, e.height + e.body_height + 0.2), {"color": STUN_STAR_COLOR, "size": 0.15, "life": 0.4, "vy": 0.4})
		&"summon":
			for i in _count(key, 0.7, dt):
				mote(_jitter(e, 1.5, e.height + _rng.randf_range(0.2, 1.0)), {"color": DarkFantasy.BOSS_BLOOD, "size": 0.15, "life": 0.5, "vy": 2.0})


# 羈絆的狀態（Build 改版第 5 步）：失衡頭上轉星星、燃燒層數越多冒越多火、冰冷冒白霜、冰棺全身冒冰晶
func _emit_bond_status(e: Enemy, a: Dictionary, key: String, dt: float) -> void:
	if a.get("staggered", false):
		for i in _count(key + ":stagger", 0.25, dt):
			mote(_jitter(e, 0.4, e.height + e.body_height + 0.2), {"color": STUN_STAR_COLOR, "size": 0.13, "life": 0.4, "vy": 0.4})
	var stacks: int = a.get("burn_stacks", 0)
	if stacks > 1:
		for i in _count(key + ":burn", 0.08 * stacks, dt):
			mote(_jitter(e, 0.45, e.height + _rng.randf_range(0.3, e.body_height)), {"color": Enemy.BURN_COLOR, "size": 0.13, "life": 0.35, "vy": 1.6})
	var chill: int = a.get("chill", 0)
	if chill > 0:
		for i in _count(key + ":chill", 0.05 * chill, dt):
			mote(_jitter(e, 0.45, e.height + _rng.randf_range(0.2, e.body_height)), {"color": Enemy.CHILL_COLOR, "size": 0.1, "life": 0.5, "vy": -0.3})
	if a.get("coffin", false):
		for i in _count(key + ":coffin", 0.4, dt):
			mote(_jitter(e, 0.6, e.height + _rng.randf_range(0.0, e.body_height + 0.2)), {"color": COFFIN_SHARD_COLOR, "size": 0.16, "life": 0.6, "vy": 0.5})


# Boss 砸地：裂紋已經爬滿、快要爆開的那一圈，地上的碎石一直跳起來
func _emit_slam_pebbles(e: Enemy, a: Dictionary, key: String, dt: float) -> void:
	var slam: Dictionary = e.def.slam
	var rings: Array = slam.rings
	var phase: StringName = a.get("phase", &"")
	var pt: float = a.get("phase_time", 0.0)
	var windup: float = a.get("windup", slam.windup)
	for i in rings.size():
		if not EnemyAnimator.slam_band_charging(phase, pt, windup, i, slam.ring_delay):
			continue
		var inner: float = e.radius * 0.6 if i == 0 else rings[i - 1]
		for n in _count("%s:p%d" % [key, i], 1.2, dt):
			var ang := _rng.randf() * TAU
			var r := _rng.randf_range(inner, rings[i])
			burst(Vector3(e.pos.x + sin(ang) * r, e.height + 0.1, e.pos.y + cos(ang) * r),
				{"color": CHARGE_DUST_COLOR, "count": 1, "speed": 0.4, "up": 2.5, "size": 0.13, "life": 0.35})


# 守墓人提燈：windup 時燈火轉藍、往提燈聚（吸氣）；spin_windup 藍火繞著身體轉（下一下要掃一圈）；
# flame 時前方扇形的火舌 + 從提燈往外噴的粒子；spin 時身邊一整圈
func _emit_lantern(e: Enemy, a: Dictionary, key: String, dt: float) -> void:
	var f: Dictionary = e.def.lantern
	var lamp := _lamp_at(e)
	match a.get("phase", &""):
		&"windup":
			for i in _count(key, 2.0, dt):
				mote(Vector3(lamp.x + _rng.randf_range(-0.35, 0.35), lamp.y + _rng.randf_range(-0.2, 0.3), lamp.z + _rng.randf_range(-0.35, 0.35)),
					{"color": LANTERN_BLUE, "size": 0.18, "life": 0.3, "vy": 0.2})
		&"spin_windup":
			for i in _count(key, 2.0, dt):
				var ang := _rng.randf() * TAU
				mote(Vector3(e.pos.x + sin(ang) * 1.2, e.height + _rng.randf_range(0.4, 1.6), e.pos.y + cos(ang) * 1.2),
					{"color": LANTERN_BLUE, "size": 0.2, "life": 0.3, "vy": 0.6})
		&"flame":
			_flame(e, f.range, f.arc, dt)
			_flame_jet(e, f.range, f.arc, key, dt)
		&"spin":
			_flame(e, f.spin_range, TAU, dt)
			_flame_jet(e, f.spin_range, TAU, key, dt)


# 提燈的位置（守墓人左手前方、肩膀高度）
func _lamp_at(e: Enemy) -> Vector3:
	var fwd := MathUtil.dir_from_angle(e.facing)
	var side := Vector2(fwd.y, -fwd.x)
	var lamp := e.pos + fwd * 0.7 - side * 0.4
	return Vector3(lamp.x, e.height + 1.9, lamp.y)


# 火舌：這隻怪前方 reach、arc 的扇形（TAU = 一整圈），跟著它的位置與朝向；每幀閃一下
func _flame(e: Enemy, reach: float, arc: float, dt: float) -> void:
	_flame_stream(e, reach, arc, dt)
	var mesh := _flame_mesh(reach, arc)
	var node: MeshInstance3D = _flames.get(e.id)
	if node == null:
		node = _flame_node(mesh)
		add_child(node)
		_flames[e.id] = node
	elif node.mesh != mesh:
		node.mesh = mesh
	node.position = Vector3(e.pos.x, e.ground_height + FLAME_Y, e.pos.y)
	node.rotation.y = e.facing
	node.transparency = _rng.randf_range(FLAME_FLICKER.x, FLAME_FLICKER.y)
	_flame_seen[e.id] = true


# 立體火柱：每團火從起點（提燈；一整圈時是身體）往扇形裡的某個方向流 FLAME_TRAVEL 秒到範圍盡頭，到了就從起點重來。
# 剛開始噴時每團的進度從負的開始，火柱會從提燈「噴出來」長到全長；燈光在火焰中段一直閃
func _flame_stream(e: Enemy, reach: float, arc: float, dt: float) -> void:
	var s: Dictionary = _streams.get(e.id, {})
	if s.is_empty():
		s = _new_stream()
		add_child(s.node)
		_streams[e.id] = s
	var full := arc >= TAU
	var from := _lamp_at(e) if not full else Vector3(e.pos.x, e.height + 1.2, e.pos.y)
	var ground := e.ground_height + FLAME_Y
	var mm: MultiMesh = s.mm
	mm.visible_instance_count = FLAME_BLOBS
	for i in FLAME_BLOBS:
		var b: Dictionary = s.blobs[i]
		var was: float = b.t
		b.t += dt / FLAME_TRAVEL
		if b.t >= 1.0 or (was < 0.0 and b.t >= 0.0):   # 從起點重新出發：換一個方向
			b.t = fmod(b.t, 1.0)
			b.ang = _rng.randf() * TAU if full else _rng.randf_range(-0.5, 0.5) * arc * FLAME_BLOB_SPREAD
			b.lift = _rng.randf_range(-0.2, 0.45)
		var t: float = b.t
		if t < 0.0:
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), from))
			continue
		var ang: float = e.facing + b.ang
		var travel := 1.0 - pow(1.0 - t, 1.6)   # 一出提燈最快、越遠越慢（火往外散開）
		var at := from.lerp(Vector3(e.pos.x + sin(ang) * reach, ground + b.lift, e.pos.y + cos(ang) * reach), travel)
		at.y += sin(t * PI) * 0.35 + _rng.randf_range(-0.06, 0.06)   # 中段往上捲一點、抖動
		var size := lerpf(FLAME_BLOB_SIZE.x, FLAME_BLOB_SIZE.y, t) * _rng.randf_range(0.85, 1.15)
		var c := (FLAME_STREAM_COLORS[0] as Color).lerp(FLAME_STREAM_COLORS[1], t * 2.0) if t < 0.5 \
			else (FLAME_STREAM_COLORS[1] as Color).lerp(FLAME_STREAM_COLORS[2], t * 2.0 - 1.0)
		var dir := Vector3(sin(ang), 0.0, cos(ang))
		mm.set_instance_transform(i, Transform3D(Basis.looking_at(dir, Vector3.UP).scaled_local(Vector3(size, size * 0.7, size * FLAME_BLOB_STRETCH)), at))
		mm.set_instance_color(i, c)
	var light: OmniLight3D = s.light
	var mid := from.lerp(Vector3(e.pos.x, ground, e.pos.y) + Vector3(sin(e.facing), 0.0, cos(e.facing)) * reach, FLAME_LIGHT_AT) if not full else from
	light.position = Vector3(mid.x, e.ground_height + FLAME_LIGHT_HEIGHT, mid.z)
	light.omni_range = reach * (0.9 if not full else 1.4)
	light.light_energy = _rng.randf_range(FLAME_LIGHT_ENERGY.x, FLAME_LIGHT_ENERGY.y)


func _new_stream() -> Dictionary:
	var node := Node3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = FLAME_BLOBS
	mm.visible_instance_count = 0
	mm.mesh = _blob_mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -10, -200), Vector3(400, 60, 400))   # 火團的位置是世界座標，不讓整組被視錐剔除
	node.add_child(mmi)
	var light := OmniLight3D.new()
	light.light_color = FLAME_LIGHT_COLOR
	light.shadow_enabled = false
	light.omni_attenuation = 1.4
	node.add_child(light)
	var blobs := []
	for i in FLAME_BLOBS:
		blobs.append({"t": -float(i) / FLAME_BLOBS, "ang": 0.0, "lift": 0.0})
	return {"node": node, "mm": mm, "light": light, "blobs": blobs}


func _flame_node(mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _flame_mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


# 噴流：粒子從提燈（一整圈時從身體）出發，往扇形裡的方向飛，FLAME_JET_LIFE 秒後剛好到範圍的 70%~100% 才消失；開頭大、越飛越小
func _flame_jet(e: Enemy, reach: float, arc: float, key: String, dt: float) -> void:
	var from := _lamp_at(e) if arc < TAU else Vector3(e.pos.x, e.height + 1.2, e.pos.y)
	var color: Color = e.def.lantern.color
	for i in _count(key + ":jet", FLAME_JET, dt):
		if _particles.size() >= MAX_PARTICLES:
			return
		var ang := e.facing + _rng.randf_range(-arc / 2.0, arc / 2.0)
		var r := reach * _rng.randf_range(0.7, 1.0)
		var to := Vector3(e.pos.x + sin(ang) * r, e.ground_height + FLAME_Y * _rng.randf_range(0.5, 1.5), e.pos.y + cos(ang) * r)
		spawned_total += 1
		_particles.append({
			"pos": from, "vel": (to - from) / FLAME_JET_LIFE, "rot": Vector2(_rng.randf() * 3.0, _rng.randf() * 3.0), "gravity": 0.0,
			"color": color.lerp(Color("ffe070"), _rng.randf()), "size": FLAME_JET_SIZE * _rng.randf_range(0.8, 1.2),
			"life": FLAME_JET_LIFE, "max_life": FLAME_JET_LIFE,
		})


func _flame_mesh(reach: float, arc: float) -> ArrayMesh:
	var key := "%.2f|%.2f" % [reach, arc]
	if not _flame_meshes.has(key):
		_flame_meshes[key] = _make_flame_mesh(reach, arc)
	return _flame_meshes[key]


func _add_emitter(life: float, tick: Callable) -> void:
	_emitter_serial += 1
	_emitters.append({"key": "em%d" % _emitter_serial, "life": life, "max_life": life, "tick": tick, "gate": _gate})


func _update_emitters(dt: float) -> void:
	for i in range(_emitters.size() - 1, -1, -1):
		var em := _emitters[i]
		em.life -= dt
		if em.life <= 0.0:
			_emitters.remove_at(i)
			continue
		if _gate_open(em.gate):
			em.tick.call(1.0 - em.life / em.max_life, em.key, dt)


func _update_particles(dt: float) -> void:
	for i in range(_particles.size() - 1, -1, -1):
		var p := _particles[i]
		p.life -= dt
		if p.life <= 0.0:
			_particles.remove_at(i)
			continue
		p.vel.y -= p.gravity * dt
		var pos: Vector3 = p.pos + p.vel * dt
		pos.y = maxf(0.05, pos.y)
		p.pos = pos
		p.rot.x += dt * 6.0
	_multimesh.visible_instance_count = _particles.size()
	for i in _particles.size():
		var p := _particles[i]
		var s: float = p.size * (p.life / p.max_life)
		var basis := Basis.from_euler(Vector3(p.rot.x, p.rot.y, 0.0)).scaled(Vector3.ONE * s)
		_multimesh.set_instance_transform(i, Transform3D(basis, p.pos))
		_multimesh.set_instance_color(i, p.color)


func _update_transients(dt: float) -> void:
	for i in range(_transients.size() - 1, -1, -1):
		var t := _transients[i]
		t.life -= dt
		if t.life <= 0.0:
			t.node.queue_free()
			_transients.remove_at(i)
			continue
		if not t.gate.is_empty():
			t.node.visible = _gate_open(t.gate)
		t.update.call(1.0 - t.life / t.max_life)


# ───────── 網格與材質 ─────────

func _add_transient(node: MeshInstance3D, life: float, update: Callable) -> void:
	if _transients.size() >= MAX_TRANSIENTS:   # 滿了就先結束最舊的
		_transients[0].node.queue_free()
		_transients.remove_at(0)
	add_child(node)
	if not _gate.is_empty():
		node.visible = _gate_open(_gate)
	update.call(0.0)
	_transients.append({"node": node, "life": life, "max_life": life, "update": update, "gate": _gate})


func _transient_mesh(mesh: Mesh, color: Color, opacity: float) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color, opacity)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func _set_alpha(node: MeshInstance3D, alpha: float) -> void:
	var mat: StandardMaterial3D = node.material_override
	mat.albedo_color.a = alpha


# 平放的圓環（內徑 0.85、外徑 1），縮放 = 半徑
static func _make_ring_mesh() -> ArrayMesh:
	return _make_sector_mesh(RING_INNER, 1.0, TAU, RING_SEGMENTS)


# 火舌的網格：平放的扇形（中心線朝 +Z），FLAME_INNER 到 reach 分成幾圈、照 FLAME_COLORS 由內到外漸變，最外緣 FLAME_RIM 一圈較亮
static func _make_flame_mesh(reach: float, arc: float, segments: int = SLASH_SEGMENTS) -> ArrayMesh:
	var rim_at := reach * (1.0 - FLAME_RIM)
	var radii: Array[float] = [FLAME_INNER, lerpf(FLAME_INNER, rim_at, 0.5), rim_at, reach]
	var colors: Array[Color] = [FLAME_COLORS[0], FLAME_COLORS[1], FLAME_COLORS[2], FLAME_RIM_COLOR]
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var segs := segments * 2 if arc >= TAU else segments
	for i in segs:
		var a0 := -arc / 2.0 + arc * i / segs
		var a1 := -arc / 2.0 + arc * (i + 1) / segs
		var d0 := Vector3(sin(a0), 0.0, cos(a0))
		var d1 := Vector3(sin(a1), 0.0, cos(a1))
		for j in radii.size() - 1:
			var c_in: Color = colors[j] if j < 2 else FLAME_RIM_COLOR   # 亮邊那一圈整圈都亮
			var c_out: Color = colors[j + 1]
			var r0: float = radii[j]
			var r1: float = radii[j + 1]
			verts.append_array([d0 * r0, d0 * r1, d1 * r1, d0 * r0, d1 * r1, d1 * r0])
			cols.append_array([c_in, c_out, c_out, c_in, c_out, c_in])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# 平放的扇環：中心線朝 +Z（facing = 0），角度 arc、內徑 inner、外徑 outer
static func _make_sector_mesh(inner: float, outer: float, arc: float, segments: int = SLASH_SEGMENTS) -> ArrayMesh:
	var verts := PackedVector3Array()
	for i in segments:
		var a0 := -arc / 2.0 + arc * i / segments
		var a1 := -arc / 2.0 + arc * (i + 1) / segments
		var d0 := Vector3(sin(a0), 0.0, cos(a0))
		var d1 := Vector3(sin(a1), 0.0, cos(a1))
		verts.append_array([d0 * inner, d0 * outer, d1 * outer, d0 * inner, d1 * outer, d1 * inner])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
