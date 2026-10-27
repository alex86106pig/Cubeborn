# 音效與背景音樂（畫面層）：訂閱 GameEvents 播放預先產生的 WAV（tools/bake_sfx.gd、bake_music.gd）
# 事件與音效的對應照搬網頁版 Sound.js 的 #bindEvents；M 鍵靜音（記在 user://），音樂依波次切換一般 / Boss 曲
class_name Sound
extends Node

const SFX_DIR := "res://audio/sfx/"
const MUSIC := {&"normal": preload("res://audio/music/normal.wav"), &"boss": preload("res://audio/music/boss.wav")}
const SETTINGS_PATH := "user://settings.cfg"
const MAX_POLYPHONY := 32
const SILENT_DB := -60.0
# 設定頁的音量滑桿（2026-10-27）：音樂、音效各走一條匯流排，總音量是 Master；滑桿 0~1 乘在 Config.AUDIO 的混音上
const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"

# 網頁版 CUES 的全部名稱（tests/check.gd 會比對網頁版與 audio/sfx/ 的檔案）
const CUE_NAMES: Array[String] = [
	"swing", "swingHeavy", "shieldBash", "fireBolt", "arcaneCast", "explosion",
	"hit", "hitHeavy", "playerHurt", "potion", "sprint", "denied",
	"enemySpawn", "bowDraw", "arrowShot", "enemyDeath",
	"bossSlamWindup", "bossSlam", "bossChargeWindup", "bossWallHit", "bossSummon", "enrage", "bossDeath",
	"waveStart", "bossAppear", "victory", "defeat", "pause", "resume", "restart",
]
# 同一音效的最短間隔（秒），避免一次打中多隻怪時爆音（同網頁版）
const MIN_INTERVAL := {"hit": 0.04, "hitHeavy": 0.05, "enemyDeath": 0.06, "enemySpawn": 0.1, "bowDraw": 0.15}
const DEFAULT_INTERVAL := 0.03
const SKILL_CUES := {&"heal": "potion", &"plantTorch": "shieldBash"}
# 個別音效的音量（dB）：v0.44.0 法杖普攻太吵（fireBolt 平均 −31.6 dB，比揮砍 swing 的 −36.1 大 4.5 dB，每 0.56 秒一發）
const CUE_DB := {"fireBolt": -8.0}

var world: World
var local_peer := World.HOST_PEER_ID   # 距離衰減以這個玩家為準（main.gd 連線時設定）
var is_muted := false

var _streams: Dictionary = {}       # 音效名稱 -> AudioStream
var _last_played: Dictionary = {}   # 音效名稱 -> 秒
var _sfx := AudioStreamPlayer.new()
var _music := AudioStreamPlayer.new()
var _music_track: StringName = &""
var _music_tween: Tween
var _has_started := false


func setup(p_world: World) -> void:
	world = p_world


func _init() -> void:
	_sfx.bus = _bus(SFX_BUS)
	_music.bus = _bus(MUSIC_BUS)


func _ready() -> void:
	for cue_name in CUE_NAMES:
		_streams[cue_name] = load(SFX_DIR + cue_name + ".wav")
	var gain: float = Config.AUDIO.baked_gain
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = MAX_POLYPHONY
	_sfx.stream = poly
	_sfx.volume_db = linear_to_db(Config.AUDIO.master * Config.AUDIO.sfx / gain)
	add_child(_sfx)
	_sfx.play()
	add_child(_music)
	_load_settings()
	GameEvents.event_emitted.connect(_on_event)


# 停止所有音效與音樂：音效伺服器下一次混音才放掉播放物件，結束程式前要先呼叫、等幾幀（main.quit_game），否則回報洩漏
# 只在結束程式時呼叫，之後不再理會事件：連線時等待結束的這段時間對方先斷線，客戶端收到 game:restart 會把音樂又播起來（2026-10-27 查到的洩漏）
func stop_all() -> void:
	if GameEvents.event_emitted.is_connected(_on_event):
		GameEvents.event_emitted.disconnect(_on_event)
	_kill_tween()
	_sfx.stop()
	_music.stop()


func _exit_tree() -> void:
	stop_all()


# gain：距離衰減的音量比例（0~1），0 不播（也不占同一音效的最短間隔）
func play(cue_name: String, gain := 1.0) -> void:
	var stream: AudioStream = _streams.get(cue_name)
	if stream == null or not _sfx.playing or gain <= 0.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_played.get(cue_name, -INF) < MIN_INTERVAL.get(cue_name, DEFAULT_INTERVAL):
		return
	_last_played[cue_name] = now
	(_sfx.get_stream_playback() as AudioStreamPlaybackPolyphonic).play_stream(stream, 0.0, cue_db(cue_name, gain))


## 一次播放的音量（dB）：個別音效的音量 + 距離衰減
static func cue_db(cue_name: String, gain: float) -> float:
	return CUE_DB.get(cue_name, 0.0) + linear_to_db(gain)


## 距離 → 音量比例：hear_full 內 1、hear_max 以外 0，中間 (1 − t)²
static func distance_gain(dist: float) -> float:
	var a: Dictionary = Config.AUDIO
	var t := clampf((dist - a.hear_full) / (a.hear_max - a.hear_full), 0.0, 1.0)
	return (1.0 - t) * (1.0 - t)


