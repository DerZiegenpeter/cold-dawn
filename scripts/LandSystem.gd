extends Node
class_name LandSystem

## LandSystem
## Zentrale Komponente für alle Land-Validierungen
## Optimiert mit Broad-Phase + Narrow-Phase

signal land_data_ready

var state_polygons: Dictionary = {}           # state_id -> Array[Array] (Ringe)
var state_centers: Dictionary = {}            # state_id -> Vector3 (Weltposition)

var _state_ids: Array = []

var _initialized := false

func _ready() -> void:
	# Wird später von Globe initialisiert
	pass

func initialize_from_globe(globe: Globe) -> void:
	if _initialized:
		return

	state_polygons = globe.state_polygons
	state_centers = globe.state_centers
	_state_ids = state_centers.keys()

	_initialized = true
	land_data_ready.emit()
	print("[LandSystem] Initialisiert mit ", _state_ids.size(), " States")

func is_position_on_land(world_pos: Vector3) -> bool:
	if not _initialized or world_pos.length() < 1.0:
		return false

	# === Broad Phase (sehr schnell) ===
	var min_dist := 999999.0
	var closest_state_id := -1

	for state_id in _state_ids:
		var center: Vector3 = state_centers[state_id]
		var dist := center.distance_to(world_pos)
		if dist < min_dist:
			min_dist = dist
			closest_state_id = state_id

	# Wenn weit weg von allen Centern → definitiv Wasser
	if min_dist > 120.0:
		return false

	# === Narrow Phase (teurer, aber nur bei Bedarf) ===
	if closest_state_id != -1 and state_polygons.has(closest_state_id):
		var ring: Array = state_polygons[closest_state_id]
		if _point_in_polygon_world(world_pos, ring):
			return true

	# Fallback: Prüfe alle nahen States (falls Broad-Phase nicht getroffen hat)
	for state_id in _state_ids:
		if state_centers[state_id].distance_to(world_pos) < 80.0:
			if state_polygons.has(state_id):
				if _point_in_polygon_world(world_pos, state_polygons[state_id]):
					return true

	return false

func _point_in_polygon_world(world_pos: Vector3, ring: Array) -> bool:
	var pos_norm := world_pos.normalized()
	var lat := rad_to_deg(asin(pos_norm.y))
	var lon := rad_to_deg(atan2(pos_norm.x, pos_norm.z))

	return _point_in_polygon(lon, lat, ring)

func _point_in_polygon(lon: float, lat: float, ring: Array) -> bool:
	var inside := false
	var j := ring.size() - 1
	for i in range(ring.size()):
		var xi := float(ring[i][0])
		var yi := float(ring[i][1])
		var xj := float(ring[j][0])
		var yj := float(ring[j][1])

		var intersect := ((yi > lat) != (yj > lat)) and \
			(lon < (xj - xi) * (lat - yi) / (yj - yi) + xi if yj != yi else xi)
		if intersect:
			inside = not inside
		j = i
	return inside

func get_nearest_land_position(world_pos: Vector3) -> Vector3:
	# Später erweiterbar (z.B. Projektion auf nächsten State-Rand)
	return world_pos
