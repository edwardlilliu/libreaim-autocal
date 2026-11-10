extends SceneTree
## Plays the whole deadzone calibration with a simulated worn controller
## (tests/simulated_controller.gd) and checks the saved profile removes its
## drift. Run through run-deadzone-tests.ps1, which isolates saved settings.
const Benchmark = preload("res://modules/gameplay_manager/calibration/deadzone_benchmark.gd")
const DT := 1.0 / 60.0

var flow
var pad
var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

## Advances the flow frame by frame; [param each] moves the simulated hands
func frames(seconds: float, each: Callable = Callable()) -> void:
	for i in roundi(seconds / DT):
		if each.is_valid():
			each.call(i * DT)
		pad.step(DT)
		flow._process(DT)

func roll(stick: String, seconds := 3.0, turns := 2.0) -> void:
	frames(seconds, func(t: float) -> void: pad.hold(stick, Vector2.from_angle(TAU * turns * t / seconds)))
	pad.release(stick)
	frames(0.5)

func flick(stick: String, direction: int) -> void:
	pad.hold(stick, Vector2.from_angle(TAU * direction / 8.0))
	frames(0.15)
	pad.release(stick)
	frames(0.7)

func pull(trigger: String, seconds_in := 0.6, seconds_out := 0.5) -> void:
	frames(seconds_in, func(t: float) -> void: pad.squeeze(trigger, t / seconds_in))
	frames(seconds_out, func(t: float) -> void: pad.squeeze(trigger, 1.0 - t / seconds_out))
	pad.squeeze(trigger, 0.0)
	frames(0.2)

func new_flow(seed_value: int):
	if flow != null:
		flow.free()
	flow = load("res://modules/gameplay_manager/calibration/deadzone_calibration.tscn").instantiate()
	flow.set_script(load("res://tests/simulated_deadzone_calibration.gd"))
	flow.controller.rng.seed = seed_value
	root.add_child(flow)
	flow.set_process(false)
	pad = flow.controller
	frames(0.1)

func calibrate_sticks() -> void:
	flow._begin_session()
	flow._begin_rest()
	frames(4.2)
	roll("left")
	for d in 8:
		flick("left", d)
	roll("right")
	for d in 8:
		flick("right", d)

