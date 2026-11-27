extends SceneTree
## Run with a real renderer, not --headless. Reports observed frame intervals.
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1100,720)
	var scene: PackedScene = load("res://examples/slime/playground.tscn")
	var sample := scene.instantiate()
	root.add_child(sample)
	var player = sample.get_node("WorldFrame/World/Stage/Player")
	var camera = sample.get_node("WorldFrame/World/Stage/Camera")
	await player.wait_until_settled()
	for mode in ["topology","splats"]:
		var load_frames := PackedFloat64Array()
		var load_previous := Time.get_ticks_usec()
		player.request_renderer(mode)
		while player.morphing:
			await process_frame
			var load_now := Time.get_ticks_usec()
			load_frames.append(float(load_now-load_previous)/1000.0)
			load_previous = load_now
		if not load_frames.is_empty():
			load_frames.sort()
			print("SLIME_LOAD_BENCH ",mode," responsive_frames=",load_frames.size()," p95_ms=",snappedf(load_frames[int(load_frames.size()*.95)],.01)," max_frame_ms=",snappedf(load_frames[-1],.01))
		for i in range(20): await process_frame
		var samples := PackedFloat64Array()
		var previous := Time.get_ticks_usec()
		for i in range(240):
			camera.orbit(.006)
			if not player.morphing:
				player.request_form("mushroom" if player.current_form == "slime" else "slime")
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append(float(now-previous)/1000.0)
			previous = now
		var total := 0.0
		for value in samples: total += value
		samples.sort()
		var mean := total/samples.size()
		print("SLIME_GPU_BENCH ",mode," orbit+morph mean_frame_ms=",snappedf(mean,.01)," observed_fps=",snappedf(1000.0/mean,.1)," p95_ms=",snappedf(samples[int(samples.size()*.95)],.01))
		await player.wait_until_settled()
		player.reset_to_slime()
		await player.wait_until_settled()
	quit()
