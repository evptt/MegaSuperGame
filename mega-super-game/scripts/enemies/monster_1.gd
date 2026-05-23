extends CharacterBody3D
class_name Monster1AI

const BT_SUCCESS := 0
const BT_FAILURE := 1
const BT_RUNNING := 2

enum Behavior {IDLE, PATROL, CHASE, SEARCH, FLEE, ATTACK, DEAD}


class BTNode:
	func tick(_actor) -> int:
		return BT_FAILURE


class BTSequence extends BTNode:
	var children: Array = []

	func _init(p_children: Array = []) -> void:
		children = p_children

	func tick(actor) -> int:
		for child in children:
			var result: int = child.tick(actor)
			if result != BT_SUCCESS:
				return result
		return BT_SUCCESS


class BTSelector extends BTNode:
	var children: Array = []

	func _init(p_children: Array = []) -> void:
		children = p_children

	func tick(actor) -> int:
		for child in children:
			var result: int = child.tick(actor)
			if result != BT_FAILURE:
				return result
		return BT_FAILURE


class BTCondition extends BTNode:
	var predicate: Callable

	func _init(p_predicate: Callable) -> void:
		predicate = p_predicate

	func tick(actor) -> int:
		return BT_SUCCESS if predicate.call(actor) else BT_FAILURE


class BTAction extends BTNode:
	var action: Callable

	func _init(p_action: Callable) -> void:
		action = p_action

	func tick(actor) -> int:
		var result: Variant = action.call(actor)
		if result is int:
			return result
		if result is bool:
			return BT_SUCCESS if result else BT_FAILURE
		return BT_FAILURE


@export var max_health: float = 60.0
@export var patrol_speed: float = 2.2
@export var chase_speed: float = 4.8
@export var flee_speed: float = 5.8
@export var gravity: float = 24.0

@export var detection_radius: float = 18.0
@export var lose_interest_radius: float = 26.0
@export var attack_range: float = 5.5
@export var attack_damage: float = 15.0
@export var attack_cooldown_time: float = 4.0
@export var target_memory_time: float = 4.0

@export var flee_health_ratio: float = 0.35
@export var flee_duration: float = 2.5
@export var flee_safe_distance: float = 13.0

@export var patrol_radius: float = 12.0
@export var patrol_wait_min: float = 0.8
@export var patrol_wait_max: float = 2.4
@export var search_wait_time: float = 1.5
@export var turn_speed: float = 9.0

@export var call_for_help: bool = true
@export var alert_group_name: StringName = &"monsters"
@export var alert_cooldown_time: float = 4.0
@export var start_awake: bool = false

@onready var _navigation_agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
@onready var _detection_area: Area3D = get_node_or_null("Area3D") as Area3D

@export var roar_stream: AudioStream
@export var roar_volume_db: float = -4.0

var _root: BTNode
var _health: float = 0.0
var _home_position: Vector3
var _player: Node3D
var _last_known_player_position: Vector3
var _has_last_known_position := false
var _target_memory_left := 0.0
var _alert_cooldown_left := 0.0
var _attack_cooldown_left := 0.0
var _roar_player: AudioStreamPlayer3D = null
var _roar_cooldown_left: float = 0.0
var _flee_left := 0.0
var _search_wait_left := 0.0
var _patrol_wait_left := 0.0
var _patrol_index := -1
var _patrol_target := Vector3.ZERO
var _patrol_target_ready := false
var _flee_target := Vector3.ZERO
var _is_player_in_detection := false
var _awake := false
var _behavior: int = Behavior.PATROL
var _rng := RandomNumberGenerator.new()
var _can_see_player_cached := false
var _can_see_player_timer := 0.0
const VISION_CHECK_INTERVAL := 0.2
var _player_search_timer := 0.0
const PLAYER_SEARCH_INTERVAL := 2.0
const DEBUG_MONSTER_COMBAT := true


func _ready() -> void:
	_rng.randomize()
	_health = max_health
	_home_position = global_position
	_player = _find_player()
	_awake = start_awake
	_build_behavior_tree()
	_bind_detection_area()
	_setup_roar_player()
	_request_next_patrol_target(true)
	_add_to_monster_group()


func _physics_process(delta: float) -> void:
	if not _awake:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	_update_timers(delta)
	_refresh_player()
	_try_play_roar()
	_update_senses()
	if _root != null:
		_root.tick(self )
	_apply_movement(delta)
	move_and_slide()


