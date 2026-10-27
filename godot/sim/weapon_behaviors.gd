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
		var hits := Hitbox.strike(p.world, p, p.pos, p.facing, shape, {
			"damage": p.move_damage(def) * (def.finisher_mul if fin else 1.0), "damage_type": p.weapon.damage_type,
			"knockback": def.get("finisher_knockback", def.knockback * def.finisher_impact_mul) if fin else def.knockback,
			"hit_stop": def.hit_stop * (def.finisher_impact_mul if fin else 1.0),
			"shake": def.shake * (def.finisher_shake_mul if fin else 1.0),
			"is_heavy": fin, "blockable": true, "force_crit": fin and def.get("finisher_crit", false),
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


# 影步（F6 雙匕首右鍵）：瞬移到 range 內離準星最近那隻怪的背後（背後是牆就繞著怪找空位），背刺一下必爆擊；
# 沒有怪就不瞬移，冷卻改成 miss_cooldown
class ShadowStep extends Behavior:
	func enter(p: Player, def: Dictionary, data: Dictionary) -> void:
		data.lock_facing = true
		data.target_id = 0
		var best := INF
		for e in Combat.hostiles_of(p.world, p.team, p.id):
			if e is Player or e.pos.distance_to(p.pos) > def.range + e.radius:
				continue
			var d := e.pos.distance_squared_to(p.aim_point)
			if d < best:
				best = d
				data.target_id = e.id
		if data.target_id == 0:
			p.world.cooldowns.start(p.cd("player.special"), def.miss_cooldown * p.stats.value(&"cooldown"))

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
			"heal_per_sec": def.heal_per_sec, "damage_per_sec": p.move_damage(def), "damage_type": p.weapon.damage_type,
		})


# 點燃（F8 火把）：招式有 burn 時，打中的怪每秒受到 burn.pct_per_sec 的持續傷害 burn.duration 秒（不觸發道具）
static func ignite(p: Player, def: Dictionary, hits: Array[Entity]) -> void:
	if not def.has("burn"):
		return
	for t in hits:
		if t is Enemy:
			(t as Enemy).apply_burn(p.id, p.pct_damage(def.burn.pct_per_sec), def.burn.duration)


# 火把準備姿態（F8）：進入後左右鍵換成 stance 的招式（Player.action_def），翻滾、跳躍、換武器、倒地才結束
class TorchStance extends Behavior:
	func phase(p: Player, _def: Dictionary, _data: Dictionary, name: StringName) -> void:
		if name == &"active":
			p.torch_stance = true


# 插火把（F8，準備姿態的左鍵）：插在腳下，整關不熄；每關 per_floor 支、冷卻 cooldown 秒；只有房主產生火把實體
class PlantTorch extends Behavior:
	func phase(p: Player, def: Dictionary, _data: Dictionary, name: StringName) -> void:
		if name != &"active":
			return
		var key := p.cd("player.torch")
		if p.torches_left <= 0 or not p.world.cooldowns.is_ready(key):
			p.world.emit_event("skill:onCooldown", {"key": "player.torch", "player_id": p.id})
			return
		p.world.cooldowns.start(key, def.cooldown)
		p.torches_left -= 1
		if p.world.is_authority:
			var t := Torch.new(p.world, p.pos + WeaponBehaviors.forward(p) * 0.6, p.id)
			p.world.add_entity(t)
			p.world.torches.append(t)


# 噴火（F8，準備姿態的右鍵）：前方扇形大範圍傷害 + 點燃
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


