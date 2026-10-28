class_name PlayerManager
extends CharacterBody3D
## First person character controller

signal shooted ## When player shoots
signal missed ## When player mises a shot

const SHOOT_COOLDOWN: float = 0.1
const MAX_CAMERA_ANGLE: int = 89 ## Max vertical angle of the camera

@export var bullet_hole_scene: PackedScene

@onready var _camera: Camera3D = $Head/Camera3D
@onready var _raycast: RayCast3D = $Head/Camera3D/RayCast3D

var _current_shoot_cooldown: float
var _gravity_force: float = 20.0
var _jump_force: float = 8
var _current_jumps := 2
var _max_jumps := 2
var _mouse_sensitivity: float = 0.01
var _speed: int = 5
var _shoot_machinegun: bool = false
var _movement_enabled: bool = true
## Calibration uses one controller and a temporary speed, in degrees/second.
var controller_only: bool = false
var controller_device: int = -1
var controller_sensitivity_override: float = -1.0

func _ready() -> void:
	_camera.fov = SaveManager.settings.get_data("video", "fov")
	_mouse_sensitivity = _get_mouse_sensitivity()
	SaveManager.settings.data_updated.connect(_on_settings_data_updated)

func _input(event: InputEvent) -> void:
	if controller_only and (not (event is InputEventJoypadButton or event is InputEventJoypadMotion) or event.device != controller_device):
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.screen_relative.x * _mouse_sensitivity)
		_rotate_camera(-event.screen_relative.y * _mouse_sensitivity)
	if _shoot_machinegun == false:
		if event.is_action_pressed("shoot"):
			_shoot(1)
	if event.is_action_pressed("jump") and _movement_enabled:
		_jump()

func _process(delta: float) -> void:
	if _shoot_machinegun == true:
		_current_shoot_cooldown += delta
		if _current_shoot_cooldown > SHOOT_COOLDOWN:
			if Input.is_action_pressed("shoot"):
				_shoot(SHOOT_COOLDOWN)
				_current_shoot_cooldown = 0
	
	_handle_joypad_rotation(delta)

func _physics_process(delta: float) -> void:
	if !_movement_enabled:
		return
	
	if !is_on_floor():
		velocity.y -= _gravity_force * delta
	else:
		_current_jumps = _max_jumps
	
	var input := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)
	
	var movement_velocity := Vector3(input.x, 0, input.y) * _speed
	movement_velocity = transform.basis * movement_velocity
	
	velocity.x = lerp(velocity.x, movement_velocity.x, delta * 10)
	velocity.z = lerp(velocity.z, movement_velocity.z, delta * 10)
	
	move_and_slide()

func initialize(player_settings: Dictionary) -> void:
	_movement_enabled = player_settings.get("movement_enabled", _movement_enabled)
	_speed = player_settings.get("speed", _speed)
	_jump_force = player_settings.get("jump_force", _jump_force)
	_gravity_force = player_settings.get("gravity_force", _gravity_force)
	_speed = player_settings.get("speed", _speed)
	_max_jumps = player_settings.get("max_jumps", _max_jumps)
	_shoot_machinegun = player_settings.get("shoot_machinegun", _shoot_machinegun)

func _on_settings_data_updated(category: String, id: String, value: Variant) -> void:
	if category == "video" and id == "fov":
		_camera.fov = value
	if category == "controls" and id in ["sensitivity", "sensitivity_game", "sensitivity_game_value"]:
		_mouse_sensitivity = _get_mouse_sensitivity()

func _get_mouse_sensitivity() -> float:
	var user_sensitivity: float = SaveManager.settings.get_data("controls", "sensitivity")
	var conversion_sensitivity: float = SaveManager.settings.get_data("controls", "sensitivity_game_value")
	return user_sensitivity * conversion_sensitivity

func _handle_joypad_rotation(delta: float) -> void:
	var joypad_dir: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if controller_only:
		var raw := Vector2(Input.get_joy_axis(controller_device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(controller_device, JOY_AXIS_RIGHT_Y))
		var deadzone := InputMap.action_get_deadzone("look_left")
		joypad_dir = Vector2.ZERO if raw.length() <= deadzone else raw.normalized() * clampf((raw.length() - deadzone) / (1.0 - deadzone), 0.0, 1.0)
	if joypad_dir.length() > 0:
		var speed := controller_sensitivity_override if controller_sensitivity_override > 0 else get_controller_sensitivity()
		rotate_y(-joypad_dir.x * deg_to_rad(speed) * delta)
		_rotate_camera(-joypad_dir.y * deg_to_rad(speed) * delta)

## Preserve the old controller speed until the user saves an independent one.
func get_controller_sensitivity() -> float:
	return float(SaveManager.settings.get_data("controls", "controller_sensitivity", rad_to_deg(_get_mouse_sensitivity() * 1000.0)))

func _rotate_camera(amount: float) -> void:
	_camera.rotate_x(amount)
	_camera.rotation.x = clamp(
		_camera.rotation.x,
		deg_to_rad(-MAX_CAMERA_ANGLE),
		deg_to_rad(MAX_CAMERA_ANGLE)
	)

func _jump() -> void:
	if _current_jumps > 0:
		_current_jumps -= 1
		velocity.y = _jump_force

func _shoot(damage: float) -> void:
	shooted.emit()
	_raycast.force_raycast_update()
	if _raycast.is_colliding():
		var target = _raycast.get_collider()
		if target != null:
			_create_bullet_hole(target)
			if target is Area3D:
				if target.is_in_group("Target"):
					target.hit(damage)
					return
	missed.emit()

func _create_bullet_hole(target: Node3D) -> void:
	var bullet_hole_instance = bullet_hole_scene.instantiate()
	
	target.add_child(bullet_hole_instance)
	bullet_hole_instance.global_transform.origin = _raycast.get_collision_point() + _raycast.get_collision_normal() * 0.01
	
	if abs(_raycast.get_collision_normal().dot(Vector3.FORWARD)) != 1:
		bullet_hole_instance.look_at(
			bullet_hole_instance.global_position + _raycast.get_collision_normal(),
			Vector3.FORWARD
		)
