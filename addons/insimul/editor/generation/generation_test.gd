# generation_test.gd — the Godot headless leg of the Generation Console gate
# (US-GE2), exercising the LOGIC LAYER (InsimulJobReducer + InsimulJobPoller) over
# mocked SSE frames, a mocked poll response, and a fake scheduler.
#
# The dock UI (insimul_generation_console_dock.gd) needs a running editor and is
# only structurally checked. The machine-runnable source of truth is
# packages/core/src/editor/{generation-console,job-poller}.ts + their .test.ts
# (they run on a bare box under `npm test`); this file is the end-to-end Godot
# confirmation for the merge gate, including the editor-restart teardown path. When
# NO `godot` binary is present the runner SKIPs.
#
#   godot --headless -s addons/insimul/editor/generation/generation_test.gd
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_test_reducer_lifecycle()
	_test_terminal_freeze()
	_test_parse_frames()
	_test_poller_until_terminal()
	_test_poller_teardown_drops_late_response()
	_finish()


func _finish() -> void:
	print("-----------------------------------------------------------")
	print("[insimul-generation] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _test_reducer_lifecycle() -> void:
	var job := InsimulJobReducer.initial_job("j1")
	_report("initial is queued", String(job.get("status", "")) == "queued", "")
	job = InsimulJobReducer.reduce(job, {"progress": 0.2, "stage": "settlements"})
	_report("progress promotes queued->running", String(job.get("status", "")) == "running" and InsimulJobReducer.progress_percent(job) == 20, "%s" % job)
	job = InsimulJobReducer.reduce(job, {"status": "succeeded", "added": 3, "updated": 1, "removed": 2})
	_report("succeeded forces progress 1 + diff", InsimulJobReducer.progress_percent(job) == 100 and int(job.get("added", 0)) == 3, "%s" % job)
	_report("summarize done", InsimulJobReducer.summarize(job) == "Done: +3 / ~1 / -2.", InsimulJobReducer.summarize(job))


func _test_terminal_freeze() -> void:
	var done := InsimulJobReducer.reduce(InsimulJobReducer.initial_job("j"), {"status": "succeeded", "added": 5})
	var after := InsimulJobReducer.reduce(done, {"status": "running", "added": 99})
	_report("terminal job is frozen", int(after.get("added", 0)) == 5 and String(after.get("status", "")) == "succeeded", "%s" % after)


func _test_parse_frames() -> void:
	var ev := InsimulJobReducer.parse_job_event('{"status":"running","progress":0.5,"stage":"lots"}')
	_report("parse SSE frame", String(ev.get("status", "")) == "running" and float(ev.get("progress", 0.0)) == 0.5, "%s" % ev)
	_report("blank frame -> empty", InsimulJobReducer.parse_job_event("  ").is_empty(), "")
	var job := InsimulJobReducer.parse_job('{"jobId":"j9","status":"running","progress":0.4}')
	_report("parse_job poll body", String(job.get("job_id", "")) == "j9" and InsimulJobReducer.progress_percent(job) == 40, "%s" % job)
	_report("parse_job rejects no jobId", InsimulJobReducer.parse_job('{"status":"running"}').is_empty(), "")


func _test_poller_until_terminal() -> void:
	var sched := FakeScheduler.new()
	var fetch := ManualFetch.new()
	var updates: Array = []
	var poller := InsimulJobPoller.new(fetch.make_fetch(), func(job): updates.append(job), sched)
	poller.start()
	_report("first poll issued", fetch.calls == 1, "")
	fetch.resolve(InsimulJobReducer.reduce(InsimulJobReducer.initial_job("j"), {"status": "running", "progress": 0.3}))
	_report("running schedules a timer", sched.live_count() == 1, "")
	sched.flush()
	fetch.resolve(InsimulJobReducer.reduce(InsimulJobReducer.initial_job("j"), {"status": "succeeded"}))
	_report("succeeded disposes, no live timer", poller.is_disposed() and sched.live_count() == 0, "")
	_report("two updates delivered", updates.size() == 2, "%d" % updates.size())


func _test_poller_teardown_drops_late_response() -> void:
	var sched := FakeScheduler.new()
	var fetch := ManualFetch.new()
	var updates: Array = []
	var poller := InsimulJobPoller.new(fetch.make_fetch(), func(job): updates.append(job), sched)
	poller.start()
	# Editor tears the dock down while the request is in flight.
	poller.dispose()
	# The zombie response arrives — it must be dropped entirely.
	fetch.resolve(InsimulJobReducer.reduce(InsimulJobReducer.initial_job("j"), {"status": "running", "progress": 0.9}))
	_report("late response dropped (no update)", updates.is_empty(), "%d" % updates.size())
	_report("no orphaned timer after dispose", sched.live_count() == 0 and not poller.has_pending_timer(), "")


func _report(name: String, ok: bool, detail: String) -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", name, ("" if detail.is_empty() else "  " + detail)])
	if ok:
		_pass += 1
	else:
		_fail += 1


# ── Test doubles ──────────────────────────────────────────────────────────────

## A fake scheduler: timers are inert until flush() runs the due ones.
class FakeScheduler:
	var _next := 1
	var live := {}
	func set_timer(fn: Callable, _ms: int) -> int:
		var id := _next
		_next += 1
		live[id] = fn
		return id
	func clear_timer(handle: int) -> void:
		live.erase(handle)
	func flush() -> void:
		var due := live.values()
		live.clear()
		for fn in due:
			fn.call()
	func live_count() -> int:
		return live.size()


## A fetch seam whose callbacks are captured so the test fires them by hand.
class ManualFetch:
	var pending: Array = []
	var calls := 0
	func make_fetch() -> Callable:
		return func(on_done: Callable):
			calls += 1
			pending.append(on_done)
	func resolve(job: Dictionary) -> void:
		if not pending.is_empty():
			var cb: Callable = pending.pop_front()
			cb.call(job)
