# 玩家操作：移動、轉向、普攻與連段、格擋、受擊、輸入緩衝、死亡、數字鍵道具、翻滾、跳躍、動作手感
# 由 tests/check.gd 呼叫；每個 check_* 回傳 "" = 通過，否則是失敗原因
class_name PlayerChecks
extends CheckKit

static func check_player_move() -> String:
	var w := _new_world()
	_run(w, _cmd(Vector2(1, 0), Vector2(100, 0)), 60)
	var p := _player(w)
	var speed: float = Config.PLAYER.move_speed
	if absf(p.pos.x - speed) > EPS or absf(p.pos.y) > EPS:
		return "60 步後位置 (%.4f, %.4f)，預期 (%.2f, 0)" % [p.pos.x, p.pos.y, speed]
	# 斜向輸入長度被限制為 1（權威端不信任輸入）
	var w2 := _new_world()
	_run(w2, _cmd(Vector2(1, 1)), 60)
	var dist := _player(w2).pos.length()
	if absf(dist - speed) > EPS:
		return "斜向 1 秒移動 %.4f，預期 %.2f" % [dist, speed]
	return ""


static func check_facing() -> String:
	var w := _new_world()
	_run(w, _cmd(Vector2.ZERO, Vector2(5, 0)), 10)
	var f := _player(w).facing
	if absf(f - PI / 2.0) > EPS:
		return "瞄準 +X 時 facing=%.4f，預期 %.4f" % [f, PI / 2.0]
	_run(w, _cmd(Vector2.ZERO, Vector2(0, -5)), 10)
	f = absf(_player(w).facing)
	if absf(f - PI) > EPS:
		return "瞄準 -Z 時 |facing|=%.4f，預期 π" % f
	return ""


static func check_arena_clamp() -> String:
	var w := _new_world()
	_run(w, _cmd(Vector2(1, 0)), 600)
	var p := _player(w)
	var limit: float = Config.WORLD.arena_half_size - Config.PLAYER.radius
	if absf(p.pos.x - limit) > EPS:
		return "x=%.4f，預期 %.4f" % [p.pos.x, limit]
	return ""


static func check_attack_timing() -> String:
	var w := _new_world()
	var p := _player(w)
	_run(w, _cmd(Vector2(1, 0), Vector2(0, 5), InputCmd.BTN_ATTACK), 1)
	if not p.action.is_in(&"attack"):
		return "按住左鍵後應進入 attack，實際 %s" % p.action.current_name
	_run(w, _cmd(Vector2(1, 0)), 1)
	var a: Dictionary = WeaponDefs.WEAPONS[&"swordShield"].attack
	var expected_speed: float = Config.PLAYER.move_speed * a.move_speed_mul
	if absf(p.velocity.length() - expected_speed) > EPS:
		return "攻擊中移速 %.4f，預期 %.4f" % [p.velocity.length(), expected_speed]
	var steps := 2
	while p.action.is_in(&"attack") and steps < 120:
		_run(w, _cmd(Vector2(1, 0)), 1)
		steps += 1
	var expected := ceili((a.windup + a.active + a.recovery) / DT)
	if steps - 1 != expected or not p.action.is_in(&"ready"):
		return "攻擊持續 %d 步（%.3f 秒），預期 %d 步；結束後狀態 %s" % [steps - 1, (steps - 1) * DT, expected, p.action.current_name]
	return ""


static func check_combo() -> String:
	var w := _new_world()
	var p := _player(w)
	var dummy := _dummy(w, Vector2(0, 1.5))
	var events: Array[Dictionary] = []
	var hold := _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK)
	var finisher_recovery := 0.0
	var reached_finisher := false
	for i in 200:
		w.step({World.HOST_PEER_ID: hold}, DT)
		events.append_array(w.events)
		if p.action.is_in(&"attack") and p.action.data.get("is_finisher", false):
			reached_finisher = true
			finisher_recovery = p.action.data.durations[2]
		elif reached_finisher and p.action.is_in(&"attack"):
			break   # 第四刀開始（回到第一段）
	var a: Dictionary = WeaponDefs.WEAPONS[&"swordShield"].attack
	var base := WeaponDefs.move_base_damage(WeaponDefs.WEAPONS[&"swordShield"], a)
	var want := [base, base, base * a.finisher_mul]   # v0.41.0 起保留小數（第三段 21.6，原本四捨五入成 22）
	var amounts := _damage_amounts(events, dummy.id)
	var same := amounts.size() == want.size()
	for i in mini(amounts.size(), want.size()):
		same = same and absf(amounts[i] - want[i]) < 1e-4
	if not same:
		return "三段傷害 %s，預期 %s" % [amounts, want]
	if absf(finisher_recovery - a.recovery * a.finisher_recovery_mul) > EPS:
		return "第三段後搖 %.3f 秒，預期 %.3f" % [finisher_recovery, a.recovery * a.finisher_recovery_mul]
	# 重擊（顯示與音效）只有第三段；爆擊率預設 0%，不會有真正的爆擊
	var heavies := _named(events, "entity:damaged").map(func(e: Dictionary) -> bool: return e.is_heavy)
	if heavies != [false, false, true]:
		return "is_heavy 應只有第三段為 true，實際 %s" % [heavies]
	var crits := _named(events, "entity:damaged").map(func(e: Dictionary) -> bool: return e.is_crit)
	if crits != [false, false, false]:
		return "爆擊率 0%% 時 is_crit 應全為 false，實際 %s" % [crits]
	var sfx := _named(events, "sfx:cue").map(func(e: Dictionary) -> String: return e.cue)
	if sfx != ["swing", "swing", "swingHeavy"]:
		return "音效 %s，預期 swing / swing / swingHeavy" % [sfx]
	return ""


# 格擋（劍盾右鍵）：操作、判定、範圍三段
static func check_block() -> String:
	var err := _block_controls()
	if err == "":
		err = _block_hits()
	if err == "":
		err = _block_ranges()
	return err


const HOLD := InputCmd.BTN_SPECIAL_HELD                       # 右鍵按住
const PRESS_HOLD := InputCmd.BTN_SPECIAL | InputCmd.BTN_SPECIAL_HELD   # 右鍵這一步按下並按住


