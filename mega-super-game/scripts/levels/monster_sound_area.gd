extends Area3D

@export var sound_stream: AudioStream
@export var sound_volume_db: float = -2.0

var _played: bool = false
var _sound_player: AudioStreamPlayer3D = null

func _ready() -> void:
	if sound_stream == null:
		var default_sound := load("res://assets/sounds/alien/alien_sound.mp3")
		if default_sound != null:
			sound_stream = default_sound

	_sound_player = AudioStreamPlayer3D.new()
	_sound_player.stream = sound_stream
	_sound_player.volume_db = sound_volume_db
	_sound_player.autoplay = false
	add_child(_sound_player)

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _played:
		return
	if body is Node and body.is_in_group("player"):
		_played = true
		if _sound_player != null and _sound_player.stream != null:
			_sound_player.play()
