extends Node

## MovementSystem
## New path-based movement (extensible)

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

	# Generate simple segmented path on the globe
	var path := generate_path_on_sphere(entity.global_position, target_world_pos, 7)

	# Store path on entity
	entity.set_meta("current_path", path)
	entity.set_meta("current_path_index", 0)

	# Set first waypoint as target
	if path.size() > 0:
		_set_target_position(entity, path[0])

	return true

func generate_path_on_sphere(start: Vector3, end: Vector3, segments: int = 6) -> Array[Vector3]:
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

func has_active_path(entity: Node) -> bool:
	if not is_instance_valid(entity):
		return false
	var path = entity.get_meta("current_path", [])
	return path is Array and path.size() > 0