## 事件的發聲位置（沒有位置的全場音效：勝利、波次、暫停…回傳 null）
static func event_pos(w: World, event_name: String, p: Dictionary) -> Variant:
	if p.has("pos") and event_name in ["sfx:cue", "entity:damaged", "hit:predicted", "entity:died"]:
		return p.pos
	var id: int = 0
	match event_name:
		"entity:damaged", "hit:predicted":
			id = p.get("target_id", 0)
		"entity:died":
			id = p.get("entity_id", 0)
		"skill:used", "player:revived":
			id = p.get("player_id", 0)
	var e: Entity = w.entities.get(id) if w != null and id != 0 else null
	return e.pos if e != null else null


## 這個事件的音效在本機要多大聲（0~1）：本機角色還在時依距離衰減，否則（主選單、還沒有角色）全音量
static func event_gain(w: World, listener: Player, event_name: String, p: Dictionary) -> float:
	if listener == null:
		return 1.0
	var at: Variant = event_pos(w, event_name, p)
	return 1.0 if at == null else distance_gain(listener.pos.distance_to(at))


func toggle_mute() -> bool:
	is_muted = not is_muted
	_apply_mute()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "muted", is_muted)
	cfg.save(SETTINGS_PATH)
	return is_muted


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		is_muted = cfg.get_value("audio", "muted", false)
	_apply_mute()


func _apply_mute() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), is_muted)


## 設定頁的音量（0~1）：bus 是 &"Master"、MUSIC_BUS 或 SFX_BUS；0 等於關掉（−80 dB）
static func set_volume(bus: StringName, volume: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(_bus(bus)), linear_to_db(maxf(volume, 1e-4)))


# 匯流排不在專案的匯流排配置裡（沒有 default_bus_layout），第一次用到時建立，送到 Master
static func _bus(bus: StringName) -> StringName:
	if AudioServer.get_bus_index(bus) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	return bus


## 事件 → 音效名稱（沒有對應時回傳 ""）；照網頁版 Sound.js 的 #bindEvents
static func cue_for_event(w: World, event_name: String, p: Dictionary) -> String:
	match event_name:
		"sfx:cue":
			return p.cue
		"entity:damaged", "hit:predicted":   # 客戶端預測打中先播；房主的同一下（predicted）不再播
			if p.get("predicted", false):
				return ""
			if w != null and w.entities.get(p.target_id) is Player:
				return "playerHurt"
			return "hitHeavy" if p.get("is_heavy", false) or p.get("is_crit", false) else "hit"
		"entity:died":
			var e: Entity = w.entities.get(p.entity_id) if w != null else null
			if e is Enemy:
				return "bossDeath" if e.id == w.boss_id else "enemyDeath"
		"skill:used":
			var player: Player = w.entities.get(p.player_id) as Player if w != null else null
			var key: String = p.key
			if player != null and key.begins_with("player.slot"):
				var slot: Variant = player.slots.get_slot(player, key.trim_prefix("player.slot").to_int() - 1)
				if slot != null:
					return SKILL_CUES.get(slot.def.id, "")
		"skill:onCooldown":
			return "denied"
		"wave:started":
			return "bossAppear" if p.is_boss else "waveStart"
		"boss:enraged":
			return "enrage"
		"game:defeat":   # 全員倒下（單機倒下時和 player:died 同一步發出）
			return "defeat"
		"player:revived":
			return "potion"
		"game:victory":
			return "victory"
		"game:restart":
			return "restart"
		"game:paused":
			return "pause" if p.paused else "resume"
	return ""


func _on_event(event_name: String, p: Dictionary) -> void:
	var cue := cue_for_event(world, event_name, p)
	# 開場的 game:restart 不出聲（網頁版開場時瀏覽器還不允許出聲，聽不到這一聲）
	if cue == "restart" and not _has_started:
		cue = ""
	if cue != "":
		play(cue, event_gain(world, world.players.get(local_peer) if world != null else null, event_name, p))
	if event_name == "game:restart":
		_has_started = true
	if event_name == "game:paused":
		_music.stream_paused = p.paused
	var track := music_for_event(_music_track, event_name, p)
	if track == &"":
		if _music_track != &"":
			_fade_music_out()
	elif track != _music_track or event_name == "game:restart":
		_play_music(track)


## 事件之後該播哪一首（&"" = 停止）：開場 / 重新開始播一般曲、Boss 波換 Boss 曲、死亡或勝利淡出
static func music_for_event(current: StringName, event_name: String, p: Dictionary) -> StringName:
	match event_name:
		"game:restart":
			return &"normal"
		"wave:started":
			return &"boss" if p.is_boss else current
		"game:defeat", "game:victory":
			return &""
	return current


# 換曲：舊曲淡出後新曲從頭淡入（同一首也從頭播）
func _play_music(track: StringName) -> void:
	_music_track = track
	var fade: float = Config.AUDIO.music_fade
	var target := linear_to_db(Config.AUDIO.master * Config.AUDIO.music / Config.AUDIO.baked_gain)
	_kill_tween()
	_music_tween = create_tween()
	if _music.playing:
		_music_tween.tween_property(_music, ^"volume_db", SILENT_DB, fade * 0.5)
	_music_tween.tween_callback(func() -> void:
		_music.stream = MUSIC[track]
		_music.stream_paused = false
		_music.volume_db = SILENT_DB
		_music.play())
	_music_tween.tween_property(_music, ^"volume_db", target, fade)


func _fade_music_out() -> void:
	_music_track = &""
	_kill_tween()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, ^"volume_db", SILENT_DB, Config.AUDIO.music_fade)
	_music_tween.tween_callback(_music.stop)


func _kill_tween() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
