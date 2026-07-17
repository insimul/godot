class_name InsimulSaveSystem
extends RefCounted
## Portable save system for the Godot runtime (US-GC2).
##
## New-game / save / load with envelope integrity. The exactness that matters —
## canonical key-sorted JSON + SHA-256 byte-identical to
## packages/core/src/save-envelope.ts — is delegated ENTIRELY to the
## InsimulSaveCodec GDExtension class (gdextension/src/insimul_save_codec.*,
## backed by the host-tested C++ core). GDScript never re-implements the hash:
## Godot's JSON.stringify orders keys and formats numbers differently, so it
## would not match. This class owns only slot I/O on `user://` and the envelope
## read/verify/write flow around the codec.
##
## Cross-engine parity: mirrors the Unreal FInsimulSaveSystem shell + the Unity
## leg — same envelope format ("insimul-save-v2"), same golden fixtures
## (packages/core/conformance/saves), same v1->v3 migration. This replaces the
## template systems/save_system.gd for the portable dimension; the template
## bootstrap wiring (autoload + NPC controllers) lands in US-GC4. See MIGRATION.md.
##
## KB snapshot/restore: currentState.prologFacts is the canonical truth state.
## `snapshot_kb()` writes a fact list into the codec; `restore_kb()` reads it back
## as Array[Dictionary]{predicate,args} for the Prolog runtime (InsimulProlog) to
## re-assert. The bridge to a live KB is wired by the quest system (US-GC3) and the
## bootstrap (US-GC4).

const SAVE_DIR := "user://saves/"
const MAX_SLOTS := 3
const ENVELOPE_FORMAT := "insimul-save-v2"

var _last_error := ""


## True when the InsimulSaveCodec GDExtension class is registered (the extension
## is built + loaded). When false, every codec-backed method fails cleanly with
## last_error() set — the headless test SKIPS on this, and the host C++ gate
## (gdextension/test/run_save_tests.sh) covers the codec semantics regardless.
static func codec_available() -> bool:
	return ClassDB.class_exists("InsimulSaveCodec")


func last_error() -> String:
	return _last_error


## Instantiate a fresh codec, or null (with last_error set) when the extension is
## unavailable.
func _new_codec() -> Object:
	if not codec_available():
		_last_error = "InsimulSaveCodec GDExtension not available (build the extension)"
		return null
	return ClassDB.instantiate("InsimulSaveCodec")


# ─────────────────────────────────────────────
# New game / save / load
# ─────────────────────────────────────────────

## Build a fresh, current-version save around a world-snapshot document (the shape
## of SaveFile.worldSnapshot or a WorldIR export). Returns the loaded codec, or
## null on error (malformed snapshot / extension missing).
func new_game(world_snapshot_json: String, id: String, user_id: String, world_id: String, name: String, slot_index: int, created_at: String = "1970-01-01T00:00:00.000Z") -> Object:
	var codec := _new_codec()
	if codec == null:
		return null
	if not codec.new_game(world_snapshot_json, id, user_id, world_id, name, slot_index, created_at):
		_last_error = codec.last_error()
		return null
	return codec


## Write the codec's current SaveFile to `slot` as a verifiable export envelope.
## `insimul_version` / `exported_at` are stamped into the envelope wrapper (they
## do NOT affect the integrity hash, which covers the saveFile only).
func save_to_slot(codec: Object, slot: int, insimul_version: String = "insimul-godot", exported_at: String = "") -> bool:
	if codec == null:
		_last_error = "save_to_slot: codec is null"
		return false
	if slot < 0 or slot >= MAX_SLOTS:
		_last_error = "save_to_slot: invalid slot %d" % slot
		return false
	var envelope: String = codec.build_envelope(insimul_version, exported_at)
	return _write_slot_text(slot, envelope)


## Read + validate slot `slot`. Verifies the envelope format and recomputes the
## SHA-256 integrity over the wrapped saveFile (rejecting corruption/tampering),
## then loads + migrates it. Returns the loaded codec, or null on any failure.
func load_from_slot(slot: int) -> Object:
	var text := _read_slot_text(slot)
	if text.is_empty():
		return null
	return load_envelope(text)


## Validate + load a raw envelope JSON string. Mirrors validateSaveFileEnvelope in
## save-envelope.ts: format tag, present saveFile, and a recomputed integrity hash
## that must equal the stored one.
func load_envelope(envelope_json: String) -> Object:
	var json := JSON.new()
	if json.parse(envelope_json) != OK:
		_last_error = "envelope is not valid JSON: %s" % json.get_error_message()
		return null
	var env: Dictionary = json.data if json.data is Dictionary else {}
	if env.get("format", "") != ENVELOPE_FORMAT:
		_last_error = "unknown envelope format: expected '%s', got '%s'" % [ENVELOPE_FORMAT, str(env.get("format", ""))]
		return null
	if not (env.get("saveFile") is Dictionary):
		_last_error = "envelope is missing saveFile payload"
		return null
	var integrity: String = str(env.get("integrity", ""))
	if integrity.is_empty():
		_last_error = "envelope is missing integrity hash"
		return null

	var codec := _new_codec()
	if codec == null:
		return null
	# Re-serialize the saveFile (any formatting) and let the codec canonicalize +
	# hash it: the canonical bytes are formatting-independent, so a match proves
	# the file is intact.
	var save_json: String = JSON.stringify(env.get("saveFile"))
	if not codec.load(save_json):
		_last_error = codec.last_error()
		return null
	if codec.compute_integrity() != integrity:
		_last_error = "save file integrity check failed — file may be corrupted or tampered"
		return null
	return codec


# ─────────────────────────────────────────────
# KB snapshot / restore (currentState.prologFacts)
# ─────────────────────────────────────────────

## Overwrite currentState.prologFacts on the codec with `facts`, each a
## Dictionary { "predicate": String, "args": Array[String|int|float] }.
func snapshot_kb(codec: Object, facts: Array) -> void:
	if codec != null:
		codec.snapshot_facts(facts)


## Read currentState.prologFacts back as Array[Dictionary]{predicate,args}.
func restore_kb(codec: Object) -> Array:
	if codec == null:
		return []
	return codec.restore_facts()


# ─────────────────────────────────────────────
# Slot management (user://)
# ─────────────────────────────────────────────

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


func delete_save(slot: int) -> void:
	var path := _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _slot_path(slot: int) -> String:
	return SAVE_DIR.path_join("save_slot_%d.json" % slot)


func _write_slot_text(slot: int, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if file == null:
		_last_error = "failed to open save file for write: %s" % _slot_path(slot)
		return false
	file.store_string(text)
	file.close()
	return true


func _read_slot_text(slot: int) -> String:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		_last_error = "no save found in slot %d" % slot
		return ""
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		_last_error = "failed to read save file: %s" % path
	return text
