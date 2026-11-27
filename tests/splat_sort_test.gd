extends SceneTree
const Player = preload("res://addons/gaussian_cake/runtime/splat_player_3d.gd")
const Clip = preload("res://addons/gaussian_cake/resources/splat_clip.gd")
var checks := 0
var failures := 0
var player: Node3D
var camera: Camera3D

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",message)

func _initialize() -> void:
	run.call_deferred()

func assert_order(label: String) -> void:
	var cache = player._cache
	var model_view: Transform3D = camera.global_transform.affine_inverse() * player.global_transform
	var direction := Vector3(model_view.basis.x.z,model_view.basis.y.z,model_view.basis.z.z)
	var a: int = cache.interval(player.time)
	var blend: float = clampf((player.time-cache.times[a])/(cache.times[a+1]-cache.times[a]),0,1)
	var depths := PackedFloat32Array()
	var expected: Array[int] = []
	depths.resize(cache.count)
	for i in range(cache.count):
		expected.append(i)
		depths[i] = direction.dot(cache.position_at(a,i).lerp(cache.position_at(a+1,i),blend))
	expected.sort_custom(func(left: int, right: int): return depths[left]<depths[right] if depths[left]!=depths[right] else left<right)
	check(player._order == expected,label+" matches exact depth+ID reference sort")
	var pixels: PackedFloat32Array = player._order_pixels
	var correct := true
	for i in range(cache.count): correct = correct and int(pixels[i]) == expected[i]
	check(correct,label+" GPU lookup agrees with sorted IDs")

func tie_clip() -> Resource:
	var clip := Clip.new()
	var positions := [Vector3(0,0,0),Vector3(0,0,-1),Vector3(0,0,1),Vector3(0,0,-0.0),Vector3(0,0,-1),Vector3(0,0,2),Vector3(0,0,-2),Vector3(1,0,0)]
	var data := PackedByteArray([71,67,83,80,76,65,84,0])
	data.resize(72+positions.size()*56*2)
	data.encode_u32(8,1)
	data.encode_u32(12,64)
	data.encode_u32(16,positions.size())
	data.encode_u32(20,2)
	data.encode_u32(24,1)
	data.encode_u32(28,1)
	data.encode_float(32,1.0)
	data.encode_u32(36,56)
	for axis in range(3):
		data.encode_float(40+axis*4,-10)
		data.encode_float(52+axis*4,10)
	data.encode_float(64,0)
	data.encode_float(68,1)
	for frame in range(2):
		for i in range(positions.size()):
			var start := 72+(frame*positions.size()+i)*56
			var p: Vector3 = positions[i]
			data.encode_float(start,p.x)
			data.encode_float(start+4,p.y)
			data.encode_float(start+8,p.z)
			data.encode_float(start+24,1)
			for axis in range(3): data.encode_float(start+28+axis*4,-5)
			for channel in range(4): data.encode_float(start+40+channel*4,1)
	clip.cache_bytes=data
	return clip

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	camera=Camera3D.new()
	world.add_child(camera)
	camera.current=true
	player=Player.new()
	player.autoplay=false
	player.camera=camera
	player.clip=tie_clip()
	world.add_child(player)
	await process_frame
	await process_frame
	player.set_process(false)
	assert_order("negative / positive / signed-zero / equal depths")
	var before_count: int = player.sort_count
	var buffer: PackedFloat32Array = player._renderer.multimesh.buffer
	player.position=Vector3(2,3,-100)
	camera.position=Vector3(-4,2,1)
	player._render_frame()
	check(player.sort_count==before_count,"pure translations reuse ordering")
	camera.near=.35
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	player._render_frame()
	check(player.sort_count==before_count,"projection/near changes do not sort")
	check(is_equal_approx(player._material.get_shader_parameter("camera_near"),.35),"near clipping uniform updates without sort")
	player.rotation.y=.47
	player._render_frame()
	check(player.sort_count==before_count+1,"model rotation invalidates ordering")
	assert_order("rotated tie geometry")
	check(player._renderer.multimesh.buffer==buffer,"instance buffer remains immutable after sorting")
	player.clip=load("res://examples/slime/assets/morphs/slime_to_mushroom.gcsplat")
	await process_frame
	await process_frame
	check(player._cache.count==48000,"full density retained")
	player.position=Vector3.ZERO
	camera.position=Vector3(3,2,5)
	camera.look_at(Vector3.ZERO)
	for t in [0.0,.031,.11,.24,.66,.75,.40,.02]:
		player.seek(t)
		assert_order("48k seek %s" % t)
	player.scale=Vector3(1.2,.7,1.8)
	camera.position=Vector3(-4,1,-3)
	camera.look_at(Vector3.ZERO)
	player._render_frame()
	assert_order("camera rotation + nonuniform model scale")
	print("SPLAT SORT: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
