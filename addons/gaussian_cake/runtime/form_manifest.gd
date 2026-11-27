@tool
extends RefCounted
## Structural validation for library.json, independent of scene nodes and I/O.

const MAX_FORMS := 128
const StateMachine = preload("form_state_machine.gd")

static func validate(value: Variant) -> String:
	if not value is Dictionary:
		return "Invalid form library manifest."
	if value.get("format") != "GaussianCakeFormLibrary" or value.get("version") != 1 or value.get("color_space") != "linear":
		return "Invalid form library manifest."
	for field in ["names", "splats"]:
		if not value.has(field):
			return "Missing manifest field: " + field
	if not value.names is Array or value.names.size() < 2 or value.names.size() > MAX_FORMS:
		return "Invalid form names."
	var names := PackedStringArray()
	for name in value.names:
		if not name is String or name.is_empty() or names.has(name):
			return "Invalid or duplicate form name."
		names.append(name)
	if not _is_path(value.splats):
		return "Invalid splat library path."
	if value.has("topology"):
		var topology_error := _validate_topology(value)
		if not topology_error.is_empty():
			return topology_error
	var graph_error := StateMachine.validate(value.get("state_machine", {}), names)
	if not graph_error.is_empty(): return graph_error
	return _validate_maps(value.get("transport_maps", []), names)

static func _validate_topology(value: Dictionary) -> String:
	for field in ["colors", "vertices", "rows_per_form"]:
		if not value.has(field):
			return "Missing topology manifest field: " + field
	if not _is_path(value.topology) or not _is_path(value.colors):
		return "Invalid topology or color atlas path."
	if not _is_positive_integer(value.vertices) or not _is_positive_integer(value.rows_per_form):
		return "Invalid topology vertex count or atlas rows."
	return ""

static func _validate_maps(entries: Variant, names: PackedStringArray) -> String:
	if not entries is Array:
		return "Invalid transport map list."
	var pairs := {}
	for entry in entries:
		if not entry is Dictionary or not entry.has("from") or not entry.has("to") or not entry.has("path"):
			return "Invalid transport map entry."
		if not _is_path(entry.path) or not entry.get("metrics", {}) is Dictionary:
			return "Invalid transport map path or metrics."
		if not entry.from is String or not entry.to is String:
			return "Invalid transport endpoint names."
		var source := names.find(entry.from)
		var target := names.find(entry.to)
		var key := "%d:%d" % [source, target]
		if source < 0 or target < 0 or source == target or pairs.has(key):
			return "Unknown, repeated or identical transport endpoints."
		pairs[key] = true
	return ""

static func _is_path(value: Variant) -> bool:
	return value is String and not value.is_empty()

static func _is_positive_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and value > 0 and value == floor(value)
