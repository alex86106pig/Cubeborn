# 平衡數字表：照現在的資料表實際跑模擬，量武器普攻、右鍵、技能的傷害，怪物的威脅，與第 1 層的經濟（祭壇、靈魂、主袋填滿率），寫成 docs/平衡數字.md
# 平常用 `node tools/release.mjs --balance` 跑；直接跑：在 godot/ 內 <Godot> --headless --path . -s res://tests/balance_report.gd -- --out=<檔案路徑>
# 條件：白裝、技能 1 級、沒有道具與羈絆、測試場地（不含挖墳難度倍率）；怪是假人（抗性清空、每步拉回原位、不會死）
# 技能目標（docs/設計方向.md「技能強度」）：放一次對每隻怪的傷害 = 普攻單體每秒傷害 ×（耗魔 ÷ 那把武器的回魔）÷ SKILL_K（右鍵 ÷ SPECIAL_K）；有暈眩或補血的功能型 × CONTROL_MUL
# 單體、一群兩種站位都看：一群時算「有打到的怪平均每隻吃多少」（扇形、分裂的箭打一群時每隻只中一支，打一隻時才會好幾支都中）
extends SceneTree

const DT := 1.0 / 60.0
const SKILL_K := 2.0     # 許家慶 2026-11-04：技能耗魔 ÷ 3、倍率 ÷ 2，總輸出 × 1.5（原本 3）
const SPECIAL_K := 3.0   # 右鍵照舊
const CONTROL_MUL := 0.5
const TOLERANCE := 0.2          # 實際 / 目標在 1 ± 這麼多以內算達標
# 經濟目標（docs/設計方向.md「經濟目標」）：x = 目標、y = 容差；照真實地圖算，不跑機器人
const ECON_SEEDS := 20
const ECON_TARGET := {&"fill": Vector2(0.6, 0.1), &"pressure": Vector2(1.4, 0.2)}
const ECON_MIN_CHESTS := 1      # 每小關至少幾個祭壇或石棺
# 武器目標（docs/設計方向.md「武器強度」）：普攻每秒 + 右鍵按耗魔攤平（耗魔 ÷ 那把武器的回魔 當冷卻秒數），打一隻近戰 / 遠程各一檔；打一群是自己打一隻的幾倍
const WEAPON_TARGET := {&"melee": 30.0, &"ranged": 22.0}
const GROUP_BAND := Vector2(3.0, 6.0)
# 打一群偏高但刻意保留的武器（使用者 2026-10-31：不能降傷害，同一下打到的每隻都要一樣痛，不做遞減；揮擊範圍是手感）
const GROUP_KEEP := [&"swordShield", &"torch", &"scepter", &"shovel"]
# 打一隻要比這些武器都高（不看類型的目標）：雙匕首是全部最高（許家慶 2026-11-05：高風險高傷害，近身比短弓痛）；
# 短弓是遠程最高（使用者 2026-11-02：專打單體、箭不穿透，打一群偏低是代價；2026-11-05 起只跟遠程比）
const TRIGGER_TARGET := 1.0   # 左鍵的命中袋 / 出手袋每秒發動約幾次（_trigger_table）
const SINGLE_TOP := {&"dagger": &"", &"shortbow": &"ranged"}   # 武器 → 跟哪種類型比（空 = 全部）
const BASIC_TIME := 10.0        # 普攻量幾秒取平均
const SKILL_WINDOW := 6.0       # 放一次後量幾秒（落雷延遲、火池、拖尾、燃燒都算進去）
const MELEE_RANGE := 2.0        # 單體假人離玩家多遠：近戰武器
const RANGED_RANGE := 6.0       # 遠程武器
const DANGER_TIME := 20.0       # 怪打站著不動的玩家量幾秒
# 武器與它的普攻（[武器 id, &""]：第二欄是原本的副手，拿掉主副手後一律空的）
const LOADOUTS := [[&"swordShield", &""], [&"dagger", &""], [&"torch", &""], [&"staff", &""], [&"scepter", &""],
	[&"shortbow", &""], [&"longbow", &""], [&"shovel", &""]]
