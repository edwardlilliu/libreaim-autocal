extends Control
## calibration selection in main menu

func _ready() -> void:
	_add_calibration_buttons()
	_select_calibration("sensitivity")

func _on_calibrate_pressed() -> void:
	_start_calibration()

## Adds the calibration mode button list
func _add_calibration_buttons() -> void:
	var calibration_list := $Calibrations/Calibrations/ScrollContainer/Calibrations
	for calibration in _get_sorted_calibration_ids():
		var button := Button.new()
		button.text = Global.calibrations[calibration].get("title", "No title")
		button.icon = Global.get_scenario_thumbnail(Global.calibrations[calibration].path)
		button.set_expand_icon(true)
		button.name = calibration
		button.set_text_alignment(HORIZONTAL_ALIGNMENT_LEFT)
		button.pressed.connect(_select_calibration.bind(button.name))
		calibration_list.add_child(button)

## Calibration ids sorted by the optional "order" key in their info.cfg
## (lower first, missing = 0), then by title
func _get_sorted_calibration_ids() -> Array:
	var ids: Array = Global.calibrations.keys()
	ids.sort_custom(func(a, b) -> bool:
		var order_a: int = Global.calibrations[a].get("order", 0)
		var order_b: int = Global.calibrations[b].get("order", 0)
		if order_a != order_b:
			return order_a < order_b
		return str(Global.calibrations[a].get("title", a)) < str(Global.calibrations[b].get("title", b)))
	return ids

## Select what calibration mode to run
func _select_calibration(id: String) -> void:
	Global.current_calibration = Global.calibrations[id]
	
	_set_current_calibration_title(id)
	_set_current_calibration_description(id)

## Sets the calibration mode title
func _set_current_calibration_title(type: String) -> void:
	var title: Label = $CurrentCalibration/VBoxContainer/Title
	title.text = Global.calibrations[type].get("title", "No title")

## Sets the calibration mode description
func _set_current_calibration_description(type: String) -> void:
	var description: Label = $CurrentCalibration/VBoxContainer/Description
	description.text = str(Global.calibrations[type].get("description", "No description"))

## Loads the calibration mode
func _start_calibration() -> void:
	if Global.current_calibration.get("id", "") == "sensitivity":
		get_tree().change_scene_to_file("res://modules/gameplay_manager/sensitivity_calibration.tscn")
		return
	# Calibrations that come with a scenario.tscn play exactly like the
	# scenarios under Play, through the regular gameplay manager
	var scenario_path: String = Global.current_calibration.get("path", "") + "scenario.tscn"
	if ResourceLoader.exists(scenario_path):
		Global.current_scenario = Global.current_calibration
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		get_tree().change_scene_to_file(Global.GAMEPLAY_MANAGER_PATH)
		return
	get_tree().change_scene_to_file(Global.CALIBRATION_MANAGER_PATH)
