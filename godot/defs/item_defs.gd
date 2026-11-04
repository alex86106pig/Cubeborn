# 物品資料：武器與道具共用一種格式（唯一編號、稀有度、占格形狀、效果列表）；道具清單見 docs/道具清單.md
# 測試用初稿：強度分數 power 是 Claude 暫定的平衡參考，等之後用實際戰鬥量測校正
# 格數看稀有度（RARITIES.cells：白 1、綠 2、藍 3、紫橘 4），check.gd 會驗證形狀格數符合；bonds = 屬於哪些羈絆（BondDefs，空的不進掉落池）
#
# 效果（effects 的每一筆）有四種寫法：
#   屬性      {"stat", "op", "value"}：放進身上就生效，以道具實例 id 為來源套進 sim/stats.gd（B6 已接上）
#   條件屬性  {"when", "stat", "op", "value", ...}：條件成立時才生效（例如低血、翻滾後幾秒），參數見 CONDITIONS
#   觸發      {"on", "do", "chance"?, ...}：放進觸發袋的效果（BagTriggers）：do 是動作、參數見 ACTIONS；on 只用來對到預設的袋子，chance 不看
#   能力      {"ability", ...}：新增一種能力（二段跳、護盾），參數見 ABILITIES
# 後三種有些已接上（IMPLEMENTED_*，效果在 sim/item_effects.gd），其他的只有資料：說明加「效果尚未實作」、寶箱不開出（LootDefs.drop_pool）
class_name ItemDefs

const BAG_SIZE := Vector2i(6, 1)   # 倉庫 6 格，每格放一件東西（不管形狀，Inventory.cells）
const BLOCK_HIT_DAMAGE_PCT := 1.0   # 招架成功算右鍵命中：沒有「那一下的傷害」，右邊命中袋用武器基礎傷害的 100%（Player.pct_damage）

# cells：道具占幾格（Build 改版第 5 步，要放得進武器格子）；同稀有度的形狀可以不同
const RARITIES := {
	&"white": {"name": "普通", "color": Color("d8d8d8"), "cells": 1},
	&"green": {"name": "優良", "color": Color("5fd35f"), "cells": 2},
	&"blue": {"name": "稀有", "color": Color("4fa3ff"), "cells": 3},
	&"purple": {"name": "史詩", "color": Color("b36bff"), "cells": 4},
	&"orange": {"name": "傳說", "color": Color("ff9a2e"), "cells": 4},
}

# 占格形狀：格子座標 (x, y)，左上角為 (0, 0)；放進背包時可旋轉（背包介面再做）
const SHAPES := {
	&"dot": [Vector2i(0, 0)],
	&"i2": [Vector2i(0, 0), Vector2i(1, 0)],
	&"i3": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
	&"l3": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)],
	&"i4": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
	&"o4": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	&"l4": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)],
	&"t4": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],
	&"s4": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],
	&"p5": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2)],
	&"t5": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(1, 2)],
	&"u5": [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
	&"r6": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)],
	&"cross6": [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(1, 3)],
	&"l6": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3)],
	&"h7": [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i(2, 2)],
}

# 條件屬性的條件；params = 必填參數
const CONDITIONS := {
	&"target_full_hp": {"name": "對滿血敵人", "params": []},
	&"hp_below": {"name": "自己生命低於門檻", "params": ["threshold"]},
	&"after_kill": {"name": "擊殺後一段時間", "params": ["duration"]},
	&"after_roll": {"name": "翻滾後一段時間", "params": ["duration"]},
	&"per_kill_stack": {"name": "本層每擊殺 1 隻疊一層", "params": ["max"]},
	&"from_elite": {"name": "來自精英怪", "params": []},
}

# 觸發時機
const TRIGGERS := {
	&"hit": {"name": "命中時"},
	&"attack": {"name": "普攻時"},
	&"kill": {"name": "擊殺時"},
	&"hurt": {"name": "受傷時"},
	&"hurt_melee": {"name": "受到近戰傷害時"},
	&"projectile_hit": {"name": "投射物命中時"},
	&"roll": {"name": "翻滾時"},
	&"lethal": {"name": "受到致命傷害時"},
	&"death": {"name": "死亡時"},
	&"interval": {"name": "每隔固定秒數", "params": ["period"]},
}

# 觸發後的動作；params = 必填參數
const ACTIONS := {
	&"explode": {"name": "爆炸", "params": []},
	&"chain_lightning": {"name": "連鎖閃電", "params": ["targets"]},
	&"poison": {"name": "中毒", "params": []},
	&"freeze": {"name": "冰凍", "params": ["duration"]},
	&"ignite": {"name": "點燃", "params": []},
	&"reflect": {"name": "反彈傷害", "params": ["ratio"]},
	&"heal_max_hp": {"name": "回復最大生命的比例", "params": ["ratio"]},
	&"restore_mana": {"name": "回復魔力", "params": ["ratio"]},   # ratio = 最大魔力的比例
	&"throw_knife": {"name": "追加飛刀", "params": []},
	&"wisp": {"name": "放出追蹤鬼火", "params": []},
	&"slash_wave": {"name": "射出斬波", "params": ["count", "damage_ratio"]},
	&"lightning_strike": {"name": "對附近敵人落雷", "params": []},
	&"summon_skeleton": {"name": "召喚骷髏僕從", "params": ["max"]},
	&"slow_time": {"name": "周圍時間變慢", "params": ["duration", "slow"]},
	&"cheat_death": {"name": "留 1 血並無敵", "params": ["invuln"]},
	&"revive": {"name": "復活", "params": []},
	# 羈絆道具（Build 改版第 5 步）：燃燒 / 冰冷的層數照 BondEffects（沒有那個羈絆最多 1 層）
	&"ignite_area": {"name": "周圍的怪疊燃燒", "params": ["radius", "stacks"]},
	&"fire_pool": {"name": "留下殘火", "params": ["radius", "duration", "burn_per_sec"]},
	&"chill": {"name": "目標疊冰冷", "params": ["stacks"]},
	&"frost_nova": {"name": "周圍的怪疊冰冷（以自己為中心）", "params": ["radius", "stacks"]},
	&"wisp_rally": {"name": "鬼火衝向最近的怪", "params": []},
}

const ABILITIES := {
	&"double_jump": {"name": "二段跳", "params": []},
	&"bone_shield": {"name": "自動回充的護盾", "params": ["ratio", "recharge_delay"]},
	&"wisp_orb": {"name": "繞著自己轉的鬼火", "params": ["count", "damage_type"]},   # BondEffects.wisp_plan
	&"wisp_frenzy": {"name": "鬼火擊殺後鬼火傷害變高", "params": []},
	&"skill_support": {"name": "輔助相鄰的技能", "params": ["mode", "tags"]},        # ActiveSlots.supports_of                 # 數值在 PROCS.wisp_frenzy
}

