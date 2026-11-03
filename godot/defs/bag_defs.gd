# 觸發袋資料：背包 = 主袋 + 接在四邊的袋子（規則在 docs/設計方向.md「觸發袋」，數字 Claude 暫定）
# 主袋放數值道具；袋子放效果、技能、修飾，接在哪一邊決定按鍵（SIDES），袋子的種類決定時機（BAGS）
# 觸發道具改寫成效果：拿掉時機與機率，道具原本的動作（ItemDefs 效果的 do）對到 EFFECTS，重複的合併（對照在 docs/道具清單.md）
class_name BagDefs

const MAIN_SIZE := Vector2i(6, 4)   # 主袋

# 邊：source 是哪個動作會觸發接在這一邊的袋子（primary 普攻、secondary 右鍵招式、key 數字鍵、空 = 不分按鍵）
const SIDES := {
	&"left": {"name": "左鍵", "source": &"primary"},
	&"right": {"name": "右鍵", "source": &"secondary"},
	&"bottom": {"name": "不分按鍵", "source": &""},
	&"top": {"name": "數字鍵", "source": &"key"},
}

# 袋子種類：sides 能接哪幾邊；on 是道具資料原本的觸發時機（ItemDefs 效果的 on），H1 用來把觸發道具對到袋子
# icd：同一袋多久最多發動一次（秒）；period：計時袋的間隔；max：最多幾個（按鍵袋 = 數字鍵 1~4）
const BAGS := {
	&"cast": {"name": "出手袋", "sides": [&"left", &"right"], "on": [&"attack"], "desc": "每次出手時發動"},
	&"hit": {"name": "命中袋", "sides": [&"left", &"right"], "on": [&"hit", &"projectile_hit"], "icd": 0.3, "desc": "打中東西時，從命中點發動"},
	&"kill": {"name": "擊殺袋", "sides": [&"left", &"right"], "on": [&"kill"], "desc": "打死怪時，從怪死的位置發動"},
	&"hurt": {"name": "受傷袋", "sides": [&"bottom"], "on": [&"hurt", &"hurt_melee"], "desc": "自己被打中時發動"},
	&"roll": {"name": "翻滾袋", "sides": [&"bottom"], "on": [&"roll"], "desc": "翻滾時發動"},
	&"timer": {"name": "計時袋", "sides": [&"bottom"], "on": [&"interval"], "period": 3.0, "desc": "每隔一段時間發動"},
	&"key": {"name": "按鍵袋", "sides": [&"top"], "on": [], "max": 4, "desc": "按數字鍵發動"},
}

# 留在主袋的觸發：致命傷、死亡（守護亡靈、復活十字）不是攻擊的時機，當成常駐能力
const MAIN_TRIGGERS: Array[StringName] = [&"lethal", &"death"]

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
