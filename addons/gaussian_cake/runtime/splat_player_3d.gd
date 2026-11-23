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
var _last_transform := Transform3D()
var _last_time := -1.0
var _last_near := -1.0

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
	_instance_buffer.resize(_cache.count * 16)
	for i in range(_cache.count):
		_order[i] = i
		_instance_buffer[i*16] = 1.0
		_instance_buffer[i*16+5] = 1.0
		_instance_buffer[i*16+10] = 1.0
	_initialize_playback(_cache.duration)

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
	if _last_time == time and _last_transform == model_view and _last_near == view_camera.near:
		return
	_last_time = time
	_last_transform = model_view
	_last_near = view_camera.near
	var a: int = _cache.interval(time)
	if _loaded_frame != a:
		if _frame_a == null:
			_frame_a = ImageTexture.create_from_image(_cache.frame_image(a))
			_frame_b = ImageTexture.create_from_image(_cache.frame_image(a+1))
		else:
			_frame_a.update(_cache.frame_image(a))
			_frame_b.update(_cache.frame_image(a+1))
		_material.set_shader_parameter("frame_a", _frame_a)
		_material.set_shader_parameter("frame_b", _frame_b)
		_loaded_frame = a
	var blend: float = clampf((time-_cache.times[a]) / (_cache.times[a+1]-_cache.times[a]), 0.0, 1.0)
	_material.set_shader_parameter("frame_blend", blend)
	_material.set_shader_parameter("camera_near", view_camera.near)
	for i in range(_cache.count):
		var position: Vector3 = _cache.position_at(a, i).lerp(_cache.position_at(a+1, i), blend)
		_depths[i] = (model_view * position).z
	_order.sort_custom(func(left: int, right: int) -> bool:
		return _depths[left] < _depths[right] if _depths[left] != _depths[right] else left < right)
	for slot in range(_cache.count):
		# Exact in Compatibility's half-float custom data, even above ID 2048.
		_instance_buffer[slot*16+12] = float(_order[slot] % 256)
		_instance_buffer[slot*16+13] = float(_order[slot] / 256)
	_renderer.multimesh.buffer = _instance_buffer
