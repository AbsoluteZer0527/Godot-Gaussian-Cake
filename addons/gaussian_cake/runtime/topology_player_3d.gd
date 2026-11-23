@tool
extends "playback_3d.gd"
## Godot's native GLB import supplies the mesh, materials and animation tracks.

@export_group("Topology Asset")
@export var source_scene: PackedScene:
	set(value):
		if source_scene != null and source_scene.changed.is_connected(_queue_rebuild):
			source_scene.changed.disconnect(_queue_rebuild)
		source_scene = value
		if source_scene != null:
			source_scene.changed.connect(_queue_rebuild)
		_queue_rebuild()
@export var animation_name: StringName = &"":
	set(value):
		animation_name = value
		_queue_rebuild()
## Some Godot imports leave COLOR_0 disabled on StandardMaterial3D.
## Use per-instance overrides, preserving the shared imported materials.
@export var use_vertex_colors := true:
	set(value):
		use_vertex_colors = value
		_queue_rebuild()

var _model: Node
var _animation_player: AnimationPlayer
var _selected_animation: StringName
var _last_time := -1.0

func get_animation_names() -> PackedStringArray:
	return _animation_player.get_animation_list() if is_instance_valid(_animation_player) else PackedStringArray()

func _rebuild() -> void:
	super._rebuild()
	if not is_inside_tree():
		return
	_animation_player = null
	_last_time = -1.0
	if is_instance_valid(_model):
		if _model.get_parent() == self:
			remove_child(_model)
			_model.queue_free()
	_model = null
	if source_scene == null:
		_fail("Assign a shared-topology GLB to Source Scene.")
		return
	_model = source_scene.instantiate()
	if _model == null:
		_fail("Could not instantiate Source Scene.")
		return
	if use_vertex_colors:
		_enable_vertex_colors(_model)
	var players: Array[AnimationPlayer] = []
	_collect_players(_model, players)
	for candidate in players:
		candidate.autoplay = ""
		candidate.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	# Generated children have no scene owner, so saving the player does not duplicate the asset.
	add_child(_model)
	for candidate in players:
		candidate.stop(true)
	for candidate in players:
		for name in candidate.get_animation_list():
			if name != "RESET" and (animation_name.is_empty() or name == animation_name):
				_animation_player = candidate
				_selected_animation = name
				break
		if _animation_player != null:
			break
	if _animation_player == null:
		_fail("No matching animation. Keep Animation > Import enabled on the GLB and check Animation Name.")
		return
	var animation := _animation_player.get_animation(_selected_animation)
	if animation.length <= 0.0:
		_fail("The selected animation has no duration.")
		return
	# Do not change loop_mode on the shared Animation resource.
	_animation_player.play(_selected_animation)
	_animation_player.pause()
	_initialize_playback(animation.length)

func _collect_players(node: Node, result: Array[AnimationPlayer]) -> void:
	if node is AnimationPlayer:
		result.append(node)
	for child in node.get_children():
		_collect_players(child, result)

func _enable_vertex_colors(node: Node) -> void:
	if node is MeshInstance3D and node.mesh is ArrayMesh:
		for surface in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var colors = arrays[Mesh.ARRAY_COLOR]
			var material = node.get_active_material(surface)
			if colors != null and not colors.is_empty() and material is BaseMaterial3D and not material.vertex_color_use_as_albedo:
				var local: BaseMaterial3D = material.duplicate()
				local.vertex_color_use_as_albedo = true
				node.set_surface_override_material(surface, local)
	for child in node.get_children():
		_enable_vertex_colors(child)

func _render_frame() -> void:
	if not is_instance_valid(_animation_player) or _last_time == time:
		return
	_animation_player.seek(time, true, true)
	_last_time = time
