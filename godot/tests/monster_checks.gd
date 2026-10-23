# 怪物稀有度、詞條與怪群（D5）的自動檢查，由 tests/check.gd 呼叫；每個函式回傳 "" = 通過，否則是失敗原因
class_name MonsterChecks

const DT := 1.0 / 60.0
const EPS := 1e-3

static var _made: Array[World] = []   # 建立過的 World：檢查中途失敗也能在最後 cleanup() 切斷循環參照


static func cleanup() -> void:
	for w in _made:
		w.clear()
	_made.clear()


static func _world(map_id: StringName = &"test_arena", packs := false, seed_value := 12345, spawner := false) -> World:
	var w := World.new(map_id)
	w.spawn_packs = packs
	w.reset(seed_value)
	w.spawner.finished = not spawner
	_made.append(w)
	return w


static func _step(w: World, n: int, keep_hp := false) -> void:
	var p: Player = w.players[World.HOST_PEER_ID]
	for i in n:
		w.step({World.HOST_PEER_ID: InputCmd.new()}, DT)
		if keep_hp:
			p.hp = p.max_hp


static func _grunt(w: World, at: Vector2, rarity: StringName, affixes: Array = []) -> Enemy:
	var e := w.spawner.spawn_at(w, &"grunt", at)
	e.set_rarity(rarity, affixes, "")
	e.apply_rarity_stats()
	return e


# ───────── 稀有度 ─────────

static func check_rarity() -> String:
	var w := _world()
	var rare := _grunt(w, Vector2(0, 10), MonsterRarityDefs.RARE)
	if absf(rare.max_hp - 180.0) > EPS or absf(rare.hp - 180.0) > EPS or absf(rare.damage_mul - 1.5) > EPS:
		return "稀有骷髏：生命 %.1f / %.1f、攻擊力 ×%.2f，預期 180 / 180、×1.5" % [rare.hp, rare.max_hp, rare.damage_mul]
	if absf(rare.radius - 0.54) > EPS or absf(rare.body_height - 1.95 * 1.2) > EPS:
		return "稀有骷髏體型：半徑 %.3f、身高 %.3f，預期 0.54、2.34" % [rare.radius, rare.body_height]
	var magic := _grunt(w, Vector2(5, 10), MonsterRarityDefs.MAGIC)
	if absf(magic.max_hp - 72.0) > EPS or absf(magic.damage_mul - 1.2) > EPS or absf(magic.radius - 0.45) > EPS:
		return "魔法骷髏：生命 %.1f、攻擊力 ×%.2f、半徑 %.2f，預期 72、×1.2、0.45" % [magic.max_hp, magic.damage_mul, magic.radius]
	# 詞條數：魔法 1~2（兩種都會出現）、稀有 3，不重複；稀有怪有名字
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 2000:
		for r: StringName in [MonsterRarityDefs.MAGIC, MonsterRarityDefs.RARE]:
			var list := MonsterRarityDefs.roll_affixes(MonsterRarityDefs.affix_count(r, rng), rng)
			var want: Array = MonsterRarityDefs.RARITIES[r].affixes
			if list.size() < want[0] or list.size() > want[1]:
				return "%s 抽到 %d 條詞條" % [r, list.size()]
			var uniq := {}
			for id in list:
				uniq[id] = true
			if uniq.size() != list.size():
				return "詞條重複：%s" % [list]
			if r == MonsterRarityDefs.MAGIC:
				seen[list.size()] = true
	if not (seen.has(1) and seen.has(2)):
		return "魔法怪 2000 次只抽到 %s 條" % [seen.keys()]
	var named := w.spawner.spawn_at(w, &"grunt", Vector2(-5, 10))
	Spawner.roll_rarity(w, named, MonsterRarityDefs.RARE)
	if named.rare_name == "" or named.affixes.size() != 3:
		return "稀有怪應有名字與 3 條詞條：「%s」%s" % [named.rare_name, named.affixes]
	# 每群：魔法 1~2 隻（平均 1.5）、稀有 25%（20000 群，誤差 ±1.5%）
	var rares := 0
	var magics := 0
	for i in 20000:
		var list := MonsterRarityDefs.roll_pack_rarities(10, rng)
		var m := list.count(MonsterRarityDefs.MAGIC)
		var r := list.count(MonsterRarityDefs.RARE)
		if m < 1 or m > 2 or r > 1:
			return "一群有 %d 隻魔法、%d 隻稀有" % [m, r]
		magics += m
		rares += r
	if absf(rares / 20000.0 - 0.25) > 0.015 or absf(magics / 20000.0 - 1.5) > 0.03:
		return "20000 群：稀有 %.1f%%（預期 25%%）、每群魔法 %.2f 隻（預期 1.5）" % [rares / 200.0, magics / 20000.0]
	return ""


