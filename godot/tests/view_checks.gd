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


# 互動列表（ui/interact_list.gd）：按得到 F 的只有一個不開、兩個以上才開；滾輪 / 上下鍵（cycle）頭尾接起來換；每列有字；
# 選中的那個離開範圍就回到最近的；場上的「[F]」提示跟著選中的（WorldLabels._focus_id）
static func check_interact_list() -> String:
	var w := _new_world()
	var p := _player(w)
	var list := InteractList.new()
	list.world = w
	var labels := WorldLabels.new()
	labels.world = w
	labels.interact_list = list
	var a := w.drop_item(&"whetstone", p.pos + Vector2(0.6, 0))
	list.refresh()
	var err := ""
	if list.is_open() or list.selected_id != a.id:
		err = "只有一個按得到時不應開列表、選的是它：開 %s、選 %d" % [list.is_open(), list.selected_id]
	var b := w.drop_item(&"bone_charm" if ItemDefs.ITEMS.has(&"bone_charm") else &"whetstone", p.pos + Vector2(-1.0, 0))
	list.refresh()
	if err == "" and (not list.is_open() or list.selected_id != a.id):
		err = "兩個以上應開列表、原本選的不被搶走：開 %s、選 %d" % [list.is_open(), list.selected_id]
	if err == "":
		list.cycle(1)
		var second := list.selected_id
		list.cycle(1)
		if second != b.id or list.selected_id != a.id:
			err = "往下換應選到第二個、再往下回到第一個：%d → %d" % [second, list.selected_id]
	if err == "":
		for o: Dictionary in list.options:
			if InteractList.label(w, p, o) == "":
				err = "每一列都要有字：%s" % [o]
	if err == "":
		list.cycle(1)
		if labels._focus_id(p) != b.id:
			err = "場上的 [F] 提示應跟著列表選中的那個：%d / %d" % [labels._focus_id(p), b.id]
	if err == "":
		b.pos = p.pos + Vector2(LootDefs.INTERACT_RANGE + 5.0, 0)
		list.refresh()
		if list.selected_id != a.id or list.is_open():
			err = "選中的那個離開範圍應回到最近的、只剩一個就收起：選 %d、開 %s" % [list.selected_id, list.is_open()]
	list.free()
	labels.free()
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
	# 武器欄：手上那把的名稱（沒有副手）
	hud._process(DT)
	if hud._weapon.text != "武器：" + WeaponDropDefs.display_name(p.weapon_slots[Loadout.MAIN]):
		return "武器欄應只寫手上那把：%s" % hud._weapon.text
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
	var err: String = await _check_main_menu(hud)
	if err == "":
		err = await _check_class_select(hud)
	if err == "":
		err = _check_test_panel(hud)
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
		# 被動 / 左鍵 / 右鍵 / 翻滾
		var want_rows := 4
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


# 武器測試場的測試面板：預設隱藏；五個分頁、道具 / 技能每個一顆；選武器 + 稀有度 + 詞條按「放進背包」照選的發出，詞條超過上限擋下；
# 怪物分頁每種一顆（不含冤魂、僕從）；整個面板（從 y 130 起）塞得進 1920 × 1080
static func _check_test_panel(hud: Variant) -> String:
	var tp: TestPanel = hud.test_panel
	if tp.visible or hud.revive_button.visible:
		return "測試面板與立即復活平常應隱藏"
	if tp.pages.size() != TestPanel.TABS.size():
		return "測試面板應有 %d 個分頁，實際 %d" % [TestPanel.TABS.size(), tp.pages.size()]
	var count := func(t: StringName) -> int:
		return (tp.pages[t] as ScrollContainer).get_child(0).find_children("*", "Button", true, false).size()
	var items := TestPanel._ids_of(&"item").size()
	var skills := TestPanel._ids_of(&"skill").size()
	skills += SkillDefs.LEVEL.max + 1   # 技能分頁另有等級按鈕（＋1 與每一級）
	# 怪物分頁另有成長（層、小關）、稀有度、一次幾隻、木樁擺法的按鈕
	var enemies := Practice.enemy_types().size() + MonsterRarityDefs.RARITIES.size() + MapDefs.PRACTICE_MAPS.size() + MapGenDefs.STAGES.size() \
		+ Practice.SPAWN_COUNTS.size() + Spawner.TRAINING_KINDS.size()
	if count.call(&"item") != items or count.call(&"skill") != skills or count.call(&"enemy") != enemies:
		return "道具 / 技能 / 怪物按鈕應有 %d / %d / %d 顆，實際 %d / %d / %d" % [items, skills, enemies, count.call(&"item"), count.call(&"skill"), count.call(&"enemy")]
	var got := []
	tp.weapon_requested.connect(func(base: StringName, rarity: StringName) -> void: got.append([base, rarity]))
	tp._pick_base(&"staff")
	tp._pick_rarity(&"green")
	tp._request_weapon()
	if got != [[&"staff", &"green"]] or not tp._rarity_buttons.has(WeaponDropDefs.START_RARITY) or "_affix_buttons" in tp:
		return "放進背包應送出 法杖 / 綠，稀有度有灰色、沒有詞條按鈕：%s" % [got]
	# 袋子分頁：袋子分開列每種袋子 × 大小；背包合併換成三顆開格按鈕
	tp.set_bag_mode(false)
	var bag_buttons: int = tp._bag_page.find_children("*", "Button", true, false).size()
	tp.set_bag_mode(true)
	var unlock_buttons: int = tp._bag_page.find_children("*", "Button", true, false).size()
	tp.set_bag_mode(false)
	if bag_buttons != BagDefs.BAGS.size() * BagDefs.TIERS.size() or unlock_buttons != 3:
		return "袋子分頁應有 %d 顆袋子、合併時 3 顆開格：%d / %d" % [BagDefs.BAGS.size() * BagDefs.TIERS.size(), bag_buttons, unlock_buttons]
	var spawned := []
	tp.enemy_requested.connect(func(type: StringName, rarity: StringName, n: int) -> void: spawned.append([type, rarity, n]))
	tp._pick_enemy_rarity(MonsterRarityDefs.MAGIC)
	tp._pick_count(Practice.SPAWN_COUNTS[1])
	var grunt_button: Button = (tp.pages[&"enemy"] as ScrollContainer).get_child(0).find_children("*", "Button", true, false).filter(
		func(b: Button) -> bool: return b.text == EnemyDefs.def_of(&"grunt").get("name", "grunt"))[0]
	grunt_button.pressed.emit()
	if spawned != [[&"grunt", MonsterRarityDefs.MAGIC, Practice.SPAWN_COUNTS[1]]]:
		return "生怪應帶選的稀有度與隻數：%s" % [spawned]
	# 成長、木樁、作弊、技能等級各自發出選的值；reset_choices 回到預設而且不發訊號
	var sent := []
	tp.stage_chosen.connect(func(f: int, s: int) -> void: sent.append([&"stage", f, s]))
	tp.dummies_requested.connect(func(k: StringName) -> void: sent.append([&"dummy", k]))
	tp.cheat_toggled.connect(func(id: StringName, on: bool) -> void: sent.append([&"cheat", id, on]))
	tp.item_requested.connect(func(id: StringName, lv: int) -> void: sent.append([&"item", id, lv]))
	tp._floor_buttons[2].pressed.emit()
	tp._stage_buttons[3].pressed.emit()
	tp._dummy_buttons[&"crowd"].pressed.emit()
	tp._cheat_buttons[&"mana"].button_pressed = true
	tp._pick_level(3)
	var whirl: Button = (tp.pages[&"skill"] as ScrollContainer).get_child(0).find_children("*", "Button", true, false).filter(
		func(b: Button) -> bool: return b.text == ItemDefs.ITEMS[&"whirlwind"].name)[0]
	whirl.pressed.emit()
	var want_sent := [[&"stage", 2, 1], [&"stage", 2, 3], [&"dummy", &"crowd"], [&"cheat", &"mana", true], [&"item", &"whirlwind", 3]]
	if sent != want_sent:
		return "成長 / 木樁 / 作弊 / 技能等級應各自發出選的值：%s" % [sent]
	tp.reset_choices()
	if sent != want_sent or tp.enemy_floor != 1 or tp.enemy_stage != 1 or tp.enemy_count != 1 or tp.skill_level != 0 \
			or tp.dummy_kind != Spawner.TRAINING_DEFAULT or tp._cheat_buttons[&"mana"].button_pressed or tp.enemy_rarity != MonsterRarityDefs.NORMAL:
		return "reset_choices 應回到預設而且不發訊號：%s" % [sent]
	# 傷害統計的字再長也不會把面板撐寬
	var narrow := tp.get_combined_minimum_size().x
	tp.set_meter("秒傷 123456（最近 5 秒）　總 123456789　最高 1234567　12345 下　秒傷 123456（最近 5 秒）　總 123456789")
	if tp.get_combined_minimum_size().x > narrow + 1.0:
		return "傷害統計的字變長不應把面板撐寬：%.0f → %.0f" % [narrow, tp.get_combined_minimum_size().x]
	# 平常收起（只剩分頁與工具列）；點分頁展開、再點同一頁收起
	tp.set_collapsed(true)
	if tp._body.visible:
		return "測試面板應預設收起"
	tp.show_tab(&"item")
	var opened: bool = tp._body.visible and tp.pages[&"item"].visible
	tp.show_tab(&"item")
	if not opened or tp._body.visible:
		return "點分頁應展開、再點同一頁應收起（展開 %s、收起後 %s）" % [opened, tp._body.visible]
	# 在左上、血條下面：右緣離畫面中央（角色）至少 200，展開時塞得進 1080 高
	tp.active = true
	hud._process(DT)
	var top: float = hud._top_left.position.y + hud._top_left.get_combined_minimum_size().y + 12.0
	for t: StringName in TestPanel.TABS:
		tp.show_tab(t)
		var size := tp.get_combined_minimum_size()
		if tp.position.x + size.x > 960.0 - 200.0 or top + size.y > 1080.0:
			return "測試面板（%s 分頁）%.0f × %.0f、左上 (%.0f, %.0f)：右緣要離畫面中央 200 以上、下緣塞得進 1080" % [TestPanel.TAB_NAMES[t], size.x, size.y, tp.position.x, top]
	# 開背包時藏起來（讓位給左邊的屬性面板），關掉再出現
	hud.inventory_panel.visible = true
	hud._process(DT)
	var hidden_with_bag: bool = not tp.visible
	hud.inventory_panel.visible = false
	hud._process(DT)
	var back: bool = tp.visible
	tp.active = false
	hud._process(DT)
	if not hidden_with_bag or not back:
		return "開背包時測試面板應藏起來、關掉再出現（藏 %s、回來 %s）" % [hidden_with_bag, back]
	return ""


# 技能欄的左右鍵（許家慶 2026-11-06 右鍵統一成「按一下放一招、耗魔」）：每把武器只有左鍵普攻、右鍵招式兩格，右鍵顯示耗魔；
# 沒有招架、火把準備姿態、鐵鏟舉著怪這類換招的格子
static func check_skill_bar_parry() -> String:
	var w := _new_world()
	var p := _player(w)
	var bar := SkillBar.new()
	_scene_root().add_child(bar)
	var err := ""
	for wid: StringName in WeaponDefs.WEAPONS:
		p.equip_weapon(wid)
		bar.refresh(w, p)
		var wd: Dictionary = WeaponDefs.WEAPONS[wid]
		if bar._attack_slot.icon_id != wd.attack.icon or bar._special_slot.icon_id != wd.special.icon or bar._special_slot.mana_def != wd.special:
			err = "%s：技能欄左鍵應是 %s、右鍵 %s（帶耗魔）：%s / %s" % [wid, wd.attack.icon, wd.special.icon, bar._attack_slot.icon_id, bar._special_slot.icon_id]
		elif bar._slots.has("player.parry") or bar._slots.has("player.breath"):
			err = "%s：技能欄不應有招架或噴火的換招格：%s" % [wid, bar._slots.keys()]
		if err != "":
			break
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
	_run(w, _cmd(Vector2.ZERO, Vector2(0, 5)), roundi(Config.MANA.cast_gap / DT / 2.0))
	bar.refresh(w, p)
	var s: SkillBar.Slot = bar._slots["player.special"]
	var err := ""
	if s.cd_ratio <= 0.0 or s.cd_left <= 0.0:
		err = "短弓散射後右鍵格應在防連按間隔裡：比例 %.2f、秒數 %.2f" % [s.cd_ratio, s.cd_left]
	elif not (s.icon.get_index() < s.mask.get_index() and s.mask.get_index() < s.cd_text.get_index()):
		err = "疊放順序應為 圖示 < 遮罩 < 秒數：%d / %d / %d" % [s.icon.get_index(), s.mask.get_index(), s.cd_text.get_index()]
	bar.queue_free()
	return err


# 寶石座的一般技能（耗魔、資料沒有 mode）：右下寫耗魔、魔力不夠圖示變暗；右鍵格也寫耗魔；排在後面的 Q 藥水照樣顯示剩幾瓶
static func check_skill_bar_gem_skill() -> String:
	var w := _new_world()
	var p := _player(w)
	p.add_item(&"whirlwind")
	var bar := SkillBar.new()
	_scene_root().add_child(bar)
	bar.refresh(w, p)
	var gem: SkillBar.Slot = bar._slots[ActiveSlots.cd_key(0)]
	var heal: SkillBar.Slot = bar._slots[ActiveSlots.cd_key(ActiveSlots.HEAL_INDEX)]
	var special: SkillBar.Slot = bar._slots["player.special"]
	var cost := roundi(ActiveSlots.mana_cost(p, p.slots.get_slot(p, 0)))
	var err := ""
	if bar._slots.has(ActiveSlots.cd_key(BagDefs.BAGS.key.max)) or not bar._slots.has(ActiveSlots.cd_key(BagDefs.BAGS.key.max - 1)):
		err = "技能欄的數字鍵應跟按鍵袋上限一樣多（%d 格）" % BagDefs.BAGS.key.max
	if gem.cost.text != str(cost) or gem.icon.modulate.a < 1.0:
		err = "旋風斬那格應寫耗魔 %d、魔力夠時不變暗：「%s」、%.2f" % [cost, gem.cost.text, gem.icon.modulate.a]
	elif special.cost.text != (str(roundi(p.mana_cost_of(p.weapon.special))) if p.weapon.special.has("mana") else ""):
		err = "右鍵格應寫耗魔（%s），實際「%s」" % [p.weapon.special.get("mana", "不耗魔"), special.cost.text]
	elif heal.charges.text != str(p.slots.heal.charges) or heal.cost.text != "":
		err = "鑲著技能時 Q 藥水格應顯示剩 %d 瓶、不寫耗魔，實際「%s」「%s」" % [p.slots.heal.charges, heal.charges.text, heal.cost.text]
	if err == "":
		p.mana = cost - 1.0
		bar.refresh(w, p)
		if gem.icon.modulate.a >= 1.0:
			err = "魔力不夠放旋風斬時那格應變暗"
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
	for b: Button in [menu.single_button, menu.multi_button, menu.weapon_test_button, menu.anim_viewer_button]:
		if not _shown(b, menu):
			return "主選單首頁應看得到「%s」" % b.text
	var viewer_asks := [0]
	menu.anim_viewer_pressed.connect(func() -> void: viewer_asks[0] += 1)
	menu.anim_viewer_button.pressed.emit()
	if viewer_asks[0] != 1:
		return "按「動畫檢視器」應發出 anim_viewer_pressed（main.gd 重開成檢視器）"
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
	var pause_need: Vector2 = await _settled_min_size(hud._pause.get_child(0))   # 等畫面更新再量：剛顯示時拿到的是舊快取、偏小
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


# 遊玩紀錄的隊友誤傷：兩人世界 P1 揮劍真的打中 P2，P2 的紀錄寫「隊友（誤傷） · 武器名」，不出現內部代號 player；打的人自己的紀錄沒有
static func check_run_log_friendly() -> String:
	var w := World.new(&"test_arena")
	w.spawn_packs = false
	w.friendly_fire = true   # 大廳的誤傷開關（預設關）
	w.reset(7, [1, 2])
	w.spawner.finished = true
	_worlds.append(w)
	var p1: Player = w.players[1]
	var p2: Player = w.players[2]
	p1.pos = Vector2.ZERO
	p2.pos = Vector2(0, 1.2)
	var hit_log := RunLog.new()
	hit_log.me_id = p2.id
	var self_log := RunLog.new()
	self_log.me_id = p1.id
	for i in 30:
		var attack := InputCmd.new()
		attack.aim = Vector2(0, 5)
		attack.buttons = InputCmd.BTN_ATTACK
		var idle := InputCmd.new()
		idle.aim = Vector2(0, 5)
		w.step({1: attack, 2: idle}, Config.FIXED_DT)
		for e: Dictionary in w.events:
			hit_log.on_event(w, e.name, e)
			self_log.on_event(w, e.name, e)
	var text := hit_log.summary_text()
	var want := "%s · %s：" % [RunLog.NAMES[&"player"], p1.weapon.name]
	if hit_log.hits_taken == 0 or not text.contains(want) or text.contains("player"):
		return "被隊友打中應寫「%s」、不寫 player：%s" % [want, text]
	if self_log.hits_taken != 0:
		return "出招的人自己不應記到被打"
	return ""


# 你造成的傷害：左鍵、技能、觸發袋的道具效果、燃燒各記一項（名稱寫得出來），每一下都有來源（沒有「其他」），
# 合計 = 假人實際扣的血；僕從打的算召喚者的
static func check_run_log_dealt() -> String:
	var w := _new_world(5)
	var p := _player(w)
	p.loadout.equip_new(p, &"swordShield")
	p.pos = Vector2.ZERO
	p.facing = 0.0
	var dummies := SkillChecks._targets(w)
	var rl := RunLog.new()
	rl.me_id = p.id
	var feed := func() -> void:
		for e: Dictionary in w.events:
			rl.on_event(w, e.name, e)
		w.events.clear()
	if p.loadout.find_item(p.add_item(&"whirlwind")).get("where", -9) != 0:
		return "旋風斬應放進按鍵袋"
	var slot_cmd := _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.slot_bit(SkillChecks._slot_of(p, &"whirlwind")))
	for i in 100:
		var cmd := slot_cmd if i == 0 else _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK if i >= 30 and i < 70 else 0)
		_run(w, cmd, 1)
		feed.call()
	p.mana = p.max_mana()
	if not BagTriggers.run_effect(w, p, &"thunder_rune", dummies[0], 50.0):
		return "雷鳴符文的連鎖閃電應發動得了"
	feed.call()
	dummies[1].add_burn(p.id, 5.0, 2.0, 1, 1)
	for i in 150:
		_run(w, _cmd(Vector2.ZERO), 1)
		feed.call()
	var lost := 0.0
	for e in dummies:
		lost += e.max_hp - e.hp
	var weapon_key := "p|" + String(p.weapon.name)
	for key in [weapon_key, "k:whirlwind", "i:thunder_rune", "burn"]:
		if rl.by_credit.get(key, {}).get("damage", 0.0) <= 0.0:
			return "你造成的傷害應有「%s」：%s（旋風斬在第 %d 格、魔力 %.0f、狀態 %s）" % [key, rl.by_credit, SkillChecks._slot_of(p, &"whirlwind"), p.mana, p.action.current_name]
	if rl.by_credit.has("?"):
		return "每一下都應有來源，不應有「其他」：%s" % [rl.by_credit]
	if absf(rl.damage_dealt - lost) > 0.01:
		return "你造成的傷害合計 %.2f，假人實際扣 %.2f" % [rl.damage_dealt, lost]
	var text := "\n".join(PackedStringArray(rl.dealt_lines()))
	for want in ["你造成的傷害 %s：" % UiKit.dmg_text(lost), "左鍵（%s） " % p.weapon.name, "技能 %s " % ItemDefs.ITEMS.whirlwind.name, "%s " % ItemDefs.ITEMS.thunder_rune.name, "燃燒 "]:
		if not text.contains(want):
			return "結算的傷害來源缺「%s」：\n%s" % [want, text]
	# 僕從打的：事件帶 by = 召喚者，算進召喚者的紀錄
	rl.on_event(w, "entity:damaged", {"target_id": dummies[0].id, "source_id": p.id + 999, "by": p.id, "credit": "k:bone_guard", "amount": 12.0})
	if rl.by_credit.get("k:bone_guard", {}).get("damage", 0.0) != 12.0:
		return "僕從打的（by = 自己）應算自己的：%s" % [rl.by_credit]
	_note("你造成的傷害：\n" + text)
	return ""


# 遊玩紀錄的魔力與袋子：袋子裡的技能放出 / 魔力不夠各記一次、魔力見底的累計秒數、回報有袋子與魔力那兩行；
# 背包的「滿魔也放不出來」：照放的順序累加耗魔超過最大魔力的才算
static func check_run_log_mana() -> String:
	var w := _new_world(5)
	var p := _player(w)
	p.loadout.equip_new(p, &"swordShield")
	SkillChecks._targets(w)
	if p.loadout.find_item(p.add_item(&"whirlwind")).get("where", -9) != 0:
		return "旋風斬應放進按鍵袋"
	var bag: Dictionary = p.loadout.key_bags()[0]
	p.mana = p.max_mana()
	BagTriggers.run_bag(w, p, bag, null, 0.0)
	p.mana = 0.0
	BagTriggers.run_bag(w, p, bag, null, 0.0)
	var rec: Array = p.cast_log.get(&"whirlwind", [])
	if rec != [1, 1]:
		return "旋風斬應記放出 1、魔力不夠 1：%s" % [rec]
	var rl := RunLog.new()
	rl.me_id = p.id
	for i in 31:
		rl.track(w, i * 0.1)
	if absf(rl.mana_low_time - 3.0) > 0.05 or rl.mana_low_first != 0.0:
		return "魔力 0 追 3 秒應記見底 3 秒、第一次 0:00：%.2f / %.2f" % [rl.mana_low_time, rl.mana_low_first]
	var text := rl.report_text(w)
	for want in ["袋子：按鍵（%s）" % ItemDefs.ITEMS.whirlwind.name, "魔力：最大 %d" % roundi(p.max_mana()), "%s 1 / 1" % ItemDefs.ITEMS.whirlwind.name]:
		if not text.contains(want):
			return "回報缺「%s」：\n%s" % [want, text]
	if not InventoryPanel.starved_entries(p, bag).is_empty():
		return "最大魔力放得下旋風斬時不應標放不出來"
	p.set_stat_source(&"test_low", [[&"max_mana", Stats.MUL, 0.01]])
	var starved := InventoryPanel.starved_entries(p, bag)
	p.remove_stat_source(&"test_low")
	if starved.size() != 1 or starved[0].id != &"whirlwind":
		return "最大魔力比旋風斬耗魔少時應標它放不出來：%s" % [starved]
	return ""


