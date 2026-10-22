# 屬性計算：結果 = (基礎值 + Σadd) × (1 + Σpct) × Πmul，再取整（有設定的屬性）並限制在上下限內
# 加成以「來源」為單位整批設定或移除（道具、增益、波次倍率、除錯）；同一來源再次設定會整批取代
# 同類加成相加（兩個 +8% = +16%）；暫時效果、波次倍率、冷卻縮減用 mul 相乘
class_name Stats
extends RefCounted

const ADD := &"add"
const PCT := &"pct"
const MUL := &"mul"

var _base: Dictionary = {}      # stat -> float；沒設定的用 StatDefs 的 base
var _sources: Dictionary = {}   # source -> Array，每筆 [stat, op, value]
var _cache: Dictionary = {}     # stat -> float


func _init(base: Dictionary = {}) -> void:
	for stat: StringName in base:
		set_base(stat, base[stat])


func set_base(stat: StringName, value: float) -> void:
	assert(StatDefs.STATS.has(stat), "Unknown stat: %s" % stat)
	_base[stat] = value
	_cache.erase(stat)


func base(stat: StringName) -> float:
	return _base.get(stat, StatDefs.STATS[stat].base)


func set_source(source: StringName, mods: Array) -> void:
	for m: Array in mods:
		assert(StatDefs.STATS.has(m[0]) and m[1] in [ADD, PCT, MUL], "Bad stat modifier: %s" % [m])
	_sources[source] = mods
	_cache.clear()


func remove_source(source: StringName) -> void:
	if _sources.erase(source):
		_cache.clear()


func has_source(source: StringName) -> bool:
	return _sources.has(source)


func value(stat: StringName) -> float:
	var cached: Variant = _cache.get(stat)
	if cached != null:
		return cached
	var add := 0.0
	var pct := 0.0
	var mul := 1.0
	for mods: Array in _sources.values():
		for m: Array in mods:
			if m[0] != stat:
				continue
			match m[1]:
				ADD:
					add += m[2]
				PCT:
					pct += m[2]
				MUL:
					mul *= m[2]
	var def: Dictionary = StatDefs.STATS[stat]
	var v := (base(stat) + add) * (1.0 + pct) * mul
	if def.get("round", false):
		v = roundf(v)
	v = clampf(v, def.min, def.max)
	_cache[stat] = v
	return v
