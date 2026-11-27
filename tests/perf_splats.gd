extends SceneTree
const Player = preload("res://addons/gaussian_cake/runtime/splat_player_3d.gd")
var player: Node3D
var camera: Camera3D

func _initialize() -> void:
	run.call_deferred()

func measure(label: String, action: Callable, iterations := 60) -> void:
	var samples := PackedFloat64Array()
	for i in range(iterations + 5):
		var start := Time.get_ticks_usec()
		action.call(i)
		var elapsed := float(Time.get_ticks_usec()-start)/1000.0
		if i >= 5: samples.append(elapsed)
	samples.sort()
	var total := 0.0
	for value in samples: total += value
	print("SPLAT_BENCH ",label," mean_ms=",snappedf(total/samples.size(),.001)," median_ms=",snappedf(samples[samples.size()/2],.001)," p95_ms=",snappedf(samples[int(samples.size()*.95)],.001))

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	camera=Camera3D.new()
	world.add_child(camera)
	camera.position=Vector3(0,1,5)
	camera.look_at(Vector3.ZERO)
	camera.current=true
	player=Player.new()
	player.autoplay=false
	player.camera=camera
	var start := Time.get_ticks_usec()
	player.clip=load("res://examples/slime/assets/morphs/slime_to_mushroom.gcsplat")
	world.add_child(player)
	await process_frame
	await process_frame
	player.set_process(false)
	print("SPLAT_BENCH initial_load_ms=",float(Time.get_ticks_usec()-start)/1000.0," count=",player._cache.count)
	measure("camera_rotation",func(i):
		camera.position=Vector3(5*sin(i*.025),1,5*cos(i*.025))
		camera.look_at(Vector3.ZERO)
		player._render_frame())
	measure("morph",func(i): player.seek(float(i%60)/60.0*.75))
	player.seek(0.0)
	measure("translation",func(i):
		player.position.x=i*.001
		player._render_frame())
	measure("unchanged",func(_i): player._render_frame())
	quit()
