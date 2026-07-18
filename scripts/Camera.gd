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
		target_yaw += delta.x * current_sens
		target_pitch += delta.y * current_sens
		last_mouse_pos = event.position

func _process(delta: float) -> void:
	var t: float = clampf(smoothness * delta, 0.0, 1.0)
	yaw = lerp(yaw, target_yaw, t)
	pitch = lerp(pitch, target_pitch, t)
	distance = lerp(distance, target_distance, t * 0.65)
	_update_position()

	if globe:
		_fade_coastlines()
		_fade_all_states()
		_fade_cities()
		_fade_ground_entities()

func _update_position() -> void:
	if not target: return
	var dir := Vector3(
		cos(deg_to_rad(yaw)) * cos(deg_to_rad(pitch)),
		sin(deg_to_rad(pitch)),
		sin(deg_to_rad(yaw)) * cos(deg_to_rad(pitch))
	).normalized()
	global_position = target.global_position + dir * distance
	look_at(target.global_position, Vector3.UP)

func _fade_coastlines() -> void:
	var coast: Node = globe.get_node_or_null("Coastlines")
	if not coast: return
	var mat: StandardMaterial3D = coast.material_override as StandardMaterial3D
	if not mat: return

	var alpha := 1.0
	if distance < 550:
		alpha = 0.0
	elif distance < 900:
		alpha = clamp((distance - 550) / 350.0, 0.0, 1.0)
	var col = mat.albedo_color
	# Absolute target alpha (prevents sticky values)
	col.a = lerp(0.15, 1.0, alpha) if alpha > 0.0 else 0.15
	if distance < 550:
		col.a = 0.0
	mat.albedo_color = col

func _fade_all_states() -> void:
	if not globe: return
	# Absolute alpha based purely on camera distance.
	# States only become visible together with cities when zoomed in close.
	var target_alpha := 0.0
	if distance < states_fade_end:
		target_alpha = 1.0
	elif distance < states_fade_start:
		target_alpha = clamp((states_fade_start - distance) / (states_fade_start - states_fade_end), 0.0, 1.0)
	else:
		target_alpha = 0.0

	for child in globe.get_children():
		if child is MeshInstance3D and child.name.begins_with("State_"):
			var mat := child.material_override as StandardMaterial3D
			if not mat: continue
			var col = mat.albedo_color
			# Absolute set – never depends on previous frame value
			col.a = target_alpha * 0.55
			if distance < states_fade_end + 20.0:
				col.a = 1.0
			mat.albedo_color = col

func _fade_cities() -> void:
	var cities_node: Node = globe.get_node_or_null("Cities")
	if not cities_node: return
	var mat: StandardMaterial3D = cities_node.material_override as StandardMaterial3D
	if not mat: return

	# Same thresholds as states so they appear/disappear together
	var target_alpha := 0.0
	if distance < states_fade_end:
		target_alpha = 1.0
	elif distance < states_fade_start:
		target_alpha = clamp((states_fade_start - distance) / (states_fade_start - states_fade_end), 0.0, 1.0)
	else:
		target_alpha = 0.0

	var col = mat.albedo_color
	col.a = target_alpha * 0.7
	if distance < states_fade_end + 20.0:
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
	if not _did_hit_anything(mouse_pos):
		UnitManager.deselect()

