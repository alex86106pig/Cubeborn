# 武器行為：由玩家的 attack / special 狀態在 windup → active → recovery 各階段呼叫（照搬網頁版 weaponBehaviors.js）
# 介面：enter(p, def, data) / phase(p, def, data, name) / update(p, def, data, name, k, dt) / exit(p, def, data)
# k 為目前階段的進度 0~1；data 是本次出手的暫存資料（data.lock_facing 可鎖定轉向）
# 模擬層只做命中、位移、投射物；姿勢由畫面層 view/animator.gd 依 player.anim 計算（15.5）
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


# 瞄準點太靠近（0.5 單位內）時沿用目前朝向
static func aim_direction(p: Player) -> Vector2:
	var v := p.aim_point - p.pos
	if v.length_squared() < 0.25:
		return forward(p)
	return v.normalized()


# 玩家投射物從胸口高度發射；在空中發射時，飛出 bolt_settle_distance 內降回離地 bolt_altitude（才打得到地上的怪）
static func spawn_projectile(p: Player, params: Dictionary) -> void:
	params["owner"] = p
	params["altitude"] = p.height + Config.HEIGHT.bolt_altitude
	params["settle_altitude"] = Config.HEIGHT.bolt_altitude
	params["settle_distance"] = Config.HEIGHT.bolt_settle_distance
	p.world.spawn_projectile(Projectile.new(p.world, params))


class MeleeSwing extends Behavior:
	func enter(p: Player, def: Dictionary, data: Dictionary) -> void:
		p.combo_step = (p.combo_step + 1) % 3 if p.combo_timer > 0.0 else 0
		data.is_finisher = p.combo_step == 2
		data.swing_dir = -1 if p.combo_step == 1 else 1   # 第二段反手
		data.scale = def.finisher_scale if data.is_finisher else 1.0
		data.hit = {}
		if data.is_finisher:
			data.durations[2] = def.recovery * def.finisher_recovery_mul

	func phase(p: Player, def: Dictionary, data: Dictionary, name: StringName) -> void:
		if name == &"active":
			data.lock_facing = true
			p.knockback += WeaponBehaviors.forward(p) * (def.lunge * data.scale)
		elif name == &"recovery":
			data.lock_facing = false

	func update(p: Player, def: Dictionary, data: Dictionary, name: StringName, _k: float, _dt: float) -> void:
		if name != &"active":
			return
		var fin: bool = data.is_finisher
		var shape := {"shape": &"sector", "range": def.range * data.scale, "arc": def.arc * data.scale}
		Hitbox.strike(p.world, p, p.pos, p.facing, shape, {
			"damage": def.damage * (def.finisher_mul if fin else 1.0) * p.damage_mul,
			"knockback": def.knockback * (def.finisher_impact_mul if fin else 1.0),
			"hit_stop": def.hit_stop * (def.finisher_impact_mul if fin else 1.0),
			"shake": def.shake * (def.finisher_shake_mul if fin else 1.0),
			"is_heavy": fin, "blockable": true,
		}, data.hit)

	func exit(p: Player, def: Dictionary, _data: Dictionary) -> void:
		p.combo_timer = def.combo_window


class ShieldBash extends Behavior:
	func enter(p: Player, def: Dictionary, data: Dictionary) -> void:
		data.dir = WeaponBehaviors.aim_direction(p)
		data.hit = {}
		data.lock_facing = true
		p.facing = atan2(data.dir.x, data.dir.y)
		p.set_stat_source(&"shieldBash", [[&"damage_taken", Stats.MUL, def.damage_taken_mul], [&"knockback_taken", Stats.MUL, 0.0]])

	func phase(p: Player, def: Dictionary, data: Dictionary, name: StringName) -> void:
		if name == &"active":
			p.forced_velocity = data.dir * def.dash_speed
			p.has_forced_velocity = true
			p.mass = def.dash_mass
		elif name == &"recovery":
			p.has_forced_velocity = false
			p.mass = Config.PLAYER.mass

	func update(p: Player, def: Dictionary, data: Dictionary, name: StringName, _k: float, _dt: float) -> void:
		if name != &"active":
			return
		var center: Vector2 = p.pos + data.dir * def.hit_offset
		Hitbox.strike(p.world, p, center, p.facing, {"shape": &"circle", "radius": def.radius}, {
			"damage": def.damage * p.damage_mul, "knockback": def.knockback, "origin": p.pos,
			"hit_stop": def.hit_stop, "shake": def.shake, "is_heavy": true, "blockable": false,
		}, data.hit)

	func exit(p: Player, _def: Dictionary, _data: Dictionary) -> void:
		p.has_forced_velocity = false
		p.mass = Config.PLAYER.mass
		p.remove_stat_source(&"shieldBash")


class FireBolt extends Behavior:
	func phase(p: Player, def: Dictionary, _data: Dictionary, name: StringName) -> void:
		if name != &"active":
			return
		var dir := WeaponBehaviors.aim_direction(p)
		p.facing = atan2(dir.x, dir.y)
		WeaponBehaviors.spawn_projectile(p, {
			"pos": p.pos + dir * def.spawn_offset, "direction": dir, "speed": def.projectile_speed,
			"range": def.range, "radius": def.projectile_radius, "damage": def.damage * p.damage_mul,
			"knockback": def.knockback, "color": def.color, "hit_stop": def.hit_stop, "shake": def.shake,
		})


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
			"range": data.dist - def.spawn_offset, "radius": def.projectile_radius, "damage": 0.0,
			"color": def.color,
			"explosion": {
				"radius": def.explosion_radius, "damage": def.damage * p.damage_mul, "knockback": def.knockback,
				"hit_stop": def.hit_stop, "shake": def.shake,
			},
		})


static var BEHAVIORS := {
	&"meleeSwing": MeleeSwing.new(),
	&"shieldBash": ShieldBash.new(),
	&"fireBolt": FireBolt.new(),
	&"arcaneBurst": ArcaneBurst.new(),
}
