extends CanvasLayer
## Shows which calibration stage is running and how many hits are left.
## Lives inside the scenario and wires itself to the spawner, so the regular
## GameplayManager needs no changes to show it.

# Preloaded instead of using the class name, so this script works even before
# the editor has registered the new class
const Stage := preload("res://modules/gameplay_manager/calibration/calibration_stage.gd")

## The CalibrationTargetSpawner to follow
@export var spawner: Node

@onready var _root: Control = $Root
@onready var _stage_number: Label = %StageNumber
@onready var _stage_title: Label = %StageTitle
@onready var _progress: Label = %Progress
@onready var _banner: Label = %Banner

var _banner_tween: Tween
var _finished: bool = false

func _ready() -> void:
	_banner.visible = false
	if spawner == null:
		push_warning("CalibrationHUD has no spawner set.")
		return
	spawner.stage_started.connect(_on_stage_started)
	spawner.stage_progress.connect(_on_stage_progress)
	spawner.finished.connect(_on_finished)
	spawner.ui_areas_provider = get_covered_areas
	# Show the first stage before the player starts
	if not spawner.stages.is_empty():
		_show_stage(0, spawner.stages[0])
		_on_stage_progress(0, spawner.stages[0].hits_required)

func _notification(what: int) -> void:
	# Hide behind the pause menu, like the regular gameplay UI does
	if what == NOTIFICATION_PAUSED:
		_root.visible = false
	elif what == NOTIFICATION_UNPAUSED:
		_root.visible = not _finished

## Screen areas this HUD and the gameplay stats panel cover, so targets can
## avoid them
func get_covered_areas() -> Array[Rect2]:
	var areas: Array[Rect2] = []
	if not _root.is_visible_in_tree():
		return areas
	areas.append(%StagePanel.get_global_rect())
	if _banner.visible and _banner.modulate.a > 0.05:
		# Only the text itself, not the whole (wide) label
		var font := _banner.get_theme_font("font")
		var font_size := _banner.get_theme_font_size("font_size")
		var text_size := font.get_string_size(_banner.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		areas.append(Rect2(_banner.get_global_rect().get_center() - text_size / 2.0, text_size))
	# Time / score / accuracy panel of the regular GameplayUI
	var stats_panel := get_tree().current_scene.get_node_or_null("GameplayUI/GameplayUI/MarginContainer/Panel") as Control
	if stats_panel != null and stats_panel.is_visible_in_tree():
		areas.append(stats_panel.get_global_rect())
	return areas

func _on_stage_started(index: int, stage: Stage) -> void:
	_show_stage(index, stage)
	# Stage 1 shares the spot of "Shoot to start", so only later stages are announced
	if index > 0:
		_show_banner("Stage %d: %s" % [index + 1, stage.title])

func _on_stage_progress(hits: int, hits_required: int) -> void:
	_progress.text = "%d / %d" % [hits, hits_required]

func _on_finished() -> void:
	_finished = true
	_root.visible = false

func _show_stage(index: int, stage: Stage) -> void:
	_stage_number.text = "Stage %d / %d" % [index + 1, spawner.stages.size()]
	_stage_title.text = stage.title

## Shows a large message under the crosshair that fades out on its own
func _show_banner(text: String, duration: float = 1.5) -> void:
	if _banner_tween != null:
		_banner_tween.kill()
	_banner.text = text
	_banner.modulate.a = 1.0
	_banner.visible = true
	_banner_tween = create_tween()
	_banner_tween.tween_interval(duration)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.4)
	_banner_tween.tween_callback(_banner.hide)
