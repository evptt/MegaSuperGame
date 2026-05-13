extends CharacterBody3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var footstep_player: AudioStreamPlayer3D = $FootstepPlayer


const SPEED = 5.0
const JUMP_VELOCITY = 4.5

@export var mouseSensivity = 0.1
@export var step_interval = 0.45
@export var footstep_streams: Array[AudioStream] = []

var _step_timer = 0.0
var _step_index = 0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * mouseSensivity))
		camera_pivot.rotate_x(deg_to_rad(-event.relative.y * mouseSensivity))

func _physics_process(delta: float) -> void:
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
