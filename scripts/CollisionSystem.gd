extends Node

## CollisionSystem

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

			var diff: Vector3 = a.global_position - b.global_position
			var dist: float = diff.length()
			if dist < 0.05 or dist > separation_radius: continue

			var push := diff.normalized() * ((separation_radius - dist) * separation_force)

			var na := a.global_position.normalized()
			var ta := (push - push.dot(na) * na) * 0.6
			a.global_position += ta

			var nb := b.global_position.normalized()
			var tb := (-push - (-push).dot(nb) * nb) * 0.3
			b.global_position += tb

			if a.has_method("_orient_to_surface"): a._orient_to_surface()
			if b.has_method("_orient_to_surface"): b._orient_to_surface()
