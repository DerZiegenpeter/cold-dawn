extends Node

## MovementSystem
## Centralized, domain-aware smooth movement on sphere (globe) for ground/air/naval entities.
## - Ground: only on land (states)
## - Air: anywhere
## - Naval: only on water (not states)
## Modern approach: single movement update logic, adaptive path segments, correct angular speeds.

var _path_visualizer: MeshInstance3D = null

## Angular speeds in rad/s (reasonable game speeds ~ few seconds to cross globe)
const ENTITY_SPEEDS := {
	"ground": 0.35,
	"air": 0.75,
	"naval": 0.5
}

func _get_entity_type(entity: Node) -> String:
	if entity == null:
		return "ground"
	if entity.get("data") != null and entity.data is Dictionary and entity.data.has("type"):
		return str(entity.data["type"])
	if entity is AirEntity:
		return "air"
	if entity is GroundEntity:
		return "ground"
	if entity is NavalEntity:
		return "naval"
	return "ground"

func get_angular_speed(entity: Node) -> float:
	var t: String = _get_entity_type(entity)
	return float(ENTITY_SPEEDS.get(t, 0.5))

func request_move(entity: Node, target_world_pos: Vector3) -> bool:
	if not is_instance_valid(entity):
		return false

	var etype: String = _get_entity_type(entity)
	var is_naval: bool = etype == "naval"
	var is_air: bool = etype == "air"

	var globe: Node = entity.get_parent() if entity.has_method("get_globe") else null
	if not globe:
		globe = entity.get_parent()

	var valid: bool = true

	if is_naval:
		if LandSystem and LandSystem.is_position_on_land(target_world_pos):
			valid = false
	elif not is_air:
		if LandSystem and not LandSystem.is_position_on_land(target_world_pos):
			valid = false

	if not valid:
		print("[MovementSystem] Move blocked: ", etype, " cannot go to this domain")
		return false

	var path: Array[Vector3] = generate_path_on_sphere(entity.global_position, target_world_pos, 6)

	entity.set_meta("current_path", path)
	entity.set_meta("current_path_index", 0)
	entity.set_meta("velocity", Vector3.ZERO)

	if path.size() > 0:
		entity.set_meta("target_pos", path[0])

	_show_path_visualization(globe, path)

	return true

func generate_path_on_sphere(start: Vector3, end: Vector3, min_segments: int = 6) -> Array[Vector3]:
	if start.is_equal_approx(end):
		return [end]
	var angle: float = start.angle_to(end)
	# Adaptive segments based on angular distance (~every 4 degrees) so long routes have more detail, not fixed length
	var segments: int = maxi(min_segments, int(ceil(angle / deg_to_rad(4.0))))
	segments = mini(segments, 48)
	var path: Array[Vector3] = []
	var radius: float = start.length()
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var pos: Vector3 = start.slerp(end, t)
		path.append(pos.normalized() * radius)
	return path

func clear_path(entity: Node) -> void:
	if is_instance_valid(entity):
		entity.set_meta("current_path", [])
		entity.set_meta("current_path_index", 0)
		entity.set_meta("velocity", Vector3.ZERO)
		entity.set_meta("target_pos", Vector3.ZERO)
		_hide_path_visualization()

func has_active_path(entity: Node) -> bool:
	if not is_instance_valid(entity):
		return false
	var path: Array = entity.get_meta("current_path", []) as Array
	return path is Array and path.size() > 0

func update_movement(entity: Node, delta: float) -> void:
	"""Centralized path following with domain enforcement and correct speed. Replaces duplicated _follow_path in entities."""
	if not has_active_path(entity) or not is_instance_valid(entity):
		return

	var path: Array = entity.get_meta("current_path", []) as Array
	var index: int = entity.get_meta("current_path_index", 0)

	var etype: String = _get_entity_type(entity)
	var speed: float = get_angular_speed(entity)
	var requires_land: bool = etype == "ground"
	var requires_water: bool = etype == "naval"

	if path.size() == 0 or index >= path.size():
		clear_path(entity)
		return

	var waypoint: Vector3 = path[index]
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
			if entity.has_method("_orient_to_surface"):
				entity._orient_to_surface()
			if "last_valid_pos" in entity:
				entity.last_valid_pos = entity.global_position
			return
	else:
		var t: float = step / angle if angle > 0.001 else 1.0
		var new_dir: Vector3 = current_dir.slerp(target_dir, clampf(t, 0.0, 1.0))
		entity.global_position = new_dir * current_pos.length()

	# Enforce domain rules after every movement step (prevents crossing forbidden terrain mid-path)
	if LandSystem:
		var on_land: bool = LandSystem.is_position_on_land(entity.global_position)
		var valid: bool = true
		if requires_land and not on_land:
			valid = false
		elif requires_water and on_land:
			valid = false
		if not valid:
			if "last_valid_pos" in entity and entity.last_valid_pos != Vector3.ZERO:
				entity.global_position = entity.last_valid_pos
			clear_path(entity)
			return

	if entity.has_method("_orient_to_surface"):
		entity._orient_to_surface()
	if "last_valid_pos" in entity:
		entity.last_valid_pos = entity.global_position

func _show_path_visualization(globe: Node, path: Array) -> void:
	_hide_path_visualization()

	if path.size() < 2 or not globe:
		return

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "PathVisualizer"

	var immediate_mesh: ImmediateMesh = ImmediateMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(0.85, 0.9, 1.0)
	material.emission_energy_multiplier = 2.2
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 1, 1, 0.65)
	material.render_priority = 40

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)

	for pos in path:
		immediate_mesh.surface_add_vertex(pos)

	immediate_mesh.surface_end()

	mesh_instance.mesh = immediate_mesh
	globe.add_child(mesh_instance)

	_path_visualizer = mesh_instance

func _hide_path_visualization() -> void:
	if _path_visualizer and is_instance_valid(_path_visualizer):
		_path_visualizer.queue_free()
	_path_visualizer = null
