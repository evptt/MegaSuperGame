extends CanvasLayer

const LOAD_MODE := 0
const SAVE_MODE := 1
const CONFIRM_NONE := 0
const CONFIRM_OVERWRITE := 1
const CONFIRM_DELETE := 2

signal closed

var title_label: Label
var subtitle_label: Label
var slots_container: VBoxContainer
var status_label: Label
var progress_bar: ProgressBar
var cancel_button: Button
var panel_root: Control
var confirm_overlay: Control
var confirm_title_label: Label
var confirm_message_label: Label
var confirm_cancel_button: Button
var confirm_accept_button: Button

var _mode := LOAD_MODE
var _is_busy := false
var _is_confirm_visible := false
var _confirm_type := CONFIRM_NONE
var _confirm_slot_id := -1
var _active_slot_id := -1
var _loading_scene_path := ""
var _loading_progress := []
var _pending_save_data: Dictionary = {}


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_hide_busy_state()
	visible = false


func open_load_mode() -> void:
	_mode = LOAD_MODE
	visible = true
	_refresh_slots()
	_set_title("LOAD GAME", "Select a saved game to load")
	cancel_button.text = "CANCEL"
	status_label.text = ""
	_show_idle_state()
	_hide_confirm()
	cancel_button.grab_focus()


func open_save_mode() -> void:
	_mode = SAVE_MODE
	visible = true
	_refresh_slots()
	_set_title("SAVE GAME", "Select a slot to save current progress")
	cancel_button.text = "CANCEL"
	status_label.text = ""
	_show_idle_state()
	_hide_confirm()
	cancel_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _is_busy:
		return
	if _is_confirm_visible:
		if event.is_action_pressed("ui_cancel") and not event.is_echo():
			get_viewport().set_input_as_handled()
			_hide_confirm()
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
	panel.position = Vector2(-360.0, -260.0)
	panel.custom_minimum_size = Vector2(720.0, 520.0)
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
	title_label.add_theme_font_size_override("font_size", 34)
	title_label.add_theme_color_override("font_color", Color(0.95, 0.63, 0.22))
	title_label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
	title_label.add_theme_constant_override("outline_size", 2)
	content.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.add_theme_font_size_override("font_size", 18)
	subtitle_label.add_theme_color_override("font_color", Color(0.90, 0.84, 0.76, 0.88))
	content.add_child(subtitle_label)

	slots_container = VBoxContainer.new()
	slots_container.add_theme_constant_override("separation", 10)
	content.add_child(slots_container)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.add_theme_color_override("font_color", Color(0.96, 0.88, 0.78))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(status_label)

	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.custom_minimum_size = Vector2(660.0, 20.0)
	progress_bar.visible = false
	progress_bar.add_theme_stylebox_override("background", _create_progress_background())
	progress_bar.add_theme_stylebox_override("fill", _create_progress_fill())
	content.add_child(progress_bar)

	cancel_button = Button.new()
	cancel_button.text = "CANCEL"
	cancel_button.custom_minimum_size = Vector2(180.0, 40.0)
	cancel_button.focus_mode = Control.FOCUS_ALL
	cancel_button.flat = true
	cancel_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	cancel_button.add_theme_font_size_override("font_size", 24)
	cancel_button.add_theme_color_override("font_color", Color(0.68, 0.31, 0.05))
	cancel_button.add_theme_color_override("font_hover_color", Color(1.0, 0.58, 0.1))
	cancel_button.add_theme_stylebox_override("normal", _create_button_style())
	cancel_button.add_theme_stylebox_override("hover", _create_button_style())
	cancel_button.add_theme_stylebox_override("pressed", _create_button_style())
	cancel_button.add_theme_stylebox_override("focus", _create_button_style())
	cancel_button.pressed.connect(close_window)
	content.add_child(cancel_button)

	confirm_overlay = Control.new()
	confirm_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	confirm_overlay.visible = false
	panel_root.add_child(confirm_overlay)

	var confirm_dim := ColorRect.new()
	confirm_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm_dim.color = Color(0.0, 0.0, 0.0, 0.72)
	confirm_overlay.add_child(confirm_dim)

	var confirm_panel := PanelContainer.new()
	confirm_panel.set_anchors_preset(Control.PRESET_CENTER)
	confirm_panel.position = Vector2(-260.0, -120.0)
	confirm_panel.custom_minimum_size = Vector2(520.0, 240.0)
	confirm_panel.add_theme_stylebox_override("panel", _create_panel_style())
	confirm_overlay.add_child(confirm_panel)

	var confirm_content := VBoxContainer.new()
	confirm_content.add_theme_constant_override("separation", 14)
	confirm_content.offset_left = 24.0
	confirm_content.offset_top = 22.0
	confirm_content.offset_right = -24.0
	confirm_content.offset_bottom = -22.0
	confirm_panel.add_child(confirm_content)

	confirm_title_label = Label.new()
	confirm_title_label.add_theme_font_size_override("font_size", 30)
	confirm_title_label.add_theme_color_override("font_color", Color(0.95, 0.63, 0.22))
	confirm_title_label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
	confirm_title_label.add_theme_constant_override("outline_size", 2)
	confirm_content.add_child(confirm_title_label)

	confirm_message_label = Label.new()
	confirm_message_label.add_theme_font_size_override("font_size", 18)
	confirm_message_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.80))
	confirm_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_content.add_child(confirm_message_label)

	var confirm_buttons := HBoxContainer.new()
	confirm_buttons.add_theme_constant_override("separation", 12)
	confirm_content.add_child(confirm_buttons)

	confirm_accept_button = _create_confirm_button("YES")
	confirm_accept_button.pressed.connect(_accept_confirm)
	confirm_buttons.add_child(confirm_accept_button)

	confirm_cancel_button = _create_confirm_button("NO")
	confirm_cancel_button.pressed.connect(_hide_confirm)
	confirm_buttons.add_child(confirm_cancel_button)


