@tool
extends RefCounted
var error := ""
var count := 0
var source := 0
var target := 0
var ids := PackedInt32Array()
var data := PackedByteArray()
func load_file(path: String) -> bool:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return _fail("Cannot open transport map.")
	if file.get_length() < 32 or file.get_length() > 32+50000*4: return _fail("Invalid transport map size.")
	return load_bytes(file.get_buffer(file.get_length()))
func load_bytes(bytes: PackedByteArray) -> bool:
	error = ""
	ids = PackedInt32Array()
	data = PackedByteArray()
	if bytes.size() < 32 or bytes.size() > 32+50000*4: return _fail("Invalid transport map size.")
	if bytes.slice(0,8) != PackedByteArray([71,67,77,65,80,0,0,0]): return _fail("Invalid GCMAP magic.")
	if bytes.decode_u32(8) != 1 or bytes.decode_u32(12) != 32 or bytes.decode_u32(28) != 1: return _fail("Unsupported transport map version or flags.")
	count = bytes.decode_u32(16)
	source = bytes.decode_u32(20)
	target = bytes.decode_u32(24)
	if count < 1 or count > 50000 or source > 127 or target > 127 or source == target or bytes.size() != 32+count*4:
		return _fail("Invalid transport map dimensions.")
	var seen := PackedByteArray()
	seen.resize(count)
	ids.resize(count)
	for i in range(count):
		var value := bytes.decode_u32(32+i*4)
		if value >= count or seen[value] != 0: return _fail("Transport map must be a bijection.")
		seen[value] = 1
		ids[i] = value
	data = bytes
	return true
func _fail(message: String) -> bool:
	error = message
	ids = PackedInt32Array()
	data = PackedByteArray()
	return false
