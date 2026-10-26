class_name CalibrationTargetSpawner
extends TargetSpawner
## Spawns one target at a time, always fully inside the player's view, and
## works through a list of stages. Each stage keeps its targets in one zone of
## the screen (see calibration_stage.gd) and ends after a set number of hits.
## Positions are picked on screen at the moment a target spawns, so they are
## relative to wherever the player is aiming. When the last stage is done it
## emits [signal finished], which the Scenario passes on to end the round.

signal stage_started(index: int, stage: Resource)
signal stage_progress(hits: int, hits_required: int)
signal stage_completed(index: int, stage: Resource)
signal finished ## When the last stage is completed

# Preloaded instead of using the class name, so this script works even before
# the editor has registered the new class
const Stage := preload("res://modules/gameplay_manager/calibration/calibration_stage.gd")

const MAX_SPAWN_ATTEMPTS: int = 300
## Pixels kept between a target and any UI area
const UI_PADDING: float = 12.0

## Stages, in the order they are played
@export var stages: Array[Stage] = []
## Seconds with no target on screen between two stages (shots fired in between
## count as misses)
@export_range(0.0, 10.0, 0.1, "suffix:s") var stage_break: float = 0.0

@export_group("Screen zones")
## Strip along every screen edge that targets never touch, as a fraction of
## the screen height
@export_range(0.0, 0.25, 0.005) var edge_margin: float = 0.05
## Width of the outer zone, measured inward from the edge margin, as a fraction
## of the screen height
@export_range(0.05, 0.5, 0.005) var outer_zone_width: float = 0.2
## Radius of the center zone around the crosshair, as a fraction of the screen
## height
@export_range(0.02, 0.5, 0.005) var center_zone_radius: float = 0.15
## Center-zone targets spawn at least this far from the crosshair, so there is
## always some aiming to do
@export_range(0.0, 0.2, 0.005) var center_zone_min_offset: float = 0.03

@export_group("Play area")
## Targets stay within this angle left or right of the direction this node
## faces (-Z), so the view doesn't drift away over many flicks
@export_range(10.0, 180.0, 1.0, "degrees") var max_yaw: float = 90.0
## Targets stay within this angle above or below the horizon
@export_range(10.0, 85.0, 1.0, "degrees") var max_pitch: float = 50.0
## Once the view has turned past this fraction of the play area, new targets
## are placed back toward the middle
@export_range(0.0, 1.0, 0.05) var recenter_after: float = 0.5

## Returns the screen areas covered by UI as an Array[Rect2] in viewport
## coordinates. Targets are never placed underneath them.
var ui_areas_provider: Callable = Callable()

var _rng := RandomNumberGenerator.new()
var _stage_index: int = -1
var _hits_in_stage: int = 0
var _current_target: Target = null
var _last_target_position: Vector3
var _has_last_target: bool = false
var _break_timer: Timer

func _ready() -> void:
	# Unlike TargetSpawner, nothing spawns until start() is called
	_rng.randomize()
	if behavior == null:
		behavior = TargetMovementBehaviorStatic.new()
	_break_timer = Timer.new()
	_break_timer.one_shot = true
	_break_timer.timeout.connect(_on_break_timer_timeout)
	add_child(_break_timer)
	# Deferred so the Scenario has spawned the player (and its camera) first
	start.call_deferred()

## Starts the first stage
func start() -> void:
	if stages.is_empty():
		push_warning("CalibrationTargetSpawner has no stages.")
		finished.emit()
		return
	_start_stage(0)

## True while a target is waiting to be shot
func has_active_target() -> bool:
	return _current_target != null

func get_stage_count() -> int:
	return stages.size()

func _start_stage(index: int) -> void:
	_stage_index = index
	_hits_in_stage = 0
	var stage: Stage = stages[index]
	size = Vector2(stage.target_radius, stage.target_radius * 2.0) # a sphere
	stage_started.emit(index, stage)
	stage_progress.emit(0, stage.hits_required)
	_spawn_target()

func _spawn_target() -> void:
	var target: Target = _packed_target.instantiate()
	target.init(size, behavior.duplicate(), health, shape)
	target.destroyed.connect(_on_target_destroyed)
	target.hitted.connect(_on_target_hitted)
	target.position = _get_valid_target_spawn_position()
	add_child(target)
	_current_target = target

func _on_target_destroyed() -> void:
	if is_instance_valid(_current_target):
		_last_target_position = _current_target.global_position
		_has_last_target = true
	_current_target = null
	target_destroyed.emit()

	var stage: Stage = stages[_stage_index]
	_hits_in_stage += 1
	stage_progress.emit(_hits_in_stage, stage.hits_required)
	if _hits_in_stage < stage.hits_required:
		_spawn_target()
		return

	stage_completed.emit(_stage_index, stage)
	if _stage_index + 1 >= stages.size():
		finished.emit()
	elif stage_break > 0.0:
		_break_timer.start(stage_break)
	else:
		_start_stage(_stage_index + 1)

func _on_break_timer_timeout() -> void:
	_start_stage(_stage_index + 1)

