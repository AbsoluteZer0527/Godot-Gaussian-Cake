extends SceneTree
const Decoder = preload("res://addons/gaussian_cake/runtime/transport_map_decoder.gd")
const Player = preload("res://addons/gaussian_cake/runtime/form_player_3d.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: "+label)
func near(a: PackedFloat32Array,b: PackedFloat32Array) -> bool:
	if a.size() != b.size(): return false
	for i in range(a.size()):
		if i >= 3 and i <= 6: continue
		if absf(a[i]-b[i]) > 0.00001: return false
	var qa := Quaternion(a[3],a[4],a[5],a[6]).normalized()
	var qb := Quaternion(b[3],b[4],b[5],b[6]).normalized()
	return absf(qa.dot(qb)) > 0.999999
func reject(bytes: PackedByteArray, label: String) -> void:
	var decoder := Decoder.new()
	check(not decoder.load_bytes(bytes) and not decoder.error.is_empty() and decoder.ids.is_empty(),label)
func prepared(player: Node) -> void:
	while player.loading: await process_frame
func run() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/transport_maps/0_1.gcmap")
	var decoder := Decoder.new()
	check(decoder.load_bytes(bytes),"valid permutation")
	check(decoder.ids == PackedInt32Array([1,2,0]) and decoder.source == 0 and decoder.target == 1,"header and IDs")
	var bad := bytes.duplicate(); bad.encode_u32(32,2); reject(bad,"duplicate destination rejected")
	bad = bytes.duplicate(); bad.encode_u32(32,3); reject(bad,"out of range destination rejected")
	bad = bytes.duplicate(); bad.encode_u32(8,2); reject(bad,"unknown version rejected")
	bad = bytes.duplicate(); bad.encode_u32(12,64); reject(bad,"wrong header size rejected")
	bad = bytes.duplicate(); bad.encode_u32(28,0); reject(bad,"unknown flags rejected")
	bad = bytes.duplicate(); bad.encode_u32(20,128); reject(bad,"impossible source index rejected")
	bad = bytes.duplicate(); bad.encode_u32(24,0); reject(bad,"identical endpoints rejected")
	bad = bytes.duplicate(); bad.resize(bad.size()-1); reject(bad,"truncated map rejected")
	bad = bytes.duplicate(); bad.append(0); reject(bad,"trailing map bytes rejected")
	bad = bytes.duplicate(); bad[0] = 0; reject(bad,"bad magic rejected")
	var player := Player.new()
	check(player.splat_count == 0,"public count is zero before initialization")
	player.library_path = "res://tests/fixtures/transport_maps/library.json"
	player.paused = true
	root.add_child(player)
	await player.wait_until_ready()
	check(player.error.is_empty() and player.initialized,"splat-only library imported")
	check(player.splat_count == 3,"public count exposes the initialized library")
	check(player.topology == null and player.renderer_mode == "splats","topology optional")
	player.set_renderer("topology")
	check(player.renderer_mode == "splats" and player.splats.visible,"missing topology guarded")
	check(player.transport_mode == "shared","legacy shared default")
	player.transport_mode = "refined"
	var expected := PackedInt32Array([0,1,2])
	for cycle in range(3):
		for pair in [[0,1],[1,2],[2,0]]:
			var before: Array[PackedFloat32Array] = []
			for i in range(3): before.append(player.splat_attributes(i))
			var key := "%d:%d" % [pair[0],pair[1]]
			var mapping: PackedInt32Array = player.transport_maps[key].ids
			for i in range(3): expected[i] = mapping[expected[i]]
			player.morph_to(player.names[pair[1]])
			await prepared(player)
			check(player.last_transport == "refined","pair map selected")
			check(player.canonical_ids() == expected,"map composed through current slot IDs")
			for i in range(3): check(near(player.splat_attributes(i),before[i]),"no source jump across cycle")
			player.seek(1.0)
			var records: PackedFloat32Array = player._decoder.records(pair[1])
			for i in range(3): check(near(player.splat_attributes(i),records.slice(expected[i]*14,expected[i]*14+14)),"exact destination set after permutation")
	# Shared transport from an already-permuted endpoint preserves canonical IDs.
	player.transport_mode = "shared"
	player.morph_to("stone")
	await prepared(player)
	check(player.canonical_ids() == expected,"shared mode carries existing IDs")
	player.seek(1.0)
	player.snap_to_form("slime")
	check(player.canonical_ids() == PackedInt32Array([0,1,2]) and player.current_form == "slime","snap resets canonical pose")
	player.transport_mode = "refined"
	player.morph_to("apple")
	await prepared(player)
	player.seek(0.37)
	var held: Array[PackedFloat32Array] = []
	for i in range(3): held.append(player.splat_attributes(i))
	player.morph_to("mushroom")
	await prepared(player)
	check(player.last_transport == "fallback","arbitrary interruption uses stable-ID fallback")
	for i in range(3): check(near(player.splat_attributes(i),held[i]),"interrupted pose continuous")
	player.seek(1.0)
	var old_progress: float = player.progress
	await process_frame
	check(player.progress == old_progress,"paused clock holds pose")
	player.queue_free()
	await process_frame
	# Real 48k assets: import dimensions, every forward/inverse map, a full nonidentity cycle.
	var real := Player.new()
	real.library_path = "res://examples/transitions/assets/library.json"
	real.paused = true
	real.transport_mode = "refined"
	root.add_child(real)
	await real.wait_until_ready()
	check(real.initialized and real._decoder.count == 48000,"complex 48k splat-only library")
	check(real.transport_maps.size() == 6,"all directed complex pairs imported")
	check(real.splat_count == 48000,"public count exposes complex library size")
	check(real.get_transport_metrics("unknown","reef").is_empty(),"unknown pair metrics are empty")
	var metrics: Dictionary = real.get_transport_metrics("island","reef")
	var original_objective: float = metrics.after.objective
	metrics.after.objective = -1.0
	check(real.get_transport_metrics("island","reef").after.objective == original_objective,"public metrics are a deep copy")
	for key in real.transport_maps:
		var pair: PackedStringArray = key.split(":")
		var forward: PackedInt32Array = real.transport_maps[key].ids
		var inverse: PackedInt32Array = real.transport_maps[pair[1]+":"+pair[0]].ids
		var correct := true
		for i in range(forward.size()):
			if inverse[forward[i]] != i: correct = false; break
		check(correct,"real inverse permutation "+key)
	var identity := PackedInt32Array()
	identity.resize(48000)
	for i in range(identity.size()): identity[i] = i
	for pair in [[0,1],[1,2],[2,0]]:
		var held_real: PackedFloat32Array = real.splat_attributes(23117)
		var mapping: PackedInt32Array = real.transport_maps["%d:%d" % [pair[0],pair[1]]].ids
		for i in range(identity.size()): identity[i] = mapping[identity[i]]
		real.morph_to(real.names[pair[1]])
		await prepared(real)
		check(real.last_transport == "refined" and real.canonical_ids() == identity,"real composed IDs")
		check(near(real.splat_attributes(23117),held_real),"real cycle source continuity")
		real.seek(1.0)
		var endpoint: PackedFloat32Array = real._decoder.records(pair[1])
		for i in [0,97,23117,47999]: check(near(real.splat_attributes(i),endpoint.slice(identity[i]*14,identity[i]*14+14)),"real endpoint attributes")
	real.queue_free()
	await process_frame
	print("Transport maps: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
