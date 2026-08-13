class_name InsimulModuleActivation
extends RefCounted
## What a world ACTIVATES, resolved from core's table rather than from a list in
## this plugin — tasklist 147, US-3.
##
## ## The claim this file has to keep
##
## "Adding a module to a genre bundle requires no engine code change." That is
## only true if nothing here spells a module, a rule pack or a genre — so nothing
## here does, and `tools/verify-mechanics/check-mechanics.mjs`'s seventh check
## greps this file for every name in the vendored table and fails on a hit. The
## names live in core (`src/modules/module-contract.ts`), the resolution lives in
## core (`src/modules/module-activation.ts`), and this file asks.
##
## [codeblock]
## var activation := InsimulModuleActivation.for_world(DataLoader.load_world_data())
## for line in activation.report():
##     print(line)
## var kb := activation.kb_with(world_facts)   # only the packs this world selects
## [/codeblock]
##
## ## Three answers, and they are not the same answer
##
## Core distinguishes them and so does this file, because conflating any two of
## them is a different bug:
##
## [codeblock]
## for_world(ir) / for_genre(id)  a bundle core knows  -> exactly what it selects
##                                a bundle it does not -> nothing but the shared
##                                                        vocabulary, is_known()
##                                                        false. An unrecognised
##                                                        world must not inherit
##                                                        every mechanic in the
##                                                        build.
## undeclared()                   nothing was said     -> every pack. Right for a
##                                                        tool or an editor
##                                                        session, and a WARNING
##                                                        in a game — which is why
##                                                        source() is reported.
## [/codeblock]
##
## ## What "not active" means
##
## Nothing. A module the world did not select contributes no consulted pack (its
## vocabulary is not in [method kb_with]'s output, so its authored gates do not
## even resolve) and no registered system ([InsimulMechanicActivator] opens no
## session for it and wires none of its host interfaces).

## The genre arrived in the World IR's `meta.genreConfig.id`.
const SOURCE_WORLD_IR := "worldIr"
## The host named the genre itself.
const SOURCE_GENRE := "genre"
## Nothing was declared, so the whole vocabulary is in play. See the class doc.
const SOURCE_UNDECLARED := "undeclared"

var _source := SOURCE_UNDECLARED
var _genre := ""
var _known := false
var _modules: Array = []
var _packs := PackedStringArray()
var _interfaces := PackedStringArray()
var _reason := ""
var _error := ""
var _pack_text := ""
var _pack_text_loaded := false
var _runtime_predicates := PackedStringArray()


## Resolve from a World IR — a parsed `world_ir.json`, or anything with the same
## `meta.genreConfig.id`. The genre is the ONLY thing that has to cross the ABI
## for a plugin to know what to activate.
static func for_world(ir: Dictionary) -> InsimulModuleActivation:
	return _resolve({"ir": ir})


## Resolve from a genre id the host already has.
static func for_genre(genre_id: String) -> InsimulModuleActivation:
	return _resolve({"genre": genre_id})


## Resolve with nothing declared: every pack in the build, no module activated.
static func undeclared() -> InsimulModuleActivation:
	return _resolve({})


## Which of the [constant SOURCE_WORLD_IR] constants the genre came from. A game
## that reads [constant SOURCE_UNDECLARED] here is running the whole vocabulary
## because nobody said otherwise, which is worth a line in the boot log.
func source() -> String:
	return _source


## The genre id this was resolved for, or "" when nothing was declared.
func genre() -> String:
	return _genre


## Whether core has a bundle for this genre. False means the shared vocabulary
## and nothing else — NOT "every mechanic".
func is_known() -> bool:
	return _known


## Why the resolution is what it is, when it is worth saying. "" otherwise.
func reason() -> String:
	return _reason


## Whether this world selects the named module.
func is_active(module_id: String) -> bool:
	for entry in _modules:
		if String(entry.get("id", "")) == module_id:
			return true
	return false


## Every selected module, as core's own flat descriptors: `id`, `name`,
## `predicatePack`, `irSection`, `decisionLayer`, `hostInterface`, `conforms`.
func modules() -> Array:
	return _modules.duplicate(true)


## The selected module ids, in core's manifest order.
func module_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in _modules:
		out.append(String(entry.get("id", "")))
	return out


## The host interfaces this world's modules execute through, deduplicated. The
## whole list an adapter registers — and nothing outside it should be wired.
func host_interfaces() -> PackedStringArray:
	return _interfaces.duplicate()


