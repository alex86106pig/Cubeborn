# 觸發袋資料：背包 = 主袋 + 接在四邊的袋子（規則在 docs/設計方向.md「觸發袋」，數字 Claude 暫定）
# 主袋放數值道具；袋子放效果、技能、修飾，接在哪一邊決定按鍵（SIDES），袋子的種類決定時機（BAGS）
# 觸發道具改寫成效果：拿掉時機與機率，道具原本的動作（ItemDefs 效果的 do）對到 EFFECTS，重複的合併（對照在 docs/道具清單.md）
# 袋子的格子：x 沿著接的那一邊、y 往外（length × depth），換邊時內容不用轉；畫面與同色區塊照 Loadout.board_cell 換成主袋座標
class_name BagDefs

const MAIN_SIZE := Vector2i(6, 6)   # 主袋：四邊邊長都是 6（接得下兩個小袋、3 個按鍵袋）

# 邊：source 是哪個動作會觸發接在這一邊的袋子（primary 普攻、secondary 右鍵招式、key 數字鍵、空 = 不分按鍵）
const SIDES := {
	&"left": {"name": "左鍵", "source": &"primary"},
	&"right": {"name": "右鍵", "source": &"secondary"},
	&"bottom": {"name": "不分按鍵", "source": &""},
	&"top": {"name": "數字鍵", "source": &"key"},
}
const SIDE_ORDER: Array[StringName] = [&"top", &"left", &"right", &"bottom"]

# 袋子種類：item 是掉落與倉庫用的物品 id（ItemDefs kind bag）；sides 能接哪幾邊；
# on 是道具資料原本的觸發時機（ItemDefs 效果的 on），用來把觸發道具對到袋子；icd：同一袋多久最多發動一次（秒）；
# period：計時袋的間隔；max：最多接幾個（按鍵袋 = 數字鍵，上方邊長 6 接得下 3 個）；length：這種袋子的長度（沒寫照 TIERS；按鍵袋短一格）
const BAGS := {
	&"cast": {"name": "出手袋", "item": &"bag_cast", "sides": [&"left", &"right"], "on": [&"attack"], "desc": "出手時發動（左鍵每出手 N 下一次，N 看武器）"},
	&"hit": {"name": "命中袋", "item": &"bag_hit", "sides": [&"left", &"right"], "on": [&"hit", &"projectile_hit"], "icd": 0.3, "desc": "打中東西時，從命中點發動（左鍵每打中 N 下一次，N 看武器；右鍵同一袋 0.3 秒最多一次）"},
	&"kill": {"name": "擊殺袋", "item": &"bag_kill", "sides": [&"left", &"right"], "on": [&"kill"], "desc": "打死怪時，從怪死的位置發動"},
	&"hurt": {"name": "受傷袋", "item": &"bag_hurt", "sides": [&"bottom"], "on": [&"hurt", &"hurt_melee"], "icd": 0.5, "desc": "自己被打中時發動（同一袋 0.5 秒最多一次）"},
	&"roll": {"name": "翻滾袋", "item": &"bag_roll", "sides": [&"bottom"], "on": [&"roll"], "desc": "翻滾時發動"},
	&"timer": {"name": "計時袋", "item": &"bag_timer", "sides": [&"bottom"], "on": [&"interval"], "period": 3.0, "desc": "每 3 秒發動一次"},
	&"key": {"name": "按鍵袋", "item": &"bag_key", "sides": [&"top"], "on": [], "max": 3, "length": 2, "desc": "按數字鍵發動（由左到右是 1~3）"},
}

# 每種袋子（接在哪一邊）放出來的傷害倍率：觸發得少的痛、觸發得多的輕，讓每種袋子每分鐘的總輸出差不多（許家慶 2026-11-05：命中袋比擊殺袋好觸發太多）
# 數字 = 左鍵命中袋每分鐘發動次數 ÷ 這種袋子的，夾在 0.6~2.5（Claude 照自動試玩算：守墓騎士、竊影者、祕術師、盜墓遊俠各 2 場第 1 層的平均，每分鐘
# 左鍵命中 24.5 ÷ N ≈ 12、左鍵出手 ≈ 17、擊殺 4.5、受傷 4.2、翻滾 9.1、計時 20、右鍵命中 / 出手約 2.5；按鍵袋自己按，不調）；耗魔不變，所以觸發得少的也比較省魔
const POWER := {
	&"hit": {&"left": 1.0, &"right": 2.5}, &"cast": {&"left": 0.75, &"right": 2.5}, &"kill": {&"left": 2.5, &"right": 2.5},
	&"hurt": {&"bottom": 2.5}, &"roll": {&"bottom": 1.25}, &"timer": {&"bottom": 0.6}, &"key": {&"top": 1.0},
}


