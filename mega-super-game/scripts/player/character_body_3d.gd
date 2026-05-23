extends CharacterBody3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = get_node_or_null("CameraPivot/Camera3D")
@onready var footstep_player: AudioStreamPlayer3D = $FootstepPlayer

const DEBUG_PLAYER_DAMAGE := true

const SPEED = 7.0
const JUMP_VELOCITY = 5.5

# Sprint / stamina
@export var max_stamina: float = 5.0
@export var stamina_drain_rate: float = 1.5 # units per second while sprinting
@export var stamina_recover_rate: float = 0.75 # units per second when not sprinting
@export var sprint_multiplier: float = 1.8
var stamina: float = max_stamina

# Health (simple placeholder)
@export var max_health: float = 100.0
var health: float = max_health
var _is_dead: bool = false

# Lidar modes
var lidar_modes: Array = ["Normal", "Detail", "Stealth"]
var lidar_mode_index: int = 0

@export var mouseSensivity: float = 0.1
@export var min_camera_pitch_degrees := -89.0
@export var max_camera_pitch_degrees := 89.0
@export var step_interval: float = 0.45
@export var footstep_streams: Array[AudioStream] = []
@export var punch_stream: AudioStream

const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")

var _pause_menu: CanvasLayer = null
var _global_audio: Node = null
var _settings_system: Node = null
var _punch_player: AudioStreamPlayer = null

var _step_timer = 0.0
var _step_index = 0
var _right_click_pressed = false
var _lidar_system: Object = null
var _hud_instanced := false
var _hud_node: Node = null

func _ready() -> void:
	set_process_input(true)
	set_process_unhandled_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	_lidar_system = _get_lidar_system()
	# Attach HUD script to existing HUD node under the player, fallback to instancing
	if not _hud_instanced:
		var hud_script = load("res://scripts/ui/hud.gd")
		if hud_script != null:
			var hud_node = get_node_or_null("HUD")
			if hud_node != null:
				hud_node.set_script(hud_script)
				_hud_node = hud_node
				_hud_instanced = true
			else:
				var inst = hud_script.new()
				get_tree().get_current_scene().add_child(inst)
				_hud_node = inst
				_hud_instanced = true
	_setup_pause_menu()
	_global_audio = _get_global_audio()
	_settings_system = _get_settings_system()
	_apply_mouse_sensitivity_from_settings()
	_connect_settings_signals()
	_setup_damage_feedback()
	if camera == null:
		return
	if _lidar_system != null:
		# Register the actual camera position and orientation as lidar origin
		_lidar_system.call("register_origin", camera)
		var visualizer = _lidar_system.call("create_visualizer", get_tree().get_current_scene(), "LidarPointCloud") as MultiMeshInstance3D
		_lidar_system.call("register_visualizer", visualizer)
		# Start scanning
		_lidar_system.call("start_scan")
	# Emit initial HUD values
	_emit_stamina_changed()
	_emit_health_changed()
	_emit_lidar_mode_changed()
	var save_system := get_node_or_null("/root/SaveSystem")
	if save_system != null and save_system.has_method("apply_pending_load"):
		save_system.call("apply_pending_load", self )

	# Auto-load project footstep sounds if none provided in the inspector
	if footstep_streams.is_empty():
		for i in range(8):
			var p := "res://assets/sounds/footsteps/footstep%d.wav" % i
			var s := load(p)
			if s != null:
				footstep_streams.append(s)
		_step_index = 0


func _setup_pause_menu() -> void:
	var scene_root := get_tree().get_current_scene()
	if scene_root == null:
		return
	var pause_node := scene_root.get_node_or_null("PauseMenu")
	print("[Player] _setup_pause_menu existing=", pause_node)
	if pause_node == null:
		pause_node = PAUSE_MENU_SCENE.instantiate()
		pause_node.name = "PauseMenu"
		# Parent may be busy during scene setup; defer adding to avoid "Parent node is busy" error
		scene_root.call_deferred("add_child", pause_node)
	_pause_menu = pause_node as CanvasLayer
	print("[Player] _setup_pause_menu _pause_menu=", _pause_menu)


func _get_global_audio() -> Node:
	var scene_root := get_tree().get_current_scene()
	if scene_root == null:
		return null
	return scene_root.get_node_or_null("GlobalAudio")


