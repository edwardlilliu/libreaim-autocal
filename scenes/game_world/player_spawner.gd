class_name PlayerSpawner
extends Node3D

const PLAYER = preload("uid://dkiet13jnna2m")

var _player: PlayerManager

func initialize() -> void:
	_player = PLAYER.instantiate()
	add_child(_player)

## Returns the PlayerManager Node
func get_player() -> PlayerManager:
	return _player