# ───────── 詞條 ─────────

static func check_affixes() -> String:
	var w := _world()
	var g := w.spawner.spawn_at(w, &"grunt", Vector2(0, 10))
	var s0 := g.speed
	g.set_rarity(MonsterRarityDefs.NORMAL, [&"swift", &"mighty"])
	g.apply_rarity_stats()
	if absf(g.speed - s0 * 1.3) > EPS or absf(g.damage_mul - 1.3) > EPS:
		return "迅捷 / 強壯：移速 %.3f（預期 %.3f）、攻擊力 ×%.2f（預期 ×1.3）" % [g.speed, s0 * 1.3, g.damage_mul]
	var armored := _grunt(w, Vector2(5, 10), MonsterRarityDefs.NORMAL, [&"armored"])
	var dealt := armored.take_damage(20.0, Vector2(0, 1), 0.0, 0)
	if dealt != 15:
		return "厚皮：受到 20 傷害扣 %d，預期 15" % dealt
	# 再生：每秒 2% 最大生命（36 → 0.72）
	var regen := _grunt(w, Vector2(-5, 10), MonsterRarityDefs.NORMAL, [&"regen"])
	regen.hp = 10.0
	_step(w, 60)
	if absf(regen.hp - 10.72) > 0.01:
		return "再生：1 秒後生命 %.3f，預期 10.72" % regen.hp

	# 吸血：揮砍 12 → 回 2.4
	var w2 := _world()
	var vamp := _grunt(w2, Vector2(0, 1.2), MonsterRarityDefs.NORMAL, [&"vampiric"])
	vamp.hp = 20.0
	var p2: Player = w2.players[World.HOST_PEER_ID]
	for i in 300:
		_step(w2, 1)
		if p2.hp < p2.max_hp:
			break
	if p2.hp >= p2.max_hp or absf(vamp.hp - 22.4) > 0.01:
		return "吸血：玩家生命 %.0f、骷髏生命 %.2f（預期打中 12 後回到 22.4）" % [p2.hp, vamp.hp]

	# 狂暴：生命低於 30% 時移速、狀態機速度 ×1.4
	var w3 := _world()
	var fr := _grunt(w3, Vector2(0, 12), MonsterRarityDefs.NORMAL, [&"frenzy"])
	_step(w3, 50)
	var fs := fr.speed
	fr.hp = 36.0 * 0.3 + 0.5
	_step(w3, 1)
	if fr.action_speed != 1.0:
		return "狂暴：生命 31% 就觸發了"
	fr.hp = 36.0 * 0.3 - 0.5
	_step(w3, 1)
	if absf(fr.action_speed - 1.4) > EPS or absf(fr.speed - fs * 1.4) > EPS:
		return "狂暴：生命 29%% 時狀態機速度 ×%.2f、移速 %.3f（預期 ×1.4、%.3f）" % [fr.action_speed, fr.speed, fs * 1.4]

	# 死亡爆炸：死時預警、0.8 秒後半徑 2.2 爆炸 20 傷害；3.0 外炸不到
	for dist: float in [1.5, 3.0]:
		var w4 := _world()
		var p4: Player = w4.players[World.HOST_PEER_ID]
		var vol := _grunt(w4, Vector2(0, dist), MonsterRarityDefs.NORMAL, [&"volatile"])
		vol.die()
		var warned := w4.events.any(func(ev: Dictionary) -> bool: return ev.name == "fx:telegraph" and absf(ev.radius - 2.2) < EPS)
		if not warned:
			return "死亡爆炸：死的時候沒有 2.2 的預警圈"
		var hit_step := -1
		for i in 60:
			_step(w4, 1)
			for ev in w4.events:
				if ev.name == "entity:damaged" and ev.target_id == p4.id:
					if ev.amount != 20:
						return "死亡爆炸傷害 %d，預期 20" % ev.amount
					hit_step = i + 1
			if hit_step > 0:
				break
		if dist < 2.0 and (hit_step < 47 or hit_step > 50):
			return "死亡爆炸：第 %d 步炸到玩家，預期約第 48 步（0.8 秒）" % hit_step
		if dist > 2.0 and hit_step > 0:
			return "死亡爆炸：距離 3.0 的玩家也被炸到"

	# 召喚：醒來 8 秒後叫 2 隻骷髏戰士，同時最多 6 隻
	var w5 := _world()
	var sm := _grunt(w5, Vector2(0, 12), MonsterRarityDefs.NORMAL, [&"summoner"])
	var minions := func() -> int:
		var n := 0
		for e in w5.enemies:
			if e is Enemy and (e as Enemy).summoner_id == sm.id and not e.is_dead:
				n += 1
		return n
	_step(w5, roundi((0.7 + 8.0) / DT) - 3, true)
	if minions.call() != 0:
		return "召喚：8.7 秒前就叫出 %d 隻" % minions.call()
	_step(w5, 6, true)
	if minions.call() != 2:
		return "召喚：8.7 秒後應有 2 隻，實際 %d" % minions.call()
	_step(w5, roundi(25.0 / DT), true)
	if minions.call() != 6:
		return "召喚：33.7 秒後應有 6 隻（上限），實際 %d" % minions.call()
	return ""


