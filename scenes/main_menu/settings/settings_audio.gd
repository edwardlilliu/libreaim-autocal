class_name SettingsAudio
extends Control
## Audio settings

@onready var hit_sound_option_button := $HitSoundOptionButton
@onready var hit_sound_preview: AudioStreamPlayer = $HitSoundPreview/AudioStreamPlayer
@onready var destroy_sound_option_button: OptionButton = $DestroySoundOptionButton
@onready var destroy_sound_preview: AudioStreamPlayer = $DestroySoundPreview/AudioStreamPlayer

func _ready() -> void:
	_add_destroy_sounds(hit_sound_option_button)
	_add_destroy_sounds(destroy_sound_option_button)
	_set_selected_sound_index(hit_sound_option_button, "hit_sound")
	_set_selected_sound_index(destroy_sound_option_button, "destroy_sound")
	_update_setting_sound(SaveManager.settings.get_data("audio", "volume"))
	$Volume.change_value.connect(_on_volume_change_value)

func _on_hit_sound_option_button_item_selected(index: int) -> void:
	SaveManager.settings.set_data("audio", "hit_sound", hit_sound_option_button.get_item_metadata(index))
	hit_sound_preview.update_setting_sound()

func _on_hit_sound_preview_pressed() -> void:
	hit_sound_preview.play()

func _on_destroy_sound_option_button_item_selected(index: int) -> void:
	SaveManager.settings.set_data("audio", "destroy_sound", destroy_sound_option_button.get_item_metadata(index))
	destroy_sound_preview.update_setting_sound()

func _on_destroy_sound_preview_pressed() -> void:
	destroy_sound_preview.play()

func _on_volume_change_value(new_value: float) -> void:
	_update_setting_sound(new_value)

func _update_setting_sound(new_value: float) -> void:
	if new_value != null:
		var this_bus := AudioServer.get_bus_index("Master")
		AudioServer.set_bus_volume_db(this_bus, lerpf(-20, 0, new_value))
		AudioServer.set_bus_mute(this_bus, new_value == 0)

func _set_selected_sound_index(option_button: OptionButton, setting_id: String) -> void:
	var selected = SaveManager.settings.get_data("audio", setting_id)
	for i in range(option_button.item_count):
		if selected == option_button.get_item_metadata(i):
			option_button.select(i)
			return

func _add_destroy_sounds(options_button: OptionButton):
	var i = 0
	for path:String in Global.get_destroy_sounds():
		options_button.add_item(path.get_file(), i)
		options_button.set_item_metadata(i, path)
		i += 1
