# 快照的編碼與套用（15.18）：房主把 World 打包成只含數值的陣列，客戶端把陣列套到鏡像 World 的實體上
# 實體欄位固定順序（E_*），各類別的額外欄位放在 E_EXTRA
# 網路上傳的是壓縮過的格式（encode_entity）：數值欄位放 PackedFloat32Array、動畫的欄位名稱換成 ANIM_KEYS 的索引；
# 客戶端收到時 decode_snapshot 展開成 E_* 的格式再使用
class_name NetCodec

enum { S_RUN, S_TICK, S_ACK, S_WORLD, S_ENTITIES }
enum { W_WAVE, W_KILLS, W_TIME, W_OVER, W_BOSS, W_DEFEATED }
enum { E_ID, E_KIND, E_X, E_Z, E_H, E_FACING, E_HP, E_MAX_HP, E_VX, E_VZ, E_FLASH, E_INVULN, E_DEAD, E_ANIM, E_EXTRA }
# 玩家的 E_EXTRA
enum { P_PEER, P_WEAPON, P_ROLLS, P_DOWNED, P_DOWN_TIMER, P_REVIVE, P_PARRY, P_DODGE }

const ENEMY_KINDS: Array[StringName] = [&"grunt", &"archer", &"boss"]
# 動畫欄位名稱 → 索引（Player._update_anim、Enemy._update_anim、Boss._anim_extra）；不在表裡的照樣用字串送
const ANIM_KEYS: Array[String] = [
	"loco", "loco_time", "action", "action_time", "behavior", "phase", "k", "swing_dir", "is_finisher",
	"trail_color", "airborne", "blocking", "parry", "vz", "revive",
	"state", "time", "enraged", "phase_time", "origin",
]
# 玩家動畫欄位的預設值：和預設值相同的欄位不送（大部分時間只剩移動層、動作層的名稱與秒數），收到時補回
const PLAYER_ANIM_DEFAULTS := {
	"behavior": &"", "phase": &"", "k": 0.0, "swing_dir": 1, "is_finisher": false, "trail_color": null,
	"airborne": false, "blocking": false, "parry": 0.0, "vz": 0.0, "revive": 0.0,
}
const NUM_FIRST := E_X      # E_X ~ E_INVULN 是數值欄位，網路上放進一個 PackedFloat32Array
const NUM_LAST := E_INVULN


# 實體的部分只編一次，再依玩家填上各自的 ack（房主最後套用的該玩家輸入編號）
static func encode_entities(world: World) -> Array:
	var out := []
	for e: Entity in world.entities.values():
		if not e.is_removed:
			out.append(encode_entity(e))
	return out


static func make_snapshot(world: World, entities: Array, ack: int) -> Array:
	var s := world.stats
	return [world.run_id, world.tick, ack, [s.wave, s.kills, s.time, world.is_over, world.boss_id, world.is_defeated], entities]


# 網路格式：[id, kind, 數值（PackedFloat32Array）, is_dead, 動畫（[索引或名稱, 值, …]）, extra]
static func encode_entity(e: Entity) -> Array:
	var a := entity_fields(e)
	var nums := PackedFloat32Array(a.slice(NUM_FIRST, NUM_LAST + 1))
	var is_player: bool = a[E_KIND] == &"player"
	return [a[E_ID], a[E_KIND], nums, a[E_DEAD], pack_anim(a[E_ANIM], PLAYER_ANIM_DEFAULTS if is_player else {}), a[E_EXTRA]]


static func decode_entity(w: Array) -> Array:
	var a := [w[0], w[1]]
	for v: float in w[2]:
		a.append(v)
	var is_player: bool = w[1] == &"player"
	a.append_array([w[3], unpack_anim(w[4], PLAYER_ANIM_DEFAULTS if is_player else {}), w[5]])
	return a


# 收到的快照展開成 E_* 格式（原地修改並回傳）
static func decode_snapshot(snap: Array) -> Array:
	snap[S_ENTITIES] = (snap[S_ENTITIES] as Array).map(decode_entity)
	return snap


static func pack_anim(anim: Dictionary, defaults: Dictionary) -> Array:
	var out := []
	for k: Variant in anim:
		var v: Variant = anim[k]
		if defaults.has(k) and typeof(v) == typeof(defaults[k]) and v == defaults[k]:
			continue
		var i := ANIM_KEYS.find(String(k))
		out.append(i if i >= 0 else String(k))
		out.append(v)
	return out


static func unpack_anim(packed: Array, defaults: Dictionary) -> Dictionary:
	var out := defaults.duplicate()
	for i in range(0, packed.size(), 2):
		var k: Variant = packed[i]
		out[ANIM_KEYS[k] if k is int else k] = packed[i + 1]
	return out


# 展開的格式（E_*）
static func entity_fields(e: Entity) -> Array:
	var a := [e.id, e.kind, e.pos.x, e.pos.y, e.height, e.facing, e.hp, e.max_hp,
		e.velocity.x, e.velocity.y, e.flash_timer, e.invuln_timer, e.is_dead, {}, []]
	if e is Player:
		var p := e as Player
		a[E_ANIM] = p.anim
		a[E_EXTRA] = [p.peer_id, p.weapon_id, p.roll_charges, p.is_downed, p.down_timer, p.revive_progress, p.parry_timer, p.dodge_timer]
	elif e is Enemy:
		a[E_ANIM] = (e as Enemy).anim
		a[E_EXTRA] = [(e as Boss).is_enraged if e is Boss else false]
	elif e is Projectile:
		var pr := e as Projectile
		a[E_EXTRA] = [pr.visual, pr.color, pr.radius, pr.team]
	else:
		a[E_EXTRA] = [e.team, e.radius]
	return a


