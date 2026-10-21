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
	&"sprint": {
		"id": &"sprint",
		"name": "疾跑",
		"icon": "»",
		"mode": &"cooldown",
		"cooldown": 8.0,
		"behavior": &"speedBuff",
		"duration": 3.0,
		"speed_mul": 1.6,
		"color": Color("6fe3ff"),
	},
}
