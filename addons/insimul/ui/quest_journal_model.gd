class_name InsimulQuestJournalModel
extends RefCounted
## Quest journal / tracker / offer view-model (US-GU2).
##
## The Godot mirror of the engine-neutral quest UI contract
## (packages/core/src/ui/quest-journal-model.ts). Holds the player-facing quest set
## (present-only projections: id, title, difficulty, status) and the interaction
## state the three quest panels share:
##   - the JOURNAL: tab filtering (all / active / completed / available) + counts,
##   - the TRACKER HUD: the bounded set of tracked ACTIVE quests,
##   - the OFFER dialog: accept / decline of an AVAILABLE quest (radiant arrivals
##     land here via upsert()).
##
## Lifecycle transitions mirror the real InsimulQuestSystem signals — accept
## (available -> active), complete (active -> completed, auto-untracked), upsert (a
## radiant quest_offered arrival appears as available). Shared cases:
## packages/core/conformance/ui/quest-journal-cases.json.

const DEFAULT_MAX_TRACKED := 3

var _order: Array[String] = []
var _by_id: Dictionary = {}          # id -> { id, title, status, difficulty?, ... }
var _tracked: Array[String] = []
var _filter: String = "all"
var _max_tracked: int = DEFAULT_MAX_TRACKED


func _init(max_tracked: int = DEFAULT_MAX_TRACKED) -> void:
	_max_tracked = max_tracked if max_tracked > 0 else DEFAULT_MAX_TRACKED


## Replace the whole quest set (e.g. on load), preserving given order.
func set_quests(entries: Array) -> void:
	_order.clear()
	_by_id.clear()
	_tracked.clear()
	for e in entries:
		upsert(e)


## Add or replace a quest by id (a radiant arrival / quest_offered lands here). A
## brand-new id is appended so list order stays stable.
func upsert(entry: Dictionary) -> void:
	var id := String(entry.get("id", ""))
	if id.is_empty():
		return
	if not _by_id.has(id):
		_order.append(id)
	_by_id[id] = entry.duplicate(true)


func get_quest(id: String) -> Dictionary:
	if _by_id.has(id):
		return (_by_id[id] as Dictionary).duplicate(true)
	return {}


## Accept an AVAILABLE quest (available -> active). No-op otherwise.
func accept(id: String) -> bool:
	if not _by_id.has(id) or String(_by_id[id].get("status", "")) != "available":
		return false
	_by_id[id]["status"] = "active"
	return true


## Decline an AVAILABLE quest (offer dismissed) — removes it entirely.
func decline(id: String) -> bool:
	if not _by_id.has(id) or String(_by_id[id].get("status", "")) != "available":
		return false
	_remove(id)
	return true


## Complete an ACTIVE quest (active -> completed) and auto-untrack it.
func complete(id: String) -> bool:
	if not _by_id.has(id) or String(_by_id[id].get("status", "")) != "active":
		return false
	_by_id[id]["status"] = "completed"
	untrack(id)
	return true


func _remove(id: String) -> void:
	_by_id.erase(id)
	_order.erase(id)
	untrack(id)


# ── Filtering / counts ────────────────────────────────────────────────────────

func set_filter(filter: String) -> void:
	_filter = filter


func current_filter() -> String:
	return _filter


## Quests matching the current filter, in stable insertion order.
func filtered() -> Array:
	var out: Array = []
	for id in _order:
		var e: Dictionary = _by_id[id]
		if _filter == "all" or String(e.get("status", "")) == _filter:
			out.append(e.duplicate(true))
	return out


func filtered_ids() -> Array:
	var out: Array = []
	for e in filtered():
		out.append(String(e.get("id", "")))
	return out


func counts() -> Dictionary:
	var c := {"all": 0, "active": 0, "completed": 0, "available": 0}
	for id in _order:
		var status := String(_by_id[id].get("status", ""))
		c["all"] += 1
		if c.has(status):
			c[status] += 1
	return c


# ── Tracker HUD ───────────────────────────────────────────────────────────────

## Track an ACTIVE quest for the HUD. Fails if the quest is not active, already
## tracked, or the tracked set is full (max_tracked). Returns true on a change.
func track(id: String) -> bool:
	if not _by_id.has(id) or String(_by_id[id].get("status", "")) != "active":
		return false
	if id in _tracked:
		return false
	if _tracked.size() >= _max_tracked:
		return false
	_tracked.append(id)
	return true


func untrack(id: String) -> bool:
	if id in _tracked:
		_tracked.erase(id)
		return true
	return false


func is_tracked(id: String) -> bool:
	return id in _tracked


## The tracker HUD view: tracked quests that are still active, in track order.
func tracked_quests() -> Array:
	var out: Array = []
	for id in _tracked:
		if _by_id.has(id) and String(_by_id[id].get("status", "")) == "active":
			out.append((_by_id[id] as Dictionary).duplicate(true))
	return out


func tracked_ids() -> Array:
	var out: Array = []
	for e in tracked_quests():
		out.append(String(e.get("id", "")))
	return out
