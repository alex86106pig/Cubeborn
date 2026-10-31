# 平衡數字表：照現在的資料表實際跑模擬，量武器普攻、右鍵、寶石座技能的傷害，與怪物的威脅，寫成 docs/平衡數字.md
# 平常用 `node tools/release.mjs --balance` 跑；直接跑：在 godot/ 內 <Godot> --headless --path . -s res://tests/balance_report.gd -- --out=<檔案路徑>
# 條件：白裝、技能 1 級、沒有道具與羈絆、測試場地（不含挖墳難度倍率）；怪是假人（抗性清空、每步拉回原位、不會死）
# 技能目標（docs/設計方向.md「技能強度」）：放一次對每隻怪的傷害 = 普攻單體每秒傷害 × 冷卻 ÷ SKILL_K；有暈眩或補血的功能型 × CONTROL_MUL
# 單體、一群兩種站位都看：一群時算「有打到的怪平均每隻吃多少」（扇形、分裂的箭打一群時每隻只中一支，打一隻時才會好幾支都中）
extends SceneTree

const DT := 1.0 / 60.0
const SKILL_K := 3.0
const CONTROL_MUL := 0.5
const TOLERANCE := 0.2          # 實際 / 目標在 1 ± 這麼多以內算達標
# 武器目標（docs/設計方向.md「武器強度」）：普攻每秒 + 右鍵按冷卻攤平，打一隻近戰 / 遠程各一檔；打一群是自己打一隻的幾倍
const WEAPON_TARGET := {&"melee": 30.0, &"ranged": 22.0}
const GROUP_BAND := Vector2(3.0, 6.0)
const BASIC_TIME := 10.0        # 普攻量幾秒取平均
const SKILL_WINDOW := 6.0       # 放一次後量幾秒（落雷延遲、火池、拖尾、燃燒都算進去）
const MELEE_RANGE := 2.0        # 單體假人離玩家多遠：近戰武器
const RANGED_RANGE := 6.0       # 遠程武器
const DANGER_TIME := 20.0       # 怪打站著不動的玩家量幾秒
# 武器（主手 + 副手）與它的普攻；木盾的技能用長劍＋木盾的普攻比
const LOADOUTS := [[&"longsword", &"woodShield"], [&"dagger", &""], [&"torch", &""], [&"staff", &""], [&"scepter", &""],
	[&"shortbow", &""], [&"longbow", &""], [&"shovel", &""]]
# 刻意不照目標的招式（行為名稱 → 原因），表上標「保留」
const KEEP := {
	&"arcaneBurst": "350% 是使用者同意的數字（系統說明 §1）",
	&"chargedShot": "量的是蓄滿：要站著蓄 1 秒、移速減半，蓄滿高一點是代價",
}
const ENEMIES := [&"grunt", &"archer", &"zombie", &"bloater", &"hound", &"gravekeeper", &"boss"]

var _worlds: Array[World] = []


func _initialize() -> void:
	var out_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.substr(6)
	var lines: Array[String] = []
	lines.append("# 平衡數字")
	lines.append("")
	lines.append("> `node tools/release.mjs --balance` 產生，不要手改；調完 `defs/` 的數字重跑。版本 v%s。" % GameVersion.VERSION)
	lines.append("> 條件：白裝、技能 1 級、沒有道具與羈絆、測試場地（不含挖墳難度倍率）。假人抗性清空、站著不動、不會死。")
	lines.append("> 單體假人：近戰武器在 %.0f 單位、遠程在 %.0f 單位（以自己為中心的範圍技能放在範圍內）；一群 = 那個位置 4×3 共 12 隻（以自己為中心的換成身邊一圈 8 隻）。" % [MELEE_RANGE, RANGED_RANGE])
	lines.append("")
	var basic := _basic_table(lines)
	_weapon_table(lines)
	_move_table(lines, basic)
	_enemy_tables(lines, basic)
	for w in _worlds:
		w.clear()
	var text := "\n".join(lines) + "\n"
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		print("寫入 ", out_path)
	else:
		print(text)
	quit()


