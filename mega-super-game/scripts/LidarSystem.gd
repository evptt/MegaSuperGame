extends Node
class_name LidarSystem

signal scan_completed(global_position: Vector3)
signal point_cloud_updated(point_count: int)
signal scan_started()
signal scan_stopped()

# Autostart лидарного сканирования при загрузке сцены.
@export var autostart: bool = true

# Пауза между ударами лидарного импульса.
@export var pulse_interval: float = 0.24

# Количество рейкастов в одном импульсе. 600 по умолчанию, максимум 2000.
@export var ray_count: int = 800


# Радиус сканирования лидаром.
@export var scan_distance: float = 65.0

# Горизонтальный и вертикальный угол обзора в градусах.
@export var scan_angle_horizontal: float = 180.0
@export var scan_angle_vertical: float = 90.0

# Время жизни точек после импульса. Значение 0 означает постоянные точки до переполнения.
@export var point_lifetime: float = 0.0

# Размер метки на поверхности в мировых единицах.
@export var point_size_world: float = 0.05

# Отступ метки от поверхности, чтобы избежать з-файтинга и слипания с текстурой.
@export var point_offset: float = 0.12

# Размер ячейки для агрегации точек. Одна ячейка = одна метка.
@export var point_cell_size: float = 0.08


# Вертикальный шаг для дополнительного смещения точек по высоте.
@export var point_height_step: float = 0.0

# Максимальное количество меток, чтобы не создавать фреймдропы.
@export var max_point_cells: int = 65000

# Параметры дистанционного затемнения.
@export var fog_start: float = 0.3
@export var fog_end: float = 15.0
@export var enable_fog: bool = false

# Маска коллизий для лидарных лучей.
# По умолчанию игнорируем слой 2, чтобы лидар не попадал в капсулу движения монстра
# и использовал отдельный LidarProxy-коллайдер.
const DEFAULT_SCAN_COLLISION_MASK: int = 0x7FFFFFFF & ~(1 << 1)
@export var scan_collision_mask: int = DEFAULT_SCAN_COLLISION_MASK

# В ручном режиме сканирование запускается только по выстрелу правой кнопкой мыши.
@export var manual_scan: bool = true
@export var manual_scan_interval: float = 0.05
@export var manual_ray_count: int = 220

# Переменные для будущей системы перегрева.
@export var max_heat: float = 100.0
@export var heat_per_pulse: float = 5.0
var heat: float = 0.0

var _origin: Node3D
var _visualizer: MultiMeshInstance3D
var _point_material: Material
var _point_cells: Dictionary = {}
var _point_cell_indices: Dictionary = {}
var _index_to_cell_key: Dictionary = {}
var _point_cell_order: Array = []
var _point_cell_order_head: int = 0
var _free_instance_indices: Array = []
var _point_cloud_dirty: bool = false
var _dirty_indices: Array = []
var _base_point_mesh: Mesh
var _scan_timer: float = 0.0
var _manual_scan_timer: float = 0.0
var _is_scanning: bool = false
const VISUALIZER_AABB_EXTENTS: Vector3 = Vector3(1000.0, 1000.0, 1000.0)

func _ready() -> void:
	point_height_step = clamp(point_height_step, 0.002, 0.02)
	if _base_point_mesh != null:
		_base_point_mesh = null
	_build_point_material()
	_build_base_point_mesh()
	if _visualizer != null:
		_visualizer.multimesh.mesh = _base_point_mesh
		_set_visualizer_aabb(_visualizer)
	if autostart and _origin != null:
		start_scan()

func _process(delta: float) -> void:
	if manual_scan and _manual_scan_timer > 0.0:
		_manual_scan_timer = max(0.0, _manual_scan_timer - delta)
	if _is_scanning and not manual_scan and _origin != null:
		_scan_timer -= delta
		if _scan_timer <= 0.0:
			_scan_timer += pulse_interval
			if can_scan():
				emit_scan()
				heat = min(max_heat, heat + heat_per_pulse)

	update_point_cloud(delta)