func _update_timers(delta: float) -> void:
	if _target_memory_left > 0.0:
		_target_memory_left = maxf(0.0, _target_memory_left - delta)
	if _alert_cooldown_left > 0.0:
		_alert_cooldown_left = maxf(0.0, _alert_cooldown_left - delta)
	if _attack_cooldown_left > 0.0:
		_attack_cooldown_left = maxf(0.0, _attack_cooldown_left - delta)
	if _roar_cooldown_left > 0.0:
		_roar_cooldown_left = maxf(0.0, _roar_cooldown_left - delta)
	if _flee_left > 0.0:
		_flee_left = maxf(0.0, _flee_left - delta)
	if _search_wait_left > 0.0:
		_search_wait_left = maxf(0.0, _search_wait_left - delta)
	if _patrol_wait_left > 0.0:
		_patrol_wait_left = maxf(0.0, _patrol_wait_left - delta)
	_can_see_player_timer = maxf(0.0, _can_see_player_timer - delta)
	_player_search_timer = maxf(0.0, _player_search_timer - delta)


func _refresh_player() -> void:
	if is_instance_valid(_player):
		return
	# Только переискиваем периодически, не каждый кадр
	if _player_search_timer > 0.0:
		return
	_player = _find_player()
	_player_search_timer = PLAYER_SEARCH_INTERVAL


func _update_senses() -> void:
	_is_player_in_detection = false
	if not is_instance_valid(_player):
		return

	var distance := global_position.distance_to(_player.global_position)
	if distance <= detection_radius:
		_is_player_in_detection = true
		_last_known_player_position = _player.global_position
		_has_last_known_position = true
		_target_memory_left = target_memory_time
		if _can_see_player():
			_alert_once(_player.global_position)

	if _has_last_known_position and distance <= lose_interest_radius:
		_target_memory_left = maxf(_target_memory_left, target_memory_time * 0.35)


func _build_behavior_tree() -> void:
	_root = BTSelector.new([
		BTSequence.new([
			BTCondition.new(Callable(self , "_bt_is_dead")),
			BTAction.new(Callable(self , "_bt_do_dead")),
		]),
		BTSequence.new([
			BTCondition.new(Callable(self , "_bt_should_flee")),
			BTAction.new(Callable(self , "_bt_flee")),
		]),
		BTSequence.new([
			BTCondition.new(Callable(self , "_bt_has_threat_memory")),
			BTSelector.new([
				BTSequence.new([
					BTCondition.new(Callable(self , "_bt_can_see_player")),
					BTAction.new(Callable(self , "_bt_alert_allies")),
					BTSelector.new([
						BTSequence.new([
							BTCondition.new(Callable(self , "_bt_player_in_attack_range")),
							BTAction.new(Callable(self , "_bt_attack")),
						]),
						BTAction.new(Callable(self , "_bt_chase")),
					]),
				]),
				BTSequence.new([
					BTCondition.new(Callable(self , "_bt_has_last_known_position")),
					BTAction.new(Callable(self , "_bt_search_last_known_position")),
				]),
			]),
		]),
		BTAction.new(Callable(self , "_bt_patrol")),
	])


func _bt_is_dead(_actor = null) -> bool:
	return _health <= 0.0


func _bt_do_dead(_actor = null) -> int:
	queue_free()
	return BT_SUCCESS


func _bt_should_flee(_actor = null) -> bool:
	if _health > max_health * flee_health_ratio:
		return false
	return is_instance_valid(_player) and (_is_player_in_detection or _target_memory_left > 0.0)


func _bt_flee(_actor = null) -> int:
	_behavior = Behavior.FLEE
	if _flee_left <= 0.0:
		_flee_left = flee_duration
		_flee_target = _build_flee_target()
		if _navigation_agent != null:
			_navigation_agent.target_position = _flee_target

	if _flee_left <= 0.0 and global_position.distance_to(_flee_target) <= 1.5:
		return BT_SUCCESS

	if is_instance_valid(_player) and global_position.distance_to(_player.global_position) >= flee_safe_distance:
		return BT_SUCCESS

	return BT_RUNNING


func _bt_has_threat_memory(_actor = null) -> bool:
	return is_instance_valid(_player) and (_is_player_in_detection or _target_memory_left > 0.0 or _has_last_known_position)


