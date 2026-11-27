@tool
extends VBoxContainer
## Informational only: playback controls and saved settings stay native properties.
const REFRESH_SIGNALS := [&"library_ready", &"state_changed", &"editor_preview_changed"]
var _player: WeakRef
var _status: Label

func _init() -> void:
	name = "FormPreviewStatus"
	add_theme_constant_override("separation", 4)
	var hint := Label.new()
	hint.text = "Editor preview only. Duration sets playback speed."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate.a = 0.7
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)

func setup(player: Object) -> void:
	_player = weakref(player)

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

func _refresh() -> void:
	var player := _get_player()
	if player == null:
		_status.text = "Select a form player to preview."
	elif player.has_method("editor_preview_status"):
		_status.text = player.editor_preview_status()
	else:
		_status.text = "Load a form library to preview."
