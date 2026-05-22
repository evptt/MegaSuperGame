extends CanvasLayer

signal closed

const MIN_MOUSE_SENSITIVITY := 0.02
const MAX_MOUSE_SENSITIVITY := 0.30

var panel_root: Control
var title_label: Label
var subtitle_label: Label
var master_volume_slider: HSlider
var master_volume_value: Label
var menu_volume_slider: HSlider
var menu_volume_value: Label
var fullscreen_toggle: CheckButton
var mouse_sensitivity_slider: HSlider
var mouse_sensitivity_value: Label
var close_button: Button

var _is_syncing_controls := false


func _ready() -> void:
	layer = 210
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	_sync_from_system()


func open_window() -> void:
	visible = true
	_sync_from_system()
	close_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		close_window()


func _build_ui() -> void:
	panel_root = Control.new()
	panel_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.58)
	panel_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-370.0, -250.0)
	panel.custom_minimum_size = Vector2(740.0, 500.0)
	panel.add_theme_stylebox_override("panel", _create_panel_style())
	panel_root.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	content.offset_left = 28.0
	content.offset_top = 22.0
	content.offset_right = -28.0
	content.offset_bottom = -22.0
	panel.add_child(content)

	title_label = Label.new()
	title_label.text = "SETTINGS"
	title_label.add_theme_font_size_override("font_size", 34)
	title_label.add_theme_color_override("font_color", Color(0.95, 0.63, 0.22))
	title_label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
	title_label.add_theme_constant_override("outline_size", 2)
	content.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.text = "Audio, display and input"
	subtitle_label.add_theme_font_size_override("font_size", 18)
	subtitle_label.add_theme_color_override("font_color", Color(0.90, 0.84, 0.76, 0.88))
	content.add_child(subtitle_label)

	var master_row := _create_slider_row("MASTER VOLUME", "Overall game volume", 0.0, 100.0, 1.0, "0%")
	master_volume_slider = master_row["slider"]
	master_volume_value = master_row["value_label"]
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	content.add_child(master_row["row"])

	var menu_row := _create_slider_row("MENU MUSIC VOLUME", "Reserved for future menu music", 0.0, 100.0, 1.0, "0%")
	menu_volume_slider = menu_row["slider"]
	menu_volume_value = menu_row["value_label"]
	menu_volume_slider.value_changed.connect(_on_menu_volume_changed)
	content.add_child(menu_row["row"])

	content.add_child(_create_toggle_row())

	var mouse_row := _create_slider_row("MOUSE SENSITIVITY", "Camera look speed", MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY, 0.005, "0.10")
	mouse_sensitivity_slider = mouse_row["slider"]
	mouse_sensitivity_value = mouse_row["value_label"]
	mouse_sensitivity_slider.value_changed.connect(_on_mouse_sensitivity_changed)
	content.add_child(mouse_row["row"])

	close_button = Button.new()
	close_button.text = "CLOSE"
	close_button.custom_minimum_size = Vector2(180.0, 40.0)
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_ALL
	close_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.add_theme_color_override("font_color", Color(0.68, 0.31, 0.05))
	close_button.add_theme_color_override("font_hover_color", Color(1.0, 0.58, 0.1))
	close_button.add_theme_color_override("font_pressed_color", Color(1.0, 0.72, 0.24))
	close_button.add_theme_color_override("font_focus_color", Color(1.0, 0.72, 0.24))
	close_button.add_theme_stylebox_override("normal", _create_text_style())
	close_button.add_theme_stylebox_override("hover", _create_text_style())
	close_button.add_theme_stylebox_override("pressed", _create_text_style())
	close_button.add_theme_stylebox_override("focus", _create_text_style())
	close_button.pressed.connect(close_window)
	content.add_child(close_button)


func _create_slider_row(title: String, description: String, min_value: float, max_value: float, step_value: float, initial_text: String) -> Dictionary:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	row.add_child(header)

	var label_block := VBoxContainer.new()
	label_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label_block)

	var title_label_node := Label.new()
	title_label_node.text = title
	title_label_node.add_theme_font_size_override("font_size", 22)
	title_label_node.add_theme_color_override("font_color", Color(0.80, 0.34, 0.04))
	label_block.add_child(title_label_node)

	var description_label := Label.new()
	description_label.text = description
	description_label.add_theme_font_size_override("font_size", 16)
	description_label.add_theme_color_override("font_color", Color(0.90, 0.84, 0.76, 0.82))
	label_block.add_child(description_label)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(70.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 18)
	value_label.add_theme_color_override("font_color", Color(0.95, 0.63, 0.22))
	header.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.add_theme_stylebox_override("slider", _create_slider_style())
	slider.add_theme_stylebox_override("grabber", _create_grabber_style())
	row.add_child(slider)

	value_label.text = initial_text
	return {
		"row": row,
		"slider": slider,
		"value_label": value_label,
	}


