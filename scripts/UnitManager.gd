extends Node

## UnitManager
## Manages spawning and tracking of all unit entities (ground, air, naval)

@export var ground_entity_scene: PackedScene = preload("res://scenes/GroundEntity.tscn")
@export var air_entity_scene: PackedScene = preload("res://scenes/AirEntity.tscn")
@export var naval_entity_scene: PackedScene = preload("res://scenes/NavalEntity.tscn")

var active_entities: Array = []
var nation_colors: Dictionary = {}
var globe: Node = null

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
