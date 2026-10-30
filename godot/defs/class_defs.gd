# 職業資料（F2，demo 版；草案見 docs/設計方向.md「職業與武器」的職業構想連結，數字 Claude 暫定、使用者逐項確認中）
# 職業 = 基礎數值 + 起始武器 + 職業被動；被動跟著職業走、不綁武器。套用在 Player.apply_class
# stats：覆寫 StatDefs 的基礎值（沒寫的照 StatDefs / Config.PLAYER）；passive.mods：被動的屬性加成（來源 &"class"）
# passive.friendly_back_mul：被隊友從背後打到時的傷害倍率（Combat.apply_damage）；passive.attack_no_slow：移動中普攻不減速（Player 算移速）
# passive.roll_buff：[秒數, 屬性加成]，翻滾結束後套上（增益 &"rollHaste"）
# passive.revive_speed / revive_hp_ratio：救隊友的速度倍率、救起後的血量比例（World._update_downed）
# passive.vision_add / near_radius：視野距離加多少、身邊一圈的半徑（Vision.view_range / near_radius）
# passive.dig_speed / dig_damage_taken：挖墳速度倍率（DigEvent）、挖墳中受到傷害的倍率（Combat）
# colors：模型配色（DarkFantasy.player_character）：armor 盔甲、trim 腰甲、cape 披風
# locked / unlock：還沒解鎖（選角畫面顯示鎖頭與解鎖條件、選不到；目前都解鎖了，之後成就解鎖用）
class_name ClassDefs

const NONE := &""   # 沒選職業：照舊用共用的基準數值（測試與自動驗證用）

const ORDER: Array[StringName] = [&"guardian", &"arcanist", &"ranger", &"gravedigger", &"shadow", &"priest", &"mercenary"]

const CLASSES := {
	&"guardian": {
		"name": "守墓騎士",
		"weapon": &"swordShield",
		"pitch": "站在隊伍最前面，替後面的隊友擋傷害。",
		"stats": {&"max_hp": 130.0, &"armor": 20.0, &"resist_all": 0.09, &"elem_damage": 0.9, &"hp_regen": 0.5, &"move_speed": 6.2},
		"passive": {
			"desc": "受到傷害 −10%；被隊友從背後打到時傷害 −50%",
			"mods": [[&"damage_taken", Stats.MUL, 0.9]],
			"friendly_back_mul": 0.5,
		},
		"colors": {"armor": Color("8a93a3"), "trim": Color("4a505c"), "cape": Color("6b1d24")},
	},
	&"arcanist": {
		"name": "祕術師",
		"weapon": &"staff",
		"pitch": "玻璃大砲：普攻慢，靠技能爆發，被摸到就很危險。",
		"stats": {&"max_hp": 80.0, &"resist_all": 0.2, &"phys_damage": 0.9, &"elem_damage": 1.2, &"hp_regen": 0.3},
		"passive": {
			"desc": "技能冷卻 −10%",
			"mods": [[&"cooldown", Stats.MUL, 0.9]],
		},
		"colors": {"armor": Color("5a4a8a"), "trim": Color("2e2550"), "cape": Color("b9a7ff")},
	},
	&"ranger": {
		"name": "盜墓遊俠",
		"weapon": &"shortbow",
		"pitch": "邊跑邊射的放風箏玩法。",
		"stats": {&"max_hp": 90.0, &"phys_damage": 1.15, &"elem_damage": 0.9, &"attack_speed": 1.1, &"hp_regen": 0.3, &"dodge": 0.05, &"move_speed": 7.0},
		"passive": {
			"desc": "移動中「普通攻擊」不減速（右鍵照常減速）",
			"attack_no_slow": true,
		},
		"colors": {"armor": Color("4d6b45"), "trim": Color("2c3d27"), "cape": Color("b8d49a")},
	},
	&"shadow": {
		"name": "竊影者",
		"weapon": &"daggers",
		"pitch": "貼身高速連擊，翻滾進出、影步繞到背後。",
		"stats": {&"max_hp": 85.0, &"armor": 5.0, &"resist_all": 0.05, &"phys_damage": 1.05, &"elem_damage": 0.9, &"attack_speed": 1.15,
			&"hp_regen": 0.25, &"crit_damage": 1.75, &"dodge": 0.1, &"move_speed": 7.2},
		"passive": {
			"desc": "翻滾後 1.5 秒內攻速 +30%；翻滾次數 +1",
			"mods": [[&"roll_charges", Stats.ADD, 1.0]],
			"roll_buff": [1.5, [[&"attack_speed", Stats.PCT, 0.3]]],
		},
		"colors": {"armor": Color("3a3f4a"), "trim": Color("22252c"), "cape": Color("9aa3b5")},
	},
	&"priest": {
		"name": "驅魔神官",
		"weapon": &"scepter",
		"pitch": "揮著權杖把亡靈逼退，順便替隊友補血。",
		"stats": {&"max_hp": 110.0, &"armor": 10.0, &"resist_all": 0.17, &"phys_damage": 0.95, &"elem_damage": 1.1, &"hp_regen": 0.75},
		"passive": {
			"desc": "救援速度 +50%；被救起的隊友恢復 50% 生命（平常 30%）",
			"revive_speed": 1.5,
			"revive_hp_ratio": 0.5,
		},
		"colors": {"armor": Color("8a7a4a"), "trim": Color("4a4028"), "cape": Color("fff0b0")},
	},
	&"mercenary": {
		"name": "火把傭兵",
		"weapon": &"torch",
		"pitch": "插火把替全隊照亮戰場，必要時吹出一片火。",
		"stats": {&"max_hp": 100.0, &"armor": 10.0, &"resist_all": 0.09, &"elem_damage": 1.1, &"hp_regen": 0.4, &"crit_damage": 1.6, &"move_speed": 6.8},
		"passive": {
			"desc": "視野 +3 單位；身邊看得到的範圍 4 → 6",
			"vision_add": 3.0,
			"near_radius": 6.0,
		},
		"colors": {"armor": Color("8a4a3a"), "trim": Color("4a2a20"), "cape": Color("ffb070")},
	},
	&"gravedigger": {
		"name": "掘墓人",
		"weapon": &"shovel",
		"pitch": "把怪鏟起來，丟出去砸別隻，或埋進土裡。",
		"stats": {&"max_hp": 120.0, &"armor": 15.0, &"resist_all": 0.05, &"phys_damage": 1.1, &"elem_damage": 0.9, &"attack_speed": 0.9,
			&"hp_regen": 0.6, &"treasure": 0.2, &"move_speed": 6.2},
		"passive": {
			"desc": "挖墳速度 +40%；挖墳中受到傷害 −25%",
			"dig_speed": 1.4,
			"dig_damage_taken": 0.75,
		},
		"colors": {"armor": Color("7a5a3a"), "trim": Color("4a3624"), "cape": Color("d9b98a")},
	},
}

# 選角畫面上還沒做的職業：只佔一格（問號、鎖住），不進 ORDER / CLASSES（大廳預設、apply_class 都碰不到）
const PLACEHOLDERS := {
	&"necromancer": {"name": "死靈術士", "unlock": "尚未開放"},
}


# 可以選嗎：有這個職業而且沒鎖（大廳收客戶端的選擇也看這個）
static func is_pickable(id: StringName) -> bool:
	return CLASSES.has(id) and not CLASSES[id].get("locked", false)
