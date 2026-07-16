extends Node

## CameraSystem
## Reine Kamera-Logik (Orbit, Zoom, Smoothing). Keine Input- oder Spiel-Logik.

@export var start_distance: float = 1400.0
@export var min_distance: float = 505.0
@export var max_distance: float = 2200.0
@export var sensitivity: float = 0.11
@export var smoothness: float = 11.0

var yaw: float = 30.0
var pitch: float = 15.0
var distance: float = 1400.0
var target_yaw: float = 30.0
var target_pitch: float = 15.0
var target_distance: float = 1400.0

var target: Node3D

func _ready() -> void:
	if not target:
		target = get_node_or_null("../Globe")
	distance = start_distance
	target_distance = start_distance

func update_camera(delta: float) -> void:
	var t: float = clampf(smoothness * delta, 0.0, 1.0)
	yaw = lerp(yaw, target_yaw, t)
	pitch = lerp(pitch, target_pitch, t)
	distance = lerp(distance, target_distance, t * 0.65)
	_update_position()

func _update_position() -> void:
	if not target: return
	var dir := Vector3(
		cos(deg_to_rad(yaw)) * cos(deg_to_rad(pitch)),
		sin(deg_to_rad(pitch)),
		 sin(deg_to_rad(yaw)) * cos(deg_to_rad(pitch))
	).normalized()
	global_position = target.global_position + dir * distance
	look_at(target.global_position, Vector3.UP)

func add_yaw(delta: float) -> void:
	target_yaw += delta

func add_pitch(delta: float) -> void:
	target_pitch += delta

func zoom_in(factor: float = 0.96) -> void:
	target_distance = max(min_distance, target_distance * factor)

func zoom_out(factor: float = 1.04) -> void:
	target_distance = min(max_distance, target_distance * factor)

func set_target(new_target: Node3D) -> void:
	target = new_target
