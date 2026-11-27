extends RefCounted
## Command-line capture and benchmark support, kept separate from the gallery UI.
const OUTPUT_DIRECTORY := "res://out/transitions"
const WARMUP_MSEC := 2200
var gallery: Control

func _init(view: Control) -> void:
	gallery = view

static func requested() -> bool:
	var arguments := OS.get_cmdline_user_args()
	return arguments.has("--transition-benchmark") or arguments.has("--transition-capture") or arguments.has("--transition-smoke")

func run() -> void:
	if _has_arg("--transition-benchmark"):
		await _benchmark()
	else:
		await _automated_preview()

func _has_arg(argument: String) -> bool:
	return OS.get_cmdline_user_args().has(argument)

func _argument(prefix: String, fallback: String) -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with(prefix+"="): return value.trim_prefix(prefix+"=")
	return fallback

func _select_pair(default_from: String, default_to: String) -> Dictionary:
	var from_name := _argument("--transition-from", default_from)
	var to_name := _argument("--transition-to", default_to)
	gallery.source.select(maxi(0,gallery.NAMES.find(from_name)))
	gallery.destination.select(maxi(0,gallery.NAMES.find(to_name)))
	var transport := _argument("--transition-mode","refined")
	gallery.mode.select(0 if transport == "refined" else 1)
	if _has_arg("--transition-raw"): gallery.get_node("%Pixel").button_pressed = false
	return {"from": from_name, "to": to_name, "mode": transport}

func _warm_renderer() -> void:
	var warm_until := Time.get_ticks_msec() + WARMUP_MSEC
	while Time.get_ticks_msec() < warm_until:
		await gallery.get_tree().process_frame

func _output_path(filename: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIRECTORY))
	return OUTPUT_DIRECTORY.path_join(filename)

func _automated_preview() -> void:
	var pair := _select_pair("cactus", "island")
	await gallery._begin()
	gallery.forms.paused = true
	gallery.forms.seek(float(_argument("--transition-progress","0.5")))
	gallery.get_node("%Pause").text = "Play"
	gallery.distance = 3.2 if pair.from == "cactus" or pair.to == "cactus" else 2.8
	gallery._update_camera()
	await _warm_renderer()
	if _has_arg("--transition-capture"):
		await RenderingServer.frame_post_draw
		var path := _output_path("%s-%s-%s-%03d-%s.png" % [
			pair.from, pair.to, pair.mode, roundi(gallery.forms.progress * 100),
			"pixel" if gallery.pixel else "raw"
		])
		gallery.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		print("Transition capture: ",path)
	if _has_arg("--expect-pack"):
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(gallery.forms.library_path))
		var packed := not FileAccess.file_exists("res://addons/gaussian_cake/editor/transport_map_importer.gd")
		packed = packed and gallery.forms.transport_maps.size() == 6 and gallery.forms.last_transport == "refined"
		for entry in manifest.transport_maps:
			packed = packed and not FileAccess.file_exists(gallery.forms.library_path.get_base_dir().path_join(entry.path))
		print("TRANSITION_PACKED_RESOURCES ","PASS" if packed else "FAIL")
		if not packed:
			gallery.get_tree().quit(1)
			return
	print("TRANSITION_SMOKE_OK count=",gallery.forms.splat_count," map=",gallery.forms.last_transport," progress=",gallery.forms.progress)
	gallery.get_tree().quit()

func _benchmark() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var pair := _select_pair("island", "reef")
	gallery.forms.snap_to_form(pair.from)
	await _warm_renderer()
	var prepare_start := Time.get_ticks_usec()
	await gallery._begin()
	gallery.forms.paused = true
	var prepare_ms := float(Time.get_ticks_usec()-prepare_start)/1000.0
	# Endpoint packing/upload is setup; measure only warmed interpolation/sorting.
	for i in range(5): await gallery.get_tree().process_frame
	gallery.forms.seek(0.0)
	gallery.forms.paused = false
	var times := PackedFloat64Array()
	var previous := Time.get_ticks_usec()
	while gallery.forms.progress < 1.0:
		await gallery.get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now-previous)/1000.0)
		previous = now
	times.sort()
	var total := 0.0
	for value in times: total += value
	var result := {
		"from": pair.from, "to": pair.to, "mode": pair.mode,
		"look": "pixel" if gallery.pixel else "raw",
		"count": gallery.forms.splat_count, "frames": times.size(),
		"mean_ms": total / times.size(), "fps": 1000.0 * times.size() / total,
		"p50_ms": times[int(times.size() * 0.5)],
		"p95_ms": times[int(times.size() * 0.95)], "worst_ms": times[-1],
		"endpoint_prepare_ms": prepare_ms, "vsync": false,
		"device": RenderingServer.get_video_adapter_name()
	}
	var path := _output_path("benchmark-%s-%s.json" % [pair.mode, result.look])
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("TRANSITION_BENCHMARK ",JSON.stringify(result))
	gallery.get_tree().quit()
