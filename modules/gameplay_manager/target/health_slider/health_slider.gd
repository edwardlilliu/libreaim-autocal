class_name HealthSlider
extends Sprite3D
## Slider that shows the health of the enemy targets

func _process(_delta: float) -> void:
	var health = $"..".health
	var max_health = $"..".max_health
	$SubViewport/ProgressBar.value = lerp(0, 100, health / max_health)
	$SubViewport/ProgressBar/Label.text = str(health)

func _on_target_hitted() -> void:
	var health = $"..".health
	var max_health = $"..".max_health
	$AudioStreamPlayer.pitch_scale = lerpf(1.15, 0.85, health / max_health)
	$AudioStreamPlayer.play()
	$AnimationPlayer.play("RESET")
	$AnimationPlayer.play("shot")