# 遊玩紀錄的連線卡住時間點（另起一行）；客戶端換小關的事件比鏡像先到時，等鏡像換好才記那一關（地形不是上一關的）
static func check_run_log_net() -> String:
	var nt := RunLog.net_text({"role": "客戶端", "players": 2, "rtt_ms": [80], "snapshot_gap_max_ms": 1383,
		"stalls": [{"at": 268.0, "stage": "1-3", "what": "快照斷", "ms": 1383}, {"at": 300.0, "stage": "1-3", "what": "回應", "ms": 2367}], "stall_count": 5})
	if not nt.ends_with("\n  卡住的時間點：4:28 1-3 快照斷 1383 ms、5:00 1-3 回應 2367 ms…等共 5 次"):
		return "卡住的時間點那行不對：%s" % nt
	var w := _new_world(5)
	var rl := RunLog.new()
	rl.me_id = _player(w).id
	rl.on_event(w, "stage:started", {"floor": w.floor_num, "stage": w.stage_num + 1})
	if not rl.floors.is_empty():
		return "鏡像還在上一關時不應記下新的一關：%s" % [rl.floors]
	w.stage_num += 1
	rl.track(w, 1.0)
	if rl.floors.size() != 1 or rl.floors[0].stage != w.stage_num:
		return "鏡像換到 1-%d 後應記下那一關：%s" % [w.stage_num, rl.floors]
	return ""


# 遊玩紀錄的武器那一行與「來不及反應算看不見」：只用 RunLog（不建 HUD），事件直接餵
static func check_run_log_weapons_react() -> String:
	var w := _new_world(5)
	var p := _player(w)
	p.pos = Vector2.ZERO
	p.facing = 0.0   # 面向 +Z
	var rl := RunLog.new()
	rl.me_id = p.id
	w.stats.time = 30.0
	for e: Dictionary in [
			{"name": "weapon:dropped", "uid": "w1", "base": "swordShield", "rarity": "white", "pos": Vector2.ZERO},
			{"name": "weapon:dropped", "uid": "w2", "base": "dagger", "rarity": "blue", "pos": Vector2.ZERO},
			{"name": "weapon:added", "player_id": p.id, "uid": "w1", "slot": -1},
			{"name": "weapon:added", "player_id": p.id, "uid": "w0", "slot": 0},   # 不是殺怪掉的（開場、合成）不算
			{"name": "inventory:full", "player_id": p.id, "item": "dagger", "pickup_id": 7},
			{"name": "inventory:full", "player_id": p.id + 1, "item": "dagger", "pickup_id": 8}]:
		rl.on_event(w, e.name, e)
	if rl.weapon_drops != {&"white": 1, &"blue": 1} or rl.weapons_picked != 1 or rl.bag_full_at != 30.0:
		return "武器統計：掉落 %s、撿 %d、撿不下 %.1f（應 白 1 藍 1、1、30）" % [rl.weapon_drops, rl.weapons_picked, rl.bag_full_at]
	rl.track(w, 12.0)
	var line := rl.weapon_text()
	for want in ["武器掉落 2 把（普通 1 · 稀有 1）", "撿了 1 把", "背包 0:30 第一次撿不下", "現在的武器 0:12 換上"]:
		if not line.contains(want):
			return "武器那一行缺「%s」：%s" % [want, line]
	# 屍犬在背後 6（看不見）→ 撲進身邊 1.5（4 以內看得到）→ 0.2 秒後打中：算看不見；前方一直看得到的腐屍 1 秒後打中：看得到
	var dog := _spawn(w, &"hound", Vector2(0, -6))
	var zombie := _spawn(w, &"zombie", Vector2(0, 5))
	rl.track(w, 40.0)
	dog.pos = Vector2(0, -1.5)
	rl.track(w, 40.1)
	w.stats.time = 40.3
	rl.on_event(w, "entity:damaged", {"target_id": p.id, "source_id": dog.id, "source_kind": &"hound", "amount": 10.0})
	rl.track(w, 41.0)
	w.stats.time = 41.0
	rl.on_event(w, "entity:damaged", {"target_id": p.id, "source_id": zombie.id, "source_kind": &"zombie", "amount": 8.0})
	if rl.by_source.get(&"hound", {}).get("unseen", 0) != 1 or rl.by_source.get(&"zombie", {}).get("unseen", -1) != 0:
		return "從背後撲進來 %.1f 秒就打中應算看不見、一直看得到的不算：%s" % [0.2, rl.by_source]
	return ""


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
			"顯示卡：", "· 陰影關・光源開", "  陰影開・光源開：平均 63 FPS · 卡頓 0 次", "  陰影關・光源開：平均 8 FPS · 卡頓 1 次",
			"  卡頓的時間點：1:05 一般 120 ms"]:
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
	for id: StringName in SkillDefs.SKILLS:   # 傷害來源比顯示上限多：最長的名稱、併成「其他」那行都要塞得進
		rl._add_dealt(w, "k:" + String(id), 99999.0)
	rl._add_dealt(w, "p", 999999.0)
	hud._on_event("game:defeat", {"stats": w.stats.duplicate()})
	var box: Control = hud._game_over_log.get_parent()
	var need: Vector2 = box.get_combined_minimum_size()
	var screen := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	if need.y <= 0.0 or need.x > screen.x or need.y > screen.y:
		return "結算畫面需要 %s，超出 %s" % [need, screen]
	_note("結算畫面最多行時需要 %.0f × %.0f（畫面 %.0f × %.0f）" % [need.x, need.y, screen.x, screen.y])
	hud._on_event("game:restart", {})
	if rl.hits_taken != 0 or rl.damage_dealt != 0.0 or not rl.by_credit.is_empty() or not rl.kills.is_empty() or not rl.downs.is_empty() or rl.frames != 0 or rl.result != "" or not rl.by_video.is_empty() or not rl.weapon_drops.is_empty() or rl.bag_full_at >= 0.0 or not rl.hitch_list.is_empty():
		return "game:restart 後遊玩紀錄應清空"
	# 卡頓記時間點與當時在做什麼：換小關 / 換層 / 開局後 1 秒內算那一下，其他算一般；每層那行不重複小關編號
	var rl2 := RunLog.new()
	var layout := MapDefs.layout_text({"stage": 2, "themes": [[&"open"], [&"tombs", &"ruins"]]})
	rl2.floors.append({"floor": 1, "stage": 1, "map": "墓園", "start": 0.0, "event_start": -1.0, "event_open": -1.0, "layout": ""})
	rl2.add_frame(0.08, 0.2)
	rl2.add_frame(0.08, 30.0)
	rl2.floors.append({"floor": 1, "stage": 2, "map": "墓園", "start": 100.0, "event_start": -1.0, "event_open": -1.0, "layout": layout})
	rl2.add_frame(0.19, 100.1)
	rl2.add_frame(0.016, 100.2)
	rl2.floors.append({"floor": 2, "stage": 0, "map": "墓窟", "start": 200.0, "event_start": -1.0, "event_open": -1.0, "layout": ""})
	rl2.add_frame(0.09, 200.05)
	var want_hitch := "卡頓的時間點：0:00 開局 80 ms、0:30 一般 80 ms、1:40 換小關 190 ms、3:20 換層 90 ms"
	if rl2.hitches != 4 or rl2.hitch_text() != want_hitch:
		return "卡頓的時間點不對（%d 次）：%s" % [rl2.hitches, rl2.hitch_text()]
	var stage_line: String = rl2.floors_text(150.0)[1]
	if stage_line != "1-2 墓園 1:40 空地、墓碑林＋教堂廢墟":
		return "每層那行不該重複小關編號：%s" % stage_line
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
	var want: Array[String] = ["player", "chest:small", "chest:big", "coin", "projectile:arrow", "projectile:orb", "forge", "torch", "relic:item", "relic:skill",
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
	for path in ["res://ui/hud.gd", "res://ui/world_labels.gd", "res://ui/floaters.gd", "res://ui/net_panel.gd", "res://ui/main_menu.gd", "res://ui/player_tags.gd", "res://ui/inventory_panel.gd", "res://ui/run_log.gd", "res://ui/settings_panel.gd", "res://ui/ui_kit.gd"]:
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
	# 淡入淡出中換武器（隊友在視野外換了武器再走回來）：舊武器的網格刪掉後再淡、還原都不能碰到它，新武器也要跟著淡
	# 網頁版對已刪掉的物件做 as 轉型直接當掉（2026-10-31 房主兩次），這裡用 Fade 有沒有回報錯誤與新武器的透明度判斷
	if err == "":
		var rig := DarkFantasy.player_character(p.class_id)
		rig.set_weapon(&"longsword")
		Fade.apply(rig, 0.5)
		var old_weapon := rig.weapon_main
		rig.set_weapon(&"staff")
		old_weapon.free()   # set_weapon 是 queue_free（幀尾才刪），直接刪掉模擬下一幀
		Fade.apply(rig, 0.25)
		var staff_alpha := -1.0
		for mi in PartKit.mesh_instances(rig.weapon_main):
			var m := mi.material_override
			if m is ShaderMaterial:
				staff_alpha = ((m as ShaderMaterial).next_pass as BaseMaterial3D).albedo_color.a
			break
		if not is_equal_approx(staff_alpha, Fade.level_of(0.25) / float(Fade.LEVELS)):
			err = "淡入淡出中換武器：新武器應跟著淡（透明度 %.2f，實際 %.2f）" % [Fade.level_of(0.25) / float(Fade.LEVELS), staff_alpha]
		Fade.apply(rig, 1.0)
		if err == "" and Fade.is_fading(rig):
			err = "淡入淡出中換武器：完全顯示後應還原"
		rig.free()
	# 連線時本機選過、等隊友選完的遺物：看得到時也維持半透明（relic_taken_alpha）；只有隊友選過的照常不透明
	if err == "":
		var relic := w.drop_relic(&"small", p.pos + MathUtil.dir_from_angle(p.facing) * 2.0)
		relic.taken[World.HOST_PEER_ID + 1] = true
		w.tick += 1
		for i in 8:
			view.sync(w, 1.0, 0.05)
		var rn: Node3D = view._nodes[relic.id]
		if not rn.visible or Fade.is_fading(rn):
			err = "只有隊友選過的遺物在本機應照常不透明（顯示 %s、淡入淡出中 %s）" % [rn.visible, Fade.is_fading(rn)]
		else:
			relic.taken[World.HOST_PEER_ID] = true
			for i in 8:
				view.sync(w, 1.0, 0.05)
			var want := Fade.level_of(Config.VISION.relic_taken_alpha) / float(Fade.LEVELS)
			if not rn.visible or not is_equal_approx(_fade_alpha(rn), want):
				err = "本機選過的遺物應半透明 %.2f（實際顯示 %s、透明度 %.2f）" % [want, rn.visible, _fade_alpha(rn)]
	if err == "":
		p.is_dead = true
		view.sync(w, 1.0, 0.016)
		if not front_node.visible or _fade_alpha(front_node) != 1.0:
			err = "本機角色陣亡後應立刻全部看得到（不淡入）"
	view.free()
	return err


# 留在地上的特效（聖光圈、腐氣、蜘蛛網）在背後放的也建立、先藏著，轉身看到時顯示；短的預警圈在背後照樣不畫
static func check_lingering_fx() -> String:
	var w := _new_world()
	var p := _player(w)
	p.facing = 0.0
	var view := WorldView.new()
	view.sync(w, 1.0, 0.016)
	var fx := view.effects
	var err := ""
	var before := fx._transients.size()
	view.on_event("fx:telegraph", {"pos": Vector2(0, -8), "height": 0.0, "radius": 1.0, "color": Color.WHITE, "life": WorldView.LINGER_MIN * 0.5})
	if fx._transients.size() != before:
		err = "背後的短預警圈不應畫"
	var made: Array = []
	if err == "":
		view.on_event("fx:telegraph", {"pos": Vector2(0, -12), "height": 0.0, "radius": 4.0, "color": Color.WHITE, "life": WorldView.LINGER_MIN * 4.0, "fill": true})
		made = fx._transients.slice(before)
		if made.is_empty() or made.any(func(t: Dictionary) -> bool: return t.node.visible):
			err = "背後放的聖光圈應建立但藏著：%d 個零件、顯示 %s" % [made.size(), made.map(func(t: Dictionary) -> bool: return t.node.visible)]
	if err == "":
		p.facing = PI
		w.tick += 1
		view.sync(w, 1.0, 0.1)
		if made.any(func(t: Dictionary) -> bool: return not t.node.visible):
			err = "轉身看到後聖光圈應顯示"
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
	if err == "":
		err = _check_mana_bar(hb, p)
	if err == "":
		err = _check_reload_ring(hb, p)
	if err == "":
		err = _check_bar_follows_model(hb, rare)
	hb.free()
	cam.free()
	return err


# 血條畫在模型的位置（WorldView.render_pos，同 sync 的補間）：上一步在旁邊 2 格、補間一半時，血條的中心在兩者正中間，不在模擬位置
static func _check_bar_follows_model(hb: HealthBars, e: Entity) -> String:
	var saved_prev := e.prev_pos
	e.prev_pos = e.pos + Vector2(2, 0)
	WorldView.render_alpha = 0.5
	var want: Vector2 = hb._screen(WorldView.render_pos(e, e.body_height + WorldLabels.ENEMY_OFFSET))
	var sim: Vector2 = hb._screen(Vector3(e.pos.x, e.height + e.body_height + WorldLabels.ENEMY_OFFSET, e.pos.y))
	var bar := hb.bars().filter(func(b: Dictionary) -> bool: return b.entity == e)
	WorldView.render_alpha = 1.0
	e.prev_pos = saved_prev
	if bar.is_empty():
		return "補間檢查：稀有怪沒有血條"
	var x: float = (bar[0].rect as Rect2).get_center().x
	if absf(x - want.x) > 0.5 or absf(want.x - sim.x) < 1.0:
		return "血條中心 x %.1f 應跟著模型的補間位置 %.1f（模擬位置 %.1f）" % [x, want.x, sim.x]
	return ""


# 自己頭上的魔力條：比例 = 魔力 / 上限、滿了不畫；在血條正下方不重疊（血條滿血不畫時位置一樣）；倒地不畫
static func _check_mana_bar(hb: HealthBars, p: Player) -> String:
	p.mana = p.max_mana()
	if not hb.mana_bar().is_empty():
		return "魔力滿時不應畫魔力條：%s" % [hb.mana_bar()]
	p.mana = p.max_mana() * 0.4
	var m := hb.mana_bar()
	if absf(m.ratio - 0.4) > EPS or not (m.rect as Rect2).size.is_equal_approx(hb.MANA_SIZE):
		return "魔力條比例 %.3f、尺寸 %s（應為 0.400、%s）" % [m.ratio, m.rect.size, hb.MANA_SIZE]
	var hp_rect: Rect2 = hb.bars().filter(func(b: Dictionary) -> bool: return b.entity == p)[0].rect
	if m.rect.position.y < hp_rect.end.y + 1.0 or absf(m.rect.get_center().x - hp_rect.get_center().x) > 0.5:
		return "魔力條應在血條正下方：血條 %s、魔力條 %s" % [hp_rect, m.rect]
	p.hp = p.max_hp
	if not (hb.mana_bar().rect as Rect2).is_equal_approx(m.rect):
		return "滿血（血條不畫）時魔力條的位置不應跳動"
	p.is_downed = true
	var down := hb.mana_bar()
	p.is_downed = false
	if not down.is_empty():
		return "倒地時不應畫魔力條"
	return ""


# 自己的弓裝填圓圈：只在有箭袋的弓裝填中畫、比例 = 已裝的時間 / 裝填時間、在血條右邊不重疊；倒地不畫
static func _check_reload_ring(hb: HealthBars, p: Player) -> String:
	p.equip_weapon(&"shortbow")
	if not hb.reload_ring().is_empty():
		return "沒在裝填不應畫裝填圓圈"
	var atk: Dictionary = p.weapon.attack
	p.reload_timer = atk.reload_time * 0.25
	var r := hb.reload_ring()
	if r.is_empty() or absf(r.ratio - 0.75) > EPS:
		return "裝填剩 25%% 時圓圈應畫 0.75：%s" % [r]
	p.hp = p.max_hp * 0.5
	var hp_rect: Rect2 = hb.bars().filter(func(b: Dictionary) -> bool: return b.entity == p)[0].rect
	if r.center.x - hb.RING_RADIUS < hp_rect.end.x + 1.0 or absf(r.center.y - hp_rect.get_center().y) > 0.5:
		return "裝填圓圈應在血條右邊：血條 %s、圓心 %s" % [hp_rect, r.center]
	p.is_downed = true
	var down := hb.reload_ring()
	p.is_downed = false
	p.reload_timer = 0.0
	if not down.is_empty():
		return "倒地時不應畫裝填圓圈"
	return ""


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


# 每一種實體類別（繼承 Entity、沒有子類別的 class_name；之後新增的也算）都要在開場預熱建出模型、掛上剪影，
# 網格的材質都寫模板值（沒寫的話剪影會整片蓋在自己身上）；不要剪影的列在 WorldView.XRAY_EXEMPT 並寫原因
static func check_xray_every_entity() -> String:
	var base_of := {}
	for c: Dictionary in ProjectSettings.get_global_class_list():
		base_of[c["class"]] = c["base"]
	var has_child := {}
	for k: StringName in base_of:
		has_child[base_of[k]] = true
	var leaves: Array[StringName] = []
	for k: StringName in base_of:
		var b: StringName = k
		while base_of.has(b) and b != &"Entity":
			b = base_of[b]
		if b == &"Entity" and k != &"Entity" and not has_child.has(k):
			leaves.append(k)
	var view := WorldView.new()
	_scene_root().add_child(view)
	view.warm_up(Vector3(20, 0, -15))
	var err := ""
	for k in leaves:
		if not view.warm_classes.has(k) and not WorldView.XRAY_EXEMPT.has(k):
			err = "實體類別 %s 沒有在開場預熱建模型（WorldView.warm_up），也沒列在 XRAY_EXEMPT：新種類要加進預熱，才驗得到剪影、也不會第一次出現時卡頓" % k
			break
	if err == "":
		for i in view._warm_nodes.size():
			var node: Node3D = view._warm_nodes[i]
			if view.warm_keys[i].begins_with("fade:"):
				continue
			if not node.has_meta(&"xray"):
				err = "%s 的模型沒有剪影" % view.warm_keys[i]
				break
			var bad := _xray_unwritten(node)
			if bad != "":
				err = "%s 的網格 %s 沒有寫模板值（材質要從共用的工廠拿：_flat_material / _glow_material / PartKit.mat）" % [view.warm_keys[i], bad]
				break
	_note("實體類別 %d 種：%s" % [leaves.size(), leaves])
	view.queue_free()
	return err


# node 底下（跳過 XRAY_SKIP）第一個沒寫模板值的網格名稱；都有寫回傳空字串
static func _xray_unwritten(node: Node) -> String:
	for child in node.get_children():
		if WorldView.XRAY_SKIP.has(child.name):
			continue
		if child is MeshInstance3D:
			var m := (child as MeshInstance3D).material_override as BaseMaterial3D
			if m == null or m.stencil_mode != BaseMaterial3D.STENCIL_MODE_CUSTOM:
				return String(child.name)
		var deeper := _xray_unwritten(child)
		if deeper != "":
			return deeper
	return ""


# 每層出口的外觀（EventDefs.EXIT_STYLES）：第 1 層土堆 + 墓碑；換到第 2 層整個換成石棺，棺蓋跟著進度往旁邊滑開，打開後棺口有洞與出口環；
# 第 3 層換成巨繭（_check_cocoon_look）
# 換關過場（ui/level_transition.gd）：收圈在模擬換關（LEAVE.cover 秒）之前就全黑；地形沒換就一直黑著、不顯示卡片；
# 換了才出卡片（關卡名、基礎難度、門的獎勵、這關有鐵砧），至少停 HOLD 秒再打開；地形一直沒換 GIVE_UP 秒後也會打開
static func check_level_transition() -> String:
	var w := World.new(&"test_arena")
	_worlds.append(w)
	w.run_seed = 7
	w.floor_num = 1
	w.stage_num = 2
	w.load_map(&"graveyard")
	var lt := LevelTransition.new()
	lt.size = Vector2(1920, 1080)
	var dt := 1.0 / 60.0
	var center := Vector2(1200, 500)
	lt.start(EventDefs.LEAVE.cover, w)
	var t := 0.0
	while t < EventDefs.LEAVE.cover - dt * 1.5:
		lt.update(dt, w, center)
		t += dt
	if not lt.is_black():
		lt.free()
		return "模擬換關（%.2f 秒）之前畫面應已全黑（%.2f 秒時還沒）" % [EventDefs.LEAVE.cover, t]
	for i in 60:
		lt.update(dt, w, center)
	if not lt.is_black() or lt.card_text() != "":
		lt.free()
		return "地形還沒換應一直黑著、不顯示卡片"
	w.next_stage(&"skill")   # 1-2 → 1-3：門的獎勵是技能、1-3 有鐵砧
	lt.set_card(w, w.floor_num, w.stage_num, roundi(w.base_difficulty), "skill")
	lt.update(dt, w, center)
	var want := "1-3 墓園\n基礎難度 %d\n獲得：技能\n這關有鐵砧" % roundi(w.base_difficulty)
	if lt.card_text() != want or not w.map.has("anvil"):
		var got := lt.card_text()
		lt.free()
		return "卡片應寫「%s」，實際「%s」" % [want.replace("\n", " / "), got.replace("\n", " / ")]
	t = dt
	while t < LevelTransition.HOLD - dt * 1.5:
		lt.update(dt, w, center)
		t += dt
	if not lt.is_black():
		lt.free()
		return "卡片應至少停 %.2f 秒" % LevelTransition.HOLD
	for i in ceili((LevelTransition.OPEN + 0.1) / dt) + 2:
		lt.update(dt, w, center)
	if lt.is_active() or lt.visible:
		lt.free()
		return "打開後過場應結束"
	lt.start(EventDefs.LEAVE.cover, w)   # 地形一直沒換（例如連線斷了）
	for i in ceili((EventDefs.LEAVE.cover + LevelTransition.GIVE_UP + LevelTransition.OPEN + 0.2) / dt):
		lt.update(dt, w, center)
	var stuck := lt.is_active()
	lt.free()
	if stuck:
		return "地形沒換 %.1f 秒後也應打開" % LevelTransition.GIVE_UP
	return ""


static func check_exit_looks() -> String:
	for f: int in EventDefs.EXIT_STYLES:
		for key in ["look", "idle", "hold", "doing", "bar", "started", "opened"]:
			if not EventDefs.exit_style(f).has(key):
				return "第 %d 層的出口文字少了 %s" % [f, key]
	var w := _new_world(3, false, &"graveyard_a")
	var view := WorldView.new()
	view.sync(w, 1.0, 0.016)
	var err := ""
	if view._grave == null or view._grave.get_node_or_null(^"Mound") == null:
		err = "第 1 層的出口應是土堆"
	else:
		w.next_floor()
		view.sync(w, 1.0, 0.016)
		var lid: Node3D = view._grave.get_node_or_null(^"Lid")
		if lid == null or view._grave.get_node_or_null(^"Mound") != null:
			err = "第 2 層的出口應換成石棺（看外觀 %s）" % view._grave_look
		else:
			var x0 := lid.position.x
			w.event.state = DigEvent.ACTIVE
			w.event.progress = 0.5
			view.sync(w, 1.0, 0.016)
			var x1 := lid.position.x
			w.event.state = DigEvent.OPEN
			w.event.progress = 1.0
			view.sync(w, 1.0, 0.016)
			if not (x1 > x0 + 0.1 and lid.position.x > x1 + 0.1):
				err = "棺蓋應跟著進度滑開：0 → %.2f、50%% → %.2f、打開 → %.2f" % [x0, x1, lid.position.x]
			elif not (view._grave.get_node(^"Hole") as Node3D).visible or not (view._grave.get_node(^"ExitRing") as Node3D).visible:
				err = "石棺打開後應看得到洞與出口環"
			else:
				err = _check_cocoon_look(w, view)
	view.free()
	return err


# 第 3 層的出口換成巨繭：兩半繭殼跟著進度往兩邊剝開，打開後裂口的光收掉、地上有洞與出口環
static func _check_cocoon_look(w: World, view: WorldView) -> String:
	w.next_floor()
	view.sync(w, 1.0, 0.016)
	var left: Node3D = view._grave.get_node_or_null(^"ShellL")
	var right: Node3D = view._grave.get_node_or_null(^"ShellR")
	if left == null or right == null or view._grave.get_node_or_null(^"Lid") != null:
		return "第 3 層的出口應換成巨繭（看外觀 %s）" % view._grave_look
	var gap0 := right.position.x - left.position.x
	w.event.state = DigEvent.ACTIVE
	w.event.progress = 0.5
	view.sync(w, 1.0, 0.016)
	var gap1 := right.position.x - left.position.x
	w.event.state = DigEvent.OPEN
	w.event.progress = 1.0
	view.sync(w, 1.0, 0.016)
	var gap2 := right.position.x - left.position.x
	if not (gap1 > gap0 + 0.1 and gap2 > gap1 + 0.1) or absf(left.position.x + right.position.x) > 0.001:
		return "繭殼應跟著進度往兩邊對稱剝開：0 → %.2f、50%% → %.2f、打開 → %.2f" % [gap0, gap1, gap2]
	if (view._grave.get_node(^"Slit") as Node3D).visible or not (view._grave.get_node(^"Hole") as Node3D).visible \
			or not (view._grave.get_node(^"ExitRing") as Node3D).visible:
		return "巨繭打開後裂口的光應收掉、看得到洞與出口環"
	return ""


# 牆後的寶箱是金色剪影、鍛造祭壇是灰白剪影；同種寶箱共用材質；空地上的沒有剪影
static func check_object_xray() -> String:
	var w := _new_world(3, false, &"graveyard_a")
	var p := _player(w)
	# 同 check_xray：王族墓南牆北邊，玩家在 y 57 面向南，牆邊 y 60.6 和相機之間有牆
	p.pos = MapDefs.to_world(w.map, Vector2(48, 57))
	p.facing = 0.0
	var chest := Chest.new(w, &"small", MapDefs.to_world(w.map, Vector2(48, 60.6)))
	w.add_entity(chest)
	var forge := Forge.new(w, MapDefs.to_world(w.map, Vector2(49.5, 60.6)))
	w.add_entity(forge)
	var open_chest := Chest.new(w, &"small", MapDefs.to_world(w.map, Vector2(46, 55)))
	w.add_entity(open_chest)
	var view := WorldView.new()
	var overlay := func(node: Node3D) -> Material:
		for mi in PartKit.mesh_instances(node):
			if mi.material_overlay != null:
				return mi.material_overlay
		return null
	view.sync(w, 1.0, 0.016)
	var cn: Node3D = view._nodes[chest.id]
	var fn: Node3D = view._nodes[forge.id]
	var on: Node3D = view._nodes[open_chest.id]
	var err := ""
	if overlay.call(cn) != WorldView.xray_material(WorldView.XRAY_LOOT):
		err = "牆後的寶箱應有金色剪影：判斷 %s、疊加材質 %s" % [view._xray_needed(w, chest), overlay.call(cn)]
	elif overlay.call(fn) != WorldView.xray_material(WorldView.XRAY_OBJECT):
		err = "牆後的鍛造祭壇應有灰白剪影：判斷 %s、疊加材質 %s" % [view._xray_needed(w, forge), overlay.call(fn)]
	elif overlay.call(on) != null:
		err = "空地上的寶箱不應有剪影"
	else:
		# 直接建兩個模型比（同步出來的剛進視野、正在淡入，材質換成半透明的那一份）
		var x := view._create_view(chest)
		var y := view._create_view(open_chest)
		var drawn := func(mi: MeshInstance3D) -> bool: return not WorldView.XRAY_SKIP.has(mi.name)   # 碰撞圈（F2）不寫模板值、不必共用
		var a: Array = PartKit.mesh_instances(x).filter(drawn).map(func(mi: MeshInstance3D) -> Material: return mi.material_override)
		var b: Array = PartKit.mesh_instances(y).filter(drawn).map(func(mi: MeshInstance3D) -> Material: return mi.material_override)
		if a != b:
			err = "同種寶箱應共用材質（寫模板值的材質各一份，網頁版每份都要編一次著色器）"
		x.free()
		y.free()
	view.free()
	return err


static func check_hints() -> String:
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
	# 腳邊有東西：跳「按住 Alt 看詳細」；名稱旁的提示只在按得到 F、沒按 Alt 時出現（按住 Alt 才畫說明卡）
	w.drop_item(&"whetstone", p.pos + Vector2(1.0, 0))
	tick.call(10.0)
	if shown[-1] != &"ground_info":
		h.free()
		return "腳邊有東西應跳 ground_info：%s" % [shown]
	var texts := [WorldLabels.pickup_text("磨刀石", false, false), WorldLabels.pickup_text("磨刀石", true, false), WorldLabels.pickup_text("磨刀石", true, true)]
	if texts != ["磨刀石", "[F] 撿起 磨刀石  [Alt] 詳細", "[F] 撿起 磨刀石"]:
		h.free()
		return "地上道具的名稱：不在腳邊只有名稱、在腳邊加 [F] 與 [Alt] 詳細、按住 Alt 不再提示：%s" % [texts]
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
	# 弧光照每一下的動作：劍 1、2 斜、3 直；權杖第 2 下往下砸是直的；匕首刺是窄的
	var tilts: Array = slashes.map(func(e: Dictionary) -> float: return e.get("tilt", 0.0))
	if not (tilts[0] < -0.3 and tilts[1] < -0.3 and absf(tilts[2] + PI / 2.0) < 0.01):
		return "劍的三段弧光應是斜、斜、直：傾斜 %s" % [tilts]
	for spec: Array in [[&"scepter", 2, 1, true], [&"dagger", 5, 0, false]]:
		var ws := _new_world()
		_spawn(ws, &"grunt", Vector2(0, 1.5))
		_player(ws).equip_weapon(spec[0])
		var evs: Array[Dictionary] = []
		for i in spec[1]:
			_run_collect(ws, _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_ATTACK), 1, evs)
			_run_collect(ws, _cmd(Vector2.ZERO), 30, evs)
		var sl := _named(evs, "fx:slash")
		var arc0: float = WeaponDefs.WEAPONS[spec[0]].attack.arc
		if spec[3]:
			if sl.size() != spec[1]:
				return "權杖連段應發出 %d 次 fx:slash：%d" % [spec[1], sl.size()]
			if absf(sl[-1].get("tilt", 0.0) + PI / 2.0) > 0.01:
				return "權杖第 2 下往下砸，弧光應是直的：傾斜 %.2f" % sl[-1].get("tilt", 0.0)
		elif sl.is_empty() or sl.any(func(e: Dictionary) -> bool: return e.arc > arc0 * 0.5):
			return "匕首刺的弧光應是窄的（判定 %.2f）：%s" % [arc0, sl.map(func(e: Dictionary) -> float: return e.arc)]
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
	for name in ["fx:slash", "fx:muzzle", "fx:fizzle", "fx:explosion", "fx:boss_slam", "entity:damaged"]:
		if _named(events, name).is_empty():
			return "應發出 %s" % name
	if not _named(events, "fx:telegraph").is_empty():
		return "法杖奧術爆裂不應畫落點圈"
	events.append({"name": "fx:erupt_warn", "pos": Vector2(0, 8), "height": 0.0, "radius": 2.5, "life": 1.0})
	events.append({"name": "fx:erupt_warn", "pos": Vector2(0, 8), "height": 0.0, "radius": 2.5, "life": 1.0, "look": &"sarcophagus"})
	events.append({"name": "fx:erupt_warn", "pos": Vector2(0, 8), "height": 0.0, "radius": 2.5, "life": 1.0, "look": &"cocoon"})
	events.append({"name": "fx:boss_teleport_warn", "pos": Vector2(0, 8), "height": 0.0, "life": 0.6})
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


