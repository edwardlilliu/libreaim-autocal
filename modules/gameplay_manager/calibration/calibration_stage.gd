class_name CalibrationStage
extends Resource
## One stage of a calibration test: where its targets spawn, how big and
## how far away they are, and how many hits it takes to finish it

## Area of the screen the targets of a stage spawn in
enum Zone {
	OUTER, ## Band along the screen edges (the very edge excluded)
	INTERMEDIATE, ## Between the outer band and the center zone
	CENTER, ## Close to the crosshair
}

## Name shown to the player
@export var title: String = "Stage"
## Where on screen this stage's targets spawn
@export var zone: Zone = Zone.OUTER
## Targets the player has to hit to finish the stage
@export_range(1, 100) var hits_required: int = 10
## Distance from the camera to each target, in meters
@export_range(1.0, 100.0, 0.1, "suffix:m") var target_distance: float = 10.0
## Radius of each target, in meters
@export_range(0.05, 2.0, 0.01, "suffix:m") var target_radius: float = 0.5
## How far a new target must be from where the previous one was, as a fraction
## of the screen height (0 = no minimum). Measured on screen at the moment the
## new target spawns.
@export_range(0.0, 1.0, 0.01) var min_distance_from_last: float = 0.0