func _refresh_slots() -> void:
	for child in slots_container.get_children():
		child.queue_free()
	var save_system := _get_save_system()
	if save_system == null:
		status_label.text = "Save system is unavailable."
		return
	var slots: Array = save_system.call("list_slots")
	for slot_info in slots:
		slots_container.add_child(_create_slot_row(int(slot_info.get("slot_id", 0)), slot_info))


func _create_slot_row(slot_id: int, slot_info: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(660.0, 66.0)

	var main_button := Button.new()
	main_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_button.custom_minimum_size = Vector2(0.0, 66.0)
	main_button.focus_mode = Control.FOCUS_ALL
	main_button.flat = true
	main_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	main_button.text = _build_slot_text(slot_id, slot_info)
	main_button.add_theme_font_size_override("font_size", 22)
	main_button.add_theme_color_override("font_color", Color(0.78, 0.34, 0.04))
	main_button.add_theme_color_override("font_hover_color", Color(1.0, 0.62, 0.12))
	main_button.add_theme_color_override("font_pressed_color", Color(1.0, 0.76, 0.30))
	main_button.add_theme_color_override("font_focus_color", Color(1.0, 0.76, 0.30))
	main_button.add_theme_color_override("font_disabled_color", Color(0.35, 0.23, 0.14, 0.46))
	main_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_button.add_theme_stylebox_override("normal", _create_slot_style())
	main_button.add_theme_stylebox_override("hover", _create_slot_style(Color(0.14, 0.11, 0.07, 0.96), Color(0.96, 0.62, 0.22)))
	main_button.add_theme_stylebox_override("pressed", _create_slot_style(Color(0.18, 0.10, 0.05, 0.98), Color(0.98, 0.46, 0.10)))
	main_button.add_theme_stylebox_override("focus", _create_slot_style(Color(0.12, 0.10, 0.06, 0.96), Color(0.98, 0.78, 0.34)))
	main_button.pressed.connect(_on_slot_selected.bind(slot_id))
	if _mode == LOAD_MODE and not bool(slot_info.get("exists", false)):
		main_button.disabled = true
	row.add_child(main_button)

	if _mode == LOAD_MODE:
		var delete_button := _create_small_action_button("DELETE")
		delete_button.disabled = not bool(slot_info.get("exists", false))
		delete_button.pressed.connect(_prompt_delete_slot.bind(slot_id, slot_info))
		row.add_child(delete_button)

	return row


func _create_small_action_button(text: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(120.0, 66.0)
	button.focus_mode = Control.FOCUS_ALL
	button.flat = true
	button.text = text
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color(0.64, 0.20, 0.04))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.38, 0.10))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.56, 0.12))
	button.add_theme_color_override("font_focus_color", Color(1.0, 0.56, 0.12))
	button.add_theme_color_override("font_disabled_color", Color(0.35, 0.23, 0.14, 0.46))
	button.add_theme_stylebox_override("normal", _create_slot_style(Color(0.10, 0.08, 0.06, 0.92), Color(0.38, 0.22, 0.08, 1.0)))
	button.add_theme_stylebox_override("hover", _create_slot_style(Color(0.18, 0.10, 0.05, 0.98), Color(0.98, 0.46, 0.10)))
	button.add_theme_stylebox_override("pressed", _create_slot_style(Color(0.22, 0.10, 0.04, 0.98), Color(0.98, 0.30, 0.08)))
	button.add_theme_stylebox_override("focus", _create_slot_style(Color(0.16, 0.10, 0.05, 0.98), Color(0.98, 0.78, 0.34)))
	return button


