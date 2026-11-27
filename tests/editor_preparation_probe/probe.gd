@tool
extends EditorPlugin
## Runs only in an isolated verification project with tiny external input files.
const Job = preload("res://addons/gaussian_cake/editor/preparation_job.gd")
const Player = preload("res://addons/gaussian_cake/runtime/form_player_3d.gd")
const Decoder = preload("res://addons/gaussian_cake/runtime/form_decoder.gd")
const Graph = preload("res://addons/gaussian_cake/runtime/form_state_machine.gd")
var checks := 0
var failures := 0
var inputs: Dictionary
var results: Array[Dictionary] = []
var errors: Array[String] = []
var job: Node
var controller: Node
var scene: Node3D
var player: Node

func _enter_tree() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("EDITOR TEST FAIL: " + label)

func wait_for(condition: Callable, label: String, milliseconds: int = 30000) -> bool:
	var deadline := Time.get_ticks_msec() + milliseconds
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var done: bool = condition.call()
	check(done, label)
	return done

func settings() -> Dictionary:
	return {"cli_path":inputs.cli_path, "source_path":inputs.source_path,
		"target_path":inputs.target_path, "count":128, "samples":64,
		"mixtures":4, "color_match":0.35, "dc_only":false}

func on_prepared(manifest: String, source: String, target: String, cached: bool) -> void:
	results.append({"manifest":manifest,"source":source,"target":target,"cached":cached})

func bake(spec: Dictionary) -> Dictionary:
	var previous := results.size()
	check(job.start(spec), "valid preparation request starts")
	if not await wait_for(func(): return not job.busy, "preparation finishes without blocking editor frames"):
		job.cancel()
		return {}
	check(results.size() == previous + 1, "successful preparation publishes one result")
	if results.size() == previous: printerr("PREPARATION DIAGNOSTIC: ",job.status,"\n",job.log_text)
	return results.back() if results.size() > previous else {}

func valid_bundle(result: Dictionary) -> void:
	if result.is_empty(): return
	var manifest_path: String = result.manifest
	check(manifest_path.begins_with("res://gaussian_cake_generated/"), "prepared output is portable inside the project")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	check(manifest is Dictionary and manifest.get("format") == "GaussianCakeFormLibrary", "published library manifest is valid")
	if not manifest is Dictionary: return
	check(manifest.names == [result.source,result.target] and result.source != result.target, "source and target names remain distinct")
	var decoder := Decoder.new()
	check(decoder.load_file(manifest_path.get_base_dir().path_join(manifest.splats)), "published endpoint bytes pass runtime validation")
	check(decoder.count == 128 and decoder.form_count == 2, "raw inputs produce two endpoints at the requested count")
	check(decoder.records(0) != decoder.records(1), "distinct input models produce distinct endpoint data")
	check(not manifest.has("topology"), "raw-model preparation accurately declares splat output")

