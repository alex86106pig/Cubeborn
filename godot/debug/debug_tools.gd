# 除錯與自動驗證用的操作（非正式系統；2026-10-25 從 main.gd 搬出來）：
#   開場布置（--horde、--player-at、--at-dig、--exit-open、--ghost、--elites）、F3 移速 +50%、F4 放入下一個道具、F5 清空道具
# 這些直接改模擬狀態、不經過 InputCmd，所以只在單機（或開局前的權威端）使用
class_name DebugTools
extends RefCounted

var _item_index := 0


# 開局後照啟動參數布置場面：效能量測的怪群、站位、挖墳事件、冤魂、魔法 / 稀有怪、武器測試木樁
static func setup_run(world: World, me: Player, args: LaunchArgs) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5   # 固定位置，每次量測可以比較
	if args.player_at != Vector2.INF:   # 先移動玩家，--horde 才會生在新位置周圍
		me.pos = MapDefs.to_world(world.map, args.player_at)
		me.prev_pos = me.pos
	# --horde=N：玩家周圍 4~16 隨機生 N 隻（骷髏戰士 80%、弓手 20%），照常爬出後追玩家
	for i in args.horde:
		var type := &"archer" if rng.randf() < 0.2 else &"grunt"
		var a := rng.randf() * TAU
		var at := world.nav.nearest_walkable(me.pos + Vector2(sin(a), cos(a)) * rng.randf_range(4.0, 16.0))
		world.spawner.spawn_at(world, type, at)
	if args.at_dig:
		me.pos = world.event.point + (world.spawn_point - world.event.point).normalized() * 1.5
		me.prev_pos = me.pos
	if args.exit_open:
		world.event._start(world)
		world.event.state = DigEvent.OPEN
		world.event.progress = 1.0
	if args.ghost:
		var g := world.spawner.spawn_at(world, &"ghost", world.nav.nearest_walkable(me.pos + Vector2(-1.0, -1.0).normalized() * 5.0))
		g.ghost_of = -1
	if args.weapon_test:
		Spawner.spawn_training_dummies(world, me.pos)
	if args.elites:
		var up := Vector2(-1.0, -1.0).normalized()   # 等距相機的畫面上方
		var side := Vector2(1.0, -1.0).normalized()
		var list := [[MonsterRarityDefs.RARE, up * 5.0], [MonsterRarityDefs.MAGIC, up * 4.0 + side * 3.0], [MonsterRarityDefs.MAGIC, up * 4.0 - side * 3.0]]
		for r: Array in list:
			var e := world.spawner.spawn_at(world, &"grunt", world.nav.nearest_walkable(me.pos + r[1]))
			Spawner.roll_rarity(world, e, r[0])


# F4：依道具清單順序，每按一次放一個道具進背包（循環；放不下就提示背包滿了）
func add_next_item(world: World, player: Player) -> void:
	if player == null or player.is_dead:
		return
	var ids := ItemDefs.item_ids()
	var before := world.events.size()   # 上一步的事件已經送過，只送這次新增的
	player.add_item(ids[_item_index % ids.size()])
	_item_index += 1
	GameEvents.emit_all(world.events.slice(before))


# F3：切換玩家「移速 +50%」，驗證屬性系統用
static func toggle_speed(player: Player) -> void:
	if player == null:
		return
	if player.stats.has_source(&"debug"):
		player.remove_stat_source(&"debug")
	else:
		player.set_stat_source(&"debug", [[&"move_speed", Stats.PCT, Config.DEBUG.speed_bonus]])


# F5：清空身上的道具
static func clear_items(player: Player) -> void:
	if player != null:
		player.clear_items()
