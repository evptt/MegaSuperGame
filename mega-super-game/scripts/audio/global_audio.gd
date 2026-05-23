extends Node

@export var ambient_stream: AudioStream
@export var ambient_volume_db: float = -6.0
@export var ambient_autoplay: bool = true

@export var breathing_stream: AudioStream
@export var breathing_volume_db: float = -6.0
@export var breathing_autoplay: bool = true

@export var lidar_scan_stream: AudioStream
@export var lidar_scan_volume_db: float = -3.0

@export var random_sounds_interval_sec: float = 20.0
@export var random_sounds_volume_db: float = -6.0

var _ambient_player: AudioStreamPlayer = null
var _breathing_player: AudioStreamPlayer = null
var _lidar_scan_player: AudioStreamPlayer = null
var _random_sounds_player: AudioStreamPlayer = null
var _random_sound_timer: Timer = null
var _random_sound_streams: Array[AudioStream] = []
var _random_sound_index := 0
var _random_sound_started := false
var _lidar_scan_active := false


func _ready() -> void:
	_setup_players()
	_load_default_streams()
	_load_random_sound_streams()
	_apply_streams()
	_start_random_sound_cycle()


func _setup_players() -> void:
	_ambient_player = _ensure_player("AmbientPlayer")
	_breathing_player = _ensure_player("BreathingPlayer")
	_lidar_scan_player = _ensure_player("LidarScanPlayer")
	_random_sounds_player = _ensure_player("RandomSoundsPlayer")
	
	# Connect finished signals for looping background sounds
	_ambient_player.finished.connect(_on_ambient_finished)
	_breathing_player.finished.connect(_on_breathing_finished)
	_random_sounds_player.finished.connect(_on_random_sound_finished)
	
	_random_sound_timer = _ensure_timer("RandomSoundTimer")
	_random_sound_timer.one_shot = true
	_random_sound_timer.timeout.connect(_on_random_sound_timer_timeout)


func _ensure_player(player_name: String) -> AudioStreamPlayer:
	var player := get_node_or_null(player_name) as AudioStreamPlayer
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = player_name
		add_child(player)
	return player


func _load_default_streams() -> void:
	if ambient_stream == null:
		var ambient_default := load("res://assets/sounds/ambient/ambient.mp3")
		if ambient_default != null:
			ambient_stream = ambient_default
	if breathing_stream == null:
		var breathing_default := load("res://assets/sounds/ambient/breathing.wav")
		if breathing_default != null:
			breathing_stream = breathing_default
	if lidar_scan_stream == null:
		var lidar_default := load("res://assets/sounds/ambient/lidar_scan.wav")
		if lidar_default != null:
			lidar_scan_stream = lidar_default


func _apply_streams() -> void:
	if _ambient_player != null:
		_ambient_player.stream = ambient_stream
		_ambient_player.volume_db = ambient_volume_db
		if ambient_autoplay and _ambient_player.stream != null:
			_ambient_player.play()

	if _breathing_player != null:
		_breathing_player.stream = breathing_stream
		_breathing_player.volume_db = breathing_volume_db
		if breathing_autoplay and _breathing_player.stream != null:
			_breathing_player.play()

	if _lidar_scan_player != null:
		_lidar_scan_player.stream = lidar_scan_stream
		_lidar_scan_player.volume_db = lidar_scan_volume_db
		_lidar_scan_player.finished.connect(_on_lidar_scan_finished)

	if _random_sounds_player != null:
		_random_sounds_player.volume_db = random_sounds_volume_db


func _ensure_timer(timer_name: String) -> Timer:
	var timer := get_node_or_null(timer_name) as Timer
	if timer == null:
		timer = Timer.new()
		timer.name = timer_name
		add_child(timer)
	return timer


func _load_random_sound_streams() -> void:
	_random_sound_streams.clear()
	var dir := DirAccess.open("res://assets/sounds/random_sounds")
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and _is_supported_audio_file(file_name):
			var stream := load("res://assets/sounds/random_sounds/%s" % file_name)
			if stream is AudioStream:
				_random_sound_streams.append(stream)
		file_name = dir.get_next()
	dir.list_dir_end()
	_random_sound_streams.sort_custom(Callable(self , "_compare_audio_streams"))


func _is_supported_audio_file(file_name: String) -> bool:
	var extension := file_name.get_extension().to_lower()
	return extension == "wav" or extension == "mp3" or extension == "ogg" or extension == "flac"


func _compare_audio_streams(left: AudioStream, right: AudioStream) -> bool:
	return left.resource_path < right.resource_path


func _start_random_sound_cycle() -> void:
	if _random_sounds_player == null or _random_sound_streams.is_empty():
		return
	if not _random_sound_started:
		_random_sound_started = true
		_play_next_random_sound()


func _play_next_random_sound() -> void:
	if _random_sounds_player == null or _random_sound_streams.is_empty():
		return
	_random_sounds_player.stop()
	_random_sounds_player.stream = _random_sound_streams[_random_sound_index]
	_random_sounds_player.volume_db = random_sounds_volume_db
	_random_sound_index = (_random_sound_index + 1) % _random_sound_streams.size()
	_random_sounds_player.play()


func start_lidar_scan() -> void:
	_lidar_scan_active = true
	if _lidar_scan_player != null and _lidar_scan_player.stream != null and not _lidar_scan_player.playing:
		_lidar_scan_player.play()


func stop_lidar_scan() -> void:
	_lidar_scan_active = false
	if _lidar_scan_player != null:
		_lidar_scan_player.stop()


func _on_lidar_scan_finished() -> void:
	if _lidar_scan_active and _lidar_scan_player != null and _lidar_scan_player.stream != null:
		_lidar_scan_player.play()


func _on_ambient_finished() -> void:
	if _ambient_player != null and _ambient_player.stream != null:
		_ambient_player.play()


func _on_breathing_finished() -> void:
	if _breathing_player != null and _breathing_player.stream != null:
		_breathing_player.play()


func _on_random_sound_finished() -> void:
	if _random_sound_timer != null and random_sounds_interval_sec > 0.0:
		_random_sound_timer.start(random_sounds_interval_sec)


func _on_random_sound_timer_timeout() -> void:
	_play_next_random_sound()
