extends Node3D
## Controller-only sensitivity search with separate validation and explicit apply.
## The existing aim-test scenario supplies its targets; ordinary Play is unchanged.

const Benchmark = preload("res://modules/gameplay_manager/calibration/sensitivity_benchmark.gd")
const AIM_SCENE = preload("res://assets/default_data/custom_resources/calibrations/aim_test/scenario.tscn")
const ACCENT := Color("a8e6cf")

enum Phase { SETUP, READY, RUNNING, PAUSED, RESULTS, INTERRUPTED }
var _phase: Phase = Phase.SETUP
var _previous_scenario: Dictionary
var _baseline: float
var _device: int = -1
var _device_name: String = ""
var _device_guid: String = ""
var _queue: Array[Dictionary] = []
var _index: int = 0
var _search_results: Array[Dictionary] = []
var _validation_results: Array[Dictionary] = []
var _recommendation: Dictionary = {}
var _validated: bool = false
var _validation: bool = false
var _practice: bool = true
var _round_active: bool = false
var _elapsed: float = 0.0
var _shots: int = 0
var _hits: int = 0
var _last_hit_time: float = 0.0
var _times: Array[float] = []
var _scenario: Node3D
var _player: PlayerManager
var _spawner: CalibrationTargetSpawner
var _canvas: CanvasLayer
var _screen: Control
var _panel: PanelContainer
var _body: VBoxContainer
var _hud: Control
var _hud_panel: PanelContainer
var _hud_text: Label
var _device_picker: OptionButton
var _start_button: Button
var _manual_speed: SpinBox
var _status: Label
var _session_seed: int

func _ready() -> void:
	_previous_scenario = Global.current_scenario.duplicate(true)
	_baseline = _saved_speed()
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Input.joy_connection_changed.connect(_on_controller_changed)
	_build_ui()
	_show_setup()

func _exit_tree() -> void:
	Global.current_scenario = _previous_scenario
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _saved_speed() -> float:
	var legacy: float = float(SaveManager.settings.get_data("controls", "sensitivity")) \
		* float(SaveManager.settings.get_data("controls", "sensitivity_game_value")) * 1000.0
	return clampf(float(SaveManager.settings.get_data("controls", "controller_sensitivity", rad_to_deg(legacy))), Benchmark.MIN_SPEED, Benchmark.MAX_SPEED)

func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	add_child(_canvas)
	_screen = Control.new()
	_canvas.add_child(_screen)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("111c29")
	_screen.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_screen.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size.x = 1000
	_panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(_panel)
	var margins := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 32)
	_panel.add_child(margins)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 18)
	margins.add_child(_body)
	_hud = Control.new()
	_canvas.add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_panel = PanelContainer.new()
	_hud_panel.position = Vector2(28, 24)
	_hud_panel.add_theme_stylebox_override("panel", _panel_style())
	_hud.add_child(_hud_panel)
	_hud_text = Label.new()
	_hud_text.add_theme_font_size_override("font_size", 24)
	_hud_panel.add_child(_hud_text)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 30)
	crosshair.add_theme_color_override("font_color", ACCENT)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud.add_child(crosshair)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(20, 20)
	crosshair.size = Vector2(40, 40)
	_hud.hide()

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1b2a3a")
	style.set_corner_radius_all(16)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func _clear_screen(title: String, description: String) -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_hud.hide()
	_screen.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_label("CONTROLLER CALIBRATION", 18, ACCENT)
	_label(title, 40)
	_label(description, 22)

