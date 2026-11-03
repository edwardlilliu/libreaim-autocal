extends "res://modules/gameplay_manager/player/player_manager.gd"
## Deterministic controller inventory for the real player scene.
var devices: Array[int] = [17]
var guids := {17: "test-controller", 23: "other-controller"}
var sticks := {17: Vector2(0.47, -0.01), 23: Vector2.ZERO}

func _get_controller_devices() -> Array[int]:
	return devices

func _get_controller_guid(device: int) -> String:
	return guids.get(device, "")

func _read_controller_stick(device: int) -> Vector2:
	return sticks.get(device, Vector2.ZERO)
