# 遊玩紀錄（v0.34.0）：只記本機玩家這一局的擊殺、受到的傷害（依攻擊者種類分）、被看不見的攻擊打中幾次、每次倒下被誰打倒；
# 結算畫面顯示（ui/hud.gd）。只讀事件與模擬狀態，不修改模擬；連線時客戶端用房主送來的事件各記各的
# 「看不見」：被打中那一刻攻擊者在不在自己的視野裡（sim/vision.gd，牆擋視線也算看不見）；攻擊者已經消失時用攻擊的出發點判斷
class_name RunLog
extends RefCounted

const MAX_DOWNS_SHOWN := 5
# Boss 名字同 HUD.BOSS_NAME；不直接引用 HUD：check.gd（-s 腳本）會用到本檔，引用 HUD 會連帶要求 autoload GameEvents 而編譯失敗
const NAMES := {
	&"grunt": "骷髏戰士", &"archer": "骷髏弓手", &"boss": "亡骸騎士", &"ghost": "冤魂",
	&"projectile": "投射物（射手已死）",
}

var me_id := 0          # 本機玩家的實體 id（HUD 每次有角色時更新；倒下 / 陣亡後角色還在，id 不變）
var kills := {}         # 種類 → 隻數（只算自己打死的）
var damage_taken := 0.0
var hits_taken := 0
var unseen_hits := 0
var unseen_damage := 0.0
var by_source := {}     # 種類 → {damage, hits, unseen}
var downs: Array[Dictionary] = []   # 每次倒下 / 死亡：{kind, unseen}


func reset() -> void:
	kills.clear()
	damage_taken = 0.0
	hits_taken = 0
	unseen_hits = 0
	unseen_damage = 0.0
	by_source.clear()
	downs.clear()


func on_event(world: World, name: String, p: Dictionary) -> void:
	match name:
		"entity:damaged":
			if me_id == 0 or p.get("target_id", 0) != me_id:
				return
			var kind: StringName = p.get("source_kind", &"")
			var amount: float = p.get("amount", 0.0)
			var unseen := not _attacker_seen(world, p)
			var s: Dictionary = by_source.get(kind, {"damage": 0.0, "hits": 0, "unseen": 0})
			s.damage += amount
			s.hits += 1
			hits_taken += 1
			damage_taken += amount
			if unseen:
				s.unseen += 1
				unseen_hits += 1
				unseen_damage += amount
			by_source[kind] = s
			if p.get("lethal", false):
				downs.append({"kind": kind, "unseen": unseen})
		"entity:died":
			var kind: StringName = p.get("kind", &"")
			if me_id != 0 and p.get("source_id", 0) == me_id and kind != &"player":
				kills[kind] = kills.get(kind, 0) + 1
		"game:restart":
			reset()


func _attacker_seen(world: World, p: Dictionary) -> bool:
	var me: Player = world.entities.get(me_id) if world != null else null
	if me == null:
		return true
	# 不用 Vision.entity_visible：致命的那一下自己已經倒地，那個函式會把所有東西都當成看得到
	var src: Entity = world.entities.get(p.get("source_id", 0))
	if src != null and not src.is_removed and src != me:
		return Vision.point_visible(world, me, src.pos, src.radius)
	return Vision.point_visible(world, me, p.get("origin", me.pos))


static func name_of(kind: StringName) -> String:
	return NAMES.get(kind, String(kind) if kind != &"" else "不明")


func total_kills() -> int:
	var n := 0
	for k: StringName in kills:
		n += kills[k]
	return n


# 結算畫面的文字（中文自動折行會斷在詞中間，每項一行）
func summary_text() -> String:
	var lines: Array[String] = []
	var kill_kinds := kills.keys()
	kill_kinds.sort_custom(func(a: StringName, b: StringName) -> bool: return kills[a] > kills[b])
	var kill_parts := kill_kinds.map(func(k: StringName) -> String: return "%s %d" % [name_of(k), kills[k]])
	lines.append("你的擊殺 %d" % total_kills() + ("：" + " · ".join(PackedStringArray(kill_parts)) if not kill_parts.is_empty() else ""))
	if hits_taken == 0:
		lines.append("沒有受到傷害")
	else:
		lines.append("受到傷害 %s（被打中 %d 次）" % [UiKit.dmg_text(damage_taken), hits_taken])
		lines.append("被看不見的攻擊打中 %d 次 / %s 傷害（%d%%）" % [unseen_hits, UiKit.dmg_text(unseen_damage), roundi(100.0 * unseen_damage / maxf(1.0, damage_taken))])
		var kinds := by_source.keys()
		kinds.sort_custom(func(a: StringName, b: StringName) -> bool: return by_source[a].damage > by_source[b].damage)
		for k: StringName in kinds:
			var s: Dictionary = by_source[k]
			lines.append("%s：%s 傷害 · %d 次" % [name_of(k), UiKit.dmg_text(s.damage), s.hits] + ("（看不見 %d 次）" % s.unseen if s.unseen > 0 else ""))
	if not downs.is_empty():
		var parts: Array[String] = []
		for d in downs.slice(0, MAX_DOWNS_SHOWN):
			parts.append(name_of(d.kind) + ("（看不見）" if d.unseen else ""))
		lines.append("倒下 %d 次：被 %s 打倒" % [downs.size(), "、".join(parts)] + ("…" if downs.size() > MAX_DOWNS_SHOWN else ""))
	return "\n".join(lines)
