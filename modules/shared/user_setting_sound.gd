extends AudioStreamPlayer
## Plays a sound defined in the user settings

@export var sound_id: String

func _ready() -> void:
	update_setting_sound()
	SaveManager.settings.data_updated.connect(_on_settings_data_updated)
	
func _on_settings_data_updated(category: String, id: String, _value: Variant) -> void:
	if category == "audio" and id == sound_id:
		update_setting_sound()

func update_setting_sound() -> void:
	stream = Global.get_current_setting_sound(sound_id)
