extends Node3D
class_name Globe

@export_group("Globe Settings")
@export var earth_radius: float = 500.0
const SURFACE_LIFT := 1.002

@export_group("Visuals")
@export var coastline_color: Color = Color(0.2, 1.0, 0.35)
@export var coastline_emission_energy: float = 2.0

@export var state_color: Color = Color(0.85, 0.85, 0.9)
@export var state_emission_energy: float = 0.6

@export var water_color: Color = Color(0.35, 0.7, 1.0)
@export var water_emission_energy: float = 1.5

@export var city_color: Color = Color(1.0, 1.0, 1.0)

func _ready() -> void:
	create_coastlines()
	create_states()
	create_cities()
	create_rivers()
	create_lakes()
	print("Cold Dawn Globe ready!")

func lat_lon_to_vector3(lat_deg: float, lon_deg: float, radius: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	var x := radius * cos(lat) * sin(lon)
	var y := radius * sin(lat)
	var z := radius * cos(lat) * cos(lon)
	return Vector3(x, y, z)

func load_geojson(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Datei nicht gefunden: " + path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var content := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(content) != OK:
		push_error("JSON Fehler: " + json.get_error_message())
		return {}
	return json.data

func create_line_layer(file_path: String, name: String, albedo: Color, emission_energy: float, render_priority: int) -> void:
	var data := load_geojson(file_path)
	if data.is_empty(): return

	var vertices := PackedVector3Array()

	if data.get("type") == "FeatureCollection":
		for feature in data.get("features", []):
			_add_geometry(feature.get("geometry", {}), vertices)
	elif data.get("type") == "GeometryCollection":
		for geom in data.get("geometries", []):
			_add_geometry(geom, vertices)
	else:
		_add_geometry(data, vertices)

	if vertices.is_empty(): return

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = albedo
	mat.emission_energy_multiplier = emission_energy
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = render_priority

	if name != "Coastlines":
		mat.albedo_color.a = 0.0

	mi.material_override = mat
	add_child(mi)

func _add_geometry(geom: Dictionary, vertices: PackedVector3Array) -> void:
	if not geom.has("type") or not geom.has("coordinates"): return
	match geom.type:
		"LineString": _add_line_string(geom.coordinates, vertices)
		"MultiLineString":
			for line in geom.coordinates: _add_line_string(line, vertices)
		"Polygon":
			if geom.coordinates.size() > 0: _add_line_string(geom.coordinates[0], vertices)
		"MultiPolygon":
			for poly in geom.coordinates:
				if poly.size() > 0: _add_line_string(poly[0], vertices)

func _add_line_string(line_coords: Array, vertices: PackedVector3Array) -> void:
	if line_coords.size() < 2: return
	for i in range(line_coords.size() - 1):
		var p1 = line_coords[i]
		var p2 = line_coords[i + 1]
		if p1.size() < 2 or p2.size() < 2: continue
		var v1 := lat_lon_to_vector3(p1[1], p1[0], earth_radius * SURFACE_LIFT)
		var v2 := lat_lon_to_vector3(p2[1], p2[0], earth_radius * SURFACE_LIFT)
		vertices.append(v1)
		vertices.append(v2)

func create_coastlines() -> void:
	create_line_layer("res://data/geojson/coastline.geojson", "Coastlines", coastline_color, coastline_emission_energy, 10)

func create_states() -> void:
	create_line_layer("res://data/geojson/states.geojson", "States", state_color, state_emission_energy, 8)

func create_rivers() -> void:
	create_line_layer("res://data/geojson/rivers.geojson", "Rivers", water_color, water_emission_energy, 4)

func create_lakes() -> void:
	create_line_layer("res://data/geojson/lakes.geojson", "Lakes", water_color, water_emission_energy, 4)

func create_cities() -> void:
	var data := load_geojson("res://data/geojson/cities.geojson")
	if data.is_empty(): return

	var positions := PackedVector3Array()
	if data.get("type") == "FeatureCollection":
		for feature in data.get("features", []):
			var geom = feature.get("geometry", {})
			if geom.get("type") == "Point":
				var c = geom.get("coordinates", [])
				if c.size() >= 2:
					var v := lat_lon_to_vector3(c[1], c[0], earth_radius * SURFACE_LIFT)
					positions.append(v)

	if positions.is_empty(): return

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)

	var mi := MeshInstance3D.new()
	mi.name = "Cities"
	mi.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = city_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.point_size = 2.0
	mat.render_priority = 6
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.0
	mi.material_override = mat

	add_child(mi)
