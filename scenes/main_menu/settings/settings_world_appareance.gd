extends Node
## World appareance settings

@onready var _world_color: ColorPickerButton = $WorldColor/Color
@onready var _world_texture: OptionButton = $WorldTexture
@onready var _target_color: ColorPickerButton = $TargetColor/TargetColor
@onready var _preview: TextureRect = $Preview
@onready var _target_preview = $Preview/TargetPreview
@onready var _ambient_color: ColorPickerButton = $AmbientColor/Color

func _ready() -> void:
	var i = 0
	for path: String in Global.get_world_textures():
		_world_texture.add_icon_item(CustomResourceManager.get_image(path), path.get_file(), i)
		_world_texture.set_item_metadata(i, path)
		i+=1
	_world_color.color = SaveManager.settings.get_data("world", "world_color")
	_target_color.color = SaveManager.settings.get_data("world", "target_color")
	_ambient_color.color = SaveManager.settings.get_data("world", "ambient_color")
	_get_selected_texture_index()
	_update_preview()

func _on_color_color_changed(color: Color) -> void:
	SaveManager.settings.set_data("world", "world_color", color)
	_update_preview()

func _on_target_color_color_changed(color: Color) -> void:
	SaveManager.settings.set_data("world", "target_color", color)
	_update_preview()

func _on_world_texture_item_selected(index) -> void:
	SaveManager.settings.set_data("world", "world_texture", _world_texture.get_item_metadata(index))
	_update_preview()

func _on_amient_color_changed(color: Color) -> void:
	SaveManager.settings.set_data("world", "ambient_color", color)
	_update_preview()

func _get_selected_texture_index() -> void:
	var selected = SaveManager.settings.get_data("world", "world_texture")
	for i in range(_world_texture.item_count):
		if selected == _world_texture.get_item_metadata(i):
			_world_texture.select(i)
	_update_preview()

func _update_preview() -> void:
	_preview.texture = Global.get_current_world_texture()
	_preview.self_modulate = SaveManager.settings.get_data("world", "world_color")
	_target_preview.color = SaveManager.settings.get_data("world", "target_color")
