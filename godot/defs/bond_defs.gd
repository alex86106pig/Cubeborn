# 羈絆（Build 改版第 5 步）：道具的 bonds 列出它屬於哪些羈絆（跨羈絆的道具兩邊各算 1 件）
# 只算鑲在主手 / 副手格子上的道具，同一種道具鑲好幾個只算 1 件；件數湊到門檻就啟動那一階（Loadout.bond_counts）
# 第一版 5 個羈絆；門檻與每階效果 Claude 暫定（武器格子 artifact），效果在第 5b 步接上
class_name BondDefs

const BONDS := {
	&"phys": {"name": "物理", "color": Color("d8d8d8"), "thresholds": [2, 4, 6, 8, 10], "tiers": [
		"物理傷害 +10%",
		"命中累積失衡值（連段最後一下更多）；失衡的怪 1.5 秒不能動、受到傷害 +30%",
		"擊退 +50%；把怪撞到牆或其他怪身上，額外造成 50% 物理傷害",
		"物理傷害無視目標 30% 的物理抗性",
		"對失衡的怪必定暴擊；失衡中生命低於 15% 的怪直接處決",
	]},
	&"fire": {"name": "火焰", "color": Color("ff8a3d"), "thresholds": [3, 5, 7], "tiers": [
		"火焰命中疊燃燒：每層每秒武器攻擊 10%，持續 4 秒，最多 5 層",
		"疊滿 5 層時爆炸（半徑 3），清空層數",
		"燃燒中的怪死亡時，把層數全部傳給 4 單位內最近的 2 隻怪",
	]},
	&"cold": {"name": "冰霜", "color": Color("8fd8ff"), "thresholds": [3, 5, 7], "tiers": [
		"冰霜命中疊冰冷：每層減速 10%，最多 5 層",
		"冰冷滿 5 層凍結 2 秒；打凍結的怪傷害 +50% 並碎冰（解除凍結）",
		"碎冰時噴出 6 片冰錐；凍結中被殺的怪不會觸發死亡效果",
	]},
	&"guard": {"name": "防禦", "color": Color("c9a25a"), "thresholds": [3, 6, 9], "tiers": [
		"護甲 +20%；招架成功回復 3% 最大生命",
		"招架成功後 2 秒內，下一擊必定暴擊、傷害 +80%",
		"招架成功時放出衝擊波，彈回範圍內的投射物；受到的傷害 20% 反彈給攻擊者",
	]},
	&"wisp": {"name": "鬼火", "color": Color("b48cff"), "thresholds": [3, 6, 9], "tiers": [
		"每件鬼火道具帶 1 顆鬼火繞著你轉，碰到怪造成武器攻擊 25%",
		"鬼火每 2 秒自動飛向最近的怪攻擊，再飛回來",
		"鬼火數量加倍；鬼火的命中也會觸發武器上看部位的道具（機率減半）",
	]},
}


# count 件時啟動到第幾階（0 = 還沒啟動）
static func tier(bond: StringName, count: int) -> int:
	var t := 0
	for need: int in BONDS[bond].thresholds:
		if count >= need:
			t += 1
	return t


# 下一階要幾件；已經滿階回傳 -1
static func next_threshold(bond: StringName, count: int) -> int:
	for need: int in BONDS[bond].thresholds:
		if count < need:
			return need
	return -1
