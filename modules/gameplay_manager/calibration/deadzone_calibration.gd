extends Node3D
## Deadzone calibration: rest sampling -> range sampling -> profile -> A/B verification.

const Benchmark = preload("res://modules/gameplay_manager/calibration/deadzone_benchmark.gd")
const SensBenchmark = preload("res://modules/gameplay_manager/calibration/sensitivity_benchmark.gd")
const AIM_SCENE = preload("res://assets/default_data/custom_resources/calibrations/aim_test/scenario.tscn")

@onready var _screen: Control = $CanvasLayer/Screen
@onready var _title: Label = $CanvasLayer/Screen/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Title
@onready var _body: Label = $CanvasLayer/Screen/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Body
@onready var _picker: OptionButton = $CanvasLayer/Screen/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/DevicePicker
@onready var _progress: ProgressBar = $CanvasLayer/Screen/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Progress
@onready var _buttons: Array[Button] = [
	$CanvasLayer/Screen/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/Button1,
	$CanvasLayer/Screen/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/Button2,
	$CanvasLayer/Screen/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/Button3,
]
@onready var _hud: Control = $CanvasLayer/Hud
@onready var _hud_panel: Control = $CanvasLayer/Hud/HudPanel
@onready var _hud_text: Label = $CanvasLayer/Hud/HudPanel/HudText

const SETUP_INTRO := "Measures stick drift and how far your stick reaches, then compares the result with a default deadzone on the aim test."

enum Phase { SETUP, SAMPLE_READY, REST, RANGE, SUMMARY, VERIFY_READY, RUNNING, PAUSED, RESULTS, INTERRUPTED }
var _phase: Phase = Phase.SETUP

var _actions: Array = []
var _setup_message: String = ""
var _previous_scenario: Dictionary
var _device: int = -1
var _device_name: String = ""
var _device_guid: String = ""

var _sample_kind: Phase = Phase.REST
var _sample_time: float = 0.0
var _samples: Array[Vector2] = []
var _rest: Dictionary = {}
var _range: Dictionary = {}
var _profile: Dictionary = {}

var _queue: Array[Dictionary] = []
var _index: int = 0
var _practice: bool = true
var _results: Array[Dictionary] = []
var _verified: bool = false
var _seed: int
var _round_active: bool = false
var _elapsed: float = 0.0
var _shots: int = 0
var _hits: int = 0
var _last_hit_time: float = 0.0
var _times: Array[float] = []
var _scenario: Node3D
var _player: PlayerManager
var _spawner: CalibrationTargetSpawner

func _ready() -> void:
	_previous_scenario = Global.current_scenario.duplicate(true)
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_controller_changed)
	for i in _buttons.size():
		_buttons[i].pressed.connect(_on_action.bind(i))
	_show_setup()

func _exit_tree() -> void:
	Global.current_scenario = _previous_scenario
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _show_page(title: String, body: String, actions: Array = [], picker := false, progress := false) -> void:
	_actions = actions
	_title.text = title
	_body.text = body
	_picker.visible = picker
	_progress.visible = progress
	_progress.value = 0
	for i in _buttons.size():
		var b := _buttons[i]
		b.visible = i < actions.size()
		b.disabled = false
		if b.visible:
			b.text = actions[i][0]
	_screen.show()
	_hud.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	for b in _buttons:
		if b.visible:
			b.grab_focus()
			break

func _on_action(i: int) -> void:
	if i < _actions.size():
		(_actions[i][1] as Callable).call()

func _show_setup(message: String = "") -> void:
	_clear_round()
	_phase = Phase.SETUP
	_setup_message = message
	_show_page("Deadzone calibration", SETUP_INTRO,
		[["Start calibration", _begin_session], ["Back to menu", _back]], true)
	_refresh_controllers()

func _refresh_controllers() -> void:
	if _phase != Phase.SETUP:
		return
	var selected := _picker.get_selected_id()
	_picker.clear()
	var devices := Input.get_connected_joypads()
	for id in devices:
		_picker.add_item(Input.get_joy_name(id), id)
		if id == selected:
			_picker.select(_picker.item_count - 1)
	_buttons[0].disabled = devices.is_empty()
	var note := _setup_message
	if devices.is_empty():
		_picker.add_item("Connect a controller to start", -1)
		note = "Connect your controller to begin."
	_body.text = SETUP_INTRO + ("\n\n" + note if note != "" else "")
	if not _buttons[0].disabled:
		_buttons[0].grab_focus()

func _begin_session() -> void:
	_device = _picker.get_selected_id()
	if not _selected_controller_connected():
		_refresh_controllers()
		return
	_device_name = Input.get_joy_name(_device)
	_device_guid = Input.get_joy_guid(_device)
	_rest = {}
	_range = {}
	_profile = {}
	_queue.clear()
	_seed = randi_range(1, 100000000)
	_show_sample_ready(Phase.REST)

