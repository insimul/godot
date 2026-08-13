class_name InsimulTalosAdapter
extends Node
## The Insimul side of a Talos session: six groups, four methods, three signals,
## and not one Talos symbol (TALOS_INSIMUL_BRIDGE.md §7.4, §7.5).
##
## WHAT MAKES THIS POSSIBLE. Talos's Godot game-side contract is entirely
## duck-typed: the Bridge finds a game's participation through manifest-declared
## GROUPS plus method and signal NAMES. There is no interface to implement, no
## base class to extend and no script to preload, so this file cannot break a
## build that has no Talos in it — there is nothing to resolve. The dependency
## runs the other way and it is DATA: `talos.game.yaml` must name these groups,
## or a perfectly good adapter is invisible.
##
## THE ONE RULE (§7.5). **This node never reads the knowledge base while it is
## being constructed** — not in `_init`, not in `_ready`. Autoload order is
## registration order and registration order is whichever addon a developer
## enabled first, so a `_ready`-time read works on one machine and not the next,
## and it fails SILENTLY: an early read returns an empty KB, not an error, and a
## Conductor reads "no facts" as a fact. The fix is structural rather than
## sequential — this node has no KB until a running game hands it one through
## `attach_world()`, so there is no ordering to get wrong. Until then
## `talos_ready_state()` answers false and every state answer is the bridge's
## retryable `insimul_kb_uninitialized` refusal rather than an empty success.
##
## WHAT IT MAPS (§3.4-§3.6, §3.8):
##
##   query_state         a Prolog query over the live KB, reached through the
##                       manifest's `watch:` entries and `_get()`
##   set_progress_var    an assert, reached through `_set()` — refused when it
##                       would land on a world TEMPLATE
##   save/restore        insimul_kb_snapshot / insimul_kb_restore, stamped with
##                       the four version axes so the archive is invalidatable
##   teleport            generated places, announced as runtime markers
##   set_seed            the world seed
##   declare_context     the host PHASE — never Insimul's @world
##   events              KB deltas
##
## Every DECISION in that list belongs to `InsimulTalosBridge`
## (gdextension/src/talos_bridge.*), which is host-tested by
## gdextension/test/run_talos_bridge_tests.sh. This file gathers readings and
## carries out orders; it decides nothing on its own, so there is no second
## opinion to drift.

## Where the two shipped data files live. The bridge decides FROM these bytes:
## the version matrix is the workspace's published one (mirrored by
## tools/vendor-supported-versions.mjs) and the contract is this artifact's own
## declared surface. Nothing about either is compiled in.
const CONTRACT_PATH := "res://addons/insimul_talos/bridge-contract.json"
const MATRIX_PATH := "res://addons/insimul_talos/supported-versions.json"

## The GDExtension class carrying the decision half. Absent means the Insimul
## plugin is not installed or not built — which is a broken install, not a
## degraded one, and is reported as such rather than worked around.
const BRIDGE_CLASS := "InsimulTalosBridge"

## Talos's contract, by the names its runtime modules look for. Spelled here so
## a rename upstream is a one-line diff rather than a hunt, and so the gate
## (tools/verify-talos-bridge/check-bridge.mjs) can hold the manifest fragment
## and this file to the same list.
const MARKER_SIGNAL := "talos_marker_registered"

## Property prefixes the manifest's `watch:` entries address. A progress var and
## a read-only projection are different things with different failure modes, so
## they get different namespaces rather than one bag of keys.
const STATE_PREFIX := "insimul/state/"
const PROGRESS_PREFIX := "insimul/progress/"

## A marker the game announced: `talos_marker_registered(label, marker_type, node)`.
signal talos_marker_registered(label: String, marker_type: String, node: Node)

## A host game-state PHASE transition: `(context, transition, reason)`. Named
## `context` because that is Talos's field; it is never Insimul's `@world`.
signal talos_context_changed(context: String, transition: String, reason: String)

## One gameplay telemetry event: `(event, data)`. Here these are KB deltas.
signal talos_event(event: String, data: Dictionary)

var _bridge: Object = null
var _configure_error := ""

## The live KB (an InsimulProlog), and what the game said about the world it
## belongs to. Null and empty until `attach_world()` — see the §7.5 note above.
var _kb: Object = null
var _world_id := ""
var _seed := ""
var _active_modules: PackedStringArray = PackedStringArray()

## Declared read-only projections: watch key -> Prolog goal. The game declares
## what a Director may plan from; the bridge never invents a goal.
var _state_goals: Dictionary = {}

## Declared progress vars: name -> the last value written, for read-back.
var _progress: Dictionary = {}

## Runtime markers the game announced, in announcement order.
var _markers: Array = []

## The most recent refusal, as the JSON envelope the bridge produced. Empty when
## the last answer was an admission. Exposed so a manifest can watch it: a
## refusal nobody can see is a refusal that reads as an outage.
var last_refusal := ""


