@tool
extends VBoxContainer
## Native graph controls; edits are scene overrides with standard Godot undo/redo.
const StateMachine = preload("../runtime/form_state_machine.gd")
var player: Node
var undo_manager: EditorUndoRedoManager
var graph_view: GraphEdit
var any_form: CheckBox
var initial: OptionButton
var edges: OptionButton
var seconds: SpinBox
var remove: Button
var status: Label
var _graph: Dictionary = {}
var _syncing := false
var _refresh_queued := false

func _ready() -> void:
	custom_minimum_size.y = 320
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	any_form = CheckBox.new()
	any_form.text = "Any form"
	any_form.tooltip_text = "Allow all destinations. Arrows override default duration. Turn off to allow only arrows."
	toolbar.add_child(any_form)
	any_form.toggled.connect(func(value: bool):
		if _syncing: return
		var data := _graph.duplicate(true)
		data.allow_any = value
		_commit(data, "Change form transition policy"))
	var label := Label.new()
	label.text = "Initial"
	toolbar.add_child(label)
	initial = OptionButton.new()
	toolbar.add_child(initial)
	initial.item_selected.connect(func(index: int):
		var data := _graph.duplicate(true)
		data.initial = player.names[index]
		_commit(data, "Change initial form"))
	var reset := Button.new()
	reset.text = "Use library graph"
	reset.tooltip_text = "Remove this scene's graph override."
	reset.pressed.connect(func(): _commit({}, "Restore library state graph"))
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(reset)
	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	graph_view = GraphEdit.new()
	graph_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_view.custom_minimum_size.y = 230
	graph_view.right_disconnects = true
	graph_view.minimap_enabled = false
	graph_view.show_arrange_button = false
	add_child(graph_view)
	graph_view.connection_request.connect(_connect_states)
	graph_view.disconnection_request.connect(_disconnect_states)
	graph_view.end_node_move.connect(_save_positions)
	var edge_bar := HBoxContainer.new()
	add_child(edge_bar)
	edges = OptionButton.new()
	edges.custom_minimum_size.x = 220
	edge_bar.add_child(edges)
	edges.item_selected.connect(func(_index: int): _select_edge())
	seconds = SpinBox.new()
	seconds.min_value = 0.01
	seconds.max_value = 3600
	seconds.step = 0.01
	seconds.suffix = "s"
	edge_bar.add_child(seconds)
	seconds.value_changed.connect(func(value: float):
		if _syncing or edges.selected < 0: return
		var data := _graph.duplicate(true)
		data.transitions[edges.selected].duration = value
		_commit(data, "Change form transition duration"))
	remove = Button.new()
	remove.text = "Remove arrow"
	remove.pressed.connect(func():
		if edges.selected < 0: return
		var data := _graph.duplicate(true)
		data.transitions.remove_at(edges.selected)
		_commit(data, "Remove form transition"))
	edge_bar.add_child(remove)
	_refresh()

func bind_player(value: Node) -> void:
	if player == value: return
	if is_instance_valid(player):
		if player.state_graph_changed.is_connected(queue_refresh): player.state_graph_changed.disconnect(queue_refresh)
		if player.library_ready.is_connected(queue_refresh): player.library_ready.disconnect(queue_refresh)
		if player.state_changed.is_connected(queue_refresh): player.state_changed.disconnect(queue_refresh)
	player = value
	if is_instance_valid(player):
		player.state_graph_changed.connect(queue_refresh)
		player.library_ready.connect(queue_refresh)
		player.state_changed.connect(queue_refresh)
	queue_refresh()

func queue_refresh() -> void:
	if _refresh_queued: return
	_refresh_queued = true
	_refresh.call_deferred()

