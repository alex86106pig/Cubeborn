# 武器行為：由玩家的 attack / special 狀態在 windup → active → recovery 各階段呼叫（照搬網頁版 weaponBehaviors.js）
# 介面：enter(p, def, data) / phase(p, def, data, name) / update(p, def, data, name, k, dt) / exit(p, def, data)
# k 為目前階段的進度 0~1；data 是本次出手的暫存資料（data.lock_facing 可鎖定轉向）
# 模擬層只做命中、位移、投射物；姿勢由畫面層 view/animator.gd 依 player.anim 計算（PROJECT_GUIDELINES.md 第 11 節）
class_name WeaponBehaviors


class Behavior:
	func enter(_p: Player, _def: Dictionary, _data: Dictionary) -> void:
		pass

	func phase(_p: Player, _def: Dictionary, _data: Dictionary, _name: StringName) -> void:
		pass

	func update(_p: Player, _def: Dictionary, _data: Dictionary, _name: StringName, _k: float, _dt: float) -> void:
		pass

	func exit(_p: Player, _def: Dictionary, _data: Dictionary) -> void:
		pass


static func forward(p: Player) -> Vector2:
	return MathUtil.dir_from_angle(p.facing)


# 招式沒發動（影步沒有怪、鏟子沒抓到）：扣掉的魔力只留 miss_mana，其他退回
static func refund_miss(p: Player, def: Dictionary, data: Dictionary) -> void:
	var keep: float = def.get("miss_mana", 0.0) * p.stats.value(&"mana_cost")
	p.gain_mana(maxf(0.0, data.get("mana_spent", 0.0) - keep))


# 瞄準點太靠近（0.5 單位內）時沿用目前朝向
static func aim_direction(p: Player) -> Vector2:
	var v := p.aim_point - p.pos
	if v.length_squared() < 0.25:
		return forward(p)
	return v.normalized()


# 玩家投射物從胸口高度發射；在空中發射時，飛出 bolt_settle_distance 內降回離地 bolt_altitude（才打得到地上的怪）
# 一般投射物（魔彈、箭）的參數：往 dir 射出，傷害、擊退、外觀照招式資料（visual 預設光球）
static func shot_params(p: Player, def: Dictionary, dir: Vector2) -> Dictionary:
	return {
		"pos": p.pos + dir * def.spawn_offset, "direction": dir, "speed": def.projectile_speed,
		"range": def.range * p.weapon_range_mul(), "radius": def.projectile_radius, "damage": p.move_damage(def),
		"damage_type": p.weapon.damage_type, "knockback": def.knockback, "color": def.color, "hit_stop": def.hit_stop, "shake": def.shake,
		"no_stagger": def.get("no_stagger", false), "visual": def.get("visual", &"orb"), "pierce_count": def.get("pierce_count", 0),
	}


static func spawn_projectile(p: Player, params: Dictionary) -> void:
	params["owner"] = p
	if not params.has("attack"):
		params["attack"] = p.attack_tag()   # 飛到才打中：出手時記下是普攻還是右鍵（觸發袋分左右）
	params["altitude"] = p.height + Config.HEIGHT.bolt_altitude
	params["settle_altitude"] = Config.HEIGHT.bolt_altitude
	params["settle_distance"] = Config.HEIGHT.bolt_settle_distance
	p.world.spawn_projectile(Projectile.new(p.world, params))


