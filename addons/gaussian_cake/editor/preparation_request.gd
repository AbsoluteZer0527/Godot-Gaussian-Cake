@tool
extends RefCounted
## File preparation and validation run on a worker, without editor or scene access.
const Decoder = preload("../runtime/form_decoder.gd")
const Manifest = preload("../runtime/form_manifest.gd")
const SCHEMA := 1
const MAX_INPUT_BYTES := 1024 * 1024 * 1024
const CHUNK_BYTES := 1024 * 1024
var settings: Dictionary
var cache_root := ""
var generated_root := ""
var key := ""
var stage := ""
var _input_hashes := {}
var _mutex := Mutex.new()
var _cancelled := false

func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()

func is_cancelled() -> bool:
	_mutex.lock()
	var value := _cancelled
	_mutex.unlock()
	return value

static func normalize(input: Dictionary, project_root: String) -> Dictionary:
	var value := {}
	for field in ["cli_path", "source_path", "target_path"]:
		if not input.get(field) is String or str(input[field]).strip_edges().is_empty():
			return {"error": "Choose " + field.replace("_", " ") + "."}
		var path: String = input[field].strip_edges()
		if path.begins_with("res://"):
			path = project_root.path_join(path.trim_prefix("res://"))
		elif not path.is_absolute_path():
			path = project_root.path_join(path)
		path = path.simplify_path()
		if not FileAccess.file_exists(path):
			return {"error": "File does not exist: " + path}
		if field != "cli_path" and path.get_extension().to_lower() not in ["ply", "glb"]:
			return {"error": "Choose a .ply or .glb model: " + path}
		value[field] = path
	for field in ["count", "samples", "mixtures", "up"]:
		var defaults := {"count":12000,"samples":1200,"mixtures":8,"up":0}
		var maximums := {"count":50000,"samples":1000000,"mixtures":128,"up":3}
		var number: Variant = input.get(field, defaults[field])
		var minimum := 0 if field == "up" else (4 if field == "samples" else 1)
		if (not number is int and not number is float) or not is_finite(float(number)) or float(number) != floor(float(number)) or number < minimum or number > maximums[field]:
			return {"error": "Invalid %s: use an integer from %d to %d." % [field,minimum,maximums[field]]}
		value[field] = int(number)
	if value.mixtures > value.samples:
		return {"error": "Mixture count cannot exceed sample count."}
	for field in ["color_match", "size", "crop"]:
		var defaults := {"color_match":0.35,"size":1.0,"crop":100.0}
		var maximums := {"color_match":1.0,"size":1000.0,"crop":100000.0}
		var number: Variant = input.get(field,defaults[field])
		if (not number is int and not number is float) or not is_finite(float(number)) or number < 0.0 or number > maximums[field] or (field != "color_match" and number == 0.0):
			return {"error": "Invalid " + field.replace("_", " ") + "."}
		value[field] = float(number)
	if not input.get("dc_only",false) is bool:
		return {"error": "DC-only color must be on or off."}
	value.dc_only = input.get("dc_only",false)
	for endpoint in ["source", "target"]:
		var fallback: String = value[endpoint+"_path"].get_file().get_basename()
		var name_value: Variant = input.get(endpoint+"_name", fallback)
		if not name_value is String:
			return {"error": "Form names must be text."}
		var form_name: String = name_value.strip_edges()
		if form_name.is_empty(): form_name = endpoint
		while form_name.to_utf8_buffer().size() > 240: form_name = form_name.left(form_name.length()-1)
		value[endpoint+"_name"] = form_name
	if value.source_name == value.target_name:
		value.source_name += "_source"
		value.target_name += "_target"
	return {"settings":value}

