# 產生音效 WAV（headless，在 godot/ 內）：<Godot> --headless --path . -s res://tools/bake_sfx.gd
# 配方照搬網頁版 legacy/src/audio/Sound.js 的 CUES（名稱、參數逐一對應）；噪音用固定種子，重跑結果相同
# 網頁版有隨機的部分（噪音起點、骷髏死亡的碎裂間隔）在這裡固定成一種
extends SceneTree

const OUT_DIR := "res://audio/sfx/"
const MAX_SECONDS := 2.5
const TAIL_THRESHOLD := 0.0005   # 結尾低於此音量的部分剪掉


static func cues() -> Dictionary:
	return {
		# 玩家攻擊
		"swing": func(s: Synth) -> void: s.noise(0, {"dur": 0.13, "vol": 0.32, "from": 2200, "to": 600, "q": 1.5}),
		"swingHeavy": func(s: Synth) -> void:
			s.noise(0, {"dur": 0.2, "vol": 0.3, "from": 1500, "to": 300, "q": 1.2})
			s.tone(0, {"type": &"triangle", "from": 140, "to": 60, "dur": 0.2, "vol": 0.18}),
		"shieldBash": func(s: Synth) -> void:
			s.noise(0, {"dur": 0.25, "vol": 0.28, "type": &"lowpass", "from": 1800, "to": 200})
			s.tone(0, {"from": 110, "to": 40, "dur": 0.22, "vol": 0.35}),
		"fireBolt": func(s: Synth) -> void:
			s.tone(0, {"type": &"sawtooth", "from": 260, "to": 900, "dur": 0.14, "vol": 0.12, "filter": 1800})
			s.noise(0, {"dur": 0.18, "vol": 0.12, "type": &"highpass", "from": 3000, "to": 1500}),
		"arcaneCast": func(s: Synth) -> void:
			s.tone(0, {"type": &"triangle", "from": 380, "to": 1150, "dur": 0.32, "vol": 0.14})
			s.tone(0, {"from": 760, "to": 2300, "dur": 0.32, "vol": 0.06, "delay": 0.03}),
		"explosion": func(s: Synth) -> void:
			s.noise(0, {"dur": 0.55, "vol": 0.4, "type": &"lowpass", "from": 1600, "to": 90})
			s.tone(0, {"from": 90, "to": 30, "dur": 0.45, "vol": 0.4}),

		# 命中
		"hit": func(s: Synth) -> void:
			s.noise(0, {"dur": 0.06, "vol": 0.25, "type": &"highpass", "from": 2500, "to": 1200})
			s.tone(0, {"type": &"triangle", "from": 200, "to": 90, "dur": 0.09, "vol": 0.25}),
		"hitHeavy": func(s: Synth) -> void:
			s.noise(0, {"dur": 0.12, "vol": 0.32, "type": &"bandpass", "from": 1800, "to": 500, "q": 0.8})
			s.tone(0, {"from": 150, "to": 45, "dur": 0.18, "vol": 0.4}),
		"playerHurt": func(s: Synth) -> void:
			s.tone(0, {"type": &"square", "from": 240, "to": 110, "dur": 0.16, "vol": 0.14, "filter": 1200})
			s.noise(0, {"dur": 0.1, "vol": 0.18, "type": &"lowpass", "from": 900, "to": 200}),

		# 道具技能
		"potion": func(s: Synth) -> void:
			var notes := [523, 659, 784, 1047]
			for i in notes.size():
				s.tone(0, {"from": notes[i], "dur": 0.18, "vol": 0.12, "delay": i * 0.06})
			s.noise(0, {"dur": 0.25, "vol": 0.06, "type": &"highpass", "from": 4000, "to": 6000}),
		"sprint": func(s: Synth) -> void: s.noise(0, {"dur": 0.3, "vol": 0.45, "from": 400, "to": 2400, "q": 1.2}),
		"denied": func(s: Synth) -> void:
			s.tone(0, {"type": &"square", "from": 150, "dur": 0.06, "vol": 0.08, "filter": 900})
			s.tone(0, {"type": &"square", "from": 120, "dur": 0.07, "vol": 0.08, "filter": 900, "delay": 0.08}),

		# 敵人
		"enemySpawn": func(s: Synth) -> void: s.noise(0, {"dur": 0.45, "vol": 0.25, "type": &"lowpass", "from": 400, "to": 120, "attack": 0.08}),
		"bowDraw": func(s: Synth) -> void: s.tone(0, {"type": &"triangle", "from": 180, "to": 320, "dur": 0.5, "vol": 0.05, "attack": 0.15, "filter": 900}),
		"arrowShot": func(s: Synth) -> void:
			s.noise(0, {"dur": 0.09, "vol": 0.18, "from": 3500, "to": 1400, "q": 2})
			s.tone(0, {"type": &"triangle", "from": 340, "to": 240, "dur": 0.12, "vol": 0.12}),
		# 小怪前搖（Godot 版加的；每種怪一個、同一隻的兩招不重複）：骨頭喀啦 + 刀刮、低沉呻吟、短吠、低吼、金屬滑過、土塊跳動、吸氣、咕嚕
		"skeletonRaise": func(s: Synth) -> void:
			for i in 5:
				s.noise(0, {"dur": 0.03, "vol": 0.16, "type": &"highpass", "from": 2600 + i * 300, "delay": i * 0.05})
			s.noise(0, {"dur": 0.3, "vol": 0.08, "from": 3000, "to": 5000, "q": 3, "attack": 0.1, "delay": 0.1}),
		"zombieGroan": func(s: Synth) -> void:
			s.tone(0, {"type": &"sawtooth", "from": 95, "to": 75, "dur": 0.45, "vol": 0.16, "attack": 0.1, "filter": 500})
			s.noise(0, {"dur": 0.4, "vol": 0.1, "type": &"lowpass", "from": 600, "to": 250, "attack": 0.1}),
		"houndBark": func(s: Synth) -> void:
			s.tone(0, {"type": &"square", "from": 520, "to": 300, "dur": 0.09, "vol": 0.1, "filter": 1400})
			s.noise(0, {"dur": 0.08, "vol": 0.16, "from": 1500, "to": 700, "q": 1.5}),
		"houndGrowl": func(s: Synth) -> void:
			for i in 6:
				s.tone(0, {"type": &"sawtooth", "from": 72, "to": 62, "dur": 0.06, "vol": 0.4, "filter": 350, "delay": i * 0.05})
			s.noise(0, {"dur": 0.32, "vol": 0.35, "type": &"lowpass", "from": 380, "to": 220}),
		"spearDraw": func(s: Synth) -> void:
			s.noise(0, {"dur": 0.35, "vol": 0.35, "from": 2800, "to": 4200, "q": 6, "attack": 0.12})
			s.tone(0, {"type": &"triangle", "from": 900, "to": 1200, "dur": 0.3, "vol": 0.12, "attack": 0.1}),
		"beetleDig": func(s: Synth) -> void:
			for i in 6:
				s.noise(0, {"dur": 0.04, "vol": 0.45, "type": &"lowpass", "from": 700, "to": 300, "delay": i * 0.065}),
		"wraithInhale": func(s: Synth) -> void: s.noise(0, {"dur": 0.6, "vol": 0.3, "from": 600, "to": 2400, "q": 1.2, "attack": 0.45}),
		"bloaterGurgle": func(s: Synth) -> void:   # 咕嚕聲越冒越急
			var at := [0.0, 0.1, 0.18, 0.25, 0.31, 0.36, 0.4, 0.44]
			for i in at.size():
				s.tone(0, {"from": 150 + i * 12, "to": 90, "dur": 0.05, "vol": 0.22, "delay": at[i]}),
		"enemyAlert": func(s: Synth) -> void:   # 怪群發現玩家：發現的那一隻短促的吼
			s.tone(0, {"type": &"sawtooth", "from": 150, "to": 260, "dur": 0.22, "vol": 0.16, "attack": 0.03, "filter": 900})
			s.noise(0, {"dur": 0.25, "vol": 0.14, "from": 500, "to": 1400, "q": 1.4, "attack": 0.03}),
		"enemyDeath": func(s: Synth) -> void:
			for i in 4:
				s.noise(0, {"dur": 0.04, "vol": 0.18, "type": &"highpass", "from": 2200 + i * 400, "delay": i * 0.035 + s.rng.randf() * 0.02})
			s.tone(0, {"type": &"square", "from": 260, "to": 70, "dur": 0.25, "vol": 0.06, "filter": 800}),

		# Boss
		"bossSlamWindup": func(s: Synth) -> void: s.tone(0, {"type": &"sawtooth", "from": 55, "to": 110, "dur": 0.6, "vol": 0.12, "attack": 0.3, "filter": 400}),
		"bossSlam": func(s: Synth) -> void:
			s.noise(0, {"dur": 0.7, "vol": 0.45, "type": &"lowpass", "from": 1200, "to": 60})
			s.tone(0, {"from": 70, "to": 25, "dur": 0.6, "vol": 0.5}),
		"bossChargeWindup": func(s: Synth) -> void: s.tone(0, {"type": &"sawtooth", "from": 70, "to": 180, "dur": 0.55, "vol": 0.12, "attack": 0.25, "filter": 600}),
		"bossWallHit": func(s: Synth) -> void:
			s.noise(0, {"dur": 0.4, "vol": 0.4, "type": &"lowpass", "from": 2000, "to": 100})
			s.tone(0, {"from": 100, "to": 35, "dur": 0.35, "vol": 0.4}),
		"bossSummon": func(s: Synth) -> void:
			s.tone(0, {"from": 220, "to": 660, "dur": 0.9, "vol": 0.1, "attack": 0.3})
			s.tone(0, {"from": 233, "to": 700, "dur": 0.9, "vol": 0.08, "attack": 0.3}),
		"enrage": func(s: Synth) -> void:
			s.tone(0, {"type": &"sawtooth", "from": 65, "to": 50, "dur": 1.1, "vol": 0.2, "attack": 0.1, "filter": 500})
			s.noise(0, {"dur": 1.0, "vol": 0.2, "type": &"lowpass", "from": 700, "to": 150, "attack": 0.1}),
		"bossDeath": func(s: Synth) -> void:
			s.noise(0, {"dur": 1.6, "vol": 0.4, "type": &"lowpass", "from": 900, "to": 40, "attack": 0.02})
			s.tone(0, {"type": &"sawtooth", "from": 110, "to": 30, "dur": 1.5, "vol": 0.18, "filter": 400}),

		# 流程
		"waveStart": func(s: Synth) -> void:
			s.tone(0, {"from": 196, "dur": 1.4, "vol": 0.18})
			s.tone(0, {"from": 392, "dur": 1.0, "vol": 0.06})
			s.tone(0, {"from": 587, "dur": 0.7, "vol": 0.03}),
		"bossAppear": func(s: Synth) -> void:
			s.tone(0, {"from": 98, "dur": 2.0, "vol": 0.25})
			s.tone(0, {"from": 104, "dur": 2.0, "vol": 0.15})
			s.tone(0, {"type": &"sawtooth", "from": 49, "dur": 1.8, "vol": 0.08, "filter": 300}),
		"victory": func(s: Synth) -> void:
			var notes := [262, 330, 392, 523]
			for i in notes.size():
				s.tone(0, {"type": &"triangle", "from": notes[i], "dur": 0.9, "vol": 0.13, "delay": i * 0.14}),
		"defeat": func(s: Synth) -> void:
			var notes := [330, 262, 196, 131]
			for i in notes.size():
				s.tone(0, {"type": &"triangle", "from": notes[i], "dur": 0.8, "vol": 0.13, "delay": i * 0.22}),
		"pause": func(s: Synth) -> void: s.tone(0, {"from": 660, "to": 440, "dur": 0.12, "vol": 0.08}),
		"resume": func(s: Synth) -> void: s.tone(0, {"from": 440, "to": 660, "dur": 0.12, "vol": 0.08}),
		"restart": func(s: Synth) -> void: s.tone(0, {"type": &"triangle", "from": 330, "to": 660, "dur": 0.25, "vol": 0.1}),

		# 骰子模式（Godot 版加的）：骰子撞桌、撞牆、撞骰盅的木頭喀一聲（DiceTable.clacked 照撞擊速度給音量）
		"diceClack": func(s: Synth) -> void:
			s.noise(0, {"dur": 0.035, "vol": 0.3, "type": &"bandpass", "from": 2600, "to": 1800, "q": 2.5})
			s.tone(0, {"type": &"triangle", "from": 900, "to": 620, "dur": 0.05, "vol": 0.14}),
	}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var gain: float = Config.AUDIO.baked_gain
	var worst := 0.0
	for cue_name: String in cues():
		var s := Synth.new(MAX_SECONDS, cue_name.hash())
		cues()[cue_name].call(s)
		_trim_tail(s)
		var p := s.peak()
		worst = maxf(worst, p * gain)
		s.save_wav(OUT_DIR + cue_name + ".wav", gain)
		print("%-17s %.3f 秒  峰值 %.3f（寫入後 %.3f）" % [cue_name, s.buf.size() / float(Synth.RATE), p, p * gain])
	print("共 %d 個，寫入後最大峰值 %.3f%s" % [cues().size(), worst, "（超過 1，會失真！）" if worst > 1.0 else ""])
	quit(1 if worst > 1.0 else 0)


static func _trim_tail(s: Synth) -> void:
	var last := 0
	for i in s.buf.size():
		if absf(s.buf[i]) > TAIL_THRESHOLD:
			last = i
	s.buf.resize(last + roundi(0.01 * Synth.RATE))
