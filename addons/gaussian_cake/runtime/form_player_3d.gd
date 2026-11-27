@tool
extends Node3D
## Direct, interruptible morphs across a prepared form library. No pair clips needed.
signal library_ready
signal state_changed
signal morph_finished(form: String)
signal editor_preview_changed
signal transition_rejected(from_form: String, to_form: String)
signal state_graph_changed
const Decoder = preload("form_decoder.gd")
const Manifest = preload("form_manifest.gd")
const StateMachine = preload("form_state_machine.gd")
@export_storage var state_machine_override: Dictionary = {}:
	set(value):
		state_machine_override = value.duplicate(true)
		state_graph_changed.emit()
		if is_inside_tree() and is_node_ready() and not error.is_empty() and not _reload_requested:
			_reload_requested = true
			reload_library.call_deferred()
var _library_state_machine: Dictionary = {}
const SplatRenderer = preload("form_splat_renderer.gd")
const COLOR_SHADER = preload("../shaders/form_colors.gdshader")
@export_file("*.json") var library_path := "":
	set(value):
		library_path = value
		if is_inside_tree() and is_node_ready() and not _reload_requested:
			_reload_requested = true
			reload_library.call_deferred()
@export var camera: Camera3D:
	set(value):
		camera = value
		if is_instance_valid(splats): splats.camera = value
@export_enum("topology", "splats") var renderer_mode := "topology":
	set(value):
		if value != "topology" and value != "splats": return
		if initialized and not is_instance_valid(topology): value = "splats"
		renderer_mode = value
		if initialized: _update_renderer()
@export_range(0.01,30.0,0.05) var duration := 1.5
@export_enum("shared", "refined") var transport_mode := "shared":
	set(value):
		if value != "shared" and value != "refined": return
		transport_mode = value
		_request_editor_preview()
@export var paused := false

## These saved settings only affect the editor viewport, never the game's initial pose.
@export_group("Morph Preview", "preview_")
@export var preview_source := "":
	set(value):
		preview_source = value
		_request_editor_preview()
@export var preview_target := "":
	set(value):
		preview_target = value
		_request_editor_preview()
@export_range(0.0, 1.0, 0.001) var preview_progress := 0.0:
	set(value):
		preview_progress = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
		if _preview_clock_write: return
		if Engine.is_editor_hint():
			_preview_playing = false
		_request_editor_preview()
@export var preview_loop := false
@export_tool_button("Play / Pause", "Play") var preview_play_pause = editor_preview_toggle
@export_tool_button("Reset", "Stop") var preview_reset = editor_preview_reset
@export_group("")

var preview_playing: bool:
	get: return Engine.is_editor_hint() and _preview_playing
var preview_preparing: bool:
	get: return Engine.is_editor_hint() and (_preview_dirty or _preview_sync_queued or loading or _reload_requested)
var last_transport := "shared"
var transition_metrics: Dictionary = {}
var transport_maps: Dictionary = {}
var initialized := false
var loading := false
var error := ""
var current_form := ""
var target_form := ""
var progress := 1.0
var morphing: bool:
	get: return _active or _snapshot_pending
var splat_count: int:
	get: return _decoder.count if initialized else 0
var names := PackedStringArray()
var topology: Node3D
var splats: Node3D

# Canonical IDs keep pair maps valid after earlier transitions reorder display slots.
var _source_ids := PackedInt32Array()
var _destination_ids := PackedInt32Array()
var _source_form := 0
var _destination_form := 0
var _decoder: RefCounted
var _meshes: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _source_weights := PackedFloat32Array()
var _destination_weights := PackedFloat32Array()
var _weights := PackedFloat32Array()
var _source_records := PackedFloat32Array()
var _destination_records := PackedFloat32Array()
var _source_positions := PackedVector3Array()
var _destination_positions := PackedVector3Array()
var _seconds := 1.5
var _active := false
var _thread: Thread
var _snapshot_pending := false
var _pending_form := ""
var _pending_duration := 1.5
var _pending_weights := PackedFloat32Array()
var _reload_requested := false
var _loading_library := false