# 袋子放出來的傷害倍率 = 大小的倍率（強化袋、鐵砧）× 種類與邊的倍率（POWER）
static func power_of(bag: Dictionary) -> float:
	var p: float = bag.mul * POWER.get(bag.kind, {}).get(bag.side, 1.0)
	if has_rule(bag, &"blood_pact"):   # 橘色技能「血契」：這一袋傷害 × power
		p *= SkillDefs.SKILLS.blood_pact.power
	return p


# 袋子裡有沒有某個橘色的袋子規則（SkillDefs 的 rule：echo / resonance / blood_pact）
static func has_rule(bag: Dictionary, rule: StringName) -> bool:
	for e: Dictionary in bag.get("entries", []):
		var d: Dictionary = SkillDefs.SKILLS.get(e.id, {})
		if d.get("rule", &"") == rule:
			return true
	return false


# 左鍵（普攻）觸發的這幾種袋子數下數：每 N 下發動一次，N = 武器的 trigger_every（BagTriggers._ready）；右鍵照 icd
const COUNTED: Array[StringName] = [&"hit", &"cast"]

# 留在主袋的觸發：致命傷、死亡（守護亡靈、復活十字）不是攻擊的時機，當成常駐能力
const MAIN_TRIGGERS: Array[StringName] = [&"lethal", &"death"]

# 袋子的大小與特性（袋子實例的 tier）：mul 是裡面的效果與技能的傷害倍率；curse 是接著時角色多的缺點（屬性來源 &"curse:<uid>"）
const TIERS := {
# 小袋 3 × 2 放得下最大的效果道具（4 格的 L、S、T 形）
	&"small": {"name": "", "length": 3, "depth": 2, "mul": 1.0},
	&"big": {"name": "大", "length": 4, "depth": 2, "mul": 1.0},
	&"strong": {"name": "強化", "length": 3, "depth": 2, "mul": 1.5},
	&"cursed": {"name": "詛咒", "length": 5, "depth": 2, "mul": 1.0, "curse": [[&"damage_taken", Stats.MUL, 1.2]], "curse_desc": "接著時受到傷害 +20%"},
}

# 袋子裡的效果每發動一次耗魔 = 道具強度 power × 這個值（技能照技能自己的耗魔）
const EFFECT_MANA_PER_POWER := 1.0
# 效果沒有目標時（計時、翻滾、出手、按鍵）找身邊這麼遠內最近的怪；觸發的那一下沒有傷害時用武器基礎傷害的 100% 當基準
const AUTO_TARGET_RANGE := 8.0

# 開局（Player.apply_class）：按鍵袋 1 裝著起始技能，加一個職業的小觸發袋（[種類, 接哪一邊]）；沒選職業只有空的按鍵袋
const START := {
	&"guardian": {"skill": &"shield_slam", "bag": [&"hit", &"right"]},
	&"arcanist": {"skill": &"frost_nova", "bag": [&"timer", &"bottom"]},
	&"ranger": {"skill": &"volley", "bag": [&"hit", &"left"]},
	&"shadow": {"skill": &"knife_fan", "bag": [&"kill", &"left"]},
	&"priest": {"skill": &"holy_pillar", "bag": [&"hurt", &"bottom"]},
	&"mercenary": {"skill": &"fire_flask", "bag": [&"hit", &"left"]},   # 插火把拿掉後（許家慶 2026-11-06）改成火瓶（Claude 暫定）
	&"gravedigger": {"skill": &"ground_slam", "bag": [&"hit", &"right"]},
}

