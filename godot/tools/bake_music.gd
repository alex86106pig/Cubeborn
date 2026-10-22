# 產生背景音樂 WAV（headless，在 godot/ 內）：<Godot> --headless --path . -s res://tools/bake_music.gd
# 曲目照搬 mockups/背景音樂.html 的「B 哥德輓歌」（使用者選定）：一般戰鬥與 Boss 戰各一首，每首 4 小節循環
# 無縫循環：多算一段尾音後疊回開頭；持續低音的頻率與 LFO 微調成在一個循環內剛好整數圈，接縫不會喀一聲
extends SceneTree

const OUT_DIR := "res://audio/music/"
const D := 50                # D3（MIDI）
const STEPS := 64            # 4 小節 × 16 分音符
const TAIL_SECONDS := 4.5    # 和弦最長 3.6 秒，多算的尾音疊回開頭


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var gain: float = Config.AUDIO.baked_gain
	var worst := 0.0
	for track in [["normal", 64.0, _normal_step, Callable()], ["boss", 92.0, _boss_step, _boss_drone]]:
		var step_dur: float = 60.0 / track[1] / 4.0
		var loop_len := STEPS * step_dur
		var s := Synth.new(loop_len + TAIL_SECONDS, track[0].hash())
		for i in STEPS:
			track[2].call(s, i * step_dur, i)
		s.fold_loop(loop_len)
		if track[3].is_valid():
			track[3].call(s, loop_len)
		var p := s.peak()
		worst = maxf(worst, p * gain)
		s.save_wav(OUT_DIR + track[0] + ".wav", gain, true)
		# 接縫：最後一個樣本到第一個樣本的跳動，應與曲中相鄰樣本的最大跳動同一個等級
		var max_jump := 0.0
		for j in range(1, s.buf.size()):
			max_jump = maxf(max_jump, absf(s.buf[j] - s.buf[j - 1]))
		print("%-7s %d BPM  循環 %.2f 秒  峰值 %.3f  接縫跳動 %.4f（曲中最大 %.4f）" % [
			track[0], track[1], loop_len, p, absf(s.buf[0] - s.buf[-1]), max_jump])
	quit(1 if worst > 1.0 else 0)


# 試聽頁 note()：固定音高，attack 後指數衰減到 dur + release；cutoff 為低通
static func _note(s: Synth, t: float, midi: float, dur: float, vol: float, type: StringName, attack := 0.01, release := 0.0, cutoff := 0.0) -> void:
	s.tone(t, {"type": type, "from": Synth.hz(midi), "dur": dur, "vol": vol, "attack": attack, "release": release, "filter": cutoff})


# 一般戰鬥（64 BPM）：每小節一個小調和弦（方波 + 正弦），每拍一個三角波旋律音
static func _normal_step(s: Synth, t: float, i: int) -> void:
	var chords := [[D - 12, D, D + 3, D + 7], [D - 16, D - 4, D + 2, D + 5], [D - 19, D - 7, D - 2, D + 3], [D - 17, D - 5, D + 1, D + 4]]
	var melody := [D + 15, null, D + 14, D + 12, D + 10, null, D + 12, null, D + 9, null, D + 10, D + 12, D + 13, null, null, null]
	var bar := (i / 16) % 4
	if i % 16 == 0:
		for n: int in chords[bar]:
			_note(s, t, n, 3.6, 0.025, &"square", 0.4, 0.0, 900.0)
			_note(s, t, n, 3.6, 0.03, &"sine", 0.4)
	if i % 4 == 0:
		var m: Variant = melody[(i / 4 + bar * 4) % 16]
		if m != null:
			_note(s, t, m, 0.8, 0.05, &"triangle", 0.05, 0.4)


# Boss 戰（92 BPM）：八分音符鋸齒琶音、每小節方波和弦、每半小節一記低鼓
static func _boss_step(s: Synth, t: float, i: int) -> void:
	var roots := [D - 12, D - 16, D - 19, D - 13]
	var r: int = roots[(i / 16) % 4]
	if i % 2 == 0:
		_note(s, t, r + [0, 12, 7, 12][(i / 2) % 4], 0.14, 0.05, &"sawtooth", 0.01, 0.0, 1200.0)
	if i % 16 == 0:
		for n in [r + 12, r + 15, r + 19]:
			_note(s, t, n, 2.4, 0.03, &"square", 0.2, 0.0, 1400.0)
	if i % 8 == 0:
		s.drum(t, 90.0, 45.0, 0.3, 0.4)


# 試聽頁的 drone([D2], vol 0.05, cutoff 200, LFO 0.08 Hz)；遊戲中由播放器淡入，這裡不做開頭 2 秒的淡入
# 只算剛好一個循環（不參與尾音疊回），頻率含音分偏移後在循環內為整數圈
static func _boss_drone(s: Synth, loop_len: float) -> void:
	var det := Synth.drone_detune(0)
	var f := roundf(Synth.hz(D - 24) * det * loop_len) / loop_len / det
	var lfo := maxf(1.0, roundf(0.08 * loop_len)) / loop_len
	s.drone(0.0, loop_len, [f], 0.05, 200.0, lfo, 150.0, loop_len)
