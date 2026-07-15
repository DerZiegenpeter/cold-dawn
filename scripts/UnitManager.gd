extends Node

## UnitManager
## Manages spawning and tracking of all unit entities (ground, air, naval)

@export var ground_entity_scene: PackedScene = preload("res://scenes/GroundEntity.tscn")
@export var air_entity_scene: PackedScene = preload("res://scenes/AirEntity.tscn")
@export var naval_entity_scene: PackedScene = preload("res://scenes/NavalEntity.tscn")

var active_entities: Array = []
var nation_colors: Dictionary = {}
var globe: Node = null
var selected_entity: Node = null

func initialize(globe_node: Node) -> void:
	globe = globe_node
	_load_nation_colors()
	print("[UnitManager] Initialized with globe")

func _load_nation_colors() -> void:
	var path := "res://data/nations.json"
	if not FileAccess.file_exists(path):
		push_warning("[UnitManager] nations.json nicht gefunden!")
		return

	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("[UnitManager] nations.json Parsing fehlgeschlagen")
		return

	for nation in json.data:
		var code := str(nation.get("id", ""))
		if code == "": continue
		
		var color_array: Array = nation.get("color", [])
		if color_array.size() >= 3:
			nation_colors[code] = Color(float(color_array[0]), float(color_array[1]), float(color_array[2]))

func load_and_spawn_oob(oob_path: String = "res://data/oob.json") -> void:
	if not globe:
		push_error("[UnitManager] Globe nicht initialisiert!")
		return

	if not FileAccess.file_exists(oob_path):
		push_warning("[UnitManager] oob.json nicht gefunden")
		return

	var file := FileAccess.open(oob_path, FileAccess.READ)
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("[UnitManager] oob.json Parsing fehlgeschlagen")
		return

	var oob_data: Array = json.data if json.data is Array else []

	for entry in oob_data:
		_spawn_entity(entry)

	print("[UnitManager] ", active_entities.size(), " Entities gespawnt")

func _process(delta: float) -> void:
	if CollisionSystem:
		CollisionSystem.resolve_collisions(active_entities)

func _spawn_entity(entry: Dictionary) -> void:
	var type: String = entry.get("type", "ground")

	var entity_scene: PackedScene
	var extra_height: float = 1.1

	if type == "air":
		entity_scene = air_entity_scene
		extra_height = 4.0
	elif type == "naval":
		entity_scene = naval_entity_scene
		extra_height = 0.6
	else:
		entity_scene = ground_entity_scene
		extra_height = 1.1

	if not entity_scene:
		push_error("[UnitManager] Entity Scene nicht gesetzt für type: " + type)
		return

	var entity = entity_scene.instantiate()

	var owner_code: String = entry.get("owner", "XXX")
	var color = nation_colors.get(owner_code, Color(0.6, 0.6, 0.6))

	globe.add_child(entity)

	# Set initial position
	if entry.has("position"):
		var pos_dict: Dictionary = entry["position"]
		if pos_dict.has("lat") and pos_dict.has("lon"):
			var lat: float = float(pos_dict["lat"])
			var lon: float = float(pos_dict["lon"])
			var lift: float = 1.002
			var base_radius: float = globe.earth_radius * lift
			var radius: float = base_radius + extra_height
			var world_pos: Vector3 = globe.lat_lon_to_vector3(lat, lon, radius)
			entity.global_position = world_pos

	entity.set_data(entry, color)

	active_entities.append(entity)

# ==================== SELECTION & INTERACTION ====================

func select_entity(entity: Node) -> void:
	if not is_instance_valid(entity):
		return
	if selected_entity and is_instance_valid(selected_entity) and selected_entity.has_method("set_selected"):
		selected_entity.set_selected(false)
	selected_entity = entity
	if entity.has_method("set_selected"):
		entity.set_selected(true)
	print("[UnitManager] Selected: ", entity.name)

func deselect() -> void:
	if selected_entity and is_instance_valid(selected_entity) and selected_entity.has_method("set_selected"):
		selected_entity.set_selected(false)
	selected_entity = null
	print("[UnitManager] Deselected")

func move_selected_to(world_pos: Vector3) -> void:
	if selected_entity and is_instance_valid(selected_entity) and selected_entity.has_method("move_to"):
		if CollisionSystem and CollisionSystem.has_method("end_combat"):
			for other in active_entities:
				if other != selected_entity and CollisionSystem._are_enemies(selected_entity, other):
					CollisionSystem.end_combat(selected_entity, other)

		selected_entity.move_to(world_pos)
		print("[UnitManager] Move requested for selected entity")

# ==================== FADE / LOD ====================

func update_fade_for_all(cam_distance: float) -> void:
	var alpha := 1.0
	if cam_distance > 1600:
		alpha = 0.0
	elif cam_distance > 1100:
		alpha = clamp((1600.0 - cam_distance) / 500.0, 0.0, 1.0)
	elif cam_distance < 600:
		alpha = 1.0
	for entity in active_entities:
		if is_instance_valid(entity) and entity.has_method("update_fade"):
			entity.update_fade(alpha)

# ==================== MOUSE PICKING ====================

func get_entity_at_mouse(mouse_pos: Vector2, cam: Camera3D, max_pixel_dist: float = 25.0) -> Node:
	if not cam or active_entities.is_empty():
		return null

	# Precise physics raycast first
	var from := cam.project_ray_origin(mouse_pos)
	var dir := cam.project_ray_normal(mouse_pos)
	var space_state := cam.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 20000.0)
	query.collision_mask = 1
	query.collide_with_areas = true
	var result := space_state.intersect_ray(query)

	if result and result.has("collider"):
		var collider: Object = result.collider
		var parent: Node = collider.get_parent() if is_instance_valid(collider) else null
		if parent and parent in active_entities:
			return parent
		if parent:
			var grandparent: Node = parent.get_parent()
			if grandparent and grandparent in active_entities:
				return grandparent

	# Fallback: closest on screen (now with tighter threshold)
	var closest: Node = null
	var closest_dist := 999999.0
	for e in active_entities:
		if not is_instance_valid(e): continue
		var screen_pos := cam.unproject_position(e.global_position)
		var dist := screen_pos.distance_to(mouse_pos)
		if dist < max_pixel_dist and dist < closest_dist:
			closest_dist = dist
			closest = e
	return closest