# 操作（v0.41.0）：按住才格擋、放開就放下、沒有冷卻與時間上限、可移動轉向、翻滾可提前結束；
# 格擋中按左鍵招架（冷卻 parry.cooldown，冷卻中按發 skill:onCooldown），判定時間結束都沒擋到 = 盾擊傷害 × fail_damage_mul
static func _block_controls() -> String:
	var w := _new_world()
	var p := _player(w)
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(5, 0), PRESS_HOLD), 1, events)
	if not p.action.is_in(&"special") or p.block_time < 0.0:
		return "按住右鍵應開始格擋"
	if not _named(events, "skill:used").is_empty() or not w.cooldowns.is_ready(p.cd("player.special")):
		return "格擋不應有冷卻：%s" % [_named(events, "skill:used")]
	# 格擋中可以移動（×0.5）、會轉向瞄準點
	_run(w, _cmd(Vector2(0, 1), Vector2(5, 0), HOLD), 20)
	var sp: Dictionary = WeaponDefs.WEAPONS[&"swordShield"].special
	var block_speed: float = Config.PLAYER.move_speed * sp.move_speed_mul
	var aim_angle := MathUtil.angle_to(p.pos, Vector2(5, 0))   # 邊走邊瞄準固定點，朝向要用目前位置算
	if absf(p.velocity.length() - block_speed) > EPS or absf(angle_difference(p.facing, aim_angle)) > 0.05:
		return "格擋中移速 %.3f（預期 %.3f）、朝向 %.2f（預期 %.2f）" % [p.velocity.length(), block_speed, p.facing, aim_angle]
	# 沒有時間上限：按住 5 秒還在格擋（原本 3 秒就放下）
	_run(w, _cmd(Vector2.ZERO, Vector2(5, 0), HOLD), roundi(5.0 / DT))
	if p.block_time < 0.0:
		return "按住右鍵 5 秒後應還在格擋"
	# 放開：下一步就放下盾（進入收招），收招後回到 ready
	_run(w, _cmd(Vector2.ZERO, Vector2(5, 0)), 1)
	if p.block_time >= 0.0 or p.anim.phase != &"recovery":
		return "放開右鍵應立刻放下盾、進入收招：格擋 %s、階段 %s" % [p.block_time >= 0.0, p.anim.phase]
	_run(w, _cmd(Vector2.ZERO, Vector2(5, 0)), ceili(sp.recovery / DT) + 1)
	if not p.action.is_in(&"ready"):
		return "收招後應回到 ready，實際 %s" % p.action.current_name
	# 沒有冷卻：馬上再按住又能格擋
	_run(w, _cmd(Vector2.ZERO, Vector2(5, 0), PRESS_HOLD), 1)
	if p.block_time < 0.0:
		return "放開後馬上再按住右鍵應能再格擋（沒有冷卻）"
	# 按一下就放開（同一步）：不舉盾
	var w1 := _new_world()
	var p1 := _player(w1)
	_run(w1, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL), 1)
	_run(w1, _cmd(Vector2.ZERO, Vector2(0, 5)), 3)
	if p1.block_time >= 0.0 or not p1.action.is_in(&"ready"):
		return "只按一下沒按住右鍵不應格擋：%s" % p1.action.current_name
	# 翻滾可以提前結束格擋
	var w2 := _new_world()
	var p2 := _player(w2)
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, 5), PRESS_HOLD), 10)
	_run(w2, _cmd(Vector2(1, 0), Vector2(0, 5), HOLD | InputCmd.BTN_ROLL), 1)
	if not p2.action.is_in(&"roll") or p2.block_time >= 0.0:
		return "格擋中按翻滾應結束格擋並翻滾，實際狀態 %s" % p2.action.current_name
	return _parry_controls(sp)


# 招架：格擋中按左鍵、冷卻、判定時間內沒擋到 → 傷害減半的盾擊；放開右鍵也等判定結束；沒格擋時左鍵照常普攻
static func _parry_controls(sp: Dictionary) -> String:
	var pr: Dictionary = sp.parry
	var w := _new_world()
	var p := _player(w)
	p.facing = 0.0
	var dummy := _dummy(w, Vector2(0, 2.0))
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), PRESS_HOLD), 5)
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), HOLD | InputCmd.BTN_ATTACK), 1, events)
	var used := _named(events, "skill:used").filter(func(e: Dictionary) -> bool: return e.key == "player.parry")
	if p.parry_time < 0.0 or used.size() != 1 or not p.action.is_in(&"special"):
		return "格擋中按左鍵應開始招架（skill:used player.parry、還在格擋）：parry_time %.2f、%s、%s" % [p.parry_time, used, p.action.current_name]
	if absf(w.cooldowns.remaining(p.cd("player.parry")) - pr.cooldown) > DT * 1.5:
		return "招架冷卻應約 %.1f 秒，實際 %.3f" % [pr.cooldown, w.cooldowns.remaining(p.cd("player.parry"))]
	# 判定中放開右鍵：等判定結束才打出盾擊；沒擋到攻擊 → 傷害 24 × 0.5 = 12（保留小數，v0.41.0）
	var hp0 := dummy.hp
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5)), ceili(pr.window / DT) + 1)
	var full := WeaponDefs.move_base_damage(WeaponDefs.WEAPONS[&"swordShield"], pr)
	var want: float = full * pr.fail_damage_mul
	if absf((hp0 - dummy.hp) - want) > 1e-4:
		return "招架沒擋到攻擊應打出 %.1f 傷害（%.0f × %.1f），實際 %.4f" % [want, full, pr.fail_damage_mul, hp0 - dummy.hp]
	if p.parry_time >= 0.0 or p.block_time >= 0.0:
		return "判定結束、右鍵已放開後應放下盾"
	# 冷卻中再招架：發 skill:onCooldown、不招架
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5)), ceili(sp.recovery / DT) + 1)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), PRESS_HOLD), 3)
	var ev2: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), HOLD | InputCmd.BTN_ATTACK), 1, ev2)
	var cd_ev := _named(ev2, "skill:onCooldown").filter(func(e: Dictionary) -> bool: return e.key == "player.parry")
	if cd_ev.size() != 1 or p.parry_time >= 0.0:
		return "招架冷卻中按左鍵應發 skill:onCooldown 且不招架：%s、parry_time %.2f" % [cd_ev, p.parry_time]
	# 一直按住左鍵不會連續招架（只有剛按下那一步算）：冷卻好了也要再按一次
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), HOLD | InputCmd.BTN_ATTACK), roundi(pr.cooldown / DT) + 2)
	if p.parry_time >= 0.0 or not w.cooldowns.is_ready(p.cd("player.parry")):
		return "按住左鍵不放不應在冷卻好後自動招架"
	return ""


