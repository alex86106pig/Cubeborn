# 墓穴蜘蛛（第 3 層的怪，第 2 層的石棺噴出來；數值 Claude 暫定）：同骷髏弓手保持距離、橫移，停下瞄準（前腳抬起、腹部翹起）
# 後吐蛛絲彈：打中玩家纏住 web.root 秒（不能動、出招）；沒打中（飛到盡頭、撞牆、被盾擋下）就在落點結成蛛網：
# 站在網上移速 × web.slow，被火焰傷害打到就燒掉（GroundZones.burn_webs）
class_name Spider
extends RangedEnemy


func fire() -> void:
	world.emit_event("sfx:cue", {"cue": "arrowShot", "pos": pos})
	var dir := MathUtil.dir_from_angle(facing)
	var aim := {}
	var target: Entity = nearest_target()
	if target != null:
		aim = {"aim_altitude": _shot_altitudes(target.pos).y, "aim_distance": pos.distance_to(target.pos)}
		# 蛛絲彈飛到目標當時的位置就落地（沒打中就在那裡結網），不會一直飛到射程盡頭
		aim["range"] = minf(def.projectile_range, pos.distance_to(target.pos) + def.web.overshoot)
	world.spawn_projectile(Projectile.new(world, {
		"owner": self, "pos": pos + dir * def.projectile_offset, "direction": dir,
		"speed": def.projectile_speed, "range": aim.get("range", def.projectile_range), "radius": def.projectile_radius,
		"damage": def.projectile_damage * damage_mul, "knockback": def.projectile_knockback,
		"color": def.projectile_color, "visual": &"orb", "altitude": height + Config.HEIGHT.arrow_altitude,
		"blockable": def.projectile_blockable, "web": def.web,
		"aim_altitude": aim.get("aim_altitude", height + Config.HEIGHT.arrow_altitude), "aim_distance": aim.get("aim_distance", 0.0),
	}))
