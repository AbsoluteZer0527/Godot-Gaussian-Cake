extends Control
## Three complex endpoints; the entire gallery/HUD is editable in showcase.tscn.
const LABELS := ["Cactus capture", "Lighthouse island", "Coral reef"]
const NAMES := ["cactus", "island", "reef"]
const Automation = preload("showcase_automation.gd")
const PIXEL_SHADER = preload("pixel_palette.gdshader")
@onready var forms = $WorldFrame/World/Stage/Forms
@onready var camera: Camera3D = $WorldFrame/World/Stage/Camera
@onready var frame: SubViewportContainer = $WorldFrame
@onready var source: OptionButton = %Source
@onready var destination: OptionButton = %Destination
@onready var mode: OptionButton = %Mapping
@onready var scrub: HSlider = %Progress
@onready var timing: HSlider = %Duration
var pixel := true
var yaw := 0.55
var pitch := 0.40
var distance := 3.2
var _dragging := false
var _busy := false
var _idle := 0.0
var _palette_material: ShaderMaterial
var _hud_clock := 0.0
var _warm_time := 0
var _palette_size := 72

func _ready() -> void:
	for label in LABELS:
		source.add_item(label)
		destination.add_item(label)
	destination.select(1)
	mode.add_item("Refined pair map")
	mode.add_item("Shared reference")
	forms.camera = camera
	forms.paused = true
	forms.transport_mode = "refined"
	%Begin.pressed.connect(_begin)
	%Pause.pressed.connect(_pause)
	%Pixel.toggled.connect(_set_pixel)
	mode.item_selected.connect(_mapping_changed)
	source.item_selected.connect(_selection_changed)
	destination.item_selected.connect(_selection_changed)
	scrub.value_changed.connect(_scrubbed)
	timing.value_changed.connect(func(value: float): %DurationText.text = "%.1f s" % value)
	frame.gui_input.connect(_world_input)
	frame.resized.connect(_resize_world)
	_palette_material = ShaderMaterial.new()
	_palette_material.shader = PIXEL_SHADER
	var colors: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://examples/transitions/palette.json"))
	var palette := PackedVector3Array()
	for rgb in colors: palette.append(Vector3(rgb[0],rgb[1],rgb[2]))
	_palette_size = palette.size()
	_palette_material.set_shader_parameter("palette_size",palette.size())
	palette.resize(80)
	_palette_material.set_shader_parameter("palette",palette)
	_set_pixel(true)
	_update_camera()
	await forms.wait_until_ready()
	if not forms.error.is_empty():
		%Status.text = forms.error
		return
	_warm_time = Time.get_ticks_msec()
	%Count.text = "%s GAUSSIANS / ENDPOINT" % _commas(forms.splat_count)
	_update_metrics()
	if Automation.requested():
		var automation = Automation.new(self)
		await automation.run()

func _commas(number: int) -> String:
	return str(number / 1000) + "," + ("%03d" % (number % 1000)) if number >= 1000 else str(number)

func _begin() -> void:
	if _busy or not forms.initialized: return
	_busy = true
	%Begin.disabled = true
	while forms.loading: await get_tree().process_frame
	forms.paused = true
	forms.snap_to_form(NAMES[source.selected])
	forms.transport_mode = "refined" if mode.selected == 0 else "shared"
	forms.morph_to(NAMES[destination.selected],timing.value)
	while forms.loading: await get_tree().process_frame
	forms.paused = false
	%Pause.text = "Pause"
	_update_metrics()
	_busy = false
	%Begin.disabled = false
	_idle = 0.0

func _pause() -> void:
	if not forms.initialized or _busy: return
	if forms.progress >= 1.0:
		_begin()
		return
	forms.paused = not forms.paused
	if not forms.paused: forms.resume()
	%Pause.text = "Play" if forms.paused else "Pause"

func _selection_changed(_index: int) -> void:
	if source.selected == destination.selected: destination.select((source.selected+1)%NAMES.size())
	_update_metrics()