# 判定：正面擋揮砍、背後擋不住、招架成功全額盾反、Boss 衝鋒擋得住但全額推退、Boss 砸地擋不住
static func _block_hits() -> String:
	var front := Vector2(0, -5)   # 骷髏在玩家 -Z 方向（_grunt_swinging 的配置）
	# 一般格擋：骷髏舉刀時就按住右鍵 → 擋下、不是招架
	var w := _new_world()
	var p := _player(w)
	var g := _grunt_swinging(w, p)
	_run(w, _cmd(Vector2.ZERO, front, PRESS_HOLD), 1)
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO, front, HOLD), 40, events)
	var blocked := _named(events, "player:blocked")
	if p.hp != p.max_hp or blocked.size() != 1 or blocked[0].perfect:
		return "正面應擋下揮砍（不是招架）：血量 %.0f、blocked 事件 %s" % [p.hp, blocked]
	# 背對：擋不住
	var w2 := _new_world()
	var p2 := _player(w2)
	_grunt_swinging(w2, p2)
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, 10), PRESS_HOLD), 1)
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, 10), HOLD), 40)
	if p2.hp >= p2.max_hp:
		return "背對骷髏格擋應擋不住"
	# 招架成功：面向骷髏按住右鍵，在命中前約 0.1 秒按左鍵 → 擋下、下一步全額盾反 25 傷害，右鍵還按著就繼續格擋
	var w3 := _new_world()
	var p3 := _player(w3)
	var g3 := _grunt_swinging(w3, p3)
	var s: Dictionary = EnemyDefs.ENEMIES.grunt.swing
	_run(w3, _cmd(Vector2.ZERO, front, PRESS_HOLD), 1)
	_run(w3, _cmd(Vector2.ZERO, front, HOLD), roundi((s.windup - 0.1) / DT) - 2)
	var g_hp := g3.hp
	var ev3: Array[Dictionary] = []
	_run_collect(w3, _cmd(Vector2.ZERO, front, HOLD | InputCmd.BTN_ATTACK), 1, ev3)
	_run_collect(w3, _cmd(Vector2.ZERO, front, HOLD), 15, ev3)
	var b3 := _named(ev3, "player:blocked")
	if b3.size() != 1 or not b3[0].perfect or p3.hp != p3.max_hp:
		return "招架判定中擋下應為招架成功：%s、血量 %.0f" % [b3, p3.hp]
	var parry_dmg := WeaponDefs.move_base_damage(WeaponDefs.WEAPONS[&"swordShield"], WeaponDefs.WEAPONS[&"swordShield"].special.parry)
	if absf((g_hp - g3.hp) - parry_dmg) > 1e-4 or p3.block_time < 0.0:
		return "招架成功應造成 %.0f 傷害、右鍵還按著就繼續格擋：傷害 %.2f、格擋 %s" % [parry_dmg, g_hp - g3.hp, p3.block_time >= 0.0]
	# Boss 衝鋒（v0.18.2）：正面擋得住、不扣血、只判定一次，但被推退得比一般格擋遠（100% 擊退）
	var w6 := _new_world()
	var p6 := _player(w6)
	var boss6 := _spawn(w6, &"boss", Vector2(0, 8.0))
	_run(w6, _cmd(Vector2.ZERO, Vector2(0, 8)), roundi(EnemyDefs.ENEMIES.boss.spawn_time / DT) + 2)
	boss6.facing = PI
	boss6.fsm.change(&"charge")
	_run(w6, _cmd(Vector2.ZERO, Vector2(0, 8), PRESS_HOLD), 1)
	var ev6: Array[Dictionary] = []
	var push := 0.0   # 擋下那一步的被動推退速度（Boss 本身的推擠不算在內）
	for i in 90:
		_run_collect(w6, _cmd(Vector2.ZERO, boss6.pos, HOLD), 1, ev6)
		if push == 0.0 and not _named(w6.events, "player:blocked").is_empty():
			push = p6.knockback.length()
	var b6 := _named(ev6, "player:blocked")
	if p6.hp != p6.max_hp or b6.size() != 1:
		return "正面應擋下 Boss 衝鋒且只判定一次：血量 %.0f、blocked %d 次" % [p6.hp, b6.size()]
	# 衝鋒擊退 18 ÷ 玩家質量 2 = 9，同一步衰減一次後約 7.7；一般格擋 30% 只有約 2.3
	var expected_push: float = EnemyDefs.ENEMIES.boss.charge.knockback / Config.PLAYER.mass * exp(-Config.COMBAT.knockback_damping * DT)
	if absf(push - expected_push) > 0.05:
		return "擋下衝鋒的推退速度應約 %.2f（100%% 擊退），實際 %.2f" % [expected_push, push]
	# Boss 砸地：格擋也擋不住
	var w5 := _new_world()
	var p5 := _player(w5)
	var boss := _spawn(w5, &"boss", Vector2(0, 2.0))
	_run(w5, _cmd(Vector2.ZERO, Vector2(0, 5), PRESS_HOLD), 20)
	boss.slam_ring(0, {})
	if p5.hp >= p5.max_hp:
		return "Boss 砸地不能被格擋"
	return ""


