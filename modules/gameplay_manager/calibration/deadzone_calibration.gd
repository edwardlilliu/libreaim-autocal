extends Node3D
## Controller calibration: hands off -> left stick -> right stick -> triggers
## -> summary -> save.
##
## Each stick is rolled around its rim to measure its range, then flicked in
## eight directions and released to measure where it comes to rest; the
## deadzone covers every one of those resting spots. Each trigger is squeezed
## all the way three times. The math lives in deadzone_benchmark.gd.

const Benchmark = preload("res://modules/gameplay_manager/calibration/deadzone_benchmark.gd")
const ControllerView = preload("res://modules/gameplay_manager/calibration/controller_view.gd")

@onready var _screen: Control = $CanvasLayer/Screen
@onready var _title: Label = $CanvasLayer/Screen/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Title
@onready var _view: ControllerView = $CanvasLayer/Screen/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ControllerView
@onready var _body: Label = $CanvasLayer/Screen/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Body
@onready var _picker: OptionButton = $CanvasLayer/Screen/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/DevicePicker
@onready var _progress: ProgressBar = $CanvasLayer/Screen/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Progress
@onready var _buttons: Array[Button] = [
	$CanvasLayer/Screen/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/Button1,
	$CanvasLayer/Screen/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/Button2,
	$CanvasLayer/Screen/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/Button3,
]
const SETUP_INTRO := "Calibrates both sticks (drift and range) and both triggers, in about a minute.\nMove the sticks and squeeze the triggers to check the right controller is selected."
const STEPS := 4
const SIDE := {"left": "left", "right": "right", "lt": "left", "rt": "right"}

enum Phase { SETUP, SAMPLE_READY, REST, STICK_RANGE, STICK_RELEASE, TRIGGER, SUMMARY, INTERRUPTED }
var _phase: Phase = Phase.SETUP

var _actions: Array = []
var _setup_message: String = ""
var _device: int = -1
var _device_name: String = ""
var _device_guid: String = ""
var _inputs: Dictionary = {}

var _sample_time: float = 0.0
var _step_time: float = 0.0
var _rest_samples: Array[Dictionary] = []
var _rest: Dictionary = {}

var _stick: String = ""
var _range_tracker: Benchmark.RangeTracker
var _release_tracker: Benchmark.ReleaseTracker
var _range_samples: Dictionary = {} ## stick -> Array[Vector2]
var _rest_points: Dictionary = {} ## stick -> Array[Vector2]
var _stick_results: Dictionary = {}

var _trigger: String = ""
var _pull_tracker: Benchmark.PullTracker
var _trigger_results: Dictionary = {}

var _profile: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_controller_changed)
	_picker.item_selected.connect(func(_index: int) -> void: _refresh_controllers())
	for i in _buttons.size():
		_buttons[i].pressed.connect(_on_action.bind(i))
	_show_setup()

#region Input (overridden by tests)

func _read_inputs(device: int) -> Dictionary:
	return Benchmark.read_inputs(device)

func _connected_devices() -> Array[int]:
	return Input.get_connected_joypads()

func _joy_name(device: int) -> String:
	return Input.get_joy_name(device)

func _joy_guid(device: int) -> String:
	return Input.get_joy_guid(device)

#endregion

#region Pages

## With [param measuring], the actions go on the quieter secondary buttons
## and nothing takes focus, so a controller button press can't cancel a step
func _show_page(title: String, body: String, actions: Array = [], picker := false, progress := false, measuring := false) -> void:
	_actions = actions.duplicate()
	if measuring:
		_actions.push_front(null) # leave the primary button out
	_title.text = title
	_body.text = body
	_picker.visible = picker
	_progress.visible = progress
	_progress.value = 0
	for i in _buttons.size():
		var b := _buttons[i]
		b.visible = i < _actions.size() and _actions[i] != null
		b.disabled = false
		if b.visible:
			b.text = _actions[i][0]
	_screen.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if measuring:
		for b in _buttons:
			b.release_focus()
		return
	for b in _buttons:
		if b.visible:
			b.grab_focus()
			break

func _on_action(i: int) -> void:
	if i < _actions.size() and _actions[i] != null:
		(_actions[i][1] as Callable).call()

func _step_title(step: int, name: String) -> String:
	return "Step %d of %d • %s" % [step, STEPS, name]

#endregion

#region Setup

func _show_setup(message: String = "") -> void:
	_phase = Phase.SETUP
	_setup_message = message
	_view.reset()
	_show_page("Deadzone calibration", SETUP_INTRO, [["Start calibration", _begin_session], ["Back to menu", _back]], true)
	_refresh_controllers()

