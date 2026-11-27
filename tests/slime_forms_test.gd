extends SceneTree
## Exercise the actual sample's direct form library, controls and triggers.
const NAMES := ["slime", "mushroom", "stone", "apple", "crate"]
const IDS := [0, 37, 997, 12001, 23017, 35999, 47999]
var checks := 0
var failures := 0
var sample: Control
var player: CharacterBody3D
var forms: Node3D

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func prepared() -> bool:
	var limit := Time.get_ticks_msec() + 30000
	while forms.loading and Time.get_ticks_msec() < limit:
		await process_frame
	check(not forms.loading and forms.error.is_empty(), "endpoint preparation finishes without error")
	return not forms.loading and forms.error.is_empty()

func force_form(name: String) -> bool:
	forms.morph_to(name, 1.5)
	if not await prepared(): return false
	forms.seek(1.0)
	return true

func close_arrays(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if not is_finite(a[i]) or not is_finite(b[i]) or absf(a[i]-b[i]) > .00002: return false
	return true

func snapshot() -> Array[PackedFloat32Array]:
	var result: Array[PackedFloat32Array] = []
	for id in IDS: result.append(forms.splat_attributes(id))
	return result

func same_splats(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if a[i].size() != 14 or b[i].size() != 14: return false
		for j in 14:
			if j >= 3 and j <= 6: continue
			if not is_finite(a[i][j]) or not is_finite(b[i][j]) or absf(a[i][j]-b[i][j]) > .00002: return false
		var qa := Quaternion(a[i][3], a[i][4], a[i][5], a[i][6])
		var qb := Quaternion(b[i][3], b[i][4], b[i][5], b[i][6])
		if absf(qa.dot(qb)) < .99998: return false
	return true

func ticks(count: int) -> void:
	for i in count: await physics_frame

func settled() -> bool:
	var limit := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < limit:
		await process_frame
		if not player.last_error.is_empty(): break
		if player.ready_for_input and not player.loading and not player.morphing: return true
	check(false, "sample settles: " + player.last_error)
	return false

func run() -> void:
	var packed = load("res://examples/slime/playground.tscn")
	check(packed is PackedScene, "playground scene imports")
	if not packed is PackedScene:
		finish()
		return
	sample = packed.instantiate()
	check(sample.get_script() != null, "playground UI/controller script loads")
	if sample.get_script() == null:
		finish()
		return
	root.add_child(sample)
	player = sample.get_node("WorldFrame/World/Stage/Player")
	forms = player.get_node("VisualRoot/Forms")
	if not await settled():
		finish()
		return
	check(is_equal_approx(player.morph_duration, 1.5), "duration is twice the former 0.75 seconds")
	var collider: CollisionShape3D = player.get_node("CollisionShape3D")
	var collider_id := collider.shape.get_instance_id()
	var collider_transform := collider.transform
	forms.set_process(false)
	var endpoints: Dictionary = {}
	for name in NAMES:
		if not await force_form(name):
			finish()
			return
		endpoints[name] = snapshot()
		var weights: PackedFloat32Array = forms.topology_weights()
		check(weights.size() == 5 and is_equal_approx(weights[NAMES.find(name)], 1.0), name + " has an exact named topology endpoint")
		check(endpoints[name][0].size() == 14, name + " exposes full Gaussian attributes")
	for mode in ["topology", "splats"]:
		player.request_renderer(mode)
		await prepared()
		for source in NAMES:
			for destination in NAMES:
				if source == destination: continue
				await force_form(source)
				player.request_form(destination)
				await prepared()
				forms.seek(.5)
				var weights: PackedFloat32Array = forms.topology_weights()
				check(forms.morphing and forms.target_form == destination, mode + " direct " + source + " to " + destination)
				check(is_equal_approx(weights[NAMES.find(source)], .5) and is_equal_approx(weights[NAMES.find(destination)], .5), "midpoint blends the requested forms directly")
				if source != "slime" and destination != "slime": check(is_zero_approx(weights[0]), "non-slime pair does not visit slime")
				forms.seek(1.0)
				check(forms.current_form == destination and not forms.morphing, "transition completes at destination")
				check(same_splats(snapshot(), endpoints[destination]), "Gaussian endpoint does not depend on source or renderer")
				check(collider.shape.get_instance_id() == collider_id and collider.transform == collider_transform, "morph preserves collider")
	await force_form("apple")
	player.request_form("mushroom")
	await prepared()
	forms.seek(.37)
	var before_weights: PackedFloat32Array = forms.topology_weights()
	var before_splats := snapshot()
	player.request_form("crate")
	await prepared()
	check(close_arrays(forms.topology_weights(), before_weights), "retarget has no topology pose jump")
	check(same_splats(snapshot(), before_splats), "retarget has no Gaussian pose jump")
	check(forms.target_form == "crate" and forms.morphing, "latest destination replaces unfinished transition")
	forms.seek(.26)
	before_weights = forms.topology_weights()
	before_splats = snapshot()
	player.request_renderer("topology")
	await prepared()
	player.request_renderer("splats")
	await prepared()
	check(close_arrays(forms.topology_weights(), before_weights) and same_splats(snapshot(), before_splats), "renderer switch preserves interrupted pose")
	forms.seek(1.0)
	check(forms.current_form == "crate", "retarget finishes at final requested form")
	await force_form("slime")
	forms.set_process(true)
	player.position = Vector3(0,.1,0)
	player.request_form("apple")
	var started := Time.get_ticks_msec()
	var start := player.position
	Input.action_press("slime_right")
	await ticks(18)
	Input.action_release("slime_right")
	check(player.position.distance_to(start) > .3 and player.morphing, "character moves while morphing")
	await settled()
	check(Time.get_ticks_msec()-started >= 1300, "1.5-second runtime clock ignores old clip timestamps")
	var trigger: Area3D = sample.get_node("WorldFrame/World/Stage/Targets/Mushroom")
	player.global_position = trigger.global_position + Vector3(0,.05,0)
	player.velocity = Vector3.ZERO
	await ticks(5)
	check(player.desired_form == "mushroom", "real Area3D contact requests mushroom from apple")
	await settled()
	check(player.current_form == "mushroom", "contact completes direct apple to mushroom")
	player.reset_to_slime()
	await settled()
	await ticks(12)
	check(player.current_form == "slime" and not player.morphing, "standing inside target does not retrigger")
	player.global_position = Vector3(0,.1,0)
	await ticks(5)
	player.global_position = trigger.global_position + Vector3(0,.05,0)
	await ticks(5)
	await settled()
	check(player.current_form == "mushroom", "leaving and reentering target triggers again")
	finish()

func finish() -> void:
	if is_instance_valid(sample):
		sample.queue_free()
		await process_frame
	print("SLIME FORMS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