func _label(text: String, size: int = 22, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 900
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	_body.add_child(label)
	return label

func _buttons() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_body.add_child(row)
	return row

func _button(row: HBoxContainer, text: String, action: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 52)
	button.add_theme_font_size_override("font_size", 22)
	if primary:
		button.add_theme_color_override("font_color", ACCENT)
	button.pressed.connect(action)
	row.add_child(button)
	return button

func _show_setup(message: String = "") -> void:
	_clear_round()
	_phase = Phase.SETUP
	_baseline = _saved_speed()
	_clear_screen("Find your controller sensitivity", "Try three look speeds, then check the best candidate on fresh targets. You choose whether to save it.")
	_label("Current speed: %.1f°/s  •  Mouse sensitivity stays separate" % _baseline, 24, ACCENT)
	var row := _buttons()
	_device_picker = OptionButton.new()
	_device_picker.custom_minimum_size = Vector2(460, 48)
	_device_picker.add_theme_font_size_override("font_size", 22)
	row.add_child(_device_picker)
	_label("Optional manual adjustment (degrees per second at full stick):", 20)
	var manual_row := _buttons()
	_manual_speed = SpinBox.new()
	_manual_speed.min_value = Benchmark.MIN_SPEED
	_manual_speed.max_value = Benchmark.MAX_SPEED
	_manual_speed.step = 0.1
	_manual_speed.value = _baseline
	_manual_speed.suffix = "°/s"
	_manual_speed.custom_minimum_size = Vector2(240, 48)
	manual_row.add_child(_manual_speed)
	_button(manual_row, "Save manual setting", _save_manual)
	_label("Use the right stick to aim and your mapped shoot button (default: right shoulder). Each measured round has 9 targets, after 3 practice targets. Only the selected controller counts.", 20)
	_status = _label(message, 20, ACCENT)
	var actions := _buttons()
	_start_button = _button(actions, "Start calibration", _begin_session, true)
	_button(actions, "Back to menu", _back)
	_refresh_controllers()
	if not _start_button.disabled:
		_start_button.grab_focus()

func _refresh_controllers() -> void:
	if _phase != Phase.SETUP or not is_instance_valid(_device_picker):
		return
	var selected := _device_picker.get_selected_id()
	_device_picker.clear()
	var devices := Input.get_connected_joypads()
	for id in devices:
		_device_picker.add_item(Input.get_joy_name(id), id)
		if id == selected:
			_device_picker.select(_device_picker.item_count - 1)
	_start_button.disabled = devices.is_empty()
	if devices.is_empty():
		_device_picker.add_item("Connect a controller to start", -1)
		_status.text = "Connect your controller. You can still save a manual speed."
	elif _status.text.begins_with("Connect your controller"):
		_status.text = "Controller ready."

func _save_manual() -> void:
	_manual_speed.apply()
	SaveManager.settings.set_data("controls", "controller_sensitivity", float(_manual_speed.value))
	_show_setup("Manual sensitivity saved. Calibration will start from this value.")

func _begin_session() -> void:
	if Input.get_connected_joypads().is_empty():
		_refresh_controllers()
		return
	_device = _device_picker.get_selected_id()
	if not Input.get_connected_joypads().has(_device):
		return
	_device_name = Input.get_joy_name(_device)
	_device_guid = Input.get_joy_guid(_device)
	_baseline = _saved_speed()
	_session_seed = randi_range(1, 100000000)
	_queue.clear()
	_search_results.clear()
	_validation_results.clear()
	_recommendation = {}
	_validated = false
	_validation = false
	for speed in Benchmark.candidates(_baseline):
		_queue.append({"speed": speed, "seed": _session_seed})
	_queue.shuffle()
	_index = 0
	_practice = true
	_show_ready()

func _show_ready() -> void:
	_phase = Phase.READY
	var name := "Validation" if _validation else "Benchmark"
	var description := "Fresh targets compare your current speed with the candidate." if _validation else "Compare different speeds with the same target sizes and stage rules."
	_clear_screen("%s • round %d of %d" % [name, _index + 1, _queue.size()], description)
	_label("Trial speed: %.1f°/s" % float(_queue[_index].speed), 30, ACCENT)
	_label("3 practice targets" if _practice else "9 measured targets", 28)
	_label("Aim with the right stick. Hit each target using your shoot button. Targets move from wide flicks to smaller movements. Press Esc or the controller Back/Select button to pause.", 22)
	_label("Practice is not scored. Your saved sensitivity is unchanged." if _practice else "The clock starts when you press Begin. Accuracy and completion time both count.", 20)
	var actions := _buttons()
	_button(actions, "Begin practice" if _practice else "Begin measured round", _start_round, true).grab_focus()
	_button(actions, "Cancel calibration", _cancel)

func _start_round() -> void:
	if not _selected_controller_connected():
		_interrupt("Controller disconnected. Reconnect it and restart calibration so the comparison stays consistent.")
		return
	_clear_round()
	Global.current_scenario = Global.calibrations["aim_test"].duplicate(true)
	_scenario = AIM_SCENE.instantiate()
	# This flow supplies its own instructions, timer, and results.
	var old_hud := _scenario.get_node("CalibrationHUD")
	_scenario.remove_child(old_hud)
	old_hud.free()
	_spawner = _scenario.get_node("CalibrationTargetSpawner")
	_spawner.sequence_seed = int(_queue[_index].seed) + (7 if _practice else 0)
	for i in range(_spawner.stages.size()):
		_spawner.stages[i] = _spawner.stages[i].duplicate()
		_spawner.stages[i].hits_required = 1 if _practice else Benchmark.HITS_PER_STAGE
	_spawner.stage_started.connect(_on_stage_started)
	_spawner.finished.connect(_on_finished)
	_spawner.ui_areas_provider = _covered_areas
	_scenario.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_scenario)
	_scenario.initialize()
	_player = _scenario.get_player()
	_player.controller_only = true
	_player.controller_device = _device
	_player.controller_sensitivity_override = float(_queue[_index].speed)
	_player.shooted.connect(_on_shot)
	_scenario.target_hitted.connect(_on_hit)
	_elapsed = 0
	_last_hit_time = 0
	_shots = 0
	_hits = 0
	_times.clear()
	_phase = Phase.RUNNING
	_round_active = true
	_screen.hide()
	_hud.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_update_hud()

