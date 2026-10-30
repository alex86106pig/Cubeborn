# 羈絆（Build 改版第 5 步）：道具的 bonds 列出它屬於哪些羈絆（跨羈絆的道具兩邊各算 1 件）
# 只算鑲在主手 / 副手格子上的道具，同一種道具鑲好幾個只算 1 件；件數湊到門檻就啟動那一階（Loadout.bond_counts）
# 第一版 5 個羈絆；門檻、每階效果與數字 Claude 暫定（武器格子 artifact），效果在 sim/bond_effects.gd
# 火焰 / 冰霜的層數：沒有那個羈絆時最多 1 層（火把、焚香爐照樣點得著），第 1 階起才會疊
class_name BondDefs

const BONDS := {
	&"phys": {"name": "物理", "color": Color("d8d8d8"), "thresholds": [2, 4, 6, 8, 10], "tiers": [
		"物理傷害 +10%",
		"命中累積失衡值（連段最後一下更多）；失衡的怪 1.5 秒不能動、受到傷害 +30%",
		"擊退 +50%；被擊退的怪撞到其他怪時，兩隻都受那一下 50% 的物理傷害",
		"物理傷害無視目標 30% 的物理抗性",
		"對失衡的怪必定暴擊；失衡中生命低於 15% 的怪直接處決（Boss 不會）",
	], "params": {
		"phys_damage": 0.1,                 # 第 1 階：物理傷害 +10%
		"poise_ratio": 0.3,                 # 第 2 階：累積的實際傷害到最大生命的 30% 就失衡（Boss 一樣算）
		"poise_finisher_mul": 2.0,          # 連段最後一下累積 2 倍
		"poise_decay": 3.0,                 # 3 秒沒再累積就歸零
		"stagger_time": 1.5, "stagger_damage_taken": 1.3,
		"knockback": 0.5,                   # 第 3 階：擊退 +50%
		"ram_ratio": 0.5, "ram_window": 0.4,   # 被擊退的怪 0.4 秒內撞到別的怪：兩隻各受那一下的 50% 物理傷害
		"resist_pierce": 0.3,               # 第 4 階：無視 30% 物理抗性（只減正的抗性）
		"execute_hp": 0.15,                 # 第 5 階
	}},
	&"fire": {"name": "火焰", "color": Color("ff8a3d"), "thresholds": [3, 5, 7], "tiers": [
		"火焰命中疊燃燒：每層每秒武器攻擊 10%，持續 4 秒，最多 5 層",
		"疊滿 5 層時爆炸（半徑 3），清空層數",
		"燃燒中的怪死亡時，把層數全部傳給 4 單位內最近的 2 隻怪",
	], "params": {
		"stack_pct": 0.1, "duration": 4.0, "max_stacks": 5,   # 每層每秒武器基礎傷害 10%（Player.pct_damage）
		"burst_radius": 3.0, "burst_pct": 1.0,                 # 第 2 階：爆炸傷害 = 武器基礎傷害 100%
		"spread_range": 4.0, "spread_count": 2,
	}},
	&"cold": {"name": "冰霜", "color": Color("8fd8ff"), "thresholds": [3, 5, 7], "tiers": [
		"冰霜命中疊冰冷：每層減速 10%，最多 5 層",
		"冰冷滿 5 層凍結 2 秒；打凍結的怪傷害 +50% 並碎冰（解除凍結）",
		"碎冰時噴出 6 片冰錐；凍結中被殺的怪不會觸發死亡效果",
	], "params": {
		"slow_per_stack": 0.1, "duration": 4.0, "max_stacks": 5,
		"freeze_time": 2.0, "shatter_mul": 1.5,
		"shards": 6, "shard_pct": 0.5, "shard_speed": 14.0, "shard_range": 6.0,   # 冰錐每片武器基礎傷害 50%
	}},
	&"guard": {"name": "防禦", "color": Color("c9a25a"), "thresholds": [3, 6, 9], "tiers": [
		"護甲 +20%；招架成功回復 3% 最大生命",
		"招架成功後 2 秒內，下一擊必定暴擊、傷害 +80%",
		"招架成功時放出衝擊波，消掉範圍內的投射物；受到的傷害 20% 反彈給攻擊者",
	], "params": {
		"armor": 0.2, "parry_heal": 0.03,
		"riposte_time": 2.0, "riposte_mul": 1.8,
		"wave_radius": 3.0, "reflect": 0.2,
	}},
	&"wisp": {"name": "鬼火", "color": Color("b48cff"), "thresholds": [3, 6, 9], "tiers": [
		"沒有自帶鬼火的鬼火道具也各帶 1 顆鬼火（鬼火燈本來就有），鬼火碰到怪造成武器攻擊 25%",
		"鬼火每 2 秒自動飛向最近的怪攻擊，再飛回來",
		"鬼火數量加倍；鬼火的命中也會觸發武器上看部位的道具（機率減半）",
	], "params": {
		"pct": 0.25, "orbit_radius": 1.6, "orbit_speed": 2.4, "radius": 0.3, "hit_interval": 0.5,   # 轉速：弧度 / 秒
		"dash_interval": 2.0, "dash_range": 6.0, "dash_speed": 16.0,
		"proc_chance_mul": 0.5,
	}},
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


static func param(bond: StringName, key: String) -> Variant:
	return BONDS[bond].params[key]
