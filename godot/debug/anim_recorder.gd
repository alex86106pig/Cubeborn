# 錄動作（除錯用，動作表 PoseGallery 與動畫檢視器 AnimViewer 共用）：用真的模擬跑一段，錄下每一步的 anim、速度、位置。
# 一段 = 一列 { name（顯示的名字）, key（英文 id）, subject（Player / Enemy）, frames（[{anim, vel, pos, facing, height, ground, events}]）, samples（動作表取的 8 步）, make }；
# make() 回傳一隻新的角色 { rig, anim（Animator / EnemyAnimator） }，從第 0 步重播到第 i 步就是第 i 步的姿勢（動畫器的平滑也算進去）。
# 用完要 clear()：錄的時候建的 World 有循環參照
class_name AnimRecorder
extends RefCounted

const COLS := 8
const DT := Config.FIXED_DT
const PLAYER_WEAPONS: Array[StringName] = [&"swordShield", &"staff", &"shortbow", &"longbow", &"dagger", &"scepter", &"torch", &"shovel"]
const ENEMY_MODELS: Array[StringName] = [&"grunt", &"archer", &"spearman", &"zombie", &"bloater", &"hound", &"spider", &"beetle", &"bone_wheel", &"boss", &"gravekeeper", &"werewolf", &"bone_general", &"bone_colossus"]
const BOSS_MOVES := {
	&"boss": [0, [&"slam", &"charge", &"summon", &"cleave"]],
	&"gravekeeper": [0, [&"shovel", &"dig", &"lantern", &"whistle", &"scoop"]],
	&"werewolf": [1, [&"claw", &"leap", &"howl"]],
	&"bone_general": [0, [&"slam", &"charge", &"cleave"]],
	&"bone_colossus": [1, [&"spikes", &"sweep", &"wheel", &"devour"]],
}
const BOSS_KIND := {&"werewolf": &"gravekeeper", &"bone_colossus": &"bone_general"}   # 第二型態的模型 → 種類
const MODEL_NAMES := {&"werewolf": "墓園狼人", &"bone_colossus": "萬骨聚合體"}
const PLAYER_ACTIONS := {
	"idle": "待機", "run": "跑", "sprint": "衝刺跑（Ctrl）", "attack": "普攻連段", "attack+move": "邊走邊普攻", "special": "右鍵",
	"roll": "翻滾", "jump": "跳", "potion": "喝藥水", "stagger": "受擊硬直", "knocked": "被擊倒", "dead": "倒地",
}
const SKILLS_PER_PAGE := 6
const AI_SECONDS := 12.0   # 怪物照 AI 自己打的錄幾秒

var _worlds: Array[World] = []


func clear() -> void:
	for w in _worlds:
		w.clear()
	_worlds.clear()


# 可以看的角色：{ id, name }（id 給 rows 用：player-<武器>、enemy-<模型>）
static func subjects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for w: StringName in PLAYER_WEAPONS:
		out.append({"id": "player-%s" % w, "name": "玩家・%s" % WeaponDefs.WEAPONS[w].get("name", w)})
	for m: StringName in ENEMY_MODELS:
		var kind: StringName = BOSS_KIND.get(m, m)
		out.append({"id": "enemy-%s" % m, "name": MODEL_NAMES.get(m, EnemyDefs.ENEMIES[kind].get("name", m))})
	return out


# 戰技（category 是 attack 的技能）
static func skill_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in SkillDefs.SKILLS:
		if SkillDefs.SKILLS[id].get("category", &"") == &"attack":
			ids.append(id)
	return ids


