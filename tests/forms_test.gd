extends SceneTree
const Decoder = preload("res://addons/gaussian_cake/runtime/form_decoder.gd")
const Renderer = preload("res://addons/gaussian_cake/runtime/form_splat_renderer.gd")
const Library = preload("res://addons/gaussian_cake/resources/form_library.gd")
var checks := 0
var failures := 0
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: "+message)
func _initialize() -> void: run.call_deferred()

func fixture() -> PackedByteArray:
	var metadata := JSON.stringify({"names":["slime","apple","mushroom"],"reference":0,"profile":"endpoint-v1"}).to_utf8_buffer()
	while metadata.size()%4: metadata.append(32)
	var bytes := PackedByteArray()
	bytes.resize(64)
	var magic := PackedByteArray([71,67,70,79,82,77,83,0])
	for i in range(8): bytes[i] = magic[i]
	for entry in [[8,1],[12,64],[16,2],[20,3],[24,metadata.size()],[28,1],[32,56]]: bytes.encode_u32(entry[0],entry[1])
	bytes.encode_float(36,1.5)
	for axis in range(3):
		bytes.encode_float(40+axis*4,-10.0)
		bytes.encode_float(52+axis*4,10.0)
	bytes.append_array(metadata)
	for form in range(3):
		for i in range(2):
			var q := Quaternion(Vector3.UP,float(form)*0.4)
			var record := PackedFloat32Array([float(form),float(i),float(form-i),q.x,q.y,q.z,q.w,-2.0+form*.2,-2.0,-3.0,.2+form*.2,.5,.7,1.0])
			bytes.append_array(record.to_byte_array())
	return bytes

func rejects(bytes: PackedByteArray, label: String) -> void:
	var decoder := Decoder.new()
	check(not decoder.load_bytes(bytes) and not decoder.error.is_empty(),label)
	check(decoder.data.is_empty(),label+" leaves no usable payload")