## Picks a spot for the next target: inside the current stage's screen zone,
## fully on screen and clear of the UI, far enough from the previous target and
## inside the play area. Returns it in this node's local space.
func _get_valid_target_spawn_position() -> Vector3:
	var stage: Stage = stages[_stage_index]
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		push_warning("No camera to place calibration targets with.")
		return Vector3(0, 0, -stage.target_distance)

	var screen := get_viewport().get_visible_rect().size
	var ui_areas: Array[Rect2] = []
	if ui_areas_provider.is_valid():
		ui_areas.assign(ui_areas_provider.call())
	var min_last_distance := stage.min_distance_from_last * screen.y
	var check_last := _has_last_target and min_last_distance > 0.0 \
		and not camera.is_position_behind(_last_target_position)
	var last_on_screen := camera.unproject_position(_last_target_position) if check_last else Vector2.ZERO
	var view_offset := _get_play_area_offset(camera.global_position,
		camera.global_position - camera.global_basis.z)

	var best_position := Vector3.ZERO
	var best_penalty := INF
	for _attempt: int in range(MAX_SPAWN_ATTEMPTS):
		var point := _get_random_point_near_zone(stage.zone, screen)
		if not _is_point_in_zone(point, stage.zone, screen):
			continue
		var world_position := camera.project_ray_origin(point) \
			+ camera.project_ray_normal(point) * stage.target_distance
		if not _is_target_visible(camera, world_position, stage.target_radius, screen, ui_areas):
			continue

		# Soft rules, most important first: bend them rather than fail
		var penalty := 0.0
		if check_last and point.distance_to(last_on_screen) < min_last_distance:
			penalty += 1000.0
		var offset := _get_play_area_offset(camera.global_position, world_position)
		if offset > 1.0:
			penalty += 100.0 + offset
		elif view_offset > recenter_after and offset >= view_offset:
			penalty += 1.0
		if penalty < best_penalty:
			best_penalty = penalty
			best_position = world_position
			if penalty == 0.0:
				break

	if best_penalty == INF:
		# Zones don't fit this screen (e.g. a very small window): aim straight ahead
		push_warning("No valid calibration target position found, spawning at the crosshair.")
		best_position = camera.global_position - camera.global_basis.z * stage.target_distance
	return to_local(best_position)

## Random point in an area that contains the zone (checked afterwards)
func _get_random_point_near_zone(zone: Stage.Zone, screen: Vector2) -> Vector2:
	var margin := edge_margin * screen.y
	var outer_limit := (edge_margin + outer_zone_width) * screen.y
	match zone:
		Stage.Zone.INTERMEDIATE:
			return Vector2(
				_rng.randf_range(outer_limit, screen.x - outer_limit),
				_rng.randf_range(outer_limit, screen.y - outer_limit))
		Stage.Zone.CENTER:
			var min_radius := center_zone_min_offset * screen.y
			var max_radius := center_zone_radius * screen.y
			# sqrt keeps points evenly spread over the ring's area
			var radius := sqrt(_rng.randf_range(min_radius * min_radius, max_radius * max_radius))
			return screen / 2.0 + Vector2.from_angle(_rng.randf() * TAU) * radius
		_:
			return Vector2(
				_rng.randf_range(margin, screen.x - margin),
				_rng.randf_range(margin, screen.y - margin))

func _is_point_in_zone(point: Vector2, zone: Stage.Zone, screen: Vector2) -> bool:
	var edge_distance := _get_edge_distance(point, screen)
	var center_distance := point.distance_to(screen / 2.0)
	var outer_limit := (edge_margin + outer_zone_width) * screen.y
	match zone:
		Stage.Zone.OUTER:
			return edge_distance >= edge_margin * screen.y and edge_distance <= outer_limit
		Stage.Zone.INTERMEDIATE:
			return edge_distance > outer_limit and center_distance > center_zone_radius * screen.y
		Stage.Zone.CENTER:
			return center_distance >= center_zone_min_offset * screen.y \
				and center_distance <= center_zone_radius * screen.y
	return false

## True if the whole target, not just its center, stays clear of the edge
## margin and of every UI area
func _is_target_visible(camera: Camera3D, world_position: Vector3, radius: float,
		screen: Vector2, ui_areas: Array[Rect2]) -> bool:
	if camera.is_position_behind(world_position):
		return false
	var center := camera.unproject_position(world_position)
	var pixel_radius := 0.0
	for i: int in range(8):
		var angle := TAU * i / 8.0
		var offset := (camera.global_basis.x * cos(angle) + camera.global_basis.y * sin(angle)) * radius
		pixel_radius = maxf(pixel_radius, camera.unproject_position(world_position + offset).distance_to(center))
	if _get_edge_distance(center, screen) - pixel_radius < edge_margin * screen.y:
		return false
	for area: Rect2 in ui_areas:
		if area.grow(pixel_radius + UI_PADDING).has_point(center):
			return false
	return true

## How far a position is from the middle of the play area: 0 straight ahead,
## 1 on its border, more than 1 outside it
func _get_play_area_offset(from: Vector3, world_position: Vector3) -> float:
	var direction := global_basis.inverse() * (world_position - from).normalized()
	var yaw := rad_to_deg(atan2(direction.x, -direction.z))
	var pitch := rad_to_deg(asin(clampf(direction.y, -1.0, 1.0)))
	return maxf(absf(yaw) / max_yaw, absf(pitch) / max_pitch)

func _get_edge_distance(point: Vector2, screen: Vector2) -> float:
	return minf(minf(point.x, screen.x - point.x), minf(point.y, screen.y - point.y))
