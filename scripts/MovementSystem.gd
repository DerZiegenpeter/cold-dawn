extends Node

## MovementSystem
## High-quality domain-aware pathfinding + movement for Ground / Naval / Air
## - Air: direct great-circle (fastest)
## - Ground: stays on land, finds reasonable detours if needed
## - Naval: stays on water, finds reasonable detours around continents

var _path_visualizer: MeshInstance3D = null

const ENTITY_SPEEDS := {
	"ground": 1.4,
	"air": 2.8,
	"naval": 1.6
}

func _get_entity_type(entity: Node) -> String:
	if entity == null: return "ground"
	if entity.get("data") != null and entity.data is Dictionary and entity.data.has("type"):
		return str(entity.data["type"])
	if entity is AirEntity: return "air"
	if entity is GroundEntity: return "ground"
	if entity is NavalEntity: return "naval"
	return "ground"

func get_angular_speed(entity: Node) -> float:
	var t: String = _get_entity_type(entity)
	return float(ENTITY_SPEEDS.get(t, 1.5))

func request_move(entity: Node, target_world_pos: Vector3) -> bool:
	if not is_instance_valid(entity): return false

	var etype: String = _get_entity_type(entity)
	var is_naval: bool = etype == "naval"
	var is_air: bool = etype == "air"
	var requires_land: bool = etype == "ground"
	var requires_water: bool = is_naval

	var globe: Node = entity.get_parent() if entity.has_method("get_globe") else entity.get_parent()

	# Domain check at target
	var valid: bool = true
	if is_naval:
		if LandSystem and LandSystem.is_position_on_land(target_world_pos): valid = false
	elif not is_air:
		if LandSystem and not LandSystem.is_position_on_land(target_world_pos): valid = false

	if not valid:
		print("[Movement] Ziel nicht erreichbar für ", etype)
		return false

	# Generate smart path (with detours for ground/naval if needed)
	var path: Array[Vector3] = generate_domain_aware_path(entity, target_world_pos, etype)

	entity.set_meta("current_path", path)
	entity.set_meta("current_path_index", 0)

	_show_path_visualization(globe, path)
	return true

# ==================== SMART PATH GENERATION ====================
func generate_domain_aware_path(entity: Node, target: Vector3, etype: String) -> Array[Vector3]:
	var start: Vector3 = entity.global_position
	var is_air: bool = etype == "air"

	# Air: always direct (fastest)
	if is_air:
		return _generate_direct_path(start, target)

	# Ground / Naval: try direct first
	var direct_path: Array[Vector3] = _generate_direct_path(start, target)
	if _is_path_valid(direct_path, etype):
		return direct_path

	# Blocked → try to find detour(s)
	return _find_detour_path(start, target, etype)

func _generate_direct_path(start: Vector3, end: Vector3) -> Array[Vector3]:
	if start.is_equal_approx(end): return [end]
	var start_dir: Vector3 = start.normalized()
	var end_dir: Vector3 = end.normalized()
	var angle: float = start_dir.angle_to(end_dir)
	var segments: int = maxi(8, int(ceil(angle / deg_to_rad(4.5))))
	segments = mini(segments, 48)

	var path: Array[Vector3] = []
	var radius: float = start.length()
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var dir: Vector3 = start_dir.slerp(end_dir, t)
		path.append(dir * radius)
	# Force exact end direction
	path[path.size()-1] = end_dir * radius
	return path

func _is_path_valid(path: Array[Vector3], etype: String) -> bool:
	if path.is_empty(): return false
	var requires_land: bool = etype == "ground"
	var requires_water: bool = etype == "naval"
	for pos in path:
		var on_land: bool = LandSystem and LandSystem.is_position_on_land(pos)
		if requires_land and not on_land: return false
		if requires_water and on_land: return false
	return true

func _find_detour_path(start: Vector3, target: Vector3, etype: String) -> Array[Vector3]:
	# Simple but effective detour: try rotating the target direction left/right
	var start_dir: Vector3 = start.normalized()
	var target_dir: Vector3 = target.normalized()
	var best_path: Array[Vector3] = []
	var best_score: float = 999.0

	for sign in [-1, 1]:
		for angle_offset in [15, 30, 45, 60]:
			var offset_rad: float = deg_to_rad(angle_offset) * sign
			var rotated: Vector3 = _rotate_vector_around_axis(target_dir, start_dir, offset_rad)
			var test_target: Vector3 = rotated * target.length()
			var test_path: Array[Vector3] = _generate_direct_path(start, test_target)
			if _is_path_valid(test_path, etype):
				var score: float = float(test_path.size())
				if score < best_score:
					best_score = score
					best_path = test_path

	if not best_path.is_empty():
		# Add final leg to real target if last waypoint is reasonably close in direction
		best_path.append(target)
		return best_path

	# Fallback: direct anyway (will be stopped by domain enforcement)
	return _generate_direct_path(start, target)

