@tool
class_name InsimulJobPoller
extends RefCounted
## Generation-job polling fallback + teardown (US-GE2).
##
## When the editor can't hold an SSE stream open, the Generation Console polls
## getGenerationJob on an interval. This poller owns the TIMER and the IN-FLIGHT
## REQUEST — the exact things that leak across an editor restart. It is written to
## the editor-restart-safety criterion, mirroring
## packages/core/src/editor/job-poller.ts (the tested source of truth,
## job-poller.test.ts):
##
##   - dispose() cancels the pending timer AND flips `_disposed`, so a fetch
##     callback returning AFTER dispose is DROPPED (no on_update, no next poll).
##   - Polling stops on its own once the job reaches a terminal status.
##
## Both seams are injected so the lifecycle is testable headless (generation_test.gd):
##   - `_fetch_job`: Callable(on_done: Callable) — performs one poll, calls
##     on_done.call(job_dict_or_empty). The real dock backs it with an HTTPRequest.
##   - `_scheduler`: an object with set_timer(fn: Callable, ms: int) -> int and
##     clear_timer(handle: int). The real dock backs it with a SceneTreeTimer.

var _fetch_job: Callable
var _on_update: Callable
var _scheduler
var _interval_ms: int = 1000
var _max_polls: int = 600

var _timer_handle: int = -1
var _disposed := false
var _started := false
var _poll_count := 0


func _init(fetch_job: Callable, on_update: Callable, scheduler, interval_ms: int = 1000, max_polls: int = 600) -> void:
	_fetch_job = fetch_job
	_on_update = on_update
	_scheduler = scheduler
	_interval_ms = interval_ms
	_max_polls = max_polls


func is_disposed() -> bool:
	return _disposed


func poll_count() -> int:
	return _poll_count


func has_pending_timer() -> bool:
	return _timer_handle != -1


## Begin polling immediately. Idempotent; a no-op after dispose.
func start() -> void:
	if _started or _disposed:
		return
	_started = true
	_poll()


func _poll() -> void:
	if _disposed:
		return
	_poll_count += 1
	_fetch_job.call(func(job):
		# Drop a response that arrives after teardown — the defining safety rule.
		if _disposed:
			return
		if job is Dictionary and not job.is_empty():
			_on_update.call(job)
			if InsimulJobReducer.is_terminal(job):
				dispose()
				return
		if _poll_count >= _max_polls:
			dispose()
			return
		_schedule_next()
	)


func _schedule_next() -> void:
	if _disposed:
		return
	_timer_handle = _scheduler.set_timer(func():
		_timer_handle = -1
		_poll()
	, _interval_ms)


## Tear down: cancel the pending timer and drop any in-flight response. Safe to
## call multiple times and from any callback (e.g. the dock's _exit_tree).
func dispose() -> void:
	_disposed = true
	if _timer_handle != -1:
		_scheduler.clear_timer(_timer_handle)
		_timer_handle = -1