# 已接上的條件、觸發 + 動作（v0.33.0 第一批 8 個道具、G 第二批，sim/item_effects.gd）
const IMPLEMENTED_CONDITIONS: Array[StringName] = [&"target_full_hp", &"hp_below", &"after_kill", &"after_roll", &"per_kill_stack", &"from_elite"]
const IMPLEMENTED_TRIGGERS: Array[String] = ["kill|explode", "kill|heal_max_hp", "kill|restore_mana", "hit|chain_lightning", "hit|poison", "hit|freeze",
	"hurt_melee|reflect", "hurt|explode", "projectile_hit|explode", "hit|ignite",
	"attack|throw_knife", "attack|slash_wave", "interval|lightning_strike", "roll|slow_time",
	"lethal|cheat_death", "death|revive", "kill|wisp", "kill|summon_skeleton",
	"hit|ignite_area", "hit|fire_pool", "hit|chill", "interval|frost_nova", "roll|frost_nova", "kill|wisp_rally"]
const IMPLEMENTED_ABILITIES: Array[StringName] = [&"double_jump", &"bone_shield", &"wisp_orb", &"wisp_frenzy", &"skill_support"]   # 二段跳在 Player.air_jumps，護盾在 ItemEffects.absorb

# 觸發動作的數值（v0.33.0，說明沒寫到的由 Claude 暫定，試玩後再調）；damage_ratio 都是乘「觸發的那一下」的傷害
# 同一種動作有多個道具時機率相加（最多 100%）、沒有機率的（回血）效果相加
const PROCS := {
	&"explode": {"radius": 2.5, "damage_ratio": 0.5, "knockback": 6.0, "color": Color("ff9a2e")},   # 擊殺那一下的 50%
	&"chain_lightning": {"jump_range": 5.0, "damage_ratio": 0.5, "color": Color("9fd8ff")},       # 每跳 50%，不會打同一隻兩次
	&"poison": {"duration": 3.0, "total_ratio": 0.6, "tick": 0.5, "color": Color("7cff5a")},       # 3 秒共 60%，每 0.5 秒扣一次；再中毒重新計時、取較高的
	&"freeze": {"color": Color("a8e6ff")},   # 冰凍時不能動、不出招（Boss 不會被冰凍）
	# ---- 第二批（G，2026-10-27 Claude 暫定）；icd = 內部冷卻秒數（快速武器不會觸發過頻，ItemEffects.icd_ready）----
	&"life_on_hit": {"icd": 0.3},   # 蝙蝠牙：命中回復每 0.3 秒最多一次
	&"mana_on_hit": {"icd": 0.3},   # 武器詞條「命中回魔」：同上
	&"reflect": {"color": Color("d0d0d0")},   # 荊棘鎖甲：反彈實際扣的血 × 道具的 ratio
	&"hurt_explode": {"radius": 3.0, "icd": 0.5, "color": Color("ff5a3a")},   # 王墓之心：以自己為中心、扣護甲前的受傷量 × damage_ratio
	&"ignite": {"pct_per_sec": 0.15, "duration": 3.0, "spread_interval": 1.0, "spread_range": 2.0},   # 永恆之焰：命中那一下 15% / 秒 × 3 秒（同火把）；每 1 秒傳給 2 單位內一隻
	# 飛刀 / 斬波 / 落雷的傷害是手上武器基礎傷害的百分比（Player.pct_damage，含攻擊力與物理 / 屬性傷害）
	&"throw_knife": {"icd": 0.3, "damage_pct": 0.6, "speed": 18.0, "range": 10.0, "radius": 0.2, "color": Color("c8d0dc"), "visual": &"arrow", "sfx": "arrowShot"},
	&"slash_wave": {"icd": 0.3, "spread": 0.2618, "speed": 16.0, "range": 8.0, "radius": 0.45, "color": Color("b36bff"), "visual": &"orb", "sfx": "arcaneCast"},   # 穿透；spread 0.2618 = 15°
	&"lightning_strike": {"range": 8.0, "targets": 3, "damage_pct": 1.5, "radius": 0.8, "color": Color("9fd8ff")},
	&"slow_time": {"radius": 5.0, "boss_mul": 0.6, "color": Color("8fa8ff")},   # 一般怪移速與出招 × (1 − slow)，Boss × boss_mul
	&"revive": {"hp_ratio": 0.5, "invuln": 2.0, "color": Color("ffe08a")},   # 復活十字；守護亡靈的無敵秒數在道具資料
	# 鬼火燈籠：擊殺那一下的 80%；速度 8、飛 4 秒、每秒最多轉 4 弧度追 10 單位內最近的怪；每人同時最多 6 顆
	&"wisp": {"damage_ratio": 0.8, "speed": 8.0, "life": 4.0, "turn_rate": 4.0, "seek_range": 10.0, "max": 6, "radius": 0.22, "color": Color("7dffb0")},
	# 亡者大軍的骷髏僕從數值在 EnemyDefs.ENEMIES.minion
	&"wisp_frenzy": {"duration": 5.0, "damage_mul": 1.5},   # 噬魂燈：鬼火擊殺後 5 秒，鬼火傷害 ×1.5
}

