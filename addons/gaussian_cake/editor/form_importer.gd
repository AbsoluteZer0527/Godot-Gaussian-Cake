@tool
extends EditorImportPlugin
const Decoder = preload("../runtime/form_decoder.gd")
const Library = preload("../resources/form_library.gd")
func _get_importer_name() -> String: return "gaussian_cake.forms_v1"
func _get_visible_name() -> String: return "Gaussian Cake Form Library"
func _get_recognized_extensions() -> PackedStringArray: return PackedStringArray(["gcforms"])
func _get_save_extension() -> String: return "res"
func _get_resource_type() -> String: return "Resource"
func _get_format_version() -> int: return 1
func _get_preset_count() -> int: return 1
func _get_preset_name(_preset_index: int) -> String: return "Default"
func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]: return []
func _get_option_visibility(_path: String, _option_name: StringName, _options: Dictionary) -> bool: return true
func _import(source_file: String, save_path: String, _options: Dictionary, _platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var decoder := Decoder.new()
	if not decoder.load_file(source_file):
		push_error("Gaussian Cake: " + decoder.error)
		return ERR_FILE_CORRUPT
	var library := Library.new()
	library.library_bytes = decoder.data
	library.resource_name = "%d forms · %d splats" % [decoder.form_count,decoder.count]
	return ResourceSaver.save(library,save_path+".res")
