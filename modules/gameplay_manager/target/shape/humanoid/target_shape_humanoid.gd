extends TargetShape
## Target shape for a capsule or a sphere

func init(_size: Vector2, color: Color) -> void:
	set_target_material(color)
	_connect_to_hitboxes()

func set_target_material(color: Color) -> void:
	_mesh_instance = $humanoid/HumanoidBase_NotOverlapping
	var material_override = _mesh_instance.mesh.surface_get_material(0)
	material_override.set_albedo(color)
	material_override.set_emission(color)
	_mesh_instance.material_override = material_override
