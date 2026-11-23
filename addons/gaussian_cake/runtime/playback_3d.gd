@tool
extends Node3D
## Shared clock. Imported assets remain immutable; each node owns its time.

signal playback_finished
signal playback_error(message: String)
enum LoopMode { ONCE, LOOP, PING_PONG }

@export_group("Playback")
@export var autoplay := true
@export var loop_mode: LoopMode = LoopMode.PING_PONG:
	set(value):
		loop_mode = value
		_phase = _time
@export_range(0.0, 8.0, 0.05) var speed := 1.0:
	set(value):
		speed = maxf(value, 0.0) if is_finite(value) else 1.0
@export_group("Editor Preview")
@export_range(0.0, 1.0, 0.001) var preview_progress := 0.0:
	set(value):
		preview_progress = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
		if Engine.is_editor_hint() and is_inside_tree():
			seek(preview_progress * _duration)

var duration: float:
	get: return _duration
var time: float:
	get: return _time
var progress: float:
	get: return _time / _duration if _duration > 0.0 else 0.0
var playing := false
var error := ""
var _duration := 0.0
var _time := 0.0
var _phase := 0.0
var _rebuild_pending := false

func _ready() -> void:
	_rebuild()

func _enter_tree() -> void:
	if is_node_ready():
		_queue_rebuild()

func _queue_rebuild() -> void:
	if is_inside_tree() and not _rebuild_pending:
		_rebuild_pending = true
		_rebuild.call_deferred()

func _rebuild() -> void:
	_rebuild_pending = false

func _initialize_playback(length: float) -> void:
	_duration = length
	error = ""
	playing = autoplay and not Engine.is_editor_hint()
	seek(preview_progress * length if Engine.is_editor_hint() else 0.0)
	update_configuration_warnings()

func _fail(message: String) -> void:
	error = message
	_duration = 0.0
	_time = 0.0
	_phase = 0.0
	playing = false
	update_configuration_warnings()
	playback_error.emit(message)

func _get_configuration_warnings() -> PackedStringArray:
	return PackedStringArray([error]) if not error.is_empty() else PackedStringArray()

func play() -> void:
	if _duration <= 0.0 or not error.is_empty() or Engine.is_editor_hint():
		return
	if loop_mode == LoopMode.ONCE and _time >= _duration:
		seek(0.0)
	playing = true

func pause() -> void:
	playing = false

func stop() -> void:
	playing = false
	seek(0.0)

func seek(seconds: float) -> void:
	if not is_finite(seconds):
		return
	_time = clampf(seconds, 0.0, _duration)
	_phase = _time
	_render_frame()

func _process(delta: float) -> void:
	if not error.is_empty() or _duration <= 0.0:
		return
	if not Engine.is_editor_hint():
		_advance(delta)
	_render_frame()

func _advance(delta: float) -> void:
	if not playing or not is_finite(delta) or delta <= 0.0:
		return
	_phase += delta * speed
	match loop_mode:
		LoopMode.ONCE:
			_time = minf(_phase, _duration)
			if _phase >= _duration:
				playing = false
				_render_frame() # Apply the endpoint before notifying game code.
				playback_finished.emit()
		LoopMode.LOOP:
			_phase = fposmod(_phase, _duration)
			_time = _phase
		LoopMode.PING_PONG:
			_phase = fposmod(_phase, 2.0 * _duration)
			_time = pingpong(_phase, _duration)

func _render_frame() -> void:
	pass

