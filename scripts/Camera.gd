extends Camera3D
class_name OrbitalCamera

@export var target: Node3D
@export var start_distance: float = 1400.0
@export var min_distance: float = 505.0
@export var max_distance: float = 2200.0
@export var sensitivity: float = 0.11
@export var smoothness: float = 11.0

@export_group("LOD")
@export var states_fade_start: float = 850.0
@export var states_fade_end: float = 550.0

var yaw: float = 30.0
var pitch: float = 15.0
var distance: float = 1400.0
var target_yaw: float = 30.0
var target_pitch: float = 15.0
var target_distance: float = 1400.0

var is_dragging := false
var last_mouse_pos := Vector2.ZERO

@onready var globe: Globe = get_node_or_null("../Globe")

func _ready() -> void:
	if not target:
		target = get_node_or_null("../Globe")
	distance = start_distance
	target_distance = start_distance
	_update_position()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_dragging = event.pressed
			last_mouse_pos = event.position

		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_left_click()

		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_right_click()

		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			var zoom_factor := 0.96
			if distance < 800:
				zoom_factor = lerp(0.993, 0.96, clamp((distance - 505) / 295.0, 0.0, 1.0))
			target_distance = max(min_distance, target_distance * zoom_factor)

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var zoom_factor := 1.04
			if distance < 800:
				zoom_factor = lerp(1.007, 1.04, clamp((distance - 505) / 295.0, 0.0, 1.0))
			target_distance = min(max_distance, target_distance * zoom_factor)

	elif event is InputEventMouseMotion and is_dragging:
		var delta: Vector2 = event.position - last_mouse_pos
		var current_sens: float = sensitivity * clampf(distance / 1100.0, 0.25, 1.0)
		target_yaw   -= delta.x * current_sens
		target_pitch = clamp(target_pitch + delta.y * current_sens, -80, 80)
		last_mouse_pos = event.position

func _process(delta: float) -> void:
	var t: float = clampf(smoothness * delta, 0.0, 1.0)
	yaw      = lerp(yaw, target_yaw, t)
	pitch    = lerp(pitch, target_pitch, t)
	distance = lerp(distance, target_distance, t * 0.65)
	_update_position()

	if globe:
		_fade_coastlines()
		_fade_all_states()
		_fade_cities()
		_fade_ground_entities()

func _fade_coastlines() -> void:
	var coast := globe.get_node_or_null("Coastlines")
	if not coast: return
	var mat := coast.material_override as StandardMaterial3D
	if not mat: return

	var alpha := 1.0
	if distance < 550:
		alpha = 0.0
	elif distance < 900:
		alpha = clamp((distance - 550) / 350.0, 0.0, 1.0)

	var col = mat.albedo_color
	col.a = lerp(col.a, 0.15, alpha)
	mat.albedo_color = col

func _fade_all_states() -> void:
	if not globe: return
	for child in globe.get_children():
		if child is MeshInstance3D and child.name.begins_with("State_"):
			var mat := child.material_override as StandardMaterial3D
			if not mat: continue

			var alpha := 1.0
			if distance > states_fade_start:
				alpha = 0.0
			elif distance < states_fade_end:
				alpha = 1.0
			else:
				alpha = clamp((states_fade_start - distance) / (states_fade_start - states_fade_end), 0.0, 1.0)

			var col = mat.albedo_color
			col.a = lerp(col.a, 0.4, alpha)
			if distance < states_fade_end + 30:
				col.a = 1.0
			mat.albedo_color = col

func _fade_cities() -> void:
	var cities_node := globe.get_node_or_null("Cities")
	if not cities_node: return
	var mat := cities_node.material_override as StandardMaterial3D
	if not mat: return

	var alpha := 1.0
	if distance > states_fade_start:
		alpha = 0.0
	elif distance < states_fade_end:
		alpha = 1.0
	else:
		alpha = clamp((states_fade_start - distance) / (states_fade_start - states_fade_end), 0.0, 1.0)

	var col = mat.albedo_color
	col.a = lerp(col.a, 0.4, alpha)
	if distance < states_fade_end + 30:
		col.a = 1.0
	mat.albedo_color = col