# 怪物攻擊不畫預警圈：sim/ 裡只有玩家方的道具與地面持續區（聖光圈）可以發 fx:telegraph；
# 怪物（Boss 瞬移、死亡爆炸詞條、挖墳點噴怪）與法杖落點各自檢查不發
const TELEGRAPH_ALLOWED := ["item_effects.gd", "ground_zones.gd", "skill_behaviors.gd"]   # 都是玩家方的（技能的落點）

static func check_no_monster_telegraph() -> String:
	for path in _list_gd("res://sim"):
		if path.get_file() in TELEGRAPH_ALLOWED:
			continue
		if _read_text(path).contains("\"fx:telegraph\""):
			return "%s 發出 fx:telegraph：怪物攻擊不畫預警圈（只允許 %s）" % [path, TELEGRAPH_ALLOWED]
	return ""


# Boss 每一招的預備動作兩兩不同：各招預備到一半時，手臂（前後、張開）、身體前後傾、頭的角度合計至少差 MIN_POSE_DIFF 弧度
# 亡骸騎士：砸地、衝鋒、召喚、直劈；守墓人：鐵鏟揮擊、瘋狂鏟土、提燈噴火、口哨、鏟起；墓園狼人（守墓人 form 1）：三連爪、飛撲、狼嚎
const MIN_POSE_DIFF := 1.0
const BOSS_MOVES := {   # 模型 -> [種類, 型態, 招式資料所在（"" = 種類的最上層）, 招式]
	&"boss": [&"boss", 0, "", [&"slam", &"charge", &"summon", &"cleave"]],
	&"gravekeeper": [&"gravekeeper", 0, "", [&"shovel", &"dig", &"lantern", &"whistle", &"scoop"]],
	&"werewolf": [&"gravekeeper", 1, "wolf", [&"claw", &"leap", &"howl"]],
}

static func check_boss_windup_poses() -> String:
	for model: StringName in BOSS_MOVES:
		var fail := _check_windup_poses(model, BOSS_MOVES[model])
		if fail != "":
			return fail
	return ""


static func _check_windup_poses(model: StringName, spec: Array) -> String:
	var type: StringName = spec[0]
	var b_def: Dictionary = EnemyDefs.ENEMIES[type]
	var move_defs: Dictionary = b_def if spec[2] == "" else b_def[spec[2]]
	var poses := {}
	for move: StringName in spec[3]:
		var w := _new_world()
		var p := _player(w)
		p.pos = Vector2(0, 7)
		var boss := _spawn(w, type, Vector2.ZERO)
		if spec[1] > 0:
			(boss as Gravekeeper).form = spec[1]
		var rig := DarkFantasy.character(model)
		var anim := EnemyAnimator.new(rig, boss)
		_run(w, _cmd(Vector2.ZERO), roundi(b_def.spawn_time / DT) + 2)
		boss.fsm.change(move)
		var windup: float = move_defs[move].windup
		for i in roundi(windup * 0.5 / DT):
			p.hp = p.max_hp
			_run(w, _cmd(Vector2.ZERO), 1)
			anim.update(boss, DT)
		if boss.anim.state != move:
			rig.free()
			return "%s 預備到一半時狀態變成 %s" % [move, boss.anim.state]
		poses[move] = [rig.arm_r.rotation.x, rig.arm_l.rotation.x, rig.arm_r.rotation.y, rig.arm_l.rotation.y,
			rig.body.rotation.x, rig.head.rotation.x]
		rig.free()
	var moves: Array = poses.keys()
	for i in moves.size():
		for j in range(i + 1, moves.size()):
			var a: Array = poses[moves[i]]
			var b: Array = poses[moves[j]]
			var diff := 0.0
			for k in a.size():
				diff += absf(a[k] - b[k])
			if diff < MIN_POSE_DIFF:
				return "%s 的 %s 和 %s 預備動作太像：關節角度合計只差 %.2f（至少 %.1f）" % [model, moves[i], moves[j], diff, MIN_POSE_DIFF]
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


# 守墓人噴火的火舌：追著噴時是 lantern.range × arc 的扇形、轉圈時是 spin_range 一整圈、鏟起連段 B 直噴是 bury.range × arc，跟著朝向；
# 噴的時候有噴流粒子；噴完（recovery）就拿掉；開場預熱有畫過火舌的材質
static func check_flame_fx() -> String:
	var setup := MonsterChecks._keeper_world(4.0)
	var w: World = setup[0]
	var p: Player = setup[1]
	var k: Gravekeeper = setup[2]
	var f: Dictionary = k.def.lantern
	var view := Effects.new()
	_scene_root().add_child(view)
	view.warm_up(Vector3.ZERO)
	var warmed := view.get_children().any(func(n: Node) -> bool: return n is MeshInstance3D and (n as MeshInstance3D).material_override == view._flame_mat)
	var err := "" if warmed else "開場預熱沒有畫火舌的材質"
	k.fsm.change(&"lantern")
	var seen := {}
	var jet_before := view.spawned_total
	for i in roundi((f.windup + f.duration + f.spin_windup + f.spin_time + f.recovery) / DT) + 5:
		if err != "":
			break
		p.hp = p.max_hp
		w.step({World.HOST_PEER_ID: InputCmd.new()}, DT)
		view.sync(w, DT)
		var phase: StringName = k.fsm.data.get("phase", &"") if k.fsm.is_in(&"lantern") else &""
		var node: MeshInstance3D = view._flames.get(k.id)
		match phase:
			&"flame":
				if node == null or node.mesh != view._flame_mesh(f.range, f.arc) or absf(angle_difference(node.rotation.y, k.facing)) > 1e-3:
					err = "追著噴時應有 %.1f × %.0f° 的火舌、跟著朝向" % [f.range, rad_to_deg(f.arc)]
			&"spin":
				if node == null or node.mesh != view._flame_mesh(f.spin_range, TAU):
					err = "轉圈時應有半徑 %.1f 的一整圈火舌" % f.spin_range
			&"windup", &"spin_windup":
				if node != null:
					err = "%s（預備）時不應有火舌" % phase
			_:
				if node != null and not k.fsm.is_in(&"lantern"):
					err = "噴完應拿掉火舌"
		seen[phase] = true
	var jets := view.spawned_total - jet_before
	if err == "" and (not seen.has(&"flame") or not seen.has(&"spin")):
		err = "沒有跑到追著噴與轉圈：%s" % [seen.keys()]
	if err == "" and jets < roundi((f.duration + f.spin_time) * Effects.FLAME_JET * Effects.STEPS_PER_SECOND * 0.9):
		err = "噴火期間噴流粒子太少：%d 顆" % jets
	# 鏟起連段 B 的直噴：畫面只看動畫欄位
	var b: Dictionary = k.def.scoop.bury
	k.fsm.change(&"chase")
	view.sync(w, DT)
	k.anim = {"state": &"scoop", "phase": &"bury", "phase_time": b.step_time + b.open + b.flame * 0.5}
	view.sync(w, DT)
	if err == "" and (not view._flames.has(k.id) or (view._flames[k.id] as MeshInstance3D).mesh != view._flame_mesh(b.range, b.arc)):
		err = "鏟起連段 B 直噴時應有 %.1f × %.0f° 的火舌" % [b.range, rad_to_deg(b.arc)]
	view.queue_free()
	if err == "":
		_note("噴火特效：噴流粒子 %d 顆（%.1f 秒）" % [jets, f.duration + f.spin_time])
	return err


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
		texts.append_array([w.name, w.special.name, w.special.icon, w.special.get("desc", "")])
		for kind: String in ["attack"]:
			if w.has(kind):
				texts.append_array([w[kind].name, w[kind].icon, w[kind].get("desc", "")])
		for alt: Dictionary in [w.get("stance", {}), w.get("grab", {})]:
			for kind: String in ["attack", "special"]:   # 火把舉著時只換左鍵
				if alt.has(kind):
					texts.append_array([alt[kind].name, alt[kind].icon, alt[kind].get("desc", "")])
	for c: Dictionary in ClassDefs.CLASSES.values():
		texts.append_array([c.name, c.pitch, c.passive.desc])
	for c: Dictionary in ClassDefs.PLACEHOLDERS.values():
		texts.append_array([c.name, c.unlock])
	for s: Dictionary in SkillDefs.SKILLS.values():
		texts.append_array([s.get("name", ""), s.icon, s.get("desc", "")])
	for id: StringName in SkillDefs.gem_skill_ids():   # 技能的名稱與說明在物品資料；技能欄、遺物卡片的那一行
		texts.append_array([ItemDefs.ITEMS[id].name, ItemDefs.ITEMS[id].desc, UiKit.skill_line(id), UiKit.skill_damage_line(id), UiKit.skill_upgrade_line(id, 1)])
	var hud_consts: Dictionary = load("res://ui/hud.gd").get_script_constant_map()
	texts.append_array([hud_consts.CONTROLS_TEXT, hud_consts.BOSS_NAME])
	for s: Dictionary in StatDefs.STATS.values():
		texts.append(s.name)
	for g: Dictionary in StatDefs.PANEL_GROUPS:
		texts.append(g.name)
	for id: StringName in ItemDefs.ITEMS:
		texts.append_array([ItemDefs.ITEMS[id].name, ItemDefs.ITEMS[id].desc, "獲得 ", UiKit.effect_damage_line(id)])
	texts.append(StatDefs.format_value(&"armor", 8.0) + StatDefs.format_value(&"hp_regen", 1.0))
	# HUD 程式裡的字串常值（標題、橫幅、結算、按鍵名稱）
	var re := RegEx.create_from_string("\"([^\"\\\\]*)\"")
	for path in ["res://ui/hud.gd", "res://ui/skill_bar.gd", "res://ui/stats_panel.gd", "res://ui/class_select.gd", "res://ui/inventory_panel.gd"]:
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
		var expect: String = sound_script.SKILL_CUES.get(slot.def.get("id", slot.get("id", &"")), "") if slot != null else ""
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
	# 加入方只收 interest_radius 內的實體：受傷、死亡事件自己帶發聲位置，世界裡沒有這隻怪也照距離衰減；
	# 還是查不到位置的實體事件不播（原本當全場音效全音量，遠處隊友打怪反而最大聲）；冷卻中的「拒絕」音只給按的人聽
	var victim := _spawn(w, &"grunt", me.pos + Vector2(0, 25))
	w.events.clear()
	Combat.apply_damage(w, mate, victim, {"damage": 99999.0})
	for event_name: String in ["entity:damaged", "entity:died"]:
		var evs := _named(w.events, event_name)
		if evs.is_empty() or not evs[0].has("pos"):
			return "%s 事件應帶發聲位置 pos（加入方的世界不一定有這個實體）" % event_name
		if absf(sound_script.event_gain(null, me, event_name, evs[0]) - 0.25) > EPS:
			return "世界裡沒有這隻怪時，25 單位外的 %s 音量應 0.25，實際 %.3f" % [event_name, sound_script.event_gain(null, me, event_name, evs[0])]
	if sound_script.event_gain(null, me, "entity:damaged", {"target_id": 99999}) != 0.0:
		return "查不到位置的受傷事件應不播（實際音量 %.2f）" % sound_script.event_gain(null, me, "entity:damaged", {"target_id": 99999})
	if sound_script.event_gain(w, me, "skill:onCooldown", {"key": "player.roll", "player_id": mate.id}) != 0.0 \
			or sound_script.event_gain(w, me, "skill:onCooldown", {"key": "player.roll", "player_id": me.id}) != 1.0:
		return "冷卻中的「拒絕」音只給按的人聽（隊友按的應 0、自己按的應 1）"
	return ""


