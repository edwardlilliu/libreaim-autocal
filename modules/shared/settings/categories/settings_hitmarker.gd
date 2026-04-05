extends VBoxContainer

@onready var _hitmarker_texture: OptionButton = $VBoxContainer/HitmarkerTexture

func _ready() -> void:
	_load_hitmarker_textures()
	_on_enable_hitmarker_toggle_checkbox(SaveManager.settings.get_data("crosshair_hitmarker", "hitmarker_enable"))
	$EnableHitmarker.toggle_checkbox.connect(_on_enable_hitmarker_toggle_checkbox)
	_get_selected_texture_index()

func _on_hitmarker_texture_item_selected(index: int) -> void:
	SaveManager.settings.set_data("crosshair_hitmarker", "hitmarker_texture", _hitmarker_texture.get_item_metadata(index))

func _on_enable_hitmarker_toggle_checkbox(value: bool) -> void:
	$VBoxContainer.visible = value

func _load_hitmarker_textures() -> void:
	var i = 0
	for path: String in Global.get_hitmarker_textures():
		_hitmarker_texture.add_icon_item(CustomResourceManager.get_image(path), path.get_file(), i)
		_hitmarker_texture.set_item_metadata(i, path)
		i += 1

func _get_selected_texture_index() -> void:
	var selected = SaveManager.settings.get_data("crosshair_hitmarker", "hitmarker_texture")
	for i in range(_hitmarker_texture.item_count):
		if selected == _hitmarker_texture.get_item_metadata(i):
			_hitmarker_texture.select(i)