# Editor preview owns a separate clock and always starts a pair at its canonical source.
# Scrubbing an already prepared pair only updates GPU interpolation weights.
var _preview_pair: Array[String] = []
var _preview_dirty := false
var _preview_sync_queued := false
var _preview_playing := false
var _preview_clock_write := false
var _preview_normalizing := false

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		add_to_group("gaussian_cake_form_previews")
		if is_node_ready(): _request_editor_preview()

func _ready() -> void:
	if not library_path.is_empty(): _load_library()

func _fail(message: String) -> void:
	error = message
	loading = false
	_loading_library = false
	_active = false
	_preview_playing = false
	_preview_dirty = false
	update_configuration_warnings()
	state_changed.emit()
	if Engine.is_editor_hint():
		notify_property_list_changed()
		editor_preview_changed.emit()
	push_error("Gaussian Cake forms: " + message)

func _get_configuration_warnings() -> PackedStringArray:
	if not error.is_empty(): return PackedStringArray([error])
	if library_path.is_empty(): return PackedStringArray(["Assign the exported library.json to Library Path."])
	return PackedStringArray()

func _load_resource(path: String) -> Resource:
	if Engine.is_editor_hint():
		var resource: Resource = load(path)
		if resource == null: _fail("Cannot load resource: " + path)
		return resource
	if ResourceLoader.load_threaded_request(path) != OK:
		_fail("Cannot request resource: " + path)
		return null
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
		_fail("Cannot load resource: " + path)
		return null
	return ResourceLoader.load_threaded_get(path)

func _load_library() -> void:
	_loading_library = true
	loading = true
	if Engine.is_editor_hint():
		editor_preview_changed.emit()
	var manifest := _read_manifest()
	if manifest.is_empty():
		return
	names = PackedStringArray(manifest.names)
	_library_state_machine = manifest.get("state_machine", {}).duplicate(true)
	var graph_error := StateMachine.validate(get_state_machine(), names)
	if not graph_error.is_empty():
		_fail(graph_error)
		return
	var directory := library_path.get_base_dir()
	if not await _load_splat_library(directory.path_join(manifest.splats)):
		return
	if manifest.has("topology"):
		if not await _load_topology(manifest, directory):
			return
	else:
		renderer_mode = "splats"
	if not await _load_transport_maps(manifest.get("transport_maps", []), directory):
		return
	var graph := get_state_machine()
	_reset_endpoint(names.find(graph.initial) if not graph.is_empty() else 0)
	_create_splat_renderer()
	initialized = true
	loading = false
	_loading_library = false
	update_configuration_warnings()
	set_renderer(renderer_mode)
	library_ready.emit()
	state_changed.emit()
	if Engine.is_editor_hint():
		_normalize_editor_forms()
		_preview_pair.clear()
		notify_property_list_changed()
		_request_editor_preview()

func _read_manifest() -> Dictionary:
	if not FileAccess.file_exists(library_path):
		error = "Form library manifest does not exist: " + library_path
		loading = false
		_loading_library = false
		_preview_dirty = false
		_preview_playing = false
		update_configuration_warnings()
		if Engine.is_editor_hint():
			notify_property_list_changed()
			editor_preview_changed.emit()
		return {}
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(library_path))
	var message := Manifest.validate(manifest)
	if not message.is_empty():
		_fail(message)
		return {}
	return manifest

func _load_splat_library(path: String) -> bool:
	var resource: Resource = await _load_resource(path)
	if resource == null: return false
	if not resource.has_method("get_decoder"):
		_fail("The splat library was not imported as a Gaussian Cake form resource.")
		return false
	if Engine.is_editor_hint():
		_decoder = resource.get_decoder()
	else:
		_thread = Thread.new()
		if _thread.start(func(): return resource.get_decoder()) != OK:
			_thread = null
			_fail("Cannot start form validation worker.")
			return false
		while _thread.is_alive(): await get_tree().process_frame
		_decoder = _thread.wait_to_finish()
		_thread = null
	if not _decoder.error.is_empty():
		_fail(_decoder.error)
		return false
	if _decoder.names != names:
		_fail("Mesh and splat form names or ordering do not match.")
		return false
	return true

