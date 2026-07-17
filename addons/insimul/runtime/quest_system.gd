class_name InsimulQuestSystem
extends RefCounted
## Portable quest system for the Godot runtime (US-GC3).
##
## Rebuilt on the real Prolog KB (InsimulProlog) + the host-tested quest core
## (InsimulQuestCore, gdextension/src/quest_system.*). The parity that matters —
## quest HYDRATION and the RADIANT tick byte-identical to the TS semantics
## authority (packages/core/src/prolog/quest-hydrator.ts) — is delegated ENTIRELY
## to the InsimulQuestCore GDExtension class; GDScript never re-implements it.
##
## Cross-engine parity: mirrors the Unreal FInsimulQuestSystem + the Unity leg —
## same golden corpus (packages/core/conformance/quests/{hydration,radiant}-cases.json),
## same fact-asserting transition semantics. This replaces the template
## systems/quest_system.gd for the portable dimension; the template bootstrap wiring
## (autoload + NPC controllers reading the world source) lands in US-GC4.
##
## KB model: currentState.prologFacts is the canonical truth state the save system
## snapshots/restores. `_facts` mirrors it as Array[Dictionary]{predicate,args} and
## is what the core evaluates completion against; when an InsimulProlog engine is
## attached (`attach_kb`), every assertion is ALSO consulted into it so real Prolog
## queries (custom completion rules beyond the built-in triggers) are available.
##
## Signals are preserved for UI (offer panels, quest trackers, journals).

signal quest_accepted(quest_id: String)
signal quest_completed(quest_id: String)
signal objective_completed(quest_id: String, objective_id: String)
signal quest_offered(quest_id: String, tick: int)

var _core: Object = null
var _prolog: Object = null

## quest_id -> { "content": String, "status": String, "projection": Dictionary }.
var _quests: Dictionary = {}
var _active_quest_ids: Array[String] = []
var _completed_quest_ids: Array[String] = []

## The live KB as Array[Dictionary]{predicate, args} — the save snapshot state.
var _facts: Array = []

var _last_error := ""


## True when the InsimulQuestCore GDExtension class is registered (the extension is
## built + loaded). When false, every core-backed method fails cleanly with
## last_error() set — the headless test SKIPS on this, and the host C++ gate
## (gdextension/test/run_quest_tests.sh) covers the quest semantics regardless.
static func core_available() -> bool:
	return ClassDB.class_exists("InsimulQuestCore")


func _init() -> void:
	if core_available():
		_core = ClassDB.instantiate("InsimulQuestCore")


func last_error() -> String:
	return _last_error


## Attach a live InsimulProlog KB. Assertions made through this quest system are
## also consulted into it, and existing `_facts` are replayed so the engine and the
## fact mirror start in sync. Optional — the built-in completion triggers work
## without it.
func attach_kb(prolog: Object) -> void:
	_prolog = prolog
	if _prolog != null:
		for fact in _facts:
			_prolog.assert_fact(_fact_to_prolog_text(fact))


# ─────────────────────────────────────────────
# Quest loading + hydration
# ─────────────────────────────────────────────

## Hydrate a quest from its Prolog `content` and register it. Returns the present-
## only projection Dictionary (empty on error / no quest facts).
func load_quest(quest_id: String, content: String, status: String = "") -> Dictionary:
	if _core == null:
		_last_error = "InsimulQuestCore GDExtension not available (build the extension)"
		return {}
	var canonical: String = _core.hydrate_canonical(content, status)
	var projection: Dictionary = {}
	if not canonical.is_empty():
		var parsed: Variant = JSON.parse_string(canonical)
		if parsed is Dictionary:
			projection = parsed
	_quests[quest_id] = {
		"content": content,
		"status": status,
		"projection": projection,
	}
	return projection


## Load every quest from a world source's quest list. Each entry is a Dictionary
## carrying at least { "id": String, "content": String } and optionally "status".
func load_quests(quest_entries: Array) -> void:
	for entry in quest_entries:
		var qid: String = str(entry.get("id", ""))
		if qid.is_empty():
			continue
		load_quest(qid, str(entry.get("content", "")), str(entry.get("status", "")))


func get_projection(quest_id: String) -> Dictionary:
	if _quests.has(quest_id):
		return _quests[quest_id].get("projection", {})
	return {}


func get_all_quest_ids() -> Array[String]:
	var ids: Array[String] = []
	for qid in _quests.keys():
		ids.append(qid)
	return ids


# ─────────────────────────────────────────────
# Quest lifecycle
# ─────────────────────────────────────────────

func accept_quest(quest_id: String) -> bool:
	if quest_id in _active_quest_ids or not _quests.has(quest_id):
		return false
	_active_quest_ids.append(quest_id)
	quest_accepted.emit(quest_id)
	return true


