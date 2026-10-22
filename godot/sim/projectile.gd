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
var explosion: Dictionary = {}  # { radius, damage, knockback, hit_stop, shake }；空 = 一般投射物
var traveled := 0.0


# p：owner、pos、direction、speed、range、radius、damage、knockback、color、visual、hit_stop、shake、explosion
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


func update(dt: float) -> void:
	if is_removed:
		return
	var step_len := speed * dt
	pos += direction * step_len
	traveled += step_len

	for target in Combat.hostiles_of(world, team):
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
			"hit_stop": hit_stop, "shake": shake,
		})
	remove()


func _expire() -> void:
	if not explosion.is_empty():
		_explode()
	remove()


func _explode() -> void:
	world.emit_event("sfx:cue", {"cue": "explosion"})
	var source := _source()
	for target in Combat.query_circle(pos, explosion.radius, Combat.hostiles_of(world, team)):
		Combat.apply_damage(world, source, target, {
			"damage": explosion.damage, "knockback": explosion.knockback, "origin": pos,
			"hit_stop": explosion.hit_stop, "is_heavy": true,
		})
	world.emit_event("camera:shake", {"amount": explosion.shake, "duration": Config.COMBAT.explosion_shake_duration})
