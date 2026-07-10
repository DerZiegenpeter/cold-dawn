extends Node3D
class_name GroundEntity

## Ground Entity (z.B. Divisionen, Einheiten)
## - Rechteckiges Billboard-Quad auf der Globus-Oberfläche
## - Wird per Left-Click ausgewählt (über UnitManager)
## - Wird per Right-Click auf den Globus bewegt

signal moved(new_pos: Vector3)

var data: Dictionary = {}
var nation_color: Color = Color(0.6, 0.6, 0.6)
var is_selected: bool = false

var mesh_instance: MeshInstance3D = null

func _ready() -> void:
	_create_visual()

func _create_visual() -> void:
	if mesh_instance != null:
		return

	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Visual"

	var quad := QuadMesh.new()
	quad.size = Vector2(18, 12)  # Rechteck (breiter als hoch)
	mesh_instance.mesh = quad

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = nation_color
	mat.render_priority = 25
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	
	mesh_instance.material_override = mat
	mesh_instance.billboard_mode = GeometryInstance3D.BILLBOARD_ENABLED

	add_child(mesh_instance)

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
	# Leicht über die Oberfläche heben, damit das Rechteck sichtbar bleibt
	var lifted_pos := world_pos.normalized() * (world_pos.length() + 6.0)
	global_position = lifted_pos
	moved.emit(lifted_pos)

func update_fade(alpha: float) -> void:
	if mesh_instance == null:
		return
	var mat := mesh_instance.material_override as StandardMaterial3D
	if mat == null:
		return

	var col := mat.albedo_color
	col.a = alpha
	mat.albedo_color = col

	# Bei Selektion Emission beibehalten
	if is_selected and mat.emission_enabled:
		mat.emission_energy_multiplier = lerp(0.8, 1.8, alpha)

func _update_visual() -> void:
	if mesh_instance == null:
		return

	var mat := mesh_instance.material_override as StandardMaterial3D
	if mat == null:
		return

	if is_selected:
		mat.albedo_color = nation_color.lightened(0.4)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 1.0, 0.6)
		mat.emission_energy_multiplier = 1.5
		mesh_instance.scale = Vector3(1.25, 1.25, 1.25)
	else:
		mat.albedo_color = nation_color
		mat.emission_enabled = false
		mesh_instance.scale = Vector3.ONE
