# 小怪的狀態機：要從別的狀態進入「開始出招」的狀態（Enemy.attack_starts）時先問出手名額（AttackQuota），拿不到就不換、回傳 false，下一步再試
class_name EnemyFsm
extends StateMachine


func change(name: StringName, p_data: Dictionary = {}) -> bool:
	var e := ctx as Enemy
	if e != null and current != null and e.attack_starts().has(name) and not e.attack_states().has(current_name):
		var target := e.nearest_target()
		if not AttackQuota.take(e, target):
			e.hold_off(target)   # 沒輪到：這一步改成往玩家背後繞（呼叫端接著就 return）
			return false
	return super.change(name, p_data)
