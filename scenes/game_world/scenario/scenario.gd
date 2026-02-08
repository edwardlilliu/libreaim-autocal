@tool
@icon("res://scenes/game_world/scenario/scenario.svg")
class_name Scenario
extends Node3D
## A custom training scenario to be played

signal target_destroyed ## When player destroys the target
signal target_hitted ## When player when player hits the target

@export var _light: DirectionalLight3D
@export var _target_spawners: Array[TargetSpawner]

func _get_configuration_warnings() -> PackedStringArray:
	var warnings = []
	if _light == null:
		warnings.append("There should be a light node.")
	if _target_spawners == null or _target_spawners.is_empty():
		warnings.append("There should be a target spawner node.")
	return warnings

func initialize() -> void:
	_update_world_appareance()
	for target_spawner: TargetSpawner in _target_spawners:
		target_spawner.target_destroyed.connect(_on_target_destroyed)
		target_spawner.target_hitted.connect(_on_target_hitted)

func _update_world_appareance() -> void:
	var world_material: StandardMaterial3D = preload("res://assets/material_default.tres")
	world_material.albedo_texture = Global.get_current_world_texture()

func _on_target_destroyed() -> void:
	target_destroyed.emit()

func _on_target_hitted() -> void:
	target_hitted.emit()
