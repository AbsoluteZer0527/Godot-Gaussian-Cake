@tool
extends EditorExportPlugin
## JSON manifests are not imported Resources. Include generated libraries at export.
const GENERATED := "res://gaussian_cake_generated"

func _get_name() -> String:
	return "GaussianCakePreparedLibraries"

func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	var root := DirAccess.open(GENERATED)
	if root == null: return
	for directory in root.get_directories():
		var path := GENERATED.path_join(directory).path_join("library.json")
		if not FileAccess.file_exists(path): continue
		var bytes := FileAccess.get_file_as_bytes(path)
		var manifest: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if manifest is Dictionary and manifest.get("format") == "GaussianCakeFormLibrary":
			add_file(path, bytes, false)