func _load_topology(manifest: Dictionary, directory: String) -> bool:
	var packed: Resource = await _load_resource(directory.path_join(manifest.topology))
	var colors: Resource = await _load_resource(directory.path_join(manifest.colors))
	if packed == null or colors == null: return false
	if not packed is PackedScene or not colors is Texture2D:
		_fail("Expected a topology GLB and a color atlas texture.")
		return false
	if colors.get_width() != 1024 or colors.get_height() != int(manifest.rows_per_form)*names.size():
		_fail("Color atlas dimensions do not match the form manifest.")
		return false
	topology = packed.instantiate()
	topology.name = "Topology"
	add_child(topology)
	for node in topology.find_children("*","MeshInstance3D",true,false):
		var mesh_node: MeshInstance3D = node
		if mesh_node.mesh.get_blend_shape_count() != names.size()-1:
			_fail("Topology mesh has the wrong number of blend shapes.")
			return false
		for i in range(1,names.size()):
			if mesh_node.mesh.get_blend_shape_name(i-1) != names[i]:
				_fail("Topology blend shape names do not match the library.")
				return false
		_meshes.append(mesh_node)
		# All endpoints and their convex blends fit inside these conservative bounds.
		mesh_node.custom_aabb = _decoder.bounds.grow(0.1)
		for surface in range(mesh_node.mesh.get_surface_count()):
			var material := ShaderMaterial.new()
			material.shader = COLOR_SHADER
			material.set_shader_parameter("form_colors",colors)
			material.set_shader_parameter("form_count",names.size())
			mesh_node.set_surface_override_material(surface,material)
			_materials.append(material)
	if _meshes.is_empty():
		_fail("Topology scene has no morph mesh.")
		return false
	return true

func _load_transport_maps(entries: Array, directory: String) -> bool:
	for entry in entries:
		var source := names.find(entry.from)
		var target := names.find(entry.to)
		var key := "%d:%d" % [source, target]
		var resource: Resource = await _load_resource(directory.path_join(entry.path))
		if resource == null:
			return false
		if not resource.has_method("get_decoder"):
			_fail("Transport map was not imported as a Gaussian Cake map.")
			return false
		var decoded = resource.get_decoder()
		if not decoded.error.is_empty() or decoded.count != _decoder.count or decoded.source != source or decoded.target != target:
			_fail("Transport map does not match the form library.")
			return false
		transport_maps[key] = {"ids": decoded.ids, "metrics": entry.get("metrics", {})}
	return true

func _create_splat_renderer() -> void:
	splats = SplatRenderer.new()
	splats.name = "Splats"
	splats.camera = camera
	splats.configure(_decoder.count,_decoder.bounds,_source_records,_destination_records,_source_positions,_destination_positions)
	add_child(splats)

func reload_library() -> void:
	editor_preview_pause()
	_preview_pair.clear()
	_preview_dirty = false
	# Finish in-flight immutable resource preparation/snapshot before replacing it.
	# Multiple Inspector edits coalesce to the most recent path.
	while _loading_library or _snapshot_pending: await get_tree().process_frame
	_reload_requested = false
	initialized = false
	state_graph_changed.emit()
	_active = false
	error = ""
	progress = 1.0
	names = PackedStringArray()
	_meshes.clear()
	_materials.clear()
	_decoder = null
	transport_maps.clear()
	if Engine.is_editor_hint():
		notify_property_list_changed()
		editor_preview_changed.emit()
	for child in [topology,splats]:
		if is_instance_valid(child):
			remove_child(child)
			child.queue_free()
	topology = null
	splats = null
	if library_path.is_empty():
		loading = false
		update_configuration_warnings()
		if Engine.is_editor_hint(): editor_preview_changed.emit()
		return
	_load_library()

func wait_until_ready() -> void:
	while not initialized and error.is_empty(): await get_tree().process_frame

func wait_until_settled() -> void:
	while error.is_empty() and (not initialized or loading or morphing): await get_tree().process_frame

func set_renderer(mode: String) -> void:
	if mode != "topology" and mode != "splats": return
	renderer_mode = mode

func _update_renderer() -> void:
	if not initialized: return
	if is_instance_valid(topology): topology.visible = renderer_mode == "topology"
	splats.visible = renderer_mode == "splats"
	splats.set_process(splats.visible)
	splats.camera = camera
	_apply_pose()
	state_changed.emit()

func get_state_machine() -> Dictionary:
	return (state_machine_override if not state_machine_override.is_empty() else _library_state_machine).duplicate(true)

