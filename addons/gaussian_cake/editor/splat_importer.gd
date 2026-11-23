@tool
extends EditorImportPlugin
const Decoder = preload("../runtime/splat_decoder.gd")
const Clip = preload("../resources/splat_clip.gd")

func _get_importer_name() -> String:
	return "gaussian_cake.splat_v1"

func _get_visible_name() -> String:
	return "Gaussian Cake Splat Clip"

func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["gcsplat"])

func _get_save_extension() -> String:
	return "res"

func _get_resource_type() -> String:
	return "Resource"

func _get_format_version() -> int:
	return 1

func _get_preset_count() -> int:
	return 1

func _get_preset_name(_preset_index: int) -> String:
	return "Default"

func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return [{"name": "limits/max_splats", "default_value": 50000,
		"property_hint": PROPERTY_HINT_RANGE, "hint_string": "1,50000,1"}]

func _get_option_visibility(_path: String, _option_name: StringName, _options: Dictionary) -> bool:
	return true

func _import(source_file: String, save_path: String, options: Dictionary,
		_platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var decoder := Decoder.new()
	if not decoder.load_file(source_file):
		push_error("Gaussian Cake: %s: %s" % [source_file, decoder.error])
		return ERR_FILE_CORRUPT
	var limit := clampi(int(options.get("limits/max_splats", 50000)), 1, 50000)
	if decoder.count > limit:
		push_error("Gaussian Cake: %d splats exceeds import limit %d. Re-export at a lower count; start with 5,000." % [decoder.count, limit])
		return ERR_INVALID_DATA
	var clip := Clip.new()
	clip.cache_bytes = decoder.data
	clip.resource_name = "%d splats · %d frames · %.2f s" % [decoder.count, decoder.frames, decoder.duration]
	return ResourceSaver.save(clip, save_path + ".res")
