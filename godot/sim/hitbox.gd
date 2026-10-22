# 通用攻擊判定（v0.17.0）：玩家與怪物共用的形狀查詢、出招、記錄本步出現的判定（畫面層 F2 顯示用）
# 形狀 shape：{ shape: &"sector", range, arc }（以 facing 為中心的扇形）| { shape: &"circle", radius }
# 出招的 hit 欄位同 Combat.apply_damage（含 band 高度範圍），另外標 blockable（能不能被格擋，B5 格擋用）
class_name Hitbox


static func query(world: World, team: StringName, origin: Vector2, facing: float, shape: Dictionary) -> Array[Entity]:
	var candidates := Combat.hostiles_of(world, team)
	match shape.shape:
		&"sector":
			return Combat.query_sector(origin, facing, shape.range, shape.arc, candidates)
		&"circle":
			return Combat.query_circle(origin, shape.radius, candidates)
	assert(false, "Unknown hitbox shape: %s" % shape.shape)
	return []


# 出一次招：記錄判定、對形狀內的敵對目標套用傷害；already（id -> true）裡的目標跳過，查到的目標會加進去（同一招只打一次）
# 回傳實際命中的目標
static func strike(world: World, source: Entity, origin: Vector2, facing: float, shape: Dictionary, hit: Dictionary, already: Dictionary = {}) -> Array[Entity]:
	var band: Vector2 = hit.get("band", Combat.body_band(source))
	world.record_hitbox({"shape": shape, "origin": origin, "facing": facing, "band": band, "team": source.team})
	var hits: Array[Entity] = []
	for target in query(world, source.team, origin, facing, shape):
		if already.has(target.id):
			continue
		already[target.id] = true
		if Combat.apply_damage(world, source, target, hit):
			hits.append(target)
	return hits
