extends Node
class_name MovementSystem

## MovementSystem
## Zuständig für die Bewegung von Ground- und Air-Entities
## Hält GroundEntities strikt auf Land

func request_move(entity: GroundEntity, target_world_pos: Vector3) -> bool:
	if not entity or not is_instance_valid(entity):
		return false

	var globe := entity.get_globe()
	if not globe:
		return false

	# LandSystem nutzen (falls verfügbar)
	if LandSystem and LandSystem.is_position_on_land(target_world_pos):
		entity._set_target_position(target_world_pos)
		return true
	else:
		print("[MovementSystem] Move auf ungültiges Gebiet blockiert")
		return false

func update_entity_movement(entity: GroundEntity, delta: float) -> void:
	if not entity or not is_instance_valid(entity):
		return

	# Hier könnte später komplexere Bewegungslogik (Pathfinding etc.) rein
	pass
