extends Node
class_name CollisionSystem

## CollisionSystem
## Zuständig für Separation zwischen GroundEntities

@export var separation_radius: float = 3.8
@export var separation_force: float = 2.8

func resolve_collisions(entities: Array) -> void:
	var count := entities.size()
	if count < 2:
		return

	for i in range(count):
		var a: GroundEntity = entities[i]
		if not is_instance_valid(a) or a.global_position.length() < 1.0:
			continue

		for j in range(i + 1, count):
			var b: GroundEntity = entities[j]
			if not is_instance_valid(b) or b.global_position.length() < 1.0:
				continue

			var diff := a.global_position - b.global_position
			var dist := diff.length()

			if dist < 0.05 or dist > separation_radius:
				continue

			var push_dir := diff.normalized()
			var force := (separation_radius - dist) * separation_force

			var normal_a := a.global_position.normalized()
			var tangential_a := (push_dir - push_dir.dot(normal_a) * normal_a) * force * 0.6
			a.global_position += tangential_a

			var normal_b := b.global_position.normalized()
			var tangential_b := (-push_dir - (-push_dir).dot(normal_b) * normal_b) * force * 0.3
			b.global_position += tangential_b

			a._orient_to_surface()
			b._orient_to_surface()
