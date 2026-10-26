# 職業資料（F2，demo 版；草案見 docs/設計方向.md「職業與武器」的職業構想連結，數字 Claude 暫定、使用者逐項確認中）
# 職業 = 基礎數值 + 起始武器 + 職業被動；被動跟著職業走、不綁武器。套用在 Player.apply_class
# stats：覆寫 StatDefs 的基礎值（沒寫的照 StatDefs / Config.PLAYER）；passive.mods：被動的屬性加成（來源 &"class"）
# passive.friendly_back_mul：被隊友從背後打到時的傷害倍率（Combat.apply_damage）；passive.attack_no_slow：移動中普攻不減速（Player 算移速）
# colors：模型配色（DarkFantasy.player_character）：armor 盔甲、trim 腰甲、cape 披風
class_name ClassDefs

const NONE := &""   # 沒選職業：照舊用共用的基準數值（測試與自動驗證用）

const ORDER: Array[StringName] = [&"guardian", &"arcanist", &"ranger"]

const CLASSES := {
	&"guardian": {
		"name": "守墓騎士",
		"weapon": &"swordShield",
		"pitch": "站在隊伍最前面，替後面的隊友擋傷害。",
		"stats": {&"max_hp": 130.0, &"armor": 20.0, &"magic_resist": 10.0, &"magic_damage": 0.9, &"hp_regen": 1.0, &"move_speed": 6.2},
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
		"stats": {&"max_hp": 80.0, &"magic_resist": 25.0, &"phys_damage": 0.9, &"magic_damage": 1.2, &"hp_regen": 0.6},
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
		"stats": {&"max_hp": 90.0, &"phys_damage": 1.15, &"magic_damage": 0.9, &"attack_speed": 1.1, &"hp_regen": 0.6, &"dodge": 0.05, &"move_speed": 7.0},
		"passive": {
			"desc": "移動中「普通攻擊」不減速（右鍵照常減速）",
			"attack_no_slow": true,
		},
		"colors": {"armor": Color("4d6b45"), "trim": Color("2c3d27"), "cape": Color("b8d49a")},
	},
}
