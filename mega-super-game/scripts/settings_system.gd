extends Node

signal setting_changed(setting_name: String, value: Variant)

const CONFIG_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "settings"
const MIN_MOUSE_SENSITIVITY := 0.02
const MAX_MOUSE_SENSITIVITY := 0.30

var master_volume_percent: float = 100.0
var menu_music_volume_percent: float = 100.0
var fullscreen_enabled: bool = false
var mouse_sensitivity: float = 0.1


func _ready() -> void:
	_load_settings()
	_apply_all_settings()


func get_master_volume_percent() -> float:
	return master_volume_percent


func get_menu_music_volume_percent() -> float:
	return menu_music_volume_percent


func get_fullscreen_enabled() -> bool:
	return fullscreen_enabled


func get_mouse_sensitivity() -> float:
	return mouse_sensitivity


func set_master_volume_percent(value: float) -> void:
	master_volume_percent = clampf(value, 0.0, 100.0)
	_apply_audio_settings()
	_save_settings()
	emit_signal("setting_changed", "master_volume_percent", master_volume_percent)


func set_menu_music_volume_percent(value: float) -> void:
	menu_music_volume_percent = clampf(value, 0.0, 100.0)
	_apply_audio_settings()
	_save_settings()
	emit_signal("setting_changed", "menu_music_volume_percent", menu_music_volume_percent)


func set_fullscreen_enabled(value: bool) -> void:
	fullscreen_enabled = value
	_apply_display_settings()
	_save_settings()
	emit_signal("setting_changed", "fullscreen_enabled", fullscreen_enabled)


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
	_save_settings()
	emit_signal("setting_changed", "mouse_sensitivity", mouse_sensitivity)


func get_settings_snapshot() -> Dictionary:
	return {
		"master_volume_percent": master_volume_percent,
		"menu_music_volume_percent": menu_music_volume_percent,
		"fullscreen_enabled": fullscreen_enabled,
		"mouse_sensitivity": mouse_sensitivity,
	}


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		master_volume_percent = float(config.get_value(SETTINGS_SECTION, "master_volume_percent", master_volume_percent))
		menu_music_volume_percent = float(config.get_value(SETTINGS_SECTION, "menu_music_volume_percent", menu_music_volume_percent))
		fullscreen_enabled = bool(config.get_value(SETTINGS_SECTION, "fullscreen_enabled", fullscreen_enabled))
		mouse_sensitivity = clampf(float(config.get_value(SETTINGS_SECTION, "mouse_sensitivity", mouse_sensitivity)), MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SETTINGS_SECTION, "master_volume_percent", master_volume_percent)
	config.set_value(SETTINGS_SECTION, "menu_music_volume_percent", menu_music_volume_percent)
	config.set_value(SETTINGS_SECTION, "fullscreen_enabled", fullscreen_enabled)
	config.set_value(SETTINGS_SECTION, "mouse_sensitivity", mouse_sensitivity)
	config.save(CONFIG_PATH)


func _apply_all_settings() -> void:
	_apply_audio_settings()
	_apply_display_settings()


func _apply_audio_settings() -> void:
	_apply_bus_volume("Master", master_volume_percent)
	_apply_bus_volume("MenuMusic", menu_music_volume_percent)


func _apply_bus_volume(bus_name: String, percent: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		return
	var clamped := clampf(percent, 0.0, 100.0)
	var db := -80.0
	if clamped > 0.0:
		db = linear_to_db(clamped / 100.0)
	AudioServer.set_bus_volume_db(bus_index, db)


func _apply_display_settings() -> void:
	if fullscreen_enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)