extends Control
## FPS limit settings

@onready var _fps_limit_slider: HSlider = $FPSLimitSlider
@onready var _fps_limit_label: Label = $FPSLimitLabel

func _ready() -> void:
	_fps_limit_slider.value = SaveManager.settings.get_data("video", "fps_limit")
	update_label()

func _on_fps_limit_slider_value_changed(value) -> void:
	SaveManager.settings.set_data("video", "fps_limit", value)
	DisplayManager.set_max_fps(value)
	update_label()

func update_label() -> void:
	_fps_limit_label.text = "FPS Limit: %d fps" % _fps_limit_slider.value 
