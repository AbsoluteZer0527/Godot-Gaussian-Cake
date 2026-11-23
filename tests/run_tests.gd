extends SceneTree
const Topology = preload("res://addons/gaussian_cake/runtime/topology_player_3d.gd")
const Splats = preload("res://addons/gaussian_cake/runtime/splat_player_3d.gd")
const Clip = preload("res://addons/gaussian_cake/resources/splat_clip.gd")
const Decoder = preload("res://addons/gaussian_cake/runtime/splat_decoder.gd")
var failures := 0
var checks := 0
var finished_count := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	_run.call_deferred()

func exercise_clock(player: Node) -> void:
	player.set_process(false)
	check(player.duration > 0.0, "clip duration")
	player.stop()
	check(player.time == 0.0 and not player.playing, "stop resets")
	player.seek(player.duration)
	check(player.progress == 1.0, "exact endpoint")
	player.seek(-4.0)
	check(player.time == 0.0, "seek clamps negative time")
	player.loop_mode = player.LoopMode.ONCE
	player.speed = 1.0
	finished_count = 0
	player.playback_finished.connect(_on_finished)
	player.play()
	player._process(player.duration * 0.3)
	check(is_equal_approx(player.progress, 0.3), "play advances")
	player.pause()
	player._process(0.1)
	check(is_equal_approx(player.progress, 0.3), "pause holds")
	player.play()
	player._process(player.duration * 2.0)
	check(player.time == player.duration and not player.playing and finished_count == 1, "once reaches end and emits once")
	player._process(1.0)
	check(finished_count == 1, "finish signal does not repeat")
	player.play()
	check(player.time == 0.0, "play after finish restarts")
	player.loop_mode = player.LoopMode.LOOP
	player.seek(player.duration * 0.9)
	player._process(player.duration * 0.2)
	check(is_equal_approx(player.progress, 0.1), "loop wraps")
	player.loop_mode = player.LoopMode.PING_PONG
	player.seek(player.duration)
	player._process(player.duration * 0.25)
	check(is_equal_approx(player.progress, 0.75), "ping pong reverses")
	player.speed = 2.0
	player.seek(0.0)
	player._process(player.duration * 0.1)
	check(is_equal_approx(player.progress, 0.2), "speed multiplier")
	player.stop()
	player.playback_finished.disconnect(_on_finished)

func _on_finished() -> void:
	finished_count += 1

