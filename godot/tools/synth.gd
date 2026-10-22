# 離線合成工具（只給 tools/bake_*.gd 用，遊戲執行時不載入）：照網頁版 Web Audio 的做法逐樣本計算
# 振盪器（sine / triangle / square / sawtooth）、頻率與音量的指數漸變、BiquadFilter（公式同 Web Audio 規格）、白噪音、寫 WAV
class_name Synth
extends RefCounted

const RATE := 44100
const SILENT := 0.0001   # Web Audio 範例中指數漸變的起點與終點

var buf := PackedFloat32Array()
var rng := RandomNumberGenerator.new()


func _init(seconds: float, seed_value: int) -> void:
	buf.resize(ceili(seconds * RATE))
	rng.seed = seed_value


static func hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


# 指數漸變：k 為 0~1 的進度
static func _exp_ramp(from: float, to: float, k: float) -> float:
	return from * pow(to / from, clampf(k, 0.0, 1.0))


# Web Audio 的 setValueAtTime(0.0001) → exponentialRamp(vol, attack) → exponentialRamp(0.0001, end)
static func _envelope(t: float, vol: float, attack: float, end: float) -> float:
	if t < attack:
		return _exp_ramp(SILENT, vol, t / attack)
	if t < end:
		return _exp_ramp(vol, SILENT, (t - attack) / maxf(end - attack, 1e-6))
	return SILENT


# PolyBLEP：方波與鋸齒波在跳變處修正，減少數位合成的高頻雜音（瀏覽器內建波形本來就是限頻的）
static func _blep(p: float, dp: float) -> float:
	if p < dp:
		var x := p / dp
		return x + x - x * x - 1.0
	if p > 1.0 - dp:
		var x := (p - 1.0) / dp
		return x * x + x + x + 1.0
	return 0.0


static func _wave(type: StringName, p: float, dp: float) -> float:
	match type:
		&"square":
			return (1.0 if p < 0.5 else -1.0) + _blep(p, dp) - _blep(fmod(p + 0.5, 1.0), dp)
		&"sawtooth":
			return 2.0 * p - 1.0 - _blep(p, dp)
		&"triangle":
			return 1.0 - 4.0 * absf(p - 0.5)
	return sin(TAU * p)


## 雙二階濾波器，係數公式照 Web Audio 規格：lowpass / highpass 的 Q 單位是 dB，bandpass 是一般 Q 值
class Biquad:
	var type: StringName
	var q: float
	var b0 := 1.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0

	func _init(p_type: StringName, p_q: float) -> void:
		type = p_type
		q = p_q

	func set_freq(f: float) -> void:
		var w0 := TAU * clampf(f, 10.0, Synth.RATE * 0.49) / Synth.RATE
		var cw := cos(w0)
		var alpha := sin(w0) / (2.0 * q) if type == &"bandpass" else sin(w0) / (2.0 * pow(10.0, q / 20.0))
		var a0 := 1.0 + alpha
		match type:
			&"highpass":
				b0 = (1.0 + cw) / 2.0
				b1 = -(1.0 + cw)
				b2 = b0
			&"bandpass":
				b0 = alpha
				b1 = 0.0
				b2 = -alpha
			_:
				b0 = (1.0 - cw) / 2.0
				b1 = 1.0 - cw
				b2 = b0
		b0 /= a0
		b1 /= a0
		b2 /= a0
		a1 = -2.0 * cw / a0
		a2 = (1.0 - alpha) / a0

	func process(x: float) -> float:
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		return y


## 網頁版 Sound.js 的 tone()：o = { type, from, to, dur, vol, attack, delay, filter, release }
## release 給音樂用：音量在 dur + release 才降到最小（網頁版 note()）
func tone(start: float, o: Dictionary) -> void:
	var type: StringName = o.get("type", &"sine")
	var from: float = o.from
	var to: float = maxf(1.0, o.get("to", from))
	var dur: float = o.dur
	var vol: float = o.get("vol", 0.3)
	var attack: float = o.get("attack", 0.005)
	var end: float = dur + o.get("release", 0.0)
	var cutoff: float = o.get("filter", 0.0)
	var filter: Biquad = null
	if cutoff > 0.0:
		filter = Biquad.new(&"lowpass", 1.0)
		filter.set_freq(cutoff)
	var t0: float = start + o.get("delay", 0.0)
	var phase := [0.0]   # lambda 捕捉的區域變數是複本，狀態要放在陣列裡才會保留
	_mix(t0, end + 0.02, func(t: float) -> float:
		var f := _exp_ramp(from, to, t / dur)
		var dp := f / Synth.RATE
		var s := _wave(type, phase[0], dp)
		phase[0] = fmod(phase[0] + dp, 1.0)
		if filter != null:
			s = filter.process(s)
		return s * _envelope(t, vol, attack, end))


