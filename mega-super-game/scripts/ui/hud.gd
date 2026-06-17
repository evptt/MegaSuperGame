extends CanvasLayer

# HUD attached to the existing HUD CanvasLayer under Player.
# Layout matches the screenshot: goal top-left, health/stamina bottom-left,
# weapon/ammo and lidar bottom-right.

const BAR_WIDTH := 220.0
const BAR_HEIGHT := 8.0
const LEFT_MARGIN := 32.0
const TOP_MARGIN := 28.0
const BOTTOM_MARGIN := 32.0
const RIGHT_MARGIN := 32.0
const RIGHT_BLOCK_WIDTH := 300.0
const INTRO_TUTORIAL_STEP_DELAY := 0.25
const INTRO_TUTORIAL_END_DELAY := 0.6
const INTRO_TUTORIAL_FONT_SIZE := 26
const INTRO_TUTORIAL_TOP_OFFSET := 92.0
const INTRO_TUTORIAL_LINE_GAP := 6
const STORY_MESSAGE_FONT_SIZE := 30
const STORY_MESSAGE_TOP_OFFSET := 62.0
const INTRO_STORY_TEXT := "Нужно найти выход,\nв технической зоне вроде был\nлифт на поверхность..."
const STORY_HINT_DURATION := 5.0
const POST_TUTORIAL_STORY_DELAY := 1.0
const STORY_TEXT_SECOND := "Нет питания...\nНаверху пультовая, в коридоре\nвроде должен быть путь до неё..."
const STORY_TEXT_THIRD := "Так, электричество есть.\nПора уходить отсюда..."
const POWER_HINT_TEXT := "Нажмите \"E\" чтобы включить питание"

var layout_root: Control
var goal_label: Label
var health_title_label: Label
var stamina_title_label: Label
var health_bg: ColorRect
var health_fill: ColorRect
var stamina_bg: ColorRect
var stamina_fill: ColorRect
var health_bar_root: Control
var stamina_bar_root: Control
var weapon_title_label: Label
var ammo_label: Label
var divider_line: ColorRect
var lidar_title_label: Label
var lidar_label: Label
var reload_indicator_label: Label
var hit_overlay: ColorRect
var tutorial_root: Control
var tutorial_box: VBoxContainer
var story_root: Control
var story_label: Label
var _tutorial_active := false
var _tutorial_seen_actions := {}
var _tutorial_stage := -1
var _story_message_token := 0
var _awaiting_power_activation := false
var _power_activated := false
signal tutorial_stage_completed
var _player: CharacterBody3D = null
var _weapon: Node3D = null
var _last_reload_time_left := 0.0