func _refresh_controllers() -> void:
	if _phase != Phase.SETUP:
		return
	var selected := _picker.get_selected_id()
	_picker.clear()
	var devices := _connected_devices()
	for id in devices:
		_picker.add_item(_joy_name(id), id)
		if id == selected:
			_picker.select(_picker.item_count - 1)
	_buttons[0].disabled = devices.is_empty()
	var note := _setup_message
	if devices.is_empty():
		_picker.add_item("Connect a controller to start", -1)
		note = "Connect your controller to begin."
	elif note == "":
		note = _saved_profile_note(_joy_guid(_picker.get_selected_id()))
	_body.text = SETUP_INTRO + ("\n\n" + note if note != "" else "")
	if not _buttons[0].disabled:
		_buttons[0].grab_focus()

func _saved_profile_note(guid: String) -> String:
	var saved: Variant = SaveManager.settings.get_data("controls", "controller_deadzone_profile", {})
	if not saved is Dictionary or saved.is_empty() or saved.get("controller_guid", "") != guid:
		return ""
	if Benchmark.is_compatible(saved, guid):
		return "This controller already has a saved profile. A new calibration replaces it only when you save."
	return "This controller's saved profile is from an older calibration that only measured the right stick, so it is no longer used. Calibrate again to replace it."

func _begin_session() -> void:
	_device = _picker.get_selected_id()
	if not _selected_controller_connected():
		_refresh_controllers()
		return
	_device_name = _joy_name(_device)
	_device_guid = _joy_guid(_device)
	_rest = {}
	_range_samples = {}
	_rest_points = {}
	_stick_results = {}
	_trigger_results = {}
	_profile = {}
	_view.reset()
	_show_rest_ready()

#endregion

func _process(delta: float) -> void:
	var device := _picker.get_selected_id() if _phase == Phase.SETUP else _device
	if device >= 0 and _connected_devices().has(device):
		_inputs = _read_inputs(device)
	else:
		_inputs = {"left": Vector2.ZERO, "right": Vector2.ZERO, "lt": 0.0, "rt": 0.0}
	_view.set_inputs(_inputs)
	match _phase:
		Phase.REST:
			_sample_rest(delta)
		Phase.STICK_RANGE:
			_track_range(delta)
		Phase.STICK_RELEASE:
			_track_release(delta)
		Phase.TRIGGER:
			_track_trigger(delta)
		Phase.SUMMARY:
			_update_preview()

#region Step 1: hands off

func _show_rest_ready(error: String = "") -> void:
	_phase = Phase.SAMPLE_READY
	_view.focus = []
	var hint := "Set the controller down, or hold it without touching the sticks or triggers. This measures where each stick and trigger rests and how much it jitters."
	if error != "":
		hint += "\n\n" + error
	_show_page(_step_title(1, "Hands off"), hint, [["Try again" if error != "" else "Begin", _begin_rest], ["Cancel", _cancel]], false, true)

func _begin_rest() -> void:
	if not _selected_controller_connected():
		_interrupt("Controller disconnected. Reconnect it and start again.")
		return
	_rest_samples.clear()
	_sample_time = -Benchmark.SETTLE_SECONDS
	_phase = Phase.REST
	_show_page(_step_title(1, "Hands off"), "Get ready…", [["Cancel", _cancel]], false, true, true)

func _sample_rest(delta: float) -> void:
	_sample_time += delta
	if _sample_time < 0.0:
		_body.text = "Get ready… take your hands off the sticks and triggers."
		return
	_rest_samples.append(_inputs)
	_progress.value = clampf(_sample_time / Benchmark.REST_SECONDS, 0.0, 1.0) * 100.0
	_body.text = "Measuring where everything rests. Hands off for %d more seconds." % ceili(maxf(Benchmark.REST_SECONDS - _sample_time, 0.0))
	if _sample_time < Benchmark.REST_SECONDS:
		return
	_rest = Benchmark.analyze_rest(_rest_samples)
	if not _rest.valid:
		_show_rest_ready(str(_rest.reason))
		return
	_start_stick("left")

#endregion

#region Steps 2 and 3: sticks

func _start_stick(stick: String) -> void:
	_stick = stick
	_step_time = 0.0
	var center: Vector2 = _rest[stick].center
	var points: Array[Vector2] = [center]
	_rest_points[stick] = points
	_range_tracker = Benchmark.RangeTracker.new(center)
	_phase = Phase.STICK_RANGE
	_view.focus = [stick]
	_view.sticks[stick] = {"sectors": _range_tracker.covered_mask(), "rest_points": points}
	_show_page(_step_title(_stick_step(), "%s stick range" % stick.capitalize()),
		"Push the %s stick all the way to the edge and roll it around in slow circles until the ring around it is full." % stick,
		[["Cancel", _cancel]], false, true, true)

func _stick_step() -> int:
	return 2 if _stick == "left" else 3

