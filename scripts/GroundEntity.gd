extends Node3D
class_name GroundEntity

## Ground Entity (z.B. Divisionen, Einheiten)
## - 3D Rechteck (stehend auf der Globus-Oberfläche)
## - Nur Kantenlinien sichtbar (Wireframe-Style)
## - Immer fix zur Oberfläche ausgerichtet (kein Camera-Facing)
## - Bewegt sich smooth zum Ziel (lerp)
## - Kleiner als vorher

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

	# === 3D Wireframe Rechteck (nur Kanten) ===
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()

	# Kleines stehendes Rechteck (breite x höhe)
	var width := 5.0
	var height := 8.0
	var thickness := 0.3

	# Vorderes Rechteck (4 Ecken)
	vertices.push_back(Vector3(-width/2, 0, -thickness/2))
	vertices.push_back(Vector3( width/2, 0, -thickness/2))
	vertices.push_back(Vector3( width/2, height, -thickness/2))
	vertices.push_back(Vector3(-width/2, height, -thickness/2))

	# Hinteres Rechteck (für leichten 3D-Effekt)
	vertices.push_back(Vector3(-width/2, 0,  thickness/2))
	vertices.push_back(Vector3( width/2, 0,  thickness/2))
	vertices.push_back(Vector3( width/2, height,  thickness/2))
	vertices.push_back(Vector3(-width/2, height,  thickness/2))

	# Linien-Indizes (vorne + hinten + verbindungen)
	# Vorne
	indices.append_array([0,1, 1,2, 2,3, 3,0])
	# Hinten
	indices.append_array([4,5, 5,6, 6,7, 7,4])
	# Verbindungen
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
	mat.emission_energy_multiplier = 0.8
	mat.render_priority = 30

	mesh_instance.material_override = mat

	add_child(mesh_instance)

func _process(delta: float) -> void:
	# Smooth movement zum Ziel
	if target_pos != Vector3.ZERO:
		var dist := global_position.distance_to(target_pos)
		if dist > 0.3:
			global_position = global_position.lerp(target_pos, clamp(6.0 * delta, 0.0, 1.0))
			_orient_to_surface()
		else:
			target_pos = Vector3.ZERO

func _orient_to_surface() -> void:
	if mesh_instance == null:
		return
	var normal := global_position.normalized()
	# Ausrichtung: Rechteck steht "aufrecht" auf der Globus-Oberfläche
	var basis := Basis()
	basis.y = normal
	var right := normal.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.01:
		right = normal.cross(Vector3.RIGHT).normalized()
	basis.x = right
	basis.z = normal.cross(right).normalized()
	mesh_instance.transform.basis = basis

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
	# Zielposition leicht über der Oberfläche
	var lifted := world_pos.normalized() * (world_pos.length() + 5.0)
	target_pos = lifted
	# Optional: Hier später Land-Check einbauen (nur auf States)

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
		mat.emission_energy_multiplier = 2.0
		mesh_instance.scale = Vector3(1.3, 1.3, 1.3)
	else:
		mat.albedo_color = nation_color
		mat.emission_energy_multiplier = 0.8
		mesh_instance.scale = Vector3.ONE
