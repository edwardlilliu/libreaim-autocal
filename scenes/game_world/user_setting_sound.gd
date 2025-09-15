extends AudioStreamPlayer
## Plays a sound defined in the user setttings

@export var sound_id: String

func _ready() -> void:
	update_setting_sound()

func update_setting_sound() -> void:
	var volume = SaveManager.settings.get_data("audio", "volume")
	if volume != null:
		var this_bus := AudioServer.get_bus_index("Master")
		AudioServer.set_bus_volume_db(this_bus, lerpf(-20, 0, volume))
		AudioServer.set_bus_mute(this_bus, volume == 0)
	stream = Global.get_current_setting_sound(sound_id)

func _on_volume_updated(_value: float) -> void:
	update_setting_sound()
