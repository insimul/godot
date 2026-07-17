@tool
class_name InsimulWorldCompat
extends RefCounted
## World compatibility badge — logic layer (US-GE2).
##
## Mirrors packages/core/src/editor/world-browser.ts `worldCompatibility`: given a
## world's save-format version and the editor's supported version, returns the
## badge the World Browser detail pane shows. The core module is the tested source
## of truth (world-browser.test.ts); this is the GDScript parity implementation the
## dock uses, covered by browser_test.gd (merge-gate GUT) + the structural lint.

## The save-format version this editor supports. MUST track SAVE_FILE_VERSION in
## packages/core/src/save-file.ts (and MAX_SUPPORTED_SAVE_VERSION in
## runtime/world_source.gd) — a world stamped beyond this needs a newer editor.
const SUPPORTED_SAVE_FORMAT := 3


## Compatibility of `world_save_format` with `supported` (defaults to the editor's
## SUPPORTED_SAVE_FORMAT). Returns { "level": String, "message": String } where
## level is "compatible" | "warning" | "incompatible".
static func compatibility(world_save_format: int, supported: int = SUPPORTED_SAVE_FORMAT) -> Dictionary:
	if world_save_format == supported:
		return {"level": "compatible", "message": "Save format v%d matches the editor." % world_save_format}
	if world_save_format < supported:
		return {
			"level": "warning",
			"message": "Save format v%d is older than the editor (v%d); it will be migrated on import." % [world_save_format, supported],
		}
	return {
		"level": "incompatible",
		"message": "Save format v%d is newer than the editor (v%d); update the editor to open this world." % [world_save_format, supported],
	}
