extends Node
## Manages the application window

signal window_mode_updated(window_mode: DisplayServer.WindowMode)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var selected = SaveManager.settings.get_data("video", "window_mode")
	set_window_mode(get_window_mode_from_string(selected))
	set_resolution(SaveManager.settings.get_data("video", "resolution"))
	_set_max_fps_from_settings()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			set_window_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		else:
			set_window_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

func _notification(what: int):
	match what:
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_set_max_fps_from_settings()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			set_max_fps(10)

func set_window_mode_from_string(window_mode: String) -> void:
	set_window_mode(get_window_mode_from_string(window_mode))

func get_window_mode_from_string(window_mode: String):
	match window_mode:
		"fullscreen":
			return DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		"windowed":
			return DisplayServer.WINDOW_MODE_MAXIMIZED
	return null

func get_string_from_window_mode(window_mode: DisplayServer.WindowMode):
	match window_mode:
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			return "fullscreen"
		DisplayServer.WINDOW_MODE_MAXIMIZED:
			return "windowed"
	return null

func set_window_mode(window_mode: DisplayServer.WindowMode) -> void:
	window_mode_updated.emit(window_mode)
	DisplayServer.window_set_mode(window_mode)
	if window_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		SaveManager.settings.set_data("video", "window_mode", "fullscreen")
	elif window_mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
		SaveManager.settings.set_data("video", "window_mode", "windowed")

func set_max_fps(value) -> void:
	Engine.set_max_fps(value)

func set_resolution(value: float) -> void:
	get_viewport().scaling_3d_scale = value / 100.0

func _get_screen_refresh_rate() -> int:
	return int(DisplayServer.screen_get_refresh_rate(DisplayServer.get_primary_screen()))

func _set_max_fps_from_settings() -> void:
	var value = SaveManager.settings.get_data("video", "fps_limit")
	if value < 0:
		value = _get_screen_refresh_rate()
		SaveManager.settings.set_data("video", "fps_limit", value)
	set_max_fps(value)