func _bt_can_see_player(_actor = null) -> bool:
	if not is_instance_valid(_player):
		return false
	if _can_see_player_timer <= 0.0:
		_can_see_player_cached = _can_see_player()
		_can_see_player_timer = VISION_CHECK_INTERVAL
	return _can_see_player_cached


func _bt_player_in_attack_range(_actor = null) -> bool:
	return is_instance_valid(_player) and _flat_distance_to_player() <= attack_range


func _bt_has_last_known_position(_actor = null) -> bool:
	return _has_last_known_position


func _bt_alert_allies(_actor = null) -> int:
	_alert_once(_player.global_position if is_instance_valid(_player) else global_position)
	return BT_SUCCESS


func _bt_attack(_actor = null) -> int:
	_behavior = Behavior.ATTACK
	var target := _resolve_player_target()
	if not is_instance_valid(target):
		return BT_FAILURE

	if _flat_distance_to_player() > attack_range:
		return BT_FAILURE

	if _attack_cooldown_left > 0.0:
		return BT_FAILURE

	velocity = Vector3.ZERO
	_apply_damage_to_player(attack_damage)
	_attack_cooldown_left = attack_cooldown_time
	return BT_SUCCESS


func _bt_chase(_actor = null) -> int:
	if not is_instance_valid(_player) and not _has_last_known_position:
		return BT_FAILURE

	_behavior = Behavior.CHASE
	if is_instance_valid(_player):
		_last_known_player_position = _player.global_position
		_has_last_known_position = true
		_target_memory_left = target_memory_time
		# Only update navigation target if player moved significantly
		if _navigation_agent != null and _navigation_agent.target_position.distance_to(_player.global_position) > 2.5:
			_navigation_agent.target_position = _player.global_position

		if _bt_can_see_player():
			_alert_once(_player.global_position)
			return BT_RUNNING

	if _has_last_known_position and _navigation_agent != null:
		if _navigation_agent.target_position.distance_to(_last_known_player_position) > 1.0:
			_navigation_agent.target_position = _last_known_player_position

	return BT_RUNNING


func _bt_search_last_known_position(_actor = null) -> int:
	if not _has_last_known_position:
		return BT_FAILURE

	_behavior = Behavior.SEARCH
	if _navigation_agent != null:
		_navigation_agent.target_position = _last_known_player_position

	if global_position.distance_to(_last_known_player_position) > 1.25:
		return BT_RUNNING

	if _search_wait_left <= 0.0:
		_search_wait_left = search_wait_time
		return BT_RUNNING

	if _search_wait_left > 0.0:
		return BT_RUNNING

	_has_last_known_position = false
	_target_memory_left = 0.0
	return BT_SUCCESS


func _bt_patrol(_actor = null) -> int:
	_behavior = Behavior.PATROL
	if _patrol_wait_left > 0.0:
		velocity = Vector3.ZERO
		return BT_RUNNING

	if not _patrol_target_ready or global_position.distance_to(_patrol_target) <= 1.1:
		_request_next_patrol_target(false)
		if _patrol_wait_left > 0.0:
			velocity = Vector3.ZERO
			return BT_RUNNING

	if _navigation_agent != null:
		_navigation_agent.target_position = _patrol_target
	return BT_RUNNING


