extends Node3D
class_name PoliticalMap

## Politische Weltkarte (Performance + gute Kugelkrümmung)
## - Ein Mesh pro Land
## - Alles auf exakt derselben Höhe (1.002)
## - Korrekte Unterteilung bei großen Ländern

@export var globe_path: NodePath = ^"../../Globe"
@export var fill_radius_multiplier: float = 1.002
@export var render_priority: int = 15
@export var emission_energy: float = 0.5
@export var base_subdivision: int = 1          # Basis-Unterteilung
@export var enabled: bool = false   # Deaktiviert per Default wegen langer Ladezeit (53MB states.geojson). Code bleibt erhalten!

var _globe: Globe
var _country_meshes: Dictionary = {}

func _ready() -> void:
	if not enabled:
		print("PoliticalMap deaktiviert (Performance – Code bleibt erhalten, einfach enabled=true setzen oder im Inspector aktivieren)")
		return

	print("=== PoliticalMap gestartet ===")
	_globe = get_node_or_null(globe_path)
	if not _globe:
		push_error("PoliticalMap: Globe nicht gefunden!")
		return
	
	_create_batched_political_map()

func _create_batched_political_map() -> void:
	clear_map()

	var nations := _load_json_array("res://data/nations.json")
	if nations.is_empty():
		push_warning("PoliticalMap: nations.json nicht gefunden!")
		return

	var geo_data := _load_json_dict("res://data/geojson/states.geojson")
	if geo_data.is_empty():
		return

	# state_id → country_code Mapping
	var state_to_country: Dictionary = {}
	for nation in nations:
		var code := str(nation.get("id", ""))
		if code == "": continue
		for sid in nation.get("states", []):
			state_to_country[int(sid)] = code

	# States pro Land sammeln
	var country_geometries: Dictionary = {}
	for nation in nations:
		var code := str(nation.get("id", ""))
		if code != "":
			country_geometries[code] = []

	var features: Array = geo_data.get("features", [])
	var index := 0

	for feature in features:
		index += 1
		var state_id := index
		var owner_code: String = state_to_country.get(state_id, "")
		
		if owner_code != "" and country_geometries.has(owner_code):
			var rings := _extract_outer_rings(feature.get("geometry", {}))
			country_geometries[owner_code].append_array(rings)

	# Pro Land ein Mesh erstellen
	var created := 0

	for nation in nations:
		var code := str(nation.get("id", ""))
		if code == "" or not country_geometries.has(code):
			continue
		
		var rings: Array = country_geometries[code]
		if rings.is_empty():
			continue
		
		var color := _get_color_from_nation(nation)
		var mi := _create_country_mesh(rings, color, code)
		
		if mi:
			_globe.add_child(mi)
			_country_meshes[code] = mi
			created += 1

	print("✅ PoliticalMap: ", created, " Länder als Meshes erstellt")

func _get_color_from_nation(nation: Dictionary) -> Color:
	if nation.has("color") and nation["color"] is Array and nation["color"].size() >= 3:
		var c = nation["color"]
		return Color(float(c[0]), float(c[1]), float(c[2]), 0.55)
	return Color(0.6, 0.6, 0.6, 0.4)

func _create_country_mesh(rings: Array, color: Color, country_code: String) -> MeshInstance3D:
	var mesh_verts := PackedVector3Array()
	var mesh_indices := PackedInt32Array()
	var vcount := 0
	var radius := _globe.earth_radius * fill_radius_multiplier

	for ring in rings:
		if ring.size() < 3: continue
		
		var tris := Geometry2D.triangulate_polygon(ring)
		if tris.is_empty(): continue
		
		for i in range(0, tris.size(), 3):
			var tri_verts: Array[Vector3] = []
			for j in 3:
				var pidx := tris[i + j]
				var pt: Vector2 = ring[pidx]
				var v3 := _lat_lon_to_vector3(pt.y, pt.x, radius)
				tri_verts.append(v3)
			
			# Unterteilung je nach Polygon-Größe
			var level := base_subdivision
			if ring.size() > 80:
				level = base_subdivision + 1
			
			if level > 0:
				var subdivided := _subdivide_triangle(tri_verts, level, radius)
				for sv in subdivided:
					mesh_verts.append(sv)
					mesh_indices.append(vcount)
					vcount += 1
			else:
				for v in tri_verts:
					mesh_verts.append(v)
					mesh_indices.append(vcount)
					vcount += 1

	if mesh_verts.is_empty():
		return null

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh_verts
	arrays[Mesh.ARRAY_INDEX] = mesh_indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.name = "Political_" + country_code
	mi.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = emission_energy
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = render_priority
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	mi.material_override = mat
	return mi

func _subdivide_triangle(verts: Array[Vector3], level: int, radius: float) -> Array[Vector3]:
	if level <= 0:
		return verts

	var a: Vector3 = verts[0]
	var b: Vector3 = verts[1]
	var c: Vector3 = verts[2]

	var mab := ((a + b) * 0.5).normalized() * radius
	var mbc := ((b + c) * 0.5).normalized() * radius
	var mca := ((c + a) * 0.5).normalized() * radius

	var result: Array[Vector3] = []

	# 4 neue Dreiecke
	result.append_array(_subdivide_triangle([a, mab, mca], level - 1, radius))
	result.append_array(_subdivide_triangle([b, mbc, mab], level - 1, radius))
	result.append_array(_subdivide_triangle([c, mca, mbc], level - 1, radius))
	result.append_array(_subdivide_triangle([mab, mbc, mca], level - 1, radius))

	return result

func clear_map() -> void:
	for mi in _country_meshes.values():
		if is_instance_valid(mi):
			mi.queue_free()
	_country_meshes.clear()

# ==================== HELPER ====================

func _load_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path): return []
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK: return []
	return json.data if json.data is Array else []

func _load_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK: return {}
	return json.data if json.data is Dictionary else []

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
			pts.append(Vector2(float(c[0]), float(c[1])))
	return pts

func _extract_outer_rings(geom: Dictionary) -> Array[PackedVector2Array]:
	var rings: Array[PackedVector2Array] = []
	if not geom.has("type") or not geom.has("coordinates"): return rings
	match geom.type:
		"Polygon":
			if geom.coordinates.size() > 0:
				rings.append(_coords_to_packed_vec2(geom.coordinates[0]))
		"MultiPolygon":
			for poly in geom.coordinates:
				if poly.size() > 0:
					rings.append(_coords_to_packed_vec2(geom.coordinates[0]))
	return rings
