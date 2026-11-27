@tool
extends "playback_3d.gd"
const Clip = preload("../resources/splat_clip.gd")
const SPLAT_SHADER = preload("../shaders/splat.gdshader")
const MAX_SPLATS := 50000

@export_group("Splat Asset")
@export var clip: Clip:
	set(value):
		if clip != null and clip.changed.is_connected(_queue_rebuild):
			clip.changed.disconnect(_queue_rebuild)
		clip = value
		if clip != null:
			clip.changed.connect(_queue_rebuild)
		_queue_rebuild()
## Optional override for runtime viewports. Leave empty for the viewport's active camera.
@export var camera: Camera3D

var _preview_camera: Camera3D
var _cache: RefCounted
var _renderer: MultiMeshInstance3D
var _material: ShaderMaterial
var _frame_a: ImageTexture
var _frame_b: ImageTexture
var _loaded_frame := -1
var _order: Array[int] = []
var _depths := PackedFloat32Array()
var _instance_buffer := PackedFloat32Array()
var _sort_keys := PackedInt64Array()
var _order_pixels := PackedFloat32Array()
var _order_texture: ImageTexture
var _positions_a := PackedVector3Array()
var _positions_b := PackedVector3Array()
var _last_depth_direction := Vector3(INF, INF, INF)
var _last_transform := Transform3D()
var _last_time := -1.0
var _last_near := -1.0
## Diagnostics measure CPU work, not GPU frame time.
var last_sort_usec := 0
var sort_count := 0

func _enter_tree() -> void:
	super._enter_tree()
	if Engine.is_editor_hint():
		add_to_group("gaussian_cake_editor_splats")

func set_preview_camera(value: Camera3D) -> void:
	_preview_camera = value

func _rebuild() -> void:
	super._rebuild()
	if not is_inside_tree():
		return
	if is_instance_valid(_renderer):
		if _renderer.get_parent() == self:
			remove_child(_renderer)
			_renderer.queue_free()
	_renderer = null
	_cache = null
	_material = null
	_frame_a = null
	_frame_b = null
	_order_texture = null
	_positions_a = PackedVector3Array()
	_positions_b = PackedVector3Array()
	_last_depth_direction = Vector3(INF, INF, INF)
	_last_near = -1.0
	last_sort_usec = 0
	sort_count = 0
	_loaded_frame = -1
	_last_time = -1.0
	_order.clear()
	_depths = PackedFloat32Array()
	_instance_buffer = PackedFloat32Array()
	if clip == null:
		_fail("Assign an imported .gcsplat resource to Clip.")
		return
	_cache = clip.get_decoder()
	if not _cache.error.is_empty():
		_fail(_cache.error)
		return
	if _cache.count > MAX_SPLATS:
		_fail("This player supports up to 50,000 splats. Re-export with a lower count; start with 5,000.")
		return
	_renderer = MultiMeshInstance3D.new()
	_renderer.name = "GaussianSplats"
	_renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_renderer)
	_material = ShaderMaterial.new()
	_material.shader = SPLAT_SHADER
	_renderer.material_override = _material
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	instances.mesh = quad
	instances.instance_count = _cache.count
	instances.custom_aabb = _cache.bounds.grow(0.05)
	_renderer.multimesh = instances
	_order.resize(_cache.count)
	_depths.resize(_cache.count)
	_sort_keys.resize(_cache.count)
	_order_pixels.resize(256 * ceili(float(_cache.count) / 256.0))
	_instance_buffer.resize(_cache.count * 16)
	for i in range(_cache.count):
		_order[i] = i
		_instance_buffer[i*16] = 1.0
		_instance_buffer[i*16+5] = 1.0
		_instance_buffer[i*16+10] = 1.0
		# Instance IDs stay fixed. Only the small slot->splat lookup changes when sorted.
		_instance_buffer[i*16+12] = float(i % 256)
		_instance_buffer[i*16+13] = float(i / 256)
	instances.buffer = _instance_buffer
	_initialize_playback(_cache.duration)

func _frame_positions(frame: int) -> PackedVector3Array:
	var start: int = _cache.payload + frame * _cache.count * 56
	var values: PackedFloat32Array = _cache.data.slice(start, start + _cache.count * 56).to_float32_array()
	var result := PackedVector3Array()
	result.resize(_cache.count)
	for i in range(_cache.count):
		var offset := i * 14
		result[i] = Vector3(values[offset], values[offset+1], values[offset+2])
	return result

