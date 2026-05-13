extends CharacterBody3D

@export var move_speed := 3.0
@export var max_hp := 30.0

const HEALTH_BAR_WIDTH := 0.76
const HEALTH_BAR_HEIGHT := 0.06
const HEALTH_BAR_BG_WIDTH := 0.8
const HEALTH_BAR_BG_HEIGHT := 0.1
const HEALTH_BAR_OFFSET := Vector3(0.0, 1.2, 0.0)

var _hp := 0.0
var _player: Node3D
var _health_bar_root: Node3D
var _health_bar_fill: MeshInstance3D
var _health_bar_width := HEALTH_BAR_WIDTH


func _ready() -> void:
	_hp = max_hp
	_player = _find_player()
	_create_health_bar()
	_update_health_bar()


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = _find_player()
		if _player == null:
			velocity = Vector3.ZERO
			move_and_slide()
			return

	var to_player := _player.global_transform.origin - global_transform.origin
	to_player.y = 0.0
	if to_player.length() > 0.05:
		velocity = to_player.normalized() * move_speed
	else:
		velocity = Vector3.ZERO

	move_and_slide()


func apply_damage(amount: float) -> void:
	_hp -= amount
	_update_health_bar()
	if _hp <= 0.0:
		queue_free()


func _find_player() -> Node3D:
	var node := get_tree().get_first_node_in_group("player")
	if node == null:
		node = get_tree().get_root().find_child("Player", true, false)
	if node == null:
		node = get_tree().get_root().find_child("PlayerTest", true, false)
	return node as Node3D


func _create_health_bar() -> void:
	var bar_root := Node3D.new()
	bar_root.name = "HealthBar"
	bar_root.position = HEALTH_BAR_OFFSET
	add_child(bar_root)

	var bg := MeshInstance3D.new()
	bg.name = "HealthBarBG"
	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(HEALTH_BAR_BG_WIDTH, HEALTH_BAR_BG_HEIGHT)
	bg.mesh = bg_mesh
	var bg_material := StandardMaterial3D.new()
	bg_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_material.albedo_color = Color(0.0, 0.0, 0.0, 0.6)
	bg_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg.material_override = bg_material
	bar_root.add_child(bg)

	var fill := MeshInstance3D.new()
	fill.name = "HealthBarFill"
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)
	fill.mesh = fill_mesh
	var fill_material := StandardMaterial3D.new()
	fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_material.albedo_color = Color(0.1, 0.9, 0.2, 0.9)
	fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fill.material_override = fill_material
	fill.position = Vector3(0.0, 0.0, 0.01)
	bar_root.add_child(fill)

	_health_bar_root = bar_root
	_health_bar_fill = fill
	_health_bar_width = fill_mesh.size.x


func _update_health_bar() -> void:
	if _health_bar_fill == null:
		return
	if max_hp <= 0.0:
		_health_bar_fill.visible = false
		return

	var ratio := clampf(_hp / max_hp, 0.0, 1.0)
	_health_bar_fill.visible = ratio > 0.0
	_health_bar_fill.scale = Vector3(ratio, 1.0, 1.0)
	var pos := _health_bar_fill.position
	pos.x = (_health_bar_width * (ratio - 1.0)) * 0.5
	_health_bar_fill.position = Vector3(pos.x, pos.y, pos.z)
