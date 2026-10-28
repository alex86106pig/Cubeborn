# 畫面、介面與音效：視野、預熱、剪影、新手提示、HUD、結算、特效、字型、模型零件、音效與音樂
# 由 tests/check.gd 呼叫；每個 check_* 回傳 "" = 通過，否則是失敗原因
class_name ViewChecks
extends CheckKit

static func check_sim_cues() -> String:
	var cues := _cue_names()
	var re := RegEx.create_from_string("\"cue\": \"(\\w+)\"")
	var count := 0
	for path in _list_gd("res://sim"):
		for m in re.search_all(_read_text(path)):
			count += 1
			if not cues.has(m.get_string(1)):
				return "%s 的音效「%s」不在 Sound.CUE_NAMES" % [path, m.get_string(1)]
	if count < 8:   # 目前 sim/ 有 9 個字面音效名稱；玩家武器音效走變數，由「武器資料」檢查負責
		return "只比對到 %d 個 sfx:cue，比對規則可能失效" % count
	return ""


# -s 執行的檢查腳本在 autoload 註冊前就編譯，不能直接寫 HUD / GameEvents 型別（hud.gd 引用了 GameEvents），
# 所以 HUD 用 load() 在執行時載入、變數不寫型別，事件直接交給 HUD
static func _feed_hud(hud: Node, events: Array[Dictionary]) -> void:
	for e in events:
		hud._on_event(e.name, e)


# 寶箱模型（v0.38.0）：已開過的寶箱重新建立模型時（連線離開視野再回來）箱蓋直接是打開的，沒開過的照常關著
static func check_chest_lid() -> String:
	var w := _new_world()
	var shut := Chest.new(w, &"small", Vector2(3, 3))
	var open := Chest.new(w, &"big", Vector2(-3, 3))
	open.opened = true
	for c in [shut, open]:
		w.add_entity(c)
		w.chests.append(c)
	var view := WorldView.new()
	view.sync(w, 1.0, DT)
	var lid_shut: float = (view._nodes[shut.id] as Node3D).get_node(^"Lid").rotation.x
	var lid_open: float = (view._nodes[open.id] as Node3D).get_node(^"Lid").rotation.x
	view.free()
	if absf(lid_shut) > EPS or absf(lid_open - WorldView.CHEST_LID_OPEN) > EPS:
		return "剛建立的模型：沒開過的箱蓋 %.2f（應 0）、開過的 %.2f（應 %.2f）" % [lid_shut, lid_open, WorldView.CHEST_LID_OPEN]
	return ""


# 挖墳進度條（v0.38.0）：事件進行中顯示進度與說明（Boss 活著 / 怪潮中），出口打開後收起；Boss 血條排在它下面
static func check_dig_bar() -> String:
	var w := _new_world(5, true, &"graveyard_a")
	var cam := _test_camera()
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w, cam)
	_scene_root().add_child(hud)
	var err := ""
	hud._process(DT)
	if hud._dig_box.visible:
		err = "事件還沒開始就顯示挖墳進度條"
	if err == "":
		w.event._start(w)
		w.event.progress = 0.42
		hud._process(DT)
		if not hud._dig_box.visible or hud._dig.text.text != "42%" or not hud._dig_name.text.contains("噴出怪物"):
			err = "事件中：進度條 %s、%s、%s（說明要提到噴怪）" % [hud._dig_box.visible, hud._dig.text.text, hud._dig_name.text]
		elif absf(hud._dig.fill.size.x - hud._dig.width * 0.42) > 0.5:
			err = "進度條長度 %.1f，預期 %.1f" % [hud._dig.fill.size.x, hud._dig.width * 0.42]
	if err == "":
		var top: Control = hud._dig_box.get_parent()
		if top != hud._boss_box.get_parent() or hud._dig_box.get_index() > hud._boss_box.get_index():
			err = "Boss 血條應和挖墳進度條在同一欄、排在下面"
		elif top.get_combined_minimum_size().x > 1920.0:
			err = "上方中央那一欄寬 %.0f，超出 1920" % top.get_combined_minimum_size().x
	if err == "":
		w.event.state = DigEvent.OPEN
		hud._process(DT)
		if hud._dig_box.visible:
			err = "出口打開後應收起挖墳進度條"
	# 投票橫幅：投票中才顯示；自己還沒同意時提示 Enter / Esc，同意後不提示
	if err == "":
		w.event.vote_by = World.HOST_PEER_ID
		w.event.vote_left = 9.2
		w.event.vote_yes.assign([2])
		hud._process(DT)
		if not hud._vote.visible or not hud._vote.text.contains("[Enter]") or not hud._vote.text.contains("10 秒"):
			err = "投票中、自己還沒同意：橫幅 %s「%s」" % [hud._vote.visible, hud._vote.text]
		w.event.vote_yes.assign([2, World.HOST_PEER_ID])
		hud._process(DT)
		if err == "" and hud._vote.text.contains("[Enter]"):
			err = "自己同意後不應再提示 Enter / Esc：%s" % hud._vote.text
		w.event.vote_by = 0
		w.event.vote_yes.clear()
		hud._process(DT)
		if err == "" and hud._vote.visible:
			err = "沒有投票時應收起投票橫幅"
	hud.queue_free()
	cam.queue_free()
	return err


static func check_hud() -> String:
	var w := _new_world(5, true)
	var cam := _test_camera()
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w, cam)
	_scene_root().add_child(hud)
	var p := _player(w)
	hud._process(DT)
	var hp_text := "%d / %d" % [p.max_hp, p.max_hp]
	if hud._wave.text != "準備中" or hud._hp.text.text != hp_text:
		return "開場文字錯誤：%s / %s（預期 準備中 / %s）" % [hud._wave.text, hud._hp.text.text, hp_text]
	_run(w, _cmd(Vector2.ZERO), roundi(Config.SPAWNER.first_delay / DT) + 10)
	_feed_hud(hud, w.events)
	hud._process(DT)
	var wave_text := "第 1 / %d 波" % WaveDefs.WAVES.size()
	if hud._wave.text != wave_text:
		return "波次文字 %s，預期 %s" % [hud._wave.text, wave_text]
	var b := _spawn(w, &"boss", Vector2(5, 5))
	_run(w, _cmd(Vector2.ZERO), 30)
	Combat.apply_damage(w, p, b, {"damage": 500.0, "is_heavy": true})
	p.hp = 50.0
	Combat.apply_damage(w, b, p, {"damage": 10.0})
	_feed_hud(hud, w.events)
	hud._process(DT)
	if not hud._boss_box.visible or not hud._boss_name.text.contains("狂暴"):
		return "Boss 血條應顯示且標示狂暴：visible=%s name=%s" % [hud._boss_box.visible, hud._boss_name.text]
	if hud._floaters.get_child_count() < 2:
		return "應產生浮動數字，實際 %d 個" % hud._floaters.get_child_count()
	w.events.clear()
	p.add_item(&"loaded_dice")
	_feed_hud(hud, w.events)
	var dice: Dictionary = ItemDefs.ITEMS[&"loaded_dice"]
	if hud._banner.text != "獲得 %s\n%s" % [dice.name, dice.desc]:
		return "item:added 橫幅文字錯誤：%s" % hud._banner.text
	# 別人撿到的不跳（v0.38.0：連線時事件全廣播，原本會跳在對方畫面）
	hud._banner.text = ""
	hud._on_event("item:added", {"player_id": p.id + 1000, "item": "whetstone", "uid": "x"})
	if hud._banner.text != "":
		return "別人撿到道具不應跳橫幅：%s" % hud._banner.text
	# 武器欄的另一把標示切換鍵 X（v0.38.0，原本寫 Q）
	p.add_weapon({"uid": &"st", "base": &"staff", "rarity": &"white", "affixes": [] as Array[StringName]})
	hud._process(DT)
	if not hud._weapon.text.contains("（X："):
		return "武器欄的另一把應標示 X：%s" % hud._weapon.text
	for name in ["game:paused", "player:died", "game:defeat", "game:victory", "game:restart"]:
		var payload := {"paused": true, "stats": w.stats.duplicate()}
		hud._on_event(name, payload)
	if hud._game_over.visible or hud._pause.visible:
		return "game:restart 後結算與暫停畫面應隱藏"
	if hud._quit_button.get_parent() == null or not hud._pause.is_ancestor_of(hud._quit_button) or not hud._quit_button.visible:
		return "暫停畫面應有可見的「離開遊戲」按鈕"
	var quit_count := [0]
	hud.quit_requested.connect(func() -> void: quit_count[0] += 1)
	hud._quit_button.pressed.emit()
	if quit_count[0] != 1:
		return "按下「離開遊戲」應發出 quit_requested 一次，實際 %d 次" % quit_count[0]
	hud._on_event("game:victory", {"stats": w.stats.duplicate()})
	if not hud._game_over.visible or hud._game_over_title.text != "勝利！":
		return "game:victory 應顯示勝利畫面"
	hud.queue_free()
	cam.queue_free()
	return ""


# 主選單（v0.39.0）：首頁三個按鈕、多人頁放連線面板、按鈕發訊號、尺寸塞得進 1920×1080；
# 關掉後連線面板搬回暫停畫面，單機暫停時不顯示、連線中才顯示；暫停畫面有「回主選單」
static func check_main_menu() -> String:
	var w := _new_world(5)
	var cam := _test_camera()
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w, cam)
	_scene_root().add_child(hud)
	var err := _check_main_menu(hud)
	if err == "":
		err = await _check_class_select(hud)
	if err == "":
		err = _check_weapon_test_bar(hud)
	hud.queue_free()
	cam.queue_free()
	return err


# 選角畫面（2026-10-27）：點職業只是選、按「開始」才發出（職業, 難度）；鎖住的佔位選不到；
# 數值條是選的職業套上 Player.apply_class 後的屬性；技能四格；整頁塞得進介面最大檔
static func _check_class_select(hud: Variant) -> String:
	var cs: ClassSelect = hud.class_select
	var started: Array = []
	cs.start_pressed.connect(func(id: StringName, d: StringName) -> void: started.append([id, d]))
	cs.open_single()
	var last: StringName = ClassDefs.ORDER.back()
	cs.class_buttons[last].pressed.emit()
	if not started.is_empty() or cs.selected != last:
		return "點職業應只是選、不開局：選了 %s、開局 %s" % [cs.selected, started]
	for id: StringName in ClassDefs.PLACEHOLDERS:
		if not _shown(cs.class_buttons[id], cs):
			return "選角畫面應看得到佔位「%s」" % ClassDefs.PLACEHOLDERS[id].name
		cs.class_buttons[id].pressed.emit()
	if cs.selected != last:
		return "點鎖住的佔位不應被選到：%s" % cs.selected
	cs.difficulty_buttons[&"hard"].pressed.emit()
	cs.start_button.pressed.emit()
	if started != [[last, &"hard"]]:
		return "按「開始」應發出 start_pressed(選的職業, 難度)：%s" % [started]
	for id: StringName in ClassDefs.ORDER:
		cs.class_buttons[id].pressed.emit()
		var p := Player.new(hud.world, 0)   # 每個職業一個新角色：apply_class 只覆寫職業有寫的屬性
		p.apply_class(id)
		for i in ClassSelect.CHART.size():
			var want := p.stats.base(ClassSelect.CHART[i][0])
			if not is_equal_approx(cs.chart.values[i][1], want):
				p.detach()
				return "%s 的數值條「%s」應是 %s，實際 %s" % [ClassDefs.CLASSES[id].name, ClassSelect.CHART[i][1], want, cs.chart.values[i][1]]
		if not is_equal_approx(cs.chart.values[0][1], ClassDefs.CLASSES[id].stats.max_hp):
			p.detach()
			return "%s 的生命條應是職業資料的 %s" % [ClassDefs.CLASSES[id].name, ClassDefs.CLASSES[id].stats.max_hp]
		# 被動 / 左鍵 / 右鍵 / 翻滾，武器帶技能欄技能（火把的插火把）的多一格
		var want_rows := 5 if WeaponDefs.WEAPONS[ClassDefs.CLASSES[id].weapon].has("slot_skill") else 4
		if cs._skills.get_child_count() != want_rows or cs.name_label.text != ClassDefs.CLASSES[id].name:
			p.detach()
			return "%s：技能應有 %d 格（%d）、名稱「%s」" % [ClassDefs.CLASSES[id].name, want_rows, cs._skills.get_child_count(), cs.name_label.text]
		p.detach()
	var room := _menu_room()
	var need := await _settled_min_size(cs.get_child(0).get_child(0))
	_note("選角畫面 %.0f×%.0f（介面最大檔時可用 %.0f×%.0f）" % [need.x, need.y, room.x, room.y])
	if need.x > room.x or need.y > room.y:
		return "選角畫面 %.0f×%.0f，超出介面最大檔時的 %.0f×%.0f" % [need.x, need.y, room.x, room.y]
	# 畫面大小固定（2026-10-27 使用者：不要隨字數變化）：每個職業、單人 / 四人大廳的整頁一樣大，資訊欄的內容放得下（固定框會裁切）
	var single_size := need
	var clip_h: float = ClassSelect.INFO_SIZE.y - ClassSelect.INFO_PAD * 2.0
	for id: StringName in ClassDefs.ORDER:
		cs.class_buttons[id].pressed.emit()
		var page_size := await _settled_min_size(cs.get_child(0).get_child(0))
		var content_h: float = cs.info_box.get_combined_minimum_size().y
		if page_size != single_size or content_h > clip_h:
			return "%s：整頁 %s（應固定 %s）、資訊欄內容高 %.0f（框 %.0f）" % [ClassDefs.CLASSES[id].name, page_size, single_size, content_h, clip_h]
	# 「拖動旋轉」提示在舞台右下角、不超出舞台
	var stage_rect := (cs.drag_hint.get_parent() as Control).get_global_rect()
	var hint_rect := cs.drag_hint.get_global_rect()
	_note("拖動旋轉提示 %s（舞台 %s）" % [hint_rect, stage_rect])
	if not stage_rect.encloses(hint_rect) or stage_rect.end.x - hint_rect.end.x < ClassSelect.HINT_MARGIN.x - 1.0:
		return "「拖動旋轉」提示 %s 應在舞台 %s 裡、離右邊至少 %.0f" % [hint_rect, stage_rect, ClassSelect.HINT_MARGIN.x]
	# 四人大廳（名單、四個人的頭上標籤）也一樣大；右上角有「複製房號」
	cs.show_lobby(&"lobby_client", [1, 2, 3, 4], 3, {1: ["guardian", true], 2: ["ranger", true], 3: ["priest", false], 4: ["gravedigger", true]}, &"hard", "房號 ABCD（4 / 4 人）", "ABCD")
	need = await _settled_min_size(cs.get_child(0).get_child(0))
	_note("選角畫面（四人大廳）%.0f×%.0f" % [need.x, need.y])
	if need != single_size:
		return "四人大廳的選角畫面 %.0f×%.0f，應和單人一樣 %.0f×%.0f" % [need.x, need.y, single_size.x, single_size.y]
	if not _shown(cs.copy_button, cs):
		return "大廳右上角應有「複製房號」"
	cs.copy_button.pressed.emit()
	if cs.copied != "ABCD":
		return "按「複製房號」應放進 ABCD，實際「%s」" % cs.copied
	cs.open_single()
	cs.back_button.pressed.emit()
	if cs.visible:
		return "選角畫面按「返回」應關掉"
	return ""


