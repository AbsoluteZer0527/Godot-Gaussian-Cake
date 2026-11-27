extends Node3D
## Runs the scene created by the editor preparation probe, including from an isolated PCK.
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func _ready() -> void:
	var player := get_node("PreparedMorph")
	var deadline := Time.get_ticks_msec() + 15000
	while not player.initialized and player.error.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(player.initialized and player.error.is_empty(), "prepared forms load without the authoring CLI")
	if player.initialized:
		check(player.names.size() == 2 and player.splat_count == 128, "prepared runtime endpoints retain the requested count")
		check(player.current_form == player.names[0], "editor preview does not replace runtime initial form")
		player.paused = true
		player.morph_to(player.names[1], 2.0)
		while player.loading: await get_tree().process_frame
		player.seek(0.5)
		check(is_equal_approx(player.progress, 0.5), "prepared library morphs at runtime")
		player.seek(1.0)
		check(player.current_form == player.names[1], "prepared target reaches its endpoint")
	if "--expect-pack" in OS.get_cmdline_user_args():
		check(FileAccess.file_exists(player.library_path), "generated manifest is included in PCK")
		check(not FileAccess.file_exists("res://addons/gaussian_cake/editor/preparation_job.gd"), "preparation backend stays outside the game")
		check(not FileAccess.file_exists("res://test-inputs.json"), "external authoring paths stay outside the game")
	print("Gaussian Cake prepared runtime: ",checks," checks, ",failures," failures")
	get_tree().quit(1 if failures else 0)
