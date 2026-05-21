extends CharacterBody3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = get_node_or_null("CameraPivot/Camera3D")
@onready var footstep_player: AudioStreamPlayer3D = $FootstepPlayer


const SPEED = 5.0
const JUMP_VELOCITY = 4.5

@export var mouseSensivity = 0.1
@export var step_interval = 0.45
@export var footstep_streams: Array[AudioStream] = []

var _step_timer = 0.0
var _step_index = 0
var _right_click_pressed = false
var _left_click_pressed = false

func _ready() -> void:
	print("[Lidar DEBUG] character_body_3d ready")
	set_process_input(true)
	set_process_unhandled_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	var lidar_system = _get_lidar_system()
	print("[Lidar DEBUG] lidar_system=", lidar_system)
	if camera == null:
		return
	if lidar_system != null:
		# Register the actual camera position and orientation as lidar origin
		lidar_system.call("register_origin", camera)
		var visualizer = lidar_system.call("create_visualizer", get_tree().get_current_scene(), "LidarPointCloud") as MultiMeshInstance3D
		lidar_system.call("register_visualizer", visualizer)
		# Start scanning
		lidar_system.call("start_scan")

func _get_lidar_system() -> Object:
	var root = get_tree().get_root()
	if root.has_node("LidarSystem"):
		print("[Lidar DEBUG] found autoload at /root/LidarSystem")
		return root.get_node("LidarSystem")
	print("[Lidar DEBUG] /root/LidarSystem not found")
	print("[Lidar DEBUG] has_singleton=", Engine.has_singleton("LidarSystem"))
	if Engine.has_singleton("LidarSystem"):
		return Engine.get_singleton("LidarSystem")
	return null

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * mouseSensivity))
		camera_pivot.rotate_x(deg_to_rad(-event.relative.y * mouseSensivity))

func _physics_process(delta: float) -> void:
	var right_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var left_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if left_pressed and not _left_click_pressed:
		_left_click_pressed = true
		print("[Lidar DEBUG] left pressed detected")
	elif not left_pressed:
		_left_click_pressed = false

	if right_pressed:
		var lidar_system = _get_lidar_system()
		if lidar_system != null:
			lidar_system.call("emit_scan")
		_right_click_pressed = true
	elif not right_pressed and _right_click_pressed:
		_right_click_pressed = false

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	if is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.1:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_play_next_footstep()
			_step_timer = step_interval
	else:
		_step_timer = 0.0

	move_and_slide()

func _play_next_footstep() -> void:
	if footstep_streams.is_empty():
		return
	footstep_player.stream = footstep_streams[_step_index % footstep_streams.size()]
	_step_index += 1
	footstep_player.play()
