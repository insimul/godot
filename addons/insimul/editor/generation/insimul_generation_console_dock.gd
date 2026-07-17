@tool
class_name InsimulGenerationConsoleDock
extends Control
## Generation Console dock — UI (US-GE2).
##
## The @tool Control the EditorPlugin docks into the editor. A THIN view over the
## logic layer: InsimulJobReducer owns the job lifecycle state machine and
## InsimulJobPoller owns the polling-fallback timer/request with a clean teardown;
## this file wires Godot Controls (button, ProgressBar, log) to those calls and
## dispatches operations through InsimulEditorSession. Per the "logic layer tested;
## UI structurally checked" split, the reducer + poller are exercised headless
## (generation_test.gd) and this file is covered by the structural lint + the human
## end-to-end pass (VERIFICATION.md).
##
## Editor-restart safety: the poller is disposed in _exit_tree, so leaving the
## editor (or reloading the dock) never orphans a timer or an in-flight request.

var session: InsimulEditorSession
var world_id: String = ""
var generator: String = "world"

var _job: Dictionary = {}
var _poller: InsimulJobPoller = null

var _start_btn: Button
var _sync_btn: Button
var _bar: ProgressBar
var _log: RichTextLabel

## Active poll timers, keyed by handle (this dock is its own poller Scheduler).
var _timers: Dictionary = {}
var _next_handle: int = 1


func _init(editor_session: InsimulEditorSession = null) -> void:
	session = editor_session
	name = "Insimul Generation"


func _ready() -> void:
	_build_ui()


func _exit_tree() -> void:
	# Tear down the poller so no timer/request survives the dock.
	if _poller != null:
		_poller.dispose()
		_poller = null
	for handle in _timers.keys():
		var t = _timers[handle]
		if is_instance_valid(t):
			t.queue_free()
	_timers.clear()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var toolbar := HBoxContainer.new()
	root.add_child(toolbar)

	_start_btn = Button.new()
	_start_btn.text = "Run Generator"
	_start_btn.pressed.connect(start_job)
	toolbar.add_child(_start_btn)

	_sync_btn = Button.new()
	_sync_btn.text = "Sync Now"
	_sync_btn.disabled = true
	_sync_btn.pressed.connect(sync_now)
	toolbar.add_child(_sync_btn)

	_bar = ProgressBar.new()
	_bar.min_value = 0
	_bar.max_value = 100
	root.add_child(_bar)

	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_log)


## Start a generation job, then begin polling it (the SSE-fallback path).
func start_job() -> void:
	if session == null or world_id == "":
		return
	var body := JSON.stringify({"worldId": world_id, "generator": generator})
	session.call_operation("startGenerationJob", body, func(res: Dictionary):
		var job := InsimulJobReducer.parse_job(String(res.get("body", "")))
		if job.is_empty():
			_append_log("start failed")
			return
		_job = job
		_render()
		_begin_polling(String(job.get("job_id", "")))
	)


func _begin_polling(job_id: String) -> void:
	# One poll = one getGenerationJob request; the reducer folds the response.
	var fetch := func(on_done: Callable):
		var ref := JSON.stringify({"jobId": job_id})
		session.call_operation("getGenerationJob", ref, func(res: Dictionary):
			on_done.call(InsimulJobReducer.parse_job(String(res.get("body", ""))))
		)
	_poller = InsimulJobPoller.new(fetch, _on_job_update, self)
	_poller.start()


func _on_job_update(job: Dictionary) -> void:
	_job = job
	_render()
	if InsimulJobReducer.is_terminal(_job):
		_sync_btn.disabled = String(_job.get("status", "")) != "succeeded"


func sync_now() -> void:
	if session == null or _job.is_empty():
		return
	var ref := JSON.stringify({"jobId": String(_job.get("job_id", ""))})
	session.call_operation("syncGenerationJob", ref, func(res: Dictionary):
		_append_log("sync: " + String(res.get("body", "")))
	)


func _render() -> void:
	if _bar == null:
		return
	_bar.value = InsimulJobReducer.progress_percent(_job)
	_append_log(InsimulJobReducer.summarize(_job))


func _append_log(line: String) -> void:
	if _log != null and line != "":
		_log.add_text(line + "\n")


# ── Scheduler seam (SceneTreeTimer-backed) for InsimulJobPoller ────────────────

## Schedule `fn` after `ms`; returns a handle usable with clear_timer.
func set_timer(fn: Callable, ms: int) -> int:
	var handle := _next_handle
	_next_handle += 1
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = float(ms) / 1000.0
	add_child(timer)
	_timers[handle] = timer
	timer.timeout.connect(func():
		_timers.erase(handle)
		if is_instance_valid(timer):
			timer.queue_free()
		fn.call()
	)
	timer.start()
	return handle


## Cancel a scheduled timer by handle.
func clear_timer(handle: int) -> void:
	if _timers.has(handle):
		var timer = _timers[handle]
		if is_instance_valid(timer):
			timer.stop()
			timer.queue_free()
		_timers.erase(handle)