# 刻意不照目標的招式（行為名稱 → 原因），表上標「保留」
const KEEP := {
	&"arcaneBurst": "350% 是使用者同意的數字（系統說明 §1）",
	&"chargedShot": "量的是蓄滿：要站著蓄 1 秒、移速減半，蓄滿高一點是代價",
	&"fireBreath": "火把普攻已到近戰目標：噴火照右鍵目標打一隻會超過雙匕首（武器強度），傷害維持 125%、靠點燃與 90° 範圍",
	&"soul_reaver": "成長型：量的是 0 層（目標 × 0.6），這一層殺 30 隻後 × 1.9 ≈ 目標 × 1.15（mockups/橘色技能.html 方案 3）",
	&"fire_flask": "全吃法強、火把的法強只有基礎傷害的 0.75：倍率調高到火把上跟改之前一樣（火把傭兵的起始技能，使用者 2026-11-13 同意），所以比照比例算的目標高 1.33 倍",
	&"flame_dash": "同火瓶：全吃法強，倍率調高到火把上跟改之前一樣（使用者 2026-11-13 同意）",
	&"grudge": "成長型：量的是沒受傷時的保底（目標 × 0.5），受到的傷害 × 1.7 × 預算加上去，被打越多越痛",
	&"star_sign": "要放 3 顆才有傷害：量一次放是 0；3 顆的三角形每秒打 175%、最多 20 秒",
}
const ENEMIES := [&"grunt", &"archer", &"zombie", &"bloater", &"hound", &"spearman", &"bone_wheel", &"beetle", &"spider", &"hive", &"lich", &"wraith", &"gravekeeper", &"boss", &"bone_general", &"grave_worm"]

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
	_trigger_table(lines)
	_move_table(lines, basic)
	_cross_table(lines)
	_enemy_tables(lines, basic)
	_economy_table(lines)
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


# ───────── 經濟 ─────────

