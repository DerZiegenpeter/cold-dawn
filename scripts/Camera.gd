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

@export var rivers_lakes_fade_start: float = 380.0
@export var rivers_lakes_fade_end: float = 180.0

var yaw: float = 30.0
var pitch: float = 15.0
var distance: float = 1400.0
var target_yaw: float = 30.0
var target_pitch: float = 15.0
var target_distance: float = 1400.0

var is_dragging := false
var last_mouse_pos := Vector2.ZERO

@onready var globe: Node3D = get_node_or_null("../Globe")

func _ready() -> void:
	if not target:
		target = get_node_or_null("../Globe")
	distance = start_distance
	target_distance = start_distance
	_update_position()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = event.pressed
			last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_distance = max(min_distance, target_distance * 0.96)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_distance = min(max_distance, target_distance * 1.04)

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
		_fade_coastlines_vs_states()
		_fade_layer("States", states_fade_start, states_fade_end)
		_fade_layer("Cities", states_fade_start, states_fade_end)
		_fade_layer("Rivers", rivers_lakes_fade_start, rivers_lakes_fade_end)
		_fade_layer("Lakes", rivers_lakes_fade_start, rivers_lakes_fade_end)

func _fade_coastlines_vs_states() -> void:
	var coast := globe.get_node_or_null("Coastlines")
	if not coast: return
	var mat := coast.material_override as StandardMaterial3D
	if not mat: return

	var alpha := 1.0
	if distance < 550:
		alpha = 0.0
	elif distance < 900:
		var t := (distance - 550) / (900 - 550)
		alpha = clamp(t, 0.0, 1.0)

	var col = mat.albedo_color
	col.a = lerp(col.a, alpha, 0.15)
	mat.albedo_color = col

func _fade_layer(layer_name: String, fade_start: float, fade_end: float) -> void:
	var layer := globe.get_node_or_null(layer_name)
	if not layer or not layer is MeshInstance3D: return

	var mat := layer.material_override as StandardMaterial3D
	if not mat: return

	var alpha := 1.0
	if distance > fade_start:
		alpha = 0.0
	elif distance < fade_end:
		alpha = 1.0
	else:
		var t := (fade_start - distance) / (fade_start - fade_end)
		alpha = clamp(t, 0.0, 1.0)

	# Wichtiger Fix: Sichere Methode + aggressives Blenden
	var col = mat.albedo_color
	col.a = lerp(col.a, alpha, 0.4)

	# Hard Override: Wenn sehr nah → sofort voll sichtbar
	if distance < fade_end + 30:
		col.a = 1.0

	mat.albedo_color = col

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