func _build_slot_text(slot_id: int, slot_info: Dictionary) -> String:
	var exists := bool(slot_info.get("exists", false))
	var scene_name := str(slot_info.get("scene_name", "Unknown"))
	var timestamp := str(slot_info.get("timestamp", ""))
	if _mode == LOAD_MODE:
		if exists:
			return "SLOT %d\n%s  %s" % [slot_id, scene_name, timestamp]
		return "SLOT %d\nEMPTY SLOT" % slot_id
	if exists:
		return "SLOT %d\nOverwrite %s  %s" % [slot_id, scene_name, timestamp]
	return "SLOT %d\nEmpty slot - save here" % slot_id


func _on_slot_selected(slot_id: int) -> void:
	if _mode == SAVE_MODE:
		_request_save_slot(slot_id)
	else:
		_load_slot(slot_id)


func _prompt_delete_slot(slot_id: int, slot_info: Dictionary) -> void:
	if _is_busy:
		return
	_confirm_type = CONFIRM_DELETE
	_confirm_slot_id = slot_id
	confirm_title_label.text = "DELETE SLOT"
	confirm_message_label.text = "Delete slot %d permanently?\n%s  %s" % [slot_id, str(slot_info.get("scene_name", "Unknown")), str(slot_info.get("timestamp", ""))]
	confirm_accept_button.text = "DELETE"
	confirm_accept_button.add_theme_color_override("font_color", Color(0.82, 0.18, 0.08))
	show_confirm()


func _request_save_slot(slot_id: int) -> void:
	var save_system := _get_save_system()
	if save_system == null:
		status_label.text = "Save system is unavailable."
		return
	var slot_data: Dictionary = save_system.call("read_slot", slot_id)
	if not slot_data.is_empty():
		_confirm_type = CONFIRM_OVERWRITE
		_confirm_slot_id = slot_id
		confirm_title_label.text = "OVERWRITE SLOT"
		confirm_message_label.text = "Overwrite slot %d?\n%s  %s" % [slot_id, str(slot_data.get("scene_name", "Unknown")), str(slot_data.get("timestamp", ""))]
		confirm_accept_button.text = "OVERWRITE"
		confirm_accept_button.add_theme_color_override("font_color", Color(0.90, 0.48, 0.08))
		show_confirm()
		return
	_save_slot(slot_id)


func _accept_confirm() -> void:
	var slot_id := _confirm_slot_id
	var confirm_type := _confirm_type
	_hide_confirm()
	if slot_id < 0:
		return
	if confirm_type == CONFIRM_OVERWRITE:
		_save_slot(slot_id)
	elif confirm_type == CONFIRM_DELETE:
		_delete_slot(slot_id)


func _save_slot(slot_id: int) -> void:
	var save_system := _get_save_system()
	if save_system == null:
		status_label.text = "Save system is unavailable."
		return
	if save_system.call("save_current_game", slot_id):
		status_label.text = "Game saved to slot %d." % slot_id
		_refresh_slots()
		_show_idle_state()
	else:
		status_label.text = "Failed to save slot %d." % slot_id


func _delete_slot(slot_id: int) -> void:
	var save_system := _get_save_system()
	if save_system == null:
		status_label.text = "Save system is unavailable."
		return
	if save_system.call("delete_slot", slot_id):
		status_label.text = "Slot %d deleted." % slot_id
		_refresh_slots()
		_show_idle_state()
	else:
		status_label.text = "Failed to delete slot %d." % slot_id