func _covered_areas() -> Array[Rect2]:
	return [_hud_panel.get_global_rect().grow(16)]

func _process(delta: float) -> void:
	if _phase != Phase.RUNNING or not _round_active:
		return
	_elapsed += delta
	_update_hud()
	if _elapsed >= Benchmark.ROUND_TIMEOUT:
		_interrupt("This round reached the 75-second limit. No recommendation was saved. Try a comfortable manual speed or restart when ready.")

func _update_hud() -> void:
	var total := 3 if _practice else Benchmark.TARGET_COUNT
	var stage := maxi(0, _spawner._stage_index) + 1 if is_instance_valid(_spawner) else 1
	_hud_text.text = "%s • Stage %d / 3\nTargets %d / %d   |   %.1f s\nEsc / Back: pause" % ["Practice" if _practice else "Measured round", stage, _hits, total, _elapsed]

func _on_stage_started(_stage_index: int, _stage: Resource) -> void:
	_update_hud()

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
	# A disconnect/cancel between the signal and deferred callback invalidates it.
	if _phase != Phase.RUNNING:
		return
	var result := Benchmark.result(float(_queue[_index].speed), _elapsed, _shots, _hits, _times)
	_clear_round()
	if _practice:
		_practice = false
		_show_ready()
		return
	if not result.valid:
		_interrupt("This round did not produce a complete measurement. Restart calibration; your current setting is unchanged.")
		return
	if _validation:
		_validation_results.append(result)
	else:
		_search_results.append(result)
	_index += 1
	if _index < _queue.size():
		_practice = true
		_show_ready()
	elif _validation:
		_evaluate_validation()
	else:
		_recommendation = Benchmark.choose(_search_results, _baseline)
		if _recommendation.is_empty() or is_equal_approx(float(_recommendation.speed), _baseline):
			_show_results()
		else:
			_validation = true
			_queue = [{"speed": _baseline, "seed": _session_seed + 1001}, {"speed": _recommendation.speed, "seed": _session_seed + 1001}]
			_queue.shuffle()
			_index = 0
			_practice = true
			_show_ready()

