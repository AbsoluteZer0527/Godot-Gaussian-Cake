extends Node3D
const Topology = preload("res://addons/gaussian_cake/runtime/topology_player_3d.gd")
const Splats = preload("res://addons/gaussian_cake/runtime/splat_player_3d.gd")
const Forms = preload("res://addons/gaussian_cake/runtime/form_player_3d.gd")
const FORM_LIBRARY := "res://examples/assets/forms/library.json"

func _ready() -> void:
	var topology := Topology.new()
	topology.source_scene = load("res://examples/assets/round_to_tall.glb")
	add_child(topology)
	var splats := Splats.new()
	splats.clip = load("res://examples/assets/round_to_tall.gcsplat")
	add_child(splats)
	topology.seek(0.5)
	splats.seek(0.5)
	var ok := topology.error.is_empty() and splats.error.is_empty() and topology.time == 0.5 and splats.time == 0.5
	# A clean consumer project contains only the addon and exported assets.
	var forms := Forms.new()
	forms.library_path = FORM_LIBRARY
	forms.paused = true
	forms.transport_mode = "refined"
	add_child(forms)
	await forms.wait_until_ready()
	ok = ok and forms.initialized and forms.error.is_empty() and forms.splat_count == 3
	if forms.initialized:
		for target in ["apple", "mushroom", "slime"]:
			forms.morph_to(target, 2.0)
			while forms.loading: await get_tree().process_frame
			ok = ok and forms.last_transport == "refined"
			forms.seek(1.0)
			ok = ok and forms.current_form == target
	if "--expect-pack" in OS.get_cmdline_user_args():
		ok = ok and not FileAccess.file_exists("res://examples/assets/round_to_tall.gcsplat")
		ok = ok and not FileAccess.file_exists("res://addons/gaussian_cake/editor/splat_importer.gd")
		ok = ok and not FileAccess.file_exists("res://addons/gaussian_cake/editor/transport_map_importer.gd")
		ok = ok and not FileAccess.file_exists("res://examples/assets/forms/forms.gcforms")
		for filename in ["0_1.gcmap", "1_2.gcmap", "2_0.gcmap"]:
			ok = ok and not FileAccess.file_exists(FORM_LIBRARY.get_base_dir().path_join(filename))
	print("Gaussian Cake packaged resources: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
