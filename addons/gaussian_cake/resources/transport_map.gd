@tool
extends Resource
const Decoder = preload("../runtime/transport_map_decoder.gd")
@export_storage var map_bytes := PackedByteArray():
	set(value):
		map_bytes = value
		_decoder = null
		emit_changed()
var _decoder: RefCounted
func get_decoder() -> RefCounted:
	if _decoder == null:
		_decoder = Decoder.new()
		_decoder.load_bytes(map_bytes)
	return _decoder
