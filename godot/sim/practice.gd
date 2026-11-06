# 武器測試場（單機）：測試面板直接改模擬狀態——指定稀有度的武器（照掉落規則擲數值）、道具與技能（技能有了就升級）、袋子 / 開格、
# 在面前生怪（可選魔法 / 稀有）、怪物停手、立即復活。規則都跟正式遊戲同一套，只是取得方式不同
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


# 照指定的稀有度做一把武器，跟正式遊戲一樣：灰色 = 起始武器（數值固定），其他照掉落的規則擲數值（WeaponDropDefs.make 給 rng）
static func make_weapon(world: World, base: StringName, rarity: StringName) -> Dictionary:
	if rarity == WeaponDropDefs.START_RARITY:
		return WeaponDropDefs.make(world.new_weapon_uid(), base, rarity)
	return WeaponDropDefs.make(world.new_weapon_uid(), base, rarity, world.rng)


# 武器放進背包（手上空著就拿起來，同撿到）；放不下掉在腳邊。回傳 true = 進了背包或手上
static func give_weapon(world: World, p: Player, inst: Dictionary) -> bool:
	if p.add_weapon(inst):
		return true
	world.drop_weapon(inst, p.pos)
	return false


# 道具或技能放進背包；放不下掉在腳邊（腳邊欄拖得進背包）。身上已經有、還沒滿級的技能照遺物的規則升 1 級（Relic.pick）
# 回傳給面板的一句話
static func give_item(world: World, p: Player, id: StringName) -> String:
	var name: String = ItemDefs.ITEMS[id].name
	var lv: int = p.skill_levels.get(id, 1)
	if ItemDefs.is_skill(id) and p.loadout.has_item(id) and lv < SkillDefs.LEVEL.max:
		p.skill_levels[id] = lv + 1
		world.emit_event("skill:leveled", {"player_id": p.id, "skill": String(id), "level": lv + 1})
		return "%s 升到 %d 級" % [name, lv + 1]
	if p.add_item(id) != &"":
		return "拿到 " + name
	world.drop_item(id, p.pos)
	return "背包滿了，放在腳邊：" + name


# 袋子（只有袋子分開的模式）：照撿到的規則接上，接不下進倉庫，都放不下掉在腳邊
static func give_bag(world: World, p: Player, kind: StringName, tier: StringName) -> String:
	var b := BagDefs.make(&"", kind, tier)
	if p.loadout.merged:
		return "背包合併沒有袋子：用「開格」"
	if p.loadout.add_bag(p, kind, tier) != &"":
		return "拿到 " + BagDefs.bag_name(b)
	world.drop_item(BagDefs.BAGS[kind].item, p.pos)
	return "放不下，放在腳邊：" + BagDefs.bag_name(b)


# 背包合併的開格：random 隨機 1 格（同過小關）、pick 自選 +1 次（同 Boss / 鐵砧）、all 全部打開
static func unlock(world: World, p: Player, action: StringName) -> String:
	if not p.loadout.merged:
		return "袋子分開的模式沒有鎖格"
	match action:
		&"random":
			if not p.loadout.unlock_random(p, world.rng):
				return "全部都開了"
		&"pick":
			p.loadout.unlock_picks += 1
			return "自選開格 %d 次：打開背包點鎖著的格子" % p.loadout.unlock_picks
		&"all":
			for s in p.loadout.locked_spots():
				p.loadout.unlock_cell(p, s.where, s.cell)
	p.loadout.refresh_items(p)
	return "還鎖著 %d 格" % p.loadout.locked_spots().size()


# 在玩家面前 SPAWN_AHEAD 生一隻（走得到的最近位置）；Boss 照常接上 Boss 血條
# rarity：普通 / 魔法 / 稀有，詞條與名字照正式遊戲抽（Spawner.roll_rarity）
static func spawn_enemy(world: World, p: Player, type: StringName, rarity: StringName = MonsterRarityDefs.NORMAL) -> Enemy:
	var at := world.nav.nearest_walkable(p.pos + MathUtil.dir_from_angle(p.view_facing()) * SPAWN_AHEAD)
	var e := world.spawner.spawn_at(world, type, at)
	if e != null and not e.is_boss():
		Spawner.roll_rarity(world, e, rarity)
	return e


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