func _show_sample_ready(kind: Phase, error: String = "") -> void:
	_phase = Phase.SAMPLE_READY
	_sample_kind = kind
	var title := "Step 1 of 2 • Resting stick" if kind == Phase.REST else "Step 2 of 2 • Stick range"
	var hint := "Set the controller down or hold it still and take your thumbs off the sticks. This measures drift." \
		if kind == Phase.REST else "Push the right stick all the way to the rim and roll it slowly in full circles."
	if error != "":
		hint += "\n\n" + error
	_show_page(title, hint, [["Try again" if error != "" else "Begin", _begin_sampling], ["Cancel", _cancel]], false, true)

func _begin_sampling() -> void:
	if not _selected_controller_connected():
		_interrupt("Controller disconnected. Reconnect it and start again.")
		return
	_samples.clear()
	_sample_time = -Benchmark.SETTLE_SECONDS
	_phase = _sample_kind
	_actions = []
	for b in _buttons:
		b.hide()

func _sample(delta: float) -> void:
	_sample_time += delta
	if _sample_time < 0.0:
		_body.text = "Get ready…"
		return
	var stick := Benchmark.read_stick(_device)
	var duration := Benchmark.REST_SECONDS if _phase == Phase.REST else Benchmark.RANGE_SECONDS
	_samples.append(stick)
	_progress.value = clampf(_sample_time / duration, 0.0, 1.0) * 100.0
	_body.text = "Stick: (%.2f, %.2f)   magnitude %.2f" % [stick.x, stick.y, stick.length()]
	if _sample_time >= duration:
		_finish_sampling()

func _finish_sampling() -> void:
	if _phase == Phase.REST:
		_rest = Benchmark.analyze_rest(_samples)
		if _rest.valid:
			_show_sample_ready(Phase.RANGE)
		else:
			_show_sample_ready(Phase.REST, str(_rest.reason))
	else:
		_range = Benchmark.analyze_range(_samples)
		if _range.valid:
			_build_summary()
		else:
			_show_sample_ready(Phase.RANGE, str(_range.reason))

func _build_summary() -> void:
	_profile = Benchmark.build_profile(_rest, _range, _device_name, _device_guid)
	_phase = Phase.SUMMARY
	var off := Vector2(_profile.offset[0], _profile.offset[1])
	var text := "Inner deadzone: %.3f\nOuter deadzone: %.3f\nDrift offset: (%.3f, %.3f)\nDirections covered: %d / %d\n\nVerify the profile on a short aim round, or save it now." % [
		_profile.inner, _profile.outer, off.x, off.y, _range.covered, Benchmark.SECTORS]
	_show_page("Profile ready", text, [
		["Verify on aim test", _show_verify_ready],
		["Save now", _save_profile.bind(false)],
		["Redo", _show_setup.bind("")]])

func _show_verify_ready() -> void:
	if _queue.is_empty():
		_queue = [{"label": "Your profile", "profile": _profile}, {"label": "Default deadzone", "profile": Benchmark.DEFAULT_PROFILE}]
		_queue.shuffle()
		_results.clear()
		_index = 0
		_practice = true
	_phase = Phase.VERIFY_READY
	var info := ("3 practice targets (not scored)" if _practice else "9 measured targets") \
		+ "\nAim with the right stick. Esc / Back pauses."
	_show_page("Verification • round %d of %d" % [_index + 1, _queue.size()], info,
		[["Begin practice" if _practice else "Begin measured round", _start_round], ["Cancel", _cancel]])

func _start_round() -> void:
	if not _selected_controller_connected():
		_interrupt("Controller disconnected. Reconnect it and start again.")
		return
	_clear_round()
	Global.current_scenario = Global.calibrations["aim_test"].duplicate(true)
	_scenario = AIM_SCENE.instantiate()
	var old_hud := _scenario.get_node("CalibrationHUD")
	_scenario.remove_child(old_hud)
	old_hud.free()
	_spawner = _scenario.get_node("CalibrationTargetSpawner")
	_spawner.sequence_seed = _seed + (7 if _practice else 0)
	for i in range(_spawner.stages.size()):
		_spawner.stages[i] = _spawner.stages[i].duplicate()
		_spawner.stages[i].hits_required = 1 if _practice else SensBenchmark.HITS_PER_STAGE
	_spawner.finished.connect(_on_finished)
	_spawner.ui_areas_provider = func() -> Array[Rect2]: return [_hud_panel.get_global_rect().grow(16)]
	_scenario.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_scenario)
	_scenario.initialize()
	_player = _scenario.get_player()
	_player.controller_only = true
	_player.controller_device = _device
	_player.controller_deadzone_profile = _queue[_index].profile
	_player.shooted.connect(_on_shot)
	_scenario.target_hitted.connect(_on_hit)
	_elapsed = 0.0
	_last_hit_time = 0.0
	_shots = 0
	_hits = 0
	_times.clear()
	_phase = Phase.RUNNING
	_round_active = true
	_screen.hide()
	_hud.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(delta: float) -> void:
	match _phase:
		Phase.REST, Phase.RANGE:
			_sample(delta)
		Phase.RUNNING:
			if not _round_active:
				return
			_elapsed += delta
			var total := 3 if _practice else SensBenchmark.TARGET_COUNT
			_hud_text.text = "%s\nTargets %d / %d   |   %.1f s\nEsc / Back: pause" % ["Practice" if _practice else "Measured", _hits, total, _elapsed]
			if _elapsed >= SensBenchmark.ROUND_TIMEOUT:
				_interrupt("This round hit the time limit. Nothing was saved.")