# 第 1 層：每小關的祭壇、石棺與開場的怪能賺的靈魂（ECON_SEEDS 個種子平均），和目標比
# 主袋填滿率 = 祭壇數 × 祭壇平均開出的數值道具格數 ÷ 主袋格數（全開的上限，同稀有度每件機率一樣）；小技能與修飾放袋子，另外列；靈魂壓力 = 全開要的靈魂 ÷ 全清賺的靈魂（不含怪潮）
func _economy_table(lines: Array[String]) -> void:
	var stages := 5   # 第 1 層 1-1 ~ 1-5
	var altars: Array[float] = []
	var coffins: Array[float] = []
	var souls: Array[float] = []
	altars.resize(stages)
	coffins.resize(stages)
	souls.resize(stages)
	var fewest := 1 << 20
	var short_most := 0
	for seed_value in range(1, ECON_SEEDS + 1):
		var w := World.new()
		w.reset(seed_value)
		var short := 0
		for st in stages:
			short += w.map.get("chest_short", 0)
			var n := 0
			for c in w.chests:
				n += 1
				if (c as Chest).tier == &"small":
					altars[st] += 1.0
				else:
					coffins[st] += 1.0
			fewest = mini(fewest, n)
			var boss_seen := false
			for e in w.enemies:
				if not (e as Enemy).no_souls and not e.is_dead:
					souls[st] += LootDefs.KILL_SOULS.get((e as Enemy).type, 0)
					boss_seen = boss_seen or (e as Enemy).is_boss()
			if w.map.has("boss_room") and not boss_seen:   # Boss 開打才生，開場的怪裡沒有
				souls[st] += LootDefs.KILL_SOULS.boss
			if st < stages - 1:
				w.next_stage(&"")
		short_most = maxi(short_most, short)
		w.clear()
	lines.append("")
	lines.append("## 經濟（第 1 層）")
	lines.append("")
	lines.append("> 照真實地圖算 %d 個種子的平均，不跑機器人。全清靈魂只算開場的怪與 Boss，不含怪潮與挖墳噴的怪。主袋填滿率假設祭壇全開、同稀有度每件機率一樣、沒算 Boss 掉的道具與 3 選 1 的取捨；實際拿到多少看 `--playtest`。" % ECON_SEEDS)
	lines.append("")
	lines.append("| 小關 | 祭壇 | 石棺 | 全清靈魂 |")
	lines.append("|---|---|---|---|")
	var total := {&"altar": 0.0, &"coffin": 0.0, &"souls": 0.0}
	for st in stages:
		var a := altars[st] / ECON_SEEDS
		var c := coffins[st] / ECON_SEEDS
		var s := souls[st] / ECON_SEEDS
		total.altar += a
		total.coffin += c
		total.souls += s
		lines.append("| 1-%d | %.1f | %.1f | %.0f |" % [st + 1, a, c, s])
	lines.append("| **整層** | **%.1f** | **%.1f** | **%.0f** |" % [total.altar, total.coffin, total.souls])
	var weights: Dictionary = LootDefs.CHESTS.small.weights
	var cells := 0.0        # 每個祭壇平均幾格放主袋（數值）
	var bag_cells := 0.0    # 每個祭壇平均幾格放袋子（小技能、修飾）
	var weight_sum := 0.0
	for r: StringName in weights:
		var stat := 0
		var other := 0
		var count := 0
		for id: StringName in ItemDefs.ITEMS:
			if ItemDefs.ITEMS[id].kind == &"item" and ItemDefs.ITEMS[id].rarity == r:
				count += 1
				if ItemDefs.role_of(id) == ItemDefs.ROLE_STAT:
					stat += Inventory.cells_of(id, 0).size()
				else:
					other += Inventory.cells_of(id, 0).size()
		cells += weights[r] * stat / maxf(count, 1.0)
		bag_cells += weights[r] * other / maxf(count, 1.0)
		weight_sum += weights[r]
	cells /= weight_sum
	bag_cells /= weight_sum
	var main_cells := BagDefs.MAIN_SIZE.x * BagDefs.MAIN_SIZE.y
	var cost: float = total.altar * LootDefs.CHESTS.small.price + total.coffin * LootDefs.CHESTS.big.price
	var fill: float = total.altar * cells / main_cells
	var pressure: float = cost / maxf(total.souls, 1.0)
	lines.append("")
	lines.append("每個祭壇平均開出 %.2f 格放主袋（數值）、%.2f 格放袋子（小技能、修飾）；主袋 %d 格。全開要 %.0f 靈魂，放袋子的共 %.1f 格，另有 %.1f 個石棺的技能。" % [cells, bag_cells, main_cells, cost, total.altar * bag_cells, total.coffin])
	lines.append("")
	lines.append("| 指標 | 目標 | 實際 | |")
	lines.append("|---|---|---|---|")
	lines.append("| 主袋填滿率（全開上限） | %.0f%% ± %.0f%% | %.0f%% | %s |" % [ECON_TARGET.fill.x * 100.0, ECON_TARGET.fill.y * 100.0, fill * 100.0, _econ_mark(fill, ECON_TARGET.fill)])
	lines.append("| 靈魂壓力（全開 ÷ 全清） | %.1f ± %.1f | %.2f | %s |" % [ECON_TARGET.pressure.x, ECON_TARGET.pressure.y, pressure, _econ_mark(pressure, ECON_TARGET.pressure)])
	lines.append("| 每小關最少的祭壇和石棺 | 至少 %d | %d | %s |" % [ECON_MIN_CHESTS, fewest, "達標" if fewest >= ECON_MIN_CHESTS else "**偏低**"])
	lines.append("| 放不下少放的（最多的一局） | 0 | %d | %s |" % [short_most, "達標" if short_most == 0 else "**偏高**"])


