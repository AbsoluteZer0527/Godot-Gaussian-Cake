extends Camera3D
## A perspective third-person camera; the editable Camera node remains in Stage.
@export var target_path := NodePath("../Player")
@export var target_height := .8
@export_range(3.0,12.0,.1) var distance := 6.8
@export var orbit_yaw := .35
@export_range(.12,1.25,.01) var orbit_pitch := .43
@export var follow_speed := 10.0
@export var mouse_sensitivity := .006
@export var keyboard_orbit_speed := 1.5
var follow_point := Vector3.ZERO
var _target: Node3D
var _dragging := false

func _ready() -> void:
	_target = get_node(target_path)
	projection = Camera3D.PROJECTION_PERSPECTIVE
	for spec in [["slime_orbit_left", KEY_Q], ["slime_orbit_right", KEY_E]]:
		if not InputMap.has_action(spec[0]):
			InputMap.add_action(spec[0])
			var event := InputEventKey.new()
			event.physical_keycode = spec[1]
			InputMap.action_add_event(spec[0],event)
	snap_to_target()

func snap_to_target() -> void:
	if not is_instance_valid(_target): return
	follow_point = _target.global_position + Vector3.UP*target_height
	_place()

func orbit(yaw_delta: float, pitch_delta: float = 0.0) -> void:
	orbit_yaw = wrapf(orbit_yaw+yaw_delta, -PI, PI)
	orbit_pitch = clampf(orbit_pitch+pitch_delta,.12,1.25)
	_place()

func zoom(steps: float) -> void:
	distance = clampf(distance*pow(.88,steps),3.0,12.0)
	_place()

func _process(delta: float) -> void:
	if not is_instance_valid(_target): return
	var orbit_input := Input.get_axis("slime_orbit_left","slime_orbit_right")
	orbit_yaw = wrapf(orbit_yaw + orbit_input*keyboard_orbit_speed*delta,-PI,PI)
	var desired := _target.global_position + Vector3.UP*target_height
	follow_point = follow_point.lerp(desired,1.0-exp(-follow_speed*delta))
	_place()

func _place() -> void:
	var horizontal := cos(orbit_pitch)*distance
	global_position = follow_point + Vector3(sin(orbit_yaw)*horizontal,sin(orbit_pitch)*distance,cos(orbit_yaw)*horizontal)
	look_at(follow_point)

func handle_camera_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: zoom(1)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom(-1)
	elif event is InputEventMouseMotion and _dragging:
		orbit(-event.screen_relative.x*mouse_sensitivity,event.screen_relative.y*mouse_sensitivity)
