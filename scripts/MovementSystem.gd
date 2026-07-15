extends Node

## MovementSystem
## Path-based movement with visualization

var _path_visualizer: MeshInstance3D = null

func request_move(entity: Node, target_world_pos: Vector3) -> bool:
	if not is_instance_valid(entity):
		return false

	var is_naval := false
	if entity.get("data") != null and entity.data is Dictionary:
		is_naval = entity.data.get("type", "") == "naval"

	var globe := entity.get_parent() if entity.has_method("get_globe") else null
	if not globe:
		globe = entity.get_parent()

	var valid := true

	if is_naval:
		if LandSystem and LandSystem.is_position_on_land(target_world_pos):
			valid = false
			print("[MovementSystem] Naval kann nicht auf Land!")
	else:
		if LandSystem and not LandSystem.is_position_on_land(target_world_pos):
			valid = false
			print("[MovementSystem] Nur auf Land!")

	if not valid:
		return false

	var path := generate_path_on_sphere(entity.global_position, target_world_pos, 8)

	entity.set_meta("current_path", path)
	entity.set_meta("current_path_index", 0)

	if path.size() > 0:
		_set_target_position(entity, path[0])

	_show_path_visualization(globe, path)

	return true

func generate_path_on_sphere(start: Vector3, end: Vector3, segments: int = 8) -> Array[Vector3]:
	var path: Array[Vector3] = []
	var radius := start.length()

	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var pos := start.slerp(end, t)
		path.append(pos.normalized() * radius)

	return path

func _set_target_position(entity: Node, world_pos: Vector3) -> void:
	if entity.has_method("_set_target_position"):
		entity._set_target_position(world_pos)

func clear_path(entity: Node) -> void:
	if is_instance_valid(entity):
		entity.set_meta("current_path", [])
		entity.set_meta("current_path_index", 0)
		_hide_path_visualization()

func has_active_path(entity: Node) -> bool:
	if not is_instance_valid(entity):
		return false
	var path = entity.get_meta("current_path", [])
	return path is Array and path.size() > 0

func _show_path_visualization(globe: Node, path: Array) -> void:
	_hide_path_visualization()

	if path.size() < 2 or not globe:
		return

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "PathVisualizer"

	var immediate_mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(0.9, 0.95, 1.0)
	material.emission_energy_multiplier = 2.5
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 1, 1, 0.7)
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
