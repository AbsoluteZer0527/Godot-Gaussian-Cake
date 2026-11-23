extends Node3D
@onready var player = %Player
@onready var slider: HSlider = %Timeline
@onready var status: Label = %Status
@onready var camera_rig: Node3D = %CameraRig
var updating := false

func _ready() -> void:
	if not player.error.is_empty():
		status.text = player.error
		return
	slider.max_value = player.duration
	slider.editable = true
	status.text = "%.2f second clip · Space: play/pause · arrows: orbit · drag slider to scrub" % player.duration
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			_capture(argument.trim_prefix("--capture="))

func _capture(path: String) -> void:
	player.pause()
	player.seek(player.duration * 0.5)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--sample="):
			player.seek(player.duration * argument.trim_prefix("--sample=").to_float())
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit(0 if result == OK else 1)

func _scrub(value: float) -> void:
	if not updating:
		player.pause()
		player.seek(value)

func _process(delta: float) -> void:
	camera_rig.rotate_y((float(Input.is_key_pressed(KEY_RIGHT))-float(Input.is_key_pressed(KEY_LEFT))) * delta)
	updating = true
	slider.value = player.time
	updating = false

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if player.playing:
			player.pause()
		else:
			player.play()