func _refresh() -> void:
	_refresh_queued = false
	if not is_node_ready(): return
	_syncing = true
	graph_view.clear_connections()
	for child in graph_view.get_children():
		if child is GraphNode:
			graph_view.remove_child(child)
			child.queue_free()
	var selected_edge := edges.selected
	initial.clear()
	edges.clear()
	var available: bool = is_instance_valid(player) and player.initialized and player.error.is_empty() and not player.loading
	any_form.disabled = not available
	initial.disabled = not available
	graph_view.visible = available
	if not available:
		status.text = "Select a loaded form player."
		seconds.editable = false
		remove.disabled = true
		_syncing = false
		return
	_graph = player.get_state_machine()
	if _graph.is_empty(): _graph = StateMachine.default_graph(player.names)
	if _graph.positions.is_empty(): _graph.positions = StateMachine.default_graph(player.names).positions
	var error := StateMachine.validate(_graph, player.names)
	if not error.is_empty():
		status.text = error
		_syncing = false
		return
	status.text = "Connect ports. Save the scene to keep changes."
	any_form.set_pressed_no_signal(_graph.get("allow_any", false))
	for index in range(player.names.size()):
		var form: String = player.names[index]
		initial.add_item(form)
		var node := GraphNode.new()
		node.name = "state_%d" % index
		node.title = form + (" (initial)" if form == _graph.initial else "")
		node.position_offset = Vector2(_graph.positions[index][0], _graph.positions[index][1]) + Vector2(20, 70)
		node.custom_minimum_size.x = 170
		var preview := Button.new()
		preview.text = "Preview"
		preview.pressed.connect(_preview.bind(form))
		node.add_child(preview)
		node.set_slot(0, true, 0, Color.WHITE, true, 0, Color.WHITE)
		graph_view.add_child(node)
	initial.select(player.names.find(_graph.initial))
	for edge in _graph.transitions:
		graph_view.connect_node("state_%d" % player.names.find(edge.from), 0, "state_%d" % player.names.find(edge.to), 0)
		edges.add_item("%s -> %s" % [edge.from, edge.to])
	if edges.item_count > 0: edges.select(clampi(selected_edge, 0, edges.item_count - 1))
	_select_edge()
	_syncing = false

func _select_edge() -> void:
	seconds.editable = edges.item_count > 0
	remove.disabled = edges.item_count == 0
	if edges.selected >= 0: seconds.set_value_no_signal(_graph.transitions[edges.selected].duration)

func _connect_states(source: StringName, _a: int, target: StringName, _b: int) -> void:
	var from_form: String = player.names[String(source).trim_prefix("state_").to_int()]
	var to_form: String = player.names[String(target).trim_prefix("state_").to_int()]
	if from_form == to_form: return
	for edge in _graph.transitions:
		if edge.from == from_form and edge.to == to_form: return
	var data := _graph.duplicate(true)
	data.transitions.append({"from": from_form, "to": to_form, "duration": player.duration})
	_commit(data, "Connect form states")

func _disconnect_states(source: StringName, _a: int, target: StringName, _b: int) -> void:
	var from_form: String = player.names[String(source).trim_prefix("state_").to_int()]
	var to_form: String = player.names[String(target).trim_prefix("state_").to_int()]
	var data := _graph.duplicate(true)
	for index in range(data.transitions.size()):
		if data.transitions[index].from == from_form and data.transitions[index].to == to_form:
			data.transitions.remove_at(index)
			_commit(data, "Disconnect form states")
			return

func _save_positions() -> void:
	var data := _graph.duplicate(true)
	for index in range(player.names.size()):
		var node: GraphNode = graph_view.get_node("state_%d" % index)
		var position := node.position_offset - Vector2(20, 70)
		data.positions[index] = [clampf(position.x, -100000, 100000), clampf(position.y, -100000, 100000)]
	_commit(data, "Move form states")

func _preview(form: String) -> void:
	if not is_instance_valid(player): return
	var source: String = player.preview_target if player.preview_progress >= 1.0 else player.preview_source
	if source.is_empty(): source = _graph.initial
	var length := StateMachine.transition_duration(_graph, source, form, player.duration)
	if length < 0:
		status.text = "No arrow: %s -> %s" % [source, form]
		return
	player.editor_preview_pause()
	player.preview_source = source
	player.preview_target = form
	player.preview_progress = 0.0
	player.editor_preview_toggle.call_deferred()

func _commit(data: Dictionary, label: String) -> void:
	if not is_instance_valid(player) or undo_manager == null: return
	var error := StateMachine.validate(data, player.names)
	if not error.is_empty():
		status.text = error
		return
	undo_manager.create_action(label, UndoRedo.MERGE_DISABLE, player)
	undo_manager.add_do_property(player, "state_machine_override", data.duplicate(true))
	undo_manager.add_undo_property(player, "state_machine_override", player.state_machine_override.duplicate(true))
	undo_manager.commit_action()
