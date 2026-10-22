# 地形資料：場地內的長方體石台（中心 XZ、大小 XZ、頂面高度）
# 目前只有驗證跳躍用的測試石台，放在場地 +X +Z 角落；D1 做正式墓地地圖時換掉
class_name TerrainDefs

const TEST_BLOCKS: Array[Dictionary] = [
	{"center": Vector2(9.0, 12.0), "size": Vector2(2.5, 2.5), "top": 0.5},    # 走不上去、跳得上去
	{"center": Vector2(12.0, 12.0), "size": Vector2(3.5, 3.5), "top": 1.0},   # 緊鄰上一塊；跳得上去，可以站著走
	{"center": Vector2(11.0, 8.0), "size": Vector2(6.0, 1.0), "top": 2.5},    # 跳不上去，當牆
]
