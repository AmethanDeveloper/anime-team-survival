class_name Audio
extends Node
## Звук: эффекты (res://audio/sfx), фразы героев (res://heroes/<id>/voice), музыка (res://audio/music, res://audio/duel).

static var I: Audio = null
static var vol_master := 0.8
static var vol_sfx := 0.8
static var vol_voice := 1.0
static var vol_music := 0.45

var pool3d: Array[AudioStreamPlayer3D] = []
var pool2d: Array[AudioStreamPlayer] = []
var voice_player: AudioStreamPlayer
var music_player: AudioStreamPlayer
var sfx_cache := {}
var last_play := {}
var voice_last := {}
var music_kind := ""


func _ready() -> void:
	I = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 24:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 28.0
		p.max_distance = 95.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 0.6
		add_child(p)
		pool3d.append(p)
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool2d.append(p)
	voice_player = AudioStreamPlayer.new()
	add_child(voice_player)
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	music_player.finished.connect(_on_music_finished)


func _exit_tree() -> void:
	if I == self:
		I = null


static func db(v: float) -> float:
	return linear_to_db(maxf(v, 0.0001))


func _stream(name: String) -> AudioStream:
	if sfx_cache.has(name):
		return sfx_cache[name]
	var s: AudioStream = null
	for e in ["ogg", "wav", "mp3"]:
		var p := "res://audio/sfx/%s.%s" % [name, e]
		if ResourceLoader.exists(p):
			s = load(p)
			break
	sfx_cache[name] = s
	return s


## Звуковой эффект. pos — позиция в мире (или null для 2D).
static func sfx(name: String, pos: Variant = null, vol := 1.0, pitch_var := 0.08, min_gap := 0.04) -> void:
	if I == null or name == "":
		return
	I._play(name, pos, vol, pitch_var, min_gap)


func _play(name: String, pos: Variant, vol: float, pitch_var: float, min_gap: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if last_play.get(name, -10.0) + min_gap > now:
		return
	last_play[name] = now
	var s := _stream(name)
	if s == null:
		return
	var v := vol * vol_sfx * vol_master
	if pos == null:
		for p in pool2d:
			if not p.playing:
				p.stream = s
				p.volume_db = db(v)
				p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
				p.play()
				return
	else:
		for p in pool3d:
			if not p.playing:
				p.stream = s
				p.global_position = pos
				p.volume_db = db(v) + 6.0
				p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
				p.play()
				return


## Фраза героя. chance — вероятность (для частых событий вроде «идти»).
static func voice(hero_id: String, event: String, chance := 1.0, min_gap := 2.5) -> bool:
	if I == null:
		return false
	if randf() > chance:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	var key := hero_id + ":" + event
	if I.voice_last.get(key, -100.0) + min_gap > now:
		return false
	var list := HeroAssets.voices(hero_id, event)
	if list.is_empty():
		return false
	I.voice_last[key] = now
	I.voice_player.stream = list.pick_random()
	I.voice_player.volume_db = db(vol_voice * vol_master)
	I.voice_player.play()
	return true


static func music(kind: String) -> void:
	if I == null or I.music_kind == kind:
		return
	I.music_kind = kind
	I._next_track()


func _next_track() -> void:
	var folder := "res://audio/duel/" if music_kind == "duel" else "res://audio/music/"
	var list := HeroAssets.audio_folder(folder)
	if list.is_empty() and music_kind == "duel":
		list = HeroAssets.audio_folder("res://audio/music/")
	if list.is_empty():
		music_player.stop()
		return
	music_player.stream = list.pick_random()
	music_player.volume_db = db(vol_music * vol_master)
	music_player.play()


func _on_music_finished() -> void:
	_next_track()


static func apply_volumes() -> void:
	if I == null:
		return
	I.music_player.volume_db = db(vol_music * vol_master)
	I.voice_player.volume_db = db(vol_voice * vol_master)
