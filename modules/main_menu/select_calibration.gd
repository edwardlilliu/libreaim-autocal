extends Control
## Scenario selection in main menu

func _ready() -> void:
	pass

func _on_calibrate_pressed() -> void:
	pass

## Adds the scenario button list
func _add_calibration_buttons() -> void:
	var calibration_list := $Calibrations/Calibrations/ScrollContainer/Calibrations
	for calibration in Global.calibrations:
		var button := Button.new()
