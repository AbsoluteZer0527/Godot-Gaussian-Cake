extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",message)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	root.size = Vector2i(1100,720)
	var sample = load("res://examples/slime/playground.tscn").instantiate()
	root.add_child(sample)
	await sample.player.wait_until_settled()
	check(sample.pixel_look,"pixel presentation enabled by default")
	check(sample.world_frame.material is ShaderMaterial,"world has a real postprocess material")
	check(sample.palette.size() == 40 and sample.dither_amount > 0,"curated palette and ordered dithering configured")
	check(sample.world_frame.scale == Vector2(3,3),"1100x720 uses integer 3x enlargement")
	check(sample.world.size == Vector2i(366,240),"world rendered at integer source dimensions")
	check(sample.world_frame.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,"nearest enlargement keeps crisp pixels")
	check(sample.get_node("HUD").material == null,"HUD remains outside the world color pass")
	var toggle := InputEventKey.new()
	toggle.physical_keycode = KEY_P
	toggle.pressed = true
	sample._unhandled_key_input(toggle)
	check(not sample.pixel_look and sample.world_frame.material == null,"P turns off palette/dither pass")
	check(sample.world_frame.scale == Vector2.ONE and sample.world.size == Vector2i(1100,720),"raw mode renders natively without changing camera")
	sample._unhandled_key_input(toggle)
	check(sample.pixel_look and sample.world_frame.material != null,"P restores pixel look")
	root.size = Vector2i(800,600)
	await process_frame
	await process_frame
	check(sample.world_frame.scale == Vector2(2,2) and sample.world.size == Vector2i(400,300),"resize retains integer pixels")
	sample.queue_free()
	await process_frame
	print("PIXEL PRESENTATION: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
