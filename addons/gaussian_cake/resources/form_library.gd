@tool
class_name GaussianCakeFormLibrary
extends Resource
const Decoder = preload("../runtime/form_decoder.gd")
var _decoder_mutex := Mutex.new()
@export_storage var library_bytes := PackedByteArray():
	set(value):
		_decoder_mutex.lock()
		library_bytes = value
		_decoder = null
		_decoder_mutex.unlock()
		emit_changed()
var _decoder: RefCounted

func get_decoder() -> RefCounted:
	_decoder_mutex.lock()
	if _decoder == null:
		# Publish only the fully validated decoder. Several player workers may share
		# this ResourceLoader resource and request it concurrently.
		var candidate := Decoder.new()
		candidate.load_bytes(library_bytes)
		_decoder = candidate
	var result := _decoder
	_decoder_mutex.unlock()
	return result