func is_quest_active(quest_id: String) -> bool:
	return quest_id in _active_quest_ids


func is_quest_completed(quest_id: String) -> bool:
	return quest_id in _completed_quest_ids


# ─────────────────────────────────────────────
# KB (currentState.prologFacts) + query-driven completion
# ─────────────────────────────────────────────

## Assert a ground fact into the KB (idempotent). `args` is Array[String|int|float].
## Mirrored into the attached InsimulProlog engine when present.
func assert_fact(predicate: String, args: Array) -> void:
	var fact := { "predicate": predicate, "args": args }
	if _has_fact(fact):
		return
	_facts.append(fact)
	if _prolog != null:
		_prolog.assert_fact(_fact_to_prolog_text(fact))


## Evaluate a quest's completion against the current KB. Asserts
## quest_objective_complete / quest_complete facts (via the core), emits
## objective_completed for each newly satisfied objective and quest_completed on the
## transition, and moves the quest into the completed set. Returns the core's
## transition Dictionary.
func evaluate_quest(quest_id: String) -> Dictionary:
	if _core == null or not _quests.has(quest_id):
		return {}
	var q: Dictionary = _quests[quest_id]
	var before := _completed_object_ids(quest_id)
	var result: Dictionary = _core.evaluate_quest(q.get("content", ""), q.get("status", ""), _facts)

	# Adopt the post-evaluation KB (objective/complete facts the core asserted).
	_facts = result.get("facts", _facts)
	if _prolog != null:
		for fact in _facts:
			_prolog.assert_fact(_fact_to_prolog_text(fact))

	# Emit objective_completed for objectives satisfied this evaluation.
	var satisfied: Array = result.get("satisfied_objective_ids", [])
	for obj_id in satisfied:
		if obj_id not in before:
			objective_completed.emit(quest_id, str(obj_id))

	if result.get("completed", false):
		q["status"] = "completed"
		if quest_id not in _completed_quest_ids:
			_completed_quest_ids.append(quest_id)
		_active_quest_ids.erase(quest_id)
		quest_completed.emit(quest_id)
	return result


# ─────────────────────────────────────────────
# Radiant tick
# ─────────────────────────────────────────────

## Run the deterministic radiant tick. `radiant_quests` is Array[Dictionary]{id,
## tags:Array[String], status}. Appends the emitted quest_offered facts to the KB
## and emits the quest_offered signal for each. Returns the emitted facts.
func run_radiant_tick(radiant_quests: Array, max_offering: int, ticks: int) -> Array:
	if _core == null:
		_last_error = "InsimulQuestCore GDExtension not available (build the extension)"
		return []
	var facts: Array = _core.radiant_tick(radiant_quests, max_offering, ticks)
	for fact in facts:
		var args: Array = fact.get("args", [])
		assert_fact(fact.get("predicate", ""), args)
		if args.size() >= 2:
			quest_offered.emit(str(args[0]), int(args[1]))
	return facts


# ─────────────────────────────────────────────
# Save bridge (currentState.prologFacts)
# ─────────────────────────────────────────────

## The live KB as Array[Dictionary]{predicate, args} — hand this to
## InsimulSaveSystem.snapshot_kb().
func kb_facts() -> Array:
	return _facts


## Restore the KB from a saved fact list (InsimulSaveSystem.restore_kb output).
func restore_kb(facts: Array) -> void:
	_facts = facts.duplicate(true)
	if _prolog != null:
		for fact in _facts:
			_prolog.assert_fact(_fact_to_prolog_text(fact))


# ─────────────────────────────────────────────
# Internal helpers
# ─────────────────────────────────────────────

func _has_fact(fact: Dictionary) -> bool:
	for existing in _facts:
		if existing.get("predicate", "") != fact.get("predicate", ""):
			continue
		if existing.get("args", []) == fact.get("args", []):
			return true
	return false


func _completed_object_ids(quest_id: String) -> Array:
	var ids: Array = []
	for fact in _facts:
		if fact.get("predicate", "") != "quest_objective_complete":
			continue
		var args: Array = fact.get("args", [])
		if args.size() >= 2 and str(args[0]) == quest_id:
			ids.append(str(args[1]))
	return ids


## Render a fact Dictionary as Prolog source text `predicate(arg0, arg1)` for
## assertion into an InsimulProlog engine. Atoms are emitted bare; numbers as-is.
func _fact_to_prolog_text(fact: Dictionary) -> String:
	var parts: Array = []
	for arg in fact.get("args", []):
		if arg is int or arg is float:
			parts.append(str(arg))
		else:
			parts.append(str(arg))
	return "%s(%s)" % [fact.get("predicate", ""), ", ".join(parts)]
