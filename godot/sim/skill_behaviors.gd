# 主動技能 / 道具行為（照搬網頁版 skillBehaviors.js）：can_use 為額外使用條件，activate 執行效果
class_name SkillBehaviors


class Behavior:
	func can_use(_owner: Player, _def: Dictionary) -> bool:
		return true

	func activate(_owner: Player, _def: Dictionary) -> void:
		pass


class Heal extends Behavior:
	func can_use(owner: Player, _def: Dictionary) -> bool:
		return owner.hp < owner.max_hp

	func activate(owner: Player, def: Dictionary) -> void:
		var healed := owner.heal(def.amount)
		owner.world.emit_event("entity:healed", {"target_id": owner.id, "amount": healed})
		owner.world.emit_event("fx:heal", {"pos": owner.pos, "height": owner.height, "color": def.color})


class SpeedBuff extends Behavior:
	func activate(owner: Player, def: Dictionary) -> void:
		owner.add_buff(def.id, def.duration, {"stats": [[&"move_speed", Stats.MUL, def.speed_mul]], "trail_color": def.color})
		owner.world.emit_event("fx:sprint", {"pos": owner.pos, "height": owner.height, "color": def.color})


static var BEHAVIORS := {
	&"heal": Heal.new(),
	&"speedBuff": SpeedBuff.new(),
}
