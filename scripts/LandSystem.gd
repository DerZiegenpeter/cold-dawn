extends Node

## LandSystem
## Zentrale Komponente für alle Land-Validierungen

signal land_data_ready

var state_polygons: Dictionary = {}
var state_centers: Dictionary = {}

var _state_ids: Array = []
var _initialized: bool = false

func initialize_from_globe(globe: Node) -> void:
	if _initialized:
		return

	if globe.has_method("get_state_polygons"):
		state_polygons = globe.call("get_state_polygons") as Dictionary
	if globe.has_method("get_state_centers"):
		state_centers = globe.call("get_state_centers") as Dictionary

	_state_ids = state_centers.keys()
	_initialized = true
	land_data_ready.emit()
	print("[LandSystem] Initialisiert mit ", _state_ids.size(), " States")

func is_position_on_land(world_pos: Vector3) -> bool:
	if not _initialized or world_pos.length() < 1.0:
		return false

	var n: Vector3 = world_pos.normalized()
	var lat: float = rad_to_deg(asin(n.y))
	var lon: float = rad_to_deg(atan2(n.x, n.z))

	# Improved broadphase: check states whose centers are within safe radius (covers large countries like Russia/US)
	# Brute-force nearby polygons for correctness. Perf fine for game use.
	for id_variant in _state_ids:
		var id: int = int(id_variant)
		if not state_centers.has(id): continue
		var center: Vector3 = state_centers[id] as Vector3
		var cdist: float = center.distance_to(world_pos)
		if cdist > 650.0: continue
		if state_polygons.has(id) and _point_in_polygon(lon, lat, state_polygons[id]):
			return true

	return false

func _point_in_polygon_world(world_pos: Vector3, ring: Array) -> bool:
	var n: Vector3 = world_pos.normalized()
	var lat: float = rad_to_deg(asin(n.y))
	var lon: float = rad_to_deg(atan2(n.x, n.z))
	return _point_in_polygon(lon, lat, ring)

func _point_in_polygon(lon: float, lat: float, ring: Array) -> bool:
	var inside: bool = false
	var j: int = ring.size() - 1
	for i in range(ring.size()):
		var xi: float = float(ring[i][0])
		var yi: float = float(ring[i][1])
		var xj: float = float(ring[j][0])
		var yj: float = float(ring[j][1])
		if ((yi > lat) != (yj > lat)) and (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi if yj != yi else xi):
			inside = not inside
		j = i
	return inside
