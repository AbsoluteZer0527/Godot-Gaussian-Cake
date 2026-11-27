@tool
extends "splat_player_3d.gd"
## Reuses the optimized clip renderer and ordering implementation with two live endpoints.
class EndpointCache extends RefCounted:
	var error := ""
	var count := 0
	var duration := 1.0
	var bounds := AABB()
	var times := PackedFloat32Array([0.0,1.0])
	var records: Array[PackedFloat32Array] = []
	var positions: Array[PackedVector3Array] = []
	func interval(_time: float) -> int: return 0
	func frame_image(index: int) -> Image:
		var bytes := records[index].to_byte_array()
		var height := ceili(float(count)/256.0)
		bytes.resize(1792*height*8)
		return Image.create_from_data(1792,height,false,Image.FORMAT_RGF,bytes)

class EndpointClip extends "../resources/splat_clip.gd":
	var endpoint_cache: RefCounted
	func get_decoder() -> RefCounted: return endpoint_cache

func configure(count: int, bounds: AABB, a: PackedFloat32Array, b: PackedFloat32Array, pa: PackedVector3Array, pb: PackedVector3Array) -> void:
	var endpoint_cache := EndpointCache.new()
	endpoint_cache.count = count
	endpoint_cache.bounds = bounds
	endpoint_cache.records = [a,b]
	endpoint_cache.positions = [pa,pb]
	var endpoint_clip := EndpointClip.new()
	endpoint_clip.endpoint_cache = endpoint_cache
	autoplay = false
	clip = endpoint_clip

func set_endpoints(a: PackedFloat32Array, b: PackedFloat32Array, pa: PackedVector3Array, pb: PackedVector3Array) -> void:
	_cache.records[0] = a
	_cache.records[1] = b
	_cache.positions[0] = pa
	_cache.positions[1] = pb
	_frame_a = null
	_frame_b = null
	_loaded_frame = -1
	_last_time = -1.0

func _frame_positions(frame: int) -> PackedVector3Array:
	return _cache.positions[frame]