# ───────── 普攻 ─────────

func _basic_table(lines: Array[String]) -> Dictionary:
	lines.append("## 普攻每秒傷害")
	lines.append("")
	lines.append("| 武器 | 單體 | 一群（12 隻合計） |")
	lines.append("|---|---:|---:|")
	var out := {}
	for lo: Array in LOADOUTS:
		var single := _basic(lo, false)
		var pack := _basic(lo, true)
		out[lo[0]] = single
		lines.append("| %s | %.1f | %.1f |" % [_loadout_name(lo), single, pack])
	out[&"woodShield"] = out[&"longsword"]
	lines.append("")
	return out


func _basic(lo: Array, pack: bool) -> float:
	var s := _setup(lo)
	var w: World = s[0]
	var p: Player = s[1]
	var at := p.pos + Vector2(0, _range_of(lo[0]))
	var spots := _pack(at) if pack else [at]
	var d := _dummies(w, spots)
	for i in roundi(BASIC_TIME / DT):
		_step(w, _cmd(at, InputCmd.BTN_ATTACK), d, spots)
	return _total(d) / BASIC_TIME


# ───────── 武器 ─────────

# 每把武器單拿（長劍的右鍵是蓄力突刺，不拿木盾）：普攻每秒 + 有傷害的右鍵按冷卻攤平
func _weapon_table(lines: Array[String]) -> void:
	lines.append("## 武器強度（普攻 + 右鍵）")
	lines.append("")
	lines.append("普攻每秒 + 右鍵每次 ÷ 冷卻（單拿這把；格擋、準備姿態、鏟起不算傷害）。打一隻目標：近戰 %.0f、遠程 %.0f（±%.0f%%）；打一群的倍數 = 一群合計 ÷ 打一隻，目標 %.0f~%.0f 倍。" % [WEAPON_TARGET.melee, WEAPON_TARGET.ranged, TOLERANCE * 100.0, GROUP_BAND.x, GROUP_BAND.y])
	lines.append("")
	lines.append("| 武器 | 類型 | 基礎傷害 | 打一隻每秒 | 目標 | 比 | 打一群每秒 | 倍數 | |")
	lines.append("|---|---|---:|---:|---:|---:|---:|---:|---|")
	for lo: Array in LOADOUTS:
		var wid: StringName = lo[0]
		var wpn: Dictionary = WeaponDefs.WEAPONS[wid]
		var alone: Array = [wid, &""]
		var single := _basic(alone, false)
		var pack := _basic(alone, true)
		var sp: Dictionary = wpn.get("special", {})
		if sp.has("cooldown") and sp.has("damage_pct"):
			single += _special_hit(alone, sp, false).x / sp.cooldown
			pack += _special_hit(alone, sp, true).x / sp.cooldown
		var target: float = WEAPON_TARGET[wpn.type]
		var ratio := single / target
		var mul := pack / single if single > 0.0 else 0.0
		var off: Array[String] = []
		if absf(ratio - 1.0) > TOLERANCE:
			off.append("打一隻" + ("偏低" if ratio < 1.0 else "偏高"))
		if mul < GROUP_BAND.x or mul > GROUP_BAND.y:
			off.append("打一群" + ("偏低" if mul < GROUP_BAND.x else "偏高"))
		lines.append("| %s | %s | %.1f | %.1f | %.0f | %.2f | %.0f | %.1f | %s |" % [wpn.name, "近戰" if wpn.type == &"melee" else "遠程",
			wpn.base_damage, single, target, ratio, pack, mul, "✓" if off.is_empty() else "、".join(off)])
	lines.append("")


# ───────── 右鍵與技能 ─────────

