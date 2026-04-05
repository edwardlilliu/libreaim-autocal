extends TargetShape
## Target shape for a capsule or a sphere

func init(size: Vector2, color: Color) -> void:
	shape.size.x = size.x
	shape.size.y = size.y
	shape.size.z = size.x
	_mesh_instance.mesh.size.x = size.x
	_mesh_instance.mesh.size.y = size.y
	_mesh_instance.mesh.size.z = size.x
	_set_target_material(color)

func _set_target_material(color: Color) -> void:
	var material_override = _mesh_instance.get_mesh().get_material()
	material_override.set_albedo(color)
	material_override.set_emission(color)
	_mesh_instance.material_override = material_override
