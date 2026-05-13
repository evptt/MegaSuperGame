extends Node3D

const FIRE_INTERVAL := 0.15
const SWAY_STRENGTH_X := 0.0042
const SWAY_STRENGTH_Y := 0.0032
const BOB_STRENGTH_X := 0.03
const BOB_STRENGTH_Y := 0.02
const RECOIL_BACK := 0.06
const RECOIL_UP := 0.025
const RECOIL_PITCH := -3.5
const RECOIL_YAW := 0.6
const MUZZLE_ANCHOR_NAME := "challenger#Cube_001"

const FIRE_STREAM: AudioStream = preload("res://assets/JDSherbert - FirearmFX - Desert Eagle SFX Pack (FREE)/Mono/wav (HD)/JDSherbert - Firearm FX - Pistol SFX Pack - Desert Eagle - Fire - 1.wav")

@onready var fire_player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()

@export var fire_range := 120.0
@export var fire_damage := 10.0
@export var muzzle_offset := Vector3(0.32, -0.2, -0.7)

var _base_position: Vector3
var _base_rotation: Vector3
var _cooldown := 0.0
var _bob_time := 0.0
var _recoil_position := Vector3.ZERO
var _recoil_rotation := Vector3.ZERO
var _player: CharacterBody3D
var _camera: Camera3D
var _muzzle: Node3D
var _muzzle_flash: GPUParticles3D


func _ready() -> void:
	_base_position = position
	_base_rotation = rotation_degrees
	_player = _find_player()
	_camera = _find_camera()
	_muzzle = _find_muzzle_anchor()
	if _muzzle == null:
		_muzzle = _create_muzzle()
	_muzzle_flash = _create_muzzle_flash()

	fire_player.stream = FIRE_STREAM
	fire_player.unit_size = 12.0
	fire_player.volume_db = -2.0
	add_child(fire_player)


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _cooldown <= 0.0:
		_fire()
		_cooldown = FIRE_INTERVAL

	_update_pose(delta)


func _update_pose(delta: float) -> void:
	var local_velocity := Vector3.ZERO
	if is_instance_valid(_player):
		local_velocity = global_transform.basis.inverse() * _player.velocity
		if Vector2(_player.velocity.x, _player.velocity.z).length() > 0.1:
			_bob_time += delta * 5.0
		else:
			_bob_time = move_toward(_bob_time, 0.0, delta * 2.0)

	var bob := Vector3(
		sin(_bob_time * 0.55) * BOB_STRENGTH_X,
		abs(cos(_bob_time * 1.1)) * BOB_STRENGTH_Y,
		0.0
	)
	var sway := Vector3(
		- clampf(local_velocity.x * SWAY_STRENGTH_X, -0.04, 0.04),
		- clampf(local_velocity.y * SWAY_STRENGTH_Y, -0.025, 0.025),
		0.0
	)

	_recoil_position = _recoil_position.lerp(Vector3.ZERO, delta * 12.0)
	_recoil_rotation = _recoil_rotation.lerp(Vector3.ZERO, delta * 14.0)

	position = _base_position + bob + sway + _recoil_position
	rotation_degrees = _base_rotation + _recoil_rotation


func _fire() -> void:
	fire_player.pitch_scale = randf_range(0.96, 1.04)
	fire_player.play()
	_recoil_position += Vector3(0.0, -RECOIL_UP, RECOIL_BACK)
	_recoil_rotation += Vector3(RECOIL_PITCH, randf_range(-RECOIL_YAW, RECOIL_YAW), randf_range(-0.4, 0.4))
	_play_muzzle_flash()
	_fire_hitscan()


func _find_player() -> CharacterBody3D:
	var current := get_parent()
	while current != null:
		if current is CharacterBody3D:
			return current
		current = current.get_parent()
	return null


func _find_camera() -> Camera3D:
	# Try parent first
	var parent := get_parent()
	if parent is Camera3D:
		return parent as Camera3D
	
	# Try find in children
	var cam := find_child("Camera3D", true, false) as Camera3D
	if cam != null:
		return cam
	
	# Try find in parent's children
	if parent != null:
		cam = parent.find_child("Camera3D", true, false) as Camera3D
		if cam != null:
			return cam
	
	# Try find going up the tree
	var current := parent
	while current != null:
		cam = current.find_child("Camera3D", true, false) as Camera3D
		if cam != null:
			return cam
		current = current.get_parent()
	
	return null


func _find_muzzle_anchor() -> Node3D:
	var node := find_child(MUZZLE_ANCHOR_NAME, true, false)
	return node as Node3D


func _create_muzzle() -> Node3D:
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = muzzle_offset
	add_child(muzzle)
	return muzzle


func _create_muzzle_flash() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "MuzzleFlash"
	particles.one_shot = true
	particles.emitting = false
	particles.amount = 18
	particles.lifetime = 0.08
	particles.explosiveness = 1.0
	particles.randomness = 0.2

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.02
	material.direction = Vector3(0.0, 0.0, -1.0)
	material.spread = 18.0
	material.initial_velocity_min = 6.0
	material.initial_velocity_max = 10.0
	material.gravity = Vector3.ZERO
	material.scale_min = 0.06
	material.scale_max = 0.12
	material.color = Color(1.0, 0.9, 0.6, 0.9)
	particles.process_material = material

	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	var quad_material := StandardMaterial3D.new()
	quad_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad_material.albedo_color = Color(1.0, 0.8, 0.4, 0.9)
	quad_material.emission_enabled = true
	quad_material.emission = Color(1.0, 0.8, 0.4, 1.0)
	quad_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = quad_material
	particles.draw_pass_1 = quad

	_muzzle.add_child(particles)
	return particles


func _play_muzzle_flash() -> void:
	if _muzzle_flash == null:
		return
	_muzzle_flash.restart()
	_muzzle_flash.emitting = true


func _fire_hitscan() -> void:
	if _camera == null:
		return
	var from := _camera.global_transform.origin
	var dir := -_camera.global_transform.basis.z
	var to := from + dir * fire_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [ self , _player]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return
	var collider: Object = result.get("collider")
	if collider == null:
		return
	# Try to apply damage to the collider or its parent
	var target = collider
	if not target.has_method("apply_damage"):
		# If collider is a CollisionShape3D, try parent
		if target is Node:
			var parent = (target as Node).get_parent()
			if parent != null and parent.has_method("apply_damage"):
				target = parent
	if target.has_method("apply_damage"):
		target.call("apply_damage", fire_damage)
	elif target is RigidBody3D:
		var body := target as RigidBody3D
		var hit_pos: Vector3 = result.get("position", body.global_transform.origin)
		var impulse_dir := (to - from).normalized()
		body.apply_impulse(impulse_dir * fire_damage, hit_pos - body.global_transform.origin)