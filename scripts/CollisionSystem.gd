extends Node

## CollisionSystem
## Handles separation between entities. Air entities do not collide/separate with Ground entities.

@export var separation_radius := 3.8
@export var separation_force := 2.8

func resolve_collisions(entities: Array) -> void:
	var count := entities.size()
	if count < 2: return

	for i in range(count):
		var a = entities[i]
		if not is_instance_valid(a) or a.global_position.length() < 1.0: continue

		for j in range(i + 1, count):
			var b = entities[j]
			if not is_instance_valid(b) or b.global_position.length() < 1.0: continue

			# Skip collision between air and ground entities (air flies over ground units)
			var type_a := _get_entity_type(a)
			var type_b := _get_entity_type(b)
			if (type_a == "air" and type_b == "ground") or (type_a == "ground" and type_b == "air"):
				continue

			var diff: Vector3 = a.global_position - b.global_position
			var dist: float = diff.length()
			if dist < 0.05 or dist > separation_radius: continue

			var push: Vector3 = diff.normalized() * ((separation_radius - dist) * separation_force)

			var na: Vector3 = a.global_position.normalized()
			var ta: Vector3 = (push - push.dot(na) * na) * 0.6
			a.global_position += ta

			var nb: Vector3 = b.global_position.normalized()
			var tb: Vector3 = (-push - (-push).dot(nb) * nb) * 0.3
			b.global_position += tb

			if a.has_method("_orient_to_surface"): a._orient_to_surface()
			if b.has_method("_orient_to_surface"): b._orient_to_surface()

func _get_entity_type(entity: Node) -> String:
	if not is_instance_valid(entity):
		return "unknown"
	# Primary method: use the data dictionary set during spawning (most reliable)
	if entity.has("data") and entity.data is Dictionary:
		var t = entity.data.get("type", "")
		if t != "":
			return str(t)
	# Fallbacks (only if data is missing)
	if entity.has_method("get_class"):
		var cls := entity.get_class()
		if cls == "AirEntity":
			return "air"
		if cls == "GroundEntity":
			return "ground"
		if cls == "NavalEntity":
			return "naval"
	return "ground"  # default