static func check_mesh_counts() -> String:
	# 只查遊戲裡用關節版畫的角色（玩家、Boss）。小怪在遊戲裡用蒙皮版，繪製次數由「蒙皮小怪」檢查（≤ 2 個網格）；
	# 小怪的關節版只是蒙皮的模板，畫面上不出現，零件數不影響效能
	var limits := {&"player": 20, &"boss": 22}
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
	var arena := DarkFantasy.build_arena(Vector2.ONE * Config.WORLD.arena_half_size, rng)
	var n := PartKit.mesh_instances(arena).size()
	arena.free()
	if n > 12:
		return "場地有 %d 個零件，上限 12" % n
	for model: StringName in [&"longsword", &"staff"]:
		var w := DarkFantasy.weapon(model)
		if w.is_empty() or w.main == null:
			return "武器 %s 沒有建立外觀" % model
		(w.main as Node3D).free()
	for model: StringName in [&"woodShield", &"dagger"]:
		var o := DarkFantasy.offhand(model)
		var node: Variant = o.get("offhand", o.get("left"))
		if node == null:
			return "副手 %s 沒有建立外觀" % model
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


# 長劍：待機刃朝上下（玩家、骷髏），骷髏往下劈時也是；三連砍 1 往左下劈、2 往右上撩、3 從頭後上方劈到前下方；
# 權杖第 1 下、火把也是右上往左下斜揮；武器尖端不進地；雙匕首待機刀尖朝前上方、刺出朝正前方，刃一直朝上下
static func check_sword_edge() -> String:
	var rec := AnimRecorder.new()
	var err := ""
	var cuts := {}
	var low := INF
	for row: Dictionary in rec.rows("player-swordShield", false):
		if not (row.key in ["idle", "attack"]):
			continue
		var made: Dictionary = (row.make as Callable).call()
		var rig = made.rig
		for i in (row.frames as Array).size():
			AnimRecorder.step(row, made, i)
			var a: Dictionary = row.frames[i].anim
			var tip := _sword_tf(rig) * (DarkFantasy.sword_axis() * 1.1)
			low = minf(low, tip.y)
			if a.action == &"attack" and a.phase == &"active":
				var n := 2 if a.is_finisher else (1 if a.swing_dir < 0 else 0)
				if not cuts.has(n):
					cuts[n] = [tip, tip]
				cuts[n][1] = tip
		if row.key == "idle":
			var w := (_sword_tf(rig).basis * Vector3.RIGHT).normalized()
			if absf(w.x) > 0.1:
				err = "玩家待機時劍刃應朝上下：刃寬方向 %s" % w
		(rig as Node).free()
	if err == "":
		var swung := false
		for row: Dictionary in rec.rows("enemy-grunt"):
			if not (row.key in ["chase", "swing"]):
				continue
			swung = swung or row.key == "swing"
			var made: Dictionary = (row.make as Callable).call()
			for i in (row.frames as Array).size():
				AnimRecorder.step(row, made, i)
				var w := (_sword_tf(made.rig).basis * Vector3.RIGHT).normalized()
				if i >= row.start and absf(w.x) > 0.25:
					err = "骷髏 %s 時劍刃應朝上下（第 %d 步）：刃寬方向 %s" % [row.key, i - row.start, w]
			(made.rig as Object).free()
		if err == "" and not swung:
			err = "骷髏沒有錄到揮砍"
	for subject: String in ["player-scepter", "player-torch"]:
		if err != "":
			break
		var sw := _first_swing(rec, subject, Vector3.UP * 0.9)
		if sw.is_empty() or not (sw[1].x - sw[0].x > 0.6 and sw[0].y - sw[1].y > 0.8):
			err = "%s 普攻第 1 下應從右上往左下斜揮：尖端 %s" % [subject, sw]
		elif sw[2] < 0.1:
			err = "%s 普攻時武器尖端低到 %.2f（進地裡）" % [subject, sw[2]]
		else:
			_note("%s 第 1 下尖端 %s → %s、最低 %.2f" % [subject, sw[0], sw[1], sw[2]])
	if err == "":
		err = _check_dagger_aim(rec)
	rec.clear()
	if err != "":
		return err
	if cuts.size() != 3:
		return "三連砍應錄到 3 段：%s" % [cuts.keys()]
	var c0: Array = cuts[0]
	var c1: Array = cuts[1]
	var c2: Array = cuts[2]
	if not (c0[1].x - c0[0].x > 0.8 and c0[0].y - c0[1].y > 1.0):
		return "第 1 段應從右上往左下劈：劍尖 %s → %s" % c0
	if not (c1[0].x - c1[1].x > 0.8 and c1[1].y - c1[0].y > 1.0):
		return "第 2 段應從左下往右上撩：劍尖 %s → %s" % c1
	if not (c2[0].z < 0.0 and c2[0].y > 2.0 and c2[1].z > 0.8 and c2[1].y < 1.0):
		return "第 3 段應從頭後上方劈到前下方：劍尖 %s → %s" % c2
	if low < 0.1:
		return "揮劍時劍尖低到 %.2f（進地裡）" % low
	_note("三連砍劍尖：1 %s → %s、2 %s → %s、3 %s → %s、最低 %.2f" % [c0[0], c0[1], c1[0], c1[1], c2[0], c2[1], low])
	return ""


# 雙匕首：待機兩把刀尖朝前上方、刺出那把朝正前方（收在腰側時也朝前），刃一直朝上下；刺完回待機刀尖不會甩
static func _check_dagger_aim(rec: AnimRecorder) -> String:
	for row: Dictionary in rec.rows("player-dagger", false):
		if not (row.key in ["idle", "attack"]):
			continue
		var made: Dictionary = (row.make as Callable).call()
		var rig = made.rig
		var err := ""
		var stabs := 0
		var prev: Array = []
		for i in (row.frames as Array).size():
			AnimRecorder.step(row, made, i)
			var a: Dictionary = row.frames[i].anim
			var dirs: Array = []
			for right: bool in [true, false]:
				var t := _hand_tf(rig, right)
				var d := (t.basis * Vector3.DOWN).normalized()
				var w := (t.basis * Vector3.BACK).normalized()
				dirs.append(d)
				if i > 10 and absf(w.y) < 0.7:
					err = "匕首的刃應朝上下（%s 第 %d 步）：刃寬方向 %s" % [row.key, i, w]
				var stabbing: bool = a.action == &"attack" and a.phase == &"active" and a.k > 0.5 and (right == (a.swing_dir >= 0) or a.is_finisher)
				if stabbing:
					stabs += 1
					if d.z < 0.95:
						err = "匕首刺出時刀尖應朝正前方（第 %d 步）：%s" % [i, d]
				if row.key == "idle" and i > 20 and not (d.y > 0.4 and d.y < 0.8 and d.z > 0.5):
					err = "匕首待機刀尖應朝前上方：%s" % d
			if i > 10 and not prev.is_empty() and a.action == &"ready" and (dirs[0].angle_to(prev[0]) > 0.15 or dirs[1].angle_to(prev[1]) > 0.15):
				err = "匕首刺完回待機時刀尖甩了一下（第 %d 步）：%.2f / %.2f 弧度" % [i, dirs[0].angle_to(prev[0]), dirs[1].angle_to(prev[1])]
			prev = dirs
			if err != "":
				break
		(rig as Node).free()
		if err != "":
			return err
		if row.key == "attack" and stabs == 0:
			return "匕首普攻沒有錄到刺出"
	return ""


static func _hand_tf(rig, right: bool) -> Transform3D:
	var t := Transform3D.IDENTITY
	for j in ([rig.body, rig.arm_r, rig.forearm_r, rig.hand_r] if right else [rig.body, rig.arm_l, rig.forearm_l, rig.hand_l]):
		t = t * Transform3D(Basis.from_euler(j.rotation, EULER_ORDER_YXZ).scaled_local(j.scale), j.position)
	return t


# 普攻連段第一次出手那幾步的武器尖端 [第一步, 最後一步, 整段最低]；tip = 尖端在手掌座標的位置
static func _first_swing(rec: AnimRecorder, subject: String, tip: Vector3) -> Array:
	for row: Dictionary in rec.rows(subject, false):
		if row.key != "attack":
			continue
		var made: Dictionary = (row.make as Callable).call()
		var from: Variant = null
		var to := Vector3.ZERO
		var low := INF
		var done := false
		for i in (row.frames as Array).size():
			AnimRecorder.step(row, made, i)
			var a: Dictionary = row.frames[i].anim
			var at := _sword_tf(made.rig) * tip
			low = minf(low, at.y)
			if a.action == &"attack" and a.phase == &"active" and not done:
				if from == null:
					from = at
				to = at
			elif from != null:
				done = true
		(made.rig as Node).free()
		return [from, to, low] if from != null else []
	return []


# 右手掌掛點相對角色根節點（Rig 與 SkinnedRig 的關節都只有 position / rotation / scale）
static func _sword_tf(rig) -> Transform3D:
	var t := Transform3D.IDENTITY
	for j in [rig.body, rig.arm_r, rig.forearm_r, rig.hand_r]:
		t = t * Transform3D(Basis.from_euler(j.rotation, EULER_ORDER_YXZ).scaled_local(j.scale), j.position)
	return t


# 骷髏弓手：瞄準時左手舉平、右手拉弦；射完右手平滑放下（第一幀不直接跳回）；
# 目標在射擊距離內時左手停在預備高度、不放下（畫面層自己算距離）；離開射擊距離後平滑放回垂直（弓平放）
static func check_archer_bow_arm() -> String:
	var w := _new_world()
	var p := _player(w)
	p.stats.set_base(&"max_hp", 99999.0)
	p.hp = 99999.0
	var archer := _spawn(w, &"archer", p.pos + Vector2(0, 8))
	var rig := DarkFantasy.character(&"archer")
	var anim := EnemyAnimator.new(rig, archer)
	var prev_state: StringName = &""
	var highest := 0.0
	var aimed := false
	# 右拳（拉弦手）的高度：手肘往外側抬（IK 算出來在 rotation.z），所以量拳頭的位置，不量 arm_r 的單一角度
	var draw_from := INF     # 開始瞄準時右拳的高度
	var draw_top := -INF     # 拉滿時右拳的高度
	var right_after := INF   # 射完第一幀右拳的高度
	for i in 900:
		_run(w, _cmd(Vector2.ZERO), 1)
		anim.update(archer, DT)
		var state: StringName = archer.anim.state
		if state == &"aim":
			highest = minf(highest, rig.arm_l.rotation.x)
			var hy := BodyPose.hand_pos(rig, true).y
			if draw_from == INF:
				draw_from = hy
			draw_top = maxf(draw_top, hy)
		elif prev_state == &"aim":
			aimed = true
			right_after = BodyPose.hand_pos(rig, true).y
			break
		prev_state = state
	var held := 0.0   # 射完後 30 步之後左手的角度（應停在預備高度）
	for i in 30:
		_run(w, _cmd(Vector2.ZERO), 1)
		anim.update(archer, DT)
		held = rig.arm_l.rotation.x
	var reach: float = archer.def.preferred_range[1] + archer.def.fire_reach
	var in_range := archer.pos.distance_to(p.pos) <= reach
	# 玩家跑到射擊距離外：弓手應平滑放下
	p.pos = archer.pos + Vector2(0, -(reach + 8.0))
	var first_out := INF
	for i in 90:
		_run(w, _cmd(Vector2.ZERO), 1)
		anim.update(archer, DT)
		if first_out == INF and archer.anim.state == &"kite" and archer.pos.distance_to(p.pos) > reach:
			first_out = rig.arm_l.rotation.x
	var rest := rig.arm_l.rotation.x
	var out_state: StringName = archer.anim.state
	rig.free()
	if not aimed:
		return "弓手 15 秒內沒有瞄準射完"
	if highest > -1.4:
		return "弓手瞄準時左手應舉到接近水平：最高 %.2f" % highest
	if draw_top - draw_from < 0.3:
		return "弓手拉弦時右拳只從 %.2f 抬到 %.2f，應拉到下巴的高度" % [draw_from, draw_top]
	if right_after < draw_from + 0.45 * (draw_top - draw_from):
		return "弓手射完第一幀右拳就掉到 %.2f（拉滿 %.2f、開始 %.2f），應從拉弦姿勢平滑放下" % [right_after, draw_top, draw_from]
	if not in_range or absf(held - EnemyAnimator.BOW_ARM_READY) > 0.05:
		return "目標在射擊距離內時弓手射完應停在預備高度 %.2f：在射擊距離內 %s、30 步後 %.2f" % [EnemyAnimator.BOW_ARM_READY, in_range, held]
	if first_out == INF or first_out > EnemyAnimator.BOW_ARM_READY / 2.0:   # 從預備高度放下，第一幀還要在一半以上
		return "目標離開射擊距離後第一幀左手 %.2f，應平滑放下、不直接跳回" % first_out
	if out_state == &"kite" and absf(rest - EnemyAnimator.BOW_ARM_REST) > 0.01:
		return "目標在射擊距離外 1.5 秒後左手應回到垂直：%.2f" % rest
	_note("弓手瞄準時左手最高 %.2f、右拳 %.2f → 拉滿 %.2f → 射完第一幀 %.2f、射程內射完 30 步後左手 %.2f、離開射程第一幀 %.2f、1.5 秒後 %.2f（%s）" % [highest, draw_from, draw_top, right_after, held, first_out, rest, out_state])
	return ""


# 身體零件：披風整片在軀幹與腰帶後面（不穿進身體）、身體前方沒有披風色的零件；盾的尖角和盾面同一平面（盾的厚度 < 0.2）；
# 騎士骨架有 5 個身上掛點（第一次合併與之後用模板組出的都有），盾掛在 forearm_l、箭袋掛在 back、箭袋在袋口與袋底中間
static func check_body_parts() -> String:
	var looks := {&"boss": [DarkFantasy.C.death_armor, DarkFantasy.C.iron, Color("1c1a22")]}
	for id: StringName in ClassDefs.ORDER:
		var c: Dictionary = ClassDefs.CLASSES[id].colors
		looks[id] = [c.armor, c.trim, c.cape]
	for id: StringName in looks:
		var rig := DarkFantasy.character(id) if id == &"boss" else DarkFantasy.player_character(id)
		var body_back := INF   # 軀幹與腰帶最後面的 z
		var cape_front := -INF
		for child in rig.body.get_children():
			if not child is MeshInstance3D:
				continue
			var mi := child as MeshInstance3D
			var color: Color = (mi.material_override as StandardMaterial3D).albedo_color
			var box := mi.get_aabb()
			if color.is_equal_approx(looks[id][2]):
				cape_front = maxf(cape_front, box.end.z)
			elif color.is_equal_approx(looks[id][0]) or color.is_equal_approx(looks[id][1]):
				body_back = minf(body_back, box.position.z)
		rig.free()
		if cape_front == -INF or body_back == INF:
			return "%s 找不到披風或軀幹的零件（顏色重複？）" % id
		if cape_front >= body_back:
			return "%s 的披風穿進身體：披風最前 z %.3f、軀幹最後 z %.3f" % [id, cape_front, body_back]
	var shield: Node3D = DarkFantasy.offhand(&"woodShield").offhand
	var thick := 0.0
	for mi in PartKit.mesh_instances(shield):
		thick = maxf(thick, mi.get_aabb().size.x)
	shield.free()
	if thick >= 0.2:
		return "盾的厚度 %.2f：尖角沒有和盾面同一平面" % thick
	for n in 2:   # 第一次合併建出的、之後用模板組出的
		var rig := DarkFantasy.player_character(&"guardian")
		var want: Array[StringName] = [&"back", &"forearm_l", &"head", &"hip_l", &"hip_r"]
		if rig.mount_nodes.size() != want.size() or want.any(func(m: StringName) -> bool: return not rig.mount_nodes.has(m)):
			var names: Array = rig.mount_nodes.keys()
			rig.free()
			return "騎士骨架的掛點應有 back / forearm_l / head / hip_l / hip_r：%s" % [names]
		rig.set_weapon(&"longsword", &"woodShield")
		var on_forearm: bool = rig.weapon_offhand.get_parent() == rig.mount_nodes[&"forearm_l"]
		rig.set_weapon(&"dagger", &"dagger")
		if rig.weapon_left == null or rig.weapon_left.get_parent() != rig.held_l or rig.held_l.get_parent() != rig.hand_l or rig.weapon_offhand != null:
			rig.free()
			return "副手匕首應掛在左手的手持關節 held_l（hand_l 底下）、沒有盾"
		rig.set_weapon(&"shortbow")
		var back: Node3D = rig.mount_nodes[&"back"]
		var on_back: bool = rig.weapon_back.get_parent() == back
		var center := back.position + rig.weapon_back.position
		rig.free()
		if not on_forearm or not on_back:
			return "盾應掛在 forearm_l（%s）、箭袋應掛在 back（%s）" % [on_forearm, on_back]
		if center.distance_to((DarkFantasy.QUIVER_MOUTH + DarkFantasy.QUIVER_BOTTOM) / 2.0) > 0.001:
			return "箭袋中心 %s 應在袋口與袋底中間" % center
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


# 背包介面：背包和屬性面板並排塞得進介面最大檔時的畫面；腳邊欄只列按得到 F 的地上道具，拖進背包送出 OP_PICKUP（實際撿起放在那一格）、
# 背包的東西拖到腳邊送出 OP_DROP、滑鼠停著的腳邊道具顯示說明；撿不下時 HUD 發 inventory_full，面板提示拿掉哪一件就放得下，關掉就清除
static func check_inventory_panel() -> String:
	var w := _new_world(5)
	var cam := _test_camera()
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w, cam)
	_scene_root().add_child(hud)
	var p := _player(w)
	var panel: InventoryPanel = hud.inventory_panel
	hud.toggle_stats_panel()
	panel.visible = true
	var room := _menu_room()
	var stats_size: Vector2 = await _settled_min_size(hud._stats_panel)
	var panel_size: Vector2 = await _settled_min_size(panel)
	# 兩邊離畫面邊緣 16 / 24（hud.gd）；腳邊框浮在屬性面板與背包中間（再空 16）
	var need := Vector2(16 + stats_size.x + 16 + InventoryPanel.FEET_W + InventoryPanel.FEET_GAP + panel_size.x + 24, maxf(stats_size.y, panel_size.y))
	_note("背包 + 腳邊框 + 屬性面板 %.0f×%.0f（介面最大檔時可用 %.0f×%.0f）" % [need.x, need.y, room.x, room.y])
	var err := ""
	if need.x > room.x or need.y > room.y:
		err = "背包 + 腳邊框 + 屬性面板 %.0f×%.0f，超出介面最大檔時的 %.0f×%.0f" % [need.x, need.y, room.x, room.y]
	var ops: Array = []
	panel.op_requested.connect(func(op: Array) -> void: ops.append(op))
	panel._process(DT)
	if err == "" and panel.feet_panel.visible:   # 2026-10-31 使用者：腳邊沒東西時不用顯示
		err = "腳邊沒有東西時不應顯示腳邊欄"
	var stone := w.drop_item(&"whetstone", p.pos + Vector2(1.0, 0))
	w.drop_item(&"whetstone", p.pos + Vector2(LootDefs.INTERACT_RANGE + 3.0, 0))
	panel._process(DT)
	if err == "" and (panel._feet.size() != 1 or panel._feet[0] != stone or not panel.feet_panel.visible):
		err = "腳邊欄應只有按得到 F 的那一個磨刀石，實際 %d 個（顯示 %s）" % [panel._feet.size(), panel.feet_panel.visible]
	if err == "":
		panel._hover_pickup = stone.id
		if not String(panel._info_of(p).get("title", "")).contains("在地上"):
			err = "滑鼠停在腳邊的道具上應顯示說明（標「在地上」）：%s" % panel._info_of(p)
		panel._hover_pickup = 0
	var cell_at := func(c: Vector2i) -> Vector2: return panel._grid_origin() + (Vector2(c) + Vector2(0.5, 0.5)) * InventoryPanel.CELL
	if err == "":
		panel._start_drag(p, panel._feet_row_rect(0).get_center())
		panel._finish_drag(p, cell_at.call(Vector2i(2, 0)))
		if ops != [[InputCmd.OP_PICKUP, stone.id, 2, 0, 0, Loadout.BAG]]:
			err = "從腳邊拖到倉庫 (2, 0) 應送出 OP_PICKUP，實際 %s" % [ops]
	if err == "":
		var cmd := _cmd(Vector2.ZERO)
		cmd.inv_ops = ops.duplicate()
		ops.clear()
		_run(w, cmd, 1)
		if p.inventory.entries.size() != 1 or p.inventory.entries[0].cell != Vector2i(2, 0):
			err = "送出的 OP_PICKUP 應把磨刀石放在 (2, 0)：%s" % [p.inventory.entries]
	if err == "":
		var uid: StringName = p.inventory.entries[0].uid
		panel._start_drag(p, cell_at.call(Vector2i(2, 0)))
		panel._finish_drag(p, panel._feet_rect().get_center())
		if ops != [[InputCmd.OP_DROP, String(uid)]]:
			err = "背包的東西拖到腳邊應送出 OP_DROP，實際 %s" % [ops]
	# 腳邊拖到主袋 (1, 1)：OP_PICKUP 帶 Loadout.CORE；送出後生效，滑鼠停著顯示在主袋
	if err == "":
		ops.clear()
		var stone2 := w.drop_item(&"whetstone", p.pos + Vector2(1.0, 0))
		panel._process(DT)
		var at: Vector2 = panel._bcell_rect(Vector2i(1, 1)).get_center()
		panel._start_drag(p, panel._feet_row_rect(panel._feet.find(stone2)).get_center())
		panel._finish_drag(p, at)
		if ops != [[InputCmd.OP_PICKUP, stone2.id, 1, 1, 0, Loadout.CORE]]:
			err = "從腳邊拖到主袋 (1, 1) 應送出帶 CORE 的 OP_PICKUP，實際 %s" % [ops]
		else:
			var cmd2 := _cmd(Vector2.ZERO)
			cmd2.inv_ops = ops.duplicate()
			ops.clear()
			_run(w, cmd2, 1)
			panel._hover_uid = p.loadout.core.occupied().get(Vector2i(1, 1), &"")
			var title := String(panel._info_of(p).get("title", ""))
			panel._hover_uid = &""
			if not title.contains("在主袋"):
				err = "主袋 (1, 1) 的磨刀石說明應寫「在主袋」：%s" % title
	# 撿不下：倉庫 6 格全滿、主袋也塞滿，倉庫每格一件，拿掉任何一件就放得下 2 × 2 的道具（建議第一件）
	if err == "":
		p.clear_items()
		for y in ItemDefs.BAG_SIZE.y:
			for x in ItemDefs.BAG_SIZE.x:
				p.inventory.add(StringName("d_%d_%d" % [x, y]), &"loaded_dice", Vector2i(x, y), 0)
		while p.loadout.add_item(p, &"loaded_dice", {}, 0, Loadout.CORE) != &"":   # 主袋也塞滿，撿起來才會放不下
			pass
		var buckler := w.drop_item(_shaped(&"o4"), p.pos + Vector2(0, 1.0))
		var full_ids: Array[int] = []
		hud.inventory_full.connect(func(id: int) -> void: full_ids.append(id))
		w.events.clear()
		var press := _cmd(Vector2.ZERO, Vector2(0, 5), InputCmd.BTN_INTERACT)
		_run(w, press, 1)
		_feed_hud(hud, w.events)
		if full_ids != [buckler.id]:
			err = "撿不下 2 × 2 的道具時 HUD 應發 inventory_full(%d)，實際 %s" % [buckler.id, full_ids]
		else:
			panel.show_full(buckler.id)
			panel._process(DT)
			var text := panel._full_text(p, buckler)
			if panel._full_target() != buckler or panel._suggest != &"d_0_0" or not text.contains("拿掉") or not text.contains(ItemDefs.ITEMS[&"loaded_dice"].name):
				err = "撿不下時應標出那件道具、建議拿掉第一格的骰子：目標 %s、建議 %s、文字 %s" % [panel._full_target(), panel._suggest, text]
			panel.visible = false
			if err == "" and panel._full_pickup != 0:
				err = "關掉背包後應清除撿不下的提示"
	# 滾輪：內容（盤 + 倉庫）比捲動區高就捲得下去，捲到底不會超過
	if err == "":
		panel.visible = true
		panel.size.y = panel.custom_minimum_size.y   # 用最小高度：測試的視窗比 1080 高，內容放得下就測不到捲動
		panel._process(DT)
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.position = panel._view_rect().get_center()
		for i in 30:
			panel._gui_input(wheel)
		var max_scroll: float = maxf(0.0, panel._content_height(p) - panel._view_rect().size.y)
		_note("背包介面捲動區高 %.0f、內容高 %.0f" % [panel._view_rect().size.y, panel._content_height(p)])
		if max_scroll <= 0.0 or absf(panel._scroll - max_scroll) > 0.5:
			err = "滾輪往下捲到底應停在 %.0f，實際 %.0f" % [max_scroll, panel._scroll]
	hud.queue_free()
	cam.queue_free()
	return err