## The interfaces ONE selected module executes through. Empty for a module this
## world did not select, which is what makes host wiring a lookup rather than a
## table in the engine.
func interfaces_for(module_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for entry in _modules:
		if String(entry.get("id", "")) != module_id:
			continue
		var declared: Variant = entry.get("hostInterface", [])
		if declared is Array:
			for name in declared:
				out.append(String(name))
	return out


## The rule-pack areas this world consults, in core's CONSULT ORDER.
func predicate_packs() -> PackedStringArray:
	return _packs.duplicate()


## The consulted Prolog TEXT for [method predicate_packs], joined in that order.
##
## The order is a hard constraint and not tidiness: a later pack adds clauses for
## predicates an earlier one declares `:- dynamic`, and a `:- dynamic` arriving
## after a clause for the same predicate is a `permission_error` on a strict ISO
## engine — which is the engine this plugin links. Fetched once and cached.
func pack_source() -> String:
	if _pack_text_loaded:
		return _pack_text
	_pack_text_loaded = true
	var response := _call("prolog.packs", {"areas": _to_array(_packs)})
	var packs: Variant = response.get("packs", [])
	if not (packs is Array):
		return _pack_text
	var chunks := PackedStringArray()
	var predicates := PackedStringArray()
	for entry in packs:
		if not (entry is Dictionary):
			continue
		chunks.append(String(entry.get("prolog", "")))
		var declared: Variant = entry.get("runtimePredicates", [])
		if declared is Array:
			for signature in declared:
				if not predicates.has(String(signature)):
					predicates.append(String(signature))
	_runtime_predicates = predicates
	_pack_text = "\n".join(chunks)
	return _pack_text


## The `name/arity` of every per-playthrough predicate the active packs declare —
## what a save may legitimately carry back in. Empty until [method pack_source]
## has run, which [method kb_with] does.
func runtime_predicates() -> PackedStringArray:
	pack_source()
	return _runtime_predicates.duplicate()


## The KB a session for this world opens with: the active packs, then the
## world's own facts. A module's gate reads its pack's predicates, so facts
## alone are not enough — and a module this world did not select has no
## vocabulary in here at all.
func kb_with(world_facts: String) -> String:
	var source_text := pack_source()
	if world_facts.strip_edges().is_empty():
		return source_text
	return "%s\n%s" % [source_text, world_facts]


## Why the resolution failed, or "". A failed resolution answers
## [constant SOURCE_UNDECLARED] with no packs, never a silent empty set.
func last_error() -> String:
	return _error


## A boot-log block, so a creator is TOLD what this world runs.
func report() -> PackedStringArray:
	var lines := PackedStringArray()
	if not _error.is_empty():
		lines.append("[Insimul] activation: unresolved (%s)" % _error)
		return lines
	lines.append(
		"[Insimul] activation — genre %s (from %s)%s"
		% [
			_genre if not _genre.is_empty() else "<none>",
			_source,
			"" if _known or _source == SOURCE_UNDECLARED else " — UNKNOWN to core",
		]
	)
	if not _reason.is_empty():
		lines.append("  %s" % _reason)
	for entry in _modules:
		var interfaces := _strings(entry.get("hostInterface", []))
		lines.append(
			"  %-11s %-26s %s"
			% [
				String(entry.get("id", "")),
				String(entry.get("name", "")),
				", ".join(interfaces) if interfaces.size() > 0 else "-",
			]
		)
	lines.append("  packs: %s" % (", ".join(_packs) if _packs.size() > 0 else "-"))
	return lines


# ── the boundary ─────────────────────────────────────────────────────────────
# Above: Godot types. Below: JSON. Every name in the answer is core's.

static func _resolve(args: Dictionary) -> InsimulModuleActivation:
	var activation := InsimulModuleActivation.new()
	var response := activation._call("modules.activate", args)
	if response.is_empty():
		if activation._error.is_empty():
			activation._error = "modules.activate returned nothing"
		push_warning("[Insimul] activation unresolved: %s" % activation._error)
		return activation
	activation._source = String(response.get("source", SOURCE_UNDECLARED))
	activation._reason = String(response.get("reason", ""))
	var answer: Variant = response.get("active", null)
	if answer is Dictionary:
		var resolved: Dictionary = answer
		activation._genre = String(resolved.get("genre", ""))
		activation._known = bool(resolved.get("known", false))
		var declared: Variant = resolved.get("modules", [])
		if declared is Array:
			activation._modules = (declared as Array).duplicate(true)
	activation._packs = activation._strings(response.get("predicatePacks", []))
	activation._interfaces = activation._strings(response.get("hostInterfaces", []))
	return activation


func _strings(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if value is Array:
		for item in value:
			out.append(String(item))
	return out


func _to_array(value: PackedStringArray) -> Array:
	var out := []
	for item in value:
		out.append(item)
	return out


func _call(method: String, args: Dictionary) -> Dictionary:
	_error = ""
	if not ClassDB.class_exists("InsimulCore"):
		_error = "InsimulCore is not registered — this build has no libinsimulcore"
		return {}
	var core := InsimulCore.new()
	if not core.is_available():
		_error = core.last_error()
		return {}
	var response := core.call_json(method, JSON.stringify(args))
	if response.is_empty():
		_error = core.last_error()
		return {}
	var parsed: Variant = JSON.parse_string(response)
	if typeof(parsed) != TYPE_DICTIONARY:
		_error = "core returned a non-object result for %s" % method
		return {}
	return parsed