# 錄一個角色的全部動作：player-<武器>（基本動作 + 第一把武器是它的戰技）、enemy-<模型>、skills-<頁>（動作表用，每頁 6 招）
func rows(id: String, with_skills := true) -> Array:
	if id.begins_with("player-"):
		var weapon := StringName(id.trim_prefix("player-"))
		var out := player_rows(weapon)
		if with_skills:
			out.append_array(skill_rows(skill_ids().filter(func(s: StringName) -> bool: return SkillDefs.SKILLS[s].weapons[0] == weapon)))
		return out
	if id.begins_with("skills-"):
		var page := id.trim_prefix("skills-").to_int()
		var ids := skill_ids()
		return skill_rows(ids.slice((page - 1) * SKILLS_PER_PAGE, mini(page * SKILLS_PER_PAGE, ids.size())))
	if id.begins_with("enemy-"):
		return enemy_rows(StringName(id.trim_prefix("enemy-")))
	push_warning("AnimRecorder：沒有這個角色 %s" % id)
	return []


func _new_world() -> World:
	var w := World.new(&"test_arena")
	w.spawn_packs = false
	w.reset(7)
	w.spawner.finished = true
	_worlds.append(w)
	return w


static func _cmd(move: Vector2, buttons: int = 0) -> InputCmd:
	var c := InputCmd.new()
	c.move = move
	c.aim = Vector2(0, 5)
	c.buttons = buttons
	return c


func _player(w: World, weapon: StringName) -> Player:
	var p: Player = w.players[World.HOST_PEER_ID]
	p.equip_weapon(weapon)
	p.stats.set_base(&"max_hp", 1e6)
	p.hp = 1e6
	return p


# 跑 steps 步、每步錄下 anim、速度、位置；cmd(i) 給第 i 步的輸入
static func _record(w: World, e: Entity, steps: int, cmd: Callable) -> Array:
	var out := []
	for i in steps:
		var c: InputCmd = cmd.call(i)
		w.step({World.HOST_PEER_ID: c}, DT)
		out.append({"anim": e.anim.duplicate(true), "vel": e.velocity, "pos": e.pos, "facing": e.facing, "height": e.height,
			"ground": e.ground_height, "events": w.events.duplicate(true)})   # events：這一步的事件（檢視器拿來放特效）
	return out


static func even(from: int, to: int) -> Array[int]:
	var out: Array[int] = []
	for c in COLS:
		out.append(from + roundi((to - from) * float(c) / (COLS - 1)))
	return out


# ───────── 玩家 ─────────

func player_rows(weapon: StringName) -> Array:
	var rows := []
	var specs := [
		["idle", 40, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO)],
		["run", 60, func(_i: int) -> InputCmd: return _cmd(Vector2(0, 1))],
		["sprint", 60, func(i: int) -> InputCmd: return _cmd(Vector2(0, 1), InputCmd.BTN_RUN if i == 0 else 0)],
		["attack", 100, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO, InputCmd.BTN_ATTACK)],
		["attack+move", 80, func(_i: int) -> InputCmd: return _cmd(Vector2(1, 0), InputCmd.BTN_ATTACK)],
		["special", 70, func(i: int) -> InputCmd: return _cmd(Vector2.ZERO, (InputCmd.BTN_SPECIAL | InputCmd.BTN_SPECIAL_HELD) if i < 2 else 0)],
		["roll", 40, func(i: int) -> InputCmd: return _cmd(Vector2(0, 1), InputCmd.BTN_ROLL if i == 2 else 0)],
		["jump", 50, func(i: int) -> InputCmd: return _cmd(Vector2.ZERO, InputCmd.BTN_JUMP if i == 2 else 0)],
		["potion", 45, func(i: int) -> InputCmd: return _cmd(Vector2.ZERO, InputCmd.slot_bit(ActiveSlots.HEAL_INDEX) if i == 2 else 0)],
	]
	for spec: Array in specs:
		var w := _new_world()
		var p := _player(w, weapon)
		if spec[0] == "potion":
			p.hp = p.max_hp * 0.5
		_record(w, p, 20, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))   # 先站穩
		var frames := _record(w, p, spec[1], spec[2])
		rows.append(_player_row(spec[0], p, frames))
	for extra: String in ["stagger", "knocked", "dead"]:
		var w := _new_world()
		var p := _player(w, weapon)
		_record(w, p, 20, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))
		match extra:
			"stagger":
				p.action.change(&"stagger")
			"knocked":
				p.knock_down(1.0)
			"dead":
				p.hp = 0.0
				p.die(0)
		var frames := _record(w, p, 45, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))
		rows.append(_player_row(extra, p, frames))
	return rows


