# 物品資料：武器與道具共用一種格式（唯一編號、稀有度、占格形狀、效果列表）；道具清單見 docs/道具清單.md
# 測試用初稿：強度分數 power 與格數都是 Claude 暫定，等之後用實際戰鬥量測校正
# 格數 = ceil(power ÷ 稀有度效率)（docs/道具清單.md「強度與格數」），check.gd 會驗證形狀格數符合
#
# 效果（effects 的每一筆）有四種寫法：
#   屬性      {"stat", "op", "value"}：放進身上就生效，以道具實例 id 為來源套進 sim/stats.gd（B6 已接上）
#   條件屬性  {"when", "stat", "op", "value", ...}：條件成立時才生效（例如低血、翻滾後幾秒），參數見 CONDITIONS
#   觸發      {"on", "do", "chance"?, ...}：事件發生時執行動作，參數見 TRIGGERS / ACTIONS
#   能力      {"ability", ...}：新增一種能力（二段跳、護盾），參數見 ABILITIES
# 後三種有些已接上（IMPLEMENTED_*，效果在 sim/item_effects.gd），其他的只有資料：說明加「效果尚未實作」、寶箱不開出（LootDefs.drop_pool）
class_name ItemDefs

const BAG_SIZE := Vector2i(8, 6)   # 背包 8 × 6 格（暫定）

# efficiency：每格能放多少強度分數，越稀有越划算
const RARITIES := {
	&"white": {"name": "普通", "color": Color("d8d8d8"), "efficiency": 1.0},
	&"green": {"name": "優良", "color": Color("5fd35f"), "efficiency": 1.15},
	&"blue": {"name": "稀有", "color": Color("4fa3ff"), "efficiency": 1.3},
	&"purple": {"name": "史詩", "color": Color("b36bff"), "efficiency": 1.5},
	&"orange": {"name": "傳說", "color": Color("ff9a2e"), "efficiency": 1.75},
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
	&"throw_knife": {"name": "追加飛刀", "params": []},
	&"wisp": {"name": "放出追蹤鬼火", "params": []},
	&"slash_wave": {"name": "射出斬波", "params": ["count", "damage_ratio"]},
	&"lightning_strike": {"name": "對附近敵人落雷", "params": []},
	&"summon_skeleton": {"name": "召喚骷髏僕從", "params": ["max"]},
	&"slow_time": {"name": "周圍時間變慢", "params": ["duration", "slow"]},
	&"cheat_death": {"name": "留 1 血並無敵", "params": ["invuln"]},
	&"revive": {"name": "復活", "params": []},
}

const ABILITIES := {
	&"double_jump": {"name": "二段跳", "params": []},
	&"bone_shield": {"name": "自動回充的護盾", "params": ["ratio", "recharge_delay"]},
}

# 已接上的條件、觸發 + 動作（v0.33.0 第一批 8 個道具，sim/item_effects.gd）；能力的二段跳在 Player.air_jumps
const IMPLEMENTED_CONDITIONS: Array[StringName] = [&"target_full_hp", &"hp_below", &"after_kill"]
const IMPLEMENTED_TRIGGERS: Array[String] = ["kill|explode", "kill|heal_max_hp", "hit|chain_lightning", "hit|poison", "hit|freeze"]

# 觸發動作的數值（v0.33.0，說明沒寫到的由 Claude 暫定，試玩後再調）；damage_ratio 都是乘「觸發的那一下」的傷害
# 同一種動作有多個道具時機率相加（最多 100%）、沒有機率的（回血）效果相加
const PROCS := {
	&"explode": {"radius": 2.5, "damage_ratio": 0.5, "knockback": 6.0, "color": Color("ff9a2e")},   # 擊殺那一下的 50%
	&"chain_lightning": {"jump_range": 5.0, "damage_ratio": 0.5, "color": Color("9fd8ff")},       # 每跳 50%，不會打同一隻兩次
	&"poison": {"duration": 3.0, "total_ratio": 0.6, "tick": 0.5, "color": Color("7cff5a")},       # 3 秒共 60%，每 0.5 秒扣一次；再中毒重新計時、取較高的
	&"freeze": {"color": Color("a8e6ff")},   # 冰凍時不能動、不出招（Boss 不會被冰凍）
}