func _mapping_changed(_index: int) -> void:
	# Comparing restarts the selected pair from identical canonical source poses.
	# Applying a different map to a live interpolated pose is not a fair A/B.
	if not forms.initialized or _busy: return
	var held: float = forms.progress
	var was_paused: bool = forms.paused
	await _begin()
	forms.seek(held)
	forms.paused = was_paused
	%Pause.text = "Play" if forms.paused else "Pause"

func _scrubbed(value: float) -> void:
	if not forms.initialized or _busy: return
	forms.paused = true
	forms.seek(value)
	%Pause.text = "Play"

func _set_pixel(value: bool) -> void:
	pixel = value
	frame.material = _palette_material if pixel else null
	_resize_world()
	%Look.text = ("PIXEL / %d COLORS" % _palette_size) if pixel else "RAW / SOURCE COLORS"

func _resize_world() -> void:
	frame.stretch_shrink = 2 if pixel else 1
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel else CanvasItem.TEXTURE_FILTER_LINEAR

func _world_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(1.7,distance*0.9)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(7.0,distance*1.1)
		_update_camera()
	if event is InputEventMouseMotion and _dragging:
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch+event.relative.y*0.006,-0.5,1.2)
		_update_camera()

func _update_camera() -> void:
	var focus := Vector3(0,-0.15,0)
	camera.position = focus+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	camera.look_at(focus)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P: %Pixel.button_pressed = not pixel
		if event.keycode == KEY_B:
			mode.select(1-mode.selected)
			_mapping_changed(mode.selected)
		if event.keycode == KEY_SPACE: _pause()
	if event is InputEventMouseButton and not event.pressed: _dragging = false

func _process(delta: float) -> void:
	if not is_instance_valid(forms) or not forms.initialized: return
	scrub.set_value_no_signal(forms.progress)
	%ProgressText.text = "%03d%%" % roundi(forms.progress*100.0)
	_hud_clock += delta
	if _hud_clock > 0.25:
		_hud_clock = 0.0
		%Performance.text = ("%d FPS" % Engine.get_frames_per_second()) if Time.get_ticks_msec()-_warm_time > 2000 else "Warming renderer"
		%Status.text = "Preparing endpoint order…" if forms.loading else ("%s  →  %s" % [LABELS[source.selected],LABELS[destination.selected]])
	if %Auto.button_pressed and not _busy and forms.progress >= 1.0 and not forms.loading:
		_idle += delta
		if _idle > 1.2:
			source.select(destination.selected)
			destination.select((destination.selected+1)%NAMES.size())
			# Continue from the current slot order; do not reset identities between forms.
			forms.transport_mode = "refined" if mode.selected == 0 else "shared"
			forms.paused = false
			forms.morph_to(NAMES[destination.selected],timing.value)
			%Pause.text = "Pause"
			_update_metrics()
			_idle = 0.0

func _update_metrics() -> void:
	if not forms.initialized: return
	var metrics: Dictionary = forms.get_transport_metrics(
		NAMES[source.selected], NAMES[destination.selected]
	)
	%MappingLabel.text = "PAIR REFINEMENT" if mode.selected == 0 else "SHARED REFERENCE"
	if source.selected == destination.selected: %MappingLabel.text = "REST ENDPOINT"
	if metrics.is_empty():
		%Metrics.text = "Shared-reference correspondence · no pair map"
		return
	var before: Dictionary = metrics.get("before",{})
	var after: Dictionary = metrics.get("after",{})
	var old: float = before.get("objective",0.0)
	var new: float = after.get("objective",0.0)
	var reduction := 100.0*(1.0-new/old) if old > 0.0 else 0.0
	%Metrics.text = "Pair cost  %.4f → %.4f  /  %.1f%% lower\nTravel RMS  %.3f → %.3f   ·   P95  %.3f → %.3f" % [old,new,reduction,before.get("rms_distance",0.0),after.get("rms_distance",0.0),before.get("p95_distance",0.0),after.get("p95_distance",0.0)]
