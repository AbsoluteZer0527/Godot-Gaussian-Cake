extends SceneTree
const Manifest = preload("res://addons/gaussian_cake/runtime/form_manifest.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	# Exercise published manifests as well as types that previously reached casts
	# or ResourceLoader before validation, producing engine errors instead of a
	# clear manifest failure.
	var topology: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://examples/slime/assets/forms/library.json"))
	var splats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://examples/transitions/assets/library.json"))
	check(Manifest.validate(topology).is_empty(), "existing topology + splat library remains valid")
	check(Manifest.validate(splats).is_empty(), "existing refined splat-only library remains valid")
	check(not Manifest.validate(null).is_empty(), "invalid JSON rejected")
	for field in ["splats", "topology", "colors"]:
		var invalid := topology.duplicate(true)
		invalid[field] = {"path": "unexpected.json"}
		check(not Manifest.validate(invalid).is_empty(), "non-string resource path: " + field)
	for value in [[], {}, "1", 0, -1, 1.5, INF, NAN]:
		var invalid := topology.duplicate(true)
		invalid.rows_per_form = value
		check(not Manifest.validate(invalid).is_empty(), "invalid atlas dimensions rejected")
	var invalid_map := splats.duplicate(true)
	invalid_map.transport_maps[0].metrics = []
	check(not Manifest.validate(invalid_map).is_empty(), "non-dictionary metrics rejected")
	invalid_map = splats.duplicate(true)
	invalid_map.transport_maps[0].from = {"name": "cactus"}
	check(not Manifest.validate(invalid_map).is_empty(), "non-string endpoint name rejected")
	invalid_map = splats.duplicate(true)
	invalid_map.transport_maps.append(invalid_map.transport_maps[0].duplicate(true))
	check(not Manifest.validate(invalid_map).is_empty(), "duplicate directed pair rejected")
	check(Manifest.validate(splats).is_empty(), "validation does not mutate the source manifest")
	print("Form manifest: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
