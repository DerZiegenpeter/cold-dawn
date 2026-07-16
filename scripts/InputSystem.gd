extends Node

## InputSystem
## Zentrale Stelle für alle Maus- und Tastatureingaben.
## Delegiert an CommandSystem und CameraSystem.

@onready var camera_system = get_node("/root/CameraSystem")
@onready var command_system = get_node("/root/CommandSystem")
@onready var unit_manager = get_node("/root/UnitManager")
@onready var globe = get_node("/root/Main/Globe")

var is_dragging := false
var last_mouse_pos := Vector2.ZERO

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and is_dragging:
		_handle_mouse_drag(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		is_dragging = event.pressed
		last_mouse_pos = event.position

	elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_left_click()
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_handle_right_click()
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
		camera_system.zoom_in()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera_system.zoom_out()

func _handle_mouse_drag(event: InputEventMouseMotion) -> void:
	var delta: Vector2 = event.position - last_mouse_pos
	var sens := camera_system.sensitivity * clampf(camera_system.distance / 1100.0, 0.25, 1.0)
	camera_system.add_yaw(delta.x * sens)
	camera_system.add_pitch(delta.y * sens)
	last_mouse_pos = event.position

func _handle_left_click() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var cam := get_viewport().get_camera_3d()
	var entity = unit_manager.get_entity_at_mouse(mouse_pos, cam)
	if entity:
		unit_manager.select_entity(entity)
		return

func _handle_right_click() -> void:
	if not unit_manager.selected_entity: return

	var mouse_pos := get_viewport().get_mouse_position()
	var cam := get_viewport().get_camera_3d()

	var target_entity = unit_manager.get_entity_at_mouse(mouse_pos, cam, 20.0)
	if target_entity and target_entity != unit_manager.selected_entity:
		var attacker_3d := unit_manager.selected_entity as Node3D
		var target_3d := target_entity as Node3D
		if attacker_3d and target_3d and command_system:
			command_system.try_attack(attacker_3d, target_3d)
		return

	var hit_pos := _raycast_to_globe(mouse_pos, cam)
	if hit_pos != Vector3.ZERO:
		var selected_3d := unit_manager.selected_entity as Node3D
		if selected_3d and command_system:
			command_system.issue_move_command(selected_3d, hit_pos)

func _raycast_to_globe(mouse_pos: Vector2, cam: Camera3D) -> Vector3:
	var from := cam.project_ray_origin(mouse_pos)
	var dir := cam.project_ray_normal(mouse_pos)
	if globe and globe.has_method("_raycast_to_globe_sphere"):
		return globe._raycast_to_globe_sphere(from, dir)
	return Vector3.ZERO