# 武器測試場的按鈕列（2026-10-27）：預設隱藏；每把武器一顆（按下發 weapon_test_equip）+ 重置木樁；寬度塞得進 1920
static func _check_weapon_test_bar(hud: Variant) -> String:
	var bar: HBoxContainer = hud.weapon_test_bar
	if bar.visible:
		return "武器測試場的按鈕列平常應隱藏"
	var buttons := bar.get_children().filter(func(c: Node) -> bool: return c is Button)
	if buttons.size() != WeaponDefs.WEAPONS.size() + 1:
		return "按鈕列應有 %d 把武器 + 重置木樁，實際 %d 顆" % [WeaponDefs.WEAPONS.size(), buttons.size()]
	var got: Array[StringName] = []
	hud.weapon_test_equip.connect(func(id: StringName) -> void: got.append(id))
	for i in WeaponDefs.WEAPONS.size():
		(buttons[i] as Button).pressed.emit()
	if got != WeaponDefs.WEAPONS.keys():
		return "武器按鈕應依序發出 %s，實際 %s" % [WeaponDefs.WEAPONS.keys(), got]
	if bar.get_combined_minimum_size().x > 1920.0:
		return "按鈕列寬 %.0f，超出 1920" % bar.get_combined_minimum_size().x
	return ""


# 技能欄（v0.41.0）：劍盾格擋中左鍵那格換成「招架」並顯示招架冷卻，放下盾換回普攻；法杖沒有招架格
static func check_skill_bar_parry() -> String:
	var w := _new_world()
	var p := _player(w)
	var bar := SkillBar.new()
	_scene_root().add_child(bar)
	var err := ""
	bar.refresh(w, p)
	if bar._parry_slot == null or bar._parry_slot.visible or not bar._attack_slot.visible:
		err = "沒格擋時左鍵應顯示普攻、招架格隱藏"
	if err == "":
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL | InputCmd.BTN_SPECIAL_HELD), 3)
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL_HELD | InputCmd.BTN_ATTACK), 1)
		bar.refresh(w, p)
		var cd_left: float = bar._slots["player.parry"].cd_left
		if not bar._parry_slot.visible or bar._attack_slot.visible or bar._parry_slot.icon_id != WeaponDefs.WEAPONS.swordShield.special.parry.icon or cd_left <= 0.0:
			err = "格擋中左鍵應換成「招架」並顯示冷卻：顯示 %s、文字 %s、冷卻 %.2f" % [bar._parry_slot.visible, bar._parry_slot.icon_id, cd_left]
	if err == "":
		_run(w, _cmd(Vector2.ZERO, Vector2(0, 5)), 30)
		bar.refresh(w, p)
		if bar._parry_slot.visible or not bar._attack_slot.visible:
			err = "放下盾後左鍵應換回普攻"
	if err == "":
		p.equip_weapon(&"staff")
		bar.refresh(w, p)
		if bar._parry_slot != null:
			err = "法杖不應有招架格"
	if err == "":
		# 火把（2026-10-27）：舉著時只有左鍵換成噴火（右鍵格不變）；插火把在技能欄第一個空格、顯示武器上的次數，換武器就消失
		p.equip_weapon(&"torch")
		bar.refresh(w, p)
		var tw: Dictionary = WeaponDefs.WEAPONS[&"torch"]
		var plant: Dictionary = SkillDefs.SKILLS[tw.slot_skill]
		var idx := p.slots.weapon_slot_index(p)
		var plant_slot: SkillBar.Slot = bar._slots.get(ActiveSlots.cd_key(idx)) if idx >= 0 else null
		if idx != Config.PLAYER.slots.find(null) or plant_slot == null or plant_slot.icon_id != plant.icon \
				or plant_slot.charges.text != str(plant.charges):
			err = "拿火把時插火把應在第 %d 格、顯示 %d 次：第 %d 格 %s / %s" % [Config.PLAYER.slots.find(null) + 1, plant.charges, idx + 1,
				plant_slot.icon_id if plant_slot else "-", plant_slot.charges.text if plant_slot else "-"]
		p.active_weapon()["slot_charges"] = 1
		bar.refresh(w, p)
		if err == "" and (plant_slot.charges.text != "1" or WeaponDropDefs.display_name(p.active_weapon()).right(3) != "（1）"):
			err = "插火把次數與武器名稱應跟著武器（剩 1）：%s / %s" % [plant_slot.charges.text, WeaponDropDefs.display_name(p.active_weapon())]
		p.torch_stance = true
		bar.refresh(w, p)
		if err == "" and (not bar._alt_left.visible or bar._attack_slot.visible or not bar._special_slot.visible \
				or bar._alt_left.icon_id != tw.stance.attack.icon):
			err = "舉著火把時左鍵應換成「%s」、右鍵不變：%s / 右鍵 %s" % [tw.stance.attack.icon, bar._alt_left.icon_id, bar._special_slot.visible]
		p.torch_stance = false
		bar.refresh(w, p)
		if err == "" and (bar._alt_left.visible or not bar._attack_slot.visible):
			err = "放下火把應換回平常的左鍵"
	if err == "":
		# 鐵鏟舉著怪：左右鍵換成拋出 / 埋入
		p.equip_weapon(&"shovel")
		bar.refresh(w, p)
		var free_key := ActiveSlots.cd_key(Config.PLAYER.slots.find(null))
		if bar._slots[free_key].icon_id != "" or p.slots.get_slot(p, Config.PLAYER.slots.find(null)) != null:
			err = "換成鐵鏟後插火把的格子應空出來：%s" % bar._slots[free_key].icon_id
		p.held_enemy_id = -1
		bar.refresh(w, p)
		var gr: Dictionary = WeaponDefs.WEAPONS[&"shovel"].grab
		if not bar._alt_left.visible or bar._alt_left.icon_id != gr.attack.icon or bar._alt_right.icon_id != gr.special.icon:
			err = "舉著怪時左右鍵應換成「%s」/「%s」" % [gr.attack.icon, gr.special.icon]
		p.held_enemy_id = 0
	bar.queue_free()
	return err


# 技能欄 CD 遮罩：文字圖示（散射、影步…）與秒數都是格子的子節點，會畫在格子 _draw 上面；
# 遮罩獨立一層，疊放順序要是 圖示 < 遮罩 < 秒數，冷卻中才會壓暗圖示、秒數浮在最上面
static func check_skill_bar_cd_mask() -> String:
	var w := _new_world()
	var p := _player(w)
	p.equip_weapon(&"shortbow")
	var bar := SkillBar.new()
	_scene_root().add_child(bar)
	bar.refresh(w, p)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_SPECIAL | InputCmd.BTN_SPECIAL_HELD), 1)
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5)), 30)
	bar.refresh(w, p)
	var s: SkillBar.Slot = bar._slots["player.special"]
	var err := ""
	if s.cd_ratio <= 0.0 or s.cd_left <= 0.0:
		err = "短弓散射後右鍵格應在冷卻：比例 %.2f、秒數 %.2f" % [s.cd_ratio, s.cd_left]
	elif not (s.icon.get_index() < s.mask.get_index() and s.mask.get_index() < s.cd_text.get_index()):
		err = "疊放順序應為 圖示 < 遮罩 < 秒數：%d / %d / %d" % [s.icon.get_index(), s.mask.get_index(), s.cd_text.get_index()]
	bar.queue_free()
	return err


# 從 node 往上到 menu 都是 visible（-s 檢查裡 is_visible_in_tree 不可靠）
static func _shown(node: Control, menu: Control) -> bool:
	var n: Node = node
	while n != null and n != menu:
		if n is CanvasItem and not n.visible:
			return false
		n = n.get_parent()
	return n == menu and menu.visible


static func _check_main_menu(hud: Variant) -> String:
	var menu: Variant = hud.main_menu
	if menu.visible:
		return "HUD 一建立時主選單應隱藏（由 main.gd 決定要不要顯示）"
	hud.show_title(true)
	if not menu.visible or menu.page != &"home" or hud._pause.visible:
		return "show_title 後應顯示主選單首頁、暫停畫面隱藏"
	for b: Button in [menu.single_button, menu.multi_button, menu.weapon_test_button]:
		if not _shown(b, menu):
			return "主選單首頁應看得到「%s」" % b.text
	if menu.quit_button.visible == OS.has_feature("web"):
		return "「離開遊戲」桌面版要顯示、網頁版要隱藏"
	if _shown(menu.back_button, menu):
		return "首頁不應看到多人頁的「返回」"
	var counts := {"single": 0, "back": 0, "quit": 0, "title": 0}
	menu.single_pressed.connect(func() -> void: counts.single += 1)
	menu.back_pressed.connect(func() -> void: counts.back += 1)
	hud.quit_requested.connect(func() -> void: counts.quit += 1)
	hud.title_requested.connect(func() -> void: counts.title += 1)
	# 單人遊戲打開選角畫面（2026-10-27），選角畫面的內容在「選角畫面」那項檢查
	menu.single_button.pressed.emit()
	if not hud.class_select.visible or hud.class_select.mode != &"single":
		return "按「單人遊戲」應打開選角畫面（單人）"
	hud.class_select.back_button.pressed.emit()
	if hud.class_select.visible or not menu.visible or menu.page != &"home":
		return "選角畫面按「返回」應回到主選單首頁"
	menu.quit_button.pressed.emit()
	menu.multi_button.pressed.emit()
	# 桌面版先選連線方式（v0.40.0）：房號（要有 webrtc-native 擴充）/ IP；網頁版只有房號，直接進多人頁
	if NetSession.ip_supported():
		if menu.page != &"method" or not _shown(menu.room_button, menu) or not _shown(menu.ip_button, menu):
			return "桌面版按「多人遊戲」應先到選連線方式頁（房號 / IP）"
		if menu.room_button.disabled:
			return "載入 webrtc-native 後「房號連線」應可以按"
		menu.ip_button.pressed.emit()
		if hud.net_panel.method != &"ip" or hud.net_panel._address.placeholder_text != "房主 IP":
			return "選 IP 連線後連線面板應改成輸入 IP：%s / %s" % [hud.net_panel.method, hud.net_panel._address.placeholder_text]
		menu.show_page(&"method")
		menu.room_button.pressed.emit()
	if hud.net_panel.method != &"room" or not hud.net_panel._address.placeholder_text.contains("房號"):
		return "選房號連線後連線面板應改成輸入房號：%s" % hud.net_panel.method
	if menu.page != &"multi" or _shown(menu.single_button, menu) or not _shown(menu.back_button, menu):
		return "選好連線方式應切到多人頁（看得到返回、看不到首頁按鈕）"
	if hud.net_panel.get_parent() != menu.net_slot or not _shown(hud.net_panel, menu):
		return "多人頁應看得到連線面板"
	menu.back_button.pressed.emit()
	if counts.single != 1 or counts.quit != 1 or counts.back != 1:
		return "按鈕訊號次數錯誤：%s" % counts
	# 最長的狀態文字（房號房主大廳、4 人）也要塞得進畫面
	hud.net_panel.room_code = "ABCD"
	hud.net_panel.show_state(&"lobby_host", [1, 2, 3, 4], 1, "")
	if not hud.net_panel._status.text.contains("網頁版都可以"):
		return "房號大廳應說明電腦版、網頁版都能加入：%s" % hud.net_panel._status.text
	# 介面大小開到最大檔時，16:9 的畫面只剩 1920×1080 ÷ 檔位（設定頁 UI_SCALES）
	var room := _menu_room()
	# 節點不在場景樹裡，切頁後整個選單的最小尺寸快取不會更新：改成「該頁自己的尺寸 + 上方標題那幾行」
	var box: VBoxContainer = menu.get_child(0)
	var pages := {&"home": menu._home, &"method": menu._method, &"multi": menu._multi}
	var header := 0.0
	for c: Control in box.get_children():
		if not pages.values().has(c):
			header += c.get_combined_minimum_size().y + box.get_theme_constant(&"separation")
	for page: StringName in pages:
		menu.show_page(page)
		var page_size: Vector2 = pages[page].get_combined_minimum_size()
		var size := Vector2(page_size.x, page_size.y + header)
		_note("主選單%s頁 %.0f×%.0f（介面最大檔時可用 %.0f×%.0f）" % [page, size.x, size.y, room.x, room.y])
		if size.x > room.x or size.y > room.y:
			return "主選單%s頁 %.0f×%.0f，超出介面最大檔時的 %.0f×%.0f" % [page, size.x, size.y, room.x, room.y]
	hud.show_menu(true)
	var pause_need: Vector2 = hud._pause.get_child(0).get_combined_minimum_size()
	hud.show_menu(false)
	_note("暫停畫面 %.0f×%.0f" % [pause_need.x, pause_need.y])
	if pause_need.x > room.x or pause_need.y > room.y:
		return "暫停畫面 %.0f×%.0f，超出介面最大檔時的 %.0f×%.0f" % [pause_need.x, pause_need.y, room.x, room.y]
	hud.show_title(false)
	if menu.visible or hud.net_panel.get_parent() != hud._pause_net_slot:
		return "關掉主選單後連線面板應搬回暫停畫面"
	hud.net_panel.show_state(&"single", [], 1, "")
	hud.show_menu(true)
	if hud.net_panel.visible:
		return "單機暫停時不應顯示連線面板（開房 / 加入改從主選單）"
	hud.net_panel.show_state(&"playing", [1, 2], 1, "")
	hud.show_menu(true, "選單", "")
	if not hud.net_panel.visible:
		return "連線中的選單應顯示連線面板（人數與離開連線）"
	if not hud._pause.is_ancestor_of(hud._title_button) or not hud._title_button.visible:
		return "暫停畫面應有可見的「回主選單」按鈕"
	hud._title_button.pressed.emit()
	if counts.title != 1:
		return "按下「回主選單」應發出 title_requested 一次，實際 %d 次" % counts.title
	return ""


