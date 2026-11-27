@tool
extends EditorInspectorPlugin
signal preparation_requested
## Native Inspector properties retain scene serialization and undo/redo behavior.
const FormPlayer = preload("../runtime/form_player_3d.gd")
const FormSelector = preload("form_selector_property.gd")
const PreviewStatus = preload("form_preview_status.gd")

func _can_handle(object: Object) -> bool:
	return object is FormPlayer

func _parse_begin(_object: Object) -> void:
	var prepare := Button.new()
	prepare.name = "OpenMorphPreparation"
	prepare.text = "Prepare PLY/GLB models…"
	prepare.tooltip_text = "Choose source and target model files in the Gaussian Cake dock."
	prepare.pressed.connect(func(): preparation_requested.emit())
	add_custom_control(prepare)

func _parse_group(object: Object, group: String) -> void:
	if group != "Morph Preview":
		return
	var status := PreviewStatus.new()
	status.setup(object)
	add_custom_control(status)

func _parse_property(object: Object, _type: Variant.Type, name: String,
		_hint_type: PropertyHint, _hint_string: String,
		usage_flags: int, _wide: bool) -> bool:
	if name != "preview_source" and name != "preview_target":
		return false
	var selector := FormSelector.new()
	selector.setup(object, name)
	selector.read_only = (usage_flags & PROPERTY_USAGE_READ_ONLY) != 0
	add_property_editor(name, selector)
	return true