func run() -> void:
	var bytes := fixture()
	var decoder := Decoder.new()
	check(decoder.load_bytes(bytes),"valid endpoint fixture accepted")
	check(decoder.count==2 and decoder.form_count==3 and decoder.names==PackedStringArray(["slime","apple","mushroom"]),"names and dimensions decoded")
	check(is_equal_approx(decoder.duration,1.5),"default slow duration decoded")
	check(decoder.records(2)[0]==2 and decoder.positions(2)[1]==Vector3(2,1,1),"endpoint attributes and cached positions agree")
	var bad := bytes.duplicate(); bad[0]=0; rejects(bad,"wrong magic rejected")
	bad=bytes.duplicate();bad.encode_u32(8,2);rejects(bad,"unknown version rejected")
	bad=bytes.duplicate();bad.encode_u32(28,0);rejects(bad,"unknown color flags rejected")
	bad=bytes.duplicate();bad.encode_u32(32,52);rejects(bad,"wrong stride rejected")
	bad=bytes.duplicate();bad.resize(bad.size()-1);rejects(bad,"truncated endpoint rejected")
	bad=bytes.duplicate();bad.encode_u32(16,50001);rejects(bad,"renderer capacity enforced")
	bad=bytes.duplicate();bad.encode_float(36,NAN);rejects(bad,"nonfinite duration rejected")
	bad=bytes.duplicate();bad.encode_float(decoder.payload,NAN);rejects(bad,"nonfinite geometry rejected")
	bad=bytes.duplicate();bad.encode_float(decoder.payload+24,0);rejects(bad,"zero quaternion rejected")
	bad=bytes.duplicate();bad.encode_float(decoder.payload+28,81);rejects(bad,"overflowing scale rejected")
	bad=bytes.duplicate();bad.encode_float(decoder.payload+52,1.2);rejects(bad,"invalid alpha rejected")
	bad=bytes.duplicate();bad.encode_float(decoder.payload,20);rejects(bad,"center outside bounds rejected")
	bad=bytes.duplicate();bad[64]=0;rejects(bad,"invalid metadata rejected without parser crash")
	var start := decoder.records(0)
	var end := decoder.records(2)
	var snapshot: Dictionary = Decoder.snapshot(start,end,.37)
	var endpoint := Decoder.interpolate_record(start,end,1,1)
	for field in range(14): check(absf(endpoint[field]-end[14+field])<1e-6,"exact endpoint field %d"%field)
	for index in range(2):
		var before := Decoder.interpolate_record(start,end,.37,index)
		var after := Decoder.interpolate_record(snapshot.records,decoder.records(1),0,index)
		for field in range(14): check(absf(before[field]-after[field])<1e-6,"retarget continuity %d/%d"%[index,field])
		var q := Quaternion(after[3],after[4],after[5],after[6])
		check(absf(q.length_squared()-1)<1e-6,"retarget keeps quaternion normalized")
	var a := start.duplicate()
	var b := start.duplicate()
	for field in range(3,7): b[field] = -b[field]
	var midpoint := Decoder.interpolate_record(a,b,.5,0)
	check(absf(midpoint[6])>.9999,"antipodal quaternions choose shortest path")
	var shared := Library.new()
	shared.library_bytes = bytes
	var worker_a := Thread.new()
	var worker_b := Thread.new()
	worker_a.start(func(): return shared.get_decoder())
	worker_b.start(func(): return shared.get_decoder())
	while worker_a.is_alive() or worker_b.is_alive(): await process_frame
	var decoded_a: RefCounted = worker_a.wait_to_finish()
	var decoded_b: RefCounted = worker_b.wait_to_finish()
	check(decoded_a==decoded_b and decoded_a.error.is_empty() and decoded_b.records(2).size()==28,"concurrent players share only fully validated immutable decoder")
	shared.library_bytes = bytes
	check(shared.get_decoder()!=decoded_a and decoded_a.records(2).size()==28,"resource replacement invalidates cache without mutating current players")
	verify_core_contract()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position=Vector3(0,2,8)
	var renderer := Renderer.new()
	renderer.camera=camera
	renderer.configure(decoder.count,decoder.bounds,start,end,decoder.positions(0),decoder.positions(2))
	root.add_child(renderer)
	await process_frame
	renderer.seek(.37)
	var instance_id: int = renderer._renderer.multimesh.get_instance_id()
	check(renderer.error.is_empty() and renderer._positions_b==decoder.positions(2),"live endpoints use optimized splat renderer")
	renderer.set_endpoints(snapshot.records,decoder.records(1),snapshot.positions,decoder.positions(1))
	renderer.seek(0)
	check(instance_id==renderer._renderer.multimesh.get_instance_id(),"retarget preserves GPU instance allocation")
	check(renderer._positions_a==snapshot.positions,"retarget refreshes cached sorting positions")
	renderer.queue_free();camera.queue_free()
	await process_frame
	print("FORM LIBRARY: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

func verify_core_contract() -> void:
	var source := Decoder.new()
	check(source.load_file("res://tests/fixtures/forms_contract/forms.gcforms"),"native C++ form export is readable")
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/forms_contract/golden.json"))
	check(golden.cases.size()==21,"native golden covers20directedpairs plusinterruption")
	for test_case in golden.cases:
		var values: PackedFloat32Array = source.records(int(test_case.initial))
		for step in test_case.steps:
			var state: Dictionary = Decoder.snapshot(values,source.records(int(step.target)),smoothstep(0.0,1.0,float(step.progress)))
			values = state.records
		for index in range(source.count):
			var expected: Array = test_case.records[index]
			for field in range(14):
				if field >= 3 and field <= 6: continue
				check(absf(values[index*14+field]-float(expected[field]))<0.00002,"C++/Godot attribute parity")
			var q := Quaternion(values[index*14+3],values[index*14+4],values[index*14+5],values[index*14+6])
			var wanted := Quaternion(expected[3],expected[4],expected[5],expected[6])
			check(absf(q.dot(wanted))>.99998,"C++/Godot rotation parity")
