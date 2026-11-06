# 按 F 互動得到的東西（許家慶 2026-11-06：好幾個疊在一起時角色旁邊出現列表，滾輪 / 上下鍵挑要跟哪個互動，參考原神撿東西）
# options 列出這位玩家現在按得到的：地上的道具、遺物（含鐵砧）、寶箱、鍛造祭壇、假裝 NPC 的守墓人、出口（挖完的墳墓 / 小關的門）、挖墳點；
# 由近到遠。畫面層的列表（ui/interact_list.gd）挑一個，按 F 時跟著輸入送 [InputCmd.OP_INTERACT, id]；房主用 use 再檢查一次搆不搆得到
# 救人不在列表裡：倒地的隊友旁按住 F 一律先救（Player 動作層 Ready）
class_name Interactables

const EXIT := -2   # 出口：挖完的墳墓旁、小關的門前（DigEvent.can_exit）
const DIG := -3    # 挖墳點（按住 F，DigEvent.can_dig）


# [{ id, kind, gap }]：id 是實體 id（出口、挖墳點用 EXIT / DIG）、kind 是 &"pickup" / &"relic" / &"chest" / &"forge" / &"keeper" / &"exit" / &"dig"、
# gap 是身體邊緣的距離（出口、挖墳點用到中心的距離）
static func options(world: World, p: Player) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if p == null or p.is_dead or p.is_downed or p.descended:
		return out
	for e in world.pickups:
		if not e.is_removed and world.can_reach(p, e):
			out.append({"id": e.id, "kind": &"pickup", "gap": world.reach_gap(p, e)})
	for e in world.relics:
		if not e.is_removed and not (e as Relic).taken.has(p.peer_id) and world.can_reach(p, e):
			out.append({"id": e.id, "kind": &"relic", "gap": world.reach_gap(p, e)})
	for e in world.chests:
		if not e.is_removed and not (e as Chest).opened and world.can_reach(p, e):
			out.append({"id": e.id, "kind": &"chest", "gap": world.reach_gap(p, e)})
	for e in world.forges:
		if not e.is_removed and world.can_reach(p, e):
			out.append({"id": e.id, "kind": &"forge", "gap": world.reach_gap(p, e)})
	var keeper := world.entities.get(world.boss_id) as Gravekeeper
	if keeper != null and keeper.can_talk(p):
		out.append({"id": keeper.id, "kind": &"keeper", "gap": world.reach_gap(p, keeper)})
	var ev := world.event
	if ev.can_exit(world, p) and not ev.is_voting():
		out.append({"id": EXIT, "kind": &"exit", "gap": _exit_gap(world, p)})
	if ev.can_dig(world, p) and not p.is_digging():
		out.append({"id": DIG, "kind": &"dig", "gap": p.pos.distance_to(ev.point)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.gap < b.gap)
	return out


static func _exit_gap(world: World, p: Player) -> float:
	var door := DigEvent.door_at(world, p)
	if door >= 0:
		return p.pos.distance_to(MapDefs.to_world(world.map, DigEvent.doors(world)[door].reach))
	return p.pos.distance_to(world.event.point)


# 跟 id 那一個互動（房主；還搆得到才做）：做了回傳 true。挖墳點不在這裡做（按住 F 由動作層 Ready 開挖），回傳 false
static func use(world: World, p: Player, id: int) -> bool:
	if id == EXIT:
		if not world.event.can_exit(world, p):
			return false
		world.event.request_exit(world, p)
		return true
	if id == DIG:
		return false
	var e: Entity = world.entities.get(id)
	if e == null or e.is_removed or not world.can_reach(p, e):
		return false
	if e is ItemPickup:
		p.loadout.take_pickup(p, e as ItemPickup)
	elif e is Relic:
		if (e as Relic).taken.has(p.peer_id):
			return false
		(e as Relic).open_for(p)
	elif e is Chest:
		if (e as Chest).opened:
			return false
		(e as Chest).try_open(p)
	elif e is Gravekeeper:
		if not (e as Gravekeeper).can_talk(p):
			return false
		(e as Gravekeeper).talk()
	elif world.forges.has(e):
		world.emit_event("forge:opened", {"player_id": p.id, "forge_id": e.id})   # 本機玩家的畫面打開背包（main.gd）
	else:
		return false
	return true
