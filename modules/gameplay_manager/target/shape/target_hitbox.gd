class_name TargetHitbox
extends Area3D
## One hitbox of a TargetShape

signal hitted(damage: float)

@export var damage_multiplier := 1.0

func _ready() -> void:
	add_to_group("Target")

func hit(damage: float) -> void:
	hitted.emit(damage * damage_multiplier)
