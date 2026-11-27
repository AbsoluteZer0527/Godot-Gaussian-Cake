@tool
extends EditorProperty
## Exact names are item metadata, so commas/colons never become enum separators.
const REFRESH_SIGNALS := [&"library_ready", &"state_changed", &"editor_preview_changed"]
var _player: WeakRef
var _property_name := ""
var _names := PackedStringArray()
var _locked := false
var _option: OptionButton

func _init() -> void:
	_option = OptionButton.new()
	_option.name = "FormOption"
	_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option.fit_to_longest_item = false
	_option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_option.item_selected.connect(_selected)
	add_child(_option)
	add_focusable(_option)

func setup(player: Object, property_name: String) -> void:
	_player = weakref(player)
	_property_name = property_name

func _enter_tree() -> void:
	var player := _get_player()
	if player != null:
		for signal_name in REFRESH_SIGNALS:
			if player.has_signal(signal_name) and not player.is_connected(signal_name, _refresh):
				player.connect(signal_name, _refresh)
	_refresh()

func _exit_tree() -> void:
	var player := _get_player()
	if player != null:
		for signal_name in REFRESH_SIGNALS:
			if player.has_signal(signal_name) and player.is_connected(signal_name, _refresh):
				player.disconnect(signal_name, _refresh)

func _get_player() -> Object:
	return _player.get_ref() if _player != null else null

func _set_read_only(value: bool) -> void:
	_locked = value
	_refresh()

func _update_property() -> void:
	_refresh()

func _refresh() -> void:
	if _option == null:
		return
	var player := _get_player()
	if player == null:
		_show_placeholder("Library unavailable")
		return
	var available: PackedStringArray = player.names
	if available.is_empty():
		_names = PackedStringArray()
		_show_placeholder("Loading forms…" if player.loading else "Load a form library")
		return
	if available != _names or _option.item_count != available.size():
		_names = available.duplicate()
		_option.clear()
		for form_name in _names:
			_option.add_item(form_name)
			_option.set_item_metadata(_option.item_count - 1, form_name)
	var current: String = player.get(_property_name)
	var index := _names.find(current)
	# The player resolves empty/stale selections after loading. UI refresh never
	# writes a fallback into the scene or creates an invisible undo action.
	if _option.selected != index:
		_option.select(index)
	_option.disabled = _locked or read_only or not player.initialized or not player.error.is_empty()
	_option.tooltip_text = current if index >= 0 else "Choose a form from this library."

func _show_placeholder(message: String) -> void:
	if _option.item_count != 1 or _option.get_item_text(0) != message:
		_option.clear()
		_option.add_item(message)
		_option.select(0)
	_option.disabled = true
	_option.tooltip_text = message

func _selected(index: int) -> void:
	if _option.disabled or index < 0 or index >= _option.item_count:
		return
	var value: String = _option.get_item_metadata(index)
	emit_changed(_property_name, value)