func inspect() -> Dictionary:
	var fingerprints := {}
	for field in ["cli_path", "source_path", "target_path"]:
		var path: String = settings[field]
		var checksum := _checksum(path)
		if checksum.is_empty(): return _error("Cannot read file or preparation was cancelled: " + path)
		fingerprints[path] = checksum
		if field != "cli_path" and path.get_extension().to_lower() == "glb":
			var dependencies := _glb_dependencies(path)
			if dependencies.has("error"): return dependencies
			for dependency in dependencies.paths:
				var digest := _checksum(dependency)
				if digest.is_empty(): return _error("Cannot read GLB dependency: " + dependency)
				fingerprints[dependency] = digest
	if is_cancelled(): return {"cancelled":true}
	var identity := {"schema":SCHEMA,"settings":settings,"inputs":fingerprints}
	_input_hashes = fingerprints
	key = JSON.stringify(identity, "", true).sha256_text()
	var cached := _find_cached()
	if not cached.is_empty():
		return {"manifest":_resource_path(cached.path_join("library.json")),"cached":true}
	if is_cancelled(): return {"cancelled":true}
	# A fresh private directory isolates crashes, cancellation, and failed exports.
	# The fingerprint belongs in metadata, not in this temporary path. Keeping
	# staging short leaves room for the native exporter's atomic-write filenames
	# on Windows projects whose own directory is already deeply nested.
	stage = cache_root.path_join((str(Time.get_ticks_usec())+"-"+str(randi())).sha256_text().left(16))
	if DirAccess.make_dir_recursive_absolute(stage) != OK:
		return _error("Cannot create preparation workspace: " + stage)
	var project := {
		"format":"GaussianCakeFormProject","version":1,"default_duration":4.0,
		"splats":{
			"reference":settings.source_name,"count":settings.count,"samples":settings.samples,
			"mixtures":settings.mixtures,"color_match":settings.color_match,"size":settings.size,
			"up":settings.up,"crop":settings.crop,"dc_only":settings.dc_only,
			"forms":[{"name":settings.source_name,"source":settings.source_path},
				{"name":settings.target_name,"source":settings.target_path}]
		}
	}
	if not _write_json(stage.path_join("models.gcformproject"),project):
		return _error("Cannot write the generated form project.")
	return {"project":stage.path_join("models.gcformproject"),"output":stage.path_join("result")}

func validate_and_publish() -> Dictionary:
	var output := stage.path_join("result")
	var message := _validate_bundle(output)
	if not message.is_empty(): return _error(message)
	if is_cancelled(): return {"cancelled":true}
	for path in _input_hashes:
		if _checksum(path) != _input_hashes[path]:
			return _error("A source model, dependency, or CLI changed during preparation. Prepare again.")
	var metadata := {"schema":SCHEMA,"key":key,"source_name":settings.source_name,"target_name":settings.target_name,
		"manifest_sha256":_checksum(output.path_join("library.json")),"splats_sha256":_checksum(output.path_join("forms.gcforms"))}
	if is_cancelled(): return {"cancelled":true}
	if metadata.manifest_sha256.is_empty() or metadata.splats_sha256.is_empty() or not _write_json(output.path_join("preparation.json"),metadata):
		return _error("Cannot record the prepared library checksums.")
	if DirAccess.make_dir_recursive_absolute(generated_root) != OK:
		return _error("Cannot create generated asset folder.")
	var destination := generated_root.path_join(key)
	# Existing invalid or unrelated output is left untouched. A new successful
	# revision gets its own directory; the previous player's asset remains usable.
	if DirAccess.dir_exists_absolute(destination) or FileAccess.file_exists(destination):
		if _valid_cached(destination): return {"manifest":_resource_path(destination.path_join("library.json")),"cached":true}
		destination += "-"+str(Time.get_ticks_usec())
	if is_cancelled(): return {"cancelled":true}
	# Cache and final assets are inside one Godot project, so this directory rename
	# publishes the validated bundle together, without partially imported assets.
	if DirAccess.rename_absolute(output,destination) != OK:
		return _error("Cannot publish prepared library: " + destination)
	return {"manifest":_resource_path(destination.path_join("library.json")),"cached":false}

func _find_cached() -> String:
	var directory := generated_root.path_join(key)
	if _valid_cached(directory): return directory
	if not DirAccess.dir_exists_absolute(generated_root): return ""
	var root := DirAccess.open(generated_root)
	if root == null: return ""
	# Repaired cache entries use new directories so a corrupt/unrelated existing
	# folder is never overwritten. Discover valid revisions after editor restarts.
	for name in root.get_directories():
		if is_cancelled(): return ""
		if name.begins_with(key+"-") and _valid_cached(generated_root.path_join(name)):
			return generated_root.path_join(name)
	return ""

