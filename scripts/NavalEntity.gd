extends Node3D
class_name NavalEntity

signal moved(new_pos: Vector3)

var data: Dictionary = {}
var nation_color: Color = Color(0.6, 0.6, 0.6)
var is_selected: bool = false

var mesh_instance: MeshInstance3D = null
var collision_area: Area3D = null
var target_pos: Vector3 = Vector3.ZERO

var last_valid_pos: Vector3 = Vector3.ZERO

const ENTITY_SIZE := 2.2
const NAVAL_LENGTH := 5.0
const NAVAL_WIDTH := 1.0
const NAVAL_HEIGHT := 0.7

func _ready() -> void:
	_create_visual()
	_setup_collision_from_scene_or_create()
	last_valid_pos = global_position

func _create_visual() -> void:
	if mesh_instance != null: return

	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Visual"

	var mesh: ArrayMesh = ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()

	var l: float = NAVAL_LENGTH / 2.0
	var w: float = NAVAL_WIDTH / 2.0
	var h: float = NAVAL_HEIGHT / 2.0

	vertices.push_back(Vector3(-w, -h, -l))
	vertices.push_back(Vector3( w, -h, -l))
	vertices.push_back(Vector3( w,  h, -l))
	vertices.push_back(Vector3(-w,  h, -l))
	vertices.push_back(Vector3(-w, -h,  l))
	vertices.push_back(Vector3( w, -h,  l))
	vertices.push_back(Vector3( w,  h,  l))
	vertices.push_back(Vector3(-w,  h,  l))

	indices.append_array([0,1, 1,2, 2,3, 3,0])
	indices.append_array([4,5, 5,6, 6,7, 7,4])
	indices.append_array([0,4, 1,5, 2,6, 3,7])

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

	mesh_instance.mesh = mesh

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = nation_color
	mat.emission_enabled = true
	mat.emission = nation_color
	mat.emission_energy_multiplier = 1.2
	mat.render_priority = 30

	mesh_instance.material_override = mat

	add_child(mesh_instance)

func _setup_collision_from_scene_or_create() -> void:
	if has_node("CollisionArea"):
		collision_area = get_node("CollisionArea")
		return

	collision_area = Area3D.new()
	collision_area.name = "CollisionArea"
	collision_area.collision_layer = 1
	collision_area.collision_mask = 1

	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(NAVAL_WIDTH, NAVAL_HEIGHT, NAVAL_LENGTH)
	shape.shape = box
	collision_area.add_child(shape)
	add_child(collision_area)

func _process(delta: float) -> void:
	if MovementSystem and MovementSystem.has_active_path(self):
		MovementSystem.update_movement(self, delta)
		return

	# Legacy direct movement
	if target_pos == Vector3.ZERO:
		last_valid_pos = global_position
		return

	var current_dir: Vector3 = global_position.normalized()
	var target_dir: Vector3 = target_pos.normalized()
	var angle: float = current_dir.angle_to(target_dir)

	var step: float = 0.5 * delta

	if angle <= step:
		global_position = target_pos
		last_valid_pos = global_position
		target_pos = Vector3.ZERO
		MovementSystem.clear_path(self)
		_orient_to_surface()
		return

	var t: float = step / angle
	var new_dir: Vector3 = current_dir.slerp(target_dir, t)
	global_position = new_dir * global_position.length()

	if LandSystem and LandSystem.is_position_on_land(global_position):
		global_position = last_valid_pos
		target_pos = Vector3.ZERO
		MovementSystem.clear_path(self)
		return

	_orient_to_surface()
	last_valid_pos = global_position

func get_globe() -> Node:
	return get_parent()

func _orient_to_surface() -> void:
	if not mesh_instance: return
	var normal: Vector3 = global_position.normalized()
	if normal.length_squared() < 0.0001: return

	# Proper flat ship orientation (long axis tangential)
	var y_axis: Vector3 = normal
	var arbitrary: Vector3 = Vector3(0, 0, 1)
	if abs(y_axis.dot(arbitrary)) > 0.99:
		arbitrary = Vector3(1, 0, 0)
	var z_axis: Vector3 = arbitrary.cross(y_axis).normalized()
	var x_axis: Vector3 = y_axis.cross(z_axis).normalized()
	mesh_instance.transform.basis = Basis(x_axis, y_axis, z_axis)

func set_data(entry: Dictionary, color: Color) -> void:
	data = entry
	nation_color = color
	if not mesh_instance: _create_visual()
	_update_visual()
	_orient_to_surface()
	last_valid_pos = global_position

func set_selected(selected: bool) -> void:
	is_selected = selected
	_update_visual()

func _set_target_position(world_pos: Vector3) -> void:
	var s: float = ENTITY_SIZE
	target_pos = world_pos.normalized() * (world_pos.length() + s * 0.4)

func move_to(world_pos: Vector3) -> void:
	if MovementSystem:
		MovementSystem.request_move(self, world_pos)

func update_fade(alpha: float) -> void:
	if not mesh_instance: return
	var mat: StandardMaterial3D = mesh_instance.material_override as StandardMaterial3D
	if mat: mat.albedo_color.a = alpha

func _update_visual() -> void:
	if not mesh_instance: return
	var mat: StandardMaterial3D = mesh_instance.material_override as StandardMaterial3D
	if not mat: return

	if is_selected:
		mat.albedo_color = nation_color.lightened(0.5)
		mat.emission_energy_multiplier = 2.5
	else:
		mat.albedo_color = nation_color
		mat.emission_energy_multiplier = 1.2