# 遺物的 N 選 1（Build 改版第 6 步；2026-10-31 卡片直排在背包左邊）：打開遺物就顯示卡片（張數 = 選項數）並自動打開背包與屬性面板，
# 三者並排塞得進介面最大檔的畫面；卡片的羈絆標籤寫目前件數、效果的數字金色；點卡片送 OP_RELIC_PICK、Esc 送 OP_RELIC_CLOSE；
# 選完 / 關掉時自動打開的背包一起關，原本就開著的不關；背包拿著東西時 R / Esc 不給遺物面板
static func check_relic_panel() -> String:
	var w := _new_world(5)
	var cam := _test_camera()
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w, cam)
	_scene_root().add_child(hud)
	var p := _player(w)
	var relic := w.drop_relic(&"big", p.pos + Vector2(1.0, 0))
	relic.open_for(p)
	# 說明最長的 3 個道具，最壞情況的卡片高度
	var ids := ItemDefs.item_ids().filter(func(id: StringName) -> bool: return not ItemDefs.ITEMS[id].get("bonds", []).is_empty())
	ids.sort_custom(func(x: StringName, y: StringName) -> bool: return String(ItemDefs.ITEMS[x].desc).length() > String(ItemDefs.ITEMS[y].desc).length())
	relic.offers[p.peer_id] = ids.slice(0, 3)
	var panel: RelicPanel = hud.relic_panel
	var inv: InventoryPanel = hud.inventory_panel
	panel.refresh(w, p)
	var size: Vector2 = await _settled_min_size(panel)
	var inv_size: Vector2 = await _settled_min_size(inv)
	var stats_size: Vector2 = await _settled_min_size(hud._stats_panel)
	var room := _menu_room()
	_note("遺物 3 選 1 %.0f×%.0f（背包 %.0f、屬性面板 %.0f 寬；介面最大檔時可用 %.0f×%.0f）" % [size.x, size.y, inv_size.x, stats_size.x, room.x, room.y])
	var err := ""
	if not panel.visible or panel.choice_count != 3:
		err = "打開遺物應顯示 3 張卡片：顯示 %s、%d 張" % [panel.visible, panel.choice_count]
	elif not inv.visible or not hud.is_stats_panel_open():
		err = "打開遺物應自動打開背包與屬性面板（背包 %s、屬性面板 %s）" % [inv.visible, hud.is_stats_panel_open()]
	elif size.y + 32 > room.y or 16 + stats_size.x + 16 + size.x + 16 + inv_size.x + 24 > room.x:
		err = "遺物 3 選 1 %.0f×%.0f 和背包、屬性面板並排塞不進 %.0f×%.0f" % [size.x, size.y, room.x, room.y]
	if err == "":
		var bond: StringName = ItemDefs.ITEMS[ids[0]].bonds[0]
		var chip_text := "%s %d 格" % [BondDefs.BONDS[bond].name, p.loadout.bond_counts.get(bond, 0)]
		var labels: Array = panel._cards.get_child(0).find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
		var bb := panel.effect_bbcode("擊殺後 3 秒攻速 +30%")
		var gold := UiKit.GOLD.to_html(false)
		if not labels.has(chip_text):
			err = "卡片應有羈絆標籤「%s」（名稱 + 目前格數）：%s" % [chip_text, labels]
		elif not bb.contains("[color=#%s]3 秒[/color]" % gold) or not bb.contains("[color=#%s]+30%%[/color]" % gold):
			err = "效果的數字應包成金色：%s" % bb
	var ops: Array = []
	panel.op_requested.connect(func(op: Array) -> void: ops.append(op))
	# 背包拿著東西時，R / Esc 不給遺物面板（R 旋轉、Esc 放回）
	if err == "":
		InputCollector.register_actions()
		var collector := InputCollector.new()
		collector.relic_panel = panel
		collector.inventory_panel = inv
		var r_key := InputEventAction.new()
		r_key.action = &"restart"
		r_key.pressed = true
		p.add_weapon({"uid": &"rw", "base": &"swordShield", "rarity": &"white", "affixes": []})
		var occupied := p.inventory.occupied()
		inv._start_drag(p, inv._grid_origin() + (Vector2(occupied.keys()[0]) + Vector2(0.5, 0.5)) * InventoryPanel.CELL)
		var eaten: bool = collector._relic_key(r_key)
		var held_ops := ops.duplicate()
		inv._cancel()
		var eaten_free: bool = collector._relic_key(r_key)
		collector.free()
		if eaten or not held_ops.is_empty():
			err = "背包拿著東西時按 R 不應重骰（遺物面板收走了 %s、%s）" % [eaten, held_ops]
		elif not eaten_free or ops != [[InputCmd.OP_RELIC_REROLL, relic.id]]:
			err = "背包沒拿東西時按 R 應重骰：%s" % [ops]
		ops.clear()
	if err == "":
		panel.close()
		panel.refresh(w, p)
		if ops != [[InputCmd.OP_RELIC_CLOSE]] or panel.visible or inv.visible or hud.is_stats_panel_open():
			err = "Esc 應送出 OP_RELIC_CLOSE、藏起來，自動打開的背包與屬性面板一起關：%s、顯示 %s、背包 %s" % [ops, panel.visible, inv.visible]
	if err == "":
		# 背包原本就開著：選完不關
		p.relic_id = 0
		panel.refresh(w, p)
		hud.set_bag_open(true)
		relic.open_for(p)
		panel.refresh(w, p)
		ops.clear()
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		(panel._cards.get_child(1) as Control).gui_input.emit(click)
		if ops != [[InputCmd.OP_RELIC_PICK, relic.id, 1]]:
			err = "點第 2 張卡片應送出 OP_RELIC_PICK 第 1 個：%s" % [ops]
		elif panel.visible or not inv.visible:
			err = "原本就開著的背包，選完遺物不應關掉（面板 %s、背包 %s）" % [panel.visible, inv.visible]
	if err == "":
		# 被打到：3 選 1 先不選、背包與屬性面板關掉；持續傷害的一跳不關
		p.relic_id = 0
		panel.refresh(w, p)
		relic.open_for(p)
		panel.refresh(w, p)
		ops.clear()
		hud._on_event("entity:damaged", {"target_id": p.id, "pos": p.pos, "amount": 3.0, "minor": true})
		var after_tick: bool = panel.visible and inv.visible
		hud._on_event("entity:damaged", {"target_id": p.id, "pos": p.pos, "amount": 12.0})
		panel.refresh(w, p)
		if not after_tick:
			err = "持續傷害的一跳不應關掉 3 選 1 與背包"
		elif ops != [[InputCmd.OP_RELIC_CLOSE]] or panel.visible or inv.visible or hud.is_stats_panel_open():
			err = "被打到應送出 OP_RELIC_CLOSE、關掉 3 選 1、背包與屬性面板：%s、面板 %s、背包 %s、屬性面板 %s" % [ops, panel.visible, inv.visible, hud.is_stats_panel_open()]
	hud.queue_free()
	cam.queue_free()
	return err


# 鍛造祭壇（Build 改版第 8 步；2026-10-31 改成兩格放武器）：祭壇旁開背包就顯示鍛造面板；右鍵武器、拿著點格子、拖到另一把上都放進格子；
# 放了一把後能合的武器發亮、其他變暗；不能合時寫原因、按鈕不能按；點詞條再按合成送 [OP_MERGE, a, b, 留 a, 留 b] 並清空；
# 面板和背包並排塞得進畫面；離開祭壇就關掉、清空
static func check_forge_panel() -> String:
	var w := _new_world(5)
	var cam := _test_camera()
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w, cam)
	_scene_root().add_child(hud)
	var p := _player(w)
	var inv: InventoryPanel = hud.inventory_panel
	var forge_panel: ForgePanel = hud.forge_panel
	inv.visible = true
	var forge := _forge_near(w, p)
	# 說明最長的詞條，最壞情況的面板寬度
	var ids: Array = WeaponDropDefs.AFFIXES.keys()
	ids.sort_custom(func(x: StringName, y: StringName) -> bool: return String(WeaponDropDefs.AFFIXES[x].desc).length() > String(WeaponDropDefs.AFFIXES[y].desc).length())
	var main_aff: Array[StringName] = [ids[0], ids[1], ids[2], ids[3]]
	var bag_aff: Array[StringName] = [ids[4], ids[5], ids[6], ids[7]]
	p.weapon_slots[Loadout.MAIN] = {"uid": &"fa", "base": &"swordShield", "rarity": &"purple", "affixes": main_aff}
	p.apply_active_weapon()
	p.add_weapon({"uid": &"fb", "base": &"swordShield", "rarity": &"purple", "affixes": bag_aff})
	p.add_weapon({"uid": &"fs", "base": &"staff", "rarity": &"purple", "affixes": []})
	var ops: Array = []
	inv.op_requested.connect(func(op: Array) -> void: ops.append(op))
	forge_panel.op_requested.connect(func(op: Array) -> void: ops.append(op))
	forge_panel.refresh(w, p, true)
	await _settled_min_size(inv)
	var cell_of := func(uid: StringName) -> Vector2:
		for c: Vector2i in p.inventory.occupied():
			if p.inventory.occupied()[c] == uid:
				return inv._grid_origin() + (Vector2(c) + Vector2(0.5, 0.5)) * InventoryPanel.CELL
		return Vector2(-1, -1)
	var mouse := func(pos: Vector2, button: MouseButton) -> InputEventMouseButton:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = true
		ev.position = pos
		ev.global_position = pos
		return ev
	var fb: Dictionary = p.inventory.find(&"fb").weapon
	var fs: Dictionary = p.inventory.find(&"fs").weapon
	var err := ""
	if not forge_panel.visible or forge_panel.uids != [&"", &""] or not forge_panel._ok.disabled:
		err = "站在鍛造祭壇旁打開背包應顯示鍛造面板（兩格空的、合成不能按）：顯示 %s、%s" % [forge_panel.visible, forge_panel.uids]
	# 右鍵主手 → 放進格子 1；同種同稀有度的 fb 發亮、法杖變暗
	if err == "":
		inv._gui_input(mouse.call(inv._slot_rect(Loadout.MAIN).get_center(), MOUSE_BUTTON_RIGHT))
		if forge_panel.uids != [&"fa", &""] or not ops.is_empty():
			err = "鍛造祭壇旁右鍵主手的武器應放進鍛造格子 1、不送操作：%s、%s" % [forge_panel.uids, ops]
		elif not forge_panel.glow(fb) or forge_panel.dims(fb) or forge_panel.glow(fs) or not forge_panel.dims(fs):
			err = "放了紫色劍盾後，背包裡的紫色劍盾應發亮、紫色法杖應變暗"
	# 點一下拿起法杖、點格子 2 → 寫原因「要同種武器」、合成不能按；手上的放回去
	if err == "":
		inv._start_drag(p, cell_of.call(&"fs"))
		inv._held = true
		forge_panel._slot_input(mouse.call(Vector2(10, 10), MOUSE_BUTTON_LEFT), 1)
		if forge_panel.uids != [&"fa", &"fs"] or not forge_panel.reason().begins_with("要同種武器") or not forge_panel._ok.disabled or not inv._drag.is_empty():
			err = "拿著法杖點格子 2：應放進去、寫「要同種武器」、合成不能按（%s、「%s」、不能按 %s）" % [forge_panel.uids, forge_panel.reason(), forge_panel._ok.disabled]
	# 點格子 2 拿出法杖；主手拖到背包的 fb 上 → 兩把都在格子裡（fa 已經在就不重複）、可以合
	if err == "":
		forge_panel._slot_input(mouse.call(Vector2(10, 10), MOUSE_BUTTON_LEFT), 1)
		inv._start_drag(p, inv._slot_rect(Loadout.MAIN).get_center())
		inv._finish_drag(p, cell_of.call(&"fb"))
		if forge_panel.uids != [&"fa", &"fb"] or forge_panel.reason() != "" or forge_panel._ok.disabled or not ops.is_empty():
			err = "主手拖到同種武器上應兩把都放進鍛造格子、可以合、先不送：%s、「%s」、%s" % [forge_panel.uids, forge_panel.reason(), ops]
	var size: Vector2 = await _settled_min_size(forge_panel)
	var inv_size: Vector2 = await _settled_min_size(inv)
	var room := _menu_room()
	_note("合成面板 %.0f×%.0f（背包 %.0f 寬；介面最大檔時可用 %.0f×%.0f）" % [size.x, size.y, inv_size.x, room.x, room.y])
	if err == "" and (size.x + 16 + inv_size.x + 24 > room.x or size.y + 120 > room.y):
		err = "合成面板 %.0f×%.0f 放在背包左邊塞不進 %.0f×%.0f" % [size.x, size.y, room.x, room.y]
	# 背包的浮動說明：最長的 4 條詞條（含分支）的橘色武器也要塞得進畫面；滑鼠在哪都不超出畫面、會換行；數字與羈絆有染色
	if err == "":
		var long_ids: Array = WeaponDropDefs.AFFIXES.keys().filter(func(id: StringName) -> bool: return WeaponDropDefs.AFFIXES[id].kind != &"branch")
		long_ids.sort_custom(func(x: StringName, y: StringName) -> bool: return String(WeaponDropDefs.AFFIXES[x].desc).length() > String(WeaponDropDefs.AFFIXES[y].desc).length())
		var branches: Array = WeaponDropDefs.AFFIXES.keys().filter(func(id: StringName) -> bool: return WeaponDropDefs.AFFIXES[id].kind == &"branch")
		branches.sort_custom(func(x: StringName, y: StringName) -> bool: return String(WeaponDropDefs.AFFIXES[x].desc).length() > String(WeaponDropDefs.AFFIXES[y].desc).length())
		var worst: Array[StringName] = [branches[0], long_ids[0], long_ids[1], long_ids[2]]
		var info := UiKit.item_info(&"staff", {"uid": &"wi", "base": &"staff", "rarity": &"orange", "affixes": worst})
		var font: Font = inv.get_theme_default_font()
		var text_w := InventoryPanel.TIP_W - InventoryPanel.TIP_PAD * 2.0
		var body_h := UiKit.draw_rich_lines(null, font, Vector2.ZERO, info.lines, text_w, InventoryPanel.TIP_FONT)
		var screen := Vector2(1920, 1080)
		var room_h := screen.y - InventoryPanel.TIP_MARGIN * 2.0 - InventoryPanel.TIP_PAD * 2.0 - 60.0   # 60：標題最多兩行加間距
		_note("浮動說明：最長的橘色武器 %.0f px（可用 %.0f）" % [body_h, room_h])
		if body_h > room_h:
			err = "最長的橘色武器說明 %.0f px 超出畫面可用的 %.0f px" % [body_h, room_h]
		var tip := Vector2(InventoryPanel.TIP_W, 300)
		for pointer: Vector2 in [Vector2.ZERO, Vector2(960, 540), Vector2(1920, 0), Vector2(0, 1080), screen]:
			var box := InventoryPanel.tip_rect(pointer, tip, screen)
			if err == "" and not Rect2(Vector2.ZERO, screen).encloses(box):
				err = "滑鼠在 %s 時浮動說明 %s 超出畫面" % [pointer, box]
			if err == "" and box.has_point(pointer):
				err = "滑鼠在 %s 時浮動說明 %s 蓋住滑鼠" % [pointer, box]
		if err == "" and (not inv._tip_layer.top_level or inv._tip_layer.get_parent() != inv):
			err = "浮動說明要畫在 top_level 的子節點上，否則會被面板的 clip_contents 裁掉"
		var line_h := font.get_height(InventoryPanel.TIP_FONT)
		var wrapped := UiKit.draw_rich_lines(null, font, Vector2.ZERO, ["很長的說明文字".repeat(12)], 200.0, InventoryPanel.TIP_FONT)
		if err == "" and wrapped < line_h * 2.0:
			err = "長文字應換行：高度 %.0f" % wrapped
		var runs := UiKit.rich_runs("移速 +8% · 火焰傷害 300%", Color.WHITE)
		var colors := {}
		for run: Array in runs:
			colors[run[0]] = run[1]
		if err == "" and (colors.get("+8%") != UiKit.GOLD or colors.get("300%") != UiKit.GOLD or colors.get("火焰") != BondDefs.BONDS[&"fire"].color or colors.get("移速") != UiKit.RICH_ATTR_COLOR):
			err = "說明文字的數字、羈絆、屬性應染色：%s" % [runs]
		if err == "" and not String(UiKit.item_info(&"worn_boots", {}).title).contains("數值 · 普通"):
			err = "標題應寫種類與稀有度：%s" % UiKit.item_info(&"worn_boots", {}).title
	if err == "":
		(forge_panel._rows[0].get_child(1) as Button).pressed.emit()
		forge_panel._ok.pressed.emit()
		if ops != [[InputCmd.OP_MERGE, "fa", "fb", String(main_aff[1]), String(bag_aff[0])]] or forge_panel.uids != [&"", &""]:
			err = "點格子 1 那把的第 2 條再按合成，應送出留 %s 與 %s 的 OP_MERGE 並清空格子：%s、%s" % [main_aff[1], bag_aff[0], ops, forge_panel.uids]
	if err == "":
		forge_panel.put(&"fa")
		forge.pos += Vector2(LootDefs.FORGE.range + 5.0, 0.0)
		forge_panel.refresh(w, p, true)
		if forge_panel.visible or forge_panel.uids != [&"", &""]:
			err = "離開鍛造祭壇後鍛造面板應關掉並清空"
	hud.queue_free()
	cam.queue_free()
	return err


