extends Node

## CollisionSystem
## Final Rules:
## - ONLY same domain collides:
##     Land  <-> Land
##     Naval <-> Naval
##     Air   <-> Air
## - All cross-domain = NO collision

@export var separation_radius := 4.5
@export var separation_force := 1.8
@export var combat_radius := 3.0
@export var combat_push_multiplier := 0.08

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

			if type_a != type_b:
				continue

			var diff: Vector3 = a.global_position - b.global_position
			var dist: float = diff.length()
			if dist < 0.05: continue

			var push_multiplier := 1.0

			if _are_enemies(a, b) and dist < combat_radius:
				push_multiplier = combat_push_multiplier
				_ensure_combat_marker(a, b, (a.global_position + b.global_position) * 0.5, false)  # skirmish = normal glow

			if dist > separation_radius: continue

			var push: Vector3 = diff.normalized() * ((separation_radius - dist) * separation_force * push_multiplier)

			var na: Vector3 = a.global_position.normalized()
			var ta: Vector3 = (push - push.dot(na) * na) * 0.5
			a.global_position += ta

			var nb: Vector3 = b.global_position.normalized()
			var tb: Vector3 = (-push - (-push).dot(nb) * nb) * 0.25
			b.global_position += tb

			if a.has_method("_orient_to_surface"): a._orient_to_surface()
			if b.has_method("_orient_to_surface"): b._orient_to_surface()

func _ensure_combat_marker(a: Node, b: Node, contact_pos: Vector3, is_battle: bool = false) -> void:
	var key := _get_combat_key(a, b)
	if _combat_markers.has(key): return

	var marker := MeshInstance3D.new()
	marker.name = "CombatMarker"

	var sphere := SphereMesh.new()
	sphere.radius = 0.7
	sphere.height = 1.4
	marker.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.15, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.3, 0.3)
	mat.emission_energy_multiplier = 4.5 if is_battle else 2.8   # brighter for Battle
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.9
	marker.material_override = mat

	marker.global_position = contact_pos.normalized() * (contact_pos.length() + 1.8)

	if a.get_parent():
		a.get_parent().add_child(marker)
	else:
		add_child(marker)

	_combat_markers[key] = marker

func start_battle(attacker: Node, target: Node) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(target): return
	if not _are_enemies(attacker, target): return

	# Force them close and create bright Battle marker
	var mid_pos = (attacker.global_position + target.global_position) * 0.5
	_ensure_combat_marker(attacker, target, mid_pos, true)  # is_battle = true → brighter glow

	# Slightly push them together so they engage
	var dir = (target.global_position - attacker.global_position).normalized()
	attacker.global_position += dir * 1.5
	target.global_position -= dir * 1.5

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
	if entity == null: return "unknown"
	if entity.get("data") != null and entity.data is Dictionary and entity.data.has("type"):
		return str(entity.data["type"])
	if entity is AirEntity: return "air"
	if entity is GroundEntity: return "ground"
	if entity is NavalEntity: return "naval"
	return "ground"

func _are_enemies(a: Node, b: Node) -> bool:
	if not a.get("data") or not b.get("data"): return false
	var owner_a := str(a.data.get("owner", ""))
	var owner_b := str(b.data.get("owner", ""))
	return owner_a != "" and owner_b != "" and owner_a != owner_b

func clear_all_combat_markers() -> void:
	for marker in _combat_markers.values():
		if is_instance_valid(marker):
			marker.queue_free()
	_combat_markers.clear()
