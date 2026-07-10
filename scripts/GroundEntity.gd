extends Node3D
class_name GroundEntity

## Ground Entity
## - Perfekter Wireframe-Würfel (nur Kanten)
## - Klein + gleichmäßige Seiten
## - Steht exakt auf der Globus-Oberfläche
## - Bewegung entlang Großkreis (bleibt auf der Kugel)
## - Konstante Geschwindigkeit, kein Easing
## - Keine Skalierung bei Selektion

signal moved(new_pos: Vector3)

var data: Dictionary = {}
var nation_color: Color = Color(0.6, 0.6, 0.6)
var is_selected: bool = false

var mesh_instance: MeshInstance3D = null
var target_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	_create_visual()

func _create_visual() -> void:
	if mesh_instance != null:
		return

	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Visual"

	# === Perfekter Wireframe-Würfel ===
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()

	var s := 3.0   # Seitenlänge (klein + gleichmäßig)

	# 8 Eckpunkte eines Würfels
	vertices.push_back(Vector3(-s/2, -s/2, -s/2))
	vertices.push_back(Vector3( s/2, -s/2, -s/2))
	vertices.push_back(Vector3( s/2,  s/2, -s/2))
	vertices.push_back(Vector3(-s/2,  s/2, -s/2))

	vertices.push_back(Vector3(-s/2, -s/2,  s/2))
	vertices.push_back(Vector3( s/2, -s/2,  s/2))
	vertices.push_back(Vector3( s/2,  s/2,  s/2))
	vertices.push_back(Vector3(-s/2,  s/2,  s/2))

	# 12 Kanten
	indices.append_array([0,1, 1,2, 2,3, 3,0])   # unten
	indices.append_array([4,5, 5,6, 6,7, 7,4])   # oben
	indices.append_array([0,4, 1,5, 2,6, 3,7])   # vertikal

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

	mesh_instance.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = nation_color
	mat.emission_enabled = true
	mat.emission = nation_color
	mat.emission_energy_multiplier = 1.2
	mat.render_priority = 30

	mesh_instance.material_override = mat

	add_child(mesh_instance)

func _process(delta: float) -> void:
	if target_pos == Vector3.ZERO:
		return

	var current_dir := global_position.normalized()
	var target_dir := target_pos.normalized()
	var angle := current_dir.angle_to(target_dir)

	if angle < 0.012:
		global_position = target_pos
		target_pos = Vector3.ZERO
		_orient_to_surface()
		return

	# Bewegung entlang Großkreis (bleibt auf der Kugeloberfläche)
	var angular_speed := 0.75   # Radiant pro Sekunde (langsam + konstant)
	var t := clamp(angular_speed * delta / angle, 0.0, 1.0)
	var new_dir := current_dir.slerp(target_dir, t)

	var radius := global_position.length()
	global_position = new_dir * radius
	_orient_to_surface()

func _orient_to_surface() -> void:
	if mesh_instance == null:
		return
	if global_position.length_squared() < 1.0:
		return   # noch keine gültige Position
	var normal := global_position.normalized()
	if normal.length_squared() < 0.0001:
		return
	mesh_instance.transform.basis = Basis.looking_at(normal, Vector3.UP)

func set_data(entry: Dictionary, color: Color) -> void:
	data = entry
	nation_color = color

	if mesh_instance == null:
		_create_visual()

	_update_visual()
	_orient_to_surface()   # jetzt Position bekannt → korrekt ausrichten

func set_selected(selected: bool) -> void:
	is_selected = selected
	_update_visual()

func move_to(world_pos: Vector3) -> void:
	# Würfel soll mit Unterseite auf der Oberfläche liegen
	var s := 3.0
	var lifted := world_pos.normalized() * (world_pos.length() + s * 0.6)
	target_pos = lifted

func update_fade(alpha: float) -> void:
	if mesh_instance == null:
		return
	var mat := mesh_instance.material_override as StandardMaterial3D
	if mat == null:
		return

	var col := mat.albedo_color
	col.a = alpha
	mat.albedo_color = col

func _update_visual() -> void:
	if mesh_instance == null:
		return

	var mat := mesh_instance.material_override as StandardMaterial3D
	if mat == null:
		return

	if is_selected:
		mat.albedo_color = nation_color.lightened(0.5)
		mat.emission_energy_multiplier = 2.5
		# Keine Skalierung mehr bei Selektion
	else:
		mat.albedo_color = nation_color
		mat.emission_energy_multiplier = 1.2
