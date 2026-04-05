extends Control

@onready var _target: MeshInstance3D = $PanelContainer/VBoxContainer/SubViewportContainer/SubViewport/Target
@onready var _world_environment: WorldEnvironment = $PanelContainer/VBoxContainer/SubViewportContainer/SubViewport/WorldEnvironment

func _ready() -> void:
	$"../TargetColor/TargetColor".color_changed.connect(_on_target_color_changed)
	$"../AmbientColor/Color".color_changed.connect(_on_ambient_color_changed)
	$"../SurfaceColor/Color".color_changed.connect(_on_surface_changed)
	$"../SurfaceTexture".item_selected.connect(_on_surface_changed)
	_set_environment_color()
	_set_target_material()

func _on_target_color_changed(_color: Color) -> void:
	_set_target_material()

func _on_ambient_color_changed(_color: Color) -> void:
	_set_environment_color()

func _on_surface_changed(_color: Color) -> void:
	$PanelContainer/VBoxContainer/SubViewportContainer/SubViewport/Floor.update_material()

func _set_environment_color() -> void:
	_world_environment.environment.background_color = SaveManager.settings.get_data("video_world", "ambient_color")

func _set_target_material() -> void:
	var material_override = _target.get_mesh().get_material()
	var col = SaveManager.settings.get_data("video_world", "target_color")
	material_override.set_albedo(col)
	material_override.set_emission(col)
	_target.material_override = material_override