func _apply_movement(delta: float) -> void:
	if _behavior == Behavior.DEAD or _behavior == Behavior.ATTACK:
		velocity.x = move_toward(velocity.x, 0.0, 40.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 40.0 * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
		return

	var active_speed := patrol_speed
	var target_position := Vector3.ZERO

	match _behavior:
		Behavior.FLEE:
			active_speed = flee_speed
			target_position = _flee_target
		Behavior.CHASE:
			active_speed = chase_speed
			target_position = _player.global_position if is_instance_valid(_player) else _last_known_player_position
		Behavior.SEARCH:
			active_speed = patrol_speed
			target_position = _last_known_player_position
		Behavior.PATROL:
			active_speed = patrol_speed
			target_position = _patrol_target
		_:
			active_speed = 0.0

	if active_speed <= 0.0 or target_position.distance_to(global_position) > 500.0:
		velocity.x = move_toward(velocity.x, 0.0, 40.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 40.0 * delta)
	else:
		var next_step := _next_navigation_step(target_position)
		var desired := next_step - global_position
		desired.y = 0.0
		if desired.length() > 0.05:
			desired = desired.normalized() * active_speed
			velocity.x = move_toward(velocity.x, desired.x, 18.0 * delta)
			velocity.z = move_toward(velocity.z, desired.z, 18.0 * delta)
			_face_movement_direction(Vector3(velocity.x, 0.0, velocity.z), delta)
		else:
			velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0


func _next_navigation_step(target_position: Vector3) -> Vector3:
	if _navigation_agent == null:
		return target_position
	
	# Update target only if it has moved enough to justify path recompute
	if _navigation_agent.target_position.distance_to(target_position) > 2.0:
		_navigation_agent.target_position = target_position
	
	# Safety checks for broken navigation
	if _navigation_agent.is_navigation_finished():
		return target_position
	
	var final_pos := _navigation_agent.get_final_position()
	if final_pos.distance_to(global_position) > 500.0:
		return target_position
	
	var next_position := _navigation_agent.get_next_path_position()
	if next_position.distance_to(global_position) <= 0.05 and global_position.distance_to(target_position) > 0.5:
		return target_position
	return next_position


func _face_movement_direction(direction: Vector3, delta: float) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() <= 0.01:
		return
	var target_yaw := atan2(flat.x, flat.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


func _bind_detection_area() -> void:
	if _detection_area == null:
		return
	if not _detection_area.body_entered.is_connected(_on_detection_body_entered):
		_detection_area.body_entered.connect(_on_detection_body_entered)
	if not _detection_area.body_exited.is_connected(_on_detection_body_exited):
		_detection_area.body_exited.connect(_on_detection_body_exited)

func _setup_roar_player() -> void:
	_roar_player = get_node_or_null("RoarPlayer") as AudioStreamPlayer3D
	if _roar_player == null:
		_roar_player = AudioStreamPlayer3D.new()
		_roar_player.name = "RoarPlayer"
		add_child(_roar_player)
	if roar_stream == null:
		var default_roar := load("res://assets/sounds/alien/alien_roar.wav")
		if default_roar != null:
			roar_stream = default_roar
	if _roar_player != null:
		_roar_player.stream = roar_stream
		_roar_player.volume_db = roar_volume_db
		_roar_player.autoplay = false

func _try_play_roar() -> void:
	if not _awake or _health <= 0.0 or _roar_cooldown_left > 0.0:
		return
	if _roar_player == null or _roar_player.stream == null:
		return
	if not _roar_player.playing:
		_roar_player.play()
		_roar_cooldown_left = 1.5


func _on_detection_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body is Node3D:
		_awake = true
		_player = body as Node3D
		_is_player_in_detection = true
		_last_known_player_position = _player.global_position
		_has_last_known_position = true
		_target_memory_left = target_memory_time


func _on_detection_body_exited(body: Node) -> void:
	if body == _player:
		_is_player_in_detection = false


func _can_see_player() -> bool:
	if not is_instance_valid(_player):
		return false

	var from_position := global_position + Vector3.UP * 1.2
	var to_position := _player.global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(from_position, to_position)
	query.exclude = [ self ]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true

	var collider: Object = hit.get("collider")
	if collider == _player:
		return true
	if collider is Node:
		var node := collider as Node
		if node.is_in_group("player"):
			return true
		while node != null:
			if node == _player:
				return true
			node = node.get_parent()
	return false


func _alert_once(source_position: Vector3) -> void:
	if not call_for_help or _alert_cooldown_left > 0.0:
		return

	_alert_cooldown_left = alert_cooldown_time
	for candidate in get_tree().get_nodes_in_group(alert_group_name):
		if candidate == self:
			continue
		if candidate.has_method("receive_alert"):
			candidate.call("receive_alert", source_position)


func receive_alert(source_position: Vector3) -> void:
	_last_known_player_position = source_position
	_has_last_known_position = true
	_target_memory_left = maxf(_target_memory_left, target_memory_time * 0.8)
	_is_player_in_detection = true


func apply_damage(amount: float) -> void:
	if _health <= 0.0:
		return
	_health = maxf(0.0, _health - amount)
	if _health <= 0.0:
		queue_free()


func _build_flee_target() -> Vector3:
	if is_instance_valid(_player):
		var away := global_position - _player.global_position
		away.y = 0.0
		if away.length() < 0.05:
			away = Vector3.FORWARD
		away = away.normalized()
		return global_position + away * maxf(flee_safe_distance, 6.0)

	return _home_position + Vector3(
		_rng.randf_range(-patrol_radius, patrol_radius),
		0.0,
		_rng.randf_range(-patrol_radius, patrol_radius)
	)


func _request_next_patrol_target(force_new: bool) -> void:
	if not force_new and _patrol_wait_left > 0.0:
		return

	_patrol_wait_left = _rng.randf_range(patrol_wait_min, patrol_wait_max)
	_patrol_target = _home_position + Vector3(
		_rng.randf_range(-patrol_radius, patrol_radius),
		0.0,
		_rng.randf_range(-patrol_radius, patrol_radius)
	)
	_patrol_target_ready = true


func _find_player() -> Node3D:
	var node := get_tree().get_first_node_in_group("player")
	if node == null:
		node = get_tree().get_root().find_child("Player", true, false)
	if node == null:
		node = get_tree().get_root().find_child("PlayerTest", true, false)
	return node as Node3D


func _resolve_player_target() -> Node3D:
	if is_instance_valid(_player):
		return _player
	_player = _find_player()
	return _player


func _apply_damage_to_player(amount: float) -> void:
	var player_target := _player
	if not is_instance_valid(player_target):
		player_target = _find_player()
	if not is_instance_valid(player_target):
		push_warning("Monster cannot apply damage: player reference is invalid")
		return

	if DEBUG_MONSTER_COMBAT:
		print("[Monster] applying damage to", player_target.name, "amount=", amount, "has_apply=", player_target.has_method("apply_damage"))

	if player_target.has_method("apply_damage"):
		player_target.call("apply_damage", amount)
		return

	if player_target is Node:
		var target_with_damage := _find_damage_target(player_target)
		if target_with_damage != null:
			if DEBUG_MONSTER_COMBAT:
				print("[Monster] applying damage via target", target_with_damage.name)
			target_with_damage.call("apply_damage", amount)
			return

	if "health" in player_target:
		var current_health := float(player_target.get("health"))
		current_health = maxf(0.0, current_health - amount)
		player_target.set("health", current_health)
		if player_target.has_method("_emit_health_changed"):
			player_target.call("_emit_health_changed")


func _flat_distance_to_player() -> float:
	if not is_instance_valid(_player):
		return INF
	var delta := _player.global_position - global_position
	delta.y = 0.0
	return delta.length()

func _find_damage_target(node: Node) -> Node:
	if node == null:
		return null
	if node.has_method("apply_damage"):
		return node
	for child in node.get_children():
		if child is Node and child.has_method("apply_damage"):
			return child
	var parent := node.get_parent()
	while parent != null:
		if parent.has_method("apply_damage"):
			return parent
		parent = parent.get_parent()
	return null


func get_save_data() -> Dictionary:
	return {
		"position": [global_position.x, global_position.y, global_position.z],
		"rotation_y_degrees": rotation_degrees.y,
		"health": _health,
		"behavior": int(_behavior),
		"patrol_index": _patrol_index,
		"last_known_player_position": [
			_last_known_player_position.x,
			_last_known_player_position.y,
			_last_known_player_position.z,
		],
		"has_last_known_position": _has_last_known_position,
	}


func apply_save_data(data: Dictionary) -> void:
	var position_data: Variant = data.get("position", [])
	if position_data is Array and position_data.size() >= 3:
		global_position = Vector3(float(position_data[0]), float(position_data[1]), float(position_data[2]))
	rotation_degrees.y = float(data.get("rotation_y_degrees", rotation_degrees.y))
	_health = clampf(float(data.get("health", _health)), 0.0, max_health)
	var saved_behavior := int(data.get("behavior", int(_behavior)))
	if saved_behavior >= 0 and saved_behavior <= Behavior.DEAD:
		_behavior = saved_behavior
	_patrol_index = int(data.get("patrol_index", _patrol_index))
	var last_known_data: Variant = data.get("last_known_player_position", [])
	if last_known_data is Array and last_known_data.size() >= 3:
		_last_known_player_position = Vector3(float(last_known_data[0]), float(last_known_data[1]), float(last_known_data[2]))
	_has_last_known_position = bool(data.get("has_last_known_position", _has_last_known_position))
	_target_memory_left = target_memory_time if _has_last_known_position else 0.0
	_request_next_patrol_target(true)


func _add_to_monster_group() -> void:
	if not is_in_group(alert_group_name):
		add_to_group(alert_group_name)
