extends SceneTree
const Graph = preload("res://addons/gaussian_cake/runtime/form_state_machine.gd")
const Player = preload("res://addons/gaussian_cake/runtime/form_player_3d.gd")
const Library = preload("res://addons/gaussian_cake/resources/form_library.gd")
var checks := 0
var failures := 0
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var resource := Library.new()
	resource.library_bytes = FileAccess.get_file_as_bytes("res://tests/fixtures/forms_contract/forms.gcforms")
	var names: PackedStringArray = resource.get_decoder().names
	var graph := Graph.default_graph(names)
	graph.initial = "apple"
	graph.allow_any = false
	graph.transitions = [{"from":"apple","to":"mushroom","duration":0.8}, {"from":"mushroom","to":"slime","duration":1.2}]
	check(Graph.validate(graph, names).is_empty(), "valid directed graph")
	check(Graph.transition_duration(graph, "apple", "mushroom", 3) == 0.8, "edge duration")
	check(Graph.transition_duration(graph, "mushroom", "apple", 3) < 0, "arrows are directed")
	for mutation in ["initial", "duplicate", "nan", "position", "policy", "version"]:
		var bad := graph.duplicate(true)
		match mutation:
			"initial": bad.initial = "unknown"
			"duplicate": bad.transitions.append(bad.transitions[0].duplicate())
			"nan": bad.transitions[0].duration = NAN
			"position": bad.positions[0] = [0, INF]
			"policy": bad.allow_any = "yes"
			"version": bad.version = 2
		check(not Graph.validate(bad, names).is_empty(), "reject " + mutation)
	DirAccess.make_dir_recursive_absolute("user://state_machine_tests")
	check(ResourceSaver.save(resource, "user://state_machine_tests/forms.res") == OK, "save fixture resource")
	var manifest := {"format":"GaussianCakeFormLibrary", "version":1, "color_space":"linear", "names":Array(names), "splats":"forms.res", "state_machine":graph}
	var file := FileAccess.open("user://state_machine_tests/library.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()
	var player := Player.new()
	player.library_path = "user://state_machine_tests/library.json"
	root.add_child(player)
	var deadline := Time.get_ticks_msec() + 10000
	while not player.initialized and player.error.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	check(player.initialized and player.error.is_empty(), "graph library loads")
	if not player.initialized:
		quit(1)
		return
	player.set_process(false)
	check(player.current_form == "apple", "initial state applied")
	check(not player.request_state("slime") and player.target_form == "apple", "forbidden edge preserves state")
	check(player.request_state("mushroom"), "allowed edge accepted")
	check(is_equal_approx(player._seconds, .8), "runtime uses edge duration")
	player.seek(.37)
	var held: PackedFloat32Array = player.splat_attributes(0)
	check(player.request_state("slime"), "interruption follows outgoing edge of requested destination")
	check(not player.request_state("crate"), "invalid request during snapshot is rejected")
	deadline = Time.get_ticks_msec() + 10000
	while player.loading and Time.get_ticks_msec() < deadline: await process_frame
	check(not player.loading and player.error.is_empty(), "interruption finishes preparing")
	var redirected: PackedFloat32Array = player.splat_attributes(0)
	for field in range(14): check(absf(held[field] - redirected[field]) < .00002, "continuous attribute %d" % field)
	check(is_equal_approx(player._seconds, 1.2), "interruption uses new edge duration")
	player.seek(1)
	check(player.target_form == "slime", "direct destination reached")
	player.state_machine_override = Graph.default_graph(names)
	check(player.can_transition_to("crate"), "scene override permits direct transition")
	check(not manifest.state_machine.allow_any, "override leaves imported graph immutable")
	player.queue_free()
	await process_frame
	print("STATE MACHINE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