func _ready() -> void:
	layer = 10
	layout_root = Control.new()
	layout_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout_root)

	tutorial_root = Control.new()
	tutorial_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	tutorial_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_root.visible = false
	tutorial_root.z_index = 20
	layout_root.add_child(tutorial_root)

	tutorial_box = VBoxContainer.new()
	tutorial_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_box.add_theme_constant_override("separation", INTRO_TUTORIAL_LINE_GAP)
	tutorial_root.add_child(tutorial_box)

	story_root = Control.new()
	story_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	story_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_root.visible = false
	story_root.z_index = 21
	layout_root.add_child(story_root)

	story_label = Label.new()
	story_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	story_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	story_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	story_label.add_theme_color_override("font_color", Color(1, 1, 1))
	story_label.add_theme_font_size_override("font_size", STORY_MESSAGE_FONT_SIZE)
	story_root.add_child(story_label)

	hit_overlay = ColorRect.new()
	hit_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit_overlay.color = Color(1, 0, 0, 0.0)
	hit_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_overlay.visible = false
	add_child(hit_overlay)

	goal_label = _make_label("GOAL: Find escape")
	health_title_label = _make_label("HEALTH")
	health_title_label.custom_minimum_size = Vector2(80, 0)
	health_bar_root = _make_bar_root()
	health_bg = _make_bar(Color(0.12, 0.12, 0.12, 0.7), health_bar_root)
	health_fill = _make_bar(Color(0.55, 0.22, 0.02, 0.95), health_bar_root)
	stamina_title_label = _make_label("STAMINA")
	stamina_title_label.custom_minimum_size = Vector2(80, 0)
	stamina_bar_root = _make_bar_root()
	stamina_bg = _make_bar(Color(0.12, 0.12, 0.12, 0.7), stamina_bar_root)
	stamina_fill = _make_bar(Color(0.18, 0.72, 0.18, 0.95), stamina_bar_root)
	weapon_title_label = _make_label("WEAPON")
	ammo_label = _make_label("AMMO: --")
	divider_line = _make_divider()
	lidar_title_label = _make_label("LIDAR")
	lidar_label = _make_label("MODE: -")
	reload_indicator_label = _make_label("Перезарядка...")
	reload_indicator_label.add_theme_font_size_override("font_size", 20)
	reload_indicator_label.visible = false

	lidar_title_label.visible = false
	lidar_label.visible = false
	divider_line.visible = false

	_update_layout()

	var viewport := get_viewport()
	if viewport != null and viewport.has_signal("size_changed"):
		viewport.connect("size_changed", Callable(self , "_update_layout"))
	set_process_unhandled_input(true)

	var player := _find_player()
	if player == null:
		player = _find_player_in_current_scene()
	if player != null:
		_player = player
		if player.has_signal("health_changed") and not player.is_connected("health_changed", Callable(self , "_on_health_changed")):
			player.connect("health_changed", Callable(self , "_on_health_changed"))
		if player.has_signal("stamina_changed") and not player.is_connected("stamina_changed", Callable(self , "_on_stamina_changed")):
			player.connect("stamina_changed", Callable(self , "_on_stamina_changed"))
		if player.has_signal("lidar_mode_changed") and not player.is_connected("lidar_mode_changed", Callable(self , "_on_lidar_mode_changed")):
			player.connect("lidar_mode_changed", Callable(self , "_on_lidar_mode_changed"))
		if player.has_signal("scan_started") and not player.is_connected("scan_started", Callable(self , "_on_scan_started")):
			player.connect("scan_started", Callable(self , "_on_scan_started"))
		_on_health_changed(player.health, player.max_health)
		_on_stamina_changed(player.stamina, player.max_stamina)
	else:
		print("[HUD] Warning: Player node not found for HUD health/stamina updates")

	_connect_weapon_ammo()
	_update_tutorial_layout()
	set_process(true)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout_root.add_child(label)
	return label


func _make_bar(color: Color, parent: Control = null) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent == null:
		layout_root.add_child(bar)
	else:
		parent.add_child(bar)
	return bar


func _make_bar_root() -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout_root.add_child(root)
	return root


func _make_divider() -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(0.55, 0.22, 0.02, 0.95)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout_root.add_child(line)
	return line


func start_intro_tutorial() -> void:
	if _tutorial_active:
		return
	_tutorial_active = true
	_tutorial_stage = -1
	_tutorial_seen_actions = {
		"up": false,
		"down": false,
		"left": false,
		"right": false,
		"fire": false,
		"reload": false,
		"scan": false,
		"run": false,
		"jump": false,
	}
	_clear_tutorial_lines()
	tutorial_root.visible = true
	story_root.visible = false
	_play_intro_tutorial()