func can_transition_to(form: String) -> bool:
	if not initialized or not error.is_empty() or not names.has(form): return false
	var graph := get_state_machine()
	return StateMachine.validate(graph, names).is_empty() and StateMachine.transition_duration(graph, target_form, form, duration) >= 0.0

func request_state(form: String) -> bool:
	if not can_transition_to(form):
		transition_rejected.emit(target_form, form)
		return false
	morph_to(form)
	return true

func morph_to(form: String, seconds: float = -1.0) -> void:
	if not initialized or not error.is_empty() or not names.has(form): return
	var graph := get_state_machine()
	if not StateMachine.validate(graph, names).is_empty(): return
	var edge_duration := StateMachine.transition_duration(graph, target_form, form, duration)
	if edge_duration < 0.0:
		transition_rejected.emit(target_form, form)
		return
	var requested_duration := edge_duration if seconds < 0.0 else seconds
	if not is_finite(requested_duration) or requested_duration < 0.01 or requested_duration > 3600: return
	if form == target_form and not _snapshot_pending and (_active or progress >= 1.0): return
	_pending_form = form
	_pending_duration = requested_duration
	if _snapshot_pending:
		target_form = form
		return # Keep the most recent destination while preserving the frozen pose.
	if progress > 0.0 and progress < 1.0:
		# Validation and interruption snapshots run off the render thread. Hold exactly
		# this pose until the snapshot is ready; movement/camera rendering stay live.
		_pending_weights = _weights.duplicate()
		var from := _source_records
		var to := _destination_records
		var eased := _eased_progress()
		_thread = Thread.new()
		if _thread.start(func(): return Decoder.snapshot(from,to,eased)) != OK:
			_thread = null
			_fail("Cannot start morph snapshot worker.")
			return
		_snapshot_pending = true
		loading = true
		target_form = form
		state_changed.emit()
		_finish_snapshot()
		return
	_source_weights = _weights.duplicate()
	if progress >= 1.0:
		_source_records = _destination_records
		_source_positions = _destination_positions
		_source_ids = _destination_ids
		_source_form = _destination_form
	_begin_transition()

func _begin_transition() -> void:
	var index := names.find(_pending_form)
	var pair_key := str(_source_form)+":"+str(index)
	var mapping := PackedInt32Array()
	transition_metrics = {}
	last_transport = "shared"
	if transport_mode == "refined":
		if _source_form >= 0 and transport_maps.has(pair_key):
			mapping = transport_maps[pair_key].ids
			transition_metrics = transport_maps[pair_key].metrics
			last_transport = "refined"
		else: last_transport = "fallback"
	var ids := _source_ids.duplicate()
	var identity := true
	for i in range(ids.size()):
		if not mapping.is_empty(): ids[i] = mapping[ids[i]]
		if ids[i] != i: identity = false
	var records: PackedFloat32Array = _decoder.records(index)
	var points: PackedVector3Array = _decoder.positions(index)
	if identity:
		_install_transition(index,records,points,ids)
		return
	# Retargeting changes only endpoint order. Work runs once, off the render thread.
	_thread = Thread.new()
	if _thread.start(func(): return _reorder(records,points,ids)) != OK:
		_thread = null
		_fail("Cannot start transport ordering worker.")
		return
	_snapshot_pending = true
	loading = true
	target_form = _pending_form
	# Publish the exact held source pose before any renderer switch during preparation.
	_destination_records = _source_records
	_destination_positions = _source_positions
	_destination_weights = _source_weights.duplicate()
	progress = 0.0
	splats.set_endpoints(_source_records,_source_records,_source_positions,_source_positions)
	_apply_pose()
	state_changed.emit()
	_finish_order(index,ids)

static func _reorder(records: PackedFloat32Array, points: PackedVector3Array, ids: PackedInt32Array) -> Dictionary:
	var ordered := PackedFloat32Array()
	ordered.resize(records.size())
	var positions := PackedVector3Array()
	positions.resize(ids.size())
	for i in range(ids.size()):
		var source := ids[i]
		positions[i] = points[source]
		for field in range(14): ordered[i*14+field] = records[source*14+field]
	return {"records":ordered,"positions":positions}

func _finish_order(index: int, ids: PackedInt32Array) -> void:
	while _thread.is_alive(): await get_tree().process_frame
	var result: Dictionary = _thread.wait_to_finish()
	_thread = null
	_snapshot_pending = false
	if names[index] != _pending_form:
		_begin_transition()
		return
	_install_transition(index,result.records,result.positions,ids)