static func check_stagger() -> String:
	var w := _new_world()
	var p := _player(w)
	_run(w, _cmd(Vector2.ZERO), 1)
	var cfg := Config.PLAYER
	var dealt := p.take_damage(10.0, Vector2(1, 0), 0.0, 0)
	if dealt != 10 or p.hp != p.max_hp - 10.0:
		return "受到 10 傷害後 hp=%.1f" % p.hp
	if not p.action.is_in(&"stagger") or absf(p.invuln_timer - cfg.invuln_time) > EPS:
		return "應進入 stagger 且無敵 %.2f 秒，實際 %s / %.3f" % [cfg.invuln_time, p.action.current_name, p.invuln_timer]
	if _named(w.events, "camera:shake").is_empty():
		return "受傷應發出 camera:shake"
	if p.take_damage(10.0, Vector2(1, 0), 0.0, 0) != -1:
		return "無敵中不應受傷"
	_run(w, _cmd(Vector2(1, 0)), 1)
	var stagger_speed: float = cfg.move_speed * cfg.stagger_move_speed_mul
	if absf(p.velocity.length() - stagger_speed) > EPS:
		return "硬直中移速 %.4f，預期 %.4f" % [p.velocity.length(), stagger_speed]
	_run(w, _cmd(Vector2(1, 0)), ceili(cfg.stagger_time / DT))
	if not p.action.is_in(&"ready"):
		return "%.2f 秒後應回到 ready，實際 %s" % [cfg.stagger_time, p.action.current_name]
	return ""


static func check_buffer() -> String:
	# 劍盾：前搖中按右鍵 → 後搖第一步取消 → 下一步接格擋（不等攻擊自然結束的第 23 步）
	var w := _new_world()
	var p := _player(w)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1)
	_run(w, _cmd(Vector2.ZERO), 1)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), PRESS_HOLD), 1)
	var started := -1
	for i in 30:
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), HOLD), 1)
		if p.action.is_in(&"special"):
			started = w.tick
			break
	var a: Dictionary = WeaponDefs.WEAPONS[&"swordShield"].attack
	var natural_end := ceili((a.windup + a.active + a.recovery) / DT) + 1   # 攻擊自然結束後才接的那一步
	if started < 0 or started >= natural_end:
		return "格擋在第 %d 步才開始，應在攻擊後搖時取消（第 %d 步之前）" % [started, natural_end]
	# 法杖：奧術爆裂前搖 0.35 秒，期間再按右鍵的緩衝 0.25 秒後過期 → 不會在後搖時被消化（不發 skill:onCooldown）
	var w2 := _new_world()
	var p2 := _player(w2)
	p2.equip_weapon(&"staff")
	var events: Array[Dictionary] = []
	_run_collect(w2, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL), 1, events)
	_run_collect(w2, _cmd(Vector2.ZERO), 1, events)
	_run_collect(w2, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL), 1, events)
	_run_collect(w2, _cmd(Vector2.ZERO), 60, events)
	if not _named(events, "skill:onCooldown").is_empty():
		return "緩衝應在 0.25 秒後過期，但後搖時仍被消化"
	return ""


static func check_player_death() -> String:
	var w := _new_world()
	var p := _player(w)
	_run(w, _cmd(Vector2.ZERO), 1)
	p.take_damage(1000.0, Vector2(1, 0), 0.0, 0)
	if not p.is_dead or _named(w.events, "player:died").is_empty() or _named(w.events, "entity:died").is_empty():
		return "應死亡並發出 entity:died 與 player:died"
	if not p.locomotion.is_in(&"dead"):
		return "移動層應為 dead，實際 %s" % p.locomotion.current_name
	var before := p.pos
	_run(w, _cmd(Vector2(1, 0), Vector2(0, 5), InputCmd.BTN_ATTACK | InputCmd.BTN_SPECIAL), 30)
	if p.pos != before or not p.action.is_in(&"ready"):
		return "死亡後仍在移動或出招：pos=%s action=%s" % [p.pos, p.action.current_name]
	return ""


static func _press_slot(w: World, index: int, events: Array[Dictionary], move: Vector2 = Vector2.ZERO) -> void:
	_run_collect(w, _cmd(move, Vector2(0, 5), InputCmd.slot_bit(index)), 1, events)


static func check_heal_slot() -> String:
	var w := _new_world()
	var p := _player(w)
	var h: Dictionary = SkillDefs.SKILLS[&"heal"]
	var amount := roundi(h.amount)
	var cd_steps := ceili(h.cooldown / DT)
	var events: Array[Dictionary] = []
	_press_slot(w, 0, events)
	if _named(events, "skill:onCooldown").is_empty() or p.slots.slots[0].charges != h.charges:
		return "滿血時使用應被擋下（skill:onCooldown）且不扣次數"
	p.hp = 1.0
	events.clear()
	_press_slot(w, 0, events)
	if p.hp != 1.0 + amount or p.slots.slots[0].charges != h.charges - 1 or not p.action.is_in(&"useItem"):
		return "1 血喝藥後 hp=%.0f charges=%d 狀態=%s，預期 %d / %d / useItem" % [p.hp, p.slots.slots[0].charges, p.action.current_name, 1 + amount, h.charges - 1]
	var healed := _named(events, "entity:healed")
	if healed.is_empty() or healed[0].amount != amount:
		return "entity:healed 應為 %d" % amount
	_run(w, _cmd(Vector2.ZERO), cd_steps / 2)
	events.clear()
	_press_slot(w, 0, events)
	if p.slots.slots[0].charges != h.charges - 1 or _named(events, "skill:onCooldown").is_empty():
		return "冷卻 %.2f 秒內再喝應被擋下" % h.cooldown
	_run(w, _cmd(Vector2.ZERO), cd_steps)
	p.hp = p.max_hp - 10.0
	events.clear()
	_press_slot(w, 0, events)
	if p.hp != p.max_hp or _named(events, "entity:healed")[0].amount != 10:
		return "差 10 血喝藥應補到上限（回 10），實際 hp=%.0f" % p.hp
	# 用完所有次數後不能再喝
	for i in h.charges:
		_run(w, _cmd(Vector2.ZERO), cd_steps + 1)
		p.hp = 1.0
		events.clear()
		_press_slot(w, 0, events)
	if p.slots.slots[0].charges != 0 or p.hp != 1.0 or _named(events, "skill:onCooldown").is_empty():
		return "%d 次用完後不能再喝：charges=%d hp=%.0f" % [h.charges, p.slots.slots[0].charges, p.hp]
	return ""


