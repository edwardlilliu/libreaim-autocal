extends Control
## Video settings

@onready var _window_mode_options = $WindowModeOptions

func _ready() -> void:
	DisplayManager.window_mode_updated.connect(_on_display_manager_window_mode_updated)
	$Resolution.change_value.connect(_on_resolution_slider_value_changed)
	$FPSLimit.change_value.connect(_on_fps_limit_change_value)
	
	$Resolution.value = SaveManager.settings.get_data("video", "resolution")
	$CameraFov.value = SaveManager.settings.get_data("video", "fov")
	
	var selected = SaveManager.settings.get_data("video", "window_mode")
	for i in range(_window_mode_options.item_count):
		if selected == _window_mode_options.get_item_text(i):
			_window_mode_options.select(i) 

func _on_window_mode_options_item_selected(index: int) -> void:
	var option: String = _window_mode_options.get_item_text(index)
	DisplayManager.set_window_mode_from_string(option)
	SaveManager.settings.set_data("video", "window_mode", option)

func _on_resolution_slider_value_changed(value: float) -> void:
	DisplayManager.set_resolution(value)

func _on_fps_limit_change_value(value: float) -> void:
	DisplayManager.set_max_fps(value)

func _on_display_manager_window_mode_updated(window_mode):
	var selected = DisplayManager.get_string_from_window_mode(window_mode)
	for i in range(_window_mode_options.item_count):
		if selected == _window_mode_options.get_item_text(i):
			_window_mode_options.select(i)