func _install_transition(index: int, records: PackedFloat32Array, points: PackedVector3Array, ids: PackedInt32Array) -> void:
	target_form = names[index]
	_seconds = _pending_duration
	_destination_weights.fill(0.0)
	_destination_weights[index] = 1.0
	_destination_records = records
	_destination_positions = points
	_destination_ids = ids
	_destination_form = index
	splats.set_endpoints(_source_records,_destination_records,_source_positions,_destination_positions)
	progress = 0.0
	_active = true
	loading = false
	_apply_pose()
	state_changed.emit()

func snap_to_form(form: String) -> void:
	if not initialized or loading or not names.has(form): return
	_reset_endpoint(names.find(form))
	splats.set_endpoints(_source_records, _destination_records, _source_positions, _destination_positions)
	_apply_pose()
	state_changed.emit()

func _reset_endpoint(index: int) -> void:
	_source_ids.resize(_decoder.count)
	for i in range(_source_ids.size()): _source_ids[i] = i
	_destination_ids = _source_ids.duplicate()
	_source_form = index
	_destination_form = index
	_source_records = _decoder.records(index)
	_destination_records = _source_records
	_source_positions = _decoder.positions(index)
	_destination_positions = _source_positions
	_source_weights.resize(names.size())
	_source_weights.fill(0.0)
	_source_weights[index] = 1.0
	_destination_weights = _source_weights.duplicate()
	_weights = _source_weights.duplicate()
	current_form = names[index]
	target_form = names[index]
	progress = 1.0
	_active = false
	last_transport = "shared"
	transition_metrics = {}

func canonical_ids() -> PackedInt32Array:
	return _destination_ids.duplicate()

func get_transport_metrics(from_name: String, to_name: String) -> Dictionary:
	var key := "%d:%d" % [names.find(from_name), names.find(to_name)]
	var entry: Dictionary = transport_maps.get(key, {})
	return entry.get("metrics", {}).duplicate(true)

func resume() -> void:
	paused = false
	if initialized and not _snapshot_pending and progress < 1.0: _active = true

func _eased_progress() -> float:
	return smoothstep(0.0,1.0,progress)

func seek(value: float) -> void:
	if not initialized or _snapshot_pending or not is_finite(value): return
	progress = clampf(value,0.0,1.0)
	_apply_pose()
	if progress >= 1.0:
		_active = false
		current_form = target_form
		state_changed.emit()

func topology_weights() -> PackedFloat32Array:
	return _weights.duplicate()

func splat_attributes(index: int) -> PackedFloat32Array:
	if not initialized or index < 0 or index >= _decoder.count: return PackedFloat32Array()
	return Decoder.interpolate_record(_source_records,_destination_records,_eased_progress(),index)

func _apply_pose() -> void:
	var eased := _eased_progress()
	for i in range(names.size()): _weights[i] = lerpf(_source_weights[i],_destination_weights[i],eased)
	for mesh_node in _meshes:
		for i in range(1,names.size()): mesh_node.set_blend_shape_value(i-1,_weights[i])
	if not _materials.is_empty():
		var shader_weights := _weights.duplicate()
		shader_weights.resize(Manifest.MAX_FORMS)
		for material in _materials:
			material.set_shader_parameter("form_weights", shader_weights)
	if renderer_mode == "splats": splats.seek(eased)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_update_editor_preview(delta)
		return
	if not initialized or paused: return
	if _snapshot_pending: return
	if not _active: return
	progress = minf(1.0,progress+delta/_seconds)
	_apply_pose()
	if progress >= 1.0:
		_active = false
		current_form = target_form
		state_changed.emit()
		morph_finished.emit(current_form)

func _finish_snapshot() -> void:
	while _thread.is_alive(): await get_tree().process_frame
	var result: Dictionary = _thread.wait_to_finish()
	_thread = null
	_source_records = result.records
	_source_positions = result.positions
	_source_weights = _pending_weights
	_source_ids = _destination_ids.duplicate()
	_source_form = -1 # An arbitrary snapshot has no exact prepared pair map.
	_snapshot_pending = false
	_begin_transition()

func _exit_tree() -> void:
	_preview_playing = false
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null

