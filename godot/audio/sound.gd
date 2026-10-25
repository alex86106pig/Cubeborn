# 音效與背景音樂（畫面層）：訂閱 GameEvents 播放預先產生的 WAV（tools/bake_sfx.gd、bake_music.gd）
# 事件與音效的對應照搬網頁版 Sound.js 的 #bindEvents；M 鍵靜音（記在 user://），音樂依波次切換一般 / Boss 曲
class_name Sound
extends Node

const SFX_DIR := "res://audio/sfx/"
const MUSIC := {&"normal": preload("res://audio/music/normal.wav"), &"boss": preload("res://audio/music/boss.wav")}
const SETTINGS_PATH := "user://settings.cfg"
const MAX_POLYPHONY := 32
const SILENT_DB := -60.0

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
const SKILL_CUES := {&"heal": "potion", &"sprint": "sprint"}

var world: World
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


# 離開時停止播放，否則音效伺服器還握著多音播放物件，結束時回報洩漏
func _exit_tree() -> void:
	_kill_tween()
	_sfx.stop()
	_music.stop()


func play(cue_name: String) -> void:
	var stream: AudioStream = _streams.get(cue_name)
	if stream == null or not _sfx.playing:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_played.get(cue_name, -INF) < MIN_INTERVAL.get(cue_name, DEFAULT_INTERVAL):
		return
	_last_played[cue_name] = now
	(_sfx.get_stream_playback() as AudioStreamPlaybackPolyphonic).play_stream(stream)


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
				var slot: Variant = player.slots.slots[key.trim_prefix("player.slot").to_int() - 1]
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
		play(cue)
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
