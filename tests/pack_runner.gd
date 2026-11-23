extends Node3D
const Topology = preload("res://addons/gaussian_cake/runtime/topology_player_3d.gd")
const Splats = preload("res://addons/gaussian_cake/runtime/splat_player_3d.gd")

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
	if "--expect-pack" in OS.get_cmdline_user_args():
		ok = ok and not FileAccess.file_exists("res://examples/assets/round_to_tall.gcsplat")
		ok = ok and not FileAccess.file_exists("res://addons/gaussian_cake/editor/splat_importer.gd")
	print("Gaussian Cake packaged resources: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
