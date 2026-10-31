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
var height := 0.0                 # 腳底離地高度（Y）
var prev_height := 0.0
var vz := 0.0                     # 垂直速度（向上為正）
var ground_height := 0.0          # 腳下的地面高度（地形石台頂面或 0）
var terrain_checked_pos := Vector2.INF   # 上次推出石台、算過落地時的位置（World.step 沒移動就跳過，D5）
var fixed := false                # 固定不動（休眠的怪群）：不積分；互推時不被推、只推開別人（v0.30.0 效能）
var body_height := 2.0            # 身高：命中判定佔 [height, height + body_height]
var invuln_timer := 0.0
var regen_block_timer := 0.0      # > 0 時生命回復暫停（玩家受傷後設定，見 Config.PLAYER.regen_delay）
var suppress_stagger := false     # 這一下傷害不造成受擊硬直（Combat 在 take_damage 前後設定，v0.27.0）
var flash_timer := 0.0
var is_dead := false
var is_removed := false


func _init(p_world: World, p_kind: StringName, p_team: StringName, p_radius: float, p_max_hp: float, p_mass: float = 1.0) -> void:
	world = p_world
	kind = p_kind
	team = p_team
	radius = p_radius
	body_height = Config.HEIGHT.body.get(p_kind, Config.HEIGHT.default_body)
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


# 能不能被當成攻擊與追擊的目標（倒地的玩家不行，見 Player）
func is_targetable() -> bool:
	return not is_dead


# 能格擋的攻擊打過來時由 Combat 呼叫；回傳 true = 擋下（不扣血）。只有玩家格擋時會擋（Player.try_block）
func try_block(_from: Vector2, _hit: Dictionary) -> bool:
	return false


# 閃避中（翻滾無敵）：不能被打中，投射物直接穿過；受傷後的無敵時間則仍會擋下投射物
func is_dodging() -> bool:
	return false


# dir 為已正規化的 XZ 方向；回傳實際傷害（套用護甲與受傷倍率），未命中回傳 -1
# 傷害與血量保留小數（v0.41.0 使用者決定），只在畫面上取整：傷害數字四捨五入、血量無條件進位（UiKit.dmg_text / hp_text）
# damage_type：StatDefs.DAMAGE_TYPES 之一，決定看護甲與哪一種抗性（StatDefs.damage_factor）
func take_damage(amount: float, dir: Vector2, p_knockback: float, source_id: int, damage_type := &"phys") -> float:
	if not can_be_hit():
		return -1.0
	var dealt := maxf(0.0, amount * StatDefs.damage_factor(stats, damage_type) * damage_taken_mul)
	hp = maxf(0.0, hp - _absorb(dealt))   # 護盾先扣（G4 骨製護盾）；回傳的 dealt 仍是整下的量
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
	# kind：遊玩紀錄算擊殺種類（v0.34.0）；pos：發聲位置（加入方只收 interest_radius 內的實體，遠處的怪不在他的世界）
	world.emit_event("entity:died", {"entity_id": id, "source_id": source_id, "kind": kind, "pos": pos})
	_on_died(source_id)


func _on_damaged(_amount: float, _source_id: int) -> void:
	pass


# 這一下要扣血的部分（有護盾的子類別覆寫）
func _absorb(amount: float) -> float:
	return amount


func _on_died(_source_id: int) -> void:
	pass


func update(_dt: float) -> void:
	pass


func integrate(dt: float) -> void:
	pos += (velocity + knockback) * dt
	knockback *= exp(-Config.COMBAT.knockback_damping * dt)
	invuln_timer = maxf(0.0, invuln_timer - dt)
	flash_timer = maxf(0.0, flash_timer - dt)
	regen_block_timer = maxf(0.0, regen_block_timer - dt)
	var regen := stats.value(&"hp_regen")
	if regen > 0.0 and regen_block_timer <= 0.0:
		heal(regen * dt)


static func gravity() -> float:
	return 8.0 * Config.JUMP.height / pow(Config.JUMP.air_time, 2.0)


func is_grounded() -> bool:
	return height <= ground_height + 1e-4 and vz <= 0.0


# 高度範圍 [low, high] 是否與身體重疊
func overlaps_height(low: float, high: float) -> bool:
	return low < height + body_height and high > height


# 垂直移動：在水平位置與地形碰撞都決定後呼叫；離開地面就受重力下墜，落到地面為止
func integrate_vertical(dt: float, terrain: Terrain) -> void:
	ground_height = terrain.ground_at(pos)
	if vz > 0.0 or height > ground_height + 1e-4:
		# 用前後速度的平均（等加速度的精確解）：60 步 / 秒時最高點正好 1.5、36 步落地
		var v0 := vz
		vz -= gravity() * dt
		height += (v0 + vz) * 0.5 * dt
		if height <= ground_height:
			height = ground_height
			vz = 0.0
	else:
		height = ground_height
		vz = 0.0


func remove() -> void:
	is_removed = true


# 由 World 在移除實體或 clear() 時呼叫：切斷循環參照（RefCounted 才會釋放）
func detach() -> void:
	world = null