# ───────── 怪群 ─────────

static func check_packs() -> String:
	var w := _world(&"graveyard_a", true)
	var c: Dictionary = MonsterRarityDefs.PACKS
	var n := w.packs.size()
	if n < c.count[0] or n > c.count[1]:
		return "地圖 A 有 %d 群，預期 12~20" % n
	for ev in w.events:
		if ev.name == "sfx:cue" and ev.cue == "enemySpawn":
			return "開場散放怪群時播了爬出音效"
	var start := {}
	var total := 0
	for i in n:
		var pk: Dictionary = w.packs[i]
		var center: Vector2 = pk.center
		if center.distance_to(w.spawn_point) < c.min_spawn_distance - EPS:
			return "第 %d 群離出生點只有 %.1f" % [i, center.distance_to(w.spawn_point)]
		for j in i:
			if center.distance_to(w.packs[j].center) < c.min_pack_distance - EPS:
				return "第 %d、%d 群只相距 %.1f" % [j, i, center.distance_to(w.packs[j].center)]
		var ids: Array = pk.ids
		if ids.size() < c.size[0] or ids.size() > c.size[1]:
			return "第 %d 群有 %d 隻，預期 6~15" % [i, ids.size()]
		var magic := 0
		var rare := 0
		for id: int in ids:
			var e: Enemy = w.entities[id]
			if e.pack_id != i or not e.dormant or not e.fsm.is_in(&"dormant") or e.wave_member:
				return "第 %d 群的 %d 號：pack_id %d、休眠 %s、狀態 %s" % [i, id, e.pack_id, e.dormant, e.fsm.current_name]
			if not w.nav.is_walkable(e.pos) or not w.nav.same_region(e.pos, w.spawn_point):
				return "第 %d 群的 %d 號在 %s：不可走或走不到出生點" % [i, id, e.pos]
			magic += 1 if e.rarity == MonsterRarityDefs.MAGIC else 0
			rare += 1 if e.rarity == MonsterRarityDefs.RARE else 0
			start[id] = e.pos
		if magic < 1 or magic > 2 or rare > 1:
			return "第 %d 群有 %d 隻魔法、%d 隻稀有" % [i, magic, rare]
		total += ids.size()
	# 玩家沒靠近：3 秒都不走（速度 0）；成員一開始若有重疊，碰撞分離推開後就完全靜止
	_step(w, 120)
	var settled := {}
	for id: int in start:
		settled[id] = (w.entities[id] as Enemy).pos
	_step(w, 60)
	for id: int in start:
		var e: Enemy = w.entities[id]
		if not e.dormant or e.velocity != Vector2.ZERO or e.pos.distance_to(settled[id]) > EPS:
			return "玩家沒靠近，%d 號就醒了或在走（第 2~3 秒移動 %.3f）" % [id, e.pos.distance_to(settled[id])]
	# 走到第 0 群 11 單位內：中心 12 以內的群整群醒來，其他的照睡
	var p: Player = w.players[World.HOST_PEER_ID]
	var near := w.nav.nearest_walkable(w.packs[0].center + Vector2(0, 11))
	if near.distance_to(w.packs[0].center) > c.wake_distance:
		near = w.packs[0].center
	p.pos = near
	_step(w, 1)
	for i in n:
		var should: bool = w.packs[i].center.distance_to(p.pos) <= c.wake_distance
		if w.packs[i].awake != should:
			return "玩家離第 %d 群 %.1f，醒來 = %s" % [i, w.packs[i].center.distance_to(p.pos), w.packs[i].awake]
		for id: int in w.packs[i].ids:
			var e: Enemy = w.entities.get(id)
			if e != null and e.dormant == should:
				return "第 %d 群的 %d 號沒跟著整群%s" % [i, id, "醒來" if should else "休眠"]
			if e != null and e.fixed == should:
				return "第 %d 群的 %d 號 fixed 應跟著休眠（v0.30.0）：%s" % [i, id, e.fixed]
			if e != null and should and e.fsm.is_in(&"dormant"):
				return "第 %d 群醒來同一步就該開始追，%d 號還在 dormant" % [i, id]
	# 遠處被打：整群醒來
	for i in n:
		if not w.packs[i].awake:
			var first: Enemy = w.entities[w.packs[i].ids[0]]
			first.take_damage(1.0, Vector2(0, 1), 0.0, p.id)
			for id: int in w.packs[i].ids:
				if (w.entities[id] as Enemy).dormant:
					return "第 %d 群被打一隻，%d 號沒醒" % [i, id]
			break
	# 決定性：同種子散放的位置一樣
	var w2 := _world(&"graveyard_a", true)
	if w2.packs.size() != n or w2.packs[n - 1].center != w.packs[n - 1].center:
		return "同種子兩次散放的怪群不同"
	return ""