func _handle_right_click() -> void:
	print("[Camera] _handle_right_click triggered")

	if not UnitManager.selected_entity:
		print("[Camera] No selected_entity - aborting right-click movement")
		return

	print("[Camera] Selected entity: ", UnitManager.selected_entity)

	var mouse_pos := get_viewport().get_mouse_position()

	# Enemy check for manual battle
	var target_entity = UnitManager.get_entity_at_mouse(mouse_pos, self, 20.0)
	if target_entity and target_entity != UnitManager.selected_entity:
		if CollisionSystem and CollisionSystem._are_enemies(UnitManager.selected_entity, target_entity):
			var dist: float = UnitManager.selected_entity.global_position.distance_to(target_entity.global_position)
			if dist < 80.0:
				if CollisionSystem.has_method("start_battle"):
					CollisionSystem.start_battle(UnitManager.selected_entity, target_entity)
				return

	# Movement – always use the robust raycast that prefers the front-side hit
	var from := project_ray_origin(mouse_pos)
	var dir := project_ray_normal(mouse_pos)
	var hit_pos := _raycast_to_globe_sphere(from, dir)

	print("[Camera] Raycast result: hit_pos = ", hit_pos)

	if hit_pos != Vector3.ZERO:
		var selected = UnitManager.selected_entity
		var allow_move := true

		# Slightly lift outward so LandSystem check is more reliable
		var lifted_hit = hit_pos.normalized() * (hit_pos.length() + 3.0)

		if selected is GroundEntity:
			if not (LandSystem and LandSystem.is_position_on_land(lifted_hit)):
				allow_move = false
				print("[Movement] Nur auf Land/States erlaubt!")
		elif selected is NavalEntity:
			if LandSystem and LandSystem.is_position_on_land(lifted_hit):
				allow_move = false
				print("[Movement] Naval kann nicht auf Land!")

		if allow_move:
			# Prefer MovementSystem so path visualization is created
			if MovementSystem and MovementSystem.has_method("request_move"):
				MovementSystem.request_move(selected, hit_pos)
			elif has_node("/root/CommandSystem") and get_node("/root/CommandSystem").has_method("issue_move_command"):
				get_node("/root/CommandSystem").issue_move_command(selected, hit_pos)
			else:
				UnitManager.move_selected_to(hit_pos)

			if globe and globe.has_method("show_click_ring"):
				globe.show_click_ring(hit_pos)
		else:
			print("[Movement] Bewegung blockiert!")

func _did_hit_anything(mouse_pos: Vector2) -> bool:
	var entity = UnitManager.get_entity_at_mouse(mouse_pos, self)
	return entity != null

# Robust sphere raycast – ALWAYS returns the closest front-side intersection
func _raycast_to_globe_sphere(from: Vector3, dir: Vector3) -> Vector3:
	if not globe:
		return Vector3.ZERO

	# Prefer the Globe's own implementation when available (more battle-tested)
	if globe.has_method("_raycast_to_globe_sphere"):
		var hit: Vector3 = globe._raycast_to_globe_sphere(from, dir)
		if hit != Vector3.ZERO:
			# Extra safety: reject true back-side hits
			var center: Vector3 = globe.global_position
			var to_cam: Vector3 = (from - center).normalized()
			var to_hit: Vector3 = (hit - center).normalized()
			if to_hit.dot(to_cam) > -0.05:  # roughly front hemisphere relative to camera
				return hit

	# Fallback implementation (identical math, prioritises nearest positive t)
	var radius: float = globe.earth_radius * 1.002
	var center: Vector3 = globe.global_position

	var oc: Vector3 = from - center
	var a: float = dir.dot(dir)
	if a < 0.000001:
		return Vector3.ZERO
	var b: float = 2.0 * oc.dot(dir)
	var c: float = oc.dot(oc) - radius * radius

	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return Vector3.ZERO

	var sqrt_disc: float = sqrt(discriminant)
	var inv_2a: float = 1.0 / (2.0 * a)
	var t0: float = (-b - sqrt_disc) * inv_2a
	var t1: float = (-b + sqrt_disc) * inv_2a

	# Choose the nearest positive intersection (front face when camera is outside)
	var t: float = -1.0
	if t0 > 0.001:
		t = t0
	if t1 > 0.001 and (t < 0.0 or t1 < t):
		t = t1

	if t < 0.0 or t > 8000.0:
		return Vector3.ZERO

	var hit: Vector3 = center + dir * t

	# Final front-side guard: reject only true back-side hits (very negative dot)
	# We allow quite negative values because clicks on the sides of the visible globe
	# can legitimately have dot ≈ -0.7 … -0.95
	var to_cam: Vector3 = (from - center).normalized()
	var to_hit: Vector3 = (hit - center).normalized()
	if to_hit.dot(to_cam) < -0.95:
		print("[Camera][Raycast] Rejected back-side hit (dot = ", to_hit.dot(to_cam), ")")
		return Vector3.ZERO

	return hit