class_name InsimulRuntime
extends RefCounted
## The portable runtime startup orchestrator for the Godot SDK (US-GC4).
##
## Ties the three runtime-core pieces from US-GC1..GC3 into the single "full loop"
## the template startup path drives:
##
##     world source  ->  save slot  ->  KB  ->  systems init
##
##   - BOOT: prefer an existing save slot (integrity-checked, migrated up by the
##     codec); if there is none — or it is unreadable/corrupt — start a NEW GAME
##     from the world snapshot. A bad slot never bricks startup.
##   - REHYDRATE: from the (migrated) SaveFile, load the world source off its
##     embedded worldSnapshot, restore the KB from currentState.prologFacts, and
##     hydrate every world quest's Prolog content.
##   - COMMIT + SAVE: snapshot the live KB back into currentState.prologFacts and
##     write a canonical, integrity-stamped envelope to the slot. A currentState-
##     only commit never mutates the worldSnapshot, so its integrity hash is stable
##     across the save/reload boundary (the §5.2 B2 portability exit criterion).
##
## Cross-engine parity: mirrors the Unreal FInsimulRuntimeContext /
## UInsimulRuntimeSubsystem (packages/unreal/Source/InsimulRuntime/Portable/
## InsimulBootstrap.* + InsimulRuntimeSubsystem.*) and the Unity leg — same golden
## fixtures, same boot/resume/fallback semantics, same world-hash-stability check.
## The exactness (canonical save + migration + quest hydration + radiant facts)
## lives in the host-tested GDExtension cores; this class only composes the
## runtime GDScript surfaces (InsimulWorldSource, InsimulSaveSystem,
## InsimulQuestSystem, InsimulProlog). The host-tested twin of the whole loop is
## gdextension/test/test_bootstrap.cpp (the InsimulRuntimeCore GDExtension class).
##
## Graceful degradation: when the GDExtension is not built (editor without the
## binary), the save codec / quest core are unavailable and boot() reports the
## failure via last_error() rather than crashing — the same pattern as the other
## runtime classes. The template keeps its legacy startup path as a fallback (see
## MIGRATION.md).

## Signals re-broadcast from the quest system so template UI (offer panels, quest
## trackers) can bind the runtime directly.
signal quest_completed(quest_id: String)
signal objective_completed(quest_id: String, objective_id: String)
signal quest_offered(quest_id: String, tick: int)

var world := InsimulWorldSource.new()
var save := InsimulSaveSystem.new()
var quests := InsimulQuestSystem.new()

var _prolog: Object = null
var _codec: Object = null
var _slot := 0
var _loaded := false
var _resumed_save := false
var _last_error := ""


func _init() -> void:
	# Re-broadcast the quest system's signals through the runtime facade.
	quests.quest_completed.connect(func(qid): quest_completed.emit(qid))
	quests.objective_completed.connect(func(qid, oid): objective_completed.emit(qid, oid))
	quests.quest_offered.connect(func(qid, tick): quest_offered.emit(qid, tick))


## True when the underlying save codec is available (the extension is built). The
## quest core is gated separately by InsimulQuestSystem.core_available().
static func available() -> bool:
	return InsimulSaveSystem.codec_available()


func last_error() -> String:
	return _last_error


func is_loaded() -> bool:
	return _loaded


## True if boot() resumed an existing save (vs starting a new game).
func did_resume_save() -> bool:
	return _resumed_save


## Attach a live InsimulProlog KB so quest assertions are also consulted into the
## real engine (custom completion rules beyond the built-in triggers). Optional.
func attach_prolog(prolog: Object) -> void:
	_prolog = prolog
	quests.attach_kb(prolog)


# ─────────────────────────────────────────────
# Boot (the template startup decision)
# ─────────────────────────────────────────────