class MeleeSwing extends Behavior:
	func enter(p: Player, def: Dictionary, data: Dictionary) -> void:
		var count: int = def.get("combo_count", 3)   # 雙匕首五連刺（F6）；劍盾三段
		p.combo_step = (p.combo_step + 1) % count if p.combo_timer > 0.0 else 0
		data.is_finisher = p.combo_step == count - 1
		data.swing_dir = -1 if p.combo_step % 2 == 1 else 1   # 偶數段反手
		data.scale = def.finisher_scale if data.is_finisher else 1.0
		data.hit = {}
		if data.is_finisher:
			data.durations[0] = def.get("finisher_windup", def.windup)
			data.durations[2] = def.get("finisher_recovery", def.recovery * def.finisher_recovery_mul)
		elif p.combo_step in def.get("beat_steps", []):
			data.durations[2] += def.beat_pause   # 節奏的停頓（雙匕首第 2、4 刺後）

	func phase(p: Player, def: Dictionary, data: Dictionary, name: StringName) -> void:
		if name == &"active":
			data.lock_facing = true
			p.knockback += WeaponBehaviors.forward(p) * (def.lunge * data.scale)
			var shape: Array = def.get("slash_shape", [])
			var look: Array = shape[p.combo_step] if p.combo_step < shape.size() else [0.0, 0.0, 1.0]
			p.world.emit_event("fx:slash", {
				"pos": p.pos, "height": p.height, "facing": p.facing, "range": def.range * data.scale * p.weapon_range_mul(),
				"arc": def.arc * data.scale * look[2], "color": def.slash_finisher_color if data.is_finisher else def.slash_color,
				"swing_dir": data.swing_dir, "tilt": look[0], "pitch": look[1],
			})
		elif name == &"recovery":
			data.lock_facing = false

	func update(p: Player, def: Dictionary, data: Dictionary, name: StringName, _k: float, _dt: float) -> void:
		if name != &"active":
			return
		var fin: bool = data.is_finisher
		var shape := {"shape": &"sector", "range": def.range * data.scale * p.weapon_range_mul(), "arc": def.arc * data.scale}
		var hits := Hitbox.strike(p.world, p, p.pos, p.facing, shape, {
			"damage": p.move_damage(def) * (def.finisher_mul if fin else 1.0), "damage_type": p.weapon.damage_type,
			"knockback": def.get("finisher_knockback", def.knockback * def.finisher_impact_mul) if fin else def.knockback,
			"hit_stop": def.hit_stop * (def.finisher_impact_mul if fin else 1.0),
			"shake": def.shake * (def.finisher_shake_mul if fin else 1.0),
			"is_heavy": fin, "finisher": fin, "blockable": true, "force_crit": fin and def.get("finisher_crit", false),
			"no_stagger": not fin and def.get("finisher_only_stagger", false),   # 雙匕首前 4 下不讓怪硬直
		}, data.hit)
		WeaponBehaviors.ignite(p, def, hits)
		if fin and def.has("finisher_burst"):
			# 終結技在前方砸出一圈（驅魔權杖第 2 下）：和扇形分開算，同一隻兩邊都打得到
			var fb: Dictionary = def.finisher_burst
			var at: Vector2 = p.pos + WeaponBehaviors.forward(p) * fb.offset
			if not data.has("burst_hit"):
				data.burst_hit = {}
				p.world.emit_event("fx:explosion", {"pos": at, "height": p.world.terrain.ground_at(at), "radius": fb.radius, "color": fb.color})
			Hitbox.strike(p.world, p, at, p.facing, {"shape": &"circle", "radius": fb.radius}, {
				"damage": p.pct_damage(fb.damage_pct), "damage_type": p.weapon.damage_type, "knockback": fb.knockback,
				"origin": at, "is_heavy": true, "blockable": false, "color": fb.color,
			}, data.burst_hit)

	func exit(p: Player, def: Dictionary, _data: Dictionary) -> void:
		p.combo_timer = def.combo_window


# 盾擊（許家慶 2026-11-06，取代按住格擋 + 左鍵招架）：按一下往前推盾，active 一開始打出盾擊（damage_pct）；
# 從出手到 active 結束都在格擋（Player.try_block），這段期間（active = block_window × 招架判定時間）擋下的第一下 = 盾反（下一步全額盾反）
class ShieldBash extends Behavior:
	func enter(p: Player, def: Dictionary, data: Dictionary) -> void:
		data.durations[1] = def.block_window * p.stats.value(&"parry_window")   # 招架判定時間（stat）拉長推盾的格擋時間
		p.block_time = 0.0
		p.parry_time = 0.0

	func phase(p: Player, def: Dictionary, data: Dictionary, name: StringName) -> void:
		if name == &"active":
			data.lock_facing = true
			p.world.emit_event("fx:slash", {"pos": p.pos, "height": p.height, "facing": p.facing, "range": def.range, "arc": def.arc,
				"color": def.parry.color, "swing_dir": 1})
			Hitbox.strike(p.world, p, p.pos, p.facing, {"shape": &"sector", "range": def.range, "arc": def.arc}, {
				"damage": p.move_damage(def), "damage_type": p.weapon.damage_type, "knockback": def.knockback,
				"hit_stop": def.hit_stop, "shake": def.shake, "blockable": true, "color": def.parry.color,
			})
		elif name == &"recovery":
			p.block_time = -1.0
			p.parry_time = -1.0

	func update(p: Player, _def: Dictionary, _data: Dictionary, name: StringName, _k: float, dt: float) -> void:
		if name != &"recovery":
			p.block_time += dt

	func exit(p: Player, _def: Dictionary, _data: Dictionary) -> void:
		p.block_time = -1.0
		p.parry_time = -1.0