## 網頁版 Sound.js 的 noise()：o = { dur, vol, type, from, to, q, attack, delay }
func noise(start: float, o: Dictionary) -> void:
	var dur: float = o.dur
	var vol: float = o.get("vol", 0.3)
	var from: float = o.get("from", 1000.0)
	var to: float = maxf(20.0, o.get("to", from))
	var attack: float = o.get("attack", 0.003)
	var filter := Biquad.new(o.get("type", &"bandpass"), o.get("q", 1.0))
	var t0: float = start + o.get("delay", 0.0)
	_mix(t0, dur + 0.02, func(t: float) -> float:
		filter.set_freq(_exp_ramp(from, to, t / dur))
		return filter.process(rng.randf() * 2.0 - 1.0) * _envelope(t, vol, attack, dur))


## 音樂試聽頁的 drum()：正弦波頻率下滑，音量從 vol 指數衰減（不含噪音，B 曲沒有用到）
func drum(start: float, from: float, to: float, dur: float, vol: float) -> void:
	var phase := [0.0]
	_mix(start, dur + 0.05, func(t: float) -> float:
		var f := _exp_ramp(from, to, t / dur)
		var s := sin(TAU * phase[0])
		phase[0] = fmod(phase[0] + f / Synth.RATE, 1.0)
		return s * (_exp_ramp(vol, SILENT, t / dur) if t < dur else SILENT))


## 持續低音每個音的音分偏移（試聽頁：偶數 -6、奇數 +6）
static func drone_detune(i: int) -> float:
	return pow(2.0, (6.0 if i % 2 else -6.0) / 1200.0)


## 音樂試聽頁的 drone()：鋸齒波經過低通（Q 2 dB），截止頻率由 LFO 擺動；從 start 持續 seconds 秒。
## warmup：先空跑幾秒讓振盪器與濾波器進入穩定狀態（循環曲目用一整個循環，接縫處的狀態就會一致）
func drone(start: float, seconds: float, freqs: Array, vol: float, cutoff: float, lfo: float, lfo_depth: float, warmup := 0.0) -> void:
	var filter := Biquad.new(&"lowpass", 2.0)
	var phases: Array[float] = []
	var steps: Array[float] = []
	for i in freqs.size():
		phases.append(0.0)
		steps.append(freqs[i] * drone_detune(i) / RATE)
	var sample := func(t: float) -> float:
		filter.set_freq(cutoff + lfo_depth * sin(TAU * lfo * t))
		var s := 0.0
		for i in phases.size():
			s += _wave(&"sawtooth", phases[i], steps[i])
			phases[i] = fmod(phases[i] + steps[i], 1.0)
		return filter.process(s) * vol
	for i in roundi(warmup * RATE):
		sample.call(float(i) / RATE - warmup)
	_mix(start, seconds, sample)


# 從 start 秒開始、持續 length 秒，把 sample(t) 加進 buf（t 為相對 start 的秒數；超出 buf 的部分捨棄）
func _mix(start: float, length: float, sample: Callable) -> void:
	var i0 := roundi(start * RATE)
	var n := mini(ceili(length * RATE), buf.size() - i0)
	for i in n:
		buf[i0 + i] += sample.call(float(i) / RATE)


func peak() -> float:
	var p := 0.0
	for s in buf:
		p = maxf(p, absf(s))
	return p


## 把 loop_len 秒之後的尾音疊回開頭，讓循環接縫處的尾音不會斷掉；buf 截成 loop_len 秒
func fold_loop(loop_len: float) -> void:
	var n := roundi(loop_len * RATE)
	for i in range(n, buf.size()):
		buf[i % n] += buf[i]
	buf.resize(n)


## 寫成 16-bit 單聲道 WAV；loop 為 true 時加上 smpl 區塊（Godot 匯入時「從 WAV 偵測」循環）
func save_wav(path: String, gain: float, loop := false) -> void:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, clampi(roundi(buf[i] * gain * 32767.0), -32768, 32767))
	var f := FileAccess.open(path, FileAccess.WRITE)
	var smpl_size := 60
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(4 + 24 + 8 + data.size() + (8 + smpl_size if loop else 0))
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)          # PCM
	f.store_16(1)          # 單聲道
	f.store_32(RATE)
	f.store_32(RATE * 2)   # 每秒位元組
	f.store_16(2)          # 每個樣本位元組
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data.size())
	f.store_buffer(data)
	if loop:
		f.store_buffer("smpl".to_ascii_buffer())
		f.store_32(smpl_size)
		for v in [0, 0, roundi(1e9 / RATE), 60, 0, 0, 0, 1, 0]:   # 製造商…循環數 1、附加資料 0
			f.store_32(v)
		for v in [0, 0, 0, buf.size() - 1, 0, 0]:   # 循環 id、類型 0（往前）、起點、終點、微調、次數 0（無限）
			f.store_32(v)
	f.close()