# 疊在一起的字：同一個目標同時跳的傷害數字（屬性轉換、冰棺分傷害）一個比一個高、別的目標不受影響；
# 地上物件的名稱碰到這一幀已經畫的就往上錯開一行，沒碰到的留在原位
# 小地圖：只畫探索過的（視野距離內、牆擋住就看不到，牆本身看得到）；還沒看過的格子全部透明（場地外框也一樣，看過才亮）；換小關清掉走過的紀錄、改用新地圖的大小
static func check_minimap() -> String:
	var w := _new_world(5, false, &"graveyard")
	var p := _player(w)
	var mm := Minimap.new()
	mm.world = w
	mm.local_player = func() -> Player: return p
	_scene_root().add_child(mm)
	mm.refresh(0.0)
	var r := Vision.view_range(p)
	var far := p.pos + Vector2(r + 3.0, 0.0)
	var seen_far := mm.is_seen(far)
	var seen_here := mm.is_seen(p.pos)
	var solid := mm._base[0]   # 左上角在地圖外框（EDGE_PAD 一圈實心）
	# 開局：沒看過的格子一格都不畫（外框也不例外），看過的才有顏色
	var edges := mm._edge.count(1)
	var paint_err := ""
	for i in mm._seen.size():
		var painted := mm._img.get_pixel(i % mm._size.x, i / mm._size.x).a > 0.0
		if painted != (mm._seen[i] == 1):
			paint_err = "第 %d 格看過 %d、畫了 %s" % [i, mm._seen[i], painted]
			break
	var seen_edge := -1
	for i in mm._edge.size():
		if mm._edge[i] and mm._seen[i]:
			seen_edge = i
			break
	var edge_pixel := mm._img.get_pixel(seen_edge % mm._size.x, seen_edge / mm._size.x) if seen_edge >= 0 else Minimap.EDGE
	var edge_bright := absf(edge_pixel.r - Minimap.EDGE.r) + absf(edge_pixel.g - Minimap.EDGE.g) + absf(edge_pixel.b - Minimap.EDGE.b) < 0.02   # 圖是 8 位元，不會剛好相等
	# 門嵌在牆裡：站在門前要算看到門
	var door_ok := true
	var doors := DigEvent.doors(w)
	var door_err := ""
	if not doors.is_empty():
		var door: Dictionary = doors[0]
		var stand := p.pos
		p.pos = MapDefs.to_world(w.map, door.reach)
		mm._timer = 0.0
		mm.refresh(0.0)
		door_ok = mm.is_seen_near(MapDefs.to_world(w.map, door.at), Minimap.DOOR_SEEN_CELLS)
		door_err = "站在門前 %s 應看得到門 %s" % [door.reach, door.at]
		p.pos = stand
	var t_build := Time.get_ticks_usec()
	mm._rebuild()
	_note("小地圖換地圖重算一次 %.1f ms（%s）" % [(Time.get_ticks_usec() - t_build) / 1000.0, mm._size])
	var t_reveal := Time.get_ticks_usec()
	mm._reveal(p.pos, r)
	_note("小地圖掃一次視線 %.2f ms（視野 %.0f，換格子才掃）" % [(Time.get_ticks_usec() - t_reveal) / 1000.0, r])
	mm.refresh(0.0)
	var old_size := mm._size
	w.next_stage(&"")
	mm._timer = 0.0
	mm.refresh(0.0)
	var reset_ok: bool = mm._size == Vector2i((w.half_extents * 2.0).ceil()) and mm.is_seen(p.pos) and not mm.is_seen(far)
	var shown := mm._seen.count(1)
	mm.queue_free()
	# 牆擋視線：自己前方 4 單位一道 2 厚的長牆，牆看得到、牆後面看不到；墓碑不擋
	var w2 := _new_world(5)
	var p2 := _player(w2)
	var front := p2.pos + Vector2(4.0, -30.0)
	var blocks: Array[Dictionary] = [{"min": front, "max": front + Vector2(2.0, 60.0), "top": 3.0, "kind": MapDefs.WALL}]
	w2.terrain = Terrain.new(blocks)
	w2.layout_key = ["牆擋視線"]
	var mm2 := Minimap.new()
	mm2.world = w2
	mm2.local_player = func() -> Player: return p2
	_scene_root().add_child(mm2)
	mm2.refresh(0.0)
	var wall_seen := mm2.is_seen(p2.pos + Vector2(4.5, 0.0))
	var behind_seen := mm2.is_seen(p2.pos + Vector2(8.0, 0.0))
	var open_seen := mm2.is_seen(p2.pos + Vector2(-8.0, 0.0))
	w2.terrain = Terrain.new([{"min": front, "max": front + Vector2(2.0, 60.0), "top": 1.3, "kind": MapDefs.TOMB}] as Array[Dictionary])
	w2.layout_key = ["墓碑不擋"]
	mm2._timer = 0.0
	mm2.refresh(0.0)
	var tomb_behind := mm2.is_seen(p2.pos + Vector2(8.0, 0.0))
	mm2.queue_free()
	if not seen_here or seen_far:
		return "出生點應看過、%.0f 外不應看過（%s / %s）" % [r + 3.0, seen_here, seen_far]
	if solid != 1:
		return "地圖外框應標成實心，實際種類 %d" % solid
	if edges == 0 or paint_err != "":
		return "開局只畫看過的格子（外框 %d 格）：%s" % [edges, paint_err]
	if not edge_bright:
		return "看過的場地外框應畫成亮色"
	if not door_ok:
		return door_err
	if not reset_ok:
		return "換小關後應照新地圖重畫（舊 %s、新 %s、地圖 %s），只看過出生點附近" % [old_size, mm._size, w.half_extents * 2.0]
	if shown > ceili(PI * (r + 1.0) * (r + 1.0)):
		return "換小關後看過的格子應只有視野一圈，實際 %d 格" % shown
	if not wall_seen or behind_seen or not open_seen:
		return "牆應看得到、牆後面看不到、沒牆的方向看得到：牆 %s、牆後 %s、開闊 %s" % [wall_seen, behind_seen, open_seen]
	if not tomb_behind:
		return "墓碑不擋視線：墓碑後面應看得到"
	return ""


static func check_overlap_text() -> String:
	var w := _new_world(5)
	var cam := _test_camera()
	var floaters := Floaters.new()
	floaters.camera = cam
	_scene_root().add_child(floaters)
	var a := _spawn(w, &"grunt", Vector2(0, 0))
	var b := _spawn(w, &"grunt", Vector2(3, 0))
	floaters.spawn(a, "10", &"dmg")
	floaters.spawn(a, "10", &"dmg", StatDefs.DAMAGE_TYPES[&"cold"].color)
	floaters.spawn(b, "10", &"dmg")
	for i in Floaters.STACK_MAX - 1:   # 疊滿 STACK_MAX 層後下一個換到旁邊一欄、從最低那層開始
		floaters.spawn(a, "10", &"dmg")
	var items: Array[Dictionary] = floaters._items
	var ys: Array = items.map(func(it: Dictionary) -> float: return it.world.y - (b.height if it.target == b.id else a.height))
	var d: Vector3 = items[-1].world - items[0].world
	var side := Vector2(d.x, d.z).length()
	floaters.queue_free()
	cam.queue_free()
	if absf(ys[1] - ys[0] - Floaters.STACK_STEP) > EPS or absf(ys[2] - ys[0]) > EPS:
		return "同一個目標同時跳的第 2 個數字應高 %.2f、別的目標不疊：%s" % [Floaters.STACK_STEP, ys]
	if absf(ys[-1] - ys[0]) > EPS or absf(side) < Floaters.STACK_SIDE - Floaters.JITTER:
		return "疊滿 %d 層後應換到旁邊一欄（同高、左右差約 %.1f）：高 %s、左右差 %.2f" % [Floaters.STACK_MAX, Floaters.STACK_SIDE, ys, side]
	var placed: Array[Rect2] = []
	var size := 17
	var y0 := WorldLabels.place_label(placed, 500.0, 300.0, 120.0, size)
	var y1 := WorldLabels.place_label(placed, 540.0, 300.0, 120.0, size)
	var y2 := WorldLabels.place_label(placed, 900.0, 300.0, 120.0, size)
	if y0 != 300.0 or y1 > y0 - size or y2 != 300.0:
		return "名稱重疊時後畫的往上錯開一行、沒碰到的不動：%.0f / %.0f / %.0f" % [y0, y1, y2]
	return ""


# 附帶的小傷害（燃燒的一跳、附加火焰傷害）事件標 minor、打擊本身不標；minor 的數字字比較小、不佔疊層（後面的打擊數字照樣從第 2 層開始）
static func check_minor_numbers() -> String:
	var w := _new_world(5)
	var p := _player(w)
	var e := LootChecks._item_dummy(w, p.pos + Vector2(0, 1.5), 100000.0)
	e.add_burn(p.id, 10.0, 3.0, 1, 1)
	var events: Array[Dictionary] = []
	_run_collect(w, _cmd(Vector2.ZERO), roundi(1.0 / DT), events)
	var burn := _named(events, "entity:damaged").filter(func(ev: Dictionary) -> bool: return ev.target_id == e.id)
	if burn.is_empty() or not burn.all(func(ev: Dictionary) -> bool: return ev.get("minor", false)):
		return "燃燒每一跳的受傷事件應標 minor：%s" % [burn]
	w.events.clear()   # 上一步燃燒那一跳的事件還留著
	p.stats.set_source(&"check_minor", [[&"added_fire", Stats.ADD, 0.5]])
	Combat.apply_damage(w, p, e, {"damage": 5.0})
	var hits := _named(w.events, "entity:damaged")
	if hits.size() != 2 or hits[0].get("minor", false) or not hits[1].get("minor", false):
		return "打擊本身不標 minor、跟著的附加火焰傷害要標：%s" % [hits]
	var cam := _test_camera()
	var floaters := Floaters.new()
	floaters.camera = cam
	_scene_root().add_child(floaters)
	floaters.spawn(e, "10", &"dmg")
	floaters.spawn(e, "3", &"minor")
	floaters.spawn(e, "10", &"dmg")
	var items: Array[Dictionary] = floaters._items
	var ys: Array = items.map(func(it: Dictionary) -> float: return it.world.y - e.height)
	var minor_font: int = (items[1].node as Label).get_theme_font_size(&"font_size")
	var dmg_font: int = (items[0].node as Label).get_theme_font_size(&"font_size")
	floaters.queue_free()
	cam.queue_free()
	if absf(ys[1] - ys[0]) > EPS or absf(ys[2] - ys[0] - Floaters.STACK_STEP) > EPS:
		return "minor 數字應在最底層、不佔疊層（下一個打擊數字在第 2 層）：%s" % [ys]
	if minor_font >= dmg_font:
		return "minor 數字應比一般傷害數字小：%d / %d" % [minor_font, dmg_font]
	return ""


# 開著背包（連屬性面板）時，最長的新手提示放在兩個面板中間、不被蓋住（太長就換行）
static func check_hint_beside_bag() -> String:
	var w := _new_world(5)
	var cam := _test_camera()
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w, cam)
	_scene_root().add_child(hud)
	var p := _player(w)
	w.drop_item(&"whetstone", p.pos + Vector2(1.0, 0))   # 腳邊有東西才顯示腳邊框（2026-10-31）：最擠的情況
	var hints: Hints = hud.hints
	hints.save_path = ""
	var longest: StringName = &""
	for id: StringName in HintDefs.HINTS:
		if longest == &"" or String(HintDefs.HINTS[id]).length() > String(HintDefs.HINTS[longest]).length():
			longest = id
	hud.toggle_stats_panel()
	hud.inventory_panel.visible = true
	hints.show_hint(longest)
	await _settled_min_size(hud.inventory_panel)
	hud.inventory_panel._process(DT)   # 擺好腳邊框
	hud._place_hints()
	await _settled_min_size(hints)
	hud._place_hints()
	await _settled_min_size(hints)
	var r: Rect2 = hints.get_rect()
	var bag: Rect2 = hud.inventory_panel.get_rect()
	var stats: Rect2 = hud._stats_panel.get_rect()
	var feet: Rect2 = hud.inventory_panel.feet_panel.get_rect()
	_note("開背包時的新手提示 %.0f×%.0f（%.0f ~ %.0f；屬性面板到 %.0f、腳邊框從 %.0f、背包從 %.0f）" % [r.size.x, r.size.y, r.position.x, r.end.x, stats.end.x, feet.position.x, bag.position.x])
	var feet_shown: bool = hud.inventory_panel.feet_panel.visible
	var corner_open: bool = hud._top_right.visible   # 右上的層數、擊殺：背包開著時藏起來（背包蓋不滿右緣）
	hud.inventory_panel.visible = false   # 腳邊框跟著藏：上面先記下
	var corner_closed: bool = hud._top_right.visible
	hud.queue_free()
	cam.queue_free()
	var screen: Vector2 = hints.get_parent_control().size
	if r.position.y < 0.0 or r.end.y > screen.y:
		return "開背包時新手提示（%s）換行後超出畫面：提示 %s、畫面 %s" % [longest, r, screen]
	if r.position.x < stats.end.x or r.end.x > bag.position.x or not feet_shown or r.intersects(feet):
		return "開背包時新手提示（%s）應在屬性面板與背包中間、不蓋到腳邊框：提示 %s、屬性 %s、腳邊框 %s、背包 %s" % [longest, r, stats, feet, bag]
	if corner_open or not corner_closed:
		return "右上的層數 / 擊殺應在背包開著時藏起來、關掉後顯示：開著 %s、關掉 %s" % [corner_open, corner_closed]
	return ""


# 屬性面板：使用中的屬性剛好在一組、核心屬性一直顯示；其他屬性有加成才顯示，整組都沒顯示就連標題一起藏，拿掉加成就藏回去
static func check_stats_panel() -> String:
	var group_of := {}
	for g: Dictionary in StatDefs.PANEL_GROUPS:
		for stat: StringName in g.stats:
			if not StatDefs.STATS.has(stat):
				return "屬性面板「%s」組的 %s 不在 StatDefs.STATS" % [g.name, stat]
			if group_of.has(stat):
				return "%s 同時在屬性面板的「%s」與「%s」組" % [stat, group_of[stat], g.name]
			group_of[stat] = g.name
	for stat: StringName in StatDefs.STATS:
		if StatDefs.STATS[stat].in_use and not group_of.has(stat):
			return "使用中的屬性 %s（%s）沒放進屬性面板的任何一組" % [stat, StatDefs.STATS[stat].name]
	for stat: StringName in StatDefs.PANEL_CORE:
		if not group_of.has(stat):
			return "核心屬性 %s 不在屬性面板的任何一組" % stat
	var w := _new_world(5)
	var p := _player(w)
	var panel := StatsPanel.new()
	_scene_root().add_child(panel)
	var err := _stats_panel_state(panel, p, "開局")
	var hidden: Array = StatDefs.PANEL_GROUPS.filter(func(g: Dictionary) -> bool: return not panel.shown_groups().has(g.name))
	if err == "" and hidden.is_empty():
		err = "開局每一組都有顯示（%s），看不出沒加成的組會藏起來" % ", ".join(panel.shown_groups())
	if err == "":
		var g: Dictionary = hidden[0]
		var stat: StringName = g.stats[0]
		p.stats.set_source(&"check_panel", [[stat, Stats.ADD, 1.0]])
		err = _stats_panel_state(panel, p, "%s 加 1" % StatDefs.STATS[stat].name)
		if err == "" and not panel.shown_groups().has(g.name):
			err = "%s 有加成後「%s」組的標題應顯示，實際顯示的組：%s" % [StatDefs.STATS[stat].name, g.name, ", ".join(panel.shown_groups())]
		p.stats.remove_source(&"check_panel")
		if err == "":
			err = _stats_panel_state(panel, p, "拿掉加成")
		if err == "" and panel.shown_groups().has(g.name):
			err = "拿掉 %s 的加成後「%s」組應整組藏起來" % [StatDefs.STATS[stat].name, g.name]
	panel.queue_free()
	return err


# 每列顯示 = 核心屬性或不是基礎值；refresh 後比對
static func _stats_panel_state(panel: StatsPanel, p: Player, when: String) -> String:
	panel.refresh(p)
	for g: Dictionary in StatDefs.PANEL_GROUPS:
		for stat: StringName in g.stats:
			if not StatDefs.STATS[stat].in_use:
				continue
			var want: bool = StatDefs.PANEL_CORE.has(stat) or not is_equal_approx(p.stats.value(stat), p.stats.base(stat))
			if panel.is_stat_shown(stat) != want:
				return "%s：屬性面板的 %s 應%s顯示（值 %.3f、基礎 %.3f）" % [when, StatDefs.STATS[stat].name, "" if want else "不", p.stats.value(stat), p.stats.base(stat)]
	return ""


# 背包的點擊操作：左鍵點一下拿在手上、再點一下放下（送 OP_MOVE），按住拖曳照舊；拿著時右鍵 / Esc 放回、點面板外面丟掉；
# 右鍵直接裝上：背包的道具 → 主手格子（照 find_spot）、技能只進能用的寶石座（不能用的提示）、鑲著的 → 背包、主手武器不拿下來（提示）、
# 腳邊的武器 → 背包、背包的武器 → 換上；畫法的種類分得出武器 / 技能 / 輔助 / 道具
static func check_inventory_click() -> String:
	var w := _new_world(5)
	var cam := _test_camera()
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w, cam)
	_scene_root().add_child(hud)
	var p := _player(w)
	var panel: InventoryPanel = hud.inventory_panel
	hud.toggle_stats_panel()
	panel.visible = true
	await _settled_min_size(panel)
	panel._process(DT)
	var ops: Array = []
	panel.op_requested.connect(func(op: Array) -> void: ops.append(op))
	var cell_at := func(c: Vector2i) -> Vector2: return panel._grid_origin() + (Vector2(c) + Vector2(0.5, 0.5)) * InventoryPanel.CELL
	var mouse := func(pos: Vector2, button: MouseButton, pressed: bool) -> InputEventMouseButton:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		return ev
	var click := func(pos: Vector2) -> void:
		panel._gui_input(mouse.call(pos, MOUSE_BUTTON_LEFT, true))
		panel._gui_input(mouse.call(pos, MOUSE_BUTTON_LEFT, false))
	var apply := func() -> void:
		var cmd := _cmd(Vector2.ZERO)
		cmd.inv_ops = ops.duplicate()
		ops.clear()
		_run(w, cmd, 1)
	var err := ""
	var stone := p.loadout.add_item(p, &"whetstone", {"cell": Vector2i(0, 0), "rot": 0}, 0, Loadout.BAG)
	click.call(cell_at.call(Vector2i(0, 0)))
	if not panel._held or panel._drag.get("uid", &"") != stone or not ops.is_empty():
		err = "左鍵點一下背包的磨刀石應拿在手上、還不送操作：held %s、拿著 %s、操作 %s" % [panel._held, panel._drag, ops]
	if err == "":
		panel._gui_input(mouse.call(cell_at.call(Vector2i(3, 0)), MOUSE_BUTTON_LEFT, true))
		if ops != [[InputCmd.OP_MOVE, String(stone), 3, 0, 0, Loadout.BAG]] or not panel._drag.is_empty() or panel._held:
			err = "拿著時左鍵點 (3, 0) 應放下（OP_MOVE 到 (3, 0)），實際 %s、手上 %s" % [ops, panel._drag]
	ops.clear()
	if err == "":
		click.call(cell_at.call(Vector2i(0, 0)))
		panel._input(mouse.call(Vector2.ZERO, MOUSE_BUTTON_RIGHT, true))
		var esc := InputEventKey.new()
		esc.physical_keycode = KEY_ESCAPE
		esc.pressed = true
		var after_right: bool = panel._drag.is_empty()
		click.call(cell_at.call(Vector2i(0, 0)))
		panel._input(esc)
		if not after_right or not panel._drag.is_empty() or not ops.is_empty():
			err = "拿著時右鍵、Esc 都應放回原處、不送操作：右鍵後 %s、Esc 後 %s、操作 %s" % [after_right, panel._drag, ops]
	if err == "":
		panel._gui_input(mouse.call(cell_at.call(Vector2i(0, 0)), MOUSE_BUTTON_LEFT, true))
		panel._gui_input(mouse.call(cell_at.call(Vector2i(5, 0)), MOUSE_BUTTON_LEFT, false))
		if ops != [[InputCmd.OP_MOVE, String(stone), 5, 0, 0, Loadout.BAG]]:
			err = "按住拖到 (5, 0) 放開應照舊送 OP_MOVE，實際 %s" % [ops]
	ops.clear()
	if err == "":
		click.call(cell_at.call(Vector2i(0, 0)))
		var outside: Vector2 = panel.get_global_rect().position - Vector2(4, 4)
		panel._input(mouse.call(outside, MOUSE_BUTTON_LEFT, true))
		if ops != [[InputCmd.OP_DROP, String(stone)]]:
			err = "拿著時點面板外面應丟掉（OP_DROP），實際 %s" % [ops]
	ops.clear()
	# 右鍵：倉庫的磨刀石 → 主袋，位置和撿起來一樣（Loadout.auto_place）；主袋裡的右鍵 → 拿回倉庫
	if err == "":
		var want: Dictionary = p.loadout.auto_place(&"whetstone")
		panel._gui_input(mouse.call(cell_at.call(Vector2i(0, 0)), MOUSE_BUTTON_RIGHT, true))
		if want.get("where", -9) != Loadout.CORE or ops != [[InputCmd.OP_MOVE, String(stone), want.spot.cell.x, want.spot.cell.y, want.spot.rot, Loadout.CORE]]:
			err = "右鍵倉庫的磨刀石應放進主袋 %s，實際 %s" % [want, ops]
		else:
			apply.call()
			if p.loadout.core.find(stone).is_empty():
				err = "右鍵送出後磨刀石應在主袋：%s" % [p.loadout.core.entries]
	if err == "":
		var at: Dictionary = p.loadout.core.find(stone)
		var pos: Vector2 = panel._bcell_rect(at.cell + Inventory.cells_of(at.id, at.rot)[0]).get_center()
		var back: Dictionary = p.inventory.find_spot(&"whetstone")
		panel._gui_input(mouse.call(pos, MOUSE_BUTTON_RIGHT, true))
		if ops != [[InputCmd.OP_MOVE, String(stone), back.cell.x, back.cell.y, back.rot, Loadout.BAG]]:
			err = "右鍵主袋的磨刀石應拿回倉庫 %s，實際 %s" % [back, ops]
	ops.clear()
	if err == "":
		panel._notice = ""
		panel._gui_input(mouse.call(panel._slot_rect(Loadout.MAIN).get_center(), MOUSE_BUTTON_RIGHT, true))
		if not ops.is_empty() or panel._notice == "":
			err = "右鍵主手的武器不應送操作（主手不能空著）、要提示：操作 %s、提示「%s」" % [ops, panel._notice]
	# 技能：倉庫的旋風斬右鍵 → 按鍵袋（第 0 個袋子）
	if err == "":
		var whirl := p.loadout.add_item(p, &"whirlwind", {"cell": Vector2i(5, 0), "rot": 0}, 0, Loadout.BAG)
		panel._gui_input(mouse.call(cell_at.call(Vector2i(5, 0)), MOUSE_BUTTON_RIGHT, true))
		var key := p.loadout.auto_place(&"whirlwind")
		if key.get("where", -9) != 0 or ops != [[InputCmd.OP_MOVE, String(whirl), key.spot.cell.x, key.spot.cell.y, key.spot.rot, 0]]:
			err = "右鍵旋風斬應放進按鍵袋 %s，實際 %s" % [key, ops]
		p.loadout.container(Loadout.BAG).remove(whirl)
	ops.clear()
	# 武器：腳邊的法杖右鍵 → 背包（不帶手）；背包的法杖右鍵 → 換上主手
	if err == "":
		var inst := {"uid": w.new_weapon_uid(), "base": &"staff", "rarity": &"white", "affixes": [] as Array[StringName]}
		var staff := w.drop_weapon(inst, p.pos + Vector2(1.0, 0))
		panel._process(DT)
		var row := panel._feet.find(staff)
		panel._gui_input(mouse.call(panel._feet_row_rect(row).get_center(), MOUSE_BUTTON_RIGHT, true))
		var spot: Dictionary = p.inventory.find_spot(&"staff")
		if row < 0 or ops != [[InputCmd.OP_PICKUP, staff.id, spot.cell.x, spot.cell.y, spot.rot, Loadout.BAG]]:
			err = "右鍵腳邊的法杖應撿進背包 %s，實際 %s" % [spot, ops]
		else:
			apply.call()
			var e: Dictionary = p.inventory.find(inst.uid)
			var first: Vector2i = e.cell + Inventory.cells_of(e.id, e.rot)[0] if not e.is_empty() else Vector2i(-1, -1)
			panel._gui_input(mouse.call(cell_at.call(first), MOUSE_BUTTON_RIGHT, true))
			if e.is_empty() or ops != [[InputCmd.OP_EQUIP, String(inst.uid), Loadout.MAIN]]:
				err = "右鍵背包的法杖應換上主手（OP_EQUIP），實際 %s" % [ops]
	if err == "":
		var kinds := {&"staff": &"weapon", &"meteor": &"skill", &"split_support": &"support", &"whetstone": &"item", &"bag_hit": &"bag"}
		for id: StringName in kinds:
			if UiKit.item_kind(id) != kinds[id]:
				err = "%s 的畫法種類應是 %s，實際 %s" % [id, kinds[id], UiKit.item_kind(id)]
				break
	hud.queue_free()
	cam.queue_free()
	return err


