extends SceneTree
## Real-renderer interruption diagnostic: camera stays live during pose snapshot.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size=Vector2i(1100,720)
	var sample: Control=load("res://examples/slime/playground.tscn").instantiate()
	root.add_child(sample)
	var forms: Node3D=sample.get_node("WorldFrame/World/Stage/Player/VisualRoot/Forms")
	var camera: Camera3D=sample.get_node("WorldFrame/World/Stage/Camera")
	await forms.wait_until_ready()
	if not forms.error.is_empty(): quit(1);return
	forms.set_process(false)
	forms.set_renderer("splats")
	forms.morph_to("apple")
	forms.seek(.37)
	for i in range(20): await process_frame
	var started := Time.get_ticks_usec()
	var previous := started
	var intervals := PackedFloat64Array()
	forms.morph_to("mushroom")
	while forms.loading:
		camera.orbit(.006)
		await process_frame
		var now := Time.get_ticks_usec()
		intervals.append((now-previous)/1000.0)
		previous=now
	var hold_ms := (Time.get_ticks_usec()-started)/1000.0
	for i in range(16):
		camera.orbit(.006)
		await process_frame
		var now := Time.get_ticks_usec()
		intervals.append((now-previous)/1000.0)
		previous=now
	intervals.sort()
	print("FORM_RETARGET snapshot_hold_ms=",snappedf(hold_ms,.01)," responsive_frames=",intervals.size()-16," p95_frame_ms=",snappedf(intervals[int(intervals.size()*.95)],.01)," max_frame_ms=",snappedf(intervals[-1],.01))
	quit()