func _get_settings_system() -> Node:
	return get_node_or_null("/root/SettingsSystem")

func _setup_damage_feedback() -> void:
	_punch_player = _ensure_audio_player("PunchPlayer")
	if punch_stream == null:
		var default_punch := load("res://assets/sounds/punch.wav")
		if default_punch != null:
			punch_stream = default_punch
	if _punch_player != null:
		_punch_player.stream = punch_stream
		_punch_player.volume_db = -4.0

func _ensure_audio_player(player_name: String) -> AudioStreamPlayer:
	var player := get_node_or_null(player_name) as AudioStreamPlayer
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = player_name
		add_child(player)
	return player

func _connect_settings_signals() -> void:
	if _settings_system == null:
		return
	if _settings_system.has_signal("setting_changed") and not _settings_system.is_connected("setting_changed", Callable(self , "_on_setting_changed")):
		_settings_system.connect("setting_changed", Callable(self , "_on_setting_changed"))


func _apply_mouse_sensitivity_from_settings() -> void:
	if _settings_system != null and _settings_system.has_method("get_mouse_sensitivity"):
		mouseSensivity = float(_settings_system.call("get_mouse_sensitivity"))


func _on_setting_changed(setting_name: String, value: Variant) -> void:
	if setting_name == "mouse_sensitivity":
		mouseSensivity = float(value)

func _get_lidar_system() -> Object:
	var root = get_tree().get_root()
	if root.has_node("LidarSystem"):
		return root.get_node("LidarSystem")
	if Engine.has_singleton("LidarSystem"):
		return Engine.get_singleton("LidarSystem")
	return null

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * mouseSensivity))
		camera_pivot.rotate_x(deg_to_rad(-event.relative.y * mouseSensivity))
		var min_pitch := deg_to_rad(min_camera_pitch_degrees)
		var max_pitch := deg_to_rad(max_camera_pitch_degrees)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, min_pitch, max_pitch)

		# Toggle lidar mode on E key press
		if event is InputEventKey and event.pressed and not event.echo:
			if event.scancode == KEY_E:
				_toggle_lidar_mode()

func _emit_lidar_scan() -> void:
	if _lidar_system == null:
		_lidar_system = _get_lidar_system()
	if _lidar_system != null:
		_lidar_system.call("emit_scan")


func _start_lidar_scan_audio() -> void:
	if _global_audio == null:
		_global_audio = _get_global_audio()
	if _global_audio != null and _global_audio.has_method("start_lidar_scan"):
		_global_audio.call("start_lidar_scan")


func _stop_lidar_scan_audio() -> void:
	if _global_audio == null:
		_global_audio = _get_global_audio()
	if _global_audio != null and _global_audio.has_method("stop_lidar_scan"):
		_global_audio.call("stop_lidar_scan")

func _physics_process(delta: float) -> void:
	var right_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	if right_pressed:
		if not _right_click_pressed:
			_start_lidar_scan_audio()
		_emit_lidar_scan()
		_right_click_pressed = true
	elif _right_click_pressed:
		_stop_lidar_scan_audio()
		_right_click_pressed = false

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Sprint and stamina handling
	var is_sprinting := _is_sprint_pressed()

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var move_speed := SPEED
	if is_sprinting and stamina > 0.05 and direction.length() > 0.1:
		move_speed = SPEED * sprint_multiplier
		stamina = max(0.0, stamina - stamina_drain_rate * delta)
		_emit_stamina_changed()
	else:
		# Recover stamina when not sprinting
		stamina = min(max_stamina, stamina + stamina_recover_rate * delta)
		_emit_stamina_changed()

	_update_hud_stamina()

	if direction:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)

	if is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.1:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_play_next_footstep()
			_step_timer = step_interval
	else:
		_step_timer = 0.0

	move_and_slide()


func _is_sprint_pressed() -> bool:
	if InputMap.has_action("run") and Input.is_action_pressed("run"):
		return true
	if InputMap.has_action("sprint") and Input.is_action_pressed("sprint"):
		return true
	if InputMap.has_action("ui_run") and Input.is_action_pressed("ui_run"):
		return true
	return Input.is_key_pressed(KEY_SHIFT)