# kind：&"item" 道具 / &"weapon" 武器（weapon 對應 WeaponDefs，數值在那邊，這裡只放背包用的欄位）/ &"skill" 技能（只能鑲在寶石座，SkillDefs 同 id）
# power 只有道具需要；武器的格數之後和背包一起定
const ITEMS := {
	# ---- 觸發袋（kind bag，BagDefs.BAGS）：掉在地上、放倉庫、遺物的選項；撿起來是 BagDefs.make 的袋子實例，倉庫裡占 2 格 ----
	&"bag_cast": {"kind": &"bag", "name": "出手袋", "rarity": &"green", "shape": &"i2", "bonds": [], "desc": "接在左 / 右邊：普攻 / 右鍵出手時發動裡面的東西", "effects": []},
	&"bag_hit": {"kind": &"bag", "name": "命中袋", "rarity": &"green", "shape": &"i2", "bonds": [], "desc": "接在左 / 右邊：普攻 / 右鍵打中時發動裡面的東西", "effects": []},
	&"bag_kill": {"kind": &"bag", "name": "擊殺袋", "rarity": &"green", "shape": &"i2", "bonds": [], "desc": "接在左 / 右邊：普攻 / 右鍵打死怪時發動裡面的東西", "effects": []},
	&"bag_hurt": {"kind": &"bag", "name": "受傷袋", "rarity": &"green", "shape": &"i2", "bonds": [], "desc": "接在下方：自己被打中時發動裡面的東西", "effects": []},
	&"bag_roll": {"kind": &"bag", "name": "翻滾袋", "rarity": &"green", "shape": &"i2", "bonds": [], "desc": "接在下方：翻滾時發動裡面的東西", "effects": []},
	&"bag_timer": {"kind": &"bag", "name": "計時袋", "rarity": &"green", "shape": &"i2", "bonds": [], "desc": "接在下方：每 3 秒發動裡面的東西", "effects": []},
	&"bag_key": {"kind": &"bag", "name": "按鍵袋", "rarity": &"green", "shape": &"i2", "bonds": [], "desc": "接在上方：按數字鍵發動裡面的東西（由左到右是 1~3）", "effects": []},

	# ---- 武器 ----
	&"longsword": {"kind": &"weapon", "name": "長劍", "rarity": &"white", "shape": &"i3", "weapon": &"longsword",
		"desc": "單手。左鍵三段斬擊；沒有副手時按住右鍵蓄力突刺", "effects": []},
	&"woodShield": {"kind": &"weapon", "name": "木盾", "rarity": &"white", "shape": &"o4", "weapon": &"woodShield",
		"desc": "副手。按住右鍵格擋，格擋中左鍵招架", "effects": []},
	&"staff": {"kind": &"weapon", "name": "法杖", "rarity": &"white", "shape": &"i4", "weapon": &"staff",
		"desc": "左鍵魔彈、右鍵奧術爆裂", "effects": []},
	&"shortbow": {"kind": &"weapon", "name": "短弓", "rarity": &"white", "shape": &"l4", "weapon": &"shortbow",
		"desc": "左鍵快射（可按住連射）、右鍵扇形散射 5 支", "effects": []},
	&"dagger": {"kind": &"weapon", "name": "匕首", "rarity": &"white", "shape": &"i2", "weapon": &"dagger",
		"desc": "單手，也能當副手。左鍵三連刺、右鍵影步到怪背後背刺；兩手都拿匕首時左鍵換成五連刺", "effects": []},
	&"scepter": {"kind": &"weapon", "name": "驅魔權杖", "rarity": &"white", "shape": &"l3", "weapon": &"scepter",
		"desc": "左鍵聖光敲擊（神聖、擊退）、右鍵聖光圈（隊友回血、亡靈受傷）", "effects": []},
	&"torch": {"kind": &"weapon", "name": "火把", "rarity": &"white", "shape": &"i3", "weapon": &"torch",
		"desc": "左鍵揮擊並點燃；右鍵舉起火把（準備姿態：左鍵插火把、右鍵噴火），火光全隊看得到", "effects": []},
	&"shovel": {"kind": &"weapon", "name": "鐵鏟", "rarity": &"white", "shape": &"l4", "weapon": &"shovel",
		"desc": "左鍵鏟地（窄、遠、擊退）；右鍵鏟起面前一隻怪：再按左鍵拋出、右鍵埋進土裡", "effects": []},
	&"longbow": {"kind": &"weapon", "name": "長弓", "rarity": &"white", "shape": &"i4", "weapon": &"longbow",
		"desc": "左鍵重射（可擊退）、按住右鍵蓄力、放開射出穿透箭", "effects": []},

	# ---- 白色：基本屬性 ----
	&"worn_boots": {"kind": &"item", "name": "磨損皮靴", "rarity": &"white", "power": 1.6, "shape": &"dot", "bonds": [],
		"desc": "移速 +8%", "effects": [{"stat": &"move_speed", "op": Stats.PCT, "value": 0.08}]},
	&"whetstone": {"kind": &"item", "name": "磨刀石", "rarity": &"white", "power": 1.6, "shape": &"dot", "bonds": [&"phys"],
		"desc": "攻擊力 +8%", "effects": [{"stat": &"damage", "op": Stats.PCT, "value": 0.08}]},
	&"light_gloves": {"kind": &"item", "name": "輕巧手套", "rarity": &"white", "power": 2.0, "shape": &"dot", "bonds": [&"phys"],
		"desc": "攻速 +10%", "effects": [{"stat": &"attack_speed", "op": Stats.PCT, "value": 0.1}]},
	&"stale_bread": {"kind": &"item", "name": "乾硬麵包", "rarity": &"white", "power": 2.0, "shape": &"dot", "bonds": [&"guard"],
		"desc": "最大生命 +20", "effects": [{"stat": &"max_hp", "op": Stats.ADD, "value": 20.0}]},
	&"bandage_roll": {"kind": &"item", "name": "繃帶捲", "rarity": &"white", "power": 2.0, "shape": &"dot", "bonds": [&"guard"],
		"desc": "每秒回復 1 生命", "effects": [{"stat": &"hp_regen", "op": Stats.ADD, "value": 1.0}]},
	&"rusty_breastplate": {"kind": &"item", "name": "鏽鐵護心", "rarity": &"white", "power": 1.5, "shape": &"dot", "bonds": [&"guard"],
		"desc": "護甲 +8", "effects": [{"stat": &"armor", "op": Stats.ADD, "value": 8.0}]},
	&"loaded_dice": {"kind": &"item", "name": "灌鉛骰子", "rarity": &"white", "power": 0.6, "shape": &"dot", "bonds": [&"phys"],
		"desc": "爆擊率 +6%", "effects": [{"stat": &"crit_chance", "op": Stats.ADD, "value": 0.06}]},
	&"bat_fang": {"kind": &"item", "name": "蝙蝠牙", "rarity": &"white", "power": 1.5, "shape": &"dot", "bonds": [],
		"desc": "回復 1 生命", "effects": [{"stat": &"life_on_hit", "op": Stats.ADD, "value": 1.0}]},
	&"grave_purse": {"kind": &"item", "name": "盜墓者錢袋", "rarity": &"white", "power": 1.0, "shape": &"dot", "bonds": [],
		"desc": "靈魂獲得 +15%", "effects": [{"stat": &"soul_gain", "op": Stats.PCT, "value": 0.15}]},
	&"light_feather": {"kind": &"item", "name": "輕羽", "rarity": &"white", "power": 0.8, "shape": &"dot", "bonds": [],
		"desc": "翻滾冷卻 −10%", "effects": [{"stat": &"roll_cooldown", "op": Stats.MUL, "value": 0.9}]},
	&"lead_weight": {"kind": &"item", "name": "鉛墜", "rarity": &"white", "power": 0.8, "shape": &"dot", "bonds": [&"phys"],
		"desc": "擊退 +20%", "effects": [{"stat": &"knockback", "op": Stats.PCT, "value": 0.2}]},
	&"wormwood": {"kind": &"item", "name": "苦艾酒", "rarity": &"white", "power": 0.8, "shape": &"dot", "bonds": [],
		"desc": "回魔 +30%", "effects": [{"stat": &"mana_regen", "op": Stats.PCT, "value": 0.3}]},
	&"powder_pouch": {"kind": &"item", "name": "火藥包", "rarity": &"white", "power": 1.2, "shape": &"dot", "bonds": [&"fire"],
		"desc": "小爆炸", "effects": [{"on": &"kill", "chance": 0.1, "do": &"explode"}]},
	&"hound_collar": {"kind": &"item", "name": "獵犬項圈", "rarity": &"white", "power": 1.0, "shape": &"dot", "bonds": [&"phys"],
		"desc": "對滿血敵人傷害 +25%", "effects": [{"when": &"target_full_hp", "stat": &"damage", "op": Stats.PCT, "value": 0.25}]},
	&"vigil_candle": {"kind": &"item", "name": "守夜蠟燭", "rarity": &"white", "power": 0.5, "shape": &"dot", "bonds": [],
		"desc": "視野距離與角度 +10%", "effects": [{"stat": &"vision", "op": Stats.PCT, "value": 0.1}]},

	# ---- 綠色：條件與觸發 ----
	&"thunder_rune": {"kind": &"item", "name": "雷鳴符文", "rarity": &"green", "power": 3.0, "shape": &"i2", "bonds": [],
		"desc": "連鎖閃電（3 個目標）", "effects": [{"on": &"hit", "chance": 0.1, "do": &"chain_lightning", "targets": 3}]},
	&"venom_blade": {"kind": &"item", "name": "淬毒刀刃", "rarity": &"green", "power": 3.0, "shape": &"i2", "bonds": [],
		"desc": "讓目標中毒（持續傷害）", "effects": [{"on": &"hit", "chance": 0.15, "do": &"poison"}]},
	&"war_drum": {"kind": &"item", "name": "戰鼓", "rarity": &"green", "power": 2.5, "shape": &"i2", "bonds": [&"phys"],
		"desc": "擊殺後 3 秒攻速 +30%", "effects": [{"when": &"after_kill", "duration": 3.0, "stat": &"attack_speed", "op": Stats.PCT, "value": 0.3}]},
	&"berserker_charm": {"kind": &"item", "name": "狂戰士護符", "rarity": &"green", "power": 2.5, "shape": &"i2", "bonds": [&"phys"],
		"desc": "生命低於 35% 時傷害 +25%", "effects": [{"when": &"hp_below", "threshold": 0.35, "stat": &"damage", "op": Stats.PCT, "value": 0.25}]},
	&"thorn_mail": {"kind": &"item", "name": "荊棘鎖甲", "rarity": &"green", "power": 3.0, "shape": &"i2", "bonds": [&"guard"],
		"desc": "把受到傷害的 50% 反彈給目標", "effects": [{"on": &"hurt_melee", "do": &"reflect", "ratio": 0.5}]},
	&"hunter_cloak": {"kind": &"item", "name": "獵人斗篷", "rarity": &"green", "power": 3.0, "shape": &"i2", "bonds": [],
		"desc": "翻滾後 1.5 秒內爆擊率 +50%", "effects": [{"when": &"after_roll", "duration": 1.5, "stat": &"crit_chance", "op": Stats.ADD, "value": 0.5}]},
	&"bone_buckler": {"kind": &"item", "name": "骨製護盾", "rarity": &"green", "power": 3.5, "shape": &"i2", "bonds": [&"guard"],
		"desc": "護盾為最大生命的 8%，3 秒沒受傷就自動回充", "effects": [{"ability": &"bone_shield", "ratio": 0.08, "recharge_delay": 3.0}]},
	&"sleeve_knife": {"kind": &"item", "name": "袖中飛刀", "rarity": &"green", "power": 3.0, "shape": &"i2", "bonds": [&"phys"],
		"desc": "追加一把飛刀", "effects": [{"on": &"attack", "chance": 0.2, "do": &"throw_knife"}]},
	&"wisp_lantern": {"kind": &"item", "name": "鬼火燈籠", "rarity": &"green", "power": 3.5, "shape": &"i2", "bonds": [&"wisp"],
		"desc": "放出會追蹤敵人的鬼火", "effects": [{"on": &"kill", "do": &"wisp"}]},
	&"lockpick": {"kind": &"item", "name": "撬鎖工具", "rarity": &"green", "power": 1.5, "shape": &"i2", "bonds": [],
		"desc": "祭壇與石棺價格 −10%", "effects": [{"stat": &"chest_price", "op": Stats.MUL, "value": 0.9}]},
	&"lodestone": {"kind": &"item", "name": "磁石", "rarity": &"green", "power": 1.0, "shape": &"i2", "bonds": [],
		"desc": "撿東西的範圍 +50%", "effects": [{"stat": &"pickup_radius", "op": Stats.PCT, "value": 0.5}]},
	&"iron_cloak": {"kind": &"item", "name": "鐵皮斗篷", "rarity": &"green", "power": 2.3, "shape": &"i2", "bonds": [&"guard"],
		"desc": "受到投射物傷害 −15%", "effects": [{"stat": &"projectile_damage_taken", "op": Stats.MUL, "value": 0.85}]},

	# ---- 藍色：改變打法 ----
	&"frost_heart": {"kind": &"item", "name": "霜之心", "rarity": &"blue", "power": 5.0, "shape": &"l3", "bonds": [&"cold"],
		"desc": "冰凍目標 1.5 秒", "effects": [{"on": &"hit", "chance": 0.1, "do": &"freeze", "duration": 1.5}]},
	&"soul_scythe": {"kind": &"item", "name": "吸魂鐮", "rarity": &"blue", "power": 4.5, "shape": &"l3", "bonds": [],
		"desc": "回復 15% 最大魔力", "effects": [{"on": &"kill", "do": &"restore_mana", "ratio": 0.15}]},
	&"twin_leap_boots": {"kind": &"item", "name": "雙躍之靴", "rarity": &"blue", "power": 4.0, "shape": &"i3", "bonds": [],
		"desc": "可以二段跳", "effects": [{"ability": &"double_jump"}]},
	&"blast_quiver": {"kind": &"item", "name": "爆裂箭袋", "rarity": &"blue", "power": 5.0, "shape": &"i3", "bonds": [&"fire"],
		"desc": "在目標身上爆炸", "effects": [{"on": &"projectile_hit", "do": &"explode"}]},
	&"gale_charm": {"kind": &"item", "name": "疾風護符", "rarity": &"blue", "power": 5.0, "shape": &"i3", "bonds": [],
		"desc": "翻滾多 1 次充能", "effects": [{"stat": &"roll_charges", "op": Stats.ADD, "value": 1.0}]},
	&"pact_of_dead": {"kind": &"item", "name": "亡者之契", "rarity": &"blue", "power": 6.0, "shape": &"l3", "bonds": [&"phys"],
		"desc": "本層每擊殺 1 隻傷害 +1%（最多 30%）", "effects": [{"when": &"per_kill_stack", "max": 30, "stat": &"damage", "op": Stats.PCT, "value": 0.01}]},
	&"guardian_spirit": {"kind": &"item", "name": "守護亡靈", "rarity": &"blue", "power": 5.0, "shape": &"l3", "bonds": [&"guard"],
		"desc": "受到致命傷害時留 1 血並無敵 2 秒，每層一次", "effects": [{"on": &"lethal", "do": &"cheat_death", "invuln": 2.0, "per_floor": 1}]},
	&"thunder_bell": {"kind": &"item", "name": "雷霆鈴", "rarity": &"blue", "power": 5.5, "shape": &"l3", "bonds": [],
		"desc": "降下一道落雷", "effects": [{"on": &"interval", "period": 5.0, "do": &"lightning_strike"}]},
	&"greedy_hand": {"kind": &"item", "name": "貪婪之手", "rarity": &"blue", "power": 2.5, "shape": &"i3", "bonds": [],
		"desc": "精英怪給的靈魂 ×2", "effects": [{"when": &"from_elite", "stat": &"soul_gain", "op": Stats.MUL, "value": 2.0}]},

	# ---- 紫色：強力 ----
	&"resurrection_cross": {"kind": &"item", "name": "復活十字", "rarity": &"purple", "power": 9.0, "shape": &"t4", "bonds": [&"guard"],
		"desc": "死亡時復活一次，用完碎掉並空出格子", "effects": [{"on": &"death", "do": &"revive", "consume": true}]},
	&"rift_blade": {"kind": &"item", "name": "裂空之刃", "rarity": &"purple", "power": 9.0, "shape": &"l4", "bonds": [&"phys"],
		"desc": "射出 2 道會穿透的斬波", "effects": [{"on": &"attack", "do": &"slash_wave", "count": 2, "damage_ratio": 0.5}]},
	&"blood_crown": {"kind": &"item", "name": "血族王冠", "rarity": &"purple", "power": 6.0, "shape": &"o4", "bonds": [],
		"desc": "造成傷害的 3% 轉為回復生命", "effects": [{"stat": &"lifesteal", "op": Stats.ADD, "value": 0.03}]},
	&"hourglass": {"kind": &"item", "name": "時之沙漏", "rarity": &"purple", "power": 6.0, "shape": &"t4", "bonds": [],
		"desc": "耗魔 −25%", "effects": [{"stat": &"mana_cost", "op": Stats.MUL, "value": 0.75}]},
	&"obsidian_skin": {"kind": &"item", "name": "黑曜石皮膚", "rarity": &"purple", "power": 7.5, "shape": &"s4", "bonds": [&"guard"],
		"desc": "受到傷害 −20%，但移速 −5%", "effects": [
			{"stat": &"damage_taken", "op": Stats.MUL, "value": 0.8},
			{"stat": &"move_speed", "op": Stats.PCT, "value": -0.05}]},
	&"army_of_dead": {"kind": &"item", "name": "亡者大軍", "rarity": &"purple", "power": 8.0, "shape": &"o4", "bonds": [],
		"desc": "召喚骷髏僕從（最多 3 隻），僕從倒下時碎骨爆裂", "effects": [{"on": &"kill", "chance": 0.2, "do": &"summon_skeleton", "max": 3}]},

	# ---- 橘色：改變整個 build ----
	&"tomb_heart": {"kind": &"item", "name": "王墓之心", "rarity": &"orange", "power": 10.0, "shape": &"o4", "bonds": [&"guard", &"fire"],
		"desc": "對周圍爆炸", "effects": [{"on": &"hurt", "do": &"explode", "damage_ratio": 3.0}]},
	&"eternal_flame": {"kind": &"item", "name": "永恆之焰", "rarity": &"orange", "power": 12.0, "shape": &"s4", "bonds": [&"fire"],
		"desc": "點燃目標，燃燒會擴散到附近敵人", "effects": [{"on": &"hit", "do": &"ignite", "spread": true}]},
	&"stasis_watch": {"kind": &"item", "name": "停滯懷錶", "rarity": &"orange", "power": 10.0, "shape": &"t4", "bonds": [&"cold"],
		"desc": "周圍時間變慢 2 秒（敵人慢 70%）", "effects": [{"on": &"roll", "do": &"slow_time", "duration": 2.0, "slow": 0.7}]},

	# ---- 羈絆道具（Build 改版第 5 步，效果 Claude 暫定）：取代移出掉落池的 18 個（那些留給之後的閃電、腐毒、閃避等羈絆）----
	&"ember_core": {"kind": &"item", "name": "炭心", "rarity": &"white", "power": 1.5, "shape": &"dot", "bonds": [&"fire"],
		"desc": "普攻附加 10% 火焰傷害", "effects": [{"stat": &"added_fire", "op": Stats.ADD, "value": 0.1}]},
	&"lamp_oil": {"kind": &"item", "name": "燈油", "rarity": &"white", "power": 1.2, "shape": &"dot", "bonds": [&"fire"],
		"desc": "燃燒傷害 +25%", "effects": [{"stat": &"burn_damage", "op": Stats.PCT, "value": 0.25}]},
	&"frost_crystal": {"kind": &"item", "name": "霜晶", "rarity": &"white", "power": 1.5, "shape": &"dot", "bonds": [&"cold"],
		"desc": "普攻附加 10% 冰霜傷害", "effects": [{"stat": &"added_cold", "op": Stats.ADD, "value": 0.1}]},
	&"cold_iron_charm": {"kind": &"item", "name": "寒鐵護符", "rarity": &"white", "power": 1.2, "shape": &"dot", "bonds": [&"cold"],
		"desc": "冰冷的怪對你造成的傷害 −15%", "effects": [{"stat": &"chilled_damage_taken", "op": Stats.MUL, "value": 0.85}]},
	&"white_wisp_lamp": {"kind": &"item", "name": "白鬼火燈", "rarity": &"white", "power": 1.5, "shape": &"dot", "bonds": [&"wisp"],
		"desc": "帶 1 顆秘術鬼火繞著你轉", "effects": [{"ability": &"wisp_orb", "count": 1, "damage_type": &"arcane"}]},
	&"wick": {"kind": &"item", "name": "燈芯", "rarity": &"white", "power": 1.0, "shape": &"dot", "bonds": [&"wisp"],
		"desc": "鬼火傷害 +20%", "effects": [{"stat": &"wisp_damage", "op": Stats.PCT, "value": 0.2}]},
	&"incense_burner": {"kind": &"item", "name": "焚香爐", "rarity": &"green", "power": 3.0, "shape": &"i2", "bonds": [&"fire"],
		"desc": "讓周圍 2 單位的怪各疊 1 層燃燒", "effects": [{"on": &"hit", "chance": 0.25, "do": &"ignite_area", "radius": 2.0, "stacks": 1}]},
	&"oil_jar": {"kind": &"item", "name": "火油罐", "rarity": &"green", "power": 3.0, "shape": &"i2", "bonds": [&"fire"],
		"desc": "在目標腳下留 3 秒殘火，站在上面的怪每秒疊 1 層燃燒", "effects": [{"on": &"hit", "chance": 0.2, "do": &"fire_pool", "radius": 1.5, "duration": 3.0, "burn_per_sec": 1.0}]},
	&"ice_coffin_nail": {"kind": &"item", "name": "冰棺釘", "rarity": &"green", "power": 3.0, "shape": &"i2", "bonds": [&"cold"],
		"desc": "目標冰冷 +2 層", "effects": [{"on": &"hit", "do": &"chill", "stacks": 2}]},
	&"blue_wisp_lamp": {"kind": &"item", "name": "藍鬼火燈", "rarity": &"green", "power": 3.0, "shape": &"i2", "bonds": [&"wisp", &"cold"],
		"desc": "帶 1 顆冰霜鬼火繞著你轉（也算冰霜）", "effects": [{"ability": &"wisp_orb", "count": 1, "damage_type": &"cold"}]},
	&"red_wisp_lamp": {"kind": &"item", "name": "紅鬼火燈", "rarity": &"green", "power": 3.0, "shape": &"i2", "bonds": [&"wisp", &"fire"],
		"desc": "帶 1 顆火焰鬼火繞著你轉（也算火焰）", "effects": [{"ability": &"wisp_orb", "count": 1, "damage_type": &"fire"}]},
	&"frost_bell": {"kind": &"item", "name": "寒霜鈴", "rarity": &"blue", "power": 4.5, "shape": &"l3", "bonds": [&"cold"],
		"desc": "讓周圍 4 單位的怪冰冷 +2 層", "effects": [{"on": &"interval", "period": 5.0, "do": &"frost_nova", "radius": 4.0, "stacks": 2}]},
	&"winter_charm": {"kind": &"item", "name": "凜冬護符", "rarity": &"blue", "power": 4.0, "shape": &"i3", "bonds": [&"cold"],
		"desc": "冰冷每層的減速再 +4%", "effects": [{"stat": &"chill_slow", "op": Stats.ADD, "value": 0.04}]},
	&"frost_boots": {"kind": &"item", "name": "霜行靴", "rarity": &"blue", "power": 4.0, "shape": &"l3", "bonds": [&"cold"],
		"desc": "周圍 2 單位的怪冰冷 +1 層", "effects": [{"on": &"roll", "do": &"frost_nova", "radius": 2.0, "stacks": 1}]},
	&"soul_banner": {"kind": &"item", "name": "招魂幡", "rarity": &"blue", "power": 4.0, "shape": &"i3", "bonds": [&"wisp"],
		"desc": "所有鬼火衝向最近的怪", "effects": [{"on": &"kill", "do": &"wisp_rally"}]},
	&"wisp_jar": {"kind": &"item", "name": "鬼火罐", "rarity": &"blue", "power": 4.5, "shape": &"l3", "bonds": [&"wisp"],
		"desc": "帶 2 顆秘術鬼火繞著你轉", "effects": [{"ability": &"wisp_orb", "count": 2, "damage_type": &"arcane"}]},
	&"nether_lamp": {"kind": &"item", "name": "冥燈", "rarity": &"purple", "power": 6.0, "shape": &"t4", "bonds": [&"wisp"],
		"desc": "鬼火打中怪時回復 1 生命", "effects": [{"stat": &"wisp_life_on_hit", "op": Stats.ADD, "value": 1.0}]},
	&"soul_eater_lamp": {"kind": &"item", "name": "噬魂燈", "rarity": &"purple", "power": 7.0, "shape": &"o4", "bonds": [&"wisp"],
		"desc": "鬼火擊殺時，5 秒內鬼火傷害 +50%", "effects": [{"ability": &"wisp_frenzy"}]},

	# ---- 技能（Build 改版第 7 步）：只能鑲在寶石座、能用的武器與動作在 SkillDefs（同一個 id）----
	&"plantTorch": {"kind": &"skill", "name": "插火把", "rarity": &"white", "shape": &"dot", "desc": "插在地上照亮周圍、全隊看得到；每層 3 次（火把自帶）", "effects": []},
	&"whirlwind": {"kind": &"skill", "name": "旋風斬", "rarity": &"white", "shape": &"dot", "desc": "原地轉一圈，砍四周的怪", "effects": []},
	&"charge_slash": {"kind": &"skill", "name": "衝鋒斬", "rarity": &"white", "shape": &"dot", "desc": "往前衝 5 單位，砍到路上的怪", "effects": []},
	&"sword_wave": {"kind": &"skill", "name": "劍氣", "rarity": &"white", "shape": &"dot", "desc": "揮劍射出一道會穿透的劍氣", "effects": []},
	&"ambush": {"kind": &"skill", "name": "背刺突襲", "rarity": &"white", "shape": &"dot", "desc": "瞬移到 6 單位內最近的怪背後，刺一刀，必爆擊", "effects": []},
	&"knife_fan": {"kind": &"skill", "name": "扇形飛刀", "rarity": &"white", "shape": &"dot", "desc": "往前方扇形射出 5 把飛刀", "effects": []},
	&"smoke_bomb": {"kind": &"skill", "name": "煙霧彈", "rarity": &"white", "shape": &"dot", "desc": "腳下放煙霧 3 秒：裡面的怪攻擊會打偏，自己閃避 +30%", "effects": []},
	&"fire_nova": {"kind": &"skill", "name": "火焰新星", "rarity": &"white", "shape": &"dot", "desc": "以自己為中心爆一圈火，點燃周圍的怪", "effects": []},
	&"fire_flask": {"kind": &"skill", "name": "火瓶", "rarity": &"white", "shape": &"dot", "desc": "丟一瓶火油，落地後燒 4 秒", "effects": []},
	&"flame_dash": {"kind": &"skill", "name": "火焰衝刺", "rarity": &"white", "shape": &"dot", "desc": "往前衝，經過的地方留下一條火", "effects": []},
	&"shield_charge": {"kind": &"skill", "name": "盾衝", "rarity": &"white", "shape": &"dot", "desc": "舉盾往前衝，撞到的怪被擊退並暈眩 0.8 秒", "effects": []},
	&"taunt": {"kind": &"skill", "name": "嘲諷", "rarity": &"white", "shape": &"dot", "desc": "周圍的怪 3 秒內改打你，這段時間你受到的傷害 −33%", "effects": []},
	&"shield_slam": {"kind": &"skill", "name": "震盾", "rarity": &"white", "shape": &"dot", "desc": "敲盾放出震波，周圍的怪被擊退並暈眩 0.5 秒", "effects": []},
	&"frost_nova": {"kind": &"skill", "name": "冰霜新星", "rarity": &"white", "shape": &"dot", "desc": "身邊爆一圈冰霜，周圍的怪冰冷 +2 層", "effects": []},
	&"meteor": {"kind": &"skill", "name": "隕石", "rarity": &"white", "shape": &"dot", "desc": "準星的位置延遲 1 秒後大爆炸", "effects": []},
	&"chain_bolt": {"kind": &"skill", "name": "閃電鏈", "rarity": &"white", "shape": &"dot", "desc": "射出一道閃電，在怪之間跳 4 次", "effects": []},
	&"holy_pillar": {"kind": &"skill", "name": "聖光柱", "rarity": &"white", "shape": &"dot", "desc": "準星的位置落下光柱：怪受神聖傷害、隊友回血", "effects": []},
	&"bone_guard": {"kind": &"skill", "name": "骸骨衛士", "rarity": &"white", "shape": &"dot", "desc": "召喚 2 隻骷髏僕從，存在 10 秒", "effects": []},
	&"blessing": {"kind": &"skill", "name": "祝福", "rarity": &"white", "shape": &"dot", "desc": "5 秒內自己和附近隊友的攻速 +25%", "effects": []},
	&"volley": {"kind": &"skill", "name": "連珠箭", "rarity": &"white", "shape": &"dot", "desc": "對前方快速連射 5 箭", "effects": []},
	&"leap_shot": {"kind": &"skill", "name": "後跳射", "rarity": &"white", "shape": &"dot", "desc": "往後跳 4 單位，同時扇形射出 3 箭", "effects": []},
	&"lightning_arrow": {"kind": &"skill", "name": "閃電箭", "rarity": &"white", "shape": &"dot", "desc": "射中後電到附近 3 隻怪", "effects": []},
	&"arrow_rain": {"kind": &"skill", "name": "箭雨", "rarity": &"white", "shape": &"dot", "desc": "準星的位置下 2 秒箭雨", "effects": []},
	&"snipe": {"kind": &"skill", "name": "狙擊", "rarity": &"white", "shape": &"dot", "desc": "蓄力 0.8 秒，射出一支會穿透的重箭", "effects": []},
	&"frost_arrow": {"kind": &"skill", "name": "冰霜箭", "rarity": &"white", "shape": &"dot", "desc": "射中後炸開，周圍的怪冰冷 +2 層", "effects": []},
	&"ground_slam": {"kind": &"skill", "name": "震地", "rarity": &"white", "shape": &"dot", "desc": "往地上一砸，前方扇形的怪被擊退並暈眩 0.5 秒", "effects": []},
	&"dirt_toss": {"kind": &"skill", "name": "甩土", "rarity": &"white", "shape": &"dot", "desc": "甩出一團土塊，炸開後周圍的怪短暫暈眩", "effects": []},
	&"burrow": {"kind": &"skill", "name": "掘地", "rarity": &"white", "shape": &"dot", "desc": "鑽進土裡無敵 1 秒、往前移動 6 單位，出土時震開周圍的怪", "effects": []},

	# ---- 魔力道具：回魔與最大魔力（照 is_mana_item 掉）；魔力照武器之後一律寫 %（固定加值放在魔力少的武器上會變很強，許家慶 2026-11-04）----
	&"mana_shard": {"kind": &"item", "name": "藍晶碎片", "rarity": &"white", "power": 0.8, "shape": &"dot", "bonds": [],
		"desc": "最大魔力 +15%", "effects": [{"stat": &"max_mana", "op": Stats.PCT, "value": 0.15}]},
	&"prayer_beads": {"kind": &"item", "name": "冥想念珠", "rarity": &"green", "power": 2.0, "shape": &"i2", "bonds": [],
		"desc": "回魔 +60%", "effects": [{"stat": &"mana_regen", "op": Stats.PCT, "value": 0.6}]},
	&"mana_crystal": {"kind": &"item", "name": "魔力水晶", "rarity": &"green", "power": 2.0, "shape": &"i2", "bonds": [],
		"desc": "最大魔力 +30%", "effects": [{"stat": &"max_mana", "op": Stats.PCT, "value": 0.3}]},
	&"mage_heart": {"kind": &"item", "name": "法師之心", "rarity": &"blue", "power": 4.0, "shape": &"l3", "bonds": [],
		"desc": "最大魔力 +50%、回魔 +20%", "effects": [{"stat": &"max_mana", "op": Stats.PCT, "value": 0.5}, {"stat": &"mana_regen", "op": Stats.PCT, "value": 0.2}]},
	&"abyss_chalice": {"kind": &"item", "name": "深淵之杯", "rarity": &"purple", "power": 6.0, "shape": &"t4", "bonds": [],
		"desc": "最大魔力 +30%、回魔 +40%", "effects": [{"stat": &"max_mana", "op": Stats.PCT, "value": 0.3}, {"stat": &"mana_regen", "op": Stats.PCT, "value": 0.4}]},

	# ---- 輔助道具（Build 改版第 7 步）：鑲在寶石座上下左右才有效，只對標籤相符的技能（SkillDefs.TAGS）----
	# 一般輔助讓相鄰技能耗魔 +power × 10%（SkillDefs.SUPPORT_MANA，寫在 desc 最後）；節能只減不加
	&"split_support": {"kind": &"item", "name": "分裂", "rarity": &"green", "power": 3.0, "shape": &"i2", "bonds": [],
		"desc": "輔助：相鄰的範圍 / 投射技能 0.25 秒後再放一次（傷害 60%）；耗魔 +30%", "effects": [{"ability": &"skill_support", "mode": &"split", "tags": [&"area", &"projectile"]}]},
	&"extend_support": {"kind": &"item", "name": "延長", "rarity": &"white", "power": 1.5, "shape": &"dot", "bonds": [],
		"desc": "輔助：相鄰的範圍 / 投射 / 移動技能範圍與距離 +50%；耗魔 +15%", "effects": [{"ability": &"skill_support", "mode": &"extend", "tags": [&"area", &"projectile", &"move"]}]},
	&"fire_support": {"kind": &"item", "name": "火焰化", "rarity": &"green", "power": 3.0, "shape": &"i2", "bonds": [&"fire"],
		"desc": "輔助：相鄰的範圍 / 投射 / 近戰技能改成火焰傷害；耗魔 +30%", "effects": [{"ability": &"skill_support", "mode": &"fire", "tags": [&"area", &"projectile", &"melee"]}]},
	&"cold_support": {"kind": &"item", "name": "霜化", "rarity": &"green", "power": 3.0, "shape": &"i2", "bonds": [&"cold"],
		"desc": "輔助：相鄰的範圍 / 投射 / 近戰技能改成冰霜傷害；耗魔 +30%", "effects": [{"ability": &"skill_support", "mode": &"cold", "tags": [&"area", &"projectile", &"melee"]}]},
	&"conserve_support": {"kind": &"item", "name": "節能", "rarity": &"green", "power": 3.0, "shape": &"i2", "bonds": [],
		"desc": "輔助：相鄰的技能耗魔 −30%（所有技能都能輔助）", "effects": [{"ability": &"skill_support", "mode": &"conserve", "mana_mul": 0.7, "tags": [&"area", &"projectile", &"move", &"melee", &"guard", &"summon", &"buff"]}]},
	# 隊友的屍體（D6，kind &"corpse"）：不是道具，寶箱不會開出；背包條目 uid 是 Player.corpse_uid(死者)
	&"corpse": {"kind": &"corpse", "name": "隊友的屍體", "rarity": &"white", "shape": &"r6",
		"desc": "帶到下一層，死者會變成冤魂；打倒冤魂就能復活", "effects": []},
}


