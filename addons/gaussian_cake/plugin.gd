@tool
extends EditorPlugin

const Importer = preload("editor/splat_importer.gd")
const TopologyPlayer = preload("runtime/topology_player_3d.gd")
const SplatPlayer = preload("runtime/splat_player_3d.gd")
var _importer: EditorImportPlugin

func _enter_tree() -> void:
	_importer = Importer.new()
	add_import_plugin(_importer)
	var icon := get_editor_interface().get_base_control().get_theme_icon("MeshInstance3D", "EditorIcons")
	add_custom_type("GaussianCakeTopologyPlayer3D", "Node3D", TopologyPlayer, icon)
	add_custom_type("GaussianCakeSplatPlayer3D", "Node3D", SplatPlayer, icon)
	set_process(true)

func _exit_tree() -> void:
	set_process(false)
	remove_custom_type("GaussianCakeTopologyPlayer3D")
	remove_custom_type("GaussianCakeSplatPlayer3D")
	if _importer != null:
		remove_import_plugin(_importer)
		_importer = null
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