# 鏟起（F9 鐵鏟右鍵）：抓起面前 reach 內最近的一隻非 Boss 敵人，舉著 hold_time 秒（Player.grab_enemy）；沒抓到冷卻改成 miss_cooldown
class ShovelGrab extends Behavior:
	func phase(p: Player, def: Dictionary, _data: Dictionary, name: StringName) -> void:
		if name != &"active":
			return
		var best: Enemy = null
		var best_d := INF
		for e in p.world.enemies:
			var en := e as Enemy
			if en == null or en.is_dead or en.team == p.team or en.is_boss() or en.grabbed_by != 0 or en.buried_timer > 0.0:
				continue
			var d := en.pos.distance_to(p.pos) - en.radius - p.radius
			var ahead := WeaponBehaviors.forward(p).dot((en.pos - p.pos).normalized()) > 0.3
			if d <= def.reach and ahead and d < best_d:
				best_d = d
				best = en
		if best == null:
			p.world.cooldowns.start(p.cd("player.special"), def.miss_cooldown * p.stats.value(&"cooldown"))
			return
		p.grab_enemy(best, def.hold_time)


# 拋出（F9，舉著怪時的左鍵）：往前丟 distance（撞牆就停在牆前），路上撞到的怪受 path_damage_pct、被丟的怪落地受 damage_pct，都可擊退
class ShovelThrow extends Behavior:
	func phase(p: Player, def: Dictionary, _data: Dictionary, name: StringName) -> void:
		if name != &"active":
			return
		var held := p.release_enemy()
		if held == null:
			return
		var dir := WeaponBehaviors.aim_direction(p)
		p.facing = atan2(dir.x, dir.y)
		var start := held.pos
		var land := start
		var step := 0.5
		var travel := 0.0
		while travel + step <= def.distance:
			var nxt := start + dir * (travel + step)
			if p.world.terrain.blocks_nav(nxt, held.radius) or absf(nxt.x) > p.world.half_extents.x - held.radius or absf(nxt.y) > p.world.half_extents.y - held.radius:
				break
			travel += step
			land = nxt
		for e in p.world.enemies:
			if e == held or e.is_dead or e.team == p.team:
				continue
			var t := clampf((e.pos - start).dot(dir), 0.0, travel)
			if (start + dir * t).distance_to(e.pos) <= def.path_width + e.radius:
				Combat.apply_damage(p.world, p, e, {"damage": p.pct_damage(def.path_damage_pct), "damage_type": p.weapon.damage_type,
					"knockback": def.knockback, "origin": start + dir * t - dir, "is_heavy": true, "color": def.color})
		held.pos = land
		held.prev_pos = land
		Combat.apply_damage(p.world, p, held, {"damage": p.move_damage(def), "damage_type": p.weapon.damage_type,
			"knockback": def.knockback, "origin": land - dir, "hit_stop": def.hit_stop, "shake": def.shake, "is_heavy": true, "color": def.color})
		p.world.emit_event("fx:explosion", {"pos": land, "height": p.world.terrain.ground_at(land), "radius": 1.2, "color": def.color})


# 埋入（F9，舉著怪時的右鍵）：埋進土裡只露半身，暈 stun 秒再花 crawl 秒爬出（Enemy.bury），受到 damage_pct
class ShovelBury extends Behavior:
	func phase(p: Player, def: Dictionary, _data: Dictionary, name: StringName) -> void:
		if name != &"active":
			return
		var held := p.release_enemy()
		if held == null:
			return
		Combat.apply_damage(p.world, p, held, {"damage": p.move_damage(def), "damage_type": p.weapon.damage_type,
			"knockback": 0.0, "no_stagger": true, "hit_stop": def.hit_stop, "shake": def.shake, "is_heavy": true, "color": def.color})
		held.bury(def.stun + def.crawl)


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
	&"shieldBlock": ShieldBlock.new(),
	&"fireBolt": FireBolt.new(),
	&"arcaneBurst": ArcaneBurst.new(),
	&"arrowFan": ArrowFan.new(),
	&"chargedShot": ChargedShot.new(),
	&"shadowStep": ShadowStep.new(),
	&"holyCircle": HolyCircle.new(),
	&"torchStance": TorchStance.new(),
	&"plantTorch": PlantTorch.new(),
	&"fireBreath": FireBreath.new(),
	&"shovelGrab": ShovelGrab.new(),
	&"shovelThrow": ShovelThrow.new(),
	&"shovelBury": ShovelBury.new(),
}
