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


# 插火把（F8）：插在面前，整關不熄；只有房主產生火把實體
class PlantTorch extends Behavior:
	func activate(owner: Player, _def: Dictionary) -> void:
		if owner.world.is_authority:
			var t := Torch.new(owner.world, owner.pos + WeaponBehaviors.forward(owner) * 0.6, owner.id)
			owner.world.add_entity(t)
			owner.world.torches.append(t)


static var BEHAVIORS := {
	&"heal": Heal.new(),
	&"plantTorch": PlantTorch.new(),
}
