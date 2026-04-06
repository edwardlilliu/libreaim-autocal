@abstract
class_name TargetShape
extends CollisionShape3D
## Manages the shape of a Target[br]
## - Target CollisionShape3D shape[br]
## - Target MeshInstance3D[br]
## - Target MeshInstance3D Animator

signal hitted(damage: float)

@warning_ignore("unused_private_class_variable")
@export var _mesh_instance: MeshInstance3D

func _connect_to_hitboxes() -> void:
	for hitbox: TargetHitbox in $Hitboxes.get_children():
		hitbox.hitted.connect(_on_hitbox_hitted)

func _on_hitbox_hitted(damage: float) -> void:
	hitted.emit(damage)