func _play_intro_tutorial() -> void:
	await _show_tutorial_line("Проверка систем", false)
	await get_tree().create_timer(INTRO_TUTORIAL_STEP_DELAY).timeout
	await _show_tutorial_line("...", true)
	await get_tree().create_timer(INTRO_TUTORIAL_STEP_DELAY).timeout
	await _show_tutorial_line("WASD - передвижение", true)
	await _wait_for_tutorial_stage(0)
	await get_tree().create_timer(INTRO_TUTORIAL_STEP_DELAY).timeout
	await _show_tutorial_line("ЛКМ - стрельба из оружия", true)
	await _wait_for_tutorial_stage(1)
	await get_tree().create_timer(INTRO_TUTORIAL_STEP_DELAY).timeout
	await _show_tutorial_line("R - перезарядка оружия", true)
	await _wait_for_tutorial_stage(2)
	await get_tree().create_timer(INTRO_TUTORIAL_STEP_DELAY).timeout
	await _show_tutorial_line("ПКМ - сканирование", true)
	await _wait_for_tutorial_stage(3)
	await get_tree().create_timer(INTRO_TUTORIAL_STEP_DELAY).timeout
	await _show_tutorial_line("SHIFT - бег", true)
	await _wait_for_tutorial_stage(4)
	await get_tree().create_timer(INTRO_TUTORIAL_STEP_DELAY).timeout
	await _show_tutorial_line("Пробел - прыжок", true)
	await _wait_for_tutorial_stage(5)
	await get_tree().create_timer(INTRO_TUTORIAL_STEP_DELAY).timeout
	await _show_tutorial_line("...", true)
	await get_tree().create_timer(INTRO_TUTORIAL_END_DELAY).timeout
	_clear_tutorial_lines()
	tutorial_root.visible = false
	_tutorial_stage = -1
	_tutorial_active = false
	_tutorial_seen_actions = {}
	await get_tree().create_timer(POST_TUTORIAL_STORY_DELAY).timeout
	await show_center_message(INTRO_STORY_TEXT, STORY_HINT_DURATION)


func _show_tutorial_line(text: String, with_prefix: bool) -> void:
	if tutorial_box == null:
		return
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	if with_prefix:
		row.add_child(_make_tutorial_label(">", Color(0.18, 0.9, 0.4), INTRO_TUTORIAL_FONT_SIZE))

	row.add_child(_make_tutorial_label(text, Color(1, 1, 1), INTRO_TUTORIAL_FONT_SIZE))
	tutorial_box.add_child(row)
	_update_tutorial_layout()


