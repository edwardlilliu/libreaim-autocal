extends SceneTree
## Controller calibration geometry and real physics-shot regression checks.
## Run with disposable saves through run-controller-aim-tests.ps1.

const Benchmark = preload("res://modules/gameplay_manager/calibration/sensitivity_benchmark.gd")
var AimScene: PackedScene
var Crosshair: Script

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func shoot_target(flow, radius_offset: float) -> void:
	var camera: Camera3D = flow._player.get_node("Head/Camera3D")
	var target = flow._spawner._current_target
	var radius: float = flow._spawner.stages[flow._spawner._stage_index].target_radius
	target.global_position = camera.global_position - camera.global_basis.z * 8.0 \
		+ camera.global_basis.x * radius * radius_offset
	await physics_frame
	await physics_frame
	flow._player._shoot(1.0)
	await settle()

func run() -> void:
	# Load scene scripts after project autoloads have entered the tree.
	AimScene = load("res://assets/default_data/custom_resources/calibrations/aim_test/scenario.tscn")
	Crosshair = load("res://modules/shared/crosshair.gd")
	for value in [null, "22", {}, [], Vector2.ZERO, NAN, INF, -INF, 0.0, -5.0]:
		check(is_equal_approx(Benchmark.resolve_speed(value), 180.0), "invalid or missing speed uses independent default: %s" % str(value))
	check(is_equal_approx(Benchmark.resolve_speed(22.0), 22.0), "explicit slow speed remains unchanged")
	check(is_equal_approx(Benchmark.resolve_speed(240), 240.0), "integer speed is accepted")
	check(is_equal_approx(Benchmark.resolve_speed(0.5), 1.0), "positive speeds clamp to lower bound")
	check(is_equal_approx(Benchmark.resolve_speed(900.0), 720.0), "speed clamps to upper bound")
	check(Benchmark.candidates(22.0) == [22.0, 144.0, 216.0], "very low baseline compares practical alternatives")
	check(Benchmark.candidates(100.0) == [100.0, 80.0, 120.0], "normal baseline retains neighboring candidates")
	var saves = root.get_node("SaveManager")
	saves.settings.get_file().erase_section_key("controls", "controller_sensitivity")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var flow = load("res://tests/simulated_sensitivity_calibration.gd").new()
	viewport.add_child(flow)
	await settle()
	var crosshair: Control = flow._hud.get_node_or_null("Crosshair")
	check(is_instance_valid(crosshair), "sensitivity uses a named shared crosshair")
	if not is_instance_valid(crosshair):
		print("CONTROLLER AIM TESTS: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	check(crosshair.get_script() == Crosshair, "sensitivity uses the same crosshair renderer as normal Play")
	for resolution in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(1024, 768)]:
		viewport.size = resolution
		await settle()
		check(crosshair.global_position.is_equal_approx(Vector2(resolution) / 2.0), "crosshair drawing origin stays centered at %s" % str(resolution))
		check(crosshair.size.is_equal_approx(Vector2.ZERO), "crosshair has no font-box offset at %s" % str(resolution))
	viewport.size = Vector2i(1920, 1080)
	flow._device = -1
	flow._baseline = 180.0
	flow._queue.assign([{"speed": 180.0, "seed": 4815}, {"speed": 216.0, "seed": 4815}])
	flow._practice = false
	flow._start_round()
	await settle()
	flow._player._movement_enabled = false
	for value in [null, 22.0, 240.0, "bad", NAN]:
		if value == null:
			if saves.settings.get_file().has_section_key("controls", "controller_sensitivity"):
				saves.settings.get_file().erase_section_key("controls", "controller_sensitivity")
		else:
			saves.settings.set_data("controls", "controller_sensitivity", value)
		var expected := Benchmark.resolve_speed(value)
		check(is_equal_approx(flow._saved_speed(), expected), "sensitivity setup resolves %s consistently" % str(value))
		check(is_equal_approx(flow._player.get_controller_sensitivity(), expected), "normal player resolves %s consistently" % str(value))
	saves.settings.set_data("controls", "controller_sensitivity", 180.0)
	flow._player.controller_only = false
	flow._player.controller_sensitivity_override = -1.0
	var initial_yaw: float = flow._player.rotation.y
	Input.action_press("look_right", 1.0)
	flow._player._handle_joypad_rotation(0.25)
	Input.action_release("look_right")
	check(is_equal_approx(absf(rad_to_deg(flow._player.rotation.y - initial_yaw)), 45.0), "default full-stick speed turns 45 degrees in a quarter second")
	flow._player.controller_only = true
	flow._player.controller_sensitivity_override = 180.0
	var original = AimScene.instantiate()
	var original_stages = original.get_node("CalibrationTargetSpawner").stages
	var measured_radii: Array[float] = []
	for i in range(3):
		var stage = flow._spawner.stages[i]
		var source = original_stages[i]
		measured_radii.append(stage.target_radius)
		check(stage != source, "stage %d is a private calibration resource" % i)
		check(is_equal_approx(stage.target_radius, maxf(source.target_radius, source.target_distance * 0.035)), "stage %d has a controller-friendly visible target" % i)
	check(is_equal_approx(original_stages[2].target_radius, 0.25), "original aim-test precision target is unchanged")
	original.free()
	var camera: Camera3D = flow._player.get_node("Head/Camera3D")
	var ray: RayCast3D = camera.get_node("RayCast3D")
	var ray_direction := (ray.to_global(ray.target_position) - ray.global_position).normalized()
	check(ray_direction.dot(-camera.global_basis.z) > 0.9999, "shooting ray points through the visible center")
	await shoot_target(flow, 1.4)
	check(flow._hits == 0 and flow._shots == 1, "shot outside visible target misses")
	await shoot_target(flow, 0.0)
	check(flow._hits == 1 and flow._shots == 2, "visible target center registers a real physics hit")
	await shoot_target(flow, 0.8)
	check(flow._hits == 2 and flow._shots == 3, "near visible target edge registers a real physics hit")
	for hit in range(2, Benchmark.TARGET_COUNT):
		check(flow._spawner._stage_index == hit / Benchmark.HITS_PER_STAGE, "real shots progress through stage for hit %d" % hit)
		await shoot_target(flow, 0.0)
	check(flow._search_results.size() == 1, "nine real hits complete the measured round")
	if flow._search_results.size() == 1:
		check(flow._search_results[0].hits == 9 and flow._search_results[0].shots == 10, "measurement records real hits and misses")
		check(is_equal_approx(flow._search_results[0].accuracy, 0.9), "measurement accuracy reflects actual raycast results")
	flow._start_round()
	await settle()
	for i in range(3):
		check(is_equal_approx(flow._spawner.stages[i].target_radius, measured_radii[i]), "candidate %d uses the same target geometry" % i)
	flow._clear_round()
	saves.settings.set_data("controls", "controller_sensitivity", 22.0)
	flow._reset_speed()
	check(is_equal_approx(flow._saved_speed(), 180.0), "reset button replaces old slow setting")
	saves.settings.load_data()
	check(is_equal_approx(flow._saved_speed(), 180.0), "reset speed survives reloading saves")
	viewport.queue_free()
	await settle()
	print("CONTROLLER AIM TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
