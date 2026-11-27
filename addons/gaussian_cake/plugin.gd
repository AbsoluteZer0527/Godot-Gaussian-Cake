@tool
extends EditorPlugin

const SplatImporter = preload("editor/splat_importer.gd")
const TopologyPlayer = preload("runtime/topology_player_3d.gd")
const SplatPlayer = preload("runtime/splat_player_3d.gd")
const FormImporter = preload("editor/form_importer.gd")
const FormPlayer = preload("runtime/form_player_3d.gd")
const MapImporter = preload("editor/transport_map_importer.gd")
const FormInspector = preload("editor/form_inspector_plugin.gd")
const FormGraph = preload("editor/form_graph_editor.gd")
var _form_graph: Control
const PreparationController = preload("editor/preparation_controller.gd")
const PreparationExport = preload("editor/preparation_export_plugin.gd")
var _map_importer: EditorImportPlugin
var _splat_importer: EditorImportPlugin
var _form_importer: EditorImportPlugin
var _form_inspector: EditorInspectorPlugin
var _selection: EditorSelection
var _preparation: Node
var _preparation_export: EditorExportPlugin

func _enter_tree() -> void:
	_form_graph = FormGraph.new()
	_form_graph.undo_manager = get_undo_redo()
	add_control_to_bottom_panel(_form_graph, "Form states")
	_form_inspector = FormInspector.new()
	add_inspector_plugin(_form_inspector)
	_selection = get_editor_interface().get_selection()
	_selection.selection_changed.connect(_pause_unselected_previews)
	_map_importer = MapImporter.new()
	add_import_plugin(_map_importer)
	_splat_importer = SplatImporter.new()
	add_import_plugin(_splat_importer)
	_form_importer = FormImporter.new()
	add_import_plugin(_form_importer)
	var icon := get_editor_interface().get_base_control().get_theme_icon("MeshInstance3D", "EditorIcons")
	add_custom_type("GaussianCakeTopologyPlayer3D", "Node3D", TopologyPlayer, icon)
	add_custom_type("GaussianCakeSplatPlayer3D", "Node3D", SplatPlayer, icon)
	add_custom_type("GaussianCakeFormPlayer3D", "Node3D", FormPlayer, icon)
	_preparation_export = PreparationExport.new()
	add_export_plugin(_preparation_export)
	_preparation = PreparationController.new()
	add_child(_preparation)
	_preparation.initialize(self)
	_form_inspector.preparation_requested.connect(_preparation.show_panel)
	set_process(true)

func _exit_tree() -> void:
	if _form_graph != null:
		_form_graph.bind_player(null)
		remove_control_from_bottom_panel(_form_graph)
		_form_graph.queue_free()
		_form_graph = null
	set_process(false)
	if is_instance_valid(_preparation):
		_preparation.shutdown()
		_preparation.queue_free()
		_preparation = null
	if _preparation_export != null:
		remove_export_plugin(_preparation_export)
		_preparation_export = null
	if _selection != null and _selection.selection_changed.is_connected(_pause_unselected_previews):
		_selection.selection_changed.disconnect(_pause_unselected_previews)
	_selection = null
	for player in get_tree().get_nodes_in_group("gaussian_cake_form_previews"):
		player.editor_preview_pause()
	if _form_inspector != null:
		remove_inspector_plugin(_form_inspector)
		_form_inspector = null
	remove_custom_type("GaussianCakeTopologyPlayer3D")
	remove_custom_type("GaussianCakeSplatPlayer3D")
	remove_custom_type("GaussianCakeFormPlayer3D")
	if _map_importer != null:
		remove_import_plugin(_map_importer)
		_map_importer = null
	if _form_importer != null:
		remove_import_plugin(_form_importer)
		_form_importer = null
	if _splat_importer != null:
		remove_import_plugin(_splat_importer)
		_splat_importer = null
	for player in get_tree().get_nodes_in_group("gaussian_cake_editor_splats"):
		player.set_preview_camera(null)

func _process(_delta: float) -> void:
	# Editor-only access stays here; runtime scripts work without EditorInterface.
	var viewport := get_editor_interface().get_editor_viewport_3d(0)
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	for player in get_tree().get_nodes_in_group("gaussian_cake_editor_splats"):
		player.set_preview_camera(camera)

func _pause_unselected_previews() -> void:
	if _selection == null:
		return
	var selected := _selection.get_selected_nodes()
	var form_selection: Node = null
	for node in selected:
		if node is FormPlayer:
			form_selection = node
			break
	if _form_graph != null: _form_graph.bind_player(form_selection)
	for player in get_tree().get_nodes_in_group("gaussian_cake_form_previews"):
		if not selected.has(player):
			player.editor_preview_pause()

