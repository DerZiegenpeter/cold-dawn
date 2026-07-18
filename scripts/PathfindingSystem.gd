extends Node

## PathfindingSystem - Lightweight & Fast version
## Much simpler and way more performant than the old heavy brute-force detour search.
## Still provides basic detours around water/land when possible.

func generate_path(entity: Node3D, target: Vector3) -> Array[Vector3]:
	if not is_instance_valid(entity):
		return []

	var etype: String = _get_entity_type(entity)
	var start: Vector3 = entity.global_position

	# Air always flies direct - fast and simple
	if etype == "air":
		return _generate_direct_path(start, target)

	# Try direct first (fast path)
	var direct: Array[Vector3] = _generate_direct_path(start, target)
	if _is_path_valid(direct, etype):
		return direct

	# Only for ground/naval: try a few cheap detours
	print("[Pathfinding] Direct path invalid for ", etype, " - trying fast detour...")
	var detour := _find_simple_detour(start, target, etype)

	if not detour.is_empty() and _is_path_valid(detour, etype):
		print("[Pathfinding] Simple detour found")
		return detour

	# Fallback: return direct anyway (MovementSystem will stop if it becomes invalid)
	print("[Pathfinding] No good detour found quickly - using direct (may stop at border)")
	return direct


func _get_entity_type(entity: Node) -> String:
	if entity.get("data") != null and entity.data is Dictionary and entity.data.has("type"):
		return str(entity.data["type"])
	if entity is AirEntity: return "air"
	if entity is GroundEntity: return "ground"
	if entity is NavalEntity: return "naval"
	return "ground"


func _generate_direct_path(start: Vector3, end: Vector3) -> Array[Vector3]:
	if start.is_equal_approx(end):
		return [end]

	var start_dir := start.normalized()
	var end_dir := end.normalized()
	var angle := start_dir.angle_to(end_dir)

	# Fewer segments = faster
	var segments := clampi(maxi(6, int(ceil(angle / deg_to_rad(8.0)))), 6, 24)

	var path: Array[Vector3] = []
	var radius := start.length()
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var dir := start_dir.slerp(end_dir, t)
		path.append(dir * radius)

	path[path.size() - 1] = end_dir * radius
	return path


func _is_path_valid(path: Array[Vector3], etype: String) -> bool:
	if path.is_empty():
		return false

	var requires_land := etype == "ground"
	var requires_water := etype == "naval"

	# Sparse sampling - much faster (every 2nd point + ends)
	var step := maxi(1, path.size() / 6)
	for i in range(0, path.size(), step):
		var pos := path[i]
		var on_land := LandSystem and LandSystem.is_position_on_land(pos)
		if requires_land and not on_land:
			return false
		if requires_water and on_land:
			return false

	# Always check the very end
	var last_on_land := LandSystem and LandSystem.is_position_on_land(path[path.size() - 1])
	if requires_land and not last_on_land:
		return false
	if requires_water and last_on_land:
		return false

	return true


# Simple, fast detour logic - only a handful of cheap attempts instead of 50+
func _find_simple_detour(start: Vector3, target: Vector3, etype: String) -> Array[Vector3]:
	var start_dir := start.normalized()
	var target_dir := target.normalized()
	var radius := start.length()

	var axis := start_dir.cross(target_dir)
	if axis.length_squared() < 0.0001:
		axis = start_dir.cross(Vector3.UP)
		if axis.length_squared() < 0.0001:
			axis = start_dir.cross(Vector3.RIGHT)
	axis = axis.normalized()

	var best_path: Array[Vector3] = []
	var best_cost := 1e30

	# Only try a few sensible offsets - much faster
	var offsets := [20.0, 35.0, 50.0, 70.0]

	for sign in [-1.0, 1.0]:
		for ang_deg in offsets:
			var offset := deg_to_rad(ang_deg) * sign

			var mid_base := start_dir.slerp(target_dir, 0.5)
			var mid_dir := mid_base.rotated(axis, offset).normalized()
			var mid_pos := mid_dir * radius

			# Quick domain check on midpoint
			var on_land := LandSystem and LandSystem.is_position_on_land(mid_pos)
			if etype == "ground" and not on_land: continue
			if etype == "naval" and on_land: continue

			var path1 := _generate_direct_path(start, mid_pos)
			var path2 := _generate_direct_path(mid_pos, target)

			if _is_path_valid(path1, etype) and _is_path_valid(path2, etype):
				var combined := path1.duplicate()
				for j in range(1, path2.size()):
					combined.append(path2[j])

				var cost := float(combined.size()) + ang_deg * 0.1
				if cost < best_cost:
					best_cost = cost
					best_path = combined

	return best_path
