class_name TargetShapeManager
extends Node
## Manages switching and controling the target shape

var _this_shape: TargetShape

func init(size: Vector2, shape: PackedScene = null) -> void:
	if shape == null:
		shape = load("res://modules/gameplay_manager/target/shape/capsule/target_shape_capsule.tscn")
	_this_shape = shape.instantiate()
	$"..".add_child(_this_shape)
	var color: Color = SaveManager.settings.get_data("video_world", "target_color")
	_this_shape.init(size, color)