func _toggle_lidar_mode() -> void:
	lidar_mode_index = (lidar_mode_index + 1) % lidar_modes.size()
	_emit_lidar_mode_changed()


func _emit_stamina_changed() -> void:
	emit_signal("stamina_changed", stamina, max_stamina)


func _update_hud_stamina() -> void:
	if _hud_node != null and _hud_node.has_method("set_stamina"):
		_hud_node.call("set_stamina", stamina, max_stamina)


func _emit_health_changed() -> void:
	emit_signal("health_changed", health, max_health)

func _play_punch_sound() -> void:
	if _punch_player == null or _punch_player.stream == null:
		return
	_punch_player.play()

func _flash_damage() -> void:
	if _hud_node != null and _hud_node.has_method("flash_damage"):
		_hud_node.call("flash_damage")

func apply_damage(amount: float) -> void:
	if amount <= 0.0 or _is_dead:
		return

	if DEBUG_PLAYER_DAMAGE:
		print("[Player] apply_damage", amount, "before=", health)

	health = clampf(health - amount, 0.0, max_health)
	_emit_health_changed()
	_play_punch_sound()
	_flash_damage()

	if DEBUG_PLAYER_DAMAGE:
		print("[Player] health after=", health)

	if health <= 0.0:
		_on_player_died()

func _on_player_died() -> void:
	if _is_dead:
		return

	_is_dead = true
	health = 0.0
	print("[Player] died, _pause_menu=", _pause_menu)

	if _pause_menu == null:
		_setup_pause_menu()

	if _pause_menu != null and _pause_menu.has_method("show_death_menu"):
		# show_death_menu may need the node to be in the tree; defer the call to be safe
		_pause_menu.call_deferred("show_death_menu")
		print("[Player] requested death menu (deferred)")
		return

	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _emit_lidar_mode_changed() -> void:
	var mode_name: String = str(lidar_modes[lidar_mode_index])
	emit_signal("lidar_mode_changed", lidar_mode_index, mode_name)


func get_save_data() -> Dictionary:
	var weapon := get_node_or_null("CameraPivot/weapon")
	var weapon_data: Dictionary = {}
	if weapon != null and weapon.has_method("get_save_data"):
		weapon_data = weapon.call("get_save_data")
	return {
		"position": [global_position.x, global_position.y, global_position.z],
		"yaw_degrees": rotation_degrees.y,
		"camera_pitch_degrees": camera_pivot.rotation_degrees.x,
		"health": health,
		"stamina": stamina,
		"lidar_mode_index": lidar_mode_index,
		"weapon": weapon_data,
	}


func apply_save_data(data: Dictionary) -> void:
	var position_data: Variant = data.get("position", [])
	if position_data is Array and position_data.size() >= 3:
		global_position = Vector3(float(position_data[0]), float(position_data[1]), float(position_data[2]))
	rotation_degrees.y = float(data.get("yaw_degrees", rotation_degrees.y))
	camera_pivot.rotation_degrees.x = clampf(float(data.get("camera_pitch_degrees", camera_pivot.rotation_degrees.x)), min_camera_pitch_degrees, max_camera_pitch_degrees)
	health = clampf(float(data.get("health", health)), 0.0, max_health)
	stamina = clampf(float(data.get("stamina", stamina)), 0.0, max_stamina)
	lidar_mode_index = clampi(int(data.get("lidar_mode_index", lidar_mode_index)), 0, max(0, lidar_modes.size() - 1))
	var weapon := get_node_or_null("CameraPivot/weapon")
	var weapon_data: Variant = data.get("weapon", {})
	if weapon != null and weapon_data is Dictionary and weapon.has_method("apply_save_data"):
		weapon.call("apply_save_data", weapon_data)
	_emit_stamina_changed()
	_emit_health_changed()
	_emit_lidar_mode_changed()
	_update_hud_stamina()


signal stamina_changed(current: float, max: float)
signal health_changed(current: float, max: float)
signal lidar_mode_changed(index: int, name: String)

func _play_next_footstep() -> void:
	if footstep_streams.is_empty():
		return
	footstep_player.stream = footstep_streams[_step_index % footstep_streams.size()]
	_step_index += 1
	footstep_player.play()
