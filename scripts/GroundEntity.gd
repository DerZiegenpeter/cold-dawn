extends Node3D
class_name GroundEntity

## Ground Entity
## - Flache Seite auf Oberfläche (wireframe cube)
## - Collision jetzt in der Scene definiert (Area3D + BoxShape3D size 2.2 passend zur Entity-Größe)
## - Kollision mit anderen GroundEntities wird aktiv aufgelöst (kein Überlappen mehr)
## - Einheiten können nicht mehr außerhalb von States (auf Wasser) bewegt werden (Gate in Camera + Validierung)

signal moved(new_pos: Vector3)

var data: Dictionary = {}
var nation_color: Color = Color(0.6, 0.6, 0.6)
var is_selected: bool = false

var mesh_instance: MeshInstance3D = null
var collision_area: Area3D = null
var target_pos: Vector3 = Vector3.ZERO

const ENTITY_SIZE := 2.2
const COLLISION_RADIUS := 2.8  # Etwas Puffer für Separation

func _ready() -> void:
	_create_visual()
	_setup_collision_from_scene_or_create()

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

	var s := ENTITY_SIZE

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

func _setup_collision_from_scene_or_create() -> void:
	# Priorität: Collision aus der Scene verwenden (wie gewünscht "in der scene für ground entities")
	if has_node("CollisionArea"):
		collision_area = get_node("CollisionArea")
		print("[GroundEntity] CollisionArea aus Scene geladen (Größe passend zur Entity)")
		return

	# Fallback: dynamisch erzeugen (für alte Scenes ohne Node)
	if collision_area != null:
		return

	collision_area = Area3D.new()
	collision_area.name = "CollisionArea"
	collision_area.collision_layer = 1
	collision_area.collision_mask = 1
	collision_area.monitoring = true
	collision_area.monitorable = true

	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ENTITY_SIZE, ENTITY_SIZE, ENTITY_SIZE)
	shape_node.shape = box
	shape_node.name = "CollisionShape3D"

	collision_area.add_child(shape_node)
	add_child(collision_area)
	print("[GroundEntity] CollisionArea dynamisch erstellt (Fallback)")

func _process(delta: float) -> void:
	_resolve_entity_collisions()  # NEU: Aktive Kollisionsauflösung zwischen GroundEntities

	if target_pos == Vector3.ZERO:
		return

	var current_dir: Vector3 = global_position.normalized()
	var target_dir: Vector3 = target_pos.normalized()
	var angle: float = current_dir.angle_to(target_dir)

	var angular_speed: float = 0.04
	var step: float = angular_speed * delta

	if angle <= step:
		global_position = target_pos
		target_pos = Vector3.ZERO
		_orient_to_surface()
		_resolve_entity_collisions()  # Nach Ankunft nochmal prüfen
		return

	var t: float = step / angle
	var new_dir: Vector3 = current_dir.slerp(target_dir, t)

	var radius: float = global_position.length()
	global_position = new_dir * radius
	_orient_to_surface()

func _resolve_entity_collisions() -> void:
	# Einfache Separation: GroundEntities stoßen sich gegenseitig ab (kein Überlappen)
	if not is_instance_valid(self) or global_position.length() < 1.0:
		return

	var others = []
	if Engine.has_singleton("UnitManager"):
		others = UnitManager.active_entities

	for other in others:
		if other == self or not is_instance_valid(other) or not other is GroundEntity:
			continue
		if other.global_position.length() < 1.0:
			continue

		var diff: Vector3 = global_position - other.global_position
		var dist: float = diff.length()
		if dist < 0.001 or dist > COLLISION_RADIUS * 2.0:
			continue

		# Separation force (stärker wenn näher)
		var push_strength: float = (COLLISION_RADIUS * 2.0 - dist) * 0.6
		var push_dir: Vector3 = diff.normalized() * push_strength

		# Auf Sphere bleiben: nur tangential verschieben (nicht radial)
		var normal: Vector3 = global_position.normalized()
		var tangential: Vector3 = push_dir - push_dir.dot(normal) * normal

		global_position += tangential * 0.5  # Sanft anwenden
		# Optional: auch anderen leicht zurückschieben (symmetrisch)
		if is_instance_valid(other):
			var other_normal: Vector3 = other.global_position.normalized()
			var other_tang: Vector3 = -tangential - (-tangential).dot(other_normal) * other_normal
			other.global_position += other_tang * 0.25

		_orient_to_surface()

func _orient_to_surface() -> void:
	if mesh_instance == null:
		return
	if global_position.length_squared() < 1.0:
		return
	var normal: Vector3 = global_position.normalized()
	if normal.length_squared() < 0.0001:
		return

	mesh_instance.transform.basis = Basis.looking_at(normal, Vector3.UP)

func set_data(entry: Dictionary, color: Color) -> void:
	data = entry
	nation_color = color

	if mesh_instance == null:
		_create_visual()
	if collision_area == null:
		_setup_collision_from_scene_or_create()

	_update_visual()
	_orient_to_surface()

func set_selected(selected: bool) -> void:
	is_selected = selected
	_update_visual()

func move_to(world_pos: Vector3) -> void:
	var s: float = ENTITY_SIZE
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