func _move_table(lines: Array[String], basic: Dictionary) -> void:
	lines.append("## 右鍵與寶石座技能")
	lines.append("")
	lines.append("目標 = 放一次對每隻怪的傷害 = 普攻單體每秒 × 冷卻 ÷ %.0f（有暈眩或補血 × %.1f）。單體、一群都和目標比：一群看有打到的怪平均每隻吃多少；比在 %.1f~%.1f 算達標（一群只打到 1 隻的、召喚不看）。" % [SKILL_K, CONTROL_MUL, 1.0 - TOLERANCE, 1.0 + TOLERANCE])
	lines.append("")
	lines.append("| 招式 | 武器 | 冷卻 | 目標 | 單體每次 | 比 | 一群打到 | 一群每隻 | 比 | 一群合計 | |")
	lines.append("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|")
	for lo: Array in LOADOUTS:
		# 右鍵看主手單拿時（長劍拿著木盾時右鍵是格擋，蓄力突刺要拿掉盾）；格擋、準備姿態、鏟起這類沒冷卻或不算傷害的不列
		var sp: Dictionary = WeaponDefs.WEAPONS[lo[0]].get("special", {})
		if sp.has("cooldown") and sp.has("damage_pct"):
			_move_row(lines, basic, "右鍵・" + String(sp.name), lo[0], sp.cooldown, sp.has("stun") or sp.has("heal_per_sec"),
				func(pack: bool) -> Vector2: return _special_hit([lo[0], &""], sp, pack), KEEP.get(sp.behavior, ""))
	for id: StringName in SkillDefs.gem_skill_ids():
		var def: Dictionary = SkillDefs.SKILLS[id]
		var wid: StringName = def.weapons[0]
		if not def.has("damage_pct") and def.behavior != &"summon":
			lines.append("| %s | %s | %.0f | 功能技能，不算傷害 | | | | | | | |" % [ItemDefs.ITEMS[id].name, WeaponDefs.WEAPONS[wid].name, def.cooldown])
			continue
		_move_row(lines, basic, ItemDefs.ITEMS[id].name, wid, def.cooldown, def.has("stun") or def.has("heal_ratio"),
			func(pack: bool) -> Vector2: return _skill_hit(id, pack), "", def.behavior != &"summon")
	lines.append("")


# group：要不要看一群每隻（召喚的僕從一次打一隻，打一群時平均每隻沒有意義）
func _move_row(lines: Array[String], basic: Dictionary, label: String, wid: StringName, cd: float, control: bool, hit: Callable, keep := "", group := true) -> void:
	var single: Vector2 = hit.call(false)   # (總傷害, 打到幾隻)
	var pack: Vector2 = hit.call(true)
	var target: float = basic[wid] * cd / SKILL_K * (CONTROL_MUL if control else 1.0)
	var ratio := single.x / target if target > 0.0 else 0.0
	var each := pack.x / maxf(pack.y, 1.0)
	var pack_ratio := each / target if target > 0.0 else 0.0
	var off: Array[String] = []
	if absf(ratio - 1.0) > TOLERANCE:
		off.append("單體" + ("偏低" if ratio < 1.0 else "偏高"))
	var judged := group and pack.y >= 2.0
	if judged and absf(pack_ratio - 1.0) > TOLERANCE:
		off.append("一群" + ("偏低" if pack_ratio < 1.0 else "偏高"))
	var mark := "✓" if off.is_empty() else "、".join(off)
	if keep != "" and not off.is_empty():
		mark = "保留：" + keep
	lines.append("| %s | %s | %.0f | %.0f | %.0f | %.2f | %d | %.0f | %s | %.0f | %s |" % [label, WeaponDefs.WEAPONS[wid].name, cd, target, single.x, ratio,
		pack.y, each, ("%.2f" % pack_ratio) if judged else "—", pack.x, mark])