func _create_toggle_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var text_block := VBoxContainer.new()
	text_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_block)

	var title_node := Label.new()
	title_node.text = "FULLSCREEN MODE"
	title_node.add_theme_font_size_override("font_size", 22)
	title_node.add_theme_color_override("font_color", Color(0.80, 0.34, 0.04))
	text_block.add_child(title_node)

	var description_node := Label.new()
	description_node.text = "Switch between windowed and fullscreen display"
	description_node.add_theme_font_size_override("font_size", 16)
	description_node.add_theme_color_override("font_color", Color(0.90, 0.84, 0.76, 0.82))
	text_block.add_child(description_node)

	fullscreen_toggle = CheckButton.new()
	fullscreen_toggle.text = "FULLSCREEN"
	fullscreen_toggle.focus_mode = Control.FOCUS_ALL
	fullscreen_toggle.add_theme_font_size_override("font_size", 20)
	fullscreen_toggle.add_theme_color_override("font_color", Color(0.88, 0.48, 0.08))
	fullscreen_toggle.add_theme_color_override("font_hover_color", Color(1.0, 0.62, 0.12))
	fullscreen_toggle.add_theme_color_override("font_pressed_color", Color(1.0, 0.76, 0.30))
	fullscreen_toggle.add_theme_color_override("font_focus_color", Color(1.0, 0.76, 0.30))
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	row.add_child(fullscreen_toggle)

	return row


func _sync_from_system() -> void:
	var settings_system := _get_settings_system()
	if settings_system == null:
		return
	_is_syncing_controls = true
	if master_volume_slider != null:
		master_volume_slider.value = float(settings_system.call("get_master_volume_percent"))
	if menu_volume_slider != null:
		menu_volume_slider.value = float(settings_system.call("get_menu_music_volume_percent"))
	if fullscreen_toggle != null:
		fullscreen_toggle.button_pressed = bool(settings_system.call("get_fullscreen_enabled"))
	if mouse_sensitivity_slider != null:
		mouse_sensitivity_slider.value = float(settings_system.call("get_mouse_sensitivity"))
	_update_slider_value_labels()
	_is_syncing_controls = false


func _on_master_volume_changed(value: float) -> void:
	if _is_syncing_controls:
		return
	_update_master_volume_label(value)
	var settings_system := _get_settings_system()
	if settings_system != null:
		settings_system.call("set_master_volume_percent", value)


func _on_menu_volume_changed(value: float) -> void:
	if _is_syncing_controls:
		return
	_update_menu_volume_label(value)
	var settings_system := _get_settings_system()
	if settings_system != null:
		settings_system.call("set_menu_music_volume_percent", value)


func _on_fullscreen_toggled(enabled: bool) -> void:
	if _is_syncing_controls:
		return
	var settings_system := _get_settings_system()
	if settings_system != null:
		settings_system.call("set_fullscreen_enabled", enabled)


func _on_mouse_sensitivity_changed(value: float) -> void:
	if _is_syncing_controls:
		return
	_update_mouse_sensitivity_label(value)
	var settings_system := _get_settings_system()
	if settings_system != null:
		settings_system.call("set_mouse_sensitivity", value)


func _update_slider_value_labels() -> void:
	_update_master_volume_label(master_volume_slider.value)
	_update_menu_volume_label(menu_volume_slider.value)
	_update_mouse_sensitivity_label(mouse_sensitivity_slider.value)


func _update_master_volume_label(value: float) -> void:
	if master_volume_value != null:
		master_volume_value.text = "%d%%" % int(round(value))


func _update_menu_volume_label(value: float) -> void:
	if menu_volume_value != null:
		menu_volume_value.text = "%d%%" % int(round(value))


func _update_mouse_sensitivity_label(value: float) -> void:
	if mouse_sensitivity_value != null:
		mouse_sensitivity_value.text = "%.3f" % value


func close_window() -> void:
	visible = false
	emit_signal("closed")
	queue_free()


func _create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.04, 0.98)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.62, 0.36, 0.10, 1.0)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


func _create_text_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	return style


func _create_slider_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.08, 0.06, 0.96)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.38, 0.22, 0.08, 1.0)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


func _create_grabber_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.88, 0.48, 0.08, 1.0)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


func _get_settings_system() -> Node:
	return get_node_or_null("/root/SettingsSystem")