func _make_tutorial_label(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _clear_tutorial_lines() -> void:
	if tutorial_box == null:
		return
	for child in tutorial_box.get_children():
		child.queue_free()


func _update_tutorial_layout() -> void:
	if tutorial_root == null or tutorial_box == null:
		return
	var size := get_viewport().get_visible_rect().size
	var min_size := tutorial_box.get_combined_minimum_size()
	tutorial_box.size = min_size
	tutorial_box.position = Vector2((size.x - min_size.x) * 0.5, (size.y * 0.5) - min_size.y - INTRO_TUTORIAL_TOP_OFFSET)
	_update_story_layout()


func _update_story_layout() -> void:
	if story_root == null or story_label == null:
		return
	var size := get_viewport().get_visible_rect().size
	var min_size := story_label.get_combined_minimum_size()
	if min_size == Vector2.ZERO:
		min_size = Vector2(720.0, 120.0)
	story_label.size = min_size
	story_label.position = Vector2((size.x - min_size.x) * 0.5, (size.y * 0.5) - min_size.y - STORY_MESSAGE_TOP_OFFSET)
	story_root.size = size


func show_center_message(text: String, duration: float = 0.0) -> void:
	_story_message_token += 1
	var token := _story_message_token
	if story_root == null or story_label == null:
		return
	story_label.text = text
	story_root.visible = true
	_update_story_layout()
	if duration > 0.0:
		await get_tree().create_timer(duration).timeout
		if token == _story_message_token:
			hide_center_message()


func hide_center_message() -> void:
	_story_message_token += 1
	if story_root != null:
		story_root.visible = false


func show_checkpoint_prompt(text: String) -> void:
	show_center_message(text, 0.0)


func show_checkpoint_story_hint(checkpoint_index: int) -> void:
	if checkpoint_index == 1:
		show_center_message(STORY_TEXT_SECOND, STORY_HINT_DURATION)
	elif checkpoint_index == 2:
		_power_activated = false
		_awaiting_power_activation = true
		show_center_message(POWER_HINT_TEXT, 0.0)


func show_power_activation_hint() -> void:
	_power_activated = false
	_awaiting_power_activation = true
	show_center_message(POWER_HINT_TEXT, 0.0)


func hide_power_activation_hint() -> void:
	if _power_activated:
		return
	_awaiting_power_activation = false
	hide_center_message()


func notify_power_activated() -> void:
	if not _awaiting_power_activation:
		return
	_power_activated = true
	_awaiting_power_activation = false
	hide_center_message()
	show_center_message(STORY_TEXT_THIRD, STORY_HINT_DURATION)


func _register_tutorial_action(action: String) -> void:
	if not _tutorial_active:
		return
	if not _tutorial_seen_actions.has(action):
		return
	_tutorial_seen_actions[action] = true
	_check_tutorial_progress()


func _wait_for_tutorial_stage(stage: int) -> void:
	_tutorial_stage = stage
	_check_tutorial_progress()
	if _tutorial_stage == -1:
		return
	await tutorial_stage_completed


func _check_tutorial_progress() -> void:
	if not _tutorial_active:
		return
	var completed := false
	match _tutorial_stage:
		0:
			completed = bool(_tutorial_seen_actions.get("up", false)) and bool(_tutorial_seen_actions.get("down", false)) and bool(_tutorial_seen_actions.get("left", false)) and bool(_tutorial_seen_actions.get("right", false))
		1:
			completed = bool(_tutorial_seen_actions.get("fire", false))
		2:
			completed = bool(_tutorial_seen_actions.get("reload", false))
		3:
			completed = bool(_tutorial_seen_actions.get("scan", false))
		4:
			completed = bool(_tutorial_seen_actions.get("run", false))
		5:
			completed = bool(_tutorial_seen_actions.get("jump", false))
		_:
			completed = false
	if completed:
		_tutorial_stage = -1
		tutorial_stage_completed.emit()


func set_goal(text: String) -> void:
	if goal_label == null:
		return
	goal_label.text = "GOAL: %s" % text


func _find_player() -> CharacterBody3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as CharacterBody3D

func flash_damage() -> void:
	if hit_overlay == null:
		return
	hit_overlay.visible = true
	hit_overlay.color = Color(1, 0, 0, 0.35)
	await get_tree().create_timer(0.05).timeout
	if hit_overlay != null:
		hit_overlay.color = Color(1, 0, 0, 0.0)
		hit_overlay.visible = false


func _find_player_in_current_scene() -> CharacterBody3D:
	var scene_root := get_tree().get_current_scene()
	if scene_root == null:
		return null
	var player := scene_root.get_node_or_null("Player")
	if player != null and player is CharacterBody3D:
		return player as CharacterBody3D
	return null

func _connect_weapon_ammo() -> void:
	var root := get_tree().get_current_scene()
	if root == null:
		return
	_search_weapon_node(root)


func _search_weapon_node(node: Node) -> void:
	if node == null:
		return
	if node.has_signal("ammo_changed"):
		if not node.is_connected("ammo_changed", Callable(self , "_on_ammo_changed")):
			node.connect("ammo_changed", Callable(self , "_on_ammo_changed"))
	if node.has_signal("shot_fired"):
		if not node.is_connected("shot_fired", Callable(self , "_on_weapon_fired")):
			node.connect("shot_fired", Callable(self , "_on_weapon_fired"))
		var current_value: Variant = node.get("current_ammo")
		var max_value: Variant = node.get("max_ammo")
		var current_ammo := 0 if current_value == null else int(current_value)
		var max_ammo := 0 if max_value == null else int(max_value)
		_on_ammo_changed(current_ammo, max_ammo)
		_weapon = node
		return
	for child in node.get_children():
		_search_weapon_node(child)


func _update_layout() -> void:
	if layout_root == null:
		return
	var size := get_viewport().get_visible_rect().size

	goal_label.position = Vector2(LEFT_MARGIN, TOP_MARGIN)

	var bottom_y := size.y - BOTTOM_MARGIN
	health_title_label.position = Vector2(LEFT_MARGIN, bottom_y - 42.0)
	health_bar_root.position = Vector2(LEFT_MARGIN + 82.0, bottom_y - 36.0)
	health_bar_root.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	health_bg.position = Vector2.ZERO
	health_bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	health_fill.position = Vector2.ZERO
	health_fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)

	stamina_title_label.position = Vector2(LEFT_MARGIN, bottom_y - 12.0)
	stamina_bar_root.position = Vector2(LEFT_MARGIN + 82.0, bottom_y - 6.0)
	stamina_bar_root.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	stamina_bg.position = Vector2.ZERO
	stamina_bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	stamina_fill.position = Vector2.ZERO
	stamina_fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)

	var right_x := size.x - RIGHT_MARGIN - RIGHT_BLOCK_WIDTH
	var right_top_y := bottom_y - 62.0
	weapon_title_label.position = Vector2(right_x, right_top_y)
	ammo_label.position = Vector2(right_x, right_top_y + 24.0)

	divider_line.position = Vector2(size.x - RIGHT_MARGIN - 128.0, bottom_y - 58.0)
	divider_line.size = Vector2(2.0, 88.0)

	lidar_title_label.position = Vector2(size.x - RIGHT_MARGIN - 78.0, right_top_y)
	lidar_label.position = Vector2(size.x - RIGHT_MARGIN - 78.0, right_top_y + 24.0)
	
	reload_indicator_label.position = Vector2((size.x - reload_indicator_label.get_combined_minimum_size().x) * 0.5, (size.y * 0.5) + 32.0)
	_update_story_layout()


