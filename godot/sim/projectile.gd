# 投射物：直線飛行，命中或飛到最大距離時結束；設定 explosion 時結束會造成範圍爆炸（照搬網頁版 Projectile.js）
class_name Projectile
extends Entity

var owner_id := 0
var direction := Vector2.ZERO
var speed := 0.0
var range_ := 0.0
var damage := 0.0
var knockback_force := 0.0
var color := Color.WHITE        # 只給畫面用
var visual: StringName = &"orb" # 只給畫面用：&"orb" 發光球體、&"arrow" 箭矢
var hit_stop := 0.0
var shake := 0.0
var blockable := true           # 有方向的投射物預設能被格擋（B5）；爆炸一律不能
var explosion: Dictionary = {}  # { radius, damage, knockback, hit_stop, shake }；空 = 一般投射物
var traveled := 0.0
var start_altitude := 0.0       # 發射時的飛行高度（height 是目前的飛行高度）
var settle_altitude := 0.0      # 離地高度目標（settle_distance > 0 時才用）
var settle_distance := 0.0      # 飛出幾單位內從 start_altitude 降到「地面 + settle_altitude」；0 = 高度不變


# p：owner、pos、direction、speed、range、radius、damage、knockback、color、visual、hit_stop、shake、explosion、
#    altitude（預設 發射者腳底 + HEIGHT.bolt_altitude）、settle_altitude、settle_distance
# damage 與 explosion.damage 在發射時就乘好攻擊者的攻擊力，發射者死掉後命中也照樣算
func _init(p_world: World, p: Dictionary) -> void:
	var owner: Entity = p.owner
	super(p_world, &"projectile", owner.team, p.get("radius", 0.25), 1.0)
	owner_id = owner.id
	pos = p.pos
	direction = (p.direction as Vector2).normalized()
	facing = atan2(direction.x, direction.y)
	speed = p.speed
	range_ = p.range
	damage = p.get("damage", 0.0)
	knockback_force = p.get("knockback", 0.0)
	color = p.get("color", Color.WHITE)
	visual = p.get("visual", &"orb")
	hit_stop = p.get("hit_stop", 0.0)
	shake = p.get("shake", 0.0)
	explosion = p.get("explosion", {})
	blockable = p.get("blockable", true)
	start_altitude = p.get("altitude", owner.height + Config.HEIGHT.bolt_altitude)
	settle_altitude = p.get("settle_altitude", 0.0)
	settle_distance = p.get("settle_distance", 0.0)
	height = start_altitude


func band() -> Vector2:
	return Combat.band_around(height, Config.HEIGHT.projectile_half)


func update(dt: float) -> void:
	if is_removed:
		return
	var step_len := speed * dt
	pos += direction * step_len
	traveled += step_len
	if settle_distance > 0.0:
		var k := minf(traveled / settle_distance, 1.0)
		height = lerpf(start_altitude, world.terrain.ground_at(pos) + settle_altitude, k)
	if world.terrain.is_solid(pos, height):
		_expire()
		return

	var b := band()
	for target in Combat.hostiles_of(world, team):
		# 翻滾無敵或高度不重疊（從頭頂 / 腳下飛過）時直接穿過
		if target.is_dodging() or not target.overlaps_height(b.x, b.y):
			continue
		var r := radius + target.radius
		if target.pos.distance_squared_to(pos) <= r * r:
			_on_hit(target)
			return

	var half := world.arena_half_size
	var outside := absf(pos.x) > half or absf(pos.y) > half
	if traveled >= range_ or outside:
		_expire()


# 發射者已被移除時，以投射物本身當傷害來源
func _source() -> Entity:
	return world.entities.get(owner_id, self)


func _on_hit(target: Entity) -> void:
	if not explosion.is_empty():
		_explode()
	else:
		# 擊退方向沿飛行方向
		Combat.apply_damage(world, _source(), target, {
			"damage": damage, "knockback": knockback_force, "origin": pos - direction,
			"hit_stop": hit_stop, "shake": shake, "band": band(), "blockable": blockable,
		})
	remove()


func _expire() -> void:
	if not explosion.is_empty():
		_explode()
	remove()


func _explode() -> void:
	world.emit_event("sfx:cue", {"cue": "explosion"})
	var source := _source()
	# 爆炸範圍從地面往上 HEIGHT.explosion_height（空中目標太高就炸不到）
	var ground := world.terrain.ground_at(pos)
	var blast := Vector2(ground - Config.HEIGHT.reach_below, ground + Config.HEIGHT.explosion_height)
	Hitbox.strike(world, source, pos, facing, {"shape": &"circle", "radius": explosion.radius}, {
		"damage": explosion.damage, "knockback": explosion.knockback, "origin": pos,
		"hit_stop": explosion.hit_stop, "is_heavy": true, "band": blast, "blockable": false,
	})
	if Combat.should_shake(self):
		world.emit_event("camera:shake", {"amount": explosion.shake, "duration": Config.COMBAT.explosion_shake_duration})
