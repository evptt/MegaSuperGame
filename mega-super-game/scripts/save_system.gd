extends Node

const SAVE_DIR := "user://saves"
const SAVE_FILE_TEMPLATE := "slot_%d.json"
const SAVE_VERSION := 1
const FALLBACK_SCENE_PATH := "res://scenes/levels/main.tscn"
const DEFAULT_SLOT_COUNT := 3

var _pending_load_data: Dictionary = {}


func _ready() -> void:
	_ensure_save_dir()


func get_slot_path(slot_id: int) -> String:
	return "%s/%s" % [SAVE_DIR, SAVE_FILE_TEMPLATE % slot_id]


func has_save(slot_id: int) -> bool:
	return FileAccess.file_exists(get_slot_path(slot_id))


func list_slots() -> Array:
	var slots: Array = []
	for slot_id in range(1, DEFAULT_SLOT_COUNT + 1):
		slots.append(get_slot_info(slot_id))
	return slots


func get_slot_info(slot_id: int) -> Dictionary:
	var data := read_slot(slot_id)
	return {
		"slot_id": slot_id,
		"exists": not data.is_empty(),
		"timestamp": str(data.get("timestamp", "")),
		"scene_path": str(data.get("scene_path", FALLBACK_SCENE_PATH)),
		"scene_name": _scene_display_name(str(data.get("scene_path", FALLBACK_SCENE_PATH))),
	}


func read_slot(slot_id: int) -> Dictionary:
	var path := get_slot_path(slot_id)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var raw := file.get_as_text()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var data := parsed as Dictionary
	if int(data.get("version", 0)) != SAVE_VERSION:
		return {}
	return data


func save_current_game(slot_id: int) -> bool:
	var scene_root := get_tree().get_current_scene()
	if scene_root == null:
		return false
	var player := _find_player(scene_root)
	if player == null or not player.has_method("get_save_data"):
		return false

	var player_data: Dictionary = player.call("get_save_data")
	var data := {
		"version": SAVE_VERSION,
		"timestamp": Time.get_datetime_string_from_system(),
		"scene_path": scene_root.scene_file_path if scene_root.scene_file_path != "" else FALLBACK_SCENE_PATH,
		"player": player_data,
	}
	return _write_slot(slot_id, data)


func delete_slot(slot_id: int) -> bool:
	var path := get_slot_path(slot_id)
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


func set_pending_load_data(data: Dictionary) -> void:
	_pending_load_data = data.duplicate(true)


func apply_pending_load(player: Node) -> bool:
	if _pending_load_data.is_empty():
		return false
	if player == null or not player.has_method("apply_save_data"):
		return false
	var player_data: Dictionary = _pending_load_data.get("player", {}) as Dictionary
	if typeof(player_data) != TYPE_DICTIONARY:
		return false
	player.call("apply_save_data", player_data)
	_pending_load_data = {}
	return true


func _write_slot(slot_id: int, data: Dictionary) -> bool:
	_ensure_save_dir()
	var path := get_slot_path(slot_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


func _ensure_save_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))


func _find_player(scene_root: Node) -> Node:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		return players[0]
	return scene_root.get_node_or_null("Player")


func _scene_display_name(scene_path: String) -> String:
	if scene_path == "":
		return "Unknown"
	return scene_path.get_file().trim_suffix(".tscn")
