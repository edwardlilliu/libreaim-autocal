extends Control
## Crosshair settings

signal refresh_crosshair

@onready var crosshair := $CrosshairSettings/Preview/Crosshair
@onready var file_export := $ExportFileDialog
@onready var file_import := $ImportFileDialog

func _ready() -> void:
	file_export.visible = false
	file_import.visible = false
	_load_saved()
	%dot.change_value.connect(_on_crosshair_updated)
	%dot.toggle_checkbox.connect(_on_crosshair_updated)
	%length.change_value.connect(_on_crosshair_updated)
	%thickness.change_value.connect(_on_crosshair_updated)
	%gap.change_value.connect(_on_crosshair_updated)
	%outline.change_value.connect(_on_crosshair_updated)
	%outline.toggle_checkbox.connect(_on_crosshair_updated)

func _on_export_pressed() -> void:
	file_export.current_dir = "/"
	file_export.visible = true

func _on_import_pressed() -> void:
	file_import.current_dir = "/"
	file_import.visible = true

func _on_export_file_dialog_file_selected(path: String) -> void:
	var cfg := ConfigFile.new()
	for key in SaveManager.settings.get_file().get_section_keys("crosshair"):
		cfg.set_value("crosshair", key, SaveManager.settings.get_data("crosshair", key))
	cfg.save(path)

func _on_import_file_dialog_file_selected(path: String) -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		push_warning("Could not import crosshair %s"%path)
		return
	for key in SaveManager.settings.get_file().get_section_keys("crosshair"):
		SaveManager.settings.set_data("crosshair", key, \
			cfg.get_value("crosshair", key))
	_load_saved()
	_queue_refresh_crosshair()

func _on_crosshair_updated(_value: Variant) -> void:
	_queue_refresh_crosshair()

func _on_crosshair_color_color_changed(color: Color) -> void:
	change_value("color", color)

func _on_outline_color_color_changed(color: Color) -> void:
	change_value("outline_color", color)

func change_value(key: String, value) -> void:
	SaveManager.settings.set_data("crosshair", key, value)
	_queue_refresh_crosshair()

func _queue_refresh_crosshair():
	# delay changes so we do not spam this event in load_saved()
	if not get_tree().process_frame.is_connected(_call_refresh_crosshair):
		get_tree().process_frame.connect(_call_refresh_crosshair, CONNECT_ONE_SHOT)

func _call_refresh_crosshair() -> void:
	refresh_crosshair.emit()

func _load_saved() -> void:
	crosshair._load_save()
	%dot.checkbox_value = crosshair._dot_enable
	%length.value = crosshair._length
	%thickness.value = crosshair._thickness
	%gap.value = crosshair._gap
	%crosshair_color.color = crosshair._color
	%outline.value = crosshair._outline_width
	%outline.checkbox_value = crosshair._outline_enable
	%outline_color.color = crosshair._outline_color
	%crosshair_color.color = crosshair._color
