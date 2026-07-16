extends Node

## PathfindingSystem
## Zuständig für die Generierung von Pfaden (direkt + Umwege für Ground/Naval).

func generate_path(entity: Node, target: Vector3) -> Array[Vector3]:
	if not is_instance_valid(entity):
		return []

	var etype := _get_entity_type(entity)
	var start := entity.global_position

	if etype == "air":
		return _generate_direct_path(start, target)

	var direct := _generate_direct_path(start, target)
	if _is_path_valid(direct, etype):
		return direct

	return _find_detour_path(start, target, etype)

func _get_entity_type(entity: Node) -> String:
	if entity.get("data") != null and entity.data is Dictionary and entity.data.has("type"):
		return str(entity.data["type"])
	if entity is AirEntity: return "air"
	if entity is GroundEntity: return "ground"
	if entity is NavalEntity: return "naval"
	return "ground"

func _generate_direct_path(start: Vector3, end: Vector3) -> Array[Vector3]:
	if start.is_equal_approx(end): return [end]
	var start_dir := start.normalized()
	var end_dir := end.normalized()
	var angle := start_dir.angle_to(end_dir)
	var segments := maxi(8, int(ceil(angle / deg_to_rad(4.5))))
	segments = mini(segments, 48)

	var path: Array[Vector3] = []
	var radius := start.length()
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var dir := start_dir.slerp(end_dir, t)
		path.append(dir * radius)
	path[path.size() - 1] = end_dir * radius
	return path

func _is_path_valid(path: Array[Vector3], etype: String) -> bool:
	if path.is_empty(): return false
	var requires_land := etype == "ground"
	var requires_water := etype == "naval"
	for pos in path:
		var on_land := LandSystem and LandSystem.is_position_on_land(pos)
		if requires_land and not on_land: return false
		if requires_water and on_land: return false
	return true

func _find_detour_path(start: Vector3, target: Vector3, etype: String) -> Array[Vector3]:
	var start_dir := start.normalized()
	var target_dir := target.normalized()
	var best_path: Array[Vector3] = []
	var best_score := 999.0

	for sign in [-1, 1]:
		for angle_offset in [15, 30, 45, 60]:
			var offset_rad := deg_to_rad(angle_offset) * sign
			var rotated := _rotate_vector_around_axis(target_dir, start_dir, offset_rad)
			var test_target := rotated * target.length()
			var test_path := _generate_direct_path(start, test_target)
			if _is_path_valid(test_path, etype):
				var score := float(test_path.size())
				if score < best_score:
					best_score = score
					best_path = test_path

	if not best_path.is_empty():
		best_path.append(target)
		return best_path

	return _generate_direct_path(start, target)

func _rotate_vector_around_axis(v: Vector3, axis: Vector3, angle: float) -> Vector3:
	var cos_a := cos(angle)
	var sin_a := sin(angle)
	return v * cos_a + axis.cross(v) * sin_a + axis * v.dot(axis) * (1.0 - cos_a)
