# 實體基底：位置、速度、半徑、屬性與血量、擊退、受傷/死亡流程（XZ 平面以 Vector2(x, z) 表示）
class_name Entity
extends RefCounted

var world: World
var id := 0
var kind: StringName       # 畫面層依此選模型，例如 &"player"
var team: StringName       # &"player" | &"enemy"
var radius := 0.5
var mass := 1.0
var stats: Stats
var hp := 1.0
# 常用屬性的捷徑（唯讀，改數值請用 set_stat_source）
var max_hp: float:
	get:
		return stats.value(&"max_hp")
var damage_mul: float:
	get:
		return stats.value(&"damage")
var damage_taken_mul: float:
	get:
		return stats.value(&"damage_taken")
var knockback_mul: float:
	get:
		return stats.value(&"knockback_taken")
var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO      # 上一步的位置，畫面層補間用
var velocity := Vector2.ZERO      # 本步主動移動速度，由各實體 update 設定
var knockback := Vector2.ZERO     # 被動位移速度，指數衰減
var facing := 0.0
var prev_facing := 0.0
var invuln_timer := 0.0
var flash_timer := 0.0
var is_dead := false
var is_removed := false


func _init(p_world: World, p_kind: StringName, p_team: StringName, p_radius: float, p_max_hp: float, p_mass: float = 1.0) -> void:
	world = p_world
	kind = p_kind
	team = p_team
	radius = p_radius
	stats = Stats.new({&"max_hp": p_max_hp})
	hp = max_hp
	mass = p_mass


# 設定某個來源的屬性加成（見 sim/stats.gd）；最大生命提高時目前生命增加同樣的量，降低時只截到上限
func set_stat_source(source: StringName, mods: Array) -> void:
	var before := max_hp
	stats.set_source(source, mods)
	_on_max_hp_changed(before)


func remove_stat_source(source: StringName) -> void:
	var before := max_hp
	stats.remove_source(source)
	_on_max_hp_changed(before)


func _on_max_hp_changed(before: float) -> void:
	var after := max_hp
	if after > before and not is_dead:
		hp += after - before
	hp = minf(hp, after)


func can_be_hit() -> bool:
	return not is_dead and invuln_timer <= 0.0 and not is_dodging()


# 閃避中（翻滾無敵）：不能被打中，投射物直接穿過；受傷後的無敵時間則仍會擋下投射物
func is_dodging() -> bool:
	return false


# dir 為已正規化的 XZ 方向；回傳實際傷害（套用護甲與受傷倍率），未命中回傳 -1
func take_damage(amount: float, dir: Vector2, p_knockback: float, source_id: int) -> int:
	if not can_be_hit():
		return -1
	var dealt := maxi(0, roundi(amount * StatDefs.armor_damage_factor(stats.value(&"armor")) * damage_taken_mul))
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
	var regen := stats.value(&"hp_regen")
	if regen > 0.0:
		heal(regen * dt)


func remove() -> void:
	is_removed = true


# 由 World 在移除實體或 clear() 時呼叫：切斷循環參照（RefCounted 才會釋放）
func detach() -> void:
	world = null
