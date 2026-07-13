extends Node

## CollisionSystem
## Handles separation between entities.
## Current rules:
## - Air has NO collision with anything
## - Naval does NOT collide with Land/Ground
## - Land collides with Land
## - Naval collides with Naval
## Later: Combat when enemy units touch

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

			var type_a := _get_entity_type(a)
			var type_b := _get_entity_type(b)

			# === NEW COLLISION RULES ===
			# Air has no collision with anything (flies over everything)
			if type_a == "air" or type_b == "air":
				continue

			# Naval does not collide with Land/Ground
			if (type_a == "naval" and type_b == "ground") or (type_a == "ground" and type_b == "naval"):
				continue

			# Everything else collides (land-land, naval-naval)

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

			# TODO: Basic combat hook for later (enemy contact)
			# if _are_enemies(a, b) and dist < 2.0:
			#     _trigger_combat(a, b)

func _get_entity_type(entity: Node) -> String:
	if entity == null:
		return "unknown"

	if entity.get("data") != null and entity.data is Dictionary and entity.data.has("type"):
		return str(entity.data["type"])

	# Fallback
	if entity is AirEntity:
		return "air"
	if entity is GroundEntity:
		return "ground"
	if entity is NavalEntity:
		return "naval"
	return "ground"

# Placeholder for future diplomacy/combat system
func _are_enemies(a: Node, b: Node) -> bool:
	if not a.get("data") or not b.get("data"): return false
	var owner_a = a.data.get("owner", "")
	var owner_b = b.data.get("owner", "")
	if owner_a == "" or owner_b == "": return false
	return owner_a != owner_b   # Simple: different owner = enemy (until diplomacy.json exists)
