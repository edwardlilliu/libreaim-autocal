extends Node
## World appareance settings

@onready var _surface_color: ColorPickerButton = $SurfaceColor/Color
@onready var _world_texture: OptionButton = $WorldTexture
@onready var _target_color: ColorPickerButton = $TargetColor/TargetColor
@onready var _ambient_color: ColorPickerButton = $AmbientColor/Color

func _ready() -> void:
	var i = 0
	for path: String in Global.get_world_textures():
		_world_texture.add_icon_item(CustomResourceManager.get_image(path), path.get_file(), i)
		_world_texture.set_item_metadata(i, path)
		i+=1
	_surface_color.color = SaveManager.settings.get_data("video_world", "surface_color")
	_target_color.color = SaveManager.settings.get_data("video_world", "target_color")
	_ambient_color.color = SaveManager.settings.get_data("video_world", "ambient_color")
	_get_selected_texture_index()

func _on_color_color_changed(color: Color) -> void:
	SaveManager.settings.set_data("video_world", "surface_color", color)

func _on_target_color_color_changed(color: Color) -> void:
	SaveManager.settings.set_data("video_world", "target_color", color)

func _on_world_texture_item_selected(index) -> void:
	SaveManager.settings.set_data("video_world", "surface_texture", _world_texture.get_item_metadata(index))

func _on_amient_color_changed(color: Color) -> void:
	SaveManager.settings.set_data("video_world", "ambient_color", color)

func _get_selected_texture_index() -> void:
	var selected = SaveManager.settings.get_data("video_world", "surface_texture")
	for i in range(_world_texture.item_count):
		if selected == _world_texture.get_item_metadata(i):
			_world_texture.select(i)