## Boot the runtime for `slot`. If the slot holds a valid save, resume it;
## otherwise start a new game from `fallback_world_snapshot_json`. A present-but-
## corrupt slot falls back to a new game (did_resume_save() == false) rather than
## aborting the boot. Returns { ok, resumed_save, error }.
func boot(slot: int, fallback_world_snapshot_json: String, id: String, user_id: String, world_id: String, name: String, created_at: String = "1970-01-01T00:00:00.000Z") -> Dictionary:
	_slot = slot
	_loaded = false
	_resumed_save = false
	_last_error = ""

	# Prefer resuming a present, valid save slot.
	if save.has_save(slot):
		var codec: Object = save.load_from_slot(slot)
		if codec != null and _rehydrate(codec):
			_codec = codec
			_resumed_save = true
			_loaded = true
			return _boot_result(true, true, "")
		# A corrupt/incompatible slot must not brick startup — fall through to a new
		# game rather than aborting the boot.

	# New game from the world snapshot.
	var new_codec: Object = save.new_game(fallback_world_snapshot_json, id, user_id, world_id, name, slot, created_at)
	if new_codec == null:
		_last_error = save.last_error()
		return _boot_result(false, false, _last_error)
	if not _rehydrate(new_codec):
		return _boot_result(false, false, _last_error)
	_codec = new_codec
	_resumed_save = false
	_loaded = true
	return _boot_result(true, false, "")


## (Re)build the world source + KB + hydrated quests from a loaded codec. Uses the
## codec's canonical SaveFile as the single rehydration path, so a resumed older
## save is read at the current version after its migration chain has run.
func _rehydrate(codec: Object) -> bool:
	var save_json: String = codec.serialize_canonical()
	if not world.load_from_save_file_json(save_json):
		_last_error = "runtime rehydrate: %s" % world.last_error()
		return false

	# Restore the KB from currentState.prologFacts (empty on a fresh new game).
	quests.restore_kb(save.restore_kb(codec))

	# Systems init: hydrate every world quest's Prolog content (the source of truth).
	var snapshot: InsimulSaveFile.WorldSnapshot = world.world()
	if snapshot != null:
		quests.load_quests(snapshot.quests)
	return true


func _boot_result(ok: bool, resumed: bool, error: String) -> Dictionary:
	return { "ok": ok, "resumed_save": resumed, "error": error }


# ─────────────────────────────────────────────
# Systems (KB-driven quest + radiant progress)
# ─────────────────────────────────────────────

## Evaluate every objective-bearing quest against the KB, applying the fact-
## asserting transitions and emitting the objective/quest signals. Returns the
## per-quest transition Dictionaries.
func evaluate_all_quests() -> Array:
	var transitions: Array = []
	for qid in quests.get_all_quest_ids():
		var proj: Dictionary = quests.get_projection(qid)
		var objectives: Array = proj.get("objectives", [])
		if objectives.is_empty():
			continue # nothing query-driven to evaluate (e.g. no-op content)
		transitions.append(quests.evaluate_quest(qid))
	return transitions


## Run the deterministic radiant tick over the world's radiant-tagged quests,
## asserting the offering facts into the KB and emitting quest_offered. Returns the
## emitted facts.
func run_radiant_tick(max_offering: int, ticks: int) -> Array:
	var candidates: Array = []
	for qid in quests.get_all_quest_ids():
		var proj: Dictionary = quests.get_projection(qid)
		var tags: Array = proj.get("tags", [])
		if "radiant" not in tags:
			continue
		candidates.append({
			"id": qid,
			"tags": tags,
			"status": str(proj.get("status", "")),
		})
	return quests.run_radiant_tick(candidates, max_offering, ticks)


# ─────────────────────────────────────────────
# Save
# ─────────────────────────────────────────────

## Snapshot the live KB into currentState.prologFacts, then write the current
## SaveFile to `_slot` as a canonical, integrity-stamped envelope. Captures quest +
## radiant progress. Returns false (with last_error set) on any failure.
func save_game(insimul_version: String = "insimul-godot", exported_at: String = "") -> bool:
	if _codec == null:
		_last_error = "save_game: runtime is not booted"
		return false
	save.snapshot_kb(_codec, quests.kb_facts())
	if not save.save_to_slot(_codec, _slot, insimul_version, exported_at):
		_last_error = save.last_error()
		return false
	return true


## SHA-256 hex of the current SaveFile's worldSnapshot alone — stable across a
## currentState-only commit + save/reload (the world-hash-stability parity check,
## computed byte-identically in the host-tested core). Requires the codec; returns
## "" when unavailable.
func world_snapshot_integrity() -> String:
	if _codec == null:
		return ""
	return _codec.world_snapshot_integrity()
