extends AudioStreamPlayer
## Plays a sound defined in the user settings

@export var sound_id: String

func _ready() -> void:
	update_setting_sound()

func update_setting_sound() -> void:
	stream = Global.get_current_setting_sound(sound_id)