# Запускает лидарное сканирование. Можно передать origin и visualizer сразу.
func start_scan(origin: Node3D = null, visualizer: Node3D = null) -> void:
	if origin != null:
		register_origin(origin)
	if visualizer != null:
		register_visualizer(visualizer)
	if _origin == null:
		push_warning("LidarSystem.start_scan() called without origin. Call register_origin() first.")
		return
	if _visualizer == null:
		create_visualizer(get_tree().get_current_scene(), "LidarPointCloud")
	_is_scanning = true
	_scan_timer = pulse_interval
	emit_signal("scan_started")

# Останавливает лидар.
func stop_scan() -> void:
	_is_scanning = false
	emit_signal("scan_stopped")

# Проверка, можно ли сканировать сейчас.
func can_scan() -> bool:
	return _is_scanning and heat < max_heat and _origin != null

# Регистрирует узел, от которого пускаются лучи.
func register_origin(origin: Node3D) -> void:
	_origin = origin

# Регистрирует узел визуализации точек.
func register_visualizer(mesh_instance: Node3D) -> void:
	if mesh_instance == null:
		push_warning("LidarSystem.register_visualizer() called with null mesh_instance")
		return
	if not mesh_instance is MultiMeshInstance3D:
		push_warning("LidarSystem.register_visualizer() requires MultiMeshInstance3D")
		return
	if _point_material == null:
		_build_point_material()
	if _base_point_mesh == null:
		_build_base_point_mesh()
	_visualizer = mesh_instance
	_visualizer.multimesh = MultiMesh.new()
	_visualizer.multimesh.mesh = _base_point_mesh
	_prepare_multimesh_pool(_visualizer.multimesh)
	_visualizer.material_override = _point_material
	_set_visualizer_aabb(_visualizer)

# Создаёт MeshInstance3D для облака точек и возвращает его.
func _deferred_add_visualizer(parent: Node, mesh_instance: Node3D) -> void:
	if parent is Node3D:
		(parent as Node3D).add_child(mesh_instance)
	else:
		get_tree().get_current_scene().add_child(mesh_instance)

func create_visualizer(parent: Node, name: String = "LidarPointCloud") -> MultiMeshInstance3D:
	if _point_material == null:
		_build_point_material()
	if _base_point_mesh == null:
		_build_base_point_mesh()
	var mesh_instance = MultiMeshInstance3D.new()
	mesh_instance.name = name
	if mesh_instance != null:
		mesh_instance.multimesh = MultiMesh.new()
		mesh_instance.multimesh.mesh = _base_point_mesh
		_prepare_multimesh_pool(mesh_instance.multimesh)
		mesh_instance.material_override = _point_material
		_set_visualizer_aabb(mesh_instance)
		mesh_instance.visible = true
	_deferred_add_visualizer.call_deferred(parent, mesh_instance)
	_visualizer = mesh_instance
	return mesh_instance

# Изменяет количество лучей. Ограничиваем, чтобы не перегружать CPU.
func set_ray_count(value: int) -> void:
	ray_count = clamp(value, 1, 2000)

# Устанавливает углы обзора.
func set_scan_angles(horizontal: float, vertical: float) -> void:
	scan_angle_horizontal = horizontal
	scan_angle_vertical = vertical

# Выполняет один импульс лидарного сканирования.
func emit_scan() -> void:
	if _origin == null:
		return
	if manual_scan and _manual_scan_timer > 0.0:
		return
	var origin_point = _get_scan_origin()
	var used_rays = manual_ray_count if manual_scan else ray_count
	var hits = _perform_scan(origin_point, used_rays)
	for hit in hits:
		_add_point_cells_from_hit(hit)
	if manual_scan:
		_manual_scan_timer = manual_scan_interval
	emit_signal("scan_completed", origin_point)

func _add_point_cells_from_hit(hit: Dictionary) -> void:
	var offsets = [
		Vector3.ZERO,
		Vector3.UP * point_height_step,
		Vector3.UP * point_height_step * 2.0
	]
	for offset in offsets:
		_add_point_cell({
			"position": hit.position + offset,
			"normal": hit.normal,
			"color": hit.color
		})

