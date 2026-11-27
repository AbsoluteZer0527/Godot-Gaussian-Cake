extends SceneTree
## Saved Inspector previews must never replace a game's initial pose or clock.
const Player = preload("res://addons/gaussian_cake/runtime/form_player_3d.gd")
const LIBRARY := "res://tests/fixtures/transport_maps/library.json"
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	run.call_deferred()

func argument(prefix: String) -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with(prefix + "="):
			return value.trim_prefix(prefix + "=")
	return ""

func ready_player(player: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while not player.initialized and player.error.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(player.initialized and player.error.is_empty(), "runtime library loads")
	return player.initialized

func near(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	if a.size() != b.size(): return false
	for i in range(a.size()):
		if absf(a[i] - b[i]) > 0.00005: return false
	return true

func run() -> void:
	var saved := argument("--preview-saved")
	for start_paused in [false, true]:
		var player: Node
		if saved.is_empty():
			player = Player.new()
			player.library_path = LIBRARY
			player.preview_source = "apple"
			player.preview_target = "mushroom"
			player.preview_progress = 0.65
			player.preview_loop = true
		else:
			var packed := load(saved) as PackedScene
			check(packed != null, "saved editor scene loads")
			if packed == null: quit(1); return
			check(packed.get_state().get_node_count() == 1, "saved preview contains no generated renderer children")
			player = packed.instantiate()
			check(player.preview_source == "slime" and player.preview_target == "apple", "saved pair retained as authoring settings")
			check(is_equal_approx(player.preview_progress, 0.35), "saved scrub setting retained")
		player.paused = start_paused
		root.add_child(player)
		if not await ready_player(player): quit(1); return
		player.set_process(false)
		check(player.current_form == player.names[0] and player.target_form == player.names[0], "game starts at the canonical reference")
		check(player.progress == 1.0 and not player.morphing, "saved editor progress does not start gameplay")
		check(player.paused == start_paused, "preview never changes gameplay paused setting")
		check(not player.preview_playing and not player.preview_preparing, "no editor preview work at runtime")
		var first: PackedFloat32Array = player._decoder.records(0)
		check(near(player.splat_attributes(0), first.slice(0, 14)), "runtime initial splats match reference")
		player.editor_preview_toggle()
		player.editor_preview_reset()
		player.editor_preview_pause()
		player.preview_source = player.names[1]
		player.preview_target = player.names[2]
		player.preview_progress = 0.4
		player._process(0.2)
		check(player.target_form == player.names[0] and player.progress == 1.0, "editor controls are inert at runtime")
		player.paused = false
		player.morph_to(player.names[1], 1.0)
		while player.loading: await process_frame
		player._process(0.25)
		check(is_equal_approx(player.progress, 0.25), "normal gameplay clock still advances")
		player.editor_preview_toggle()
		player.preview_progress = 0.8
		check(is_equal_approx(player.progress, 0.25), "preview changes cannot seek a running game morph")
		player.queue_free()
		await process_frame
	print("Gaussian Cake form preview runtime: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