func _econ_mark(value: float, target: Vector2) -> String:
	if value < target.x - target.y:
		return "**偏低**"
	return "**偏高**" if value > target.x + target.y else "達標"


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

# 每把武器：普攻每秒 + 有傷害的右鍵按冷卻攤平
func _weapon_table(lines: Array[String]) -> void:
	lines.append("## 武器強度（普攻 + 右鍵）")
	lines.append("")
	lines.append("普攻每秒 + 右鍵每次 ÷（耗魔 ÷ 那把武器的回魔）（單拿這把；盾擊只算推盾那一下，盾反不算）。打一隻目標：近戰 %.0f、遠程 %.0f（±%.0f%%）；打一群的倍數 = 一群合計 ÷ 打一隻，目標 %.0f~%.0f 倍。雙匕首打一隻要是全部最高、短弓是遠程最高（比 = 自己 ÷ 組裡第二高）。" % [WEAPON_TARGET.melee, WEAPON_TARGET.ranged, TOLERANCE * 100.0, GROUP_BAND.x, GROUP_BAND.y])
	lines.append("")
	lines.append("| 武器 | 類型 | 基礎傷害 | 打一隻每秒 | 目標 | 比 | 打一群每秒 | 倍數 | |")
	lines.append("|---|---|---:|---:|---:|---:|---:|---:|---|")
	var singles := {}
	var packs := {}
	for lo: Array in LOADOUTS:
		var wid: StringName = lo[0]
		var alone: Array = [wid, &""]
		singles[wid] = _basic(alone, false)
		packs[wid] = _basic(alone, true)
		var sp: Dictionary = WeaponDefs.WEAPONS[wid].get("special", {})
		if sp.has("mana") and sp.has("damage_pct"):
			singles[wid] += _special_hit(alone, sp, false).x / _cd_of(sp, wid)
			packs[wid] += _special_hit(alone, sp, true).x / _cd_of(sp, wid)
	for lo: Array in LOADOUTS:
		var wid: StringName = lo[0]
		var wpn: Dictionary = WeaponDefs.WEAPONS[wid]
		var single: float = singles[wid]
		var pack: float = packs[wid]
		var mul := pack / single if single > 0.0 else 0.0
		var off: Array[String] = []
		var target: float = WEAPON_TARGET[wpn.type]
		var ratio := single / target
		var target_text := "%.0f" % target
		if SINGLE_TOP.has(wid):
			# 要比同一組的其他武器都高：目標欄寫「最高」或「遠程最高」，比 = 自己 ÷ 組裡第二高
			var among: StringName = SINGLE_TOP[wid]
			var others := 0.0
			for k: StringName in singles:
				if k != wid and (among == &"" or WeaponDefs.WEAPONS[k].type == among):
					others = maxf(others, singles[k])
			ratio = single / others
			target_text = "最高" if among == &"" else "遠程最高"
			if ratio <= 1.0:
				off.append("打一隻不是最高")
			if mul < GROUP_BAND.x:
				off.append("保留：打一群偏低（%s）" % ("專打單體、箭不穿透" if wid == &"shortbow" else "貼身單殺，範圍窄"))
		else:
			if absf(ratio - 1.0) > TOLERANCE:
				off.append("打一隻" + ("偏低" if ratio < 1.0 else "偏高"))
			if mul < GROUP_BAND.x:
				off.append("打一群偏低")
		if mul > GROUP_BAND.y:
			off.append("保留：打一群偏高（不降傷害、揮擊範圍是手感）" if GROUP_KEEP.has(wid) else "打一群偏高")
		lines.append("| %s | %s | %.1f | %.1f | %s | %.2f | %.0f | %.1f | %s |" % [wpn.name, "近戰" if wpn.type == &"melee" else "遠程",
			wpn.base_damage, single, target_text, ratio, pack, mul, "✓" if off.is_empty() else "、".join(off)])
	lines.append("")