static func bridge_available() -> bool:
	## True when the Insimul plugin's GDExtension is built and loaded.
	return ClassDB.class_exists(BRIDGE_CLASS)


func _ready() -> void:
	# Joining groups is not reading a knowledge base. This is the whole of what
	# construction may do: announce that this node exists, and configure the
	# decision half from files.
	for group in _declared_groups():
		add_to_group(group)
	_configure()


func _configure() -> void:
	if not bridge_available():
		_configure_error = (
			"the %s GDExtension class is not registered — insimul-talos-bridge needs the "
			+ "Insimul plugin installed and its extension built"
		) % BRIDGE_CLASS
		return
	var contract := _read_text(CONTRACT_PATH)
	var matrix := _read_text(MATRIX_PATH)
	if contract.is_empty() or matrix.is_empty():
		_configure_error = (
			"a half-present install: %s and %s both ship with this addon and one of them "
			+ "did not load"
		) % [CONTRACT_PATH, MATRIX_PATH]
		return
	_bridge = ClassDB.instantiate(BRIDGE_CLASS)
	if not _bridge.configure(contract, matrix):
		_configure_error = str(_bridge.last_error())
		_bridge = null


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _declared_groups() -> PackedStringArray:
	## The six groups of §7.4, read from the contract rather than listed here.
	## A group this node joins and the manifest does not declare — or the reverse
	## — is an adapter the Bridge cannot see, so there is exactly one place the
	## names live and both readers quote it.
	if _bridge != null:
		return _bridge.groups()
	var parsed: Variant = JSON.parse_string(_read_text(CONTRACT_PATH))
	var names: PackedStringArray = PackedStringArray()
	if parsed is Dictionary and (parsed as Dictionary).has("groups"):
		var groups: Dictionary = (parsed as Dictionary)["groups"]
		for key in groups:
			names.append(str((groups[key] as Dictionary)["group"]))
	return names


# ─────────────────────────────────────────────
# The game hands the adapter a world. Nothing above this line reads a KB.
# ─────────────────────────────────────────────

## Attach the live knowledge base and what the game knows about its world.
## Call this once a world is loaded — never earlier. Until it is called this
## adapter reports not-ready and refuses every state answer, which is §7.5's
## rule made structural: there is no KB here to read too early.
func attach_world(kb: Object, world_id: String, seed_value: String,
		active_modules: PackedStringArray = PackedStringArray()) -> void:
	_kb = kb
	_world_id = world_id
	_seed = seed_value
	_active_modules = active_modules
	talos_event.emit("level_loaded", {"world_id": world_id, "seed": seed_value})


## Drop the world — a return to a menu, a world unloaded. The adapter goes back
## to not-ready rather than answering from a knowledge base that is gone.
func detach_world() -> void:
	_kb = null
	_world_id = ""
	_seed = ""
	_active_modules = PackedStringArray()
	_state_goals.clear()
	_progress.clear()
	_markers.clear()


## Declare what a `query_state` watch key means, as a Prolog goal. The game owns
## the goal: a bridge that invented one would be answering a question nobody
## asked, and a schema-invalid predicate fails loudly at the schema rather than
## returning empty.
func declare_state(key: String, goal: String) -> void:
	_state_goals[key] = goal


## Register a place the world generated, with the entity id that resolves into
## the KB. Announced on demand, because a generator makes its markers long
## before a Bridge has finished binding.
func register_marker(label: String, marker_type: String, node: Node) -> void:
	_markers.append({"label": label, "marker_type": marker_type, "node": node})


func kb_ready() -> bool:
	return _kb != null and not _world_id.is_empty()


func configure_error() -> String:
	return _configure_error


# ─────────────────────────────────────────────
# The six group contracts
# ─────────────────────────────────────────────

func talos_ready_state() -> bool:
	## §2.10's two-phase readiness, answered honestly. False while the bridge is
	## unconfigured or no world is attached; a Bridge that polls this never asks
	## the KB a question the KB cannot answer.
	##
	## A version refusal does NOT hold readiness down: §7.7 wants that refused at
	## the handshake, and tbp/1.x has no carrier for `capabilities.insimul`, so the
	## refusal travels on the events channel instead (see `hello_decision()`).
	return _bridge != null and kb_ready()


func talos_save() -> Dictionary:
	## Tier-1 checkpoint = `insimul_kb_snapshot`, plus the version stamp that
	## makes the archive invalidatable at all. TBP's save_checkpoint response
	## carries {id, tier, frame, latency_ms, bytes, level} and no version field, so
	## an adapter that does not stamp the axes itself produces an archive nobody
	## can ever prove stale (§7.7, REFUSE_AT_HELLO.md).
	var gate := _gate("save_checkpoint")
	if not gate.is_empty():
		return {"insimul.refusal": gate}
	var image: String = str(_kb.snapshot())
	var stamp: Variant = JSON.parse_string(str(_bridge.checkpoint_stamp(_readings())))
	return {
		"insimul.kb": image,
		"insimul.stamp": stamp if stamp is Dictionary else {},
		"insimul.world_id": _world_id,
		"insimul.seed": _seed,
	}