# 右鍵：按下（按住類的蓄滿 charge_time 再放開），量 SKILL_WINDOW 秒
func _special_hit(lo: Array, sp: Dictionary, pack: bool) -> Vector2:
	var s := _setup(lo)
	var w: World = s[0]
	var p: Player = s[1]
	var at := p.pos + Vector2(0, _range_of(lo[0]))
	var spots := _pack(at) if pack else [at]
	var d := _dummies(w, spots)
	var held := InputCmd.BTN_SPECIAL_HELD if sp.get("hold", false) else 0
	_step(w, _cmd(at, InputCmd.BTN_SPECIAL | held), d, spots)
	for i in roundi(sp.get("charge_time", 0.0) / DT) + 1:
		_step(w, _cmd(at, held), d, spots)
	for i in roundi(SKILL_WINDOW / DT):
		_step(w, _cmd(at, 0), d, spots)
	return Vector2(_total(d), _hits(d))


func _skill_hit(id: StringName, pack: bool) -> Vector2:
	var def: Dictionary = SkillDefs.SKILLS[id]
	var wid: StringName = def.weapons[0]
	var lo: Array = [&"longsword", &"woodShield"] if wid == &"woodShield" else [wid, &""]
	var s := _setup(lo)
	var w: World = s[0]
	var p: Player = s[1]
	if _slot_of(p, id) < 0:
		for g: Dictionary in p.slots.gems(p).duplicate():   # 火把出廠鑲著插火把：先拿下來
			p.loadout.remove_item(p, g.entry.uid)
		p.add_item(id)
	var idx := _slot_of(p, id)
	assert(idx >= 0, "%s 鑲不上 %s" % [id, wid])
	var self_centered: bool = def.behavior in [&"nova", &"cone"]
	var dist := _range_of(wid)
	match def.behavior:
		&"nova":
			dist = def.radius * 0.7
		&"cone":
			dist = def.range * 0.7
		&"burrow":
			dist = def.distance   # 往前鑽固定距離，在出土的地方炸開
	var at := p.pos + Vector2(0, dist)
	var spots: Array = [at]
	if pack:
		spots = _ring(p.pos, dist) if self_centered else _pack(at)
	var d := _dummies(w, spots)
	var window := maxf(SKILL_WINDOW, def.get("life", 0.0) + 0.5)   # 召喚的僕從活多久就量多久
	_step(w, _cmd(at, InputCmd.slot_bit(idx)), d, spots)
	for i in roundi(window / DT):
		_step(w, _cmd(at, 0), d, spots)
	return Vector2(_total(d), _hits(d))


# ───────── 怪物 ─────────

func _enemy_tables(lines: Array[String], basic: Dictionary) -> void:
	lines.append("## 普攻打死一隻要幾秒")
	lines.append("")
	lines.append("怪物血量 ÷（普攻單體每秒 × (1 − 抗性)）；抗性看武器的傷害屬性。")
	lines.append("")
	var head := "| 怪物 | 血量 |"
	var sep := "|---|---:|"
	for lo: Array in LOADOUTS:
		head += " %s |" % WeaponDefs.WEAPONS[lo[0]].name
		sep += "---:|"
	lines.append(head)
	lines.append(sep)
	for kind: StringName in ENEMIES:
		var def: Dictionary = EnemyDefs.ENEMIES[kind]
		var row := "| %s | %.0f |" % [RunLog.NAMES[kind], def.max_hp]
		for lo: Array in LOADOUTS:
			var wpn: Dictionary = WeaponDefs.WEAPONS[lo[0]]
			var resist: float = def.get("resists", {}).get(wpn.damage_type, 0.0)
			row += " %.1f |" % (def.max_hp / (basic[lo[0]] * (1.0 - resist)))
		lines.append(row)
	lines.append("")
	lines.append("## 怪物打玩家")
	lines.append("")
	lines.append("一隻怪對站著不動的玩家（長劍＋木盾、不格擋）打 %.0f 秒的平均每秒傷害；「幾秒打死」= 玩家基礎生命 %.0f ÷ 每秒。0 = 這段時間沒出手（Boss、守墓人要先觸發）。" % [DANGER_TIME, Config.PLAYER.max_hp])
	lines.append("")
	lines.append("| 怪物 | 每秒傷害 | 幾秒打死 |")
	lines.append("|---|---:|---:|")
	for kind: StringName in ENEMIES:
		var dps := _danger(kind)
		lines.append("| %s | %.1f | %s |" % [RunLog.NAMES[kind], dps, ("%.1f" % (Config.PLAYER.max_hp / dps)) if dps > 0.0 else "—"])
	lines.append("")


