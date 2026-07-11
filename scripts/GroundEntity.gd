extends Node3D
class_name GroundEntity

## Ground Entity
## - Wireframe Würfel
## - Steht immer exakt mit flacher Seite auf der Oberfläche (Raute-Optik durch 45°)
## - Konstante Geschwindigkeit, kein Abbremsen/Anfahren, kein End-Wackeln
## - Ground nur auf Land (wird beim Befehl geprüft)

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

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()

	var s := 2.2

	vertices.push_back(Vector3(-s/2, -s/2, -s/2))
	vertices.push_back(Vector3( s/2, -s/2, -s/2))
	vertices.push_back(Vector3( s/2,  s/2, -s/2))
	vertices.push_back(Vector3(-s/2,  s/2, -s/2))

	vertices.push_back(Vector3(-s/2, -s/2,  s/2))
	vertices.push_back(Vector3( s/2, -s/2,  s/2))
	vertices.push_back(Vector3( s/2,  s/2,  s/2))
	vertices.push_back(Vector3(-s/2,  s/2,  s/2))

	indices.append_array([0,1, 1,2, 2,3, 3,0])
	indices.append_array([4,5, 5,6, 6,7, 7,4])
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

func _process(delta: float) -> void:
	if target_pos == Vector3.ZERO:
		return

	var current_dir: Vector3 = global_position.normalized()
	var target_dir: Vector3 = target_pos.normalized()
	var angle: float = current_dir.angle_to(target_dir)

	# Konstante Winkelgeschwindigkeit - kein Abbremsen, kein End-Sprint/Wackeln
	var angular_speed: float = 0.04  # bei Bedarf anpassen (0.03 = sehr langsam, 0.06 = flotter)
	var step: float = angular_speed * delta

	if angle <= step:
		global_position = target_pos
		target_pos = Vector3.ZERO
		_orient_to_surface()
		return

	var t: float = step / angle
	var new_dir: Vector3 = current_dir.slerp(target_dir, t)

	var radius: float = global_position.length()
	global_position = new_dir * radius
	_orient_to_surface()   # immer perfekt zur Oberfläche ausrichten (auch während der Bewegung auf der Kugel)

func _orient_to_surface() -> void:
	if mesh_instance == null:
		return
	if global_position.length_squared() < 1.0:
		return
	var normal: Vector3 = global_position.normalized()
	if normal.length_squared() < 0.0001:
		return

	# Flache Seite zum Globus-Mittelpunkt (ganze Seite "unten")
	mesh_instance.transform.basis = Basis.looking_at(normal, Vector3.UP)

	# 45° Roll für schöne Raute-Optik (Rechteck geneigt)
	mesh_instance.rotate_object_local(Vector3.FORWARD, deg_to_rad(45))

func set_data(entry: Dictionary, color: Color) -> void:
	data = entry
	nation_color = color

	if mesh_instance == null:
		_create_visual()

	_update_visual()
	_orient_to_surface()

func set_selected(selected: bool) -> void:
	is_selected = selected
	_update_visual()

func move_to(world_pos: Vector3) -> void:
	var s: float = 2.2
	# Exakt mit unterer Seite auf der Oberfläche
	var lifted: Vector3 = world_pos.normalized() * (world_pos.length() + s * 0.5)
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
	else:
		mat.albedo_color = nation_color
		mat.emission_energy_multiplier = 1.2
