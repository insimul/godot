class_name InsimulMechanicSession
extends RefCounted
## One live band-120 decision layer, on the Godot side of the C ABI — tasklist
## 147, US-1.
##
## THIS FILE IS THE HOST HALF OF "READINGS IN, ORDERS OUT". The adapter's half is
## `gdextension/corebridge/js/host-mechanics.js`; between them they turn eight
## callback interfaces into something a C ABI with no callbacks can carry:
##
##     1. the game gathers what core would have ASKED it (a raycast, a navmesh
##        path, an entity's base stats) BEFORE the call, and passes it in;
##     2. core decides;
##     3. everything core would have TOLD the host comes back as `orders`, and
##        `_drain()` below calls the wired host implementation for each one.
##
## The engine therefore executes exactly what it would have executed in-process,
## in the same order, with the same arguments — but the boundary stayed JSON in,
## JSON out, which is what keeps `insimulcore.h` free of function pointers and
## this plugin free of a threading model core has to know about.
##
## ## Sessions
##
## A decision layer is STATEFUL — a roster, accumulated `threat/3`, banked XP, a
## worn loadout, a Prolog KB — and a bridge call is not. So a module is opened
## once, held, called many times and disposed:
##
## [codeblock]
## var combat := InsimulMechanicSession.open("combat", {
##     "kb": world_kb, "seed": 7,
##     "combatants": [{"id": "nessa", "health": 30, "maxHealth": 30}],
##     "actions": world_combat_actions,
## }, {"ICombatSystem": my_combat_host, "ITrajectoryProbe": my_probe})
##
## var report := combat.call_row("attack", {
##     "attackerId": "nessa", "targetId": "boar", "action": "crossbow_shot",
##     "tick": tick,
##     # the reading, taken by the host before the call
##     "trajectory": my_probe.query({"attacker": "nessa", "target": "boar",
##                                   "action": "crossbow_shot"}),
## })
## [/codeblock]
##
## `call_row()` returns core's own report and has ALREADY carried out the orders
## it came with, so a caller that ignores the return value still gets a game that
## moves.
##
## ## What this file must never do
##
## Decide anything. No damage number, no cost, no suspicion level, no refusal is
## computed here — every one of them arrives in the report. If arithmetic over a
## mechanic ever appears in this file, the adoption has forked.

## The seven modules this build can open, in `mechanic.modules` order.
const MODULES := [
	"combat",
	"stamina",
	"perception",
	"traversal",
	"skill",
	"equipment",
	"routine",
]

## Which host interface each order's `host` field names, mapped to the GDScript
## method that carries it out. The adapter emits core's own member names; this is
## the ONLY place they become snake_case, so a rename in core fails here rather
## than in nine call sites.
const ORDER_METHODS := {
	"ICombatSystem": {
		"registerEntity": "register_entity",
		"unregisterEntity": "unregister_entity",
		"applyDamage": "apply_damage",
	},
	"ISurvivalSystem": {
		"consumeStamina": "consume_stamina",
		"recoverStamina": "recover_stamina",
	},
	"ICombatStatSink": {"applyStats": "apply_stats"},
	"ISkillModifierSink": {"applyModifiers": "apply_modifiers"},
	"ILocomotionHost": {"travel": "travel"},
	"IAgentActionHost": {"perform": "perform"},
}

## The module this session drives — one of [constant MODULES].
var module := ""
## The adapter's session handle. 0 means the session is not open.
var handle := 0

var _core: InsimulCore = null
var _hosts := {}
var _last_error := ""
## Orders carried out by the most recent call, for a debug overlay or a test.
var _last_orders: Array = []


## Open a session for `module`.
##
## `args`  the module's create arguments, in core's own field names (see the row
##         table in `gdextension/corebridge/js/entry.js`). `kb` is the world's
##         Prolog source: a module whose gate reads a predicate the KB does not
##         define fails the call rather than silently permitting, so pass the
##         rule packs the world loaded, not just its facts.
## `hosts` interface name -> an implementation from
##         [InsimulMechanicHosts]. Anything absent gets that interface's
##         documented fallback, which is never "nothing happens".
##
## Returns null when the bridge is unavailable or the module refused to open;
## the reason is on [method last_error] of the returned session, or pushed as a
## warning when there is no session to carry it.
static func open(module_name: String, args: Dictionary, hosts: Dictionary = {}) -> InsimulMechanicSession:
	var session := InsimulMechanicSession.new()
	session.module = module_name
	session._hosts = hosts.duplicate()
	if not MODULES.has(module_name):
		push_warning("[Insimul] no such mechanic module: %s" % module_name)
		return null
	var core := session._ensure_core()
	if core == null:
		push_warning("[Insimul] mechanic module %s: %s" % [module_name, session._last_error])
		return null
	var result := session._call("%s.create" % module_name, args)
	if result.is_empty():
		push_warning("[Insimul] mechanic module %s failed to open: %s" % [module_name, session._last_error])
		return null
	session.handle = int(result.get("session", 0))
	# A create is a call like any other: registering a combatant is an
	# `ICombatSystem.registerEntity` order, and the host must see it.
	session._drain(result)
	return session


