extends Node

## CommandSystem
## Interpretiert Spielbefehle (Move, Attack, etc.) und delegiert an die richtigen Systeme.

@onready var pathfinding = get_node("/root/PathfindingSystem")
@onready var movement = get_node("/root/MovementSystem")
@onready var unit_manager = get_node("/root/UnitManager")
@onready var collision = get_node("/root/CollisionSystem")

func issue_move_command(entity: Node, target_world_pos: Vector3) -> void:
	if not is_instance_valid(entity):
		return

	var path: Array[Vector3] = pathfinding.generate_path(entity as Node3D, target_world_pos)
	if path.is_empty():
		return

	entity.set_meta("current_path", path)
	entity.set_meta("current_path_index", 0)

	if get_node("/root/Main/Globe").has_method("show_click_ring"):
		get_node("/root/Main/Globe").show_click_ring(target_world_pos)

func try_attack(attacker: Node, target: Node) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return

	var attacker_3d: Node3D = attacker as Node3D
	var target_3d: Node3D = target as Node3D
	if attacker_3d == null or target_3d == null:
		return

	if collision and collision._are_enemies(attacker, target):
		var dist := attacker_3d.global_position.distance_to(target_3d.global_position)
		if dist < 80.0:
			collision.start_battle(attacker, target)
		else:
			issue_move_command(attacker, target_3d.global_position)