class FireBolt extends Behavior:
	# 有箭袋的弓（短弓）：最後一支是重箭，多拉弓 heavy_last.extra_windup 秒
	func enter(p: Player, def: Dictionary, data: Dictionary) -> void:
		data.heavy = def.has("quiver") and p.quiver == 1
		if data.heavy:
			data.durations[0] += def.heavy_last.extra_windup
			data.is_finisher = true

	func phase(p: Player, def: Dictionary, data: Dictionary, name: StringName) -> void:
		if name != &"active":
			return
		var dir := WeaponBehaviors.aim_direction(p)
		p.facing = atan2(dir.x, dir.y)
		var params := WeaponBehaviors.shot_params(p, def, dir)
		if data.get("heavy", false):
			var hv: Dictionary = def.heavy_last
			params.damage = p.pct_damage(hv.damage_pct)
			params.knockback = hv.knockback
			params.no_stagger = false
			params.color = hv.color
		WeaponBehaviors.spawn_projectile(p, params)
		if def.has("quiver"):
			p.use_arrow(def)
		p.world.emit_event("fx:muzzle", {"pos": p.pos + dir * def.spawn_offset, "height": p.height + Config.HEIGHT.bolt_altitude, "color": def.color})


class ArcaneBurst extends Behavior:
	func enter(p: Player, def: Dictionary, data: Dictionary) -> void:
		var v := p.aim_point - p.pos
		var dist := clampf(v.length(), def.min_range, def.range)
		data.dir = v.normalized() if v.length_squared() > 0.01 else WeaponBehaviors.forward(p)
		data.dist = dist
		data.target = p.pos + data.dir * dist
		data.lock_facing = true
		p.facing = atan2(data.dir.x, data.dir.y)

	func phase(p: Player, def: Dictionary, data: Dictionary, name: StringName) -> void:
		if name != &"active":
			return
		WeaponBehaviors.spawn_projectile(p, {
			"pos": p.pos + data.dir * def.spawn_offset, "direction": data.dir, "speed": def.projectile_speed,
			"range": data.dist - def.spawn_offset, "radius": def.projectile_radius, "damage": 0.0, "damage_type": p.weapon.damage_type,
			"color": def.color,
			"explosion": {
				"radius": def.explosion_radius, "damage": p.move_damage(def), "knockback": def.knockback,
				"hit_stop": def.hit_stop, "shake": def.shake,
			},
		})


# 扇形散射（F4 短弓右鍵）：朝瞄準方向一次射出 count 支，平均分布在 fan_arc 內
class ArrowFan extends Behavior:
	func phase(p: Player, def: Dictionary, _data: Dictionary, name: StringName) -> void:
		if name != &"active":
			return
		var dir := WeaponBehaviors.aim_direction(p)
		var base := atan2(dir.x, dir.y)
		p.facing = base
		var n: int = def.count
		for i in n:
			var a: float = base + (def.fan_arc * (float(i) / (n - 1) - 0.5) if n > 1 else 0.0)
			WeaponBehaviors.spawn_projectile(p, WeaponBehaviors.shot_params(p, def, MathUtil.dir_from_angle(a)))
		p.world.emit_event("fx:muzzle", {"pos": p.pos + dir * def.spawn_offset, "height": p.height + Config.HEIGHT.bolt_altitude, "color": def.color})


# 蓄力穿透箭（F5 長弓右鍵）：按住蓄力（hold，停在 active），放開進收招時射出；
# 傷害 = damage_pct → full_damage_pct 依蓄力秒數 / charge_time 線性變化，箭穿透一直線上所有敵人
class ChargedShot extends Behavior:
	func enter(_p: Player, _def: Dictionary, data: Dictionary) -> void:
		data.charge = 0.0

	func update(p: Player, def: Dictionary, data: Dictionary, name: StringName, _k: float, dt: float) -> void:
		if name == &"active":
			data.charge = minf(data.charge + dt, def.charge_time)
			var dir := WeaponBehaviors.aim_direction(p)
			p.facing = atan2(dir.x, dir.y)

	func phase(p: Player, def: Dictionary, data: Dictionary, name: StringName) -> void:
		if name != &"recovery":
			return
		var dir := WeaponBehaviors.aim_direction(p)
		p.facing = atan2(dir.x, dir.y)
		var params := WeaponBehaviors.shot_params(p, def, dir)
		var ratio: float = data.charge / def.charge_time
		params.damage = p.move_damage(def) * lerpf(1.0, def.full_damage_pct / def.damage_pct, ratio)
		params.pierce = true
		WeaponBehaviors.spawn_projectile(p, params)
		p.world.emit_event("sfx:cue", {"cue": def.sfx_release, "pos": p.pos})
		p.world.emit_event("fx:muzzle", {"pos": p.pos + dir * def.spawn_offset, "height": p.height + Config.HEIGHT.bolt_altitude, "color": def.color})