func _add_point_cell(hit: Dictionary) -> void:
	var cell_key = Vector3i(
		int(floor(hit.position.x / point_cell_size)),
		int(floor(hit.position.y / point_cell_size)),
		int(floor(hit.position.z / point_cell_size))
	)
	if _point_cells.has(cell_key):
		var existing = _point_cells[cell_key]
		existing.position = hit.position
		existing.normal = hit.normal
		existing.color = hit.color
		if point_lifetime > 0.0:
			existing.time_left = point_lifetime
		_point_cells[cell_key] = existing
		if _point_cell_indices.has(cell_key):
			_dirty_indices.append(_point_cell_indices[cell_key])
		_point_cloud_dirty = true
		return
	if _free_instance_indices.size() == 0:
		while _point_cell_order_head < _point_cell_order.size():
			var oldest_key = _point_cell_order[_point_cell_order_head]
			_point_cell_order_head += 1
			if _point_cells.has(oldest_key):
				var removed_index = _point_cell_indices[oldest_key]
				_point_cells.erase(oldest_key)
				_point_cell_indices.erase(oldest_key)
				_index_to_cell_key.erase(removed_index)
				_free_instance_indices.append(removed_index)
				_dirty_indices.append(removed_index)
				break
		# Compact ring buffer when head grows too large.
		if _point_cell_order_head > 4096 and _point_cell_order_head > _point_cell_order.size() / 2:
			var compact_order: Array = []
			for i in range(_point_cell_order_head, _point_cell_order.size()):
				compact_order.append(_point_cell_order[i])
			_point_cell_order = compact_order
			_point_cell_order_head = 0
	var new_index = _free_instance_indices.pop_back()
	_point_cells[cell_key] = {
		"position": hit.position,
		"normal": hit.normal,
		"time_left": point_lifetime,
		"color": hit.color
	}
	_point_cell_order.append(cell_key)
	_point_cell_indices[cell_key] = new_index
	_index_to_cell_key[new_index] = cell_key
	_dirty_indices.append(new_index)
	_point_cloud_dirty = true

func _get_scan_origin() -> Vector3:
	var origin_point = _origin.global_transform.origin
	if _origin is Camera3D:
		var camera = _origin as Camera3D
		var viewport = camera.get_viewport()
		if viewport != null:
			var size = viewport.get_visible_rect().size
			if size.x > 0 and size.y > 0:
				origin_point = camera.project_ray_origin(size * 0.5)
			else:
				origin_point -= _origin.global_transform.basis.z * 0.25
		else:
			origin_point -= _origin.global_transform.basis.z * 0.25
	return origin_point

# Создаёт массив попаданий одним импульсом.
func _perform_scan(origin_point: Vector3, count_override: int = -1) -> Array:
	if _origin is Camera3D:
		return _perform_camera_scan(origin_point, count_override)
	var results: Array = []
	var count = count_override > 0 if count_override > 0 else clamp(ray_count, 1, 2000)
	if count <= 0:
		return results
	var horizontal_rad = deg_to_rad(scan_angle_horizontal)
	var vertical_rad = deg_to_rad(scan_angle_vertical)
	var aspect_ratio = max(0.01, horizontal_rad / max(0.01, vertical_rad))
	var horizontal_steps = max(1, int(round(sqrt(count * aspect_ratio))))
	var vertical_steps = max(1, int(round(count / max(1, horizontal_steps))))
	var forward = - _origin.global_transform.basis.z
	var right = _origin.global_transform.basis.x
	var up = _origin.global_transform.basis.y
	var ray_index = 0
	for y in range(vertical_steps):
		if ray_index >= count:
			break
		var elevation = lerp(-vertical_rad * 0.5, vertical_rad * 0.5, y / max(1, vertical_steps - 1))
		for x in range(horizontal_steps):
			if ray_index >= count:
				break
			var azimuth = lerp(-horizontal_rad * 0.5, horizontal_rad * 0.5, x / max(1, horizontal_steps - 1))
			var direction = (
				right * sin(azimuth) * cos(elevation) +
				up * sin(elevation) +
				forward * cos(azimuth) * cos(elevation)
			).normalized()
			var hit = _cast_ray(origin_point, direction)
			if hit.size() > 0:
				results.append(hit)
			ray_index += 1
	return results

