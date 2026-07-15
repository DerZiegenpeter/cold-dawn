extends Node

## CollisionSystem
## Rules:
## - Land vs Land: collision
## - Naval vs Naval: collision
## - Air vs (Air, Land, Naval): collision
## - Everything else (Land-Naval, etc.): no collision
##
## Combat: Hostile units that get close stick + get red marker

@export var separation_radius := 3.8
@export var separation_force := 2.8
@export var combat_radius := 2.5
@export var combat_push_multiplier := 0.15   # they stick together

# Track active combat markers (contact_pos -> red sphere)
var _combat_markers: Dictionary = {}

func resolve_collisions(entities: Array) -> void:
	var count := entities.size()
	if count < 2: return

	for i in range(count):
		var a = entities[i]
		if not is_instance_valid(a) or a.global_position.length() < 1.0: continue

		for j in range(i + 1, count):
			var b = entities[j]
			if not is_instance_valid(b) or b.global_position.length() < 1.0: continue

			var type_a := _get_entity_type(a)
			var type_b := _get_entity_type(b)

			# === COLLISION RULES ===
			var should_collide := false

			if type_a == "land" and type_b == "land":
				should_collide = true
			elif type_a == "naval" and type_b == "naval":
				should_collide = true
			elif type_a == "air" or type_b == "air":
				should_collide = true

			if not should_collide:
				continue

			var diff: Vector3 = a.global_position - b.global_position
			var dist: float = diff.length()
			if dist < 0.05: continue

			var is_combat := false
			var push_multiplier := 1.0

			# === COMBAT LOGIC ===
			if _are_enemies(a, b) and dist < combat_radius:
				is_combat = true
				push_multiplier = combat_push_multiplier   # they stick
				_ensure_combat_marker(a, b, (a.global_position + b.global_position) * 0.5)

			if dist > separation_radius: continue

			var push: Vector3 = diff.normalized() * ((separation_radius - dist) * separation_force * push_multiplier)

			var na: Vector3 = a.global_position.normalized()
			var ta: Vector3 = (push - push.dot(na) * na) * 0.6
			a.global_position += ta

			var nb: Vector3 = b.global_position.normalized()
			var tb: Vector3 = (-push - (-push).dot(nb) * nb) * 0.3
			b.global_position += tb

			if a.has_method("_orient_to_surface"): a._orient_to_surface()
			if b.has_method("_orient_to_surface"): b._orient_to_surface()

func _ensure_combat_marker(a: Node, b: Node, contact_pos: Vector3) -> void:
	var key := _get_combat_key(a, b)
	if _combat_markers.has(key):
		return

	var marker := MeshInstance3D.new()
	marker.name = "CombatMarker"

	var sphere := SphereMesh.new()
	sphere.radius = 1.2
	sphere.height = 2.4
	marker.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.1, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.2, 0.2)
	mat.emission_energy_multiplier = 2.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.85
	marker.material_override = mat

	# Place marker slightly above surface
	marker.global_position = contact_pos.normalized() * (contact_pos.length() + 2.0)

	# Attach to globe or one of the units
	if a.get_parent():
		a.get_parent().add_child(marker)
	else:
		add_child(marker)

	_combat_markers[key] = marker

func end_combat(a: Node, b: Node) -> void:
	var key := _get_combat_key(a, b)
	if _combat_markers.has(key):
		var marker = _combat_markers[key]
		if is_instance_valid(marker):
			marker.queue_free()
		_combat_markers.erase(key)

func _get_combat_key(a: Node, b: Node) -> String:
	var id_a := a.get_instance_id()
	var id_b := b.get_instance_id()
	return str(min(id_a, id_b)) + "_" + str(max(id_a, id_b))

func _get_entity_type(entity: Node) -> String:
	if entity == null:
		return "unknown"

	if entity.get("data") != null and entity.data is Dictionary and entity.data.has("type"):
		return str(entity.data["type"])

	if entity is AirEntity:
		return "air"
	if entity is GroundEntity:
		return "ground"
	if entity is NavalEntity:
		return "naval"
	return "ground"

func _are_enemies(a: Node, b: Node) -> bool:
	if not a.get("data") or not b.get("data"): return false
	var owner_a := str(a.data.get("owner", ""))
	var owner_b := str(b.data.get("owner", ""))
	if owner_a == "" or owner_b == "": return false
	return owner_a != owner_b

func clear_all_combat_markers() -> void:
	for marker in _combat_markers.values():
		if is_instance_valid(marker):
			marker.queue_free()
	_combat_markers.clear()