func _player_row(key: String, p: Player, frames: Array, last := -1) -> Dictionary:
	return {"key": key, "name": PLAYER_ACTIONS.get(key, key), "subject": p, "frames": frames,
		"samples": even(0, frames.size() - 1 if last < 0 else last),
		"make": func() -> Dictionary:
			var rig := DarkFantasy.player_character(p.class_id)
			return {"rig": rig, "anim": Animator.new(rig)}}


# 戰技：先真的在模擬裡放（身前擺一隻打不死的骷髏當目標，位移、打中的火花、爆炸都錄得到）；放不出來的（例如條件不符）
# 才退回假的：站穩錄好 anim，再每一步把 skill / skill_time 塞進去（衝刺類給往前的速度與位置，腳才會跑）
func skill_rows(ids: Array) -> Array:
	var rows := []
	for id: StringName in ids:
		var real := _cast_row(id)
		if not real.is_empty():
			rows.append(real)
			continue
		var def: Dictionary = SkillDefs.SKILLS[id]
		var w := _new_world()
		var p := _player(w, def.weapons[0])
		var base := _record(w, p, 20, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))
		var idle: Dictionary = base[-1].anim
		var total := SkillDefs.pose_time(id)
		var steps := roundi(total / DT) + 6
		var frames := []
		var pos: Vector2 = p.pos
		for s in steps:
			var t := s * DT
			var a := idle.duplicate(true)
			var vel := Vector2.ZERO
			if t < total:
				a["skill"] = id
				a["skill_time"] = t
				if def.behavior in [&"dash", &"burrow"] and t < def.time:
					vel = Vector2(0, def.distance / def.time)
					a["loco"] = &"move"
			pos += vel * DT
			frames.append({"anim": a, "vel": vel, "pos": pos, "facing": p.facing, "height": p.height, "ground": p.ground_height, "events": []})
		var row := _player_row(String(id), p, frames, roundi(total / DT))
		row.name = "戰技・%s" % ItemDefs.ITEMS[id].get("name", id) if ItemDefs.ITEMS.has(id) else String(id)
		rows.append(row)
	return rows


func _cast_row(id: StringName) -> Dictionary:
	var def: Dictionary = SkillDefs.SKILLS[id]
	var w := _new_world()
	var p := _player(w, def.weapons[0])
	var bag: Dictionary = p.loadout.key_bags()[0]
	var where := p.loadout.bags.find(bag)
	var spot := p.loadout.container(where).find_spot(id)
	if spot.is_empty() or p.loadout.add_item(p, id, spot, 0, where) == &"":
		return {}
	var dummy := _spawn(w, &"grunt", p.pos + Vector2(0, 1.6), 0)
	dummy.stats.set_base(&"max_hp", 1e6)
	dummy.hp = 1e6
	var lead := _record(w, p, 20, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))
	p.mana = p.max_mana()
	var steps := roundi(SkillDefs.pose_time(id) / DT) + 12
	var frames := _record(w, p, steps, func(i: int) -> InputCmd: return _cmd(Vector2.ZERO, InputCmd.slot_bit(0) if i == 0 else 0))
	if p.cast_log.get(id, [0, 0])[0] < 1:
		return {}
	var row := _player_row(String(id), p, lead + frames)
	row.start = lead.size()
	row.samples = even(lead.size(), lead.size() + roundi(SkillDefs.pose_time(id) / DT))
	row.name = "戰技・%s" % ItemDefs.ITEMS[id].get("name", id) if ItemDefs.ITEMS.has(id) else String(id)
	return row


# ───────── 怪物 ─────────

