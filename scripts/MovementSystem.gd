extends Node

## MovementSystem
## Führt Bewegung entlang eines bereits generierten Pfades aus.
## Path-Generierung liegt jetzt im PathfindingSystem.

var _path_visualizer: MeshInstance3D = null

const ENTITY_SPEEDS := {
	"ground": 1.4,
	"air": 2.8,
	"naval": 1.6
}

func get_angular_speed(entity: Node) -> float:
	var etype: String = _get_entity_type(entity)
	return float(ENTITY_SPEEDS.get(etype, 1.5))

func _get_entity_type(entity: Node) -> String:
	if entity.get("data") != null and entity.data is Dictionary and entity.data.has("type"):
		return str(entity.data["type"])
	if entity is AirEntity: return "air"
	if entity is GroundEntity: return "ground"
	if entity is NavalEntity: return "naval"
	return "ground"

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

	var entity_3d: Node3D = entity as Node3D
	if entity_3d == null:
		return

	var raw_path = entity.get_meta("current_path", [])
	if not (raw_path is Array):
		clear_path(entity)
		return

	var path: Array = raw_path as Array
	var index: int = entity.get_meta("current_path_index", 0)

	var speed: float = get_angular_speed(entity)
	var etype: String = _get_entity_type(entity)
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

	var current_pos: Vector3 = entity_3d.global_position
	var current_dir: Vector3 = current_pos.normalized()
	var target_dir: Vector3 = waypoint.normalized()
	var angle: float = current_dir.angle_to(target_dir)

	var step: float = speed * delta

	if angle <= step or angle < 0.001:
		entity_3d.global_position = waypoint
		index += 1
		entity.set_meta("current_path_index", index)

		if index >= path.size():
			clear_path(entity)
			if entity.has_method("_orient_to_surface"): entity._orient_to_surface()
			if "last_valid_pos" in entity: entity.last_valid_pos = entity_3d.global_position
			return
	else:
		var t: float = step / angle if angle > 0.001 else 1.0
		var new_dir: Vector3 = current_dir.slerp(target_dir, clampf(t, 0.0, 1.0))
		entity_3d.global_position = new_dir * current_pos.length()

	# Domain enforcement
	if LandSystem:
		var on_land: bool = LandSystem.is_position_on_land(entity_3d.global_position)
		var valid: bool = true
		if requires_land and not on_land: valid = false
		elif requires_water and on_land: valid = false
		if not valid:
			if "last_valid_pos" in entity and entity.last_valid_pos != Vector3.ZERO:
				entity_3d.global_position = entity.last_valid_pos
			clear_path(entity)
			return

	if entity.has_method("_orient_to_surface"): entity._orient_to_surface()
	if "last_valid_pos" in entity: entity.last_valid_pos = entity_3d.global_position

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

func _hide_path_visualization() -> void:
	if _path_visualizer and is_instance_valid(_path_visualizer):
		_path_visualizer.queue_free()
		_path_visualizer = null
