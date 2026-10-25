# 局外存檔（v0.45）：累計金幣，存在 user://profile.cfg（和 settings.cfg 的設定分開）
# main.gd 收到 coins:gained 就加上去並立刻存檔（中途離開也不會少算）；連線時每台電腦各自存自己的
# 之後的局外成長（天賦、解鎖）也記在這裡
class_name Profile
extends RefCounted

const SECTION := "profile"

var save_path := "user://profile.cfg"   # 測試與自動驗證設成 "" 就不讀寫檔案
var coins := 0                          # 累計金幣


func load_file() -> void:
	coins = 0
	if save_path == "":
		return
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK:
		coins = int(cfg.get_value(SECTION, "coins", 0))


func add_coins(amount: int) -> void:
	if amount <= 0:
		return
	coins += amount
	_save()


func _save() -> void:
	if save_path == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(save_path)   # 保留檔案裡的其他欄位
	cfg.set_value(SECTION, "coins", coins)
	cfg.save(save_path)