func _perform_camera_scan(origin_point: Vector3, count_override: int = -1) -> Array:
	var results: Array = []
	var camera = _origin as Camera3D
	var viewport = camera.get_viewport()
	if viewport == null:
		return []
	var size = viewport.get_visible_rect().size
	if size.x <= 0 or size.y <= 0:
		return []
	var count = clamp(count_override, 1, 2000) if count_override > 0 else clamp(ray_count, 1, 2000)
	var radius = min(size.x, size.y) * 0.5
	var center = size * 0.5
	var ray_index = 0
	while ray_index < count:
		# Генерируем случайную точку в круге
		var angle = randf() * 2 * PI
		var r = sqrt(randf()) * radius # sqrt для равномерного распределения
		var offset = Vector2(cos(angle) * r, sin(angle) * r)
		var screen_point = center + offset
		var direction = camera.project_ray_normal(screen_point).normalized()
		var hit = _cast_ray(origin_point, direction)
		if hit.size() > 0:
			results.append(hit)
		ray_index += 1
	return results

# Выполняет один рейкаст и возвращает точку с цветом.
func _cast_ray(origin_point: Vector3, direction: Vector3) -> Dictionary:
	var query = PhysicsRayQueryParameters3D.create(origin_point, origin_point + direction * scan_distance)
	var exclude_nodes = [_origin]
	var current = _origin
	while current != null:
		if current is PhysicsBody3D or current is CollisionObject3D:
			exclude_nodes.append(current)
			break
		current = current.get_parent()
	query.exclude = exclude_nodes
	query.collision_mask = scan_collision_mask
	var result = _origin.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return {}
	var collider: Object = result.get("collider")
	var position: Vector3 = result.get("position")
	var normal: Vector3 = result.get("normal")
	return {"position": position, "normal": normal, "color": _get_point_color(collider)}

# Определяет цвет точки по группе коллайдера и добавляет вариацию.
func _get_point_color(collider: Object) -> Color:
	var base_color = Color(0.05, 0.20, 0.22) # Very muted cyan/turquoise (25% of normal)
	
	if collider is Node:
		var node = collider as Node
		
		# Check if this collider or any parent is a monster
		var current = node
		var is_monster = false
		while current != null:
			if current.is_in_group("monsters"):
				is_monster = true
				break
			current = current.get_parent()
		
		if is_monster:
			base_color = Color(0.25, 0.05, 0.05) # Very muted red (25% of normal)
		else:
			# Check if this collider or any parent is named "floor".
			# Avoid class-based GridMap detection so GridMap2 (ceiling) is not treated as floor.
			var floor_check = node
			var is_floor = false
			while floor_check != null:
				if floor_check.is_in_group("floor"):
					is_floor = true
					break
				if floor_check.name.to_lower() == "floor":
					is_floor = true
					break
				floor_check = floor_check.get_parent()
			
			if is_floor:
				base_color = Color(0.25, 0.175, 0.025) # Very muted orange (25% of normal)
	
	# Add color variation with increased contrast
	var variation = randi() % 3
	if variation == 0:
		# Darker shade (40% of base)
		base_color = base_color * 0.4
	elif variation == 2:
		# Lighter shade (160% of base, capped at 1.0)
		base_color = Color(
			min(1.0, base_color.r * 1.6),
			min(1.0, base_color.g * 1.6),
			min(1.0, base_color.b * 1.6),
			1.0
		)
	# variation == 1 keeps normal shade
	
	return base_color