func backend_checks() -> void:
	job = Job.new()
	add_child(job)
	job.prepared.connect(on_prepared)
	job.failed.connect(func(message: String): errors.append(message))
	var bad := settings()
	bad.cli_path = inputs.cli_path + ".missing"
	check(not job.start(bad) and not job.busy, "missing CLI is rejected before launching")
	check(not errors.is_empty() and not errors.back().is_empty(), "invalid CLI has an actionable error")
	bad = settings()
	bad.source_path = inputs.source_path + ".missing.glb"
	check(not job.start(bad) and not job.busy, "missing model is rejected before launching")
	bad = settings()
	bad.count = 50001
	check(not job.start(bad), "Godot's splat-count limit is validated before preparation")
	bad = settings()
	bad.samples = 3
	bad.mixtures = 1
	check(not job.start(bad), "unsupported low sample count is rejected before launching CLI")
	var first := await bake(settings())
	valid_bundle(first)
	if first.is_empty(): return
	check(not first.cached, "first request runs the real authoring CLI")
	var original_payload := FileAccess.get_sha256(first.manifest.get_base_dir().path_join("forms.gcforms"))
	var original_bytes := FileAccess.get_file_as_bytes(first.manifest.get_base_dir().path_join("forms.gcforms"))
	var cached := await bake(settings())
	check(not cached.is_empty() and cached.cached and cached.manifest == first.manifest, "unchanged inputs reuse the validated cache")
	var target_bytes := FileAccess.get_file_as_bytes(inputs.target_path)
	var changed_file := FileAccess.open(inputs.target_path, FileAccess.WRITE)
	changed_file.store_buffer(target_bytes)
	changed_file.store_string("\ncomment fixture content changed\n")
	changed_file.close()
	var changed := await bake(settings())
	check(not changed.is_empty() and not changed.cached and changed.manifest != first.manifest, "input content changes invalidate preparation cache")
	check(FileAccess.get_sha256(first.manifest.get_base_dir().path_join("forms.gcforms")) == original_payload, "preparing changed inputs preserves the previous valid bundle")
	changed_file = FileAccess.open(inputs.target_path, FileAccess.WRITE)
	changed_file.store_buffer(target_bytes)
	changed_file.close()
	var error_count := errors.size()
	var result_count := results.size()
	bad = settings()
	bad.target_path = inputs.malformed_path
	check(job.start(bad), "malformed existing input reaches CLI validation")
	await wait_for(func(): return not job.busy, "malformed input terminates cleanly")
	check(errors.size() > error_count and not errors.back().is_empty(), "CLI failure is shown to the user")
	check(results.size() == result_count, "failed preparation never publishes a playable result")
	check(FileAccess.get_sha256(first.manifest.get_base_dir().path_join("forms.gcforms")) == original_payload, "CLI failure preserves the previous good output")
	var corrupt_file := FileAccess.open(first.manifest.get_base_dir().path_join("forms.gcforms"), FileAccess.WRITE)
	corrupt_file.store_string("damaged cache fixture")
	corrupt_file.close()
	var repaired := await bake(settings())
	check(not repaired.is_empty() and not repaired.cached, "damaged cached payload is rejected and prepared again")
	valid_bundle(repaired)
	var repaired_cached := await bake(settings())
	check(not repaired_cached.is_empty() and repaired_cached.cached and repaired_cached.manifest == repaired.manifest, "repaired cache revision is reusable")
	# Restore the deliberately damaged fixture before Godot scans all project assets.
	# The backend's preservation and repair assertions above remain independent.
	corrupt_file = FileAccess.open(first.manifest.get_base_dir().path_join("forms.gcforms"), FileAccess.WRITE)
	corrupt_file.store_buffer(original_bytes)
	corrupt_file.close()
	var capture := settings()
	capture.source_path = inputs.capture_source
	capture.target_path = inputs.capture_target
	error_count = errors.size()
	result_count = results.size()
	check(job.start(capture), "Gaussian PLY captures reach preparation")
	await wait_for(func(): return not job.busy, "view-dependent color validation finishes")
	check(errors.size() > error_count and results.size() == result_count, "discarding capture SH requires explicit base-color permission")
	capture.dc_only = true
	var capture_result := await bake(capture)
	valid_bundle(capture_result)
	var uppercase := settings()
	uppercase.source_path = inputs.uppercase_source_path
	uppercase.target_path = inputs.uppercase_target_path
	valid_bundle(await bake(uppercase))
	var external := settings()
	external.source_path = inputs.external_source_path
	var external_result := await bake(external)
	valid_bundle(external_result)
	if not external_result.is_empty():
		var external_bytes := FileAccess.get_file_as_bytes(inputs.external_buffer_path)
		var changed_bytes := external_bytes.duplicate()
		changed_bytes.encode_float(0, changed_bytes.decode_float(0) + 0.15)
		var external_file := FileAccess.open(inputs.external_buffer_path, FileAccess.WRITE)
		external_file.store_buffer(changed_bytes)
		external_file.close()
		var external_changed := await bake(external)
		check(not external_changed.is_empty() and not external_changed.cached and external_changed.manifest != external_result.manifest, "external GLB buffer changes invalidate cached preparation")
		external_file = FileAccess.open(inputs.external_buffer_path, FileAccess.WRITE)
		external_file.store_buffer(external_bytes)
		external_file.close()
	var slow := settings()
	slow.count = 512
	slow.samples = 25000
	slow.mixtures = 8
	result_count = results.size()
	check(job.start(slow), "cancel test launches a preparation job")
	if await wait_for(func(): return int(job.get("process_id")) > 0, "CLI process is running before cancellation"):
		var pid: int = job.get("process_id")
		job.cancel()
		await wait_for(func(): return not job.busy and not OS.is_process_running(pid), "Cancel stops the owned CLI process promptly", 5000)
		check(results.size() == result_count, "canceled work never publishes partial output")
	else:
		job.cancel()
	var retry := await bake(settings())
	check(not retry.is_empty() and retry.cached, "Prepare remains usable after cancellation")
	job.shutdown()
	job.queue_free()
	await get_tree().process_frame