# ── 背包合併模式（mockups/背包合併.html，許家慶 2026-11-05 提出、2026-11-06 選定細節；跟袋子分開的模式並存、測試後留一種）──
# 主袋與四周的觸發區固定接好、不能拿下來，大部分格子鎖著，一局靠開格長大；換武器不搬袋子
# 區塊：[種類, 接哪一邊, offset, 沿著邊的長度, 往外的深度]；觸發區每塊 2 × 3 = 6 格、數字區一鍵 1 格（技能都是 1 格）
# 全部打開 = 主袋 36 + 觸發區 9 × 6 + 數字 3 = 93 格（Claude 暫定）
const MODE_BAGS := &"bags"       # 袋子分開（原本的觸發袋）
const MODE_MERGED := &"merged"   # 背包合併
const MERGED_ZONES: Array[Array] = [
	[&"hit", &"left", 0, 2, 3], [&"kill", &"left", 2, 2, 3], [&"cast", &"left", 4, 2, 3],
	[&"hit", &"right", 0, 2, 3], [&"kill", &"right", 2, 2, 3], [&"cast", &"right", 4, 2, 3],
	[&"hurt", &"bottom", 0, 2, 3], [&"roll", &"bottom", 2, 2, 3], [&"timer", &"bottom", 4, 2, 3],
	[&"key", &"top", 1, 1, 1], [&"key", &"top", 2, 1, 1], [&"key", &"top", 3, 1, 1],
]
const MERGED_START_CORE := Rect2i(1, 1, 3, 3)   # 開局主袋開的格子（主袋座標）
const MERGED_START_CLASS := 2                   # 職業那一區開幾格（貼著主袋的那一排，裝著起始技能）
const MERGED_START_KEYS := 1                    # 數字區開幾格（空的）
# 開格（許家慶 2026-11-06）：過小關、門的「袋子」獎勵隨機開 1 格（整個背包隨機）；Boss 與鐵砧給自選 1 格；
# 菁英怪原本掉袋子的改掉武器（機率照 ELITE_DROP，World.on_enemy_died）

# 取得：菁英怪（魔法 / 稀有）死掉時掉袋子的機率；掉哪種看怪的種類（沒列的隨機）
const ELITE_DROP := {&"magic": 0.25, &"rare": 0.6}
const ELITE_BAG := {&"bloater": &"kill", &"hound": &"roll", &"archer": &"hit", &"zombie": &"hurt", &"spider": &"timer", &"beetle": &"roll",
	&"spearman": &"hurt", &"bone_wheel": &"cast", &"grunt": &"hit"}
const CURSED_CHANCE := {&"small": 0.0, &"big": 0.15}   # 祭壇 / 石棺開出的遺物有這個機率把一個選項換成詛咒袋
const ANVIL := {"mul_step": 0.25, "max_mul": 2.0}   # 鐵砧：強化一次倍率 +0.25，最多 ×2

# 效果（觸發道具改寫）：顏色看道具本身的 bonds，空的是無色格
const EFFECTS := {
	&"explode": {"name": "爆炸"},
	&"frost": {"name": "寒氣"},
	&"chain_lightning": {"name": "連鎖閃電"},
	&"poison": {"name": "中毒"},
	&"freeze": {"name": "冰凍"},
	&"ignite": {"name": "點燃擴散"},
	&"ignite_area": {"name": "周圍燃燒"},
	&"fire_pool": {"name": "殘火"},
	&"heal": {"name": "回血"},
	&"throw_knife": {"name": "飛刀"},
	&"slash_wave": {"name": "斬波"},
	&"lightning_strike": {"name": "落雷"},
	&"slow_time": {"name": "緩時"},
	&"summon_skeleton": {"name": "召喚骷髏"},
	&"wisp": {"name": "放鬼火"},
	&"wisp_rally": {"name": "鬼火衝刺"},
	&"restore_mana": {"name": "回魔"},
	&"reflect": {"name": "反彈"},
}

# 效果的標籤（修飾蓋上去時照這個過濾，ItemDefs.mod_applies；Claude 暫定，2026-11-04 許家慶同意）：有範圍的算 area、會飛的算 projectile
const EFFECT_TAGS := {
	&"explode": [&"area"], &"frost": [&"area"], &"ignite_area": [&"area"], &"fire_pool": [&"area"], &"lightning_strike": [&"area"],
	&"chain_lightning": [&"projectile"], &"throw_knife": [&"projectile"], &"slash_wave": [&"projectile"], &"wisp": [&"projectile"],
	&"heal": [&"buff"], &"restore_mana": [&"buff"], &"slow_time": [&"buff"], &"wisp_rally": [&"buff"], &"summon_skeleton": [&"summon"],
	&"reflect": [&"melee"],
}
# 會打出一下傷害的效果：火焰化 / 霜化只對這些有作用（中毒、點燃、冰凍、殘火這類狀態效果不換屬性）
const EFFECT_TYPED: Array[StringName] = [&"explode", &"chain_lightning", &"reflect", &"lightning_strike", &"throw_knife", &"slash_wave", &"wisp"]