# 道具 id 依清單順序（除錯鍵 F4 循環用；不含武器）
static func item_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in ITEMS:
		if ITEMS[id].kind == &"item":
			ids.append(id)
	return ids


static func cell_count(id: StringName) -> int:
	return SHAPES[ITEMS[id].shape].size()


# 依稀有度應占的格數
static func expected_cells(id: StringName) -> int:
	return RARITIES[ITEMS[id].rarity].cells


# 放進身上就生效的屬性加成，格式同 Stats.set_source：[[屬性, 運算, 數值], …]
# mul：印記格（WeaponDropDefs.IMPRINT）的倍率，加 / 百分比乘上去、相乘的取 mul 次方
static func stat_mods(id: StringName, mul := 1.0) -> Array:
	var mods := []
	for e: Dictionary in ITEMS[id].effects:
		if e.has("stat") and not e.has("when"):
			var v: float = e.value
			if mul != 1.0:
				v = pow(v, mul) if e.op == Stats.MUL else v * mul
			mods.append([e.stat, e.op, v])
	return mods


# 效果是否已接上遊戲
static func is_implemented(effect: Dictionary) -> bool:
	if effect.has("ability"):
		return IMPLEMENTED_ABILITIES.has(effect.ability)
	if effect.has("on"):
		return IMPLEMENTED_TRIGGERS.has("%s|%s" % [effect.on, effect.do])
	if effect.has("when") and not IMPLEMENTED_CONDITIONS.has(effect.when):
		return false
	return effect.has("stat") and StatDefs.STATS[effect.stat].in_use