static func check_sprint_slot() -> String:
	var w := _new_world()
	var p := _player(w)
	var events: Array[Dictionary] = []
	_press_slot(w, 1, events, Vector2(1, 0))
	if not p.action.is_in(&"useItem"):
		return "按 2 應進入 useItem，實際 %s" % p.action.current_name
	var s: Dictionary = SkillDefs.SKILLS[&"sprint"]
	var base: float = Config.PLAYER.move_speed
	var item_steps := 1
	while p.action.is_in(&"useItem") and item_steps < 60:
		_run(w, _cmd(Vector2(1, 0)), 1)
		item_steps += 1
	if item_steps - 1 != ceili(Config.PLAYER.use_item_time / DT):
		return "使用道具動作 %d 步，預期 %d" % [item_steps - 1, ceili(Config.PLAYER.use_item_time / DT)]
	if absf(p.velocity.length() - base * s.speed_mul) > EPS:
		return "疾跑移速 %.3f，預期 %.3f" % [p.velocity.length(), base * s.speed_mul]
	if p.anim.trail_color == null:
		return "疾跑中 anim.trail_color 應有顏色（給畫面畫殘影）"
	_run(w, _cmd(Vector2(1, 0)), ceili(s.duration / DT) - item_steps + 2)
	if absf(p.velocity.length() - base) > EPS:
		return "%.1f 秒後移速 %.3f，應回到 %.2f" % [s.duration, p.velocity.length(), base]
	var cd := w.cooldowns.remaining(_player(w).cd(ActiveSlots.cd_key(1)))
	var elapsed := (w.tick - 1) * DT
	if absf(cd - (s.cooldown - elapsed)) > DT * 1.5:
		return "疾跑 CD 剩 %.3f，預期約 %.3f" % [cd, s.cooldown - elapsed]
	return ""


static func check_slot_buffer() -> String:
	var w := _new_world()
	var p := _player(w)
	p.hp = 40.0
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1)
	_run(w, _cmd(Vector2.ZERO), 1)
	var events: Array[Dictionary] = []
	_press_slot(w, 0, events)
	var started := -1
	for i in 30:
		_run(w, _cmd(Vector2.ZERO), 1)
		if p.action.is_in(&"useItem"):
			started = w.tick
			break
	var a: Dictionary = WeaponDefs.WEAPONS[&"swordShield"].attack
	var natural_end := ceili((a.windup + a.active + a.recovery) / DT) + 1
	var want_hp := 40.0 + SkillDefs.SKILLS[&"heal"].amount
	if started < 0 or started >= natural_end or p.hp != want_hp:
		return "攻擊中按 1：第 %d 步才使用、hp=%.0f（應在後搖取消、第 %d 步之前，並回到 %.0f）" % [started, p.hp, natural_end, want_hp]
	events.clear()
	_press_slot(w, 3, events)
	_run_collect(w, _cmd(Vector2.ZERO), 30, events)
	if not _named(events, "skill:onCooldown").is_empty():
		return "空欄位不應發出 skill:onCooldown"
	return ""


# 按一次翻滾（往 +X）直到回到 ready；回傳 [位移, 步數]
static func _do_roll(w: World, p: Player) -> Array:
	var start := p.pos
	_run(w, _cmd(Vector2(1, 0), Vector2(0, 5), InputCmd.BTN_ROLL), 1)
	var steps := 1
	while p.action.is_in(&"roll") and steps < 300:
		_run(w, _cmd(Vector2.ZERO), 1)
		steps += 1
	# 最後一步已回到 ready（沒有位移），不算在翻滾步數內
	return [p.pos.distance_to(start), steps - 1]


static func check_roll_motion() -> String:
	var duration_steps := roundi(Config.ROLL.duration / DT)
	var w := _new_world()
	var p := _player(w)
	var dist: float = Config.ROLL.distance
	var r := _do_roll(w, p)
	if absf(r[0] - dist) > 0.02 or r[1] != duration_steps:
		return "翻滾應 %d 步翻 %.1f 單位，實際 %d 步 %.3f 單位" % [duration_steps, dist, r[1], r[0]]
	if p.roll_charges != 0:
		return "翻滾後次數應為 0，實際 %d" % p.roll_charges
	# 冷卻中再按：不會翻，提示冷卻
	w.events.clear()
	_run(w, _cmd(Vector2(1, 0), Vector2(0, 5), InputCmd.BTN_ROLL), 1)
	if p.action.is_in(&"roll") or _named(w.events, "skill:onCooldown").is_empty():
		return "沒有次數時按翻滾應提示冷卻、不翻"
	# 從開始翻滾算起 cooldown 秒回滿
	_run(w, _cmd(Vector2.ZERO), roundi(Config.ROLL.cooldown / DT) - duration_steps - 3)
	if p.roll_charges != 0:
		return "%.2f 秒前不應回充" % Config.ROLL.cooldown
	_run(w, _cmd(Vector2.ZERO), 3)
	if p.roll_charges != 1:
		return "%.2f 秒後應回充 1 次，實際 %d" % [Config.ROLL.cooldown, p.roll_charges]

	var w2 := _new_world()
	var p2 := _player(w2)
	p2.set_stat_source(&"test", [[&"move_speed", Stats.PCT, 0.5]])
	var fast := _do_roll(w2, p2)
	if absf(fast[0] - dist * 1.5) > 0.03 or fast[1] != duration_steps:
		return "移速 +50%% 應 %d 步翻 %.1f 單位，實際 %d 步 %.3f 單位" % [duration_steps, dist * 1.5, fast[1], fast[0]]

	var w3 := _new_world()
	var p3 := _player(w3)
	p3.set_stat_source(&"test", [[&"roll_charges", Stats.ADD, 1.0], [&"roll_cooldown", Stats.MUL, 0.9]])
	p3.roll_charges = p3.roll_max()
	_run(w3, _cmd(Vector2(1, 0), Vector2(0, 5), InputCmd.BTN_ROLL), 1)
	var cd := w3.cooldowns.remaining(_player(w3).cd(Player.ROLL_CD))
	if absf(cd - Config.ROLL.cooldown * 0.9) > DT * 1.5:
		return "翻滾冷卻 −10%% 應為 %.3f 秒，實際 %.3f" % [Config.ROLL.cooldown * 0.9, cd]
	while p3.action.is_in(&"roll"):
		_run(w3, _cmd(Vector2.ZERO), 1)
	var second := _do_roll(w3, p3)
	if second[1] != duration_steps or p3.roll_charges != 0:
		return "次數 +1 應能連翻第二次，實際 %d 步、剩 %d 次" % [second[1], p3.roll_charges]
	return ""