func _on_shot() -> void:
	if _round_active and _phase == Phase.RUNNING:
		_shots += 1

func _on_hit() -> void:
	if _round_active and _phase == Phase.RUNNING:
		_hits += 1
		_times.append(_elapsed - _last_hit_time)
		_last_hit_time = _elapsed

func _on_finished() -> void:
	if not _round_active:
		return
	_round_active = false
	_finish_round.call_deferred()

func _finish_round() -> void:
	if _phase != Phase.RUNNING:
		return
	var result := SensBenchmark.result(_reference_speed(), _elapsed, _shots, _hits, _times)
	_clear_round()
	if _practice:
		_practice = false
		_show_verify_ready()
		return
	if not result.valid:
		_interrupt("This round did not produce a complete measurement. Nothing was saved.")
		return
	_results.append({"label": _queue[_index].label, "result": result})
	_index += 1
	if _index < _queue.size():
		_practice = true
		_show_verify_ready()
	else:
		_show_results()

func _reference_speed() -> float:
	return SensBenchmark.resolve_speed(SaveManager.settings.get_data("controls", "controller_sensitivity", SensBenchmark.DEFAULT_SPEED))

func _show_results() -> void:
	_phase = Phase.RESULTS
	var with_profile: Dictionary = {}
	var with_default: Dictionary = {}
	var text := ""
	for entry in _results:
		var r: Dictionary = entry.result
		if entry.label == "Your profile":
			with_profile = r
		else:
			with_default = r
		text += "%s     %.2f s     %.1f%% accuracy     %d shots\n" % [entry.label, float(r.seconds), float(r.accuracy) * 100.0, int(r.shots)]
	_verified = Benchmark.verified(with_profile, with_default)
	text += "\n" + ("No clear difference from the default." if _verified
		else "Your profile did not clearly match the default on this run. You can still save it, or try again.")
	_show_page("Results", text, [
		["Save profile", _save_profile.bind(true)],
		["Discard", _back],
		["Try again", _show_setup.bind("")]])

func _save_profile(from_verification: bool) -> void:
	if _profile.is_empty():
		return
	var saved := _profile.duplicate(true)
	saved["verified"] = from_verification and _verified
	if from_verification:
		saved["verification"] = _results.duplicate(true)
	SaveManager.settings.set_data("controls", "controller_deadzone_profile", saved)
	_show_setup("Deadzone profile saved. It will be used in your next training round.")

func _unhandled_input(event: InputEvent) -> void:
	if _phase == Phase.RUNNING and (event.is_action_pressed("esc") or (event is InputEventKey and event.is_action_pressed("ui_cancel"))):
		_pause_round()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _phase == Phase.RUNNING:
		_pause_round()

func _pause_round() -> void:
	if not _round_active or not is_instance_valid(_scenario):
		return
	_phase = Phase.PAUSED
	_scenario.process_mode = Node.PROCESS_MODE_DISABLED
	_show_page("Paused", "Paused time does not count. Resume when you are ready to aim.",
		[["Resume", _resume_round], ["Cancel calibration", _cancel]])

func _resume_round() -> void:
	if not _selected_controller_connected():
		_interrupt("Controller disconnected. Reconnect it and start again.")
		return
	_phase = Phase.RUNNING
	_scenario.process_mode = Node.PROCESS_MODE_PAUSABLE
	_screen.hide()
	_hud.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _selected_controller_connected() -> bool:
	return Input.get_connected_joypads().has(_device)

func _on_controller_changed(device: int, connected: bool) -> void:
	if _phase == Phase.SETUP:
		_refresh_controllers()
	elif device == _device and not connected and _phase != Phase.RESULTS and _phase != Phase.INTERRUPTED:
		_interrupt("Controller disconnected. Reconnect it and start again. Nothing was saved.")

func _interrupt(message: String) -> void:
	_phase = Phase.INTERRUPTED
	_clear_round()
	_show_page("Calibration stopped", message, [["Return to setup", _show_setup.bind("")], ["Back to menu", _back]])

func _clear_round() -> void:
	_round_active = false
	if is_instance_valid(_scenario):
		_scenario.process_mode = Node.PROCESS_MODE_DISABLED
		remove_child(_scenario)
		_scenario.queue_free()
	_scenario = null
	_player = null
	_spawner = null

func _cancel() -> void:
	_show_setup("Calibration cancelled. Your saved profile is unchanged.")

func _back() -> void:
	_clear_round()
	get_tree().change_scene_to_file(Global.MAIN_MENU_PATH)
