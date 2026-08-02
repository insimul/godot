class_name InsimulRadiantSource
extends RefCounted
## Radiant quest generation for the Godot SDK — the FIRST slice of `@insimul/core`
## this plugin adopts (tasklist 100; RUNTIME_CORE_ADOPTION.md §5).
##
## Radiant quests are the ones a game generates on the fly from templates and the
## current world state ("cull the wolves", "deliver bread to cara") rather than
## authoring by hand. Core owns that algorithm — 678 lines of Prolog-driven,
## seeded, deterministic slot filling — and this plugin now calls it instead of
## re-implementing it.
##
## THIS FILE IS THE ONLY PLACE GODOT TYPES BECOME CORE'S TYPES. Everything below
## `InsimulCore` is JSON: `InsimulCore.call_json()` marshals bytes and nothing
## else, precisely so this translation cannot end up scattered across call sites
## or duplicated in C++ (US-2's fourth criterion). The whole stack:
##
##     InsimulRadiantSource      <- you are here; Dictionary <-> JSON
##     InsimulCore               <- RefCounted wrapper over the C ABI
##     libinsimulcore            <- QuickJS + the vendored @insimul/core bundle
##     libinsimul                <- Trealla, natively linked
##
## PERFORMANCE. `generate()` crosses a JSON boundary and runs a Prolog program.
## It is a DECISION call — tick it when the director should offer new work (on
## entering a settlement, on a day boundary, every few seconds at most), never
## from `_process`. See gdextension/corebridge/include/insimulcore.h.
##
## PARITY. The generated quests are pinned by the shared cross-runtime corpus
## `conformance/radiant/*.json` — the same 11 vectors packages/core runs. The
## host gate is `gdextension/test/run_radiant_tests.sh`.

## Radiant quests come from `@insimul/core` through the native bridge.
const SOURCE_CORE := "core"

## This plugin's PRE-ADOPTION behaviour: no radiant quest GENERATION at all.
## (`InsimulRuntime.run_radiant_tick()` is a different thing — it *offers*
## already-authored radiant quests over successive ticks. Nothing in this repo
## has ever turned templates + world state into new quests.) Kept
## selectable for one story (US-2 -> US-3) so the two can be run over the same
## corpus and every difference classified, the same discipline tasklist 91 used
## when it kept tau-prolog alive for one story before deleting it.
##
## US-3 RAN THAT DIFF AND RETAINED THIS DELIBERATELY (the story's last criterion
## is "removed OR explicitly retained with a reason"). Two reasons:
##   1. It is not a superseded implementation. Deleting tau-prolog removed a
##      SECOND implementation of a thing; there is no second implementation of
##      radiant generation here — `none` is the "off" setting, and a game that
##      does not want procedurally generated quests still needs it.
##   2. It is now load-bearing evidence. `run_radiant_tests.sh --source none`
##      classifies all 11 vectors as 4 AGREE / 7 GAIN / 0 REGRESSION, and that
##      assertion is what keeps "the adoption is a strict capability gain" true
##      after somebody edits the generator. Removing the leg would delete the
##      proof along with the code.
## It is also a genuine runtime fallback: a build without libinsimulcore lands
## here rather than erroring.
const SOURCE_NONE := "none"

## Which implementation answers `generate()`. Defaults to core; set to
## SOURCE_NONE to reproduce pre-adoption behaviour.
var source := SOURCE_CORE

var _core: InsimulCore = null
var _last_error := ""


func _init(radiant_source: String = SOURCE_CORE) -> void:
	source = radiant_source


## Reason the last call returned an empty result, or "" if it succeeded.
func last_error() -> String:
	return _last_error


## True when the core bridge is present and started. When false, `generate()`
## behaves as SOURCE_NONE and `last_error()` explains why.
func is_core_available() -> bool:
	if source != SOURCE_CORE:
		return false
	return _ensure_core() != null


## The base radiant template pack core ships, as Prolog source. A game can feed
## this straight into `generate()`'s `templates` rather than authoring its own.
## Returns "" if core is unavailable.
func base_templates() -> String:
	var core := _ensure_core()
	if core == null:
		return ""
	var result := _call("radiant.baseTemplates", {})
	if result.is_empty():
		return ""
	return String(result.get("templates", ""))


## Generate radiant quests for one tick.
##
## `kb`        world facts + rules as Prolog source lines (the current KB).
## `templates` the radiant template pack as Prolog source lines.
## `seed`      String or int — hashed to a uint32. The SAME seed, kb and `now`
##             always produce byte-identical quests, on every engine.
## `now`       current in-game time in seconds; drives cooldowns and quest ids.
## `max_quests` cap for this tick; <= 0 means unbounded.
##
## Returns an Array of Dictionaries, one per quest, with core's own field names
## so a caller can be read against the contract:
##   { questId, templateId, questContent, factsToAssert, factsToRetract }
## `questContent` is canonical quest Prolog to consult; `factsToRetract` must be
## retracted BEFORE `factsToAssert` is asserted (they are the stale cooldowns the
## fresh ones replace).
##
## Returns [] when nothing can be generated this tick — which is a normal
## outcome, not an error. Check `last_error()` to tell the two apart.
func generate(
	kb: PackedStringArray,
	templates: PackedStringArray,
	seed: Variant,
	now: int,
	max_quests: int = 0
) -> Array:
	_last_error = ""
	if source == SOURCE_NONE:
		return []

	# Core takes ONE Prolog program: world facts first, then the template pack.
	# This concatenation is part of the contract the corpus pins — the reference
	# runner (packages/core/src/conformance/__tests__/radiant-corpus.test.ts)
	# joins the two arrays with newlines in exactly this order.
	var program := PackedStringArray()
	program.append_array(kb)
	program.append_array(templates)

	var options := {
		"seed": seed,
		"now": now,
	}
	if max_quests > 0:
		options["maxQuests"] = max_quests

	var result := _call("radiant.generate", {
		"kb": "\n".join(program),
		"options": options,
	})
	if result.is_empty():
		return []
	var quests: Variant = result.get("quests", [])
	return quests if quests is Array else []


## The adopted core surface, sorted — a build sanity check for a game that wants
## to assert the bridge is the one it expects.
func core_methods() -> PackedStringArray:
	var result := _call("core.methods", {})
	var methods: Variant = result.get("methods", [])
	var out := PackedStringArray()
	if methods is Array:
		for method_name in methods:
			out.append(String(method_name))
	return out


## The bridge's version stamp: "<abi> (quickjs <pin>, core <commit>)".
func core_version() -> String:
	var core := _ensure_core()
	return core.get_version() if core != null else ""


# ── the boundary ─────────────────────────────────────────────────────────────
# Everything above deals in Godot types; everything below deals in JSON. The two
# meet here and nowhere else.

func _ensure_core() -> InsimulCore:
	if _core != null:
		return _core if _core.is_available() else null
	if not ClassDB.class_exists("InsimulCore"):
		_last_error = "InsimulCore is not registered — this build has no libinsimulcore"
		return null
	_core = InsimulCore.new()
	if not _core.is_available():
		_last_error = _core.last_error()
		return null
	return _core


func _call(method: String, args: Dictionary) -> Dictionary:
	var core := _ensure_core()
	if core == null:
		if _last_error.is_empty():
			_last_error = "core bridge unavailable"
		return {}
	var response := core.call_json(method, JSON.stringify(args))
	if response.is_empty():
		_last_error = core.last_error()
		return {}
	var parsed: Variant = JSON.parse_string(response)
	if typeof(parsed) != TYPE_DICTIONARY:
		_last_error = "core returned a non-object result for %s" % method
		return {}
	return parsed