# 道具的效果是不是全部都接上了
static func item_implemented(id: StringName) -> bool:
	return ITEMS[id].effects.all(is_implemented)


# 魔力道具：效果是魔力屬性或回復魔力（不屬於羈絆也會掉，LootDefs.drop_pool）
const MANA_STATS: Array[StringName] = [&"max_mana", &"mana_regen", &"mana_cost", &"mana_on_hit"]


static func is_mana_item(id: StringName) -> bool:
	return ITEMS[id].effects.any(func(e: Dictionary) -> bool: return MANA_STATS.has(e.get("stat", &"")) or e.get("do", &"") == &"restore_mana")


# 輔助道具（skill_support 能力）：回傳那筆效果，不是回傳 {}
static func support_of(id: StringName) -> Dictionary:
	for e: Dictionary in ITEMS[id].effects:
		if e.get("ability", &"") == &"skill_support":
			return e
	return {}


static func is_skill(id: StringName) -> bool:
	return ITEMS.has(id) and ITEMS[id].kind == &"skill"


# 觸發袋的分類（BagDefs）：數值放主袋；效果、技能、修飾放袋子。武器與屍體不放袋子，回傳 &""
const ROLE_STAT := &"stat"
const ROLE_EFFECT := &"effect"
const ROLE_SKILL := &"skill"
const ROLE_MOD := &"mod"


static func role_of(id: StringName) -> StringName:
	match ITEMS[id].kind:
		&"skill":
			return ROLE_SKILL
		&"item":
			if not support_of(id).is_empty():
				return ROLE_MOD
			return ROLE_EFFECT if effect_of(id) != &"" else ROLE_STAT
	return &""


# 觸發道具改寫成的效果（BagDefs.EFFECTS）；不是效果的回傳 &""
static func effect_of(id: StringName) -> StringName:
	if BagDefs.EFFECT_ITEMS.has(id):
		return BagDefs.EFFECT_ITEMS[id][0]
	for e: Dictionary in ITEMS[id].effects:
		if e.has("on") and not BagDefs.MAIN_TRIGGERS.has(e.on):
			return BagDefs.effect_of_action(e.do)
	return &""


# 觸發道具原本的時機對到哪種袋子（自動擺放與說明的預設）；不是觸發道具的回傳 &""
static func default_bag_of(id: StringName) -> StringName:
	if BagDefs.EFFECT_ITEMS.has(id):
		return BagDefs.EFFECT_ITEMS[id][1]
	for e: Dictionary in ITEMS[id].effects:
		if e.has("on"):
			return BagDefs.bag_for_trigger(e.on)
	return &""
