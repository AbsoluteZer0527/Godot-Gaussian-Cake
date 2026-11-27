@tool
extends RefCounted
## Immutable, validated GCFORMS v1 endpoint library. Attributes use linear RGB.
const MAX_BYTES := 512 * 1024 * 1024
var error := ""
var count := 0
var form_count := 0
var duration := 1.5
var bounds := AABB()
var names := PackedStringArray()
var data := PackedByteArray()
var payload := 0
var _records: Array[PackedFloat32Array] = []
var _positions: Array[PackedVector3Array] = []

func load_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _fail("Cannot open form library: " + path)
	if file.get_length() < 64 or file.get_length() > MAX_BYTES: return _fail("Invalid form library size.")
	return load_bytes(file.get_buffer(file.get_length()))

func load_bytes(bytes: PackedByteArray) -> bool:
	error = ""
	data = PackedByteArray()
	names = PackedStringArray()
	_records.clear()
	_positions.clear()
	if bytes.size() < 64 or bytes.size() > MAX_BYTES: return _fail("Invalid form library size.")
	if bytes.slice(0,8) != PackedByteArray([71,67,70,79,82,77,83,0]): return _fail("Invalid GCFORMS magic.")
	if bytes.decode_u32(8) != 1 or bytes.decode_u32(12) != 64 or bytes.decode_u32(28) != 1 or bytes.decode_u32(32) != 56:
		return _fail("Unsupported form library version, flags or record size.")
	count = bytes.decode_u32(16)
	form_count = bytes.decode_u32(20)
	var metadata_bytes := bytes.decode_u32(24)
	duration = bytes.decode_float(36)
	if count < 1 or count > 50000 or form_count < 2 or form_count > 128 or metadata_bytes < 2 or metadata_bytes > 65536 or metadata_bytes % 4 != 0:
		return _fail("Unsupported form library dimensions (maximum 50,000 splats, 128 forms).")
	if not is_finite(duration) or duration < 0.01 or duration > 3600: return _fail("Invalid default morph duration.")
	payload = 64 + metadata_bytes
	if bytes.size() != payload + count * form_count * 56: return _fail("Truncated form library or invalid dimensions.")
	var parser := JSON.new()
	if parser.parse(bytes.slice(64,payload).get_string_from_utf8()) != OK: return _fail("Invalid form library JSON metadata.")
	var metadata: Variant = parser.data
	if not metadata is Dictionary or metadata.get("profile") != "endpoint-v1" or metadata.get("reference") != 0:
		return _fail("Unsupported form library metadata.")
	var name_list: Variant = metadata.get("names")
	if not name_list is Array or name_list.size() != form_count: return _fail("Form names do not match the payload.")
	for value in name_list:
		if not value is String or value.is_empty() or value.to_utf8_buffer().size() > 256 or names.has(value): return _fail("Form names must be nonempty, unique and at most 256 UTF-8 bytes.")
		names.append(value)
	var lower := Vector3(bytes.decode_float(40),bytes.decode_float(44),bytes.decode_float(48))
	var upper := Vector3(bytes.decode_float(52),bytes.decode_float(56),bytes.decode_float(60))
	if not lower.is_finite() or not upper.is_finite() or lower.x > upper.x or lower.y > upper.y or lower.z > upper.z:
		return _fail("Invalid form bounds.")
	bounds = AABB(lower,upper-lower)
	var expanded_bounds := bounds.grow(0.0001)
	for form in range(form_count):
		var start := payload + form * count * 56
		var values := bytes.slice(start,start+count*56).to_float32_array()
		var positions := PackedVector3Array()
		positions.resize(count)
		for value in values:
			if not is_finite(value): return _fail("Non-finite form attribute.")
		for i in range(count):
			var offset := i*14
			positions[i] = Vector3(values[offset],values[offset+1],values[offset+2])
			if not expanded_bounds.has_point(positions[i]): return _fail("Form center lies outside library bounds.")
			var q := Quaternion(values[offset+3],values[offset+4],values[offset+5],values[offset+6])
			if absf(q.length_squared()-1.0) >= 0.001: return _fail("Invalid form quaternion.")
			for axis in range(7,10):
				if absf(values[offset+axis]) > 80.0: return _fail("Unsupported form scale.")
			var radius := 3.0*exp(maxf(values[offset+7],maxf(values[offset+8],values[offset+9])))
			if not expanded_bounds.has_point(positions[i]-Vector3.ONE*radius) or not expanded_bounds.has_point(positions[i]+Vector3.ONE*radius):
				return _fail("Form support lies outside library bounds.")
			for channel in range(10,14):
				if values[offset+channel] < 0.0 or values[offset+channel] > 1.0: return _fail("Invalid form color or opacity.")
		_records.append(values)
		_positions.append(positions)
	data = bytes
	return true

func _fail(message: String) -> bool:
	error = message
	data = PackedByteArray()
	_records.clear()
	_positions.clear()
	return false

func records(form: int) -> PackedFloat32Array:
	return _records[form]

func positions(form: int) -> PackedVector3Array:
	return _positions[form]

static func interpolate_record(a: PackedFloat32Array, b: PackedFloat32Array, t: float, index: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(14)
	var offset := index*14
	for field in range(14): result[field] = lerpf(a[offset+field],b[offset+field],t)
	var qa := Quaternion(a[offset+3],a[offset+4],a[offset+5],a[offset+6]).normalized()
	var qb := Quaternion(b[offset+3],b[offset+4],b[offset+5],b[offset+6]).normalized()
	var q := qa.slerp(qb,t).normalized()
	result[3]=q.x; result[4]=q.y; result[5]=q.z; result[6]=q.w
	return result

static func snapshot(a: PackedFloat32Array, b: PackedFloat32Array, t: float) -> Dictionary:
	var result := PackedFloat32Array()
	result.resize(a.size())
	var points := PackedVector3Array()
	points.resize(a.size()/14)
	for index in range(points.size()):
		var offset := index*14
		for field in range(14): result[offset+field] = lerpf(a[offset+field],b[offset+field],t)
		var qa := Quaternion(a[offset+3],a[offset+4],a[offset+5],a[offset+6]).normalized()
		var qb := Quaternion(b[offset+3],b[offset+4],b[offset+5],b[offset+6]).normalized()
		var q := qa.slerp(qb,t).normalized()
		result[offset+3]=q.x; result[offset+4]=q.y; result[offset+5]=q.z; result[offset+6]=q.w
		points[index] = Vector3(result[offset],result[offset+1],result[offset+2])
	return {"records":result,"positions":points}
