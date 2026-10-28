# 快照的編碼與套用（docs/系統說明.md §8）：房主把 World 打包成只含數值的陣列，客戶端把陣列套到鏡像 World 的實體上
# 實體欄位固定順序（E_*），各類別的額外欄位放在 E_EXTRA
# 網路上傳的是壓縮過的格式（encode_entity）：數值欄位放 PackedFloat32Array、動畫的欄位名稱換成 ANIM_KEYS 的索引；
# 客戶端收到時 decode_snapshot 展開成 E_* 的格式再使用
class_name NetCodec

enum { S_RUN, S_TICK, S_ACK, S_WORLD, S_ENTITIES }
enum { W_WAVE, W_KILLS, W_TIME, W_OVER, W_BOSS, W_DEFEATED, W_SOULS, W_FLOOR, W_EVENT, W_COINS }
enum { E_ID, E_KIND, E_X, E_Z, E_H, E_FACING, E_HP, E_MAX_HP, E_VX, E_VZ, E_FLASH, E_INVULN, E_DEAD, E_ANIM, E_EXTRA }
# 玩家的 E_EXTRA
enum { P_PEER, P_WEAPON, P_ROLLS, P_DOWNED, P_DOWN_TIMER, P_REVIVE, P_PARRY, P_DODGE, P_INV, P_SLOTS, P_ACTIVE, P_STUN, P_DESCENDED, P_QUIVER, P_RELOAD }
# 寶箱的 E_EXTRA：[tier, opened]；地上道具：[item_id, 武器（WeaponDropDefs.to_array，不是武器為 []）, 屍體的主人 peer id]（D3 / D4 / D6）

const ENEMY_KINDS: Array[StringName] = [&"grunt", &"archer", &"boss", &"ghost", &"minion", &"zombie", &"bloater"]
# 動畫欄位名稱 → 索引（Player._update_anim、Enemy._update_anim、Boss._anim_extra）；不在表裡的照樣用字串送
const ANIM_KEYS: Array[String] = [
	"loco", "loco_time", "action", "action_time", "behavior", "phase", "k", "swing_dir", "is_finisher",
	"trail_color", "airborne", "blocking", "parry", "vz", "revive", "stunned",
	"state", "time", "enraged", "phase_time", "origin", "torch_stance", "burning", "holding", "buried", "grabbed",
	"shield", "running", "burst",
]
# 玩家動畫欄位的預設值：和預設值相同的欄位不送（大部分時間只剩移動層、動作層的名稱與秒數），收到時補回
const PLAYER_ANIM_DEFAULTS := {
	"behavior": &"", "phase": &"", "k": 0.0, "swing_dir": 1, "is_finisher": false, "trail_color": null,
	"airborne": false, "blocking": false, "parry": 0.0, "vz": 0.0, "revive": 0.0, "stunned": false, "grabbed": false, "torch_stance": false, "holding": false,
	"shield": 0.0, "running": false,
}
# 數值欄位 E_X ~ E_MAX_HP 用 float32；E_VX ~ E_INVULN 只給別人的實體外推與閃白，用 half（16 位元）
# 二進位格式（v0.35.0）用的種類與常見名稱表：在表裡的送 1 byte 索引，不在表裡的照樣送字串（表只影響大小、不影響正確性）
const KINDS: Array[StringName] = [&"player", &"grunt", &"archer", &"boss", &"ghost", &"chest", &"pickup", &"projectile", &"coin", &"torch", &"minion", &"zombie", &"bloater"]
const NAMES: Array[StringName] = [
	&"idle", &"move", &"chase", &"kite", &"aim", &"attack", &"swing", &"cleave", &"slam", &"charge", &"rush", &"summon",
	&"hurt", &"stagger", &"dead", &"dormant", &"spawn", &"climb", &"jump", &"stun", &"ready", &"special", &"roll", &"dig",
	&"downed", &"revive", &"windup", &"strike", &"recover", &"block", &"parry", &"lunge", &"bite", &"dash", &"recovery", &"swell",
]
enum { T_NULL, T_FALSE, T_TRUE, T_INT, T_FLOAT, T_NAME, T_SNAME, T_STRING, T_COLOR, T_VEC2, T_VARIANT }
const NO_INDEX := 255
const NORMAL_ENEMY_EXTRA := [false]   # 普通怪（非 Boss、沒有稀有度）的 extra：網路上不送
# 實體旗標（encode_entity）：F_DEAD 已死；F_EXTRA 有 extra；其餘表示該欄位是預設值、整個不送
const F_DEAD := 1
const F_EXTRA := 2
const F_FULL_HP := 4
const F_STILL := 8
const F_NO_TIMERS := 16
const F_GROUND0 := 32


