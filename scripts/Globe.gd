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
@export var city_color: Color = Color(1.0, 1.0, 1.0)

var state_data: Dictionary = {}
var state_polygons: Dictionary = {}
var state_centers: Dictionary = {}

func _ready() -> void:
	load_state_data()
	create_coastlines()
	create_states()
	create_cities()

	LandSystem.initialize_from_globe(self)
	UnitManager.initialize(self)
	UnitManager.load_and_spawn_oob()

	print("Cold Dawn Globe ready!")

func get_state_polygons() -> Dictionary:
	return state_polygons

func get_state_centers() -> Dictionary:
	return state_centers

# Robust sphere raycast – always returns the closest front-side hit
func _raycast_to_globe_sphere(from: Vector3, dir: Vector3) -> Vector3:
	var radius: float = earth_radius * 1.002
	var center: Vector3 = global_position

	var oc: Vector3 = from - center
	var a: float = dir.dot(dir)
	if a < 0.000001:
		return Vector3.ZERO
	var b: float = 2.0 * oc.dot(dir)
	var c: float = oc.dot(oc) - radius * radius

	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return Vector3.ZERO

	var sqrt_disc: float = sqrt(discriminant)
	var inv_2a: float = 1.0 / (2.0 * a)
	var t0: float = (-b - sqrt_disc) * inv_2a
	var t1: float = (-b + sqrt_disc) * inv_2a

	# When camera is outside the sphere the smaller positive t is always the front hit
	var t: float = -1.0
	if t0 > 0.001:
		t = t0
	if t1 > 0.001 and (t < 0.0 or t1 < t):
		t = t1

	if t < 0.0:
		return Vector3.ZERO

	# Reject absurdly far hits (safety against numerical issues)
	if t > 8000.0:
		return Vector3.ZERO

	var hit: Vector3 = center + dir * t

	# Extra front-side guard (prevents rare back-face hits when camera is very close)
	var to_cam: Vector3 = (from - center).normalized()
	var to_hit: Vector3 = (hit - center).normalized()
	if to_hit.dot(to_cam) < -0.05:
		return Vector3.ZERO

	return hit

func show_click_ring(world_pos: Vector3) -> void:
	var ring := MeshInstance3D.new()
	ring.name = "ClickRing"

	var immediate_mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(0.4, 0.7, 1.0)
	material.emission_energy_multiplier = 4.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.6, 0.85, 1.0, 0.85)
	material.render_priority = 50

	var normal: Vector3 = world_pos.normalized()
	var radius: float = 12.0
	var segments: int = 64
	var lift: float = 3.5

	var arbitrary: Vector3 = Vector3(0, 1, 0)
	if abs(normal.dot(arbitrary)) > 0.99:
		arbitrary = Vector3(1, 0, 0)
	var tangent1: Vector3 = normal.cross(arbitrary).normalized()
	var tangent2: Vector3 = normal.cross(tangent1).normalized()

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	for i in range(segments + 1):
		var angle: float = float(i) / float(segments) * TAU
		var offset: Vector3 = tangent1 * cos(angle) * radius + tangent2 * sin(angle) * radius
		var pos: Vector3 = (normal * (world_pos.length() + lift)) + offset
		immediate_mesh.surface_add_vertex(pos)
	immediate_mesh.surface_end()

	ring.mesh = immediate_mesh
	add_child(ring)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(2.5, 2.5, 2.5), 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(material, "emission_energy_multiplier", 0.5, 0.85)
	tween.tween_callback(ring.queue_free).set_delay(1.0)

func load_state_data() -> void:
	var path := "res://data/states.json"
	if not FileAccess.file_exists(path): return
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		for state in json.data:
			state_data[int(state["id"])] = state
	file.close()

func create_states() -> void:
	var data := load_geojson("res://data/geojson/states.geojson")
	if data.is_empty() or data.get("type") != "FeatureCollection": return

	var created := 0
	var index := 0

	for feature in data.get("features", []):
		index += 1
		var state_id := index

	var vertices := PackedVector3Array()
		_add_geometry(feature.get("geometry", {}), vertices)

	if feature.get("geometry", {}).get("type") in ["Polygon", "MultiPolygon"]:
		var coords = feature["geometry"]["coordinates"]
		var outer := []
		if feature["geometry"]["type"] == "Polygon" and coords.size() > 0:
			outer = coords[0]
		elif feature["geometry"]["type"] == "MultiPolygon" and coords.size() > 0:
			outer = coords[0][0] if coords[0].size() > 0 else []
		if outer.size() > 0:
			state_polygons[state_id] = outer

		if vertices.is_empty(): continue

		var center := Vector3.ZERO
		for v in vertices:
			center += v
		if vertices.size() > 0:
			center /= float(vertices.size())
			center = center.normalized() * (earth_radius * SURFACE_LIFT)

		state_centers[state_id] = center

		var local := PackedVector3Array()
		local.resize(vertices.size())
		for i in range(vertices.size()):
			local[i] = vertices[i] - center

		var mesh := ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = local
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

		var mi := MeshInstance3D.new()
		mi.name = "State_" + str(state_id)
		mi.mesh = mesh
		mi.position = center

		var mat := StandardMaterial3D.new()
		mat.albedo_color = state_color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = state_color
		mat.emission_energy_multiplier = state_emission_energy
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.render_priority = 8
		mat.albedo_color.a = 0.0

		mi.material_override = mat
		add_child(mi)
		created += 1

	print("States erstellt: ", created)

func create_coastlines() -> void:
	create_line_layer("res://data/geojson/coastline.geojson", "Coastlines", coastline_color, coastline_emission_energy, 10)

func create_cities() -> void:
	var data := load_geojson("res://data/geojson/cities.geojson")
	if data.is_empty(): return

	var positions := PackedVector3Array()
	for feature in data.get("features", []):
		var geom = feature.get("geometry", {})
		if geom.get("type") == "Point":
			var c = geom.get("coordinates", [])
			if c.size() >= 2:
				positions.append(lat_lon_to_vector3(c[1], c[0], earth_radius * SURFACE_LIFT))

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

func create_line_layer(file_path: String, name: String, albedo: Color, emission_energy: float, render_priority: int) -> void:
	var data := load_geojson(file_path)
	if data.is_empty(): return

	var vertices := PackedVector3Array()
	if data.get("type") == "FeatureCollection":
		for feature in data.get("features", []):
			_add_geometry(feature.get("geometry", {}), vertices)

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

func lat_lon_to_vector3(lat_deg: float, lon_deg: float, radius: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	var x := radius * cos(lat) * sin(lon)
	var y := radius * sin(lat)
	var z := radius * cos(lat) * cos(lon)
	return Vector3(x, y, z)

func load_geojson(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var content := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(content) != OK: return {}
	return json.data

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
		vertices.append(lat_lon_to_vector3(p1[1], p1[0], earth_radius * SURFACE_LIFT))
		vertices.append(lat_lon_to_vector3(p2[1], p2[0], earth_radius * SURFACE_LIFT))