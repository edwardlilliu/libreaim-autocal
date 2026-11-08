extends Node3D
## Deadzone calibration: rest sampling -> range sampling -> profile -> save.

const Benchmark = preload("res://modules/gameplay_manager/calibration/deadzone_benchmark.gd")

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
const SETUP_INTRO := "Measures stick drift and how far your stick reaches"

enum Phase { SETUP, SAMPLE_READY, REST, RANGE, SUMMARY, INTERRUPTED }
var _phase: Phase = Phase.SETUP

var _actions: Array = []
var _setup_message: String = ""
var _device: int = -1
var _device_name: String = ""
var _device_guid: String = ""

var _sample_kind: Phase = Phase.REST
var _sample_time: float = 0.0
var _samples: Array[Vector2] = []
var _rest: Dictionary = {}
var _range: Dictionary = {}
var _profile: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_controller_changed)
	for i in _buttons.size():
		_buttons[i].pressed.connect(_on_action.bind(i))
	_show_setup()

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
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	for b in _buttons:
		if b.visible:
			b.grab_focus()
			break

func _on_action(i: int) -> void:
	if i < _actions.size():
		(_actions[i][1] as Callable).call()

func _show_setup(message: String = "") -> void:
	_phase = Phase.SETUP
	_setup_message = message
	_show_page("Deadzone calibration", SETUP_INTRO, [["Start calibration", _begin_session], ["Back to menu", _back]], true)
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

func _process(delta: float) -> void:
	if _phase == Phase.REST or _phase == Phase.RANGE:
		_sample(delta)

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
	var text := "Inner deadzone: %.3f\nOuter deadzone: %.3f\nDrift offset: (%.3f, %.3f)\nDirections covered: %d / %d\n\nSave this profile, or redo the calibration." % [
		_profile.inner, _profile.outer, off.x, off.y, _range.covered, Benchmark.SECTORS]
	_show_page("Profile ready", text, [
		["Save now", _save_profile],
		["Redo", _show_setup.bind("")]])

func _save_profile() -> void:
	if _profile.is_empty():
		return
	SaveManager.settings.set_data("controls", "controller_deadzone_profile", _profile.duplicate(true))
	_show_setup("Deadzone profile saved. It will be used in your next training round.")

func _selected_controller_connected() -> bool:
	return Input.get_connected_joypads().has(_device)

func _on_controller_changed(device: int, connected: bool) -> void:
	if _phase == Phase.SETUP:
		_refresh_controllers()
	elif device == _device and not connected and _phase != Phase.INTERRUPTED:
		_interrupt("Controller disconnected. Reconnect it and start again. Nothing was saved.")

func _interrupt(message: String) -> void:
	_phase = Phase.INTERRUPTED
	_show_page("Calibration stopped", message, [["Return to setup", _show_setup.bind("")], ["Back to menu", _back]])

func _cancel() -> void:
	_show_setup("Calibration cancelled. Your saved profile is unchanged.")

func _back() -> void:
	get_tree().change_scene_to_file(Global.MAIN_MENU_PATH)
