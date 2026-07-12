extends Node3D
class_name AirEntity

signal moved(new_pos: Vector3)

var data: Dictionary = {}
var nation_color: Color = Color(0.6, 0.6, 0.6)
var is_selected: bool = false

var mesh_instance: MeshInstance3D = null
var target_pos: Vector3 = Vector3.ZERO

const ENTITY_SIZE := 2.2

func _ready() -> void:
	_create_visual()

func _create_visual() -> void:
	if mesh_instance != null: return

	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Visual"

	# Changed from wireframe cube to sphere for air entities
	var sphere := SphereMesh.new()
	sphere.radius = ENTITY_SIZE * 0.65
	sphere.height = ENTITY_SIZE * 1.3
	sphere.radial_segments = 24
	sphere.rings = 12

	mesh_instance.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = nation_color
	mat.emission_enabled = true
	mat.emission = nation_color
	mat.emission_energy_multiplier = 1.4
	mat.render_priority = 35

	mesh_instance.material_override = mat

	add_child(mesh_instance)

func _process(delta: float) -> void:
	if target_pos == Vector3.ZERO:
		return

	var current_dir := global_position.normalized()
	var target_dir := target_pos.normalized()
	var angle := current_dir.angle_to(target_dir)

	var step := 0.05 * delta

	if angle <= step:
		global_position = target_pos
		target_pos = Vector3.ZERO
		_orient_to_surface()
		return

	var t := step / angle
	var new_dir := current_dir.slerp(target_dir, t)
	global_position = new_dir * global_position.length()
	_orient_to_surface()

func _orient_to_surface() -> void:
	if not mesh_instance: return
	# For sphere, simple outward orientation (no need for complex rotation like cube)
	var normal := global_position.normalized()
	if normal.length_squared() < 0.0001: return
	# Sphere is symmetric, but we can still align if future needs (e.g. selection marker)
	mesh_instance.transform.basis = Basis.looking_at(normal, Vector3.UP)

func set_data(entry: Dictionary, color: Color) -> void:
	data = entry
	nation_color = color
	if not mesh_instance: _create_visual()
	_update_visual()
	_orient_to_surface()

func set_selected(selected: bool) -> void:
	is_selected = selected
	_update_visual()

func move_to(world_pos: Vector3) -> void:
	# Air Entities dürfen über Wasser fliegen -> kein Land-Check
	var s := ENTITY_SIZE
	target_pos = world_pos.normalized() * (world_pos.length() + s * 1.8)

func update_fade(alpha: float) -> void:
	if not mesh_instance: return
	var mat := mesh_instance.material_override as StandardMaterial3D
	if mat: mat.albedo_color.a = alpha

func _update_visual() -> void:
	if not mesh_instance: return
	var mat := mesh_instance.material_override as StandardMaterial3D
	if not mat: return

	if is_selected:
		mat.albedo_color = nation_color.lightened(0.5)
		mat.emission_energy_multiplier = 2.8
	else:
		mat.albedo_color = nation_color
		mat.emission_energy_multiplier = 1.4
