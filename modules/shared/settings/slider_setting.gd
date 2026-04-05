@tool
extends Node
## A component to make settings options

signal change_value(value: float)
signal toggle_checkbox(value: bool)

@export var label_text := "Label":
	set(new_value):
		label_text = new_value
		$Label.text = new_value

## Extra information for the user
@export_multiline var tooltip: String:
	set(new_value):
		$Label.tooltip_text = new_value
		tooltip = new_value
		if tooltip != "":
			$Label.mouse_default_cursor_shape = Control.CURSOR_HELP
		else:
			$Label.mouse_default_cursor_shape = Control.CURSOR_ARROW

@export_group("Save this setting")
## On true, this setting will be saved and loaded automatically
@export var save_this_setting: bool:
	set(new_value):
		save_this_setting = new_value

## Category of this setting
@export var settings_category: String:
	set(new_value):
		settings_category = new_value

## Id of this slider setting
@export var settings_slider_id: String:
	set(new_value):
		settings_slider_id = new_value

## Id of this checkbox setting
@export var settings_checkbox_id: String:
	set(new_value):
		settings_checkbox_id = new_value

@export_group("Slider")
@export var has_slider := true:
	set(value):
		has_slider = value
		$SpinBox.visible = has_slider
		$Slider.visible = has_slider

@export var max_value: float = 100:
	set(new_value):
		max_value = new_value
		$Slider.max_value = new_value
		$SpinBox.max_value = new_value

@export var min_value: float = 0:
	set(new_value):
		min_value = new_value
		$Slider.min_value = new_value

@export var value: float = 50.0:
	set(new_value):
		if new_value > max_value:
			value = max_value
		elif new_value < min_value:
			value = min_value
		else:
			value = new_value
		
		$SpinBox.value = new_value
		$Slider.value = new_value
		change_value.emit(new_value)

@export var step: float = 0.1:
	set(new_value):
		if new_value <= 0:
			return
		$SpinBox.step = new_value
		$Slider.step = new_value
		step = new_value

## Adds the specified prefix string before the numerical value of the SpinBox.
@export var suffix: String:
	set(value):
		suffix = value
		$SpinBox.suffix = suffix

@export_group("Checkbox")
@export var has_checkbox := true:
	set(value):
		has_checkbox = value
		$CheckBox.visible = has_checkbox

@export var checkbox_value := true:
	set(value):
		checkbox_value = value
		$CheckBox.button_pressed = value

@onready var slider = $Slider

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if save_this_setting and settings_category != "":
		if settings_checkbox_id != "":
			checkbox_value = SaveManager.settings.get_data(settings_category, settings_checkbox_id)
		if settings_slider_id != "":
			value = SaveManager.settings.get_data(settings_category, settings_slider_id)

func _on_spin_box_value_changed(new_value: float) -> void:
	value = new_value

func _on_slider_value_changed(new_value: float) -> void:
	value = new_value
	_try_save_this_setting(settings_slider_id, new_value)

func _on_check_box_toggled(button_pressed: bool) -> void:
	toggle_checkbox.emit(button_pressed)
	_try_save_this_setting(settings_checkbox_id, button_pressed)

## Save this setting on the user settings
func _try_save_this_setting(id: String, new_value: Variant) -> void:
	if save_this_setting and !Engine.is_editor_hint():
		SaveManager.settings.set_data(settings_category, id, new_value)
