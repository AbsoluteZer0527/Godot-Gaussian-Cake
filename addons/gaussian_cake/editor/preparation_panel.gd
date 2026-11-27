@tool
extends VBoxContainer
## Code-free authoring controls. The editor plugin owns preparation and scene changes.
signal prepare_requested(settings: Dictionary)
signal cancel_requested
signal use_result_requested
signal settings_changed(settings: Dictionary)

const PathPicker = preload("preparation_path_picker.gd")
var _source: PathPicker
var _target: PathPicker
var _cli: PathPicker
var _count: SpinBox
var _samples: SpinBox
var _mixtures: SpinBox
var _color_match: SpinBox
var _dc_only: CheckBox
var _advanced: VBoxContainer
var _advanced_toggle: Button
var _tool_summary: Label
var _prepare: Button
var _cancel: Button
var _use_result: Button
var _progress: ProgressBar
var _status: Label
var _target_description: Label
var _result: Label
var _log: TextEdit
var _log_toggle: Button
var _busy := false
var _applying := false
var _configuring := false
var _manifest := ""

func _init() -> void:
	name = "Gaussian Cake"
	custom_minimum_size = Vector2(250, 150)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.name = "PreparationScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	_label("Prepare a morph", content)
	_hint("Prepares a Gaussian splat morph from PLY captures or GLB meshes.", content)
	_source = _model_picker("Source Model", "SourceModel", content)
	_target = _model_picker("Target Model", "TargetModel", content)
	_count = _number("Splats per form", "SplatCount", 1, 50000, 1, 12000, content)
	_count.tooltip_text = "More splats preserve detail but increase preparation time and rendering cost."
	_hint("Choose both models, then prepare once. Preview speed can be changed afterward.", content)
	_tool_summary = _hint("Choose the preparation tool below.", content)
	_tool_summary.name = "ToolSummary"

	_advanced_toggle = _fold_button("Preparation settings", "PreparationSettingsToggle", content)
	_advanced = VBoxContainer.new()
	_advanced.name = "PreparationSettings"
	_advanced.add_theme_constant_override("separation", 8)
	_advanced.visible = false
	content.add_child(_advanced)
	_advanced_toggle.toggled.connect(func(open: bool): _advanced.visible = open)
	_cli = PathPicker.new()
	_cli.name = "CliPath"
	var executable_extensions := PackedStringArray(["exe"]) if OS.get_name() == "Windows" else PackedStringArray()
	var executable_filters := PackedStringArray(["*.exe ; Executables"]) if OS.get_name() == "Windows" else PackedStringArray()
	_cli.setup("Gaussian Cake CLI", executable_extensions, executable_filters, "Select gc_cli.exe from the Gaussian Cake build. Needed only while preparing models.")
	_cli.path_changed.connect(_settings_changed)
	_advanced.add_child(_cli)
	_hint("Select the Gaussian Cake preparation tool once. Your game only needs the generated assets.", _advanced)
	_samples = _number("Matching samples", "MatchingSamples", 4, 1000000, 1, 1200, _advanced)
	_mixtures = _number("Matching groups", "MatchingGroups", 1, 128, 1, 8, _advanced)
	_color_match = _number("Color matching", "ColorMatching", 0, 1, 0.05, 0.35, _advanced)
	_color_match.tooltip_text = "How strongly correspondence favors similar colors. Zero matches by shape alone."
	_dc_only = CheckBox.new()
	_dc_only.name = "BaseColorOnly"
	_dc_only.text = "Use base color only"
	_dc_only.tooltip_text = "Allow discarding view-dependent spherical-harmonic color from Gaussian PLY captures. The current Godot player uses base color."
	_dc_only.toggled.connect(_settings_changed)
	_advanced.add_child(_dc_only)
	_hint("For captures with view-dependent color, this explicitly allows discarding that extra color data.", _advanced)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	content.add_child(actions)
	_prepare = Button.new()
	_prepare.name = "Prepare"
	_prepare.text = "Prepare"
	_prepare.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prepare.pressed.connect(_request_prepare)
	actions.add_child(_prepare)
	_cancel = Button.new()
	_cancel.name = "Cancel"
	_cancel.text = "Cancel"
	_cancel.pressed.connect(func(): cancel_requested.emit())
	actions.add_child(_cancel)
	_progress = ProgressBar.new()
	_progress.name = "PreparationProgress"
	_progress.custom_minimum_size.y = 5
	_progress.show_percentage = false
	_progress.indeterminate = true
	_progress.editor_preview_indeterminate = true
	_progress.visible = false
	content.add_child(_progress)
	_status = _label("Choose your source and target models.", content)
	_status.name = "PreparationStatus"
	_result = _label("", content)
	_result.name = "PreparationResult"
	_result.visible = false
	_target_description = _hint("The prepared morph will be added to the open scene. Use Morph Preview in its Inspector.", content)
	_target_description.name = "SceneTarget"
	_use_result = Button.new()
	_use_result.name = "UseInScene"
	_use_result.text = "Use in scene"
	_use_result.pressed.connect(func(): use_result_requested.emit())
	content.add_child(_use_result)

	_log_toggle = _fold_button("Preparation log", "PreparationLogToggle", content)
	_log = TextEdit.new()
	_log.name = "PreparationLog"
	_log.editable = false
	_log.custom_minimum_size.y = 140
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_log.visible = false
	content.add_child(_log)
	_log_toggle.toggled.connect(func(open: bool): _log.visible = open)
	_refresh_controls()

