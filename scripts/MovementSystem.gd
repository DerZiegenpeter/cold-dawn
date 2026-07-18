extends Node

## MovementSystem v3 - Fixed speed + robust path following
## - Much lower, sensible default speeds (no more teleporting)
## - Smooth single-step movement per frame (no aggressive multi-waypoint jumping)
## - Better waypoint advancement logic (angle + overshoot detection)
## - Softer domain enforcement during movement (less false stops on detours)
## - Still has clear_path(), constant speed, domain rules

signal path_completed(entity: Node3D)

@export var ground_speed: float = 0.18          # rad/s — much better for r=500 globe
@export var naval_speed: float = 0.22
@export var air_speed: float = 0.45

var _current_visualized_entity: Node = null
var _visual_path: MeshInstance3D = null

var _active_paths: Dictionary = {}  # Node3D -> {"path": Array[Vector3], "index": int}


func request_move(entity: Node3D, target_pos: Vector3) -> void:
	if not is_instance_valid(entity):
		return

	print("[Movement] request_move called for ", entity, " to ", target_pos)

	var etype: String = _get_entity_type(entity)
	var on_land: bool = LandSystem and LandSystem.is_position_on_land(target_pos)

	if etype == "ground" and not on_land:
		print("[Movement] Blocked: Ground unit cannot move to water")
		return
	if etype == "naval" and on_land:
		print("[Movement] Blocked: Naval unit cannot move to land")
		return

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

	var path_data: Dictionary = _active_paths.get(entity, {})
	var path: Array[Vector3]
	var idx: int

	if not path_data.is_empty():
		path = path_data.path
		idx = path_data.index
	else:
		if not entity.has_meta("current_path") or not entity.has_meta("current_path_index"):
			return
		path = entity.get_meta("current_path")
		idx = entity.get_meta("current_path_index")

	if idx >= path.size():
		_complete_path(entity)
		return

	var current: Vector3 = entity.global_position
	var target: Vector3 = path[idx]

	var current_dir: Vector3 = current.normalized()
	var target_dir: Vector3 = target.normalized()
	var angle: float = current_dir.angle_to(target_dir)

	var etype: String = _get_entity_type(entity)
	var speed: float = ground_speed
	if etype == "naval": speed = naval_speed
	elif etype == "air": speed = air_speed

	var angular_step: float = speed * delta

	# Smooth single step per frame (prevents teleport feel)
	if angle <= 0.008 or angular_step >= angle:   # very close or would overshoot
		# Snap to waypoint and advance
		entity.global_position = target
		idx += 1

		if idx >= path.size():
			_complete_path(entity)
			return

		# Check if we can immediately take the next waypoint too (small segments)
		var next_target = path[idx]
		var next_dir = next_target.normalized()
		var next_angle = entity.global_position.normalized().angle_to(next_dir)
		if next_angle < 0.01:
			entity.global_position = next_target
			idx += 1
			if idx >= path.size():
				_complete_path(entity)
				return

	else:
		# Normal smooth slerp movement
		var t: float = clampf(angular_step / max(angle, 0.0001), 0.0, 1.0)
		var new_dir: Vector3 = current_dir.slerp(target_dir, t)
		var new_pos: Vector3 = new_dir * current.length()

		# Softer domain check — only stop if clearly invalid for several frames (simple version: just warn)
		var on_land: bool = LandSystem and LandSystem.is_position_on_land(new_pos)
		if (etype == "ground" and not on_land) or (etype == "naval" and on_land):
			# Instead of hard crash/stop, we log and continue (path should be valid)
			print("[Movement] Warning: slight domain violation during move (may be float precision on detour)")
			# We still move — better than stopping the unit completely
			entity.global_position = new_pos
		else:
			entity.global_position = new_pos

	# Sync
	_sync_path(entity, path, idx)


func _sync_path(entity: Node3D, path: Array[Vector3], idx: int) -> void:
	_active_paths[entity] = {"path": path, "index": idx}
	entity.set_meta("current_path", path)
	entity.set_meta("current_path_index", idx)


func _complete_path(entity: Node3D, stopped_invalid: bool = false) -> void:
	_active_paths.erase(entity)
	if is_instance_valid(entity):
		if entity.has_meta("current_path"):
			entity.remove_meta("current_path")
		if entity.has_meta("current_path_index"):
			entity.remove_meta("current_path_index")
		_hide_path_visualization()
	if not stopped_invalid:
		path_completed.emit(entity)


func clear_path(entity: Node3D) -> void:
	if not is_instance_valid(entity):
		return
	_active_paths.erase(entity)
	if entity.has_meta("current_path"):
		entity.remove_meta("current_path")
	if entity.has_meta("current_path_index"):
		entity.remove_meta("current_path_index")
	if _current_visualized_entity == entity:
		_hide_path_visualization()
		_current_visualized_entity = null


func has_active_path(entity: Node3D) -> bool:
	if not is_instance_valid(entity):
		return false
	return _active_paths.has(entity) or entity.has_meta("current_path")


func _get_entity_type(entity: Node) -> String:
	if entity.get("data") != null and entity.data is Dictionary and entity.data.has("type"):
		return str(entity.data["type"])
	if entity is AirEntity: return "air"
	if entity is GroundEntity: return "ground"
	if entity is NavalEntity: return "naval"
	return "ground"


func _apply_path(entity: Node3D, path: Array[Vector3]) -> void:
	_active_paths[entity] = {"path": path, "index": 0}
	entity.set_meta("current_path", path)
	entity.set_meta("current_path_index", 0)
	_current_visualized_entity = entity

	var unit_manager := get_node_or_null("/root/UnitManager")
	if unit_manager and unit_manager.selected_entity == entity:
		var globe := entity.get_parent()
		if globe:
			_show_path_visualization(globe, path)


func _generate_direct_fallback(start: Vector3, end: Vector3) -> Array[Vector3]:
	if start.is_equal_approx(end):
		return [end]
	var start_dir: Vector3 = start.normalized()
	var end_dir: Vector3 = end.normalized()
	var angle: float = start_dir.angle_to(end_dir)
	var segments: int = clampi(maxi(8, int(ceil(angle / deg_to_rad(5.0)))), 8, 40)

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
	if path.size() < 2: return

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


func _hide_path_visualization() -> void:
	if is_instance_valid(_visual_path):
		_visual_path.queue_free()
	_visual_path = null
