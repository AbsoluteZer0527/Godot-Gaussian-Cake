extends CharacterBody3D
## Gameplay movement wraps the addon's reusable direct-form player.
signal state_changed

const FORMS := ["slime", "mushroom", "stone", "apple", "crate"]
@export_range(0.1, 10.0, 0.1) var morph_duration := 1.5
@export var movement_speed := 3.2
@export var turning_speed := 12.0
@export var arena_half_size := Vector2(6.6, 5.4)
@export var camera_path := NodePath("../Camera")

@onready var forms = $VisualRoot/Forms
@onready var stage_camera: Camera3D = get_node(camera_path)
@onready var visual_root: Node3D = $VisualRoot
var source_label := "SLIME"
var current_form: String:
	get: return forms.current_form if forms != null else "slime"
var desired_form: String:
	get: return forms.target_form if forms != null else "slime"
var renderer_mode: String:
	get: return forms.renderer_mode if forms != null else "topology"
var ready_for_input: bool:
	get: return forms != null and forms.initialized and forms.error.is_empty()
var last_error: String:
	get: return forms.error if forms != null else ""
var blend: float:
	get: return forms.progress if forms != null else 0.0
var loading: bool:
	get: return forms == null or forms.loading
var morphing: bool:
	get: return forms != null and forms.morphing

func _ready() -> void:
	_register_inputs()
	forms.camera = stage_camera
	forms.duration = morph_duration
	forms.state_changed.connect(func(): state_changed.emit())
	await forms.wait_until_ready()
	state_changed.emit()

func _register_inputs() -> void:
	var mapping := {
		"slime_left": [KEY_A, KEY_LEFT], "slime_right": [KEY_D, KEY_RIGHT],
		"slime_up": [KEY_W, KEY_UP], "slime_down": [KEY_S, KEY_DOWN],
		"slime_reset": [KEY_R], "slime_toggle": [KEY_M],
	}
	for action in mapping:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in mapping[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

func request_form(form: String) -> void:
	if not form in FORMS or not ready_for_input:
		return
	source_label = "CURRENT SHAPE" if morphing else current_form.to_upper()
	forms.request_state(form)
	state_changed.emit()

func reset_to_slime() -> void:
	request_form("slime")

func request_renderer(mode: String) -> void:
	if mode != "topology" and mode != "splats":
		return
	forms.set_renderer(mode)
	state_changed.emit()

func wait_until_settled() -> void:
	await forms.wait_until_ready()
	await forms.wait_until_settled()

func _process(_delta: float) -> void:
	if not ready_for_input:
		return
	if Input.is_action_just_pressed("slime_reset"):
		reset_to_slime()
	if Input.is_action_just_pressed("slime_toggle"):
		request_renderer("splats" if renderer_mode == "topology" else "topology")

func _physics_process(delta: float) -> void:
	var movement := Vector2.ZERO
	# Keep walking while changing shape so touching another target can redirect it.
	if ready_for_input:
		movement = Input.get_vector("slime_left", "slime_right", "slime_up", "slime_down")
	var right := stage_camera.global_basis.x
	right.y = 0
	var forward := -stage_camera.global_basis.z
	forward.y = 0
	var wish := right.normalized() * movement.x - forward.normalized() * movement.y
	if wish.length_squared() > .001:
		var target_yaw := atan2(wish.x, wish.z)
		visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_yaw, 1.0-exp(-turning_speed*delta))
	velocity.x = wish.x * movement_speed
	velocity.z = wish.z * movement_speed
	velocity.y -= 20.0 * delta
	move_and_slide()
	position.x = clampf(position.x, -arena_half_size.x, arena_half_size.x)
	position.z = clampf(position.z, -arena_half_size.y, arena_half_size.y)
	if position.y < -3.0:
		position = Vector3(0, 0.1, 2.0)
		velocity = Vector3.ZERO
