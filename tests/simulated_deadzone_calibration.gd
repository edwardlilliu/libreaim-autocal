extends "res://modules/gameplay_manager/calibration/deadzone_calibration.gd"
## The real calibration flow, reading a simulated controller instead of a real one
var controller = load("res://tests/simulated_controller.gd").new()
var devices: Array[int] = [17]
var guids := {17: "test-controller"}

func _read_inputs(_device: int) -> Dictionary:
	return controller.read()

func _connected_devices() -> Array[int]:
	return devices

func _joy_name(device: int) -> String:
	return "Simulated pad" if devices.has(device) else ""

func _joy_guid(device: int) -> String:
	return guids.get(device, "")
