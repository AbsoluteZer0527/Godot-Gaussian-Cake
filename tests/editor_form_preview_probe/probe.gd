@tool
extends EditorPlugin
const Player = preload("res://addons/gaussian_cake/runtime/form_player_3d.gd")
const Decoder = preload("res://addons/gaussian_cake/runtime/form_decoder.gd")
const TINY := "res://assets/tiny/library.json"
const COMBINED := "res://assets/combined/library.json"
const COMPLEX := "res://assets/complex/library.json"
var checks := 0
var failures := 0
var player: Node

func _enter_tree() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("EDITOR TEST FAIL: " + label)

func wait_for(condition: Callable, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var complete: bool = condition.call()
	check(complete, label)
	return complete

func prepared() -> bool:
	return await wait_for(func(): return player.initialized and not player.preview_preparing and not player.loading, "preview prepares %s to %s at %.2f" % [player.preview_source, player.preview_target, player.preview_progress])

func property_editor(property: String) -> EditorProperty:
	for candidate in get_editor_interface().get_inspector().find_children("*", "EditorProperty", true, false):
		if not candidate.is_queued_for_deletion() and candidate.get_edited_object() == player and candidate.get_edited_property() == property:
			return candidate
	return null

func history_settled(history: UndoRedo) -> void:
	await wait_for(func(): return not get_undo_redo().is_committing_action() and not history.is_committing_action(), "Inspector history action finishes committing")

func selector(property: String) -> OptionButton:
	var editor := property_editor(property)
	return editor.find_child("FormOption", true, false) as OptionButton if editor != null else null

func choose(property: String, name: String) -> void:
	await wait_for(func(): return selector(property) != null, "Inspector dropdown is rebuilt before selecting " + property)
	var option := selector(property)
	check(option != null and not option.disabled, property + " is an enabled Inspector dropdown")
	if option == null or option.disabled: return
	var found := -1
	for index in range(option.item_count):
		if option.get_item_metadata(index) == name: found = index; break
	check(found >= 0, "dropdown contains exact form name " + name)
	if found < 0: return
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(player))
	var version := history.get_version()
	option.select(found)
	option.item_selected.emit(found)
	await wait_for(func(): return player.get(property) == name, "Inspector selection commits " + property)
	await wait_for(func(): return history.get_version() > version, "Inspector records selection in undo history")
	await history_settled(history)
	await prepared()

func show_player() -> void:
	var editor := get_editor_interface()
	editor.get_selection().clear()
	editor.get_selection().add_node(player)
	editor.edit_node(player)
	await wait_for(func(): return editor.get_inspector().get_edited_object() == player, "Inspector finishes selecting the preview node")
	await wait_for(func(): return selector("preview_source") != null and selector("preview_target") != null, "real Inspector uses custom form dropdowns")
	# Native editors can be built lazily in a folded group. Expanding before
	# edit_node's deferred Inspector rebuild only expands the previous object.
	editor.get_inspector().expand_all_folding()
	await wait_for(func(): return property_editor("preview_progress") != null, "expanded Morph Preview exposes its native progress control")