func _evaluate_validation() -> void:
	var original: Dictionary = {}
	var candidate: Dictionary = {}
	for result in _validation_results:
		if is_equal_approx(float(result.speed), _baseline):
			original = result
		else:
			candidate = result
	_validated = Benchmark.improves(candidate, original)
	_show_results()

func _show_results() -> void:
	_phase = Phase.RESULTS
	_clear_screen("A faster setting to try" if _validated else "No clear improvement found", "These short trials are a starting point, not a guarantee of your ideal sensitivity.")
	_label("Current: %.1f°/s%s" % [_baseline, "   →   Recommended: %.1f°/s" % float(_recommendation.speed) if _validated else "   •   Keep your current setting"], 28, ACCENT)
	var results := _validation_results if _validation else _search_results
	_label("VALIDATION RESULTS" if _validation else "BENCHMARK RESULTS", 18, ACCENT)
	for entry in results:
		var label := "Current" if is_equal_approx(float(entry.speed), _baseline) else "Trial"
		_label("%s  %.1f°/s     %.2f seconds     %.1f%% accuracy     %d shots" % [label, float(entry.speed), float(entry.seconds), float(entry.accuracy) * 100.0, int(entry.shots)], 22)
	_label("A recommendation needs at least 5% faster completion with accuracy no more than 2 percentage points lower, including on fresh validation targets.", 20)
	var actions := _buttons()
	if _validated:
		_button(actions, "Apply recommendation", _apply_recommendation, true).grab_focus()
	else:
		_button(actions, "Keep current", _back, true).grab_focus()
	if _validated:
		_button(actions, "Keep current", _back)
	_button(actions, "Try again", _show_setup)

func _apply_recommendation() -> void:
	if _phase != Phase.RESULTS or not _validated or _recommendation.is_empty():
		return
	SaveManager.settings.set_data("controls", "controller_sensitivity", float(_recommendation.speed))
	SaveManager.settings.set_data("controls", "sensitivity_profile", {
		"version": Benchmark.VERSION, "created_at": Time.get_datetime_string_from_system(true),
		"controller_name": _device_name, "controller_guid": _device_guid,
		"original_speed": _baseline, "recommended_speed": _recommendation.speed,
		"search": _search_results.duplicate(true), "validation": _validation_results.duplicate(true),
		"seed": _session_seed, "validated": true,
	})
	_show_setup("Recommendation applied and saved. Your next training round will use it.")

func _unhandled_input(event: InputEvent) -> void:
	var pause_pressed := event.is_action_pressed("esc") or (event is InputEventKey and event.is_action_pressed("ui_cancel"))
	if _phase == Phase.RUNNING and pause_pressed:
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
	_clear_screen("Calibration paused", "Paused time does not count. Resume when you are ready to aim.")
	var actions := _buttons()
	_button(actions, "Resume", _resume_round, true).grab_focus()
	_button(actions, "Cancel calibration", _cancel)

func _resume_round() -> void:
	if not _selected_controller_connected():
		_interrupt("Reconnect the controller and restart calibration. Your saved setting is unchanged.")
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
	elif device == _device and not connected and _phase in [Phase.READY, Phase.RUNNING, Phase.PAUSED]:
		_interrupt("Controller disconnected. Reconnect it and restart calibration; no trial settings were saved.")

func _interrupt(message: String) -> void:
	_phase = Phase.INTERRUPTED
	_clear_round()
	_clear_screen("Calibration stopped", message)
	var actions := _buttons()
	_button(actions, "Return to setup", _show_setup, true).grab_focus()
	_button(actions, "Back to menu", _back)

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
	_show_setup("Calibration cancelled. Your saved sensitivity is unchanged.")

func _back() -> void:
	_clear_round()
	get_tree().change_scene_to_file(Global.MAIN_MENU_PATH)
