extends Node

## MovementSystem
## Handles path following, constant-speed movement on sphere, and domain enforcement.
## All entity types (Ground / Naval / Air) use this system.

signal path_completed(entity: Node3D)

@export var ground_speed: float = 1.4          # rad/s
@export var naval_speed: float = 1.6
@export var air_speed: float = 2.8

var _current_visualized_entity: Node = null

var _visual_path: Node3D = null

var _visual_material: StandardMaterial3D = null

func request_move(entity: Node3D, target_pos: Vector3) -> void:
	if not is_instance_valid(entity):
		return

	print("[Movement] request_move called for ", entity, " to ", target_pos)

	# Domain pre-check (prevents obviously invalid moves)
	var etype: String = _get_entity_type(entity)
	var on_land: bool = LandSystem and LandSystem.is_position_on_land(target_pos)

	if etype == "ground" and not on_land:
		print("[Movement] Blocked: Ground unit cannot move to water")
		return
	if etype == "naval" and on_land:
		print("[Movement] Blocked: Naval unit cannot move to land")
		return

	# Generate path (PathfindingSystem handles domain-aware detours)
	var path: Array[Vector3] = []
	if has_node("/root/PathfindingSystem"):
		path = get_node("/root/PathfindingSystem").generate_path(entity, target_pos)
	else:
		path = _generate_direct_fallback(entity.global_position, target_pos)

	if path.is_empty():
		print("[Movement] No path generated")
		return

	_apply_path(entity, path)


func update_movement(entity: Node3D, delta: float) -> void:
	if not is_instance_valid(entity):
		return

	if not entity.has_meta("current_path") or not entity.has_meta("current_path_index"):
		return

	var path: Array[Vector3] = entity.get_meta("current_path")
	var idx: int = entity.get_meta("current_path_index")

	if idx >= path.size():
		entity.remove_meta("current_path")
		entity.remove_meta("current_path_index")
		_hide_path_visualization()
		path_completed.emit(entity)
		return

	var target: Vector3 = path[idx]
	var current: Vector3 = entity.global_position

	var etype: String = _get_entity_type(entity)
	var speed: float = ground_speed
	if etype == "naval":
		speed = naval_speed
	elif etype == "air":
		speed = air_speed

	# Constant angular speed movement
	var dir_to_target: Vector3 = (target - current).normalized()
	var current_dir: Vector3 = current.normalized()
	var angle: float = current_dir.angle_to(dir_to_target)

	if angle < 0.01:
		# Reached current waypoint
		idx += 1
		entity.set_meta("current_path_index", idx)
		if idx >= path.size():
			entity.remove_meta("current_path")
			entity.remove_meta("current_path_index")
			_hide_path_visualization()
			path_completed.emit(entity)
		return
		target = path[idx]
		dir_to_target = (target - current).normalized()
		angle = current_dir.angle_to(dir_to_target)

	var t: float = clampf((speed * delta) / max(angle, 0.0001), 0.0, 1.0)
	var new_dir: Vector3 = current_dir.slerp(dir_to_target, t)
	var new_pos: Vector3 = new_dir * current.length()

	# Domain enforcement every frame
	var on_land: bool = LandSystem and LandSystem.is_position_on_land(new_pos)
	if (etype == "ground" and not on_land) or (etype == "naval" and on_land):
		# Stop movement - invalid terrain
		entity.remove_meta("current_path")
		entity.remove_meta("current_path_index")
		_hide_path_visualization()
		print("[Movement] Stopped - left valid domain")
		return

	entity.global_position = new_pos

	# Update index if we passed the waypoint
	if current_dir.angle_to(dir_to_target) < 0.03:
		idx += 1
		entity.set_meta("current_path_index", idx)


func _get_entity_type(entity: Node) -> String:
	if entity.get("data") != null and entity.data is Dictionary and entity.data.has("type"):
		return str(entity.data["type"])
	if entity is AirEntity:
		return "air"
	if entity is GroundEntity:
		return "ground"
	if entity is NavalEntity:
		return "naval"
	return "ground"


func _apply_path(entity: Node3D, path: Array[Vector3]) -> void:
	entity.set_meta("current_path", path)
	entity.set_meta("current_path_index", 0)
	_current_visualized_entity = entity

	# Only visualize path for the selected unit to reduce heavy ImmediateMesh lag
	if UnitManager and UnitManager.selected_entity == entity:
		var globe = entity.get_parent()
		if globe:
			_show_path_visualization(globe, path)


func _generate_direct_fallback(start: Vector3, end: Vector3) -> Array[Vector3]:
	if start.is_equal_approx(end):
		return [end]
	var start_dir: Vector3 = start.normalized()
	var end_dir: Vector3 = end.normalized()
	var angle: float = start_dir.angle_to(end_dir)
	var segments: int = maxi(8, int(ceil(angle / deg_to_rad(5.0))))
	segments = mini(segments, 40)

	var path: Array[Vector3] = []
	var radius: float = start.length()
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var dir: Vector3 = start_dir.slerp(end_dir, t)
		path.append(dir * radius)

	path[path.size() - 1] = end_dir * radius
	return path


func _show_path_visualization(globe: Node, path: Array[Vector3]) -> void:
	_hide_path_visualization()

	if path.size() < 2:
		return

	var immediate := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.6, 1.0)
	mat.emission_energy_multiplier = 2.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for pos in path:
		immediate.surface_add_vertex(pos)
	immediate.surface_end()

	var mi := MeshInstance3D.new()
	mi.mesh = immediate
	mi.name = "PathVisual"
	globe.add_child(mi)

	_visual_path = mi
	_visual_material = mat


func _hide_path_visualization() -> void:
	if is_instance_valid(_visual_path):
		_visual_path.queue_free()
	_visual_path = null
	_visual_material = null


func has_active_path(entity: Node3D) -> bool:
	return is_instance_valid(entity) and entity.has_meta("current_path")