func near(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	if a.size() != b.size(): return false
	for index in range(a.size()):
		if absf(a[index] - b[index]) > 0.00005: return false
	return true

func check_pose(source: String, target: String, amount: float, refined: bool = false) -> void:
	var a: int = player.names.find(source)
	var b: int = player.names.find(target)
	check(a >= 0 and b >= 0, "pose endpoints exist")
	if a < 0 or b < 0: return
	var source_records: PackedFloat32Array = player._decoder.records(a)
	var destination_records: PackedFloat32Array = player._decoder.records(b)
	var mapping: PackedInt32Array = player.transport_maps.get("%d:%d" % [a,b], {}).get("ids", PackedInt32Array())
	for index in [0, mini(2, player.splat_count-1)]:
		var destination_index: int = mapping[index] if refined and not mapping.is_empty() else index
		var expected := Decoder.interpolate_record(source_records.slice(index*14,index*14+14), destination_records.slice(destination_index*14,destination_index*14+14), smoothstep(0.0,1.0,amount), 0)
		check(near(player.splat_attributes(index), expected), "displayed splat %d agrees with %s to %s at %.2f" % [index,source,target,amount])

func run() -> void:
	var editor := get_editor_interface()
	await wait_for(func(): return not editor.get_resource_filesystem().is_scanning(), "editor filesystem is ready")
	var scene := editor.get_edited_scene_root()
	if scene == null:
		scene = Node3D.new()
		scene.name = "FormPreviewTests"
		editor.add_root_node(scene)
	player = Player.new()
	player.name = "Morph"
	player.library_path = TINY
	player.preview_source = "slime"
	player.preview_target = "apple"
	player.preview_progress = 0.5
	scene.add_child(player)
	player.owner = scene
	if not await prepared(): finish(); return
	await show_player()
	check(selector("preview_source").item_count == player.names.size(), "dropdown lists the whole assigned library")
	check_pose("slime", "apple", 0.5)
	await choose("preview_source", "apple")
	await choose("preview_target", "mushroom")
	check_pose("apple", "mushroom", player.preview_progress)
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(player))
	check(history != null and history.has_undo(), "Inspector changes enter scene undo history")
	if history != null:
		await history_settled(history)
		history.undo()
		await wait_for(func(): return player.preview_target == "apple", "undo restores target form")
		await prepared()
		await history_settled(history)
		history.redo()
		await wait_for(func(): return player.preview_target == "mushroom", "redo restores target form")
		await prepared()
	await show_player()
	# Undo/redo may rebuild the native Inspector on a later editor frame even
	# though the player's deferred preview preparation has already completed.
	await wait_for(func(): return property_editor("preview_progress") != null, "Inspector progress control finishes rebuilding")
	var progress_editor := property_editor("preview_progress")
	check(progress_editor != null, "Inspector exposes normalized progress")
	var progress_version := history.get_version() if history != null else -1
	if progress_editor != null: progress_editor.emit_changed("preview_progress", 0.3)
	await wait_for(func(): return is_equal_approx(player.preview_progress, 0.3), "Inspector progress commits")
	await prepared()
	check_pose("apple", "mushroom", 0.3)
	if history != null:
		await wait_for(func(): return history.get_version() > progress_version, "Inspector records progress in undo history")
		await history_settled(history)
		history.undo()
		await wait_for(func(): return is_equal_approx(player.preview_progress,0.5), "undo restores Inspector progress")
		await prepared()
		check_pose("apple", "mushroom", 0.5)
		await history_settled(history)
		history.redo()
		await wait_for(func(): return is_equal_approx(player.preview_progress,0.3), "redo restores Inspector progress")
		await prepared()
		check_pose("apple", "mushroom", 0.3)
	# Scrubbing an unchanged pair must reuse its endpoint textures and canonical IDs.
	await wait_for(func(): return player.splats._frame_a != null and player.splats._frame_b != null, "preview endpoint textures are uploaded")
	var frame_a: ImageTexture = player.splats._frame_a
	var frame_b: ImageTexture = player.splats._frame_b
	var ids: PackedInt32Array = player.canonical_ids()
	for amount in [0.1,0.7,0.3]:
		player.preview_progress = amount
		await prepared()
		check_pose("apple", "mushroom", amount)
		check(player.splats._frame_a == frame_a and player.splats._frame_b == frame_b and player.canonical_ids() == ids, "scrubbing reuses pair textures and endpoint ordering")
	player.set_process(false)
	player.duration = 2.0
	player.editor_preview_toggle()
	check(player.preview_playing, "Play starts editor clock")
	player._process(0.4)
	check(is_equal_approx(player.preview_progress, 0.5), "preview clock respects Duration")
	player.editor_preview_toggle()
	check(not player.preview_playing, "Pause stops editor clock")
	player._process(0.4)
	check(is_equal_approx(player.preview_progress, 0.5), "paused preview holds pose")
	player.preview_loop = true
	player.preview_progress = 0.95
	await prepared()
	player.editor_preview_toggle()
	player._process(0.2)
	check(player.preview_playing and player.preview_progress < 0.2, "loop wraps and keeps playing")
	player.editor_preview_reset()
	await prepared()
	check(not player.preview_playing and player.preview_progress == 0.0, "Reset returns to source and pauses")
	check_pose("apple", "mushroom", 0.0)
	player.preview_loop = false
	player.preview_progress = 0.9
	await prepared()
	player.editor_preview_toggle()
	player._process(0.4)
	check(not player.preview_playing and player.preview_progress == 1.0, "non-loop preview stops at the target")
	check_pose("apple", "mushroom", 1.0)
	player.editor_preview_toggle()
	check(player.preview_playing and player.preview_progress == 0.0, "Play at the endpoint restarts from source")
	player.editor_preview_pause()
	player.set_process(true)
	player.preview_target = "apple"
	player.preview_progress = 0.6
	await prepared()
	player.editor_preview_toggle()
	check(not player.preview_playing, "identical source and target stays static")
	check_pose("apple", "apple", 0.6)
	player.preview_source = "slime"
	player.preview_target = "apple"
	player.transport_mode = "refined"
	player.preview_progress = 0.4
	await prepared()
	check(player.last_transport == "refined", "editor preview uses prepared pair map")
	check_pose("slime", "apple", 0.4, true)
	player.library_path = COMPLEX
	await prepared()
	await show_player()
	check(player.splat_count == 48000 and selector("preview_target").item_count == 3, "library replacement refreshes dropdowns and count")
	player.preview_source = "cactus"
	player.preview_target = "island"
	player.preview_progress = 0.1
	await get_tree().process_frame
	player.preview_source = "island"
	player.preview_target = "reef"
	for value in [0.2,0.8,0.35,0.63]: player.preview_progress = value
	await prepared()
	check(player.preview_source == "island" and player.preview_target == "reef" and is_equal_approx(player.preview_progress,0.63), "rapid pair and scrub edits retain the latest request")
	check_pose("island", "reef", 0.63, true)
	player.preview_progress = 0.0
	await prepared()
	check_pose("island", "reef", 0.0, true)
	player.preview_progress = 1.0
	await prepared()
	check_pose("island", "reef", 1.0, true)
	player.library_path = COMBINED
	await prepared()
	player.preview_source = "slime"
	player.preview_target = "apple"
	player.transport_mode = "shared"
	player.preview_progress = 0.35
	await prepared()
	player.renderer_mode = "topology"
	check(player.topology.visible and not player.splats.visible, "topology preview is visible")
	var weights: PackedFloat32Array = player.topology_weights()
	var eased := smoothstep(0.0,1.0,0.35)
	check(is_equal_approx(weights[player.names.find("apple")],eased) and is_equal_approx(weights[0],1.0-eased), "topology preview uses the same progress")
	player.renderer_mode = "splats"
	check(player.splats.visible and not player.topology.visible, "splat preview is visible")
	check(player.topology_weights() == weights, "renderer switch preserves preview pose")
	check_pose("slime", "apple", 0.35)
	var packed := PackedScene.new()
	check(packed.pack(player) == OK, "preview node can be packed")
	check(packed.get_state().get_node_count() == 1, "generated renderer children do not serialize")
	check(ResourceSaver.save(packed,"res://preview_saved.tscn") == OK, "preview scene saves")
	var restored := packed.instantiate()
	check(restored.preview_source == "slime" and restored.preview_target == "apple" and is_equal_approx(restored.preview_progress,0.35), "source target and progress survive scene saving")
	restored.free()
	await show_player()
	if "--preview-capture" in OS.get_cmdline_user_args(): await capture_preview()
	player.editor_preview_toggle()
	check(player.preview_playing, "selected preview can play")
	editor.get_selection().clear()
	await wait_for(func(): return not player.preview_playing, "deselecting pauses preview")
	await show_player()
	player.editor_preview_toggle()
	editor.set_plugin_enabled("gaussian_cake",false)
	await wait_for(func(): return not player.preview_playing, "disabling plugin pauses preview")
	editor.set_plugin_enabled("gaussian_cake",true)
	await wait_for(func(): return editor.is_plugin_enabled("gaussian_cake"), "addon re-enables")
	player.library_path = "res://missing-library.json"
	await wait_for(func(): return not player.loading and not player.error.is_empty(), "missing library reports a useful error")
	await show_player()
	check(not player.editor_preview_status().is_empty(), "preview status explains missing library")
	check(selector("preview_target").disabled, "unavailable preview dropdown is disabled")
	player.library_path = TINY
	await prepared()
	check(player.error.is_empty(), "preview recovers after assigning valid library")
	editor.get_selection().clear()
	editor.get_inspector().edit(null)
	player.queue_free()
	await get_tree().process_frame
	finish()

func capture_preview() -> void:
	var editor := get_editor_interface()
	editor.set_main_screen_editor("3D")
	editor.get_inspector().expand_all_folding()
	# Invoke the editor's own framing command when available; keep its real viewport
	# and registered Inspector controls in the capture, rather than building a mock UI.
	for menu in editor.get_base_control().find_children("*", "PopupMenu", true, false):
		for index in range(menu.item_count):
			if menu.get_item_text(index) == "Focus and Frame Selection":
				menu.id_pressed.emit(menu.get_item_id(index))
	var progress_control := property_editor("preview_progress")
	if progress_control != null: editor.get_inspector().ensure_control_visible(progress_control)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://out")
	var image := editor.get_base_control().get_viewport().get_texture().get_image()
	check(image.save_png("res://out/inspector-preview.png") == OK, "real editor preview screenshot saves")
	print("FORM_PREVIEW_CAPTURE ",ProjectSettings.globalize_path("res://out/inspector-preview.png"))

func finish() -> void:
	var report := FileAccess.open("res://editor-form-preview-result.txt",FileAccess.WRITE)
	report.store_string(str(failures))
	report.close()
	print("Gaussian Cake form editor: ",checks," checks, ",failures," failures")
	get_tree().quit(1 if failures else 0)
