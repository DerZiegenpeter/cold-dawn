extends Node

## LandSystem
## Zentrale Komponente für alle Land-Validierungen

signal land_data_ready

var state_polygons: Dictionary = {}
var state_centers: Dictionary = {}

var _state_ids: Array = []
var _initialized := false

func initialize_from_globe(globe: Node) -> void:
	if _initialized:
		return

	if globe.has_method("get_state_polygons"):
		state_polygons = globe.call("get_state_polygons")
	if globe.has_method("get_state_centers"):
		state_centers = globe.call("get_state_centers")

	_state_ids = state_centers.keys()
	_initialized = true
	land_data_ready.emit()
	print("[LandSystem] Initialisiert mit ", _state_ids.size(), " States")

func is_position_on_land(world_pos: Vector3) -> bool:
	if not _initialized or world_pos.length() < 1.0:
		return false

	# Broad Phase
	var min_dist := 999999.0
	var closest_id := -1

	for id in _state_ids:
		var dist := state_centers[id].distance_to(world_pos)
		if dist < min_dist:
			min_dist = dist
			closest_id = id

	if min_dist > 120.0:
		return false

	# Narrow Phase
	if closest_id != -1 and state_polygons.has(closest_id):
		if _point_in_polygon_world(world_pos, state_polygons[closest_id]):
			return true

	for id in _state_ids:
		if state_centers[id].distance_to(world_pos) < 80.0:
			if state_polygons.has(id) and _point_in_polygon_world(world_pos, state_polygons[id]):
				return true

	return false

func _point_in_polygon_world(world_pos: Vector3, ring: Array) -> bool:
	var n := world_pos.normalized()
	var lat := rad_to_deg(asin(n.y))
	var lon := rad_to_deg(atan2(n.x, n.z))
	return _point_in_polygon(lon, lat, ring)

func _point_in_polygon(lon: float, lat: float, ring: Array) -> bool:
	var inside := false
	var j := ring.size() - 1
	for i in range(ring.size()):
		var xi := float(ring[i][0])
		var yi := float(ring[i][1])
		var xj := float(ring[j][0])
		var yj := float(ring[j][1])
		if ((yi > lat) != (yj > lat)) and (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi if yj != yi else xi):
			inside = not inside
		j = i
	return inside
