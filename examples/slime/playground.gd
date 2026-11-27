extends Control
const TOON_SHADER = preload("toon_morph.gdshader")
const PIXEL_SHADER = preload("pixel_palette.gdshader")
@export_group("Pixel presentation")
@export var pixel_look := true
@export_range(144, 480, 8) var pixel_rows := 240
@export_range(0.0, 0.15, 0.005) var dither_amount := 0.04
@export var palette := PackedColorArray([
	Color("0d1620"), Color("172831"), Color("1e3029"), Color("34452f"),
	Color("4c6b3f"), Color("5f7d49"), Color("718949"), Color("87a94d"),
	Color("659937"), Color("83b93b"), Color("99d63e"), Color("a4df43"),
	Color("b0e555"), Color("c4f18b"), Color("407a3f"), Color("55a24c"),
	Color("384a62"), Color("526a82"), Color("6a7d99"), Color("8291ab"),
	Color("a7b2c1"), Color("583d2b"), Color("80532f"), Color("a2733e"),
	Color("b98045"), Color("dc9d52"), Color("e5ae63"), Color("f2ce89"),
	Color("763d38"), Color("993e38"), Color("b44d43"), Color("d95c50"),
	Color("e77761"), Color("f39a73"), Color("9f8963"), Color("c7ae7d"),
	Color("edd3a0"), Color("ffe6af"), Color("af9f6d"), Color("6d7d4a")
])
@onready var player = $WorldFrame/World/Stage/Player
@onready var camera: Camera3D = $WorldFrame/World/Stage/Camera
@onready var world_frame: SubViewportContainer = $WorldFrame
@onready var world: SubViewport = $WorldFrame/World
var _pixel_material: ShaderMaterial
var _target_labels: Array[Label] = []
var _label_anchors: Array[Node3D] = []

func _ready() -> void:
	if "--slime-raw" in OS.get_cmdline_user_args():
		pixel_look = false
	_pixel_material = ShaderMaterial.new()
	_pixel_material.shader = PIXEL_SHADER
	var colors := PackedVector3Array()
	colors.resize(48)
	for i in range(mini(palette.size(),48)):
		colors[i] = Vector3(palette[i].r,palette[i].g,palette[i].b)
	_pixel_material.set_shader_parameter("palette",colors)
	_pixel_material.set_shader_parameter("palette_size",clampi(palette.size(),1,48))
	_pixel_material.set_shader_parameter("dither_amount",dither_amount)
	# The viewport is shown at an integer number of screen pixels. HUD stays native.
	world_frame.stretch = false
	world_frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
	world_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(_resize_world)
	_resize_world()
	for visual in get_tree().get_nodes_in_group("slime_target_visual"):
		_apply_static_material(visual)
	for target in $WorldFrame/World/Stage/Targets.get_children():
		var anchor: Label3D = target.get_node("Label")
		anchor.hide()
		_label_anchors.append(anchor)
		_target_labels.append($HUD/TargetNames.get_node(NodePath(String(target.name))))
	$HUD/Mode.pressed.connect(_toggle_mode)
	$HUD/Reset.pressed.connect(player.reset_to_slime)
	if "--slime-capture" in OS.get_cmdline_user_args() or "--slime-smoke" in OS.get_cmdline_user_args():
		_capture.call_deferred()

func _resize_world() -> void:
	if world_frame == null or _pixel_material == null:
		return
	var available := Vector2i(maxi(2,int(size.x)),maxi(2,int(size.y)))
	var integer_scale := maxi(1,floori(float(available.y) / float(pixel_rows))) if pixel_look else 1
	var resolution := Vector2i(maxi(2,available.x / integer_scale),maxi(2,available.y / integer_scale))
	world.size = resolution
	world_frame.size = Vector2(resolution)
	world_frame.scale = Vector2.ONE * integer_scale
	world_frame.position = ((Vector2(available) - Vector2(resolution) * integer_scale) * 0.5).floor()
	world_frame.material = _pixel_material if pixel_look else null

func set_pixel_look(enabled: bool) -> void:
	pixel_look = enabled
	_resize_world()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_P:
		set_pixel_look(not pixel_look)
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		camera.handle_camera_input(event)

func _apply_static_material(node: Node) -> void:
	if node is MeshInstance3D:
		for surface in range(node.mesh.get_surface_count()):
			var material := ShaderMaterial.new()
			material.shader = TOON_SHADER
			node.set_surface_override_material(surface, material)
	for child in node.get_children():
		_apply_static_material(child)

func _toggle_mode() -> void:
	player.request_renderer("splats" if player.renderer_mode == "topology" else "topology")

func _process(_delta: float) -> void:
	for i in range(_target_labels.size()):
		var point := _label_anchors[i].global_position
		var screen := camera.unproject_position(point) * world_frame.scale + world_frame.position
		var label := _target_labels[i]
		label.visible = not camera.is_position_behind(point) and screen.y > 110 and screen.y < size.y-100 and screen.x > 65 and screen.x < size.x-65
		label.position = (screen - Vector2(60,13)).round()
	$HUD/Mode.text = "M  /  " + ("TOPOLOGY" if player.renderer_mode == "topology" else "SPLATS")
	$HUD/Mode.disabled = not player.ready_for_input
	$HUD/Reset.disabled = not player.ready_for_input
	var status: String = player.current_form.to_upper()
	if not player.last_error.is_empty():
		status = player.last_error
	elif player.loading:
		status = "Preparing shape…"
	elif player.morphing:
		status = player.source_label + "  →  " + player.desired_form.to_upper()
	$HUD/State.text = status
	$HUD/Progress.visible = player.morphing
	$HUD/Progress.value = player.blend

func _capture() -> void:
	await player.wait_until_settled()
	var mode := "topology"
	var form := "slime"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--slime-mode="): mode = arg.get_slice("=",1)
		if arg.begins_with("--slime-form="): form = arg.get_slice("=",1)
	player.request_renderer(mode)
	player.request_form(form)
	await player.wait_until_settled()
	if not player.last_error.is_empty():
		get_tree().quit(1)
		return
	if "--slime-smoke" in OS.get_cmdline_user_args():
		print("SLIME_SMOKE mode=", player.renderer_mode, " form=", player.current_form, " OK")
		get_tree().quit(0)
		return
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out/slime"))
	var suffix := "" if pixel_look else "-raw"
	var path := "res://out/slime/playground-%s-%s%s.png" % [mode,form,suffix]
	var result := get_viewport().get_texture().get_image().save_png(path)
	print("SLIME_CAPTURE ", path, " result=", result)
	get_tree().quit(result)
