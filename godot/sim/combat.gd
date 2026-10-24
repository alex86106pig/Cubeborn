# 傷害結算與命中判定查詢（扇形、圓形）；照搬網頁版 legacy/src/combat/Combat.js
class_name Combat


# team 的敵對陣營中仍存活的實體；倒地的玩家不會被當成目標
# 誤傷（Config.NET.friendly_fire）：玩家方的攻擊也會打到其他玩家，但不會打到出招者自己（source_id）
static func hostiles_of(world: World, team: StringName, source_id: int = 0) -> Array[Entity]:
	var out: Array[Entity] = []
	if team == &"player":
		for e in world.enemies:
			if not e.is_dead:
				out.append(e)
		if Config.NET.friendly_fire:
			for p in world.player_list:
				if p.id != source_id and p.is_targetable():
					out.append(p)
	else:
		for p in world.player_list:
			if p.is_targetable():
				out.append(p)
	return out


# hit：damage（已含攻擊者的攻擊力，由發動招式的一方計算）、knockback、origin（預設 source.pos，擊退方向為 origin → target）、
#      hit_stop（命中定格秒數，只給畫面層）、shake、is_heavy（重擊：第三段、盾反、爆炸，只影響顯示與音效）、blockable（能不能被格擋）、
#      color（命中粒子顏色，只給畫面層；預設白色）、
#      band（高度範圍 Vector2(下緣, 上緣)；預設是攻擊者的身體往腳底下延伸 HEIGHT.reach_below，見 body_band）、
#      max_air（選填：目標腳底離自己腳下地面超過這個高度就打不到）、no_stagger（選填：不讓目標進入受擊硬直）
# 這裡套用攻擊者的爆擊與擊退屬性；護甲與受傷倍率在 Entity.take_damage
# 回傳是否實際命中（高度不重疊、被格擋也算沒命中）
static func apply_damage(world: World, source: Entity, target: Entity, hit: Dictionary) -> bool:
	# 傷害一律由房主判定：客戶端本機預測自己的出招時不扣任何血（C3）
	if not world.is_authority or target == null or not target.can_be_hit():
		return false
	# 命中結果不是本機預測得到的，事件不標行動者（客戶端才不會當成自己已經播過而丟掉）
	var actor := world.event_actor
	world.event_actor = 0
	var landed := _apply_damage(world, source, target, hit)
	world.event_actor = actor
	return landed