func talos_load(state: Dictionary) -> void:
	## The archive rule: a checkpoint is only valid within its `snapshot_version`,
	## and Go-Explore archives persist ACROSS runs — so an entry from before a core
	## upgrade is INVALIDATED, never restored. Restoring a stale-format snapshot
	## that happens to parse is the worst available failure, because it produces a
	## world that is subtly not the world the archive believed it had.
	var gate := _gate("restore_checkpoint")
	if not gate.is_empty():
		return
	var stamp: Dictionary = state.get("insimul.stamp", {})
	var entry := {"engine": "godot", "id": str(state.get("insimul.world_id", "")),
			"axes": stamp.get("axes", {})}
	var decision: String = str(_bridge.evaluate_archive(JSON.stringify(entry)))
	var parsed: Variant = JSON.parse_string(decision)
	if not (parsed is Dictionary) or not (parsed as Dictionary).get("ok", false):
		_refuse(decision, "restore_checkpoint")
		return
	if not _kb.restore(str(state.get("insimul.kb", ""))):
		_report_assert_failed("insimul_kb_restore failed: %s" % str(_kb.last_error()))


func talos_announce_markers() -> void:
	## Re-announce every runtime marker, because the Bridge asked. A generator
	## registers its markers before a Bridge has connected to the signal, so a
	## registration emitted once at generation time is lost to exactly the
	## consumer that needed it. Idempotent by construction.
	if not _gate("teleport").is_empty():
		return
	for marker in _markers:
		var entry: Dictionary = marker
		talos_marker_registered.emit(str(entry["label"]), str(entry["marker_type"]),
				entry["node"] as Node)


func talos_set_seed(value: int) -> void:
	## The world seed. Recorded rather than silently applied: generation is
	## deterministic FROM a seed, so reseeding a world that is already open does
	## not re-derive it, and reporting that is more useful than pretending.
	var gate := _gate("set_seed")
	if not gate.is_empty():
		return
	var reseeded := str(value)
	var changed := reseeded != _seed
	_seed = reseeded
	talos_event.emit("progress_var", {
		"name": "insimul.seed",
		"value": reseeded,
		"applied_to_open_world": changed,
	})


## Declare a host game-state PHASE. Named for Talos's field and never used for
## Insimul's `@world`, which is the collision §3.8 defuses.
func declare_phase(phase: String, transition: String, reason: String) -> void:
	talos_context_changed.emit(phase, transition, reason)


# ─────────────────────────────────────────────
# query_state / set_progress_var, through the manifest's watch entries
# ─────────────────────────────────────────────

func _get(property: StringName) -> Variant:
	var key := String(property)
	if key.begins_with(STATE_PREFIX):
		return _query_state(key.substr(STATE_PREFIX.length()))
	if key.begins_with(PROGRESS_PREFIX):
		return _progress.get(key.substr(PROGRESS_PREFIX.length()), null)
	return null


func _set(property: StringName, value: Variant) -> bool:
	var key := String(property)
	if not key.begins_with(PROGRESS_PREFIX):
		return false
	_write_progress_var(key.substr(PROGRESS_PREFIX.length()), value)
	return true


func _query_state(key: String) -> Variant:
	## One declared projection, answered from the live KB — the digest IS the
	## state rather than a watch-list's guess at it. Solutions are canonically
	## sorted and capped by the bridge before they are reported, because core
	## compares solutions as an unordered multiset and TBP requires truncation to
	## be deterministic (§3.4).
	var gate := _gate("query_state")
	if not gate.is_empty():
		return gate
	if not _state_goals.has(key):
		return null
	var solutions: Array = _kb.query(str(_state_goals[key]))
	return _bridge.query_digest(JSON.stringify(solutions), 0)


func _write_progress_var(name: String, value: Variant) -> void:
	## A progress var IS a fact, so setting one is an assert — and the drift a
	## nightly lint guards against elsewhere cannot occur here, because there is no
	## second registration to fall out of sync with (§3.6).
	var decision: String = str(_bridge.progress_var(name, JSON.stringify(value),
			_targets_template(), _readings()))
	var parsed: Variant = JSON.parse_string(decision)
	if not (parsed is Dictionary) or not (parsed as Dictionary).get("ok", false):
		_refuse(decision, "set_progress_var")
		return
	_progress[name] = value
	talos_event.emit("progress_var", {"name": name, "value": value})


