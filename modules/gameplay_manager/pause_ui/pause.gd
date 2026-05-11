extends CanvasLayer

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") && get_tree().paused:
		trigger_pause(false)
	elif event.is_action_pressed("ui_cancel") && !get_tree().paused:
		trigger_pause(true)

func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT:
		trigger_pause(true)

func trigger_pause(new_pause_state: bool) -> void:
	get_tree().paused = new_pause_state
	visible = new_pause_state
	$"../GameplayUI".visible = !new_pause_state
	%CurrentGamemode.text = Global.get_current_scenario_value("title")
	%GamemodeIcon.texture = Global.get_scenario_thumbnail(Global.get_current_scenario_value("path"))
	if (new_pause_state):
		%Resume.grab_focus()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		%Settings.visible = false

func _on_resume_pressed() -> void:
	trigger_pause(false)

func _on_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(Global.MAIN_MENU_PATH)

func _on_settings_pressed() -> void:
	var settings: Control = %Settings
	settings.visible = !settings.visible
