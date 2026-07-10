extends Node

signal entity_selected(entity)
signal entity_deselected()

@export var ground_entity_scene: PackedScene = preload("res://scenes/GroundEntity.tscn")
@export var air_entity_scene: PackedScene = preload("res://scenes/AirEntity.tscn")

var active_entities: Array = []
var selected_entity = null

var nation_colors: Dictionary = {}
var globe: Globe = null

func _ready() -> void:
	_load_nation_colors()

func initialize(globe_node) -> void:
	globe = globe_node
	print("[UnitManager] Globe registriert")

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

func _spawn_entity(entry: Dictionary) -> void:
	var type: String = entry.get("type", "ground")

	var entity_scene: PackedScene
	if type == "air":
		entity_scene = air_entity_scene
	else:
		entity_scene = ground_entity_scene

	if not entity_scene:
		push_error("[UnitManager] Entity Scene nicht gesetzt!")
		return

	var entity = entity_scene.instantiate()

	var owner_code: String = entry.get("owner", "XXX")
	var color = nation_colors.get(owner_code, Color(0.6, 0.6, 0.6))

	globe.add_child(entity)

	# Set initial position - EXAKT auf der Oberfläche (konsistent mit move_to)
	if entry.has("position"):
		var pos_dict: Dictionary = entry["position"]
		if pos_dict.has("lat") and pos_dict.has("lon"):
			var lat: float = float(pos_dict["lat"])
			var lon: float = float(pos_dict["lon"])
			var lift: float = 1.002
			var base_radius: float = globe.earth_radius * lift
			# Ground: exakt surface + s/2 (1.1), vorher 2.8 -> schwebte!
			# Air bleibt höher schwebend
			var extra_height: float = 8.0 if type == "air" else 1.1
			var radius: float = base_radius + extra_height
			var world_pos: Vector3 = globe.lat_lon_to_vector3(lat, lon, radius)
			entity.global_position = world_pos

	entity.set_data(entry, color)

	active_entities.append(entity)

func select_entity(entity) -> void:
	if selected_entity == entity:
		return

	if selected_entity:
		selected_entity.set_selected(false)

	selected_entity = entity
	entity.set_selected(true)
	entity_selected.emit(entity)
	print("[UnitManager] Selected: ", entity.data.get("name", "Unknown"))

func deselect() -> void:
	if selected_entity:
		selected_entity.set_selected(false)
		selected_entity = null
		entity_deselected.emit()
		print("[UnitManager] Deselected")

func move_selected_to(world_pos: Vector3) -> void:
	if not selected_entity:
		return
	selected_entity.move_to(world_pos)
	print("[UnitManager] Move command issued")

func get_entity_at_mouse(mouse_pos: Vector2, camera: Camera3D) -> Variant:
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)

	var closest = null
	var closest_dist := 999999.0

	for e in active_entities:
		var entity: Node3D = e as Node3D
		if not is_instance_valid(entity):
			continue
		
		var to_entity: Vector3 = (entity.global_position - from).normalized()
		var angle: float = dir.dot(to_entity)
		var dist: float = from.distance_to(entity.global_position)

		if angle > 0.985 and dist < closest_dist:
			closest_dist = dist
			closest = entity

	return closest

func update_fade_for_all(distance: float) -> void:
	var alpha: float = 1.0
	if distance > 1200:
		alpha = 0.0
	elif distance < 700:
		alpha = 1.0
	else:
		alpha = clamp((1200.0 - distance) / 500.0, 0.0, 1.0)

	for entity in active_entities:
		if is_instance_valid(entity):
			entity.update_fade(alpha)