# kind：&"item" 道具 / &"weapon" 武器（weapon 對應 WeaponDefs，數值在那邊，這裡只放背包用的欄位）
# power 只有道具需要；武器的格數之後和背包一起定
const ITEMS := {
	# ---- 武器 ----
	&"swordShield": {"kind": &"weapon", "name": "劍盾", "rarity": &"white", "shape": &"o4", "weapon": &"swordShield",
		"desc": "左鍵三段斬擊、按住右鍵格擋，格擋中左鍵招架", "effects": []},
	&"staff": {"kind": &"weapon", "name": "法杖", "rarity": &"white", "shape": &"i4", "weapon": &"staff",
		"desc": "左鍵魔彈、右鍵奧術爆裂", "effects": []},
	&"shortbow": {"kind": &"weapon", "name": "短弓", "rarity": &"white", "shape": &"l4", "weapon": &"shortbow",
		"desc": "左鍵快射（可按住連射）、右鍵扇形散射 5 支", "effects": []},
	&"daggers": {"kind": &"weapon", "name": "雙匕首", "rarity": &"white", "shape": &"i2", "weapon": &"daggers",
		"desc": "左鍵五連刺（第 5 下必爆擊、擊退）、右鍵影步到怪背後背刺", "effects": []},
	&"longbow": {"kind": &"weapon", "name": "長弓", "rarity": &"white", "shape": &"i4", "weapon": &"longbow",
		"desc": "左鍵重射（可擊退）、按住右鍵蓄力、放開射出穿透箭", "effects": []},

	# ---- 白色：基本屬性 ----
	&"worn_boots": {"kind": &"item", "name": "磨損皮靴", "rarity": &"white", "power": 1.6, "shape": &"i2",
		"desc": "移速 +8%", "effects": [{"stat": &"move_speed", "op": Stats.PCT, "value": 0.08}]},
	&"whetstone": {"kind": &"item", "name": "磨刀石", "rarity": &"white", "power": 1.6, "shape": &"i2",
		"desc": "攻擊力 +8%", "effects": [{"stat": &"damage", "op": Stats.PCT, "value": 0.08}]},
	&"light_gloves": {"kind": &"item", "name": "輕巧手套", "rarity": &"white", "power": 2.0, "shape": &"i2",
		"desc": "攻速 +10%", "effects": [{"stat": &"attack_speed", "op": Stats.PCT, "value": 0.1}]},
	&"stale_bread": {"kind": &"item", "name": "乾硬麵包", "rarity": &"white", "power": 2.0, "shape": &"i2",
		"desc": "最大生命 +20", "effects": [{"stat": &"max_hp", "op": Stats.ADD, "value": 20.0}]},
	&"bandage_roll": {"kind": &"item", "name": "繃帶捲", "rarity": &"white", "power": 2.0, "shape": &"i2",
		"desc": "每秒回復 1 生命", "effects": [{"stat": &"hp_regen", "op": Stats.ADD, "value": 1.0}]},
	&"rusty_breastplate": {"kind": &"item", "name": "鏽鐵護心", "rarity": &"white", "power": 1.5, "shape": &"i2",
		"desc": "護甲 +8", "effects": [{"stat": &"armor", "op": Stats.ADD, "value": 8.0}]},
	&"loaded_dice": {"kind": &"item", "name": "灌鉛骰子", "rarity": &"white", "power": 0.6, "shape": &"dot",
		"desc": "爆擊率 +6%", "effects": [{"stat": &"crit_chance", "op": Stats.ADD, "value": 0.06}]},
	&"bat_fang": {"kind": &"item", "name": "蝙蝠牙", "rarity": &"white", "power": 1.5, "shape": &"i2",
		"desc": "每次命中回復 1 生命", "effects": [{"stat": &"life_on_hit", "op": Stats.ADD, "value": 1.0}]},
	&"grave_purse": {"kind": &"item", "name": "盜墓者錢袋", "rarity": &"white", "power": 1.0, "shape": &"dot",
		"desc": "靈魂獲得 +15%", "effects": [{"stat": &"soul_gain", "op": Stats.PCT, "value": 0.15}]},
	&"light_feather": {"kind": &"item", "name": "輕羽", "rarity": &"white", "power": 0.8, "shape": &"dot",
		"desc": "翻滾冷卻 −10%", "effects": [{"stat": &"roll_cooldown", "op": Stats.MUL, "value": 0.9}]},
	&"lead_weight": {"kind": &"item", "name": "鉛墜", "rarity": &"white", "power": 0.8, "shape": &"dot",
		"desc": "擊退 +20%", "effects": [{"stat": &"knockback", "op": Stats.PCT, "value": 0.2}]},
	&"wormwood": {"kind": &"item", "name": "苦艾酒", "rarity": &"white", "power": 0.8, "shape": &"dot",
		"desc": "技能冷卻 −6%", "effects": [{"stat": &"cooldown", "op": Stats.MUL, "value": 0.94}]},
	&"powder_pouch": {"kind": &"item", "name": "火藥包", "rarity": &"white", "power": 1.2, "shape": &"i2",
		"desc": "擊殺時 10% 機率小爆炸", "effects": [{"on": &"kill", "chance": 0.1, "do": &"explode"}]},
	&"hound_collar": {"kind": &"item", "name": "獵犬項圈", "rarity": &"white", "power": 1.0, "shape": &"dot",
		"desc": "對滿血敵人傷害 +25%", "effects": [{"when": &"target_full_hp", "stat": &"damage", "op": Stats.PCT, "value": 0.25}]},
	&"vigil_candle": {"kind": &"item", "name": "守夜蠟燭", "rarity": &"white", "power": 0.5, "shape": &"dot",
		"desc": "視野距離與角度 +10%", "effects": [{"stat": &"vision", "op": Stats.PCT, "value": 0.1}]},

	# ---- 綠色：條件與觸發 ----
	&"thunder_rune": {"kind": &"item", "name": "雷鳴符文", "rarity": &"green", "power": 3.0, "shape": &"l3",
		"desc": "命中 10% 機率連鎖閃電（3 個目標）", "effects": [{"on": &"hit", "chance": 0.1, "do": &"chain_lightning", "targets": 3}]},
	&"venom_blade": {"kind": &"item", "name": "淬毒刀刃", "rarity": &"green", "power": 3.0, "shape": &"i3",
		"desc": "命中 15% 機率中毒（持續傷害）", "effects": [{"on": &"hit", "chance": 0.15, "do": &"poison"}]},
	&"war_drum": {"kind": &"item", "name": "戰鼓", "rarity": &"green", "power": 2.5, "shape": &"l3",
		"desc": "擊殺後 3 秒攻速 +30%", "effects": [{"when": &"after_kill", "duration": 3.0, "stat": &"attack_speed", "op": Stats.PCT, "value": 0.3}]},
	&"berserker_charm": {"kind": &"item", "name": "狂戰士護符", "rarity": &"green", "power": 2.5, "shape": &"i3",
		"desc": "生命低於 35% 時傷害 +25%", "effects": [{"when": &"hp_below", "threshold": 0.35, "stat": &"damage", "op": Stats.PCT, "value": 0.25}]},
	&"thorn_mail": {"kind": &"item", "name": "荊棘鎖甲", "rarity": &"green", "power": 3.0, "shape": &"l3",
		"desc": "反彈 50% 受到的近戰傷害", "effects": [{"on": &"hurt_melee", "do": &"reflect", "ratio": 0.5}]},
	&"hunter_cloak": {"kind": &"item", "name": "獵人斗篷", "rarity": &"green", "power": 3.0, "shape": &"i3",
		"desc": "翻滾後 1.5 秒內爆擊率 +50%", "effects": [{"when": &"after_roll", "duration": 1.5, "stat": &"crit_chance", "op": Stats.ADD, "value": 0.5}]},
	&"bone_buckler": {"kind": &"item", "name": "骨製護盾", "rarity": &"green", "power": 3.5, "shape": &"o4",
		"desc": "護盾為最大生命的 8%，3 秒沒受傷就自動回充", "effects": [{"ability": &"bone_shield", "ratio": 0.08, "recharge_delay": 3.0}]},
	&"sleeve_knife": {"kind": &"item", "name": "袖中飛刀", "rarity": &"green", "power": 3.0, "shape": &"i3",
		"desc": "普攻 20% 機率追加一把飛刀", "effects": [{"on": &"attack", "chance": 0.2, "do": &"throw_knife"}]},
	&"wisp_lantern": {"kind": &"item", "name": "鬼火燈籠", "rarity": &"green", "power": 3.5, "shape": &"t4",
		"desc": "擊殺時放出會追蹤敵人的鬼火", "effects": [{"on": &"kill", "do": &"wisp"}]},
	&"lockpick": {"kind": &"item", "name": "撬鎖工具", "rarity": &"green", "power": 1.5, "shape": &"i2",
		"desc": "祭壇與石棺價格 −10%", "effects": [{"stat": &"chest_price", "op": Stats.MUL, "value": 0.9}]},
	&"lodestone": {"kind": &"item", "name": "磁石", "rarity": &"green", "power": 1.0, "shape": &"dot",
		"desc": "撿東西的範圍 +50%", "effects": [{"stat": &"pickup_radius", "op": Stats.PCT, "value": 0.5}]},
	&"iron_cloak": {"kind": &"item", "name": "鐵皮斗篷", "rarity": &"green", "power": 2.3, "shape": &"i2",
		"desc": "受到投射物傷害 −15%", "effects": [{"stat": &"projectile_damage_taken", "op": Stats.MUL, "value": 0.85}]},

	# ---- 藍色：改變打法 ----
	&"frost_heart": {"kind": &"item", "name": "霜之心", "rarity": &"blue", "power": 5.0, "shape": &"l4",
		"desc": "命中 10% 機率冰凍 1.5 秒", "effects": [{"on": &"hit", "chance": 0.1, "do": &"freeze", "duration": 1.5}]},
	&"soul_scythe": {"kind": &"item", "name": "吸魂鐮", "rarity": &"blue", "power": 4.5, "shape": &"t4",
		"desc": "擊殺回復 3% 最大生命", "effects": [{"on": &"kill", "do": &"heal_max_hp", "ratio": 0.03}]},
	&"twin_leap_boots": {"kind": &"item", "name": "雙躍之靴", "rarity": &"blue", "power": 4.0, "shape": &"s4",
		"desc": "可以二段跳", "effects": [{"ability": &"double_jump"}]},
	&"blast_quiver": {"kind": &"item", "name": "爆裂箭袋", "rarity": &"blue", "power": 5.0, "shape": &"i4",
		"desc": "投射物命中時爆炸", "effects": [{"on": &"projectile_hit", "do": &"explode"}]},
	&"gale_charm": {"kind": &"item", "name": "疾風護符", "rarity": &"blue", "power": 5.0, "shape": &"o4",
		"desc": "翻滾多 1 次充能", "effects": [{"stat": &"roll_charges", "op": Stats.ADD, "value": 1.0}]},
	&"pact_of_dead": {"kind": &"item", "name": "亡者之契", "rarity": &"blue", "power": 6.0, "shape": &"p5",
		"desc": "本層每擊殺 1 隻傷害 +1%（最多 30%）", "effects": [{"when": &"per_kill_stack", "max": 30, "stat": &"damage", "op": Stats.PCT, "value": 0.01}]},
	&"guardian_spirit": {"kind": &"item", "name": "守護亡靈", "rarity": &"blue", "power": 5.0, "shape": &"l4",
		"desc": "受到致命傷害時留 1 血並無敵 2 秒，每層一次", "effects": [{"on": &"lethal", "do": &"cheat_death", "invuln": 2.0, "per_floor": 1}]},
	&"thunder_bell": {"kind": &"item", "name": "雷霆鈴", "rarity": &"blue", "power": 5.5, "shape": &"t5",
		"desc": "每 5 秒對附近敵人落雷", "effects": [{"on": &"interval", "period": 5.0, "do": &"lightning_strike"}]},
	&"greedy_hand": {"kind": &"item", "name": "貪婪之手", "rarity": &"blue", "power": 2.5, "shape": &"i2",
		"desc": "精英怪給的靈魂 ×2", "effects": [{"when": &"from_elite", "stat": &"soul_gain", "op": Stats.MUL, "value": 2.0}]},

	# ---- 紫色：強力 ----
	&"resurrection_cross": {"kind": &"item", "name": "復活十字", "rarity": &"purple", "power": 9.0, "shape": &"cross6",
		"desc": "死亡時復活一次，用完碎掉並空出格子", "effects": [{"on": &"death", "do": &"revive", "consume": true}]},
	&"rift_blade": {"kind": &"item", "name": "裂空之刃", "rarity": &"purple", "power": 9.0, "shape": &"l6",
		"desc": "攻擊額外射出 2 道斬波，各造成 50% 傷害", "effects": [{"on": &"attack", "do": &"slash_wave", "count": 2, "damage_ratio": 0.5}]},
	&"blood_crown": {"kind": &"item", "name": "血族王冠", "rarity": &"purple", "power": 6.0, "shape": &"o4",
		"desc": "造成傷害的 3% 轉為回復生命", "effects": [{"stat": &"lifesteal", "op": Stats.ADD, "value": 0.03}]},
	&"hourglass": {"kind": &"item", "name": "時之沙漏", "rarity": &"purple", "power": 6.0, "shape": &"t4",
		"desc": "技能冷卻 −25%", "effects": [{"stat": &"cooldown", "op": Stats.MUL, "value": 0.75}]},
	&"obsidian_skin": {"kind": &"item", "name": "黑曜石皮膚", "rarity": &"purple", "power": 7.5, "shape": &"p5",
		"desc": "受到傷害 −20%，但移速 −5%", "effects": [
			{"stat": &"damage_taken", "op": Stats.MUL, "value": 0.8},
			{"stat": &"move_speed", "op": Stats.PCT, "value": -0.05}]},
	&"army_of_dead": {"kind": &"item", "name": "亡者大軍", "rarity": &"purple", "power": 8.0, "shape": &"r6",
		"desc": "擊殺時 20% 機率召喚骷髏僕從（最多 3 隻）", "effects": [{"on": &"kill", "chance": 0.2, "do": &"summon_skeleton", "max": 3}]},

	# ---- 橘色：改變整個 build ----
	&"tomb_heart": {"kind": &"item", "name": "王墓之心", "rarity": &"orange", "power": 10.0, "shape": &"r6",
		"desc": "受傷時對周圍爆炸，傷害為受傷量的 300%", "effects": [{"on": &"hurt", "do": &"explode", "damage_ratio": 3.0}]},
	&"eternal_flame": {"kind": &"item", "name": "永恆之焰", "rarity": &"orange", "power": 12.0, "shape": &"h7",
		"desc": "所有攻擊都會點燃敵人，燃燒會擴散到附近敵人", "effects": [{"on": &"hit", "do": &"ignite", "spread": true}]},
	&"stasis_watch": {"kind": &"item", "name": "停滯懷錶", "rarity": &"orange", "power": 10.0, "shape": &"cross6",
		"desc": "翻滾時周圍時間變慢 2 秒（敵人慢 70%）", "effects": [{"on": &"roll", "do": &"slow_time", "duration": 2.0, "slow": 0.7}]},
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


# 依強度分數與稀有度效率算出應占的格數
static func expected_cells(id: StringName) -> int:
	var def: Dictionary = ITEMS[id]
	return ceili(def.power / RARITIES[def.rarity].efficiency - 1e-6)


# 放進身上就生效的屬性加成，格式同 Stats.set_source：[[屬性, 運算, 數值], …]
static func stat_mods(id: StringName) -> Array:
	var mods := []
	for e: Dictionary in ITEMS[id].effects:
		if e.has("stat") and not e.has("when"):
			mods.append([e.stat, e.op, e.value])
	return mods


# 效果是否已接上遊戲
static func is_implemented(effect: Dictionary) -> bool:
	if effect.get("ability", &"") == &"double_jump":   # v0.27.0（Player.air_jumps）
		return true
	if effect.has("on"):
		return IMPLEMENTED_TRIGGERS.has("%s|%s" % [effect.on, effect.do])
	if effect.has("when") and not IMPLEMENTED_CONDITIONS.has(effect.when):
		return false
	return effect.has("stat") and StatDefs.STATS[effect.stat].in_use


# 道具的效果是不是全部都接上了
static func item_implemented(id: StringName) -> bool:
	return ITEMS[id].effects.all(is_implemented)
