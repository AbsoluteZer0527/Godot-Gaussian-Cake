extends SceneTree
var failures := 0
var checks := 0
var sample: Control
var player: CharacterBody3D
var camera: Camera3D

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",message)

func _initialize() -> void:
	run.call_deferred()

func ticks(count: int) -> void:
	for i in range(count): await physics_frame

func settled() -> bool:
	var limit := Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<limit:
		await process_frame
		if not player.last_error.is_empty():
			check(false,player.last_error)
			return false
		if player.ready_for_input and not player.morphing and player.current_form==player.desired_form:
			return true
	check(false,"sample operation timed out")
	return false

func run() -> void:
	sample = load("res://examples/slime/playground.tscn").instantiate()
	root.add_child(sample)
	player = sample.get_node("WorldFrame/World/Stage/Player")
	camera = sample.get_node("WorldFrame/World/Stage/Camera")
	if not await settled():
		finish()
		return
	check(camera.projection==Camera3D.PROJECTION_PERSPECTIVE,"camera is perspective third person")
	check(player.forms.initialized and player.forms.current_form=="slime", "shared form library starts at slime")
	var visual: Node3D=player.get_node("VisualRoot")
	var collider: CollisionShape3D=player.get_node("CollisionShape3D")
	var collider_transform := collider.transform
	var collider_id := collider.shape.get_instance_id()
	player.position=Vector3(0,.1,0)
	camera.snap_to_target()
	var start := player.position
	var forward := -camera.global_basis.z
	forward.y=0
	Input.action_press("slime_up")
	await ticks(24)
	Input.action_release("slime_up")
	await ticks(2)
	var travelled := player.position-start
	travelled.y=0
	check(travelled.length()>.3 and travelled.normalized().dot(forward.normalized())>.98,"W moves relative to camera forward")
	var facing := visual.global_basis.z.normalized()
	facing.y=0
	check(facing.normalized().dot(forward.normalized())>.98,"visual +Z turns toward travel direction")
	var heading := visual.rotation.y
	await ticks(10)
	check(is_equal_approx(heading,visual.rotation.y),"slime preserves facing when movement stops")
	check(player.rotation==Vector3.ZERO and collider.transform==collider_transform and collider.shape.get_instance_id()==collider_id,"visual rotation does not rotate or rebuild collider")
	var before_yaw: float=camera.orbit_yaw
	var press:=InputEventMouseButton.new()
	press.button_index=MOUSE_BUTTON_RIGHT
	press.pressed=true
	sample._input(press)
	var motion:=InputEventMouseMotion.new()
	motion.relative=Vector2(1,1)
	motion.screen_relative=Vector2(80,20)
	sample._input(motion)
	press.pressed=false
	sample._input(press)
	check(absf(angle_difference(before_yaw,camera.orbit_yaw)+80*camera.mouse_sensitivity)<.0001,"RMB orbit uses screen pixels independent of pixel scale")
	var released_yaw: float=camera.orbit_yaw
	sample._input(motion)
	check(is_equal_approx(released_yaw,camera.orbit_yaw),"mouse motion stops orbit after RMB release")
	Input.action_press("slime_orbit_right")
	await ticks(10)
	Input.action_release("slime_orbit_right")
	check(absf(angle_difference(released_yaw,camera.orbit_yaw))>.05,"E keyboard action orbits")
	camera.zoom(99)
	check(is_equal_approx(camera.distance,3.0),"zoom has safe minimum")
	camera.zoom(-99)
	check(is_equal_approx(camera.distance,12.0),"zoom has safe maximum")
	camera.orbit(0,99)
	check(is_equal_approx(camera.orbit_pitch,1.25),"pitch clamps before overhead flip")
	camera.orbit(0,-99)
	check(is_equal_approx(camera.orbit_pitch,.12),"pitch keeps camera above ground")
	player.position=Vector3(0,.1,0)
	await ticks(45)
	check(camera.follow_point.distance_to(player.global_position+Vector3.UP*camera.target_height)<.05,"camera follows moving player smoothly")
	player.request_renderer("splats")
	check(player.renderer_mode == "splats", "renderer selection applies to shared form player")
	if not await settled():
		finish()
		return
	check(player.renderer_mode=="splats" and player.last_error.is_empty(),"Gaussian renderer uses prepared endpoint library")
	check(is_equal_approx(player.morph_duration,1.5),"sample defaults to slower 1.5-second morphs")
	player.request_form("mushroom")
	await settled()
	check(is_equal_approx(heading,visual.rotation.y),"morph and renderer switch preserve current facing")
	check(collider.transform==collider_transform,"morph leaves gameplay collider independent of visual yaw")
	finish()

func finish() -> void:
	if is_instance_valid(sample):
		sample.queue_free()
		await process_frame
	print("THIRD PERSON: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