# ───────── 左鍵的觸發袋 ─────────

# 每把武器一直普攻一隻：每秒打中幾下、出手幾下（同一步打到好幾隻算一下），除以 trigger_every = 命中袋 / 出手袋每秒發動幾次
# 目標約每秒 1 次（許家慶 2026-11-05：取代機率，打得快的武器 N 大）
func _trigger_table(lines: Array[String]) -> void:
	lines.append("## 左鍵的命中袋 / 出手袋")
	lines.append("")
	lines.append("一直普攻一隻假人 %.0f 秒：每秒打中 / 出手幾下（同一步打到好幾隻算一下）；N = 武器的 trigger_every（每 N 下發動一次）；目標每秒約 %.1f 次（±%.0f%%）。" % [BASIC_TIME, TRIGGER_TARGET, TOLERANCE * 100.0])
	lines.append("")
	lines.append("| 武器 | 每秒打中 | 每秒出手 | N | 命中袋每秒 | 出手袋每秒 | |")
	lines.append("|---|---:|---:|---:|---:|---:|---|")
	for lo: Array in LOADOUTS:
		var s := _setup(lo)
		var w: World = s[0]
		var p: Player = s[1]
		var at := p.pos + Vector2(0, _range_of(lo[0]))
		var d := _dummies(w, [at])
		for i in roundi(BASIC_TIME / DT):
			_step(w, _cmd(at, InputCmd.BTN_ATTACK), d, [at])
		var hits: float = p.trigger_moments.get(&"hit:primary", 0) / BASIC_TIME
		var casts: float = p.trigger_moments.get(&"cast:primary", 0) / BASIC_TIME
		var n: int = maxi(1, WeaponDefs.WEAPONS[lo[0]].get("trigger_every", 1))
		var off: Array[String] = []
		for x: Array in [["命中袋", hits / n], ["出手袋", casts / n]]:
			if absf(x[1] / TRIGGER_TARGET - 1.0) > TOLERANCE:
				off.append(x[0] + ("偏低" if x[1] < TRIGGER_TARGET else "偏高"))
		lines.append("| %s | %.2f | %.2f | %d | %.2f | %.2f | %s |" % [_loadout_name(lo), hits, casts, n, hits / n, casts / n, "✓" if off.is_empty() else "、".join(off)])
	lines.append("")


# ───────── 右鍵與技能 ─────────