# 影步（F6 雙匕首右鍵）：瞬移到 range 內離準星最近那隻怪的背後（背後是牆就繞著怪找空位），背刺一下必爆擊；
# 沒有怪就不瞬移，只扣 miss_mana
class ShadowStep extends Behavior:
	func enter(p: Player, def: Dictionary, data: Dictionary) -> void:
		data.lock_facing = true
		data.target_id = 0
		var best := INF
		for e in Combat.hostiles_of(p.world, p.team, p.id):
			if e.team == p.team or e.pos.distance_to(p.pos) > def.range + e.radius:   # 誤傷的隊友不當目標；冤魂與玩家互相可以
				continue
			var d := e.pos.distance_squared_to(p.aim_point)
			if d < best:
				best = d
				data.target_id = e.id
		if data.target_id == 0:
			WeaponBehaviors.refund_miss(p, def, data)

	func phase(p: Player, def: Dictionary, data: Dictionary, name: StringName) -> void:
		var target: Entity = p.world.entities.get(data.target_id)
		if name != &"active" or target == null or target.is_dead:
			return
		var spot := WeaponBehaviors.behind(p, target)
		p.pos = spot
		p.facing = MathUtil.angle_to(spot, target.pos)
		p.world.emit_event("fx:slash", {"pos": p.pos, "height": p.height, "facing": p.facing, "range": 1.6, "arc": PI * 0.5, "color": def.color, "swing_dir": 1})
		Combat.apply_damage(p.world, p, target, {
			"damage": p.move_damage(def), "damage_type": p.weapon.damage_type, "knockback": def.knockback,
			"hit_stop": def.hit_stop, "shake": def.shake, "is_heavy": true, "force_crit": true, "color": def.color,
		})


# 聖光圈（F7 驅魔權杖右鍵）：在腳下放 duration 秒的聖光圈（GroundZones），隊友每秒回血、敵人每秒受到 damage_pct（持續傷害）
class HolyCircle extends Behavior:
	func phase(p: Player, def: Dictionary, _data: Dictionary, name: StringName) -> void:
		if name != &"active":
			return
		GroundZones.add(p.world, {
			"pos": p.pos, "radius": def.radius, "duration": def.duration, "owner_id": p.id, "color": def.color,
			"heal_per_sec": def.heal_per_sec, "damage_per_sec": p.move_damage(def), "damage_type": p.weapon.damage_type, "credit": "s",
		})


# 點燃（F8 火把）：招式有 burn 時，打中的怪每秒受到 burn.pct_per_sec 的持續傷害 burn.duration 秒（不觸發道具）
static func ignite(p: Player, def: Dictionary, hits: Array[Entity]) -> void:
	if not def.has("burn"):
		return
	for t in hits:
		if t is Enemy:
			(t as Enemy).apply_burn(p.id, p.pct_damage(def.burn.pct_per_sec), def.burn.duration)


# 噴火（F8 火把右鍵；許家慶 2026-11-06 拿掉準備姿態，按右鍵直接噴）：前方扇形大範圍傷害 + 點燃
class FireBreath extends Behavior:
	func phase(p: Player, def: Dictionary, data: Dictionary, name: StringName) -> void:
		if name == &"windup":
			data.lock_facing = false
		elif name == &"active":
			data.lock_facing = true
			data.hit = {}
			p.world.emit_event("fx:slash", {"pos": p.pos, "height": p.height, "facing": p.facing, "range": def.range, "arc": def.arc, "color": def.color, "swing_dir": 1})

	func update(p: Player, def: Dictionary, data: Dictionary, name: StringName, _k: float, _dt: float) -> void:
		if name != &"active":
			return
		var hits := Hitbox.strike(p.world, p, p.pos, p.facing, {"shape": &"sector", "range": def.range, "arc": def.arc}, {
			"damage": p.move_damage(def), "damage_type": p.weapon.damage_type, "knockback": def.knockback,
			"hit_stop": def.hit_stop, "shake": def.shake, "color": def.color, "blockable": false,
		}, data.hit)
		WeaponBehaviors.ignite(p, def, hits)