func _load_slot(slot_id: int) -> void:
	var save_system := _get_save_system()
	if save_system == null:
		status_label.text = "Save system is unavailable."
		return
	var slot_data: Dictionary = save_system.call("read_slot", slot_id)
	if typeof(slot_data) != TYPE_DICTIONARY or slot_data.is_empty():
		status_label.text = "Slot %d is empty." % slot_id
		return
	_active_slot_id = slot_id
	_pending_save_data = slot_data.duplicate(true)
	_loading_scene_path = str(slot_data.get("scene_path", "res://scenes/levels/main.tscn"))
	if _loading_scene_path == "":
		_loading_scene_path = "res://scenes/levels/main.tscn"
	_show_loading_state("Loading slot %d..." % slot_id)
	var request_result := ResourceLoader.load_threaded_request(_loading_scene_path)
	if request_result != OK:
		status_label.text = "Failed to start loading slot %d." % slot_id
		_hide_busy_state()
		return
	set_process(true)


func _process(_delta: float) -> void:
	if not _is_busy:
		return
	var status := ResourceLoader.load_threaded_get_status(_loading_scene_path, _loading_progress)
	if _loading_progress.size() > 0:
		progress_bar.value = float(_loading_progress[0]) * 100.0
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var resource := ResourceLoader.load_threaded_get(_loading_scene_path)
		var save_system := _get_save_system()
		if save_system != null:
			save_system.call("set_pending_load_data", _pending_save_data)
		if resource is PackedScene:
			get_tree().change_scene_to_packed(resource)
		else:
			status_label.text = "Loaded resource is not a PackedScene."
			_hide_busy_state()
			return
		set_process(false)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		status_label.text = "Failed to load slot %d." % _active_slot_id
		_hide_busy_state()
		set_process(false)


func close_window() -> void:
	if _is_busy:
		return
	visible = false
	emit_signal("closed")
	queue_free()


func _show_loading_state(message: String) -> void:
	_is_busy = true
	panel_root.mouse_filter = Control.MOUSE_FILTER_STOP
	progress_bar.visible = true
	progress_bar.value = 0.0
	status_label.text = message
	cancel_button.disabled = true
	for child in slots_container.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _hide_busy_state() -> void:
	_is_busy = false
	progress_bar.visible = false
	cancel_button.disabled = false
	set_process(false)
	_active_slot_id = -1
	_loading_scene_path = ""
	_pending_save_data = {}
	for child in slots_container.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_STOP


func _show_idle_state() -> void:
	_hide_busy_state()
	status_label.text = ""


func show_confirm() -> void:
	_is_confirm_visible = true
	confirm_overlay.visible = true
	panel_root.mouse_filter = Control.MOUSE_FILTER_STOP
	confirm_cancel_button.grab_focus()


func _hide_confirm() -> void:
	_is_confirm_visible = false
	_confirm_type = CONFIRM_NONE
	_confirm_slot_id = -1
	confirm_overlay.visible = false
	confirm_accept_button.add_theme_color_override("font_color", Color(0.90, 0.48, 0.08))
	if visible and not _is_busy:
		cancel_button.grab_focus()


func _create_confirm_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(140.0, 40.0)
	button.focus_mode = Control.FOCUS_ALL
	button.flat = true
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color(0.90, 0.48, 0.08))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.62, 0.12))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.76, 0.30))
	button.add_theme_color_override("font_focus_color", Color(1.0, 0.76, 0.30))
	button.add_theme_stylebox_override("normal", _create_slot_style())
	button.add_theme_stylebox_override("hover", _create_slot_style(Color(0.14, 0.11, 0.07, 0.96), Color(0.96, 0.62, 0.22)))
	button.add_theme_stylebox_override("pressed", _create_slot_style(Color(0.18, 0.10, 0.05, 0.98), Color(0.98, 0.46, 0.10)))
	button.add_theme_stylebox_override("focus", _create_slot_style(Color(0.12, 0.10, 0.06, 0.96), Color(0.98, 0.78, 0.34)))
	return button


func _set_title(title: String, subtitle: String) -> void:
	title_label.text = title
	subtitle_label.text = subtitle


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


func _create_slot_style(fill_color: Color = Color(0.10, 0.08, 0.06, 0.92), border_color: Color = Color(0.38, 0.22, 0.08, 1.0)) -> StyleBoxFlat:
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
	style.content_margin_left = 12
	style.content_margin_top = 10
	style.content_margin_right = 12
	style.content_margin_bottom = 10
	return style


func _create_button_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	return style


func _create_progress_background() -> StyleBoxFlat:
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


func _create_progress_fill() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.88, 0.48, 0.08, 1.0)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


func _get_save_system() -> Node:
	return get_node_or_null("/root/SaveSystem")