func find_controller() -> Node:
	var nodes := get_tree().get_nodes_in_group("gaussian_cake_preparation_controllers")
	for candidate in nodes:
		if not candidate.is_queued_for_deletion() and candidate._alive: return candidate
	return null

func form_nodes() -> Array[Node]:
	var result: Array[Node] = []
	for child in scene.find_children("*","Node",true,false):
		if child is Player: result.append(child)
	return result

func click_prepare(spec: Dictionary) -> void:
	controller.panel.configure(spec)
	var button := controller.panel.find_child("Prepare",true,false) as Button
	check(button != null and not button.disabled, "preparation dock exposes an enabled Prepare button")
	if button != null and not button.disabled: button.pressed.emit()

func wait_player(expected_path: String = "") -> bool:
	return await wait_for(func(): return is_instance_valid(player) and player.initialized and not player.loading and not player.preview_preparing and (expected_path.is_empty() or player.library_path == expected_path), "generated library imports and the preview node becomes ready")

func editor_checks() -> void:
	var editor := get_editor_interface()
	await wait_for(func(): return find_controller() != null, "addon registers preparation controller")
	controller = find_controller()
	if controller == null: return
	editor.open_scene_from_path("res://preparation_workspace.tscn")
	await wait_for(func(): return editor.get_edited_scene_root() != null and editor.get_edited_scene_root().scene_file_path == "res://preparation_workspace.tscn", "test scene is active")
	scene = editor.get_edited_scene_root()
	editor.get_selection().clear()
	editor.get_selection().add_node(scene)
	editor.edit_node(scene)
	var picker: Control = controller.panel.find_child("SourceModel",true,false).find_child("Path",true,false)
	check(picker.get_script().is_tool(), "model path field runs its drag-and-drop methods in the editor")
	check(picker._can_drop_data(Vector2.ZERO,{"files":PackedStringArray([inputs.source_path])}), "model field accepts one GLB file")
	check(not picker._can_drop_data(Vector2.ZERO,{"files":PackedStringArray([inputs.source_path,inputs.target_path])}), "model field rejects ambiguous multi-file drops")
	check(not picker._can_drop_data(Vector2.ZERO,{"files":PackedStringArray([inputs.cli_path])}), "model field rejects unsupported file types")
	var changed := [false]
	controller.panel.settings_changed.connect(func(_settings: Dictionary): changed[0] = true, CONNECT_ONE_SHOT)
	picker._drop_data(Vector2.ZERO,{"files":PackedStringArray([inputs.source_path])})
	check(changed[0] and controller.panel.get_settings().source_path == inputs.source_path, "file drop updates preparation settings")
	await click_prepare(settings())
	if not await wait_for(func(): return form_nodes().size() == 1, "Prepare creates a form player in the active scene"):
		return
	player = form_nodes()[0]
	if not await wait_player(): return
	await wait_for(func(): return not controller._applying, "scene assignment finishes before undo")
	check(player.owner == scene, "generated preview node belongs to the editable scene")
	check(player.renderer_mode == "splats" and player.splat_count == 128, "prepared PLY/GLB pair previews as Gaussian splats")
	check(player.preview_source == player.names[0] and player.preview_target == player.names[1], "prepared source and target are selected automatically")
	var original_path: String = player.library_path
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	check(history != null and history.has_undo(), "preview node creation enters scene undo history")
	if history != null:
		history.undo()
		await wait_for(func(): return form_nodes().is_empty(), "Undo removes the created preview node")
		history.redo()
		await wait_for(func(): return form_nodes().size() == 1, "Redo restores the preview node")
		player = form_nodes()[0]
		await wait_player(original_path)
	editor.get_selection().clear()
	editor.get_selection().add_node(player)
	editor.edit_node(player)
	var original_graph := Graph.default_graph(player.names)
	player.state_machine_override = original_graph
	var swapped := settings()
	swapped.source_path = inputs.target_path
	swapped.target_path = inputs.source_path
	await click_prepare(swapped)
	await wait_for(func(): return player.library_path != original_path, "Prepare updates the selected existing form player")
	await wait_player()
	await wait_for(func(): return not controller._applying, "replacement assignment finishes before undo")
	check(form_nodes().size() == 1, "selected-node preparation does not create duplicate preview nodes")
	check(player.state_machine_override.is_empty(), "replacement preparation clears the previous library's state graph override")
	var swapped_path: String = player.library_path
	if history != null:
		history.undo()
		await wait_player(original_path)
		check(player.state_machine_override == original_graph, "Undo restores the previous state graph with its library")
		history.redo()
		await wait_player(swapped_path)
		check(player.state_machine_override.is_empty(), "Redo clears the previous graph again")
	player.preview_progress = 0.5
	await wait_player()
	check(is_equal_approx(player.progress, 0.5), "prepared forms scrub through the existing Inspector preview")
	editor.get_selection().clear()
	editor.get_selection().add_node(player)
	editor.edit_node(player)
	await wait_for(func(): return editor.get_inspector().get_edited_object() == player and editor.get_inspector().find_child("OpenMorphPreparation",true,false) != null, "Inspector exposes the model preparation launcher")
	var launch_button := editor.get_inspector().find_child("OpenMorphPreparation",true,false) as Button
	if launch_button != null: launch_button.pressed.emit()
	await wait_for(func(): return controller.panel.is_visible_in_tree(), "Inspector launcher opens the preparation dock")
	player.name = "PreparedMorph"
	scene.set_script(load("res://preparation_smoke.gd"))
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK and ResourceSaver.save(packed,"res://preparation_smoke.tscn") == OK, "prepared preview scene saves for standalone runtime checks")
	check(packed.get_state().get_node_count() == 2, "generated render children are excluded from saved scene")
	if "--preparation-capture" in OS.get_cmdline_user_args(): await capture_panel()
	# Disabling the addon must terminate the child process, even if its dock disappears.
	var slow := settings()
	slow.count = 511
	slow.samples = 25000
	slow.mixtures = 8
	controller.request_prepare(slow)
	if await wait_for(func(): return int(controller.job.get("process_id")) > 0, "plugin shutdown test starts its CLI process"):
		var pid: int = controller.job.get("process_id")
		editor.set_plugin_enabled("gaussian_cake", false)
		await wait_for(func(): return not OS.is_process_running(pid), "disabling addon stops its preparation subprocess", 5000)
		editor.set_plugin_enabled("gaussian_cake", true)
		await wait_for(func(): return find_controller() != null, "preparation panel returns after enabling addon")
	controller = find_controller()
	if controller != null: controller.job.cancel()

