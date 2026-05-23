extends Area3D

@export var checkpoint_index: int = 1
@export var goal_text: String = ""
@export var is_final_checkpoint: bool = false
@export var final_message: String = "You escaped from the facility"
@export var final_delay: float = 2.0
@export var return_scene_path: String = "res://scenes/ui/main_menu.tscn"

var _triggered := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _triggered:
		return
	if body == null or not body.is_in_group("player"):
		return
	var progress: Node = get_tree().root.get_node_or_null("CheckpointProgress")
	if progress == null or not bool(progress.call("can_trigger", checkpoint_index)):
		return

	_triggered = true
	monitoring = false
	progress.call("advance")
	_update_goal()
	if is_final_checkpoint:
		await _run_victory_sequence()


func _update_goal() -> void:
	if goal_text.is_empty():
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	var hud := scene_root.get_node_or_null("Player/HUD")
	if hud != null and hud.has_method("set_goal"):
		hud.call("set_goal", goal_text)


func _run_victory_sequence() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	for player in get_tree().get_nodes_in_group("player"):
		if player is Node:
			player.set_process(false)
			player.set_physics_process(false)
			player.set_process_input(false)
			player.set_process_unhandled_input(false)
			player.set_process_unhandled_key_input(false)

	var overlay := CanvasLayer.new()
	overlay.layer = 200
	scene_root.add_child(overlay)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(root)

	var black := ColorRect.new()
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.color = Color(0, 0, 0, 1)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(black)

	var message := Label.new()
	message.text = final_message
	message.add_theme_color_override("font_color", Color(1, 1, 1))
	message.add_theme_font_size_override("font_size", 58)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.set_anchors_preset(Control.PRESET_FULL_RECT)
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(message)

	await get_tree().create_timer(final_delay).timeout
	get_tree().change_scene_to_file(return_scene_path)