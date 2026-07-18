extends Node

## MovementSystem - Komplett neu & optimiert (elegant + performant)
## - Saubere interne Pfadverwaltung + volle Abwärtskompatibilität zu Meta (für bestehende Entities)
## - Robuster, glatter Path-Following mit Multi-Waypoint-Advance pro Frame (smoother, kein Ruckeln/Stuck)
## - Explizite clear_path() Funktion (fixt alle Aufrufe in Ground/Air/NavalEntity)
## - Bessere Viz-Logik (weniger Leaks, nur für aktuell selected)
## - Konstante exakte Winkelgeschwindigkeit (sofort volle Speed, kein Anfahren)
## - Domain-Checks nur wo nötig + Safety-Net
## - Viel lesbarer, dokumentierter Code, weniger Duplikate

signal path_completed(entity: Node3D)

@export var ground_speed: float = 1.4          # rad/s (angular on sphere)
@export var naval_speed: float = 1.6
@export var air_speed: float = 2.8

var _current_visualized_entity: Node = null
var _visual_path: MeshInstance3D = null

# Interne elegante Verwaltung (schneller Zugriff, weniger Meta-Overhead)
var _active_paths: Dictionary = {}  # Node3D -> {"path": Array[Vector3], "index": int}


func request_move(entity: Node3D, target_pos: Vector3) -> void:
	if not is_instance_valid(entity):
		return

	print("[Movement] request_move called for ", entity, " to ", target_pos)

	var etype: String = _get_entity_type(entity)
	var on_land: bool = LandSystem and LandSystem.is_position_on_land(target_pos)

	# Domain Pre-Check (sofortige Ablehnung ungültiger Ziele)
	if etype == "ground" and not on_land:
		print("[Movement] Blocked: Ground unit cannot move to water (no state/land)")
		return
	if etype == "naval" and on_land:
		print("[Movement] Blocked: Naval unit cannot move to land/state")
		return

	# Path generieren (PathfindingSystem macht Domain-aware Detours für Ground/Naval)
	var path: Array[Vector3] = []
	if has_node("/root/PathfindingSystem"):
		path = get_node("/root/PathfindingSystem").generate_path(entity, target_pos)
	else:
		path = _generate_direct_fallback(entity.global_position, target_pos)

	if path.is_empty():
		print("[Movement] No path generated")
		return

	_apply_path(entity, path)


func update_movement(entity: Node3D, delta: float) -> void:
	if not is_instance_valid(entity):
		return

	# Hole Path-Daten (intern bevorzugt, Meta als Fallback für Kompatibilität)
	var path_data: Dictionary = _active_paths.get(entity, {})
	var path: Array[Vector3]
	var idx: int

	if not path_data.is_empty():
		path = path_data.path
		idx = path_data.index
	else:
		if not entity.has_meta("current_path") or not entity.has_meta("current_path_index"):
			return
		path = entity.get_meta("current_path")
		idx = entity.get_meta("current_path_index")

	if idx >= path.size():
		_complete_path(entity)
		return

	var current: Vector3 = entity.global_position
	var etype: String = _get_entity_type(entity)
	var speed: float = ground_speed
	if etype == "naval":
		speed = naval_speed
	elif etype == "air":
		speed = air_speed

	var angular_step: float = speed * delta

	# === ROBUSTER & GLATTER FOLLOWING ===
	# While-Loop: Advance so viele Waypoints wie möglich in diesem Frame
	# -> glattes, ruckelfreies Bewegen auch bei hohen Deltas oder schnellen Einheiten
	# -> verhindert "Laggy" Gefühl und Stuck an Waypoints
	while idx < path.size():
		var target: Vector3 = path[idx]
		var current_dir: Vector3 = current.normalized()
		var target_dir: Vector3 = target.normalized()
		var angle: float = current_dir.angle_to(target_dir)

		if angle <= angular_step + 0.0005:  # Erreicht oder übersprungen
			current = target
			entity.global_position = current
			idx += 1
			angular_step -= angle  # Rest für nächsten Waypoint
			if idx >= path.size():
				_complete_path(entity)
				return
			continue
		else:
			# Noch nicht am aktuellen Target -> slerp mit exaktem angular_step
			var t: float = clampf(angular_step / max(angle, 0.0001), 0.0, 1.0)
			var new_dir: Vector3 = current_dir.slerp(target_dir, t)
			var new_pos: Vector3 = new_dir * current.length()

			# Domain Safety-Net (nur bei Ground/Naval relevant)
			var on_land: bool = LandSystem and LandSystem.is_position_on_land(new_pos)
			if (etype == "ground" and not on_land) or (etype == "naval" and on_land):
				_complete_path(entity, true)
				print("[Movement] Stopped - left valid domain during movement")
				return

			entity.global_position = new_pos
			break  # In diesem Frame fertig

	# Sync zurück (intern + Meta für Entity-Checks)
	_sync_path(entity, path, idx)