# 每個實體只編一次：[位元組（id、種類、數值、旗標、動畫）, extra（普通怪為 null）, 實體]；房主再依玩家挑選（NetHost.snapshots）
static func encode_entities(world: World) -> Array:
	var out := []
	for e: Entity in world.entities.values():
		if not e.is_removed:
			out.append(encode_entity(e))
	return out


# entities：encode_entities 的紀錄（可以只挑一部分）；peer_id：收件人（別人的背包不送；0 = 全送）
# 網路格式：[run, tick, ack, world, 所有實體接在一起的 PackedByteArray, 有 extra 的實體的 extra（照順序）]；收到後 decode_snapshot 展開成 E_* 陣列
static func make_snapshot(world: World, entities: Array, ack: int, peer_id: int = 0) -> Array:
	var s := world.stats
	var bytes := PackedByteArray()
	var extras := []
	for rec: Array in entities:
		bytes.append_array(rec[0])
		var extra: Variant = rec[1]
		if extra == null:
			continue
		if peer_id != 0 and rec[2] is Player and (rec[2] as Player).peer_id != peer_id:
			extra = (extra as Array).duplicate()
			extra[P_INV] = []   # 別人的背包客戶端用不到（只有自己的背包面板要看）
		extras.append(extra)
	return [world.run_id, world.tick, ack, [s.wave, s.kills, s.time, world.is_over, world.boss_id, world.is_defeated, world.souls,
		world.floor_num, [world.event.state, world.event.progress, world.event.time, world.base_difficulty, world.event.horde,
		world.event.vote_by, world.event.vote_left, world.event.vote_yes.duplicate()], world.run_coins], bytes, extras]


# 單一實體的網路紀錄：[位元組, extra（普通怪為 null）, 實體]
# 位元組：id（u32）、種類（u8，不在表裡再接字串）、旗標（u8）、x、z、[高度]、朝向、最大生命、[生命]、[速度 x2（half）]、[閃白、無敵（half）]、動畫
# 旗標標示的欄位等於預設值時整個不送（無損）：滿血、靜止、計時器都是 0、高度 0；大部分的怪每隻約 40 bytes
static func encode_entity(e: Entity) -> Array:
	var a := entity_fields(e)
	var extra: Variant = a[E_EXTRA]
	if extra == NORMAL_ENEMY_EXTRA:
		extra = null
	var flags := 0
	if a[E_DEAD]:
		flags |= F_DEAD
	if extra != null:
		flags |= F_EXTRA
	if a[E_HP] == a[E_MAX_HP]:
		flags |= F_FULL_HP
	if a[E_VX] == 0.0 and a[E_VZ] == 0.0:
		flags |= F_STILL
	if a[E_FLASH] == 0.0 and a[E_INVULN] == 0.0:
		flags |= F_NO_TIMERS
	if a[E_H] == 0.0:
		flags |= F_GROUND0
	var b := StreamPeerBuffer.new()
	b.put_u32(a[E_ID])
	var ki := KINDS.find(a[E_KIND])
	b.put_u8(ki if ki >= 0 else NO_INDEX)
	if ki < 0:
		b.put_utf8_string(String(a[E_KIND]))
	b.put_u8(flags)
	b.put_float(a[E_X])
	b.put_float(a[E_Z])
	if not flags & F_GROUND0:
		b.put_float(a[E_H])
	b.put_float(a[E_FACING])
	b.put_float(a[E_MAX_HP])
	if not flags & F_FULL_HP:
		b.put_float(a[E_HP])
	if not flags & F_STILL:
		b.put_half(a[E_VX])
		b.put_half(a[E_VZ])
	if not flags & F_NO_TIMERS:
		b.put_half(a[E_FLASH])
		b.put_half(a[E_INVULN])
	var pairs := pack_anim(a[E_ANIM], PLAYER_ANIM_DEFAULTS if a[E_KIND] == &"player" else {})
	b.put_u8(pairs.size() / 2)
	for i in range(0, pairs.size(), 2):
		if pairs[i] is int:
			b.put_u8(pairs[i])
		else:
			b.put_u8(NO_INDEX)
			b.put_utf8_string(pairs[i])
		_put_value(b, pairs[i + 1])
	return [b.data_array, extra, e]


# 單一實體：encode_entity 的紀錄 → E_* 陣列
static func decode_entity(rec: Array) -> Array:
	var b := StreamPeerBuffer.new()
	b.data_array = rec[0]
	return _read_entity(b, [rec[1]])


