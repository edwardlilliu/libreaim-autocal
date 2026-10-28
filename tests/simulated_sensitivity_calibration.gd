extends "res://modules/gameplay_manager/sensitivity_calibration.gd"
## Engine integration fixture. No physical device is needed for synthetic hits.
func _selected_controller_connected() -> bool:
	return true
