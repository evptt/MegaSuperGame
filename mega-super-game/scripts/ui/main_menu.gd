extends Control

const GAME_SCENE_PATH := "res://scenes/levels/main.tscn"
const SETTINGS_WINDOW_SCENE_PATH := "res://scenes/ui/settings_window.tscn"
const SAVE_SLOTS_WINDOW_SCENE := preload("res://scenes/ui/save_slots_window.tscn")
const MENU_BACKGROUND := preload("res://assets/menu_background/menu_background.png")

var start_button: Button
var load_button: Button
var settings_button: Button
var exit_button: Button
var loading_overlay: Control
var loading_panel: PanelContainer
var loading_label: Label
var loading_progress: ProgressBar
var _settings_window: CanvasLayer = null
var _save_slots_window: CanvasLayer = null

var _is_loading := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_background()
	_build_overlay()
	_build_menu()
	_build_loading_overlay()
	start_button.grab_focus()


func _build_background() -> void:
	var background := TextureRect.new()
	background.name = "Background"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.texture = MENU_BACKGROUND
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(background)


func _build_overlay() -> void:
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.02, 0.02, 0.03, 0.58)
	add_child(overlay)

	var vignette := ColorRect.new()
	vignette.name = "Vignette"
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.0, 0.0, 0.0, 0.20)
	add_child(vignette)


func _build_menu() -> void:
	var menu_left := 66.0
	var title_top := 738.0
	var item_top := 858.0
	var item_gap := 60.0

	var title := Label.new()
	title.text = "MENU"
	title.position = Vector2(menu_left, title_top)
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.84, 0.38, 0.05))
	title.add_theme_constant_override("outline_size", 2)
	title.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.02))
	add_child(title)

	start_button = _create_menu_button("NEW GAME")
	start_button.pressed.connect(_on_start_pressed)
	start_button.position = Vector2(menu_left - 4.0, item_top)
	add_child(start_button)

	load_button = _create_menu_button("LOAD GAME")
	load_button.pressed.connect(_on_load_pressed)
	load_button.position = Vector2(menu_left - 4.0, item_top + item_gap)
	add_child(load_button)

	settings_button = _create_menu_button("SETTINGS")
	settings_button.pressed.connect(_on_settings_pressed)
	settings_button.position = Vector2(menu_left - 4.0, item_top + item_gap * 2.0)
	add_child(settings_button)

	exit_button = _create_menu_button("EXIT")
	exit_button.pressed.connect(_on_exit_pressed)
	exit_button.position = Vector2(menu_left - 4.0, item_top + item_gap * 3.0)
	add_child(exit_button)


func _build_loading_overlay() -> void:
	loading_overlay = Control.new()
	loading_overlay.name = "LoadingOverlay"
	loading_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	loading_overlay.visible = false
	add_child(loading_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.56)
	loading_overlay.add_child(dim)

	loading_panel = PanelContainer.new()
	loading_panel.set_anchors_preset(Control.PRESET_CENTER)
	loading_panel.position = Vector2(-260.0, -92.0)
	loading_panel.custom_minimum_size = Vector2(520.0, 184.0)
	loading_panel.add_theme_stylebox_override("panel", _create_loading_panel_style())
	loading_overlay.add_child(loading_panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	content.offset_left = 28.0
	content.offset_top = 22.0
	content.offset_right = -28.0
	content.offset_bottom = -22.0
	loading_panel.add_child(content)

	loading_label = Label.new()
	loading_label.text = "LOADING"
	loading_label.add_theme_font_size_override("font_size", 32)
	loading_label.add_theme_color_override("font_color", Color(0.95, 0.63, 0.22))
	loading_label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
	loading_label.add_theme_constant_override("outline_size", 2)
	content.add_child(loading_label)

	loading_progress = ProgressBar.new()
	loading_progress.min_value = 0.0
	loading_progress.max_value = 100.0
	loading_progress.value = 0.0
	loading_progress.custom_minimum_size = Vector2(460.0, 22.0)
	loading_progress.add_theme_stylebox_override("background", _create_progress_style(Color(0.10, 0.08, 0.06, 0.9), Color(0.38, 0.22, 0.08)))
	loading_progress.add_theme_stylebox_override("fill", _create_progress_fill_style())
	content.add_child(loading_progress)

	var hint := Label.new()
	hint.text = "Loading game..."
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.90, 0.84, 0.76, 0.86))
	content.add_child(hint)


