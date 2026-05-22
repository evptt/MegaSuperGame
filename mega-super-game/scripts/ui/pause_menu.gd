extends CanvasLayer

const MAIN_MENU_SCENE_PATH := "res://scenes/ui/main_menu.tscn"
const SETTINGS_WINDOW_SCENE_PATH := "res://scenes/ui/settings_window.tscn"
const SAVE_SLOTS_WINDOW_SCENE := preload("res://scenes/ui/save_slots_window.tscn")

var panel_root: Control
var title_label: Label
var continue_button: Button
var save_button: Button
var settings_button: Button
var exit_menu_button: Button
var exit_button: Button
var _settings_window: CanvasLayer = null
var _save_slots_window: CanvasLayer = null
var _visible_menu := false
var _is_death_menu := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_update_layout()
	panel_root.visible = false
	var viewport := get_viewport()
	if viewport != null and viewport.has_signal("size_changed"):
		viewport.connect("size_changed", Callable(self , "_update_layout"))


func _unhandled_input(event: InputEvent) -> void:
	if _is_pause_key(event):
		get_viewport().set_input_as_handled()
		if _visible_menu:
			if _is_death_menu:
				return
			_resume_game()
		else:
			_show_pause_menu()


func _is_pause_key(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		return event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE
	return false


func _build_ui() -> void:
	panel_root = Control.new()
	panel_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel_root)

	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.0, 0.0, 0.0, 0.52)
	panel_root.add_child(overlay)

	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.0, 0.0, 0.0, 0.18)
	panel_root.add_child(vignette)

	title_label = _make_label("PAUSE", 52, Color(0.80, 0.36, 0.04))
	panel_root.add_child(title_label)

	continue_button = _make_button("CONTINUE")
	continue_button.pressed.connect(_resume_game)
	panel_root.add_child(continue_button)

	save_button = _make_button("SAVE GAME")
	save_button.pressed.connect(_open_save_slots_window)
	panel_root.add_child(save_button)

	settings_button = _make_button("SETTINGS")
	settings_button.pressed.connect(_open_settings_window)
	panel_root.add_child(settings_button)

	exit_menu_button = _make_button("EXIT TO MENU")
	exit_menu_button.pressed.connect(_exit_to_menu)
	panel_root.add_child(exit_menu_button)

	exit_button = _make_button("EXIT")
	exit_button.pressed.connect(_exit_game)
	panel_root.add_child(exit_button)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.03, 0.02, 0.01))
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(360.0, 42.0)
	button.add_theme_font_size_override("font_size", 26)
	button.add_theme_color_override("font_color", Color(0.68, 0.31, 0.05))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.60, 0.12))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.74, 0.26))
	button.add_theme_color_override("font_focus_color", Color(1.0, 0.74, 0.26))
	button.add_theme_color_override("font_disabled_color", Color(0.28, 0.16, 0.08, 0.42))
	button.add_theme_stylebox_override("normal", _empty_style())
	button.add_theme_stylebox_override("hover", _empty_style())
	button.add_theme_stylebox_override("pressed", _empty_style())
	button.add_theme_stylebox_override("focus", _empty_style())
	return button


func _empty_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.content_margin_left = 0
	style.content_margin_top = 0
	style.content_margin_right = 0
	style.content_margin_bottom = 0
	return style


func _update_layout() -> void:
	if panel_root == null:
		return
	var size := get_viewport().get_visible_rect().size
	var left_x := 66.0
	var title_y := size.y * 0.58
	var first_item_y := title_y + 110.0
	var gap := 58.0

	title_label.position = Vector2(left_x, title_y)
	continue_button.position = Vector2(left_x - 4.0, first_item_y)
	save_button.position = Vector2(left_x - 4.0, first_item_y + gap)
	settings_button.position = Vector2(left_x - 4.0, first_item_y + gap * 2.0)
	exit_menu_button.position = Vector2(left_x - 4.0, first_item_y + gap * 3.0)
	exit_button.position = Vector2(left_x - 4.0, first_item_y + gap * 4.0)


func _show_pause_menu() -> void:
	_is_death_menu = false
	_visible_menu = true
	panel_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_layout()
	continue_button.visible = true
	continue_button.disabled = false
	if continue_button.visible:
		continue_button.grab_focus()


func show_death_menu() -> void:
	_is_death_menu = true
	_visible_menu = true
	panel_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_layout()
	continue_button.visible = false
	continue_button.disabled = true
	if exit_menu_button.visible:
		exit_menu_button.grab_focus()


func _resume_game() -> void:
	_visible_menu = false
	panel_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open_save_slots_window() -> void:
	if _save_slots_window != null and is_instance_valid(_save_slots_window):
		_save_slots_window.call("open_save_mode")
		return
	var window := SAVE_SLOTS_WINDOW_SCENE.instantiate() as CanvasLayer
	_save_slots_window = window
	window.tree_exited.connect(_on_save_slots_window_closed)
	get_tree().current_scene.add_child(window)
	window.call("open_save_mode")


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


func _exit_to_menu() -> void:
	_visible_menu = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _exit_game() -> void:
	get_tree().paused = false
	get_tree().quit()