# 鏟拋（F9 鐵鏟右鍵；許家慶 2026-11-06 取代「鏟起舉 2 秒、再選拋出 / 埋入」）：鏟起面前 reach 內最近的一隻非 Boss 敵人
# （誤傷開著時也可以是隊友），直接往準星丟 distance（撞牆就停在牆前），花 flight_time 秒沿拋物線飛過去（Enemy.throw_to）；
# 路上撞到的怪受 path_damage_pct、被丟的怪落地受 damage_pct，都可擊退，都算右鍵打中。冰凍中的怪狀態機停住飛不動，直接落在落點
# 丟隊友不扣血、路上不撞怪：往落點推過去並跳起來（當位移工具）。沒抓到只扣 miss_mana
class ShovelFling extends Behavior:
	func phase(p: Player, def: Dictionary, data: Dictionary, name: StringName) -> void:
		if name != &"active":
			return
		var target := WeaponBehaviors.scoop_target(p, def.reach)
		if target == null:
			WeaponBehaviors.refund_miss(p, def, data)
			return
		var dir := WeaponBehaviors.aim_direction(p)
		p.facing = atan2(dir.x, dir.y)
		var start := target.pos
		var land := start
		var step := 0.5
		var travel := 0.0
		while travel + step <= def.distance:
			var nxt := start + dir * (travel + step)
			if p.world.terrain.blocks_nav(nxt, target.radius) or absf(nxt.x) > p.world.half_extents.x - target.radius or absf(nxt.y) > p.world.half_extents.y - target.radius:
				break
			travel += step
			land = nxt
		if target is Player:
			SkillBehaviors.push(target as Player, land - start)
			(target as Player).knock_up(Entity.gravity() * def.flight_time / 2.0)
			return
		var held := target as Enemy
		var path_hit := {"damage": p.pct_damage(def.path_damage_pct), "damage_type": p.weapon.damage_type, "attack": &"secondary",
			"knockback": def.knockback, "is_heavy": true, "color": def.color}
		var land_hit := {"damage": p.move_damage(def), "damage_type": p.weapon.damage_type, "attack": &"secondary",
			"knockback": def.knockback, "hit_stop": def.hit_stop, "shake": def.shake, "is_heavy": true, "color": def.color}
		if held.frozen_timer > 0.0 or travel <= 0.0:
			held.pos = land
			held.prev_pos = land
			Enemy.land_throw(held, p, land_hit, dir)
			return
		held.throw_to(land, def.flight_time, p, dir, def.path_width, path_hit, land_hit)


# 鏟得起來的目標：面前（朝向 ±72° 內）reach 內最近的一隻非 Boss 敵人，誤傷開著時也可以是隊友（鏟拋、活埋共用）
static func scoop_target(p: Player, reach: float) -> Entity:
	var candidates: Array[Entity] = []
	for e in p.world.enemies:
		var en := e as Enemy
		if en != null and not en.is_dead and en.team != p.team and not en.is_boss() and en.buried_timer <= 0.0 and not en.is_launching():
			candidates.append(en)
	if p.world.friendly_fire:
		for mate in p.world.player_list:
			if mate != p and mate.is_targetable() and mate.stun_timer <= 0.0:
				candidates.append(mate)
	var best: Entity = null
	var best_d := INF
	for e in candidates:
		var d := e.pos.distance_to(p.pos) - e.radius - p.radius
		var ahead := WeaponBehaviors.forward(p).dot((e.pos - p.pos).normalized()) > 0.3
		if d <= reach and ahead and d < best_d:
			best_d = d
			best = e
	return best


# 目標背後（和它面向相反）貼身的位置；被牆擋住就每 45° 繞一圈找第一個站得住的地方，都不行就留在原地
static func behind(p: Player, target: Entity) -> Vector2:
	var dist := target.radius + p.radius + 0.15
	var base := target.facing + PI
	for i in 8:
		var a := base + PI / 4.0 * ceilf(i / 2.0) * (1.0 if i % 2 == 0 else -1.0)
		var spot := target.pos + MathUtil.dir_from_angle(a) * dist
		var half := p.world.half_extents - Vector2(p.radius, p.radius)
		if absf(spot.x) > half.x or absf(spot.y) > half.y:
			continue
		if p.world.terrain.ground_at(spot) - target.ground_height <= Config.HEIGHT.step and not p.world.terrain.blocks_nav(spot, p.radius):
			return spot
	return p.pos


static var BEHAVIORS := {
	&"meleeSwing": MeleeSwing.new(),
	&"shieldBash": ShieldBash.new(),
	&"fireBolt": FireBolt.new(),
	&"arcaneBurst": ArcaneBurst.new(),
	&"arrowFan": ArrowFan.new(),
	&"chargedShot": ChargedShot.new(),
	&"shadowStep": ShadowStep.new(),
	&"holyCircle": HolyCircle.new(),
	&"fireBreath": FireBreath.new(),
	&"shovelFling": ShovelFling.new(),
}
