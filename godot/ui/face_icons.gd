# 技能 / 效果的圖示圖片：res://assets/icons/<id>.png（Gemini 生、tools/slice_icons.gd 切的去背圖，做法見 docs/系統說明.md §55「圖示」）
# 有圖的骰面、技能欄、骰子面板畫圖；沒有圖的照舊寫字（SkillDefs / DiceDefs 的 icon）
class_name FaceIcons

const DIR := "res://assets/icons/"

static var _cache := {}


static func texture(id: StringName) -> Texture2D:
	if id == &"":
		return null
	if not _cache.has(id):
		var path := DIR + String(id) + ".png"
		_cache[id] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _cache[id]


static func has(id: StringName) -> bool:
	return texture(id) != null
