class_name Target
extends CharacterBody3D
## A target for the player to shoot at

@export var health_slider_scene: PackedScene

signal destroyed ## When player destroys the target
signal hitted ## When player when player hits the target

var max_health: float
var health: float = 0.0:
	set(value):
		if value < health:
			hitted.emit()
		health = value
		if health < 0.0:
			destroyed.emit()
			queue_free()
var min_position: Vector3
var max_position: Vector3
var movement_behavior: TargetMovementBehavior

@onready var _target_shape_manager: TargetShapeManager = $TargetShapeManager
var _health_slider: HealthSlider

func init(size = Vector2(1, 2), behavior: TargetMovementBehavior = TargetMovementBehavior.new(),\
	new_health: float = 0.0, shape: PackedScene = null) -> void:
	await ready
	_target_shape_manager.init(size, shape)
	behavior.init(min_position, max_position)
	movement_behavior = behavior
	
	_set_health(new_health)
	_set_health_slider()

func _physics_process(delta: float) -> void:
	move_and_collide(movement_behavior.move_process(delta, position))

func _on_target_shape_manager_hitted(damage: float) -> void:
	health -= damage

func _set_health(new_health: float) -> void:
	max_health = new_health
	health = max_health

func _set_health_slider() -> void:
	if health > 0:
		_health_slider = health_slider_scene.instantiate()
		add_child(_health_slider)
		_health_slider.position.y = (_target_shape_manager.size.y / 2) + 0.4
		hitted.connect(_health_slider._on_target_hitted)
