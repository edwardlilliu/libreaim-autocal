extends TargetShape
## Target shape for a capsule or a sphere

func init(size: Vector2, color: Color) -> void:
	shape.radius = size.x
	shape.height = size.y
	_mesh_instance.mesh.radius = size.x
	_mesh_instance.mesh.height = size.y
	set_target_material(color)
	_connect_to_hitboxes()

func set_target_material(color: Color) -> void:
	var material_override = _mesh_instance.get_mesh().get_material()
	material_override.set_albedo(color)
	material_override.set_emission(color)
	_mesh_instance.material_override = material_override