static func is_player_of(a: Array, peer_id: int) -> bool:
	return a[E_KIND] == &"player" and a[E_EXTRA][P_PEER] == peer_id


static func find_player(snap: Array, peer_id: int) -> Array:
	for a: Array in snap[S_ENTITIES]:
		if is_player_of(a, peer_id):
			return a
	return []


# 依快照建立鏡像實體（類別與房主相同，畫面層才能照常讀欄位）
static func create_entity(world: World, a: Array) -> Entity:
	var kind: StringName = a[E_KIND]
	var at := Vector2(a[E_X], a[E_Z])
	var extra: Array = a[E_EXTRA]
	var e: Entity
	if kind == &"player":
		e = Player.new(world, extra[P_PEER])
		e.pos = at
		world.add_entity_with_id(e, a[E_ID])
	elif kind in ENEMY_KINDS:
		var enemy := Spawner.create(world, kind, at, WaveDefs.NO_SCALING)
		enemy.stats.remove_source(&"wave")   # 最大生命直接用快照的數字
		world.add_enemy(enemy, a[E_ID])
		e = enemy
	elif kind == &"projectile":
		var owner := Entity.new(world, &"owner", extra[3], 0.1, 1.0)
		var pr := Projectile.new(world, {
			"owner": owner, "pos": at, "direction": MathUtil.dir_from_angle(a[E_FACING]), "speed": 0.0, "range": 0.0,
			"radius": extra[2], "color": extra[1], "visual": extra[0], "altitude": a[E_H],
		})
		owner.detach()
		world.add_entity_with_id(pr, a[E_ID])
		world.projectiles.append(pr)
		e = pr
	else:
		e = Entity.new(world, kind, extra[0], extra[1], a[E_MAX_HP])
		e.pos = at
		world.add_entity_with_id(e, a[E_ID])
		if extra[0] == &"enemy":
			world.enemies.append(e)
	apply_entity(e, a, [], 0.0)
	e.prev_pos = e.pos
	e.prev_facing = e.facing
	e.prev_height = e.height
	return e


# 其他實體：位置在快照 a 與下一筆 b 之間補間（t = 0~1）；b 為空時用 a，再沿 a 的速度往前推 ahead 秒（快照掉包時），其餘狀態用 a
static func apply_entity(e: Entity, a: Array, b: Array, t: float, ahead: float = 0.0) -> void:
	var p := Vector2(a[E_X], a[E_Z])
	var h: float = a[E_H]
	var f: float = a[E_FACING]
	if b.is_empty():
		p += Vector2(a[E_VX], a[E_VZ]) * ahead
	elif t > 0.0:
		p = p.lerp(Vector2(b[E_X], b[E_Z]), t)
		h = lerpf(h, b[E_H], t)
		f = lerp_angle(f, b[E_FACING], t)
	e.pos = p
	e.height = h
	e.facing = f
	e.velocity = Vector2(a[E_VX], a[E_VZ])
	e.flash_timer = a[E_FLASH]
	e.invuln_timer = a[E_INVULN]
	e.is_dead = a[E_DEAD]
	apply_life(e, a)
	var anim := lerp_anim(a[E_ANIM], b[E_ANIM] if not b.is_empty() else {}, t)
	var extra: Array = a[E_EXTRA]
	if e is Player:
		var pl := e as Player
		pl.anim = anim
		if pl.weapon_id != extra[P_WEAPON]:
			pl.equip_weapon(extra[P_WEAPON])
		pl.roll_charges = extra[P_ROLLS]
		pl.is_downed = extra[P_DOWNED]
		pl.down_timer = extra[P_DOWN_TIMER]
		pl.revive_progress = extra[P_REVIVE]
		pl.parry_timer = extra[P_PARRY]
		pl.dodge_timer = extra[P_DODGE]
	elif e is Enemy:
		var en := e as Enemy
		en.anim = anim
		# 鏡像敵人不跑狀態機，只同步名稱與時間給 HUD（Boss 血條出現時機）
		en.fsm.current_name = anim.get("state", &"")
		en.fsm.time = anim.get("time", 0.0)
		if en is Boss:
			(en as Boss).is_enraged = extra[0]


# 血量與最大生命（客戶端自己的角色也用這個：血量一律以房主為準）
static func apply_life(e: Entity, a: Array) -> void:
	var max_hp: float = a[E_MAX_HP]
	if absf(e.max_hp - max_hp) > 1e-3:
		e.stats.set_base(&"max_hp", max_hp)
	e.hp = a[E_HP]


# 動畫資料補間：兩筆的非數值欄位（狀態、階段…）都相同時，數值欄位（k、經過秒數）線性補間；否則用 a
static func lerp_anim(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	if b.is_empty() or t <= 0.0:
		return a
	for k: Variant in a:
		if typeof(a[k]) != TYPE_FLOAT and (not b.has(k) or b[k] != a[k]):
			return a
	var out := a.duplicate()
	for k: Variant in a:
		if typeof(a[k]) == TYPE_FLOAT and typeof(b.get(k)) == TYPE_FLOAT:
			out[k] = lerpf(a[k], b[k], t)
	return out


# 世界層級的狀態（波次、擊殺、時間、通關 / 全滅、Boss）
static func apply_world(world: World, snap: Array) -> void:
	var w: Array = snap[S_WORLD]
	world.stats.wave = w[W_WAVE]
	world.stats.kills = w[W_KILLS]
	world.stats.time = w[W_TIME]
	world.is_over = w[W_OVER]
	world.boss_id = w[W_BOSS]
	world.is_defeated = w[W_DEFEATED]