static func check_roll_invuln() -> String:
	var invuln_steps := roundi(Config.ROLL.invuln_time / DT)
	var w := _new_world()
	var p := _player(w)
	var archer := _spawn(w, &"archer", Vector2(0, 15))
	# 開始翻滾的那一步算第 1 步，無敵涵蓋第 1 ~ 12 步（0.2 秒）
	_run(w, _cmd(Vector2(1, 0), Vector2(0, 5), InputCmd.BTN_ROLL), 1)
	for i in invuln_steps - 2:
		_run(w, _cmd(Vector2.ZERO), 1)
	if p.can_be_hit():
		return "翻滾開始後第 %d 步（0.2 秒內）應無敵" % (invuln_steps - 1)
	# 第 12 步：投射物放在玩家身上，無敵中直接穿過，不會消失
	var arrow := Projectile.new(w, {"owner": archer, "pos": p.pos, "direction": Vector2(0, -1), "speed": 0.01, "range": 5.0, "damage": 10.0})
	w.spawn_projectile(arrow)
	var hp := p.hp
	_run(w, _cmd(Vector2.ZERO), 1)
	if arrow.is_removed or p.hp != hp:
		return "無敵中投射物應穿過：removed=%s 血量 %.0f → %.0f" % [arrow.is_removed, hp, p.hp]
	# 第 13 步：無敵結束，投射物命中
	var arrow2 := Projectile.new(w, {"owner": archer, "pos": p.pos, "direction": Vector2(0, -1), "speed": 0.01, "range": 5.0, "damage": 10.0})
	w.spawn_projectile(arrow2)
	_run(w, _cmd(Vector2.ZERO), 1)
	if not arrow2.is_removed or p.hp >= hp:
		return "0.2 秒後投射物應命中：removed=%s 血量 %.0f → %.0f" % [arrow2.is_removed, hp, p.hp]
	return ""


static func check_roll_cancel() -> String:
	var roll := _cmd(Vector2(1, 0), Vector2(0, 5), InputCmd.BTN_ROLL)
	# 前搖
	var w := _new_world()
	var p := _player(w)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1)
	if not (p.action.is_in(&"attack") and p.action.data.phase_index == 0):
		return "按攻擊後應在前搖"
	_run(w, roll, 1)
	if not p.action.is_in(&"roll"):
		return "前搖應能用翻滾取消，實際狀態 %s" % p.action.current_name
	# 揮下去（active）：先緩衝，active 結束後進入後搖就翻
	var w2 := _new_world()
	var p2 := _player(w2)
	_run(w2, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1)
	while p2.action.is_in(&"attack") and p2.action.data.phase_index == 0:
		_run(w2, _cmd(Vector2.ZERO), 1)
	_run(w2, roll, 1)
	if not (p2.action.is_in(&"attack") and p2.action.data.phase_index == 1):
		return "揮下去時不應被翻滾取消，實際狀態 %s" % p2.action.current_name
	var waited := 0
	while not p2.action.is_in(&"roll") and waited < 30:
		_run(w2, _cmd(Vector2.ZERO), 1)
		waited += 1
	if not p2.action.is_in(&"roll") or waited > roundi(WeaponDefs.WEAPONS[&"swordShield"].attack.active / DT) + 1:
		return "揮下去結束後應接著翻滾（%d 步）" % waited
	# 特殊技與硬直：不取消，結束後在緩衝時間內翻
	for state in [&"special", &"stagger"]:
		var w3 := _new_world()
		var p3 := _player(w3)
		if state == &"special":
			# 用法杖的奧術爆裂（劍盾格擋可以用翻滾結束，見 _block_controls）
			p3.equip_weapon(&"staff")
			_run(w3, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL), 1)
		else:
			p3.action.change(&"stagger")
		_run(w3, roll, 1)
		if p3.action.is_in(&"roll"):
			return "%s 中不應被翻滾取消" % state
	var w4 := _new_world()
	var p4 := _player(w4)
	p4.action.change(&"stagger")
	_run(w4, roll, 1)
	_run(w4, _cmd(Vector2.ZERO), roundi(Config.PLAYER.stagger_time / DT) + 1)
	if not p4.action.is_in(&"roll"):
		return "硬直結束後應執行緩衝的翻滾，實際狀態 %s" % p4.action.current_name
	return ""


static func check_jump_motion() -> String:
	var w := _new_world()
	var p := _player(w)
	_run(w, _jump_cmd(), 1)
	var peak := p.height
	var peak_step := 1
	var steps := 1
	while not p.is_grounded() and steps < 200:
		_run(w, _cmd(Vector2.ZERO), 1)
		steps += 1
		if p.height > peak:
			peak = p.height
			peak_step = steps
	var air_steps := roundi(Config.JUMP.air_time / DT)
	if absf(peak - Config.JUMP.height) > 0.005 or peak_step != air_steps / 2 or steps != air_steps:
		return "最高 %.3f（第 %d 步）、第 %d 步落地；預期 %.2f、第 %d 步、第 %d 步" % [peak, peak_step, steps, Config.JUMP.height, air_steps / 2, air_steps]
	# 空中再按跳躍不會再往上
	_run(w, _jump_cmd(), 10)
	var vz_before := p.vz
	_run(w, _jump_cmd(), 1)
	if p.vz > vz_before:
		return "空中再按跳躍不應再往上（二段跳）"
	while not p.is_grounded():
		_run(w, _cmd(Vector2.ZERO), 1)
	# 攻擊中可以跳
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1)
	_run(w, _jump_cmd(Vector2.ZERO, InputCmd.BTN_ATTACK), 1)
	if not p.action.is_in(&"attack") or p.height <= 0.0:
		return "攻擊中應能起跳（狀態 %s、高度 %.2f）" % [p.action.current_name, p.height]
	while not p.is_grounded():
		_run(w, _cmd(Vector2.ZERO), 1)
	_run(w, _cmd(Vector2.ZERO), 30)
	# 硬直中不能跳
	p.action.change(&"stagger")
	_run(w, _jump_cmd(), 1)
	if p.height > 0.0:
		return "硬直中不應能跳"
	_run(w, _cmd(Vector2.ZERO), 30)
	# 空中翻滾：高度持續下降、水平一樣 4 單位
	var w2 := _new_world()
	var p2 := _player(w2)
	_run(w2, _jump_cmd(), air_steps / 2)
	var h0 := p2.height
	var r := _do_roll(w2, p2)
	if absf(r[0] - Config.ROLL.distance) > 0.02:
		return "空中翻滾水平應為 %.1f 單位，實際 %.3f" % [Config.ROLL.distance, r[0]]
	if p2.height >= h0:
		return "空中翻滾應照常下墜（%.2f → %.2f）" % [h0, p2.height]
	return ""


