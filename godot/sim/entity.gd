# 實體基底：位置、速度、半徑、血量、擊退、受傷/死亡流程（XZ 平面以 Vector2(x, z) 表示）
class_name Entity
extends RefCounted

var world: World
var id := 0
var kind: StringName       # 畫面層依此選模型，例如 &"player"
var team: StringName       # &"player" | &"enemy"
var radius := 0.5
var mass := 1.0
var max_hp := 1.0
var hp := 1.0
var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO      # 上一步的位置，畫面層補間用
var velocity := Vector2.ZERO      # 本步主動移動速度，由各實體 update 設定
var knockback := Vector2.ZERO     # 被動位移速度，指數衰減
var facing := 0.0
var prev_facing := 0.0
var damage_taken_mul := 1.0
var knockback_mul := 1.0
var invuln_timer := 0.0
var flash_timer := 0.0
var is_dead := false
var is_removed := false


func _init(p_world: World, p_kind: StringName, p_team: StringName, p_radius: float, p_max_hp: float, p_mass: float = 1.0) -> void:
	world = p_world
	kind = p_kind
	team = p_team
	radius = p_radius
	max_hp = p_max_hp
	hp = p_max_hp
	mass = p_mass


func can_be_hit() -> bool:
	return not is_dead and invuln_timer <= 0.0


# dir 為已正規化的 XZ 方向；回傳實際傷害，未命中回傳 -1
func take_damage(amount: float, dir: Vector2, p_knockback: float, source_id: int) -> int:
	if not can_be_hit():
		return -1
	var dealt := maxi(0, roundi(amount * damage_taken_mul))
	hp = maxf(0.0, hp - dealt)
	flash_timer = Config.COMBAT.flash_time
	knockback += dir * (p_knockback * knockback_mul / mass)
	_on_damaged(dealt, source_id)
	if hp <= 0.0:
		die(source_id)
	return dealt


func heal(amount: float) -> float:
	if is_dead:
		return 0.0
	var before := hp
	hp = minf(max_hp, hp + amount)
	return hp - before


func die(source_id: int = 0) -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector2.ZERO
	world.emit_event("entity:died", {"entity_id": id, "source_id": source_id})
	_on_died(source_id)


func _on_damaged(_amount: int, _source_id: int) -> void:
	pass


func _on_died(_source_id: int) -> void:
	pass


func update(_dt: float) -> void:
	pass


func integrate(dt: float) -> void:
	pos += (velocity + knockback) * dt
	knockback *= exp(-Config.COMBAT.knockback_damping * dt)
	invuln_timer = maxf(0.0, invuln_timer - dt)
	flash_timer = maxf(0.0, flash_timer - dt)


func remove() -> void:
	is_removed = true


# 由 World 在移除實體或 clear() 時呼叫：切斷循環參照（RefCounted 才會釋放）
func detach() -> void:
	world = null
