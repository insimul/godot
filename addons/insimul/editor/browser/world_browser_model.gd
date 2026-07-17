@tool
class_name InsimulWorldBrowserModel
extends RefCounted
## World Browser dock — logic layer (US-GE2).
##
## The pure, UI-free heart of the World Browser: it parses the listWorlds /
## importWorld API bodies, drives the list + selection reducer, builds the
## open-in-web URL, and delegates the compatibility badge to InsimulWorldCompat.
## Mirrors packages/core/src/editor/world-browser.ts (the tested source of truth,
## world-browser.test.ts). Keeping this a RefCounted with NO Control dependency is
## what makes the dock's logic testable headless (browser_test.gd) while the Control
## (insimul_world_browser_dock.gd) is only structurally checked.

## State Dictionary shape:
##   { "status": String, "worlds": Array[Dictionary], "selected_id": String,
##     "error": String }
## status is "idle" | "loading" | "loaded" | "error"; selected_id is "" when none.

var state: Dictionary = _initial()


static func _initial() -> Dictionary:
	return {"status": "idle", "worlds": [], "selected_id": "", "error": ""}


func reset() -> void:
	state = _initial()


# ---------------------------------------------------------------------------
# Response parsing (mocked-API bodies -> view-model dictionaries)
# ---------------------------------------------------------------------------

## Parse one world object defensively. Returns {} when it lacks an id.
static func parse_world(raw) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var id := String(raw.get("id", ""))
	if id == "":
		return {}
	var name := String(raw.get("name", ""))
	return {
		"id": id,
		"name": name if name != "" else id,
		"description": String(raw.get("description", "")),
		"world_version": int(raw.get("worldVersion", 0)),
		"save_format_version": int(raw.get("saveFormatVersion", 0)),
		"engine_revision": String(raw.get("engineRevision", "")),
		"npc_count": int(raw.get("npcCount", 0)),
		"settlement_count": int(raw.get("settlementCount", 0)),
		"quest_count": int(raw.get("questCount", 0)),
	}


## Parse a listWorlds body ({ "worlds": [...] }) into an Array of world dicts.
static func parse_world_list(body: String) -> Array:
	var parsed = JSON.parse_string(body)
	if not (parsed is Dictionary) or not parsed.has("worlds"):
		return []
	var raw = parsed["worlds"]
	if not (raw is Array):
		return []
	var out: Array = []
	for w in raw:
		var parsed_world := parse_world(w)
		if not parsed_world.is_empty():
			out.append(parsed_world)
	return out


## Parse an importWorld / ImportReport body. Returns {} when it lacks worldId.
static func parse_import_report(body: String) -> Dictionary:
	var parsed = JSON.parse_string(body)
	if not (parsed is Dictionary) or not parsed.has("worldId"):
		return {}
	var messages: Array = []
	for m in parsed.get("messages", []):
		if m is String:
			messages.append(m)
	return {
		"world_id": String(parsed["worldId"]),
		"dry_run": bool(parsed.get("dryRun", false)),
		"added": int(parsed.get("added", 0)),
		"updated": int(parsed.get("updated", 0)),
		"removed": int(parsed.get("removed", 0)),
		"unchanged": int(parsed.get("unchanged", 0)),
		"messages": messages,
	}


static func import_report_is_clean(report: Dictionary) -> bool:
	return int(report.get("added", 0)) == 0 and int(report.get("updated", 0)) == 0 \
		and int(report.get("removed", 0)) == 0


static func summarize_import_report(report: Dictionary) -> String:
	var prefix := "Dry run: " if bool(report.get("dry_run", false)) else ""
	var unchanged := int(report.get("unchanged", 0))
	if import_report_is_clean(report):
		return "%sno changes (%d unchanged)." % [prefix, unchanged]
	return "%s+%d / ~%d / -%d (%d unchanged)." % [
		prefix, int(report.get("added", 0)), int(report.get("updated", 0)),
		int(report.get("removed", 0)), unchanged,
	]


# ---------------------------------------------------------------------------
# Compatibility badge + open-in-web URL
# ---------------------------------------------------------------------------

static func world_compatibility(world: Dictionary, supported: int = InsimulWorldCompat.SUPPORTED_SAVE_FORMAT) -> Dictionary:
	return InsimulWorldCompat.compatibility(int(world.get("save_format_version", 0)), supported)


static func open_in_web_url(base_url: String, world_id: String) -> String:
	return "%s/worlds/%s" % [base_url.rstrip("/"), world_id.uri_encode()]


# ---------------------------------------------------------------------------
# Browser reducer (list load + selection lifecycle)
# ---------------------------------------------------------------------------

func load_start() -> void:
	state["status"] = "loading"
	state["error"] = ""


## Record a loaded worlds list; drops a now-dangling selection.
func load_success(worlds: Array) -> void:
	var keep := ""
	var current := String(state.get("selected_id", ""))
	if current != "":
		for w in worlds:
			if String(w.get("id", "")) == current:
				keep = current
				break
	state = {"status": "loaded", "worlds": worlds, "selected_id": keep, "error": ""}


func load_error(message: String) -> void:
	state["status"] = "error"
	state["error"] = message


## Select a world by id (or "" to clear). Ignores an id not in the list.
func select(world_id: String) -> void:
	if world_id != "" and not _has_world(world_id):
		return
	state["selected_id"] = world_id


func _has_world(world_id: String) -> bool:
	for w in state.get("worlds", []):
		if String(w.get("id", "")) == world_id:
			return true
	return false


## The currently-selected world dict, or {} when none.
func selected_world() -> Dictionary:
	var id := String(state.get("selected_id", ""))
	if id == "":
		return {}
	for w in state.get("worlds", []):
		if String(w.get("id", "")) == id:
			return w
	return {}
