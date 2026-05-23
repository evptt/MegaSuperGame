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
var hit_overlay: ColorRect
var _player: CharacterBody3D = null

func _ready() -> void:
	layer = 10
	layout_root = Control.new()
	layout_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout_root)

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

	_update_layout()

	var viewport := get_viewport()
	if viewport != null and viewport.has_signal("size_changed"):
		viewport.connect("size_changed", Callable(self , "_update_layout"))

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
		_on_health_changed(player.health, player.max_health)
		_on_stamina_changed(player.stamina, player.max_stamina)
	else:
		print("[HUD] Warning: Player node not found for HUD health/stamina updates")

	_connect_weapon_ammo()


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
		var current_value: Variant = node.get("current_ammo")
		var max_value: Variant = node.get("max_ammo")
		var current_ammo := 0 if current_value == null else int(current_value)
		var max_ammo := 0 if max_value == null else int(max_value)
		_on_ammo_changed(current_ammo, max_ammo)
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
