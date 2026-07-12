extends Node

## MovementSystem
## Handles movement requests. Ground on land, Naval on water, Air bypasses via own move_to.

func request_move(entity: Node, target_world_pos: Vector3) -> bool:
	if not is_instance_valid(entity):
		return false

	var is_naval := false
	if entity.has("data") and entity.data is Dictionary:
		is_naval = entity.data.get("type", "") == "naval"

	var globe := entity.get_parent() if entity.has_method("get_globe") else null
	if not globe:
		globe = entity.get_parent()

	if is_naval:
		# Naval moves only on water
		if LandSystem and not LandSystem.is_position_on_land(target_world_pos):
			if entity.has_method("_set_target_position"):
				entity._set_target_position(target_world_pos)
			return true
		else:
			print("[MovementSystem] Move blockiert (nicht auf Wasser / Naval)")
			return false
	else:
		# Ground (and default) only on land
		if LandSystem and LandSystem.is_position_on_land(target_world_pos):
			if entity.has_method("_set_target_position"):
				entity._set_target_position(target_world_pos)
			return true
		else:
			print("[MovementSystem] Move blockiert (nicht auf Land)")
			return false

	return false
