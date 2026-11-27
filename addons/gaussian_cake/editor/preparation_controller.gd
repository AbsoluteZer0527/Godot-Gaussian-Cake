@tool
extends Node
## Owns the dock, background job and undoable handoff into the edited scene.
const Job = preload("preparation_job.gd")
const PreparationPanel = preload("preparation_panel.gd")
const FormPlayer = preload("../runtime/form_player_3d.gd")

var job: Node
var panel: Control
var _dock: EditorDock
var prepared_manifest := ""
var source_name := ""
var target_name := ""
var _plugin: EditorPlugin
var _editor: EditorInterface
var _alive := false
var _applying := false
var _delivery := 0
var _status_override := ""
var _requested_scene: WeakRef
var _requested_player: WeakRef

func initialize(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_editor = plugin.get_editor_interface()
	_alive = true
	add_to_group("gaussian_cake_preparation_controllers")
	job = Job.new()
	add_child(job)
	panel = PreparationPanel.new()
	var settings: Variant = _editor.get_editor_settings().get_project_metadata("gaussian_cake", "preparation", {})
	if not settings is Dictionary: settings = {}
	if str(settings.get("cli_path", "")).is_empty(): settings["cli_path"] = find_cli()
	panel.configure(settings)
	panel.prepare_requested.connect(request_prepare)
	panel.cancel_requested.connect(_cancel)
	panel.use_result_requested.connect(use_result)
	job.changed.connect(_sync_job)
	job.prepared.connect(_on_prepared)
	_dock = EditorDock.new()
	_dock.title = "Gaussian Cake"
	_dock.layout_key = "gaussian_cake_preparation"
	_dock.icon_name = &"MeshInstance3D"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_dock.add_child(panel)
	_plugin.add_dock(_dock)
	_plugin.add_tool_menu_item("Prepare Gaussian Cake morph…", show_panel)
	_editor.get_selection().selection_changed.connect(_selection_changed)
	_plugin.scene_changed.connect(_scene_changed)
	_selection_changed()
	_sync_job()

func show_panel() -> void:
	if _alive and is_instance_valid(_dock): _dock.make_visible()

static func find_cli() -> String:
	var configured := OS.get_environment("GAUSSIAN_CAKE_CLI")
	if not configured.is_empty() and FileAccess.file_exists(configured): return configured
	var executable := "gc_cli.exe" if OS.get_name() == "Windows" else "gc_cli"
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var candidates: Array[String] = []
	for build in ["build/Release", "build"]:
		candidates.append(root.get_base_dir().path_join("Gaussian-Cake").path_join(build).path_join(executable))
		candidates.append(root.path_join(build).path_join(executable))
	for path in candidates:
		if FileAccess.file_exists(path): return path
	return ""

func _selected_player() -> Node:
	var scene := _editor.get_edited_scene_root()
	for selected in _editor.get_selection().get_selected_nodes():
		if selected is FormPlayer and scene != null and (selected == scene or scene.is_ancestor_of(selected)):
			return selected
	return null

func _scene_changed(_scene: Node) -> void:
	_selection_changed()

func _selection_changed() -> void:
	if not _alive: return
	var selected := _selected_player()
	if selected != null:
		panel.set_target_description("Will replace the library on: " + str(selected.name))
	elif _editor.get_edited_scene_root() != null:
		panel.set_target_description("Will add a PreparedMorph node to this scene.")
	else:
		panel.set_target_description("Open a 3D scene to use the prepared morph.")

func request_prepare(settings: Dictionary) -> void:
	if not _alive or job.busy or _applying: return
	_delivery += 1
	_status_override = ""
	var scene := _editor.get_edited_scene_root()
	var selected := _selected_player()
	_requested_scene = weakref(scene) if scene != null else null
	_requested_player = weakref(selected) if selected != null else null
	_editor.get_editor_settings().set_project_metadata("gaussian_cake", "preparation", settings)
	job.start(settings)

func _sync_job() -> void:
	if not _alive: return
	panel.set_job_state(job.busy, _status_override if not _status_override.is_empty() else job.status, job.log_text)
	panel.set_applying(_applying)

func _on_prepared(manifest: String, from_name: String, to_name: String, cached: bool) -> void:
	if not _alive: return
	prepared_manifest = manifest
	source_name = from_name
	target_name = to_name
	panel.set_result(manifest, from_name, to_name, cached)
	var scene: Node = _requested_scene.get_ref() if _requested_scene != null else null
	var selected: Node = _requested_player.get_ref() if _requested_player != null else null
	if scene == null or scene != _editor.get_edited_scene_root():
		_status_override = "Prepared. Open the desired scene and click Use in scene."
		_sync_job()
		return
	if _requested_player != null and selected == null:
		_status_override = "Prepared. The selected player was removed; select another node and click Use in scene."
		_sync_job()
		return
	_import_and_apply(scene, selected, _delivery)

func use_result() -> void:
	if not _alive or job.busy or _applying or prepared_manifest.is_empty(): return
	var scene := _editor.get_edited_scene_root()
	if scene == null:
		_status_override = "Open a 3D scene, then click Use in scene."
		_sync_job()
		return
	_delivery += 1
	_import_and_apply(scene, _selected_player(), _delivery)

func _cancel() -> void:
	_delivery += 1
	if _applying:
		_applying = false
		_status_override = "Scene assignment cancelled. Prepared files are available through Use in scene."
	else:
		_status_override = ""
	job.cancel()
	_sync_job()

func _import_and_apply(scene: Node, selected: Node, ticket: int) -> void:
	_applying = true
	_status_override = "Importing the prepared morph into Godot…"
	_sync_job()
	var manifest_path := prepared_manifest
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary or not manifest.has("splats"):
		_finish_apply("Prepared library is missing or invalid. Prepare again.", ticket)
		return
	var splat_path: String = manifest_path.get_base_dir().path_join(manifest.splats)
	var filesystem := _editor.get_resource_filesystem()
	# Scanning is asynchronous; file existence alone does not mean its importer ran.
	filesystem.scan()
	var deadline := Time.get_ticks_msec() + 60000
	while _alive and ticket == _delivery:
		if not filesystem.is_scanning() and not filesystem.is_importing() and not filesystem.get_file_type(splat_path).is_empty() and ResourceLoader.exists(splat_path):
			break
		if Time.get_ticks_msec() >= deadline:
			_finish_apply("Import did not finish. Check Godot's Output, then click Use in scene to retry.", ticket)
			return
		await get_tree().process_frame
	if not _alive or ticket != _delivery: return
	if not is_instance_valid(scene) or scene != _editor.get_edited_scene_root():
		_finish_apply("Prepared. The edited scene changed; click Use in scene when ready.", ticket)
		return
	if not is_instance_valid(selected) or (selected != scene and not scene.is_ancestor_of(selected)):
		selected = null
	var player := _assign_player(scene, selected)
	_editor.get_selection().clear()
	_editor.get_selection().add_node(player)
	_editor.edit_node(player)
	_editor.set_main_screen_editor("3D")
	deadline = Time.get_ticks_msec() + 15000
	while _alive and ticket == _delivery and is_instance_valid(player):
		if not player.error.is_empty():
			_finish_apply("Prepared library could not load: " + player.error, ticket)
			return
		if player.initialized and not player.preview_preparing and _editor.get_inspector().get_edited_object() == player:
			_editor.get_inspector().expand_all_folding()
			_finish_apply("Ready. Use Morph Preview in the Inspector to scrub or play.", ticket)
			return
		if Time.get_ticks_msec() >= deadline: break
		await get_tree().process_frame
	_finish_apply("Assigned. Select the form player and open Morph Preview in the Inspector.", ticket)

func _assign_player(scene: Node, selected: Node) -> Node:
	var undo := _plugin.get_undo_redo()
	var player: Node = selected
	if player == null:
		player = FormPlayer.new()
		player.name = "PreparedMorph"
		player.library_path = prepared_manifest
		player.renderer_mode = "splats"
		player.preview_source = source_name
		player.preview_target = target_name
		player.preview_progress = 0.0
		player.duration = 4.0
		undo.create_action("Add prepared Gaussian Cake morph", UndoRedo.MERGE_DISABLE, scene)
		undo.add_do_method(scene, "add_child", player, true)
		undo.add_do_property(player, "owner", scene)
		undo.add_undo_method(scene, "remove_child", player)
		undo.add_do_reference(player)
	else:
		undo.create_action("Assign prepared Gaussian Cake morph", UndoRedo.MERGE_DISABLE, scene)
		var values := {"library_path": prepared_manifest, "renderer_mode": "splats", "preview_source": source_name, "preview_target": target_name, "preview_progress": 0.0}
		# A state graph for a different set of forms cannot validate against this
		# two-form library. Reset it with the same undo action as the assignment.
		if player.has_method("get_state_machine") and player.names != PackedStringArray([source_name, target_name]):
			values["state_machine_override"] = {}
		for property in values:
			undo.add_do_property(player, property, values[property])
			undo.add_undo_property(player, property, player.get(property))
	undo.commit_action()
	return player

func _finish_apply(message: String, ticket: int) -> void:
	if not _alive or ticket != _delivery: return
	_applying = false
	_status_override = message
	_sync_job()

func shutdown() -> void:
	if not _alive: return
	_alive = false
	_delivery += 1
	_editor.get_editor_settings().set_project_metadata("gaussian_cake", "preparation", panel.get_settings())
	var selection := _editor.get_selection()
	if selection.selection_changed.is_connected(_selection_changed): selection.selection_changed.disconnect(_selection_changed)
	if _plugin.scene_changed.is_connected(_scene_changed): _plugin.scene_changed.disconnect(_scene_changed)
	job.shutdown()
	_plugin.remove_tool_menu_item("Prepare Gaussian Cake morph…")
	_plugin.remove_dock(_dock)
	_dock.queue_free()

func _exit_tree() -> void:
	shutdown()
