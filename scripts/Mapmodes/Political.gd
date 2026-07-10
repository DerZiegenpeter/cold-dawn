extends Node3D
class_name Ownership

## Ownership / Political Map Mode
## Fügt gefüllte, halbtransparente Flächen für alle States eines Landes (z.B. DEU) hinzu.
## Vollständig getrennt von Globe.gd – modular für MapModes.
## Platziere diesen Node als Child von MapModes > Political (oder direkt unter Globe).

@export var globe_path: NodePath = ^"../Globe"
@export var target_country: String = "DEU"
@export var fill_color: Color = Color(1.0, 0.85, 0.2, 0.45)  # Schickes transparentes Gelb
@export var fill_radius_multiplier: float = 1.001
@export var render_priority: int = 4
@export var emission_energy: float = 0.5

var _globe: Globe
var _fill_nodes: Array[MeshInstance3D] = []

func _ready() -> void:
	_globe = get_node_or_null(globe_path)
	if not _globe:
		push_warning("Ownership: Globe nicht gefunden unter " + str(globe_path))
		return
	
	apply_country_highlight(target_country, fill_color)

## Hauptfunktion – kann auch später per Code aufgerufen werden (z.B. für andere Länder)
func apply_country_highlight(country_code: String, color: Color) -> void:
	clear_highlights()
	
	if not _globe:
		return
	
	# 1. nations.json laden → State-IDs für das Land holen
	var nations := _load_json_array("res://data/nations.json")
	if nations.is_empty():
		push_warning("Ownership: nations.json nicht gefunden oder leer")
		return
	
	var state_ids: Array[int] = []
	for nation in nations:
		if str(nation.get("id", "")) == country_code:
			for sid in nation.get("states", []):
				state_ids.append(int(sid))
			break
	
	if state_ids.is_empty():
		print("Ownership: Keine States für Land ", country_code, " gefunden.")
		return
	
	# 2. states.geojson laden
	var geo_data := _load_json_dict("res://data/geojson/states.geojson")
	if geo_data.is_empty() or geo_data.get("type") != "FeatureCollection":
		push_warning("Ownership: states.geojson nicht gefunden oder ungültig")
		return
	
	var features: Array = geo_data.get("features", [])
	var index := 0
	var created_count := 0
	
	for feature in features:
		index += 1
		var state_id := index
		if state_id in state_ids:
			var geom: Dictionary = feature.get("geometry", {})
			_create_filled_mesh_for_state(geom, color, state_id, country_code)
			created_count += 1
	
	print("Ownership: ", country_code, " erfolgreich hervorgehoben (", created_count, " States gefüllt)")

func clear_highlights() -> void:
	for mi in _fill_nodes:
		if is_instance_valid(mi):
			mi.queue_free()
	_fill_nodes.clear()

# ==================== HELPER ====================

func _load_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return []
	var data = json.data
	return data if data is Array else []

func _load_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var data = json.data
	return data if data is Dictionary else {}

func _lat_lon_to_vector3(lat_deg: float, lon_deg: float, radius: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	var x := radius * cos(lat) * sin(lon)
	var y := radius * sin(lat)
	var z := radius * cos(lat) * cos(lon)
	return Vector3(x, y, z)

func _coords_to_packed_vec2(coords: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for c in coords:
		if c.size() >= 2:
			pts.append(Vector2(float(c[0]), float(c[1])))  # x = lon, y = lat
	return pts

func _extract_outer_rings(geom: Dictionary) -> Array[PackedVector2Array]:
	var rings: Array[PackedVector2Array] = []
	if not geom.has("type") or not geom.has("coordinates"):
		return rings
	match geom.type:
		"Polygon":
			if geom.coordinates.size() > 0:
				rings.append(_coords_to_packed_vec2(geom.coordinates[0]))
		"MultiPolygon":
			for poly in geom.coordinates:
				if poly.size() > 0:
					rings.append(_coords_to_packed_vec2(poly[0]))
	return rings

func _create_filled_mesh_for_state(geom: Dictionary, color: Color, state_id: int, country_code: String) -> void:
	var rings := _extract_outer_rings(geom)
	if rings.is_empty():
		return

	var mesh_verts := PackedVector3Array()
	var mesh_indices := PackedInt32Array()
	var vcount := 0
	var radius := _globe.earth_radius * fill_radius_multiplier

	for ring in rings:
		if ring.size() < 3:
			continue
		var tris := Geometry2D.triangulate_polygon(ring)
		if tris.is_empty():
			continue

		for i in range(0, tris.size(), 3):
			for j in 3:
				var pidx := tris[i + j]
				var pt := ring[pidx]
				var v3 := _lat_lon_to_vector3(pt.y, pt.x, radius)
				mesh_verts.append(v3)
				mesh_indices.append(vcount)
				vcount += 1

	if mesh_verts.is_empty():
		return

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh_verts
	if not mesh_indices.is_empty():
		arrays[Mesh.ARRAY_INDEX] = mesh_indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.name = "Political_" + country_code + "_" + str(state_id)
	mi.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.95, 0.5)
	mat.emission_energy_multiplier = emission_energy
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = render_priority
	mat.cull_mode = BaseMaterial3D.CULL_BACK

	mi.material_override = mat

	# Wichtig: als Child vom Globe hinzufügen → korrekte Position auf der Kugel
	_globe.add_child(mi)
	_fill_nodes.append(mi)