# 範圍：擋箭的角度（block_arc 邊界內外各 5°，箭擋下會消失）、盾反的距離與角度
static func _block_ranges() -> String:
	var sp: Dictionary = WeaponDefs.WEAPONS[&"swordShield"].special
	var edge := rad_to_deg(sp.block_arc / 2.0)
	# 角度：面向 +Z 按住右鍵 20 步後，箭從不同角度飛向玩家
	for case in [[edge - 5.0, true], [edge + 5.0, false]]:
		var w := _new_world()
		var p := _player(w)
		var archer := _spawn(w, &"archer", Vector2(0, 15))
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), PRESS_HOLD), 1)
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), HOLD), 19)
		var a := deg_to_rad(case[0])
		var from := p.pos + Vector2(sin(a), cos(a)) * 1.5
		var arrow := Projectile.new(w, {"owner": archer, "pos": from, "direction": p.pos - from, "speed": 10.0,
			"range": 5.0, "damage": 12.0, "altitude": Config.HEIGHT.arrow_altitude, "blockable": true})
		w.spawn_projectile(arrow)
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), HOLD), 20)
		if (p.hp == p.max_hp) != case[1] or not arrow.is_removed:
			return "箭從 %.0f° 飛來：%s，血量 %.0f、箭消失 %s" % [case[0], "應擋下" if case[1] else "應擋不下", p.hp, arrow.is_removed]
	# 盾反：距離 range（加目標半徑 0.5）、角度 arc；邊界角內 5°、距離邊界內外
	var pa: Dictionary = sp.parry
	var w3 := _new_world()
	var p3 := _player(w3)
	p3.facing = 0.0
	var side := deg_to_rad(rad_to_deg(pa.arc / 2.0) - 5.0)
	var side_in := _dummy(w3, Vector2(sin(side), cos(side)) * (pa.range + 0.3))
	var side_out := _dummy(w3, Vector2(-sin(side), cos(side)) * (pa.range + 0.7))
	var back := _dummy(w3, Vector2(0, -2.0))
	p3._do_parry()
	var fx := _named(w3.events, "fx:parry")
	if side_in.hp >= 1000.0 or side_out.hp < 1000.0 or back.hp < 1000.0:
		return "盾反範圍：側面 %.1f %s、%.1f %s、背後 2.0 %s（應為 中 / 沒中 / 沒中）" % [pa.range + 0.3, side_in.hp < 1000.0, pa.range + 0.7, side_out.hp < 1000.0, back.hp < 1000.0]
	if fx.size() != 1 or absf(fx[0].radius - pa.range) > EPS or absf(fx[0].arc - pa.arc) > EPS or not fx[0].has("facing"):
		return "fx:parry 應帶 radius %.1f、arc %.2f、facing：%s" % [pa.range, pa.arc, fx]
	return ""


static func check_double_jump() -> String:
	var w := _new_world()
	var p := _player(w)
	var peak := func(presses: Array) -> float:
		var top := 0.0
		for i in 90:
			var jump := presses.has(i)
			_run(w, _jump_cmd() if jump else _cmd(Vector2.ZERO), 1)
			top = maxf(top, p.height)
		return top
	var h1: float = peak.call([0, 15])
	if h1 > Config.JUMP.height + 0.01:
		return "沒有道具時空中不應再跳（最高 %.2f）" % h1
	if p.add_item(&"twin_leap_boots") == &"":
		return "雙躍之靴應放得進背包"
	var h2: float = peak.call([0, 15, 30])
	if h2 <= Config.JUMP.height + 0.3:
		return "有雙躍之靴時空中應能再跳（最高 %.2f）" % h2
	var h3: float = peak.call([0, 15, 30])
	if absf(h3 - h2) > 0.01:
		return "落地後應重置空中跳躍次數：第二次最高 %.2f，第一次 %.2f" % [h3, h2]
	return ""


# 擊退的積分：每步 position += knockback × dt，之後 knockback ×= exp(-阻尼 × dt)；k0 起速跑 n 步的總位移
static func _knockback_distance(k0: float, n: int) -> float:
	var r := exp(-Config.COMBAT.knockback_damping * DT)
	return k0 * DT * (1.0 - pow(r, n)) / (1.0 - r)


# 按一下攻擊（只按一步），之後放開跑 rest 步
static func _tap_attack(w: World, rest: int) -> void:
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5)), rest)