func _track_range(delta: float) -> void:
	_step_time += delta
	_range_tracker.add(_inputs[_stick])
	var covered := _range_tracker.covered()
	_view.sticks[_stick].sectors = _range_tracker.covered_mask()
	_progress.value = covered * 100.0 / Benchmark.SECTORS
	if covered >= Benchmark.SECTORS \
			or (covered >= Benchmark.MIN_SECTORS_COVERED and _step_time >= Benchmark.RANGE_GRACE_SECONDS):
		_range_samples[_stick] = _range_tracker.samples
		_start_release()

func _start_release() -> void:
	_step_time = 0.0
	_release_tracker = Benchmark.ReleaseTracker.new(_rest[_stick].center, _rest[_stick].noise)
	_phase = Phase.STICK_RELEASE
	_view.sticks[_stick] = {"directions": _release_tracker.done_mask(), "rest_points": _rest_points[_stick]}
	_show_page(_step_title(_stick_step(), "%s stick drift" % _stick.capitalize()), _release_hint(), [["Cancel", _cancel]], false, true, true)

func _release_hint(asked_again: int = 0) -> String:
	var hint := "Flick the %s stick toward each arrow and let go, so it snaps back on its own. An arrow turns green once the stick settles; the yellow dots show where it came to rest." % _stick
	if asked_again > 0:
		hint += "\n\n%s: the stick stopped much farther out than the others, as if a thumb was still on it. Flick %s once more and take your thumb fully off." % [
			"One arrow went grey again" if asked_again == 1 else "%d arrows went grey again" % asked_again,
			"that direction" if asked_again == 1 else "those directions"]
	elif _release_tracker != null and _release_tracker.rejected > 0:
		hint += "\n\nOne release stopped far from the middle and was ignored. Take your thumb fully off the stick after each flick."
	return hint

func _track_release(delta: float) -> void:
	_step_time += delta
	var rejected_before := _release_tracker.rejected
	if _release_tracker.add(_inputs[_stick], delta):
		_sync_rest_points()
	if _release_tracker.rejected != rejected_before:
		_body.text = _release_hint()
	_view.sticks[_stick].directions = _release_tracker.done_mask()
	var done := _release_tracker.done_count()
	_progress.value = done * 100.0 / Benchmark.RELEASE_DIRECTIONS
	if done >= Benchmark.RELEASE_DIRECTIONS:
		var asked_again := _release_tracker.review()
		_sync_rest_points()
		_view.sticks[_stick].directions = _release_tracker.done_mask()
		if asked_again > 0:
			_body.text = _release_hint(asked_again)
			return
		_finish_stick()
	elif done >= Benchmark.MIN_RELEASES and _step_time >= Benchmark.RELEASE_GRACE_SECONDS:
		_finish_stick()

## Hands-off resting spot plus every release, shared with the visual
func _sync_rest_points() -> void:
	(_rest_points[_stick] as Array).assign([_rest[_stick].center] + Array(_release_tracker.points))

func _finish_stick() -> void:
	var points: Array[Vector2] = []
	points.assign(_rest_points[_stick])
	var samples: Array[Vector2] = []
	samples.assign(_range_samples[_stick])
	var result := Benchmark.build_stick(points, float(_rest[_stick].noise), samples)
	if not result.valid:
		_phase = Phase.INTERRUPTED
		_show_page("Couldn't calibrate the %s stick" % _stick, str(result.reason),
			[["Redo this stick", _start_stick.bind(_stick)], ["Cancel", _cancel]])
		return
	_stick_results[_stick] = result
	_view.sticks[_stick] = {"rest_points": points, "offset": result.offset, "inner": result.inner, "outer": result.outer}
	if _stick == "left":
		_start_stick("right")
	else:
		_start_trigger("lt")

#endregion

#region Step 4: triggers

func _start_trigger(trigger: String) -> void:
	_trigger = trigger
	_step_time = 0.0
	var rest: float = _rest[trigger].rest
	_pull_tracker = Benchmark.PullTracker.new(rest)
	_phase = Phase.TRIGGER
	_view.focus = [trigger]
	_view.triggers[trigger] = {"pulls": 0, "pulls_needed": Benchmark.TRIGGER_PULLS, "peak": rest}
	_show_page(_step_title(4, "%s trigger" % SIDE[trigger].capitalize()),
		"Squeeze the %s trigger slowly all the way in, then let it all the way out. Do it %d times. If this trigger doesn't respond, skip it." % [SIDE[trigger], Benchmark.TRIGGER_PULLS],
		[["Skip trigger", _finish_trigger.bind(true)], ["Cancel", _cancel]], false, true, true)