static func check_url_query_args() -> String:
	# 連線參數 2026-10-27 起開放（使用者同意：多人自動測試、之後的邀請連結）；不在清單的（--net-latency、--menu-flow）照樣不轉
	var got: PackedStringArray = LaunchArgs.url_query_args("?horde=200&perf&seconds=20&player-hp=99999&host&join=ABCD&room&net-autostart=3&net-latency=100&menu-flow&elites=")
	var want := PackedStringArray(["--horde=200", "--perf", "--seconds=20", "--player-hp=99999", "--host", "--join=ABCD", "--room", "--net-autostart=3", "--elites"])
	if got != want:
		return "轉換結果 %s，預期 %s" % [got, want]
	if not LaunchArgs.url_query_args("").is_empty() or not LaunchArgs.url_query_args("?").is_empty():
		return "沒有參數時應回傳空的"
	return ""


# 設定頁（2026-10-27）：主選單首頁與暫停畫面的「設定」打開、塞得進 1920×1080；改值發 changed、存檔後讀得回來；
# 音量套到 Master / Music / SFX 匯流排；陰影、光源開關套到太陽與點光源（之後新建的精英怪也照設定）；--shadows=0 / --lights=0 解析
static func check_settings() -> String:
	var w := _new_world(5)
	var cam := _test_camera()
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w, cam)
	_scene_root().add_child(hud)
	var view := WorldView.new()
	view._setup_environment()   # 太陽（不在場景樹裡不會跑 _ready）
	var snd: Node = _sound_script().new()   # 不進場景樹（_ready 要 GameEvents，check.gd 沒有 autoload）；匯流排在 _init 就接好
	var err := _check_settings(hud, view, snd, w)
	for n: Node in [snd._sfx, snd._music, snd]:   # 播放器在 _ready 才掛上去，沒進場景樹要自己釋放
		n.free()
	view.free()
	for n: Node in [hud, cam]:
		n.queue_free()
	return err


static func _check_settings(hud: Variant, view: WorldView, snd: Variant, w: World) -> String:
	var panel: SettingsPanel = hud.settings_panel
	panel.save_path = ""
	if panel.visible:
		return "設定頁一開始應隱藏"
	hud.show_title(true)
	hud.main_menu.settings_button.pressed.emit()
	if not panel.visible or hud.main_menu.visible:
		return "主選單「設定」應打開設定頁、收起主選單（畫面上只有一層壓黑）"
	for overlay: ColorRect in [hud._pause, hud.main_menu, panel]:
		if overlay.color != UiKit.MENU_DIM:
			return "暫停、主選單、設定頁的壓黑要一樣（UiKit.MENU_DIM）：%s 是 %s" % [overlay.name, overlay.color]
	var need := panel.get_child(0).get_combined_minimum_size() as Vector2
	if need.x > _menu_room().x or need.y > _menu_room().y:
		return "設定頁需要 %s，超出介面最大檔時的 %s" % [need, _menu_room()]
	# 介面大小：滑桿是檔位索引，拉到第 0 格 = UI_SCALES[0]；設定檔裡不在檔位上的值取最接近的
	panel.ui_scale_slider.value_changed.emit(0.0)
	if panel.values.ui_scale != SettingsPanel.UI_SCALES[0] or SettingsPanel.scale_index(1.04) != SettingsPanel.UI_SCALES.find(1.0):
		return "介面大小檔位不對：%s / %d" % [panel.values.ui_scale, SettingsPanel.scale_index(1.04)]
	panel.set_value("ui_scale", 1.0)
	panel.back_button.pressed.emit()
	if panel.visible or not hud.main_menu.visible:
		return "設定頁按返回應回到主選單"
	hud.show_title(false)
	hud.show_menu(true)
	if not _shown(hud._settings_button, hud._pause):
		return "暫停畫面應看得到「設定」"
	hud._settings_button.pressed.emit()
	if not panel.visible or hud._pause.visible:
		return "暫停畫面「設定」應打開設定頁、收起暫停畫面"
	hud.show_menu(false)
	if panel.visible or hud._pause.visible:
		return "選單關掉時設定頁也要關、暫停畫面不能被叫回來"
	# 改值：發 changed、存檔、讀得回來
	var path := "user://check_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	panel.save_path = path
	var got: Array = []
	panel.changed.connect(func(k: String, v: Variant) -> void: got.append([k, v]))
	panel.sliders["music"].value_changed.emit(0.3)   # check.gd 的節點不在場景樹裡，Range 不會自己發訊號
	panel.toggles["lights"].button_pressed = false
	panel.set_value("shadows", false, false)   # 啟動參數蓋掉：不存檔
	if got != [["music", 0.3], ["lights", false], ["shadows", false]]:
		return "changed 訊號不對：%s" % [got]
	if panel.video_text() != "陰影關・光源關":
		return "設定摘要不對：%s" % panel.video_text()
	var again := SettingsPanel.new()
	again.save_path = path
	again.load_file()
	var saved := again.values.duplicate()
	again.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not is_equal_approx(saved.music, 0.3) or saved.lights != false or saved.shadows != true:
		return "存檔讀回來不對（shadows 是啟動參數蓋的，不該存）：%s" % saved
	# 音量：音樂、音效走自己的匯流排
	var sound_script := _sound_script()
	if snd._music.bus != &"Music" or snd._sfx.bus != &"SFX":
		return "音樂、音效應走 Music / SFX 匯流排：%s / %s" % [snd._music.bus, snd._sfx.bus]
	# 網頁版交給瀏覽器播（Sample）的聲音不照 Godot 的匯流排音量，音樂要由 Godot 混音
	if snd._music.playback_type != AudioServer.PLAYBACK_TYPE_STREAM:
		return "音樂應由 Godot 混音（PLAYBACK_TYPE_STREAM），網頁版音量滑桿才有效：%s" % snd._music.playback_type
	sound_script.set_volume(&"SFX", 0.5)
	var sfx_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"SFX"))
	sound_script.set_volume(&"SFX", 0.0)
	var off_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"SFX"))
	sound_script.set_volume(&"SFX", 1.0)
	if not is_equal_approx(sfx_db, linear_to_db(0.5)) or off_db > -79.0:
		return "音量 50%% 應 %.1f dB、0%% 應 −80 dB：%.1f / %.1f" % [linear_to_db(0.5), sfx_db, off_db]
	# 拉音效滑桿的試聽：第一下播，拖動中緊接著的不播
	var first: bool = snd.preview_sfx()
	var burst: bool = snd.preview_sfx()
	if not first or burst:
		return "音效試聽應第一下播、%.2f 秒內不再播：%s / %s" % [sound_script.PREVIEW_INTERVAL, first, burst]
	# 陰影、光源
	view.set_shadows(false)
	if view._sun.shadow_enabled:
		return "關陰影後太陽不該有影子"
	view.set_shadows(true)
	var rare := _spawn(w, &"grunt", Vector2(3, 8))
	rare.set_rarity(MonsterRarityDefs.RARE, [&"swift"], "測試")
	var node := view._create_view(rare)
	var lights := node.find_children("*", "OmniLight3D", true, false)
	view.set_lights(false)
	var node2 := view._create_view(rare)
	var lights2 := node2.find_children("*", "OmniLight3D", true, false)
	var err := ""
	if lights.size() != 1 or lights2.size() != 1:
		err = "稀有怪應有 1 盞光：%d / %d" % [lights.size(), lights2.size()]
	elif lights[0].visible or lights2[0].visible:
		err = "關光源後已有的和之後新建的精英怪都不該亮"
	else:
		view.set_lights(true)
		if not lights[0].visible or not lights2[0].visible:
			err = "開光源後精英怪的光應亮回來"
	node.free()
	node2.free()
	if err != "":
		return err
	var a := LaunchArgs.parse(PackedStringArray(["--shadows=0", "--lights=1"]))
	if a.video != {"shadows": false, "lights": true}:
		return "--shadows=0 --lights=1 解析成 %s" % a.video
	if LaunchArgs.url_query_args("?shadows=0&lights=0") != PackedStringArray(["--shadows=0", "--lights=0"]):
		return "網頁版應開放 ?shadows= / ?lights="
	return ""


# 按鈕標準化（2026-10-27）：ui/ 裡的按鈕都經過 UiKit.button（三種尺寸），不自己 Button.new()；三種尺寸各建一顆確認大小與字級
static func check_buttons() -> String:
	var dir := DirAccess.open("res://ui")
	for file in dir.get_files():
		if not file.ends_with(".gd") or file == "ui_kit.gd":
			continue
		var lines := FileAccess.get_file_as_string("res://ui/" + file).split("\n")
		for i in lines.size():
			var code := lines[i].get_slice("#", 0)
			if RegEx.create_from_string("(?<![A-Za-z])Button\\.new\\(").search(code):
				return "ui/%s:%d 自己建按鈕，改用 UiKit.button：%s" % [file, i + 1, lines[i].strip_edges()]
	for kind: Dictionary in [UiKit.BUTTON_L, UiKit.BUTTON_M, UiKit.BUTTON_S]:
		var b := UiKit.button("測試", kind)
		var ok: bool = b.custom_minimum_size == kind.size and b.get_theme_font_size(&"font_size") == kind.font and b.has_theme_stylebox_override(&"normal")
		b.free()
		if not ok:
			return "UiKit.button 的尺寸 / 字級 / 底框不對：%s" % kind
	return ""


# 選單在介面大小最大檔時能用的大小（16:9）
# 剛建好或換過文字的介面，字級（主題）與容器的最小尺寸要等畫面更新才算準（立刻量偏小約 15%：
# 四人大廳立刻量 1850 寬、等兩幀 2184）；等兩幀再量
static func _settled_min_size(c: Control) -> Vector2:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	await tree.process_frame
	return c.get_combined_minimum_size()


# HUD 用的測試相機：放在遊戲的視角（上方斜看），不要在原點——檢查等過畫面更新後相機才生效，
# 傷害數字等在原點附近的東西投影到相機平面會出錯（2026-10-27 加了 await 的檢查後發現）
static func _test_camera() -> Camera3D:
	var cam := Camera3D.new()
	_scene_root().add_child(cam)
	cam.look_at_from_position(Vector3(0, 20, 14), Vector3.ZERO)
	return cam


static func _menu_room() -> Vector2:
	var base := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	return base / (SettingsPanel.UI_SCALES.max() * SettingsPanel.BASE_UI_SCALE)


