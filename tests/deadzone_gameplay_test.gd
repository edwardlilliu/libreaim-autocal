extends SceneTree
## Run only through the runner, which isolates the player's saved settings.
const Benchmark = preload("res://modules/gameplay_manager/calibration/deadzone_benchmark.gd")
const PROFILE := {
	"version": 1, "controller_guid": "test-controller", "controller_name": "Test pad",
	"inner": 0.1, "outer": 0.8, "offset": Vector2(0.02, -0.01),
}
var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func make_player():
	var player = load("res://modules/gameplay_manager/player/player.tscn").instantiate()
	player.set_script(load("res://tests/simulated_deadzone_player.gd"))
	root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	return player

func run() -> void:
	var saves = root.get_node("SaveManager")
	if OS.get_cmdline_user_args().has("--verify-reload"):
		var saved: Variant = saves.settings.get_data("controls", "controller_deadzone_profile", {})
		check(Benchmark.is_compatible(saved, "test-controller"), "profile loads in a new Godot process")
		var reloaded = make_player()
		check(reloaded._get_controller_look().is_equal_approx(Vector2(0.5, 0.0)), "restarted gameplay uses saved curve")
		check(is_equal_approx(reloaded.get_controller_sensitivity(), 100.0), "saved sensitivity remains independent")
		reloaded.free()
		finish("DEADZONE RELOAD TESTS")
		return

	check(Benchmark.apply(Vector2(0.02, -0.01), PROFILE).is_zero_approx(), "resting offset produces no drift")
	check(Benchmark.apply(Vector2(0.12, -0.01), PROFILE).is_zero_approx(), "inner boundary produces no movement")
	check(Benchmark.apply(Vector2(0.47, -0.01), PROFILE).is_equal_approx(Vector2(0.5, 0)), "midpoint scales to half speed")
	check(Benchmark.apply(Vector2(0.82, -0.01), PROFILE).is_equal_approx(Vector2.RIGHT), "outer boundary reaches full speed")
	check(is_equal_approx(Benchmark.apply(Vector2.ONE, PROFILE).length(), 1.0), "diagonal input is capped at full speed")
	check(Benchmark.apply(Vector2(NAN, 0), PROFILE).is_zero_approx(), "non-finite stick input cannot move the camera")
	check(Benchmark.apply(Vector2(0.6, 0), {"inner": "bad"}).is_equal_approx(Vector2(0.5, 0)), "bad temporary curve falls back to default")
	check(Benchmark.is_compatible(PROFILE, "test-controller"), "matching controller accepts profile")
	check(not Benchmark.is_compatible(PROFILE, "other-controller"), "different controller rejects profile")
	check(not Benchmark.is_compatible(PROFILE, ""), "unknown controller rejects profile")

	# Exercise the actual calibration save path, then ordinary player input.
	var global = root.get_node("Global")
	global.current_scenario = global.scenarios["random"]
	var flow = load("res://modules/gameplay_manager/calibration/deadzone_calibration.tscn").instantiate()
	root.add_child(flow)
	flow._profile = PROFILE.duplicate(true)
	flow._save_profile(false)
	var saved: Dictionary = saves.settings.get_data("controls", "controller_deadzone_profile")
	check(Benchmark.is_compatible(saved, "test-controller"), "calibration saves a compatible profile")
	check(not saved.verified, "saving without verification does not claim it was verified")
	saves.settings.set_data("controls", "controller_sensitivity", 100.0)
	var player = make_player()
	check(not player.controller_only, "test uses ordinary gameplay mode")
	check(player._get_controller_look().is_equal_approx(Vector2(0.5, 0)), "ordinary Play applies saved deadzone")
	player._handle_joypad_rotation(0.1)
	check(is_equal_approx(player.rotation.y, deg_to_rad(-5.0)), "saved deadzone changes actual camera rotation")
	var mouse := InputEventMouseMotion.new()
	mouse.screen_relative = Vector2(20, 0)
	var before_mouse: float = player.rotation.y
	player._input(mouse)
	check(not is_equal_approx(player.rotation.y, before_mouse), "mouse aiming still works")

	var changed := PROFILE.duplicate(true)
	changed.inner = 0.2
	saves.settings.set_data("controls", "controller_deadzone_profile", changed)
	check(player._get_controller_look().is_equal_approx(Vector2(5.0 / 12.0, 0)), "newly saved profile takes effect without recreating player")
	saves.settings.set_data("controls", "controller_deadzone_profile", saved)
	saves.settings.get_file().set_value("controls", "controller_deadzone_profile", {})
	saves.settings.load_data()
	check(player._get_controller_look().is_equal_approx(Vector2(0.5, 0)), "disk reload restores applied profile")

	flow._profile = changed
	flow._cancel()
	check(saves.settings.get_data("controls", "controller_deadzone_profile") == saved, "cancel does not replace the saved profile")
	flow._device = 17
	flow._phase = flow.Phase.REST
	flow._on_controller_changed(17, false)
	check(flow._phase == flow.Phase.INTERRUPTED, "sampling disconnect interrupts calibration")
	check(saves.settings.get_data("controls", "controller_deadzone_profile") == saved, "sampling disconnect preserves saved profile")

	# The unmatched/default path must keep using the project's action mapping.
	Input.action_press("look_right", 0.4)
	var fallback := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	player.devices.clear()
	check(player._get_controller_look().is_equal_approx(fallback), "disconnected controller cannot contribute stale axes")
	player.devices.assign([23])
	check(player._get_controller_look().is_equal_approx(fallback), "unmatched controller keeps existing input behavior")
	player.guids[23] = "test-controller"
	player.sticks[23] = Vector2(0.47, -0.01)
	check(player._get_controller_look().is_equal_approx(Vector2(0.5, 0)), "reconnected controller can use a different device ID")
	player.devices.assign([17, 23])
	player.guids[23] = "other-controller"
	player.sticks[17] = PROFILE.offset
	player.sticks[23] = Vector2(0, 0.6)
	check(player._get_controller_look().is_equal_approx(Vector2(0, 0.5)), "unmatched second controller uses default deadzone")
	player.sticks[17] = Vector2(0.82, -0.01)
	check(player._get_controller_look().is_equal_approx(Vector2.RIGHT), "stronger controller wins without mixing axes")
	player.devices.assign([17])
	player.sticks[17] = Vector2(0.47, -0.01)

	var original_binding: InputEvent = InputMap.action_get_events("look_right")[0]
	var alternate := InputEventJoypadMotion.new()
	alternate.device = -1
	alternate.axis = JOY_AXIS_LEFT_X
	alternate.axis_value = 1.0
	InputMap.action_erase_events("look_right")
	InputMap.action_add_event("look_right", alternate)
	# Rebinding clears held action state in Godot; supply fresh input.
	Input.action_press("look_right", 0.4)
	check(player._get_controller_look().is_equal_approx(fallback), "custom look bindings are preserved")
	InputMap.action_erase_events("look_right")
	InputMap.action_add_event("look_right", original_binding)
	Input.action_press("look_right", 0.4)

	var invalid: Array = [null, "broken", [], {}, {"version": 1, "controller_guid": "test-controller"}]
	for entry in [
		["inner", "bad"], ["inner", NAN], ["outer", INF], ["inner", -0.2],
		["outer", 0.1], ["outer", 2.0], ["offset", [0.0, 0.0]],
		["offset", Vector2(INF, 0)], ["offset", Vector2(0.5, 0)],
		["version", "1"], ["version", 99], ["controller_guid", ""],
	]:
		var bad := PROFILE.duplicate(true)
		bad[entry[0]] = entry[1]
		invalid.append(bad)
	for bad in invalid:
		saves.settings.set_data("controls", "controller_deadzone_profile", bad)
		check(player._get_controller_look().is_equal_approx(fallback), "invalid saved profile falls back: %s" % str(bad))
	Input.action_release("look_right")
	saves.settings.set_data("controls", "controller_deadzone_profile", saved)
	player.controller_only = true
	player.controller_device = 17
	player.controller_deadzone_profile = Benchmark.DEFAULT_PROFILE.duplicate(true)
	check(player._get_controller_look().is_equal_approx(Benchmark.apply(player.sticks[17], Benchmark.DEFAULT_PROFILE)), "verification uses its temporary default instead of saved profile")
	player.controller_deadzone_profile = PROFILE.duplicate(true)
	check(player._get_controller_look().is_equal_approx(Vector2(0.5, 0)), "verification uses its temporary candidate")
	player.controller_deadzone_profile = {}
	check(player._get_controller_look().is_equal_approx(player._apply_default_look_deadzone(player.sticks[17])), "sensitivity trials retain their original deadzone")
	check(saves.settings.get_data("controls", "controller_deadzone_profile") == saved, "temporary trials never alter the saved profile")
	flow.free()
	player.free()
	finish("DEADZONE TESTS")

func finish(label: String) -> void:
	print("%s: %d checks, %d failures" % [label, checks, failures])
	quit(1 if failures > 0 else 0)
