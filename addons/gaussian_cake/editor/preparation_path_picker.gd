@tool
extends VBoxContainer
## A filesystem picker that also accepts one matching file from Godot's FileSystem dock.
signal path_changed(path: String)

class DropPathEdit extends LineEdit:
	var extensions := PackedStringArray()

	func _can_drop_data(_position: Vector2, data: Variant) -> bool:
		if not editable or not data is Dictionary or not data.has("files"):
			return false
		var files: Variant = data.files
		if not (files is Array or files is PackedStringArray) or files.size() != 1:
			return false
		return files[0] is String and (extensions.is_empty() or extensions.has(str(files[0]).get_extension().to_lower()))

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		if not _can_drop_data(at_position, data):
			return
		text = str(data.files[0])
		caret_column = text.length()
		text_changed.emit(text)

var _label: Label
var _path: DropPathEdit
var _browse: Button
var _dialog: EditorFileDialog

func _init() -> void:
	add_theme_constant_override("separation", 4)
	_label = Label.new()
	_label.name = "Label"
	add_child(_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	_path = DropPathEdit.new()
	_path.name = "Path"
	_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path.clear_button_enabled = true
	_path.placeholder_text = "Choose or drop a model"
	_path.text_changed.connect(_changed)
	row.add_child(_path)
	_browse = Button.new()
	_browse.name = "Browse"
	_browse.text = "Browse…"
	_browse.pressed.connect(_choose)
	row.add_child(_browse)
	_dialog = EditorFileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.file_selected.connect(_picked)
	add_child(_dialog)

func setup(label_text: String, extensions: PackedStringArray, filters: PackedStringArray, hint: String = "") -> void:
	_label.text = label_text
	_dialog.title = "Choose " + label_text.to_lower()
	_dialog.filters = filters
	_path.extensions = extensions
	_path.tooltip_text = hint
	_browse.tooltip_text = "Choose a file from this project or your computer."
	if not hint.is_empty():
		_label.tooltip_text = hint

func set_path(path: String) -> void:
	_path.text = path
	_path.caret_column = path.length()
	_update_tooltip()

func get_file_path() -> String:
	return _path.text.strip_edges()

func set_locked(locked: bool) -> void:
	_path.editable = not locked
	_browse.disabled = locked
	if locked and _dialog.visible:
		_dialog.hide()

func _changed(_text: String) -> void:
	_update_tooltip()
	path_changed.emit(get_file_path())

func _update_tooltip() -> void:
	_path.tooltip_text = get_file_path() if not get_file_path().is_empty() else "Choose a file, or drop one here from the FileSystem dock."

func _choose() -> void:
	if _browse.disabled:
		return
	var path := get_file_path()
	if path.begins_with("res://") or path.begins_with("user://"):
		path = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		_dialog.current_path = path
	elif path.is_absolute_path() and DirAccess.dir_exists_absolute(path.get_base_dir()):
		_dialog.current_dir = path.get_base_dir()
	_dialog.popup_centered_ratio(0.7)

func _picked(path: String) -> void:
	if _browse.disabled:
		return
	set_path(ProjectSettings.localize_path(path))
	path_changed.emit(get_file_path())