static func check_run_log() -> String:
	var w := _new_world(5)
	var cam := _test_camera()
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w, cam)
	_scene_root().add_child(hud)
	var p := _player(w)
	p.pos = Vector2.ZERO
	p.facing = 0.0   # 面向 +Z：前方 8 單位看得到、背後 8 單位看不到（身邊一圈只有 4）
	var front := _spawn(w, &"grunt", Vector2(0, 8))
	var back := _spawn(w, &"archer", Vector2(0, -8))
	w.events.clear()
	Combat.apply_damage(w, front, p, {"damage": 10.0})
	p.invuln_timer = 0.0
	Combat.apply_damage(w, back, p, {"damage": 7.0})
	p.invuln_timer = 0.0
	Combat.apply_damage(w, p, front, {"damage": 9999.0})
	p.hp = 1.0
	Combat.apply_damage(w, back, p, {"damage": 7.0})   # 致命的一下：單機直接死亡
	_feed_hud(hud, w.events)
	var rl: RunLog = hud.run_log
	var seen: int = rl.by_source.get(&"grunt", {}).get("damage", -1)
	var unseen: Dictionary = rl.by_source.get(&"archer", {})
	if rl.hits_taken != 3 or seen <= 0 or unseen.get("hits", 0) != 2 or unseen.get("unseen", 0) != 2:
		return "受傷紀錄錯誤：%d 次、骷髏戰士 %d、骷髏弓手 %s" % [rl.hits_taken, seen, unseen]
	if rl.unseen_hits != 2 or rl.damage_taken != seen + unseen.damage or rl.unseen_damage != unseen.damage:
		return "看不見的攻擊應 2 次 / %d 傷害，實際 %d 次 / %d（總傷害 %d）" % [unseen.damage, rl.unseen_hits, rl.unseen_damage, rl.damage_taken]
	if rl.kills != {&"grunt": 1}:
		return "擊殺應只有骷髏戰士 1 隻：%s" % rl.kills
	if rl.downs != [{"kind": &"archer", "unseen": true}]:
		return "應記一次被看不見的骷髏弓手打倒：%s" % [rl.downs]
	hud._on_event("game:defeat", {"stats": w.stats.duplicate()})
	var text: String = hud._game_over_log.text
	for want in ["你的擊殺 1：骷髏戰士 1", "被打中 3 次", "被看不見的攻擊打中 2 次", "骷髏弓手：", "（看不見 2 次）", "倒下 1 次：被 骷髏弓手（看不見） 打倒"]:
		if not text.contains(want):
			return "結算文字缺「%s」：\n%s" % [want, text]
	# 複製遊玩紀錄：結算畫面的按鈕，按下去拿到回報用的精簡文字；單機沒有連線那行
	rl.video = "陰影開・光源開"
	rl.frame_context = func() -> String: return "光 3 盞、怪 20 隻"
	rl.add_frame(0.016, 1.0)
	rl.video = "陰影關・光源開"
	rl.add_frame(0.12, 65.0)
	if hud._copy_button.get_parent() != hud._game_over_log.get_parent():
		return "「複製遊玩紀錄」按鈕應在結算畫面上"
	hud._copy_button.pressed.emit()
	var report: String = hud.last_report
	for want in ["Cubeborn v%s" % GameVersion.VERSION, "結果：你倒下了", "武器：", "你的擊殺 1", "被打中 3 次", "最慢一幀 120 ms（1:05，光 3 盞、怪 20 隻）", "卡頓（超過 50 ms）1 次",
			"顯示卡：", "· 陰影關・光源開", "  陰影開・光源開：平均 63 FPS · 卡頓 0 次", "  陰影關・光源開：平均 8 FPS · 卡頓 1 次"]:
		if not report.contains(want):
			return "回報文字缺「%s」：\n%s" % [want, report]
	if report.contains("連線："):
		return "單機的回報不該有連線那行：\n%s" % report
	var nt := RunLog.net_text({"role": "客戶端", "players": 3, "rtt_ms": [100, 60, 240, 80], "snapshot_gap_max_ms": 380, "input_gap_max_ms": {}})
	if nt != "連線：客戶端 · 3 人 · 回應 平均 120 / 最低 60 / 90% 240 / 最高 240 ms（4 次） · 快照最長間隔 380 ms":
		return "連線那行不對：%s" % nt
	_note("回報文字：\n" + report)
	# 最多行的情況（每種攻擊者都打過、倒下超過顯示上限）也要塞得進畫面
	for kind: StringName in RunLog.NAMES:
		rl.by_source[kind] = {"damage": 99999, "hits": 9999, "unseen": 9999}
		rl.kills[kind] = 9999
	for i in RunLog.MAX_DOWNS_SHOWN + 3:
		rl.downs.append({"kind": &"projectile", "unseen": true})
	hud._on_event("game:defeat", {"stats": w.stats.duplicate()})
	var box: Control = hud._game_over_log.get_parent()
	var need: Vector2 = box.get_combined_minimum_size()
	var screen := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	if need.y <= 0.0 or need.x > screen.x or need.y > screen.y:
		return "結算畫面需要 %s，超出 %s" % [need, screen]
	_note("結算畫面最多行時需要 %.0f × %.0f（畫面 %.0f × %.0f）" % [need.x, need.y, screen.x, screen.y])
	hud._on_event("game:restart", {})
	if rl.hits_taken != 0 or not rl.kills.is_empty() or not rl.downs.is_empty() or rl.frames != 0 or rl.result != "" or not rl.by_video.is_empty():
		return "game:restart 後遊玩紀錄應清空"
	hud.queue_free()
	cam.queue_free()
	return ""


static func check_vision_rules() -> String:
	var w := _new_world()
	var p := _player(w)
	p.pos = Vector2.ZERO
	p.facing = 0.0   # 面向 +Z
	var at := func(deg: float, dist: float) -> Vector2: return Vector2(sin(deg_to_rad(deg)), cos(deg_to_rad(deg))) * dist
	var v := Config.VISION
	var half_deg := rad_to_deg(v.angle / 2.0)
	var cases := [
		[at.call(0.0, 10.0), true, "正前方 10"], [at.call(half_deg - 5.0, 10.0), true, "邊界內 5°"], [at.call(half_deg + 5.0, 10.0), false, "邊界外 5°"],
		[at.call(0.0, v.range - 0.5), true, "正前方視野內 0.5"], [at.call(0.0, v.range + 1.0), false, "正前方視野外 1"],
		[at.call(180.0, v.near_radius - 0.5), true, "正後方身邊一圈內"], [at.call(180.0, v.near_radius + 1.0), false, "正後方身邊一圈外"],
	]
	for c in cases:
		if Vision.point_visible(w, p, c[0]) != c[1]:
			return "%s 應%s" % [c[2], "看得到" if c[1] else "看不到"]
	# 牆（x 8~14、z 7.5~8.5）：從 (11, 5) 往 +Z 看
	p.pos = Vector2(11, 5)
	if Vision.point_visible(w, p, Vector2(11, 12)):
		return "牆後 (11, 12) 應看不到"
	if Vision.point_visible(w, p, Vector2(11, 8.8)):
		return "身邊 4 單位內、但在牆後的 (11, 8.8) 也應看不到"
	if not Vision.point_visible(w, p, Vector2(11, 7.2)):
		return "牆前的 (11, 7.2) 應看得到"
	# 高台不擋：從 (2, 12) 往 +X 看過 0.5、1.0 石台
	p.pos = Vector2(2, 12)
	p.facing = PI / 2.0
	if not Vision.point_visible(w, p, Vector2(15, 12)):
		return "高台不應擋視線"
	# 投射物：自己的在背後也看得到、怪物的看不到
	p.pos = Vector2.ZERO
	p.facing = 0.0
	var archer := _spawn(w, &"archer", Vector2(0, -12))
	var mine := Projectile.new(w, {"owner": p, "pos": Vector2(0, -8), "direction": Vector2(0, -1), "speed": 0.0, "range": 5.0})
	var theirs := Projectile.new(w, {"owner": archer, "pos": Vector2(0, -8), "direction": Vector2(0, 1), "speed": 0.0, "range": 5.0})
	if not Vision.entity_visible(w, p, mine) or Vision.entity_visible(w, p, theirs) or Vision.entity_visible(w, p, archer):
		return "背後：自己的投射物 %s、弓手的箭 %s、弓手 %s（應為 看得到 / 看不到 / 看不到）" % [
			Vision.entity_visible(w, p, mine), Vision.entity_visible(w, p, theirs), Vision.entity_visible(w, p, archer)]
	# 視野邊界上、中心在外面一點：寶箱看中心（露一角不算），怪物看身體邊緣
	var edge_at: Vector2 = at.call(half_deg + 1.0, 10.0)
	var chest := Chest.new(w, &"small", edge_at)
	var grunt := _spawn(w, &"grunt", edge_at)
	if rad_to_deg(asin(chest.radius / 10.0)) <= 1.0 or rad_to_deg(asin(grunt.radius / 10.0)) <= 1.0:
		return "測試前提：寶箱與骷髏的邊緣要在視野內（半徑 %.2f / %.2f）" % [chest.radius, grunt.radius]
	if Vision.entity_visible(w, p, chest) or not Vision.entity_visible(w, p, grunt):
		return "中心在視野外 1°：寶箱 %s、骷髏 %s（應為 看不到 / 看得到）" % [Vision.entity_visible(w, p, chest), Vision.entity_visible(w, p, grunt)]
	return ""


# 去掉一行 GDScript 的註解（字串外面的 # 之後）
static func _strip_comment(line: String) -> String:
	var in_string := false
	for i in line.length():
		var ch := line[i]
		if ch == "\"" and (i == 0 or line[i - 1] != "\\"):
			in_string = not in_string
		elif ch == "#" and not in_string:
			return line.substr(0, i)
	return line


static func check_warm_up() -> String:
	var view := WorldView.new()
	_scene_root().add_child(view)
	var center := Vector3(20, 0, -15)
	view.warm_up(center)
	var want: Array[String] = ["player", "chest:small", "chest:big", "coin", "projectile:arrow", "projectile:orb",
		"grunt:%s" % MonsterRarityDefs.MAGIC, "grunt:%s" % MonsterRarityDefs.RARE]
	for kind: StringName in EnemyDefs.ENEMIES:
		want.append(String(kind))
	var err := ""
	for k in want:
		if not view.warm_keys.has(k) or not view.warm_keys.has("fade:" + k):
			err = "預熱缺少 %s 或它淡入淡出中的版本（預熱了 %s）" % [k, view.warm_keys]
			break
	# 武器每種稀有度都要（白色沒有發光、材質組合不同；v0.37.1 網頁版實測：只預熱綠色時第一把白色武器仍卡 70.8 ms）
	for rarity: StringName in ItemDefs.RARITIES:
		if err == "" and not view.warm_keys.has("weapon:%s" % rarity):
			err = "預熱缺少 %s 的武器：%s" % [rarity, view.warm_keys]
	if err == "" and not view.warm_keys.any(func(k: String) -> bool: return k.begins_with("item:")):
		err = "預熱應包含地上的道具：%s" % [view.warm_keys]
	if err == "":
		for node in view._warm_nodes:
			if node.position.distance_to(center) > 4.0:
				err = "預熱的模型要在鏡頭附近（離中心 %.1f）" % node.position.distance_to(center)
				break
	# 前一半的幀預熱模型上的點光源全關、後一半全開（網頁版有光 / 沒光是兩個著色器版本）；預熱期間視野遮罩也畫
	var lights: Array[Light3D] = []
	for node in view._warm_nodes:
		lights.append_array(node.find_children("*", "Light3D", true, false))
	if err == "" and (lights.is_empty() or lights.any(func(l: Light3D) -> bool: return l.visible)):
		err = "預熱一開始模型上的點光源應全部關掉（找到 %d 盞）" % lights.size()
	if err == "":
		var w := _new_world()
		for i in WorldView.WARM_FRAMES:
			if not view.is_warming_up():
				err = "預熱應維持 %d 幀，第 %d 幀就結束了" % [WorldView.WARM_FRAMES, i]
				break
			view.sync(w, 1.0, DT)
			if i == WorldView.WARM_FRAMES / 2 - 1 and lights.any(func(l: Light3D) -> bool: return not l.visible):
				err = "預熱後一半的幀模型上的點光源應全部打開"
				break
			if i < WorldView.WARM_FRAMES - 1 and not view._vision_overlay.visible:
				err = "預熱期間視野遮罩應該畫出來（第 %d 幀）" % i
				break
		if err == "" and (view.is_warming_up() or not view._warm_nodes.is_empty()):
			err = "預熱 %d 幀後應移除" % WorldView.WARM_FRAMES
	# 預熱過後，遊戲中的怪、寶箱、玩家淡入淡出的每一階都不必新建材質
	if err == "":
		var fw := _new_world()
		var n0 := Fade.cache_size()
		for e: Entity in [_spawn(fw, &"grunt", Vector2(0, 5)), _spawn(fw, &"archer", Vector2(2, 5)), _spawn(fw, &"boss", Vector2(4, 5)), Chest.new(fw, &"big", Vector2(-2, 5)), _player(fw)]:
			var node := view._create_view(e)
			for level in range(1, Fade.LEVELS):
				Fade.apply(node, float(level) / Fade.LEVELS)
			Fade.apply(node, 1.0)
		if Fade.cache_size() != n0:
			err = "預熱後淡入淡出還新建了 %d 個半透明材質" % (Fade.cache_size() - n0)
	var text: String = load("res://ui/hud.gd").warm_text()
	var sample: String = ItemDefs.ITEMS.values()[0].name + MonsterRarityDefs.RARE_NAME_B[0]
	for ch in sample:
		if err == "" and ch.unicode_at(0) > 127 and not text.contains(ch):
			err = "預熱文字缺「%s」" % ch
	# 介面程式碼裡寫死的字串（橫幅、場上文字…）也要涵蓋（v0.37.2：第一把武器的名字「[F] 撿起」等沒預熱，網頁版仍卡 78 ms）
	var re := RegEx.create_from_string("\"([^\"\\\\]*)\"")
	var missing := {}
	for path in ["res://ui/hud.gd", "res://ui/world_labels.gd", "res://ui/floaters.gd", "res://ui/net_panel.gd", "res://ui/main_menu.gd", "res://ui/player_tags.gd", "res://ui/inventory_panel.gd", "res://ui/run_log.gd", "res://ui/settings_panel.gd"]:
		for line in _read_text(path).split("\n"):
			for m in re.search_all(_strip_comment(line)):
				for ch in m.get_string(1):
					if ch.unicode_at(0) > 127 and not text.contains(ch):
						missing[ch] = true
	if err == "" and not missing.is_empty():
		err = "介面字串的字沒有預熱，加到 HUD.UI_CHARS：%s" % "".join(missing.keys())
	view.queue_free()
	return err