func _fade_ground_entities() -> void:
	UnitManager.update_fade_for_all(distance)

func _handle_left_click() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	
	var entity = UnitManager.get_entity_at_mouse(mouse_pos, self)
	if entity:
		UnitManager.select_entity(entity)
		return

	_try_select_state()

	if not _did_hit_anything(mouse_pos):
		UnitManager.deselect()

func _handle_right_click() -> void:
	if not UnitManager.selected_entity:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var from := project_ray_origin(mouse_pos)
	var dir := project_ray_normal(mouse_pos)

	var hit_pos := _raycast_to_globe_sphere(from, dir)
	if hit_pos != Vector3.ZERO:
		if _is_on_land(hit_pos):
			UnitManager.move_selected_to(hit_pos)
		else:
			print("[Movement] Nur auf Land/States erlaubt!")

func _is_on_land(world_pos: Vector3) -> bool:
	if not globe:
		return true

	var min_dist: float = 999999.0
	for child in globe.get_children():
		if child is MeshInstance3D:
			if child.name.begins_with("State_") or child.name.begins_with("Political_"):
				var dist: float = child.global_position.distance_to(world_pos)
				if dist < min_dist:
					min_dist = dist

	return min_dist < 38.0

func _did_hit_anything(mouse_pos: Vector2) -> bool:
	var entity = UnitManager.get_entity_at_mouse(mouse_pos, self)
	if entity:
		return true
	return false

func _raycast_to_globe_sphere(from: Vector3, dir: Vector3) -> Vector3:
	if not globe:
		return Vector3.ZERO
	var radius := globe.earth_radius * 1.002
	var center := globe.global_position

	var oc := from - center
	var a := dir.dot(dir)
	var b := 2.0 * oc.dot(dir)
	var c := oc.dot(oc) - radius * radius
	var discriminant := b * b - 4 * a * c

	if discriminant < 0:
		return Vector3.ZERO

	var t := (-b - sqrt(discriminant)) / (2.0 * a)
	if t < 0:
		t = (-b + sqrt(discriminant)) / (2.0 * a)
	if t < 0:
		return Vector3.ZERO

	return from + dir * t

func _try_select_state() -> void:
	if not globe:
		print("[Click] Kein Globe gefunden!")
		return

	print("[Click] Linksklick erkannt")

	var mouse_pos := get_viewport().get_mouse_position()
	var from := project_ray_origin(mouse_pos)
	var dir := project_ray_normal(mouse_pos)

	var closest_state: Node3D = null
	var closest_dist: float = 999999.0

	for child in globe.get_children():
		if child is MeshInstance3D and child.name.begins_with("State_"):
			var to_state: Vector3 = (child.global_position - from).normalized()
			var dist: float = from.distance_to(child.global_position)
			var angle: float = dir.dot(to_state)

			if angle > 0.98 and dist < closest_dist:
				closest_dist = dist
				closest_state = child

	if closest_state == null:
		print("[Click] Kein State in der Nähe gefunden.")
		return

	print("[Click] State gefunden: ", closest_state.name)

	var node_name = closest_state.name

	if node_name.begins_with("State_Unknown_"):
		print("=== State ohne Daten ===")
		print("Node-Name: ", node_name)
		print("========================")
		return

	var state_id := int(node_name.split("_")[1])
	if globe.state_data.has(state_id):
		var data = globe.state_data[state_id]
		print("=== State angeklickt ===")
		print("ID:        ", data.get("id"))
		print("Name:      ", data.get("name"))
		print("Owner:     ", data.get("owner"))
		print("Controller:", data.get("controller"))
		print("Cities:    ", data.get("cities", []))
		print("========================")
	else:
		print("[Click] Keine Daten für State-ID ", state_id, " gefunden.")

func _update_position() -> void:
	if not target: return
	var rad_y := deg_to_rad(yaw)
	var rad_p := deg_to_rad(pitch)
	var dir := Vector3(
		cos(rad_p) * sin(rad_y),
		sin(rad_p),
		cos(rad_p) * cos(rad_y)
	)
	global_position = target.global_position + dir * distance
	look_at(target.global_position, Vector3.UP)
