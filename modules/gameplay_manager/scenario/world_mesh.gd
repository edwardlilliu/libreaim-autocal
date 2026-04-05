## Applied to world game world meshes to get the user defined texture
extends MeshInstance3D

func _ready() -> void:
	update_material()

func update_material() -> void:
	var world_material: StandardMaterial3D = preload("res://assets/material_default.tres")
	material_override = world_material
	material_override.albedo_color = SaveManager.settings.get_data("video_world", "surface_color")
	material_override.albedo_texture = Global.get_current_world_texture()