static func check_vision_view() -> String:
	var w := _new_world()
	var p := _player(w)
	p.facing = 0.0
	var front := _spawn(w, &"grunt", Vector2(0, 8))
	var back := _spawn(w, &"grunt", Vector2(0, -8))
	var view := WorldView.new()
	view.sync(w, 1.0, 0.016)
	var front_node: Node3D = view._nodes[front.id]
	var back_node: Node3D = view._nodes[back.id]
	var err := ""
	if not front_node.visible or back_node.visible:
		err = "前方骷髏顯示 %s、背後骷髏顯示 %s（應為 true / false）" % [front_node.visible, back_node.visible]
	if err == "":
		var before := view.effects._transients.size()
		view.on_event("fx:slash", {"pos": Vector2(0, -8), "height": 0.0, "facing": 0.0, "range": 1.5, "arc": 1.7, "color": Color.WHITE, "swing_dir": 1})
		var after_back := view.effects._transients.size()
		view.on_event("fx:slash", {"pos": Vector2(0, 8), "height": 0.0, "facing": 0.0, "range": 1.5, "arc": 1.7, "color": Color.WHITE, "swing_dir": 1})
		if after_back != before or view.effects._transients.size() != before + 1:
			err = "特效：背後的揮砍多了 %d 個、前方的多了 %d 個（應為 0 / 1）" % [after_back - before, view.effects._transients.size() - after_back]
	if err == "" and (view._vision_overlay.material_override as Material).render_priority != Material.RENDER_PRIORITY_MIN:
		err = "視野變暗的遮罩要最先畫（半透明的模型不在深度貼圖裡，後畫會被切成上下兩半）"
	# 淡入淡出：轉身後原本前方的骷髏先半透明、fade_out 秒後才隱藏；背後的從透明淡入，fade_in 秒後還原成不透明
	var v := Config.VISION
	if err == "":
		p.facing = PI
		w.tick += 1   # 視野依 tick 重算
		view.sync(w, 1.0, 0.1)
		var fa := _fade_alpha(front_node)
		var ba := _fade_alpha(back_node)
		var want_out := Fade.level_of(1.0 - 0.1 / v.fade_out) / float(Fade.LEVELS)   # 透明度分 LEVELS 階
		var want_in := Fade.level_of(0.1 / v.fade_in) / float(Fade.LEVELS)
		if not front_node.visible or not is_equal_approx(fa, want_out):
			err = "轉身 0.1 秒：原本前方的骷髏應還看得到、透明度 %.2f（實際 %s / %.2f）" % [want_out, front_node.visible, fa]
		elif not back_node.visible or not is_equal_approx(ba, want_in):
			err = "轉身 0.1 秒：背後的骷髏應開始淡入、透明度 %.2f（實際 %s / %.2f）" % [want_in, back_node.visible, ba]
		else:
			# 兩次繪製：先只寫深度、再畫半透明的原材質（零件不互相透出來）
			for mi in PartKit.mesh_instances(back_node):
				var dm := mi.material_override as ShaderMaterial
				if mi.name != &"Hitbox" and (dm == null or not dm.next_pass is BaseMaterial3D or (dm.next_pass as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED):
					err = "淡入淡出中每個網格應是「只寫深度 → 半透明的原材質」兩次繪製（%s）" % mi.name
					break
	if err == "":
		var t := 0.1
		while t < maxf(v.fade_in, v.fade_out) + 0.05:
			view.sync(w, 1.0, 0.05)
			t += 0.05
		if front_node.visible:
			err = "fade_out 秒後原本前方的骷髏應隱藏"
		elif not back_node.visible or Fade.is_fading(back_node) or _fade_alpha(back_node) != 1.0:
			err = "fade_in 秒後背後的骷髏應還原成不透明（材質透明度 %.2f）" % _fade_alpha(back_node)
		elif PartKit.mesh_instances(back_node).any(func(mi: MeshInstance3D) -> bool: return mi.name != &"Hitbox" and (mi.material_override as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
			err = "淡入完成後材質應還原成不透明模式"
	# 半透明的材質共用快取：同樣的怪再轉身幾次不會再新建材質（網頁版每次轉身新建 / 切換材質會卡）
	if err == "":
		var n0 := Fade.cache_size()
		for i in 4:
			p.facing = PI - p.facing
			w.tick += 1
			view.sync(w, 1.0, 0.1)
			for j in 4:
				view.sync(w, 1.0, 0.05)
		if Fade.cache_size() != n0:
			err = "再轉身 4 次，半透明材質的快取從 %d 個變成 %d 個（應不變）" % [n0, Fade.cache_size()]
	# 一個材質用在好幾個網格上（寶箱的木頭、角色的盔甲）：淡到一半再完全顯示後，每個網格的材質與設定都要回到原本的
	if err == "":
		for e: Entity in [Chest.new(w, &"small", Vector2(0, 5)), _spawn(w, &"boss", Vector2(3, 5)), p]:
			var node := view._create_view(e)
			var before := _material_state(node)
			Fade.apply(node, 0.5)
			Fade.apply(node, 1.0)
			if _material_state(node) != before:
				err = "%s 淡入淡出後材質沒有還原：%s → %s" % [e.kind, before, _material_state(node)]
				break
	if err == "":
		p.is_dead = true
		view.sync(w, 1.0, 0.016)
		if not front_node.visible or _fade_alpha(front_node) != 1.0:
			err = "本機角色陣亡後應立刻全部看得到（不淡入）"
	view.free()
	return err


# 每個網格的材質與透明相關設定（比對淡入淡出前後）
static func _material_state(node: Node3D) -> Array:
	var out := []
	for mi in PartKit.mesh_instances(node):
		var m := mi.material_override as BaseMaterial3D
		out.append([mi.name, m.get_instance_id() if m else 0, m.transparency if m else -1, m.albedo_color.a if m else -1.0, m.render_priority if m else 0])
	return out


# 模型第一個網格材質的 alpha（淡入淡出的程度；SkinnedRig：Skeleton 底下的網格）
static func _fade_alpha(node: Node3D) -> float:
	for mi in PartKit.mesh_instances(node):
		var m := mi.material_override
		if m is ShaderMaterial:
			m = m.next_pass   # 淡入淡出中：只寫深度的那一次後面接原本的材質
		if mi.name != &"Hitbox" and m is BaseMaterial3D:
			return (m as BaseMaterial3D).albedo_color.a
	return -1.0


# 頭頂血條（v0.43.0）：滿血不畫、受傷畫；自己與隊友綠、怪物紅；背後視野外、Boss、倒地、WorldView 隱藏的不畫；
# 長度比例 = hp / max_hp；怪物血條在詞條文字下方、頭頂上方，玩家的在名牌文字下方
static func check_health_bars() -> String:
	var w := _new_world()
	var p := _player(w)
	p.pos = Vector2.ZERO
	p.facing = 0.0   # 面向 +Z
	var mate := Player.new(w, 2)
	mate.pos = Vector2(0, 3)
	w.add_entity(mate)
	var grunt := _spawn(w, &"grunt", Vector2(0, 8))
	var rare := _spawn(w, &"grunt", Vector2(3, 8))
	rare.set_rarity(MonsterRarityDefs.RARE, [&"swift"], "測試")
	rare.apply_rarity_stats()
	rare.hp = rare.max_hp
	var back := _spawn(w, &"grunt", Vector2(0, -8))
	var boss := _spawn(w, &"boss", Vector2(-4, 10))
	var cam := Camera3D.new()   # 不在場景樹裡不能投影，只是讓 bars() 有相機；投影用 _FlatBars 的固定公式
	var hb := _FlatBars.new()
	hb.world = w
	hb.camera = cam
	var err := ""
	if not hb.bars().is_empty():
		err = "全部滿血時不應畫血條，畫了 %d 條" % hb.bars().size()
	var want := {p: [0.5, hb.PLAYER_FILL], mate: [0.3, hb.PLAYER_FILL], grunt: [0.25, hb.ENEMY_FILL], rare: [0.6, hb.ENEMY_FILL]}
	for e: Entity in want:
		e.hp = e.max_hp * want[e][0]
	back.hp = back.max_hp * 0.5
	boss.hp = boss.max_hp * 0.5
	var got := {}
	if err == "":
		for b: Dictionary in hb.bars():
			got[b.entity] = b
		for e: Entity in got:
			if not want.has(e):
				err = "不該畫血條的 %s（%s）畫了" % [e.kind, "Boss" if e == boss else "背後視野外" if e == back else "?"]
	if err == "":
		for e: Entity in want:
			if not got.has(e):
				err = "受傷的 %s 沒有血條" % e.kind
				break
			var b: Dictionary = got[e]
			var size: Vector2 = hb.PLAYER_SIZE if e is Player else hb.ENEMY_SIZE
			if absf(b.ratio - want[e][0]) > EPS or b.color != want[e][1] or not (b.rect as Rect2).size.is_equal_approx(size):
				err = "%s 血條：比例 %.3f、顏色 %s、尺寸 %s（應為 %.3f、%s、%s）" % [e.kind, b.ratio, b.color, b.rect.size, want[e][0], want[e][1], size]
				break
	if err == "":
		# 不和文字重疊：血條上緣在詞條 / 名牌的基線加字的下緣（descent）之下；怪物的下緣在頭頂之上
		var font: Font = hb.get_theme_default_font()
		var label_y: float = hb._screen(Vector3(rare.pos.x, rare.height + rare.body_height + WorldLabels.ENEMY_OFFSET, rare.pos.y)).y
		var head_y: float = hb._screen(Vector3(rare.pos.x, rare.height + rare.body_height, rare.pos.y)).y
		var r: Rect2 = got[rare].rect
		var tag_y: float = hb._screen(Vector3(mate.pos.x, mate.height + PlayerTags.HEAD_OFFSET, mate.pos.y)).y
		var rp: Rect2 = got[mate].rect
		if r.position.y < label_y + font.get_descent(14) or r.end.y > head_y:
			err = "稀有怪血條 y %.1f~%.1f，應在詞條下緣 %.1f 與頭頂 %.1f 之間" % [r.position.y, r.end.y, label_y + font.get_descent(14), head_y]
		elif rp.position.y < tag_y + font.get_descent(18):
			err = "隊友血條上緣 %.1f 疊到名牌（下緣 %.1f）" % [rp.position.y, tag_y + font.get_descent(18)]
	if err == "":
		mate.is_downed = true
		hb.hidden_ids = {grunt.id: true}
		for b: Dictionary in hb.bars():
			if b.entity == mate or b.entity == grunt:
				err = "倒地的隊友（改顯示倒數）、WorldView 隱藏的骷髏不應畫血條：%s" % b.entity.kind
	hb.free()
	cam.free()
	return err


# 遊戲的正交等距相機：畫面上 1 世界單位 ≈ 1080 / (view_half_height × 2) px，高度乘 cos(仰角)（相機往下看）
class _FlatBars extends HealthBars:
	func _screen(at: Vector3) -> Variant:
		var px: float = 1080.0 / (Config.CAMERA.view_half_height * 2.0)
		return Vector2(960.0 + (at.x - at.z) * px * 0.7071, 540.0 - at.y * px * cos(Config.CAMERA.elevation) + (at.x + at.z) * px * 0.7071 * sin(Config.CAMERA.elevation))


static func check_xray() -> String:
	var w := _new_world(3, false, &"graveyard_a")
	var p := _player(w)
	# 王族墓裡面、南牆（地圖 y 61.5~63）北邊：玩家在 y 57 面向南（+Z），怪在牆邊 y 60.6（往相機 (+1, +1) 走 1.3 就碰到牆）
	p.pos = MapDefs.to_world(w.map, Vector2(48, 57))
	p.facing = 0.0
	var e := _spawn(w, &"grunt", MapDefs.to_world(w.map, Vector2(48, 60.6)))
	var view := WorldView.new()
	var has_overlay := func(node: Node3D) -> bool:
		for mi in PartKit.mesh_instances(node):
			if mi.material_overlay != null:
				return true
		return false
	view.sync(w, 1.0, 0.016)
	var err := ""
	var pn: Node3D = view._nodes[p.id]
	var en: Node3D = view._nodes[e.id]
	if not en.visible:
		err = "牆邊的怪應在視野內"
	elif not view._xray_needed(w, e) or not has_overlay.call(en):
		err = "牆邊的怪和相機之間有牆，應有剪影：判斷 %s、疊加材質 %s" % [view._xray_needed(w, e), has_overlay.call(en)]
	elif not has_overlay.call(pn):
		err = "玩家應一直有剪影"
	if err == "":
		for mi in PartKit.mesh_instances(pn):
			var m := mi.material_override as BaseMaterial3D
			if not WorldView.XRAY_SKIP.has(mi.name) and m != null and m.stencil_mode != BaseMaterial3D.STENCIL_MODE_CUSTOM:
				err = "玩家的材質 %s 沒有寫模板值" % mi.name
				break
	if err == "":
		# 走到墓中央的空地：之後的 LOS_INTERVAL 個 tick 內重新判斷，剪影拿掉
		e.pos = MapDefs.to_world(w.map, Vector2(46, 55))
		e.prev_pos = e.pos
		for i in WorldView.LOS_INTERVAL:
			w.tick += 1
			view.sync(w, 1.0, 0.016)
		if view._xray_needed(w, e) or has_overlay.call(en):
			err = "空地上的怪不應有剪影：判斷 %s、疊加材質 %s" % [view._xray_needed(w, e), has_overlay.call(en)]
	view.free()
	return err


static func check_hints() -> String:
	if InputCollector.ACTIONS.swap_weapon != KEY_X:
		return "換武器鍵應為 X（使用者 v0.31.0 指定）"
	var w := _new_world(7, false, &"graveyard_a")
	w.reset(7, [1, 2])
	w.spawner.finished = true
	var p: Player = w.players[1]
	var p2: Player = w.players[2]
	var h := Hints.new()
	h.save_path = ""
	var shown: Array[StringName] = []
	# 每 0.1 秒模擬一次畫面更新，記錄依序跳出的提示
	var tick := func(seconds: float, bag_open: bool = false) -> void:
		for i in int(round(seconds / 0.1)):
			h.update(0.1, w, p, bag_open)
			if h.current != &"" and (shown.is_empty() or shown[-1] != h.current):
				shown.append(h.current)
	tick.call(20.0)
	if Array(shown) != [&"controls", &"dig_goal"]:
		h.free()
		return "開場應依序跳操作、挖墳：%s" % [shown]
	# 撿到第 2 把同種同色武器：背包提示與合成提示
	var mk := func(uid: String) -> Dictionary:
		return {"uid": StringName(uid), "base": &"swordShield", "rarity": &"white", "affixes": [] as Array[StringName]}
	p.weapon_slots[0] = mk.call("w1")
	p.add_weapon(mk.call("w2"))
	tick.call(20.0)
	tick.call(10.0, true)
	if Array(shown.slice(2)) != [&"bag_open", &"craft", &"bag_ops"]:
		h.free()
		return "撿到可合成的武器、開背包後應跳 bag_open、craft、bag_ops：%s" % [shown]
	# 看過的不再跳
	tick.call(20.0, true)
	if shown.size() != 5:
		h.free()
		return "看過的提示又跳了：%s" % [shown]
	# 出口打開
	w.event._start(w)
	w.event.state = DigEvent.OPEN
	tick.call(10.0)
	if shown[-1] != &"exit":
		h.free()
		return "出口打開應跳 exit：%s" % [shown]
	# 排隊中條件不成立就跳過：隊友倒地排進佇列，顯示前已經救起
	p2.is_downed = true
	h.current = &"bag_ops"   # 假裝還有一則在顯示，讓 revive 留在佇列
	h.update(0.1, w, p, false)
	if not h.queue.has(&"revive"):
		h.free()
		return "隊友倒地應排進 revive"
	p2.is_downed = false
	h.current = &""
	tick.call(5.0)
	if h.seen.has(&"revive"):
		h.free()
		return "隊友已經救起，revive 不該顯示"
	# 重設後再跳
	var before := shown.size()
	h.reset_seen()
	tick.call(10.0)
	var first: StringName = shown[before] if shown.size() > before else &""
	h.free()
	if first != &"controls":
		return "重設後應重新跳操作提示：%s" % first
	return ""


static func check_effects_events() -> String:
	var handlers: Dictionary = Effects.HANDLERS
	var fx_view := Effects.new()
	for name: String in handlers:
		if not fx_view.has_method(handlers[name]):
			fx_view.free()
			return "Effects 沒有 %s 的處理函式 %s" % [name, handlers[name]]
	fx_view.free()
	# 靜態：sim/ 裡 emit_event("fx:…") 的名稱都要有處理、也要列進規範的事件表
	var guidelines := _read_text(ProjectSettings.globalize_path("res://").path_join("../PROJECT_GUIDELINES.md"))
	var re := RegEx.create_from_string("emit_event\\(\"(fx:\\w+)\"")
	var found := {}
	for path in _list_gd("res://sim"):
		for m in re.search_all(_read_text(path)):
			found[m.get_string(1)] = true
	for name: String in found:
		if not handlers.has(name):
			return "模擬層發出 %s，但 Effects.HANDLERS 沒有處理" % name
		if not guidelines.contains("`%s`" % name):
			return "%s 沒有列進 PROJECT_GUIDELINES 第 9 節的事件表" % name
	for name: String in handlers:
		if name.begins_with("fx:") and not found.has(name):
			return "Effects 處理 %s，但模擬層沒有發出這個事件" % name
	if found.size() < 10:
		return "只找到 %d 種 fx 事件，應有 10 種" % found.size()
	# 動態：實際跑招式收集事件，餵給 Effects
	var events: Array[Dictionary] = []
	var w := _new_world()
	_spawn(w, &"grunt", Vector2(0, 1.5))
	for i in 3:
		_run_collect(w, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1, events)
		_run_collect(w, _cmd(Vector2.ZERO), 30, events)
	var slashes := _named(events, "fx:slash")
	if slashes.size() != 3 or slashes[2].color != WeaponDefs.WEAPONS.swordShield.attack.slash_finisher_color or slashes[1].swing_dir != -1:
		return "三段揮砍應發出 3 次 fx:slash（第二段反手、第三段金色），實際 %s" % [slashes]
	var w2 := _new_world()
	_player(w2).equip_weapon(&"staff")
	_run_collect(w2, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1, events)
	_run_collect(w2, _cmd(Vector2.ZERO), 60, events)
	_run_collect(w2, _cmd(Vector2.ZERO, Vector2(0, 6), InputCmd.BTN_SPECIAL), 1, events)
	_run_collect(w2, _cmd(Vector2.ZERO), 90, events)
	var boss := _spawn(w2, &"boss", Vector2(0, 8))
	w2.events.clear()
	boss.slam_ring(0, {})
	events.append_array(w2.events)
	for name in ["fx:slash", "fx:muzzle", "fx:fizzle", "fx:telegraph", "fx:explosion", "fx:boss_slam", "entity:damaged"]:
		if _named(events, name).is_empty():
			return "應發出 %s" % name
	var view := Effects.new()
	_scene_root().add_child(view)
	view.world = w
	for e in events:
		view.on_event(e.name, e)
	var particles := view.particle_count()
	var transients := view.transient_count()
	view.sync(w2, DT)
	view.queue_free()
	if particles < 40 or transients < 6:
		return "餵完事件應有粒子與弧光環，實際粒子 %d、弧光環 %d" % [particles, transients]
	return ""


static func check_effects_limits() -> String:
	var view := Effects.new()
	_scene_root().add_child(view)
	view.burst(Vector3.ZERO, {"count": 2000})
	if view.particle_count() != Effects.MAX_PARTICLES:
		return "粒子應限制在 %d，實際 %d" % [Effects.MAX_PARTICLES, view.particle_count()]
	for i in 100:
		view.ring(Vector3.ZERO, 2.0)
	if view.transient_count() != Effects.MAX_TRANSIENTS:
		return "弧光環應限制在 %d，實際 %d" % [Effects.MAX_TRANSIENTS, view.transient_count()]
	view.clear()
	# 投射物拖尾：每個模擬步一顆（每秒 60 顆），不同幀率下每秒顆數要一樣
	var w := _new_world()
	var p := _player(w)
	w.spawn_projectile(Projectile.new(w, {"owner": p, "pos": Vector2(0, 2), "direction": Vector2(0, 1), "speed": 0.0, "range": 100.0}))
	var counts := []
	for fps in [30, 144]:
		var before := view.spawned_total
		for i in fps * 3:
			view.sync(w, 1.0 / fps)
		counts.append((view.spawned_total - before) / 3.0)
	for c: float in counts:
		if absf(c - 60.0) > 1.0:
			view.queue_free()
			return "拖尾每秒顆數應約 60（30 FPS / 144 FPS），實際 %.1f / %.1f" % counts
	var before_pause := view.spawned_total
	view.paused = true
	for i in 30:
		view.sync(w, 1.0 / 30.0)
	var paused_count := view.spawned_total - before_pause
	view.queue_free()
	if paused_count != 0:
		return "暫停時不應產生粒子，實際 %d 顆" % paused_count
	_feel("特效拖尾：30 FPS 每秒 %.1f 顆、144 FPS 每秒 %.1f 顆（每步 1 顆 = 60 顆）" % counts)
	return ""


static func check_flash_no_shader_switch() -> String:
	var kit := PartKit.new()
	var m := kit.mat(Color("8899aa"))
	for k in [0.0, 0.9, 0.0]:
		kit.set_flash(k)
		if not m.emission_enabled:
			return "set_flash(%.1f) 後 emission_enabled 應保持 true" % k
		if not m.emission.is_equal_approx(Color(k, k, k)):
			return "set_flash(%.1f) 後自發光應為 (%.1f, %.1f, %.1f)，實際 %s" % [k, k, k, k, m.emission]
	return ""


static func check_font_coverage() -> String:
	if ProjectSettings.get_setting("gui/theme/custom_font", "") != "res://assets/fonts/hud_font.tres":
		return "project.godot 的 gui/theme/custom_font 沒有設成打包字型"
	var font := load("res://assets/fonts/NotoSansTC-VF.ttf") as FontFile
	if font == null:
		return "讀不到 assets/fonts/NotoSansTC-VF.ttf"
	var drawn: Array = SkillIcons.DRAWN
	var texts: Array[String] = []
	for w: Dictionary in WeaponDefs.WEAPONS.values():
		texts.append_array([w.name, w.attack.name, w.attack.icon, w.special.name, w.special.icon, w.attack.get("desc", ""), w.special.get("desc", "")])
		for alt: Dictionary in [w.get("stance", {}), w.get("grab", {})]:
			for kind: String in ["attack", "special"]:   # 火把舉著時只換左鍵
				if alt.has(kind):
					texts.append_array([alt[kind].name, alt[kind].icon, alt[kind].get("desc", "")])
	for c: Dictionary in ClassDefs.CLASSES.values():
		texts.append_array([c.name, c.pitch, c.passive.desc])
	for c: Dictionary in ClassDefs.PLACEHOLDERS.values():
		texts.append_array([c.name, c.unlock])
	for s: Dictionary in SkillDefs.SKILLS.values():
		texts.append_array([s.name, s.icon, s.get("desc", "")])
	var hud_consts: Dictionary = load("res://ui/hud.gd").get_script_constant_map()
	texts.append_array([hud_consts.CONTROLS_TEXT, hud_consts.BOSS_NAME])
	for s: Dictionary in StatDefs.STATS.values():
		texts.append(s.name)
	for item: Dictionary in ItemDefs.ITEMS.values():
		texts.append_array([item.name, item.desc, "獲得 "])
	texts.append(StatDefs.format_value(&"armor", 8.0) + StatDefs.format_value(&"hp_regen", 1.0))
	# HUD 程式裡的字串常值（標題、橫幅、結算、按鍵名稱）
	var re := RegEx.create_from_string("\"([^\"\\\\]*)\"")
	for path in ["res://ui/hud.gd", "res://ui/skill_bar.gd", "res://ui/stats_panel.gd", "res://ui/class_select.gd"]:
		for m in re.search_all(_read_text(path)):
			texts.append(m.get_string(1))
	var missing := {}
	for t in texts:
		if t in drawn:
			continue
		for i in t.length():
			var code := t.unicode_at(i)
			if code > 32 and not font.has_char(code):
				missing[t[i]] = true
	if not missing.is_empty():
		return "打包字型缺字：%s" % " ".join(missing.keys())
	return ""


# 以 root 為座標系統計零件：{ meshes, min, max, bad_faces（法線與正面方向不符的三角形數） }
static func _mesh_stats(root: Node3D) -> Dictionary:
	var lo := Vector3.INF
	var hi := -Vector3.INF
	var bad := 0
	var meshes := PartKit.mesh_instances(root)
	for mi in meshes:
		var xf := mi.transform
		var n: Node = mi.get_parent()
		while n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var arrays := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for v in verts:
			lo = lo.min(xf * v)
			hi = hi.max(xf * v)
		if mi.mesh is ArrayMesh and arrays[Mesh.ARRAY_INDEX] == null:
			for i in range(0, verts.size(), 3):
				var face := (verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i])
				# Godot 正面為順時針：(b-a)×(c-a) 朝內，與法線相反（頂點是 float32，用 dot 容許誤差）
				if face.normalized().dot(-normals[i]) < 0.999:
					bad += 1
	return {"meshes": meshes.size(), "min": lo, "max": hi, "bad_faces": bad}


static func check_merge_static() -> String:
	var kit := PartKit.new()
	var root := Node3D.new()
	var arm := Node3D.new()
	arm.position = Vector3(0.5, 1, 0)
	arm.rotation.z = 0.4
	root.add_child(arm)
	var sub := Node3D.new()   # 非 anchor 的子群組：應被併入 arm
	sub.position = Vector3(0, -0.3, 0.1)
	sub.rotation.x = 0.7
	arm.add_child(sub)
	var red := kit.mat(Color.RED)
	var blue := kit.mat(Color.BLUE)
	kit.add(root, PartKit.box(0.4, 0.6, 0.3), red, {"y": 1.0})
	kit.add(root, PartKit.cyl(0.1, 0.1, 0.5, 6), red, {"x": 0.3, "rz": 0.5})
	kit.add(arm, PartKit.ico(0.1, 0), red, {"y": -0.2})
	kit.add(sub, PartKit.box(0.1, 0.1, 0.1), red, {"s": 2.0})
	kit.add(sub, PartKit.cone(0.1, 0.2, 4), blue)
	kit.add(sub, PartKit.torus(0.2, 0.03, 4, 8, PI), blue, {"rx": 0.3, "ry": 1.1})
	var gem := kit.add(arm, PartKit.ico(0.05, 1), blue, {"y": -0.5})

	var before := _mesh_stats(root)
	kit.merge_static(root, [root, arm], [gem])
	var after := _mesh_stats(root)
	var err := ""
	if not (after.min as Vector3).is_equal_approx(before.min) or not (after.max as Vector3).is_equal_approx(before.max):
		err = "外框改變：%s~%s → %s~%s" % [before.min, before.max, after.min, after.max]
	elif after.meshes != 4:
		err = "應剩 root 紅、arm 紅、arm 藍、gem 共 4 個，實際 %d 個" % after.meshes
	elif gem.get_parent() != arm or arm.get_parent() != root:
		err = "keep 的零件與 anchor 應留在原位"
	elif is_instance_valid(sub):
		err = "空的子群組應移除"
	elif after.bad_faces > 0:
		err = "%d 個三角形的法線不是朝外的面法線" % after.bad_faces
	root.free()
	return err


# 讀 tools/synth.gd 寫出的 16-bit WAV（資料從第 44 位元組開始），回傳 { samples, peak }
static func _wav_stats(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return {"samples": 0, "peak": 0.0}
	var n := bytes.decode_u32(40) / 2
	var peak := 0
	for i in n:
		peak = maxi(peak, absi(bytes.decode_s16(44 + i * 2)))
	return {"samples": n, "peak": peak / 32767.0}


static func check_sfx_files() -> String:
	var sound_script := _sound_script()
	var recipes: Array = load("res://tools/bake_sfx.gd").cues().keys()
	recipes.sort()
	var names: Array = sound_script.CUE_NAMES.duplicate()
	names.sort()
	if names.is_empty() or names != recipes:
		return "名稱不一致：配方 %d 個、Sound.CUE_NAMES %d 個" % [recipes.size(), names.size()]
	for cue_name: String in names:
		var stats := _wav_stats(sound_script.SFX_DIR + cue_name + ".wav")
		if stats.samples == 0:
			return "%s.wav 不存在或是空的（執行 tools/bake_sfx.gd）" % cue_name
		if stats.peak >= 1.0:
			return "%s.wav 峰值 %.3f，會失真" % [cue_name, stats.peak]
		if not ResourceLoader.exists(sound_script.SFX_DIR + cue_name + ".wav"):
			return "%s.wav 還沒匯入（執行 --import）" % cue_name
	return ""


static func check_music_files() -> String:
	var sound_script := _sound_script()
	var expected := {&"normal": 60.0 / 64.0 * 16.0, &"boss": 60.0 / 92.0 * 16.0}
	for track: StringName in expected:
		var stream: AudioStreamWAV = sound_script.MUSIC[track]
		if stream.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			return "%s 沒有設定循環（loop_mode = %d）" % [track, stream.loop_mode]
		if absf(stream.get_length() - expected[track]) > 0.01:
			return "%s 長度 %.3f 秒，應為 %.3f" % [track, stream.get_length(), expected[track]]
		var stats := _wav_stats("res://audio/music/%s.wav" % track)
		if stats.peak >= 1.0:
			return "%s 峰值 %.3f，會失真" % [track, stats.peak]
	return ""


static func check_sound_mapping() -> String:
	var sound_script := _sound_script()
	var w := _new_world(7, true)
	var p := _player(w)
	var grunt := _spawn(w, &"grunt", Vector2(6, 0))
	var boss := _spawn(w, &"boss", Vector2(-6, 0))
	var cue := func(event_name: String, payload: Dictionary) -> String:
		return sound_script.cue_for_event(w, event_name, payload)
	var cases := [
		[cue.call("entity:damaged", {"target_id": p.id, "is_crit": false}), "playerHurt"],
		[cue.call("entity:damaged", {"target_id": grunt.id, "is_crit": false}), "hit"],
		[cue.call("entity:damaged", {"target_id": grunt.id, "is_crit": true}), "hitHeavy"],
		[cue.call("entity:damaged", {"target_id": grunt.id, "is_heavy": true}), "hitHeavy"],
		[cue.call("entity:died", {"entity_id": grunt.id}), "enemyDeath"],
		[cue.call("entity:died", {"entity_id": boss.id}), "bossDeath"],
		[cue.call("entity:died", {"entity_id": p.id}), ""],
		[cue.call("skill:used", {"key": "player.special", "player_id": p.id}), ""],
		[cue.call("skill:onCooldown", {"key": "player.slot1", "player_id": p.id}), "denied"],
		[cue.call("wave:started", {"is_boss": false}), "waveStart"],
		[cue.call("wave:started", {"is_boss": true}), "bossAppear"],
		[cue.call("boss:enraged", {}), "enrage"],
		[cue.call("game:defeat", {}), "defeat"],
		[cue.call("player:died", {}), ""],   # v0.21.0：多人時一人陣亡不算輸，結算音效改由全員倒下的 game:defeat 播
		[cue.call("game:victory", {}), "victory"],
		[cue.call("game:paused", {"paused": true}), "pause"],
		[cue.call("game:paused", {"paused": false}), "resume"],
		[cue.call("sfx:cue", {"cue": "arrowShot"}), "arrowShot"],
	]
	for i in ActiveSlots.SLOT_COUNT:   # 道具欄依裝備的技能決定音效
		var slot: Variant = p.slots.get_slot(p, i)
		var expect: String = sound_script.SKILL_CUES.get(slot.def.id, "") if slot != null else ""
		cases.append([cue.call("skill:used", {"key": ActiveSlots.cd_key(i), "player_id": p.id}), expect])
	for c in cases:
		if c[0] != c[1]:
			return "預期 %s，實際 %s（第 %d 組）" % [c[1], c[0], cases.find(c) + 1]
		if c[1] != "" and not c[1] in sound_script.CUE_NAMES:
			return "%s 不在 CUE_NAMES" % c[1]
	if not "potion" in cases.map(func(c: Array) -> String: return c[0]):
		return "道具欄沒有治療藥水，無法驗證 potion"

	var m := func(current: StringName, event_name: String, payload: Dictionary) -> StringName:
		return sound_script.music_for_event(current, event_name, payload)
	var music_cases := [
		[m.call(&"", "game:restart", {}), &"normal"],
		[m.call(&"boss", "game:restart", {}), &"normal"],
		[m.call(&"normal", "wave:started", {"is_boss": false}), &"normal"],
		[m.call(&"normal", "wave:started", {"is_boss": true}), &"boss"],
		[m.call(&"boss", "game:defeat", {}), &""],
		[m.call(&"boss", "player:died", {}), &"boss"],
		[m.call(&"normal", "game:victory", {}), &""],
		[m.call(&"boss", "game:paused", {"paused": true}), &"boss"],
	]
	for c in music_cases:
		if c[0] != c[1]:
			return "音樂：預期 %s，實際 %s（第 %d 組）" % [c[1], c[0], music_cases.find(c) + 1]
	return ""


# 音效距離衰減與個別音量（v0.44.0）：hear_full 內全音量、hear_max 以外不播、中間 (1 − t)²；
# 模擬層的 sfx:cue 都帶發聲位置（全場音效除外）；多人時遠處隊友的攻擊音效聽不到；法杖普攻 −8 dB
static func check_sound_distance() -> String:
	var sound_script := _sound_script()
	var a: Dictionary = Config.AUDIO
	for c: Array in [[0.0, 1.0], [a.hear_full, 1.0], [20.0, 0.5625], [25.0, 0.25], [30.0, 0.0625], [a.hear_max, 0.0], [50.0, 0.0]]:
		if absf(sound_script.distance_gain(c[0]) - c[1]) > EPS:
			return "距離 %.0f 音量比例 %.4f，預期 %.4f" % [c[0], sound_script.distance_gain(c[0]), c[1]]
	if absf(sound_script.cue_db("fireBolt", 1.0) + 8.0) > EPS or absf(sound_script.cue_db("swing", 1.0)) > EPS:
		return "法杖普攻 %.1f dB、揮砍 %.1f dB，預期 −8 / 0" % [sound_script.cue_db("fireBolt", 1.0), sound_script.cue_db("swing", 1.0)]
	# 模擬層每個 sfx:cue 都要帶 pos（勝利是全場音效）
	var re := RegEx.create_from_string("\"sfx:cue\", \\{\"cue\": [^}]*\\}")
	for path in _list_gd("res://sim"):
		for m in re.search_all(_read_text(path)):
			var s := m.get_string()
			if not s.contains("\"pos\"") and not s.contains("\"victory\""):
				return "%s 的 %s 沒有帶發聲位置 pos" % [path, s]
	# 兩人：隊友在場地另一角（距離 > hear_max）揮劍，本機聽不到；走近後聽得到
	var w := World.new(&"test_arena")
	w.reset(5, [World.HOST_PEER_ID, World.HOST_PEER_ID + 1])
	w.spawner.finished = true
	_worlds.append(w)
	var me: Player = w.players[World.HOST_PEER_ID]
	var mate: Player = w.players[World.HOST_PEER_ID + 1]
	me.pos = Vector2(-14, -14)
	var gains := []
	for at: Vector2 in [Vector2(14, 14), me.pos + Vector2(4, 0)]:
		mate.pos = at
		var events: Array[Dictionary] = []
		for i in 40:
			w.step({World.HOST_PEER_ID: InputCmd.new(), World.HOST_PEER_ID + 1: _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK)}, DT)
			events.append_array(w.events)
		var swings := _named(events, "sfx:cue")
		if swings.is_empty():
			return "隊友攻擊沒有發出音效事件"
		gains.append(sound_script.event_gain(w, me, "sfx:cue", swings[0]))
	if gains[0] > 0.0 or absf(gains[1] - 1.0) > EPS:
		return "隊友在 %.1f 外揮劍音量 %.3f（應 0）、身邊 4 單位 %.3f（應 1）" % [Vector2(14, 14).distance_to(me.pos), gains[0], gains[1]]
	# 受傷、死亡用目標的位置；沒有位置的全場音效（波次）全音量；沒有本機角色時全音量
	var far := _spawn(w, &"grunt", me.pos + Vector2(0, 25))
	if absf(sound_script.event_gain(w, me, "entity:damaged", {"target_id": far.id}) - 0.25) > EPS:
		return "25 單位外的骷髏受傷音量應 0.25，實際 %.3f" % sound_script.event_gain(w, me, "entity:damaged", {"target_id": far.id})
	if absf(sound_script.event_gain(w, me, "wave:started", {"is_boss": false}) - 1.0) > EPS or absf(sound_script.event_gain(w, null, "entity:damaged", {"target_id": far.id}) - 1.0) > EPS:
		return "全場音效與沒有本機角色時應全音量"
	return ""


static func check_mesh_counts() -> String:
	var limits := {&"player": 20, &"grunt": 16, &"archer": 16, &"boss": 22}
	var err := ""
	for kind: StringName in limits:
		var rig := DarkFantasy.character(kind)
		var stats := _mesh_stats(rig)
		if stats.meshes > limits[kind]:
			err = "%s 有 %d 個零件，上限 %d" % [kind, stats.meshes, limits[kind]]
		elif stats.bad_faces > 0:
			err = "%s 有 %d 個三角形法線方向錯誤" % [kind, stats.bad_faces]
		rig.free()
		if err != "":
			return err
	var rng := RandomNumberGenerator.new()
	var arena := DarkFantasy.build_arena(Config.WORLD.arena_half_size, rng)
	var n := PartKit.mesh_instances(arena).size()
	arena.free()
	if n > 12:
		return "場地有 %d 個零件，上限 12" % n
	for model: StringName in [&"swordShield", &"staff"]:
		var w := DarkFantasy.weapon(model)
		if w.is_empty() or w.main == null:
			return "武器 %s 沒有建立外觀" % model
		for node: Variant in [w.main, w.offhand]:
			if node != null:
				(node as Node3D).free()
	return ""


# 握武器：每把玩家武器掛上去後，模型標的 grip 掛點就在拳頭中心（手掌掛點），手掌掛點上有拳頭；
# 法杖類直立是轉手掌掛點（武器本身不另外轉、拳頭和杖身一起朝上）；骷髏與 Boss 的拳頭也掛在手掌掛點上
# 檢查在 _initialize 裡跑、場景樹還沒就緒，global_transform 拿不到：位置與方向都沿著節點一層層乘局部座標算
static func check_weapon_grip() -> String:
	var w := _new_world()
	var p := _player(w)
	var rig := DarkFantasy.player_character(ClassDefs.ORDER[0])
	var anim := Animator.new(rig)
	var err := ""
	for id: StringName in WeaponDefs.WEAPONS:
		p.equip_weapon(id)
		for i in 30:
			anim.update(p, DT)
		for pair in [[rig.weapon_main, rig.hand_r], [rig.weapon_left, rig.hand_l]]:
			var model: Node3D = pair[0]
			var hand: Node3D = pair[1]
			if model == null:
				continue
			if not model.has_meta(&"mounts"):
				err = "%s 的模型沒有標掛點（DarkFantasy._hold）" % id
			elif (model.transform * (model.get_meta(&"mounts").grip as Vector3)).length() > 0.001:
				err = "%s 的 grip 離拳頭中心 %.3f" % [id, (model.transform * (model.get_meta(&"mounts").grip as Vector3)).length()]
			elif not _has_fist(hand):
				err = "%s 的手掌掛點上沒有拳頭" % id
			if err != "":
				break
		if err == "" and id in [&"staff", &"scepter", &"torch"]:
			var up := _basis_under(rig.weapon_main, rig).y.normalized().dot(Vector3.UP)
			if not rig.weapon_main.rotation.is_zero_approx() or up < 0.999:
				err = "%s 待機時應轉手掌讓杖身直立：武器自己的轉角 %s、杖身與正上方 cos %.4f" % [id, rig.weapon_main.rotation, up]
		if err != "":
			break
	rig.free()
	if err != "":
		return err
	for kind: StringName in [&"grunt", &"archer", &"boss"]:
		var enemy := DarkFantasy.character(kind)
		var ok := _has_fist(enemy.hand_r) and _has_fist(enemy.hand_l)
		enemy.free()
		if not ok:
			return "%s 的拳頭應掛在手掌掛點上" % kind
	return ""


# 弓：不拉弓時平放（弓梢連線水平、弓背朝下、弦在上）。
# 拉弓轉直立沒在這裡驗：拉弓姿勢（Animator._pose_bow）要用世界座標，檢查跑在場景樹就緒前
static func check_bow_rest() -> String:
	for id: StringName in [&"shortbow", &"longbow"]:
		var w := _new_world()
		var p := _player(w)
		p.equip_weapon(id)
		var rig := DarkFantasy.player_character(&"ranger")
		var anim := Animator.new(rig)
		for i in 30:
			anim.update(p, DT)
		var rest := _basis_under(rig.weapon_left, rig).orthonormalized()
		rig.free()
		if absf(rest.y.dot(Vector3.UP)) > 0.01 or rest.z.dot(Vector3.DOWN) < 0.99:
			return "%s 待機時弓應平放：弓梢方向 %s、弓背方向 %s" % [id, rest.y, rest.z]
	return ""


# 骷髏弓手：不瞄準時左手垂直（弓平放）、瞄準時舉起、射完回 kite 的第一幀不直接跳回垂直（平滑放下）
static func check_archer_bow_arm() -> String:
	var w := _new_world()
	var p := _player(w)
	p.stats.set_base(&"max_hp", 99999.0)
	p.hp = 99999.0
	var archer := _spawn(w, &"archer", p.pos + Vector2(0, 8))
	var rig := DarkFantasy.character(&"archer")
	var anim := EnemyAnimator.new(rig, archer)
	var rest_ok := false
	var prev_state: StringName = &""
	var highest := 0.0
	var after_aim := INF
	for i in 900:
		_run(w, _cmd(Vector2.ZERO), 1)
		anim.update(archer, DT)
		var state: StringName = archer.anim.state
		if state == &"aim":
			highest = minf(highest, rig.arm_l.rotation.x)
		elif prev_state == &"aim":
			after_aim = rig.arm_l.rotation.x
			break
		elif state == &"kite" and absf(rig.arm_l.rotation.x - EnemyAnimator.BOW_ARM_REST) < 0.01:
			rest_ok = true
		prev_state = state
	rig.free()
	if not rest_ok:
		return "弓手不瞄準時左手應垂直（%.2f）" % EnemyAnimator.BOW_ARM_REST
	if after_aim == INF:
		return "弓手 15 秒內沒有瞄準射完"
	if highest > -1.4:
		return "弓手瞄準時左手應舉到接近水平：最高 %.2f" % highest
	if after_aim > -0.5:
		return "弓手射完第一幀左手就回到 %.2f，應平滑放下" % after_aim
	_note("弓手瞄準時左手最高 %.2f、射完第一幀 %.2f" % [highest, after_aim])
	return ""


# node 相對於祖先 top 的方向（各層 basis 相乘）
static func _basis_under(node: Node3D, top: Node3D) -> Basis:
	var b := Basis.IDENTITY
	var n := node
	while n != top:
		b = n.basis * b
		n = n.get_parent() as Node3D
	return b


# 手掌掛點上有零件、而且包住掛點原點（拳頭中心）
static func _has_fist(hand: Node3D) -> bool:
	for child in hand.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).get_aabb().grow(0.001).has_point(Vector3.ZERO):
			return true
	return false


# 投射物的牆後剪影：箭飛到牆後（和相機之間有牆）也畫剪影，顏色看發射者（怪物紅、自己藍）；空地上的不畫
static func check_projectile_xray() -> String:
	var w := _new_world(3, false, &"graveyard_a")
	var p := _player(w)
	# 同 check_xray：王族墓南牆北邊，玩家在 y 57 面向南，牆邊 y 60.6 和相機之間有牆
	p.pos = MapDefs.to_world(w.map, Vector2(48, 57))
	p.facing = 0.0
	var archer := _spawn(w, &"archer", MapDefs.to_world(w.map, Vector2(40, 50)))
	var arrow := Projectile.new(w, {"owner": archer, "pos": MapDefs.to_world(w.map, Vector2(48, 60.6)), "direction": Vector2.UP,
		"speed": 0.0, "range": 10.0, "radius": 0.15, "color": Color.ORANGE, "visual": &"arrow", "altitude": Config.HEIGHT.arrow_altitude})
	w.spawn_projectile(arrow)
	var mine := Projectile.new(w, {"owner": p, "pos": MapDefs.to_world(w.map, Vector2(47, 60.6)), "direction": Vector2.UP,
		"speed": 0.0, "range": 10.0, "radius": 0.25, "color": Color.ORANGE, "visual": &"orb", "altitude": 1.0})
	w.spawn_projectile(mine)
	var view := WorldView.new()
	var overlay := func(node: Node3D) -> Material:
		for mi in PartKit.mesh_instances(node):
			if mi.material_overlay != null:
				return mi.material_overlay
		return null
	view.sync(w, 1.0, 0.016)
	var err := ""
	var an: Node3D = view._nodes[arrow.id]
	var mn: Node3D = view._nodes[mine.id]
	if not an.visible:
		err = "牆邊的箭應在視野內"
	elif not view._xray_needed(w, arrow) or overlay.call(an) != WorldView.xray_material(WorldView.XRAY_ENEMY):
		err = "牆後的怪物箭應有紅色剪影：判斷 %s、疊加材質 %s" % [view._xray_needed(w, arrow), overlay.call(an)]
	elif overlay.call(mn) != WorldView.xray_material(WorldView.XRAY_SELF):
		err = "牆後自己的魔彈應有藍色剪影：%s" % overlay.call(mn)
	if err == "":
		# 同顏色的投射物共用材質：寫了模板值的材質各自一份時，每射一發都在遊戲中編一次著色器（卡 30~40 ms）
		var materials := func(node: Node3D) -> Array:
			var out := []
			for mi in PartKit.mesh_instances(node):
				if not WorldView.XRAY_SKIP.has(mi.name) and not WorldView.XRAY_SKIP.has(mi.get_parent().name):   # 除錯用的 Hitbox 圈各自一份，不算
					out.append(mi.material_override)
			return out
		for pair: Array in [[an, view._create_view(arrow)], [mn, view._create_view(mine)]]:
			var again: Node3D = pair[1]
			var same: bool = materials.call(pair[0]) == materials.call(again)
			again.free()
			if not same:
				err = "同顏色的投射物應共用材質（%s）" % (pair[0] as Node3D).name
				break
	if err == "":
		# 飛到墓中央的空地：下一個 tick 就拿掉（投射物每個 tick 都判斷）
		arrow.pos = MapDefs.to_world(w.map, Vector2(46, 55))
		arrow.prev_pos = arrow.pos
		w.tick += 1
		view.sync(w, 1.0, 0.016)
		if view._xray_needed(w, arrow) or overlay.call(an) != null:
			err = "空地上的箭不應有剪影：判斷 %s、疊加材質 %s" % [view._xray_needed(w, arrow), overlay.call(an)]
	view.free()
	return err


# 挖墳時視野跟著滑鼠轉：模擬層的朝向跟著瞄準點，畫面的視野遮罩（變暗的扇形）跟著模型朝向
static func check_dig_vision() -> String:
	var w := _new_world(12345, false, &"graveyard_a")
	var p := _player(w)
	p.pos = w.event.point + Vector2(1.5, 0.0)
	var view := WorldView.new()
	var err := ""
	for aim: Vector2 in [Vector2(10, 0), Vector2(0, -10), Vector2(-10, 0)]:
		var want := MathUtil.angle_to(Vector2.ZERO, aim)
		_run(w, _cmd(Vector2.ZERO, p.pos + aim, InputCmd.BTN_INTERACT), 40)
		view.sync(w, 1.0, 0.016)
		var shown: float = (view._vision_overlay.material_override as ShaderMaterial).get_shader_parameter(&"facing")
		if not p.is_digging():
			err = "按住 F 應在挖墳（動作 %s）" % p.action.current_name
		elif absf(angle_difference(p.facing, want)) > 0.01 or absf(angle_difference(shown, want)) > 0.01:
			err = "挖墳中瞄準 %s：朝向 %.2f、視野遮罩 %.2f，預期都是 %.2f" % [aim, p.facing, shown, want]
		if err != "":
			break
	view.free()
	return err


# 觀戰（多人時本機陣亡後看隊友）：選人規則、視野改用隊友的、房主改送隊友附近的實體；復活後回到自己
static func check_spectate() -> String:
	var w := _new_world()
	w.reset(12345, [1, 2, 3])
	var p1: Player = w.players[1]
	var p2: Player = w.players[2]
	var p3: Player = w.players[3]
	# 選人：本機活著、倒地假死都不觀戰；陣亡後看第一位，±1 循環；看的人死了或走進出口就換
	if WorldView.spectate_target(w, 1, 0) != 0:
		return "本機活著不應觀戰"
	p1.is_downed = true
	if WorldView.spectate_target(w, 1, 0) != 0:
		return "倒地假死時不應觀戰"
	p1.is_downed = false
	p1.is_dead = true
	var picks := [WorldView.spectate_target(w, 1, 0), WorldView.spectate_target(w, 1, 2, 1), WorldView.spectate_target(w, 1, 3, 1), WorldView.spectate_target(w, 1, 2, -1)]
	if picks != [2, 3, 2, 3]:
		return "陣亡後第一位、下一位、循環、上一位應為 [2, 3, 2, 3]，實際 %s" % [picks]
	p2.is_dead = true
	if WorldView.spectate_target(w, 1, 2) != 3:
		return "看的隊友死了應換到下一位"
	p3.descended = true
	if WorldView.spectate_target(w, 1, 3) != 0:
		return "沒有站著的隊友（死了、走進出口）就不觀戰"
	p2.is_dead = false
	p3.descended = false
	# 視野：P2 面向 +Z，前方的骷髏看得到、背後的看不到（P1 陣亡時本來全部看得到）
	p1.pos = Vector2(-10, -10)
	p2.pos = Vector2(5, 0)
	p2.facing = 0.0
	var front := _spawn(w, &"grunt", Vector2(5, 8))
	var back := _spawn(w, &"grunt", Vector2(5, -8))
	var view := WorldView.new()
	view.local_peer = 1
	view.spectate_peer = 2
	view.sync(w, 1.0, 0.016)
	var err := ""
	if view.viewer() != p2 or not view._nodes[front.id].visible or view._nodes[back.id].visible or not view._vision_overlay.visible:
		err = "觀戰 P2：視野以 %s 為準、前方 %s、背後 %s、遮罩 %s（應為 P2 / true / false / true）" % [
			view.viewer().id if view.viewer() else 0, view._nodes[front.id].visible, view._nodes[back.id].visible, view._vision_overlay.visible]
	# 復活（救起、冤魂）後視野回到自己
	if err == "":
		p1.is_dead = false
		if view.viewer() != p1 or WorldView.spectate_target(w, 1, 2) != 0:
			err = "復活後視野應回到自己（觀戰對象 %d）" % WorldView.spectate_target(w, 1, 2)
	view.free()
	if err != "":
		return err
	# 房主：輸入帶著觀戰對象，快照改以他為中心挑實體（遠處的怪才送得到）
	p1.is_dead = true
	var host := NetHost.new(w)
	var cmd := _cmd(Vector2.ZERO)
	cmd.tick = 1
	cmd.spectate = 2
	host.receive_inputs(1, [cmd.to_array()])
	host.take_cmds()
	if host.spectating.get(1, 0) != 2 or host.viewer_of(1) != p2 or not host.in_interest(front, host.viewer_of(1)):
		return "房主應記下 P1 在看 P2、快照以 P2 為中心：記錄 %s、中心 %s" % [host.spectating.get(1, 0), host.viewer_of(1).id if host.viewer_of(1) else 0]
	p1.is_dead = false
	if host.viewer_of(1) != p1:
		return "P1 復活後快照應回到以自己為中心"
	return ""


# 結束程式不洩漏：主場景跑 3 秒（有怪、一直攻擊，音效還在播）後自己結束，輸出沒有 ObjectDB 洩漏、資源還在用
# 直接 quit 時還在播的音效會留下播放物件（約 5 次 4 次）；main.quit_game 先停音效、等 QUIT_AUDIO_DELAY 再結束。跑兩次提高抓到的機率
static func check_quit_no_leak() -> String:
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--seconds=3", "--horde=40", "--auto-attack"]
	for run in 2:
		var out := []
		var code := OS.execute(OS.get_executable_path(), args, out, true)
		var text := "\n".join(out)
		if code != 0 or not text.contains("tick="):
			return "主場景沒有正常跑完（exit %d）" % code
		for line in text.split("\n"):
			if line.contains("leaked at exit") or line.contains("still in use at exit"):
				return "第 %d 次結束時有洩漏：%s" % [run + 1, line.strip_edges()]
	return ""