func _render_frame() -> void:
	if _cache == null or not is_instance_valid(_renderer) or not error.is_empty():
		return
	var view_camera: Camera3D
	if Engine.is_editor_hint():
		view_camera = _preview_camera if is_instance_valid(_preview_camera) else null
	elif is_instance_valid(camera):
		view_camera = camera
	else:
		view_camera = get_viewport().get_camera_3d()
	if not is_instance_valid(view_camera):
		_renderer.visible = false
		return
	_renderer.visible = true
	var model_view := view_camera.global_transform.affine_inverse() * global_transform
	# All points receive the same depth offset under pure translation. Neither
	# translation, camera FOV nor camera roll around its viewing axis changes order.
	var depth_direction := Vector3(model_view.basis.x.z, model_view.basis.y.z, model_view.basis.z.z)
	_last_transform = model_view
	if _last_near != view_camera.near:
		_last_near = view_camera.near
		_material.set_shader_parameter("camera_near", view_camera.near)
	if _last_time == time and _last_depth_direction == depth_direction:
		last_sort_usec = 0
		return
	var sort_start := Time.get_ticks_usec()
	_last_time = time
	_last_depth_direction = depth_direction
	var a: int = _cache.interval(time)
	if _loaded_frame != a:
		if _frame_a == null:
			_frame_a = ImageTexture.create_from_image(_cache.frame_image(a))
			_frame_b = ImageTexture.create_from_image(_cache.frame_image(a+1))
			_positions_a = _frame_positions(a)
			_positions_b = _frame_positions(a+1)
		elif a == _loaded_frame + 1:
			var previous_a := _frame_a
			_frame_a = _frame_b
			_frame_b = previous_a
			_frame_b.update(_cache.frame_image(a+1))
			_positions_a = _positions_b
			_positions_b = _frame_positions(a+1)
		elif a == _loaded_frame - 1:
			var previous_b := _frame_b
			_frame_b = _frame_a
			_frame_a = previous_b
			_frame_a.update(_cache.frame_image(a))
			_positions_b = _positions_a
			_positions_a = _frame_positions(a)
		else:
			_frame_a.update(_cache.frame_image(a))
			_frame_b.update(_cache.frame_image(a+1))
			_positions_a = _frame_positions(a)
			_positions_b = _frame_positions(a+1)
		_material.set_shader_parameter("frame_a", _frame_a)
		_material.set_shader_parameter("frame_b", _frame_b)
		_loaded_frame = a
	var blend: float = clampf((time-_cache.times[a]) / (_cache.times[a+1]-_cache.times[a]), 0.0, 1.0)
	_material.set_shader_parameter("frame_blend", blend)
	for i in range(_cache.count):
		_depths[i] = depth_direction.dot(_positions_a[i].lerp(_positions_b[i], blend))
	# Native integer sort avoids hundreds of thousands of interpreted comparator
	# calls. Monotonic IEEE float32 bits preserve the previous float32 depth order;
	# the low 16 bits provide the same deterministic ID tie break (max 50,000).
	var depth_bytes := _depths.to_byte_array()
	for i in range(_cache.count):
		var bits := depth_bytes.decode_u32(i * 4)
		if bits == 0x80000000: bits = 0 # -0 and +0 are equal depths.
		var ordered := (~bits & 0xffffffff) if (bits & 0x80000000) else (bits ^ 0x80000000)
		_sort_keys[i] = (ordered << 16) | i
	_sort_keys.sort()
	for slot in range(_cache.count):
		var id := int(_sort_keys[slot] & 0xffff)
		_order[slot] = id
		_order_pixels[slot] = float(id)
	var order_image := Image.create_from_data(256, _order_pixels.size() / 256, false, Image.FORMAT_RF, _order_pixels.to_byte_array())
	if _order_texture == null:
		_order_texture = ImageTexture.create_from_image(order_image)
		_material.set_shader_parameter("splat_order", _order_texture)
	else:
		_order_texture.update(order_image)
	last_sort_usec = Time.get_ticks_usec() - sort_start
	sort_count += 1
