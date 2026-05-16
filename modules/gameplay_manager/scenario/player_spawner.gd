class_name PlayerSpawner
extends Node3D

const PLAYER = preload("uid://dkiet13jnna2m")

var _player: PlayerManager

func initialize() -> void:
	_player = PLAYER.instantiate()

	var player_settings := {}
	var keys: Array[String] = [
		"movement_enabled",
		"speed",
		"jump_force",
		"max_jumps",
		"gravity_force",
		"shoot_machinegun"
	]
	
	for key: String in keys:
		var value = Global.current_scenario.get(key)
		if value != null:
			player_settings[key] = value
	
	_player.initialize(player_settings)
	add_child(_player)

## Returns the PlayerManager Node
func get_player() -> PlayerManager:
	return _player