func _rotate_vector_around_axis(v: Vector3, axis: Vector3, angle: float) -> Vector3:
	var cos_a: float = cos(angle)
	var sin_a: float = sin(angle)
	var axis_sq: Vector3 = axis * axis
	var dot: float = v.dot(axis)
	return v * cos_a + axis.cross(v) * sin_a + axis * dot * (1.0 - cos_a)

# ==================== VISUALIZATION (high quality) ====================
func _show_path_visualization(globe: Node, path: Array) -> void:
	_hide_path_visualization()
	if path.size() < 2 or not globe: return

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "PathVisualizer"

	var immediate_mesh: ImmediateMesh = ImmediateMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(0.3, 0.6, 1.0)
	material.emission_energy_multiplier = 3.5
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.5, 0.8, 1.0, 0.75)
	material.render_priority = 45

	# Lift path slightly above surface for premium look
	var lift: float = 4.0
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	for pos in path:
		if pos is Vector3:
			var lifted: Vector3 = pos.normalized() * (pos.length() + lift)
			immediate_mesh.surface_add_vertex(lifted)
	immediate_mesh.surface_end()

	mesh_instance.mesh = immediate_mesh
	globe.add_child(mesh_instance)
	_path_visualizer = mesh_instance

func clear_path(entity: Node) -> void:
	if is_instance_valid(entity):
		entity.set_meta("current_path", [])
		entity.set_meta("current_path_index", 0)
		_hide_path_visualization()

func has_active_path(entity: Node) -> bool:
	if not is_instance_valid(entity): return false
	var raw = entity.get_meta("current_path", [])
	return raw is Array and (raw as Array).size() > 0

func update_movement(entity: Node, delta: float) -> void:
	if not has_active_path(entity) or not is_instance_valid(entity): return

	var raw_path = entity.get_meta("current_path", [])
	if not (raw_path is Array): 
		clear_path(entity)
		return
	var path: Array = raw_path as Array
	var index: int = entity.get_meta("current_path_index", 0)

	var etype: String = _get_entity_type(entity)
	var speed: float = get_angular_speed(entity)
	var requires_land: bool = etype == "ground"
	var requires_water: bool = etype == "naval"

	if path.size() == 0 or index >= path.size():
		clear_path(entity)
		return

	var waypoint_variant = path[index]
	if not (waypoint_variant is Vector3):
		clear_path(entity)
		return
	var waypoint: Vector3 = waypoint_variant

	var current_pos: Vector3 = entity.global_position
	var current_dir: Vector3 = current_pos.normalized()
	var target_dir: Vector3 = waypoint.normalized()
	var angle: float = current_dir.angle_to(target_dir)

	var step: float = speed * delta

	if angle <= step or angle < 0.001:
		entity.global_position = waypoint
		index += 1
		entity.set_meta("current_path_index", index)

		if index >= path.size():
			clear_path(entity)
			if entity.has_method("_orient_to_surface"): entity._orient_to_surface()
			if "last_valid_pos" in entity: entity.last_valid_pos = entity.global_position
			return
	else:
		var t: float = step / angle if angle > 0.001 else 1.0
		var new_dir: Vector3 = current_dir.slerp(target_dir, clampf(t, 0.0, 1.0))
		entity.global_position = new_dir * current_pos.length()

	# Domain check (gentle)
	if LandSystem:
		var on_land: bool = LandSystem.is_position_on_land(entity.global_position)
		var valid: bool = true
		if requires_land and not on_land: valid = false
		elif requires_water and on_land: valid = false
		if not valid:
			if "last_valid_pos" in entity and entity.last_valid_pos != Vector3.ZERO:
				entity.global_position = entity.last_valid_pos
			clear_path(entity)
			return

	if entity.has_method("_orient_to_surface"): entity._orient_to_surface()
	if "last_valid_pos" in entity: entity.last_valid_pos = entity.global_position

func _hide_path_visualization() -> void:
	if _path_visualizer and is_instance_valid(_path_visualizer):
		_path_visualizer.queue_free()
		_path_visualizer = null