# 道具原本的動作 → 效果（沒列的同名）；寒氣合併「目標疊冰冷」與「周圍疊冰冷」
const EFFECT_OF_ACTION := {&"chill": &"frost", &"frost_nova": &"frost"}

# 原本是數值、改成效果的道具：id → [效果, 預設的袋子]（蝙蝠牙：每次命中回 1 生命 → 命中袋的回血）
const EFFECT_ITEMS := {&"bat_fang": [&"heal", &"hit"]}


# 道具原本的觸發時機對到哪種袋子；沒有對應（主袋的觸發、不是觸發）回傳 &""
static func bag_for_trigger(on: StringName) -> StringName:
	for kind: StringName in BAGS:
		if (BAGS[kind].on as Array).has(on):
			return kind
	return &""


static func effect_of_action(action: StringName) -> StringName:
	return EFFECT_OF_ACTION.get(action, action)


# 物品 id → 袋子種類；不是袋子回傳 &""
static func kind_of_item(id: StringName) -> StringName:
	for kind: StringName in BAGS:
		if BAGS[kind].item == id:
			return kind
	return &""


# 主袋一邊的長度（袋子沿著這邊排，offset + length 不能超過）
static func edge_length(side: StringName) -> int:
	return MAIN_SIZE.y if side in [&"left", &"right"] else MAIN_SIZE.x


# 新的袋子實例（沒接上：side 空的）；uid 由 Loadout 給
static func make(uid: StringName, kind: StringName, tier: StringName = &"small") -> Dictionary:
	var t: Dictionary = TIERS[tier]
	var length: int = BAGS[kind].get("length", t.length) + (t.length - TIERS.small.length if BAGS[kind].has("length") else 0)
	return {"uid": uid, "kind": kind, "tier": tier, "length": length, "depth": t.depth, "mul": t.mul,
		"side": &"", "offset": 0, "entries": [] as Array[Dictionary]}


# 袋子的顯示名稱（「大命中袋」「詛咒計時袋」）
static func bag_name(bag: Dictionary) -> String:
	return TIERS[bag.tier].name + BAGS[bag.kind].name


# 快照：[uid, kind, tier, side, offset, length, depth, mul, [[uid, id, x, y, rot, charges], …], 鎖著的格子 [x, y, x, y…]（背包合併）]
static func to_array(bag: Dictionary) -> Array:
	var entries := []
	for e: Dictionary in bag.entries:
		entries.append([String(e.uid), String(e.id), e.cell.x, e.cell.y, e.rot, e.get("charges", -1)])
	return [String(bag.uid), String(bag.kind), String(bag.tier), String(bag.side), bag.offset, bag.length, bag.depth, bag.mul, entries,
		cells_to_array(bag.get("locked", {}))]


# 鎖著的格子（cell → true）壓成 [x, y, x, y…] 給快照；反過來 cells_from_array
static func cells_to_array(cells: Dictionary) -> Array:
	var out := []
	for c: Vector2i in cells:
		out.append(c.x)
		out.append(c.y)
	return out


static func cells_from_array(a: Array) -> Dictionary:
	var out := {}
	for i in range(0, a.size() - 1, 2):
		out[Vector2i(int(a[i]), int(a[i + 1]))] = true
	return out


static func from_array(a: Array) -> Dictionary:
	var entries: Array[Dictionary] = []
	for x: Array in a[8]:
		var e := {"uid": StringName(x[0]), "id": StringName(x[1]), "cell": Vector2i(x[2], x[3]), "rot": int(x[4])}
		if int(x[5]) >= 0:
			e["charges"] = int(x[5])
		entries.append(e)
	var b := {"uid": StringName(a[0]), "kind": StringName(a[1]), "tier": StringName(a[2]), "side": StringName(a[3]), "offset": int(a[4]),
		"length": int(a[5]), "depth": int(a[6]), "mul": float(a[7]), "entries": entries}
	if a.size() > 9 and not (a[9] as Array).is_empty():
		b["locked"] = cells_from_array(a[9])
	return b