func run() -> void:
	var saves = root.get_node("SaveManager")
	saves.settings.set_data("controls", "controller_deadzone_profile", {})

	new_flow(7)
	check(flow._phase == flow.Phase.SETUP, "starts on setup")
	check(flow._picker.get_selected_id() == 17, "connected controller is offered")
	pad.hold("left", Vector2(0.5, 0.5))
	frames(0.2)
	check(flow._view.inputs.left.length() > 0.5, "setup shows live input from the selected controller")
	pad.release("left")
	frames(0.3)

	# Step 1: hands off. Holding a stick is caught.
	flow._begin_session()
	check(flow._phase == flow.Phase.SAMPLE_READY, "session waits for Begin")
	pad.hold("right", Vector2(0.6, 0))
	flow._begin_rest()
	frames(4.2)
	check(flow._phase == flow.Phase.SAMPLE_READY and "right stick" in flow._body.text, "touched stick during hands-off is rejected")
	pad.release("right")
	frames(0.5)
	flow._begin_rest()
	frames(4.2)
	check(flow._phase == flow.Phase.STICK_RANGE and flow._stick == "left", "hands-off leads to the left stick")
	check(flow._view.focus == ["left"], "visual highlights the stick being measured")

	# Step 2: left stick
	roll("left")
	check(flow._phase == flow.Phase.STICK_RELEASE and flow._stick == "left", "full rim moves on to drift")
	check(flow._view.sticks.left.has("directions"), "visual shows the flick directions")
	for d in 8:
		flick("left", d)
	check(flow._phase == flow.Phase.STICK_RANGE and flow._stick == "right", "eight releases move on to the right stick")
	check(flow._view.sticks.left.has("inner"), "visual keeps the left stick's measured deadzone")

	# Step 3: right stick. The first flick (up) is "released" with a thumb still
	# resting on the stick, so it stops far out.
	roll("right")
	pad.hold("right", Vector2.UP)
	frames(0.15)
	pad.hold("right", Vector2(0.0, -0.3))
	frames(1.0)
	var held_spot: Vector2 = flow._release_tracker.points[-1]
	pad.release("right")
	frames(0.5)
	for d in [0, 1, 2, 3, 4, 5, 7]:
		flick("right", d)
	check(flow._phase == flow.Phase.STICK_RELEASE and not flow._release_tracker.done_mask()[6], "a release far beyond the others is asked again")
	check("thumb" in flow._body.text, "player is told to let go fully")
	check(not flow._rest_points.right.has(held_spot), "the thumb-held spot is set aside")
	flick("right", 6)
	check(flow._phase == flow.Phase.TRIGGER and flow._trigger == "lt", "sticks lead to the triggers")
	check(not flow._rest_points.right.has(held_spot), "a normal second flick replaces the thumb-held spot")

	# A stick that really does stop far out in one direction is believed the second time
	var tracker := Benchmark.ReleaseTracker.new(Vector2.ZERO, 0.0)
	for d in 8:
		var settle := Vector2.from_angle(TAU * d / 8.0) * (0.25 if d == 3 else 0.03)
		for i in 10:
			tracker.add(Vector2.from_angle(TAU * d / 8.0), DT)
		for i in 30:
			tracker.add(settle, DT)
	check(tracker.done_count() == 8 and tracker.review() == 1, "one-sided drift is asked again once")
	for i in 10:
		tracker.add(Vector2.from_angle(TAU * 3 / 8.0), DT)
	for i in 30:
		tracker.add(Vector2.from_angle(TAU * 3 / 8.0) * 0.24, DT)
	check(tracker.done_count() == 8 and tracker.review() == 0 and tracker.points.size() == 9, "repeated far stop is kept as real drift")

	# Step 4: triggers
	for i in 3:
		pull("lt")
	check(flow._trigger == "rt", "three left pulls move on to the right trigger")
	for i in 3:
		pull("rt")
	check(flow._phase == flow.Phase.SUMMARY, "both triggers lead to the summary")
	var profile: Dictionary = flow._profile
	check(Benchmark.is_compatible(profile, "test-controller"), "summary holds a usable profile")

	# The point of it all: wherever a stick settles, it reads as centered
	for stick: String in ["left", "right"]:
		var curve: Dictionary = profile[stick + "_stick"]
		var drifted := 0
		for i in 500:
			pad.hold(stick, Vector2.from_angle(pad.rng.randf() * TAU) * pad.rng.randf_range(0.5, 1.0))
			pad.release(stick)
			if not Benchmark.apply(pad.resting_position(stick), curve).is_zero_approx():
				drifted += 1
		check(drifted == 0, "%s stick never drifts after being let go (%d of 500 did)" % [stick, drifted])
		var weakest := 1.0
		for i in 32:
			var raw: Vector2 = pad.sticks[stick].offset + Vector2.from_angle(TAU * i / 32.0) * float(pad.sticks[stick].reach)
			weakest = minf(weakest, Benchmark.apply(raw.clampf(-1.0, 1.0), curve).length())
		check(weakest > 0.97, "%s stick reaches full tilt in every direction (weakest %.3f)" % [stick, weakest])
	check(profile.right_stick.inner > profile.left_stick.inner, "the more worn stick gets the larger deadzone")
	check(profile.right_stick.offset.distance_to(pad.sticks.right.offset) < 0.05, "right stick drift center is near its true offset")

	for trigger: String in ["lt", "rt"]:
		var key := "left_trigger" if trigger == "lt" else "right_trigger"
		var t: Dictionary = profile[key]
		var spec: Dictionary = pad.triggers[trigger]
		check(t.detected and not t.digital, "%s is detected as analog" % key)
		check(Benchmark.apply_trigger(spec.rest + 0.01, t) == 0.0, "%s at rest reads 0" % key)
		check(Benchmark.apply_trigger(spec.max, t) == 1.0, "%s fully pulled reads 1" % key)
		var half := Benchmark.apply_trigger(lerpf(spec.rest, spec.max, 0.5), t)
		check(half > 0.4 and half < 0.6, "%s half pulled reads about half (%.2f)" % [key, half])

	# Live preview on the summary
	pad.hold("right", Vector2.ZERO)
	pad.release("right")
	frames(0.5)
	check(flow._view.outputs.right == Vector2.ZERO, "summary preview shows a centered stick at rest")
	check(flow._view.outputs.has("lt") and flow._view.outputs.lt == 0.0, "summary preview shows trigger output")

	flow._save_profile()
	var saved: Dictionary = saves.settings.get_data("controls", "controller_deadzone_profile")
	check(saved == profile and flow._phase == flow.Phase.SETUP, "save stores the profile and returns to setup")
	check("Profile saved" in flow._body.text, "player is told the profile was saved")

	# On/off triggers are recognised; a skipped trigger falls back to the default
	new_flow(11)
	check("already has a saved profile" in flow._body.text, "setup mentions the saved profile")
	pad.triggers.lt.digital = true
	calibrate_sticks()
	for i in 3:
		pull("lt", 0.3, 0.3)
	flow._finish_trigger(true)
	check(flow._phase == flow.Phase.SUMMARY, "skipping the right trigger still finishes")
	check(flow._profile.left_trigger.digital, "on/off trigger is detected as digital")
	check(not flow._profile.right_trigger.detected, "skipped trigger is marked as not calibrated")
	check(Benchmark.apply_trigger(0.6, flow._profile.right_trigger) == Benchmark.apply_trigger(0.6, Benchmark.DEFAULT_TRIGGER), "skipped trigger uses the default curve")
	flow._cancel()
	check(saves.settings.get_data("controls", "controller_deadzone_profile") == saved, "cancel keeps the saved profile")

	# Unplugging mid-calibration stops without saving
	new_flow(13)
	flow._begin_session()
	flow._begin_rest()
	frames(4.2)
	flow._on_controller_changed(17, false)
	check(flow._phase == flow.Phase.INTERRUPTED, "disconnect interrupts calibration")
	check(saves.settings.get_data("controls", "controller_deadzone_profile") == saved, "disconnect keeps the saved profile")

	# An old right-stick-only profile is reported, not used
	saves.settings.set_data("controls", "controller_deadzone_profile", {"version": 1, "controller_guid": "test-controller", "inner": 0.05, "outer": 0.9, "offset": Vector2.ZERO})
	new_flow(17)
	check("older calibration" in flow._body.text, "setup explains an old profile is no longer used")

	flow.free()
	saves.settings.set_data("controls", "controller_deadzone_profile", {})
	print("DEADZONE FLOW TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