# 蒙皮小怪（D5 效能）：骷髏戰士 / 弓手每隻 ≤ 2 個網格、三角形數與原本的零件相同；關節寫進骨架
static func check_skinned_rig() -> String:
	for kind: StringName in [&"grunt", &"archer"]:
		var old := DarkFantasy.character(kind)
		var rig := DarkFantasy.skinned_character(kind)
		var before := 0
		var after := 0
		for mi in PartKit.mesh_instances(old):
			before += (mi.mesh as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		for mi in PartKit.mesh_instances(rig):
			after += (mi.mesh as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		var count := rig.mesh_count()
		rig.arm_r.rotation = Vector3(-1.2, 0.3, 0.0)
		rig.flush()
		var want := Basis.from_euler(Vector3(-1.2, 0.3, 0.0), EULER_ORDER_YXZ)
		var got := rig.skeleton.get_bone_pose(3).basis
		var pos := rig.skeleton.get_bone_pose(3).origin
		var want_pos: Vector3 = rig.arm_r.position
		old.free()
		rig.free()
		if count > 2:
			return "%s 蒙皮版有 %d 個網格（應 ≤ 2）" % [kind, count]
		if before != after:
			return "%s 蒙皮版頂點 %d，原本零件 %d" % [kind, after, before]
		if not got.is_equal_approx(want) or not pos.is_equal_approx(want_pos):
			return "%s 右臂的骨頭姿勢沒跟著關節" % kind
	return ""


# 連線：稀有度、詞條、名字、體型傳到客戶端；最大生命用快照的數字（不重複乘稀有度）
static func check_net_rarity() -> String:
	var w := _world()
	var e := w.spawner.spawn_at(w, &"grunt", Vector2(0, 8))
	Spawner.roll_rarity(w, e, MonsterRarityDefs.RARE)
	var wire: Array = bytes_to_var(var_to_bytes(NetCodec.encode_entity(e)))
	var cw := World.new(&"test_arena")
	cw.is_authority = false
	_made.append(cw)
	var m := NetCodec.create_entity(cw, NetCodec.decode_entity(wire)) as Enemy
	if m == null or m.rarity != e.rarity or m.affixes != e.affixes or m.rare_name != e.rare_name:
		return "客戶端的稀有度 / 詞條 / 名字不同：%s %s「%s」" % [m.rarity if m else &"", m.affixes if m else [], m.rare_name if m else ""]
	if absf(m.radius - e.radius) > EPS or absf(m.max_hp - e.max_hp) > EPS:
		return "客戶端半徑 %.3f / 最大生命 %.1f，房主 %.3f / %.1f" % [m.radius, m.max_hp, e.radius, e.max_hp]
	var plain := w.spawner.spawn_at(w, &"grunt", Vector2(3, 8))
	if (NetCodec.encode_entity(plain)[5] as Array).size() != 1:
		return "普通怪的快照不該帶稀有度欄位"
	return ""