## True while the session is open and the bridge is alive.
func is_open() -> bool:
	return handle != 0 and _core != null and _core.is_available()


## Why the last call returned nothing, or "".
func last_error() -> String:
	return _last_error


## The orders the last call produced, already carried out. For a debug overlay,
## a replay or a test — never a control input.
func last_orders() -> Array:
	return _last_orders


## Call one of this module's verbs — `attack`, `spend`, `observe`, `traverse`,
## `unlock`, `equip`, `tick`, `state`, … — and carry out whatever it orders.
##
## `args` carries the host's READINGS for this call alongside the request:
##   combat.attack     `trajectory`: what the line-of-fire probe answered
##   perception.observe `readings`: one entry per (observer, target) pair
##   traversal.traverse `probe`: per-link passability; `arrival`: what the host
##                      already knows about whether the body can get there
##   equipment.*       `baseStats`: the entity's unmodified combat stats
##
## Returns core's report, or {} on failure (see [method last_error]).
func call_row(verb: String, args: Dictionary = {}) -> Dictionary:
	if handle == 0:
		_last_error = "session is not open"
		return {}
	var payload := args.duplicate()
	payload["session"] = handle
	var result := _call("%s.%s" % [module, verb], payload)
	if result.is_empty():
		return {}
	_drain(result)
	# `state` and the other read-only rows answer with their own shape rather
	# than a { report, orders } envelope; hand back whichever arrived.
	return result.get("report", result) if result.has("report") else result


## Close the session and release the KB it owns. Safe to call twice.
func dispose() -> void:
	if handle == 0:
		return
	_call("mechanic.dispose", {"session": handle})
	handle = 0


# ── the boundary ─────────────────────────────────────────────────────────────
# Above: Godot types and host implementations. Below: JSON. The two meet here,
# exactly as they do in `radiant_source.gd`.

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
	_last_error = ""
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


## Carry out every order in a result, in the order core made them.
##
## An order for an interface the game did not wire reaches that interface's
## documented fallback rather than nothing, and an order whose member this
## version of the plugin does not know is a WARNING rather than a silent drop —
## a new member in core must be visible here, because the alternative is a game
## that quietly stops applying damage.
func _drain(result: Dictionary) -> void:
	_last_orders = []
	var orders: Variant = result.get("orders", [])
	if not (orders is Array):
		return
	for entry in orders:
		if not (entry is Dictionary):
			continue
		var order: Dictionary = entry
		var interface_name := String(order.get("host", ""))
		var member := String(order.get("call", ""))
		_last_orders.append(order)
		var members: Variant = ORDER_METHODS.get(interface_name, {})
		if not (members is Dictionary) or not members.has(member):
			push_warning(
				"[Insimul] unhandled order %s.%s — this plugin is older than the core bundle it is calling"
				% [interface_name, member]
			)
			continue
		var host: Variant = _host_for(interface_name)
		var method := String(members[member])
		match [interface_name, member]:
			["ICombatSystem", "registerEntity"]:
				host.call(method, order.get("entity", {}))
			["ICombatSystem", "unregisterEntity"]:
				host.call(method, String(order.get("entityId", "")))
			["ICombatSystem", "applyDamage"]:
				host.call(method, String(order.get("entityId", "")), float(order.get("damage", 0.0)))
			["ISurvivalSystem", "consumeStamina"], ["ISurvivalSystem", "recoverStamina"]:
				host.call(method, float(order.get("amount", 0.0)))
			["ICombatStatSink", "applyStats"]:
				host.call(method, String(order.get("entityId", "")), order.get("stats", {}))
			["ISkillModifierSink", "applyModifiers"]:
				host.call(method, String(order.get("actorId", "")), order.get("modifiers", {}))
			["ILocomotionHost", "travel"]:
				# The arrival the host reports here is ADVISORY: core already read
				# the one the call was given (`arrival` in the args), because the
				# ABI cannot await a walk that takes seconds. This is what actually
				# starts the body moving. See host-mechanics.js's `arrivalFor`.
				host.call(method, order.get("order", {}))
			["IAgentActionHost", "perform"]:
				host.call(method, order.get("order", {}))


func _host_for(interface_name: String) -> RefCounted:
	if _hosts.has(interface_name):
		return _hosts[interface_name]
	# Cached, so a module with no wired host does not allocate a fallback per
	# order — and so `_hosts` ends up holding exactly what was used.
	var fallback := InsimulMechanicHosts.default_host(interface_name)
	_hosts[interface_name] = fallback
	return fallback
