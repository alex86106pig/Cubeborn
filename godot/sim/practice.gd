# 武器測試場（單機）：測試面板直接改模擬狀態——指定稀有度與詞條的武器、道具與技能放進背包、在面前生怪、怪物停手、立即復活
# 只在單機的測試場用（World.practice）；連線不經過這裡
class_name Practice

const SPAWN_AHEAD := 6.0   # 生怪在面前多遠
# 測試面板列的怪物：骷髏僕從（玩家方）不列
const HIDDEN_ENEMIES: Array[StringName] = [&"minion"]


static func enemy_types() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in EnemyDefs.ENEMIES:
		if not HIDDEN_ENEMIES.has(id):
			out.append(id)
	return out


# 這種稀有度能選的詞條（照 AFFIXES 的順序）
static func affixes_for(rarity: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in WeaponDropDefs.AFFIXES:
		if WeaponDropDefs.allowed(id, rarity):
			out.append(id)
	return out


# 詞條選得對不對：條數不超過稀有度的上限、都是這個稀有度能出的、分支最多 1 條；回傳錯誤訊息，空字串 = 可以
static func affix_error(rarity: StringName, affixes: Array[StringName]) -> String:
	var limit := WeaponDropDefs.affix_count(rarity)
	if affixes.size() > limit:
		return "%s最多 %d 條詞條" % [ItemDefs.RARITIES[rarity].name, limit]
	var branches := 0
	for id in affixes:
		if not WeaponDropDefs.allowed(id, rarity):
			return "「%s」%s不能出" % [WeaponDropDefs.AFFIXES[id].desc, ItemDefs.RARITIES[rarity].name]
		if WeaponDropDefs.AFFIXES[id].kind == &"branch":
			branches += 1
	if branches > 1:
		return "分支詞條最多 1 條"
	return ""


# 照指定的稀有度與詞條做一把武器（不補隨機詞條）；印記格照常隨機、自帶技能照常鑲上
static func make_weapon(world: World, base: StringName, rarity: StringName, affixes: Array[StringName]) -> Dictionary:
	return {"uid": world.new_weapon_uid(), "base": base, "rarity": rarity, "affixes": affixes.duplicate()}


# 武器放進背包（手上空著就拿起來，同撿到）；放不下掉在腳邊。回傳 true = 進了背包或手上
static func give_weapon(world: World, p: Player, inst: Dictionary) -> bool:
	if p.add_weapon(inst):
		return true
	world.drop_weapon(inst, p.pos)
	return false


# 道具或技能放進背包；放不下掉在腳邊（腳邊欄拖得進背包）
static func give_item(world: World, p: Player, id: StringName) -> bool:
	if p.add_item(id) != &"":
		return true
	world.drop_item(id, p.pos)
	return false


# 在玩家面前 SPAWN_AHEAD 生一隻（走得到的最近位置）；Boss 照常接上 Boss 血條
static func spawn_enemy(world: World, p: Player, type: StringName) -> Enemy:
	var at := world.nav.nearest_walkable(p.pos + MathUtil.dir_from_angle(p.view_facing()) * SPAWN_AHEAD)
	return world.spawner.spawn_at(world, type, at)


# 清掉場上所有怪（木樁也清，之後重置木樁再擺）
static func clear_enemies(world: World) -> void:
	for e in world.enemies:
		if e.team == &"enemy":
			(e as Enemy).remove()


# 立即復活：原地滿血滿魔、短暫無敵；倒地與死亡都可以
static func revive(world: World, p: Player) -> void:
	p.resurrect(p.pos, 1.0)
	p.mana = p.max_mana()
	world.is_defeated = false
