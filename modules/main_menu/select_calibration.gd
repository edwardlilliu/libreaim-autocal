extends Control
## Scenario selection in main menu

func _ready() -> void:
	_add_calibration_buttons()
	_select_calibration("deadzones")

func _on_calibrate_pressed() -> void:
	_start_calibration()

## Adds the calibration mode button list
func _add_calibration_buttons() -> void:
	var calibration_list := $Calibrations/Calibrations/ScrollContainer/Calibrations
	for calibration in Global.calibrations:
		var button := Button.new()
		button.text = Global.calibrations[calibration].get("title", "No title")
		button.icon = Global.get_scenario_thumbnail(Global.calibrations[calibration].path)
		button.set_expand_icon(true)
		button.name = calibration
		button.set_text_alignment(HORIZONTAL_ALIGNMENT_LEFT)
		calibration_list.add_child(button)

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
	pass
