@tool
extends EditorPlugin
const Topology = preload("res://addons/gaussian_cake/runtime/topology_player_3d.gd")
const Splats = preload("res://addons/gaussian_cake/runtime/splat_player_3d.gd")
var failures := 0

func _enter_tree() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("EDITOR TEST FAIL: " + label)

func frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame

func wait_for(condition: Callable, label: String) -> bool:
	# Import and editor resource updates do not finish in a fixed frame count.
	# Keep every assertion, but wait for the state it actually promises to test.
	var deadline := Time.get_ticks_msec() + 10000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var complete: bool = condition.call()
	check(complete, label)
	return complete

func _run() -> void:
	await frames(20)
	var editor := get_editor_interface()
	check(editor.is_plugin_enabled("gaussian_cake"), "addon enabled")
	await wait_for(func(): return not editor.get_resource_filesystem().is_scanning(), "initial filesystem scan finishes")
	var root := editor.get_edited_scene_root()
	if root == null:
		root = Node3D.new()
		root.name = "EditorProbe"
		editor.add_root_node(root)
	var topology := Topology.new()
	topology.source_scene = load("res://examples/assets/round_to_tall.glb")
	root.add_child(topology)
	topology.owner = root
	var splats := Splats.new()
	var path := "res://examples/assets/round_to_tall.gcsplat"
	splats.clip = load(path)
	root.add_child(splats)
	splats.owner = root
	await wait_for(func(): return topology.duration > 0.0 and splats.duration > 0.0 and not topology._rebuild_pending and not splats._rebuild_pending, "editor playback initializes")
	check(topology.error.is_empty() and splats.error.is_empty(), "editor nodes load")
	topology.preview_progress = 0.4
	splats.preview_progress = 0.6
	await wait_for(func(): return is_equal_approx(topology.progress, 0.4) and is_equal_approx(splats.progress, 0.6), "Inspector preview progress")
	check(not topology.playing and not splats.playing, "no editor autoplay")
	await wait_for(func(): return is_instance_valid(splats._preview_camera) and splats._frame_a != null, "editor camera and GPU preview buffers")
	for i in range(2):
		editor.set_plugin_enabled("gaussian_cake", false)
		await frames(2)
		check(not editor.is_plugin_enabled("gaussian_cake"), "disable addon")
		editor.set_plugin_enabled("gaussian_cake", true)
		await frames(4)
		check(editor.is_plugin_enabled("gaussian_cake"), "reenable addon")
	# Changing registered extensions requires an editor filesystem scan to finish.
	await wait_for(func(): return not editor.get_resource_filesystem().is_scanning(), "plugin registration scan finishes")
	editor.get_resource_filesystem().scan()
	await wait_for(func(): return not editor.get_resource_filesystem().is_scanning(), "explicit filesystem scan finishes")
	# is_scanning can clear before deferred scan actions re-add an extension that
	# was temporarily unregistered. Reimport requires the EditorFileSystem entry.
	await wait_for(func(): return not editor.get_resource_filesystem().get_file_type(path).is_empty(), "clip rediscovered after plugin registration")
	# Modify only this isolated project's fixture and verify the live node sees reimport.
	var original := FileAccess.get_file_as_bytes(path)
	var changed := original.duplicate()
	changed.encode_float(32, 2.0)
	for i in range(changed.decode_u32(20)):
		changed.encode_float(64+4*i, changed.decode_float(64+4*i)*2.0)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(changed)
	file.close()
	editor.get_resource_filesystem().reimport_files(PackedStringArray([path]))
	await wait_for(func(): return is_equal_approx(splats.duration, 2.0), "live splat reimport updates duration")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(original)
	file.close()
	editor.get_resource_filesystem().reimport_files(PackedStringArray([path, "res://examples/assets/round_to_tall.glb"]))
	await wait_for(func(): return is_equal_approx(splats.duration, 1.0) and topology.error.is_empty(), "source restore and GLB reimport")
	print("Gaussian Cake editor tests: %d failures" % failures)
	var report := FileAccess.open("res://editor-test-result.txt", FileAccess.WRITE)
	report.store_string(str(failures))
	report.close()
	if is_instance_valid(topology):
		topology.queue_free()
	if is_instance_valid(splats):
		splats.queue_free()
	await frames(4)
	get_tree().quit(0 if failures == 0 else 1)