func _move_table(lines: Array[String], basic: Dictionary) -> void:
	lines.append("## 右鍵與技能")
	lines.append("")
	lines.append("目標 = 放一次對每隻怪的傷害 = 普攻單體每秒 ×（耗魔 ÷ 那把武器的回魔）÷ %.0f（右鍵 ÷ %.0f；有暈眩或補血 × %.1f）× 技能稀有度的強度預算（%s）× 傷害來源的倍率（武器係數 + 法強係數 × 法術強度 ÷ 基礎傷害；全吃武器傷害的是 1）。單體、一群都和目標比：一群看有打到的怪平均每隻吃多少；比在 %.1f~%.1f 算達標（一群只打到 1 隻的、召喚不看）。" % [SKILL_K, SPECIAL_K, CONTROL_MUL, " / ".join(SkillDefs.RARITY_BUDGET.keys().map(func(r: StringName) -> String: return "%s %.2f" % [ItemDefs.RARITIES[r].name, SkillDefs.RARITY_BUDGET[r]])), 1.0 - TOLERANCE, 1.0 + TOLERANCE])
	lines.append("")
	lines.append("| 招式 | 武器 | 耗魔 | 目標 | 單體每次 | 比 | 一群打到 | 一群每隻 | 比 | 一群合計 | |")
	lines.append("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|")
	for lo: Array in LOADOUTS:
		# 右鍵：沒有耗魔或沒有傷害的不列；盾擊（推盾期間格擋、擋下就盾反）算功能型
		var sp: Dictionary = WeaponDefs.WEAPONS[lo[0]].get("special", {})
		if sp.has("mana") and sp.has("damage_pct"):
			_move_row(lines, basic, "右鍵・" + String(sp.name), lo[0], sp.mana, sp.has("stun") or sp.has("heal_per_sec") or sp.has("block_window"),
				func(pack: bool) -> Vector2: return _special_hit([lo[0], &""], sp, pack), KEEP.get(sp.behavior, ""), true, SPECIAL_K)
	for id: StringName in SkillDefs.gem_skill_ids():
		var def: Dictionary = SkillDefs.SKILLS[id]
		var wid: StringName = def.weapons[0]
		if not def.has("damage_pct") and def.behavior != &"summon":
			var cost: String = ("%.0f" % def.mana) if def.has("mana") else "次數制"   # 插火把：每層幾次、不耗魔
			lines.append("| %s | %s | %s | 功能技能，不算傷害 | | | | | | | |" % [ItemDefs.ITEMS[id].name, WeaponDefs.WEAPONS[wid].name, cost])
			continue
		_move_row(lines, basic, "%s（%s）" % [ItemDefs.ITEMS[id].name, ItemDefs.RARITIES[ItemDefs.ITEMS[id].rarity].name], wid, def.mana, def.has("stun") or def.has("heal_ratio"),
			func(pack: bool) -> Vector2: return _skill_hit(id, pack), KEEP.get(id, ""), def.behavior != &"summon", SKILL_K, SkillDefs.budget(id) * SkillDefs.scale_mul(def, WeaponDefs.WEAPONS[wid]))
	lines.append("")


# group：要不要看一群每隻（召喚的僕從一次打一隻，打一群時平均每隻沒有意義）
# budget：技能稀有度的強度預算（SkillDefs.RARITY_BUDGET）× 傷害來源在這把武器上的倍率（SkillDefs.scale_mul），目標跟著乘；右鍵是 1
func _move_row(lines: Array[String], basic: Dictionary, label: String, wid: StringName, mana: float, control: bool, hit: Callable, keep := "", group := true, k := SKILL_K, budget := 1.0) -> void:
	var single: Vector2 = hit.call(false)   # (總傷害, 打到幾隻)
	var pack: Vector2 = hit.call(true)
	var target: float = basic[wid] * mana / _regen(wid) / k * (CONTROL_MUL if control else 1.0) * budget
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
	lines.append("| %s | %s | %.0f | %.0f | %.0f | %.2f | %d | %.0f | %s | %.0f | %s |" % [label, WeaponDefs.WEAPONS[wid].name, mana, target, single.x, ratio,
		pack.y, each, ("%.2f" % pack_ratio) if judged else "—", pack.x, mark])


# 耗魔換算成冷卻秒數（÷ 那把武器的回魔）：右鍵攤平、技能目標都用這個
func _cd_of(def: Dictionary, wid: StringName) -> float:
	return def.mana / _regen(wid)


# 武器的回魔（魔力照武器，WeaponDefs 的 mana_regen；沒寫的用 Config.MANA.regen）
func _regen(wid: StringName) -> float:
	return WeaponDefs.WEAPONS[wid].get("mana_regen", Config.MANA.regen)


