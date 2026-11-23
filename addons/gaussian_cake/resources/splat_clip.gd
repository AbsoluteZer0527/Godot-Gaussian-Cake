@tool
class_name GaussianCakeSplatClip
extends Resource
## Immutable source bytes are shared. GPU textures and clocks belong to each player.
const Decoder = preload("../runtime/splat_decoder.gd")

@export_storage var cache_bytes := PackedByteArray():
	set(value):
		cache_bytes = value
		_decoder = null
		emit_changed()

var _decoder: RefCounted

func get_decoder() -> RefCounted:
	if _decoder == null:
		_decoder = Decoder.new()
		_decoder.load_bytes(cache_bytes)
	return _decoder

func get_duration() -> float:
	return get_decoder().duration if get_decoder().error.is_empty() else 0.0

func get_splat_count() -> int:
	return get_decoder().count if get_decoder().error.is_empty() else 0