# 收到的快照展開成 E_* 格式（原地修改並回傳）
static func decode_snapshot(snap: Array) -> Array:
	if not snap[S_ENTITIES] is PackedByteArray:
		return snap   # 已經展開過
	var b := StreamPeerBuffer.new()
	b.data_array = snap[S_ENTITIES]
	var extras: Array = (snap[S_ENTITIES + 1] as Array).duplicate()
	extras.reverse()   # 從尾端取（pop_back）比較快
	var list := []
	while b.get_position() < b.get_size():
		list.append(_read_entity(b, extras))
	snap.resize(S_ENTITIES + 1)
	snap[S_ENTITIES] = list
	return snap


# extras：還沒用掉的 extra（倒序，有 F_EXTRA 旗標的實體從尾端取一個）
static func _read_entity(b: StreamPeerBuffer, extras: Array) -> Array:
	var a := [b.get_u32()]
	var ki := b.get_u8()
	var kind: StringName = KINDS[ki] if ki != NO_INDEX else StringName(b.get_utf8_string())
	var flags := b.get_u8()
	var x := b.get_float()
	var z := b.get_float()
	var h := 0.0 if flags & F_GROUND0 else b.get_float()
	var facing := b.get_float()
	var max_hp := b.get_float()
	var hp := max_hp if flags & F_FULL_HP else b.get_float()
	var vx := 0.0
	var vz := 0.0
	if not flags & F_STILL:
		vx = b.get_half()
		vz = b.get_half()
	var flash := 0.0
	var invuln := 0.0
	if not flags & F_NO_TIMERS:
		flash = b.get_half()
		invuln = b.get_half()
	a.append_array([kind, x, z, h, facing, hp, max_hp, vx, vz, flash, invuln, flags & F_DEAD != 0])
	var pairs := []
	for i in b.get_u8():
		var k := b.get_u8()
		pairs.append(k if k != NO_INDEX else b.get_utf8_string())
		pairs.append(_get_value(b))
	a.append(unpack_anim(pairs, PLAYER_ANIM_DEFAULTS if kind == &"player" else {}))
	a.append(extras.pop_back() if flags & F_EXTRA else NORMAL_ENEMY_EXTRA.duplicate())
	return a


# 動畫欄位的值：型別一個 byte + 內容（浮點數用 double，補間與比對都和房主完全一樣）
static func _put_value(b: StreamPeerBuffer, v: Variant) -> void:
	match typeof(v):
		TYPE_NIL:
			b.put_u8(T_NULL)
		TYPE_BOOL:
			b.put_u8(T_TRUE if v else T_FALSE)
		TYPE_INT:
			b.put_u8(T_INT)
			b.put_64(v)
		TYPE_FLOAT:
			b.put_u8(T_FLOAT)
			b.put_double(v)
		TYPE_STRING_NAME:
			var i := NAMES.find(v)
			if i >= 0:
				b.put_u8(T_NAME)
				b.put_u8(i)
			else:
				b.put_u8(T_SNAME)
				b.put_utf8_string(String(v))
		TYPE_STRING:
			b.put_u8(T_STRING)
			b.put_utf8_string(v)
		TYPE_COLOR:
			b.put_u8(T_COLOR)
			for c: float in [v.r, v.g, v.b, v.a]:
				b.put_float(c)
		TYPE_VECTOR2:
			b.put_u8(T_VEC2)
			b.put_float(v.x)
			b.put_float(v.y)
		_:
			b.put_u8(T_VARIANT)
			b.put_var(v)