func _valid_cached(directory: String) -> bool:
	var marker: Variant = _read_json(directory.path_join("preparation.json"))
	if not marker is Dictionary or marker.get("schema") != SCHEMA or marker.get("key") != key:
		return false
	if marker.get("source_name") != settings.source_name or marker.get("target_name") != settings.target_name:
		return false
	for entry in [["library.json","manifest_sha256"],["forms.gcforms","splats_sha256"]]:
		var digest := _checksum(directory.path_join(entry[0]))
		if digest.is_empty() or marker.get(entry[1],"") != digest: return false
	return _validate_bundle(directory).is_empty()

func _validate_bundle(directory: String) -> String:
	var manifest: Variant = _read_json(directory.path_join("library.json"))
	var message := Manifest.validate(manifest)
	if not message.is_empty(): return "Prepared output is invalid: " + message
	if manifest.get("splats") != "forms.gcforms" or manifest.has("topology") or manifest.get("transport_maps",[]) != []:
		return "CLI returned an unexpected output layout. Expected a two-form splat library."
	if manifest.names != [settings.source_name,settings.target_name]:
		return "Prepared form names do not match the selected models."
	var decoder := Decoder.new()
	if not decoder.load_file(directory.path_join("forms.gcforms")):
		return "Prepared splats are invalid: " + decoder.error
	if decoder.names != PackedStringArray(manifest.names):
		return "Prepared form names do not match the request."
	if decoder.count < settings.count:
		return "Requested %d splats, but these sources produced %d usable splats. Lower Splat count to %d or less and Prepare again." % [settings.count,decoder.count,decoder.count]
	if decoder.count != settings.count:
		return "Prepared splat count does not match the request."
	return ""

func _checksum(path: String) -> String:
	if is_cancelled(): return ""
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > MAX_INPUT_BYTES: return ""
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK: return ""
	while file.get_position() < file.get_length():
		if is_cancelled(): return ""
		var data := file.get_buffer(mini(CHUNK_BYTES,file.get_length()-file.get_position()))
		if data.is_empty() or hashing.update(data) != OK: return ""
	return hashing.finish().hex_encode()

func _glb_dependencies(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() < 20: return _error("Invalid GLB header: " + path)
	if file.get_32() != 0x46546c67 or file.get_32() != 2 or file.get_32() != file.get_length():
		return _error("Expected a binary glTF 2.0 (.glb) file: " + path)
	var size := file.get_32()
	if file.get_32() != 0x4e4f534a or size > 64*1024*1024 or size > file.get_length()-20:
		return _error("Invalid GLB JSON chunk: " + path)
	var document: Variant = JSON.parse_string(file.get_buffer(size).get_string_from_utf8())
	if not document is Dictionary: return _error("Invalid GLB JSON: " + path)
	var paths := PackedStringArray()
	for field in ["buffers","images"]:
		var entries: Variant = document.get(field,[])
		if not entries is Array: return _error("Invalid GLB " + field + ".")
		for entry in entries:
			if not entry is Dictionary: return _error("Invalid GLB " + field + " entry.")
			var uri: Variant = entry.get("uri","")
			if not uri is String: return _error("Invalid GLB dependency URI.")
			if uri.is_empty() or uri.begins_with("data:"): continue
			if uri.contains("://"): return _error("Download GLB dependencies locally before preparing: " + uri)
			var dependency := path.get_base_dir().path_join(uri.uri_decode()).simplify_path()
			if not paths.has(dependency): paths.append(dependency)
	return {"paths":paths}

func _resource_path(path: String) -> String:
	return "res://gaussian_cake_generated/"+path.trim_prefix(generated_root.trim_suffix("/")+"/")

static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() > 1024*1024: return null
	return JSON.parse_string(file.get_as_text())

static func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(value,"\t",true)+"\n")
	return file.get_error() == OK

func _error(message: String) -> Dictionary:
	return {"cancelled":true} if is_cancelled() else {"error":message}
