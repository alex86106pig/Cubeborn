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
		"no_stagger": def.get("no_stagger", false), "visual": def.get("visual", &"orb"),
	}


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
			p.world.emit_event("fx:slash", {
				"pos": p.pos, "height": p.height, "facing": p.facing, "range": def.range * data.scale * p.weapon_range_mul(),
				"arc": def.arc * data.scale, "color": def.slash_finisher_color if data.is_finisher else def.slash_color,
				"swing_dir": data.swing_dir,
			})
		elif name == &"recovery":
			data.lock_facing = false

	func update(p: Player, def: Dictionary, data: Dictionary, name: StringName, _k: float, _dt: float) -> void:
		if name != &"active":
			return
		var fin: bool = data.is_finisher
		var shape := {"shape": &"sector", "range": def.range * data.scale * p.weapon_range_mul(), "arc": def.arc * data.scale}
		Hitbox.strike(p.world, p, p.pos, p.facing, shape, {
			"damage": p.move_damage(def) * (def.finisher_mul if fin else 1.0), "damage_type": p.weapon.damage_type,
			"knockback": def.knockback * (def.finisher_impact_mul if fin else 1.0),
			"hit_stop": def.hit_stop * (def.finisher_impact_mul if fin else 1.0),
			"shake": def.shake * (def.finisher_shake_mul if fin else 1.0),
			"is_heavy": fin, "blockable": true,
		}, data.hit)

	func exit(p: Player, def: Dictionary, _data: Dictionary) -> void:
		p.combo_timer = def.combo_window


# 格擋（v0.41.0）：按住右鍵就格擋（TimedAction 依 def.hold 停在 active），可以移動與轉向；放開進入收招、放下盾
# 格擋中按左鍵招架：開始冷卻與 parry.window 秒的判定；判定中擋下由 Player.try_block 標記成功（下一步全額盾反），
# 判定時間結束都沒擋到就打出傷害減半的盾擊
class ShieldBlock extends Behavior:
	func enter(p: Player, _def: Dictionary, _data: Dictionary) -> void:
		p.block_time = 0.0
		p.parry_time = -1.0

	func phase(p: Player, _def: Dictionary, _data: Dictionary, name: StringName) -> void:
		if name == &"recovery":
			p.block_time = -1.0
			p.parry_time = -1.0

	func update(p: Player, def: Dictionary, _data: Dictionary, name: StringName, _k: float, dt: float) -> void:
		if name == &"recovery":
			return
		p.block_time += dt
		var pr: Dictionary = def.parry
		if p.parry_time >= 0.0:
			p.parry_time += dt
			if p.parry_time >= pr.window - 1e-6:
				p.parry_time = -1.0
				p._parry(false)
		elif p.attack_pressed:
			var key := p.cd("player.parry")
			if p.world.cooldowns.is_ready(key):
				p.world.cooldowns.start(key, pr.cooldown * p.stats.value(&"cooldown"))
				p.world.emit_event("skill:used", {"key": "player.parry", "player_id": p.id})
				p.parry_time = 0.0
			else:
				p.world.emit_event("skill:onCooldown", {"key": "player.parry", "player_id": p.id})

	func exit(p: Player, _def: Dictionary, _data: Dictionary) -> void:
		p.block_time = -1.0
		p.parry_time = -1.0


class FireBolt extends Behavior:
	func phase(p: Player, def: Dictionary, _data: Dictionary, name: StringName) -> void:
		if name != &"active":
			return
		var dir := WeaponBehaviors.aim_direction(p)
		p.facing = atan2(dir.x, dir.y)
		WeaponBehaviors.spawn_projectile(p, WeaponBehaviors.shot_params(p, def, dir))
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
		# 落點預警圈：持續到魔彈飛到（蓄力 + 飛行時間）
		p.world.emit_event("fx:telegraph", {
			"pos": data.target, "height": p.world.terrain.ground_at(data.target), "radius": def.explosion_radius, "color": def.color,
			"life": def.windup + dist / def.projectile_speed,
		})

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


static var BEHAVIORS := {
	&"meleeSwing": MeleeSwing.new(),
	&"shieldBlock": ShieldBlock.new(),
	&"fireBolt": FireBolt.new(),
	&"arcaneBurst": ArcaneBurst.new(),
	&"arrowFan": ArrowFan.new(),
	&"chargedShot": ChargedShot.new(),
}
