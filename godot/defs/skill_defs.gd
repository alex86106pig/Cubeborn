# 主動欄位（數字鍵 1~5）技能 / 道具資料（照搬網頁版 legacy/src/skills/skillDefs.js）；邏輯在 sim/skill_behaviors.gd
# mode：&"cooldown" 只受 CD 限制；&"charges" 另有使用次數（CD 作為防連按間隔）
class_name SkillDefs

const SKILLS := {
	&"heal": {
		"id": &"heal",
		"name": "治療藥水",
		"icon": "✚",
		"mode": &"charges",
		"charges": 3,
		"cooldown": 1.5,
		"behavior": &"heal",
		"amount": 35.0,
		"color": Color("5dff7a"),
	},
	# 插火把（F8，2026-10-27 從火把準備姿態的左鍵搬來）：手上拿火把時放在第一個空格；次數記在那把火把上（WeaponDropDefs.slot_charges），換層補滿
	&"plantTorch": {
		"id": &"plantTorch",
		"name": "插火把",
		"desc": "插在地上照亮周圍、全隊看得到；每層 3 次。",
		"icon": "torch_plant",
		"mode": &"charges",
		"charges": 3,
		"weapon_charges": true,  # 次數記在武器實例上（不是欄位上）
		"cooldown": 1.0,
		"behavior": &"plantTorch",
	},
}