# AI 自己打（玩家站在前面不動、打不死）的每個狀態取第一次出現的那段（最多 8 段）＋ Boss 每一招（強制出招）＋ 死掉
func enemy_rows(model: StringName) -> Array:
	var kind: StringName = BOSS_KIND.get(model, model)
	var rows := []
	var spec: Array = BOSS_MOVES.get(model, [0, []])
	var form: int = spec[0]
	var w := _new_world()
	var p := _player(w, &"swordShield")
	var e := _spawn(w, kind, p.pos + Vector2(0, 5), form)
	var frames := _record(w, e, roundi(AI_SECONDS / DT), func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))
	var seen := {}
	var start := 0
	for i in frames.size() + 1:
		var st: StringName = frames[i].anim.state if i < frames.size() else &""
		if i == frames.size() or st != frames[start].anim.state:
			var name: StringName = frames[start].anim.state
			if not seen.has(name) and i - start >= 3 and rows.size() < 8:
				seen[name] = true
				var end := mini(i - 1, start + roundi(2.5 / DT))
				rows.append(_enemy_row(String(name), e, model, frames.slice(0, end + 1), even(start, end), start))
			start = i
	for move: StringName in spec[1]:
		if seen.has(move):
			continue
		var w2 := _new_world()
		var p2 := _player(w2, &"swordShield")
		var b := _spawn(w2, kind, p2.pos + Vector2(0, 6), form)
		var lead := _record(w2, b, roundi(b.def.spawn_time / DT) + 2, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))
		b.fsm.change(move)
		var mf := _record(w2, b, roundi(3.0 / DT), func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))
		var end := mf.size() - 1
		for i in mf.size():
			if mf[i].anim.state != move:
				end = maxi(i - 1, 1)
				break
		rows.append(_enemy_row(String(move), b, model, lead + mf.slice(0, end + 1), even(lead.size(), lead.size() + end), lead.size()))
	var w3 := _new_world()
	var p3 := _player(w3, &"swordShield")
	var d := _spawn(w3, kind, p3.pos + Vector2(0, 6), form)
	var dl := _record(w3, d, roundi(d.def.spawn_time / DT) + 2, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))
	d.hp = 0.0
	d.die(0)
	var df := _record(w3, d, 50, func(_i: int) -> InputCmd: return _cmd(Vector2.ZERO))
	rows.append(_enemy_row("dead", d, model, dl + df, even(dl.size(), dl.size() + df.size() - 1), dl.size()))
	return rows


func _spawn(w: World, kind: StringName, at: Vector2, form: int) -> Enemy:
	var e: Enemy = w.spawner.spawn_at(w, kind, at)
	if form > 0:
		e.set(&"form", form)
	return e


# start：這段動作從第幾步開始（前面的步數是為了讓動畫器的狀態接得上，檢視器從這裡開始播）
func _enemy_row(key: String, e: Enemy, model: StringName, frames: Array, samples: Array[int], start: int) -> Dictionary:
	return {"key": key, "name": key, "subject": e, "frames": frames, "samples": samples, "start": start,
		"make": func() -> Dictionary:
			var rig: Node3D = DarkFantasy.character(model) if e.is_boss() else DarkFantasy.skinned_character(e.kind)
			return {"rig": rig, "anim": EnemyAnimator.new(rig, e)}}


# 把第 0 ~ upto 步餵給動畫器（重播到第 upto 步的姿勢）
static func replay(row: Dictionary, made: Dictionary, upto: int) -> void:
	for i in mini(upto, (row.frames as Array).size() - 1) + 1:
		step(row, made, i)


static func step(row: Dictionary, made: Dictionary, i: int) -> void:
	var subject: Entity = row.subject
	var f: Dictionary = row.frames[i]
	subject.anim = f.anim
	subject.velocity = f.vel
	subject.pos = f.pos   # 特效照實體的位置、朝向、高度放（守墓人噴火從提燈出來）
	subject.facing = f.facing
	subject.height = f.height
	subject.ground_height = f.ground
	made.anim.update(subject, DT)
