# 武器測試場（單機）：測試面板直接改模擬狀態——指定稀有度的武器（照掉落規則擲數值）、道具與技能（技能有了就升級）、袋子 / 開格、
# 在面前生怪（可選魔法 / 稀有、一次幾隻、照第幾層第幾小關的成長）、怪物停手、立即復活、作弊開關、清空背包。規則都跟正式遊戲同一套，只是取得方式不同
# 只在單機的測試場用（World.practice）；連線不經過這裡
class_name Practice

const SPAWN_AHEAD := 6.0   # 生怪在面前多遠
# 測試面板列的怪物：骷髏僕從（玩家方）不列
const HIDDEN_ENEMIES: Array[StringName] = [&"minion"]
const SPAWN_COUNTS: Array[int] = [1, 5, 10]   # 一次生幾隻（Boss 固定 1 隻）
const SPAWN_ROW := 5       # 一排幾隻
const SPAWN_GAP := 1.6     # 同一排、排與排的間隔
# 作弊開關（World.practice_cheats 的 key）：魔力 = 每步補滿；冷卻 = 清掉這位玩家的冷卻（翻滾、藥水、施放間隔）並補滿藥水；無敵 = 打不到
const CHEATS := {&"mana": "無限魔力", &"cooldown": "沒有冷卻", &"invincible": "無敵"}
# 道具分頁的分組（照 ItemDefs.role_of）；技能分頁照 SkillDefs.CATEGORIES
const ITEM_GROUPS := [[ItemDefs.ROLE_STAT, "數值"], [ItemDefs.ROLE_EFFECT, "效果"], [ItemDefs.ROLE_MOD, "修飾"]]


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
# level > 0（只對技能）：直接設成那一級，身上沒有就先放進背包。回傳給面板的一句話
static func give_item(world: World, p: Player, id: StringName, level := 0) -> String:
	var name: String = ItemDefs.ITEMS[id].name
	var lv: int = p.skill_levels.get(id, 1)
	if ItemDefs.is_skill(id) and level > 0:
		level = mini(level, SkillDefs.LEVEL.max)
		var had := p.loadout.has_item(id)
		if not had and p.add_item(id) == &"":
			world.drop_item(id, p.pos)
			return "背包滿了，放在腳邊：" + name
		p.skill_levels[id] = level
		if had and level != lv:
			world.emit_event("skill:leveled", {"player_id": p.id, "skill": String(id), "level": level})
		return "%s %d 級" % [name, level]
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
	return spawn_enemies(world, p, type, rarity, 1)[0]


# 一次生 count 隻：面前排成橫排（一排 SPAWN_ROW 隻，往後排）；Boss 只生 1 隻。生命與攻擊照 World.practice_stage 那一關的成長
static func spawn_enemies(world: World, p: Player, type: StringName, rarity: StringName, count: int) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var ahead := MathUtil.dir_from_angle(p.view_facing())
	var side := Vector2(ahead.y, -ahead.x)
	# 那一關的成長乘在平常的生成倍率上（spawn_at 的 extra 蓋不掉已經有的生命 / 攻擊，所以自己算好再生）
	var stage := stage_mul(world.practice_stage.x, world.practice_stage.y)
	var mul := world.spawner.spawn_mul(world, type, {})
	mul.hp *= stage.hp
	mul.damage *= stage.damage
	if EnemyDefs.is_boss(type):
		count = 1
	var per_row := mini(count, SPAWN_ROW)
	for i in count:
		var col := (i % SPAWN_ROW) - (per_row - 1) * 0.5
		@warning_ignore("integer_division")
		var at := p.pos + ahead * (SPAWN_AHEAD + (i / SPAWN_ROW) * SPAWN_GAP) + side * col * SPAWN_GAP
		var e := Spawner.create(world, type, world.nav.nearest_walkable(at), mul)
		world.add_enemy(e)
		if not e.is_boss():
			Spawner.roll_rarity(world, e, rarity)
		out.append(e)
	return out