func capture_panel() -> void:
	var editor := get_editor_interface()
	editor.set_main_screen_editor("3D")
	editor.get_selection().clear()
	editor.get_selection().add_node(player)
	editor.edit_node(player)
	await wait_for(func(): return editor.get_inspector().get_edited_object() == player, "capture selects prepared preview")
	editor.get_inspector().expand_all_folding()
	for menu in editor.get_base_control().find_children("*","PopupMenu",true,false):
		for index in range(menu.item_count):
			if menu.get_item_text(index) == "Focus and Frame Selection": menu.id_pressed.emit(menu.get_item_id(index))
	var panel: Control = controller.panel
	controller.show_panel()
	await wait_for(func(): return panel.is_visible_in_tree(), "preparation dock is visible in the rendered editor")
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://out")
	var image := editor.get_base_control().get_viewport().get_texture().get_image()
	check(image.save_png("res://out/preparation-panel.png") == OK, "actual preparation dock screenshot saves")
	print("PREPARATION_CAPTURE ",ProjectSettings.globalize_path("res://out/preparation-panel.png"))

func run() -> void:
	inputs = JSON.parse_string(FileAccess.get_file_as_string("res://test-inputs.json"))
	await wait_for(func(): return not get_editor_interface().get_resource_filesystem().is_scanning(), "editor filesystem is ready")
	await backend_checks()
	await editor_checks()
	await get_tree().process_frame
	await wait_for(func(): return not get_editor_interface().get_resource_filesystem().is_scanning() and not get_editor_interface().get_resource_filesystem().is_importing(), "editor scan settles before shutdown")
	var report := FileAccess.open("res://editor-preparation-result.txt",FileAccess.WRITE)
	report.store_string(str(failures))
	report.close()
	print("Gaussian Cake preparation editor: ",checks," checks, ",failures," failures")
	get_tree().quit(1 if failures else 0)