# 動作手感：擊退位移、轉身速度、普攻前衝、連段窗口
static func check_motion_feel() -> String:
	var w0 := _new_world()
	var p0 := _player(w0)
	var d := _dummy(w0, Vector2(0, 4), 1000.0, 1.0)
	Combat.apply_damage(w0, p0, d, {"damage": 1.0, "knockback": 7.0})
	_run(w0, _cmd(Vector2.ZERO, Vector2(0, -5)), 120)
	var moved := d.pos.y - 4.0
	var kb_expect := _knockback_distance(7.0, 120)
	_feel("擊退 7、質量 1：公式 %.4f，實測 %.4f 單位" % [kb_expect, moved])
	if absf(moved - kb_expect) >= 1e-4:
		return "擊退位移 %.4f，公式 %.4f" % [moved, kb_expect]

	var wt := _new_world()
	var pt := _player(wt)
	_run(wt, _cmd(Vector2.ZERO, Vector2(0, 5)), 10)
	var turn_steps := 0
	while turn_steps < 60 and absf(angle_difference(pt.facing, PI)) > 1e-4:
		_run(wt, _cmd(Vector2.ZERO, Vector2(0, -5)), 1)
		turn_steps += 1
	var turn_expect := ceili(PI / (Config.PLAYER.turn_speed * DT))
	_feel("轉身 180°：預期 %d 步，實測 %d 步（%.3f 秒）" % [turn_expect, turn_steps, turn_steps * DT])
	if turn_steps != turn_expect:
		return "轉身 %d 步，預期 %d" % [turn_steps, turn_expect]

	var def: Dictionary = WeaponDefs.WEAPONS.swordShield.attack
	var w := _new_world()
	var p := _player(w)
	var start := p.pos
	_tap_attack(w, 120)
	var lunge := p.pos.distance_to(start)
	# 前衝在 active 開始時加上，到量測時跑了 120 + 1 - windup 步
	var steps_after := 121 - roundi(def.windup / DT)
	var expect := _knockback_distance(def.lunge, steps_after)
	_feel("普攻前衝：公式 %.4f，實測 %.4f 單位" % [expect, lunge])
	if absf(lunge - expect) > 0.005:
		return "前衝 %.4f，公式 %.4f" % [lunge, expect]

	# 連段：收招後 combo_window 內出手接下一段，超過就回到第一段
	var total := roundi((def.windup + def.active + def.recovery) / DT)
	var early: float = def.combo_window - 0.05
	var late: float = def.combo_window + 0.05
	var w2 := _new_world()
	var p2 := _player(w2)
	_tap_attack(w2, total + roundi(early / DT))
	_tap_attack(w2, 0)
	var within := p2.combo_step
	var w3 := _new_world()
	var p3 := _player(w3)
	_tap_attack(w3, total + roundi(late / DT))
	_tap_attack(w3, 0)
	var after := p3.combo_step
	_feel("連段：收招後 %.2f 秒出手 → 第 %d 段；%.2f 秒出手 → 第 %d 段（窗口 %.2f 秒）" % [early, within + 1, late, after + 1, def.combo_window])
	if within != 1 or after != 0:
		return "%.2f 秒後應接第 2 段（實際第 %d 段），%.2f 秒後應回第 1 段（實際第 %d 段）" % [early, within + 1, late, after + 1]

	# 第三段前衝 × finisher_scale
	var w4 := _new_world()
	var p4 := _player(w4)
	for i in 2:
		_tap_attack(w4, total + 3)
	var before := p4.pos
	var residual := p4.knockback.length()   # 第二段前衝還沒衰減完（收招後只隔 3 步），同方向，要一起算
	_tap_attack(w4, 120)
	var fin := p4.pos.distance_to(before)
	var fin_expect := _knockback_distance(def.lunge * def.finisher_scale, steps_after) + _knockback_distance(residual, 121)
	_feel("第三段前衝：公式 %.4f，實測 %.4f 單位" % [fin_expect, fin])
	return "" if absf(fin - fin_expect) < 0.005 else "第三段前衝 %.4f，公式 %.4f" % [fin, fin_expect]


# 職業（F2）：開局套用基礎數值、起始武器與被動；沒選職業照舊；守墓騎士被隊友從背後打到減半、正面照常
static func check_classes() -> String:
	var plain := _player(_new_world())
	if plain.class_id != ClassDefs.NONE or plain.max_hp != Config.PLAYER.max_hp or plain.weapon_id != Config.PLAYER.start_weapon:
		return "沒選職業應照舊：%s、生命 %.0f、%s" % [plain.class_id, plain.max_hp, plain.weapon_id]
	for id: StringName in ClassDefs.ORDER:
		var c: Dictionary = ClassDefs.CLASSES[id]
		var w := World.new(&"test_arena")
		_worlds.append(w)
		w.spawn_packs = false
		w.player_classes[World.HOST_PEER_ID] = id
		w.reset(1)
		var p := _player(w)
		if p.class_id != id or p.weapon_id != c.weapon or p.hp != p.max_hp:
			return "%s：職業 %s、武器 %s（應 %s）、血 %.0f / %.0f" % [c.name, p.class_id, p.weapon_id, c.weapon, p.hp, p.max_hp]
		for stat: StringName in c.stats:
			if absf(p.stats.base(stat) - c.stats[stat]) > EPS:
				return "%s 的%s基礎值應 %.2f，實際 %.2f" % [c.name, StatDefs.STATS[stat].name, c.stats[stat], p.stats.base(stat)]
		for m: Array in c.passive.get("mods", []):
			var b := p.stats.base(m[0])
			var want: float = b + m[2] if m[1] == Stats.ADD else (b * (1.0 + m[2]) if m[1] == Stats.PCT else b * m[2])
			if absf(p.stats.value(m[0]) - want) > EPS:
				return "%s 被動：%s 應 %.2f，實際 %.3f" % [c.name, StatDefs.STATS[m[0]].name, want, p.stats.value(m[0])]
		w.reset(2)
		if _player(w).class_id != id:
			return "重新開始應保留職業"
	# 騎士被隊友從背後打到減半、正面照常（誤傷，Config.NET.friendly_fire）
	var g: Dictionary = ClassDefs.CLASSES[&"guardian"]
	var kw := _new_world()
	var knight := Player.new(kw, 7)
	kw.add_entity(knight)   # 加進 World：結束時 clear() 才會切斷玩家與狀態機的循環參照（不加會洩漏）
	knight.apply_class(&"guardian")
	knight.facing = 0.0   # 面向 +Z
	if knight.friendly_back_mul(Vector2(0, -2)) != g.passive.friendly_back_mul or knight.friendly_back_mul(Vector2(0, 2)) != 1.0:
		return "騎士：背後來的應 × %.1f、正面 × 1：%.2f / %.2f" % [g.passive.friendly_back_mul, knight.friendly_back_mul(Vector2(0, -2)), knight.friendly_back_mul(Vector2(0, 2))]
	return ""
