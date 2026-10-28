extends SceneTree
## Run against a disposable user-data directory; never a player's normal saves.
const Benchmark = preload("res://modules/gameplay_manager/calibration/sensitivity_benchmark.gd")
var Flow: Script

var failures: int = 0
var checks: int = 0

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

func measurement(speed: float, seconds: float, shots: int = 9, hits: int = 9) -> Dictionary:
	var times: Array[float] = []
	return Benchmark.result(speed, seconds, shots, hits, times)

func run() -> void:
	Flow = load("res://modules/gameplay_manager/sensitivity_calibration.gd")
	var original := measurement(100, 20)
	var faster := measurement(120, 17)
	check(Benchmark.improves(faster, original), "faster accurate candidate wins")
	check(not Benchmark.improves(measurement(120, 17, 12), original), "accuracy loss rejects candidate")
	check(not Benchmark.improves(measurement(120, 19.5), original), "small gain keeps baseline")
	check(not Benchmark.improves(measurement(120, 10, 8, 8), original), "incomplete round rejected")
	check(not Benchmark.improves(measurement(120, 0), original), "zero-time round rejected")
	check(not Benchmark.improves(measurement(120, 76), original), "timeout rejected")
	check(not Benchmark.improves(measurement(120, 17, 0), original), "missing shot data rejected")
	var results: Array[Dictionary] = [measurement(80, 24), faster, original]
	check(Benchmark.choose(results, 100).speed == 120, "choose independent of trial order")
	check(Benchmark.choose(results, 90).is_empty(), "missing baseline rejects recommendation")
	check(Benchmark.candidates(1).size() == 2 and Benchmark.candidates(720).size() == 2, "boundary candidates deduplicated")
	check(not Benchmark.improves(measurement(120, 21), original), "failed holdout does not validate")
	var saves = root.get_node("SaveManager")
	saves.settings.set_data("controls", "controller_sensitivity", 100.0)
	var global = root.get_node("Global")
	global.current_scenario = global.scenarios["random"]
	var flow = load("res://tests/simulated_sensitivity_calibration.gd").new()
	root.add_child(flow)
	current_scene = flow
	await settle()
	check(flow._phase == Flow.Phase.SETUP, "setup screen opens")
	check(flow._start_button.disabled == Input.get_connected_joypads().is_empty(), "start gated on physical controller")
	flow._manual_speed.get_line_edit().text = "110.0"
	flow._save_manual()
	check(is_equal_approx(float(saves.settings.get_data("controls", "controller_sensitivity")), 110.0), "manual text entry applies and saves")
	saves.settings.set_data("controls", "controller_sensitivity", 100.0)
	flow._show_setup()
	flow._device = 0
	flow._baseline = 100.0
	flow._session_seed = 12345
	flow._queue.assign([{"speed": 100.0, "seed": 12345}, {"speed": 80.0, "seed": 12345}, {"speed": 120.0, "seed": 12345}])
	flow._show_ready()
	var rounds := 0
	while flow._phase != Flow.Phase.RESULTS and rounds < 12:
		flow._start_round()
		await settle()
		check(is_instance_valid(flow._player), "round creates player")
		check(flow._player.controller_only, "benchmark accepts only selected controller")
		check(is_equal_approx(flow._player.controller_sensitivity_override, float(flow._queue[flow._index].speed)), "trial speed applied temporarily")
		var mouse := InputEventMouseMotion.new()
		mouse.screen_relative = Vector2(80, 0)
		var old_rotation: Vector3 = flow._player.rotation
		flow._player._input(mouse)
		check(flow._player.rotation.is_equal_approx(old_rotation), "mouse cannot contaminate benchmark")
		if rounds == 0:
			flow._pause_round()
			var elapsed: float = flow._elapsed
			flow._process(5.0)
			check(flow._elapsed == elapsed and flow._phase == Flow.Phase.PAUSED, "paused time excluded")
			flow._resume_round()
			check(flow._phase == Flow.Phase.RUNNING, "resume restores round")
		var total := 3 if flow._practice else Benchmark.TARGET_COUNT
		var speed: float = flow._queue[flow._index].speed
		var duration := 17.0 if is_equal_approx(speed, 120.0) else (24.0 if is_equal_approx(speed, 80.0) else 20.0)
		if flow._validation:
			duration = 16.0 if is_equal_approx(speed, 120.0) else 20.0
		for hit in range(total):
			flow._elapsed = duration * (hit + 1.0) / total
			flow._player.shooted.emit()
			flow._spawner._current_target._on_target_shape_manager_hitted(1.0)
			await settle()
		check(saves.settings.get_data("controls", "controller_sensitivity") == 100.0, "trial never changes saved setting")
		rounds += 1
	check(rounds == 10, "3 search and 2 holdout rounds, each with practice")
	check(flow._search_results.size() == 3 and flow._validation_results.size() == 2, "search and holdout measurements separate")
	check(flow._validated and flow._recommendation.speed == 120, "full flow validates winning candidate")
	flow._apply_recommendation()
	check(saves.settings.get_data("controls", "controller_sensitivity") == 120.0, "apply persists winner")
	var profile: Dictionary = saves.settings.get_data("controls", "sensitivity_profile")
	check(profile.validated and profile.validation.size() == 2, "profile retains validation evidence")
	saves.settings.load_data()
	check(saves.settings.get_data("controls", "controller_sensitivity") == 120.0, "applied setting survives reload from disk")
	flow._baseline = 100.0
	flow._validation_results.assign([measurement(100, 20), measurement(120, 22)])
	flow._evaluate_validation()
	check(not flow._validated and flow._phase == Flow.Phase.RESULTS, "failed holdout shows no recommendation")
	var before: float = saves.settings.get_data("controls", "controller_sensitivity")
	flow._queue.assign([{"speed": 140.0, "seed": 12}])
	flow._index = 0
	flow._practice = true
	flow._start_round()
	await settle()
	flow._on_controller_changed(9, false)
	check(flow._phase == Flow.Phase.RUNNING, "unrelated controller disconnect does not stop trial")
	flow._on_controller_changed(0, false)
	check(flow._phase == Flow.Phase.INTERRUPTED and not is_instance_valid(flow._scenario), "disconnect discards active round")
	check(saves.settings.get_data("controls", "controller_sensitivity") == before, "disconnect preserves saved setting")
	flow._cancel()
	check(flow._phase == Flow.Phase.SETUP, "cancel returns to setup")
	flow._start_round()
	await settle()
	flow._process(76.0)
	check(flow._phase == Flow.Phase.INTERRUPTED, "timeout interrupts instead of recommending")
	flow._validated = false
	flow._recommendation = faster
	flow._apply_recommendation()
	check(saves.settings.get_data("controls", "controller_sensitivity") == before, "unvalidated recommendation cannot be applied")
	flow._clear_round()
	flow.queue_free()
	await settle()
	check(global.current_scenario.id == "random", "previous scenario restored on exit")
	# Existing Play and live mouse sensitivity must continue to work.
	change_scene_to_file(global.GAMEPLAY_MANAGER_PATH)
	await settle()
	var player = current_scene._scenario.get_player()
	saves.settings.set_data("controls", "sensitivity", 2.0)
	check(is_equal_approx(player._mouse_sensitivity, player._get_mouse_sensitivity()), "mouse sensitivity changes immediately")
	check(is_equal_approx(player.get_controller_sensitivity(), 120.0), "normal gameplay reads independent controller speed")
	Input.joy_connection_changed.emit(0, true)
	await settle()
	check(current_scene.get_node("GameplayUI/GameplayUI/ControllerMessage").text == "Controller connected", "controller event handler accepts two arguments")
	change_scene_to_file(global.MAIN_MENU_PATH)
	await settle()
	var selection = current_scene.get_node("RightControl/SelectCalibration")
	selection._select_calibration("sensitivity")
	selection._start_calibration()
	await settle()
	check(current_scene.scene_file_path.ends_with("sensitivity_calibration.tscn"), "menu routes sensitivity to new flow")
	print("SENSITIVITY TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