func _track_trigger(delta: float) -> void:
	_step_time += delta
	_pull_tracker.add(float(_inputs[_trigger]))
	_view.triggers[_trigger].pulls = _pull_tracker.pulls()
	_view.triggers[_trigger].peak = _pull_tracker.max_seen
	_progress.value = _pull_tracker.pulls() * 100.0 / Benchmark.TRIGGER_PULLS
	if _pull_tracker.pulls() >= Benchmark.TRIGGER_PULLS:
		_finish_trigger(false)

func _finish_trigger(skipped: bool) -> void:
	var rest: Dictionary = _rest[_trigger]
	var result := Benchmark.build_trigger(float(rest.rest), float(rest.noise), null if skipped else _pull_tracker)
	_trigger_results[_trigger] = result
	_view.triggers[_trigger] = {"skipped": not result.detected, "digital": result.get("digital", false)}
	if result.detected:
		_view.triggers[_trigger].inner = result.inner
		_view.triggers[_trigger].outer = result.outer
	if _trigger == "lt":
		_start_trigger("rt")
	else:
		_build_summary()

#endregion

#region Summary

func _build_summary() -> void:
	_profile = Benchmark.build_profile(_rest, _stick_results, _trigger_results, _device_name, _device_guid)
	if _profile.is_empty():
		_interrupt("Something went wrong building the profile. Nothing was saved; please calibrate again.")
		return
	_phase = Phase.SUMMARY
	_view.focus = []
	var lines: Array[String] = []
	var warnings: Array[String] = []
	for stick: String in Benchmark.STICKS:
		var s: Dictionary = _profile[stick + "_stick"]
		var offset: Vector2 = s.offset
		lines.append("%s stick: rests at (%+.2f, %+.2f) • deadzone %d%% • full tilt at %d%%" % [
			stick.capitalize(), offset.x, offset.y, roundi(s.inner * 100.0), roundi(s.outer * 100.0)])
		if s.drift_exceeds_limit:
			warnings.append("The %s stick drifts more than the largest deadzone allowed (%d%%), so some drift may remain. Cleaning or replacing the stick would help." % [stick, roundi(Benchmark.MAX_INNER * 100.0)])
		elif s.inner > Benchmark.HEAVY_DRIFT:
			warnings.append("The %s stick drifts a lot, so small movements need a little more push before they register." % stick)
	for trigger: String in Benchmark.TRIGGERS:
		var t: Dictionary = _profile["left_trigger" if trigger == "lt" else "right_trigger"]
		var label := "%s trigger: " % SIDE[trigger].capitalize()
		if not t.detected:
			lines.append(label + "skipped")
		elif t.digital:
			lines.append(label + "on/off only (no partial presses)")
		else:
			lines.append(label + "starts at %d%% of the pull • full at %d%%" % [roundi(maxf(t.inner, 0.0) * 100.0), roundi(t.outer * 100.0)])
	var text := "\n".join(lines)
	if not warnings.is_empty():
		text += "\n\n" + "\n".join(warnings)
	text += "\n\nTry it: let go of the sticks and the green rings stay centered, even where the white dots (the raw stick) sit off center. Squeeze the triggers to see them go from 0 to 100%."
	_show_page("Profile ready", text, [["Save profile", _save_profile], ["Redo", _begin_session], ["Cancel", _cancel]])

func _update_preview() -> void:
	_view.outputs = {
		"left": Benchmark.apply(_inputs.left, _profile.left_stick),
		"right": Benchmark.apply(_inputs.right, _profile.right_stick),
		"lt": Benchmark.apply_trigger(_inputs.lt, _profile.left_trigger),
		"rt": Benchmark.apply_trigger(_inputs.rt, _profile.right_trigger),
	}

func _save_profile() -> void:
	if _profile.is_empty():
		return
	SaveManager.settings.set_data("controls", "controller_deadzone_profile", _profile.duplicate(true))
	_show_setup("Profile saved. Both sticks use it in Play and in the sensitivity calibration, and the trigger settings are stored with it.")

#endregion

func _selected_controller_connected() -> bool:
	return _connected_devices().has(_device)

func _on_controller_changed(device: int, connected: bool) -> void:
	if _phase == Phase.SETUP:
		_refresh_controllers()
	elif device == _device and not connected and _phase != Phase.INTERRUPTED:
		_interrupt("Controller disconnected. Reconnect it and start again. Nothing was saved.")

func _interrupt(message: String) -> void:
	_phase = Phase.INTERRUPTED
	_view.focus = []
	_show_page("Calibration stopped", message, [["Return to setup", _show_setup.bind("")], ["Back to menu", _back]])

func _cancel() -> void:
	_show_setup("Calibration cancelled. Your saved profile is unchanged.")

func _back() -> void:
	get_tree().change_scene_to_file(Global.MAIN_MENU_PATH)