func _on_health_changed(current: float, maxv: float) -> void:
	var pct := 0.0
	if maxv > 0.0:
		pct = clamp(current / maxv, 0.0, 1.0)
	var size := health_fill.size
	size.x = BAR_WIDTH * pct
	size.y = BAR_HEIGHT
	health_fill.size = size


func _on_stamina_changed(current: float, maxv: float) -> void:
	var pct := 0.0
	if maxv > 0.0:
		pct = clamp(current / maxv, 0.0, 1.0)
	var size := stamina_fill.size
	size.x = BAR_WIDTH * pct
	size.y = BAR_HEIGHT
	stamina_fill.size = size


func set_stamina(current: float, maxv: float) -> void:
	_on_stamina_changed(current, maxv)


func _on_ammo_changed(current: int, maxv: int) -> void:
	ammo_label.text = "AMMO: %d / %d" % [current, maxv]


func _on_lidar_mode_changed(index: int, _mode_name: String) -> void:
	lidar_label.text = "MODE: %d" % index


func _on_weapon_fired() -> void:
	_register_tutorial_action("fire")


func _on_scan_started() -> void:
	_register_tutorial_action("scan")


func _unhandled_input(event: InputEvent) -> void:
	if _awaiting_power_activation and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E:
			notify_power_activated()
			return
	if not _tutorial_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("up"):
			_register_tutorial_action("up")
		if event.is_action_pressed("down"):
			_register_tutorial_action("down")
		if event.is_action_pressed("left"):
			_register_tutorial_action("left")
		if event.is_action_pressed("right"):
			_register_tutorial_action("right")
		if event.keycode == KEY_R:
			_register_tutorial_action("reload")
		if event.keycode == KEY_SHIFT:
			_register_tutorial_action("run")
		if event.keycode == KEY_SPACE:
			_register_tutorial_action("jump")
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_register_tutorial_action("fire")
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_register_tutorial_action("scan")


func _process(delta: float) -> void:
	# Track weapon reload state
	if _weapon == null:
		return
	
	var reload_time_left: float = _weapon.get("_reload_time_left")
	if reload_time_left == null:
		return
	
	# Show reload indicator when reloading
	if reload_time_left > 0.0:
		reload_indicator_label.visible = true
	else:
		reload_indicator_label.visible = false
