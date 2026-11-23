@tool
extends RefCounted
## Minimal, standalone reader for the documented GCSPLAT v1 contract.
## Validates GCSPLAT v1 before import or runtime allocation.

const MAX_BYTES := 512 * 1024 * 1024
const TEXTURE_WIDTH := 1792 # 256 splats * 7 RG32F texels; no record crosses a row.
var error := ""
var count := 0
var frames := 0
var fps := 0
var duration := 0.0
var bounds := AABB()
var times := PackedFloat32Array()
var data := PackedByteArray()
var payload := 0

func load_file(path: String) -> bool:
	error = ""
	data = PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Cannot open %s. Export a Splats project to this file first." % path)
	if file.get_length() < 64 or file.get_length() > MAX_BYTES:
		return _fail("Invalid cache size (limit: 512 MiB).")
	return load_bytes(file.get_buffer(file.get_length()))

func load_bytes(bytes: PackedByteArray) -> bool:
	error = ""
	data = PackedByteArray()
	if bytes.size() < 64 or bytes.size() > MAX_BYTES:
		return _fail("Invalid cache size.")
	if bytes.slice(0, 8) != PackedByteArray([71, 67, 83, 80, 76, 65, 84, 0]):
		return _fail("Invalid GCSPLAT magic.")
	if bytes.decode_u32(8) != 1 or bytes.decode_u32(12) != 64 or bytes.decode_u32(28) != 1 or bytes.decode_u32(36) != 56:
		return _fail("Unsupported cache version, header, color flags or stride.")
	count = bytes.decode_u32(16)
	frames = bytes.decode_u32(20)
	fps = bytes.decode_u32(24)
	duration = bytes.decode_float(32)
	if count < 1 or count > 500000 or frames < 2 or fps < 1 or fps > 120 or not is_finite(duration) or duration < 0.01 or duration > 3600:
		return _fail("Invalid animation dimensions.")
	payload = 64 + 4 * frames
	if bytes.size() != payload + 56 * count * frames:
		return _fail("Truncated cache or incorrect frame count.")
	var lower := Vector3(bytes.decode_float(40), bytes.decode_float(44), bytes.decode_float(48))
	var upper := Vector3(bytes.decode_float(52), bytes.decode_float(56), bytes.decode_float(60))
	if not lower.is_finite() or not upper.is_finite() or lower.x > upper.x or lower.y > upper.y or lower.z > upper.z:
		return _fail("Invalid animation bounds.")
	bounds = AABB(lower, upper - lower)
	times = bytes.slice(64, payload).to_float32_array()
	if times[0] != 0.0 or absf(times[-1] - duration) > 0.00001:
		return _fail("Animation endpoints are missing.")
	for i in range(times.size()):
		if not is_finite(times[i]) or (i > 0 and times[i] <= times[i - 1]):
			return _fail("Invalid frame timestamps.")
	# Validate before allocating GPU resources or using values in the sort comparator.
	var values := bytes.slice(payload).to_float32_array()
	for value in values:
		if not is_finite(value):
			return _fail("Non-finite splat attribute.")
	for i in range(0, values.size(), 14):
		var q := Quaternion(values[i+3], values[i+4], values[i+5], values[i+6])
		if absf(q.length_squared() - 1.0) > 0.01:
			return _fail("Invalid splat quaternion.")
		for axis in range(7, 10):
			if absf(values[i+axis]) > 80.0:
				return _fail("Splat scale exceeds the supported range.")
		for channel in range(10, 14):
			if values[i+channel] < 0.0 or values[i+channel] > 1.0:
				return _fail("Invalid splat color or opacity.")
	data = bytes
	return true

func _fail(message: String) -> bool:
	error = message
	data = PackedByteArray()
	return false

func frame_image(index: int) -> Image:
	var start := payload + clampi(index, 0, frames - 1) * count * 56
	var pixels := data.slice(start, start + count * 56)
	var height := ceili(float(count) / 256.0)
	pixels.resize(TEXTURE_WIDTH * height * 8)
	return Image.create_from_data(TEXTURE_WIDTH, height, false, Image.FORMAT_RGF, pixels)

func position_at(frame: int, index: int) -> Vector3:
	var offset := payload + (frame * count + index) * 56
	return Vector3(data.decode_float(offset), data.decode_float(offset+4), data.decode_float(offset+8))

func interval(time: float) -> int:
	var lo := 0
	var hi := frames - 1
	while lo + 1 < hi:
		var mid := (lo + hi) / 2
		if times[mid] <= time:
			lo = mid
		else:
			hi = mid
	return mini(lo, frames - 2)