# 背包版面的規則（對齊與位置是 UI，由使用者看，不檢查）：羈絆欄只列收集到的（沒有就不列）；
# 腳邊框不蓋到背包與技能欄，在腳邊框上點一下拿起、再點背包的格子 = 撿起放在那一格
static func check_inventory_layout() -> String:
	var w := _new_world(5)
	var cam := _test_camera()
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w, cam)
	_scene_root().add_child(hud)
	var p := _player(w)
	var panel: InventoryPanel = hud.inventory_panel
	panel.visible = true
	await _settled_min_size(panel)
	panel._process(DT)
	var ops: Array = []
	panel.op_requested.connect(func(op: Array) -> void: ops.append(op))
	var err := ""
	if not panel._shown_bonds(p).is_empty():
		err = "開局沒有羈絆道具，羈絆欄應該是空的，實際 %s" % [panel._shown_bonds(p)]
	if err == "":
		p.loadout.add_item(p, &"whetstone", {}, 0, Loadout.CORE)
		var want: Array[StringName] = []
		for bond: StringName in BondDefs.BONDS:
			if p.loadout.bond_counts.get(bond, 0) > 0:
				want.append(bond)
		if want.is_empty() or panel._shown_bonds(p) != want:
			err = "鑲上磨刀石後羈絆欄應只列件數 > 0 的 %s，實際 %s" % [want, panel._shown_bonds(p)]
	if err == "":
		var stone := w.drop_item(&"whetstone", p.pos + Vector2(1.0, 0))
		panel._process(DT)
		var feet: Rect2 = panel.feet_panel.get_global_rect()
		var bag: Rect2 = panel.get_global_rect()
		var skills: Rect2 = hud._skill_bar.get_global_rect()
		_note("腳邊框 %s、背包 %s、技能欄 %s" % [feet, bag, skills])
		if not panel.feet_panel.visible or feet.intersects(bag) or feet.end.x > bag.position.x or feet.end.y > bag.end.y + 0.5:
			err = "腳邊框應浮在背包左邊、下緣不低於背包、不重疊：腳邊框 %s（顯示 %s）、背包 %s" % [feet, panel.feet_panel.visible, bag]
		elif feet.intersects(skills):
			err = "腳邊框不能蓋到技能欄：腳邊框 %s、技能欄 %s" % [feet, skills]
		else:
			var row := panel._feet.find(stone)
			var local: Vector2 = panel._feet_row_local(row).get_center()
			for pressed: bool in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = pressed
				ev.position = local
				panel.feet_panel._gui_input(ev)
			if row < 0 or not panel._held or panel._drag.get("pickup_id", 0) != stone.id:
				err = "在腳邊框上點一下應拿起地上的磨刀石：手上 %s" % [panel._drag]
			else:
				var cell := Vector2i(5, 0)
				var press := InputEventMouseButton.new()
				press.button_index = MOUSE_BUTTON_LEFT
				press.pressed = true
				press.position = panel._grid_origin() + (Vector2(cell) + Vector2(0.5, 0.5)) * InventoryPanel.CELL
				panel._gui_input(press)
				if ops != [[InputCmd.OP_PICKUP, stone.id, cell.x, cell.y, 0, Loadout.BAG]]:
					err = "拿著腳邊的磨刀石點倉庫 (5, 0) 應送出 OP_PICKUP，實際 %s" % [ops]
	panel.visible = false
	if err == "" and panel.feet_panel.visible:
		err = "背包關掉時腳邊框也要關掉"
	hud.queue_free()
	cam.queue_free()
	return err


# 盤（觸發袋）：盤座標與袋子座標換算來回一致（四個邊）；空的邊算得出接哪一邊、沿邊第幾格；抓袋子的空格或標題條拿起整個袋子，
# 拖到另一邊送 OP_BAG（接上），拖到倉庫送拿下來；拖東西到袋子送帶袋子編號的 OP_MOVE；標題與說明是一句話，倉庫拖放不管形狀
static func check_inventory_board() -> String:
	var w := _new_world(5)
	var p := _player(w)
	for side: StringName in BagDefs.SIDE_ORDER:
		var b := {"side": side, "offset": 1, "length": 2, "depth": 2}
		for c: Vector2i in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(1, 0)]:
			if InventoryPanel.bag_cell(b, Loadout.board_cell(b, c)) != c:
				return "%s 邊的袋子格子 %s 換成盤座標再換回來不一樣：%s" % [side, c, InventoryPanel.bag_cell(b, Loadout.board_cell(b, c))]
		var outer := Loadout.board_cell(b, Vector2i(0, 1))
		var bs := InventoryPanel.board_side(outer)
		if bs.get("side", &"") != side or bs.get("along", -1) != 1:
			return "%s 邊的空地 %s 應算出 %s、沿邊第 1 格：%s" % [side, outer, side, bs]
	var cam := _test_camera()
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w, cam)
	_scene_root().add_child(hud)
	var panel: InventoryPanel = hud.inventory_panel
	panel.visible = true
	await _settled_min_size(panel)
	panel._process(DT)
	var ops: Array = []
	panel.op_requested.connect(func(op: Array) -> void: ops.append(op))
	var err := ""
	var hit := _bag(p, &"hit", &"left")
	var hit_i := p.loadout.bags.find(hit)
	var empty_cell := panel._bcell_rect(Loadout.board_cell(hit, Vector2i(0, 0))).get_center()
	if InventoryPanel.board_target(p, Loadout.board_cell(hit, Vector2i(0, 0))).get("where", -9) != hit_i:
		err = "左邊命中袋的格子應算在那個袋子"
	if err == "":
		panel._start_drag(p, empty_cell)
		if panel._drag.get("uid", &"") != hit.uid or not panel._drag.has("bag"):
			err = "抓命中袋的空格應拿起整個袋子：%s" % [panel._drag]
		else:
			panel._finish_drag(p, panel._bcell_rect(Vector2i(BagDefs.MAIN_SIZE.x + 1, 2)).get_center())
			if ops != [[InputCmd.OP_BAG, String(hit.uid), "right", 2]]:
				err = "命中袋拖到右邊沿邊第 2 格應送 OP_BAG 接到右邊 2：%s" % [ops]
	ops.clear()
	if err == "":
		panel._start_drag(p, empty_cell)
		panel._finish_drag(p, panel._grid_origin() + Vector2(0.5, 0.5) * InventoryPanel.CELL)
		if ops != [[InputCmd.OP_BAG, String(hit.uid), "", 0, 0, 0, 0]]:
			err = "命中袋拖到倉庫 (0, 0) 應送拿下來的 OP_BAG：%s" % [ops]
	ops.clear()
	if err == "":
		var rune := p.loadout.add_item(p, &"thunder_rune", {"cell": Vector2i(0, 0), "rot": 0}, 0, Loadout.BAG)
		panel._start_drag(p, panel._grid_origin() + Vector2(0.5, 0.5) * InventoryPanel.CELL)
		panel._finish_drag(p, panel._bcell_rect(Loadout.board_cell(hit, Vector2i(1, 1))).get_center())
		if ops != [[InputCmd.OP_MOVE, String(rune), 1, 1, 0, hit_i]]:
			err = "雷鳴符文拖到命中袋 (1, 1) 應送帶袋子編號的 OP_MOVE：%s" % [ops]
	ops.clear()
	# 標題條：停著算那個袋子、抓著拿起整個袋子（裝滿的袋子沒有空格可抓）、右鍵拿下來
	if err == "":
		var head_at: Vector2 = panel._bag_head_rect(hit).get_center()
		if panel._uid_at(p, head_at) != hit.uid:
			err = "滑鼠停在標題條上應算那個袋子：%s" % panel._uid_at(p, head_at)
		else:
			panel._start_drag(p, head_at)
			var held_bag: bool = panel._drag.get("uid", &"") == hit.uid and panel._drag.has("bag")
			panel._cancel()
			var right := InputEventMouseButton.new()
			right.button_index = MOUSE_BUTTON_RIGHT
			right.pressed = true
			right.position = head_at
			panel._gui_input(right)
			if not held_bag or ops != [[InputCmd.OP_BAG, String(hit.uid), "", 0]]:
				err = "抓標題條應拿起整個袋子（%s）、右鍵應拿下來：%s" % [held_bag, ops]
	ops.clear()
	# 標題與說明：一句話講時機，下方的袋子不寫方位
	if err == "":
		var bottom := {"kind": &"roll", "side": &"bottom", "tier": &"small", "mul": 1.0, "length": 3, "depth": 2, "entries": []}
		var right_hit: Dictionary = hit.duplicate()
		right_hit.side = &"right"
		var sentence: String = InventoryPanel.bag_info(right_hit, p).lines[0]
		if InventoryPanel.head_text(bottom) != "翻滾時" or InventoryPanel.head_text(right_hit) != "右鍵打中時" or not sentence.contains("在那隻怪身上"):
			err = "袋子的標題應寫時機：%s / %s、說明「%s」" % [InventoryPanel.head_text(bottom), InventoryPanel.head_text(right_hit), sentence]
	# 滑鼠停在袋子的標題條上：這個袋子是焦點、說明框寫它；停在下方袋子裡的東西上，標題不寫「不分按鍵」
	if err == "":
		var roll := _bag(p, &"roll", &"bottom")
		var smoke := _put(p, roll, &"smoke_bomb")
		panel._hover_uid = panel._uid_at(p, panel._bag_head_rect(roll).get_center())
		var focus_ok: bool = panel._focus_bag(p) == roll and String(panel._info_of(p).title).contains("翻滾時")
		panel._hover_uid = smoke
		var item_title := String(panel._info_of(p).title)
		panel._hover_uid = &""
		if not focus_ok or item_title.contains("不分按鍵") or not item_title.contains("翻滾時"):
			err = "停在標題條上應以那個袋子為焦點（%s）；袋子裡東西的說明應寫「翻滾時」、不寫方位：%s" % [focus_ok, item_title]
		# 數值放袋子：說明寫生效中、不寫發動；「一起放」只列放得出來的（數值與修飾不算）
		var boots := _put(p, roll, &"worn_boots")
		var split := _put(p, roll, &"split_support")
		panel._hover_uid = boots
		var boots_info: Dictionary = panel._info_of(p)
		panel._hover_uid = &""
		var boots_text := "%s %s" % [boots_info.title, boots_info.lines]
		var said := InventoryPanel.fire_sentence(roll)
		if err == "" and (split == &"" or not boots_text.contains("生效中") or boots_text.contains("發動") or said.contains("磨損皮靴") or said.contains("分裂") or not said.contains(String(ItemDefs.ITEMS[&"smoke_bomb"].name))):
			err = "袋子裡的數值道具說明應寫生效中、不寫發動：%s；「一起放」只列效果與技能：%s" % [boots_text, said]
		# 修飾的說明寫透明格要蓋在技能上（第 8 步 f），不再寫「同一袋」
		if err == "":
			panel._hover_uid = split
			var split_text := "%s" % [panel._info_of(p).lines]
			panel._hover_uid = &""
			if not split_text.contains("透明格") or split_text.contains("同一袋"):
				err = "修飾的說明應寫透明格蓋在技能上：%s" % split_text
	# 倉庫不管形狀：4 格長的法杖放在倉庫最後一格，拖動時落點就是滑鼠那一格
	if err == "":
		var staff_uid := StringName("board_staff")
		p.loadout.inventory.add(staff_uid, &"staff", Vector2i(5, 0), 0, {"weapon": WeaponDropDefs.make(staff_uid, &"staff", &"white", w.rng)})
		panel._start_drag(p, panel._grid_origin() + (Vector2(5, 0) + Vector2(0.5, 0.5)) * InventoryPanel.CELL)
		panel._finish_drag(p, panel._grid_origin() + (Vector2(4, 0) + Vector2(0.5, 0.5)) * InventoryPanel.CELL)
		if ops != [[InputCmd.OP_MOVE, String(staff_uid), 4, 0, 0, Loadout.BAG]]:
			err = "倉庫的法杖拖到 (4, 0) 應送 OP_MOVE 到 (4, 0)：%s" % [ops]
	hud.queue_free()
	cam.queue_free()
	return err


# 視野看滑鼠的方向：翻滾時身體轉向翻滾方向，前方（滑鼠那邊）照樣看得到、翻滾的方向（側面）照樣看不到；畫面的扇形遮罩用同一個方向
static func check_vision_aim() -> String:
	var w := _new_world()
	var p := _player(w)
	p.pos = Vector2.ZERO
	var front := Vector2(0.0, 10.0)
	var side := Vector2(10.0, 0.0)
	var roll := _cmd(Vector2(1.0, 0.0), front, InputCmd.BTN_ROLL)
	_run(w, _cmd(Vector2.ZERO, front), 30)
	_run(w, roll, 3)
	if not p.action.is_in(&"roll") or absf(MathUtil.wrap_angle(p.facing - PI / 2.0)) > 0.3:
		return "往 +X 翻滾時身體應朝 +X（動作 %s、朝向 %.2f）" % [p.action.current_name, p.facing]
	var eye := p.pos + front
	if not Vision.point_visible(w, p, eye) or Vision.point_visible(w, p, p.pos + side):
		return "翻滾中視野應照滑鼠方向（前方 %s、翻滾那邊 %s）" % [Vision.point_visible(w, p, eye), Vision.point_visible(w, p, p.pos + side)]
	if absf(MathUtil.wrap_angle(p.view_facing() - MathUtil.angle_to(p.pos, front))) > 1e-3:
		return "view_facing 應是滑鼠的方向"
	return ""


# 在介面上按下的滑鼠鍵放開前不算攻擊：點遺物卡片（背包開著）選完、背包自動關掉時左鍵還按著，不能接著普攻；放開再按就照常
static func check_ui_click_blocks_attack() -> String:
	InputCollector.register_actions()
	var c := InputCollector.new()
	_scene_root().add_child(c)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	var err := ""
	c.mouse_captured = true
	Input.action_press(&"attack")
	c._input(press)
	c.mouse_captured = false   # 選完遺物：面板和自動打開的背包一起關
	if c._held_buttons() & InputCmd.BTN_ATTACK != 0 or c._latched & InputCmd.BTN_ATTACK != 0:
		err = "在背包上按下的左鍵，背包關掉後還按著不應算普攻"
	Input.action_release(&"attack")
	c._input(release)
	if err == "":
		Input.action_press(&"attack")
		c._input(press)
		if c._held_buttons() & InputCmd.BTN_ATTACK == 0 or c._latched & InputCmd.BTN_ATTACK == 0:
			err = "放開再按（不在介面上）應照常普攻"
		Input.action_release(&"attack")
		c._input(release)
	c.queue_free()
	return err


# 遺物卡片寫出拿過沒：同一種道具已經鑲著（羈絆不會重複算）、只在背包裡；沒有的不寫
static func check_relic_owned() -> String:
	var w := _new_world(5)
	var cam := _test_camera()
	var hud: Variant = load("res://ui/hud.tscn").instantiate()
	hud.setup(w, cam)
	_scene_root().add_child(hud)
	var p := _player(w)
	var ids := ItemDefs.item_ids().filter(func(id: StringName) -> bool: return not ItemDefs.ITEMS[id].get("bonds", []).is_empty() and ItemDefs.ITEMS[id].shape == &"dot")
	var err := ""
	p.loadout.add_item(p, ids[0])
	p.loadout.add_item(p, ids[1], {"cell": Vector2i(0, 0), "rot": 0}, 0, Loadout.BAG)
	if not p.loadout.items.any(func(it: Dictionary) -> bool: return it.id == ids[0]):
		err = "前置：%s 應自動鑲上" % ids[0]
	var relic := w.drop_relic(&"big", p.pos + Vector2(1.0, 0))
	relic.open_for(p)
	relic.offers[p.peer_id] = ids.slice(0, 3)
	var panel: RelicPanel = hud.relic_panel
	panel.refresh(w, p)
	if err == "":
		var texts := func(i: int) -> Array: return panel._cards.get_child(i).find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
		if not texts.call(0).has(RelicPanel.OWNED_ACTIVE):
			err = "已經鑲著的道具卡片應寫「%s」：%s" % [RelicPanel.OWNED_ACTIVE, texts.call(0)]
		elif not texts.call(1).has(RelicPanel.OWNED_BAG):
			err = "背包裡有的道具卡片應寫「%s」：%s" % [RelicPanel.OWNED_BAG, texts.call(1)]
		elif texts.call(2).has(RelicPanel.OWNED_ACTIVE) or texts.call(2).has(RelicPanel.OWNED_BAG):
			err = "沒拿過的道具卡片不應寫拿過：%s" % [texts.call(2)]
	hud.queue_free()
	cam.queue_free()
	return err


# ───────── 角色骨架與動作 ─────────

const LIMB_KINDS: Array[StringName] = [&"player", &"grunt", &"archer", &"zombie", &"bloater", &"hound", &"spider", &"beetle",
	&"spearman", &"gravekeeper", &"werewolf", &"boss", &"bone_colossus"]


# 每種角色都有手肘與膝蓋：前臂 / 小腿關節在上臂 / 大腿下 elbow / knee 的位置、手掌掛在前臂下（肩膀到拳頭中心還是 grip）、
# 前臂與小腿上有零件；第二隻起用模板組出來的也一樣
static func check_limb_joints() -> String:
	for kind: StringName in LIMB_KINDS:
		for round_i in 2:
			var rig := DarkFantasy.player_character(ClassDefs.ORDER[0]) if kind == &"player" else DarkFantasy.character(kind)
			var j: Dictionary = rig.to_template().joints
			var err := ""
			var grip: float = -(rig.forearm_r.position.y + rig.hand_r.position.y)
			if rig.hand_r.get_parent() != rig.forearm_r or rig.hand_l.get_parent() != rig.forearm_l:
				err = "手掌掛點應掛在前臂下"
			elif rig.shin_r.get_parent() != rig.leg_r or rig.forearm_l.get_parent() != rig.arm_l:
				err = "小腿應在大腿下、前臂應在上臂下"
			elif absf(rig.forearm_r.position.y + Rig.elbow_of(j)) > 1e-4 or absf(rig.shin_l.position.y + Rig.knee_of(j)) > 1e-4:
				err = "手肘 / 膝蓋的位置應照關節資料 elbow %.2f / knee %.2f" % [Rig.elbow_of(j), Rig.knee_of(j)]
			elif absf(grip - float(j.grip)) > 1e-4:
				err = "肩膀到拳頭中心應是 grip %.2f：%.2f" % [j.grip, grip]
			else:
				for seg: Node3D in [rig.forearm_r, rig.forearm_l, rig.shin_r, rig.shin_l]:
					if not seg.get_children().any(func(c: Node) -> bool: return c is MeshInstance3D):
						err = "%s 上沒有零件（前臂 / 小腿的零件要掛在那一節，彎的時候才會跟著動）" % seg.name
			rig.free()
			if err != "":
				return "%s（第 %d 隻）：%s" % [kind, round_i + 1, err]
	return ""


# 腳底的角色座標（照目前的腿角度算）
static func _sole(rig: Rig, right: bool) -> Vector3:
	var leg := rig.leg_r if right else rig.leg_l
	var shin := rig.shin_r if right else rig.shin_l
	var lower := leg.position.y + shin.position.y
	var local := leg.position + leg.basis * (shin.position + shin.basis * Vector3(0.0, -lower, 0.0))
	return BodyPose.body_to_root(rig, local)