# Обновляет облако точек каждый кадр.
func update_point_cloud(delta: float) -> void:
	if _point_cells.is_empty():
		return
	var dead_cells: Array = []
	for cell_key in _point_cells.keys():
		var point = _point_cells[cell_key]
		if point_lifetime > 0.0:
			point.time_left -= delta
			if point.time_left <= 0.0:
				dead_cells.append(cell_key)
				continue
		_point_cells[cell_key] = point
	if dead_cells.size() > 0:
		for key in dead_cells:
			if not _point_cell_indices.has(key):
				_point_cells.erase(key)
				continue
			var removed_index = _point_cell_indices[key]
			_point_cells.erase(key)
			_point_cell_indices.erase(key)
			_index_to_cell_key.erase(removed_index)
			_free_instance_indices.append(removed_index)
			_dirty_indices.append(removed_index)
		_point_cloud_dirty = true
	if _visualizer == null:
		return
	if not _point_cloud_dirty and _dirty_indices.size() == 0:
		return
	if _base_point_mesh == null:
		_build_base_point_mesh()
	var multimesh = _visualizer.multimesh
	if multimesh == null or multimesh.mesh == null:
		multimesh = MultiMesh.new()
		multimesh.mesh = _base_point_mesh
		_prepare_multimesh_pool(multimesh)
		_visualizer.multimesh = multimesh
	elif multimesh.instance_count != max_point_cells:
		_prepare_multimesh_pool(multimesh)

	var camera_pos = _origin.global_transform.origin
	for index in _dirty_indices:
		if index < 0 or index >= max_point_cells:
			continue
		if _index_to_cell_key.has(index):
			var cell_key = _index_to_cell_key[index]
			var point = _point_cells[cell_key]
			var normal = point.normal
			if normal == Vector3.ZERO:
				normal = Vector3.UP
			var view_dir = (camera_pos - point.position).normalized()
			if normal.dot(view_dir) < 0.0:
				normal = - normal
			var hit_position = point.position + normal * point_offset
			var xform = Transform3D(Basis(), hit_position)
			multimesh.set_instance_transform(index, xform)
			# Apply distance-based dimming via instance color
			var distance = (point.position - camera_pos).length()
			var brightness = 1.0 if not enable_fog else clamp(1.0 - (distance - fog_start) / (fog_end - fog_start), 0.0, 1.0)
			var dimmed_color = point.color * brightness
			multimesh.set_instance_color(index, dimmed_color)
		else:
			_hide_instance(multimesh, index)
	_dirty_indices.clear()
	_point_cloud_dirty = false
	emit_signal("point_cloud_updated", _point_cells.size())

# Строит материал для точки: один материал на все точки.
func _build_point_material() -> void:
	var base_material = StandardMaterial3D.new()
	base_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	base_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	base_material.vertex_color_use_as_albedo = true
	base_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_point_material = base_material

func _set_visualizer_aabb(mesh_instance: MultiMeshInstance3D) -> void:
	var aabb = AABB(-VISUALIZER_AABB_EXTENTS, VISUALIZER_AABB_EXTENTS * 2.0)
	mesh_instance.custom_aabb = aabb

func _hide_instance(multimesh: MultiMesh, index: int) -> void:
	var hidden_transform = Transform3D(Basis(), Vector3(0, -999999.0, 0))
	multimesh.set_instance_transform(index, hidden_transform)

func _prepare_multimesh_pool(multimesh: MultiMesh) -> void:
	if multimesh.instance_count != 0:
		multimesh.instance_count = 0
	multimesh.transform_format = 1 # TRANSFORM_3D
	multimesh.use_colors = true # Enable colors for instances
	if multimesh.instance_count != max_point_cells:
		multimesh.instance_count = max_point_cells
	if _free_instance_indices.size() == 0:
		for i in range(max_point_cells):
			_free_instance_indices.append(i)
	for index in _free_instance_indices:
		_hide_instance(multimesh, index)

func _build_base_point_mesh() -> void:
	var quad = QuadMesh.new()
	quad.size = Vector2(point_size_world, point_size_world)
	_base_point_mesh = quad
