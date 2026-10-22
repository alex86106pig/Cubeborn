# 地形：場地內的長方體石台。查某一點的地面高度、把腳底低於石台頂面的實體推出石台（當牆）、投射物撞牆
# 腳底高度 ≥ 頂面 − HEIGHT.step 的實體可以站在上面；圓心在石台範圍內時地面高度就是頂面
class_name Terrain
extends RefCounted

var blocks: Array[Dictionary] = []   # { min: Vector2, max: Vector2, top: float }


func _init(defs: Array[Dictionary] = []) -> void:
	for d in defs:
		var half: Vector2 = d.size / 2.0
		blocks.append({"min": d.center - half, "max": d.center + half, "top": d.top})


func ground_at(p: Vector2) -> float:
	var ground := 0.0
	for b in blocks:
		if p.x >= b.min.x and p.x <= b.max.x and p.y >= b.min.y and p.y <= b.max.y:
			ground = maxf(ground, b.top)
	return ground


# 高度 altitude 的點是否在某個石台裡面（投射物撞牆用）
func is_solid(p: Vector2, altitude: float) -> bool:
	return ground_at(p) > altitude


# 腳底低於頂面的石台當牆：圓與長方形重疊時，沿最近點方向推出去
func push_out(e: Entity) -> void:
	var step: float = Config.HEIGHT.step
	for b in blocks:
		if e.height >= b.top - step:
			continue
		var closest := Vector2(clampf(e.pos.x, b.min.x, b.max.x), clampf(e.pos.y, b.min.y, b.max.y))
		var d := e.pos - closest
		var dist_sq := d.length_squared()
		if dist_sq >= e.radius * e.radius:
			continue
		if dist_sq > 1e-8:
			var dist := sqrt(dist_sq)
			e.pos += d / dist * (e.radius - dist)
			continue
		# 圓心在石台裡面：往最近的一邊推出去
		var exits := [
			[e.pos.x - b.min.x, Vector2(b.min.x - e.radius, e.pos.y)],
			[b.max.x - e.pos.x, Vector2(b.max.x + e.radius, e.pos.y)],
			[e.pos.y - b.min.y, Vector2(e.pos.x, b.min.y - e.radius)],
			[b.max.y - e.pos.y, Vector2(e.pos.x, b.max.y + e.radius)],
		]
		exits.sort_custom(func(a: Array, c: Array) -> bool: return a[0] < c[0])
		e.pos = exits[0][1]