func _sync_path(entity: Node3D, path: Array[Vector3], idx: int) -> void:
	_active_paths[entity] = {"path": path, "index": idx}
	entity.set_meta("current_path", path)
	entity.set_meta("current_path_index", idx)


func _complete_path(entity: Node3D, stopped_invalid: bool = false) -> void:
	_active_paths.erase(entity)
	if is_instance_valid(entity):
		if entity.has_meta("current_path"):
			entity.remove_meta("current_path")
		if entity.has_meta("current_path_index"):
			entity.remove_meta("current_path_index")
		_hide_path_visualization()
	if not stopped_invalid:
		path_completed.emit(entity)


func clear_path(entity: Node3D) -> void:
	"""NEU: Explizite Clear-Funktion. Fixt alle Aufrufe in GroundEntity/AirEntity/NavalEntity."""
	if not is_instance_valid(entity):
		return
	_active_paths.erase(entity)
	if entity.has_meta("current_path"):
		entity.remove_meta("current_path")
	if entity.has_meta("current_path_index"):
		entity.remove_meta("current_path_index")
	if _current_visualized_entity == entity:
		_hide_path_visualization()
		_current_visualized_entity = null


func has_active_path(entity: Node3D) -> bool:
	if not is_instance_valid(entity):
		return false
	return _active_paths.has(entity) or entity.has_meta("current_path")


func _get_entity_type(entity: Node) -> String:
	if entity.get("data") != null and entity.data is Dictionary and entity.data.has("type"):
		return str(entity.data["type"])
	if entity is AirEntity:
		return "air"
	if entity is GroundEntity:
		return "ground"
	if entity is NavalEntity:
		return "naval"
	return "ground"


func _apply_path(entity: Node3D, path: Array[Vector3]) -> void:
	_active_paths[entity] = {"path": path, "index": 0}
	entity.set_meta("current_path", path)
	entity.set_meta("current_path_index", 0)
	_current_visualized_entity = entity

	# Viz nur für aktuell selected (vermeidet Leaks)
	var unit_manager := get_node_or_null("/root/UnitManager")
	if unit_manager and unit_manager.selected_entity == entity:
		var globe := entity.get_parent()
		if globe:
			_show_path_visualization(globe, path)


func _generate_direct_fallback(start: Vector3, end: Vector3) -> Array[Vector3]:
	if start.is_equal_approx(end):
		return [end]
	var start_dir: Vector3 = start.normalized()
	var end_dir: Vector3 = end.normalized()
	var angle: float = start_dir.angle_to(end_dir)
	var segments: int = clampi(maxi(8, int(ceil(angle / deg_to_rad(5.0)))), 8, 40)

	var path: Array[Vector3] = []
	var radius: float = start.length()
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var dir: Vector3 = start_dir.slerp(end_dir, t)
		path.append(dir * radius)
	path[path.size() - 1] = end_dir * radius
	return path


func _show_path_visualization(globe: Node, path: Array[Vector3]) -> void:
	_hide_path_visualization()
	if path.size() < 2:
		return

	var immediate := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.6, 1.0)
	mat.emission_energy_multiplier = 2.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for pos in path:
		immediate.surface_add_vertex(pos)
	immediate.surface_end()

	var mi := MeshInstance3D.new()
	mi.mesh = immediate
	mi.name = "PathVisual"
	globe.add_child(mi)
	_visual_path = mi


func _hide_path_visualization() -> void:
	if is_instance_valid(_visual_path):
		_visual_path.queue_free()
	_visual_path = null


# Optional: könnte in _process Viz bei Selection-Change updaten (für zukünftige Erweiterung)
# func _process(_delta: float) -> void:
#     pass