func _targets_template() -> bool:
	## True when there is no playthrough to write to, so an assert would land on
	## the world TEMPLATE every future playthrough is generated from. Conservative
	## on purpose: with no world attached this is the safe answer, and the bridge
	## refuses the §7.5 way first anyway.
	return _kb == null


# ─────────────────────────────────────────────
# The handshake, and refusals
# ─────────────────────────────────────────────

## The `capabilities.insimul` payload of §3.1, as JSON. Carried in the digest
## rather than in `hello`, because tbp/1.x has no carrier for it: `capabilities`
## is `additionalProperties: false` and rejects unknown keys BY DESIGN, so a
## namespaced block is a counterparty ask (§7.9) and not something this side can
## work around. Publishing it here costs nothing and travels the moment it can.
func capabilities() -> String:
	if _bridge == null:
		return ""
	return str(_bridge.capabilities(_readings()))


## Put this build through the refuse-at-hello decision (§7.7) and publish the
## answer. A refusal is reported on the events channel as `assert_failed`,
## because that is the one channel tbp/1.x already has for "this run should not
## be trusted" — and a version refusal that never reached the run would be the
## wasted run §7.7 exists to prevent.
func hello_decision() -> String:
	if _bridge == null:
		return ""
	var decision: String = str(_bridge.evaluate_hello(str(_bridge.hello(_readings()))))
	var parsed: Variant = JSON.parse_string(decision)
	if parsed is Dictionary and not (parsed as Dictionary).get("ok", false):
		_refuse(decision, "hello")
	return decision


func _readings() -> Dictionary:
	## Everything the decision half is allowed to know, gathered at CALL time.
	## `kb_ready` false means nothing below it came from a knowledge base.
	return {
		"engine": "godot",
		"engine_version": _engine_version(),
		"plugin_version": _plugin_version(),
		"core_version": _core_version(),
		"snapshot_version": _snapshot_version(),
		"world_id": _world_id,
		"seed": _seed,
		"active_modules": Array(_active_modules),
		"kb_ready": kb_ready(),
	}


func _engine_version() -> String:
	var info: Dictionary = Engine.get_version_info()
	return "%d.%d.%d" % [int(info["major"]), int(info["minor"]), int(info["patch"])]


func _plugin_version() -> String:
	var config := ConfigFile.new()
	if config.load("res://addons/insimul_talos/plugin.cfg") != OK:
		return ""
	return str(config.get_value("plugin", "version", ""))


func _core_version() -> String:
	## The c_abi axis, proxied by libinsimul's own semver — the library carries no
	## compiled-in ABI symbol, so the semver is the proxy the matrix names.
	if not ClassDB.class_exists("InsimulCore"):
		return ""
	var core: Object = ClassDB.instantiate("InsimulCore")
	if not core.has_method("core_version"):
		return ""
	return str(core.core_version())


func _snapshot_version() -> String:
	## The SAVE-FORMAT gate, and deliberately not babylon's per-world
	## `snapshotVersion` counter — publishing that here would publish the wrong
	## axis, and the bridge names that mistake as itself rather than as skew.
	if not ClassDB.class_exists("InsimulSaveCodec"):
		return ""
	var codec: Object = ClassDB.instantiate("InsimulSaveCodec")
	if not codec.has_method("save_file_version"):
		return ""
	return str(codec.save_file_version())


func _gate(verb: String) -> String:
	## Ask the bridge whether this verb may be answered at all. Returns "" when it
	## may, and the refusal envelope when it may not — never an empty success,
	## which is the one thing §7.8 says this design exists to eliminate.
	if _bridge == null:
		var envelope := JSON.stringify({
			"ok": false,
			"verdict": "refuse",
			"token": "insimul_bridge_not_configured",
			"error": {
				"code": -32003,
				"code_name": "NOT_DECLARED",
				"message": "insimul: %s" % _configure_error,
				"data": {"sub_code": "insimul_bridge_not_configured", "retryable": false},
			},
		})
		_refuse(envelope, verb)
		return envelope
	var decision: String = str(_bridge.verb(verb, _readings()))
	var parsed: Variant = JSON.parse_string(decision)
	if parsed is Dictionary and (parsed as Dictionary).get("ok", false):
		return ""
	_refuse(decision, verb)
	return decision


func _refuse(envelope: String, verb: String) -> void:
	last_refusal = envelope
	var parsed: Variant = JSON.parse_string(envelope)
	var token := ""
	if parsed is Dictionary:
		token = str((parsed as Dictionary).get("token", ""))
	push_warning("insimul-talos-bridge: %s refused (%s)" % [verb, token])
	talos_event.emit("assert_failed", {
		"message": "insimul-talos-bridge refused %s" % verb,
		"sub_code": token,
		"envelope": envelope,
	})


func _report_assert_failed(message: String) -> void:
	talos_event.emit("assert_failed", {"message": message})
