extends SceneTree
const Player = preload("res://addons/gaussian_cake/runtime/form_player_3d.gd")
const LIBRARY := "res://examples/slime/assets/forms/library.json"
var checks := 0
var failures := 0
func check(condition: bool,message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: "+message)
func _initialize() -> void: run.call_deferred()
func ready_player(player: Node) -> void:
	var deadline := Time.get_ticks_msec()+15000
	while not player.initialized and player.error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check(player.initialized and player.error.is_empty(),"library loads within15seconds")
func run() -> void:
	var first := Player.new()
	var second := Player.new()
	first.library_path=LIBRARY
	second.library_path=LIBRARY
	root.add_child(first)
	root.add_child(second)
	await ready_player(first)
	await ready_player(second)
	if not first.initialized or not second.initialized:
		quit(1)
		return
	check(first._decoder==second._decoder,"concurrent instances reuse immutable decoder")
	first.set_process(false)
	second.set_process(false)
	first.morph_to("apple")
	first.seek(.37)
	check(first.topology_weights()!=second.topology_weights(),"instance clocks and attributes remain independent")
	first.renderer_mode="splats"
	check(first.splats.visible and not first.topology.visible,"Inspector renderer property updates visibility")
	first.library_path=LIBRARY
	await process_frame
	await ready_player(first)
	var weights: PackedFloat32Array=first.topology_weights()
	check(weights[0]==1.0 and weights.slice(1)==PackedFloat32Array([0,0,0,0]),"Inspector reload resets old form weights")
	check(first.get_child_count()==2,"reload replaces runtime nodes without accumulating children")
	first.morph_to("apple")
	first.seek(1)
	first.seek(.4)
	var held: PackedFloat32Array = first.splat_attributes(997)
	first.morph_to("mushroom")
	while first.loading: await process_frame
	var redirected: PackedFloat32Array = first.splat_attributes(997)
	var maximum_error := 0.0
	for field in range(14): maximum_error=maxf(maximum_error,absf(held[field]-redirected[field]))
	check(maximum_error<.00002,"completed then seeked transition snapshots actual current pose on retarget")
	first.seek(1)
	first.seek(.4)
	first.morph_to("mushroom")
	check(first.loading,"requesting current target resumes from a manually held intermediate pose")
	while first.loading: await process_frame
	first.seek(1)
	first.morph_to("apple")
	first.seek(.4)
	first.morph_to("mushroom")
	check(first.loading,"interruption launches worker")
	# Simulate closing the scene with a snapshot worker in flight.
	first.queue_free()
	second.queue_free()
	await process_frame
	await process_frame
	print("FORM LIFECYCLE: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
