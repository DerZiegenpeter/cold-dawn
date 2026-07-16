extends Camera3D
class_name OrbitalCamera

## Camera.gd
## Dünne Wrapper-Klasse. Die eigentliche Logik liegt in CameraSystem + InputSystem.

@onready var camera_system: CameraSystem = get_node("/root/CameraSystem")

func _ready() -> void:
	camera_system.set_target(get_node_or_null("../Globe"))

func _process(delta: float) -> void:
	camera_system.update_camera(delta)

	# Optional: Fade-Logik hier oder ausgelagert lassen
	if get_node_or_null("../Globe"):
		# Fade-Logik kann später in FadeManager ausgelagert werden
		pass
