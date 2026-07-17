@tool
class_name InsimulJobReducer
extends RefCounted
## Generation Console — job lifecycle reducer (US-GE2).
##
## The pure, transport-free state machine a generation job flows through
## (queued -> running -> succeeded | failed), fed by either an SSE progress frame
## (streamGenerationJob) or a poll response (getGenerationJob). Both paths funnel
## through the SAME reduce(), so a native engine that can't stream can poll and land
## in an identical state. Mirrors packages/core/src/editor/generation-console.ts
## (the tested source of truth, generation-console.test.ts); driven headless by
## generation_test.gd (merge-gate GUT) and covered by the structural lint.

## Job Dictionary shape:
##   { "job_id": String, "status": String, "progress": float, "stage": String,
##     "message": String, "added": int, "updated": int, "removed": int,
##     "error": String }
## status is "queued" | "running" | "succeeded" | "failed".

const _VALID_STATUS := ["queued", "running", "succeeded", "failed"]


static func initial_job(job_id: String) -> Dictionary:
	return {
		"job_id": job_id, "status": "queued", "progress": 0.0, "stage": "",
		"message": "", "added": 0, "updated": 0, "removed": 0, "error": "",
	}


static func is_terminal(job: Dictionary) -> bool:
	var s := String(job.get("status", ""))
	return s == "succeeded" or s == "failed"


static func _clamp01(n: float) -> float:
	if not is_finite(n):
		return 0.0
	return clampf(n, 0.0, 1.0)


## Fold one event Dictionary (partial delta) into `job`, returning the new job. A
## terminal job is frozen — later events are ignored (so SSE + polling can overlap).
static func reduce(job: Dictionary, ev: Dictionary) -> Dictionary:
	if is_terminal(job):
		return job

	var status := String(job.get("status", "queued"))
	if ev.has("status") and _VALID_STATUS.has(String(ev["status"])):
		status = String(ev["status"])
	elif status == "queued" and (ev.has("progress") or ev.has("stage") or ev.has("message")):
		status = "running"
	if ev.has("error") and String(ev["error"]) != "":
		status = "failed"

	var progress := _clamp01(float(ev["progress"])) if ev.has("progress") else float(job.get("progress", 0.0))
	if status == "succeeded":
		progress = 1.0

	var err := String(job.get("error", ""))
	if ev.has("error") and String(ev["error"]) != "":
		err = String(ev["error"])

	return {
		"job_id": String(job.get("job_id", "")),
		"status": status,
		"progress": progress,
		"stage": String(ev["stage"]) if ev.has("stage") else String(job.get("stage", "")),
		"message": String(ev["message"]) if ev.has("message") else String(job.get("message", "")),
		"added": int(ev["added"]) if ev.has("added") else int(job.get("added", 0)),
		"updated": int(ev["updated"]) if ev.has("updated") else int(job.get("updated", 0)),
		"removed": int(ev["removed"]) if ev.has("removed") else int(job.get("removed", 0)),
		"error": err,
	}


## Fold a sequence of event dicts (e.g. a recorded stream) into a job.
static func reduce_all(job: Dictionary, events: Array) -> Dictionary:
	var acc := job
	for ev in events:
		acc = reduce(acc, ev)
	return acc


## Parse an SSE data frame into an event Dictionary of the known fields only.
## Returns {} for a blank/keepalive frame or non-object / bad JSON.
static func parse_job_event(data: String) -> Dictionary:
	var trimmed := data.strip_edges()
	if trimmed == "":
		return {}
	var parsed = JSON.parse_string(trimmed)
	if not (parsed is Dictionary):
		return {}
	return _to_event(parsed)


static func _to_event(o: Dictionary) -> Dictionary:
	var ev := {}
	if o.has("status") and _VALID_STATUS.has(String(o["status"])):
		ev["status"] = String(o["status"])
	for key in ["stage", "message", "error"]:
		if o.has(key) and o[key] is String:
			ev[key] = String(o[key])
	if o.has("progress"):
		ev["progress"] = float(o["progress"])
	for key in ["added", "updated", "removed"]:
		if o.has(key):
			ev[key] = int(o[key])
	return ev


## Parse a getGenerationJob poll body into a full job. Returns {} without a jobId.
static func parse_job(body: String) -> Dictionary:
	var parsed = JSON.parse_string(body)
	if not (parsed is Dictionary):
		return {}
	var job_id := String(parsed.get("jobId", ""))
	if job_id == "":
		return {}
	return reduce(initial_job(job_id), _to_event(parsed))


static func progress_percent(job: Dictionary) -> int:
	return int(round(_clamp01(float(job.get("progress", 0.0))) * 100.0))


static func summarize(job: Dictionary) -> String:
	match String(job.get("status", "")):
		"queued":
			return "Queued."
		"running":
			var stage := String(job.get("stage", ""))
			var suffix := " (%s)" % stage if stage != "" else ""
			return "Running%s — %d%%." % [suffix, progress_percent(job)]
		"succeeded":
			return "Done: +%d / ~%d / -%d." % [int(job.get("added", 0)), int(job.get("updated", 0)), int(job.get("removed", 0))]
		"failed":
			var err := String(job.get("error", ""))
			return "Failed: %s." % (err if err != "" else "unknown error")
		_:
			return ""