# 同一個技能配每把武器（技能不綁武器、魔力照武器）：全吃武器傷害的每秒（照回魔）與滿魔力連放的爆發應該都一樣；吃法強的跟著「法術強度 ÷ 基礎傷害」
const CROSS_SKILLS: Array[StringName] = [&"whirlwind", &"frost_nova", &"sword_wave"]
func _cross_table(lines: Array[String]) -> void:
	lines.append("## 技能 × 武器（魔力照武器）")
	lines.append("")
	lines.append("同一個技能換不同武器放：每次傷害 = 倍率 ×（基礎傷害 × 武器係數 + 法術強度 × 法強係數）；每秒 = 每次 × 回魔 ÷ 耗魔（長時間一直放）；爆發 = 每次 × 滿魔力放得出幾次。全吃武器傷害的（旋風斬）每秒與爆發各武器差不多；全吃法強的（冰霜新星）照法術強度 ÷ 基礎傷害：法杖 1.5、驅魔權杖 1.0、火把 0.75、其餘 0.5；混合的（劍氣）在中間。比 = 自己 ÷ 驅魔權杖。武器需求不符的寫放不出來。")
	lines.append("")
	lines.append("| 技能 | 武器 | 最大魔力 | 回魔 | 每次 | 每秒 | 比 | 爆發 | 比 |")
	lines.append("|---|---|---:|---:|---:|---:|---:|---:|---:|")
	for id in CROSS_SKILLS:
		var cost: float = SkillDefs.SKILLS[id].mana
		# 比的基準：驅魔權杖（法術強度 = 基礎傷害，吃武器還是吃法強都一樣；近戰、不限武器的都放得出來）
		var ref_wd: Dictionary = WeaponDefs.WEAPONS.scepter
		var ref_hit := _skill_hit(id, false, &"scepter").x
		var ref := Vector2(ref_hit * _regen(&"scepter") / cost, ref_hit * floorf(ref_wd.get("max_mana", Config.MANA.max) / cost))
		for lo: Array in LOADOUTS:
			var wid: StringName = lo[0]
			var wd: Dictionary = WeaponDefs.WEAPONS[wid]
			if not SkillDefs.fits_weapon(SkillDefs.SKILLS[id], wd):
				lines.append("| %s | %s | 放不出來（要%s武器） | | | | | | |" % [ItemDefs.ITEMS[id].name, wd.name, WeaponDefs.TAGS[SkillDefs.SKILLS[id].needs]])
				continue
			var hit := _skill_hit(id, false, wid).x
			var mx: float = wd.get("max_mana", Config.MANA.max)
			var per_sec := hit * _regen(wid) / cost
			var burst := hit * floorf(mx / cost)
			lines.append("| %s | %s | %.0f | %.2f | %.0f | %.1f | %.2f | %.0f | %.2f |" % [ItemDefs.ITEMS[id].name, wd.name, mx, _regen(wid), hit, per_sec, per_sec / ref.x, burst, burst / maxf(ref.y, 1.0)])
	lines.append("")


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


func _skill_hit(id: StringName, pack: bool, with_weapon: StringName = &"") -> Vector2:
	var def: Dictionary = SkillDefs.SKILLS[id]
	var wid: StringName = def.weapons[0] if with_weapon == &"" else with_weapon
	var lo: Array = [wid, &""]
	var s := _setup(lo)
	var w: World = s[0]
	var p: Player = s[1]
	if _slot_of(p, id) < 0:
		p.add_item(id)   # 放進按鍵袋 1
	var idx := _slot_of(p, id)
	assert(idx >= 0, "%s 放不進按鍵袋" % id)
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
	lines.append("一隻怪對站著不動的玩家（劍盾、不格擋）打 %.0f 秒的平均每秒傷害；「幾秒打死」= 玩家基礎生命 %.0f ÷ 每秒。0 = 這段時間沒出手（Boss、守墓人要先觸發）。" % [DANGER_TIME, Config.PLAYER.max_hp])
	lines.append("")
	lines.append("| 怪物 | 每秒傷害 | 幾秒打死 |")
	lines.append("|---|---:|---:|")
	for kind: StringName in ENEMIES:
		var dps := _danger(kind)
		lines.append("| %s | %.1f | %s |" % [RunLog.NAMES[kind], dps, ("%.1f" % (Config.PLAYER.max_hp / dps)) if dps > 0.0 else "—"])
	lines.append("")


func _danger(kind: StringName) -> float:
	var s := _setup([&"swordShield", &""])
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
	return WeaponDefs.WEAPONS[lo[0]].name