func _danger(kind: StringName) -> float:
	var s := _setup([&"longsword", &"woodShield"])
	var w: World = s[0]
	var p: Player = s[1]
	var e: Enemy = w.spawner.spawn_at(w, kind, p.pos + Vector2(0, 3.0))
	e.fsm.change(e.main_state)
	p.stats.set_base(&"max_hp", 1e6)   # 不讓玩家倒下（倒下後怪會換目標），扣了多少另外算
	p.hp = p.max_hp
	for i in roundi(DANGER_TIME / DT):
		w.step({World.HOST_PEER_ID: _cmd(e.pos, 0)}, DT)
	return (p.max_hp - p.hp) / DANGER_TIME


# ───────── 共用 ─────────

func _setup(lo: Array) -> Array:
	var w := World.new(&"test_arena")
	w.spawn_packs = false
	w.reset(12345)
	w.spawner.finished = true
	_worlds.append(w)
	var p: Player = w.players[World.HOST_PEER_ID]
	p.loadout.equip_new(p, lo[0])
	if lo[1] != &"":
		p.loadout.equip_offhand_new(p, lo[1])
	return [w, p]


func _range_of(wid: StringName) -> float:
	return RANGED_RANGE if WeaponDefs.WEAPONS[wid].type == &"ranged" else MELEE_RANGE


func _pack(center: Vector2) -> Array:
	var out := []
	for y in [-1.0, 0.0, 1.0]:
		for x in [-1.5, -0.5, 0.5, 1.5]:
			out.append(center + Vector2(x, y))
	return out


func _ring(center: Vector2, r: float) -> Array:
	var out := []
	for i in 8:
		out.append(center + Vector2.from_angle(TAU * i / 8.0) * r)
	return out


func _dummies(w: World, spots: Array) -> Array:
	var out := []
	for at: Vector2 in spots:
		var e: Enemy = w.spawner.spawn_at(w, &"grunt", at)
		e.fsm.change(e.main_state)
		e.stats.set_base(&"max_hp", 1e6)
		e.hp = e.max_hp
		e.set_resists({})
		out.append(e)
	return out


func _step(w: World, cmd: InputCmd, dummies: Array, spots: Array) -> void:
	w.step({World.HOST_PEER_ID: cmd}, DT)
	var p: Player = w.players[World.HOST_PEER_ID]
	p.hp = p.max_hp   # 假人會還手：玩家不倒下
	for i in dummies.size():
		dummies[i].pos = spots[i]


func _cmd(aim: Vector2, buttons: int) -> InputCmd:
	var c := InputCmd.new()
	c.aim = aim
	c.buttons = buttons
	return c


# 有受傷的假人幾隻
func _hits(dummies: Array) -> int:
	return dummies.filter(func(e: Enemy) -> bool: return e.hp < 1e6).size()


func _total(dummies: Array) -> float:
	var t := 0.0
	for e in dummies:
		t += 1e6 - e.hp
	return t


func _slot_of(p: Player, id: StringName) -> int:
	for i in ActiveSlots.GEM_SLOTS:
		var s: Variant = p.slots.get_slot(p, i)
		if s != null and s.id == id:
			return i
	return -1


func _loadout_name(lo: Array) -> String:
	var n: String = WeaponDefs.WEAPONS[lo[0]].name
	return n + ("＋" + WeaponDefs.WEAPONS[lo[1]].name if lo[1] != &"" else "")