# 倒地：Boss 類（關節版）倒下到沉入地面前，手臂、拳頭、掉下去的武器（劍、鏟子、提燈）都不穿進地裡，拳頭貼地（不浮在空中）；
# 武器離開手、躺在地上（離地 0.12 內），屍體沉完時跟著沉到地面下（純動畫，跟屍體一起消失）。玩家拿 8 把武器趴倒時，手臂、掉下去的武器、盾都不穿地（看得到的零件）、武器離開手；
# 假死被救起來武器回到手上
static func check_dead_lie() -> String:
	var rec := AnimRecorder.new()
	var err := ""
	for weapon: StringName in AnimRecorder.PLAYER_WEAPONS:
		for row: Dictionary in rec.rows("player-%s" % weapon, false):
			if row.key != "dead":
				continue
			var made: Dictionary = (row.make as Callable).call()
			var rig: Rig = made.rig
			var low := INF
			for i in (row.frames as Array).size():
				AnimRecorder.step(row, made, i)
				if i >= int(row.start):
					for j: Node3D in [rig.arm_r, rig.arm_l]:
						low = minf(low, _shown_low(rig, j))
			var held: Node3D = rig.held_l if weapon in [&"shortbow", &"longbow"] else rig.held_r
			var off := held.position.length()
			var rest := _shown_low(rig, held)
			if low < -0.01:
				err = "玩家拿%s趴倒時手臂或武器穿進地裡 %.3f" % [WeaponDefs.WEAPONS[weapon].name, low]
			elif off < 0.2 or rest > 0.12:
				err = "玩家拿%s死掉時武器應掉到地上：離手 %.2f、最低點離地 %.2f" % [WeaponDefs.WEAPONS[weapon].name, off, rest]
			elif weapon == &"swordShield":
				err = _revive_rearm(row, made)
			rig.free()
			if err != "":
				break
		if err != "":
			rec.clear()
			return err
	for model: String in ["gravekeeper", "boss", "bone_general"]:
		for row: Dictionary in rec.rows("enemy-%s" % model):
			if row.key != "dead":
				continue
			var made: Dictionary = (row.make as Callable).call()
			var rig: Rig = made.rig
			var low := INF
			var lowest := ""
			for i in (row.frames as Array).size():
				AnimRecorder.step(row, made, i)
				if i < int(row.start):
					continue
				for nm: StringName in [&"arm_r", &"arm_l", &"forearm_r", &"forearm_l", &"hand_r", &"hand_l", &"held_r", &"held_l"]:
					var y := _joint_mesh_low(rig, rig.get(nm))
					if y < low:
						low = y
						lowest = "%s 第 %d 步" % [nm, i - int(row.start)]
			var fist := BodyPose.body_to_root(rig, BodyPose.hand_pos(rig, true)).y / rig.body.scale.y
			var off := rig.held_r.position.length()
			var rest := _joint_mesh_low(rig, rig.held_r)
			var e: Enemy = row.subject
			var a: Dictionary = e.anim.duplicate()
			a.time = e.def.corpse_time
			e.anim = a
			made.anim.update(e, DT)
			var gone := -_joint_mesh_low(rig, rig.held_r, true)
			rig.free()
			if off < 0.1 or rest > 0.12:
				err = "%s 死掉時武器應掉到地上：離手 %.2f、最低點離地 %.2f" % [model, off, rest]
			elif gone > 0.0:
				err = "%s 屍體沉完時武器應跟著沉到地面下：最高點還在 %.2f" % [model, gone]
			elif low < -0.01:
				err = "%s 倒地時 %s 穿進地裡 %.3f" % [model, lowest, low]
			elif fist > EnemyAnimator.DEAD_FIST + 0.02:
				err = "%s 倒地後拳頭浮在空中：%.3f（× 縮放）" % [model, fist]
			else:
				_note("%s 倒地最低 %.3f（%s）" % [model, low, lowest])
		if err != "":
			break
	rec.clear()
	return err


# 右鍵的專屬動作：火把噴火推出時火把頭朝正前方；鐵鏟鏟拋起手時鏟面碰到地（不插深）、收招時把鏟子掀過頭
static func check_special_poses() -> String:
	var rec := AnimRecorder.new()
	var err := ""
	for weapon: String in ["torch", "shovel"]:
		for row: Dictionary in rec.rows("player-%s" % weapon, false):
			if row.key != "special":
				continue
			var made: Dictionary = (row.make as Callable).call()
			var rig: Rig = made.rig
			var head := -INF      # 噴火推出時火把頭朝前的程度（+Y 的 z）
			var scoop := INF      # 鏟拋起手時鏟子最低點
			var lift := -INF      # 鏟拋收招時拳頭最高
			for i in (row.frames as Array).size():
				AnimRecorder.step(row, made, i)
				var a: Dictionary = row.frames[i].anim
				if a.action != &"special":
					continue
				var t := _hand_tf(rig, true)
				if weapon == "torch" and a.phase == &"active" and a.k > 0.6:
					head = maxf(head, (t.basis * Vector3.UP).normalized().z)
				elif weapon == "shovel" and a.phase == &"windup":
					scoop = minf(scoop, _node_low(rig, rig.weapon_main))
				elif weapon == "shovel" and a.phase == &"recovery":
					lift = maxf(lift, t.origin.y)
			rig.free()
			if weapon == "torch" and head < 0.95:
				err = "噴火推出時火把頭應朝正前方：%.2f" % head
			elif weapon == "shovel" and (scoop < -0.08 or scoop > 0.08 or lift < 1.9):
				err = "鏟拋應先把鏟面插到地面（最低 %.2f）、再掀過頭（拳頭最高 %.2f）" % [scoop, lift]
			else:
				_note("噴火推出時火把頭朝前 %.2f" % head if weapon == "torch" else "鏟拋鏟面最低 %.2f、掀起時拳頭最高 %.2f" % [scoop, lift])
		if err != "":
			break
	rec.clear()
	return err


# 第 3 層的兩招手的動作：屍巫唸咒到最後兩手合攏在胸前（靠近中線、在身前）；尖嘯幽影尖嘯時兩手伸直往外張（比肩膀寬很多、大約肩膀高）
static func check_floor3_poses() -> String:
	var rec := AnimRecorder.new()
	var err := ""
	for spec: Array in [["lich", "aim"], ["wraith", "shriek"]]:
		for row: Dictionary in rec.rows("enemy-%s" % spec[0]):
			if row.key != spec[1]:
				continue
			var made: Dictionary = (row.make as Callable).call()
			var rig = made.rig
			AnimRecorder.replay(row, made, (row.frames as Array).size() - 1)
			var r := BodyPose.hand_pos(rig, true)
			var l := BodyPose.hand_pos(rig, false)
			var shoulder: float = rig.arm_l.position.y
			(rig as Node).free()
			if spec[0] == "lich" and not (absf(r.x) < 0.2 and absf(l.x) < 0.2 and r.z > 0.25 and l.z > 0.25):
				err = "屍巫唸咒時兩手應合攏在胸前：右 %s、左 %s" % [r, l]
			elif spec[0] == "wraith" and not (l.x - r.x > 1.2 and r.y > shoulder - 0.3 and l.y > shoulder - 0.3):
				err = "尖嘯幽影尖嘯時兩手應往外張開、大約肩膀高：右 %s、左 %s（肩膀 %.2f）" % [r, l, shoulder]
			else:
				_note("%s %s 兩手：右 %s、左 %s" % [spec[0], spec[1], r, l])
		if err != "":
			break
	rec.clear()
	return err


# node 底下所有零件的最低點（角色根節點座標）
static func _node_low(rig: Node3D, node: Node3D) -> float:
	var low := INF
	for mi in PartKit.mesh_instances(node):
		var t := Transform3D.IDENTITY
		var n: Node3D = mi
		while n != rig:
			t = Transform3D(Basis.from_euler(n.rotation, EULER_ORDER_YXZ).scaled_local(n.scale), n.position) * t if not (n is MeshInstance3D) else n.transform * t
			n = n.get_parent() as Node3D
		for v: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			low = minf(low, (rig.transform * t * v).y)
	return low


# 假死被救起來（倒地 → 站起來）武器回到手上：手持關節回到單位矩陣
static func _revive_rearm(row: Dictionary, made: Dictionary) -> String:
	var p: Player = row.subject
	var a: Dictionary = p.anim.duplicate()
	a.loco = &"idle"
	a.loco_time = 0.0
	p.anim = a
	made.anim.update(p, DT)
	var rig: Rig = made.rig
	if not Transform3D(Basis.from_euler(rig.held_r.rotation, EULER_ORDER_YXZ), rig.held_r.position).is_equal_approx(Transform3D.IDENTITY):
		return "假死站起來後武器應回到手上：手持關節 %s / %s" % [rig.held_r.position, rig.held_r.rotation]
	return ""


# node 底下看得到的零件最低點（角色根節點座標；隱藏的不算，例如沒拉弓時搭弦的箭）
static func _shown_low(rig: Node3D, node: Node3D) -> float:
	var low := INF
	for mi in PartKit.mesh_instances(node):
		var t := Transform3D.IDENTITY
		var n: Node3D = mi
		var shown := true
		while n != rig:
			shown = shown and n.visible
			t = n.transform * t
			n = n.get_parent() as Node3D
		if shown:
			for v: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				low = minf(low, (rig.transform * t * v).y)
	return low


# joint 這一節自己的零件最低點（角色根節點座標；場景樹還沒就緒，沿節點一層層乘）；high = true 回傳最高點的負值
static func _joint_mesh_low(rig: Node3D, joint: Node3D, high := false) -> float:
	var t := Transform3D.IDENTITY
	var n := joint
	while n != rig:
		t = n.transform * t
		n = n.get_parent() as Node3D
	t = rig.transform * t
	var low := INF
	for mi in PartKit.mesh_instances(joint):
		if mi.get_parent() == joint:
			for v: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				var y := (t * mi.transform * v).y
				low = minf(low, -y if high else y)
	return low


# 步態與站姿照真實動作（docs/動作參考.md）：走路擺盪期膝蓋最多彎 50~75°、跑步 90~125°、跑步髖部往前抬 55~85°；
# 踩在地上的那隻腳在踩地中段貼地（< 0.05）；上身前傾 0.5 時從髖部彎（腳還在地上、髖部在腳的正上方）；蹲低 0.3 腿長時膝蓋彎 60~120°
static func check_gait_pose() -> String:
	var rig := DarkFantasy.player_character(ClassDefs.ORDER[0])
	var leg := BodyPose.leg_length(rig)
	var err := ""
	var nums := []
	for spec: Array in [[1.6, 50.0, 75.0, "走路"], [6.5, 90.0, 125.0, "跑步"]]:
		var knee_max := 0.0
		var hip_max := 0.0
		var slip := 0.0
		for i in 60:
			var g := BodyPose.gait(rig, TAU * i / 60.0, 1.0, spec[0])
			rig.body.rotation = Vector3(g.lean, 0.0, 0.0)
			BodyPose.plant(rig, g.r, g.l, g.drop)
			knee_max = maxf(knee_max, rad_to_deg(rig.shin_r.rotation.x))
			hip_max = maxf(hip_max, -rad_to_deg(rig.leg_r.rotation.x))
			var duty := lerpf(BodyPose.DUTY_WALK, BodyPose.DUTY_RUN, g.run)
			if absf(g.u - duty / 2.0) < duty * 0.25:   # 右腳踩地中段
				slip = maxf(slip, _sole(rig, true).distance_to(g.r))
		nums.append("%s 膝 %.0f° 髖 %.0f° 腳底誤差 %.3f" % [spec[3], knee_max, hip_max, slip])
		if knee_max < spec[1] or knee_max > spec[2]:
			err = "%s擺盪期膝蓋最多彎 %.0f°，應在 %.0f~%.0f°" % [spec[3], knee_max, spec[1], spec[2]]
		elif spec[3] == "跑步" and (hip_max < 55.0 or hip_max > 85.0):
			err = "跑步髖部往前抬 %.0f°，應在 55~85°" % hip_max
		elif slip > 0.05:
			err = "%s踩地中段腳底離目標 %.3f（應貼地）" % [spec[3], slip]
		if err != "":
			break
	if err == "":
		BodyPose.straighten(rig)
		rig.body.rotation = Vector3(0.5, 0.0, 0.0)
		BodyPose.stand(rig, 0.0)
		var sr := _sole(rig, true)
		var hip := BodyPose.body_to_root(rig, rig.leg_r.position)
		if absf(sr.y) > 0.01 or absf(sr.z) > 0.01 or absf(hip.z) > 0.01:
			err = "上身前傾時應從髖部彎：腳底 %s、髖部 %s" % [sr, hip]
	if err == "":
		rig.body.rotation = Vector3.ZERO
		BodyPose.stand(rig, 0.3 * leg)
		var knee := rad_to_deg(rig.shin_l.rotation.x)
		var sl := _sole(rig, false)
		nums.append("蹲低 0.3 腿長膝 %.0f°" % knee)
		if knee < 60.0 or knee > 120.0 or absf(sl.y) > 0.01:
			err = "蹲低 0.3 腿長時膝蓋應彎 60~120°、腳底貼地：%.0f°、腳底高 %.3f" % [knee, sl.y]
	rig.free()
	_note("步態：%s" % ", ".join(nums))
	return err


static func _limb_snapshot(rig: Rig) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for n: Node3D in [rig.body, rig.arm_r, rig.arm_l, rig.forearm_r, rig.forearm_l, rig.leg_r, rig.leg_l, rig.shin_r, rig.shin_l]:
		for v in [n.rotation.x, n.rotation.y, n.rotation.z]:
			out.append(v)
	return out


# 每招戰技都有自己的角色動作：拿那招的第一把武器，做到一半時關節角度（身體、上臂、前臂、大腿、小腿）和站著不動合計差超過 0.8 弧度、
# 數值都是有限的、腳沒有踩進地裡（掘地鑽進地裡、後跳射在空中除外）；做完回到普通姿勢
static func check_skill_poses() -> String:
	var w := _new_world()
	var p := _player(w)
	var rig := DarkFantasy.player_character(ClassDefs.ORDER[0])
	var anim := Animator.new(rig)
	var err := ""
	var count := 0
	for id: StringName in SkillDefs.SKILLS:
		var def: Dictionary = SkillDefs.SKILLS[id]
		if def.get("category", &"") != &"attack":
			continue
		count += 1
		p.equip_weapon(def.weapons[0])
		_run(w, _cmd(Vector2.ZERO), 2)
		for i in 20:
			anim.update(p, DT)
		var idle := _limb_snapshot(rig)
		var total := SkillDefs.pose_time(id)
		p.anim["skill"] = id
		p.anim["skill_time"] = total * 0.5
		anim.update(p, DT)
		var mid := _limb_snapshot(rig)
		var diff := 0.0
		for i in mid.size():
			if not is_finite(mid[i]):
				err = "%s 做到一半有不是有限數的關節角度" % id
				break
			diff += absf(mid[i] - idle[i])
		if err == "" and diff < 0.8:
			err = "%s 做到一半和站著幾乎一樣：關節角度合計只差 %.2f（至少 0.8）" % [id, diff]
		if err == "" and not (id in [&"burrow", &"leap_shot"]):
			var low := minf(_sole(rig, true).y, _sole(rig, false).y)
			if low < -0.03:
				err = "%s 做到一半腳踩進地裡 %.2f" % [id, low]
		p.anim["skill"] = &""
		anim.update(p, DT)
		if err != "":
			break
	rig.free()
	if err == "" and count != 18:
		err = "戰技應有 18 招（§45）：%d" % count
	return err


# 動作表與動畫檢視器（AnimRecorder）：每個角色都錄得出動作、每段從頭播到尾關節角度都是有限數；
# 玩家 8 把武器底下合起來剛好是全部的戰技（每招掛在它的第一把武器）
static func check_anim_recorder() -> String:
	var rec := AnimRecorder.new()
	var err := ""
	var skill_rows := 0
	var total := 0
	for s: Dictionary in AnimRecorder.subjects():
		var rows := rec.rows(s.id)
		if rows.is_empty():
			err = "%s 沒有錄到動作" % s.id
		for row: Dictionary in rows:
			if err != "":
				break
			total += 1
			if String(row.name).begins_with("戰技"):
				skill_rows += 1
			var frames: Array = row.frames
			if frames.size() <= int(row.get("start", 0)):
				err = "%s 的 %s 沒有步數" % [s.id, row.key]
				break
			var made: Dictionary = (row.make as Callable).call()
			for i in frames.size():
				AnimRecorder.step(row, made, i)
			if s.id in ["player-swordShield", "enemy-gravekeeper"]:   # 腳步改成原地 / 跑也播得完
				for foot: float in [0.0, 5.0]:
					for i in frames.size():
						AnimRecorder.step(row, made, i, foot)
			var rig = made.rig
			for j in [rig.body, rig.arm_r, rig.forearm_r, rig.leg_l, rig.shin_l]:
				var r: Vector3 = j.rotation
				if not (is_finite(r.x) and is_finite(r.y) and is_finite(r.z)):
					err = "%s 的 %s 播完關節角度不是有限數" % [s.id, row.key]
			(rig as Node).free()
		if err == "" and s.id == "enemy-gravekeeper":
			err = _check_split_rows(rows)
		rec.clear()
		if err != "":
			break
	if err == "" and skill_rows != AnimRecorder.skill_ids().size():
		err = "玩家的動作裡戰技應有 %d 招：%d" % [AnimRecorder.skill_ids().size(), skill_rows]
	_note("動畫檢視器：%d 個角色、%d 段動作（戰技 %d）" % [AnimRecorder.subjects().size(), total, skill_rows])
	return err


# 守墓人拆開的招式（AnimRecorder.SPLITS）每段都錄得到、只含那一招的 phase，同一次錄的段落頭尾相接
static func _check_split_rows(rows: Array) -> String:
	var step_time: float = EnemyDefs.ENEMIES.gravekeeper.scoop.bury.step_time
	var want := {
		"scoop": [&"windup"], "scoop_miss": [&"miss"], "scoop_throw": [&"throw"], "scoop_bury": [&"bury"], "scoop_flame": [&"bury"],
		"lantern": [&"windup", &"flame"], "lantern_spin": [&"spin_windup", &"spin", &"recovery"],
	}
	for key: String in want:
		var row: Dictionary = {}
		for r: Dictionary in rows:
			if r.key == key:
				row = r
		if row.is_empty():
			return "守墓人的動作裡沒有 %s（拆開的招式沒錄到）" % key
		var frames: Array = row.frames
		for i in range(row.start, row.end):
			var a: Dictionary = frames[i].anim
			var ph: StringName = a.get("phase", &"")
			var t: float = a.get("phase_time", 0.0)
			if not (ph in want[key]) or (key == "scoop_bury" and t >= step_time) or (key == "scoop_flame" and t < step_time - 1e-6):
				return "守墓人的 %s 第 %d 步混進別的招式：phase %s、%.2f 秒" % [key, i - row.start, ph, t]
		var path: Array = row.path
		for n in path.size():
			if (n > 0 and path[n][1] != path[n - 1][2]) or (path[n][0] == key and (path[n][1] != row.start or path[n][2] != row.end)):
				return "守墓人的 %s 的段落沒有頭尾相接：%s" % [key, path]
		if path[-1][2] != frames.size():
			return "守墓人的 %s 的最後一段應演到狀態結束：%s / %d" % [key, path, frames.size()]
	return ""


# 動畫檢視器：拆開的招式接著演（反白跟著段落走、演完從起手重來）、關掉接著演只循環那一段；
# 走跑循環時角色接著往前（每步走的距離不變、腿不跳）、地板跟著；換動作視角不變
static func check_anim_viewer() -> String:
	var v := AnimViewer.new()
	_scene_root().add_child(v)
	await (Engine.get_main_loop() as SceneTree).process_frame   # _ready 要等場景樹跑一幀
	v.select("enemy-gravekeeper", "scoop_bury")
	var err := ""
	for b in v.find_children("*", "Button", true, false):
		if (b as Button).text == "回主選單":
			err = "從編輯器開的檢視器（沒有遊戲可以回）不應有「回主選單」"
	if err == "":
		err = _viewer_chain(v)
	if err == "":
		err = _viewer_loop(v)
	v.queue_free()
	return err


static func _viewer_chain(v: AnimViewer) -> String:
	var view: Array = v.status().view
	var seen: Array = [v.status().key]
	for i in 600:
		v.advance(1)
		if seen[-1] != v.status().key:
			seen.append(v.status().key)
	if seen.slice(0, 5) != ["scoop_bury", "scoop_flame", "scoop", "scoop_bury", "scoop_flame"]:
		return "接著演：從埋地開始應接噴火、再從起手重來：%s" % [seen]
	v.set_chain(false)
	v.select("enemy-gravekeeper", "scoop_bury")
	for i in 300:
		v.advance(1)
		if v.status().key != "scoop_bury":
			return "關掉接著演應只循環埋地那一段：第 %d 步演到 %s" % [i, v.status().key]
	v.set_chain(true)
	if v.status().view != view:
		return "換動作後視角變了：%s → %s" % [view, v.status().view]
	return ""


static func _viewer_loop(v: AnimViewer) -> String:
	v.select("player-swordShield", "run")
	var r: Vector2i = v.status().range
	var prev: Vector2 = v.status().pos
	var leg: float = v.status().rig.leg_r.rotation.x
	var steps: Array[float] = []
	var swing := 0.0        # 一步之內大腿最多轉多少（不含循環那一步）
	var wrap_swing := 0.0   # 循環那一步大腿轉多少
	for i in (r.y - r.x) * 3:
		v.advance(1)
		var st := v.status()
		steps.append((st.pos as Vector2).distance_to(prev))
		prev = st.pos
		var now: float = st.rig.leg_r.rotation.x
		if st.frame == r.x:
			wrap_swing = maxf(wrap_swing, absf(now - leg))
		else:
			swing = maxf(swing, absf(now - leg))
		leg = now
		var off: Vector2 = (st.floor as Vector2) - (st.pos as Vector2)
		if maxf(absf(off.x), absf(off.y)) > AnimViewer.FLOOR_SNAP / 2.0 + 0.01:
			return "地板沒跟著角色：角色 %s、地板 %s" % [st.pos, st.floor]
	var lo: float = steps.min()
	var hi: float = steps.max()
	if lo < 0.05 or hi > lo * 1.2:
		return "跑步循環時每一步走的距離應該一樣（不跳回起點、不停頓）：最少 %.3f、最多 %.3f" % [lo, hi]
	if wrap_swing > swing * 1.5:
		return "跑步循環接回去時腿跳了一下：%.2f 弧度（平常一步最多 %.2f）" % [wrap_swing, swing]
	_note("動畫檢視器跑步循環 3 次：每步 %.3f ~ %.3f、走到 %.1f，腿一步最多轉 %.2f（接回去那步 %.2f）" % [lo, hi, prev.length(), swing, wrap_swing])
	return ""
