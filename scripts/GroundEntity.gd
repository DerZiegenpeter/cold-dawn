extends Node3D
class_name GroundEntity

## Ground Entity
## - Perfekter Würfel (Wireframe mit nur Kanten)
## - Immer gleich lange Seiten
## - Steht fix auf der Globus-Oberfläche (kein Camera-Facing)
## - Sehr einfache konstante Geschwindigkeit (kein Anfahren/Abbremsen)
## - Klein

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

	# === Perfekter Wireframe-Würfel (nur Kanten sichtbar) ===
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()

	var s := 3.5   # Seitenlänge des Würfels (klein + gleichmäßig)

	# 8 Eckpunkte eines Würfels (zentriert bei 0,0,0)
	vertices.push_back(Vector3(-s/2, -s/2, -s/2))
	vertices.push_back(Vector3( s/2, -s/2, -s/2))
	vertices.push_back(Vector3( s/2,  s/2, -s/2))
	vertices.push_back(Vector3(-s/2,  s/2, -s/2))

	vertices.push_back(Vector3(-s/2, -s/2,  s/2))
	vertices.push_back(Vector3( s/2, -s/2,  s/2))
	vertices.push_back(Vector3( s/2,  s/2,  s/2))
	vertices.push_back(Vector3(-s/2,  s/2,  s/2))

	# 12 Kanten (Linien)
	# Unten
	indices.append_array([0,1, 1,2, 2,3, 3,0])
	# Oben
	indices.append_array([4,5, 5,6, 6,7, 7,4])
	# Vertikale Kanten
	indices.append_array([0,4, 1,5, 2,6, 3,7])

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

	# Wichtig: Bei Spawn direkt korrekt ausrichten
	_orient_to_surface()

func _process(delta: float) -> void:
	if target_pos == Vector3.ZERO:
		return

	var dist := global_position.distance_to(target_pos)
	if dist < 0.2:
		global_position = target_pos
		target_pos = Vector3.ZERO
		_orient_to_surface()
		return

	# Sehr einfache konstante Geschwindigkeit (kein Lerp-Easing)
	var speed := 18.0   # Einheiten pro Sekunde (langsam aber direkt)
	var dir := (target_pos - global_position).normalized()
	global_position += dir * speed * delta
	_orient_to_surface()

func _orient_to_surface() -> void:
	if mesh_instance == null:
		return
	var normal := global_position.normalized()
	# Robuste Ausrichtung: Ein Würfel steht "auf" der Oberfläche
	mesh_instance.transform.basis = Basis.looking_at(normal, Vector3.UP)

func set_data(entry: Dictionary, color: Color) -> void:
	data = entry
	nation_color = color

	if mesh_instance == null:
		_create_visual()

	_update_visual()

func set_selected(selected: bool) -> void:
	is_selected = selected
	_update_visual()

func move_to(world_pos: Vector3) -> void:
	var lifted := world_pos.normalized() * (world_pos.length() + 4.0)
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
		mesh_instance.scale = Vector3(1.4, 1.4, 1.4)
	else:
		mat.albedo_color = nation_color
		mat.emission_energy_multiplier = 1.2
		mesh_instance.scale = Vector3.ONE