func _create_menu_button(button_text: String) -> Button:
	var button := Button.new()
	button.text = button_text
	button.custom_minimum_size = Vector2(360.0, 42.0)
	button.focus_mode = Control.FOCUS_ALL
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 26)
	button.add_theme_color_override("font_color", Color(0.68, 0.31, 0.05))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.58, 0.1))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.72, 0.24))
	button.add_theme_color_override("font_focus_color", Color(1.0, 0.72, 0.24))
	button.add_theme_color_override("font_disabled_color", Color(0.28, 0.16, 0.08, 0.42))
	button.add_theme_stylebox_override("normal", _create_text_style())
	button.add_theme_stylebox_override("hover", _create_text_style())
	button.add_theme_stylebox_override("pressed", _create_text_style())
	button.add_theme_stylebox_override("focus", _create_text_style())
	return button


func _create_text_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.content_margin_left = 0
	style.content_margin_top = 0
	style.content_margin_right = 0
	style.content_margin_bottom = 0
	return style


func _create_loading_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.04, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.62, 0.36, 0.10, 1.0)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 0
	style.content_margin_top = 0
	style.content_margin_right = 0
	style.content_margin_bottom = 0
	return style


func _create_progress_style(fill_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border_color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


func _create_progress_fill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.88, 0.48, 0.08, 1.0)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


func _on_start_pressed() -> void:
	if _is_loading:
		return
	_is_loading = true
	_set_menu_interactive(false)
	loading_overlay.visible = true
	loading_progress.value = 0.0
	loading_label.text = "LOADING"
	var request_result := ResourceLoader.load_threaded_request(GAME_SCENE_PATH)
	if request_result != OK:
		push_error("Failed to start loading game scene: %s" % GAME_SCENE_PATH)
		_is_loading = false
		_set_menu_interactive(true)
		loading_overlay.visible = false
		return
	set_process(true)


func _process(_delta: float) -> void:
	if not _is_loading:
		return
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(GAME_SCENE_PATH, progress)
	if progress.size() > 0:
		loading_progress.value = float(progress[0]) * 100.0
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var resource := ResourceLoader.load_threaded_get(GAME_SCENE_PATH)
		if resource is PackedScene:
			get_tree().change_scene_to_packed(resource)
		else:
			push_error("Loaded resource is not a PackedScene: %s" % GAME_SCENE_PATH)
			_is_loading = false
			_set_menu_interactive(true)
			loading_overlay.visible = false
		set_process(false)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		push_error("Failed to load game scene: %s" % GAME_SCENE_PATH)
		_is_loading = false
		_set_menu_interactive(true)
		loading_overlay.visible = false
		set_process(false)


func _set_menu_interactive(enabled: bool) -> void:
	start_button.disabled = not enabled
	load_button.disabled = not enabled
	settings_button.disabled = not enabled
	exit_button.disabled = not enabled
	mouse_filter = Control.MOUSE_FILTER_STOP


func _on_load_pressed() -> void:
	_open_save_slots_window()


func _on_settings_pressed() -> void:
	_open_settings_window()


func _open_save_slots_window() -> void:
	if _save_slots_window != null and is_instance_valid(_save_slots_window):
		_save_slots_window.call("open_load_mode")
		return
	var window := SAVE_SLOTS_WINDOW_SCENE.instantiate() as CanvasLayer
	_save_slots_window = window
	window.tree_exited.connect(_on_save_slots_window_closed)
	get_tree().current_scene.add_child(window)
	window.call("open_load_mode")


func _on_save_slots_window_closed() -> void:
	_save_slots_window = null


func _open_settings_window() -> void:
	if _settings_window != null and is_instance_valid(_settings_window):
		_settings_window.call("open_window")
		return
	var scene := load(SETTINGS_WINDOW_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("Failed to load settings window scene: %s" % SETTINGS_WINDOW_SCENE_PATH)
		return
	var window := scene.instantiate() as CanvasLayer
	_settings_window = window
	window.tree_exited.connect(_on_settings_window_closed)
	get_tree().current_scene.add_child(window)
	window.call("open_window")


func _on_settings_window_closed() -> void:
	_settings_window = null


func _on_exit_pressed() -> void:
	get_tree().quit()