static func _get_value(b: StreamPeerBuffer) -> Variant:
	match b.get_u8():
		T_FALSE:
			return false
		T_TRUE:
			return true
		T_INT:
			return b.get_64()
		T_FLOAT:
			return b.get_double()
		T_NAME:
			return NAMES[b.get_u8()]
		T_SNAME:
			return StringName(b.get_utf8_string())
		T_STRING:
			return b.get_utf8_string()
		T_COLOR:
			return Color(b.get_float(), b.get_float(), b.get_float(), b.get_float())
		T_VEC2:
			return Vector2(b.get_float(), b.get_float())
		T_VARIANT:
			return b.get_var()
	return null


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
		a[E_EXTRA] = [p.peer_id, p.weapon_id, p.roll_charges, p.is_downed, p.down_timer, p.revive_progress, p.parry_timer, p.dodge_timer, p.inventory.to_array(),
			p.weapon_slots.map(WeaponDropDefs.to_array), p.active_slot, -p.stun_timer if p.grabbed_by != 0 else p.stun_timer, p.descended]
		if p.weapon.attack.has("quiver"):   # 箭袋（短弓）：拿著有箭袋的弓才送，快照才不會變大
			a[E_EXTRA].append_array([p.quiver, p.reload_timer])
	elif e is Chest:
		a[E_EXTRA] = [(e as Chest).tier, (e as Chest).opened]
	elif e is ItemPickup:
		a[E_EXTRA] = [(e as ItemPickup).item_id, WeaponDropDefs.to_array((e as ItemPickup).weapon), (e as ItemPickup).corpse_of]
	elif e is Coin or e is Torch:
		a[E_EXTRA] = []
	elif e is Enemy:
		a[E_ANIM] = (e as Enemy).anim
		var en := e as Enemy
		a[E_EXTRA] = [(e as Boss).is_enraged if e is Boss else false]
		if en.rarity != MonsterRarityDefs.NORMAL:   # 稀有度（D5）：普通怪不送
			a[E_EXTRA].append_array([en.rarity, en.affixes.map(func(id: StringName) -> String: return String(id)), en.rare_name])
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
		(e as Player).apply_class(world.player_classes.get(extra[P_PEER], ClassDefs.NONE))   # 開局時大廳給的職業（F3）
		e.pos = at
		world.add_entity_with_id(e, a[E_ID])
	elif kind in ENEMY_KINDS:
		var enemy := Spawner.create(world, kind, at, WaveDefs.NO_SCALING)
		enemy.stats.remove_source(&"wave")   # 最大生命直接用快照的數字
		if kind == &"minion":
			enemy.team = &"player"   # 骷髏僕從（G6）：客戶端的預測、頭頂血條顏色也要當成自己人
		if extra.size() > 1:   # 稀有度只要外觀（體型、光、名字），數值以快照為準
			enemy.set_rarity(StringName(extra[1]), (extra[2] as Array).map(func(id: String) -> StringName: return StringName(id)), extra[3])
		world.add_enemy(enemy, a[E_ID])
		e = enemy
	elif kind == &"chest":
		var chest := Chest.new(world, extra[0], at)
		world.add_entity_with_id(chest, a[E_ID])
		world.chests.append(chest)
		e = chest
	elif kind == &"pickup":
		var pickup := ItemPickup.new(world, extra[0], at, WeaponDropDefs.from_array(extra[1]))
		pickup.corpse_of = extra[2]
		world.add_entity_with_id(pickup, a[E_ID])
		world.pickups.append(pickup)
		e = pickup
	elif kind == &"coin":
		var coin := Coin.new(world, at)
		world.add_entity_with_id(coin, a[E_ID])
		world.coins.append(coin)
		e = coin
	elif kind == &"torch":
		var torch := Torch.new(world, at)
		world.add_entity_with_id(torch, a[E_ID])
		world.torches.append(torch)
		e = torch
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
		pl.show_weapon(extra[P_WEAPON])   # 別人的角色只需要招式資料與模型
		for i in pl.weapon_slots.size():   # 裝備欄只給畫面（武器稀有度的光），不套屬性
			pl.weapon_slots[i] = WeaponDropDefs.from_array(extra[P_SLOTS][i])
		pl.active_slot = extra[P_ACTIVE]
		pl.roll_charges = extra[P_ROLLS]
		pl.is_downed = extra[P_DOWNED]
		pl.down_timer = extra[P_DOWN_TIMER]
		pl.revive_progress = extra[P_REVIVE]
		pl.parry_timer = extra[P_PARRY]
		pl.dodge_timer = extra[P_DODGE]
		pl.descended = extra[P_DESCENDED]
	elif e is Enemy:
		var en := e as Enemy
		en.anim = anim
		# 鏡像敵人不跑狀態機，只同步名稱與時間給 HUD（Boss 血條出現時機）
		en.fsm.current_name = anim.get("state", &"")
		en.fsm.time = anim.get("time", 0.0)
		if en is Boss:
			(en as Boss).is_enraged = extra[0]
	elif e is Chest:
		(e as Chest).opened = extra[1]


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
	world.souls = w[W_SOULS]
	world.floor_num = w[W_FLOOR]
	var ev: Array = w[W_EVENT]
	world.event.state = ev[0]
	world.event.progress = ev[1]
	world.event.time = ev[2]
	world.base_difficulty = ev[3]
	world.event.horde = ev[4]
	world.event.vote_by = ev[5]
	world.event.vote_left = ev[6]
	world.event.vote_yes.assign(ev[7])
	world.run_coins = w[W_COINS]