# 怪物分頁的分組：每層照 FLOOR_MIX 的怪，再來 Boss，其他（召喚的、事件的）放最後。回傳 [[標題, [種類…]]…]
static func enemy_groups() -> Array:
	var out := []
	var seen: Array[StringName] = []
	for f: int in EnemyDefs.FLOOR_MIX:
		var ids: Array[StringName] = []
		for id: StringName in EnemyDefs.FLOOR_MIX[f]:
			if not seen.has(id) and not HIDDEN_ENEMIES.has(id):
				ids.append(id)
				seen.append(id)
		out.append(["第 %d 層" % f, ids])
	var bosses: Array[StringName] = []
	var others: Array[StringName] = []
	for id in enemy_types():
		if EnemyDefs.is_boss(id):
			bosses.append(id)
		elif not seen.has(id):
			others.append(id)
	out.append(["Boss", bosses])
	if not others.is_empty():
		out.append(["其他", others])
	return out


# 道具分頁的分組（數值、效果、修飾，只列效果都接上的）；各組內照稀有度排。回傳 [[標題, [id…]]…]
static func item_groups() -> Array:
	var out := []
	for g: Array in ITEM_GROUPS:
		var ids: Array[StringName] = []
		for id: StringName in ItemDefs.ITEMS:
			if ItemDefs.ITEMS[id].kind == &"item" and ItemDefs.item_implemented(id) and ItemDefs.role_of(id) == g[0]:
				ids.append(id)
		out.append([g[1], _by_rarity(ids)])
	return out


# 技能分頁的分組（戰技、法術、輔助技能）
static func skill_groups() -> Array:
	var out := []
	for cat: StringName in SkillDefs.CATEGORIES:
		var ids: Array[StringName] = []
		for id: StringName in ItemDefs.ITEMS:
			if ItemDefs.is_skill(id) and SkillDefs.SKILLS[id].get("category", &"") == cat:
				ids.append(id)
		out.append([SkillDefs.CATEGORIES[cat], _by_rarity(ids)])
	return out


# 照稀有度由低到高排；同稀有度維持資料表的順序
static func _by_rarity(ids: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for r: StringName in ItemDefs.RARITIES:
		for id in ids:
			if ItemDefs.ITEMS[id].rarity == r:
				out.append(id)
	return out


# 作弊開關：開 / 關一種（CHEATS 的 key）
static func set_cheat(world: World, id: StringName, on: bool) -> void:
	if on:
		world.practice_cheats[id] = true
	else:
		world.practice_cheats.erase(id)
	if id == &"invincible":
		for p in world.player_list:
			p.is_untouchable = on


# 每步開頭（World.step）：照開著的開關把玩家補回去。重新開始會換一批玩家，所以每步都設
static func apply_cheats(world: World) -> void:
	if world.practice_cheats.is_empty():
		return
	for p in world.player_list:
		if world.practice_cheats.has(&"mana"):
			p.mana = p.max_mana()
		if world.practice_cheats.has(&"cooldown"):
			world.cooldowns.reset_suffix(p.cd(""))
			p.slots.heal.charges = p.slots.heal.def.charges
		p.is_untouchable = world.practice_cheats.has(&"invincible")


# 生怪照第 floor_num 層第 stage 小關的成長（同正式遊戲的難度 + 小關成長，EventDefs.difficulty_mul）：生命、攻擊各乘多少
static func stage_mul(floor_num: int, stage: int) -> Dictionary:
	var d: Dictionary = EventDefs.DIFFICULTY
	var difficulty: float = (floor_num - 1) * d.per_floor + (stage - 1) * d.per_stage
	return EventDefs.difficulty_mul(difficulty, (stage - 1) + (floor_num - 1) * MapGenDefs.STAGES.size())


# 選第幾層第幾小關：之後生的怪照那一關的成長，場地換成那一層的外觀（一樣的空地，場上的東西不動）
static func set_stage(world: World, floor_num: int, stage: int) -> void:
	world.practice_stage = Vector2i(floor_num, stage)
	var want := MapDefs.practice_map(floor_num)
	if MapDefs.is_practice(world.map_id) and world.map_id != want:
		world.load_map(want)


# 清空背包：道具、技能、修飾全部拿掉，技能等級歸零（武器與袋子留著）
static func clear_inventory(p: Player) -> void:
	p.clear_items()
	p.skill_levels.clear()


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