func _run() -> void:
	var scene = load("res://examples/assets/round_to_tall.glb")
	var clip = load("res://examples/assets/round_to_tall.gcsplat")
	check(scene is PackedScene, "native GLB import")
	check(clip is Clip, "gcsplat import produces typed resource")
	if scene == null or not clip is Clip:
		finish()
		return
	check(clip.get_splat_count() == 4096, "imported metadata")
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 0, 4)
	camera.current = true
	var topology := Topology.new()
	topology.source_scene = scene
	topology.autoplay = false
	world.add_child(topology)
	check(topology.error.is_empty(), "topology setup: " + topology.error)
	if topology.error.is_empty():
		exercise_clock(topology)
		var mesh = topology._model.find_children("*", "MeshInstance3D", true, false)[0]
		check(mesh.mesh.get_blend_shape_count() > 0, "imported blend shapes")
		check(mesh.get_active_material(0).vertex_color_use_as_albedo, "source vertex colors are displayed")
		check(mesh.get_active_material(0) != mesh.mesh.surface_get_material(0), "color override does not mutate shared imported material")
		topology.seek(0.0)
		var first := PackedFloat32Array()
		for i in range(mesh.mesh.get_blend_shape_count()):
			first.append(mesh.get_blend_shape_value(i))
		topology.seek(topology.duration)
		var difference := 0.0
		for i in range(first.size()):
			difference = maxf(difference, absf(first[i]-mesh.get_blend_shape_value(i)))
		check(difference > 0.5, "seek updates actual blend weights")
		var original_loop: int = topology._animation_player.get_animation(topology._selected_animation).loop_mode
		var second := Topology.new()
		second.source_scene = scene
		second.autoplay = false
		world.add_child(second)
		second.seek(second.duration * 0.5)
		check(topology.progress == 1.0 and is_equal_approx(second.progress, 0.5), "topology instances have independent clocks")
		second.loop_mode = second.LoopMode.LOOP
		check(topology._animation_player.get_animation(topology._selected_animation).loop_mode == original_loop, "shared Animation stays immutable")
		var packed := PackedScene.new()
		check(packed.pack(topology) == OK, "pack configured node")
		check(packed.get_state().get_node_count() == 1, "generated mesh not duplicated in saved scene")
		var reopened = packed.instantiate()
		world.add_child(reopened)
		check(reopened.source_scene == scene and reopened.error.is_empty(), "scene reload restores source")
	var splats := Splats.new()
	splats.clip = clip
	splats.autoplay = false
	world.add_child(splats)
	check(splats.error.is_empty(), "splat setup: " + splats.error)
	if splats.error.is_empty():
		exercise_clock(splats)
		var second := Splats.new()
		second.clip = clip
		second.autoplay = false
		world.add_child(second)
		splats.seek(0.25)
		second.seek(0.75)
		check(splats.time == 0.25 and second.time == 0.75, "splat clocks independent")
		check(splats._renderer.multimesh != second._renderer.multimesh and splats._material != second._material, "splat GPU state independent")
		check(splats._cache == second._cache, "immutable source data shared")
		var sorted := true
		for i in range(1, splats._order.size()):
			sorted = sorted and splats._depths[splats._order[i-1]] <= splats._depths[splats._order[i]]
		check(sorted, "depth order")
		var prior := splats._last_transform
		camera.position.x += 1.0
		splats._process(0.0)
		check(splats._last_transform != prior, "paused camera movement updates sort")
		var packed := PackedScene.new()
		check(packed.pack(splats) == OK and packed.get_state().get_node_count() == 1, "splat scene stores clip, not buffers")
		var reopened = packed.instantiate()
		world.add_child(reopened)
		check(reopened.clip == clip and reopened.error.is_empty(), "splat scene reload")
		# In-place resource replacement refreshes connected players.
		clip.emit_changed()
		await process_frame
		check(splats.error.is_empty() and second.error.is_empty(), "resource change rebuilds players")
	_test_decoder(clip.cache_bytes)
	var empty_topology := Topology.new()
	world.add_child(empty_topology)
	check(not empty_topology.error.is_empty() and not empty_topology.playing, "missing topology is recoverable")
	empty_topology.source_scene = scene
	await process_frame
	check(empty_topology.error.is_empty(), "assign topology after ready")
	empty_topology.animation_name = &"does-not-exist"
	await process_frame
	check(not empty_topology.error.is_empty(), "missing animation has useful error")
	var empty_splats := Splats.new()
	world.add_child(empty_splats)
	check(not empty_splats.error.is_empty(), "missing splat clip warning")
	empty_splats.clip = clip
	await process_frame
	check(empty_splats.error.is_empty(), "assign splat clip after ready")
	world.queue_free()
	await process_frame
	finish()

func _test_decoder(original: PackedByteArray) -> void:
	var decoder := Decoder.new()
	check(decoder.load_bytes(original), "read valid bytes")
	var cases: Array[PackedByteArray] = []
	var bad := original.duplicate()
	bad[0] = 0
	cases.append(bad)
	bad = original.duplicate()
	bad.encode_u32(8, 999)
	cases.append(bad)
	cases.append(original.slice(0, original.size()-1))
	bad = original.duplicate()
	bad.encode_u32(16, 0xffffffff)
	cases.append(bad)
	bad = original.duplicate()
	bad.encode_float(68, 0.0)
	cases.append(bad)
	var payload: int = 64+4*original.decode_u32(20)
	bad = original.duplicate()
	bad.encode_float(payload, NAN)
	cases.append(bad)
	bad = original.duplicate()
	bad.encode_float(payload+52, 2.0)
	cases.append(bad)
	for invalid in cases:
		check(not decoder.load_bytes(invalid) and not decoder.error.is_empty(), "reject malformed cache")
	check(decoder.load_bytes(original), "valid cache remains intact after rejection")

func finish() -> void:
	print("Gaussian Cake tests: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
