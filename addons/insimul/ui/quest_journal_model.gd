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
##
## ## The real system drives it
##
## [method bind_quest_system] connects the live InsimulQuestSystem's signals, so a
## radiant arrival (quest_offered) lands in the journal as an AVAILABLE quest with
## no polling, and an accept/complete made anywhere in the game shows up in every
## panel sharing this model. The binding is DUCK-TYPED — signal names and
## `get_projection()` — because the quest system reaches into the GDExtension and
## nothing under addons/insimul/ui/ may, so that the default UI still loads in a
## project with no native build.

## Emitted after any change to the quest set, the filter or the tracked set. The
## journal / tracker / offer panels share ONE model and redraw off this.
signal changed

const DEFAULT_MAX_TRACKED := 3

var _order: Array[String] = []
var _by_id: Dictionary = {}          # id -> { id, title, status, difficulty?, ... }
var _tracked: Array[String] = []
var _filter: String = "all"
var _max_tracked: int = DEFAULT_MAX_TRACKED
var _quest_source: Object = null


func _init(max_tracked: int = DEFAULT_MAX_TRACKED) -> void:
	_max_tracked = max_tracked if max_tracked > 0 else DEFAULT_MAX_TRACKED


## Replace the whole quest set (e.g. on load), preserving given order.
func set_quests(entries: Array) -> void:
	_order.clear()
	_by_id.clear()
	_tracked.clear()
	for e in entries:
		upsert(e)
	changed.emit()


## Add or replace a quest by id (a radiant arrival / quest_offered lands here). A
## brand-new id is appended so list order stays stable.
func upsert(entry: Dictionary) -> void:
	var id := String(entry.get("id", ""))
	if id.is_empty():
		return
	if not _by_id.has(id):
		_order.append(id)
	_by_id[id] = entry.duplicate(true)
	changed.emit()


func get_quest(id: String) -> Dictionary:
	if _by_id.has(id):
		return (_by_id[id] as Dictionary).duplicate(true)
	return {}


## Accept an AVAILABLE quest (available -> active). No-op otherwise.
func accept(id: String) -> bool:
	if not _by_id.has(id) or String(_by_id[id].get("status", "")) != "available":
		return false
	_by_id[id]["status"] = "active"
	changed.emit()
	return true


## Decline an AVAILABLE quest (offer dismissed) — removes it entirely.
func decline(id: String) -> bool:
	if not _by_id.has(id) or String(_by_id[id].get("status", "")) != "available":
		return false
	_remove(id)
	changed.emit()
	return true


## Complete an ACTIVE quest (active -> completed) and auto-untrack it.
func complete(id: String) -> bool:
	if not _by_id.has(id) or String(_by_id[id].get("status", "")) != "active":
		return false
	_by_id[id]["status"] = "completed"
	untrack(id)
	changed.emit()
	return true


func _remove(id: String) -> void:
	_by_id.erase(id)
	_order.erase(id)
	untrack(id)


# ── Filtering / counts ────────────────────────────────────────────────────────

func set_filter(filter: String) -> void:
	if _filter == filter:
		return
	_filter = filter
	changed.emit()


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
	changed.emit()
	return true


func untrack(id: String) -> bool:
	if id in _tracked:
		_tracked.erase(id)
		changed.emit()
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


# ── The real quest system ─────────────────────────────────────────────────────

## Drive this model from the live quest system. `system` is anything carrying the
## InsimulQuestSystem signals — `quest_offered(quest_id, tick)`,
## `quest_accepted(quest_id)`, `quest_completed(quest_id)` — and, ideally,
## `get_projection(quest_id)` for the present-only projection a panel draws.
##
## Only the signals the system actually has are connected, and connecting twice is
## a no-op, so a panel may bind a system that predates a signal without erroring.
## Returns the signals that were connected.
func bind_quest_system(system: Variant) -> PackedStringArray:
	var connected := PackedStringArray()
	if not (system is Object):
		return connected
	var object := system as Object
	for pair in [
		["quest_offered", _on_quest_offered],
		["quest_accepted", _on_quest_accepted],
		["quest_completed", _on_quest_completed],
	]:
		var signal_name := String(pair[0])
		var handler: Callable = pair[1]
		if not object.has_signal(signal_name):
			continue
		if object.is_connected(signal_name, handler):
			continue
		object.connect(signal_name, handler)
		connected.append(signal_name)
	_quest_source = object
	_hydrate_from_source()
	return connected


## Re-read every known quest from the bound system. A load, a genre change, or a
## panel opened long after the binding all want this.
func refresh_from_source() -> void:
	_hydrate_from_source()


func _hydrate_from_source() -> void:
	if _quest_source == null or not _quest_source.has_method("get_all_quest_ids"):
		return
	for id in _quest_source.get_all_quest_ids():
		_upsert_from_source(String(id), "")


## The projection the system holds for `id`, as a journal entry. Falls back to a
## bare { id, title, status } when the system offers no projection — a quest that
## arrived is worth showing even if its content did not hydrate.
func _entry_from_source(id: String, status_hint: String) -> Dictionary:
	var entry := {"id": id, "title": id, "status": status_hint if not status_hint.is_empty() else "available"}
	if _quest_source != null and _quest_source.has_method("get_projection"):
		var projection: Variant = _quest_source.get_projection(id)
		if projection is Dictionary and not (projection as Dictionary).is_empty():
			entry.merge(projection as Dictionary, true)
			entry["id"] = id
	if not status_hint.is_empty():
		entry["status"] = status_hint
	elif not ["available", "active", "completed"].has(String(entry.get("status", ""))):
		entry["status"] = "available"
	return entry


func _upsert_from_source(id: String, status_hint: String) -> void:
	var status := status_hint
	if status.is_empty() and _by_id.has(id):
		status = String(_by_id[id].get("status", ""))
	if status.is_empty() and _quest_source != null:
		if _quest_source.has_method("is_quest_completed") and _quest_source.is_quest_completed(id):
			status = "completed"
		elif _quest_source.has_method("is_quest_active") and _quest_source.is_quest_active(id):
			status = "active"
	upsert(_entry_from_source(id, status))


func _on_quest_offered(quest_id: String, _tick: int) -> void:
	_upsert_from_source(String(quest_id), "available")


func _on_quest_accepted(quest_id: String) -> void:
	_upsert_from_source(String(quest_id), "active")


func _on_quest_completed(quest_id: String) -> void:
	_upsert_from_source(String(quest_id), "completed")
	untrack(String(quest_id))
