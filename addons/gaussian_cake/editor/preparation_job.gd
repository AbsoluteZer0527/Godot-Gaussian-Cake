@tool
extends Node
## Editor-only, cancellable bridge to the standalone Gaussian Cake authoring CLI.
signal changed
signal prepared(manifest_path: String, source_name: String, target_name: String, cached: bool)
signal failed(message: String)
const Request = preload("preparation_request.gd")
const MAX_LOG_CHARS := 65536
const PIPE_CHUNK := 8192
var busy := false
var status := "Choose source and target models, then Prepare."
var log_text := ""
var last_manifest := ""
var process_id: int:
	get: return int(_process_info.get("pid",0))
var _request: RefCounted
var _worker: Thread
var _process_info := {}
var _stdout_pending := PackedByteArray()
var _stderr_pending := PackedByteArray()
var _cancel_requested := false
var _shutting_down := false

func start(settings: Dictionary) -> bool:
	if busy or _shutting_down or not is_inside_tree(): return false
	log_text = ""
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var normalized := Request.normalize(settings,project_root)
	if normalized.has("error"):
		_fail(normalized.error)
		return false
	_request = Request.new()
	_request.settings = normalized.settings
	_request.cache_root = project_root.path_join(".godot/gaussian_cake/preparation")
	_request.generated_root = project_root.path_join("gaussian_cake_generated")
	_cancel_requested = false
	_stdout_pending = PackedByteArray()
	_stderr_pending = PackedByteArray()
	busy = true
	status = "Checking model files and prepared cache…"
	changed.emit()
	return _start_worker("inspect")

func cancel() -> void:
	if not busy: return
	_cancel_requested = true
	if _request != null: _request.cancel()
	if not _process_info.is_empty():
		_stop_process()
	if _worker != null and _worker.is_alive():
		status = "Cancelling preparation…"
		changed.emit()
	else:
		_finish_cancelled()

func shutdown() -> void:
	if _shutting_down: return
	_shutting_down = true
	cancel()
	# Hashing checks cancellation every 1 MiB. Validation is bounded by the
	# addon's 50k-splat input limit; no external process is waited on here.
	if _worker != null and _worker.is_started():
		_worker.wait_to_finish()
		_worker = null
	_stop_process()
	busy = false
	set_process(false)

func _exit_tree() -> void:
	shutdown()

func _start_worker(phase: String) -> bool:
	_worker = Thread.new()
	var work: Callable = _request.inspect if phase == "inspect" else _request.validate_and_publish
	if _worker.start(work) != OK:
		_worker = null
		_fail("Cannot start preparation worker.")
		return false
	return true

func _process(_delta: float) -> void:
	if not busy or _shutting_down: return
	if _worker != null:
		if _worker.is_alive(): return
		var result: Dictionary = _worker.wait_to_finish()
		_worker = null
		if _cancel_requested or result.get("cancelled",false):
			_finish_cancelled()
		elif result.has("error"):
			_fail(result.error)
		elif result.has("manifest"):
			_complete(result.manifest,result.get("cached",false))
		else:
			_launch(result.project,result.output)
		return
	if _process_info.is_empty(): return
	_read_pipes(false)
	var pid: int = _process_info.pid
	if OS.is_process_running(pid): return
	var exit_code := OS.get_process_exit_code(pid)
	_read_pipes(true)
	_close_pipes()
	_process_info = {}
	if exit_code != 0:
		if log_text.contains("view-dependent SH") and log_text.contains("dc_only"):
			_fail("Enable Use base color only under Preparation settings to discard view-dependent color, then Prepare again.")
		elif log_text.contains("Form sources do not share the same splat count"):
			_fail("The sources produced different usable splat counts. Lower Splat count to fit the smaller capture, then Prepare again. See the log for cleaned counts.")
		else:
			_fail("Preparation failed (CLI exit %d). See the log below." % exit_code)
		return
	status = "Validating and importing prepared forms…"
	changed.emit()
	_start_worker("publish")

func _launch(project: String, output: String) -> void:
	if _cancel_requested:
		_finish_cancelled()
		return
	# Argument arrays and JSON paths preserve spaces, Unicode and shell characters.
	# No command interpreter is involved and the CLI window stays hidden.
	_process_info = OS.execute_with_pipe(_request.settings.cli_path,
		PackedStringArray(["forms",project,"--output",output]),false)
	if _process_info.is_empty():
		_fail("Cannot launch Gaussian Cake CLI. Choose the gc_cli executable built by the authoring tool.")
		return
	status = "Preparing splat correspondence…"
	changed.emit()

func _read_pipes(final_read: bool) -> void:
	var received := false
	for field in ["stdio","stderr"]:
		var pipe: FileAccess = _process_info.get(field)
		if pipe == null: continue
		var data := PackedByteArray()
		# Limit each frame's work even if a helper writes a large amount of output.
		for _chunk in range(32 if final_read else 4):
			var part := pipe.get_buffer(PIPE_CHUNK)
			if part.is_empty(): break
			data.append_array(part)
			if part.size() < PIPE_CHUNK: break
		if not data.is_empty(): received = true
		var pending := _stdout_pending if field == "stdio" else _stderr_pending
		pending.append_array(data)
		var end := pending.size() if final_read else pending.rfind(10)+1
		if end > 0:
			_append_log(pending.slice(0,end).get_string_from_utf8())
			pending = pending.slice(end)
		# Bound pending partial lines from malformed helpers as well as visible logs.
		if pending.size() > MAX_LOG_CHARS:
			_append_log("[Long log line truncated]\n")
			pending = PackedByteArray()
		if field == "stdio": _stdout_pending = pending
		else: _stderr_pending = pending
	if received: changed.emit()

func _append_log(value: String) -> void:
	log_text += value
	if log_text.length() > MAX_LOG_CHARS:
		log_text = log_text.right(MAX_LOG_CHARS)

func _close_pipes() -> void:
	for field in ["stdio","stderr"]:
		var pipe: FileAccess = _process_info.get(field)
		if pipe != null: pipe.close()

func _stop_process() -> void:
	if _process_info.is_empty(): return
	var pid: int = _process_info.pid
	if OS.is_process_running(pid): OS.kill(pid)
	_close_pipes()
	_process_info = {}

func _complete(manifest: String, cached: bool) -> void:
	busy = false
	last_manifest = manifest
	status = "Prepared forms loaded from cache." if cached else "Models prepared. Loading preview…"
	changed.emit()
	prepared.emit(manifest,_request.settings.source_name,_request.settings.target_name,cached)

func _fail(message: String) -> void:
	busy = false
	status = message
	changed.emit()
	failed.emit(message)

func _finish_cancelled() -> void:
	# A cancellation can arrive after the worker returned but before _process
	# reaped it. Join that finished thread before allowing a subsequent request.
	if _worker != null and _worker.is_started() and not _worker.is_alive():
		_worker.wait_to_finish()
		_worker = null
	busy = false
	status = "Preparation cancelled."
	changed.emit()