func _validate_property(property: Dictionary) -> void:
	if not str(property.name).begins_with("preview_"): return
	if not Engine.is_editor_hint():
		property.usage &= ~PROPERTY_USAGE_EDITOR
	elif not initialized:
		property.usage |= PROPERTY_USAGE_READ_ONLY

func editor_preview_status() -> String:
	if not Engine.is_editor_hint(): return "Editor preview only"
	if _loading_library or _reload_requested: return "Loading library…"
	if not error.is_empty(): return error
	if not initialized: return "Assign Library Path to preview a morph."
	if preview_preparing: return "Preparing source and target…"
	if preview_source == preview_target: return "Same source and target · static form"
	var mapping := "Refined map" if last_transport == "refined" else "Shared reference"
	if last_transport == "fallback": mapping = "Shared fallback · no pair map"
	return "%s · %s · %.0f%%" % ["Playing" if preview_playing else "Paused", mapping, preview_progress * 100.0]

func editor_preview_pause() -> void:
	if not Engine.is_editor_hint(): return
	_preview_playing = false
	editor_preview_changed.emit()

func editor_preview_toggle() -> void:
	if not Engine.is_editor_hint() or not initialized or not error.is_empty(): return
	if _preview_playing:
		editor_preview_pause()
		return
	_normalize_editor_forms()
	if preview_source == preview_target: return
	if preview_progress >= 1.0:
		preview_progress = 0.0
	_preview_playing = true
	_request_editor_preview()

func editor_preview_reset() -> void:
	if not Engine.is_editor_hint(): return
	_preview_playing = false
	preview_progress = 0.0
	_request_editor_preview()

func _normalize_editor_forms() -> void:
	if names.is_empty(): return
	_preview_normalizing = true
	if not names.has(preview_source):
		var graph := get_state_machine()
		preview_source = graph.initial if not graph.is_empty() else names[0]
	if not names.has(preview_target):
		preview_target = names[1] if names[0] == preview_source else names[0]
	_preview_normalizing = false

func _request_editor_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree() or not is_node_ready(): return
	if _preview_normalizing: return
	_preview_dirty = true
	if not _preview_sync_queued:
		_preview_sync_queued = true
		_sync_editor_preview.call_deferred()
	editor_preview_changed.emit()

func _sync_editor_preview() -> void:
	_preview_sync_queued = false
	if not Engine.is_editor_hint() or not is_inside_tree(): return
	if not initialized or not error.is_empty():
		_preview_dirty = false
		return
	if loading or _snapshot_pending or _reload_requested: return
	_normalize_editor_forms()
	var pair: Array[String] = [preview_source, preview_target, transport_mode]
	if pair != _preview_pair:
		# A new Inspector pair is independent of the previous displayed pose.
		# Reusing the canonical endpoint also makes shared/refined comparisons fair.
		snap_to_form(preview_source)
		_preview_pair = pair
		if preview_target != preview_source:
			_pending_form = preview_target
			_pending_duration = _editor_preview_duration()
			_begin_transition()
	if loading or _snapshot_pending: return
	_preview_dirty = false
	seek(preview_progress)
	editor_preview_changed.emit()

func _editor_preview_duration() -> float:
	var fallback := duration if is_finite(duration) and duration >= 0.01 else 1.5
	var graph := get_state_machine()
	if not StateMachine.validate(graph, names).is_empty(): return fallback
	var seconds := StateMachine.transition_duration(graph, preview_source, preview_target, fallback)
	return seconds if seconds >= 0.01 else fallback

func _update_editor_preview(delta: float) -> void:
	if not initialized or not error.is_empty() or _reload_requested: return
	if loading or _snapshot_pending: return
	if _preview_dirty:
		_sync_editor_preview()
	if preview_preparing or not _preview_playing: return
	if preview_source == preview_target:
		editor_preview_pause()
		return
	if not is_finite(delta) or delta <= 0.0: return
	var next := preview_progress + delta / _editor_preview_duration()
	if next >= 1.0:
		if preview_loop:
			next = fposmod(next, 1.0)
		else:
			next = 1.0
			_preview_playing = false
	_preview_clock_write = true
	preview_progress = next
	_preview_clock_write = false
	seek(preview_progress)
	editor_preview_changed.emit()