static func _apply_damage(world: World, source: Entity, target: Entity, hit: Dictionary) -> bool:
	var band: Vector2 = hit.get("band", body_band(source))
	if not target.overlaps_height(band.x, band.y):
		return false
	# max_air：目標腳底離自己腳下地面超過這個高度（跳起來）就打不到（Boss 砸地，v0.23.0）
	if hit.has("max_air") and target.height - target.ground_height > hit.max_air + 1e-4:
		return false
	var origin: Vector2 = hit.get("origin", source.pos)
	# 格擋：只對 blockable 的攻擊（揮砍、箭）；砸地、衝鋒、爆炸擋不住
	if hit.get("blockable", false) and target.try_block(origin, hit):
		return false
	var dir := target.pos - origin
	if dir.length_squared() < 1e-6:
		dir = MathUtil.dir_from_angle(source.facing)
	dir = dir.normalized()

	var damage: float = hit.damage
	var is_proc: bool = hit.get("proc", false)   # 道具效果造成的傷害（v0.33.0）：不爆擊、不再觸發命中效果
	if source is Player and not is_proc:
		# 只對這一下生效的條件加成（對滿血敵人）：換算成攻擊力倍率乘上去（hit.damage 已含攻擊力）
		var extra := ItemEffects.target_damage_pct(source as Player, target)
		var base_mul := source.stats.value(&"damage")
		if extra > 0.0 and base_mul > 0.0:
			damage *= source.stats.value_with_pct(&"damage", extra) / base_mul
	var is_crit := false
	var crit_chance := 0.0 if is_proc else source.stats.value(&"crit_chance")
	# 爆擊率 0 時不擲骰，不消耗亂數（沒有爆擊道具時與網頁版的亂數序列相同）
	if crit_chance > 0.0 and world.rng.randf() < crit_chance:
		is_crit = true
		damage *= source.stats.value(&"crit_damage")
	var knockback: float = hit.get("knockback", 0.0) * source.stats.value(&"knockback")
	target.suppress_stagger = hit.get("no_stagger", false)   # 遠程武器的普攻不讓怪物進入受擊硬直（v0.27.0）
	var dealt := target.take_damage(damage, dir, knockback, source.id)
	target.suppress_stagger = false
	if dealt < 0:
		return false
	if source is Enemy:
		(source as Enemy).on_dealt_damage(dealt)   # 吸血詞條（D5）

	# hit_stop 只放進事件：畫面層讓攻擊者與目標的模型定格這麼久（v0.18.3 起模擬時間不再放慢，多人時不影響其他人）
	var ev := {
		"target_id": target.id, "amount": dealt, "source_id": source.id,
		"knockback": knockback, "is_heavy": hit.get("is_heavy", false), "is_crit": is_crit,
		"hit_stop": hit.get("hit_stop", 0.0), "color": hit.get("color", Color.WHITE),
	}
	if target is Player:
		# 遊玩紀錄（ui/run_log.gd，v0.34.0）：攻擊者可能這一步就消失（射手死了、投射物撞到就移除），種類與位置直接帶在事件裡；
		# lethal：這一下讓玩家倒下 / 死亡（倒下的事件比這個事件早發出）
		ev["source_kind"] = source.kind
		ev["origin"] = origin
		ev["lethal"] = target.hp <= 0.0
	world.emit_event("entity:damaged", ev)
	var shake: float = hit.get("shake", 0.0)
	if shake > 0.0 and should_shake(source):
		world.emit_event("camera:shake", {"amount": shake, "duration": Config.COMBAT.hit_shake_duration})
	if source is Player and target is Enemy:
		# 道具的命中 / 擊殺效果（v0.33.0）：放在事件之後，連鎖閃電、爆炸的傷害事件排在這一下後面
		if not is_proc:
			ItemEffects.on_hit(world, source as Player, target, damage)
		if target.is_dead:
			ItemEffects.on_kill(world, source as Player, target, damage)
	return true


# 畫面震動：玩家方的攻擊打中時不震動（v0.18.3 使用者決定，開關在 Config.FEEL）；怪物打中玩家照常震動
static func should_shake(source: Entity) -> bool:
	return source.team != &"player" or Config.FEEL.player_attack_shake


# 近戰、碰撞、衝鋒的預設高度範圍：攻擊者的身體，往腳底下延伸一點（空中揮砍打得到地上的怪）
static func body_band(e: Entity) -> Vector2:
	return Vector2(e.height - Config.HEIGHT.reach_below, e.height + e.body_height)


# 以 center 高度為中心、上下各 half 的範圍（投射物）
static func band_around(center: float, half: float) -> Vector2:
	return Vector2(center - half, center + half)


# 扇形判定：考慮目標半徑，貼身目標一律命中
static func query_sector(origin: Vector2, facing: float, range_: float, arc: float, candidates: Array[Entity]) -> Array[Entity]:
	var out: Array[Entity] = []
	for c in candidates:
		var d := c.pos - origin
		var dist := d.length()
		if dist > range_ + c.radius:
			continue
		if dist <= c.radius + 0.3:
			out.append(c)
			continue
		var diff := absf(MathUtil.wrap_angle(atan2(d.x, d.y) - facing))
		var allowance := arc / 2.0 + asin(minf(1.0, c.radius / dist))
		if diff <= allowance:
			out.append(c)
	return out


static func query_circle(center: Vector2, radius: float, candidates: Array[Entity]) -> Array[Entity]:
	var out: Array[Entity] = []
	for c in candidates:
		var r := radius + c.radius
		if c.pos.distance_squared_to(center) <= r * r:
			out.append(c)
	return out