func _label(text: String, parent: Node) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _hint(text: String, parent: Node) -> Label:
	var label := _label(text, parent)
	label.modulate.a = 0.75
	return label

func _fold_button(text: String, node_name: String, parent: Node) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.flat = true
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.toggled.connect(func(open: bool): button.text = ("▾ " if open else "▸ ") + text)
	button.text = "▸ " + text
	parent.add_child(button)
	return button

func _model_picker(label_text: String, node_name: String, parent: Node) -> PathPicker:
	var picker := PathPicker.new()
	picker.name = node_name
	picker.setup(label_text, PackedStringArray(["ply", "glb"]), PackedStringArray(["*.ply,*.glb ; PLY or GLB models"]))
	picker.path_changed.connect(_settings_changed)
	parent.add_child(picker)
	return picker

func _number(label_text: String, node_name: String, minimum: float, maximum: float, step_size: float, initial: float, parent: Node) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := _label(label_text, row)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var number := SpinBox.new()
	number.name = node_name
	number.min_value = minimum
	number.max_value = maximum
	number.step = step_size
	number.value = initial
	number.custom_minimum_size.x = 92
	number.value_changed.connect(_settings_changed)
	row.add_child(number)
	parent.add_child(row)
	return number

func configure(settings: Dictionary) -> void:
	_configuring = true
	_source.set_path(str(settings.get("source_path", "")))
	_target.set_path(str(settings.get("target_path", "")))
	_cli.set_path(str(settings.get("cli_path", "")))
	_count.value = settings.get("count", 12000)
	_samples.value = settings.get("samples", 1200)
	_mixtures.value = settings.get("mixtures", 8)
	_color_match.value = settings.get("color_match", 0.35)
	_dc_only.button_pressed = settings.get("dc_only", false)
	_advanced_toggle.button_pressed = _cli.get_file_path().is_empty()
	_configuring = false
	_refresh_controls()

func get_settings() -> Dictionary:
	return {
		"source_path": _source.get_file_path(),
		"target_path": _target.get_file_path(),
		"cli_path": _cli.get_file_path(),
		"count": int(_count.value),
		"samples": int(_samples.value),
		"mixtures": int(_mixtures.value),
		"color_match": _color_match.value,
		"dc_only": _dc_only.button_pressed,
	}

func set_job_state(busy: bool, status: String, log_text: String = "") -> void:
	_busy = busy
	_status.text = status
	if _log.text != log_text:
		_log.text = log_text
		_log.scroll_vertical = _log.get_line_count()
	_refresh_controls()

func set_result(manifest_path: String, source_name: String, target_name: String, cached: bool = false) -> void:
	_manifest = manifest_path
	_result.text = "Prepared: %s → %s%s" % [source_name, target_name, " · reused prepared assets" if cached else ""]
	_result.tooltip_text = manifest_path
	_result.visible = not manifest_path.is_empty()
	_refresh_controls()

func set_target_description(text: String, action_label: String = "Use in scene") -> void:
	_target_description.text = text
	_use_result.text = action_label

func set_applying(applying: bool) -> void:
	_applying = applying
	_refresh_controls()

func _settings_changed(_value: Variant = null) -> void:
	if _configuring:
		return
	_refresh_controls()
	settings_changed.emit(get_settings())

func _request_prepare() -> void:
	if _busy or _applying:
		return
	prepare_requested.emit(get_settings())

func _refresh_controls() -> void:
	var locked := _busy or _applying
	for picker in [_source, _target, _cli]:
		picker.set_locked(locked)
	for number in [_count, _samples, _mixtures, _color_match]:
		number.editable = not locked
	_dc_only.disabled = locked
	_prepare.disabled = locked or _source.get_file_path().is_empty() or _target.get_file_path().is_empty() or _cli.get_file_path().is_empty()
	_prepare.text = "Preparing…" if _busy else "Prepare"
	_prepare.tooltip_text = "Choose source, target, and the Gaussian Cake CLI." if _prepare.disabled and not locked else "Prepare the selected models, then preview the result in the Inspector."
	_tool_summary.text = "Tool: " + _cli.get_file_path().get_file() if not _cli.get_file_path().is_empty() else "Choose the Gaussian Cake CLI under Preparation settings."
	_cancel.disabled = not locked
	_progress.visible = locked
	_use_result.disabled = locked or _manifest.is_empty()
	_use_result.visible = not _manifest.is_empty()

