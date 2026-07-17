extends Node

## PathfindingSystem
## Generates great-circle paths on the sphere that respect domain constraints
## (ground = land only, naval = water only, air = anywhere).
## When the direct arc crosses invalid terrain, it searches for detour mid-points
## so units go around oceans / continents instead of flying through them.

func generate_path(entity: Node3D, target: Vector3) -> Array[Vector3]:
	if not is_instance_valid(entity):
		return []

	var etype: String = _get_entity_type(entity)
	var start: Vector3 = entity.global_position

	# Air always flies direct
	if etype == "air":
		return _generate_direct_path(start, target)

	# Try direct first
	var direct: Array[Vector3] = _generate_direct_path(start, target)
	if _is_path_valid(direct, etype):
		return direct

	# Search for a detour that stays on the correct domain
	var detour: Array[Vector3] = _find_detour_path(start, target, etype)
	if not detour.is_empty() and _is_path_valid(detour, etype):
		return detour

	# Last resort: still return a direct path so the unit at least tries
	# (MovementSystem will stop it if it leaves the domain)
	return direct


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


func _generate_direct_path(start: Vector3, end: Vector3) -> Array[Vector3]:
	if start.is_equal_approx(end):
		return [end]

	var start_dir: Vector3 = start.normalized()
	var end_dir: Vector3 = end.normalized()
	var angle: float = start_dir.angle_to(end_dir)

	# More segments for longer arcs → smoother movement & better land checks
	var segments: int = maxi(12, int(ceil(angle / deg_to_rad(3.5))))
	segments = mini(segments, 64)

	var path: Array[Vector3] = []
	var radius: float = start.length()
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var dir: Vector3 = start_dir.slerp(end_dir, t)
		path.append(dir * radius)

	# Guarantee exact end point (floating-point safety)
	path[path.size() - 1] = end_dir * radius
	return path


func _is_path_valid(path: Array[Vector3], etype: String) -> bool:
	if path.is_empty():
		return false

	var requires_land: bool = etype == "ground"
	var requires_water: bool = etype == "naval"

	# Sample every point (and a couple of mid-segments for long arcs)
	for i in range(path.size()):
		var pos: Vector3 = path[i]
		var on_land: bool = LandSystem and LandSystem.is_position_on_land(pos)
		if requires_land and not on_land:
			return false
		if requires_water and on_land:
			return false

	return true


func _find_detour_path(start: Vector3, target: Vector3, etype: String) -> Array[Vector3]:
	var start_dir: Vector3 = start.normalized()
	var target_dir: Vector3 = target.normalized()
	var radius: float = start.length()

	# Axis of the great-circle plane
	var axis: Vector3 = start_dir.cross(target_dir)
	if axis.length_squared() < 0.0001:
		# Nearly antipodal – pick an arbitrary perpendicular axis
		axis = start_dir.cross(Vector3.UP)
		if axis.length_squared() < 0.0001:
			axis = start_dir.cross(Vector3.RIGHT)
	axis = axis.normalized()

	var best_path: Array[Vector3] = []
	var best_cost: float = 1e30

	# Try a range of offset angles for a single mid-point
	# Larger offsets allow going around big bodies of water / landmasses
	var offsets: Array[float] = [15.0, 25.0, 35.0, 45.0, 60.0, 75.0, 90.0, 110.0, 130.0]

	for sign in [-1.0, 1.0]:
		for ang_deg in offsets:
			var offset: float = deg_to_rad(ang_deg) * sign

			# Mid-point of the original arc, then rotated out of the plane
			var mid_base: Vector3 = start_dir.slerp(target_dir, 0.5)
			var mid_dir: Vector3 = mid_base.rotated(axis, offset).normalized()
			var mid_pos: Vector3 = mid_dir * radius

			# Also try a second family of mid-points closer to start or target
			# (helps when the obstacle is near one end)
			var candidates: Array[Vector3] = [
				mid_pos,
				start_dir.slerp(mid_dir, 0.6).normalized() * radius,
				mid_dir.slerp(target_dir, 0.6).normalized() * radius
			]

			for cand in candidates:
				# Quick domain check on the candidate itself
				var on_land: bool = LandSystem and LandSystem.is_position_on_land(cand)
				if etype == "ground" and not on_land:
					continue
				if etype == "naval" and on_land:
					continue

				var path1: Array[Vector3] = _generate_direct_path(start, cand)
				var path2: Array[Vector3] = _generate_direct_path(cand, target)

				if _is_path_valid(path1, etype) and _is_path_valid(path2, etype):
					var combined: Array[Vector3] = []
					combined.append_array(path1)
					# Skip the duplicate mid-point
					for i in range(1, path2.size()):
						combined.append(path2[i])

					var cost: float = float(combined.size()) + ang_deg * 0.15  # prefer smaller detours
					if cost < best_cost:
						best_cost = cost
						best_path = combined

	# If a single mid-point failed, try a two-waypoint detour (more expensive but better coverage)
	if best_path.is_empty():
		best_path = _find_two_waypoint_detour(start, target, etype, axis, radius)

	return best_path


func _find_two_waypoint_detour(start: Vector3, target: Vector3, etype: String, axis: Vector3, radius: float) -> Array[Vector3]:
	var start_dir: Vector3 = start.normalized()
	var target_dir: Vector3 = target.normalized()
	var best: Array[Vector3] = []
	var best_cost: float = 1e30

	var offsets: Array[float] = [40.0, 70.0, 100.0]

	for sign1 in [-1.0, 1.0]:
		for ang1 in offsets:
			var mid1_dir: Vector3 = start_dir.slerp(target_dir, 0.33).rotated(axis, deg_to_rad(ang1) * sign1).normalized()
			var mid1: Vector3 = mid1_dir * radius

			var on_land1: bool = LandSystem and LandSystem.is_position_on_land(mid1)
			if etype == "ground" and not on_land1: continue
			if etype == "naval" and on_land1: continue

			for sign2 in [-1.0, 1.0]:
				for ang2 in offsets:
					var mid2_dir: Vector3 = start_dir.slerp(target_dir, 0.66).rotated(axis, deg_to_rad(ang2) * sign2).normalized()
					var mid2: Vector3 = mid2_dir * radius

					var on_land2: bool = LandSystem and LandSystem.is_position_on_land(mid2)
					if etype == "ground" and not on_land2: continue
					if etype == "naval" and on_land2: continue

					var p1: Array[Vector3] = _generate_direct_path(start, mid1)
					var p2: Array[Vector3] = _generate_direct_path(mid1, mid2)
					var p3: Array[Vector3] = _generate_direct_path(mid2, target)

					if _is_path_valid(p1, etype) and _is_path_valid(p2, etype) and _is_path_valid(p3, etype):
						var combined: Array[Vector3] = []
						combined.append_array(p1)
						for i in range(1, p2.size()):
							combined.append(p2[i])
						for i in range(1, p3.size()):
							combined.append(p3[i])

						var cost: float = float(combined.size())
						if cost < best_cost:
							best_cost = cost
							best = combined

	return best


func _rotate_vector_around_axis(v: Vector3, axis: Vector3, angle: float) -> Vector3:
	var cos_a: float = cos(angle)
	var sin_a: float = sin(angle)
	return v * cos_a + axis.cross(v) * sin_a + axis * v.dot(axis) * (1.0 - cos_a)
